import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_settings_model.dart';

class SettingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Đối tượng mặc định để dùng khi không có dữ liệu hoặc lỗi
  // Bạn có thể điều chỉnh true/false tùy theo logic mặc định của app
  static const _defaultSettings = StoreSettings(
    printBillAfterPayment: true,
    allowProvisionalBill: true,
    notifyKitchenAfterPayment: false,
    showPricesOnProvisional: false,
  );

  Stream<StoreSettings> watchStoreSettings(String storeId) {
    if (storeId.isEmpty) {
      return Stream.value(_defaultSettings);
    }

    return _db.collection('store_settings').doc(storeId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) {
        return _defaultSettings;
      }
      return StoreSettings.fromMap(snap.data()!);
    });
  }

  Future<void> updateStoreSettings(String storeId, Map<String, dynamic> partial) async {
    if (storeId.isEmpty) throw ArgumentError("storeId không hợp lệ");
    await _db.collection('store_settings').doc(storeId).set({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<StoreSettings> getStoreSettings(String storeId) async {
    if (storeId.isEmpty) {
      return StoreSettings.fromMap(null);
    }
    try {
      final doc = await _db.collection('store_settings').doc(storeId).get();
      // Nếu doc không tồn tại hoặc data null, fromMap sẽ tự xử lý (nhờ code trong StoreSettings)
      // Nhưng ta cần đảm bảo không crash khi đọc doc
      return StoreSettings.fromMap(doc.data());
    } catch (e) {
      print("Lỗi đọc StoreSettings: $e");
      return const StoreSettings(
        printBillAfterPayment: true,
        allowProvisionalBill: true,
        notifyKitchenAfterPayment: false,
        showPricesOnProvisional: false,
      );
    }
  }
}