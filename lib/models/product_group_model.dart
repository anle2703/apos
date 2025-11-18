import 'package:cloud_firestore/cloud_firestore.dart';

class ProductGroupModel {
  final String id;
  final String name;
  final int stt;

  ProductGroupModel({required this.id, required this.name, required this.stt});

  factory ProductGroupModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return ProductGroupModel(
      id: doc.id,
      name: data['name'] ?? '',
      stt: data['stt'] ?? 999,
    );
  }
}