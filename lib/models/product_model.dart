// File: lib/models/product_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';

class ProductModel {
  final String id;
  final String productName;
  final String? productCode;
  final String? productGroup;
  final String? imageUrl;
  final List<String> additionalBarcodes;
  final String? unit;
  final List<Map<String, dynamic>> additionalUnits;
  List<String> get getAllUnits {
    final List<String> units = [if (unit != null && unit!.isNotEmpty) unit!];
    units.addAll(additionalUnits.map((u) => u['unitName'] as String));
    return units;
  }
  double getCostPriceForUnit(String unitName) {
    if (unitName == unit) {
      return costPrice;
    }
    final unitData = additionalUnits.firstWhereOrNull(
          (u) => u['unitName'] == unitName,
    );
    return (unitData?['costPrice'] as num?)?.toDouble() ?? 0.0;
  }
  final double sellPrice;
  final double costPrice;
  final double stock;
  final double minStock;
  final String storeId;
  final String ownerUid;
  final String? productType;
  final Map<String, dynamic>? serviceSetup;
  final List<Map<String, dynamic>> accompanyingItems;
  final List<Map<String, dynamic>> recipeItems;
  final List<Map<String, dynamic>> compiledMaterials;
  final List<String> kitchenPrinters;
  final bool isVisibleInMenu;
  final bool manageStockSeparately;

  ProductModel({
    required this.id,
    required this.productName,
    this.productCode,
    this.productGroup,
    this.imageUrl,
    required this.additionalBarcodes,
    this.unit,
    required this.additionalUnits,
    required this.sellPrice,
    required this.costPrice,
    required this.stock,
    required this.minStock,
    required this.storeId,
    required this.ownerUid,
    this.productType,
    this.serviceSetup,
    required this.accompanyingItems,
    required this.recipeItems,
    required this.compiledMaterials,
    required this.kitchenPrinters,
    this.isVisibleInMenu = true,
    this.manageStockSeparately = false,
  });

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ProductModel(
      id: doc.id,
      productName: data['productName'] ?? '',
      productCode: data['productCode'],
      productGroup: data['productGroup'],
      imageUrl: data['imageUrl'],
      additionalBarcodes: List<String>.from(data['additionalBarcodes'] ?? []),
      unit: data['unit'],
      additionalUnits: List<Map<String, dynamic>>.from(data['additionalUnits'] ?? []),
      sellPrice: (data['sellPrice'] ?? 0).toDouble(),
      costPrice: (data['costPrice'] ?? 0).toDouble(),
      stock: (data['stock'] ?? 0).toDouble(),
      minStock: (data['minStock'] ?? 0).toDouble(),
      storeId: data['storeId'] ?? '',
      ownerUid: data['ownerUid'] ?? '',
      productType: data['productType'],
      serviceSetup: data['serviceSetup'] != null
          ? Map<String, dynamic>.from(data['serviceSetup'])
          : null,
      accompanyingItems: List<Map<String, dynamic>>.from(data['accompanyingItems'] ?? []),
      recipeItems: List<Map<String, dynamic>>.from(data['recipeItems'] ?? []),
      compiledMaterials: List<Map<String, dynamic>>.from(data['compiledMaterials'] ?? []),
      kitchenPrinters: List<String>.from(data['kitchenPrinters'] ?? []),
      isVisibleInMenu: data['isVisibleInMenu'] ?? true,
      manageStockSeparately: data['manageStockSeparately'] ?? false,
    );
  }

  static String _toTitleCase(String? input) {
    if (input == null || input.isEmpty) return '';
    return input
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }

  Map<String, dynamic> toMap() {
    final formattedAdditionalUnits = additionalUnits.map((unit) {
      final newUnit = Map<String, dynamic>.from(unit);
      newUnit['unitName'] = _toTitleCase(unit['unitName']);
      return newUnit;
    }).toList();

    return {
      'id': id,
      'productName': _toTitleCase(productName),
      'productCode': productCode?.toUpperCase(),
      'productGroup': productGroup,
      'imageUrl': imageUrl,
      'additionalBarcodes': additionalBarcodes.map((code) => code.toUpperCase()).toList(),
      'unit': unit != null ? _toTitleCase(unit!) : null,
      'additionalUnits': formattedAdditionalUnits,
      'sellPrice': sellPrice,
      'costPrice': costPrice,
      'stock': stock,
      'minStock': minStock,
      'storeId': storeId,
      'ownerUid': ownerUid,
      'productType': productType,
      'serviceSetup': serviceSetup,
      'accompanyingItems': accompanyingItems,
      'recipeItems': recipeItems,
      'compiledMaterials': compiledMaterials,
      'kitchenPrinters': kitchenPrinters,
      'isVisibleInMenu': isVisibleInMenu,
      'manageStockSeparately': manageStockSeparately,
    };
  }

  factory ProductModel.fromMap(Map<String, dynamic> map) {
    return ProductModel(
      id: map['id'] ?? '',
      productName: map['productName'] ?? 'Sản phẩm lỗi',
      productCode: map['productCode'],
      productGroup: map['productGroup'],
      imageUrl: map['imageUrl'],
      additionalBarcodes: List<String>.from(map['additionalBarcodes'] ?? []),
      unit: map['unit'],
      additionalUnits: List<Map<String, dynamic>>.from(map['additionalUnits'] ?? []),
      sellPrice: (map['sellPrice'] as num? ?? 0).toDouble(),
      costPrice: (map['costPrice'] as num? ?? 0).toDouble(),
      stock: (map['stock'] as num? ?? 0).toDouble(),
      minStock: (map['minStock'] as num? ?? 0).toDouble(),
      storeId: map['storeId'] ?? '',
      ownerUid: map['ownerUid'] ?? '',
      productType: map['productType'],
      serviceSetup: map['serviceSetup'] != null
          ? Map<String, dynamic>.from(map['serviceSetup'])
          : null,
      accompanyingItems: List<Map<String, dynamic>>.from(map['accompanyingItems'] ?? []),
      recipeItems: List<Map<String, dynamic>>.from(map['recipeItems'] ?? []),
      compiledMaterials: List<Map<String, dynamic>>.from(map['compiledMaterials'] ?? []),
      kitchenPrinters: List<String>.from(map['kitchenPrinters'] ?? []),
      isVisibleInMenu: map['isVisibleInMenu'] ?? true,
      manageStockSeparately: map['manageStockSeparately'] ?? false,
    );
  }
}