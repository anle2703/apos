import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // SỬA: Thay tham số ownerUid bằng storeId khi tính cutoff
  Future<void> ensureShiftOpen(String storeId, String userId, String userName, String ownerUid) async {
    final prefs = await SharedPreferences.getInstance();

    // SỬA: Truyền storeId vào đây
    final Map<String, int> cutoffConfig = await _getCutoffConfig(storeId);

    final String currentReportDateKey = _calculateReportDateKey(DateTime.now(), cutoffConfig['hour']!, cutoffConfig['minute']!);

    debugPrint(">>> [ShiftService] Ngày làm việc hiện tại: $currentReportDateKey");

    String? localShiftId = prefs.getString('current_shift_id');

    // --- CHECK CA LOCAL ---
    if (localShiftId != null) {
      try {
        final docRef = _firestore.collection('employee_shifts').doc(localShiftId);
        final doc = await docRef.get();

        if (doc.exists && doc.data()?['status'] == 'open') {
          final data = doc.data();
          String shiftDateKey = data?['reportDateKey'] ?? '';

          // Fallback nếu thiếu reportDateKey
          if (shiftDateKey.isEmpty && data?['startTime'] != null) {
            final Timestamp startTs = data!['startTime'];
            shiftDateKey = _calculateReportDateKey(startTs.toDate(), cutoffConfig['hour']!, cutoffConfig['minute']!);
          }

          if (shiftDateKey == currentReportDateKey) {
            return; // Ca hợp lệ, dùng tiếp
          } else {
            // Qua ngày -> Đóng ca cũ
            await docRef.update({
              'status': 'closed',
              'endTime': FieldValue.serverTimestamp(),
              'autoClosedBySystem': true,
              'note': 'Auto-closed by system (Day changed).',
            });
            await prefs.remove('current_shift_id');
            localShiftId = null;
          }
        } else {
          await prefs.remove('current_shift_id');
          localShiftId = null;
        }
      } catch (e) {
        localShiftId = null;
      }
    }

    // --- TẠO CA MỚI ---
    try {
      final query = await _firestore.collection('employee_shifts')
          .where('storeId', isEqualTo: storeId)
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'open')
          .where('reportDateKey', isEqualTo: currentReportDateKey)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        await prefs.setString('current_shift_id', query.docs.first.id);
      } else {
        await _createNewShift(storeId, userId, userName, currentReportDateKey, prefs);
      }
    } catch (e) {
      if (prefs.getString('current_shift_id') == null) {
        await _createNewShift(storeId, userId, userName, currentReportDateKey, prefs);
      }
    }
  }

  // SỬA: Hàm này giờ đọc từ store_settings
  Future<Map<String, int>> _getCutoffConfig(String storeId) async {
    int h = 0;
    int m = 0;
    try {
      // ĐỌC TỪ STORE_SETTINGS
      final doc = await _firestore.collection('store_settings').doc(storeId).get();
      if (doc.exists) {
        final data = doc.data();
        h = (data?['reportCutoffHour'] as num?)?.toInt() ?? 0;
        m = (data?['reportCutoffMinute'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return {'hour': h, 'minute': m};
  }

  String _calculateReportDateKey(DateTime time, int cutoffHour, int cutoffMinute) {
    final DateTime cutoffTimeToday = DateTime(time.year, time.month, time.day, cutoffHour, cutoffMinute);
    DateTime reportDate = time;
    if (time.isBefore(cutoffTimeToday)) {
      reportDate = time.subtract(const Duration(days: 1));
    }
    return DateFormat('yyyy-MM-dd').format(reportDate);
  }

  Future<void> _createNewShift(String storeId, String userId, String userName, String reportDateKey, SharedPreferences prefs) async {
    final newShiftRef = _firestore.collection('employee_shifts').doc();
    await newShiftRef.set({
      'storeId': storeId,
      'userId': userId,
      'userName': userName,
      'status': 'open',
      'startTime': FieldValue.serverTimestamp(),
      'reportDateKey': reportDateKey,
      'openingBalance': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await prefs.setString('current_shift_id', newShiftRef.id);
  }
}