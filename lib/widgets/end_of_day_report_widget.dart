import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../theme/number_utils.dart';
import 'package:collection/collection.dart';

class EndOfDayReportWidget extends StatelessWidget {
  final Map<String, String> storeInfo;
  final Map<String, dynamic> totalReportData;
  final List<Map<String, dynamic>> shiftReportsData;
  final String userName;

  const EndOfDayReportWidget({
    super.key,
    required this.storeInfo,
    required this.totalReportData,
    required this.shiftReportsData,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    const double fontScale = 1.6;
    final now = DateTime.now();

    // Lấy tiêu đề từ data (nếu có), mặc định là BÁO CÁO CUỐI NGÀY
    final String reportTitle = (totalReportData['reportTitle'] as String?)?.toUpperCase() ?? 'BÁO CÁO CUỐI NGÀY';

    // Lấy dữ liệu chi tiết (Sử dụng safe cast)
    final totalOrders = (totalReportData['totalOrders'] as num?)?.toInt() ?? 0;
    final totalDiscount = (totalReportData['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    final totalBillDiscount = (totalReportData['totalBillDiscount'] as num?)?.toDouble() ?? 0.0;
    final totalVoucher = (totalReportData['totalVoucher'] as num?)?.toDouble() ?? 0.0;
    final totalPointsValue = (totalReportData['totalPointsValue'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (totalReportData['totalTax'] as num?)?.toDouble() ?? 0.0;
    final totalSurcharges = (totalReportData['totalSurcharges'] as num?)?.toDouble() ?? 0.0;

    final totalRev = (totalReportData['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final totalCash = (totalReportData['totalCash'] as num?)?.toDouble() ?? 0.0;
    final totalOtherPay = (totalReportData['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;
    final totalDebt = (totalReportData['totalDebt'] as num?)?.toDouble() ?? 0.0;
    final actualRev = (totalReportData['actualRevenue'] as num?)?.toDouble() ?? 0.0;

    final opening = (totalReportData['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final totalOtherRev = (totalReportData['totalOtherRevenue'] as num?)?.toDouble() ?? 0.0;
    final totalExpense = (totalReportData['totalOtherExpense'] as num?)?.toDouble() ?? 0.0;
    final closing = (totalReportData['closingBalance'] as num?)?.toDouble() ?? 0.0;

    final productsMap = (totalReportData['productsSold'] as Map?) ?? {};

    final baseStyle = TextStyle(fontSize: 14 * fontScale, color: Colors.black, fontFamily: 'Roboto', height: 1.2);
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
    final headerStyle = baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16 * fontScale);

    return Container(
      width: 550,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. HEADER
          if (storeInfo['name'] != null)
            Text(storeInfo['name']!.toUpperCase(), textAlign: TextAlign.center, style: headerStyle),
          const SizedBox(height: 16),

          Text(reportTitle, textAlign: TextAlign.center, style: baseStyle.copyWith(fontSize: 18 * fontScale, fontWeight: FontWeight.w900)),
          Text('In lúc: ${DateFormat('HH:mm dd/MM/yyyy').format(now)}', textAlign: TextAlign.center, style: baseStyle),
          Text('Người in: $userName', textAlign: TextAlign.center, style: baseStyle),

          const SizedBox(height: 8),
          const Divider(thickness: 2, color: Colors.black),

          // 2. CHI TIẾT DOANH SỐ (Bổ sung phần này)
          _buildRow('Đơn hàng:', '$totalOrders đơn', baseStyle, boldStyle),
          const Divider(height: 8, thickness: 0.5),
          _buildRow('Chiết khấu/Món:', formatNumber(totalDiscount), baseStyle, baseStyle),
          _buildRow('Chiết khấu/Bill:', formatNumber(totalBillDiscount), baseStyle, baseStyle),
          _buildRow('Voucher:', formatNumber(totalVoucher), baseStyle, baseStyle),
          _buildRow('Điểm thưởng:', formatNumber(totalPointsValue), baseStyle, baseStyle),
          _buildRow('Thuế:', formatNumber(totalTax), baseStyle, baseStyle),
          _buildRow('Phụ thu:', formatNumber(totalSurcharges), baseStyle, baseStyle),

          const Divider(height: 16, thickness: 1.5, color: Colors.black),

          // 3. DOANH THU & THANH TOÁN
          _buildRow('Doanh Thu Bán Hàng:', formatNumber(totalRev), baseStyle, boldStyle),
          const SizedBox(height: 4),
          _buildRow('- Tiền mặt:', formatNumber(totalCash), baseStyle, baseStyle),
          _buildRow('- Chuyển khoản/Khác:', formatNumber(totalOtherPay), baseStyle, baseStyle),
          _buildRow('- Ghi nợ:', formatNumber(totalDebt), baseStyle, baseStyle),

          const Divider(height: 16, thickness: 1.5, color: Colors.black),
          _buildRow('THỰC THU:', formatNumber(actualRev), baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14 * fontScale), boldStyle.copyWith(fontSize: 14 * fontScale)),

          // 4. SỔ QUỸ
          _buildRow('Quỹ đầu:', formatNumber(opening), baseStyle, boldStyle),
          _buildRow('Thu khác (Phiếu thu):', formatNumber(totalOtherRev), baseStyle, boldStyle),
          _buildRow('Chi khác (Phiếu chi):', formatNumber(totalExpense), baseStyle, boldStyle),

          const SizedBox(height: 8),
          const Divider(thickness: 2, color: Colors.black),
          _buildRow('TỒN QUỸ CUỐI:', formatNumber(closing), baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16 * fontScale), boldStyle.copyWith(fontSize: 16 * fontScale)),
          const Divider(thickness: 2, color: Colors.black),

          // 5. CHI TIẾT CA (Chỉ hiện khi in báo cáo tổng có ca con)
          if (shiftReportsData.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('CHI TIẾT CÁC CA', textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            const Divider(color: Colors.black),
            ...shiftReportsData.map((shift) {
              final sName = shift['employeeName'] ?? 'N/A';
              final sRev = (shift['totalRevenue'] as num?)?.toDouble() ?? 0.0;
              final sOrders = (shift['totalOrders'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('- $sName ($sOrders đơn)', style: baseStyle),
                    Text(formatNumber(sRev), style: boldStyle),
                  ],
                ),
              );
            }),
            const Divider(thickness: 2, color: Colors.black),
          ],

          // 6. DANH SÁCH SẢN PHẨM
          if (productsMap.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('DANH SÁCH SẢN PHẨM', textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(flex: 5, child: Text('Tên món', style: boldStyle)),
                Expanded(flex: 2, child: Text('SL', textAlign: TextAlign.right, style: boldStyle)),
                Expanded(flex: 3, child: Text('T.Tiền', textAlign: TextAlign.right, style: boldStyle)),
              ],
            ),
            const Divider(thickness: 1, color: Colors.black),

            _buildProductList(productsMap, baseStyle, boldStyle),
          ],

          const SizedBox(height: 32),
          const Center(child: Text('--- Kết thúc báo cáo ---', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
        ],
      ),
    );
  }

  // ... (Giữ nguyên hàm _buildProductList và _buildRow cũ)
  Widget _buildProductList(Map productsMap, TextStyle baseStyle, TextStyle boldStyle) {
    final List<dynamic> items = productsMap.values.toList();
    final grouped = groupBy(items, (item) => item['productGroup'] ?? 'Khác');
    final sortedKeys = grouped.keys.toList()..sort();

    return Column(
      children: sortedKeys.map((groupName) {
        final groupItems = grouped[groupName]!;
        final activeItems = groupItems.where((i) => ((i['quantitySold'] ?? 0) as num) > 0).toList();
        if (activeItems.isEmpty) return const SizedBox.shrink();

        final double groupQty = activeItems.fold(0, (sum, i) => sum + ((i['quantitySold'] ?? 0) as num));
        final double groupTotal = activeItems.fold(0, (sum, i) => sum + ((i['totalRevenue'] ?? 0) as num));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(groupName.toString().toUpperCase(), style: boldStyle),
                  Text('${formatNumber(groupQty)} | ${formatNumber(groupTotal)}', style: boldStyle),
                ],
              ),
            ),
            const Divider(height: 4, thickness: 0.5, color: Colors.grey),

            ...activeItems.map((item) {
              final name = item['productName'] ?? 'N/A';
              final qty = (item['quantitySold'] as num?) ?? 0;
              final revenue = (item['totalRevenue'] as num?) ?? 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: Text(name, style: baseStyle)),
                    Expanded(flex: 2, child: Text(formatNumber(qty.toDouble()), textAlign: TextAlign.right, style: baseStyle)),
                    Expanded(flex: 3, child: Text(formatNumber(revenue.toDouble()), textAlign: TextAlign.right, style: baseStyle)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 4),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: labelStyle),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}