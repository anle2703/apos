import 'package:permission_handler/permission_handler.dart';
import '../services/toast_service.dart';

class PermissionService {
  static Future<void> ensurePermissions() async {
    final status = await Permission.location.request();

    if (status.isGranted) {
    } else if (status.isDenied) {
      ToastService().show(message: "Quyền location bị từ chối, không thể in LAN.", type: ToastType.error);
    } else if (status.isPermanentlyDenied) {
      ToastService().show(message: "Quyền location bị từ chối vĩnh viễn, cần vào Cài đặt mở lại.", type: ToastType.error);
      openAppSettings();
    }
  }
}
