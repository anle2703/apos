import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ShiftService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Hàm đảm bảo luôn có ca làm việc hợp lệ.
  /// Logic Mới:
  /// 1. Tính toán ngày làm việc hiện tại (Current Date) dựa trên giờ chốt sổ.
  /// 2. Kiểm tra ID trong máy:
  ///    - Nếu đang mở CÙNG ngày -> Dùng tiếp.
  ///    - Nếu đang mở KHÁC ngày -> Đóng ca cũ -> Đi tiếp để tạo mới.
  /// 3. Nếu chưa có ca (hoặc vừa đóng ca cũ) -> Tìm/Tạo mới cho ngày hiện tại.
  Future<void> ensureShiftOpen(String storeId, String userId, String userName, String ownerUid) async {
    final prefs = await SharedPreferences.getInstance();

    // --- BƯỚC 0: LẤY CẤU HÌNH & TÍNH NGÀY HIỆN TẠI ---
    // Phải biết hôm nay là ngày nào trước khi kiểm tra ca
    final Map<String, int> cutoffConfig = await _getCutoffConfig(ownerUid);
    final String currentReportDateKey = _calculateReportDateKey(DateTime.now(), cutoffConfig['hour']!, cutoffConfig['minute']!);

    debugPrint(">>> [ShiftService] Ngày làm việc hiện tại: $currentReportDateKey (Cutoff: ${cutoffConfig['hour']}:${cutoffConfig['minute']})");

    // --- BƯỚC 1: KIỂM TRA ID ĐANG LƯU TRONG MÁY ---
    String? localShiftId = prefs.getString('current_shift_id');

    if (localShiftId != null) {
      try {
        final docRef = _firestore.collection('employee_shifts').doc(localShiftId);
        final doc = await docRef.get();

        if (doc.exists) {
          final data = doc.data();
          if (data?['status'] == 'open') {
            // Lấy ngày báo cáo của ca này
            String shiftDateKey = data?['reportDateKey'] ?? '';

            // Fallback: Nếu ca cũ quá không có field reportDateKey, tính từ startTime
            if (shiftDateKey.isEmpty && data?['startTime'] != null) {
              final Timestamp startTs = data!['startTime'];
              shiftDateKey = _calculateReportDateKey(startTs.toDate(), cutoffConfig['hour']!, cutoffConfig['minute']!);
            }

            // SO SÁNH NGÀY
            if (shiftDateKey == currentReportDateKey) {
              debugPrint(">>> [ShiftService] Ca $localShiftId hợp lệ (Cùng ngày). Dùng tiếp.");
              return; // OK, Dùng tiếp
            } else {
              // KHÁC NGÀY -> ĐÓNG CA CŨ
              debugPrint(">>> [ShiftService] Ca $localShiftId đã qua ngày ($shiftDateKey vs $currentReportDateKey). Đang đóng...");
              await docRef.update({
                'status': 'closed',
                'endTime': FieldValue.serverTimestamp(),
                'autoClosedBySystem': true,
                'note': 'Hệ thống tự động đóng ca do qua giờ chốt sổ.',
              });
              await prefs.remove('current_shift_id');
              localShiftId = null; // Reset để xuống bước dưới tạo mới
            }
          } else {
            // Ca đã đóng rồi (closed)
            await prefs.remove('current_shift_id');
            localShiftId = null;
          }
        } else {
          // ID rác
          await prefs.remove('current_shift_id');
          localShiftId = null;
        }
      } catch (e) {
        debugPrint(">>> [ShiftService] Lỗi kiểm tra ca local: $e");
        localShiftId = null;
      }
    }

    // --- BƯỚC 2: TÌM CA TRÊN SERVER HOẶC TẠO MỚI ---
    // (Chạy khi không có local ID hoặc local ID vừa bị đóng do qua ngày)
    try {
      final query = await _firestore.collection('employee_shifts')
          .where('storeId', isEqualTo: storeId)
          .where('userId', isEqualTo: userId)
          .where('status', isEqualTo: 'open')
          .where('reportDateKey', isEqualTo: currentReportDateKey) // Chỉ tìm ca của NGÀY HIỆN TẠI
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        // ==> TÌM THẤY CA ĐANG MỞ CỦA NGÀY HÔM NAY
        final existingShiftId = query.docs.first.id;
        await prefs.setString('current_shift_id', existingShiftId);
        debugPrint(">>> [ShiftService] Khôi phục ca cũ từ Server (Cùng ngày): $existingShiftId");
      } else {
        // ==> KHÔNG CÓ CA NÀO CHO NGÀY HÔM NAY -> TẠO MỚI
        debugPrint(">>> [ShiftService] Tạo ca mới cho ngày $currentReportDateKey...");
        await _createNewShift(storeId, userId, userName, currentReportDateKey, prefs);
      }

    } catch (e) {
      debugPrint(">>> [ShiftService] Lỗi Query/Create: $e");
      // Fallback cuối cùng để không crash
      if (prefs.getString('current_shift_id') == null) {
        await _createNewShift(storeId, userId, userName, currentReportDateKey, prefs);
      }
    }
  }

  // --- CÁC HÀM HỖ TRỢ (HELPER) ---

  // Lấy giờ chốt sổ từ Firestore (tách riêng để dễ dùng lại)
  Future<Map<String, int>> _getCutoffConfig(String ownerUid) async {
    int h = 0;
    int m = 0;
    try {
      final userDoc = await _firestore.collection('users').doc(ownerUid).get();
      if (userDoc.exists) {
        final data = userDoc.data();
        h = (data?['reportCutoffHour'] as num?)?.toInt() ?? 0;
        m = (data?['reportCutoffMinute'] as num?)?.toInt() ?? 0;
      }
    } catch (_) {}
    return {'hour': h, 'minute': m};
  }

  // Hàm tính toán thuần túy (Pure Function): DateTime -> String Key
  String _calculateReportDateKey(DateTime time, int cutoffHour, int cutoffMinute) {
    // Tạo mốc thời gian chốt sổ của ngày hôm đó
    final DateTime cutoffTimeToday = DateTime(time.year, time.month, time.day, cutoffHour, cutoffMinute);

    DateTime reportDate = time;
    if (time.isBefore(cutoffTimeToday)) {
      // Nếu chưa tới giờ chốt sổ (VD: 2h sáng, chốt lúc 4h) -> Tính là ngày hôm qua
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
      'reportDateKey': reportDateKey, // Lưu Key ngày đã tính toán chuẩn
      'openingBalance': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });

    await prefs.setString('current_shift_id', newShiftRef.id);
    debugPrint(">>> [ShiftService] Đã TẠO CA MỚI: ${newShiftRef.id} ($reportDateKey)");
  }
}