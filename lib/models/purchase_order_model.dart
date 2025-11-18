// lib/models/purchase_order_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'supplier_model.dart';

class PurchaseOrderModel {
  final String id;
  final String code;
  final String? supplierId;
  final String supplierName;
  final double totalAmount;
  final String status;
  final DateTime createdAt; // <-- SỬA THÀNH DateTime
  final String createdBy;
  final String notes;
  final double shippingFee;
  final double discount;
  final bool isDiscountPercent;
  final double paidAmount;
  final String paymentMethod;
  final double subtotal;
  final double debtAmount;
  final List<Map<String, dynamic>> items;
  final String? updatedBy;
  final DateTime? updatedAt;

  SupplierModel? supplier;

  PurchaseOrderModel({
    required this.id,
    required this.code,
    this.supplierId,
    required this.supplierName,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.createdBy,
    required this.notes,
    required this.shippingFee,
    required this.discount,
    required this.isDiscountPercent,
    required this.paidAmount,
    required this.paymentMethod,
    required this.subtotal,
    required this.debtAmount,
    required this.items,
    this.supplier,
    this.updatedBy,
    this.updatedAt, // <-- SỬA THÀNH DateTime?
  });

  factory PurchaseOrderModel.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;

    // Lấy timestamp từ Firestore, nếu null thì dùng thời gian hiện tại
    Timestamp createdAtTimestamp = data['createdAt'] ?? Timestamp.now();
    Timestamp? updatedAtTimestamp = data['updatedAt'];

    return PurchaseOrderModel(
      id: doc.id,
      code: data['code'] ?? 'N/A',
      supplierId: data['supplierId'],
      supplierName: data['supplierName'] ?? 'Không rõ',
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      status: data['status'] ?? 'Hoàn thành',

      // Chuyển đổi Timestamp thành DateTime ngay tại đây
      createdAt: createdAtTimestamp.toDate(),

      createdBy: data['createdByName'] ?? 'Không rõ',
      notes: data['notes'] ?? '',
      shippingFee: (data['shippingFee'] as num?)?.toDouble() ?? 0.0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
      isDiscountPercent: data['isDiscountPercent'] ?? false,
      paidAmount: (data['paidAmount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] ?? 'Tiền mặt',
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      debtAmount: (data['debtAmount'] as num?)?.toDouble() ?? 0.0,
      items: List<Map<String, dynamic>>.from(data['items'] ?? []),
      updatedBy: data['updatedByName'],

      // Kiểm tra null trước khi chuyển đổi
      updatedAt: updatedAtTimestamp?.toDate(),
    );
  }
}