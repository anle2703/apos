// File: lib/helpers/end_of_day_report_printing_helper.dart

import 'dart:typed_data';
import 'package:app_4cash/services/printing_service.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class EndOfDayReportPrintingHelper {

  static Future<Uint8List> generatePdf({
    required Map<String, String> storeInfo,
    required Map<String, dynamic> totalReportData,
    required List<Map<String, dynamic>> shiftReportsData,
  }) async {
    final doc = pw.Document();
    final font = await PrintingService.loadFont();
    final boldFont = await PrintingService.loadFont(isBold: true);

    // Khổ giấy in nhiệt 80mm
    const double printableWidthMm = 72;
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity,
      marginAll: 3 * PdfPageFormat.mm,
    );

    List<pw.Widget> content = [];

    // 1. Header Cửa Hàng
    if (storeInfo['name']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text(storeInfo['name']!.toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 14), textAlign: pw.TextAlign.center)));
    }
    content.add(pw.SizedBox(height: 5));

    // 2. Báo cáo Tổng (Nếu có data)
    if (totalReportData.isNotEmpty) {
      content.addAll(_buildReportSectionWidgets(totalReportData, font, boldFont, isShiftReport: false));
    }

    // 3. Báo cáo các Ca (Nếu có data)
    if (shiftReportsData.isNotEmpty) {
      if (totalReportData.isNotEmpty) {
        content.add(pw.SizedBox(height: 10));
        content.add(pw.Header(level: 1, text: 'CHI TIẾT CA', textStyle: pw.TextStyle(font: boldFont, fontSize: 12)));
        content.add(pw.Divider(height: 1, thickness: 1, borderStyle: pw.BorderStyle.dashed));
        content.add(pw.SizedBox(height: 5));
      }
      for (int i = 0; i < shiftReportsData.length; i++) {
        final shiftData = shiftReportsData[i];
        content.addAll(_buildReportSectionWidgets(shiftData, font, boldFont, isShiftReport: true));
        // Kẻ dòng đứt đoạn giữa các ca
        if (i < shiftReportsData.length - 1) {
          content.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 10),
            child: pw.Divider(height: 1, thickness: 1, borderStyle: pw.BorderStyle.dashed),
          ));
        }
      }
    }

    // Footer
    content.add(pw.SizedBox(height: 10));
    content.add(pw.Center(child: pw.Text('--- Phần mềm quản lý bán hàng APOS---', style: pw.TextStyle(font: font, fontSize: 9, fontStyle: pw.FontStyle.italic))));

    doc.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: content,
          );
        },
      ),
    );
    return doc.save();
  }

  static List<pw.Widget> _buildReportSectionWidgets(
      Map<String, dynamic> data,
      pw.Font ttf,
      pw.Font boldTtf,
      { bool isShiftReport = false }
      ) {

    double safeParseDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is num) return val.toDouble();
      if (val is String) return double.tryParse(val) ?? 0.0;
      return 0.0;
    }

    final String reportTitle = data['reportTitle'] ?? 'BÁO CÁO';
    final String timeRange = (data['timeRange'] as String?) ?? '';
    final String employeeName = data['employeeName'] ?? '';

    List<pw.Widget> widgets = [
      pw.Center(child: pw.Text(reportTitle, style: pw.TextStyle(font: boldTtf, fontSize: 12))),
      if (timeRange.isNotEmpty)
        pw.Center(child: pw.Text(timeRange, style: pw.TextStyle(font: ttf, fontSize: 9, fontStyle: pw.FontStyle.italic)))
      else
        pw.Center(child: pw.Text("Ngày in: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}", style: pw.TextStyle(font: ttf, fontSize: 9))),

      if (employeeName.isNotEmpty)
        pw.Center(child: pw.Text("Nhân viên: $employeeName", style: pw.TextStyle(font: ttf, fontSize: 9))),

      // Giảm khoảng cách header
      pw.SizedBox(height: 2),
      pw.Divider(thickness: 1, height: 1, color: PdfColors.black), // Ép chiều cao dòng kẻ đậm
    ];

    // --- PHẦN 1: DOANH SỐ ---
    widgets.add(_buildPdfRow('Đơn hàng', data['totalOrders'], font: ttf, isCurrency: false));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Chiết khấu/SP', data['totalDiscount'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Chiết khấu/Bill', data['totalBillDiscount'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Voucher', data['totalVoucher'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Điểm thưởng', data['totalPointsValue'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Thuế', data['totalTax'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Phụ thu', data['totalSurcharges'], font: ttf));
    widgets.add(_buildDivider());

    final double revenue = safeParseDouble(data['totalRevenue']);
    final double returnRevenue = safeParseDouble(data['totalReturnRevenue']);

    widgets.add(_buildPdfRow('Tổng doanh thu bán', revenue, font: boldTtf));

    if (returnRevenue > 0) {
      widgets.add(_buildDivider());
      widgets.add(_buildPdfRow('(-) Trả hàng', returnRevenue, font: ttf, color: PdfColors.red));
      widgets.add(_buildDivider());
      widgets.add(_buildPdfRow('(=) Doanh thu thuần', revenue - returnRevenue, font: boldTtf, color: PdfColors.blue));
    }

    // --- PHẦN 2: THANH TOÁN ---
    // Giảm khoảng cách tiêu đề mục
    widgets.add(pw.SizedBox(height: 4));
    widgets.add(pw.Text('THANH TOÁN', style: pw.TextStyle(font: boldTtf, fontSize: 10)));
    // Dùng Divider gọn thay vì Divider mặc định
    widgets.add(pw.Divider(thickness: 0.5, height: 0.5, color: PdfColors.black));

    widgets.add(_buildPdfRow('Tiền mặt', data['totalCash'], font: ttf));

    final Map<String, dynamic> paymentMethods = (data['paymentMethods'] as Map<String, dynamic>?) ?? {};
    if (paymentMethods.isNotEmpty) {
      final sortedKeys = paymentMethods.keys.toList()..sort();
      for (var method in sortedKeys) {
        if (method == 'Tiền mặt') continue;
        final double amount = safeParseDouble(paymentMethods[method]);
        if (amount.abs() > 0.001) {
          widgets.add(_buildDivider());
          widgets.add(_buildPdfRow(method, amount, font: ttf));
        }
      }
    } else {
      final double other = safeParseDouble(data['totalOtherPayments']);
      if (other != 0) {
        widgets.add(_buildDivider());
        widgets.add(_buildPdfRow('Thanh toán khác', other, font: ttf));
      }
    }

    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Ghi nợ', data['totalDebt'], font: ttf));

    // --- PHẦN 3: THỰC THU ---
    widgets.add(pw.SizedBox(height: 2));
    // Dòng kẻ đậm trên dưới THỰC THU: Ép height = 1
    widgets.add(pw.Divider(thickness: 1, height: 1, color: PdfColors.black));
    widgets.add(_buildPdfRow('THỰC THU', data['actualRevenue'], font: boldTtf, fontSize: 11));
    widgets.add(pw.Divider(thickness: 1, height: 1, color: PdfColors.black));

    // --- PHẦN 4: SỔ QUỸ ---
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(_buildPdfRow(isShiftReport ? 'Quỹ đầu ca' : 'Quỹ đầu kỳ', data['openingBalance'], font: boldTtf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Thu khác', data['totalOtherRevenue'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Chi khác', data['totalOtherExpense'], font: ttf));

    double closingBalance = safeParseDouble(data['closingBalance']);

    // --- PHẦN 5: TỒN QUỸ ---
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(pw.Divider(thickness: 1, height: 1, color: PdfColors.black));
    widgets.add(_buildPdfRow(isShiftReport ? 'TỒN QUỸ CA' : 'TỒN QUỸ CUỐI KỲ', closingBalance, font: boldTtf, fontSize: 12));
    widgets.add(pw.Divider(thickness: 1, height: 1, color: PdfColors.black));

    return widgets;
  }

  static pw.Widget _buildPdfRow(String label, dynamic value, {pw.Font? font, bool isCurrency = true, bool isBold = false, PdfColor? color, double fontSize = 9}) {
    String displayValue = '0';
    double valDouble = 0.0;
    if (value is num) {valDouble = value.toDouble();}
    else if (value is String) {valDouble = double.tryParse(value) ?? 0.0;}

    if (valDouble.abs() < 0.001) {
      displayValue = isCurrency ? '0' : '0';
    } else {
      displayValue = isCurrency ? formatNumber(valDouble) : formatNumber(valDouble);
    }
    if (isCurrency && valDouble.abs() >= 0.001) displayValue += ' đ';

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: fontSize, color: color)),
          pw.Text(displayValue, style: pw.TextStyle(font: font, fontSize: fontSize, color: color, fontWeight: isBold ? pw.FontWeight.bold : null)),
        ],
      ),
    );
  }

  static pw.Widget _buildDivider() {
    return pw.Divider(
        thickness: 0.5,
        height: 0.5,
        color: PdfColors.grey400,
        borderStyle: pw.BorderStyle.dotted
    );
  }
}