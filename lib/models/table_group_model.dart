// File: lib/models/table_group_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class TableGroupModel {
  final String id;
  final String name;
  final int stt;
  final String storeId;

  TableGroupModel({
    required this.id,
    required this.name,
    required this.stt,
    required this.storeId,
  });

  factory TableGroupModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TableGroupModel(
      id: doc.id,
      name: data['name'] ?? '',
      stt: data['stt'] ?? 0,
      storeId: data['storeId'] ?? '',
    );
  }
}