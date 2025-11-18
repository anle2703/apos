// File: lib/models/bill_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class BillModel {
  final String id;
  final String billCode;
  final String tableName;
  final String status;
  final String? customerName;
  final String? customerPhone;
  final String? createdByName;
  final DateTime startTime;
  final DateTime createdAt;
  final List<dynamic> items;
  final double subtotal;
  final double discount;
  final String discountType;
  final double discountInput;
  final double taxAmount;
  final double taxPercent;
  final List<dynamic> surcharges;
  final double totalPayable;
  final Map<String, dynamic> payments;
  final double changeAmount;
  final double debtAmount;
  final String? customerId;
  final double customerPointsUsed;
  final double customerPointsValue;
  final String? voucherCode;
  final double voucherDiscount;
  final double pointsEarned;
  final double totalProfit;
  final String? reportDateKey;
  final String? shiftId;
  final List<dynamic>? staffCommissions;
  final Map<String, dynamic>? bankDetails;
  final Map<String, dynamic>? eInvoiceInfo;
  final bool hasEInvoice;
  final String? guestAddress;

  BillModel({
    required this.id,
    required this.billCode,
    required this.tableName,
    required this.status,
    this.customerName,
    this.customerPhone,
    this.createdByName,
    required this.startTime,
    required this.createdAt,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.discountType,
    required this.discountInput,
    required this.taxAmount,
    required this.taxPercent,
    required this.surcharges,
    required this.totalPayable,
    required this.payments,
    required this.changeAmount,
    required this.debtAmount,
    this.customerId,
    required this.customerPointsUsed,
    required this.customerPointsValue,
    this.voucherCode,
    required this.voucherDiscount,
    required this.pointsEarned,
    required this.totalProfit,
    this.reportDateKey,
    this.shiftId,
    this.staffCommissions,
    this.bankDetails,
    this.eInvoiceInfo,
    required this.hasEInvoice,
    this.guestAddress,
  });

  factory BillModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    final items = (data['items'] ?? []) as List<dynamic>;
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();

    DateTime startTime = createdAt;
    if (items.isNotEmpty) {
      try {
        final validDates = items
            .where((item) => item is Map && item['addedAt'] is Timestamp)
            .map((item) => (item['addedAt'] as Timestamp).toDate())
            .toList();

        if (validDates.isNotEmpty) {
          startTime = validDates.reduce((min, current) => current.isBefore(min) ? current : min);
        }
      } catch (e) {
        startTime = createdAt;
        debugPrint("Lỗi khi tính startTime cho bill ${doc.id}: $e");
      }
    }

    final eInvoiceInfo = data['eInvoiceInfo'] as Map<String, dynamic>?;
    bool checkHasEInvoice = false;
    if (eInvoiceInfo != null) {
      if ((eInvoiceInfo['reservationCode'] != null && eInvoiceInfo['reservationCode'].isNotEmpty) ||
          (eInvoiceInfo['invoiceNo'] != null && eInvoiceInfo['invoiceNo'].isNotEmpty)) {
        checkHasEInvoice = true;
      }
    }

    return BillModel(
      id: doc.id,
      billCode: data['billCode'] ?? doc.id.split('_').last,
      tableName: data['tableName'] ?? 'N/A',
      status: data['status'] ?? 'completed',
      customerName: data['customerName'],
      customerPhone: data['customerPhone'] as String?,
      createdByName: data['createdByName'],
      startTime: startTime,
      createdAt: createdAt,
      items: items,
      subtotal: (data['subtotal'] as num?)?.toDouble() ?? 0.0,
      discount: (data['discount'] as num?)?.toDouble() ?? 0.0,
      discountType: data['discountType'] as String? ?? 'VND',
      discountInput: (data['discountInput'] as num?)?.toDouble() ?? 0.0,
      taxAmount: (data['taxAmount'] as num?)?.toDouble() ?? 0.0,
      taxPercent: (data['taxPercent'] as num?)?.toDouble() ?? 0.0,
      surcharges: (data['surcharges'] as List<dynamic>?) ?? [],
      totalPayable: (data['totalPayable'] as num?)?.toDouble() ?? 0.0,
      payments: (data['payments'] as Map<String, dynamic>?) ?? {},
      changeAmount: (data['changeAmount'] as num?)?.toDouble() ?? 0.0,
      debtAmount: (data['debtAmount'] as num?)?.toDouble() ?? 0.0,
      customerId: data['customerId'] as String?,
      customerPointsUsed: (data['customerPointsUsed'] as num?)?.toDouble() ?? 0.0,
      customerPointsValue: (data['customerPointsValue'] as num?)?.toDouble() ?? 0.0,
      voucherCode: data['voucherCode'] as String?,
      voucherDiscount: (data['voucherDiscount'] as num?)?.toDouble() ?? 0.0,
      pointsEarned: (data['pointsEarned'] as num?)?.toDouble() ?? 0.0,
      totalProfit: (data['totalProfit'] as num?)?.toDouble() ?? 0.0,
      reportDateKey: data['reportDateKey'] as String?,
      shiftId: data['shiftId'] as String?,
      staffCommissions: data['staffCommissions'] as List<dynamic>?,
      bankDetails: data['bankDetails'] as Map<String, dynamic>?,
      eInvoiceInfo: data['eInvoiceInfo'] as Map<String, dynamic>?,
      hasEInvoice: checkHasEInvoice,
      guestAddress: data['guestAddress'] as String?,
    );
  }
}