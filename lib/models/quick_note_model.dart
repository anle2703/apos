import 'package:cloud_firestore/cloud_firestore.dart';

class QuickNoteModel {
  final String id;
  final String storeId;
  final String noteText;
  final List<String> productIds; // Danh sách ID sản phẩm được áp dụng
  final Timestamp createdAt;

  QuickNoteModel({
    required this.id,
    required this.storeId,
    required this.noteText,
    required this.productIds,
    required this.createdAt,
  });

  // Chuyển từ Firestore document sang model
  factory QuickNoteModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return QuickNoteModel(
      id: doc.id,
      storeId: data['storeId'] ?? '',
      noteText: data['noteText'] ?? '',
      productIds: List<String>.from(data['productIds'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  // Chuyển từ Map (ví dụ khi tạo mới) sang model
  factory QuickNoteModel.fromMap(String id, Map<String, dynamic> data) {
    return QuickNoteModel(
      id: id,
      storeId: data['storeId'] ?? '',
      noteText: data['noteText'] ?? '',
      productIds: List<String>.from(data['productIds'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  // Chuyển từ model sang Map để lưu lên Firestore
  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'noteText': noteText,
      'productIds': productIds,
      'createdAt': createdAt,
      // id không cần lưu vào map vì nó là Document ID
    };
  }

  // Hàm copyWith để dễ dàng cập nhật
  QuickNoteModel copyWith({
    String? id,
    String? storeId,
    String? noteText,
    List<String>? productIds,
    Timestamp? createdAt,
  }) {
    return QuickNoteModel(
      id: id ?? this.id,
      storeId: storeId ?? this.storeId,
      noteText: noteText ?? this.noteText,
      productIds: productIds ?? this.productIds,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}