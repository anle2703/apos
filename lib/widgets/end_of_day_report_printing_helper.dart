import 'dart:typed_data';
import 'package:app_4cash/services/printing_service.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';

class EndOfDayReportPrintingHelper {

  static Future<Uint8List> generatePdf({
    required Map<String, String> storeInfo,
    required Map<String, dynamic> totalReportData,
    required List<Map<String, dynamic>> shiftReportsData,
  }) async {
    final doc = pw.Document();
    final font = await PrintingService.loadFont();
    final boldFont = await PrintingService.loadFont(isBold: true);

    const double printableWidthMm = 72; // Khổ giấy in nhiệt 80mm
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
    if (storeInfo['address']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text(storeInfo['address']!, style: pw.TextStyle(font: font, fontSize: 9), textAlign: pw.TextAlign.center)));
    }
    if (storeInfo['phone']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text('Hotline: ${storeInfo['phone']!}', style: pw.TextStyle(font: font, fontSize: 9))));
    }
    content.add(pw.SizedBox(height: 5));
    content.add(pw.Divider(thickness: 1));

    // 2. Báo cáo Tổng
    if (totalReportData.isNotEmpty) {
      content.addAll(_buildReportSectionWidgets(totalReportData, font, boldFont, isShiftReport: false));
    }

    // 3. Báo cáo các Ca
    if (shiftReportsData.isNotEmpty) {
      if (totalReportData.isNotEmpty) {
        content.add(pw.SizedBox(height: 15));
        content.add(pw.Header(level: 1, text: 'CHI TIẾT CA', textStyle: pw.TextStyle(font: boldFont, fontSize: 12)));
        content.add(pw.Divider(height: 1, thickness: 1, borderStyle: pw.BorderStyle.dashed));
        content.add(pw.SizedBox(height: 5));
      }
      for (int i = 0; i < shiftReportsData.length; i++) {
        final shiftData = shiftReportsData[i];
        content.addAll(_buildReportSectionWidgets(shiftData, font, boldFont, isShiftReport: true));
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
    content.add(pw.Center(child: pw.Text('--- Cảm ơn quý khách ---', style: pw.TextStyle(font: font, fontSize: 9, fontStyle: pw.FontStyle.italic))));

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

  static pw.Widget _buildPdfRow(String label, dynamic value, {
    pw.Font? font,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    bool isCurrency = true,
    PdfColor? color,
    double fontSize = 9,
  }) {
    String valueString;
    if (value is num) {
      if (value.abs() < 0.001) {
        valueString = isCurrency ? '0 đ' : '0';
      } else {
        valueString = isCurrency ? '${formatNumber(value.toDouble())} đ' : formatNumber(value.toDouble());
      }
    } else {
      valueString = value.toString();
    }

    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(child: pw.Text(label, style: pw.TextStyle(font: font, fontSize: fontSize, color: color, fontWeight: fontWeight))),
          pw.Text(valueString, style: pw.TextStyle(font: font, fontSize: fontSize, fontWeight: fontWeight, color: color)),
        ],
      ),
    );
  }

  static pw.Widget _buildDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Divider(height: 1, thickness: 0.5, color: PdfColors.grey500),
    );
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

    final DateFormat timeFormat = DateFormat('dd/MM HH:mm');
    final DateFormat dayFormat = DateFormat('dd/MM/yyyy');

    DateTime? parseDateTime(dynamic dt) {
      if (dt == null) return null;
      if (dt is DateTime) return dt;
      if (dt is String) return DateTime.tryParse(dt);
      if (dt is Timestamp) return dt.toDate();
      return null;
    }

    final DateTime? startDate = parseDateTime(data['startDate']);
    final DateTime? endDate = parseDateTime(data['endDate']);
    final DateTime? calculatedStartTime = parseDateTime(data['calculatedStartTime']);
    final DateTime? calculatedEndTime = parseDateTime(data['calculatedEndTime']);

    String timeRangeInfo = "";
    if (!isShiftReport && startDate != null && endDate != null) {
      if (startDate.day == endDate.day) {
        timeRangeInfo = "Ngày: ${dayFormat.format(startDate)}";
      } else {
        timeRangeInfo = "${dayFormat.format(startDate)} - ${dayFormat.format(endDate)}";
      }
    } else if (isShiftReport && calculatedStartTime != null) {
      timeRangeInfo = "Ca: ${timeFormat.format(calculatedStartTime)}";
      if (calculatedEndTime != null) timeRangeInfo += " - ${timeFormat.format(calculatedEndTime)}";
    }

    final String reportTitle = data['reportTitle'] ?? 'BÁO CÁO';
    final String employeeName = data['employeeName'] ?? '';

    List<pw.Widget> widgets = [
      pw.Center(child: pw.Text(reportTitle, style: pw.TextStyle(font: boldTtf, fontSize: 12))),
      if (timeRangeInfo.isNotEmpty)
        pw.Center(child: pw.Text(timeRangeInfo, style: pw.TextStyle(font: ttf, fontSize: 9))),
      if (employeeName.isNotEmpty)
        pw.Center(child: pw.Text("Nhân viên: $employeeName", style: pw.TextStyle(font: ttf, fontSize: 9))),
      pw.SizedBox(height: 5),
      pw.Divider(thickness: 1, color: PdfColors.black),
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
    widgets.add(pw.SizedBox(height: 10));
    widgets.add(pw.Text('THANH TOÁN', style: pw.TextStyle(font: boldTtf, fontSize: 10)));
    widgets.add(pw.Divider(thickness: 0.5));

    // Tiền mặt
    widgets.add(_buildPdfRow('Tiền mặt', data['totalCash'], font: ttf));

    // Các phương thức khác
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

    widgets.add(pw.SizedBox(height: 5));
    widgets.add(pw.Divider(thickness: 1));
    widgets.add(_buildPdfRow('THỰC THU', data['actualRevenue'], font: boldTtf, fontSize: 11));
    widgets.add(pw.Divider(thickness: 1));

    // --- PHẦN 3: SỔ QUỸ ---
    widgets.add(pw.SizedBox(height: 5));
    widgets.add(_buildPdfRow(isShiftReport ? 'Quỹ đầu ca' : 'Quỹ đầu kỳ', data['openingBalance'], font: boldTtf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Thu khác', data['totalOtherRevenue'], font: ttf));
    widgets.add(_buildDivider());
    widgets.add(_buildPdfRow('Chi khác', data['totalOtherExpense'], font: ttf));

    // Tính toán Tồn quỹ
    double closingBalance = safeParseDouble(data['closingBalance']);

    widgets.add(pw.SizedBox(height: 5));
    widgets.add(pw.Divider(thickness: 1));
    widgets.add(_buildPdfRow(isShiftReport ? 'TỒN QUỸ CA' : 'TỒN QUỸ CUỐI KỲ', closingBalance, font: boldTtf, fontSize: 12));
    widgets.add(pw.Divider(thickness: 1));

    // --- PHẦN 4: SẢN PHẨM (Nếu cần in list sản phẩm vào PDF) ---
    // (Tuỳ chọn: Nếu bạn muốn in cả danh sách sản phẩm như ảnh chụp)
    /*
    final products = data['productsSold'] as Map<String, dynamic>? ?? {};
    if (products.isNotEmpty) {
       widgets.add(pw.SizedBox(height: 10));
       widgets.add(pw.Center(child: pw.Text('SẢN PHẨM ĐÃ BÁN', style: pw.TextStyle(font: boldTtf, fontSize: 10))));
       widgets.add(pw.Divider());
       // ... Loop logic tương tự widget ...
    }
    */

    return widgets;
  }
}