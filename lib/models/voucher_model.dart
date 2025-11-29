// File: lib/models/voucher_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class VoucherModel {
  final String id;
  final String code;
  final double value;
  final bool isPercent;
  final int? quantity;
  final int? quantityUsed;
  final Timestamp? expiryAt;
  final Timestamp? startAt;
  final bool isActive;
  final String storeId;

  VoucherModel({
    required this.id,
    required this.code,
    required this.value,
    required this.isPercent,
    this.quantity,
    this.quantityUsed,
    this.expiryAt,
    this.startAt,
    required this.isActive,
    required this.storeId,
  });

  factory VoucherModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return VoucherModel(
      id: doc.id,
      code: data['code'] ?? '',
      value: (data['value'] as num? ?? 0).toDouble(),
      isPercent: data['isPercent'] ?? false,
      quantity: (data['quantity'] as num?)?.toInt(),
      quantityUsed: (data['usedCount'] as num?)?.toInt(),
      expiryAt: data['expiryAt'] as Timestamp?,
      startAt: data['startAt'] as Timestamp?,
      isActive: data['isActive'] ?? true,
      storeId: data['storeId'] ?? '',
    );
  }
}