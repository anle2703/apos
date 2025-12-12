import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Hàm đảm bảo luôn có ca làm việc hợp lệ.
  /// Logic:
  /// 1. Kiểm tra ID đã lưu trong máy -> Nếu còn mở thì dùng tiếp.
  /// 2. Nếu không, tìm trên Server ca đang mở cùng ngày báo cáo -> Nếu có thì dùng.
  /// 3. Nếu không có -> Tạo mới.
  Future<void> ensureShiftOpen(String storeId, String userId, String userName, String ownerUid) async {
    final prefs = await SharedPreferences.getInstance();

    // --- BƯỚC 1: KIỂM TRA ID ĐANG LƯU TRONG MÁY ---
    String? localShiftId = prefs.getString('current_shift_id');

    if (localShiftId != null) {
      try {
        final doc = await _firestore.collection('employee_shifts').doc(localShiftId).get();
        if (doc.exists) {
          final data = doc.data();
          // Nếu ca này vẫn đang 'open', thì DÙNG TIẾP, không quan tâm ngày giờ (để hỗ trợ ca đêm vắt qua ngày)
          if (data?['status'] == 'open') {
            debugPrint(">>> [ShiftService] Ca hiện tại hợp lệ (Dùng tiếp): $localShiftId");
            return; // KẾT THÚC, KHÔNG TẠO MỚI
          } else {
            debugPrint(">>> [ShiftService] Ca $localShiftId đã đóng. Tìm ca mới...");
            await prefs.remove('current_shift_id'); // Xóa ID cũ đã đóng
          }
        } else {
          // ID rác (bị xóa trên server)
          await prefs.remove('current_shift_id');
        }
      } catch (e) {
        debugPrint(">>> [ShiftService] Lỗi kiểm tra ca local: $e");
      }
    }

    // --- BƯỚC 2: TÌM CA TRÊN SERVER (NẾU BƯỚC 1 KHÔNG DÙNG ĐƯỢC) ---
    try {
      // Tính ngày báo cáo hiện tại (dựa vào giờ chốt sổ)
      final String currentReportDateKey = await _getReportDateKey(ownerUid);

      final query = await _firestore.collection('employee_shifts')
          .where('storeId', isEqualTo: storeId)
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'open') // Chỉ tìm ca đang mở
          .where('reportDateKey', isEqualTo: currentReportDateKey) // Đúng ngày báo cáo
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        // ==> TÌM THẤY CA CŨ CÙNG NGÀY (VD: Đăng nhập lại máy khác)
        final existingShiftId = query.docs.first.id;
        await prefs.setString('current_shift_id', existingShiftId);
        debugPrint(">>> [ShiftService] Khôi phục ca cũ từ Server: $existingShiftId");
      } else {
        // ==> KHÔNG CÓ CA NÀO -> TẠO MỚI (Đây là lúc tạo ca mới hợp lệ)
        debugPrint(">>> [ShiftService] Không có ca mở cho ngày $currentReportDateKey. Tạo mới...");
        await _createNewShift(storeId, userId, userName, currentReportDateKey, prefs);
      }

    } catch (e) {
      debugPrint(">>> [ShiftService] Lỗi Query (Khả năng thiếu Index): $e");

      // Fallback: Nếu lỗi Query nhưng local vẫn trống -> Tạo đại để không crash app
      if (prefs.getString('current_shift_id') == null) {
        final fallbackDateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
        await _createNewShift(storeId, userId, userName, fallbackDateKey, prefs);
      }
    }
  }

  Future<String> _getReportDateKey(String ownerUid) async {
    int cutoffHour = 0;
    int cutoffMinute = 0;

    try {
      final userDoc = await _firestore.collection('users').doc(ownerUid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        cutoffHour = (data?['reportCutoffHour'] as num?)?.toInt() ?? 0;
        cutoffMinute = (data?['reportCutoffMinute'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}

    final now = DateTime.now();
    // Logic: Nếu chưa tới giờ chốt sổ -> Tính là ngày hôm qua
    final DateTime cutoffTimeToday = DateTime(now.year, now.month, now.day, cutoffHour, cutoffMinute);

    DateTime reportDate = now;
    if (now.isBefore(cutoffTimeToday)) {
      reportDate = now.subtract(const Duration(days: 1));
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
    debugPrint(">>> [ShiftService] Đã TẠO CA MỚI: ${newShiftRef.id}");
  }
}