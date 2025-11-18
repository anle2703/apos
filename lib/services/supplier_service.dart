import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/supplier_model.dart';
import '../models/purchase_order_model.dart';
import 'package:flutter/foundation.dart';
import '../theme/number_utils.dart';

class SupplierService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final CollectionReference _suppliersCollection = FirebaseFirestore.instance.collection('suppliers');
  final CollectionReference _supplierGroupsCollection = FirebaseFirestore.instance.collection('supplier_groups');

  List<String> generateSearchKeys(String name, String phone) {
    final normalizedName = name.toLowerCase().trim();
    final tokens = normalizedName.split(' ').where((t) => t.isNotEmpty).toList();
    final keys = <String>{};

    for (final token in tokens) {
      keys.add(token);
    }

    String currentPhrase = '';
    for (final token in tokens) {
      currentPhrase = (currentPhrase.isEmpty)
          ? token
          : '$currentPhrase $token';
      keys.add(currentPhrase);
    }


    final normalizedPhone = phone.trim();
    if (normalizedPhone.isNotEmpty) {
      keys.add(normalizedPhone);
      if (normalizedPhone.length >= 3) {
        keys.add(normalizedPhone.substring(normalizedPhone.length - 3));
      }
    }

    return keys.toList();
  }

  Future<List<SupplierModel>> searchSuppliers(String query) async {
    QuerySnapshot querySnapshot;
    final normalizedQuery = query.toLowerCase().trim();

    if (normalizedQuery.isEmpty) {
      querySnapshot = await _suppliersCollection.orderBy('name').limit(20).get();
    } else {
      querySnapshot = await _suppliersCollection
          .where('searchKeys', arrayContains: normalizedQuery)
          .limit(20)
          .get();
    }
    return querySnapshot.docs.map((doc) => SupplierModel.fromFirestore(doc)).toList();
  }

  Future<SupplierModel> addSupplier(Map<String, dynamic> data) async {
    final String name = (data['name'] ?? '').toString().trim();
    final String phone = (data['phone'] ?? '').toString().trim();
    final String? address = (data['address']?.toString().trim().isEmpty ?? true) ? null : data['address'].toString().trim();
    final String? taxCode = (data['taxCode']?.toString().trim().isEmpty ?? true) ? null : data['taxCode'].toString().trim().toUpperCase();
    final String storeId = data['storeId'] ?? '';
    final String? supplierGroupId = data['supplierGroupId'];
    final String? supplierGroupName = data['supplierGroupName'];

    final searchKeys = generateSearchKeys(name, phone);

    final newData = <String, dynamic>{
      'name': name,
      'phone': phone,
      'address': address,
      'taxCode': taxCode,
      'debt': 0.0,
      'searchKeys': searchKeys,
      'storeId': storeId,
      'supplierGroupId': supplierGroupId,
      'supplierGroupName': supplierGroupName,
      'createdAt': FieldValue.serverTimestamp(),
    };

    final docRef = await _suppliersCollection.add(newData);
    final doc = await docRef.get();
    return SupplierModel.fromFirestore(doc);
  }

  Future<void> updateSupplier(String id, Map<String, dynamic> data) async {
    final String name = (data['name'] ?? '').toString().trim();
    final String phone = (data['phone'] ?? '').toString().trim();
    final String? address = (data['address']?.toString().trim().isEmpty ?? true) ? null : data['address'].toString().trim();
    final String? taxCode = (data['taxCode']?.toString().trim().isEmpty ?? true) ? null : data['taxCode'].toString().trim().toUpperCase();
    final String? supplierGroupId = data['supplierGroupId']; // Lấy groupId
    final String? supplierGroupName = data['supplierGroupName']; // Lấy groupName

    final searchKeys = generateSearchKeys(name, phone);

    final newData = <String, dynamic>{
      'name': name,
      'phone': phone,
      'address': address,
      'taxCode': taxCode,
      'searchKeys': searchKeys,
      'supplierGroupId': supplierGroupId,
      'supplierGroupName': supplierGroupName,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _suppliersCollection.doc(id).update(newData);
  }

  Future<List<SupplierGroupModel>> getSupplierGroups(String storeId) async {
    try {
      final snapshot = await _supplierGroupsCollection
          .where('storeId', isEqualTo: storeId)
          .orderBy('name')
          .get();
      return snapshot.docs.map((doc) => SupplierGroupModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Lỗi khi lấy nhóm NCC: $e");
      return [];
    }
  }

  Future<String> addSupplierGroup(String name, String storeId) async {
    try {
      final docRef = await _supplierGroupsCollection.add({
        'name': capitalizeWords(name),
        'storeId': storeId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return docRef.id;
    } catch (e) {
      debugPrint("Lỗi khi thêm nhóm NCC: $e");
      throw Exception('Không thể thêm nhóm NCC: $e');
    }
  }

  Stream<List<SupplierModel>> searchSuppliersStream(String query, String storeId, {String? groupId}) {
    try {
      Query queryRef = _suppliersCollection.where('storeId', isEqualTo: storeId);
      final normalizedQuery = query.toLowerCase().trim();

      if (groupId != null && groupId.isNotEmpty) {
        queryRef = queryRef.where('supplierGroupId', isEqualTo: groupId);
      }

      if (normalizedQuery.isNotEmpty) {
        queryRef = queryRef.where('searchKeys', arrayContains: normalizedQuery);
      } else {
        queryRef = queryRef.orderBy('debt', descending: true);
      }

      return queryRef.limit(30).snapshots().map((snapshot) {
        return snapshot.docs.map((doc) => SupplierModel.fromFirestore(doc)).toList();
      });

    } catch (e) {
      debugPrint("Lỗi khi tìm nhà cung cấp: $e");
      return Stream.value([]);
    }
  }

  Future<SupplierModel?> getSupplierById(String supplierId) async {
    final doc = await _suppliersCollection.doc(supplierId).get();
    if (doc.exists) {
      return SupplierModel.fromFirestore(doc);
    }
    return null;
  }

  Future<List<PurchaseOrderModel>> getPurchaseOrdersBySupplier(String supplierId) async {
    try {
      final snapshot = await _db
          .collection('purchase_orders')
          .where('supplierId', isEqualTo: supplierId)
          .where('status', isNotEqualTo: 'Đã hủy')
          .get();
      return snapshot.docs.map((doc) => PurchaseOrderModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Lỗi khi lấy phiếu nhập của NCC: $e");
      return [];
    }
  }

  Future<void> updateSupplierDebt(String supplierId, double amountToChange) async {
    if (amountToChange == 0 || supplierId.isEmpty) return;

    final supplierRef = _suppliersCollection.doc(supplierId);
    try {
      await supplierRef.update({
        'debt': FieldValue.increment(amountToChange),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Lỗi khi cập nhật công nợ NCC $supplierId: $e");
      throw Exception('Không thể cập nhật công nợ cho nhà cung cấp.');
    }
  }

  Future<bool> checkSupplierNameExists(String name, String storeId, {String? excludeId}) async {
    var query = _suppliersCollection
        .where('storeId', isEqualTo: storeId);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) {
      return false;
    }

    final newNameLower = name.trim().toLowerCase();

    for (final doc in snapshot.docs) {
      final docName = (doc.data() as Map<String, dynamic>)['name'] as String?;
      if (docName == null) continue;

      if (docName.toLowerCase() == newNameLower) {
        if (excludeId != null && doc.id == excludeId) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  Future<bool> checkSupplierGroupInUse(String groupId, String storeId) async {
    final snapshot = await _suppliersCollection
        .where('storeId', isEqualTo: storeId) // Thêm dòng này
        .where('supplierGroupId', isEqualTo: groupId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> updateSupplierGroup(String groupId, String newName) async {
    if (newName.trim().isEmpty) {
      throw Exception('Tên nhóm không được để trống');
    }
    await _supplierGroupsCollection.doc(groupId).update({
      'name': capitalizeWords(newName),
    });
    // Lưu ý: Bạn có thể cần một cloud function để cập nhật
    // 'supplierGroupName' trong tất cả các 'suppliers' có 'supplierGroupId' này
  }

  Future<void> deleteSupplierGroup(String groupId, String storeId) async {
    // Kiểm tra xem nhóm có đang được sử dụng không (truyền storeId)
    final isInUse = await checkSupplierGroupInUse(groupId, storeId);
    if (isInUse) {
      throw Exception('Không thể xóa nhóm đang được sử dụng. Vui lòng chuyển các NCC sang nhóm khác trước.');
    }

    // Nếu không, tiến hành xóa
    final docRef = _supplierGroupsCollection.doc(groupId);
    final doc = await docRef.get();
    if (doc.exists && (doc.data() as Map<String, dynamic>?)?['storeId'] == storeId) {
      await docRef.delete();
    } else if (!doc.exists) {
      debugPrint("Nhóm $groupId không tồn tại để xóa.");
    } else {
      throw Exception('Bạn không có quyền xóa nhóm này.');
    }
  }

  Future<void> updateSupplierGroupNameInSuppliers(String groupId, String newName, String storeId) async {
    // 1. Tìm tất cả NCC thuộc nhóm này
    final query = _db.collection('suppliers')
        .where('storeId', isEqualTo: storeId)
        .where('supplierGroupId', isEqualTo: groupId);

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return; // Không có NCC nào để cập nhật
    }

    // 2. Tạo một batch write để cập nhật tất cả
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'supplierGroupName': newName});
    }

    // 3. Thực thi batch
    await batch.commit();
  }
}