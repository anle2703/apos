// Tên file: payment_method_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentMethodType { cash, bank, card, other }

class PaymentMethodModel {
  final String id;
  final String storeId;
  final String name;
  final PaymentMethodType type;
  final bool active;
  final String? bankBin;
  final String? bankAccount;
  final String? bankAccountName;
  final bool qrDisplayOnScreen;
  final bool qrDisplayOnBill;
  final bool qrDisplayOnProvisionalBill;

  PaymentMethodModel({
    required this.id,
    required this.storeId,
    required this.name,
    required this.type,
    this.active = true,
    this.bankBin,
    this.bankAccount,
    this.bankAccountName,
    this.qrDisplayOnScreen = false,
    this.qrDisplayOnBill = false,
    this.qrDisplayOnProvisionalBill = false,

  });

  factory PaymentMethodModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return PaymentMethodModel(
      id: doc.id,
      storeId: data['storeId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      type: PaymentMethodType.values.firstWhere(
            (e) => e.name == (data['type'] as String?),
        orElse: () => PaymentMethodType.other,
      ),
      active: data['active'] as bool? ?? true,
      bankBin: data['bankBin'] as String?,
      bankAccount: data['bankAccount'] as String?,
      bankAccountName: data['bankAccountName'] as String?,
      qrDisplayOnScreen: data['qrDisplayOnScreen'] as bool? ?? false,
      qrDisplayOnBill: data['qrDisplayOnBill'] as bool? ?? false,
      qrDisplayOnProvisionalBill:
      data['qrDisplayOnProvisionalBill'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'name': name,
      'type': type.name,
      'active': active,
      'bankBin': bankBin,
      'bankAccount': bankAccount,
      'bankAccountName': bankAccountName,
      'qrDisplayOnScreen': qrDisplayOnScreen,
      'qrDisplayOnBill': qrDisplayOnBill,
      'qrDisplayOnProvisionalBill': qrDisplayOnProvisionalBill,
    };
  }
}