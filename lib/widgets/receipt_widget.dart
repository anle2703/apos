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
    final bool isCheckDish = !showPrices;

    // Styles
    final baseTextStyle = TextStyle(color: Colors.black, fontFamily: 'Roboto', height: 1.1);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w900);
    final italicTextStyle = baseTextStyle.copyWith(fontStyle: FontStyle.italic);
    final strikeThroughStyle = baseTextStyle.copyWith(decoration: TextDecoration.lineThrough, decorationThickness: 2);

    // Font Sizes
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

    // Format ngắn cho chi tiết giờ (VD: 10:30 03/12)
    final shortDateTimeFormat = DateFormat('HH:mm dd/MM');

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
    if (rawStart is Timestamp) {
      startTime = rawStart.toDate();
    } else if (rawStart is String && rawStart.isNotEmpty) {
      try {
        startTime = DateTime.parse(rawStart);
      } catch (_) {}
    }

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
          Text(tableName.isNotEmpty ? '$title - $tableName' : title, textAlign: TextAlign.center, style: boldTextStyle.copyWith(fontSize: fsTitle)),
          if (isPaymentBill && billCode != null && billCode.isNotEmpty) Text(billCode, textAlign: TextAlign.center, style: baseTextStyle.copyWith(fontSize: fsInfo)),

          const SizedBox(height: 12),

          // 3. INFO SECTION
          if (settings.billShowCustomerName) _buildInfoRow('Khách hàng:', khName, baseTextStyle.copyWith(fontSize: fsInfo)),
          if (startTime != null) _buildInfoRow('Giờ vào:', timeFormat.format(startTime), baseTextStyle.copyWith(fontSize: fsInfo)),
          _buildInfoRow('Giờ in:', timeFormat.format(DateTime.now()), baseTextStyle.copyWith(fontSize: fsInfo)),
          if (settings.billShowCashierName) _buildInfoRow('Thu ngân:', userName, baseTextStyle.copyWith(fontSize: fsInfo)),

          const SizedBox(height: 16),

          // 4. TABLE HEADER
          Container(
            decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(width: 2, color: Colors.black),
                  bottom: BorderSide(width: 2, color: Colors.black),
                )),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(width: 50, child: Text('STT', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                Expanded(flex: 6, child: Text('Tên món / DV', style: boldTextStyle.copyWith(fontSize: fsItemName), textAlign: TextAlign.center)),
                Expanded(
                    flex: 4,
                    child: Text(isCheckDish ? 'SL' : 'Thành tiền', textAlign: TextAlign.right, style: boldTextStyle.copyWith(fontSize: fsItemName))),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 5. ITEM LIST
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final bool isLastItem = i == items.length - 1;

            final String itemName = item.product.productName;
            final String unit = item.selectedUnit.isNotEmpty ? item.selectedUnit : '';
            final bool isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;

            // --- TÍNH TOÁN GIÁ HIỂN THỊ ---
            double originalPrice = item.product.sellPrice;
            double effectiveUnitPrice;

            if (isTimeBased) {
              effectiveUnitPrice = 0;
            } else {
              if (item.discountValue != null && item.discountValue! > 0) {
                if (item.discountUnit == '%') {
                  effectiveUnitPrice = originalPrice * (1 - item.discountValue! / 100);
                } else {
                  effectiveUnitPrice = originalPrice - (item.discountValue! / item.quantity);
                }
              } else {
                effectiveUnitPrice = item.price;
              }
            }

            // --- BADGE GIẢM GIÁ ---
            String discountBadge = "";
            bool showOriginalPrice = false;

            if (item.discountValue != null && item.discountValue! > 0) {
              if (item.discountUnit == '%') {
                discountBadge = "-${quantityFormat.format(item.discountValue)}%";
              } else {
                if (isTimeBased) {
                  discountBadge = "-${currencyFormat.format(item.discountValue)}/h";
                } else {
                  discountBadge = "-${currencyFormat.format(item.discountValue)}";
                }
              }
              // Có giảm giá thì hiện giá gốc (để gạch ngang)
              showOriginalPrice = true;
            } else if (!isTimeBased && item.price != originalPrice) {
              showOriginalPrice = true;
              effectiveUnitPrice = item.price;
            }

            // Tax Logic
            double taxRate = 0;
            String taxLabel = 'VAT';
            if (summary['items'] is List && i < (summary['items'] as List).length) {
              final sItem = (summary['items'] as List)[i];
              if (sItem is Map) {
                taxRate = (sItem['taxRate'] as num?)?.toDouble() ?? 0.0;
                final String tKey = (sItem['taxKey'] as String?) ?? '';
                if (tKey.toUpperCase().contains('HKD')) taxLabel = 'LST';
              }
            }
            String taxStr = taxRate > 0 ? "($taxLabel ${percentFormat.format(taxRate * 100)}%)" : "";

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 6),

                // ============================================
                // TRƯỜNG HỢP 1: DỊCH VỤ TÍNH GIỜ (LAYOUT MỚI)
                // ============================================
                if (isTimeBased && !isCheckDish)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // HÀNG 1: Tên + Thuế + Chiết khấu ..... Tổng tiền
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 30, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),

                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: boldTextStyle.copyWith(fontSize: fsItemName),
                                children: [
                                  TextSpan(text: itemName),
                                  if (taxStr.isNotEmpty) TextSpan(text: ' $taxStr', style: baseTextStyle.copyWith(fontSize: fsItemName - 2)),
                                  if (discountBadge.isNotEmpty)
                                    TextSpan(
                                      text: ' [$discountBadge]',
                                      style: boldTextStyle.copyWith(fontSize: fsItemName - 1, color: Colors.black),
                                    ),
                                ],
                              ),
                            ),
                          ),

                          // Tổng tiền nằm luôn ở Hàng 1
                          Text(
                            currencyFormat.format(item.subtotal),
                            style: boldTextStyle.copyWith(fontSize: fsItemDetail),
                          ),
                        ],
                      ),

                      // HÀNG 2, 3, 4...: Chi tiết giờ (Thụt lề vào)
                      _buildTimeBasedDetails(item, fsItemDetail, shortDateTimeFormat, currencyFormat, baseTextStyle, boldTextStyle),
                    ],
                  )

                // ============================================
                // TRƯỜNG HỢP 2: KIỂM MÓN (CHECK DISH)
                // ============================================
                else if (isCheckDish)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 35, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
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
                      Expanded(
                        flex: 4,
                        child: Text(
                          isTimeBased ? "${quantityFormat.format(item.quantity)}h" : quantityFormat.format(item.quantity),
                          textAlign: TextAlign.right,
                          style: boldTextStyle.copyWith(fontSize: fsItemName + 2),
                        ),
                      ),
                    ],
                  )

                // ============================================
                // TRƯỜNG HỢP 3: MÓN THƯỜNG (PAYMENT BILL)
                // ============================================
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // LINE 1: Name ... [OriginalPrice Crossed] [Discount]
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 30, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: boldTextStyle.copyWith(fontSize: fsItemName),
                                children: [
                                  TextSpan(text: itemName),
                                  if (unit.isNotEmpty) TextSpan(text: ' ($unit)', style: baseTextStyle.copyWith(fontSize: fsItemName)),
                                  if (taxStr.isNotEmpty) TextSpan(text: ' $taxStr', style: baseTextStyle.copyWith(fontSize: fsItemName - 2)),

                                  if (showOriginalPrice) ...[
                                    TextSpan(text: '  ', style: baseTextStyle),
                                    TextSpan(
                                        text: currencyFormat.format(originalPrice),
                                        style: strikeThroughStyle.copyWith(fontSize: fsItemName - 1)),
                                  ],

                                  if (discountBadge.isNotEmpty)
                                    TextSpan(
                                      text: ' [$discountBadge]',
                                      style: boldTextStyle.copyWith(fontSize: fsItemName - 1, color: Colors.black),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),

                      // LINE 2: Phép tính tiền
                      Padding(
                        padding: const EdgeInsets.only(left: 30, top: 2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${quantityFormat.format(item.quantity)} x ${currencyFormat.format(effectiveUnitPrice)}',
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

                // TOPPINGS
                if (item.toppings.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 30),
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
                            style: italicTextStyle.copyWith(fontSize: fsItemDetail - 2));
                      }).toList(),
                    ),
                  ),

                // NOTE
                if (item.note != null && item.note!.isNotEmpty)
                  Padding(padding: const EdgeInsets.only(left: 30), child: Text('(${item.note})', style: italicTextStyle.copyWith(fontSize: fsItemDetail))),

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
                _buildRow(summary['discountName'] ?? 'Chiết khấu:', '- ${currencyFormat.format(discount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (voucherDiscount > 0) _buildRow('Voucher ($voucherCode):', '- ${currencyFormat.format(voucherDiscount)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (pointsValue > 0) _buildRow('Điểm thưởng:', '- ${currencyFormat.format(pointsValue)}', baseTextStyle.copyWith(fontSize: fsInfo)),
              if (settings.billShowSurcharge && surcharges.isNotEmpty)
                ...surcharges.map((s) => _buildRow('${s['name']}:', '+ ${currencyFormat.format((s['amount'] as num).toDouble())}', baseTextStyle.copyWith(fontSize: fsInfo))),
            ],
            if (isSimplifiedMode) _buildRow('Tổng cộng:', currencyFormat.format(subtotal), baseTextStyle.copyWith(fontSize: fsInfo)),
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
                width: 180,
                height: 180,
                child: QrImageView(
                  data: qrData!,
                  version: QrVersions.auto,
                  size: 180.0,
                  backgroundColor: Colors.white,
                  gapless: false,
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
          ],

          // 8. FOOTER
          if (settings.billShowFooter && !isCheckDish) ...[
            const SizedBox(height: 24),
            if (settings.footerText1.isNotEmpty) Center(child: Text(settings.footerText1, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
            if (settings.footerText2.isNotEmpty) Center(child: Text(settings.footerText2, style: italicTextStyle.copyWith(fontSize: fsInfo), textAlign: TextAlign.center)),
          ]
        ],
      ),
    );
  }

  // --- HELPER: TIME BASED DETAILS ---
  Widget _buildTimeBasedDetails(
      OrderItem item,
      double fontSize,
      DateFormat timeFormat,
      NumberFormat currencyFormat,
      TextStyle baseStyle,
      TextStyle boldStyle,
      ) {
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

    // Tính toán giảm giá
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
          // HÀNG 2: Tổng thời gian
          Text(
            "${timeFormat.format(startTime)} - ${timeFormat.format(endTime)} (${_formatMinutes(totalMinutes)})",
            style: baseStyle.copyWith(fontSize: fontSize, fontStyle: FontStyle.italic),
          ),

          // HÀNG 3+: Chi tiết Blocks (Định dạng: 10:30 - 11:00 (30' x 60.000/h))
          ...blocks.map((rawBlock) {
            final dynamic block = rawBlock;
            int bMinutes = 0;
            double bRate = 0;
            DateTime? bStart;
            DateTime? bEnd;

            try {
              bMinutes = (block.minutes as num).toInt();
              bRate = (block.ratePerHour as num).toDouble();

              // Nếu block là Object thì có thể lấy được startTime, endTime
              // Nếu là Map từ Firestore thì phải parse String hoặc Timestamp
              if (block is! Map) {
                bStart = block.startTime;
                bEnd = block.endTime;
              } else {
                final rawStart = block['startTime'];
                final rawEnd = block['endTime'];
                if (rawStart is Timestamp) bStart = rawStart.toDate();
                if (rawEnd is Timestamp) bEnd = rawEnd.toDate();
              }
            } catch (_) {
              // Fallback nếu không lấy được
            }

            // Fallback thời gian hiển thị nếu không lấy được chi tiết block
            String timeRange = "";
            if (bStart != null && bEnd != null) {
              timeRange = "${timeFormat.format(bStart)} - ${timeFormat.format(bEnd)}";
            }

            // Tính lại Rate sau giảm giá
            if (percentDiscount > 0) {
              bRate = bRate * (1 - percentDiscount);
            } else if (reductionPerHour > 0) {
              bRate = bRate - reductionPerHour;
            }
            if (bRate < 0) bRate = 0;

            // Tính lại chuỗi hiển thị
            String details = "+ $timeRange (${_formatMinutes(bMinutes)} x ${currencyFormat.format(bRate)}/h)";

            return Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                details,
                style: baseStyle.copyWith(fontSize: fontSize - 2, color: Colors.black87),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _formatMinutes(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0) {
      return "${h}h${m.toString().padLeft(2, '0')}'";
    }
    return "$m'";
  }

  Widget _buildInfoRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          Expanded(child: Text(value, textAlign: TextAlign.right, style: style)),
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