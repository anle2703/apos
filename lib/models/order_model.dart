// File: lib/models/order_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class OrderModel {
  final String id;
  final String tableId;
  final String tableName;
  final String status;
  final int version;
  final Timestamp startTime;
  final List<dynamic> items;
  double totalAmount;
  final String storeId;
  final int? numberOfCustomers;
  final Timestamp? createdAt;
  final String? createdByUid;
  final String? createdByName;
  final Timestamp? provisionalBillPrintedAt;
  final String? provisionalBillSource;
  final Timestamp? paidAt;
  final String? paidByUid;
  final String? paidByName;
  final Timestamp? updatedAt;
  final double? finalAmount;

  double get totalItemQuantity {
    try {
      return items.fold<double>(0.0, (total, raw) {
        final m = raw as Map<String, dynamic>;
        final q = (m['quantity'] as num?)?.toDouble() ?? 0.0;
        return total + q;
      });
    } catch (_) {
      return 0.0;
    }
  }

  OrderModel({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.status,
    required this.startTime,
    required this.items,
    required this.totalAmount,
    required this.storeId,
    this.createdAt,
    this.createdByUid,
    this.createdByName,
    this.provisionalBillPrintedAt,
    required this.version,
    this.paidAt,
    this.paidByUid,
    this.paidByName,
    this.updatedAt,
    this.finalAmount,
    this.provisionalBillSource,
    this.numberOfCustomers,
  });

  factory OrderModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>? ?? {});
    return OrderModel(
      id: doc.id,
      tableId: data['tableId']?.toString() ?? '',
      tableName: data['tableName']?.toString() ?? '',
      status: data['status']?.toString() ?? 'active',
      startTime: (data['startTime'] is Timestamp) ? data['startTime'] as Timestamp : Timestamp.now(),
      items: (data['items'] as List?)?.toList() ?? const [],
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      storeId: data['storeId']?.toString() ?? '',
      createdAt: (data['createdAt'] is Timestamp) ? data['createdAt'] as Timestamp : null,
      createdByUid: data['createdByUid'] as String?,
      createdByName: data['createdByName'] as String?,
      provisionalBillPrintedAt: (data['provisionalBillPrintedAt'] is Timestamp) ? data['provisionalBillPrintedAt'] as Timestamp : null,
      version: (data['version'] as num?)?.toInt() ?? 1,
      paidAt: (data['paidAt'] is Timestamp) ? data['paidAt'] as Timestamp : null,
      paidByUid: data['paidByUid'] as String?,
      paidByName: data['paidByName'] as String?,
      updatedAt: (data['updatedAt'] is Timestamp) ? data['updatedAt'] as Timestamp : null,
      finalAmount: (data['finalAmount'] as num?)?.toDouble(),
      provisionalBillSource: data['provisionalBillSource'] as String?,
      numberOfCustomers: data['numberOfCustomers'],

    );
  }

  factory OrderModel.fromMap(Map<String, dynamic> map) {
    return OrderModel(
      id: map['orderId']?.toString() ?? map['id']?.toString() ?? '',
      tableId: map['tableId']?.toString() ?? '',
      tableName: map['tableName']?.toString() ?? '',
      status: map['status']?.toString() ?? 'active',
      startTime: (map['startTime'] is Timestamp) ? map['startTime'] as Timestamp : Timestamp.now(),
      items: (map['items'] as List?)?.toList() ?? const [],
      totalAmount: (map['totalAmount'] as num?)?.toDouble() ?? 0.0,
      storeId: map['storeId']?.toString() ?? '',
      version: (map['version'] as num?)?.toInt() ?? 1,
      createdAt: (map['createdAt'] is Timestamp) ? map['createdAt'] as Timestamp : null,
      createdByUid: map['createdByUid'] as String?,
      createdByName: map['createdByName'] as String?,
      provisionalBillPrintedAt: (map['provisionalBillPrintedAt'] is Timestamp) ? map['provisionalBillPrintedAt'] as Timestamp : null,
      paidAt: (map['paidAt'] is Timestamp) ? map['paidAt'] as Timestamp : null,
      paidByUid: map['paidByUid'] as String?,
      paidByName: map['paidByName'] as String?,
      updatedAt: (map['updatedAt'] is Timestamp) ? map['updatedAt'] as Timestamp : null,
      finalAmount: (map['finalAmount'] as num?)?.toDouble(),
      provisionalBillSource: map['provisionalBillSource'] as String?,
      numberOfCustomers: map['numberOfCustomers'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tableId': tableId,
      'tableName': tableName,
      'status': status,
      'startTime': startTime,
      'items': items,
      'totalAmount': totalAmount,
      'storeId': storeId,
      'createdAt': createdAt,
      'createdByUid': createdByUid,
      'createdByName': createdByName,
      'provisionalBillPrintedAt': provisionalBillPrintedAt,
      'version': version,
      'paidAt': paidAt,
      'paidByUid': paidByUid,
      'paidByName': paidByName,
      'updatedAt': updatedAt,
      'finalAmount': finalAmount,
      'provisionalBillSource': provisionalBillSource,
      'numberOfCustomers': numberOfCustomers,

    };
  }

  OrderModel copyWith({
    String? id,
    String? tableId,
    String? tableName,
    String? status,
    Timestamp? startTime,
    List<dynamic>? items,
    double? totalAmount,
    String? storeId,
    Timestamp? createdAt,
    String? createdByUid,
    String? createdByName,
    ValueGetter<Timestamp?>? provisionalBillPrintedAt,
    ValueGetter<String?>? provisionalBillSource,
    Timestamp? paidAt,
    String? paidByUid,
    String? paidByName,
    Timestamp? updatedAt,
    double? finalAmount,
    int? version,
    int? numberOfCustomers,

  }) {
    return OrderModel(
      id: id ?? this.id,
      version: version ?? this.version,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      status: status ?? this.status,
      startTime: startTime ?? this.startTime,
      items: items ?? this.items,
      totalAmount: totalAmount ?? this.totalAmount,
      storeId: storeId ?? this.storeId,
      createdAt: createdAt ?? this.createdAt,
      createdByUid: createdByUid ?? this.createdByUid,
      createdByName: createdByName ?? this.createdByName,
      provisionalBillPrintedAt: provisionalBillPrintedAt != null ? provisionalBillPrintedAt() : this.provisionalBillPrintedAt,
      provisionalBillSource: provisionalBillSource != null ? provisionalBillSource() : this.provisionalBillSource,
      paidAt: paidAt ?? this.paidAt,
      paidByUid: paidByUid ?? this.paidByUid,
      paidByName: paidByName ?? this.paidByName,
      updatedAt: updatedAt ?? this.updatedAt,
      finalAmount: finalAmount ?? this.finalAmount,
      numberOfCustomers: numberOfCustomers ?? this.numberOfCustomers,

    );
  }
}