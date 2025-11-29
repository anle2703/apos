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

  const ReceiptWidget({
    super.key,
    required this.title,
    required this.storeInfo,
    required this.items,
    required this.summary,
    required this.userName,
    required this.tableName,
    this.showPrices = true,
    this.isSimplifiedMode = false,
    this.templateSettings,
    this.qrData,
  });

  @override
  Widget build(BuildContext context) {
    final settings = templateSettings ?? ReceiptTemplateModel();
    const double fontScale = 1.8;

    final bool isPaymentBill = title.toUpperCase().contains('HÓA ĐƠN');
    final bool isCheckDish = !showPrices; // Kiểm món hoặc Chuyển/Gộp bàn (thường k hiện giá)

    // Styles
    final baseTextStyle = TextStyle(color: Colors.black, fontFamily: 'Roboto', height: 1.1);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w900);
    final italicTextStyle = baseTextStyle.copyWith(fontStyle: FontStyle.italic);
    final strikeThroughStyle = baseTextStyle.copyWith(decoration: TextDecoration.lineThrough,  decorationThickness: 2);

    // Font Sizes (đã nhân scale)
    final double fsHeader = settings.billHeaderSize * fontScale;
    final double fsAddress = settings.billAddressSize * fontScale;
    final double fsPhone = settings.billPhoneSize * fontScale;
    final double fsTitle = settings.billTitleSize * fontScale;
    final double fsInfo = settings.billTextSize * fontScale; // Info không bold
    final double fsItemName = settings.billItemNameSize * fontScale;
    final double fsItemDetail = settings.billItemDetailSize * fontScale;
    final double fsTotal = settings.billTotalSize * fontScale;

    final currencyFormat = NumberFormat('#,##0', 'vi_VN');
    final quantityFormat = NumberFormat('#,##0.##', 'vi_VN');
    final timeFormat = DateFormat('HH:mm dd/MM/yyyy');
    final percentFormat = NumberFormat('#,##0.##', 'vi_VN');

    // Extract Data
    final double subtotal = (summary['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable = (summary['totalPayable'] as num?)?.toDouble() ?? 0.0;
    final double discount = (summary['discount'] as num?)?.toDouble() ?? 0.0;
    final double taxAmount = (summary['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double changeAmount = (summary['changeAmount'] as num?)?.toDouble() ?? 0.0;
    final double pointsValue = ((summary['customerPointsUsed'] as num?)?.toDouble() ?? 0.0) * 1000.0;
    final String? voucherCode = summary['voucherCode'] as String?;
    final double voucherDiscount = (summary['voucherDiscount'] as num?)?.toDouble() ?? 0.0;
    final List surcharges = (summary['surcharges'] is List) ? summary['surcharges'] : const [];
    final Map<String, dynamic> payments = (summary['payments'] is Map) ? Map<String, dynamic>.from(summary['payments']) : {};
    final double totalPaidFromDB = payments.values.fold(0.0, (a, b) => a + (b as num).toDouble());
    final double debtAmount = totalPayable - totalPaidFromDB;

    final dynamic rawStart = summary['startTime'] ?? summary['startTimeIso'];
    DateTime? startTime;
    if (rawStart is Timestamp) {startTime = rawStart.toDate();}
    else if (rawStart is String && rawStart.isNotEmpty) {try { startTime = DateTime.parse(rawStart); } catch (_) {}}

    final Map<String, dynamic> customer = (summary['customer'] is Map) ? Map<String, dynamic>.from(summary['customer']) : {};
    final String khName = customer['name'] ?? 'Khách lẻ';
    final String? billCode = summary['billCode'] as String?;

    return Container(
      width: 550,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HEADER
          if (settings.billShowStoreName && (storeInfo['name'] ?? '').isNotEmpty)
            Text(storeInfo['name']!.toUpperCase(), textAlign: TextAlign.center, style: boldTextStyle.copyWith(fontSize: fsHeader)),

          if (settings.billShowStoreAddress && (storeInfo['address'] ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(storeInfo['address']!, textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsAddress))),

          if (settings.billShowStorePhone && (storeInfo['phone'] ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2), child: Text('ĐT: ${storeInfo['phone']}', textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsPhone))),

          const SizedBox(height: 16),

          // 2. TITLE
          Text('$title - $tableName', textAlign: TextAlign.center, style: boldTextStyle.copyWith(fontSize: fsTitle)),
          if (isPaymentBill && billCode != null && billCode.isNotEmpty)
            Text(billCode, textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsInfo)),

          const SizedBox(height: 12),

          // 3. INFO SECTION (Căn phải, KHÔNG BOLD)
          if (settings.billShowCustomerName)
            _buildInfoRow('Khách hàng:', khName, baseTextStyle.copyWith(fontSize: fsInfo)),

          if (startTime != null)
            _buildInfoRow('Giờ vào:', timeFormat.format(startTime), baseTextStyle.copyWith(fontSize: fsInfo)),

          _buildInfoRow('Giờ in:', timeFormat.format(DateTime.now()), baseTextStyle.copyWith(fontSize: fsInfo)),

          if (settings.billShowCashierName)
            _buildInfoRow('Thu ngân:', userName, baseTextStyle.copyWith(fontSize: fsInfo)),

          const SizedBox(height: 16),

          // 4. TABLE HEADER
          Container(
            decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(width: 2, color: Colors.black),
                  bottom: BorderSide(width: 2, color: Colors.black),
                )
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text('STT', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                Expanded(flex: 6, child: Text('Tên món', style: boldTextStyle.copyWith(fontSize: fsItemName), textAlign: TextAlign.center)),
                Expanded(
                    flex: 4,
                    child: Text(
                        isCheckDish ? 'SL' : 'Thành tiền', // Kiểm món hiện SL, còn lại hiện Tiền
                        textAlign: TextAlign.right,
                        style: boldTextStyle.copyWith(fontSize: fsItemName)
                    )
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 5. ITEM LIST
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final bool isLastItem = i == items.length - 1;

            String itemName = item.product.productName;
            final String unit = item.selectedUnit.isNotEmpty ? item.selectedUnit : '';
            final double price = item.price;
            final double originalPrice = item.product.sellPrice;
            final bool hasPriceChanged = (price != originalPrice);

            double taxRate = 0;
            String taxLabel = 'VAT';
            if (summary['items'] is List && i < (summary['items'] as List).length) {
              final sItem = (summary['items'] as List)[i];
              if (sItem is Map) {
                taxRate = (sItem['taxRate'] as num?)?.toDouble() ?? 0.0;
                final String tKey = (sItem['taxKey'] as String?) ?? '';
                if (tKey.toUpperCase().contains('HKD')) {
                  taxLabel = 'LST';
                }
              }
            }

            String taxStr = taxRate > 0 ? "($taxLabel ${percentFormat.format(taxRate * 100)}%) " : "";

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),

                if (isCheckDish)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 35, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),

                      // Tên món
                      Expanded(
                        flex: 6,
                        child: RichText(
                          text: TextSpan(
                            style: boldTextStyle.copyWith(fontSize: fsItemName),
                            children: [
                              TextSpan(text: itemName),
                              if (unit.isNotEmpty) TextSpan(text: ' ($unit)', style: baseTextStyle.copyWith(fontSize: fsItemName)),
                            ],
                          ),
                        ),
                      ),

                      // Số lượng (Căn lề phải của cột SL)
                      Expanded(
                        flex: 4,
                        child: Text(
                          quantityFormat.format(item.quantity),
                          textAlign: TextAlign.right,
                          style: boldTextStyle.copyWith(fontSize: fsItemName + 2), // SL đậm và to hơn xíu
                        ),
                      ),
                    ],
                  )

                // TRƯỜNG HỢP 2: BILL/TẠM TÍNH (Name hàng 1, Tiền hàng 2)
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dòng 1: Tên + Thuế + Giá gốc
                      RichText(
                        text: TextSpan(
                          style: boldTextStyle.copyWith(fontSize: fsItemName),
                          children: [
                            TextSpan(text: '${i + 1}. $itemName'),
                            if (unit.isNotEmpty) TextSpan(text: ' ($unit) ', style: baseTextStyle.copyWith(fontSize: fsItemName)),
                            if (taxStr.isNotEmpty) TextSpan(text: taxStr, style: baseTextStyle.copyWith(fontSize: fsItemName)),
                            if (hasPriceChanged)
                              TextSpan(text: currencyFormat.format(originalPrice), style: strikeThroughStyle.copyWith(fontSize: fsItemName)),
                          ],
                        ),
                      ),

                      // Dòng 2: Chi tiết Tiền
                      Padding(
                        padding: const EdgeInsets.only(left: 20, top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${quantityFormat.format(item.quantity)} x ${currencyFormat.format(price)}',
                              style: baseTextStyle.copyWith(fontSize: fsItemDetail),
                            ),
                            Text(
                              currencyFormat.format(item.subtotal),
                              style: boldTextStyle.copyWith(fontSize: fsItemDetail),
                            ),
                          ],
                        ),
                      )
                    ],
                  ),

                // DÒNG 3+: Toppings
                if (item.toppings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: item.toppings.entries.map((e) {
                        final tName = e.key.productName;
                        final tQty = e.value;
                        final tPrice = e.key.sellPrice;
                        return Text(
                            isCheckDish
                                ? '+ $tName x${quantityFormat.format(tQty)}'
                                : '+ $tName (${quantityFormat.format(tQty)} x ${currencyFormat.format(tPrice)})',
                            style: italicTextStyle.copyWith(fontSize: fsItemDetail - 2)
                        );
                      }).toList(),
                    ),
                  ),

                // DÒNG CUỐI: Ghi chú
                if (item.note != null && item.note!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(left: 20), child: Text('(${item.note})', style: italicTextStyle.copyWith(fontSize: fsItemDetail))),

                if (!isLastItem)
                  const Divider(thickness: 1, color: Colors.black, height: 12)
                else
                  const Divider(thickness: 2, color: Colors.black, height: 24),
              ],
            );
          }),

          // 6. SUMMARY
          if (!isCheckDish) ...[
            if (!isSimplifiedMode) ...[
              _buildRow('Tổng cộng:', currencyFormat.format(subtotal), baseTextStyle.copyWith(fontSize: fsInfo)),
              if (settings.billShowTax && taxAmount > 0) _buildRow('Thuế:', '+ ${currencyFormat.format(taxAmount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (settings.billShowDiscount && discount > 0)
                _buildRow(
                    summary['discountName'] ?? 'Chiết khấu:',
                    '- ${currencyFormat.format(discount)}',
                    baseTextStyle.copyWith(fontSize: fsInfo)
                ),
              if (voucherDiscount > 0) _buildRow('Voucher ($voucherCode):', '- ${currencyFormat.format(voucherDiscount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (pointsValue > 0) _buildRow('Điểm thưởng:', '- ${currencyFormat.format(pointsValue)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (settings.billShowSurcharge && surcharges.isNotEmpty)
                ...surcharges.map((s) => _buildRow('${s['name']}:', '+ ${currencyFormat.format((s['amount'] as num).toDouble())}', baseTextStyle.copyWith(fontSize: fsInfo))),
            ],

            if (isSimplifiedMode)
              _buildRow('Tổng cộng:', currencyFormat.format(subtotal), baseTextStyle.copyWith(fontSize: fsInfo)),
            const SizedBox(height: 12),

            if (!isSimplifiedMode && isPaymentBill)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('THÀNH TIỀN:', style: boldTextStyle.copyWith(fontSize: fsTotal)),
                Text(currencyFormat.format(totalPayable), style: boldTextStyle.copyWith(fontSize: fsTotal + 4)),
              ],
            ),

            if (!isSimplifiedMode && isPaymentBill) ...[
              if (settings.billShowPaymentMethod && payments.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Phương thức thanh toán:', style: baseTextStyle.copyWith(fontSize: fsInfo)),
                ...payments.entries.map((entry) => _buildRow('- ${entry.key}:', currencyFormat.format((entry.value as num).toDouble()), baseTextStyle.copyWith(fontSize: fsInfo))),
              ],
              if (changeAmount > 0) _buildRow('Tiền thừa:', currencyFormat.format(changeAmount), baseTextStyle.copyWith(fontSize: fsInfo)),
              if (debtAmount > 0) _buildRow('Dư nợ:', currencyFormat.format(debtAmount), baseTextStyle.copyWith(fontSize: fsInfo)),
            ],
          ],

          // 7. QR CODE
          if (qrData != null && !isSimplifiedMode && !isCheckDish) ...[
            const SizedBox(height: 16),
            Center(child: Text('Quét mã để thanh toán', style: baseTextStyle.copyWith(fontSize: fsInfo))),
            const SizedBox(height: 4),
            Center(
              child: SizedBox(
                width: 180, height: 180,
                child: QrImageView(
                  data: qrData!, version: QrVersions.auto, size: 180.0,
                  backgroundColor: Colors.white, gapless: false, padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],

          // 8. FOOTER (SỬA: Dùng Text tùy chỉnh)
          if (settings.billShowFooter && !isCheckDish) ...[
            const SizedBox(height: 24),
            if (settings.footerText1.isNotEmpty)
              Center(child: Text(settings.footerText1, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
            if (settings.footerText2.isNotEmpty)
              Center(child: Text(settings.footerText2, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
          ]
        ],
      ),
    );
  }

  // SỬA: Helper để căn lề 2 bên (Label Trái - Value Phải)
  Widget _buildInfoRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style), // Label
          Expanded(
            // Value: Căn phải
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(value, style: style.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}