// lib/services/cash_flow_service.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CashFlowService {
  final _db = FirebaseFirestore.instance;

  Future<void> cancelManualTransaction(
      CashFlowTransaction transaction,
      String cancelledByUserName,
      ) async {
    final writeBatch = _db.batch();

    // 1. Cập nhật trạng thái phiếu -> "cancelled"
    final txRef = _db.collection('manual_cash_transactions').doc(transaction.id);
    writeBatch.update(txRef, {
      'status': 'cancelled',
      'cancelledBy': cancelledByUserName,
      'cancelledAt': FieldValue.serverTimestamp(),
    });

    try {
      // 2. Hoàn tác công nợ (Logic này đã đúng)
      if (transaction.status == 'completed') {
        if (transaction.type == TransactionType.revenue &&
            transaction.reason == "Thu nợ bán hàng" &&
            transaction.customerId != null) {
          final customerRef =
          _db.collection('customers').doc(transaction.customerId);
          writeBatch.update(customerRef, {
            'debt': FieldValue.increment(transaction.amount),
          });
        } else if (transaction.type == TransactionType.expense &&
            transaction.reason == "Trả nợ nhập hàng" &&
            transaction.supplierId != null) {
          final supplierRef =
          _db.collection('suppliers').doc(transaction.supplierId);
          writeBatch.update(supplierRef, {
            'debt': FieldValue.increment(transaction.amount),
          });
        }
      }

      // 3. Hoàn tác daily_reports (SỬA LẠI LOGIC NÀY)
      if (transaction.status == 'completed') {
        final String reportDateString;
        if (transaction.reportDateKey != null &&
            transaction.reportDateKey!.isNotEmpty) {
          reportDateString = transaction.reportDateKey!;
          debugPrint(
              ">>> Hủy Phiếu: Dùng reportDateKey đã lưu: $reportDateString");
        } else {
          // Fallback cho phiếu cũ (lưu ý: logic này có thể không khớp 100%
          // với Cloud Function nếu giờ chốt sổ khác 00:00)
          reportDateString =
              DateFormat('yyyy-MM-dd').format(transaction.date.toUtc());
          debugPrint(
              ">>> Hủy Phiếu: CẢNH BÁO: Dùng logic fallback (UTC date): $reportDateString");
        }

        final reportId = '${transaction.storeId}_$reportDateString';
        final dailyReportRef = _db.collection('daily_reports').doc(reportId);

        final Map<String, dynamic> dailyReportUpdates = {};
        final double amountToReverse = -transaction.amount; // Trừ

        if (transaction.type == TransactionType.revenue) {
          dailyReportUpdates['totalOtherRevenue'] =
              FieldValue.increment(amountToReverse);
        } else {
          dailyReportUpdates['totalOtherExpense'] =
              FieldValue.increment(amountToReverse);
        }

        // Cập nhật cấp độ Ca (shift) nếu có shiftId
        if (transaction.shiftId != null && transaction.shiftId!.isNotEmpty) {
          final String shiftKeyPrefix = 'shifts.${transaction.shiftId}';
          if (transaction.type == TransactionType.revenue) {
            dailyReportUpdates['$shiftKeyPrefix.totalOtherRevenue'] =
                FieldValue.increment(amountToReverse);
          } else {
            dailyReportUpdates['$shiftKeyPrefix.totalOtherExpense'] =
                FieldValue.increment(amountToReverse);
          }
          debugPrint(
              ">>> Hủy Phiếu: Hoàn tác ${transaction.type.name} $amountToReverse cho $shiftKeyPrefix");
        } else {
          debugPrint(
              ">>> Hủy Phiếu: CẢNH BÁO: Không tìm thấy shiftId, chỉ hoàn tác ở cấp độ tổng.");
        }

        // Cập nhật vào batch
        writeBatch.update(dailyReportRef, dailyReportUpdates);
      }

      // 4. Thực thi tất cả (Cập nhật status, Hoàn nợ, Hoàn báo cáo)
      await writeBatch.commit();
    } catch (e) {
      debugPrint("Lỗi hoàn tác công nợ hoặc báo cáo khi hủy phiếu: $e");
      rethrow; // Ném lại lỗi để dialog có thể bắt
    }
  }

  Future<void> deleteManualTransaction(String transactionId) async {
    final docRef = _db.collection('manual_cash_transactions').doc(transactionId);
    final doc = await docRef.get();

    if (!doc.exists) {
      return; // Phiếu đã bị xóa
    }

    if (doc.data()?['status'] == 'cancelled') {
      await docRef.delete();
    } else {
      throw Exception('Chỉ có thể xóa phiếu đã ở trạng thái "Đã hủy".');
    }
  }
}