import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/store_settings_model.dart';

class SettingsService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<StoreSettings> watchStoreSettings(String userId) {
    return _db.collection('users').doc(userId).snapshots().map((snap) {
      return StoreSettings.fromMap(snap.data());
    });
  }

  Future<void> updateStoreSettings(String userId, Map<String, dynamic> partial) async {
    if (userId.isEmpty) throw ArgumentError("userId không hợp lệ");
    await _db.collection('users').doc(userId).set({
      ...partial,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }


  Future<void> ensureDefaults(String storeId) async {
    final ref = _db.doc('stores/$storeId/settings');
    final snap = await ref.get();
    if (!snap.exists) {
      await ref.set(StoreSettings(
        printBillAfterPayment: true,
        allowProvisionalBill: true,
        notifyKitchenAfterPayment: false,
        showPricesOnReceipt: true,
        showPricesOnProvisional: true,
      ).toMap());
    }
  }

  Future<StoreSettings> getStoreSettings(String userId) async {
    if (userId.isEmpty) {
      return StoreSettings.fromMap(null);
    }
    final doc = await _db.collection('users').doc(userId).get();
    return StoreSettings.fromMap(doc.data());
  }
}
