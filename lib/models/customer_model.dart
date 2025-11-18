import 'package:cloud_firestore/cloud_firestore.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? citizenId;
  final String? address;
  final String? companyName;
  final String? taxId;
  final String? companyAddress;
  final String storeId;
  final List<String> searchKeys;
  final int points;
  final double? debt;
  final String? customerGroupId;
  final String? customerGroupName;
  final double totalSpent;

  CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.citizenId,
    this.address,
    this.companyName,
    this.taxId,
    this.companyAddress,
    required this.storeId,
    required this.searchKeys,
    this.points = 0,
    this.debt,
    this.customerGroupId,
    this.customerGroupName,
    this.totalSpent = 0.0,

  });

  factory CustomerModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CustomerModel(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] as String?,
      citizenId: data['citizenId'],
      address: data['address'],
      companyName: data['companyName'],
      taxId: data['taxId'],
      companyAddress: data['companyAddress'],
      storeId: data['storeId'] ?? '',
      searchKeys: List<String>.from(data['searchKeys'] ?? []),
      points: (data['points'] as num?)?.toInt() ?? 0,
      debt: (data['debt'] as num?)?.toDouble() ?? 0.0,
      customerGroupId: data['customerGroupId'],
      customerGroupName: data['customerGroupName'],
      totalSpent: (data['totalSpent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  factory CustomerModel.fromMap(Map<String, dynamic> data) {
    return CustomerModel(
      id: data['id'] ?? '', // Lấy ID từ map
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'] as String?,
      citizenId: data['citizenId'],
      address: data['address'],
      companyName: data['companyName'],
      taxId: data['taxId'],
      companyAddress: data['companyAddress'],
      storeId: data['storeId'] ?? '',
      searchKeys: List<String>.from(data['searchKeys'] ?? []),
      points: (data['points'] as num?)?.toInt() ?? 0,
      debt: (data['debt'] as num?)?.toDouble() ?? 0.0,
      customerGroupId: data['customerGroupId'],
      customerGroupName: data['customerGroupName'],
      totalSpent: (data['totalSpent'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'citizenId': citizenId,
      'address': address,
      'companyName': companyName,
      'taxId': taxId,
      'companyAddress': companyAddress,
      'storeId': storeId,
      'updatedAt': FieldValue.serverTimestamp(),
      'searchKeys': searchKeys,
      'points': points,
      'debt': debt,
      'customerGroupId': customerGroupId,
      'customerGroupName': customerGroupName,
      'totalSpent': totalSpent,
    };
  }
}