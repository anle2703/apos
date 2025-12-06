import 'package:cloud_firestore/cloud_firestore.dart';

class SurchargeModel {
  final String id;
  final String storeId;
  final String name;
  final double value;
  final bool isPercent;
  final bool isActive;
  final Timestamp? startAt; // Thời gian bắt đầu áp dụng
  final Timestamp? endAt;   // Thời gian kết thúc áp dụng

  SurchargeModel({
    required this.id,
    required this.storeId,
    required this.name,
    required this.value,
    this.isPercent = false,
    this.isActive = true,
    this.startAt,
    this.endAt,
  });

  factory SurchargeModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SurchargeModel(
      id: doc.id,
      storeId: data['storeId'] ?? '',
      name: data['name'] ?? '',
      value: (data['value'] as num?)?.toDouble() ?? 0.0,
      isPercent: data['isPercent'] ?? false,
      isActive: data['isActive'] ?? true,
      startAt: data['startAt'] as Timestamp?,
      endAt: data['endAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'name': name,
      'value': value,
      'isPercent': isPercent,
      'isActive': isActive,
      'startAt': startAt,
      'endAt': endAt,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}