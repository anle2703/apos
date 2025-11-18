import 'package:uuid/uuid.dart';

class UnitModel {
  late final String id;
  String unitName;
  double sellPrice;
  double costPrice;
  double conversionFactor;
  double stock;

  UnitModel({
    String? id,
    required this.unitName,
    required this.sellPrice,
    required this.costPrice,
    required this.stock,
    this.conversionFactor = 1.0,
  }) {
    this.id = id ?? const Uuid().v4();
  }
}
