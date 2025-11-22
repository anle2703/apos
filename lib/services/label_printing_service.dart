// File: lib/services/label_printing_service.dart

import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_item_model.dart';
import '../models/label_template_model.dart';
import '../theme/number_utils.dart';

class LabelPrintingService {
  static pw.Font? _fontRegular;
  static pw.Font? _fontBold;

  static Future<void> _ensureFontsLoaded() async {
    if (_fontRegular != null && _fontBold != null) return;
    final fontDataReg = await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf');
    final fontDataBold = await rootBundle.load('assets/fonts/RobotoMono-Bold.ttf');
    _fontRegular = pw.Font.ttf(fontDataReg);
    _fontBold = pw.Font.ttf(fontDataBold);
  }

  static Future<Uint8List> generateLabelPdf({
    required List<LabelData> labelsOnPage,
    required double pageWidthMm,
    required double pageHeightMm,
    bool forceWhiteBackground = false,
    LabelTemplateModel? settings,
    bool? isRetailMode,
  }) async {
    await _ensureFontsLoaded();

    LabelTemplateModel templateSettings = settings ?? LabelTemplateModel();
    if (settings == null) {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('label_template_settings');
      if (jsonStr != null) {
        templateSettings = LabelTemplateModel.fromJson(jsonStr);
      }
    }
    if (settings != null) templateSettings = settings;

    final bool isRetail = isRetailMode ?? false;
    final int columns = templateSettings.labelColumns;

    final pdf = pw.Document();
    final double totalWidthPoint = pageWidthMm * 2.83465;
    final double heightPoint = pageHeightMm * 2.83465;

    final double gapPoint = (columns > 1) ? (2.0 * 2.83465) : 0;
    final double singleLabelWidthPoint = (totalWidthPoint - (gapPoint * (columns - 1))) / columns;

    final pageFormat = PdfPageFormat(totalWidthPoint, heightPoint, marginAll: 0.0);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          return pw.Container(
            color: forceWhiteBackground ? PdfColors.white : null,
            width: totalWidthPoint,
            height: heightPoint,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center, // Căn giữa ngang
              children: List.generate(columns, (index) {
                if (index < labelsOnPage.length) {
                  return pw.Row(
                    children: [
                      _buildLabelContent(
                          labelsOnPage[index],
                          singleLabelWidthPoint,
                          heightPoint,
                          columns > 1,
                          templateSettings,
                          isRetail
                      ),
                      if (index < columns - 1) pw.SizedBox(width: gapPoint),
                    ],
                  );
                } else {
                  return pw.Row(
                    children: [
                      pw.Container(width: singleLabelWidthPoint, height: heightPoint),
                      if (index < columns - 1) pw.SizedBox(width: gapPoint),
                    ],
                  );
                }
              }),
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildLabelContent(
      LabelData data, double w, double h, bool isMultiColumn, LabelTemplateModel s, bool isRetail) {

    final double marginTop = s.marginTop * 2.83465;
    final double marginBottom = s.marginBottom * 2.83465;
    final double marginLeft = s.marginLeft * 2.83465;
    final double marginRight = s.marginRight * 2.83465;

    return pw.Container(
      width: w,
      height: h,
      padding: pw.EdgeInsets.fromLTRB(marginLeft, marginTop, marginRight, marginBottom),
      decoration: isMultiColumn ? const pw.BoxDecoration(
          border: pw.Border(right: pw.BorderSide(width: 0.5, style: pw.BorderStyle.dashed, color: PdfColors.grey300))
      ) : null,
      child: isRetail
          ? _buildRetailLayout(data, s)
          : _buildFnBLayout(data, s),
    );
  }

  // --- LAYOUT 1: FnB ---
  static pw.Widget _buildFnBLayout(LabelData data, LabelTemplateModel s) {
    final currencyFormat = NumberFormat('#,##0');
    final bool isBillLabel = data.tableName.startsWith('BILL');
    final String timeString = isBillLabel
        ? DateFormat('HH:mm').format(data.createdAt)
        : DateFormat('HH:mm dd/MM').format(data.createdAt);

    List<String> noteParts = [];
    if (data.item.toppings.isNotEmpty) {
      final toppingStr = data.item.toppings.entries.map((e) => "${e.key.productName} x${formatNumber(e.value)}").join('; ');
      noteParts.add(toppingStr);
    }
    if (data.item.note != null && data.item.note!.isNotEmpty) noteParts.add(data.item.note!);
    final String fullNoteString = noteParts.join('; ');

    final String productName = data.item.selectedUnit.isNotEmpty
        ? "${data.item.product.productName} (${data.item.selectedUnit})"
        : data.item.product.productName;

    return pw.Column(
      // SỬA: Dùng center để khối nội dung trôi theo margin
      mainAxisAlignment: pw.MainAxisAlignment.center,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 1. Header
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(child: pw.Text(data.tableName, style: pw.TextStyle(font: s.fnbHeaderBold ? _fontBold : _fontRegular, fontSize: s.fnbHeaderSize), maxLines: 1, overflow: pw.TextOverflow.clip)),
                pw.Text(timeString, style: pw.TextStyle(font: s.fnbTimeBold ? _fontBold : _fontRegular, fontSize: s.fnbTimeSize)),
              ],
            ),
            pw.Divider(height: 2, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),
          ],
        ),

        // SỬA: Spacer giúp đẩy Header lên đỉnh và Footer xuống đáy nếu còn chỗ trống
        pw.Spacer(),

        // 2. Center
        pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                  productName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: s.fnbProductBold ? _fontBold : _fontRegular, fontSize: s.fnbProductSize),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip
              ),
              if (fullNoteString.isNotEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 1),
                  child: pw.Text(
                      fullNoteString,
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: s.fnbNoteBold ? _fontBold : _fontRegular, fontSize: s.fnbNoteSize),
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip
                  ),
                ),
            ],
          ),
        ),

        // SỬA: Spacer thứ 2
        pw.Spacer(),

        // 3. Footer
        pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.Divider(height: 2, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(currencyFormat.format(data.item.price), style: pw.TextStyle(font: s.fnbFooterBold ? _fontBold : _fontRegular, fontSize: s.fnbFooterSize)),
                pw.Row(
                    children: [
                      pw.Text("${data.copyIndex}/${data.totalCopies}", style: pw.TextStyle(font: s.fnbFooterBold ? _fontBold : _fontRegular, fontSize: s.fnbFooterSize)),
                      pw.SizedBox(width: 2),
                      pw.Text("#${data.dailySeq}", style: pw.TextStyle(font: s.fnbFooterBold ? _fontBold : _fontRegular, fontSize: s.fnbFooterSize)),
                    ]
                )
              ],
            ),
          ],
        ),
      ],
    );
  }

  // --- LAYOUT 2: RETAIL ---
  static pw.Widget _buildRetailLayout(LabelData data, LabelTemplateModel s) {
    final currencyFormat = NumberFormat('#,##0');
    final productCode = data.item.product.productCode ?? 'N/A';
    final barcodeContent = (data.item.product.additionalBarcodes.isNotEmpty)
        ? data.item.product.additionalBarcodes.first
        : productCode;

    return pw.Column(
      // SỬA: Dùng center
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        // 1. Header
        pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                  s.retailStoreName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: s.retailHeaderBold ? _fontBold : _fontRegular, fontSize: s.retailHeaderSize),
                  maxLines: 1, overflow: pw.TextOverflow.clip
              ),
              pw.Divider(height: 2, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),
            ]
        ),

        // Spacer 1
        pw.Spacer(),

        // 2. Center
        pw.Center(
          child: pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Text(
                  data.item.product.productName,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: s.retailProductBold ? _fontBold : _fontRegular, fontSize: s.retailProductSize),
                  maxLines: 2,
                  overflow: pw.TextOverflow.clip
              ),
              pw.SizedBox(height: 2),
              if (barcodeContent.isNotEmpty)
                pw.Container(
                  height: s.retailBarcodeHeight,
                  width: s.retailBarcodeWidth,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: barcodeContent,
                    drawText: false,
                  ),
                ),
              pw.Text(
                  barcodeContent,
                  style: pw.TextStyle(font: s.retailCodeBold ? _fontBold : _fontRegular, fontSize: s.retailCodeSize)
              ),
            ],
          ),
        ),

        // Spacer 2
        pw.Spacer(),

        // 3. Footer
        pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Divider(height: 2, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                      "${currencyFormat.format(data.item.product.sellPrice)}đ",
                      style: pw.TextStyle(font: s.retailPriceBold ? _fontBold : _fontRegular, fontSize: s.retailPriceSize)
                  ),
                  pw.Text(
                      data.item.selectedUnit.isNotEmpty ? data.item.selectedUnit : (data.item.product.unit ?? ''),
                      style: pw.TextStyle(font: s.retailUnitBold ? _fontBold : _fontRegular, fontSize: s.retailPriceSize - 1)
                  ),
                ],
              ),
            ]
        ),
      ],
    );
  }
}

class LabelData {
  final OrderItem item;
  final String tableName;
  final DateTime createdAt;
  final int dailySeq;
  final int copyIndex;
  final int totalCopies;

  LabelData({
    required this.item,
    required this.tableName,
    required this.createdAt,
    required this.dailySeq,
    required this.copyIndex,
    required this.totalCopies,
  });
}