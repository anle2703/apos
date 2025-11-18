// lib/models/order_item_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../services/pricing_service.dart';
import 'product_model.dart';

class OrderItem {
  final String lineId;
  final ProductModel product;
  final double quantity;
  final double sentQuantity;
  final String selectedUnit;
  final double price;
  final List<TimeBlock> priceBreakdown;
  final Map<ProductModel, double> toppings;
  final String status;
  final String addedBy;
  final Timestamp addedAt;
  final bool isPaused;
  final Timestamp? pausedAt;
  final int totalPausedDurationInSeconds;
  final double? discountValue;
  final String? discountUnit;
  final String? note;
  final Map<String, String?>? commissionStaff;

  OrderItem({
    String? lineId,
    required this.product,
    this.quantity = 1.0,
    this.sentQuantity = 0.0,
    this.selectedUnit = '',
    required this.price,
    this.toppings = const {},
    this.status = 'active',
    required this.addedBy,
    required this.addedAt,
    this.priceBreakdown = const [],
    this.isPaused = false,
    this.pausedAt,
    this.totalPausedDurationInSeconds = 0,
    this.discountValue,
    this.discountUnit,
    this.note,
    this.commissionStaff,
  }) : lineId = lineId ?? const Uuid().v4();

  double get unsentChange => quantity - sentQuantity;
  bool get hasUnsentChanges => quantity != sentQuantity;

  double get subtotal {
    final isTimeBased = product.serviceSetup?['isTimeBased'] == true;

    double basePrice = price; // price là tổng tiền (time-based) hoặc đơn giá (normal)
    double discount = discountValue ?? 0;
    double discountedPrice = basePrice;

    if (discount > 0) {
      if ((discountUnit ?? '%') == '%') {
        discountedPrice = basePrice * (1 - discount / 100);
      } else { // 'VND'
        discountedPrice = (basePrice - discount);
      }
    }
    if (discountedPrice < 0) discountedPrice = 0;

    // Dịch vụ tính giờ không có topping và số lượng luôn là 1
    if (isTimeBased) {
      return discountedPrice;
    }

    // Tính toán cho món ăn/dịch vụ thông thường
    double toppingsTotal = 0.0;
    toppings.forEach((product, quantity) {
      toppingsTotal += product.sellPrice * quantity;
    });

    // (Đơn giá đã chiết khấu * số lượng) + topping
    // Đã xóa "this." khỏi quantity
    return (discountedPrice * quantity) + toppingsTotal;
  }

  String get groupKey {
    final sortedToppings = toppings.entries.toList()
      ..sort((a, b) => a.key.id.compareTo(b.key.id));
    final toppingsKey =
    sortedToppings.map((e) => '${e.key.id.trim()}x${e.value}').join('_');

    // === LOGIC MỚI ===
    // Thêm các trường mới vào key để phân biệt
    final priceKey = price.toString();
    final discountKey = '${discountValue ?? 0}-${discountUnit ?? '%'}';
    final noteKey = note ?? '';
    final commissionKey = commissionStaff?.toString() ?? '';

    return '${product.id.trim()}|${selectedUnit.trim()}|$priceKey|$discountKey|$noteKey|$commissionKey|$toppingsKey';
  }

  OrderItem copyWith({
    String? lineId,
    ProductModel? product,
    double? quantity,
    double? sentQuantity,
    String? selectedUnit,
    double? price,
    Map<ProductModel, double>? toppings,
    String? status,
    String? addedBy,
    Timestamp? addedAt,
    List<TimeBlock>? priceBreakdown,
    bool? isPaused,
    ValueGetter<Timestamp?>? pausedAt,
    int? totalPausedDurationInSeconds,

    // === THÊM CÁC TRƯỜNG MỚI VÀO ĐÂY ===
    double? discountValue,
    String? discountUnit,
    ValueGetter<String?>? note, // <-- Chuyển thành ValueGetter
    ValueGetter<Map<String, String?>?>? commissionStaff, // <-- Chuyển thành ValueGetter
  }) {
    return OrderItem(
      lineId: lineId ?? this.lineId,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      sentQuantity: sentQuantity ?? this.sentQuantity,
      selectedUnit: selectedUnit ?? this.selectedUnit,
      price: price ?? this.price,
      toppings: toppings ?? this.toppings,
      status: status ?? this.status,
      addedBy: addedBy ?? this.addedBy,
      addedAt: addedAt ?? this.addedAt,
      priceBreakdown: priceBreakdown ?? this.priceBreakdown,
      isPaused: isPaused ?? this.isPaused,
      pausedAt: pausedAt != null ? pausedAt() : this.pausedAt,
      totalPausedDurationInSeconds:
      totalPausedDurationInSeconds ?? this.totalPausedDurationInSeconds,

      // === ÁP DỤNG LOGIC MỚI ===
      discountValue: discountValue ?? this.discountValue,
      discountUnit: discountUnit ?? this.discountUnit,
      note: note != null ? note() : this.note, // <-- Sửa logic
      commissionStaff: commissionStaff != null ? commissionStaff() : this.commissionStaff, // <-- Sửa logic
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lineId': lineId,
      'quantity': quantity,
      'sentQuantity': sentQuantity,
      'selectedUnit': selectedUnit,
      'price': price,
      'subtotal': subtotal,
      'product': product.toMap(),
      'toppings': toppings.entries.map((e) {
        return {
          'quantity': e.value,
          'product': e.key.toMap(),
        };
      }).toList(),
      'status': status,
      'addedBy': addedBy,
      'addedAt': addedAt,
      'priceBreakdown': priceBreakdown.map((b) => b.toMap()).toList(),
      'isPaused': isPaused,
      'pausedAt': pausedAt,
      'totalPausedDurationInSeconds': totalPausedDurationInSeconds,
      'discountValue': discountValue,
      'discountUnit': discountUnit,
      'note': note,
      'commissionStaff': commissionStaff,
    };
  }

  static Timestamp? _parseToTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value;
    if (value is DateTime) return Timestamp.fromDate(value);
    if (value is String) {
      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) return Timestamp.fromDate(parsedDate);
    }
    return null;
  }

  factory OrderItem.fromMap(Map<String, dynamic> map,
      {List<ProductModel>? allProducts}) {
    Map<String, dynamic> productData;

    if (map['product'] is Map<String, dynamic>) {
      productData = map['product'] as Map<String, dynamic>;
    } else {
      productData = {
        'id': map['productId'],
        'productName': map['productName'],
        'productCode': map['productCode'],
        'productType': map['productType'],
        'unit': map['unit'],
        'sellPrice': map['price'],
        'costPrice': map['costPrice'],
        'imageUrl': map['imageUrl'],
        'serviceSetup': map['serviceSetup'],
        'additionalUnits': map['additionalUnits'] ?? [],
        'accompanyingItems': map['accompanyingItems'] ?? [],
        'kitchenPrinters': map['kitchenPrinters'] ?? [],

      };
    }

    ProductModel mainProduct;
    if (allProducts != null && allProducts.isNotEmpty) {
      final productId = productData['id'] as String?;
      mainProduct = allProducts.firstWhere(
            (p) => p.id == productId,
        orElse: () => ProductModel.fromMap(productData),
      );
    } else {
      mainProduct = ProductModel.fromMap(productData);
    }

    final Map<ProductModel, double> toppings = {};
    if (map['toppings'] is List) {
      for (var toppingData in (map['toppings'] as List)) {
        final toppingItem = OrderItem.fromMap(
            (toppingData as Map).cast<String, dynamic>(),
            allProducts: allProducts
        );
        toppings[toppingItem.product] = toppingItem.quantity;
      }
    }

    List<TimeBlock> breakdown = [];
    if (map['priceBreakdown'] is List) {
      breakdown = (map['priceBreakdown'] as List<dynamic>).map((b) {
        return TimeBlock.fromMap(b as Map<String, dynamic>);
      }).toList();
    }

    return OrderItem(
      lineId: map['lineId'] as String?, // Cho phép null, constructor sẽ tự tạo
      product: mainProduct,
      quantity: (map['quantity'] as num?)?.toDouble() ?? 1.0,
      sentQuantity: (map['sentQuantity'] as num?)?.toDouble() ?? 0.0,
      selectedUnit: map['selectedUnit'] as String? ?? '',
      price: (map['price'] as num?)?.toDouble() ?? mainProduct.sellPrice,
      toppings: toppings,
      status: map['status'] as String? ?? 'active',
      addedBy: map['addedBy'] as String? ?? 'N/A',
      addedAt: _parseToTimestamp(map['addedAt']) ?? Timestamp.now(),
      priceBreakdown: breakdown,
      isPaused: map['isPaused'] as bool? ?? false,
      pausedAt: _parseToTimestamp(map['pausedAt']),
      totalPausedDurationInSeconds: (map['totalPausedDurationInSeconds'] as num?)?.toInt() ?? 0,
      discountValue: (map['discountValue'] as num?)?.toDouble(),
      discountUnit: map['discountUnit'] as String?,
      note: map['note'] as String?,
      commissionStaff: (map['commissionStaff'] as Map?)?.cast<String, String?>(),
    );
  }
}