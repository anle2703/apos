import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/receipt_template_model.dart';

class TableNotificationWidget extends StatelessWidget {
  final Map<String, String> storeInfo;
  final String actionTitle;
  final String message;
  final String userName;
  final DateTime timestamp;
  final ReceiptTemplateModel? templateSettings;

  const TableNotificationWidget({
    super.key,
    required this.storeInfo,
    required this.actionTitle,
    required this.message,
    required this.userName,
    required this.timestamp,
    this.templateSettings,
  });

  @override
  Widget build(BuildContext context) {
    // Dùng chung setting font size với Bill cho đồng bộ
    final settings = templateSettings ?? ReceiptTemplateModel();
    const double fontScale = 1.8;

    final baseTextStyle = TextStyle(
      color: Colors.black,
      fontFamily: 'Roboto',
      height: 1.1,
      fontSize: settings.billTextSize * fontScale,
    );

    // Style cho Tiêu đề (To, Đậm)
    final titleStyle = baseTextStyle.copyWith(
        fontWeight: FontWeight.w900,
        fontSize: settings.billTitleSize * fontScale
    );

    // Style cho Nội dung chính (To hơn bình thường 1 chút, Đậm)
    final messageStyle = baseTextStyle.copyWith(
        fontWeight: FontWeight.bold,
        fontSize: (settings.billTextSize + 4) * fontScale
    );

    return Container(
      width: 550, // Chuẩn in
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Tiêu đề hành động (CHUYỂN BÀN / GỘP BÀN...)
          Text(actionTitle.toUpperCase(), textAlign: TextAlign.center, style: titleStyle),

          const SizedBox(height: 16),

          // --- SỬA ĐOẠN NÀY: CĂN 2 BÊN (TRÁI - PHẢI) ---
          _buildInfoRow('Nhân viên:', userName, baseTextStyle),
          _buildInfoRow('Thời gian:', DateFormat('HH:mm dd/MM/yyyy').format(timestamp), baseTextStyle),
          // ---------------------------------------------

          const SizedBox(height: 20),

          // MESSAGE (Nội dung chính: Từ bàn A sang B...)
          // Đóng khung để nhân viên dễ nhìn
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: messageStyle,
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // Hàm hỗ trợ tạo dòng Label - Value
  Widget _buildInfoRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2), // Khoảng cách giữa các dòng
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label nằm bên trái
          Text(label, style: style),

          // Value nằm bên phải (đẩy hết sang phải)
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: style
            ),
          ),
        ],
      ),
    );
  }
}