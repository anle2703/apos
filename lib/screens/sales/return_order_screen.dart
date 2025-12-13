// lib/screens/sales/return_order_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../models/bill_model.dart';
import '../../models/product_model.dart';
import '../../models/order_item_model.dart';
import '../../models/customer_model.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/product_search_delegate.dart';
import 'package:collection/collection.dart';
import '../../services/firestore_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../models/payment_method_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/shift_service.dart';

class ReturnService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Future<String> generateCode(String storeId, String prefix) async {
    final now = DateTime.now();
    final datePrefix = DateFormat('ddMMyy').format(now);
    final counterRef = _db.collection('counters').doc('${prefix}_${storeId}_$datePrefix');
    try {
      await counterRef.set({'count': FieldValue.increment(1)}, SetOptions(merge: true));
      final doc = await counterRef.get();
      final count = doc.data()?['count'] ?? 1;
      return '$prefix$datePrefix${count.toString().padLeft(3, '0')}';
    } catch (e) {
      return '$prefix$datePrefix${DateTime.now().millisecondsSinceEpoch % 1000}';
    }
  }

  Future<void> processExchangeTransaction({
    required String storeId,
    required UserModel currentUser,
    required List<OrderItem> returnItems,
    required List<OrderItem> exchangeItems,
    required double returnTotalValue,
    required double exchangeTotalValue,
    BillModel? originalBill,
    CustomerModel? customer,
    String? note,
    String? paymentMethodName,
    String? currentShiftId,
  }) async {
    final batch = _db.batch();
    final now = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(now);
    final reportId = '${storeId}_$todayStr';
    final dailyReportRef = _db.collection('daily_reports').doc(reportId);

    // 1. XÁC ĐỊNH KỊCH BẢN TRẢ HÀNG
    bool isCorrectionMode = false;
    if (originalBill != null &&
        originalBill.reportDateKey == todayStr &&
        originalBill.shiftId == currentShiftId) {
      isCorrectionMode = true;
    }

    bool isFullReturn = false;
    if (originalBill != null) {
      isFullReturn = _checkIfFullReturn(originalBill, returnItems);
    }

    // --- TÍNH TOÁN DATA TRẢ ---
    double totalReturnSubtotal = 0;
    double totalReturnTax = 0;
    double totalReturnItemDiscount = 0;
    double totalReturnProfit = 0;
    double totalReturnNetSubtotal = 0;
    double originalBillTotalDiscount = 0.0;
    if (originalBill != null) {
      double billDiscVal = (originalBill.discountType == 'VND')
          ? originalBill.discountInput
          : (originalBill.subtotal * originalBill.discountInput / 100);
      originalBillTotalDiscount = billDiscVal +
          originalBill.voucherDiscount +
          originalBill.customerPointsValue;
    }

    Map<String, double> currentReturnQtyMap = {};
    List<Map<String, dynamic>> returnItemsData = [];
    final Map<String, dynamic> mainProductsMap = {};

    final Map<String, dynamic> shiftProductsMap = {};
    for (var item in returnItems) {
      String key = item.lineId;
      currentReturnQtyMap[key] = (currentReturnQtyMap[key] ?? 0) + item.quantity;

      // 1. Lấy thông tin từ Bill gốc
      Map<String, dynamic>? originalItemData;
      if (originalBill != null) {
        try {
          originalItemData = originalBill.items.firstWhere((bi) {
            if (bi['lineId'] != null) return bi['lineId'] == item.lineId;
            return (bi['product'] as Map?)?['id'] == item.product.id;
          }) as Map<String, dynamic>?;
        } catch (_) {}
      }

      // 2. Lấy Giá Gốc (Gross Price) để tính toán
      double originalSellPrice = item.product.sellPrice;
      if (originalItemData != null && originalItemData['product'] != null) {
        originalSellPrice = (originalItemData['product']['sellPrice'] as num?)?.toDouble() ?? item.product.sellPrice;
      }

      // --- [PHẦN QUAN TRỌNG CẦN KHÔI PHỤC] ---
      // 3. Tính lại GIẢM GIÁ từ dữ liệu gốc (để trừ báo cáo)
      double discountForReport = 0;
      if (originalItemData != null) {
        double dVal = (originalItemData['discountValue'] as num?)?.toDouble() ?? 0;
        String dUnit = originalItemData['discountUnit'] ?? '%';

        // Lấy giá gốc tại thời điểm bán để tính %
        double originalGrossForCalc = 0;
        if (originalItemData['product'] != null) {
          originalGrossForCalc = (originalItemData['product']['sellPrice'] as num?)?.toDouble() ?? item.product.sellPrice;
        } else {
          originalGrossForCalc = item.product.sellPrice;
        }

        if (dVal > 0) {
          if (dUnit == '%') {
            discountForReport = originalGrossForCalc * (dVal / 100);
          } else {
            discountForReport = dVal;
          }
        }
      }

      // Tính tổng tiền giảm giá của dòng này
      double itemTotalDiscountToReverse = (discountForReport * item.quantity).roundToDouble();

      // [FIX LỖI]: Cộng dồn vào biến tổng để Report có dữ liệu trừ
      totalReturnItemDiscount += itemTotalDiscountToReverse;
      // ----------------------------------------

      // 4. Tính giá NET (Để hiển thị UI và tính tiền hoàn)
      double unitPriceNet = originalSellPrice - discountForReport;

      // Tính Subtotal NET
      final double itemNetSubtotal = (unitPriceNet * item.quantity).roundToDouble();

      // Cộng dồn các biến tổng (Dùng giá Net)
      totalReturnNetSubtotal += itemNetSubtotal;
      totalReturnSubtotal += itemNetSubtotal;

      // ... (Phần tính giá vốn, lợi nhuận, thuế giữ nguyên như cũ) ...
      double itemBaseCost = item.product.costPrice;
      if (originalItemData != null && originalItemData['product'] != null) {
        final p = originalItemData['product'] as Map<String, dynamic>;
        if (p['costPrice'] != null) itemBaseCost = (p['costPrice'] as num).toDouble();
      }
      double toppingsCostTotal = 0;
      final List<dynamic> toppingsList = (originalItemData != null && originalItemData['toppings'] is List)
          ? originalItemData['toppings'] : item.toppings.entries.map((e) => {'costPrice': e.key.costPrice, 'quantity': e.value}).toList();
      for (var t in toppingsList) {
        if (t is Map) {
          double tCost = (t['costPrice'] as num?)?.toDouble() ?? 0.0;
          if (tCost == 0 && t['product'] is Map && t['product']['costPrice'] != null) {
            tCost = (t['product']['costPrice'] as num).toDouble();
          }
          double tQty = (t['quantity'] as num?)?.toDouble() ?? 0.0;
          toppingsCostTotal += (tCost * tQty * item.quantity);
        }
      }
      final double itemTotalCost = ((itemBaseCost * item.quantity) + toppingsCostTotal).roundToDouble();

      double taxRate = 0.0;
      if (originalItemData != null && originalItemData['taxRate'] != null) {
        taxRate = (originalItemData['taxRate'] as num).toDouble();
      }
      double itemTax = 0.0;
      double allocatedDiscount = 0.0;
      if (originalBill != null && originalBill.subtotal > 0) {
        double itemRatio = itemNetSubtotal / originalBill.subtotal;
        allocatedDiscount = (originalBillTotalDiscount * itemRatio).roundToDouble();
        double taxableAmount = itemNetSubtotal - allocatedDiscount;
        itemTax = (taxableAmount * taxRate).roundToDouble();
      } else {
        itemTax = (itemNetSubtotal * taxRate).roundToDouble();
      }
      totalReturnTax += itemTax;

      double itemProfit = itemNetSubtotal - (itemTotalCost + allocatedDiscount);
      itemProfit = itemProfit.roundToDouble();
      totalReturnProfit += itemProfit;

      final Map<String, dynamic> itemMap = item.toMap();
      itemMap['subtotal'] = itemNetSubtotal;
      itemMap['taxAmount'] = itemTax;
      returnItemsData.add(itemMap);

      // 5. Cập nhật chi tiết sản phẩm (Sửa sai)
      if (isCorrectionMode) {
        String pId = item.product.id;
        double pQty = item.quantity;

        mainProductsMap[pId] = {
          'quantitySold': FieldValue.increment(-pQty),
          'totalRevenue': FieldValue.increment(-itemNetSubtotal),
          // [QUAN TRỌNG] Trừ discount chi tiết sản phẩm
          'totalDiscount': FieldValue.increment(-itemTotalDiscountToReverse),
        };

        if (currentShiftId != null) {
          shiftProductsMap[pId] = {
            'quantitySold': FieldValue.increment(-pQty),
            'totalRevenue': FieldValue.increment(-itemNetSubtotal),
            'totalDiscount': FieldValue.increment(-itemTotalDiscountToReverse),
          };
        }
      }
    }

    // --- 2. CHỐT SỐ LIỆU TỔNG ---
    // --- 2. CHỐT SỐ LIỆU TỔNG ---
    double returnTotalPayable = 0;
    double returnSurcharge = 0;
    List<Map<String, dynamic>> returnSurchargesList = [];
    double returnBillDiscount = 0;
    double returnVoucherDiscount = 0;
    double returnPointsValue = 0;

    // [BỎ ĐOẠN IF (ISFULLRETURN) GÂY LỖI Ở ĐÂY]
    // Chúng ta luôn tính theo tỷ lệ của số hàng đang trả lần này (kể cả là trả nốt món cuối)

    double ratio = 0.0;
    if (originalBill != null && originalBill.subtotal > 0) {
      // Tỷ lệ = Giá trị Net các món đang trả / Tổng Subtotal Bill gốc
      ratio = totalReturnNetSubtotal / originalBill.subtotal;

      // Nếu vì làm tròn mà ratio > 1 thì chặn lại (dù hiếm khi xảy ra nếu tính đúng)
      if (ratio > 1) ratio = 1;
    }

    if (originalBill != null) {
      // Tính phụ thu hoàn lại theo tỷ lệ
      returnSurchargesList = originalBill.surcharges.map((s) {
        final Map<String, dynamic> newSurcharge = Map<String, dynamic>.from(s);
        if (newSurcharge['isPercent'] != true) {
          // Tiền mặt -> Nhân tỷ lệ
          double oldAmount = (newSurcharge['amount'] as num?)?.toDouble() ?? 0.0;
          newSurcharge['amount'] = (oldAmount * ratio).roundToDouble();
        }
        return newSurcharge;
      }).toList();

      double totalOriginalSurcharge =
      originalBill.surcharges.fold(0.0, (prev, s) {
        double amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        return prev +
            (s['isPercent'] == true
                ? (originalBill.subtotal * (amt / 100))
                : amt);
      });
      returnSurcharge = (totalOriginalSurcharge * ratio).roundToDouble();

      // Tính Giảm giá hoàn lại theo tỷ lệ
      double billDiscVal = (originalBill.discountType == 'VND')
          ? originalBill.discountInput
          : (originalBill.subtotal * originalBill.discountInput / 100);

      returnBillDiscount = (billDiscVal * ratio).roundToDouble();
      returnVoucherDiscount = (originalBill.voucherDiscount * ratio).roundToDouble();
      returnPointsValue = (originalBill.customerPointsValue * ratio).roundToDouble();
    }

    double totalBillLevelReductions = returnBillDiscount + returnVoucherDiscount + returnPointsValue;

    // Công thức tính tổng cuối cùng cho lần trả này
    returnTotalPayable = (totalReturnNetSubtotal + returnSurcharge + totalReturnTax) - totalBillLevelReductions;
    returnTotalPayable = returnTotalPayable.roundToDouble();

    // --- 3. XỬ LÝ CHÊNH LỆCH ---
    final double netDifference = returnTotalPayable - exchangeTotalValue;
    double deductDebt = 0.0;
    double refundCash = 0.0;

    if (netDifference > 0) {
      double currentDebt = originalBill?.debtAmount ?? 0.0;
      if (currentDebt > 0) {
        if (netDifference <= currentDebt) {
          deductDebt = netDifference;
          refundCash = 0;
        } else {
          deductDebt = currentDebt;
          refundCash = netDifference - currentDebt;
        }
      } else {
        refundCash = netDifference;
      }
    }

    // --- 4. GHI DATABASE: BILL RT (SỐ DƯƠNG) ---
    final returnCode = await generateCode(storeId, 'TH');
    final returnBillRef =
    _db.collection('bills').doc('${storeId}_$returnCode');

    final returnBillData = {
      'storeId': storeId,
      'billCode': returnCode,
      'originalBillId': originalBill?.id,
      'originalBillCode': originalBill?.billCode,
      'tableName': 'TRẢ HÀNG',
      'status': 'return',
      'customerName': customer?.name ?? originalBill?.customerName,
      'customerId': customer?.id ?? originalBill?.customerId,
      'createdByName': currentUser.name,
      'startTime': now,
      'createdAt': FieldValue.serverTimestamp(),
      'items': returnItemsData,
      'subtotal': totalReturnSubtotal,
      'totalPayable': returnTotalPayable,
      'totalProfit': totalReturnProfit,
      'taxAmount': totalReturnTax,
      'totalSurcharges': returnSurcharge,
      'surcharges': returnSurchargesList,
      'discount': returnBillDiscount,
      'discountInput': returnBillDiscount,
      'discountType': 'VND',
      'voucherDiscount': returnVoucherDiscount,
      'debtAmount': deductDebt,
      'payments': refundCash > 0
          ? {paymentMethodName ?? 'Tiền mặt': refundCash}
          : {},
      'note': note ?? 'Trả hàng',
      'reportDateKey': todayStr,
      'shiftId': currentShiftId,
      'isCorrection': isCorrectionMode,
    };
    batch.set(returnBillRef, returnBillData);

    // --- 5. CẬP NHẬT REPORT (SỬA LỖI OVERLAPPING PATHS) ---

    // A. LẤY THÔNG TIN CA LÀM VIỆC
    Timestamp shiftStartTime = Timestamp.now();
    if (currentShiftId != null) {
      try {
        final shiftDoc = await _db
            .collection('employee_shifts')
            .doc(currentShiftId)
            .get();
        if (shiftDoc.exists) {
          shiftStartTime = shiftDoc.data()?['startTime'] as Timestamp? ??
              Timestamp.now();
        }
      } catch (e) {
        debugPrint("Lỗi lấy thông tin ca: $e");
      }
    }

    // B. CHUẨN BỊ MAP UPDATE (DÙNG NESTED MAP ĐỂ TRÁNH LỖI)
    // Map này sẽ được dùng cho batch.set(..., SetOptions(merge: true))

    // 1. Dữ liệu tổng ngày
    final Map<String, dynamic> reportUpdates = {
      'returnCount': FieldValue.increment(1),
      'totalDebt': FieldValue.increment(-deductDebt),
    };

    // 2. Map lồng nhau để lưu PaymentMethods (Ngày)
    final Map<String, dynamic> mainPaymentMethodsMap = {};
    // 3. Map lồng nhau để lưu Products (Ngày)
    // 4. Dữ liệu Ca (Shift)
    final Map<String, dynamic> shiftData = {};
    // 5. Map lồng nhau trong Ca
    final Map<String, dynamic> shiftPaymentMethodsMap = {};


    // Khởi tạo thông tin cơ bản cho Ca
    if (currentShiftId != null && currentShiftId.isNotEmpty) {
      shiftData['shiftId'] = currentShiftId;
      shiftData['userId'] = currentUser.uid;
      shiftData['userName'] = currentUser.name;
      shiftData['startTime'] = shiftStartTime;
      shiftData['status'] = 'open';
      shiftData['returnCount'] = FieldValue.increment(1);
      shiftData['totalDebt'] = FieldValue.increment(-deductDebt);
    }

    if (isCorrectionMode) {
      // SCENARIO A: CÙNG CA/NGÀY -> Trừ trực tiếp doanh thu (Sửa sai)
      reportUpdates['totalRevenue'] = FieldValue.increment(-returnTotalPayable);
      reportUpdates['totalProfit'] = FieldValue.increment(-totalReturnProfit);
      reportUpdates['totalTax'] = FieldValue.increment(-totalReturnTax);
      reportUpdates['totalSurcharges'] = FieldValue.increment(-returnSurcharge);
      reportUpdates['totalDiscount'] =
          FieldValue.increment(-totalReturnItemDiscount);
      reportUpdates['totalBillDiscount'] =
          FieldValue.increment(-returnBillDiscount);
      reportUpdates['totalVoucherDiscount'] =
          FieldValue.increment(-returnVoucherDiscount);
      reportUpdates['totalPointsValue'] =
          FieldValue.increment(-returnPointsValue);

      if (currentShiftId != null) {
        shiftData['totalRevenue'] = FieldValue.increment(-returnTotalPayable);
        shiftData['totalProfit'] = FieldValue.increment(-totalReturnProfit);
        shiftData['totalTax'] = FieldValue.increment(-totalReturnTax);
        shiftData['totalSurcharges'] = FieldValue.increment(-returnSurcharge);
        shiftData['totalDiscount'] =
            FieldValue.increment(-totalReturnItemDiscount);
        shiftData['totalBillDiscount'] =
            FieldValue.increment(-returnBillDiscount);
        shiftData['totalVoucherDiscount'] =
            FieldValue.increment(-returnVoucherDiscount);
        shiftData['totalPointsValue'] =
            FieldValue.increment(-returnPointsValue);
      }

      if (isFullReturn) {
        reportUpdates['billCount'] = FieldValue.increment(-1);
        if (currentShiftId != null) {
          shiftData['billCount'] = FieldValue.increment(-1);
        }
      }

      for (var item in returnItems) {
        String key = item.lineId;
        currentReturnQtyMap[key] = (currentReturnQtyMap[key] ?? 0) + item.quantity;

        // 1. Lấy thông tin từ Bill gốc
        Map<String, dynamic>? originalItemData;
        if (originalBill != null) {
          try {
            originalItemData = originalBill.items.firstWhere((bi) {
              if (bi['lineId'] != null) return bi['lineId'] == item.lineId;
              return (bi['product'] as Map?)?['id'] == item.product.id;
            }) as Map<String, dynamic>?;
          } catch (_) {}
        }

        // 2. Lấy Giá Gốc (Gross Price) từ Bill gốc
        double originalSellPrice = item.product.sellPrice;
        if (originalItemData != null && originalItemData['product'] != null) {
          originalSellPrice = (originalItemData['product']['sellPrice'] as num?)?.toDouble() ?? item.product.sellPrice;
        }

        // 3. Tính lại GIẢM GIÁ (để trừ báo cáo)
        double discountForReport = 0;
        if (originalItemData != null) {
          double dVal = (originalItemData['discountValue'] as num?)?.toDouble() ?? 0;
          String dUnit = originalItemData['discountUnit'] ?? '%';

          // Lấy giá gốc từ bill cũ để tính %
          double originalGrossForCalc = 0;
          if (originalItemData['product'] != null) {
            originalGrossForCalc = (originalItemData['product']['sellPrice'] as num?)?.toDouble() ?? item.product.sellPrice;
          } else {
            originalGrossForCalc = item.product.sellPrice;
          }

          if (dVal > 0) {
            if (dUnit == '%') {
              discountForReport = originalGrossForCalc * (dVal / 100);
            } else {
              discountForReport = dVal;
            }
          }
        }

        // --- [SỬA ĐOẠN NÀY] ---

        // 1. Tính toán cho hiển thị (Giá Gốc)
        // Lưu ý: itemSpecificDiscountAmt đã set = 0 ở các bước trước để hiển thị giá gốc
        final double itemGrossSubtotal = (originalSellPrice * item.quantity).roundToDouble();
        totalReturnSubtotal += itemGrossSubtotal; // Cộng dồn giá GỐC cho Bill

        // 2. Tính toán cho Logic Tỷ lệ (Giá Net)
        double unitPriceNet = originalSellPrice - discountForReport;
        final double itemNetSubtotal = (unitPriceNet * item.quantity).roundToDouble();
        totalReturnNetSubtotal += itemNetSubtotal; // [QUAN TRỌNG] Cộng dồn giá NET cho Ratio

        // 3. Discount Report
        double itemTotalDiscountToReverse = (discountForReport * item.quantity).roundToDouble();
        totalReturnItemDiscount += itemTotalDiscountToReverse;

        // 4. Tính lại DOANH THU THỰC TẾ (Net Price) để trừ báo cáo
        // [FIX QUAN TRỌNG]: Lấy Giá Gốc - Giảm Giá = Giá Thực
        double unitPricePostItemDiscount = originalSellPrice - discountForReport;

        // Tổng doanh thu cần hoàn lại (để trừ totalRevenue)
        final double itemSubtotal = (unitPricePostItemDiscount * item.quantity).roundToDouble();
        totalReturnSubtotal += itemSubtotal;

        double itemBaseCost = item.product.costPrice;
        if (originalItemData != null && originalItemData['product'] != null) {
          final p = originalItemData['product'] as Map<String, dynamic>;
          if (p['costPrice'] != null) itemBaseCost = (p['costPrice'] as num).toDouble();
        }
        double toppingsCostTotal = 0;
        final List<dynamic> toppingsList = (originalItemData != null && originalItemData['toppings'] is List)
            ? originalItemData['toppings'] : item.toppings.entries.map((e) => {'costPrice': e.key.costPrice, 'quantity': e.value}).toList();
        for (var t in toppingsList) {
          if (t is Map) {
            double tCost = (t['costPrice'] as num?)?.toDouble() ?? 0.0;
            if (tCost == 0 && t['product'] is Map && t['product']['costPrice'] != null) {
              tCost = (t['product']['costPrice'] as num).toDouble();
            }
            double tQty = (t['quantity'] as num?)?.toDouble() ?? 0.0;
            toppingsCostTotal += (tCost * tQty * item.quantity);
          }
        }
        final double itemTotalCost = ((itemBaseCost * item.quantity) + toppingsCostTotal).roundToDouble();

        double taxRate = 0.0;
        if (originalItemData != null && originalItemData['taxRate'] != null) {
          taxRate = (originalItemData['taxRate'] as num).toDouble();
        }
        double itemTax = 0.0;
        double allocatedDiscount = 0.0;
        if (originalBill != null && originalBill.subtotal > 0) {
          double itemRatio = itemSubtotal / originalBill.subtotal;
          allocatedDiscount = (originalBillTotalDiscount * itemRatio).roundToDouble();
          double taxableAmount = itemSubtotal - allocatedDiscount;
          itemTax = (taxableAmount * taxRate).roundToDouble();
        } else {
          itemTax = (itemSubtotal * taxRate).roundToDouble();
        }
        totalReturnTax += itemTax;

        double itemProfit = itemSubtotal - (itemTotalCost + allocatedDiscount);
        itemProfit = itemProfit.roundToDouble();
        totalReturnProfit += itemProfit;

        final Map<String, dynamic> itemMap = item.toMap();
        itemMap['subtotal'] = itemSubtotal;
        itemMap['taxAmount'] = itemTax;
        returnItemsData.add(itemMap);

        // 5. Cập nhật chi tiết sản phẩm (nếu là sửa sai)
        if (isCorrectionMode) {
          String pId = item.product.id;
          double pQty = item.quantity;

          mainProductsMap[pId] = {
            'quantitySold': FieldValue.increment(-pQty),
            'totalRevenue': FieldValue.increment(-itemSubtotal), // Trừ đúng số tiền Net (31.500)
            'totalDiscount': FieldValue.increment(-itemTotalDiscountToReverse), // Trừ đúng số tiền Giảm (3.500)
          };

          if (currentShiftId != null) {
            shiftProductsMap[pId] = {
              'quantitySold': FieldValue.increment(-pQty),
              'totalRevenue': FieldValue.increment(-itemSubtotal),
              'totalDiscount': FieldValue.increment(-itemTotalDiscountToReverse),
            };
          }
        }
      }
    } else {
      // SCENARIO B: KHÁC CA/NGÀY (Quy trình trả hàng chuẩn)
      reportUpdates['totalReturnRevenue'] =
          FieldValue.increment(returnTotalPayable);
      reportUpdates['totalReturnProfit'] =
          FieldValue.increment(totalReturnProfit);
      reportUpdates['totalReturnTax'] =
          FieldValue.increment(totalReturnTax);

      if (currentShiftId != null) {
        shiftData['totalReturnRevenue'] =
            FieldValue.increment(returnTotalPayable);
        shiftData['totalReturnProfit'] =
            FieldValue.increment(totalReturnProfit);
        shiftData['totalReturnTax'] =
            FieldValue.increment(totalReturnTax);
      }
    }

    // --- LOGIC TRỪ TIỀN MẶT ---
    if (refundCash > 0) {
      // Logic: Nếu không phải Sửa sai (hoặc kể cả sửa sai mà muốn trừ tiền),
      // ta cần giảm totalCash để khớp két.
      final String method = paymentMethodName ?? 'Tiền mặt';

      reportUpdates['totalCash'] = FieldValue.increment(-refundCash);
      mainPaymentMethodsMap[method] = FieldValue.increment(-refundCash);

      if (currentShiftId != null) {
        shiftData['totalCash'] = FieldValue.increment(-refundCash);
        shiftPaymentMethodsMap[method] = FieldValue.increment(-refundCash);
      }
    }

    // C. GHÉP CÁC MAP LỒNG NHAU VÀO REPORT UPDATES
    if (mainPaymentMethodsMap.isNotEmpty) {
      reportUpdates['paymentMethods'] = mainPaymentMethodsMap;
    }
    if (mainProductsMap.isNotEmpty) {
      reportUpdates['products'] = mainProductsMap;
    }

    if (currentShiftId != null && currentShiftId.isNotEmpty) {
      // Ghép con vào Shift
      if (shiftPaymentMethodsMap.isNotEmpty) {
        shiftData['paymentMethods'] = shiftPaymentMethodsMap;
      }
      if (shiftProductsMap.isNotEmpty) {
        shiftData['products'] = shiftProductsMap;
      }

      // Ghép Shift vào Report (Dùng Map lồng nhau, KHÔNG DÙNG DOT KEY)
      reportUpdates['shifts'] = {currentShiftId: shiftData};
    }

    // Thực hiện lệnh set với merge: true
    batch.set(dailyReportRef, reportUpdates, SetOptions(merge: true));

    // --- 6. HOÀN KHO ---
    await _updateStock(batch, returnItems, isReturn: true);

    // --- 7. CẬP NHẬT BILL GỐC & KHÁCH HÀNG ---
    // --- 7. CẬP NHẬT BILL GỐC & KHÁCH HÀNG (LOGIC ĐƠN GIẢN HÓA) ---
    if (originalBill != null) {
      final originalBillRef = _db.collection('bills').doc(originalBill.id);
      List<Map<String, dynamic>> updatedOriginalItems = [];

      for (var itemData in originalBill.items) {
        // 1. Clone data để tránh lỗi tham chiếu bộ nhớ
        Map<String, dynamic> processingItem = Map<String, dynamic>.from(itemData is Map ? itemData : {});

        if (processingItem.isNotEmpty) {
          String billLineId = processingItem['lineId'] ?? '';
          String pId = (processingItem['product'] as Map?)?['id'] ?? '';

          // 2. Tìm xem item này trong bill có nằm trong danh sách đang trả (returnItems) không?
          // So khớp ưu tiên theo lineId, nếu không có thì theo productId
          final matchingReturnItem = returnItems.firstWhereOrNull((rItem) {
            if (billLineId.isNotEmpty && rItem.lineId == billLineId) return true;
            return rItem.product.id == pId;
          });

          // 3. Nếu tìm thấy -> Cộng thẳng số lượng
          if (matchingReturnItem != null) {
            double currentReturnedInDb = (processingItem['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
            double returningNow = matchingReturnItem.quantity;

            // Update = Đã trả trong DB + Đang trả lần này
            processingItem['returnedQuantity'] = currentReturnedInDb + returningNow;
          }
        }
        updatedOriginalItems.add(processingItem);
      }

      final Map<String, dynamic> billUpdates = {'items': updatedOriginalItems};

      // Trừ nợ nếu có
      if (deductDebt > 0) {
        billUpdates['debtAmount'] = FieldValue.increment(-deductDebt);
      }

      billUpdates['hasReturns'] = true;
      if (isFullReturn) billUpdates['status'] = 'return';

      batch.update(originalBillRef, billUpdates);
    }

    if (customer != null) {
      int pointsToReverse = 0;
      if (originalBill != null &&
          originalBill.pointsEarned > 0 &&
          originalBill.subtotal > 0) {
        double totalOriginal = originalBill.subtotal;
        double cumulativeReturnedValue = totalReturnSubtotal;
        pointsToReverse = ((cumulativeReturnedValue / totalOriginal) *
            originalBill.pointsEarned)
            .floor();
      }

      batch.update(_db.collection('customers').doc(customer.id), {
        'totalSpent': FieldValue.increment(-returnTotalPayable),
        'debt': FieldValue.increment(-deductDebt),
        'points': FieldValue.increment(-pointsToReverse),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();

    // --- 9. TẠO BILL MUA ĐỔI ---
    if (exchangeItems.isNotEmpty) {
      await _createExchangeBillOnly(
          storeId: storeId,
          currentUser: currentUser,
          exchangeItems: exchangeItems,
          exchangeTotalValue: exchangeTotalValue,
          refCode: returnCode,
          customer: customer,
          todayStr: todayStr,
          paymentMethodName: paymentMethodName);
    }
  }

  Future<void> _createExchangeBillOnly({
    required String storeId,
    required UserModel currentUser,
    required List<OrderItem> exchangeItems,
    required double exchangeTotalValue,
    required String refCode,
    required CustomerModel? customer,
    required String todayStr,
    String? paymentMethodName,
  }) async {
    final batch = _db.batch();
    final salesCode = await generateCode(storeId, 'EX');
    final salesBillRef = _db.collection('bills').doc('${storeId}_$salesCode');

    final salesBillData = {
      'storeId': storeId,
      'billCode': salesCode,
      'relatedReturnBillId': refCode,
      'tableName': 'ĐỔI HÀNG',
      'status': 'completed',
      'customerName': customer?.name ?? 'Khách lẻ',
      'customerPhone': customer?.phone,
      'customerId': customer?.id,
      'createdByName': currentUser.name,
      'startTime': DateTime.now(),
      'createdAt': FieldValue.serverTimestamp(),
      'items': exchangeItems.map((e) => e.toMap()).toList(),
      'subtotal': exchangeTotalValue,
      'totalPayable': exchangeTotalValue,
      'totalProfit': 0,
      'debtAmount': 0,
      'payments': {paymentMethodName ?? 'Tiền mặt': exchangeTotalValue},
      'note': 'Đổi từ đơn $refCode',
      'reportDateKey': todayStr,
    };
    batch.set(salesBillRef, salesBillData);

    await _updateStock(batch, exchangeItems, isReturn: false);

    final dailyReportRef = _db.collection('daily_reports').doc('${storeId}_$todayStr');
    final Map<String, dynamic> salesReportUpdates = {
      'billCount': FieldValue.increment(1),
      'totalRevenue': FieldValue.increment(exchangeTotalValue),
      'totalCash': FieldValue.increment(exchangeTotalValue),
    };
    for (var item in exchangeItems) {
      salesReportUpdates['products.${item.product.id}.quantitySold'] = FieldValue.increment(item.quantity);
      salesReportUpdates['products.${item.product.id}.totalRevenue'] = FieldValue.increment(item.subtotal);
    }
    batch.update(dailyReportRef, salesReportUpdates);

    if (customer != null) {
      batch.update(_db.collection('customers').doc(customer.id), {
        'totalSpent': FieldValue.increment(exchangeTotalValue),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  bool _checkIfFullReturn(BillModel bill, List<OrderItem> returnItems) {
    final billItems = bill.items.whereType<Map<String, dynamic>>().toList();
    if (returnItems.length != billItems.length) return false;
    for (var billItem in billItems) {
      final String? pId = (billItem['product'] as Map?)?['id'];
      if (pId == null) continue;

      final double qty = (billItem['quantity'] as num?)?.toDouble() ?? 0.0;
      final double returned = (billItem['returnedQuantity'] as num?)?.toDouble() ?? 0.0;

      final double returningNow = returnItems
          .where((r) => r.product.id == pId)
          .fold(0.0, (tong, r) => tong + r.quantity);

      if ((returned + returningNow) < (qty - 0.001)) {
        return false;
      }
    }
    return true;
  }

  Future<void> _updateStock(WriteBatch batch, List<OrderItem> items, {required bool isReturn}) async {
    final Map<String, double> stockChanges = {};
    for (final item in items) {
      final product = item.product;
      final quantity = item.quantity;
      if ((product.productType == 'Thành phẩm/Combo' || product.productType == 'Topping/Bán kèm') &&
          product.compiledMaterials.isNotEmpty) {
        for (final material in product.compiledMaterials) {
          final materialId = material['productId'] as String?;
          final materialQty = (material['quantity'] as num?)?.toDouble() ?? 0.0;
          if (materialId != null && materialQty > 0) {
            stockChanges[materialId] = (stockChanges[materialId] ?? 0) + (materialQty * quantity);
          }
        }
      } else {
        stockChanges[product.id] = (stockChanges[product.id] ?? 0) + quantity;
      }
    }
    stockChanges.forEach((productId, qty) {
      final productRef = _db.collection('products').doc(productId);
      final double finalQty = isReturn ? qty : -qty;
      batch.update(productRef, {'stock': FieldValue.increment(finalQty)});
    });
  }
}

class _SelectReturnItemsDialog extends StatefulWidget {
  final BillModel originalBill;
  final ReturnService returnService;
  final UserModel currentUser;

  const _SelectReturnItemsDialog({
    required this.originalBill,
    required this.returnService,
    required this.currentUser
  });

  @override
  State<_SelectReturnItemsDialog> createState() => _SelectReturnItemsDialogState();
}

class _SelectReturnItemsDialogState extends State<_SelectReturnItemsDialog> {
  final Map<int, double> _itemsToReturn = {};
  late List<OrderItem> _billItems;

  @override
  void initState() {
    super.initState();
    _billItems = widget.originalBill.items
        .whereType<Map<String, dynamic>>()
        .map((e) => OrderItem.fromMap(e))
        .toList();
  }

  void _incrementQty(int index, double maxReturnable) {
    final currentQty = _itemsToReturn[index] ?? 0;
    if (currentQty < maxReturnable) {
      setState(() {
        _itemsToReturn[index] = currentQty + 1;
      });
    } else {
      ToastService().show(message: "Đã đạt giới hạn trả.", type: ToastType.warning);
    }
  }

  void _decrementQty(int index) {
    final currentQty = _itemsToReturn[index] ?? 0;
    if (currentQty > 0) {
      setState(() {
        final newQty = currentQty - 1;
        if (newQty <= 0) {
          _itemsToReturn.remove(index);
        } else {
          _itemsToReturn[index] = newQty;
        }
      });
    }
  }

  double get _calculateTotalRefund {
    double total = 0;
    _itemsToReturn.forEach((index, qty) {
      final originalItemData = widget.originalBill.items[index] as Map<String, dynamic>;
      final double origSubtotal = (originalItemData['subtotal'] as num?)?.toDouble() ?? 0.0;
      final double origQty = (originalItemData['quantity'] as num?)?.toDouble() ?? 1.0;

      double realUnitPrice = 0;
      if (origQty > 0) realUnitPrice = origSubtotal / origQty;

      total += (realUnitPrice * qty);
    });
    return total;
  }

  Future<void> _submit() async {
    if (_itemsToReturn.isEmpty) return;

    final List<OrderItem> returnList = [];
    _itemsToReturn.forEach((index, qty) {
      final originalItem = _billItems[index];

      // Tính lại giá thực tế (gồm topping/giảm giá cũ)
      final originalItemData = widget.originalBill.items[index] as Map<String, dynamic>;
      final double origSubtotal = (originalItemData['subtotal'] as num?)?.toDouble() ?? 0.0;
      final double origQty = (originalItemData['quantity'] as num?)?.toDouble() ?? 1.0;
      double realUnitPrice = (origQty > 0) ? (origSubtotal / origQty) : originalItem.price;

      returnList.add(originalItem.copyWith(quantity: qty, price: realUnitPrice));
    });

    try {
      CustomerModel? customer;
      if (widget.originalBill.customerId != null) {
        try {
          final doc = await FirebaseFirestore.instance.collection('customers').doc(widget.originalBill.customerId).get();
          if (doc.exists) customer = CustomerModel.fromFirestore(doc);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pop();

      Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text("Xử lý Đổi/Trả: ${widget.originalBill.billCode}")),
            body: ExchangeProcessorWidget(
              currentUser: widget.currentUser,
              returnService: widget.returnService,
              initialReturnItems: returnList,
              originalBill: widget.originalBill,
              customer: customer,
            ),
          )
      ));
    } catch (e) {
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Chọn món trả: ${widget.originalBill.billCode}"),
      content: SizedBox(
        width: 600,
        height: 500,
        child: Column(
          children: [
            Expanded(
              child: ListView.separated(
                itemCount: _billItems.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _billItems[index];
                  final returnQty = _itemsToReturn[index] ?? 0;

                  final rawItemMap = widget.originalBill.items[index] as Map<String, dynamic>;
                  final double alreadyReturned = (rawItemMap['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
                  final double remainingQty = item.quantity - alreadyReturned;

                  if (remainingQty <= 0.001) return const SizedBox.shrink();

                  // Giá hiển thị (đã chia đều subtotal)
                  final double origSubtotal = (rawItemMap['subtotal'] as num?)?.toDouble() ?? 0.0;
                  final double origQty = (rawItemMap['quantity'] as num?)?.toDouble() ?? 1.0;
                  final double displayPrice = origQty > 0 ? (origSubtotal / origQty) : item.price;

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.product.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            if (item.toppings.isNotEmpty)
                              Text("+ ${item.toppings.keys.map((p) => p.productName).join(', ')}", style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic)),
                            const SizedBox(height: 4),
                            Text.rich(TextSpan(children: [
                              TextSpan(text: "${formatNumber(displayPrice)} đ   ", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                              TextSpan(text: "Mua: ${formatNumber(item.quantity)} "),
                              if (alreadyReturned > 0) TextSpan(text: "(Đã trả: ${formatNumber(alreadyReturned)}) ", style: const TextStyle(color: Colors.red)),
                              TextSpan(text: "Còn: ${formatNumber(remainingQty)}", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            ]), style: const TextStyle(fontSize: 13)),
                          ],
                        )),
                        Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                          child: Row(
                            children: [
                              IconButton(icon: const Icon(Icons.remove, color: Colors.red), onPressed: () => _decrementQty(index)),
                              SizedBox(width: 30, child: Text(formatNumber(returnQty), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold))),
                              IconButton(icon: const Icon(Icons.add, color: Colors.green), onPressed: () => _incrementQty(index, remainingQty)),
                            ],
                          ),
                        )
                      ],
                    ),
                  );
                },
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Tổng hoàn dự kiến:", style: TextStyle(fontWeight: FontWeight.bold)),
                Text(formatNumber(_calculateTotalRefund), style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            )
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Đóng")),
        ElevatedButton(onPressed: _itemsToReturn.isNotEmpty ? _submit : null, child: const Text("Tiếp tục")),
      ],
    );
  }
}

class ReturnOrderScreen extends StatefulWidget {
  final UserModel currentUser;

  const ReturnOrderScreen({super.key, required this.currentUser});

  @override
  State<ReturnOrderScreen> createState() => _ReturnOrderScreenState();
}

class _ReturnOrderScreenState extends State<ReturnOrderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ReturnService _returnService = ReturnService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đổi Trả Hàng'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Theo Hóa Đơn Cũ'),
            Tab(text: 'Đổi Trả Trực Tiếp'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _ReturnByBillTab(currentUser: widget.currentUser, returnService: _returnService),
          _DirectReturnTab(currentUser: widget.currentUser, returnService: _returnService),
        ],
      ),
    );
  }
}

class ExchangeProcessorWidget extends StatefulWidget {
  final UserModel currentUser;
  final ReturnService returnService;
  final List<OrderItem> initialReturnItems;
  final BillModel? originalBill; // Có thể null
  final CustomerModel? customer; // Có thể null (nếu trả trực tiếp chưa chọn khách)

  const ExchangeProcessorWidget({
    super.key,
    required this.currentUser,
    required this.returnService,
    required this.initialReturnItems,
    this.originalBill,
    this.customer,
  });

  @override
  State<ExchangeProcessorWidget> createState() => _ExchangeProcessorWidgetState();
}

class _ExchangeProcessorWidgetState extends State<ExchangeProcessorWidget> {
  final List<OrderItem> _returnList = [];
  final List<OrderItem> _exchangeList = [];
  final TextEditingController _noteCtrl = TextEditingController();
  String? _currentShiftId;
  final FirestoreService _firestoreService = FirestoreService();

  double _dispReturnSubtotal = 0;
  double _dispReturnTax = 0;
  double _dispReturnBillDiscount = 0;
  double _dispReturnSurcharge = 0;
  double _dispTotalRefundAmount = 0;
  bool _isProcessing = false;
  double _dispExchangeTax = 0;

  Map<String, dynamic>? _storeTaxSettings;
  final Map<String, String> _productTaxMap = {};
  List<ProductModel> _allProductsCache = [];

  // PTTT cố định
  final List<String> _paymentMethods = ['Tiền mặt', 'Chuyển khoản'];
  String _selectedRefundMethod = 'Tiền mặt';
  bool _isLoadingMethods = false;

  static const Map<String, Map<String, dynamic>> _kDirectRates = {
    'HKD_0': {'rate': 0.0, 'name': '0%'},
    'HKD_RETAIL': {'rate': 0.015, 'name': '1.5%'},
    'HKD_PRODUCTION': {'rate': 0.045, 'name': '4.5%'},
    'HKD_SERVICE': {'rate': 0.07, 'name': '7%'},
    'HKD_LEASING': {'rate': 0.1, 'name': '10%'},
  };
  static const Map<String, Map<String, dynamic>> _kDeductionRates = {
    'VAT_0': {'rate': 0.0, 'name': '0%'},
    'VAT_5': {'rate': 0.05, 'name': '5%'},
    'VAT_8': {'rate': 0.08, 'name': '8%'},
    'VAT_10': {'rate': 0.1, 'name': '10%'},
  };

  @override
  void initState() {
    super.initState();
    _loadCurrentShift();
    _returnList.addAll(widget.initialReturnItems);
    _loadTaxSettings();
    _loadPaymentMethods();
    _preloadAllProducts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _calculateDetailedReturnValues();
    });
  }

  Future<void> _loadCurrentShift() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentShiftId = prefs.getString('current_shift_id');
    });
    debugPrint(">>> ReturnScreen: Ca hiện tại là $_currentShiftId");
  }

  Future<void> _loadPaymentMethods() async {
    setState(() => _isLoadingMethods = true);
    try {
      final snapshot = await _firestoreService.getPaymentMethods(widget.currentUser.storeId).first;
      final List<String> methods = ['Tiền mặt'];

      for (var doc in snapshot.docs) {
        final m = PaymentMethodModel.fromFirestore(doc);
        if (m.active && m.type != PaymentMethodType.cash) {
          methods.add(m.name);
        }
      }

      if (mounted) {
        setState(() {
          _paymentMethods.clear();
          _paymentMethods.addAll(methods);
          if (!_paymentMethods.contains(_selectedRefundMethod)) {
            _selectedRefundMethod = _paymentMethods.first;
          }
        });
      }
    } catch (e) {
      debugPrint("Lỗi load PTTT: $e");
    } finally {
      if(mounted) setState(() => _isLoadingMethods = false);
    }
  }

  Future<void> _loadTaxSettings() async {
    try {
      final settings = await _firestoreService.getStoreTaxSettings(widget.currentUser.storeId);
      if (mounted && settings != null) {
        setState(() {
          _storeTaxSettings = settings;
          final rawMap = settings['taxAssignmentMap'] as Map<String, dynamic>? ?? {};
          _productTaxMap.clear();
          rawMap.forEach((taxKey, productIds) {
            if (productIds is List) {
              for (var pid in productIds) {
                _productTaxMap[pid.toString()] = taxKey;
              }
            }
          });
        });
      }
    } catch (e) { debugPrint("Lỗi tải thuế: $e"); }
  }

  Future<void> _preloadAllProducts() async {
    try {
      final snapshot = await _firestoreService.getAllProductsStream(widget.currentUser.storeId).first;
      if (mounted) _allProductsCache = snapshot;
    } catch (_) {}
  }

  String _getTaxDisplayString(ProductModel product) {
    if (_storeTaxSettings == null) return '';
    final String calcMethod = _storeTaxSettings!['calcMethod'] ?? 'direct';
    final String? taxKey = _productTaxMap[product.id];
    if (taxKey == null) return '';

    if (calcMethod == 'deduction') {
      switch (taxKey) {
        case 'VAT_10': return '(VAT 10%)';
        case 'VAT_8': return '(VAT 8%)';
        case 'VAT_5': return '(VAT 5%)';
        case 'VAT_0': return '(VAT 0%)';
        default: return '';
      }
    } else {
      switch (taxKey) {
        case 'HKD_RETAIL': return '(LST 1.5%)';
        case 'HKD_PRODUCTION': return '(LST 4.5%)';
        case 'HKD_SERVICE': return '(LST 7%)';
        case 'HKD_LEASING': return '(LST 10%)';
        default: return '';
      }
    }
  }

  double _calculateExchangeTaxValue() {
    if (_storeTaxSettings == null) return 0.0;
    double totalTax = 0.0;
    final String calcMethod = _storeTaxSettings!['calcMethod'] ?? 'direct';
    final bool isDeduction = calcMethod == 'deduction';
    final rateMap = isDeduction ? _kDeductionRates : _kDirectRates;
    final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

    for (var item in _exchangeList) {
      final String taxKey = _productTaxMap[item.product.id] ?? defaultTaxKey;
      final double taxRate = rateMap[taxKey]?['rate'] ?? 0.0;
      double itemTotal = item.price * item.quantity;
      totalTax += (itemTotal * taxRate);
    }
    return totalTax;
  }

  double _getTaxRate(String? taxKey) {
    if (taxKey == null || _storeTaxSettings == null) return 0.0;

    final String calcMethod = _storeTaxSettings!['calcMethod'] ?? 'direct';
    final bool isDeduction = calcMethod == 'deduction';

    // Map tỷ lệ thuế (bạn có thể đưa map này ra ngoài class nếu muốn dùng chung)
    final rateMap = isDeduction ? _kDeductionRates : _kDirectRates;

    if (rateMap.containsKey(taxKey)) {
      return rateMap[taxKey]!['rate'] as double;
    }
    return 0.0;
  }

  void _calculateDetailedReturnValues() {
    double totalSubtotal = 0;
    double totalSpecificTax = 0;

    // 1. Tính Tổng Giảm Giá của Bill Gốc (Discount + Voucher + Points)
    double originalBillTotalDiscount = 0;
    if (widget.originalBill != null) {
      double discountVal = 0;
      // Tính giảm giá thủ công
      if (widget.originalBill!.discountType == 'VND') {
        discountVal = widget.originalBill!.discountInput;
      } else {
        discountVal = widget.originalBill!.subtotal * (widget.originalBill!.discountInput / 100);
      }

      originalBillTotalDiscount = discountVal +
          widget.originalBill!.voucherDiscount +
          widget.originalBill!.customerPointsValue;
    }

    for (var item in _returnList) {
      double unitPriceForReturn = item.price;
      double taxPerUnit = 0;

      if (widget.originalBill != null) {
        final originalItemData = widget.originalBill!.items.firstWhereOrNull((bi) {
          if (bi is Map<String, dynamic>) {
            if (bi['lineId'] != null && bi['lineId'] == item.lineId) return true;
            final pData = bi['product'] as Map?;
            return pData != null && pData['id'] == item.product.id;
          }
          return false;
        });

        if (originalItemData != null && originalItemData is Map<String, dynamic>) {
          final double origSubtotal = (originalItemData['subtotal'] as num?)?.toDouble() ?? 0.0;
          final double origQty = (originalItemData['quantity'] as num?)?.toDouble() ?? 1.0;

          if (origQty > 0) unitPriceForReturn = origSubtotal / origQty;

          // --- [START] LOGIC TÍNH LẠI THUẾ THỰC TẾ ---

          // 1. Lấy thuế suất (Ưu tiên lấy từ bill đã lưu, nếu k có thì lấy từ cài đặt hiện tại)
          double taxRate = 0.0;
          if (originalItemData['taxRate'] != null) {
            taxRate = (originalItemData['taxRate'] as num).toDouble();
          } else {
            // Fallback: Tìm taxKey và tra trong cài đặt
            String? taxKey = originalItemData['taxKey'];
            if (taxKey == null) {
              // Nếu bill cũ k lưu taxKey, tra theo product ID
              final productId = (originalItemData['product'] as Map)['id'];
              final defaultTaxKey = (_storeTaxSettings?['calcMethod'] == 'deduction') ? 'VAT_0' : 'HKD_0';
              taxKey = _productTaxMap[productId] ?? defaultTaxKey;
            }
            taxRate = _getTaxRate(taxKey);
          }

          if (taxRate > 0 && widget.originalBill!.subtotal > 0) {
            // 2. Tính tỷ trọng của món này trong bill gốc
            // Tỷ trọng = (Giá trị món / Tổng Subtotal Bill)
            final double itemRatio = origSubtotal / widget.originalBill!.subtotal;

            // 3. Phân bổ giảm giá cho món này
            final double allocatedDiscount = originalBillTotalDiscount * itemRatio;

            // 4. Tính giá tính thuế (Taxable Base) = Giá trị món - Giảm giá phân bổ
            final double taxableBase = origSubtotal - allocatedDiscount;

            // 5. Tính tổng thuế thực tế của dòng này
            final double realTotalLineTax = taxableBase * taxRate;

            // 6. Chia ra thuế đơn vị
            if (origQty > 0) {
              taxPerUnit = realTotalLineTax / origQty;
            }
          }
          // --- [END] ---
        }
      }

      double itemSubtotal = (unitPriceForReturn * item.quantity).roundToDouble();
      totalSubtotal += itemSubtotal;

      // Cộng thuế hoàn (đã tính lại chính xác ở trên)
      totalSpecificTax += (taxPerUnit * item.quantity);
    }

    double ratio = 0.0;
    double returnSurcharge = 0.0;
    double returnBillDiscount = 0.0;

    // Thuế dùng giá trị đã tính lại
    double returnTax = totalSpecificTax.roundToDouble();

    if (widget.originalBill != null && widget.originalBill!.subtotal > 0) {
      ratio = totalSubtotal / widget.originalBill!.subtotal;

      double totalOriginalSurcharge = widget.originalBill!.surcharges.fold(0.0, (prev, s) {
        double amt = (s['amount'] as num?)?.toDouble() ?? 0.0;
        return prev + (s['isPercent'] == true ? (widget.originalBill!.subtotal * (amt / 100)) : amt);
      });
      returnSurcharge = (totalOriginalSurcharge * ratio).roundToDouble();

      double totalOriginalBillDiscount = widget.originalBill!.discountType == 'VND'
          ? widget.originalBill!.discountInput
          : (widget.originalBill!.subtotal * widget.originalBill!.discountInput / 100);
      totalOriginalBillDiscount += widget.originalBill!.voucherDiscount;
      returnBillDiscount = (totalOriginalBillDiscount * ratio).roundToDouble();
    }

    setState(() {
      _dispReturnSubtotal = totalSubtotal;
      _dispReturnTax = returnTax;
      _dispReturnSurcharge = returnSurcharge;
      _dispReturnBillDiscount = returnBillDiscount;

      // Công thức tổng cuối cùng
      _dispTotalRefundAmount = (totalSubtotal + returnSurcharge + returnTax) - returnBillDiscount;
      _dispTotalRefundAmount = _dispTotalRefundAmount.roundToDouble();

      _dispExchangeTax = _calculateExchangeTaxValue().roundToDouble();
    });
  }

  double get _totalExchangeValue =>
      _exchangeList.fold(0.0, (tong, item) => tong + (item.price * item.quantity)) + _dispExchangeTax;

  Future<void> _pickExchangeProducts() async {
    final List<ProductModel>? selectedProducts = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: [],
      groupByCategory: true,
      allowedProductTypes: ['Hàng hóa', 'Dịch vụ/Tính giờ', 'Thành phẩm/Combo', 'Topping/Bán kèm'],
    );

    if (selectedProducts != null && selectedProducts.isNotEmpty) {
      for (var product in selectedProducts) {
        await _processNewExchangeItem(product);
      }
    }
  }

  Future<void> _processNewExchangeItem(ProductModel product) async {
    setState(() {
      _exchangeList.add(OrderItem(
        product: product,
        quantity: 1,
        price: product.sellPrice,
        selectedUnit: product.unit ?? '',
        addedAt: Timestamp.now(),
        addedBy: widget.currentUser.name ?? '',
        discountValue: 0,
        commissionStaff: {},
        toppings: {},
        note: null,
      ));
      _dispExchangeTax = _calculateExchangeTaxValue();
    });
  }

  Future<void> _editExchangeItem(int index) async {
    final item = _exchangeList[index];
    if (_allProductsCache.isEmpty) await _preloadAllProducts();

    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ProductOptionsDialog(
        product: item.product,
        allProducts: _allProductsCache,
        initialPrice: item.price,
        initialUnit: item.selectedUnit,
        initialToppings: item.toppings,
        initialNote: item.note,
      ),
    );

    if (result != null) {
      setState(() {
        _exchangeList[index] = item.copyWith(
          price: result['price'],
          selectedUnit: result['selectedUnit'],
          toppings: result['selectedToppings'],
          note: () => result['note'],
        );
        _dispExchangeTax = _calculateExchangeTaxValue();
      });
    }
  }

  void _updateReturnItemQty(int index, double delta) {
    final item = _returnList[index];
    final double newQty = item.quantity + delta;

    double maxLimit = 999999;
    if (widget.originalBill != null) {
      final originalItemData = widget.originalBill!.items.firstWhereOrNull((bi) {
        if (bi is Map<String, dynamic>) {
          if (bi['lineId'] != null && bi['lineId'] == item.lineId) return true;
          final pData = bi['product'] as Map?;
          return pData != null && pData['id'] == item.product.id;
        }
        return false;
      });
      if (originalItemData != null && originalItemData is Map<String, dynamic>) {
        double origQty = (originalItemData['quantity'] as num?)?.toDouble() ?? 0.0;
        double returned = (originalItemData['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
        maxLimit = origQty - returned;
      }
    }

    if (newQty > maxLimit) {
      ToastService().show(message: "Không thể trả quá số lượng còn lại ($maxLimit).", type: ToastType.warning);
      return;
    }

    setState(() {
      if (newQty <= 0) {
        _returnList.removeAt(index);
      } else {
        _returnList[index] = item.copyWith(quantity: newQty);
      }
      _calculateDetailedReturnValues();
    });
  }

  Future<void> _submitTransaction() async {
    if (_isProcessing) return;
    if (_returnList.isEmpty) {
      ToastService().show(message: "Chưa có sản phẩm trả lại", type: ToastType.warning);
      return;
    }

    final double diff = _totalExchangeValue - _dispTotalRefundAmount;

    String confirmMsg = "";
    if (diff > 0) {
      confirmMsg = "KHÁCH TRẢ THÊM: ${formatNumber(diff)}";
    } else {
      final double refundAmt = diff.abs();
      final double debt = widget.originalBill?.debtAmount ?? 0.0;

      if (debt > 0) {
        if (refundAmt <= debt) {
          confirmMsg = "HOÀN TIỀN: ${formatNumber(refundAmt)}\n(Trừ hoàn toàn vào dư nợ)";
        } else {
          final cashReturn = refundAmt - debt;
          confirmMsg = "HOÀN TIỀN: ${formatNumber(refundAmt)}\n(-${formatNumber(debt)} Dư nợ | -${formatNumber(cashReturn)} Tiền mặt)";
        }
      } else {
        confirmMsg = "HOÀN TIỀN KHÁCH: ${formatNumber(refundAmt)}";
      }
    }

    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Xác nhận Giao dịch"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryRow("Tổng giá trị trả:", _dispTotalRefundAmount, isBold: true, color: Colors.red),
              _buildSummaryRow("Tổng giá trị mua đổi:", _totalExchangeValue, isBold: true, color: Colors.green),
              const Divider(thickness: 1.5),
              Center(
                  child: Text(confirmMsg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)
                  )
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xác nhận")),
          ],
        )
    );

    if (confirm != true) return;
    setState(() {
      _isProcessing = true;
    });
    try {
      // 1. Gọi service để kiểm tra hoặc tạo ca mới nếu đang đóng
      await ShiftService().ensureShiftOpen(
        widget.currentUser.storeId,
        widget.currentUser.uid,
        widget.currentUser.name ?? 'NV',
        widget.currentUser.ownerUid ?? widget.currentUser.uid,
      );

      // 2. Load lại ID mới nhất từ bộ nhớ sau khi ensureShiftOpen chạy xong
      final prefs = await SharedPreferences.getInstance();
      final String? freshShiftId = prefs.getString('current_shift_id');

      if (mounted) {
        setState(() {
          _currentShiftId = freshShiftId;
        });
      }

      if (_currentShiftId == null) {
        ToastService().show(message: "Không thể tạo phiên làm việc mới. Vui lòng thử lại.", type: ToastType.error);
        return;
      }
    } catch (e) {
      debugPrint("Lỗi tạo ca khi trả hàng: $e");
    }

    try {
      String finalNote = _noteCtrl.text.isEmpty ? 'Đổi trả hàng' : _noteCtrl.text;
      if (diff < 0) {
        final double refundAmt = diff.abs();
        final double debt = widget.originalBill?.debtAmount ?? 0.0;
        if (refundAmt > debt) {
          finalNote += " [Hoàn: $_selectedRefundMethod]";
        } else if (debt > 0) {
          finalNote += " [Trừ dư nợ]";
        }
      }

      await widget.returnService.processExchangeTransaction(
        storeId: widget.currentUser.storeId,
        currentUser: widget.currentUser,
        returnItems: _returnList,
        exchangeItems: _exchangeList,
        returnTotalValue: _dispTotalRefundAmount,
        exchangeTotalValue: _totalExchangeValue,
        originalBill: widget.originalBill,
        customer: widget.customer,
        note: finalNote,
        paymentMethodName: _selectedRefundMethod,
        currentShiftId: _currentShiftId,
      );

      ToastService().show(message: "Giao dịch thành công!", type: ToastType.success);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ToastService().show(message: "Lỗi: $e", type: ToastType.error);
      }
    }
  }

  Widget _buildSummaryRow(String label, double value, {bool isNegative = false, bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: Colors.black87)),
          Text("${isNegative ? '-' : ''}${formatNumber(value)}", style: TextStyle(fontWeight: isBold ? FontWeight.bold : FontWeight.normal, color: color ?? (isNegative ? Colors.red : Colors.black87))),
        ],
      ),
    );
  }

  Widget _buildCardHeader(String title, Color bg, Color text, {Widget? action}) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: bg, width: double.infinity,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: text)),
        if(action != null) action
      ]),
    );
  }

  Widget _buildReturnSummaryPanel() {
    return Container(
      padding: const EdgeInsets.all(12), color: Colors.white,
      child: Column(
        children: [
          _buildSummaryRow("Tổng tiền hàng trả:", _dispReturnSubtotal),
          if (_dispReturnBillDiscount > 0) _buildSummaryRow("Trừ chiết khấu Bill:", _dispReturnBillDiscount, isNegative: true),
          if (_dispReturnSurcharge > 0) _buildSummaryRow("Hoàn phụ thu:", _dispReturnSurcharge),
          if (_dispReturnTax > 0) _buildSummaryRow("Hoàn thuế:", _dispReturnTax),
          const Divider(),
          _buildSummaryRow("GIÁ TRỊ HOÀN LẠI:", _dispTotalRefundAmount, isBold: true, color: Colors.red),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double diff = _totalExchangeValue - _dispTotalRefundAmount;
    final double refundAmt = diff.abs();
    final double currentDebt = widget.originalBill?.debtAmount ?? 0.0;

    String diffText = "";
    Color diffColor = Colors.grey;
    bool showPaymentMethod = false;

    // --- CHECK ĐỂ HIỂN THỊ UI ---
    if (diff > 0) {
      diffText = "KHÁCH TRẢ: ${formatNumber(diff)}";
      diffColor = Colors.green;
      showPaymentMethod = true;
    } else if (diff < 0) {
      if (currentDebt > 0) {
        if (refundAmt <= currentDebt) {
          // Trừ hoàn toàn vào nợ -> Ẩn PTTT
          diffText = "TRỪ DƯ NỢ: ${formatNumber(refundAmt)}";
          diffColor = Colors.orange;
          showPaymentMethod = false;
        } else {
          // Trừ nợ + Hoàn tiền mặt -> Hiện PTTT cho phần tiền mặt
          final cashReturn = refundAmt - currentDebt;
          diffText = "HOÀN: ${formatNumber(refundAmt)}\n(Tiền mặt: ${formatNumber(cashReturn)})";
          diffColor = Colors.red;
          showPaymentMethod = true;
        }
      } else {
        // Không nợ -> Hoàn hết -> Hiện PTTT
        diffText = "HOÀN LẠI: ${formatNumber(refundAmt)}";
        diffColor = Colors.red;
        showPaymentMethod = true;
      }
    } else {
      diffText = "THANH TOÁN: 0";
      diffColor = Colors.grey;
      showPaymentMethod = false;
    }

    return Column(
      children: [
        // BODY
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // CỘT TRÁI: HÀNG TRẢ
                Expanded(
                  flex: 4,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 2,
                    child: Column(
                      children: [
                        _buildCardHeader("HÀNG TRẢ LẠI (Nhập kho)", Colors.red.shade50, Colors.red),
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: _returnList.length,
                              separatorBuilder: (_,__) => const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _returnList[index];
                                final taxStr = _getTaxDisplayString(item.product);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // [FIX UI 1] Tên + Thuế
                                            Text.rich(TextSpan(children: [
                                              TextSpan(text: item.product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                              if(taxStr.isNotEmpty) TextSpan(text: ' $taxStr', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                                            ])),

                                            // [FIX UI 2] Danh sách Topping
                                            if (item.toppings.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 2),
                                                child: Text(
                                                  "+ ${item.toppings.keys.map((p) => p.productName).join(', ')}",
                                                  style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
                                                ),
                                              ),

                                            Text("${formatNumber(item.price)} đ", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        width: 120, height: 35,
                                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: [
                                            IconButton(
                                              icon: const Icon(Icons.remove, size: 16, color: Colors.red),
                                              onPressed: () => _updateReturnItemQty(index, -1),
                                              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 35),
                                            ),
                                            Text(formatNumber(item.quantity), style: const TextStyle(fontWeight: FontWeight.bold)),
                                            IconButton(
                                              icon: const Icon(Icons.add, size: 16, color: Colors.green),
                                              onPressed: () => _updateReturnItemQty(index, 1),
                                              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 35),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 75,
                                        child: Text(formatNumber(item.subtotal), textAlign: TextAlign.end, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                      )
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        _buildReturnSummaryPanel(),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // CỘT PHẢI
                Expanded(
                  flex: 6,
                  child: Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 2,
                    child: Column(
                      children: [
                        _buildCardHeader("HÀNG ĐỔI / MUA MỚI", Colors.green.shade50, Colors.green,
                            action: ElevatedButton.icon(
                              onPressed: _pickExchangeProducts,
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text("Thêm món"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.green, elevation: 0, visualDensity: VisualDensity.compact),
                            )
                        ),
                        Expanded(
                          child: Container(
                            color: Colors.white,
                            child: _exchangeList.isEmpty
                                ? const Center(child: Text("Chưa chọn sản phẩm đổi", style: TextStyle(color: Colors.grey)))
                                : ListView.separated(
                              padding: const EdgeInsets.all(8),
                              itemCount: _exchangeList.length,
                              separatorBuilder: (_,__) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final item = _exchangeList[index];
                                final taxStr = _getTaxDisplayString(item.product);
                                return ExchangeItemCard(
                                  item: item,
                                  index: index,
                                  taxDisplay: taxStr,
                                  onUpdate: (newItem) { setState(() => _exchangeList[index] = newItem); _dispExchangeTax = _calculateExchangeTaxValue(); },
                                  onRemove: () { setState(() => _exchangeList.removeAt(index)); _dispExchangeTax = _calculateExchangeTaxValue(); },
                                  onTap: () => _editExchangeItem(index),
                                );
                              },
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.green.shade50.withValues(alpha: 0.3),
                          child: Column(
                            children: [
                              if (_dispExchangeTax > 0) _buildSummaryRow("Thuế (Hàng đổi):", _dispExchangeTax),
                              _buildSummaryRow("TỔNG MUA MỚI:", _totalExchangeValue, isBold: true, color: Colors.green),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // FOOTER
        Card(
          elevation: 4,
          margin: const EdgeInsets.all(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                          controller: _noteCtrl,
                          decoration: const InputDecoration(
                              labelText: "Ghi chú đơn",
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                          )
                      ),
                    ),
                    const SizedBox(width: 12),

                    if (showPaymentMethod)
                      Expanded(
                        flex: 1,
                        child: InputDecorator(
                          decoration: const InputDecoration(
                              labelText: "Hoàn tiền qua",
                              border: OutlineInputBorder(),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12)
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedRefundMethod,
                              isDense: true,
                              isExpanded: true,
                              // [FIX] PTTT lấy từ DB
                              items: _isLoadingMethods
                                  ? [const DropdownMenuItem(value: 'Tiền mặt', child: Text("Đang tải..."))]
                                  : _paymentMethods.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)))).toList(),
                              onChanged: (val) { if (val != null) setState(() => _selectedRefundMethod = val); },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(diffText, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: diffColor)),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                      onPressed: _isProcessing ? null : _submitTransaction,
                      child: _isProcessing
                          ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      )
                          : const Text("HOÀN TẤT", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        )
      ],
    );
  }
}

class _ReturnByBillTab extends StatefulWidget {
  final UserModel currentUser;
  final ReturnService returnService;

  const _ReturnByBillTab({required this.currentUser, required this.returnService});

  @override
  State<_ReturnByBillTab> createState() => _ReturnByBillTabState();
}

class _ReturnByBillTabState extends State<_ReturnByBillTab> {
  final TextEditingController _searchController = TextEditingController();
  List<BillModel> _foundBills = [];
  bool _isLoading = false;
  DateTime _selectedDate = DateTime.now();

  Future<void> _searchBills() async {
    setState(() => _isLoading = true);
    try {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

      final snapshot = await FirebaseFirestore.instance
          .collection('bills')
          .where('storeId', isEqualTo: widget.currentUser.storeId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay))
          .orderBy('createdAt', descending: true)
          .get();

      final allBills = snapshot.docs.map((doc) => BillModel.fromFirestore(doc)).toList();
      final keyword = _searchController.text.toLowerCase().trim();

      if (keyword.isEmpty) {
        _foundBills = allBills;
      } else {
        _foundBills = allBills.where((bill) {
          return bill.billCode.toLowerCase().contains(keyword) ||
              (bill.customerName ?? '').toLowerCase().contains(keyword) ||
              (bill.customerPhone ?? '').contains(keyword);
        }).toList();
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tìm kiếm: $e", type: ToastType.error);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _searchBills();
    }
  }

  void _onSelectBill(BillModel cachedBill) async {
    // 1. Hiển thị loading nhẹ hoặc chặn tương tác để lấy dữ liệu mới nhất
    // (Optional: có thể show dialog loading nếu muốn, ở đây mình dùng biến _isLoading của màn hình)
    setState(() => _isLoading = true);

    BillModel? freshBill;

    try {
      // [QUAN TRỌNG] Luôn fetch lại bill từ Firestore để đảm bảo data mới nhất (đã trừ returnedQuantity)
      final docSnapshot = await FirebaseFirestore.instance
          .collection('bills')
          .doc(cachedBill.id)
          .get();

      if (docSnapshot.exists) {
        freshBill = BillModel.fromFirestore(docSnapshot);
      } else {
        ToastService().show(message: "Hóa đơn không tồn tại.", type: ToastType.error);
        setState(() => _isLoading = false);
        return;
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải dữ liệu: $e", type: ToastType.error);
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = false);

    // TỪ ĐÂY TRỞ ĐI, DÙNG freshBill THAY VÌ cachedBill
    if (freshBill.status == 'cancelled') {
      ToastService().show(message: "Không thể xử lý đơn đã hủy.", type: ToastType.warning);
      return;
    }
    if (freshBill.status == 'return') {
      ToastService().show(message: "Đơn hàng này đã được hoàn trả toàn bộ trước đó.", type: ToastType.warning);
      return;
    }

    // --- LỌC VÀ TÍNH SỐ LƯỢNG CÒN LẠI (Dùng freshBill) ---
    final List<OrderItem> billItems = [];
    for (var itemData in freshBill.items) {
      if (itemData is Map<String, dynamic>) {
        final double originalQty = (itemData['quantity'] as num?)?.toDouble() ?? 0.0;
        final double returnedQty = (itemData['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
        final double remaining = originalQty - returnedQty;

        // Chỉ thêm vào danh sách nếu còn hàng để trả
        if (remaining > 0.001) {
          billItems.add(OrderItem.fromMap(itemData).copyWith(quantity: remaining));
        }
      }
    }

    if (billItems.isEmpty) {
      ToastService().show(message: "Hóa đơn này đã trả hết hàng.", type: ToastType.warning);
      return;
    }

    CustomerModel? customer;
    if (freshBill.customerId != null) {
      try {
        final doc = await FirebaseFirestore.instance.collection('customers').doc(freshBill.customerId).get();
        if (doc.exists) customer = CustomerModel.fromFirestore(doc);
      } catch (_) {}
    }

    if (!mounted) return;

    // Chuyển trang và chờ kết quả trả về để refresh lại list bên ngoài (nếu cần)
    final bool? result = await Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("Xử lý Đổi/Trả: ${freshBill!.billCode}")),
          body: ExchangeProcessorWidget(
            currentUser: widget.currentUser,
            returnService: widget.returnService,
            initialReturnItems: billItems,
            originalBill: freshBill, // Truyền bill mới nhất vào
            customer: customer,
          ),
        )
    ));

    // Nếu xử lý xong (result == true), tự động tìm kiếm lại để cập nhật danh sách bên ngoài
    if (result == true) {
      _searchBills();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.calendar_today, color: AppTheme.primaryColor),
                onPressed: _pickDate,
              ),
              Text(DateFormat('dd/MM/yyyy').format(_selectedDate), style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                      hintText: 'Tìm hóa đơn...',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _searchBills)
                  ),
                  onSubmitted: (_) => _searchBills(),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
            itemCount: _foundBills.length,
            itemBuilder: (context, index) {
              final bill = _foundBills[index];
              return ListTile(
                title: Text('${bill.billCode} - ${bill.customerName}'),
                subtitle: Text(DateFormat('HH:mm').format(bill.createdAt)),
                trailing: Text(formatNumber(bill.totalPayable)),
                onTap: () => _onSelectBill(bill),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DirectReturnTab extends StatefulWidget {
  final UserModel currentUser;
  final ReturnService returnService;

  const _DirectReturnTab({required this.currentUser, required this.returnService});

  @override
  State<_DirectReturnTab> createState() => _DirectReturnTabState();
}

class _DirectReturnTabState extends State<_DirectReturnTab> {

  void _startDirectReturn() async {
    // 1. Chọn sản phẩm để trả trước
    final List<ProductModel>? selectedProducts = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      groupByCategory: true,
    );

    if (selectedProducts == null || selectedProducts.isEmpty) return;

    final List<OrderItem> returnItems = selectedProducts.map((p) => OrderItem(
      product: p,
      quantity: 1,
      price: p.sellPrice,
      selectedUnit: p.unit ?? '',
      addedAt: Timestamp.now(),
      addedBy: widget.currentUser.name ?? '',
      discountValue: 0,
      commissionStaff: {},
    )).toList();

    if (!mounted) return;

    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("Xử lý Đổi/Trả Trực Tiếp")),
          body: ExchangeProcessorWidget(
            currentUser: widget.currentUser,
            returnService: widget.returnService,
            initialReturnItems: returnItems,
            originalBill: null,
            customer: null, // Sẽ cần chọn khách hàng sau hoặc để khách lẻ
          ),
        )
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.assignment_return_outlined, size: 80, color: Colors.grey),
          const SizedBox(height: 20),
          const Text("Đổi trả không cần hóa đơn gốc", style: TextStyle(fontSize: 16, color: Colors.grey)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.add),
            label: const Text("Bắt đầu Đổi / Trả"),
            onPressed: _startDirectReturn,
          )
        ],
      ),
    );
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final ProductModel product;
  final List<ProductModel> allProducts;
  final double initialPrice;
  final String? initialUnit;
  final Map<ProductModel, double>? initialToppings;
  final String? initialNote;

  const _ProductOptionsDialog({
    required this.product,
    required this.allProducts,
    required this.initialPrice,
    this.initialUnit,
    this.initialToppings,
    this.initialNote,
  });

  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late String _selectedUnit;
  late TextEditingController _priceCtrl;
  late TextEditingController _noteCtrl;
  final Map<String, double> _selectedToppings = {};
  List<ProductModel> _accompanyingProducts = [];
  late List<Map<String, dynamic>> _unitOptions;

  @override
  void initState() {
    super.initState();
    _unitOptions = [
      {'unitName': widget.product.unit ?? '', 'sellPrice': widget.product.sellPrice},
      ...widget.product.additionalUnits
    ];
    _selectedUnit = widget.initialUnit ?? (widget.product.unit ?? '');

    if (!_unitOptions.any((u) => u['unitName'] == _selectedUnit)) {
      if (_unitOptions.isNotEmpty) _selectedUnit = _unitOptions.first['unitName'];
    }

    _priceCtrl = TextEditingController(text: formatNumber(widget.initialPrice));
    _noteCtrl = TextEditingController(text: widget.initialNote ?? '');

    final productMap = {for (var p in widget.allProducts) p.id: p};
    _accompanyingProducts = widget.product.accompanyingItems
        .map((item) => productMap[item['productId']])
        .where((p) => p != null)
        .cast<ProductModel>()
        .toList();

    if (widget.initialToppings != null) {
      widget.initialToppings!.forEach((p, qty) {
        if (qty > 0) _selectedToppings[p.id] = qty;
      });
    }
  }

  void _onUnitChanged(String? newUnit) {
    if (newUnit == null) return;
    setState(() {
      _selectedUnit = newUnit;
      final unitData = _unitOptions.firstWhere((u) => u['unitName'] == newUnit, orElse: () => {});
      if (unitData.isNotEmpty) {
        double basePrice = (unitData['sellPrice'] as num).toDouble();
        double toppingTotal = _calculateToppingTotal();
        _priceCtrl.text = formatNumber(basePrice + toppingTotal);
      }
    });
  }

  double _calculateToppingTotal() {
    double total = 0;
    _selectedToppings.forEach((pId, qty) {
      final p = _accompanyingProducts.firstWhereOrNull((ap) => ap.id == pId);
      if (p != null) total += (p.sellPrice * qty);
    });
    return total;
  }

  void _updateTopping(String pId, double delta) {
    setState(() {
      final current = _selectedToppings[pId] ?? 0;
      final newVal = current + delta;
      if (newVal <= 0) {
        _selectedToppings.remove(pId);
      } else {
        _selectedToppings[pId] = newVal;
      }

      final unitData = _unitOptions.firstWhere((u) => u['unitName'] == _selectedUnit, orElse: () => _unitOptions.first);
      double basePrice = (unitData['sellPrice'] as num).toDouble();
      double toppingTotal = _calculateToppingTotal();
      _priceCtrl.text = formatNumber(basePrice + toppingTotal);
    });
  }

  void _onConfirm() {
    final Map<ProductModel, double> finalToppings = {};
    _selectedToppings.forEach((pId, qty) {
      final p = _accompanyingProducts.firstWhereOrNull((ap) => ap.id == pId);
      if (p != null) finalToppings[p] = qty;
    });

    // [FIX LỖI MẤT 000]: Dùng RegExp để chỉ giữ lại số, loại bỏ dấu chấm/phẩy format
    String cleanPrice = _priceCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    final double finalPrice = double.tryParse(cleanPrice) ?? 0;

    Navigator.of(context).pop({
      'selectedUnit': _selectedUnit,
      'selectedToppings': finalToppings,
      'price': finalPrice,
      'note': _noteCtrl.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product.productName, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_unitOptions.length > 1) ...[
                const Text("Đơn vị tính:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _unitOptions.map((u) {
                    final String uName = u['unitName'];
                    final bool isSelected = uName == _selectedUnit;
                    return ChoiceChip(
                      label: Text(uName),
                      selected: isSelected,
                      onSelected: (val) => _onUnitChanged(val ? uName : null),
                      selectedColor: AppTheme.primaryColor.withValues(alpha: 0.2),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],

              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                // Thêm formatter số
                inputFormatters: [ThousandDecimalInputFormatter()],
                decoration: const InputDecoration(labelText: "Đơn giá (đã gồm topping)", border: OutlineInputBorder(), suffixText: "đ"),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _noteCtrl,
                decoration: const InputDecoration(labelText: "Ghi chú sản phẩm", border: OutlineInputBorder(), prefixIcon: Icon(Icons.note_alt_outlined)),
              ),
              const SizedBox(height: 16),

              if (_accompanyingProducts.isNotEmpty) ...[
                const Text("Topping / Bán kèm:", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._accompanyingProducts.map((p) {
                  final qty = _selectedToppings[p.id] ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text("${p.productName} (+${formatNumber(p.sellPrice)})")),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                              onPressed: () => _updateTopping(p.id, -1),
                            ),
                            Text(formatNumber(qty), style: const TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppTheme.primaryColor),
                              onPressed: () => _updateTopping(p.id, 1),
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                }),
              ]
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
        ElevatedButton(onPressed: _onConfirm, child: const Text("Xác nhận")),
      ],
    );
  }
}

class ExchangeItemCard extends StatefulWidget {
  final OrderItem item;
  final int index;
  final Function(OrderItem) onUpdate;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final String taxDisplay;

  const ExchangeItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onUpdate,
    required this.onRemove,
    required this.onTap,
    this.taxDisplay = '',
  });

  @override
  State<ExchangeItemCard> createState() => _ExchangeItemCardState();
}

class _ExchangeItemCardState extends State<ExchangeItemCard> {
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: formatNumber(widget.item.quantity));
  }

  @override
  void didUpdateWidget(covariant ExchangeItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.quantity != oldWidget.item.quantity) {
      final String newText = formatNumber(widget.item.quantity);
      if (_qtyController.text != newText) {
        _qtyController.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final double lineTotal = item.price * item.quantity;

    final List<String> availableUnits = [];
    if (item.product.unit != null && item.product.unit!.isNotEmpty) {
      availableUnits.add(item.product.unit!);
    }
    for (var u in item.product.additionalUnits) {
      if (u['unitName'] != null) availableUnits.add(u['unitName']);
    }
    if (availableUnits.isEmpty) availableUnits.add('Cái');
    final uniqueUnits = availableUnits.toSet().toList();

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: item.product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      if (widget.taxDisplay.isNotEmpty)
                        TextSpan(text: ' ${widget.taxDisplay}', style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.normal))
                    ])),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                    onPressed: widget.onRemove,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  )
                ],
              ),
              if (item.toppings.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: item.toppings.entries.map((e) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                      child: Text("+${e.key.productName} (x${formatNumber(e.value)})", style: TextStyle(fontSize: 11, color: Colors.orange.shade900)),
                    )).toList(),
                  ),
                ),
              if (item.note != null && item.note!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text("Ghi chú: ${item.note}", style: const TextStyle(fontSize: 12, color: Colors.blue, fontStyle: FontStyle.italic)),
                ),

              const SizedBox(height: 8),

              Row(
                children: [
                  SizedBox(
                    width: 120,
                    height: 35,
                    child: AppDropdown<String>(
                      labelText: 'ĐVT',
                      value: uniqueUnits.contains(item.selectedUnit) ? item.selectedUnit : uniqueUnits.first,
                      items: uniqueUnits.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))).toList(),
                      isDense: true,
                      onChanged: (val) {
                        if (val != null) {
                          double newBasePrice = item.product.sellPrice;
                          if (val != item.product.unit) {
                            final u = item.product.additionalUnits.firstWhereOrNull((element) => element['unitName'] == val);
                            if (u != null) newBasePrice = (u['sellPrice'] as num).toDouble();
                          }
                          widget.onUpdate(item.copyWith(selectedUnit: val, price: newBasePrice, toppings: {}));
                        }
                      },
                    ),
                  ),

                  const SizedBox(width: 8),

                  Container(
                    width: 100,
                    height: 35,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        InkWell(
                          onTap: () => item.quantity > 1 ? widget.onUpdate(item.copyWith(quantity: item.quantity - 1)) : null,
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.remove, size: 14, color: Colors.black)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _qtyController,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                            onChanged: (val) {
                              final q = double.tryParse(val);
                              if (q != null && q > 0) widget.onUpdate(item.copyWith(quantity: q));
                            },
                          ),
                        ),
                        InkWell(
                          onTap: () => widget.onUpdate(item.copyWith(quantity: item.quantity + 1)),
                          child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.add, size: 14, color: AppTheme.primaryColor)),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text("${formatNumber(item.price)} đ", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      Text("${formatNumber(lineTotal)} đ", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}