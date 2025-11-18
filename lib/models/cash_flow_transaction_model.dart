// lib/models/cash_flow_transaction_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { revenue, expense, all }
enum TransactionSource { bill, purchaseOrder, manual }

class CashFlowTransaction {
  final String id;
  final TransactionType type;
  final DateTime date;
  final String user;
  final double amount;
  final String paymentMethod;
  final String reason;
  final String? note;
  final String storeId;
  final String userId;
  final String? customerId;
  final String? customerName;
  final String? supplierId;
  final String? supplierName;
  final String status;
  final String? cancelledBy;
  final DateTime? cancelledAt;
  final String? reportDateKey;
  final String? shiftId; // <-- THÊM MỚI

  CashFlowTransaction({
    required this.id,
    required this.type,
    required this.date,
    required this.user,
    required this.amount,
    required this.paymentMethod,
    required this.reason,
    this.note,
    required this.storeId,
    required this.userId,
    this.customerId,
    this.customerName,
    this.supplierId,
    this.supplierName,
    this.status = 'completed',
    this.cancelledBy,
    this.cancelledAt,
    this.reportDateKey,
    this.shiftId, // <-- THÊM MỚI
  });

  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'date': Timestamp.fromDate(date),
      'user': user,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'reason': reason,
      'storeId': storeId,
      'userId': userId,
      'status': status,

      if (note != null) 'note': note,
      if (customerId != null) 'customerId': customerId,
      if (customerName != null) 'customerName': customerName,
      if (supplierId != null) 'supplierId': supplierId,
      if (supplierName != null) 'supplierName': supplierName,
      if (cancelledBy != null) 'cancelledBy': cancelledBy,
      if (cancelledAt != null) 'cancelledAt': Timestamp.fromDate(cancelledAt!),
      if (reportDateKey != null) 'reportDateKey': reportDateKey,
      if (shiftId != null) 'shiftId': shiftId, // <-- THÊM MỚI
    };
  }

  factory CashFlowTransaction.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return CashFlowTransaction(
      id: doc.id,
      type: (data['type'] == 'revenue')
          ? TransactionType.revenue
          : TransactionType.expense,
      date: (data['date'] as Timestamp).toDate(),
      user: data['user'] ?? 'N/A',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] ?? 'Tiền mặt',
      reason: data['reason'] ?? (data['type'] == 'revenue' ? 'Thu khác' : 'Chi khác'),
      note: data['note'],
      storeId: data['storeId'] ?? '',
      userId: data['userId'] ?? '',
      customerId: data['customerId'],
      customerName: data['customerName'],
      supplierId: data['supplierId'],
      supplierName: data['supplierName'],
      status: data['status'] ?? 'completed',
      cancelledBy: data['cancelledBy'],
      cancelledAt: (data['cancelledAt'] as Timestamp?)?.toDate(),
      reportDateKey: data['reportDateKey'] as String?,
      shiftId: data['shiftId'] as String?, // <-- THÊM MỚI
    );
  }

  factory CashFlowTransaction.fromMap(Map<String, dynamic> data, String id) {
    final dynamic rawDate = data['date'];
    DateTime parsedDate;
    if (rawDate is Timestamp) {
      parsedDate = rawDate.toDate();
    } else if (rawDate is String) {
      parsedDate = DateTime.parse(rawDate);
    } else {
      parsedDate = DateTime.now();
    }

    final dynamic rawCancelledAt = data['cancelledAt'];
    DateTime? parsedCancelledAt;
    if (rawCancelledAt is Timestamp) {
      parsedCancelledAt = rawCancelledAt.toDate();
    } else if (rawCancelledAt is String) {
      parsedCancelledAt = DateTime.tryParse(rawCancelledAt);
    }

    return CashFlowTransaction(
      id: id,
      type: (data['type'] == 'revenue')
          ? TransactionType.revenue
          : TransactionType.expense,
      date: parsedDate, // Sử dụng ngày đã xử lý
      user: data['user'] ?? 'N/A',
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      paymentMethod: data['paymentMethod'] ?? 'Tiền mặt',
      reason: data['reason'] ?? (data['type'] == 'revenue' ? 'Thu khác' : 'Chi khác'),
      note: data['note'],
      storeId: data['storeId'] ?? '',
      userId: data['userId'] ?? '',
      customerId: data['customerId'],
      customerName: data['customerName'],
      supplierId: data['supplierId'],
      supplierName: data['supplierName'],
      status: data['status'] ?? 'completed',
      cancelledBy: data['cancelledBy'],
      cancelledAt: parsedCancelledAt,
      reportDateKey: data['reportDateKey'],
      shiftId: data['shiftId'], // <-- THÊM MỚI
    );
  }
}
