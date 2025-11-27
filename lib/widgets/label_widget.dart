import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order_item_model.dart';
import '../models/label_template_model.dart';
import 'package:barcode_widget/barcode_widget.dart';

/// Class chứa đầy đủ thông tin cho 1 con tem để in
class LabelItemData {
  final OrderItem item;
  final String headerTitle; // Tên bàn hoặc Bill Code
  final int index;          // Tem thứ mấy (1, 2...)
  final int total;          // Tổng số tem (3) -> 1/3
  final int dailySeq;       // Số thứ tự đơn trong ngày (#101)

  LabelItemData({
    required this.item,
    required this.headerTitle,
    required this.index,
    required this.total,
    required this.dailySeq,
  });
}

class LabelRowWidget extends StatelessWidget {
  final List<LabelItemData?> items; // Thay OrderItem bằng LabelItemData
  final double widthMm;
  final double heightMm;
  final double gapMm;
  final bool isRetailMode;
  final LabelTemplateModel settings;

  const LabelRowWidget({
    super.key,
    required this.items,
    required this.widthMm,
    required this.heightMm,
    required this.settings,
    this.gapMm = 2.0,
    this.isRetailMode = false,
  });

  @override
  Widget build(BuildContext context) {
    // 203 DPI = 8 dots/mm
    const double dotsPerMm = 8.0;

    final double totalWidthPx = widthMm * dotsPerMm;
    final double heightPx = heightMm * dotsPerMm;

    // Tính toán lại khoảng cách
    final int columnCount = items.length; // Số lượng cột (ví dụ 3)
    final double gapPx = gapMm * dotsPerMm; // Khoảng cách giữa các tem (pixel)

    // LOGIC MỚI: Tính tổng khoảng trắng cần trừ
    // Ví dụ 3 tem thì có 2 khoảng hở ở giữa: (3 - 1) * gap
    final double totalGapWidthPx = (columnCount > 1) ? (columnCount - 1) * gapPx : 0;

    // Chia đều chiều rộng còn lại cho số lượng tem
    final double itemWidthPx = (columnCount > 0)
        ? (totalWidthPx - totalGapWidthPx) / columnCount
        : totalWidthPx;

    return Container(
      width: totalWidthPx,
      height: heightPx,
      color: Colors.white,
      child: Row(
        // Dùng spaceBetween để đẩy các tem ra 2 bên, khoảng hở ở giữa tự động ăn theo gapPx logic
        mainAxisAlignment: (columnCount > 1)
            ? MainAxisAlignment.spaceBetween
            : MainAxisAlignment.center,
        children: items.map((data) {
          if (data == null) {
            // Placeholder nếu thiếu tem (để giữ layout không bị dồn)
            return SizedBox(width: itemWidthPx, height: heightPx);
          }
          return SizedBox(
            width: itemWidthPx,
            height: heightPx,
            child: isRetailMode
                ? _buildRetailLayout(data, itemWidthPx, heightPx)
                : _buildFnBLayout(data, itemWidthPx, heightPx),
          );
        }).toList(),
      ),
    );
  }

  // Chuyển đổi Point (Settings) sang Pixel (Máy in)
  // PDF Preview dùng 72dpi, Máy in dùng 203dpi -> tỉ lệ ~2.83
  double _sf(double sizeFromSettings) => sizeFromSettings * 2.83;
  double _m(double mm) => mm * 8.0;

  // --- LAYOUT 1: F&B (Trà sữa, Cafe) - Chuẩn theo PDF ---
  Widget _buildFnBLayout(LabelItemData data, double w, double h) {
    final s = settings;
    final currencyFormat = NumberFormat('#,##0');
    // Nếu là Bill thì hiển thị giờ hiện tại, nếu là món cũ thì hiển thị giờ order (tùy logic, ở đây lấy giờ hiện tại cho giống PDF)
    final String timeString = DateFormat('HH:mm').format(DateTime.now());

    // Xử lý Note
    List<String> noteParts = [];
    if (data.item.toppings.isNotEmpty) {
      final toppingStr = data.item.toppings.entries
          .map((e) => "${e.key.productName} x${NumberFormat('#,##0.##').format(e.value)}")
          .join('; ');
      noteParts.add(toppingStr);
    }
    if (data.item.note != null && data.item.note!.isNotEmpty) noteParts.add(data.item.note!);
    final String fullNoteString = noteParts.join('; ');

    // Tên món + Đơn vị
    final String productName = data.item.selectedUnit.isNotEmpty
        ? "${data.item.product.productName} (${data.item.selectedUnit})"
        : data.item.product.productName;

    return Container(
      padding: EdgeInsets.fromLTRB(
          _m(s.marginLeft),
          _m(s.marginTop),
          _m(s.marginRight),
          _m(s.marginBottom)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. HEADER (Căn giữa theo chiều dọc của Row)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  data.headerTitle, // Bill Code hoặc Tên bàn
                  style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: _sf(s.fnbHeaderSize),
                      fontWeight: s.fnbHeaderBold ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black,
                      height: 1.0
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                timeString,
                style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _sf(s.fnbTimeSize),
                    fontWeight: s.fnbTimeBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                    height: 1.0
                ),
              ),
            ],
          ),

          // --- SỬA ĐỔI 1: Thay Divider bằng DashedDivider ---
          const DashedDivider(height: 4, thickness: 1.5),

          // 2. SPACER ĐẨY BODY VÀO GIỮA (Giống PDF)
          const Spacer(),

          // 3. BODY (CENTER)
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  productName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _sf(s.fnbProductSize),
                    fontWeight: s.fnbProductBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                    height: 1.1,
                  ),
                ),
                if (fullNoteString.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      fullNoteString,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: _sf(s.fnbNoteSize),
                          fontWeight: s.fnbNoteBold ? FontWeight.bold : FontWeight.normal,
                          fontStyle: FontStyle.italic,
                          color: Colors.black,
                          height: 1.1
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 4. SPACER ĐẨY FOOTER XUỐNG ĐÁY
          const Spacer(),

          // 5. FOOTER
          // --- SỬA ĐỔI 2: Thay Divider bằng DashedDivider ---
          const DashedDivider(height: 4, thickness: 1),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center, // Căn giữa dòng
            children: [
              Text(
                currencyFormat.format(data.item.price),
                style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _sf(s.fnbFooterSize),
                    fontWeight: s.fnbFooterBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                    height: 1.0
                ),
              ),
              Row(
                children: [
                  // Hiển thị 1/3, 2/3...
                  Text(
                      "${data.index}/${data.total}",
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: _sf(s.fnbFooterSize),
                          fontWeight: s.fnbFooterBold ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black,
                          height: 1.0
                      )
                  ),
                  SizedBox(width: 4),
                  // Hiển thị STT ngày (#101)
                  Text(
                      "#${data.dailySeq}",
                      style: TextStyle(
                          fontFamily: 'Roboto',
                          fontSize: _sf(s.fnbFooterSize),
                          fontWeight: s.fnbFooterBold ? FontWeight.bold : FontWeight.normal,
                          color: Colors.black,
                          height: 1.0
                      )
                  ),
                ],
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRetailLayout(LabelItemData data, double w, double h) {
    final s = settings;
    final currencyFormat = NumberFormat('#,##0');
    final productCode = data.item.product.productCode ?? '000000';
    final barcodeContent = (data.item.product.additionalBarcodes.isNotEmpty)
        ? data.item.product.additionalBarcodes.first
        : productCode;

    return Container(
      padding: EdgeInsets.fromLTRB(
          _m(s.marginLeft),
          _m(s.marginTop),
          _m(s.marginRight),
          _m(s.marginBottom)
      ),
      child: Column(
        children: [
          Text(
            s.retailStoreName.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: _sf(s.retailHeaderSize),
                fontWeight: s.retailHeaderBold ? FontWeight.bold : FontWeight.normal,
                color: Colors.black,
                height: 1.0
            ),
            maxLines: 1, overflow: TextOverflow.ellipsis,
          ),

          // --- SỬA ĐỔI 3: Thay Divider bằng DashedDivider ---
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0),
            child: DashedDivider(height: 1, thickness: 1),
          ),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Text(
                  data.item.product.productName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: _sf(s.retailProductSize),
                      fontWeight: s.retailProductBold ? FontWeight.bold : FontWeight.normal,
                      color: Colors.black,
                      height: 1.1
                  ),
                ),

                SizedBox(
                  height: _sf(s.retailBarcodeHeight) * 0.7,
                  width: w * 0.9,
                  child: BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: barcodeContent,
                    drawText: false,
                    color: Colors.black,
                  ),
                ),

                Text(
                    barcodeContent,
                    style: TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: _sf(s.retailCodeSize),
                        fontWeight: s.retailCodeBold ? FontWeight.bold : FontWeight.normal,
                        color: Colors.black,
                        height: 1.0
                    )
                ),
              ],
            ),
          ),

          // --- SỬA ĐỔI 4: Thay Divider bằng DashedDivider ---
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 2.0),
            child: DashedDivider(height: 1, thickness: 1),
          ),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                "${currencyFormat.format(data.item.product.sellPrice)}đ",
                style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _sf(s.retailPriceSize),
                    fontWeight: s.retailPriceBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                    height: 1.0
                ),
              ),
              Text(
                data.item.selectedUnit.isNotEmpty ? data.item.selectedUnit : (data.item.product.unit ?? ''),
                style: TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: _sf(s.retailPriceSize) * 0.8,
                    fontWeight: s.retailUnitBold ? FontWeight.bold : FontWeight.normal,
                    color: Colors.black,
                    height: 1.0
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- WIDGET MỚI: TẠO NÉT ĐỨT ---
class DashedDivider extends StatelessWidget {
  final double height;
  final Color color;
  final double thickness;
  final double dashWidth;
  final double dashSpace;

  const DashedDivider({
    super.key,
    this.height = 1.0,
    this.color = Colors.black,
    this.thickness = 1.0,
    this.dashWidth = 3.0,
    this.dashSpace = 3.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final boxWidth = constraints.constrainWidth();
          final dashCount = (boxWidth / (dashWidth + dashSpace)).floor();
          return Flex(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            direction: Axis.horizontal,
            children: List.generate(dashCount, (_) {
              return SizedBox(
                width: dashWidth,
                height: thickness,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: color),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}