import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/order_item_model.dart';
import '../models/receipt_template_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReceiptWidget extends StatelessWidget {
  final String title;
  final Map<String, String> storeInfo;
  final List<OrderItem> items;
  final Map<String, dynamic> summary;
  final String userName;
  final String tableName;
  final bool showPrices;
  final bool isSimplifiedMode;
  final ReceiptTemplateModel? templateSettings;
  final String? qrData;
  final bool isRetailMode;
  final bool isReturnBill;

  final List<OrderItem>? exchangeItems;
  final Map<String, dynamic>? exchangeSummary;

  const ReceiptWidget({
    super.key,
    required this.title,
    required this.storeInfo,
    required this.items,
    required this.summary,
    required this.userName,
    required this.tableName,
    this.showPrices = false,
    this.isSimplifiedMode = false,
    this.templateSettings,
    this.qrData,
    this.isRetailMode = false,
    this.isReturnBill = false,
    this.exchangeItems,
    this.exchangeSummary,
  });

  @override
  Widget build(BuildContext context) {
    final settings = templateSettings ?? ReceiptTemplateModel();
    const double fontScale = 1.8;

    final bool isCheckDish = !showPrices;
    final bool isFinancialBill = showPrices;
    final bool hasExchange = exchangeItems != null && exchangeItems!.isNotEmpty;

    final String? billCode = summary['billCode'] as String?;
    String displayTitle = title;

    if (isReturnBill) {
      displayTitle = 'ĐỔI TRẢ - ${billCode ?? ""}';
    } else if (isFinancialBill) {
      if (displayTitle.toLowerCase().contains('kiểm món') || displayTitle.isEmpty) {
        displayTitle = 'TẠM TÍNH';
      }
    }

    final baseTextStyle = TextStyle(color: Colors.black, fontFamily: 'Roboto', height: 1.1);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w900);
    final italicTextStyle = baseTextStyle.copyWith(fontStyle: FontStyle.italic);
    final strikeThroughStyle = baseTextStyle.copyWith(decoration: TextDecoration.lineThrough, decorationThickness: 2);

    final double fsHeader = settings.billHeaderSize * fontScale;
    final double fsAddress = settings.billAddressSize * fontScale;
    final double fsPhone = settings.billPhoneSize * fontScale;
    final double fsTitle = settings.billTitleSize * fontScale;
    final double fsInfo = settings.billTextSize * fontScale;
    final double fsItemName = settings.billItemNameSize * fontScale;
    final double fsItemDetail = settings.billItemDetailSize * fontScale;
    final double fsTotal = settings.billTotalSize * fontScale;

    final currencyFormat = NumberFormat('#,##0', 'vi_VN');
    final quantityFormat = NumberFormat('#,##0.##', 'vi_VN');
    final timeFormat = DateFormat('HH:mm dd/MM/yyyy');
    final percentFormat = NumberFormat('#,##0.##', 'vi_VN');
    final shortDateTimeFormat = DateFormat('HH:mm dd/MM');

    final double returnSubtotal = (summary['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double returnTotalPayable = (summary['totalPayable'] as num?)?.toDouble() ?? 0.0;
    final double returnTax = (summary['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double discount = (summary['discount'] as num?)?.toDouble() ?? 0.0;
    final double voucherDiscount = (summary['voucherDiscount'] as num?)?.toDouble() ?? 0.0;
    final double pointsValue = ((summary['customerPointsUsed'] as num?)?.toDouble() ?? 0.0) * 1000.0;
    final String? voucherCode = summary['voucherCode'] as String?;
    final List surcharges = (summary['surcharges'] is List) ? summary['surcharges'] : const [];
    Map<double, double> taxBreakdown = {};
    final bool isTaxInclusive = summary['isTaxInclusive'] == true;
    if (summary['items'] is List) {
      for (var item in summary['items']) {
        if (item is Map) {
          double rate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
          double tAmount = (item['taxAmount'] as num?)?.toDouble() ?? 0.0;
          if (tAmount == 0 && rate > 0) {
            double sub = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
            if (isTaxInclusive) {
              tAmount = sub - (sub / (1 + rate));
            } else {
              tAmount = sub * rate;
            }
          }
          if (rate > 0 && tAmount > 0) {
            taxBreakdown[rate] = (taxBreakdown[rate] ?? 0) + tAmount;
          }
        }
      }
    }
    final sortedTaxRates = taxBreakdown.keys.toList()..sort();
    final double exchangeTotalPayable = (exchangeSummary?['totalPayable'] as num?)?.toDouble() ?? 0.0;
    final double netDifference = exchangeTotalPayable - returnTotalPayable;
    final double changeAmount = (summary['changeAmount'] as num?)?.toDouble() ?? 0.0;

    final bool isProvisional = title.toUpperCase().contains('TẠM TÍNH') || title.toUpperCase().contains('KIỂM MÓN');

    double debtAmount = 0.0;
    if (summary.containsKey('debtAmount')) {
      debtAmount = (summary['debtAmount'] as num).toDouble();
    } else if (!isReturnBill) {
      final Map<String, dynamic> payments = (summary['payments'] is Map) ? Map<String, dynamic>.from(summary['payments']) : {};
      final double totalPaidFromDB = payments.values.fold(0.0, (a, b) => a + (b as num).toDouble());
      debtAmount = returnTotalPayable - totalPaidFromDB;
    }

    final dynamic rawStart = summary['startTime'] ?? summary['startTimeIso'];
    DateTime? startTime;
    if (rawStart is Timestamp) {
      startTime = rawStart.toDate();
    } else if (rawStart is String && rawStart.isNotEmpty) {
      try {
        startTime = DateTime.parse(rawStart);
      } catch (_) {}
    }

    final Map<String, dynamic> customer = (summary['customer'] is Map) ? Map<String, dynamic>.from(summary['customer']) : {};
    final String khName = customer['name'] ?? 'Khách lẻ';
    final String khPhone = customer['phone'] ?? '';
    final String khAddress = customer['guestAddress'] ?? '';
    final String? eInvoiceUrl = summary['eInvoiceFullUrl'] as String?;
    final String? eInvoiceCode = summary['eInvoiceCode'] as String?;
    final String? eInvoiceMst = summary['eInvoiceMst'] as String?;
    final bool isShipOrder = tableName.toLowerCase().contains('giao hàng') ||
        tableName.toLowerCase().contains('ship') ||
        (isRetailMode && tableName.isEmpty);
    final String? originalBillCode = summary['originalBillCode'] as String?;

    String finalTitleStr = displayTitle;
    if (!isReturnBill && tableName.isNotEmpty) {
      finalTitleStr = '$displayTitle - $tableName';
    }

    return Container(
      width: 550,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings.billShowStoreName && (storeInfo['name'] ?? '').isNotEmpty)
            Text(storeInfo['name']!.toUpperCase(),
                textAlign: TextAlign.center, style: boldTextStyle.copyWith(fontSize: fsHeader)),
          if (settings.billShowStoreAddress && (storeInfo['address'] ?? '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child:
                    Text(storeInfo['address']!, textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsAddress))),
          if (settings.billShowStorePhone && (storeInfo['phone'] ?? '').isNotEmpty)
            Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('ĐT: ${storeInfo['phone']}',
                    textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsPhone))),

          const SizedBox(height: 16),

          Text(finalTitleStr, textAlign: TextAlign.center, style: boldTextStyle.copyWith(fontSize: fsTitle)),

          if (billCode != null && billCode.isNotEmpty && !isReturnBill && !hasExchange)
            Text(billCode, textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsInfo)),

          if (originalBillCode != null && originalBillCode.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text('Hóa đơn gốc: $originalBillCode',
                  textAlign: TextAlign.center, style: italicTextStyle.copyWith(fontSize: fsInfo)),
            ),

          const SizedBox(height: 12),

          if (settings.billShowCustomerName) ...[
            _buildInfoRow('Khách hàng:', khName, baseTextStyle.copyWith(fontSize: fsInfo)),
            if (isShipOrder) ...[
              if (khPhone.isNotEmpty) _buildInfoRow('SĐT:', khPhone, baseTextStyle.copyWith(fontSize: fsInfo)),
              if (khAddress.isNotEmpty) _buildInfoRow('ĐC:', khAddress, baseTextStyle.copyWith(fontSize: fsInfo)),
            ]
          ],
          if (startTime != null && !isRetailMode && !isReturnBill)
            _buildInfoRow('Giờ vào:', timeFormat.format(startTime), baseTextStyle.copyWith(fontSize: fsInfo)),
          _buildInfoRow('Giờ in:', timeFormat.format(DateTime.now()), baseTextStyle.copyWith(fontSize: fsInfo)),
          if (settings.billShowCashierName) _buildInfoRow('Thu ngân:', userName, baseTextStyle.copyWith(fontSize: fsInfo)),

          const SizedBox(height: 16),

          _buildTableHeader(
              isReturnSection: isReturnBill || hasExchange,
              customProductName: (isReturnBill || hasExchange) ? "Sản phẩm hoàn" : "Tên sản phẩm",
              fontSize: fsItemName,
              boldStyle: boldTextStyle),

          ...items.asMap().entries.map((entry) {
            return _buildSingleItemRow(
              entry.key,
              entry.value,
              items.length,
              isCheckDish: isCheckDish,
              isFinancialBill: isFinancialBill,
              isTimeBased: entry.value.product.serviceSetup?['isTimeBased'] == true,
              fsItemName: fsItemName,
              fsItemDetail: fsItemDetail,
              baseTextStyle: baseTextStyle,
              boldTextStyle: boldTextStyle,
              italicTextStyle: italicTextStyle,
              strikeThroughStyle: strikeThroughStyle,
              currencyFormat: currencyFormat,
              quantityFormat: quantityFormat,
              timeFormat: timeFormat,
              shortDateTimeFormat: shortDateTimeFormat,
              percentFormat: percentFormat,
              taxSettingsList: (summary['items'] is List) ? summary['items'] : [],
            );
          }),

          // CHI TIẾT GIÁ TRỊ TRẢ (ĐÃ SỬA: LÀM TỔNG CHÍNH LUÔN NẾU CÓ ĐỔI HÀNG)
          if (hasExchange && isFinancialBill) ...[
            const SizedBox(height: 8),
            if (settings.billShowTax && returnTax > 0)
              _buildRow('Hoàn thuế:', '+ ${currencyFormat.format(returnTax)}', baseTextStyle.copyWith(fontSize: fsInfo)),
            if (settings.billShowDiscount && discount > 0)
              _buildRow('Hoàn chiết khấu:', '- ${currencyFormat.format(discount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
            if (voucherDiscount > 0)
              _buildRow('Hoàn voucher:', '- ${currencyFormat.format(voucherDiscount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
            if (pointsValue > 0)
              _buildRow('Hoàn điểm thưởng:', '- ${currencyFormat.format(pointsValue)}', baseTextStyle.copyWith(fontSize: fsInfo)),
            if (settings.billShowSurcharge && surcharges.isNotEmpty)
              ...surcharges.map((s) => _buildRow('Hoàn phụ thu ${s['name']}:',
                  '+ ${currencyFormat.format((s['amount'] as num).toDouble())}', baseTextStyle.copyWith(fontSize: fsInfo))),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text("Giá trị hoàn: ", style: baseTextStyle.copyWith(fontSize: fsInfo)),
                Text(currencyFormat.format(returnTotalPayable),
                    style: boldTextStyle.copyWith(fontSize: fsInfo, color: Colors.red)),
              ],
            ),
          ],

          // PHẦN 2: HÀNG ĐỔI
          if (hasExchange) ...[
            const SizedBox(height: 24),
            _buildTableHeader(
                isReturnSection: false, customProductName: "Sản phẩm đổi", fontSize: fsItemName, boldStyle: boldTextStyle),

            ...exchangeItems!.asMap().entries.map((entry) {
              return _buildSingleItemRow(
                entry.key,
                entry.value,
                exchangeItems!.length,
                isCheckDish: isCheckDish,
                isFinancialBill: isFinancialBill,
                isTimeBased: entry.value.product.serviceSetup?['isTimeBased'] == true,
                fsItemName: fsItemName,
                fsItemDetail: fsItemDetail,
                baseTextStyle: baseTextStyle,
                boldTextStyle: boldTextStyle,
                italicTextStyle: italicTextStyle,
                strikeThroughStyle: strikeThroughStyle,
                currencyFormat: currencyFormat,
                quantityFormat: quantityFormat,
                timeFormat: timeFormat,
                shortDateTimeFormat: shortDateTimeFormat,
                percentFormat: percentFormat,
                taxSettingsList: (exchangeSummary?['items'] is List) ? exchangeSummary!['items'] : [],
              );
            }),

            // [SỬA] HIỂN THỊ THUẾ HÀNG ĐỔI VÀ TỔNG MUA
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (exchangeSummary != null && exchangeSummary!['taxAmount'] != null)
                    Builder(builder: (context) {
                      double exTax = (exchangeSummary!['taxAmount'] as num).toDouble();
                      if (exTax > 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text("Thuế: ", style: baseTextStyle.copyWith(fontSize: fsInfo)),
                              Text(currencyFormat.format(exTax), style: baseTextStyle.copyWith(fontSize: fsInfo)),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    }),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text("Giá trị đổi: ", style: baseTextStyle.copyWith(fontSize: fsInfo)),
                      Text(currencyFormat.format(exchangeTotalPayable),
                          style: boldTextStyle.copyWith(fontSize: fsInfo, color: Colors.green)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // PHẦN 3: TỔNG KẾT
          if (isFinancialBill) ...[
            const SizedBox(height: 24),
            if (!hasExchange) ...[
              if (!isSimplifiedMode) ...[
                _buildRow(isReturnBill ? 'Tổng cộng hoàn:' : 'Tổng cộng:', currencyFormat.format(returnSubtotal),
                    baseTextStyle.copyWith(fontSize: fsInfo)),
                if (settings.billShowDiscount && discount > 0)
                  _buildRow(isReturnBill ? 'Hoàn chiết khấu:' : (summary['discountName'] ?? 'Chiết khấu:'),
                      '- ${currencyFormat.format(discount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
                if (voucherDiscount > 0)
                  _buildRow(isReturnBill ? 'Hoàn voucher:' : 'Voucher ($voucherCode):',
                      '- ${currencyFormat.format(voucherDiscount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
                if (pointsValue > 0)
                  _buildRow(isReturnBill ? 'Hoàn điểm thưởng:' : 'Điểm thưởng:', '- ${currencyFormat.format(pointsValue)}',
                      baseTextStyle.copyWith(fontSize: fsInfo)),
                if (settings.billShowSurcharge && surcharges.isNotEmpty)
                  ...surcharges.map((s) => _buildRow(isReturnBill ? 'Hoàn phụ thu ${s['name']}:' : '${s['name']}:',
                      '+ ${currencyFormat.format((s['amount'] as num).toDouble())}', baseTextStyle.copyWith(fontSize: fsInfo))),
                if (settings.billShowTax && returnTax > 0) ...[
                  _buildRow(isReturnBill ? 'Hoàn thuế:' : 'Thuế:', '+ ${currencyFormat.format(returnTax)}',
                      baseTextStyle.copyWith(fontSize: fsInfo)),
                  ...sortedTaxRates.map((rate) {
                    final amount = taxBreakdown[rate]!;
                    return Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: _buildRow(
                        '${percentFormat.format(rate * 100)}%:',
                        currencyFormat.format(amount),
                        baseTextStyle.copyWith(fontSize: fsInfo - 1),
                      ),
                    );
                  }),
                ],
              ],
              if (isSimplifiedMode)
                _buildRow(isReturnBill ? 'Tổng cộng hoàn:' : 'Tổng cộng:', currencyFormat.format(returnSubtotal),
                    baseTextStyle.copyWith(fontSize: fsInfo)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(isReturnBill ? 'TỔNG HOÀN TIỀN:' : 'THÀNH TIỀN:', style: boldTextStyle.copyWith(fontSize: fsTotal)),
                  Text(currencyFormat.format(returnTotalPayable), style: boldTextStyle.copyWith(fontSize: fsTotal + 4)),
                ],
              ),
            ] else ...[

              if (netDifference > 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('KHÁCH TRẢ THÊM:', style: boldTextStyle.copyWith(fontSize: fsTotal)),
                    Text(currencyFormat.format(netDifference), style: boldTextStyle.copyWith(fontSize: fsTotal + 4)),
                  ],
                )
              else if (netDifference < 0)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('HOÀN TIỀN KHÁCH:', style: boldTextStyle.copyWith(fontSize: fsTotal)),
                    Text(currencyFormat.format(netDifference.abs()), style: boldTextStyle.copyWith(fontSize: fsTotal + 4)),
                  ],
                )
              else
                Center(child: Text('KHÔNG CẦN THANH TOÁN', style: boldTextStyle.copyWith(fontSize: fsTotal))),
            ],
            if (!isSimplifiedMode) ...[
              if (settings.billShowPaymentMethod && summary['payments'] is Map && (summary['payments'] as Map).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text((isReturnBill && netDifference <= 0) ? 'Phương thức hoàn:' : 'Thanh toán qua:',
                    style: baseTextStyle.copyWith(fontSize: fsInfo)),
                ...(summary['payments'] as Map).entries.map((entry) => _buildRow('- ${entry.key}:',
                    currencyFormat.format((entry.value as num).toDouble()), baseTextStyle.copyWith(fontSize: fsInfo))),
                if (isReturnBill && debtAmount > 0)
                  _buildRow('- Trừ vào dư nợ:', currencyFormat.format(debtAmount), baseTextStyle.copyWith(fontSize: fsInfo)),
              ],
              if (changeAmount > 0)
                _buildRow('Tiền thừa:', currencyFormat.format(changeAmount), baseTextStyle.copyWith(fontSize: fsInfo)),
              if (debtAmount > 0 && !isProvisional && !isReturnBill)
                _buildRow('Dư nợ:', currencyFormat.format(debtAmount), baseTextStyle.copyWith(fontSize: fsInfo)),
            ],
          ],

          if (qrData != null && !isSimplifiedMode && isFinancialBill) ...[
            const SizedBox(height: 16),
            Center(child: Text('Quét mã chuyển khoản', style: baseTextStyle.copyWith(fontSize: fsInfo))),
            const SizedBox(height: 4),
            Center(
              child: SizedBox(
                  width: 140,
                  height: 140,
                  child: QrImageView(
                      data: qrData!,
                      version: QrVersions.auto,
                      size: 140.0,
                      backgroundColor: Colors.white,
                      gapless: false,
                      padding: EdgeInsets.zero)),
            ),
          ],
          if (eInvoiceUrl != null && eInvoiceUrl.isNotEmpty && isFinancialBill) ...[
            const SizedBox(height: 24),
            Center(child: Text('QUÉT MÃ TRA CỨU HĐĐT', style: boldTextStyle.copyWith(fontSize: fsInfo))),
            const SizedBox(height: 8),
            if (eInvoiceMst != null)
              Center(child: Text('MST bên bán: $eInvoiceMst', style: baseTextStyle.copyWith(fontSize: fsInfo))),
            if (eInvoiceCode != null)
              Center(child: Text('Mã tra cứu: $eInvoiceCode', style: baseTextStyle.copyWith(fontSize: fsInfo))),
            const SizedBox(height: 8),
            Center(
              child: SizedBox(
                  width: 140,
                  height: 140,
                  child: QrImageView(
                      data: eInvoiceUrl,
                      version: QrVersions.auto,
                      size: 140.0,
                      backgroundColor: Colors.white,
                      gapless: false,
                      padding: EdgeInsets.zero)),
            ),
          ],
          if (settings.billShowFooter && isFinancialBill) ...[
            const SizedBox(height: 24),
            if (settings.footerText1.isNotEmpty)
              Center(
                  child:
                      Text(settings.footerText1, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
            if (settings.footerText2.isNotEmpty)
              Center(
                  child:
                      Text(settings.footerText2, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
          ]
        ],
      ),
    );
  }

  Widget _buildTableHeader(
      {required bool isReturnSection,
      bool isCheckDish = false,
      required double fontSize,
      required TextStyle boldStyle,
      String? customProductName}) {
    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(width: 2, color: Colors.black), bottom: BorderSide(width: 2, color: Colors.black))),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text('STT', style: boldStyle.copyWith(fontSize: fontSize))),
          Expanded(
              flex: 6,
              child: Text(customProductName ?? (isReturnSection ? 'Sản phẩm hoàn' : 'Tên sản phẩm'),
                  style: boldStyle.copyWith(fontSize: fontSize), textAlign: TextAlign.center)),
          Expanded(
              flex: 4,
              child: Text(isReturnSection ? 'Hoàn tiền' : (isCheckDish ? 'SL' : 'Thành tiền'),
                  textAlign: TextAlign.right, style: boldStyle.copyWith(fontSize: fontSize))),
        ],
      ),
    );
  }

  Widget _buildSingleItemRow(int i, OrderItem item, int totalCount,
      {required bool isCheckDish,
      required bool isFinancialBill,
      required bool isTimeBased,
      required double fsItemName,
      required double fsItemDetail,
      required TextStyle baseTextStyle,
      required TextStyle boldTextStyle,
      required TextStyle italicTextStyle,
      required TextStyle strikeThroughStyle,
      required NumberFormat currencyFormat,
      required NumberFormat quantityFormat,
      required DateFormat timeFormat,
      required DateFormat shortDateTimeFormat,
      required NumberFormat percentFormat,
      required List<dynamic> taxSettingsList}) {
    final bool isLastItem = i == totalCount - 1;
    final String itemName = item.product.productName;
    final String unit = item.selectedUnit.isNotEmpty ? item.selectedUnit : '';

    // --- BƯỚC 1: LẤY GIÁ GỐC (CATALOG) ĐÚNG THEO ĐVT ---
    double originalCatalogPrice = item.product.sellPrice;
    if (item.selectedUnit.isNotEmpty && item.selectedUnit != item.product.unit) {
      final unitData = item.product.additionalUnits.firstWhere((u) => u['unitName'] == item.selectedUnit, orElse: () => {});
      if (unitData.isNotEmpty) {
        originalCatalogPrice = (unitData['sellPrice'] as num).toDouble();
      }
    }

    // --- BƯỚC 2: TÍNH GIÁ BÁN THỰC TẾ (HIỂN THỊ) ---
    final String? bCode = summary['billCode'] as String?;
    final bool isThBill = bCode != null && bCode.toUpperCase().trim().startsWith('TH');
    final bool isRealReturn = isThBill || isReturnBill || (summary['status'] == 'return');

    double displayUnitPrice = 0;
    double displayLineTotal = 0;

    if (isRealReturn) {
      displayLineTotal = item.price * item.quantity;
      displayUnitPrice = item.price;
    } else {
      displayUnitPrice = item.subtotal / (item.quantity > 0 ? item.quantity : 1);
      displayLineTotal = item.subtotal;
    }
    if (displayUnitPrice < 0) displayUnitPrice = 0;

    // --- BƯỚC 3: TÁCH GIÁ TRỊ TOPPING ---
    double toppingPerUnit = 0;
    if (item.toppings.isNotEmpty) {
      for (var entry in item.toppings.entries) {
        toppingPerUnit += (entry.key.sellPrice * entry.value);
      }
    }
    double currentBasePrice = displayUnitPrice - toppingPerUnit;

    // --- BƯỚC 4: QUYẾT ĐỊNH HIỂN THỊ GẠCH NGANG ---
    bool showOriginalPrice = false;
    String discountBadge = "";

    if (item.discountValue != null && item.discountValue != 0) {
      showOriginalPrice = true; // Có tăng/giảm -> Hiện gạch ngang
      if (item.discountUnit == '%') {
        discountBadge = "-${quantityFormat.format(item.discountValue)}%";
      } else {
        discountBadge = item.discountValue! < 0
            ? "+${currencyFormat.format(item.discountValue!.abs())}"
            : "-${currencyFormat.format(item.discountValue)}";
      }
    }
    // Check lệch giá thủ công
    else if ((currentBasePrice - originalCatalogPrice).abs() > 10) {
      showOriginalPrice = true;
    }

    // --- BƯỚC 5: TÍNH THUẾ ---
    double taxRate = 0;
    String taxLabel = 'VAT';
    if (i < taxSettingsList.length) {
      final sItem = taxSettingsList[i];
      if (sItem is Map) {
        taxRate = (sItem['taxRate'] as num?)?.toDouble() ?? 0.0;
        final String tKey = (sItem['taxKey'] as String?) ?? '';
        if (tKey.toUpperCase().contains('HKD')) taxLabel = 'LST';
      }
    }
    String taxStr = taxRate > 0 ? "($taxLabel ${percentFormat.format(taxRate * 100)}%)" : "";

    // --- BƯỚC 6: RENDER UI ---
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 6),
        if (isTimeBased && isFinancialBill)
          // ... (Giữ nguyên phần TimeBased) ...
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 30, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                Expanded(
                    child: RichText(
                        text: TextSpan(style: boldTextStyle.copyWith(fontSize: fsItemName), children: [
                  TextSpan(text: itemName),
                  if (taxStr.isNotEmpty) TextSpan(text: ' $taxStr', style: baseTextStyle.copyWith(fontSize: fsItemName - 2)),
                  if (discountBadge.isNotEmpty)
                    TextSpan(
                        text: ' [$discountBadge]', style: boldTextStyle.copyWith(fontSize: fsItemName - 1, color: Colors.black)),
                ]))),
                Text(currencyFormat.format(item.subtotal), style: boldTextStyle.copyWith(fontSize: fsItemDetail)),
              ]),
              _buildTimeBasedDetails(item, fsItemDetail, timeFormat, currencyFormat, baseTextStyle, boldTextStyle),
            ],
          )
        else if (isCheckDish)
          // ... (Giữ nguyên phần CheckDish) ...
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 35, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
            Expanded(
                flex: 6,
                child: RichText(
                    text: TextSpan(style: boldTextStyle.copyWith(fontSize: fsItemName), children: [
                  TextSpan(text: itemName),
                  if (unit.isNotEmpty) TextSpan(text: ' ($unit)', style: baseTextStyle.copyWith(fontSize: fsItemName)),
                ]))),
            Expanded(
                flex: 4,
                child: Text(isTimeBased ? "${quantityFormat.format(item.quantity)}h" : quantityFormat.format(item.quantity),
                    textAlign: TextAlign.right, style: boldTextStyle.copyWith(fontSize: fsItemName + 2))),
          ])
        else
          // --- BILL TÀI CHÍNH (SỬA Ở ĐÂY) ---
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 30, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                Expanded(
                    child: RichText(
                        text: TextSpan(style: boldTextStyle.copyWith(fontSize: fsItemName), children: [
                  TextSpan(text: itemName),
                  if (unit.isNotEmpty) TextSpan(text: ' ($unit) ', style: baseTextStyle.copyWith(fontSize: fsItemName)),
                  if (taxStr.isNotEmpty) TextSpan(text: '$taxStr ', style: baseTextStyle.copyWith(fontSize: fsItemName - 2)),
                  if (showOriginalPrice) ...[
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle, // Căn Widget này nằm giữa dòng văn bản
                      child: Stack(
                        alignment: Alignment.center, // Căn đường gạch vào CHÍNH GIỮA ô chứa số
                        children: [
                          Text(
                            currencyFormat.format(originalCatalogPrice),
                            style: baseTextStyle.copyWith(
                              fontSize: fsItemName, // Giữ nguyên cỡ chữ
                              fontWeight: FontWeight.w900, // Bold đậm
                              height: 1.0, // Gom gọn chiều cao dòng để căn chuẩn hơn
                            ),
                          ),
                          // Vẽ đường gạch thủ công
                          Positioned(
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 2.5, // Độ dày nét gạch (tùy chỉnh tại đây)
                              color: Colors.black, // Màu gạch
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (discountBadge.isNotEmpty)
                    TextSpan(
                        text: ' [$discountBadge]', style: boldTextStyle.copyWith(fontSize: fsItemName - 1, color: Colors.black)),
                ]))),
              ]),

              // Dòng 2: SL x Đơn giá ......... Thành tiền
              Padding(
                  padding: const EdgeInsets.only(left: 30, top: 2),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('${quantityFormat.format(item.quantity)} x ${currencyFormat.format(displayUnitPrice)}',
                        style: baseTextStyle.copyWith(fontSize: fsItemDetail)),
                    Text(currencyFormat.format(displayLineTotal), style: boldTextStyle.copyWith(fontSize: fsItemDetail)),
                  ]))
            ],
          ),
        if (item.toppings.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: item.toppings.entries.map((e) {
                  return Text(
                      isCheckDish
                          ? '+ ${e.key.productName} x${quantityFormat.format(e.value)}'
                          : '(${e.key.productName} ${quantityFormat.format(e.value)} x ${currencyFormat.format(e.key.sellPrice)})',
                      style: italicTextStyle.copyWith(fontSize: fsItemDetail - 2));
                }).toList()),
          ),
        if (item.note != null && item.note!.isNotEmpty)
          Padding(
              padding: const EdgeInsets.only(left: 30),
              child: Text('(${item.note})', style: italicTextStyle.copyWith(fontSize: fsItemDetail))),
        if (!isLastItem)
          const Divider(thickness: 1, color: Colors.black, height: 12)
        else
          const Divider(thickness: 2, color: Colors.black, height: 24),
      ],
    );
  }

  Widget _buildTimeBasedDetails(OrderItem item, double fontSize, DateFormat timeFormat, NumberFormat currencyFormat,
      TextStyle baseStyle, TextStyle boldStyle) {
    final blocks = item.priceBreakdown;
    if (blocks.isEmpty) return const SizedBox.shrink();
    final startTime = item.addedAt.toDate();
    int totalMinutes = 0;
    for (var rawBlock in blocks) {
      final dynamic b = rawBlock;
      try {
        totalMinutes += (b.minutes as num).toInt();
      } catch (_) {
        try {
          totalMinutes += (b['minutes'] as num).toInt();
        } catch (__) {}
      }
    }
    final endTime = startTime.add(Duration(minutes: totalMinutes));
    double reductionPerHour = 0;
    double percentDiscount = 0;
    if (item.discountValue != null && item.discountValue! > 0) {
      if (item.discountUnit == '%') {
        percentDiscount = item.discountValue! / 100.0;
      } else {
        reductionPerHour = item.discountValue!;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(left: 30, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("${timeFormat.format(startTime)} - ${timeFormat.format(endTime)} (${_formatMinutes(totalMinutes)})",
              style: baseStyle.copyWith(fontSize: fontSize)),
          ...blocks.map((rawBlock) {
            final dynamic block = rawBlock;
            int bMinutes = 0;
            double bRate = 0;
            DateTime? bStart;
            DateTime? bEnd;
            try {
              bMinutes = (block.minutes as num).toInt();
              bRate = (block.ratePerHour as num).toDouble();
              if (block is! Map) {
                bStart = block.startTime;
                bEnd = block.endTime;
              } else {
                final rawStart = block['startTime'];
                final rawEnd = block['endTime'];
                if (rawStart is Timestamp) bStart = rawStart.toDate();
                if (rawEnd is Timestamp) bEnd = rawEnd.toDate();
              }
            } catch (_) {}
            String timeRange = "";
            if (bStart != null && bEnd != null) {
              timeRange = "${timeFormat.format(bStart)} - ${timeFormat.format(bEnd)}";
            }
            if (percentDiscount > 0) {
              bRate = bRate * (1 - percentDiscount);
            } else if (reductionPerHour > 0) {
              bRate = bRate - reductionPerHour;
            }
            if (bRate < 0) bRate = 0;
            String details = "+ $timeRange (${_formatMinutes(bMinutes)} x ${currencyFormat.format(bRate)}/h)";
            return Padding(
                padding: const EdgeInsets.only(top: 2.0),
                child: Text(details, style: baseStyle.copyWith(fontSize: fontSize - 2, color: Colors.black87)));
          }),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) return "${h}h${m.toString().padLeft(2, '0')}'";
    return "$m'";
  }

  Widget _buildInfoRow(String label, String value, TextStyle style) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label, style: style), Expanded(child: Text(value, textAlign: TextAlign.right, style: style))]));
  }

  Widget _buildRow(String label, String value, TextStyle style) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(label, style: style), Text(value, style: style.copyWith(fontWeight: FontWeight.bold))]));
  }
}
