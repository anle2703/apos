import 'dart:convert';

class LabelTemplateModel {
  // --- Cấu hình Kích thước & Bố cục (Mới) ---
  double labelWidth;
  double labelHeight;
  int labelColumns; // 1, 2, hoặc 3 tem trên 1 hàng

  // Căn lề (mm)
  double marginTop;
  double marginBottom;
  double marginLeft;
  double marginRight;

  // --- Cấu hình FnB ---
  double fnbHeaderSize;
  bool fnbHeaderBold;
  double fnbTimeSize; // Mới
  bool fnbTimeBold;   // Mới
  double fnbProductSize;
  bool fnbProductBold;
  double fnbNoteSize;
  bool fnbNoteBold;
  double fnbFooterSize;
  bool fnbFooterBold;

  // --- Cấu hình Bán lẻ (Retail) ---
  String retailStoreName;
  double retailHeaderSize;
  bool retailHeaderBold;
  double retailProductSize;
  bool retailProductBold;
  double retailBarcodeHeight;
  double retailBarcodeWidth;
  double retailCodeSize;
  bool retailCodeBold; // Mới
  double retailPriceSize;
  bool retailPriceBold;
  bool retailUnitBold; // Mới

  LabelTemplateModel({
    this.labelWidth = 50.0,
    this.labelHeight = 30.0,
    this.labelColumns = 1,
    this.marginTop = 0.0,
    this.marginBottom = 2.0,
    this.marginLeft = 2.0,
    this.marginRight = 0.0,
    // FnB
    this.fnbHeaderSize = 8.0,
    this.fnbHeaderBold = true,
    this.fnbTimeSize = 8.0,
    this.fnbTimeBold = true,
    this.fnbProductSize = 9.0,
    this.fnbProductBold = true,
    this.fnbNoteSize = 7.0,
    this.fnbNoteBold = false,
    this.fnbFooterSize = 8.0,
    this.fnbFooterBold = true,
    // Retail
    this.retailStoreName = "Phần mềm APOS",
    this.retailHeaderSize = 7.0,
    this.retailHeaderBold = true,
    this.retailProductSize = 7.0,
    this.retailProductBold = true,
    this.retailBarcodeHeight = 15.0,
    this.retailBarcodeWidth = 70.0,
    this.retailCodeSize = 7.0,
    this.retailCodeBold = true,
    this.retailPriceSize = 8.0,
    this.retailPriceBold = true,
    this.retailUnitBold = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'labelWidth': labelWidth,
      'labelHeight': labelHeight,
      'labelColumns': labelColumns,
      'marginTop': marginTop,
      'marginBottom': marginBottom,
      'marginLeft': marginLeft,
      'marginRight': marginRight,
      'fnbHeaderSize': fnbHeaderSize,
      'fnbHeaderBold': fnbHeaderBold,
      'fnbTimeSize': fnbTimeSize,
      'fnbTimeBold': fnbTimeBold,
      'fnbProductSize': fnbProductSize,
      'fnbProductBold': fnbProductBold,
      'fnbNoteSize': fnbNoteSize,
      'fnbNoteBold': fnbNoteBold,
      'fnbFooterSize': fnbFooterSize,
      'fnbFooterBold': fnbFooterBold,
      'retailStoreName': retailStoreName,
      'retailHeaderSize': retailHeaderSize,
      'retailHeaderBold': retailHeaderBold,
      'retailProductSize': retailProductSize,
      'retailProductBold': retailProductBold,
      'retailBarcodeHeight': retailBarcodeHeight,
      'retailBarcodeWidth': retailBarcodeWidth,
      'retailCodeSize': retailCodeSize,
      'retailCodeBold': retailCodeBold,
      'retailPriceSize': retailPriceSize,
      'retailPriceBold': retailPriceBold,
      'retailUnitBold': retailUnitBold,
    };
  }

  factory LabelTemplateModel.fromJson(String source) {
    final map = json.decode(source);
    return LabelTemplateModel(
      labelWidth: (map['labelWidth'] ?? 50.0).toDouble(),
      labelHeight: (map['labelHeight'] ?? 30.0).toDouble(),
      labelColumns: (map['labelColumns'] ?? 1).toInt(),
      marginTop: (map['marginTop'] ?? 1.0).toDouble(),
      marginBottom: (map['marginBottom'] ?? 1.0).toDouble(),
      marginLeft: (map['marginLeft'] ?? 1.0).toDouble(),
      marginRight: (map['marginRight'] ?? 1.0).toDouble(),
      // FnB
      fnbHeaderSize: (map['fnbHeaderSize'] ?? 7.0).toDouble(),
      fnbHeaderBold: map['fnbHeaderBold'] ?? true,
      fnbTimeSize: (map['fnbTimeSize'] ?? 7.0).toDouble(),
      fnbTimeBold: map['fnbTimeBold'] ?? false,
      fnbProductSize: (map['fnbProductSize'] ?? 9.0).toDouble(),
      fnbProductBold: map['fnbProductBold'] ?? true,
      fnbNoteSize: (map['fnbNoteSize'] ?? 8.0).toDouble(),
      fnbNoteBold: map['fnbNoteBold'] ?? false,
      fnbFooterSize: (map['fnbFooterSize'] ?? 7.0).toDouble(),
      fnbFooterBold: map['fnbFooterBold'] ?? true,
      // Retail
      retailStoreName: map['retailStoreName'] ?? "Cửa Hàng",
      retailHeaderSize: (map['retailHeaderSize'] ?? 7.0).toDouble(),
      retailHeaderBold: map['retailHeaderBold'] ?? true,
      retailProductSize: (map['retailProductSize'] ?? 8.0).toDouble(),
      retailProductBold: map['retailProductBold'] ?? true,
      retailBarcodeHeight: (map['retailBarcodeHeight'] ?? 15.0).toDouble(),
      retailBarcodeWidth: (map['retailBarcodeWidth'] ?? 60.0).toDouble(),
      retailCodeSize: (map['retailCodeSize'] ?? 8.0).toDouble(),
      retailCodeBold: map['retailCodeBold'] ?? false,
      retailPriceSize: (map['retailPriceSize'] ?? 7.0).toDouble(),
      retailPriceBold: map['retailPriceBold'] ?? true,
      retailUnitBold: map['retailUnitBold'] ?? false,
    );
  }
}