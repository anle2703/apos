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
import 'label_printing_service.dart';
import 'package:printing/printing.dart' as printing_lib;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import '../models/label_template_model.dart';

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
    final percentFormat = NumberFormat('#,##0.##', 'vi_VN');

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

    String taxLabel = 'Thuế:';
    if (taxAmount > 0 && summary['items'] is List) {
      final summaryItems = summary['items'] as List;
      // Quét item đầu tiên có thuế để xác định loại
      for (var item in summaryItems) {
        if (item is Map && item.containsKey('taxKey')) {
          final String key = item['taxKey'].toString();
          if (key.startsWith('HKD_')) {
            taxLabel = 'Thuế gộp:'; // Nhóm 2 HKD (Trực tiếp)
            break;
          } else if (key.startsWith('VAT_')) {
            taxLabel = 'VAT:'; // Nhóm 3 HKD hoặc Doanh nghiệp (Khấu trừ)
            break;
          }
        }
      }
    }

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
        final bankInfo = vietnameseBanks.firstWhere(
              (b) => b.bin == bin,
          orElse: () => BankInfo(name: '', shortName: '', bin: ''),
        );

        if (bankInfo.shortName.isNotEmpty) {
          final amount = totalPayable.toInt().toString();
          final addInfo = Uri.encodeComponent(tableName);
          final compactUrl = 'https://img.vietqr.io/image/${bankInfo.shortName}-$acc-compact.png?amount=$amount&addInfo=$addInfo';
          try {
            qrImage = await networkImage(compactUrl);
          } catch (e) {
            debugPrint("PrintingService: Lỗi tải ảnh QR để in: $e");
            qrImage = null;
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
                pw.Expanded(flex: 5, child: pw.Text('Tên Món (Thuế)', style: pw.TextStyle(font: boldFont, fontSize: 10), textAlign: pw.TextAlign.center)),
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
                    discountText = "[-${formatNumber(it.discountValue!)}%]";
                  } else {
                    discountText = "[-${formatNumber(it.discountValue!)}đ]";
                  }
                }

                String itemName = it.product.productName;

                double itemTaxRate = 0;
                if (summary['items'] is List) {
                  final summaryItem = (summary['items'] as List)[i];
                  if (summaryItem is Map) {
                    itemTaxRate = (summaryItem['taxRate'] as num?)?.toDouble() ?? 0.0;
                  }
                }

                String taxRateStr = '';
                if (itemTaxRate > 0) {
                  double percentValue = itemTaxRate * 100;
                  taxRateStr = " (${percentFormat.format(percentValue)}%)";
                }

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
                            style: pw.TextStyle(font: boldFont, fontSize: 10),
                            children: [
                              // 1. Tên SP
                              pw.TextSpan(text: itemName),

                              // 2. Đơn vị tính (Đưa lên trước thuế)
                              if (it.selectedUnit.isNotEmpty)
                                pw.TextSpan(
                                    text: ' - ${it.selectedUnit}',
                                    style: pw.TextStyle(fontSize: 9)
                                ),

                              // 3. % Thuế (Nằm sau ĐVT)
                              if (taxRateStr.isNotEmpty)
                                pw.TextSpan(
                                  text: taxRateStr,
                                  style: pw.TextStyle(fontSize: 9),
                                ),

                              // 4. Giá gốc gạch ngang
                              if (priceHasChanged)
                                pw.TextSpan(
                                  text: ' ${currencyFormat.format(it.product.sellPrice)}',
                                  style: pw.TextStyle(
                                    fontSize: 9,
                                    decoration: pw.TextDecoration.lineThrough,
                                    decorationThickness: 2.0,
                                  ),
                                ),

                              // 5. Chiết khấu
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

              if (taxAmount > 0)
                _kvRow(
                    taxLabel,
                    '+ ${currencyFormat.format(taxAmount)} đ'
                ),

              if (discount > 0)
                _kvRow('Chiết khấu: ${discountType == '%' ? ' (${formatNumber(discountInput)}%)' : ''}', '- ${formatNumber(discount)} đ'),
              if (voucherDiscount > 0)
                _kvRow('Voucher (${voucherCode ?? ''}):', '- ${formatNumber(voucherDiscount)} đ'),
              if (pointsValue > 0)
                _kvRow('Điểm thưởng:', '- ${formatNumber(pointsValue)} đ'),

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

    debugPrint(">>> KIỂM TRA MÁY IN: Name='${printer.name}', Address='${printer.address}', VendorId='${printer.vendorId}'");

    bool shouldUseWindowsDriver = (printer.vendorId == 'DRIVER_WINDOWS') ||
        (printer.name == printer.address);

    if (shouldUseWindowsDriver) {
      try {
        debugPrint(">>> [MODE 1] ĐANG IN QUA WINDOWS DRIVER (PDF Mode)...");

        final printers = await printing_lib.Printing.listPrinters();
        final targetPrinter = printers.firstWhere(
              (p) => p.name == printer.name,
          orElse: () {
            debugPrint(">>> Cảnh báo: Không tìm thấy driver '${printer.name}' trong hệ thống. Thử dùng tên làm URL.");
            return printing_lib.Printer(url: printer.name, name: printer.name);
          },
        );

        // In trực tiếp PDF qua Driver
        return await printing_lib.Printing.directPrintPdf(
          printer: targetPrinter,
          onLayout: (format) async => pdfBytes,
          usePrinterSettings: true,
        );
      } catch (e) {
        debugPrint(">>> LỖI IN DRIVER: $e");
        return false;
      }
    }

    debugPrint(">>> [MODE 2] ĐANG IN QUA RAW BYTES (PrinterManager)...");

    final printerManager = PrinterManager.instance;
    final profile = await CapabilityProfile.load(name: 'default');
    final generator = Generator(PaperSize.mm80, profile);
    List<int> totalBytes = [];
    final model = _getPrinterModel(printer, type);

    try {
      await printerManager.disconnect(type: type);
    } catch (_) {}

    if (type == PrinterType.usb) {
      await Future.delayed(const Duration(milliseconds: 200));
    }

    final result = await printerManager.connect(type: type, model: model);

    if (result == true) {
      try {
        if (type == PrinterType.network || type == PrinterType.usb) {
          await Future.delayed(const Duration(milliseconds: 100));
        }

        await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
          final ui.Image uiImage = await page.toImage();
          final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final rawBytes = byteData.buffer.asUint8List();
            final decoded = img.decodeImage(rawBytes);
            if (decoded != null) {
              final resized = img.copyResize(decoded, width: 576);
              totalBytes += generator.image(resized);
            }
          }
        }

        await printerManager.send(type: type, bytes: Uint8List.fromList(totalBytes));
        await printerManager.disconnect(type: type);
        return true;
      } catch (e) {
        debugPrint("Lỗi Raw Send: $e");
        await printerManager.disconnect(type: type);
        return false;
      }
    } else {
      throw Exception('Không thể kết nối đến máy in (Raw Mode).');
    }
  }

  Future<int> _getNextLabelSequence() async {
    final prefs = await SharedPreferences.getInstance();
    final String todayStr = DateFormat('yyyyMMdd').format(DateTime.now());

    final String lastDate = prefs.getString('label_seq_date') ?? '';
    int currentSeq = prefs.getInt('label_seq_num') ?? 0;

    if (lastDate != todayStr) {
      currentSeq = 1;
      await prefs.setString('label_seq_date', todayStr);
    } else {
      currentSeq++;
    }

    await prefs.setInt('label_seq_num', currentSeq);
    return currentSeq;
  }

  Future<void> disconnectPrinter(PrinterType type) async {
    final printerManager = PrinterManager.instance;
    await printerManager.disconnect(type: type);
    debugPrint("Đã disconnect máy in khi thoát app.");
  }

  BasePrinterInput _getPrinterModel(PrinterDevice printer, PrinterType type) {
    switch (type) {
      case PrinterType.network:
        return TcpPrinterInput(ipAddress: printer.address!, port: 9100);
      case PrinterType.bluetooth:
        return BluetoothPrinterInput(
            name: printer.name,
            address: printer.address!,
            isBle: false,
            autoConnect: true);
      case PrinterType.usb:
        return UsbPrinterInput(
            name: printer.name,
            vendorId: printer.vendorId,
            productId: printer.productId);
    }
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

  Future<bool> printLabels({
    required List<Map<String, dynamic>> items,
    required String tableName,
    required DateTime createdAt,
    required List<ConfiguredPrinter> configuredPrinters,
    required double width,
    required double height,
    bool isRetailMode = false,
  }) async {
    try {
      final labelPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'label_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Tem".'),
      );

      final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

      final prefs = await SharedPreferences.getInstance();
      LabelTemplateModel settings = LabelTemplateModel();
      final jsonStr = prefs.getString('label_template_settings');
      if (jsonStr != null) {
        settings = LabelTemplateModel.fromJson(jsonStr);
      } else {
        settings.labelWidth = width;
        settings.labelHeight = height;
        settings.labelColumns = (width >= 65) ? 2 : 1;
      }

      final double printWidth = settings.labelWidth;
      final double printHeight = settings.labelHeight;
      final int columns = settings.labelColumns;

      List<LabelData> allLabelsQueue = [];
      int grandTotalQty = 0;
      for (var itemData in items) {
        grandTotalQty += (OrderItem.fromMap(itemData).quantity).ceil();
      }
      final int dailySeq = await _getNextLabelSequence();
      int globalCurrentIndex = 0;
      for (var itemData in items) {
        final item = OrderItem.fromMap(itemData);
        final int itemQty = item.quantity.ceil();
        for (int i = 1; i <= itemQty; i++) {
          globalCurrentIndex++;
          allLabelsQueue.add(LabelData(
            item: item,
            tableName: tableName,
            createdAt: createdAt,
            dailySeq: dailySeq,
            copyIndex: globalCurrentIndex,
            totalCopies: grandTotalQty,
          ));
        }
      }

      if (!isDesktop && labelPrinter.physicalPrinter.type == PrinterType.network) {
        final String ip = labelPrinter.physicalPrinter.device.address!;
        Socket? socket;
        try {
          socket = await Socket.connect(ip, 9100, timeout: const Duration(seconds: 5));
          List<int> totalCommands = [];

          for (int i = 0; i < allLabelsQueue.length; i += columns) {
            List<LabelData> batch = [];
            for (int c = 0; c < columns; c++) {
              if (i + c < allLabelsQueue.length) {
                batch.add(allLabelsQueue[i + c]);
              }
            }

            final pdfBytes = await LabelPrintingService.generateLabelPdf(
              labelsOnPage: batch,
              pageWidthMm: printWidth,
              pageHeightMm: printHeight,
              settings: settings,
              isRetailMode: isRetailMode, // <--- 2. TRUYỀN VÀO ĐÂY
              forceWhiteBackground: false,
            );

            final List<int> commands = await _getTsplCommandsFromPdf(pdfBytes, printWidth, printHeight);
            totalCommands.addAll(commands);
          }

          // ... (Phần gửi socket giữ nguyên) ...
          if (totalCommands.isNotEmpty) {
            const int chunkSize = 4096;
            for (var j = 0; j < totalCommands.length; j += chunkSize) {
              var end = (j + chunkSize < totalCommands.length) ? j + chunkSize : totalCommands.length;
              socket.add(totalCommands.sublist(j, end));
              await Future.delayed(const Duration(milliseconds: 5));
            }
            await socket.flush();
          }
          await Future.delayed(const Duration(seconds: 2));
          socket.destroy();
          return true;

        } catch (e) {
          try { socket?.destroy(); } catch (_) {}
          return false;
        }
      } else {
        // Logic Desktop/Khác
        for (int i = 0; i < allLabelsQueue.length; i += columns) {
          List<LabelData> batch = [];
          for (int c = 0; c < columns; c++) {
            if (i + c < allLabelsQueue.length) {
              batch.add(allLabelsQueue[i + c]);
            }
          }

          final pdfBytes = await LabelPrintingService.generateLabelPdf(
            labelsOnPage: batch,
            pageWidthMm: printWidth,
            pageHeightMm: printHeight,
            settings: settings,
            isRetailMode: isRetailMode, // <--- 3. TRUYỀN VÀO ĐÂY
            forceWhiteBackground: isDesktop,
          );

          if (isDesktop) {
            await _printRawData(
              labelPrinter.physicalPrinter.device,
              labelPrinter.physicalPrinter.type,
              pdfBytes: pdfBytes,
            );
          } else {
            await _printLabelRawTSPL(
              labelPrinter.physicalPrinter.device,
              labelPrinter.physicalPrinter.type,
              pdfBytes: pdfBytes,
              labelWidthMm: printWidth,
              labelHeightMm: printHeight,
            );
          }
          await Future.delayed(const Duration(milliseconds: 300));
        }
        return true;
      }
    } catch (e) {
      debugPrint('Lỗi in tem: $e');
      return false;
    }
  }

  Future<List<int>> _getTsplCommandsFromPdf(Uint8List pdfBytes, double width, double height) async {
    List<int> allCommands = [];

    await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
      final ui.Image uiImage = await page.toImage();
      final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final rawBytes = byteData.buffer.asUint8List();
        var decodedImage = img.decodeImage(rawBytes);

        if (decodedImage != null) {
          // --- XỬ LÝ NỀN TRẮNG (Fix lỗi nền đen) ---
          final whiteBgImage = img.Image(width: decodedImage.width, height: decodedImage.height);
          img.fill(whiteBgImage, color: img.ColorRgb8(255, 255, 255));
          img.compositeImage(whiteBgImage, decodedImage);

          // Sinh lệnh TSPL (Dùng hàm _generateTSPL chuẩn đã sửa ở bước trước)
          allCommands.addAll(_generateTSPL(whiteBgImage, width, height));
        }
      }
    }
    return allCommands;
  }

  List<int> _generateTSPL(img.Image image, double widthMm, double heightMm) {
    List<int> commands = [];

    int w = widthMm.toInt();
    int h = heightMm.toInt();

    // 1. SETUP
    // Khai báo kích thước tem vật lý
    String cmd = 'SIZE $w mm, $h mm\r\n';
    cmd += 'GAP 2 mm, 0 mm\r\n';
    cmd += 'DIRECTION 1\r\n';
    cmd += 'CLS\r\n';
    commands.addAll(utf8.encode(cmd));

    // 2. BITMAP
    // Lưu ý: widthPx là chiều rộng thực tế của ảnh (có thể nhỏ hơn w vật lý)
    int widthPx = image.width;
    int heightPx = image.height;

    // Tính số byte cho mỗi dòng (làm tròn lên)
    int widthBytes = (widthPx + 7) ~/ 8;

    String bitmapHeader = 'BITMAP 0,0,$widthBytes,$heightPx,0,';
    commands.addAll(utf8.encode(bitmapHeader));

    List<int> bitmapData = [];
    for (int y = 0; y < heightPx; y++) {
      for (int i = 0; i < widthBytes; i++) {

        // --- THAY ĐỔI QUAN TRỌNG Ở ĐÂY ---
        // Khởi tạo byte là 0xFF (11111111) -> Tương ứng toàn màu TRẮNG
        // Điều này đảm bảo các bit thừa (padding) luôn là trắng -> Hết bị kẻ dọc
        int byte = 0xFF;

        for (int j = 0; j < 8; j++) {
          int x = i * 8 + j;
          if (x < widthPx) {
            final pixel = image.getPixel(x, y);

            // LOGIC MỚI: TÌM ĐIỂM ĐEN ĐỂ "ĐỤC LỖ" TRÊN NỀN TRẮNG

            // 1. Kiểm tra có nội dung không (Alpha > 0)
            bool hasContent = pixel.a > 0;

            if (hasContent) {
              // 2. Kiểm tra độ tối (Luminance < 128 là màu tối/đen)
              // Nếu là màu tối -> Gán bit thành 0 (Set bit to 0)
              if (pixel.luminance < 128) {
                // Phép toán bit: Đảo bit 1 thành 0 tại vị trí j
                byte &= ~(1 << (7 - j));
              }
            }
            // Nếu là màu sáng hoặc trong suốt, byte vẫn giữ nguyên là 1 (Trắng)
          }
        }
        bitmapData.add(byte);
      }
    }
    commands.addAll(bitmapData);
    commands.addAll(utf8.encode('\r\n'));

    // 3. PRINT
    commands.addAll(utf8.encode('PRINT 1,1\r\n'));

    return commands;
  }

  Future<bool> _printLabelRawTSPL(
      PrinterDevice printer,
      PrinterType type, {
        required Uint8List pdfBytes,
        required double labelWidthMm,
        required double labelHeightMm,
      }) async {
    final printerManager = PrinterManager.instance;
    try {
      await printerManager.disconnect(type: type);
      if (type == PrinterType.network) await Future.delayed(const Duration(milliseconds: 200));
      final model = _getPrinterModel(printer, type);
      bool connected = await printerManager.connect(type: type, model: model).timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!connected) return false;

      List<int> tsplCommands = [];
      await for (final page in Printing.raster(pdfBytes, dpi: 203)) {
        final ui.Image uiImage = await page.toImage();
        final byteData = await uiImage.toByteData(format: ui.ImageByteFormat.png);
        if (byteData != null) {
          final rawBytes = byteData.buffer.asUint8List();
          var decodedImage = img.decodeImage(rawBytes);
          if (decodedImage != null) {
            // SỬA LỖI API IMAGE v4 tại đây tương tự hàm trên

            // 1. Tạo ảnh nền trắng
            var whiteBgImage = img.Image(width: decodedImage.width, height: decodedImage.height);

            // 2. Fill màu trắng
            img.fill(whiteBgImage, color: img.ColorRgb8(255, 255, 255));

            // 3. Merge ảnh
            img.compositeImage(whiteBgImage, decodedImage);

            tsplCommands.addAll(_generateTSPL(whiteBgImage, labelWidthMm, labelHeightMm));
          }
        }
      }

      if (tsplCommands.isNotEmpty) {
        const int chunkSize = 1024;
        for (var i = 0; i < tsplCommands.length; i += chunkSize) {
          var end = (i + chunkSize < tsplCommands.length) ? i + chunkSize : tsplCommands.length;
          await printerManager.send(type: type, bytes: Uint8List.fromList(tsplCommands.sublist(i, end)));
          await Future.delayed(const Duration(milliseconds: 5));
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
      await printerManager.disconnect(type: type);
      return true;

    } catch (e) {
      debugPrint(">>> Lỗi _printLabelRawTSPL: $e");
      try { await printerManager.disconnect(type: type); } catch (_) {}
      return false;
    }
  }
}