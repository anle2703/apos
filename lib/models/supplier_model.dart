// File: models/supplier_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class SupplierModel {
  final String id;
  String name;
  String phone;
  String? address;
  String? taxCode;
  double debt;
  List<String> searchKeys;
  String storeId; // <-- THÊM STORE ID NẾU CHƯA CÓ
  String? supplierGroupId; // <-- THÊM MỚI
  String? supplierGroupName; // <-- THÊM MỚI

  SupplierModel({
    required this.id,
    required this.name,
    required this.phone,
    this.address,
    this.taxCode,
    this.debt = 0.0,
    required this.searchKeys,
    required this.storeId, // <-- THÊM
    this.supplierGroupId, // <-- THÊM
    this.supplierGroupName, // <-- THÊM

  });

  factory SupplierModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});

    final dynamic rawPhone = data['phone'];
    final String phoneStr = rawPhone is String
        ? rawPhone
        : (rawPhone is List
        ? rawPhone.whereType<String>().where((e) => e.trim().isNotEmpty).join(', ')
        : '');

    return SupplierModel(
      id: doc.id,
      name: (data['name'] as String? ?? '').trim(),
      phone: phoneStr,
      address: (data['address'] as String?)?.trim(),
      taxCode: (data['taxCode'] as String?)?.trim(),
      debt: (data['debt'] as num?)?.toDouble() ?? 0.0,
      searchKeys: (data['searchKeys'] as List?)?.whereType<String>().toList() ?? const [],
      storeId: data['storeId'] ?? '', // <-- THÊM
      supplierGroupId: data['supplierGroupId'], // <-- THÊM
      supplierGroupName: data['supplierGroupName'], // <-- THÊM
    );
  }


  // SỬA LẠI: Hàm toMap() bây giờ rất đơn giản
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'address': address,
      'taxCode': taxCode,
      'debt': debt,
      'searchKeys': searchKeys,
      'storeId': storeId,
      'supplierGroupId': supplierGroupId,
      'supplierGroupName': supplierGroupName,
    };
  }
}

class SupplierGroupModel {
  final String id;
  final String name;
  final String storeId;

  SupplierGroupModel({
    required this.id,
    required this.name,
    required this.storeId,
  });

  factory SupplierGroupModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return SupplierGroupModel(
      id: doc.id,
      name: data['name'] ?? '',
      storeId: data['storeId'] ?? '',
    );
  }
}
