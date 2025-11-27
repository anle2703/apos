import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/cash_flow_transaction_model.dart';
import '../theme/number_utils.dart';

class CashFlowTicketWidget extends StatelessWidget {
  final Map<String, String> storeInfo;
  final CashFlowTransaction transaction;
  final String userName;

  const CashFlowTicketWidget({
    super.key,
    required this.storeInfo,
    required this.transaction,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    const double fontScale = 1.6;
    final bool isRevenue = transaction.type == TransactionType.revenue;

    final title = isRevenue ? 'PHIẾU THU' : 'PHIẾU CHI';
    final partnerLabel = isRevenue ? 'Người nộp:' : 'ĐV nhận:';
    final partnerName = transaction.customerName ?? transaction.supplierName ?? 'Khách lẻ';

    // Xử lý mã phiếu hiển thị (Bỏ prefix storeId nếu có)
    final displayId = transaction.id.contains('_') ? transaction.id.split('_').last : transaction.id;

    // Style
    final baseTextStyle = TextStyle(color: Colors.black, fontFamily: 'Roboto', height: 1.2, fontSize: 14 * fontScale);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.bold);
    final headerStyle = baseTextStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16 * fontScale);
    final titleStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w900, fontSize: 18 * fontScale);

    return Container(
      width: 550,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HEADER CỬA HÀNG
          if (storeInfo['name'] != null)
            Text(storeInfo['name']!.toUpperCase(), textAlign: TextAlign.center, style: headerStyle),
          if (storeInfo['address'] != null)
            Text(storeInfo['address']!, textAlign: TextAlign.center, style: baseTextStyle),
          if (storeInfo['phone'] != null)
            Text('SĐT: ${storeInfo['phone']}', textAlign: TextAlign.center, style: baseTextStyle),

          const SizedBox(height: 16),

          // 2. TIÊU ĐỀ - MÃ - THỜI GIAN (CENTER)
          Text(title, textAlign: TextAlign.center, style: titleStyle),
          Text('Mã: $displayId', textAlign: TextAlign.center, style: baseTextStyle),
          Text('Thời gian: ${DateFormat('HH:mm dd/MM/yyyy').format(transaction.date)}', textAlign: TextAlign.center, style: baseTextStyle),

          const SizedBox(height: 16),
          const Divider(thickness: 1.5, color: Colors.black),
          const SizedBox(height: 8),

          // 3. THÔNG TIN CHI TIẾT (Lề Trái - Lề Phải)
          _buildRow('Người tạo:', userName, baseTextStyle, baseTextStyle),
          _buildRow(partnerLabel, partnerName, baseTextStyle, baseTextStyle),
          _buildRow('Nội dung:', transaction.reason, baseTextStyle, baseTextStyle),
          _buildRow('Hình thức:', transaction.paymentMethod, baseTextStyle, baseTextStyle),

          if (transaction.note != null && transaction.note!.isNotEmpty)
            _buildRow('Ghi chú:', transaction.note!, baseTextStyle, boldTextStyle),

          const SizedBox(height: 12),
          const Divider(thickness: 1.5, color: Colors.black),
          const SizedBox(height: 8),

          // 4. TỔNG TIỀN
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('TỔNG TIỀN:', style: boldTextStyle.copyWith(fontSize: 16 * fontScale)),
              Text('${formatNumber(transaction.amount)} đ', style: boldTextStyle.copyWith(fontSize: 18 * fontScale)),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle)),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: valueStyle),
          ),
        ],
      ),
    );
  }
}