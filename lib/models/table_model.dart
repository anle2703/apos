// File: lib/models/table_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class TableModel {
  final String id;
  final String tableName;
  final String tableGroup;
  final int stt;
  final String serviceId;
  final String storeId;
  final String? qrToken;
  final String? mergedWithTableId;

  TableModel({
    required this.id,
    required this.tableName,
    required this.tableGroup,
    required this.stt,
    required this.serviceId,
    required this.storeId,
    this.qrToken,
    this.mergedWithTableId,

  });

  factory TableModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TableModel(
      id: doc.id,
      tableName: data['tableName'] ?? '',
      tableGroup: data['tableGroup'] ?? '',
      stt: data['stt'] ?? 0,
      serviceId: data['serviceId'] ?? '',
      storeId: data['storeId'] ?? '',
      qrToken: data['qrToken'] as String?,
      mergedWithTableId: data['mergedWithTableId'] as String?,

    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tableName': tableName,
      'tableGroup': tableGroup,
      'stt': stt,
      'serviceId': serviceId,
      'storeId': storeId,
      'qrToken': qrToken,
      'mergedWithTableId': mergedWithTableId,

    };
  }
}