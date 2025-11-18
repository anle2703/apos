import 'package:cloud_firestore/cloud_firestore.dart';
import 'order_item_model.dart';
import 'product_model.dart';

class WebOrderModel {
  final String id;
  final String storeId;
  final String status;
  final String type;
  final Map<String, dynamic> customerInfo;
  final List<OrderItem> items;
  final double totalAmount;
  final Timestamp createdAt;
  final String tableName;
  final String? tableId;
  final String? note;
  final Timestamp? confirmedAt;

  WebOrderModel({
    required this.id,
    required this.storeId,
    required this.status,
    required this.type,
    required this.customerInfo,
    required this.items,
    required this.totalAmount,
    required this.createdAt,
    required this.tableName,
    this.tableId,
    this.note,
    this.confirmedAt,
  });

  factory WebOrderModel.fromFirestore(DocumentSnapshot doc, List<ProductModel> allProducts) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    final List<OrderItem> parsedItems = (data['items'] as List<dynamic>? ?? [])
        .map((itemData) => OrderItem.fromMap(
      (itemData as Map).cast<String, dynamic>(),
      allProducts: allProducts,
    ))
        .toList();

    return WebOrderModel(
      id: doc.id,
      storeId: data['storeId'] ?? '',
      status: data['status'] ?? 'pending',
      type: data['type'] ?? 'ship',
      customerInfo: (data['customerInfo'] as Map<String, dynamic>?) ?? {},
      items: parsedItems,
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      createdAt: data['createdAt'] ?? Timestamp.now(),
      tableName: data['tableName'] ?? 'Không rõ',
      tableId: data['tableId'] as String?,
      note: data['note'] as String?,
      confirmedAt: data['confirmedAt'] as Timestamp?,
    );
  }

  String get customerName => customerInfo['name'] ?? 'N/A';
  String get customerPhone => customerInfo['phone'] ?? 'N/A';
  String get customerAddress => customerInfo['address'] ?? 'N/A';
}