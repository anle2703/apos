// File: lib/models/discount_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class DiscountItem {
  final String productId;
  final String productName;
  final String? imageUrl;
  final double oldPrice; // Giá gốc (để tham khảo)

  // THAY ĐỔI Ở ĐÂY: Lưu quy tắc giảm thay vì giá cố định
  final double value;    // Giá trị giảm (VD: 10 nếu là %, 10000 nếu là VNĐ)
  final bool isPercent;  // True = %, False = VNĐ

  DiscountItem({
    required this.productId,
    required this.productName,
    this.imageUrl,
    required this.oldPrice,
    required this.value,
    this.isPercent = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'imageUrl': imageUrl,
      'oldPrice': oldPrice,
      'value': value,
      'isPercent': isPercent,
    };
  }

  factory DiscountItem.fromMap(Map<String, dynamic> map) {
    return DiscountItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      imageUrl: map['imageUrl'],
      oldPrice: (map['oldPrice'] as num?)?.toDouble() ?? 0.0,
      value: (map['value'] as num?)?.toDouble() ?? 0.0,
      isPercent: map['isPercent'] ?? true,
    );
  }
}

class DiscountModel {
  final String id;
  final String name;
  final String storeId;
  final List<DiscountItem> items;

  final String type;
  final DateTime? startAt;
  final DateTime? endAt;
  final List<Map<String, String>>? dailyTimeRanges;
  final List<int>? daysOfWeek;

  final String targetType;
  final String? targetGroupId;
  final String? targetGroupName;

  final DateTime? createdAt;
  final bool isActive;

  DiscountModel({
    required this.id,
    required this.name,
    required this.storeId,
    required this.items,
    required this.type,
    this.startAt,
    this.endAt,
    this.dailyTimeRanges,
    this.daysOfWeek,
    required this.targetType,
    this.targetGroupId,
    this.targetGroupName,
    this.createdAt,
    required this.isActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'storeId': storeId,
      'items': items.map((e) => e.toMap()).toList(),
      'type': type,
      'startAt': startAt != null ? Timestamp.fromDate(startAt!) : null,
      'endAt': endAt != null ? Timestamp.fromDate(endAt!) : null,
      'dailyTimeRanges': dailyTimeRanges,
      'daysOfWeek': daysOfWeek,
      'targetType': targetType,
      'targetGroupId': targetGroupId,
      'targetGroupName': targetGroupName,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'isActive': isActive,
    };
  }

  factory DiscountModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return DiscountModel(
      id: doc.id,
      name: data['name'] ?? '',
      storeId: data['storeId'] ?? '',
      items: (data['items'] as List<dynamic>?)
          ?.map((e) => DiscountItem.fromMap(e as Map<String, dynamic>))
          .toList() ?? [],
      type: data['type'] ?? 'specific',
      startAt: (data['startAt'] as Timestamp?)?.toDate(),
      endAt: (data['endAt'] as Timestamp?)?.toDate(),
      dailyTimeRanges: (data['dailyTimeRanges'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
          .toList(),
      daysOfWeek: (data['daysOfWeek'] as List<dynamic>?)?.cast<int>(),
      targetType: data['targetType'] ?? 'all',
      targetGroupId: data['targetGroupId'],
      targetGroupName: data['targetGroupName'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      isActive: data['isActive'] ?? true,
    );
  }
}