// File: lib/services/label_printing_service.dart

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/order_item_model.dart';
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
    required OrderItem item,
    required String tableName,
    required DateTime createdAt,
    required double widthMm,
    required double heightMm,
    required int dailySeq,
    int copyIndex = 1,
    int totalCopies = 1,
    bool forceWhiteBackground = false,
  }) async {
    await _ensureFontsLoaded();
    final pdf = pw.Document();

    final double widthPoint = widthMm * 2.83465;
    final double heightPoint = heightMm * 2.83465;

    final pageFormat = PdfPageFormat(
      widthPoint,
      heightPoint,
      marginAll: 0.0,
    );

    final currencyFormat = NumberFormat('#,##0');

    // SỬA: Kiểm tra ký tự # để biết là tem sau thanh toán
    final bool isBillLabel = tableName.startsWith('BILL');
    final String timeString = isBillLabel
        ? DateFormat('HH:mm').format(createdAt)        // Tem thanh toán: Chỉ hiện giờ
        : DateFormat('HH:mm dd/MM').format(createdAt); // Tem báo bếp: Hiện Giờ + Ngày

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (ctx) {
          // --- BƯỚC 1: XỬ LÝ CHUỖI TOPPING & NOTE TRƯỚC ---
          // Gom tất cả vào 1 list string để nối lại, đảm bảo không bị lỗi hiển thị
          List<String> noteParts = [];

          // 1. Xử lý Topping
          if (item.toppings.isNotEmpty) {
            final toppingStr = item.toppings.entries.map((e) =>
            "${e.key.productName} x${formatNumber(e.value)}"
            ).join('; ');
            noteParts.add(toppingStr);
          }

          // 2. Xử lý Note
          if (item.note != null && item.note!.isNotEmpty) {
            noteParts.add(item.note!);
          }

          // Nối lại thành 1 chuỗi duy nhất ngăn cách bởi dấu ;
          final String fullNoteString = noteParts.join('; ');
          // --------------------------------------------------

          return pw.Container(
            color: forceWhiteBackground ? PdfColors.white : null,
            padding: const pw.EdgeInsets.only(
                left: 12.0,
                top: 2.0,
                right: 4.0,
                bottom: 2.0
            ),
            width: widthPoint,
            height: heightPoint,
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // --- HEADER: Tên bàn/BillCode - Thời gian ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(tableName, style: pw.TextStyle(font: _fontBold, fontSize: 8)), // Tăng nhẹ font size lên 9 cho dễ đọc
                    pw.Text(timeString, style: pw.TextStyle(font: _fontRegular, fontSize: 8)),
                  ],
                ),

                pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),

                // --- BODY: Tên món + Topping + Note (Căn giữa) ---
                pw.Expanded(
                  child: pw.Center(
                    child: pw.Column(
                      mainAxisSize: pw.MainAxisSize.min, // Co cụm nội dung lại sát nhau
                      children: [
                        // 1. Tên món
                        pw.Text(
                          item.selectedUnit.isNotEmpty
                              ? "${item.product.productName} (${item.selectedUnit})"
                              : item.product.productName,
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: _fontBold, fontSize: 9),
                          maxLines: 2,
                        ),

                        // 2. Topping & Note (Sử dụng chuỗi đã xử lý ở trên)
                        if (fullNoteString.isNotEmpty)
                          pw.Padding(
                            padding: const pw.EdgeInsets.only(top: 1),
                            child: pw.Text(
                              fullNoteString,
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(font: _fontRegular, fontSize: 8), // Font thường, size 8
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dotted),

                // --- FOOTER: Giá - STT ---
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(currencyFormat.format(item.price), style: pw.TextStyle(font: _fontBold, fontSize: 8)),
                    pw.Row(
                        children: [
                          pw.Text("$copyIndex/$totalCopies", style: pw.TextStyle(font: _fontBold, fontSize: 8)),
                          pw.Text(" #$dailySeq", style: pw.TextStyle(font: _fontBold, fontSize: 8)),
                        ]
                    )
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }
}