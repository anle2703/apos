import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show Platform;
import '../models/customer_model.dart';
import '../models/order_model.dart';
import '../models/product_group_model.dart';
import '../models/product_model.dart';
import '../models/table_group_model.dart';
import '../models/table_model.dart';
import '../models/user_model.dart';
import '../models/bill_model.dart';
import '../models/customer_group_model.dart';
import 'package:intl/intl.dart';
import 'package:app_4cash/models/voucher_model.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/quick_note_model.dart';
import '../models/payment_method_model.dart';
import '../models/web_order_model.dart';
import '../models/discount_model.dart';
import '../models/surcharge_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<ProductGroupModel>? _cachedProductGroups;
  List<TableGroupModel>? _cachedTableGroups;

  String _toTitleCase(String? input) {
    if (input == null || input.trim().isEmpty) return '';

    return input
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) {
      if (word == word.toUpperCase()) {
        return word;
      }
      return word[0].toUpperCase() + word.substring(1).toLowerCase();
    })
        .join(' ');
  }

  Stream<List<ProductModel>> getProductsStream(String storeId,
      {String? group}) {
    Query query = _db.collection('products');
    query = query.where('storeId', isEqualTo: storeId);
    if (group != null) {
      query = query.where('productGroup', isEqualTo: group);
    }
    query = query.orderBy('createdAt', descending: true);
    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => ProductModel.fromFirestore(doc)).toList());
  }

  Stream<List<ProductModel>> getAllProductsStream(String storeId) {
    return _db
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => ProductModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<UserModel>> getAllUsersInStoreStream(String storeId) {
    return _db
        .collection('users')
        .where('storeId', isEqualTo: storeId)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => UserModel.fromFirestore(doc))
            .toList());
  }

  Future<DocumentReference> addProduct(Map<String, dynamic> productData) async {
    try {
      // Logic chuẩn hóa dữ liệu (giữ nguyên của bạn)
      final product = ProductModel.fromMap(productData);
      final formatted = product.toMap();
      formatted['createdAt'] = FieldValue.serverTimestamp();

      // 1. Tạo document reference trước
      final docRef = _db.collection('products').doc();

      // 2. Ghi dữ liệu vào reference đó
      await docRef.set(formatted);

      // 3. QUAN TRỌNG: Trả về docRef để bên ngoài lấy được ID (docRef.id)
      return docRef;
    } catch (e) {
      throw Exception('Không thể thêm sản phẩm: $e');
    }
  }

  Future<void> updateProduct(String productId,
      Map<String, dynamic> data) async {
    try {
      // SAU KHI SỬA: Cập nhật trực tiếp map nhận được, không convert qua Model
      // để tránh việc các trường không gửi lên bị reset về null/mặc định.

      final Map<String, dynamic> dataToUpdate = Map.from(data);

      // Xử lý format thủ công cho các trường quan trọng (nếu có trong data gửi lên)
      // Giữ logic TitleCase và UpperCase như cũ nhưng an toàn hơn
      if (dataToUpdate.containsKey('productName') &&
          dataToUpdate['productName'] != null) {
        dataToUpdate['productName'] = _toTitleCase(dataToUpdate['productName']);
      }

      if (dataToUpdate.containsKey('unit') && dataToUpdate['unit'] != null) {
        dataToUpdate['unit'] = _toTitleCase(dataToUpdate['unit']);
      }

      if (dataToUpdate.containsKey('productCode') &&
          dataToUpdate['productCode'] != null) {
        dataToUpdate['productCode'] =
            dataToUpdate['productCode'].toString().toUpperCase();
      }

      // Luôn cập nhật thời gian sửa
      dataToUpdate['updatedAt'] = FieldValue.serverTimestamp();

      await _db.collection('products').doc(productId).update(dataToUpdate);
    } catch (e) {
      throw Exception('Không thể cập nhật sản phẩm: $e');
    }
  }

  Future<void> deleteProduct(String productId) async {
    try {
      await _db.collection('products').doc(productId).delete();
    } catch (e) {
      throw Exception('Không thể xóa sản phẩm: $e');
    }
  }

  Future<bool> doesUserExist(String uid) async {
    try {
      DocumentSnapshot doc = await _db.collection('users').doc(uid).get();
      return doc.exists;
    } catch (e) {
      throw Exception('Lỗi kiểm tra người dùng: $e');
    }
  }

  Future<UserModel?> getUserProfile(String uid) async {
    try {
      final snap = await _db
          .collection('users')
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (snap.docs.isNotEmpty) {
        return UserModel.fromFirestore(snap.docs.first);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi khi lấy thông tin người dùng: $e");
      throw Exception('Không thể lấy thông tin người dùng.');
    }
  }

  Future<void> updateUserField(String uid, Map<String, dynamic> data) async {
    try {
      final formattedData = Map<String, dynamic>.from(data);
      if (formattedData.containsKey('storeName')) {
        formattedData['storeName'] = _toTitleCase(formattedData['storeName']);
      }
      if (formattedData.containsKey('storeAddress')) {
        formattedData['storeAddress'] =
            _toTitleCase(formattedData['storeAddress']);
      }

      await _db.collection('users').doc(uid).update(formattedData);
    } catch (e) {
      throw Exception('Không thể cập nhật thông tin người dùng: $e');
    }
  }

  // Tìm đến hàm createUserProfile và sửa lại đoạn batch.set:

  Future<void> createUserProfile({
    required String uid,
    required String email,
    required String storeId,
    required String storeName,
    required String phoneNumber,
    required String role,
    String? name,
    String? storePhone,
    String? agentId, // Vẫn nhận tham số này
    String? businessType,
    String? storeAddress,
  }) async {
    try {
      final DateTime now = DateTime.now();
      final DateTime expiryDate = now.add(const Duration(days: 7));

      final batch = _db.batch();

      // 1. USER: Bỏ agentId và fcmTokens, bỏ receivePaymentNotification (vì cái này đi theo thiết bị/store)
      final userRef = _db.collection('users').doc(uid);
      batch.set(userRef, {
        'uid': uid,
        'email': email,
        'phoneNumber': phoneNumber,
        'name': _toTitleCase(name),
        'role': role,
        'active': true,
        'storeId': storeId,
        'subscriptionExpiryDate': Timestamp.fromDate(expiryDate),
        'createdAt': FieldValue.serverTimestamp(),
      });

      final settingsRef = _db.collection('store_settings').doc(storeId);
      batch.set(settingsRef, {
        'storeName': _toTitleCase(storeName),
        'storeAddress': _toTitleCase(storeAddress),
        'storePhone': storePhone,
        'businessType': businessType ?? 'retail',
        'agentId': agentId,
        'fcmTokens': [],
        'printBillAfterPayment': true,
        'allowProvisionalBill': true,
        'notifyKitchenAfterPayment': false,
        'showPricesOnProvisional': false,
        'reportCutoffHour': 0,
        'reportCutoffMinute': 0,
        'promptForCash': true,
        'qrOrderRequiresConfirmation': true,
        'enableShip': true,
        'enableBooking': true,
        'printLabelOnKitchen': false,
        'printLabelOnPayment': false,
        'labelWidth': 50,
        'labelHeight': 30,
        'skipKitchenPrint': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await batch.commit();

    } catch (e) {
      throw Exception('Không thể tạo hồ sơ người dùng và cửa hàng: $e');
    }
  }

  Future<bool> isFieldInUse(
      {required String field, required String value}) async {
    try {
      final query = await _db
          .collection('users')
          .where(field, isEqualTo: value)
          .limit(1)
          .get();
      return query.docs.isNotEmpty;
    } catch (e) {
      throw Exception('Lỗi kiểm tra dữ liệu: $e');
    }
  }

  Future<String?> getEmailFromPhoneNumber(String phoneNumber) async {
    try {
      final query = await _db.collection('users').where(
          'phoneNumber', isEqualTo: phoneNumber).limit(1).get();
      if (query.docs.isNotEmpty) {
        return query.docs.first.data()['email'] as String?;
      }
      return null;
    } catch (e) {
      throw Exception('Không thể lấy email từ SĐT: $e');
    }
  }

  Future<String> generateNextProductCode(String storeId, String prefix) async {
    try {
      final counterDocRef =
      _db.collection('counters').doc('product_codes_$storeId');
      final String counterField = '${prefix}_count';
      int? nextNumber;
      if (!kIsWeb && Platform.isWindows) {
        final counterSnapshot = await counterDocRef.get();
        if (!counterSnapshot.exists) {
          await counterDocRef.set({counterField: 1});
          nextNumber = 1;
        } else {
          final data = counterSnapshot.data() as Map<String, dynamic>;
          final currentCount = data[counterField] ?? 0;
          nextNumber = (currentCount as int) + 1;
          await counterDocRef.update({counterField: nextNumber});
        }
      } else {
        await _db.runTransaction((transaction) async {
          final counterSnapshot = await transaction.get(counterDocRef);
          if (!counterSnapshot.exists) {
            transaction.set(counterDocRef, {counterField: 1});
            nextNumber = 1;
          } else {
            final currentCount =
                (counterSnapshot.data() as Map<String,
                    dynamic>)[counterField] ?? 0;
            nextNumber = currentCount + 1;
            transaction.update(counterDocRef, {counterField: nextNumber});
          }
        });
      }
      return '$prefix${nextNumber!.toString().padLeft(5, '0')}';
    } catch (e) {
      throw Exception('Không thể tạo mã sản phẩm mới: $e');
    }
  }

  Future<void> addProductGroup(String groupName, String storeId) async {
    try {
      final query = _db
          .collection('product_groups')
          .where('storeId', isEqualTo: storeId)
          .orderBy('stt', descending: true)
          .limit(1);
      final querySnapshot = await query.get();
      int nextStt = 1;
      if (querySnapshot.docs.isNotEmpty) {
        final highestStt = querySnapshot.docs.first.data()['stt'] as int? ?? 0;
        nextStt = highestStt + 1;
      }
      await _db.collection('product_groups').add({
        'name': _toTitleCase(groupName),
        'storeId': storeId,
        'stt': nextStt,
      });
      _cachedProductGroups = null;
    } catch (e) {
      throw Exception('Không thể thêm nhóm sản phẩm: $e');
    }
  }

  Future<List<ProductGroupModel>> getProductGroups(String storeId,
      {bool forceRefresh = false, String? name}) async {
    try {
      if (_cachedProductGroups != null && !forceRefresh && name == null) {
        return _cachedProductGroups!;
      }

      Query query = _db
          .collection('product_groups')
          .where('storeId', isEqualTo: storeId);

      if (name != null) {
        query = query.where('name', isEqualTo: name);
      } else {
        query = query.orderBy('stt');
      }

      final snapshot = await query.get();
      final groups = snapshot.docs
          .map((doc) => ProductGroupModel.fromFirestore(doc))
          .toList();

      if (name == null) {
        _cachedProductGroups = groups;
      }

      return groups;
    } catch (e) {
      throw Exception('Không thể lấy danh sách nhóm: $e');
    }
  }

  Future<void> updateProductGroup(String groupId, String newName,
      int newStt) async {
    try {
      await _db
          .collection('product_groups')
          .doc(groupId)
          .update({ 'name': _toTitleCase(newName), 'stt': newStt});
      _cachedProductGroups = null;
    } catch (e) {
      throw Exception('Không thể cập nhật nhóm sản phẩm: $e');
    }
  }

  Future<void> deleteProductGroup(String groupId, String groupName,
      String storeId) async {
    try {
      final productQuery = await _db
          .collection('products')
          .where('storeId', isEqualTo: storeId)
          .where('productGroup', isEqualTo: groupName)
          .limit(1)
          .get();

      if (productQuery.docs.isNotEmpty) {
        throw Exception('Không thể xóa nhóm vì vẫn còn sản phẩm bên trong.');
      } else {
        await _db.collection('product_groups').doc(groupId).delete();
        _cachedProductGroups = null;
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('vẫn còn sản phẩm')) {
        rethrow;
      }
      throw Exception('Không thể xóa nhóm sản phẩm: $e');
    }
  }

  Future<List<ProductModel>> getTimeBasedServices(String storeId) async {
    try {
      final querySnapshot = await _db
          .collection('products')
          .where('storeId', isEqualTo: storeId)
          .where('productType', isEqualTo: 'Dịch vụ/Tính giờ')
          .where('serviceSetup.isTimeBased', isEqualTo: true)
          .get();
      return querySnapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      throw Exception('Không thể lấy danh sách dịch vụ: $e');
    }
  }

  Stream<List<TableModel>> getTablesStream(String storeId, {String? group}) {
    Query query = _db.collection('tables').where('storeId', isEqualTo: storeId);
    if (group != null) {
      query = query.where('tableGroup', isEqualTo: group);
    }
    query = query.orderBy('stt');
    return query.snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => TableModel.fromFirestore(doc)).toList());
  }

  Future<void> addTable(Map<String, dynamic> tableData) async {
    try {
      await _db.collection('tables').add(tableData);
    } catch (e) {
      throw Exception('Không thể thêm phòng/bàn: $e');
    }
  }

  Future<void> setTable(String tableId, Map<String, dynamic> tableData) async {
    try {
      await _db.collection('tables').doc(tableId).set(tableData);
    } catch (e) {
      throw Exception('Không thể tạo/cập nhật bàn ảo: $e');
    }
  }

  Future<void> addTableGroup(String groupName, String storeId) async {
    try {
      final query = _db
          .collection('table_groups')
          .where('storeId', isEqualTo: storeId)
          .orderBy('stt', descending: true)
          .limit(1);

      final querySnapshot = await query.get();
      int nextStt = 1;
      if (querySnapshot.docs.isNotEmpty) {
        final highestStt = querySnapshot.docs.first.data()['stt'] as int? ?? 0;
        nextStt = highestStt + 1;
      }

      await _db.collection('table_groups').add({
        'name': _toTitleCase(groupName),
        'storeId': storeId,
        'stt': nextStt,
      });
      _cachedTableGroups = null;
    } catch (e) {
      throw Exception('Không thể thêm nhóm phòng/bàn: $e');
    }
  }

  Future<int> findHighestTableSTT(String storeId) async {
    try {
      final querySnapshot = await _db
          .collection('tables')
          .where('storeId', isEqualTo: storeId)
          .orderBy('stt', descending: true)
          .limit(1)
          .get();
      if (querySnapshot.docs.isEmpty) {
        return 0;
      }
      return querySnapshot.docs.first.data()['stt'] as int? ?? 0;
    } catch (e) {
      throw Exception('Không thể tìm STT bàn lớn nhất: $e');
    }
  }

  Future<int> findHighestTableNumber(String storeId, String keyword) async {
    try {
      final querySnapshot = await _db
          .collection('tables')
          .where('storeId', isEqualTo: storeId)
          .where('tableName', isGreaterThanOrEqualTo: keyword)
          .where('tableName', isLessThan: '$keyword\uf8ff')
          .get();
      if (querySnapshot.docs.isEmpty) {
        return 0;
      }
      int highestNumber = 0;
      final RegExp numberRegex = RegExp(r'\d+$');
      for (var doc in querySnapshot.docs) {
        final tableName = doc.data()['tableName'] as String;
        if (tableName.startsWith("$keyword ")) {
          final match = numberRegex.firstMatch(tableName);
          if (match != null) {
            final number = int.tryParse(match.group(0)!) ?? 0;
            if (number > highestNumber) {
              highestNumber = number;
            }
          }
        }
      }
      return highestNumber;
    } catch (e) {
      throw Exception('Không thể tìm số bàn lớn nhất: $e');
    }
  }

  Future<void> updateTable(String tableId, Map<String, dynamic> data) async {
    try {
      await _db.collection('tables').doc(tableId).update(data);
    } catch (e) {
      throw Exception('Không thể cập nhật phòng/bàn: $e');
    }
  }

  Future<void> deleteTable(String tableId) async {
    try {
      await _db.collection('tables').doc(tableId).delete();
    } catch (e) {
      throw Exception('Không thể xóa phòng/bàn: $e');
    }
  }

  Future<List<TableGroupModel>> getTableGroups(String storeId,
      {bool forceRefresh = false}) async {
    try {
      if (_cachedTableGroups != null && !forceRefresh) {
        return _cachedTableGroups!;
      }
      final snapshot = await _db
          .collection('table_groups')
          .where('storeId', isEqualTo: storeId)
          .orderBy('stt')
          .get();
      final groups = snapshot.docs
          .map((doc) => TableGroupModel.fromFirestore(doc))
          .toList();
      _cachedTableGroups = groups;
      return groups;
    } catch (e) {
      throw Exception('Không thể lấy danh sách nhóm phòng/bàn: $e');
    }
  }

  Future<void> updateTableGroup(String groupId, String newName,
      int newStt) async {
    try {
      await _db
          .collection('table_groups')
          .doc(groupId)
          .update({ 'name': _toTitleCase(newName), 'stt': newStt});
      _cachedTableGroups = null;
    } catch (e) {
      throw Exception('Không thể cập nhật nhóm phòng/bàn: $e');
    }
  }

  Future<void> deleteTableGroup(String groupId, String groupName,
      String storeId) async {
    try {
      final tableQuery = await _db
          .collection('tables')
          .where('storeId', isEqualTo: storeId)
          .where('tableGroup', isEqualTo: groupName)
          .limit(1)
          .get();
      if (tableQuery.docs.isNotEmpty) {
        throw Exception('Không thể xóa nhóm vì vẫn còn phòng/bàn bên trong.');
      } else {
        await _db.collection('table_groups').doc(groupId).delete();
        _cachedTableGroups = null;
      }
    } catch (e) {
      if (e is Exception && e.toString().contains('vẫn còn phòng/bàn')) {
        rethrow;
      }
      throw Exception('Không thể xóa nhóm phòng/bàn: $e');
    }
  }

  Stream<List<TableModel>> getAllTablesStream(String storeId) {
    return _db
        .collection('tables')
        .where('storeId', isEqualTo: storeId)
        .orderBy('stt')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => TableModel.fromFirestore(doc))
            .toList());
  }

  Stream<List<OrderModel>> getActiveOrdersStream(String storeId) {
    return _db
        .collection('orders')
        .where('storeId', isEqualTo: storeId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => OrderModel.fromFirestore(doc))
            .toList());
  }

  Future<String> addOrder(Map<String, dynamic> orderData) async {
    try {
      final docRef = await _db.collection('orders').add(orderData);
      return docRef.id;
    } catch (e) {
      throw Exception('Không thể tạo đơn hàng: $e');
    }
  }

  Future<void> updateOrder(String orderId,
      Map<String, dynamic> orderData) async {
    try {
      await _db.collection('orders').doc(orderId).update(orderData);
    } catch (e) {
      throw Exception('Không thể cập nhật đơn hàng: $e');
    }
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    try {
      final orderRef = _db.collection('orders').doc(orderId);
      if (status == 'cancelled') {
        final orderDoc = await orderRef.get();
        if (orderDoc.exists) {
          final data = orderDoc.data() as Map<String, dynamic>;
          final List<dynamic> items = List.from(data['items'] ?? []);
          final updatedItems = items.map((item) {
            final itemMap = item as Map<String, dynamic>;
            itemMap['status'] = 'cancelled';
            return itemMap;
          }).toList();
          await orderRef.update({
            'status': status,
            'items': updatedItems,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      } else {
        await orderRef.update({
          'status': status,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      throw Exception('Không thể cập nhật trạng thái đơn hàng: $e');
    }
  }

  Stream<DocumentSnapshot> getOrderStream(String orderId) {
    return _db.collection('orders').doc(orderId).snapshots();
  }

  Stream<DocumentSnapshot> getOrderStreamForTable(String tableId) {
    return _db.collection('orders').doc(tableId).snapshots();
  }

  Future<Map<String, String>?> getStoreDetails(String storeId) async {
    try {
      // SỬA: Đọc trực tiếp từ 'store_settings' thay vì tìm trong 'users'
      final docSnapshot = await _db.collection('store_settings').doc(storeId).get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data();
        return {
          'name': data?['storeName'] as String? ?? '',
          'phone': data?['storePhone'] as String? ?? '',
          'address': data?['storeAddress'] as String? ?? '',
        };
      }

      // Fallback (Tuỳ chọn): Nếu chưa có trong settings thì tìm lại trong users (cho tk cũ chưa migrate)
      // Nhưng nếu bạn đã migrate hết thì có thể bỏ đoạn else này
      return null;
    } catch (e) {
      debugPrint("Lỗi khi lấy thông tin cửa hàng: $e");
      return null;
    }
  }

  Future<void> updateStoreDetails(String storeId,
      Map<String, dynamic> data) async {
    try {
      await _db.collection('stores').doc(storeId).set(
          data, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Lỗi khi cập nhật thông tin cửa hàng: $e");
      rethrow;
    }
  }

  Future<DocumentReference> createPrintJobDocument(Map<String, dynamic> jobData,
      String storeId) async {
    try {
      final dataToSave = {
        ...jobData,
        'storeId': storeId,
      };
      return await _db.collection('print_jobs').add(dataToSave);
    } catch (e) {
      debugPrint('Lỗi khi tạo document lệnh in trên cloud: $e');
      rethrow;
    }
  }

  Future<bool> isProductCodeDuplicate({
    required String storeId,
    required String productCode,
    String? currentProductId,
  }) async {
    final query = await _db
        .collection('products')
        .where('storeId', isEqualTo: storeId)
        .where('productCode', isEqualTo: productCode.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) return false;

    // Nếu chính là doc đang sửa thì không tính trùng
    if (currentProductId != null && query.docs.first.id == currentProductId) {
      return false;
    }
    return true;
  }

  Future<CustomerModel> addCustomer(Map<String, dynamic> customerData) async {
    try {
      final formattedData = Map<String, dynamic>.from(customerData);
      debugPrint(">>> DEBUG: Dữ liệu GỐC nhận từ Dialog: $customerData");

      // 1. CHUẨN HÓA VÀ ÉP KIỂU AN TOÀN (Làm cho các trường trống trở thành null)
      String? safeTitleCase(dynamic value) {
        final String? str = value as String?;
        if (str == null || str.trim().isEmpty) return null;
        return _toTitleCase(str);
      }

      String? safeValue(dynamic value) {
        final String? str = value as String?;
        return (str == null || str
            .trim()
            .isEmpty) ? null : str;
      }

      formattedData['name'] = safeTitleCase(customerData['name']);
      formattedData['address'] = safeTitleCase(customerData['address']);
      formattedData['companyName'] = safeTitleCase(customerData['companyName']);
      formattedData['companyAddress'] =
          safeTitleCase(customerData['companyAddress']);

      // Các trường không cần TitleCase nhưng cần đảm bảo là null nếu rỗng
      formattedData['email'] = safeValue(customerData['email']);
      formattedData['citizenId'] = safeValue(customerData['citizenId']);
      formattedData['taxId'] = safeValue(customerData['taxId']);

      // Xử lý customerGroupName
      if (customerData['customerGroupName'] != null) {
        formattedData['customerGroupName'] =
            safeTitleCase(customerData['customerGroupName']);
      }

      // Xóa các trường null để Firestore không lưu
      // Lưu ý: Các trường số (0 hoặc 0.0) không bị xóa ở đây.
      formattedData.removeWhere((key, value) => value == null);
      debugPrint(
          ">>> DEBUG: Dữ liệu ĐÃ CHUẨN HÓA trước khi gửi DB: $formattedData");
      formattedData['createdAt'] = FieldValue.serverTimestamp();

      // 2. Thêm vào Firestore
      final docRef = await _db.collection('customers').add(formattedData);
      debugPrint(">>> DEBUG: ID khách hàng mới: ${docRef.id}");

      // 3. Cập nhật và trả về Model
      formattedData['id'] = docRef.id;

      // Khôi phục lại các giá trị bắt buộc/default nếu bị xóa (chắc chắn phải có)
      formattedData['phone'] ??= '';
      formattedData['storeId'] ??= '';
      formattedData['searchKeys'] ??= [];

      // THÊM: Đảm bảo các trường số có giá trị mặc định cho CustomerModel.fromMap
      // Việc này đảm bảo CustomerModel.fromMap không gặp lỗi ép kiểu từ null sang num
      formattedData['points'] ??= 0;
      formattedData['debt'] ??=
      0.0; // debt là nullable trong Model, nhưng gán 0.0 nếu chưa có vẫn an toàn
      formattedData['totalSpent'] ??= 0.0;

      // Cần Timestamp thay vì FieldValue khi tạo model cục bộ
      formattedData['createdAt'] = Timestamp.now();
      debugPrint(">>> DEBUG: Dữ liệu CUỐI CÙNG đưa vào Model: $formattedData");

      // Tạo và trả về Model
      return CustomerModel.fromMap(formattedData);
    } catch (e) {
      debugPrint(">>> DEBUG (LỖI GỐC): Xảy ra lỗi khi tạo Model: $e");
      // Ném lại Exception để hàm _saveForm bắt được và hiển thị lỗi.
      throw Exception('Lỗi xử lý dữ liệu khách hàng: $e');
    }
  }

  Future<void> updateCustomer(String customerId,
      Map<String, dynamic> data) async {
    try {
      final formattedData = Map<String, dynamic>.from(data);
      formattedData['name'] = _toTitleCase(data['name']);
      formattedData['address'] = _toTitleCase(data['address']);
      formattedData['companyName'] = _toTitleCase(data['companyName']);
      formattedData['companyAddress'] = _toTitleCase(data['companyAddress']);
      if (data['customerGroup'] != null && data['customerGroup'].isNotEmpty) {
        formattedData['customerGroup'] = _toTitleCase(data['customerGroup']);
      }
      formattedData['updatedAt'] = FieldValue.serverTimestamp();
      await _db.collection('customers').doc(customerId).update(formattedData);
    } catch (e) {
      throw Exception('Không thể cập nhật khách hàng: $e');
    }
  }

  Future<String> addCustomerGroup(String groupName, String storeId) async {
    final formattedName = _toTitleCase(groupName);
    final docRef = await _db.collection('customer_groups').add({
      'name': formattedName,
      'storeId': storeId,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  Future<List<CustomerGroupModel>> getCustomerGroups(String storeId) async {
    try {
      final snapshot = await _db
          .collection('customer_groups')
          .where('storeId', isEqualTo: storeId)
          .orderBy('name')
          .get();
      return snapshot.docs
          .map((doc) => CustomerGroupModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint("Lỗi khi lấy nhóm khách hàng: $e");
      return [];
    }
  }

  Future<void> updateCustomerGroup(String groupId, String newName) async {
    if (newName
        .trim()
        .isEmpty) {
      throw Exception('Tên nhóm không được để trống');
    }
    try {
      await _db
          .collection('customer_groups')
          .doc(groupId)
          .update({ 'name': _toTitleCase(newName)});
    } catch (e) {
      throw Exception('Không thể cập nhật nhóm khách hàng: $e');
    }
  }

  Future<bool> checkCustomerGroupInUse(String groupId, String storeId) async {
    final snapshot = await _db
        .collection('customers')
        .where('storeId', isEqualTo: storeId)
        .where('customerGroupId', isEqualTo: groupId)
        .limit(1)
        .get();
    return snapshot.docs.isNotEmpty;
  }

  Future<void> deleteCustomerGroup(String groupId, String storeId) async {
    try {
      // 1. Kiểm tra xem nhóm có đang được sử dụng không (truyền storeId)
      final isInUse = await checkCustomerGroupInUse(groupId, storeId);
      if (isInUse) {
        throw Exception(
            'Không thể xóa nhóm đang được sử dụng. Vui lòng chuyển các khách hàng sang nhóm khác trước.');
      }

      // 2. Nếu không, tiến hành xóa (chỉ xóa doc đúng)
      // Mặc dù doc ID là duy nhất, kiểm tra storeId vẫn an toàn hơn
      final docRef = _db.collection('customer_groups').doc(groupId);
      final doc = await docRef.get();
      if (doc.exists && doc.data()?['storeId'] == storeId) {
        await docRef.delete();
      } else if (!doc.exists) {
        debugPrint("Nhóm $groupId không tồn tại để xóa.");
      } else {
        throw Exception('Bạn không có quyền xóa nhóm này.');
      }
    } catch (e) {
      // Ném lại lỗi cụ thể nếu có
      if (e is Exception && e.toString().contains('Không thể xóa')) {
        rethrow;
      }
      // Ném lỗi chung
      throw Exception('Không thể xóa nhóm khách hàng: $e');
    }
  }

  Stream<List<CustomerModel>> searchCustomers(String query, String storeId,
      {String? groupId}) {
    try {
      Query queryRef = _db.collection('customers').where(
          'storeId', isEqualTo: storeId);

      if (groupId != null && groupId.isNotEmpty) {
        queryRef = queryRef.where('customerGroupId', isEqualTo: groupId);
      }

      if (query.isNotEmpty) {
        queryRef =
            queryRef.where('searchKeys', arrayContains: query.toLowerCase());
      }

      return queryRef.snapshots().map((snapshot) =>
          snapshot.docs
              .map((doc) => CustomerModel.fromFirestore(doc))
              .toList());
    } catch (e) {
      debugPrint("Lỗi khi tìm khách hàng: $e");
      return Stream.value([]);
    }
  }

  Future<CustomerModel?> getCustomerById(String customerId) async {
    final doc = await _db.collection('customers').doc(customerId).get();
    if (doc.exists) {
      return CustomerModel.fromFirestore(doc);
    }
    return null;
  }

  Future<void> updateCustomerDebt(String customerId, double debtAmount) async {
    try {
      final customerRef = _db.collection('customers').doc(customerId);
      await customerRef.update({
        'debt': FieldValue.increment(debtAmount),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Lỗi khi cập nhật công nợ khách hàng: $e");
      throw Exception('Không thể cập nhật công nợ cho khách hàng.');
    }
  }

  Future<bool> isCustomerPhoneDuplicate({
    required String phone,
    required String storeId,
  }) async {
    final query = await _db
        .collection('customers')
        .where('storeId', isEqualTo: storeId)
        .where('phone', isEqualTo: phone)
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<List<BillModel>> getBillsByCustomer(String customerId) async {
    try {
      final snapshot = await _db
          .collection('bills')
          .where('customerId', isEqualTo: customerId)
          .orderBy('createdAt', descending: true)
          .get();
      // Giả định bạn có BillModel.fromFirestore để parse dữ liệu
      return snapshot.docs.map((doc) => BillModel.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint("Lỗi khi lấy hóa đơn của khách hàng: $e");
      return [];
    }
  }

  Future<String> addBill(Map<String, dynamic> billData) async {
    try {
      // 1) Kiểm tra storeId
      final String? storeId = billData['storeId'] as String?;
      if (storeId == null || storeId.isEmpty) {
        throw Exception('Store ID is required to create a bill.');
      }

      // 2) Tạo datePrefix ddMMyy (vd: 190925)
      final now = DateTime.now();
      final String datePrefix = DateFormat('ddMMyy').format(now);

      // 3) Lấy STT an toàn theo ngày (dùng collection 'counters')
      final counterDocRef = _db.collection('counters').doc(
          'bill_counts_$storeId');
      final String counterField = 'count_$datePrefix';

      int nextNumber = 0;

      // Trên Windows/Desktop có lúc runTransaction không ổn => làm giống hàm generateNextProductCode
      if (kIsWeb || Platform.isWindows) {
        final snap = await counterDocRef.get();
        if (!snap.exists) {
          await counterDocRef.set({counterField: 1});
          nextNumber = 1;
        } else {
          final data = snap.data() ?? {};
          final current = (data[counterField] ?? 0) as int;
          nextNumber = current + 1;
          await counterDocRef.update({counterField: nextNumber});
        }
      } else {
        await _db.runTransaction((tx) async {
          final snap = await tx.get(counterDocRef);
          final data = snap.data() ?? {};
          final current = (data[counterField] ?? 0) as int;
          nextNumber = current + 1;
          if (!snap.exists) {
            tx.set(counterDocRef, {counterField: nextNumber});
          } else {
            tx.update(counterDocRef, {counterField: nextNumber});
          }
        });
      }

      // 4) Ghép billId theo yêu cầu: <storeId>_bill<ddMMyy><stt4>
      final String billId = '${storeId}_BILL$datePrefix${nextNumber
          .toString()
          .padLeft(4, '0')}';

      // 5) Chuẩn hóa dữ liệu lưu bill
      final dataToSave = Map<String, dynamic>.from(billData);
      dataToSave['createdAt'] ??= FieldValue.serverTimestamp();
      dataToSave['datePrefix'] = datePrefix;
      dataToSave['sequence'] = nextNumber;
      dataToSave['status'] ??= 'completed';

      // 6) Lưu bằng doc(billId) thay vì add()
      await _db.collection('bills').doc(billId).set(dataToSave);

      final String? customerId = billData['customerId'] as String?;
      final num? totalPayableNum = billData['totalPayable'] as num?; // Lấy kiểu num cho an toàn
      final double totalPayable = totalPayableNum?.toDouble() ??
          0.0; // Chuyển sang double

      // Chỉ cập nhật nếu có customerId và totalPayable > 0
      if (customerId != null && customerId.isNotEmpty && totalPayable > 0) {
        try {
          final customerRef = _db.collection('customers').doc(customerId);
          // Dùng FieldValue.increment để cộng dồn an toàn
          await customerRef.update({
            'totalSpent': FieldValue.increment(totalPayable),
            'updatedAt': FieldValue.serverTimestamp(),
            // Cập nhật thời gian sửa đổi khách hàng
          });
          debugPrint('Đã cập nhật totalSpent cho khách hàng $customerId');
        } catch (e) {
          // Ghi log lỗi nhưng không làm dừng hàm addBill
          debugPrint(
              '!!! Lỗi khi cập nhật totalSpent cho khách hàng $customerId: $e');
          // Bạn có thể thêm xử lý báo lỗi nếu cần, nhưng không nên throw Exception ở đây
        }
      }

      return billId;
    } catch (e) {
      throw Exception('Không thể tạo bill: $e');
    }
  }

  Future<void> savePointsSettings({
    required String storeId,
    required double earnRate,
    required double redeemRate,
  }) async {
    try {
      final docId = '${storeId}_PointsSettings';
      final docRef = _db.collection('promotions').doc(docId);

      await docRef.set({
        'storeId': storeId,
        'earnRateVnd': earnRate, // Số tiền để kiếm 1 điểm
        'redeemRateVnd': redeemRate, // Giá trị của 1 điểm
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(
          merge: true)); // Dùng merge để không ghi đè các trường khác nếu có

    } catch (e) {
      throw Exception('Không thể lưu cài đặt tích điểm: $e');
    }
  }

  Future<Map<String, double>> loadPointsSettings(String storeId) async {
    try {
      final docId = '${storeId}_PointsSettings';
      final docSnapshot = await _db.collection('promotions').doc(docId).get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        return {
          'earnRate': (data['earnRateVnd'] as num?)?.toDouble() ?? 0.0,
          'redeemRate': (data['redeemRateVnd'] as num?)?.toDouble() ?? 0.0,
        };
      }
      return {
        'earnRate': 0.0,
        'redeemRate': 0.0
      }; // Trả về giá trị mặc định nếu chưa có
    } catch (e) {
      throw Exception('Không thể tải cài đặt tích điểm: $e');
    }
  }

  DocumentReference getOrderReference(String orderId) {
    return _firestore.collection('orders').doc(orderId);
  }

  DocumentReference getNewOrderReference() {
    return _firestore.collection('orders').doc();
  }

  Future<T?> runTransaction<T>(TransactionHandler<T> handler) {
    return _firestore.runTransaction(handler);
  }

  Future<void> updateCustomerPoints(String customerId, int pointsChange) async {
    if (pointsChange == 0) return;
    try {
      final customerRef = _db.collection('customers').doc(customerId);
      await customerRef.update({
        'points': FieldValue.increment(pointsChange),
        // Dùng increment để cộng/trừ an toàn
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Lỗi khi cập nhật điểm thưởng khách hàng: $e");
      throw Exception('Không thể cập nhật điểm thưởng cho khách hàng.');
    }
  }

  Stream<List<VoucherModel>> getVouchersStream(String storeId) {
    return _db
        .collection('promotions')
        .where('storeId', isEqualTo: storeId)
        .where('type', isEqualTo: 'voucher')
        .snapshots() // Dòng này trả về Stream<QuerySnapshot>
        .map((snapshot) =>
        snapshot.docs // Dùng .map để chuyển đổi nó
            .map((doc) => VoucherModel.fromFirestore(doc))
            .toList());
  }

  Future<void> addVoucher(Map<String, dynamic> voucherData) async {
    await _db.collection('promotions').add({
      ...voucherData,
      'type': 'voucher',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateVoucher(String id, Map<String, dynamic> data) async {
    await _db.collection('promotions').doc(id).update(data);
  }

  Future<void> deleteVoucher(String id) async {
    await _db.collection('promotions').doc(id).delete();
  }

  Future<VoucherModel?> validateVoucher(String code, String storeId) async {
    final query = await _db
        .collection('promotions')
        .where('storeId', isEqualTo: storeId)
        .where('type', isEqualTo: 'voucher')
        .where('code', isEqualTo: code.toUpperCase())
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      return null;
    }

    final voucher = VoucherModel.fromFirestore(query.docs.first);

    // <<< THÊM VÀO: KIỂM TRA THỜI GIAN BẮT ĐẦU >>>
    if (voucher.startAt != null &&
        voucher.startAt!.toDate().isAfter(DateTime.now())) {
      return null; // Voucher chưa tới ngày áp dụng
    }

    // Kiểm tra ngày hết hạn
    if (voucher.expiryAt != null &&
        voucher.expiryAt!.toDate().isBefore(DateTime.now())) {
      await updateVoucher(voucher.id, {'isActive': false});
      return null;
    }

    if (voucher.quantity != null && voucher.quantity! <= 0) {
      await updateVoucher(voucher.id, {'isActive': false});
      return null;
    }

    return voucher;
  }

  // Hàm này dùng để set hoặc xóa voucher mặc định
  Future<void> setDefaultVoucher(String storeId, String? voucherCode) async {
    // Nếu voucherCode là null => Xóa mặc định
    // Nếu có giá trị => Đặt làm mặc định
    await _db.collection('stores').doc(storeId).set({
      'defaultVoucherCode': voucherCode
    }, SetOptions(merge: true));
  }

  // Hàm lấy setting của store (để biết voucher nào đang là mặc định)
  Stream<DocumentSnapshot> getStoreSettingsStream(String storeId) {
    return _db.collection('stores').doc(storeId).snapshots();
  }

  Future<void> updateProductStock(WriteBatch batch, String productId,
      double quantityChange) {
    final productRef = _db.collection('products').doc(productId);
    batch.update(productRef, {'stock': FieldValue.increment(-quantityChange)});
    return Future.value();
  }

  Future<bool> isTableOccupied(String tableId, String storeId) async {
    final query = await _db.collection('orders')
    // SỬA 1: Thêm truy vấn theo storeId để đảm bảo đúng cửa hàng
        .where('storeId', isEqualTo: storeId)
        .where('tableId', isEqualTo: tableId)
    // SỬA 2: Dùng đúng trạng thái là 'active'
        .where('status', isEqualTo: 'active')
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password); // Chuyển mật khẩu thành bytes
    final digest = sha256.convert(bytes); // Băm bằng thuật toán SHA-256
    return digest.toString(); // Trả về chuỗi đã mã hóa
  }

  Future<void> createEmployeeProfile({
    required String storeId,
    required String name,
    required String phoneNumber,
    required String password,
    required String role,
    required String ownerUid,
  }) async {
    try {
      final existingUser = await _db
          .collection('users')
          .where('storeId', isEqualTo: storeId)
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (existingUser.docs.isNotEmpty) {
        throw Exception('Số điện thoại này đã được sử dụng.');
      }

      // MÃ HÓA MẬT KHẨU TRƯỚC KHI LƯU
      final hashedPassword = _hashPassword(password);

      final docRef = _db.collection('users').doc();
      await docRef.set({
        'uid': docRef.id,
        'email': null,
        'storeId': storeId,
        'name': _toTitleCase(name),
        'phoneNumber': phoneNumber,
        'password': hashedPassword, // LƯU MẬT KHẨU ĐÃ MÃ HÓA
        'role': role,
        'active': true,
        'ownerUid': ownerUid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Không thể tạo hồ sơ nhân viên: $e');
    }
  }

  Future<UserModel?> getEmployeeByPhone(String phoneNumber,
      String plainPassword) async {
    try {
      final query = await _db
          .collection('users')
          .where('phoneNumber', isEqualTo: phoneNumber)
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final userDoc = query.docs.first;
        final data = userDoc.data();

        // Chỉ xử lý nếu là tài khoản nhân viên (có trường 'password')
        if (data.containsKey('password')) {
          final storedHash = data['password'];
          final enteredPasswordHash = _hashPassword(plainPassword);

          // So sánh mật khẩu đã mã hóa
          if (storedHash == enteredPasswordHash) {
            return UserModel.fromFirestore(userDoc);
          }
        }
      }
      return null;
    } catch (e) {
      throw Exception('Lỗi tìm người dùng: $e');
    }
  }

  Stream<UserModel?> streamUserProfile(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((doc) {
      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      }
      return null;
    });
  }

  Future<void> updateUserPassword(String userId, String newPassword) async {
    final hashedPassword = _hashPassword(newPassword);
    await _db.collection('users').doc(userId).update({
      'password': hashedPassword,
    });
  }

  Future<bool> isPhoneNumberInUse({
    required String phone,
    required String storeId,
    String? currentUserId,
  }) async {
    final query = _db
        .collection('users')
        .where('storeId', isEqualTo: storeId)
        .where('phoneNumber', isEqualTo: phone);

    final result = await query.limit(1).get();

    if (result.docs.isEmpty) {
      return false;
    }

    if (currentUserId != null && result.docs.first.id == currentUserId) {
      return false;
    }

    return true;
  }

  Future<void> deleteUser(String userId) async {
    try {
      await _db.collection('users').doc(userId).delete();
    } catch (e) {
      throw Exception('Không thể xóa người dùng: $e');
    }
  }

  Future<List<UserModel>> getUsersByStore(String storeId) async {
    try {
      final querySnapshot = await _db
          .collection('users')
          .where('storeId', isEqualTo: storeId)
          .where('active', isEqualTo: true) // Chỉ lấy nhân viên đang hoạt động
          .get();

      return querySnapshot.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Lỗi khi lấy danh sách nhân viên: $e');
      return [];
    }
  }

  Stream<List<QuickNoteModel>> getQuickNotes(String storeId) {
    return _db
        .collection('quick_notes')
        .where('storeId', isEqualTo: storeId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => QuickNoteModel.fromFirestore(doc))
            .toList());
  }

  Future<void> saveQuickNote(QuickNoteModel note) async {
    try {
      final data = note.toMap();

      if (note.id.isEmpty) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await _db.collection('quick_notes').add(data);
      } else {
        data['updatedAt'] = FieldValue.serverTimestamp();
        await _db.collection('quick_notes').doc(note.id).update(data);
      }
    } catch (e) {
      throw Exception('Không thể lưu ghi chú nhanh: $e');
    }
  }

  Future<void> deleteQuickNote(String noteId) async {
    try {
      await _db.collection('quick_notes').doc(noteId).delete();
    } catch (e) {
      throw Exception('Không thể xóa ghi chú nhanh: $e');
    }
  }

  Stream<QuerySnapshot> getPaymentMethods(String storeId) {
    return _db
        .collection('payment_methods')
        .where('storeId', isEqualTo: storeId)
        .where('active', isEqualTo: true)
        .snapshots();
  }

  Future<void> addPaymentMethod(PaymentMethodModel method) {
    return _db
        .collection('payment_methods')
        .add(method.toMap());
  }

  Future<void> updatePaymentMethod(PaymentMethodModel method) {
    return _db
        .collection('payment_methods')
        .doc(method.id)
        .update(method.toMap());
  }

  Future<void> updateCustomerGroupNameInCustomers(String groupId,
      String newName, String storeId) async {
    final query = _db.collection('customers')
        .where('storeId', isEqualTo: storeId)
        .where('customerGroupId', isEqualTo: groupId);

    final snapshot = await query.get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'customerGroupName': newName});
    }
    await batch.commit();
  }

  WriteBatch batch() {
    return _db.batch();
  }

  DocumentReference getTableReference(String tableId) {
    return _db.collection('tables').doc(tableId);
  }

  Future<String> addWebOrder(Map<String, dynamic> orderData) async {
    try {
      final docRef = await _db.collection('web_orders').add(orderData);
      return docRef.id;
    } catch (e) {
      throw Exception('Không thể tạo đơn hàng web: $e');
    }
  }

  Future<void> confirmAtTableWebOrder(WebOrderModel webOrder,
      String staffName) async {
    // 1. Lấy tham chiếu đến 2 document
    final webOrderRef = _db.collection('web_orders').doc(webOrder.id);
    // ID của đơn hàng tại bàn CHÍNH LÀ ID CỦA BÀN
    final tableOrderRef = _db.collection('orders').doc(webOrder.tableId);

    // 2. Chạy Transaction
    return _db.runTransaction((transaction) async {
      final tableOrderSnap = await transaction.get(tableOrderRef);

      final List<Map<String, dynamic>> itemsToSave;
      final double totalAmount;
      final int currentVersion;

      // Lấy các món ăn từ web order và đánh dấu "đã gửi"
      // Vì chúng ta sẽ báo bếp ngay
      final List<Map<String, dynamic>> itemsToAdd = webOrder.items.map((item) {
        return item.copyWith(sentQuantity: item.quantity).toMap();
      }).toList();

      final double totalToAdd = webOrder.totalAmount;

      if (tableOrderSnap.exists) {
        // --- BÀN ĐÃ CÓ KHÁCH (Merging) ---
        final tableData = tableOrderSnap.data() as Map<String, dynamic>;
        currentVersion = (tableData['version'] as num?)?.toInt() ?? 0;

        final List<Map<String, dynamic>> existingItems =
        List<Map<String, dynamic>>.from(tableData['items'] ?? []);
        final double existingTotal =
            (tableData['totalAmount'] as num?)?.toDouble() ?? 0.0;

        // Nối 2 danh sách món ăn
        // (Lưu ý: Logic gom nhóm phức tạp hơn nên tạm thời chỉ nối list)
        itemsToSave = [...existingItems, ...itemsToAdd];
        totalAmount = existingTotal + totalToAdd;

        // Cập nhật đơn hàng tại bàn
        transaction.update(tableOrderRef, {
          'items': itemsToSave,
          'totalAmount': totalAmount,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
          // Giữ nguyên status (đang active)
        });
      } else {
        // --- BÀN TRỐNG (Tạo mới) ---
        itemsToSave = itemsToAdd;
        totalAmount = totalToAdd;

        // Tạo đơn hàng tại bàn mới
        transaction.set(tableOrderRef, {
          'id': tableOrderRef.id, // ID đơn hàng là ID của bàn
          'tableId': webOrder.tableId,
          'tableName': webOrder.tableName,
          'status': 'active', // Đã được xác nhận
          'startTime': webOrder.createdAt, // Lấy thời gian khách order
          'items': itemsToSave,
          'totalAmount': totalAmount,
          'storeId': webOrder.storeId,
          'createdAt': webOrder.createdAt,
          'createdByUid': webOrder.items.first.addedBy, // 'Guest...'
          'createdByName': 'Guest (QR)',
          'numberOfCustomers': 1,
          'version': 1,
        });
      }

      // 3. Cập nhật trạng thái web order là "đã xác nhận"
      transaction.update(webOrderRef, {
        'status': 'confirmed',
        'confirmedBy': staffName,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> unlinkMergedTables(String targetTableId) async {
    try {
      // 1. Tìm tất cả các 'TableModel' có trường 'mergedWithTableId'
      final query = _db
          .collection('tables')
          .where('mergedWithTableId', isEqualTo: targetTableId);

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) {
        return;
      }

      // 2. Dùng WriteBatch để cập nhật tất cả chúng về 'null'
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {'mergedWithTableId': null});
      }

      await batch.commit();
      debugPrint('Đã gỡ liên kết cho ${snapshot.docs.length} bàn.');
    } catch (e) {
      debugPrint("Lỗi nghiêm trọng khi gỡ liên kết bàn gộp: $e");
    }
  }

  Future<Map<String, dynamic>?> getStoreTaxSettings(String storeId) async {
    try {
      final doc = await _db.collection('store_tax_settings').doc(storeId).get();
      if (doc.exists) {
        return doc.data();
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi getStoreTaxSettings: $e");
      return null;
    }
  }

  Future<void> updateStoreTaxSettings(String storeId,
      Map<String, dynamic> settings) async {
    try {
      final settingsToSave = Map<String, dynamic>.from(settings);
      settingsToSave['storeId'] = storeId;
      await _db.collection('store_tax_settings').doc(storeId).set(
          settingsToSave, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Lỗi updateStoreTaxSettings: $e");
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getTaxThresholds() async {
    try {
      final doc = await _db
          .collection('app_config')
          .doc('tax_thresholds')
          .get();
      if (doc.exists && doc.data() != null) {
        return doc.data()!;
      }
      return {
        "hkd_revenue_threshold_group1": 200000000,
        "hkd_revenue_threshold_group2": 3000000000,
        "company_revenue_threshold_tndn_15": 3000000000
      };
    } catch (e) {
      debugPrint("Lỗi getTaxThresholds, dùng giá trị mặc định: $e");
      return {
        "hkd_revenue_threshold_group1": 200000000,
        "hkd_revenue_threshold_group2": 3000000000,
        "company_revenue_threshold_tndn_15": 3000000000
      };
    }
  }

  Future<void> updateBill(String billId, Map<String, dynamic> data) async {
    await _firestore.collection('bills').doc(billId).update(data);
  }

  // 2. Hàm mới: Lưu Bill với ID tự tạo (thay vì add() tự sinh ID)
  Future<void> setBill(String billId, Map<String, dynamic> data) async {
    await _firestore.collection('bills').doc(billId).set(data);
  }

  // --- QUẢN LÝ DISCOUNT (ROOT COLLECTION) ---

  // 1. Lấy danh sách Discount theo StoreId
  Stream<List<DiscountModel>> getDiscountsStream(String storeId) {
    return _db
        .collection('discounts') // Lưu ở Root Collection
        .where('storeId', isEqualTo: storeId) // Lọc theo StoreId
        .orderBy(
        'updatedAt', descending: true) // Sắp xếp mới nhất lên đầu (tuỳ chọn)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs
            .map((doc) => DiscountModel.fromFirestore(doc))
            .toList());
  }

  // 2. Lưu hoặc Cập nhật Discount
  // Hàm này xử lý cả tạo mới (nếu id rỗng) và cập nhật (nếu có id)
  Future<void> saveDiscount(DiscountModel discount) async {
    try {
      final collectionRef = _db.collection('discounts');

      // Nếu model đã có ID thì dùng ID đó, nếu không thì tạo ID mới
      final docRef = discount.id.isNotEmpty
          ? collectionRef.doc(discount.id)
          : collectionRef.doc();

      final data = discount.toMap();

      // Đảm bảo các trường quan trọng luôn đúng
      data['id'] = docRef.id;
      data['storeId'] = discount.storeId;
      data['updatedAt'] = FieldValue.serverTimestamp();

      // Nếu là tạo mới (dựa vào check ID ban đầu của model)
      if (discount.id.isEmpty) {
        data['createdAt'] = FieldValue.serverTimestamp();
      }

      // Sử dụng SetOptions(merge: true) để an toàn khi cập nhật
      await docRef.set(data, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Không thể lưu chương trình giảm giá: $e');
    }
  }

  // 3. Xóa Discount
  Future<void> deleteDiscount(String discountId) async {
    try {
      await _db.collection('discounts').doc(discountId).delete();
    } catch (e) {
      throw Exception('Không thể xóa chương trình giảm giá: $e');
    }
  }


  // 1. Lấy danh sách Mua X Tặng Y theo StoreId
  Stream<List<Map<String, dynamic>>> getBuyXGetYStream(String storeId) {
    return _db
        .collection('promotions')
        .where('storeId', isEqualTo: storeId)
        .where('type', isEqualTo: 'buy_x_get_y')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) =>
        snapshot.docs.map((doc) {
          final data = doc.data();
          data['id'] = doc.id; // Gán ID vào map để dùng sau này
          return data;
        }).toList());
  }

  // 2. Lưu hoặc Cập nhật Mua X Tặng Y
  Future<void> saveBuyXGetY(Map<String, dynamic> data, {String? id}) async {
    try {
      final collectionRef = _db.collection('promotions');

      // Nếu có ID thì update, không thì tạo mới
      final docRef = (id != null && id.isNotEmpty)
          ? collectionRef.doc(id)
          : collectionRef.doc();

      final dataToSave = Map<String, dynamic>.from(data);
      dataToSave['updatedAt'] = FieldValue.serverTimestamp();

      // Nếu tạo mới
      if (id == null || id.isEmpty) {
        dataToSave['createdAt'] = FieldValue.serverTimestamp();
        dataToSave['type'] = 'buy_x_get_y';
      }

      await docRef.set(dataToSave, SetOptions(merge: true));
    } catch (e) {
      throw Exception('Không thể lưu chương trình Mua X Tặng Y: $e');
    }
  }

  // 3. Xóa Mua X Tặng Y
  Future<void> deleteBuyXGetY(String id) async {
    try {
      await _db.collection('promotions').doc(id).delete();
    } catch (e) {
      throw Exception('Không thể xóa chương trình: $e');
    }
  }

  // [THÊM MỚI] Lấy danh sách sản phẩm theo danh sách ID
  Future<List<ProductModel>> getProductsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    try {
      // Firestore giới hạn whereIn tối đa 10 phần tử
      // Vì logic Mua X Tặng Y chỉ cần lấy 2 sản phẩm nên không lo vượt quá giới hạn
      final snapshot = await _db
          .collection('products')
          .where(FieldPath.documentId, whereIn: ids)
          .get();

      return snapshot.docs
          .map((doc) => ProductModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint("Lỗi lấy sản phẩm theo IDs: $e");
      return [];
    }
  }

  Stream<List<Map<String, dynamic>>> getActiveBuyXGetYPromotionsStream(
      String storeId) {
    return _db
        .collection('promotions')
        .where('storeId', isEqualTo: storeId)
        .where('type', isEqualTo: 'buy_x_get_y')
        .where('isActive', isEqualTo: true) // Chỉ lấy cái đang bật
        .snapshots()
        .map((snapshot) {
      final now = DateTime.now();
      // Lọc tiếp ngày tháng ở phía Client (do hạn chế query phức tạp của Firestore)
      return snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        return data;
      }).where((data) {
        if (data['startAt'] != null) {
          final start = (data['startAt'] as Timestamp).toDate();
          if (now.isBefore(start)) return false;
        }
        if (data['endAt'] != null) {
          final end = (data['endAt'] as Timestamp).toDate();
          if (now.isAfter(end)) return false;
        }
        return true;
      }).toList();
    });
  }

  Stream<List<SurchargeModel>> getSurchargesStream(String storeId) {
    return _db
        .collection('surcharges')
        .where('storeId', isEqualTo: storeId)
    // .orderBy('createdAt', descending: true) // <--- BỎ DÒNG NÀY
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => SurchargeModel.fromFirestore(doc))
        .toList());
  }

  // 2. Lấy danh sách active (Dùng cho Payment)
  Future<List<SurchargeModel>> getActiveSurcharges(String storeId) async {
    final now = Timestamp.now();
    try {
      final snapshot = await _db
          .collection('surcharges')
          .where('storeId', isEqualTo: storeId)
          .where('isActive', isEqualTo: true)
          .get();

      final allActive = snapshot.docs.map((doc) => SurchargeModel.fromFirestore(doc)).toList();

      // Lọc thủ công ngày giờ
      return allActive.where((s) {
        final startOk = s.startAt == null || s.startAt!.compareTo(now) <= 0;
        final endOk = s.endAt == null || s.endAt!.compareTo(now) >= 0;
        return startOk && endOk;
      }).toList();
    } catch (e) {
      debugPrint("Lỗi lấy phụ thu active: $e");
      return [];
    }
  }

  Future<void> addSurcharge(Map<String, dynamic> data) async => await _db.collection('surcharges').add(data);
  Future<void> updateSurcharge(String id, Map<String, dynamic> data) async => await _db.collection('surcharges').doc(id).update(data);
  Future<void> deleteSurcharge(String id) async => await _db.collection('surcharges').doc(id).delete();

  Future<void> updateWebOrderStatus(String orderId, String newStatus) async {
    try {
      await _db.collection('web_orders').doc(orderId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Không thể cập nhật trạng thái Web Order: $e');
    }
  }
}