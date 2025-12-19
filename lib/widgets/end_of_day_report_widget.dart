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
    final String reportTitle = (totalReportData['reportTitle'] as String?)?.toUpperCase() ?? 'BÁO CÁO CUỐI NGÀY';

    // Data parsing
    final totalOrders = (totalReportData['totalOrders'] as num?)?.toInt() ?? 0;
    final totalDiscount = (totalReportData['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    final totalBillDiscount = (totalReportData['totalBillDiscount'] as num?)?.toDouble() ?? 0.0;
    final totalVoucher = (totalReportData['totalVoucher'] as num?)?.toDouble() ?? 0.0;
    final totalPointsValue = (totalReportData['totalPointsValue'] as num?)?.toDouble() ?? 0.0;
    final totalTax = (totalReportData['totalTax'] as num?)?.toDouble() ?? 0.0;
    final totalSurcharges = (totalReportData['totalSurcharges'] as num?)?.toDouble() ?? 0.0;

    // [FIX] Lấy dữ liệu trả hàng
    final totalReturnRevenue = (totalReportData['totalReturnRevenue'] as num?)?.toDouble() ?? 0.0;
    final totalRev = (totalReportData['totalRevenue'] as num?)?.toDouble() ?? 0.0; // Gross

    final totalCash = (totalReportData['totalCash'] as num?)?.toDouble() ?? 0.0;
    final totalOtherPay = (totalReportData['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;
    final paymentMethods = (totalReportData['paymentMethods'] as Map<String, dynamic>?) ?? {};
    final totalDebt = (totalReportData['totalDebt'] as num?)?.toDouble() ?? 0.0;
    final actualRev = (totalReportData['actualRevenue'] as num?)?.toDouble() ?? 0.0;
    final opening = (totalReportData['openingBalance'] as num?)?.toDouble() ?? 0.0;
    final totalOtherRev = (totalReportData['totalOtherRevenue'] as num?)?.toDouble() ?? 0.0;
    final totalExpense = (totalReportData['totalOtherExpense'] as num?)?.toDouble() ?? 0.0;
    final closing = (totalReportData['closingBalance'] as num?)?.toDouble() ?? 0.0;
    final productsMap = (totalReportData['productsSold'] as Map?) ?? {};

    // Styles
    final baseStyle = TextStyle(fontSize: 14 * fontScale, color: Colors.black, fontFamily: 'Roboto', height: 1.2);
    final boldStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
    final headerStyle = baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16 * fontScale);
    final redStyle = baseStyle.copyWith(color: Colors.red);
    final primaryBoldStyle = boldStyle.copyWith(color: Colors.blue); // Giả lập màu primary

    return Container(
      width: 550,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // HEADER
          if (storeInfo['name'] != null)
            Text(storeInfo['name']!.toUpperCase(), textAlign: TextAlign.center, style: headerStyle),
          const SizedBox(height: 16),
          Text(reportTitle, textAlign: TextAlign.center, style: baseStyle.copyWith(fontSize: 18 * fontScale, fontWeight: FontWeight.w900)),
          Text('In lúc: ${DateFormat('HH:mm dd/MM/yyyy').format(now)}', textAlign: TextAlign.center, style: baseStyle),
          Text('Người in: $userName', textAlign: TextAlign.center, style: baseStyle),
          const SizedBox(height: 8),
          const Divider(thickness: 2, color: Colors.black),

          // DOANH SỐ
          Text("DOANH SỐ", style: boldStyle),
          const Divider(height: 8, thickness: 0.5),
          _buildRow('Đơn hàng:', '$totalOrders', baseStyle, boldStyle, isCurrency: false),
          _buildRow('Chiết khấu/Món:', formatNumber(totalDiscount), baseStyle, baseStyle),
          _buildRow('Chiết khấu/Bill:', formatNumber(totalBillDiscount), baseStyle, baseStyle),
          _buildRow('Voucher:', formatNumber(totalVoucher), baseStyle, baseStyle),
          _buildRow('Điểm thưởng:', formatNumber(totalPointsValue), baseStyle, baseStyle),
          _buildRow('Thuế:', formatNumber(totalTax), baseStyle, baseStyle),
          _buildRow('Phụ thu:', formatNumber(totalSurcharges), baseStyle, baseStyle),

          // [FIX] Hiển thị Trả hàng
          const Divider(height: 8, thickness: 0.5),
          _buildRow('Tổng doanh thu bán:', formatNumber(totalRev), baseStyle, boldStyle),

          if (totalReturnRevenue > 0) ...[
            const Divider(height: 8, thickness: 0.5),
            _buildRow('(-) Trả hàng:', formatNumber(totalReturnRevenue), redStyle, redStyle.copyWith(fontWeight: FontWeight.bold)),
            const Divider(height: 8, thickness: 0.5),
            _buildRow('(=) Doanh thu thuần:', formatNumber(totalRev - totalReturnRevenue), primaryBoldStyle, primaryBoldStyle),
          ],

          const Divider(height: 16, thickness: 1.5, color: Colors.black),

          // THANH TOÁN
          Text("THANH TOÁN", style: boldStyle),
          const Divider(height: 8, thickness: 0.5),

          // Ưu tiên Tiền mặt lên đầu
          _buildRow('Tiền mặt:', formatNumber(totalCash), baseStyle, baseStyle),

          if (paymentMethods.isNotEmpty) ...[
            ...paymentMethods.entries.sorted((a, b) => a.key.compareTo(b.key)).map((e) {
              if (e.key == 'Tiền mặt') return const SizedBox.shrink();
              final amt = (e.value as num).toDouble();
              if (amt.abs() < 0.001) return const SizedBox.shrink();
              return Column(
                children: [
                  const Divider(height: 8, thickness: 0.5),
                  _buildRow('${e.key}:', formatNumber(amt), baseStyle, baseStyle),
                ],
              );
            }),
          ] else if (totalOtherPay != 0) ...[
            const Divider(height: 8, thickness: 0.5),
            _buildRow('Thanh toán khác:', formatNumber(totalOtherPay), baseStyle, baseStyle),
          ],

          const Divider(height: 8, thickness: 0.5),
          _buildRow('Ghi nợ:', formatNumber(totalDebt), baseStyle, baseStyle),

          const Divider(height: 16, thickness: 1.5, color: Colors.black),
          _buildRow('THỰC THU:', formatNumber(actualRev), baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 14 * fontScale), boldStyle.copyWith(fontSize: 14 * fontScale)),

          // SỔ QUỸ
          Text("SỔ QUỸ", style: boldStyle),
          const Divider(height: 8, thickness: 0.5),
          _buildRow('Quỹ đầu:', formatNumber(opening), baseStyle, boldStyle),
          _buildRow('Thu khác:', formatNumber(totalOtherRev), baseStyle, boldStyle),
          _buildRow('Chi khác:', formatNumber(totalExpense), baseStyle, boldStyle),
          // Trả hàng không hiển thị ở đây để khớp App

          const SizedBox(height: 8),
          const Divider(thickness: 2, color: Colors.black),
          _buildRow('TỒN QUỸ CUỐI:', formatNumber(closing), baseStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16 * fontScale), boldStyle.copyWith(fontSize: 16 * fontScale)),
          const Divider(thickness: 2, color: Colors.black),

          // ... (Phần Chi tiết ca và Sản phẩm giữ nguyên logic cũ) ...
          if (shiftReportsData.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('CHI TIẾT CÁC CA', textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            const Divider(color: Colors.black),
            ...shiftReportsData.map((shift) {
              final sName = shift['employeeName'] ?? 'N/A';
              final sRev = (shift['totalRevenue'] as num?)?.toDouble() ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('- $sName', style: baseStyle),
                    Text(formatNumber(sRev), style: boldStyle),
                  ],
                ),
              );
            }),
            const Divider(thickness: 2, color: Colors.black),
          ],

          // Danh sách sản phẩm...
          if (productsMap.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('DANH SÁCH SẢN PHẨM', textAlign: TextAlign.center, style: headerStyle),
            const SizedBox(height: 8),
            _buildProductList(productsMap, baseStyle, boldStyle),
          ],

          const SizedBox(height: 32),
          const Center(child: Text('--- Cảm ơn và hẹn gặp lại ---', style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
        ],
      ),
    );
  }

  // ... (Giữ nguyên hàm helper _buildRow và _buildProductList)
  Widget _buildRow(String label, String value, TextStyle labelStyle, TextStyle valueStyle, {bool isCurrency = true}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: labelStyle)),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }

  Widget _buildProductList(Map productsMap, TextStyle baseStyle, TextStyle boldStyle) {
    // (Giữ nguyên logic list sản phẩm như file cũ)
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
}