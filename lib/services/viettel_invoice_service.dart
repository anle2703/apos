import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class ViettelConfig {
  final String username;
  final String password;
  final String templateCode;
  final String invoiceSeries;
  final bool autoIssueOnPayment;

  ViettelConfig({
    required this.username,
    required this.password,
    required this.templateCode,
    required this.invoiceSeries,
    this.autoIssueOnPayment = false,
  });
}

class ViettelEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  // SỬA: ĐƯỜNG DẪN ĐÚNG CỦA CẤU HÌNH THUẾ
  static const String _taxSettingsCollection = 'store_tax_settings';

  final _dio = Dio();
  final _uuid = const Uuid();
  static const String _viettelBaseUrl = 'https://api-vinvoice.viettel.vn';

  Future<void> saveViettelConfig(ViettelConfig config, String storeId) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));
      final dataToSave = {
        'provider': 'viettel',
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'updatedAt': FieldValue.serverTimestamp(), // Thêm trường này nếu muốn theo dõi thời gian sửa
      };

      await _db.collection(_configCollection).doc(storeId).set(dataToSave);

      await _db.collection(_mainConfigCollection).doc(storeId).set({
        'activeProvider': 'viettel',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình Viettel: $e");
      throw Exception('Không thể lưu cấu hình Viettel.');
    }
  }

  Future<ViettelConfig?> getViettelConfig(String storeId) async {
    try {
      // Đọc từ storeId
      final doc = await _db.collection(_configCollection).doc(storeId).get();

      // 1. Nếu chưa có dữ liệu -> Trả về null (để UI hiện form nhập mới)
      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;

      // 2. Parse dữ liệu an toàn (Dùng ?? '' để chống lỗi null)
      return ViettelConfig(
        username: data['username'] ?? '',
        // Kiểm tra kỹ password trước khi decode
        password: data['password'] != null ? utf8.decode(base64Decode(data['password'])) : '',
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
      );
    } catch (e) {
      // 3. Nếu lỗi hệ thống (Mạng, sai base64...) -> Báo lỗi đỏ để biết đường sửa
      debugPrint("Lỗi SYSTEM lấy config Viettel: $e");
      throw Exception('Lỗi hệ thống khi tải Viettel: $e');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String storeId) async {
    final config = await getViettelConfig(storeId);

    if (config == null || config.username.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }
    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToViettel(String username, String password) async {
    try {
      final response = await _dio.post(
        '$_viettelBaseUrl/auth/login',
        data: {'username': username, 'password': password},
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['access_token'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Lỗi ${e.response?.statusCode}: ${e.response?.data?['data'] ?? e.response?.data?['message'] ?? 'Sai thông tin'}');
      } else {
        throw Exception('Lỗi mạng. Vui lòng kiểm tra lại.');
      }
    }
  }

  Future<String?> _getValidToken(String storeId) async {
    final config = await getViettelConfig(storeId);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình Viettel HĐĐT.');
    }
    return await loginToViettel(config.username, config.password);
  }

  /// --- LOGIC MỚI: XÁC ĐỊNH LOẠI HÓA ĐƠN ---
  Future<String> _determineInvoiceTypeFromSettings(String storeId) async {
    try {
      // SỬA: Đọc đúng collection 'store_tax_settings'
      final docSnapshot = await _db.collection(_taxSettingsCollection).doc(storeId).get();

      if (!docSnapshot.exists) {
        debugPrint(">>> Viettel Service: Không tìm thấy cấu hình thuế cho store $storeId. Mặc định là 2.");
        return "2";
      }

      final data = docSnapshot.data() as Map<String, dynamic>;

      // Ưu tiên check calcMethod (Phương pháp tính thuế)
      final String calcMethod = data['calcMethod'] ?? 'direct';
      if (calcMethod == 'deduction') {
        return "1"; // Khấu trừ -> HĐ GTGT
      }

      final String entityType = data['entityType'] ?? 'hkd';
      final String revenueRange = data['revenueRange'] ?? 'medium';

      // Doanh nghiệp -> HĐ GTGT
      if (entityType == 'dn') {
        return "1";
      }

      // Hộ kinh doanh
      if (entityType == 'hkd') {
        // Doanh thu cao -> HĐ GTGT
        if (revenueRange == 'high') {
          return "1";
        }
        return "2"; // Còn lại -> HĐ Bán hàng
      }

      return "2";
    } catch (e) {
      debugPrint("Lỗi lấy cấu hình thuế: $e");
      return "2";
    }
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String storeId) async {
    try {
      final token = await _getValidToken(storeId);
      if (token == null) {
        throw Exception('Không thể lấy token xác thực HĐĐT.');
      }

      final config = (await getViettelConfig(storeId))!;
      final fullUsernameForUrl = config.username;
      final mst = config.username;

      // Bước này giờ sẽ trả về "1" vì cấu hình của bạn là "high" / "deduction"
      final String determinedInvoiceType = await _determineInvoiceTypeFromSettings(storeId);
      debugPrint(">>> Viettel Service: Đã xác định loại hóa đơn: $determinedInvoiceType (1=VAT, 2=Bán hàng)");

      final payload = _buildViettelPayload(billData, customer, config, determinedInvoiceType);

      final String apiUrl =
          "$_viettelBaseUrl/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/createInvoice/$fullUsernameForUrl";

      final response = await _dio.post(
        apiUrl,
        data: payload,
        options: Options(
          headers: {
            'Cookie': 'access_token=$token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        if (response.data['errorCode'] != null) {
          throw Exception("${response.data['errorCode']} - ${response.data['description']}");
        }

        final resultData = response.data['result'] as Map<String, dynamic>?;

        if (resultData == null) {
          throw Exception("Viettel không trả về kết quả (Result null). Raw: ${response.data}");
        }

        final reservationCode = resultData['reservationCode'] as String? ?? '';
        final invoiceNo = resultData['invoiceNo'] as String? ?? '';

        final String lookupUrl =
            'https://vinvoice.viettel.vn/utilities/invoice-search?taxCode=$mst&reservationCode=$reservationCode';

        return EInvoiceResult(
          providerName: 'Viettel',
          invoiceNo: invoiceNo,
          reservationCode: reservationCode,
          lookupUrl: lookupUrl,
          mst: mst,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['description'] ??
            response.data['message'] ??
            'Lỗi không xác định từ Viettel');
      }
    } on DioException catch (e) {
      String detailedError = 'Lỗi kết nối Viettel';
      if (e.response != null && e.response!.data != null) {
        final data = e.response!.data;
        if (data is Map) {
          final code = data['errorCode'] ?? data['code'];
          final desc = data['description'] ?? data['message'] ?? data['data'];
          if (desc != null) {
            detailedError = "$code: $desc";
          } else {
            detailedError = data.toString();
          }
        } else {
          detailedError = data.toString();
        }
      } else {
        detailedError = e.message ?? 'Lỗi mạng không xác định';
      }
      throw Exception('Viettel từ chối: $detailedError');
    } catch (e) {
      throw Exception('Lỗi cục bộ: ${e.toString()}');
    }
  }

  @override
  Future<void> sendEmail(String storeId, Map<String, dynamic> rawResponse) async {
    final String? transactionUuid = rawResponse['transactionID'] as String?;
    if (transactionUuid == null) return;

    final token = await _getValidToken(storeId);
    final config = (await getViettelConfig(storeId))!;

    try {
      final String apiUrl = "$_viettelBaseUrl/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/sendHtmlMailProcess";

      await _dio.post(
        apiUrl,
        data: {
          'supplierTaxCode': config.username,
          'lstTransactionUuid': transactionUuid,
        },
        options: Options(
          headers: {
            'Cookie': 'access_token=$token',
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      debugPrint("Lỗi API Viettel (gửi email): $e");
    }
  }

  /// --- HÀM BUILD PAYLOAD (ĐÃ SỬA: TÍNH LẠI ĐƠN GIÁ ĐỂ KHỚP VALIDATE) ---
  Map<String, dynamic> _buildViettelPayload(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      ViettelConfig config,
      String invoiceType) {

    // 1. CHUẨN BỊ DỮ LIỆU
    final List<dynamic> billItems = billData['items'] ?? [];
    final double billDiscount = (billData['discount'] as num?)?.toDouble() ?? 0.0;

    // Tính tổng tiền hàng trước khi giảm (để làm mẫu số phân bổ)
    double totalGoodsValue = 0.0;
    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;

      final double itemSpecificDiscount = (item['discountValue'] as num?)?.toDouble() ?? 0.0;
      double itemLineTotal;

      if (item['discountUnit'] == '%') {
        itemLineTotal = (unitPrice * quantity) * (1 - itemSpecificDiscount / 100);
      } else {
        itemLineTotal = (unitPrice * quantity) - itemSpecificDiscount;
      }
      totalGoodsValue += itemLineTotal;
    }

    // 2. XỬ LÝ DANH SÁCH HÀNG HÓA (ITEM INFO)
    final List<Map<String, dynamic>> itemInfo = [];
    final Map<double, double> taxableMap = {};
    final Map<double, double> taxAmountMap = {};

    double totalTaxAmount = 0;

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      // a. Lấy thông tin
      final productMap = item['product'] as Map<String, dynamic>?;
      final String itemName = item['productName'] ?? productMap?['productName'] ?? 'Sản phẩm';
      final String unitName = item['unitName'] ?? item['selectedUnit'] ?? productMap?['unitName'] ?? 'cái';
      final double quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final double originalUnitPrice = (item['price'] as num?)?.toDouble() ?? 0.0; // Giá gốc

      // b. Tính toán giảm giá (như cũ)
      final double rawItemTotal = originalUnitPrice * quantity;
      double itemSpecificDiscountAmount = 0;
      final double specificDiscountVal = (item['discountValue'] as num?)?.toDouble() ?? 0.0;

      if (specificDiscountVal > 0) {
        if (item['discountUnit'] == '%') {
          itemSpecificDiscountAmount = rawItemTotal * (specificDiscountVal / 100);
        } else {
          itemSpecificDiscountAmount = specificDiscountVal;
        }
      }

      double itemSubtotalAfterSpecific = rawItemTotal - itemSpecificDiscountAmount;

      double allocatedBillDiscount = 0;
      if (totalGoodsValue > 0 && billDiscount > 0) {
        allocatedBillDiscount = (itemSubtotalAfterSpecific / totalGoodsValue) * billDiscount;
      }

      double totalItemDiscount = itemSpecificDiscountAmount + allocatedBillDiscount;
      double itemNetValue = rawItemTotal - totalItemDiscount; // Giá trị thực thu
      itemNetValue = itemNetValue.roundToDouble();

      // --- CỐT LÕI CỦA VIỆC SỬA LỖI 400 ---
      // Tính lại Đơn giá mới (Effective Unit Price) để: Đơn giá mới * SL = Giá trị thực thu
      // Nếu không làm bước này, Viettel sẽ báo lỗi vì (Giá cũ * SL) != Giá trị thực thu
      double effectiveUnitPrice = itemNetValue;
      if (quantity > 0) {
        effectiveUnitPrice = itemNetValue / quantity;
      }
      // -------------------------------------

      // c. Logic Thuế (Giữ nguyên logic ép kiểu trước đó)
      double itemTaxPercent = -2;
      double itemTaxAmount = 0;

      if (invoiceType == "1") {
        final double rawRate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
        final double percent = rawRate * 100;

        if ((percent - 10).abs() < 0.1) {itemTaxPercent = 10;}
        else if ((percent - 8).abs() < 0.1) {itemTaxPercent = 8;}
        else if ((percent - 5).abs() < 0.1) {itemTaxPercent = 5;}
        else if ((percent - 0).abs() < 0.1) {
          itemTaxPercent = 0;
        }else {itemTaxPercent = 0;}

        itemTaxAmount = (itemNetValue * itemTaxPercent / 100).roundToDouble();

        taxableMap[itemTaxPercent] = (taxableMap[itemTaxPercent] ?? 0) + itemNetValue;
        taxAmountMap[itemTaxPercent] = (taxAmountMap[itemTaxPercent] ?? 0) + itemTaxAmount;

        totalTaxAmount += itemTaxAmount;
      } else {
        itemTaxPercent = -2;
        itemTaxAmount = 0;
        taxableMap[-2.0] = (taxableMap[-2.0] ?? 0) + itemNetValue;
        taxAmountMap[-2.0] = 0;
      }

      itemInfo.add({
        "selection": 1,
        "itemName": itemName,
        "unitName": unitName,
        "quantity": quantity,
        "unitPrice": effectiveUnitPrice, // <--- SỬA: Gửi đơn giá đã trừ chiết khấu
        "itemTotalAmountWithoutTax": itemNetValue,
        "taxPercentage": itemTaxPercent,
        "taxAmount": itemTaxAmount,
        "discount": 0.0,
        "itemDiscount": 0.0 // Đã trừ vào đơn giá nên discount gửi là 0
      });
    }

    // 3. TẠO TAX BREAKDOWNS
    final List<Map<String, dynamic>> taxBreakdowns = [];
    taxableMap.forEach((percent, taxable) {
      taxBreakdowns.add({
        "taxPercentage": percent,
        "taxableAmount": taxable,
        "taxAmount": taxAmountMap[percent] ?? 0,
      });
    });

    // 4. TỔNG HỢP
    // SỬA: Dùng biến 'prev' thay vì 'sum'
    final double totalAmountWithoutTax = taxableMap.values.fold(0.0, (prev, val) => prev + val);
    final double totalAmountWithTax = totalAmountWithoutTax + totalTaxAmount;

    final summarizeInfo = {
      "totalAmountWithoutTax": totalAmountWithoutTax,
      "totalTaxAmount": totalTaxAmount,
      "totalAmountWithTax": totalAmountWithTax,
      "discountAmount": billDiscount + (billData['totalItemDiscount'] ?? 0),
    };

    // 5. THANH TOÁN
    final Map<String, dynamic> billPayments = billData['payments'] ?? {};
    final List<Map<String, dynamic>> payments = [];
    billPayments.forEach((key, value) {
      payments.add({"paymentMethodName": key});
    });
    if (payments.isEmpty) payments.add({"paymentMethodName": "Tiền mặt"});

    return {
      "generalInvoiceInfo": {
        "invoiceType": invoiceType,
        "templateCode": config.templateCode,
        "invoiceSeries": config.invoiceSeries,
        "currencyCode": "VND",
        "adjustmentType": "1",
        "paymentStatus": true,
        "cusGetInvoiceRight": true,
        "transactionUuid": _uuid.v4(),
      },
      "buyerInfo": {
        "buyerName": customer?.name ?? billData['customerName'] ?? "Khách lẻ",
        "buyerLegalName": customer?.companyName ?? customer?.name ?? "Khách lẻ",
        "buyerTaxCode": customer?.taxId,
        "buyerAddressLine": customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "buyerPhoneNumber": customer?.phone ?? billData['customerPhone'],
        "buyerEmail": customer?.email,
        "buyerNotGetInvoice": "0",
      },
      "payments": payments,
      "itemInfo": itemInfo,
      "taxBreakdowns": taxBreakdowns,
      "summarizeInfo": summarizeInfo,
    };
  }
}