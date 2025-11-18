// lib/models/customer_group_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerGroupModel {
  final String id;
  final String name;
  final String storeId;

  CustomerGroupModel({
    required this.id,
    required this.name,
    required this.storeId,
  });

  factory CustomerGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CustomerGroupModel(
      id: doc.id,
      name: data['name'] ?? '',
      storeId: data['storeId'] ?? '',
    );
  }
}