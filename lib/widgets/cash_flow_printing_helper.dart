// lib/services/cash_flow_printing_helper.dart

import 'dart:typed_data';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:app_4cash/services/printing_service.dart'; //
import 'package:app_4cash/theme/number_utils.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class CashFlowPrintingHelper {
  static Future<Uint8List> generatePdf({
    required CashFlowTransaction tx,
    required Map<String, String> storeInfo,
    double? openingDebt, //
    double? closingDebt, //
  }) async {
    final pdf = pw.Document();
    // Sử dụng hàm static loadFont đã tạo
    final font = await PrintingService.loadFont();
    final boldFont = await PrintingService.loadFont(isBold: true);
    final italicFont = await PrintingService.loadFont(isItalic: true);


    final title = (tx.type == TransactionType.revenue)
        ? 'PHIẾU THU'
        : 'PHIẾU CHI';

    final partnerLabel = (tx.type == TransactionType.revenue)
        ? 'Người nộp:'
        : 'ĐV nhận:';

    final partnerName = tx.customerName ?? tx.supplierName ?? 'N/A';
    final shortId = tx.id.split('_').last;

    final pageFormat = PdfPageFormat(
      226, // 80mm width
      double.infinity, // Chiều cao tự động (vừa với nội dung)
      marginAll: 14, // 5mm
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- SỬA LẠI FONT SIZE CHO KHỚP VỚI BILL ---
              pw.Center(
                child: pw.Text(
                  storeInfo['name'] ?? 'Tên Cửa Hàng',
                  style: pw.TextStyle(font: boldFont, fontSize: 16), // Sửa từ 12 -> 16
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Center(
                child: pw.Text(
                  storeInfo['address'] ?? '',
                  style: pw.TextStyle(font: font, fontSize: 10), // Sửa từ 9 -> 10
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Center(
                child: pw.Text(
                  storeInfo['phone'] ?? '',
                  style: pw.TextStyle(font: font, fontSize: 10), // Sửa từ 9 -> 10
                  textAlign: pw.TextAlign.center,
                ),
              ),
              // --- KẾT THÚC SỬA FONT ---
              pw.SizedBox(height: 15),

              // 2. Tiêu đề
              pw.Center(
                child: pw.Text(
                  title,
                  style: pw.TextStyle(font: boldFont, fontSize: 14),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  'Mã: $shortId',
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
              ),
              pw.Center(
                child: pw.Text(
                  DateFormat('HH:mm dd/MM/yyyy').format(tx.date),
                  style: pw.TextStyle(font: font, fontSize: 9),
                ),
              ),
              pw.SizedBox(height: 15),

              // 3. Thông tin chi tiết
              _buildInfoRow('Người tạo:', tx.user, font, boldFont),
              _buildInfoRow(partnerLabel, partnerName, font, boldFont),
              _buildInfoRow('Nội dung:', tx.reason, font, boldFont),
              _buildInfoRow('Hình thức:', tx.paymentMethod, font, boldFont),
              if (tx.note != null && tx.note!.isNotEmpty)
                _buildInfoRow('Ghi chú:', tx.note!, font, boldFont),

              pw.SizedBox(height: 10),
              pw.Divider(height: 1, borderStyle: pw.BorderStyle.dashed),
              pw.SizedBox(height: 10),

              // 4. Dư nợ trước (nếu có)
              if (openingDebt != null)
                _buildInfoRow(
                    'Dư nợ trước:',
                    '${formatNumber(openingDebt)} đ',
                    font,
                    boldFont,
                    10
                ),

              // 5. Số tiền
              _buildTotalRow(
                'TỔNG TIỀN:',
                '${formatNumber(tx.amount)} đ',
                boldFont,
                12,
              ),

              // 6. Dư nợ sau (nếu có)
              if (closingDebt != null)
                _buildInfoRow(
                    'Dư nợ sau:',
                    '${formatNumber(closingDebt)} đ',
                    font,
                    boldFont,
                    10
                ),

              pw.SizedBox(height: 15),
              pw.Center(
                  child: pw.Text(
                      'Cảm ơn quý khách!',
                      style: pw.TextStyle(font: italicFont, fontSize: 10)
                  )
              ),
            ],
          );
        },
      ),
    );
    return pdf.save();
  }

  static pw.Widget _buildInfoRow(String label, String value, pw.Font font, pw.Font boldFont, [double fontSize = 10]) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(font: font, fontSize: fontSize),
            softWrap: true,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(font: boldFont, fontSize: fontSize),
              textAlign: pw.TextAlign.right,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildTotalRow(String label, String value, pw.Font boldFont, [double fontSize = 11]) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: boldFont, fontSize: fontSize)),
          pw.Text(value, style: pw.TextStyle(font: boldFont, fontSize: fontSize)),
        ],
      ),
    );
  }
}