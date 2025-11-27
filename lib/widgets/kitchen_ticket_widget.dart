import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_item_model.dart';
import '../models/receipt_template_model.dart';
import '../theme/string_extensions.dart';

class KitchenTicketWidget extends StatelessWidget {
  final String title;
  final String tableName;
  final List<OrderItem> items;
  final String userName;
  final String? customerName;
  final bool isCancelTicket;
  final ReceiptTemplateModel? templateSettings;

  const KitchenTicketWidget({
    super.key,
    required this.title,
    required this.tableName,
    required this.items,
    required this.userName,
    this.customerName,
    required this.isCancelTicket,
    this.templateSettings,
  });

  @override
  Widget build(BuildContext context) {
    final settings = templateSettings ?? ReceiptTemplateModel();
    const double fontScale = 1.8;
    final baseTextStyle = TextStyle(color: Colors.black, fontFamily: 'Roboto', height: 1.1);
    final boldTextStyle = baseTextStyle.copyWith(fontWeight: FontWeight.w900);
    final italicTextStyle = baseTextStyle.copyWith(fontStyle: FontStyle.italic);
    final quantityFormat = NumberFormat('#,##0.##');

    // Font Sizes
    final double fsTitle = settings.kitchenTitleSize * fontScale;
    final double fsInfo = settings.kitchenInfoSize * fontScale;
    final double fsHeader = settings.kitchenTableHeaderSize * fontScale;
    final double fsItemName = settings.kitchenItemNameSize * fontScale;
    final double fsQty = settings.kitchenQtySize * fontScale;
    final double fsNote = settings.kitchenNoteSize * fontScale;

    return Container(
      width: 550,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text('$title - $tableName', style: boldTextStyle.copyWith(fontSize: fsTitle), textAlign: TextAlign.center)),
          const SizedBox(height: 16),

          // --- SỬA: Căn 2 bên (Label Trái - Value Phải) như Bill ---
          if (settings.kitchenShowTime)
            _buildInfoRow('Thời gian:', DateFormat('HH:mm dd/MM').format(DateTime.now()), baseTextStyle.copyWith(fontSize: fsInfo)),

          if (settings.kitchenShowStaff)
            _buildInfoRow('NV:', userName, baseTextStyle.copyWith(fontSize: fsInfo)),

          if (settings.kitchenShowCustomer && customerName != null)
            _buildInfoRow('KH:', customerName!, baseTextStyle.copyWith(fontSize: fsInfo)),
          // ---------------------------------------------------------

          const SizedBox(height: 16),

          // Header Bảng
          Container(
            decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(width: 2, color: Colors.black),
                  bottom: BorderSide(width: 2, color: Colors.black),
                )
            ),
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 50, child: Text('STT', style: boldTextStyle.copyWith(fontSize: fsHeader))),
              Expanded(child: Text('Tên Món', style: boldTextStyle.copyWith(fontSize: fsHeader), textAlign: TextAlign.center)),
              SizedBox(width: 60, child: Text('SL', style: boldTextStyle.copyWith(fontSize: fsHeader), textAlign: TextAlign.right))
            ]),
          ),

          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value;
            final double qty = item.quantity;
            if (qty == 0) return const SizedBox.shrink();

            TextStyle itemStyle = boldTextStyle.copyWith(fontSize: fsItemName);
            if (isCancelTicket) itemStyle = itemStyle.copyWith(decoration: TextDecoration.lineThrough);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 35, child: Text('${i + 1}.', style: boldTextStyle.copyWith(fontSize: fsItemName))),
                        Expanded(
                            child: Text(
                                '${item.product.productName}${item.selectedUnit.isNotEmpty ? " (${item.selectedUnit})" : ""}',
                                style: itemStyle
                            )
                        ),
                        SizedBox(
                            width: 60,
                            child: Text(
                                isCancelTicket ? '-${quantityFormat.format(qty)}' : quantityFormat.format(qty),
                                style: boldTextStyle.copyWith(fontSize: fsQty),
                                textAlign: TextAlign.right
                            )
                        ),
                      ]
                  ),
                  if (item.note.nullIfEmpty != null)
                    Padding(padding: const EdgeInsets.only(left: 35), child: Text('(${item.note!})', style: italicTextStyle.copyWith(fontSize: fsNote))),

                  if (item.toppings.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(left: 35),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: item.toppings.entries.map((e) =>
                                Text('+${e.key.productName} x${quantityFormat.format(e.value)}', style: italicTextStyle.copyWith(fontSize: fsNote))
                            ).toList()
                        )
                    ),

                  const SizedBox(height: 8),
                  const Divider(thickness: 1, color: Colors.black, height: 12)
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // Helper căn lề 2 bên
  Widget _buildInfoRow(String label, String value, TextStyle style) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: style),
          Expanded(
            child: Text(value, textAlign: TextAlign.right, style: style),
          ),
        ],
      ),
    );
  }
}