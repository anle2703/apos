// TỆP ĐÃ SỬA: lib/widgets/end_of_day_report_printing_helper.dart

import 'dart:typed_data';
import 'package:app_4cash/services/printing_service.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:cloud_firestore/cloud_firestore.dart';

class EndOfDayReportPrintingHelper {

  // Hàm chính để tạo PDF
  static Future<Uint8List> generatePdf({
    required Map<String, String> storeInfo,
    required Map<String, dynamic> totalReportData,
    required List<Map<String, dynamic>> shiftReportsData,
  }) async {
    final doc = pw.Document();
    final font = await PrintingService.loadFont();
    final boldFont = await PrintingService.loadFont(isBold: true);

    // --- SỬA LỖI IN TRẮNG: Dùng định dạng cuộn dài vô tận ---
    const double printableWidthMm = 72; // Giống bill
    final pageFormat = PdfPageFormat(
      printableWidthMm * PdfPageFormat.mm,
      double.infinity, // Quan trọng: Dùng infinity
      marginAll: 3 * PdfPageFormat.mm, // Giống bill
    );

    // Xây dựng nội dung
    List<pw.Widget> content = [];

    // 1. Thêm thông tin cửa hàng
    if (storeInfo['name']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text(storeInfo['name']!, style: pw.TextStyle(font: boldFont, fontSize: 16))));}
    if (storeInfo['address']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text(storeInfo['address']!, style: pw.TextStyle(font: font, fontSize: 10), textAlign: pw.TextAlign.center)));}
    if (storeInfo['phone']?.isNotEmpty == true){
      content.add(pw.Center(child: pw.Text('ĐT: ${storeInfo['phone']!}', style: pw.TextStyle(font: font, fontSize: 10))));}
    content.add(pw.SizedBox(height: 8));

    // 2. Thêm báo cáo tổng
    if (totalReportData.isNotEmpty) {
      content.addAll(_buildReportSectionWidgets(totalReportData, font, boldFont, isShiftReport: false));
    }

    // 3. Thêm báo cáo ca
    if (shiftReportsData.isNotEmpty) {
      if (totalReportData.isNotEmpty) {
        content.add(pw.SizedBox(height: 15));
        // [SỬA] Dùng divider thay cho text "BÁO CÁO CHI TIẾT"
        content.add(pw.Divider(height: 1, thickness: 1.5, borderStyle: pw.BorderStyle.solid));
        content.add(pw.SizedBox(height: 15));
      }
      for (int i = 0; i < shiftReportsData.length; i++) {
        final shiftData = shiftReportsData[i];
        content.addAll(_buildReportSectionWidgets(shiftData, font, boldFont, isShiftReport: true));
        if (i < shiftReportsData.length - 1) {
          content.add(pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 15),
            // [SỬA] Dùng divider dày hơn để phân tách các ca
            child: pw.Divider(height: 1, thickness: 1.5, borderStyle: pw.BorderStyle.solid),
          ));
        }
      }
    }

    // Thêm vào trang
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

  // [THÊM MỚI] Hàm helper để tạo dòng thời gian (HH:mm dd/MM)
  static String _buildPdfTimeRangeString(DateTime start, DateTime end) {
    // Dùng format giống như bạn cung cấp
    final DateFormat formatter = DateFormat('HH:mm dd/MM');
    final String startTime = formatter.format(start);
    final String endTime;

    if (end.isAfter(DateTime.now())) {
      endTime = formatter.format(DateTime.now());
    } else {
      endTime = formatter.format(end);
    }
    return "($startTime - $endTime)";
  }

  // [THÊM MỚI] Hàm helper để tạo các tiêu đề phụ rõ ràng
  static pw.Widget _buildPdfSubHeader(String title, pw.Font boldFont, {bool showDivider = true}) {
    return pw.Padding(
        padding: pw.EdgeInsets.only(top: showDivider ? 8 : 4, bottom: 4),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              if (showDivider)
                pw.Divider(height: 6, thickness: 1, borderStyle: pw.BorderStyle.dashed),
              pw.Text(title, style: pw.TextStyle(font: boldFont, fontSize: 10)),
            ]
        )
    );
  }

  // --- Hàm helper xây dựng giao diện (Lấy từ file end_of_day_report_tab.dart) ---
  static pw.Widget _buildPdfRow(String label, dynamic value, {
    pw.Font? font,
    pw.FontWeight fontWeight = pw.FontWeight.normal,
    bool isCurrency = true,
  }) {
    String valueString;
    if (value is double) {
      valueString = isCurrency ? '${formatNumber(value)} đ' : formatNumber(value);
    } else if (value is int) {
      valueString = isCurrency ? '${formatNumber(value.toDouble())} đ' : value.toString();
    } else {
      valueString = value.toString();
    }
    if (label.length > 25) {
      label = '${label.substring(0, 22)}...';
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text(valueString, style: pw.TextStyle(font: font, fontSize: 9, fontWeight: fontWeight)),
        ],
      ),
    );
  }

  // [SỬA ĐỔI TOÀN BỘ] Hàm xây dựng layout cho từng mục
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

    final DateFormat dayFormatter = DateFormat('dd/MM/yyyy');

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

    final String dateLine;
    pw.Widget? timeLine;

    if (!isShiftReport) {
      // BÁO CÁO TỔNG
      if (startDate != null && endDate != null) {
        if (startDate.year == endDate.year && startDate.month == endDate.month && startDate.day == endDate.day) {
          dateLine = 'Ngày: ${dayFormatter.format(startDate)}';
        } else {
          dateLine = 'Từ: ${dayFormatter.format(startDate)} đến: ${dayFormatter.format(endDate)}';
        }
      } else {
        dateLine = 'Ngày: N/A';
      }
    } else {
      // BÁO CÁO CA
      if (calculatedStartTime != null) {
        dateLine = 'Ngày: ${dayFormatter.format(calculatedStartTime)}';
        // Nếu có thời gian, tạo dòng timeLine
        if (calculatedEndTime != null) {
          timeLine = pw.Center(
            child: pw.Text(
              _buildPdfTimeRangeString(calculatedStartTime, calculatedEndTime), // Gọi helper mới
              style: pw.TextStyle(font: ttf, fontSize: 9, fontStyle: pw.FontStyle.italic),
              textAlign: pw.TextAlign.center,
            ),
          );
        }
      } else {
        dateLine = 'Ngày: N/A';
      }
    }
    // --- Kết thúc Logic Ngày/Giờ ---

    final String reportTitle = data['reportTitle'] ?? 'BÁO CÁO';

    List<pw.Widget> widgets = [
      pw.Center(
        child: pw.Text(reportTitle, style: pw.TextStyle(font: boldTtf, fontSize: 11)),
      ),
      pw.SizedBox(height: 4),
      // Dòng 1: Ngày
      pw.Center(
        child: pw.Text(dateLine, style: pw.TextStyle(font: ttf, fontSize: 9), textAlign: pw.TextAlign.center),
      ),
      // Dòng 2: Giờ (chỉ hiển thị nếu là báo cáo ca)
      if (timeLine != null)
        timeLine,
    ];

    widgets.add(_buildPdfSubHeader('DOANH SỐ', boldTtf, showDivider: true));
    widgets.add(_buildPdfRow('Đơn hàng', data['totalOrders'], font: ttf, isCurrency: false));
    widgets.add(_buildPdfRow('Chiết khấu', data['totalDiscount'], font: ttf));
    widgets.add(_buildPdfRow('Voucher', data['totalVoucher'], font: ttf));
    widgets.add(_buildPdfRow('Điểm thưởng', data['totalPointsValue'], font: ttf));
    widgets.add(_buildPdfRow('Thuế', data['totalTax'], font: ttf));
    widgets.add(_buildPdfRow('Phụ thu', data['totalSurcharges'], font: ttf));

    // Nhóm 2: Thanh toán
    widgets.add(_buildPdfSubHeader('THANH TOÁN', boldTtf));
    widgets.add(_buildPdfRow('Doanh thu bán hàng', data['totalRevenue'], font: boldTtf));
    widgets.add(_buildPdfRow('Tiền mặt', data['totalCash'], font: ttf));
    widgets.add(_buildPdfRow('Thanh toán khác', data['totalOtherPayments'], font: ttf));
    widgets.add(_buildPdfRow('Ghi nợ', data['totalDebt'], font: ttf));
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dotted));
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(_buildPdfRow('Thực thu', data['actualRevenue'], font: boldTtf));

    // Nhóm 3: Sổ quỹ (Di chuyển logic tính toán ra ngoài)
    double openingBalance = safeParseDouble(data['openingBalance']);
    final double closingBalance = safeParseDouble(data['closingBalance']);

    if (!isShiftReport && openingBalance == 0.0 && closingBalance != 0.0) {

    final double actualRevenue = safeParseDouble(data['actualRevenue']);
    final double otherRevenue = safeParseDouble(data['totalOtherRevenue']);
    final double otherExpense = safeParseDouble(data['totalOtherExpense']);

    openingBalance = closingBalance - actualRevenue - otherRevenue + otherExpense;
    }

    widgets.add(_buildPdfSubHeader('SỔ QUỸ', boldTtf));
    widgets.add(_buildPdfRow(isShiftReport ? 'Quỹ đầu ca' : 'Quỹ đầu kỳ', openingBalance, font: ttf));
    widgets.add(_buildPdfRow('Thu khác', data['totalOtherRevenue'], font: ttf));
    widgets.add(_buildPdfRow('Chi khác', data['totalOtherExpense'], font: ttf));
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(pw.Divider(height: 1, thickness: 0.5, borderStyle: pw.BorderStyle.dotted));
    widgets.add(pw.SizedBox(height: 2));
    widgets.add(_buildPdfRow(isShiftReport ? 'TỒN QUỸ CA' : 'TỒN QUỸ CUỐI KỲ', closingBalance, font: boldTtf));
    return widgets;
  }
}