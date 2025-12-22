// lib/models/user_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String? email;
  final String storeId;
  final String? name;
  final String phoneNumber;
  final String role;
  final bool active;
  final String? password;
  final String? businessType;
  final Timestamp? createdAt;
  final String? storeName;
  final String? storeAddress;
  final String? serverListenMode;
  final Map<String, dynamic>? permissions;
  final String? ownerUid;
  final String? storePhone;
  final String? bankBin;
  final String? bankAccount;
  final String? bankAccountName;
  final Timestamp? subscriptionExpiryDate;
  final String? inactiveReason;
  String? agentId;

  UserModel({
    required this.uid,
    this.email,
    required this.storeId,
    this.name,
    required this.phoneNumber,
    required this.role,
    required this.active,
    this.password,
    this.businessType,
    this.createdAt,
    this.storeName,
    this.storeAddress,
    this.serverListenMode,
    this.ownerUid,
    this.storePhone,
    this.permissions,
    this.bankBin,
    this.bankAccount,
    this.bankAccountName,
    this.subscriptionExpiryDate,
    this.inactiveReason,
    this.agentId,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      uid: doc.id,
      email: data['email'] as String?,
      storeId: data['storeId'] as String? ?? '',
      name: data['name'] as String?,
      phoneNumber: data['phoneNumber'] as String? ?? '',
      role: data['role'] as String? ?? 'order',
      active: data['active'] as bool? ?? true,
      password: data['password'] as String?,
      businessType: data['businessType'] as String?,
      createdAt: data['createdAt'] as Timestamp?,
      storeName: data['storeName'] as String?,
      storeAddress: data['storeAddress'] as String?,
      serverListenMode: data['serverListenMode'] as String?,
      ownerUid: data['ownerUid'] as String?,
      storePhone: data['storePhone'] as String?,
      permissions: data['permissions'] as Map<String, dynamic>?,
      bankBin: data['bankBin'] as String?,
      bankAccount: data['bankAccount'] as String?,
      bankAccountName: data['bankAccountName'] as String?,
      subscriptionExpiryDate: data['subscriptionExpiryDate'] as Timestamp?,
      inactiveReason: data['inactiveReason'] as String?,
      agentId: data['agentId'] as String?,
    );
  }

  UserModel copyWith({
    String? uid,
    String? email,
    String? storeId,
    String? name,
    String? phoneNumber,
    String? role,
    bool? active,
    String? password,
    String? businessType,
    Timestamp? createdAt,
    String? storeName,
    String? storeAddress,
    String? serverListenMode,
    String? ownerUid,
    String? storePhone,
    Map<String, dynamic>? permissions,
    String? bankBin,
    String? bankAccount,
    String? bankAccountName,
    Timestamp? subscriptionExpiryDate,
    String? inactiveReason,
    String? agentId,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      active: active ?? this.active,
      password: password ?? this.password,
      businessType: businessType ?? this.businessType,
      createdAt: createdAt ?? this.createdAt,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      serverListenMode: serverListenMode ?? this.serverListenMode,
      ownerUid: ownerUid ?? this.ownerUid,
      storePhone: storePhone ?? this.storePhone,
      permissions: permissions ?? this.permissions,
      bankBin: bankBin ?? this.bankBin,
      bankAccount: bankAccount ?? this.bankAccount,
      bankAccountName: bankAccountName ?? this.bankAccountName,
      subscriptionExpiryDate: subscriptionExpiryDate ?? this.subscriptionExpiryDate,
      inactiveReason: inactiveReason ?? this.inactiveReason,
      agentId: agentId ?? this.agentId,
    );
  }
}