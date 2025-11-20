// File: lib/services/printing_service.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/configured_printer_model.dart';
import '../models/order_item_model.dart';
import 'package:image/image.dart' as img;
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/number_utils.dart';
import '../widgets/cash_flow_printing_helper.dart';
import '../models/cash_flow_transaction_model.dart';
import '../widgets/end_of_day_report_printing_helper.dart';
import '../theme/string_extensions.dart';
import '../widgets/bank_list.dart';

class PrintingService {
  final String tableName;
  final String userName;

  PrintingService({required this.tableName, required this.userName});

  static pw.Font? _font;
  static pw.Font? _boldFont;
  static pw.Font? _italicFont;

  static Future<pw.Font> loadFont({
    bool isBold = false,
    bool isItalic = false,
  }) async {
    if (isItalic) {
      if (_italicFont != null) return _italicFont!;
      final fontData = await rootBundle.load('assets/fonts/RobotoMono-Italic.ttf');
      _italicFont = pw.Font.ttf(fontData);
      return _italicFont!;
    }
    if (isBold) {
      if (_boldFont != null) return _boldFont!;
      final fontData = await rootBundle.load('assets/fonts/RobotoMono-Bold.ttf');
      _boldFont = pw.Font.ttf(fontData);
      return _boldFont!;
    }

    if (_font != null) return _font!;
    final fontData = await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf');
    _font = pw.Font.ttf(fontData);
    return _font!;
  }

  final Map<String, String> _keysToLabels = const {
    'cashier_printer': 'Máy in Thu ngân',
    'kitchen_printer_a': 'Máy in A',
    'kitchen_printer_b': 'Máy in B',
    'kitchen_printer_c': 'Máy in C',
    'kitchen_printer_d': 'Máy in D',
    'label_printer': 'Máy in Tem',
  };

  Future<void> _ensureFontsLoaded() async {
    if (_font != null && _boldFont != null && _italicFont != null) return;
    final fontData = await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/RobotoMono-Bold.ttf');
    final italicFontData = await rootBundle.load('assets/fonts/RobotoMono-Italic.ttf');
    _font = pw.Font.ttf(fontData);
    _boldFont = pw.Font.ttf(boldFontData);
    _italicFont = pw.Font.ttf(italicFontData);
  }

  Future<bool> printTableManagementNotification({
    required Map<String, String> storeInfo,
    required String actionTitle,
    required String message,
    required String userName,
    required DateTime timestamp,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      final pdfBytes = await _generateTableManagementPdf(
        storeInfo: storeInfo,
        actionTitle: actionTitle,
        message: message,
        userName: userName,
        timestamp: timestamp,
      );

      return await _printRawData(
        cashierPrinter.physicalPrinter.device,
        cashierPrinter.physicalPrinter.type,
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      debugPrint('Lỗi in thông báo quản lý bàn: $e');
      rethrow;
    }
  }

  Future<Uint8List> _generateTableManagementPdf({
    required Map<String, String> storeInfo,
    required String actionTitle,
    required String message,
    required String userName,
    required DateTime timestamp,
  }) async {
    final pdf = pw.Document();
    await _ensureFontsLoaded();
    final font = _font!;
    final boldFont = _boldFont!;

    const double printableWidthMm = 72;
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                  child: pw.Text(actionTitle,
                      style: pw.TextStyle(font: boldFont, fontSize: 16))),
              pw.SizedBox(height: 15),
              pw.Text(
                'Nhân viên: $userName',
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
              pw.SizedBox(height: 5),
              pw.Text(
                'Thời gian: ${DateFormat('HH:mm dd/MM/yyyy').format(timestamp)}',
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
              pw.Divider(height: 20, thickness: 1.5),
              pw.Text(
                message,
                style: pw.TextStyle(font: boldFont, fontSize: 12),
              ),
              pw.Divider(height: 20, thickness: 1.5),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<bool> printKitchenTicket({
    required List<OrderItem> itemsToPrint,
    required String targetPrinterRole,
    required List<ConfiguredPrinter> configuredPrinters,
    String? customerName,
  }) async {
    if (itemsToPrint.isEmpty) return true;
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();

    try {
      final targetPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == targetPrinterRole,
        orElse: () => throw Exception(
            '${_keysToLabels[targetPrinterRole] ?? targetPrinterRole} chưa được gán trong Cài đặt.'),
      );

      final pdfBytes = await _generateKitchenPdf(
        title: 'BÁO BẾP',
        items: itemsToPrint,
        isCancelTicket: false,
        customerName: customerName,
      );

      return await _printRawData(targetPrinter.physicalPrinter.device,
          targetPrinter.physicalPrinter.type,
          pdfBytes: pdfBytes);
    } catch (e) {
      debugPrint('Lỗi khi in cho máy "$targetPrinterRole": $e');
      rethrow;
    }
  }

  Future<bool> printProvisionalBill({
    required Map<String, String> storeInfo,
    required List<OrderItem> items,
    required Map<String, dynamic> summary,
    required bool showPrices,
    required List<ConfiguredPrinter> configuredPrinters,
    bool useDetailedLayout = false,
  }) async {
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      if (useDetailedLayout) {
        final pdfBytes = await generateReceiptPdf(
          title: 'TẠM TÍNH',
          storeInfo: storeInfo,
          items: items.where((i) => i.quantity > 0).toList(),
          summary: summary,
        );
        return await _printRawData(cashierPrinter.physicalPrinter.device,
            cashierPrinter.physicalPrinter.type,
            pdfBytes: pdfBytes);
      } else {
        final pdfBytes = await _generateBillPdf(
          title: showPrices ? 'TẠM TÍNH' : 'KIỂM MÓN',
          storeInfo: storeInfo,
          items: items.where((i) => i.quantity > 0).toList(),
          totalAmount: (summary['subtotal'] as num?)?.toDouble() ?? 0.0,
          showPrices: showPrices,
          summary: summary,
        );
        return await _printRawData(cashierPrinter.physicalPrinter.device,
            cashierPrinter.physicalPrinter.type,
            pdfBytes: pdfBytes);
      }
    } catch (e) {
      debugPrint('Lỗi in hóa đơn tạm tính: $e');
      rethrow;
    }
  }

  Future<bool> printCancelTicket({
    required List<OrderItem> itemsToCancel,
    required String targetPrinterRole,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    if (itemsToCancel.isEmpty) return true;
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();

    try {
      final targetPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == targetPrinterRole,
        orElse: () => throw Exception(
            'Máy in "${_keysToLabels[targetPrinterRole] ?? targetPrinterRole}" chưa được gán trong Cài đặt.'),
      );

      final pdfBytes = await _generateKitchenPdf(
        title: 'HỦY MÓN',
        items: itemsToCancel,
        isCancelTicket: true,
      );
      return await _printRawData(targetPrinter.physicalPrinter.device,
          targetPrinter.physicalPrinter.type,
          pdfBytes: pdfBytes);
    } catch (e) {
      debugPrint('Lỗi khi in phiếu hủy: $e');
      rethrow;
    }
  }

  Future<Uint8List> _generateKitchenPdf({
    required String title,
    required List<OrderItem> items,
    required bool isCancelTicket,
    String? customerName,
  }) async {
    final pdf = pw.Document();
    await _ensureFontsLoaded();
    final font = _font!;
    final boldFont = _boldFont!;
    final italicFont = _italicFont!;

    const double printableWidthMm = 72;
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );
    final quantityFormat = NumberFormat('#,##0.##');

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                  child: pw.Text('$title - $tableName',
                      style: pw.TextStyle(font: boldFont, fontSize: 14))),
              pw.SizedBox(height: 10),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (customerName != null && customerName.isNotEmpty) ...[
                    pw.Text(
                      'KH: $customerName',
                      style: pw.TextStyle(font: font, fontSize: 10),
                    ),
                    pw.SizedBox(height: 5),
                  ],
                  pw.Text(
                    'Nhân viên: $userName',
                    style: pw.TextStyle(font: font, fontSize: 10),
                  ),
                  pw.SizedBox(height: 5),
                  pw.Text(
                    'Thời gian: ${DateFormat('HH:mm dd/MM').format(DateTime.now())}',
                    style: pw.TextStyle(font: font, fontSize: 10),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                pw.Container(
                    width: 20,
                    child: pw.Text('STT',
                        style: pw.TextStyle(font: boldFont, fontSize: 10))),
                pw.Expanded(
                    flex: 6,
                    child: pw.Text('Tên Món',
                        style: pw.TextStyle(font: boldFont, fontSize: 10),
                        textAlign: pw.TextAlign.center)),
                pw.Container(
                    width: 20,
                    child: pw.Text('SL',
                        style: pw.TextStyle(font: boldFont, fontSize: 10),
                        textAlign: pw.TextAlign.right)),
              ]),
              pw.Divider(height: 5, thickness: 1.5),
              ...items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final double quantityToPrint = item.quantity;
                if (quantityToPrint == 0) {
                  return pw.SizedBox.shrink();
                }

                var itemStyle =
                pw.TextStyle(font: boldFont, fontSize: 12);
                if (isCancelTicket) {
                  itemStyle = itemStyle.copyWith(
                    decoration: pw.TextDecoration.lineThrough,
                    decorationThickness: 2.0,
                  );
                }

                return pw.Column(children: [
                  pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                            width: 20,
                            child: pw.Text('${i + 1}.',
                                style: pw.TextStyle(
                                    font: boldFont, fontSize: 10))),
                        pw.Expanded(
                          flex: 6,
                          child: pw.Text(
                            '${item.product.productName}${item.selectedUnit.isNotEmpty ? " (${item.selectedUnit})" : ""}',
                            style: itemStyle,
                          ),
                        ),
                        pw.Container(
                            width: 30,
                            child: pw.Text(
                              isCancelTicket
                                  ? '-${quantityFormat.format(quantityToPrint)}'
                                  : quantityFormat.format(quantityToPrint),
                              style: pw.TextStyle(
                                  font: boldFont, fontSize: 12),
                              textAlign: pw.TextAlign.right,
                            )),
                      ]),
                  if (item.note.nullIfEmpty != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            '(${item.note!})',
                            style: pw.TextStyle(
                                font: italicFont, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  if (item.toppings.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: item.toppings.entries
                            .map((e) => pw.Text(
                          '+${e.key.productName} x${quantityFormat.format(e.value)}',
                          style: pw.TextStyle(
                              font: italicFont, fontSize: 12),
                        ))
                            .toList(),
                      ),
                    ),
                  pw.Divider(
                      height: 1,
                      thickness: 1,
                      borderStyle: pw.BorderStyle.dashed),
                ]);
              }),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<bool> printReceiptBill({
    required Map<String, String> storeInfo,
    required List<OrderItem> items,
    required Map<String, dynamic> summary,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      final pdfBytes = await generateReceiptPdf(
        title: 'HÓA ĐƠN',
        storeInfo: storeInfo,
        items: items.where((i) => i.quantity > 0).toList(),
        summary: summary,
      );

      return await _printRawData(
        cashierPrinter.physicalPrinter.device,
        cashierPrinter.physicalPrinter.type,
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      debugPrint('Lỗi in hóa đơn: $e');
      rethrow;
    }
  }

  Future<Uint8List> _generateBillPdf({
    required String title,
    required List<OrderItem> items,
    required Map<String, String> storeInfo,
    required double totalAmount,
    required bool showPrices,
    required Map<String, dynamic> summary,
  }) async {
    final pdf = pw.Document();
    await _ensureFontsLoaded();
    final font = _font!;
    final boldFont = _boldFont!;
    final italicFont = _italicFont!;

    const double printableWidthMm = 72;
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );
    final currencyFormat = NumberFormat('#,##0');
    final quantityFormat = NumberFormat('#,##0.##');
    final timeOnlyFormat = DateFormat('HH:mm');

    final Map<String, dynamic> customer = (summary['customer'] is Map)
        ? Map<String, dynamic>.from(summary['customer'])
        : {};
    final double totalToPrint = (summary['subtotal'] as num?)?.toDouble() ?? totalAmount;

    String formatTotalMinutes(int totalMinutes) {
      if (totalMinutes <= 0) return "0'";
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours > 0) {
        return "${hours}h${minutes.toString().padLeft(2, '0')}'";
      }
      return "$minutes'";
    }

    final String guestAddress = (customer['guestAddress'] as String?) ?? '';
    final String khName = customer['name'] ?? 'Khách lẻ';
    final String? dbPhone = customer['phone'] as String?;
    final bool isShipOrder = tableName.startsWith('Giao Hàng');

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if ((storeInfo['name'] ?? '').isNotEmpty)
                pw.Center(
                    child: pw.Text(storeInfo['name']!,
                        style: pw.TextStyle(font: boldFont, fontSize: 16))),
              if ((storeInfo['address'] ?? '').isNotEmpty)
                pw.Center(
                    child: pw.Text(storeInfo['address']!,
                        style: pw.TextStyle(font: font, fontSize: 10),
                        textAlign: pw.TextAlign.center)),
              if ((storeInfo['phone'] ?? '').isNotEmpty)
                pw.Center(
                    child: pw.Text('SĐT: ${storeInfo['phone']}',
                        style: pw.TextStyle(font: font, fontSize: 10))),
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text('$title - $tableName',
                      style: pw.TextStyle(font: boldFont, fontSize: 14))),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                pw.Text('Thu ngân: $userName',
                    style: pw.TextStyle(font: font, fontSize: 10)),
              ]),

              pw.Text('KH: $khName', style: pw.TextStyle(font: font, fontSize: 10)),
              if (isShipOrder) ...[
                pw.Text('SĐT: $dbPhone', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('ĐC: $guestAddress', style: pw.TextStyle(font: font, fontSize: 10), maxLines: 2, overflow: pw.TextOverflow.clip),
              ],

              pw.Row(children: [
                pw.Text('Giờ in: ${DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now())}',
                    style: pw.TextStyle(font: font, fontSize: 10)),
              ]),
              pw.SizedBox(height: 10),
              pw.Row(children: [
                pw.Container(
                    width: 20,
                    child: pw.Text('STT',
                        style: pw.TextStyle(font: boldFont, fontSize: 10))),
                pw.Expanded(
                    flex: 5,
                    child: pw.Text('Tên Món',
                        style: pw.TextStyle(font: boldFont, fontSize: 10),
                        textAlign: pw.TextAlign.center)),
                pw.Expanded(
                    flex: 4,
                    child: pw.Text(showPrices ? 'T.Tiền' : 'SL',
                        style: pw.TextStyle(font: boldFont, fontSize: 10),
                        textAlign: pw.TextAlign.right)),
              ]),
              pw.Divider(height: 2, thickness: 1),

              ...items.asMap().entries.map((entry) {
                final i = entry.key;
                final item = entry.value;
                final bool isLastItem = i == items.length - 1;
                final bool isTimeBased = item.product.serviceSetup?['isTimeBased'] == true && item.priceBreakdown.isNotEmpty;

                final bool priceHasChanged = (item.price != item.product.sellPrice) && !isTimeBased;
                String discountText = '';
                if (item.discountValue != null && item.discountValue! > 0) {
                  if (item.discountUnit == '%') {
                    discountText = "(-${formatNumber(item.discountValue!)}%)";
                  } else {
                    discountText = "(-${formatNumber(item.discountValue!)}đ)";
                  }
                }

                String itemName = item.product.productName;
                if (isTimeBased) {
                  final totalMinutes = item.priceBreakdown.fold<int>(0, (tong, block) => tong + block.minutes);
                  itemName += ' (${formatTotalMinutes(totalMinutes)})';
                }

                if (showPrices) {
                  return pw.Column(children: [
                    pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                              width: 20,
                              child: pw.Text('${i + 1}.',
                                  style: pw.TextStyle(
                                      font: boldFont, fontSize: 10))),
                          pw.Expanded(
                              child: pw.RichText(
                                text: pw.TextSpan(
                                  style: pw.TextStyle(font: boldFont, fontSize: 10),
                                  children: [
                                    // 1. Tên SP
                                    pw.TextSpan(text: itemName),

                                    // 2. Đơn vị tính
                                    if (item.selectedUnit.isNotEmpty)
                                      pw.TextSpan(
                                          text: ' (${item.selectedUnit})',
                                          style: pw.TextStyle(fontSize: 9)
                                      ),

                                    // 3. Giá gốc gạch ngang
                                    if (priceHasChanged)
                                      pw.TextSpan(
                                        text: ' ${currencyFormat.format(item.product.sellPrice)}',
                                        style: pw.TextStyle(
                                          fontSize: 9,
                                          decoration: pw.TextDecoration.lineThrough,
                                          decorationThickness: 2.0,
                                        ),
                                      ),

                                    // 4. Chiết khấu
                                    if (discountText.isNotEmpty)
                                      pw.TextSpan(
                                        text: ' $discountText',
                                        style: pw.TextStyle(
                                          fontSize: 9,
                                        ),
                                      ),
                                  ],
                                ),
                              )
                          ),
                        ]),

                    if (isTimeBased)
                      pw.Row(children: [
                        pw.Container(width: 20),
                        pw.Expanded(
                            flex: 5,
                            child: pw.Text(
                              '${timeOnlyFormat.format(item.addedAt.toDate())} - ${timeOnlyFormat.format(item.addedAt.toDate().add(Duration(minutes: item.priceBreakdown.fold<int>(0, (tong, block) => tong + block.minutes))))}',
                              style: pw.TextStyle(font: font, fontSize: 10),
                            )),
                        pw.Expanded(
                            flex: 4,
                            child: pw.Text(currencyFormat.format(item.subtotal),
                                style: pw.TextStyle(font: font, fontSize: 10),
                                textAlign: pw.TextAlign.right)),
                      ])
                    else
                      pw.Row(children: [
                        pw.Container(width: 20),
                        pw.Expanded(
                            flex: 5,
                            child: pw.Text(
                                '${quantityFormat.format(item.quantity)} x ${currencyFormat.format(item.price)}',
                                style: pw.TextStyle(font: font, fontSize: 10))),
                        pw.Expanded(
                            flex: 4,
                            child: pw.Text(currencyFormat.format(item.subtotal),
                                style: pw.TextStyle(font: font, fontSize: 10),
                                textAlign: pw.TextAlign.right)),
                      ]),

                    if (item.toppings.isNotEmpty)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(left: 20),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: item.toppings.entries
                              .map((e) => pw.Text(
                            '+ ${e.key.productName} ${quantityFormat.format(e.value)} x ${currencyFormat.format(e.key.sellPrice)}',
                            style: pw.TextStyle(font: italicFont, fontSize: 9),
                          )).toList(),
                        ),
                      ),

                    _buildTimeBasedItemDetails(item, italicFont, currencyFormat),

                    pw.Divider(
                      height: 10,
                      thickness: isLastItem ? 1.2 : 0.5,
                      borderStyle: isLastItem ? pw.BorderStyle.solid : pw.BorderStyle.dashed,
                    ),
                  ]);
                } else {
                  return pw.Column(children: [
                    pw.Row(children: [
                      pw.Container(
                          width: 25,
                          child: pw.Text('${i + 1}.',
                              style: pw.TextStyle(font: boldFont, fontSize: 10))),
                      pw.Expanded(
                          flex: 6,
                          child: pw.Text(itemName, style: pw.TextStyle(font: boldFont, fontSize: 10))),
                      pw.Container(
                          width: 30,
                          child: pw.Text(quantityFormat.format(item.quantity),
                              style: pw.TextStyle(font: boldFont, fontSize: 10),
                              textAlign: pw.TextAlign.right)),
                    ]),
                    pw.Divider(
                      height: 1,
                      thickness: isLastItem ? 1.2 : 0.5,
                      borderStyle: isLastItem ? pw.BorderStyle.solid : pw.BorderStyle.dashed,
                    ),
                  ]);
                }
              }),

              if (showPrices) ...[
                pw.SizedBox(height: 10),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children: [
                  pw.Text('TỔNG CỘNG:',
                      style: pw.TextStyle(font: boldFont, fontSize: 10)),
                  pw.SizedBox(width: 10),
                  pw.Text('${currencyFormat.format(totalToPrint)} VND',
                      style: pw.TextStyle(font: boldFont, fontSize: 12)),
                ]),
              ],
              pw.SizedBox(height: 10),
              pw.Center(
                  child: pw.Text('Cảm ơn quý khách!',
                      style: pw.TextStyle(font: italicFont, fontSize: 12))),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> generateReceiptPdf({
    required String title,
    required Map<String, String> storeInfo,
    required List<OrderItem> items,
    required Map<String, dynamic> summary,
  }) async {
    final pdf = pw.Document();
    await _ensureFontsLoaded();
    final font = _font!;
    final boldFont = _boldFont!;
    final italicFont = _italicFont!;

    const double printableWidthMm = 72;
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );
    final qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
    final currencyFormat = NumberFormat('#,##0');
    final timeOnlyFormat = DateFormat('HH:mm');

    String formatTotalMinutes(int totalMinutes) {
      if (totalMinutes <= 0) return "0'";
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours > 0) {
        return "${hours}h${minutes.toString().padLeft(2, '0')}'";
      }
      return "$minutes'";
    }

    final double subtotal = (summary['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double discount = (summary['discount'] as num?)?.toDouble() ?? 0.0;
    final String discountType = (summary['discountType'] as String?) ?? 'VND';
    final double discountInput = (summary['discountInput'] as num?)?.toDouble() ?? 0.0;
    final double pointsUsed = (summary['customerPointsUsed'] as num?)?.toDouble() ?? 0.0;
    final double pointsValue = pointsUsed * 1000.0;
    final double taxPercent = (summary['taxPercent'] as num?)?.toDouble() ?? 0.0;
    final double taxAmount = (summary['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable = (summary['totalPayable'] as num?)?.toDouble() ?? 0.0;
    final double changeAmount = (summary['changeAmount'] as num?)?.toDouble() ?? 0.0;
    final String? voucherCode = summary['voucherCode'] as String?;
    final double voucherDiscount = (summary['voucherDiscount'] as num?)?.toDouble() ?? 0.0;
    final rawSurcharges = summary['surcharges'];
    final List surcharges = (rawSurcharges is List) ? rawSurcharges : const [];
    final rawPayments = summary['payments'];
    final Map<String, dynamic> payments = (rawPayments is Map) ? Map<String, dynamic>.from(rawPayments) : {};
    final Map<String, dynamic> customer = (summary['customer'] is Map) ? Map<String, dynamic>.from(summary['customer']) : {};
    final dynamic rawStart = summary['startTime'] ?? summary['startTimeIso'];
    DateTime? startTime;
    if (rawStart is Timestamp) {
      startTime = rawStart.toDate();
    } else if (rawStart is String && rawStart.isNotEmpty) {
      try { startTime = DateTime.parse(rawStart); } catch (e) { debugPrint('Không thể parse startTime: $rawStart ($e)'); }
    }
    final dynamic rawCreatedAt = summary['createdAt'];
    DateTime? createdAtTime;
    if (rawCreatedAt is Timestamp) {
      createdAtTime = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String && rawCreatedAt.isNotEmpty) {
      try { createdAtTime = DateTime.parse(rawCreatedAt); } catch (e) { debugPrint('Không thể parse createdAtTime: $rawCreatedAt ($e)'); }
    }
    final DateTime checkoutTime = createdAtTime ?? DateTime.now();
    final double totalPaidFromDB = payments.values.fold(0.0, (a, b) => a + (b as num).toDouble());
    final double debtAmount = totalPayable - totalPaidFromDB;

    final Map<String, dynamic>? bankDetails =
    (summary['bankDetails'] as Map<String, dynamic>?);

    final String? eInvoiceFullUrl = summary['eInvoiceFullUrl'] as String?;
    final String? eInvoiceCode = summary['eInvoiceCode'] as String?;
    final String? eInvoiceMst = summary['eInvoiceMst'] as String?;

    pw.ImageProvider? qrImage;

    final String guestAddress = (customer['guestAddress'] as String?) ?? '';
    final String khName = customer['name'] ?? 'Khách lẻ';
    final String? dbPhone = customer['phone'] as String?;
    final String? billCode = summary['billCode'] as String?;
    final String mainTitle = '$title - $tableName';
    final bool isShipOrder = tableName.startsWith('Giao Hàng');

    if (bankDetails != null && totalPayable > 0) {
      final bin = bankDetails['bankBin'] ?? '';
      final acc = bankDetails['bankAccount'] ?? '';
      if (bin.isNotEmpty && acc.isNotEmpty) {

        // 1. Tra cứu bank shortName
        final bankInfo = vietnameseBanks.firstWhere(
              (b) => b.bin == bin,
          orElse: () => BankInfo(name: '', shortName: '', bin: ''),
        );

        if (bankInfo.shortName.isNotEmpty) {
          final amount = totalPayable.toInt().toString();
          final addInfo = Uri.encodeComponent(tableName); // Dùng tên bàn

          // 2. Dùng API "compact" (sạch logo thừa)
          final compactUrl = 'https://img.vietqr.io/image/${bankInfo.shortName}-$acc-compact.png?amount=$amount&addInfo=$addInfo';

          debugPrint("PrintingService: Đang tải QR từ $compactUrl");

          try {
            // 3. Dùng pw.NetworkImage (từ package 'printing') để tải ảnh
            qrImage = await networkImage(compactUrl);
          } catch (e) {
            debugPrint("PrintingService: Lỗi tải ảnh QR để in: $e");
            qrImage = null; // Bỏ qua nếu lỗi
          }
        }
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (storeInfo['name']?.isNotEmpty == true)
                pw.Center(child: pw.Text(storeInfo['name']!, style: pw.TextStyle(font: boldFont, fontSize: 16))),
              if (storeInfo['address']?.isNotEmpty == true)
                pw.Center(child: pw.Text(storeInfo['address']!, style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center)),
              if ((storeInfo['phone'] ?? '').isNotEmpty)
                pw.Center(child: pw.Text('ĐT: ${storeInfo['phone']!}', style: pw.TextStyle(font: font, fontSize: 10))),
              pw.SizedBox(height: 8),

              pw.Center(child: pw.Text(mainTitle, style: pw.TextStyle(font: boldFont, fontSize: 14))),

              if (billCode != null && billCode.isNotEmpty)
                pw.Center(child: pw.Text(billCode, style: pw.TextStyle(font: font, fontSize: 10))),

              pw.SizedBox(height: 8),
              pw.Text('KH: $khName', style: pw.TextStyle(font: font, fontSize: 10)),

              if (isShipOrder) ...[
                pw.Text('SĐT: $dbPhone', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('ĐC: $guestAddress', style: pw.TextStyle(font: font, fontSize: 10), maxLines: 2, overflow: pw.TextOverflow.clip),
              ],

              if (!isShipOrder) ...[
                if (startTime != null)
                  pw.Text('Giờ vào: ${DateFormat('HH:mm dd/MM/yyyy').format(startTime)}', style: pw.TextStyle(font: font, fontSize: 10)),
                pw.Text('Giờ ra: ${DateFormat('HH:mm dd/MM/yyyy').format(checkoutTime)}', style: pw.TextStyle(font: font, fontSize: 10)),
              ] else ...[
                pw.Text('Giờ in: ${DateFormat('HH:mm dd/MM/yyyy').format(checkoutTime)}', style: pw.TextStyle(font: font, fontSize: 10)),
              ],
              pw.Text('Thu ngân: $userName', style: pw.TextStyle(font: font, fontSize: 10)),
              pw.SizedBox(height: 8),

              pw.Row(children: [
                pw.Container(width: 20, child: pw.Text('STT', style: pw.TextStyle(font: boldFont, fontSize: 10))),
                pw.Expanded(flex: 5, child: pw.Text('Tên Món', style: pw.TextStyle(font: boldFont, fontSize: 10), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 4, child: pw.Text('T.Tiền', style: pw.TextStyle(font: boldFont, fontSize: 10), textAlign: pw.TextAlign.right)),
              ]),
              pw.Divider(height: 2, thickness: 0.5),
              pw.SizedBox(height: 4),

              ...items.asMap().entries.map((entry) {
                final i = entry.key;
                final it = entry.value;
                final bool isLastItem = i == items.length - 1;
                final bool isTimeBased = it.product.serviceSetup?['isTimeBased'] == true && it.priceBreakdown.isNotEmpty;

                final bool priceHasChanged = (it.price != it.product.sellPrice) && !isTimeBased;
                String discountText = '';
                if (it.discountValue != null && it.discountValue! > 0) {
                  if (it.discountUnit == '%') {
                    discountText = "(-${formatNumber(it.discountValue!)}%)";
                  } else {
                    discountText = "(-${formatNumber(it.discountValue!)}đ)";
                  }
                }

                String itemName = it.product.productName;
                if (isTimeBased) {
                  final totalMinutes = it.priceBreakdown.fold<int>(0, (tong, block) => tong + block.minutes);
                  itemName += ' (${formatTotalMinutes(totalMinutes)})';
                }

                return pw.Column(children: [
                  pw.Row(children: [
                    pw.Container(width: 20, child: pw.Text('${i + 1}.', style: pw.TextStyle(font: boldFont, fontSize: 10))),
                    pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            style: pw.TextStyle(font: boldFont, fontSize: 10), // Style chung
                            children: [
                              // 1. Tên SP (dùng 'it')
                              pw.TextSpan(text: itemName),

                              // 2. Đơn vị tính (dùng 'it')
                              if (it.selectedUnit.isNotEmpty)
                                pw.TextSpan(
                                    text: ' (${it.selectedUnit})',
                                    style: pw.TextStyle(fontSize: 9)
                                ),

                              // 3. Giá gốc gạch ngang (dùng 'it' và 'priceHasChanged')
                              if (priceHasChanged)
                                pw.TextSpan(
                                  text: ' ${currencyFormat.format(it.product.sellPrice)}',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    decoration: pw.TextDecoration.lineThrough,
                                    decorationThickness: 2.0,
                                  ),
                                ),

                              // 4. Chiết khấu (dùng 'discountText')
                              if (discountText.isNotEmpty)
                                pw.TextSpan(
                                  text: ' $discountText',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                  ),
                                ),
                            ],
                          ),
                        )
                    ),
                  ]),

                  if (isTimeBased)
                    pw.Row(children: [
                      pw.Container(width: 20),
                      pw.Expanded(
                          flex: 5,
                          child: pw.Text(
                            '${timeOnlyFormat.format(it.addedAt.toDate())} - ${timeOnlyFormat.format(it.addedAt.toDate().add(Duration(minutes: it.priceBreakdown.fold<int>(0, (tong, block) => tong + block.minutes))))}',
                            style: pw.TextStyle(font: font, fontSize: 10),
                          )),
                      pw.Expanded(
                          flex: 4,
                          child: pw.Text(formatNumber(it.subtotal),
                              style: pw.TextStyle(font: font, fontSize: 10),
                              textAlign: pw.TextAlign.right)),
                    ])
                  else
                    pw.Row(children: [
                      pw.Container(width: 20),
                      pw.Expanded(flex: 5, child: pw.Text('${qtyFmt.format(it.quantity)} x ${formatNumber(it.price)}', style: pw.TextStyle(font: font, fontSize: 10))),
                      pw.Expanded(flex: 4, child: pw.Text(formatNumber(it.subtotal), style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.right)),
                    ]),

                  if (it.toppings.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: it.toppings.entries
                            .map((e) => pw.Text(
                          '+ ${e.key.productName} ${qtyFmt.format(e.value)} x ${formatNumber(e.key.sellPrice)}',
                          style: pw.TextStyle(font: italicFont, fontSize: 9),
                        )).toList(),
                      ),
                    ),

                  if (it.note.nullIfEmpty != null)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 20),
                      child: pw.Row(
                        children: [
                          pw.Text(
                            '(${it.note!})',
                            style: pw.TextStyle(
                              font: italicFont,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),

                  _buildTimeBasedItemDetails(it, italicFont, currencyFormat),

                  if (!isLastItem)
                    pw.Divider(
                      height: 8,
                      thickness: 0.5,
                      borderStyle: pw.BorderStyle.dashed,
                    ),
                ]);
              }),

              pw.Divider(height: 4, thickness: 0.5),
              pw.SizedBox(height: 8),

              _kvRow('Tổng cộng:', '${formatNumber(subtotal)} đ'),
              if (discount > 0)
                _kvRow('Chiết khấu: ${discountType == '%' ? ' (${formatNumber(discountInput)}%)' : ''}', '- ${formatNumber(discount)} đ'),
              if (voucherDiscount > 0)
                _kvRow('Voucher (${voucherCode ?? ''}):', '- ${formatNumber(voucherDiscount)} đ'),
              if (pointsValue > 0)
                _kvRow('Điểm thưởng:', '- ${formatNumber(pointsValue)} đ'),
              if (taxPercent > 0)
                _kvRow('Thuế VAT (${formatNumber(taxPercent)}%):', '+ ${formatNumber(taxAmount)} đ'),
              if (surcharges.isNotEmpty) ...[
                ...surcharges.map((s) {
                  final name = s['name']?.toString() ?? 'Phụ thu';
                  final bool isPercent = s['isPercent'] == true;
                  final amount = (s['amount'] as num?)?.toDouble() ?? 0.0;
                  final computedValue = isPercent ? (subtotal * amount / 100) : amount;
                  final label = isPercent ? '$name (${formatNumber(amount)}%)' : name;
                  return _kvRow(label, '+ ${formatNumber(computedValue)} đ');
                }),
              ],
              pw.SizedBox(height: 8),
              _kvRow('Thành tiền:', '${formatNumber(totalPayable)} đ'),
              if (title == 'HÓA ĐƠN') ...[
                if (payments.isNotEmpty) ...[
                  // Thêm tiêu đề phụ
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 0),
                    child: pw.Text(
                      'Phương thức thanh toán:',
                      style: pw.TextStyle(font: font, fontSize: 10),
                    ),
                  ),
                  ...payments.entries.map((entry) {
                    final methodName = entry.key;
                    final methodAmount = (entry.value as num?)?.toDouble() ?? 0.0;
                    return _kvRow(
                        '- $methodName:',
                        '${formatNumber(methodAmount)} đ',
                        small: true
                    );
                  }),
                ],
                if (changeAmount > 0)
                  _kvRow('Tiền thừa:', '${formatNumber(changeAmount)} đ'),
                if (debtAmount > 0)
                  _kvRow('Dư nợ:', '${formatNumber(debtAmount)} đ'),
              ],

              if (qrImage != null) ...[
                pw.SizedBox(height: 10),
                pw.Center(
                  child: pw.Text('Quét mã để thanh toán',
                      style: pw.TextStyle(font: font, fontSize: 10)),
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  // Dùng pw.Image để hiển thị ảnh đã tải về
                  child: pw.Image(
                    qrImage,
                    width: 100,
                    height: 100,
                  ),
                ),
              ],

              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Cảm ơn quý khách!', style: pw.TextStyle(font: italicFont, fontSize: 10))),

              if (eInvoiceFullUrl != null && eInvoiceFullUrl.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Divider(height: 2, thickness: 0.5, borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 8),
                pw.Center(
                  child: pw.Text(
                    'TRA CỨU HÓA ĐƠN ĐIỆN TỬ',
                    style: pw.TextStyle(font: boldFont, fontSize: 9),
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Builder(
                    builder: (context) {
                      String qrData = eInvoiceFullUrl;

                      if (eInvoiceMst != null && eInvoiceMst.isNotEmpty &&
                          eInvoiceCode != null && eInvoiceCode.isNotEmpty) {

                        final uri = Uri.tryParse(eInvoiceFullUrl);
                        final baseUrl = uri != null
                            ? '${uri.scheme}://${uri.host}${uri.path}'
                            : eInvoiceFullUrl;
                        qrData = '$baseUrl?taxCode=$eInvoiceMst&reservationCode=$eInvoiceCode';
                      }

                      return pw.Center(
                        child: pw.BarcodeWidget(
                          barcode: pw.Barcode.qrCode(),
                          data: qrData,
                          width: 60,
                          height: 60,
                        ),
                      );
                    }
                ),
                pw.SizedBox(height: 4),
                pw.Center(
                  child: pw.Text(
                    'MST bên bán: $eInvoiceMst',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'Mã số bí mật: $eInvoiceCode',
                    style: pw.TextStyle(font: font, fontSize: 9),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  Future<bool> printCashFlowTicket({
    required Map<String, String> storeInfo,
    required CashFlowTransaction transaction,
    required double? openingDebt,
    required double? closingDebt,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      final pdfBytes = await CashFlowPrintingHelper.generatePdf(
        tx: transaction,
        storeInfo: storeInfo,
        openingDebt: openingDebt,
        closingDebt: closingDebt,
      );

      return await _printRawData(
        cashierPrinter.physicalPrinter.device,
        cashierPrinter.physicalPrinter.type,
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      debugPrint('Lỗi in phiếu thu/chi: $e');
      rethrow;
    }
  }

  Future<bool> printEndOfDayReport({
    required Map<String, String> storeInfo,
    required Map<String, dynamic> totalReportData,
    required List<Map<String, dynamic>> shiftReportsData,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    await _ensureFontsLoaded();
    // **ĐÃ XÓA**: await PermissionService.ensurePermissions();
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      // Sử dụng helper PDF mới tạo
      final pdfBytes = await EndOfDayReportPrintingHelper.generatePdf(
        storeInfo: storeInfo,
        totalReportData: totalReportData,
        shiftReportsData: shiftReportsData,
      );

      return await _printRawData(
        cashierPrinter.physicalPrinter.device,
        cashierPrinter.physicalPrinter.type,
        pdfBytes: pdfBytes,
      );
    } catch (e) {
      debugPrint('Lỗi in Báo Cáo Tổng Kết: $e');
      rethrow;
    }
  }

  pw.Widget _kvRow(
      String key,
      String value, {
        bool bold = false,
        bool big = false,
        bool small = false,
        PdfColor? color,
        pw.Font? boldFont,
      }) {
    final fs = big ? 12 : (small ? 9 : 10);
    final normalFont = _font!;
    final effectiveBold = boldFont ?? _boldFont!;

    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(key,
            style: pw.TextStyle(
              font: bold ? effectiveBold : normalFont,
              fontSize: fs.toDouble(),
              color: color ?? PdfColors.black,
            )),
        pw.Text(value,
            style: pw.TextStyle(
              font: effectiveBold,
              fontSize: fs.toDouble(),
              color: color ?? PdfColors.black,
            )),
      ],
    );
  }

  Future<bool> _printRawData(
      PrinterDevice printer,
      PrinterType type, {
        required Uint8List pdfBytes,
      }) async {
    final printerManager = PrinterManager.instance;
    final profile = await CapabilityProfile.load(name: 'default');
    final generator = Generator(PaperSize.mm80, profile);

    List<int> totalBytes = [];

    // 1. Ngắt kết nối cũ an toàn
    try {
      await printerManager.disconnect(type: type);
    } catch (e) { /* Bỏ qua lỗi ngắt kết nối */ }

    if (type == PrinterType.usb) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    debugPrint("Đang kết nối tới máy in: ${printer.name} (${printer.address})");

    bool result = false;

    // --- SỬA LỖI: GỌI CONNECT TRỰC TIẾP TỪNG LOẠI ---
    try {
      if (type == PrinterType.network) {
        final String cleanIp = (printer.address ?? '192.168.1.100').trim();
        // Gọi trực tiếp TcpPrinterInput tại đây, không qua biến trung gian
        result = await printerManager.connect(
            type: type,
            model: TcpPrinterInput(ipAddress: cleanIp, port: 9100)
        );
      } else if (type == PrinterType.usb) {
        result = await printerManager.connect(
            type: type,
            model: UsbPrinterInput(
                name: printer.name,
                vendorId: printer.vendorId,
                productId: printer.productId)
        );
      } else {
        result = await printerManager.connect(
            type: type,
            model: BluetoothPrinterInput(
                name: printer.name,
                address: printer.address!,
                isBle: false,
                autoConnect: true)
        );
      }
    } catch (e) {
      debugPrint("Lỗi khi gọi connect: $e");
      return false;
    }
    // ------------------------------------------------

    debugPrint("Kết quả connect: $result");

    if (result == true) {
      try {
        if (type == PrinterType.network || type == PrinterType.usb) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
          final ui.Image uiImage = await page.toImage();
          final byteData =
          await uiImage.toByteData(format: ui.ImageByteFormat.png);

          if (byteData != null) {
            final rawBytes = byteData.buffer.asUint8List();
            final decoded = img.decodeImage(rawBytes);
            if (decoded != null) {
              final resized = img.copyResize(decoded, width: 576);
              totalBytes += generator.image(resized);
            }
          }
        }
        totalBytes += generator.feed(1);
        totalBytes += generator.cut();

        debugPrint("Đang gửi ${totalBytes.length} bytes...");
        await printerManager.send(
            type: type, bytes: Uint8List.fromList(totalBytes));

        // Đợi in xong rồi ngắt kết nối
        await Future.delayed(const Duration(milliseconds: 500));
        await printerManager.disconnect(type: type);

        return true;

      } catch (e) {
        debugPrint("Lỗi khi gửi dữ liệu: $e");
        await printerManager.disconnect(type: type).catchError((_) => false);
        return false;
      }
    } else {
      throw Exception('Không thể kết nối đến máy in (Connect return false).');
    }
  }

  Future<void> disconnectPrinter(PrinterType type) async {
    final printerManager = PrinterManager.instance;
    await printerManager.disconnect(type: type);
    debugPrint("Đã disconnect máy in khi thoát app.");
  }

  pw.Widget _buildTimeBasedItemDetails(
      OrderItem item,
      pw.Font italicFont,
      NumberFormat currencyFormat,
      ) {
    if (item.product.serviceSetup?['isTimeBased'] != true ||
        item.priceBreakdown.isEmpty) {
      return pw.SizedBox.shrink();
    }

    final timeFormat = DateFormat('HH:mm dd/MM');

    String formatMinutes(int totalMinutes) {
      if (totalMinutes <= 0) return "0'";
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours > 0) {
        return "${hours}h${minutes.toString().padLeft(2, '0')}'";
      }
      return "$minutes'";
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.only(left: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: item.priceBreakdown.map((block) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${timeFormat.format(block.startTime)} -> ${timeFormat.format(block.endTime)}',
                style: pw.TextStyle(font: italicFont, fontSize: 9),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 10),
                child: pw.Text(
                  "${formatMinutes(block.minutes)} x ${currencyFormat.format(block.ratePerHour)} = ${currencyFormat.format(block.cost)}",
                  style: pw.TextStyle(font: italicFont, fontSize: 9),
                ),
              )
            ],
          );
        }).toList(),
      ),
    );
  }
}