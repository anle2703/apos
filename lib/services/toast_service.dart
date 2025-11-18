import 'package:flutter/material.dart';
import 'dart:async';

// Định nghĩa các loại thông báo
enum ToastType { success, error, warning }

// Lớp chứa dữ liệu cho một thông báo
class ToastData {
  final String id;
  final String message;
  final ToastType type;

  ToastData({required this.message, required this.type}) : id = UniqueKey().toString();
}

// Lớp quản lý logic chính - ĐÃ ĐƯỢC NÂNG CẤP
class ToastService extends ChangeNotifier {
  final List<ToastData> _toasts = [];
  // Map để quản lý các timer tương ứng với mỗi toast
  final Map<String, Timer> _toastTimers = {};

  List<ToastData> get toasts => _toasts;

  static final ToastService _instance = ToastService._internal();
  factory ToastService() => _instance;
  ToastService._internal();

  void show({required String message, required ToastType type, Duration duration = const Duration(seconds: 4)}) {
    // --- LOGIC HÀNG ĐỢI (QUEUE) ---
    // Nếu đã đủ 3 thông báo
    if (_toasts.length >= 3) {
      // Lấy ra thông báo đầu tiên (cũ nhất)
      final oldestToast = _toasts.first;
      // Hủy timer của thông báo cũ nhất để nó không tự xóa nữa
      _toastTimers[oldestToast.id]?.cancel();
      _toastTimers.remove(oldestToast.id);
      // Xóa thông báo cũ nhất khỏi danh sách
      _toasts.removeAt(0);
    }

    final toast = ToastData(message: message, type: type);
    _toasts.add(toast); // Thêm thông báo mới vào cuối danh sách

    // Bắt đầu một timer mới cho thông báo mới
    final timer = Timer(duration, () => _removeToast(toast.id));
    // Lưu lại timer này
    _toastTimers[toast.id] = timer;

    notifyListeners(); // Cập nhật giao diện
  }

  void _removeToast(String id) {
    // Xóa timer tương ứng khỏi Map
    _toastTimers.remove(id);
    // Xóa toast khỏi danh sách
    _toasts.removeWhere((toast) => toast.id == id);
    notifyListeners(); // Cập nhật giao diện
  }
}