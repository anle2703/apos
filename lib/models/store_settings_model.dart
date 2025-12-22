// File: lib/models/store_settings_model.dart

import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSettings {
  final bool printBillAfterPayment;
  final bool allowProvisionalBill;
  final bool notifyKitchenAfterPayment;
  final bool showPricesOnProvisional;
  final int? reportCutoffHour;
  final int? reportCutoffMinute;
  final bool? promptForCash;
  final double? earnRate;
  final double? redeemRate;
  final String? defaultPaymentMethodId;
  final bool? qrOrderRequiresConfirmation;
  final bool? enableShip;
  final bool? enableBooking;
  final bool? printLabelOnKitchen;
  final bool? printLabelOnPayment;
  final double? labelWidth;
  final double? labelHeight;
  final bool? skipKitchenPrint;
  final String? agentId;
  final String? storeName;
  final String? storeAddress;
  final String? storePhone;
  final String? businessType;
  final List<String>? fcmTokens;
  final String? serverListenMode;

  const StoreSettings({
    required this.printBillAfterPayment,
    required this.allowProvisionalBill,
    required this.notifyKitchenAfterPayment,
    required this.showPricesOnProvisional,
    this.reportCutoffHour,
    this.reportCutoffMinute,
    this.promptForCash,
    this.earnRate,
    this.redeemRate,
    this.defaultPaymentMethodId,
    this.qrOrderRequiresConfirmation,
    this.printLabelOnKitchen,
    this.printLabelOnPayment,
    this.labelWidth,
    this.labelHeight,
    this.enableShip,
    this.enableBooking,
    this.agentId,
    this.skipKitchenPrint,
    this.storeName,
    this.storeAddress,
    this.storePhone,
    this.businessType,
    this.fcmTokens,
    this.serverListenMode,
  });

  factory StoreSettings.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    return StoreSettings(
      printBillAfterPayment     : (d['printBillAfterPayment']     as bool?) ?? true,
      allowProvisionalBill      : (d['allowProvisionalBill']      as bool?) ?? true,
      notifyKitchenAfterPayment : (d['notifyKitchenAfterPayment'] as bool?) ?? false,
      showPricesOnProvisional   : (d['showPricesOnProvisional']   as bool?) ?? false,
      reportCutoffHour          : (d['reportCutoffHour'] as num?)?.toInt(),
      reportCutoffMinute        : (d['reportCutoffMinute'] as num?)?.toInt(),
      promptForCash             : (d['promptForCash'] as bool?) ?? true,
      earnRate                  : (d['earnRate'] as num?)?.toDouble(),
      redeemRate                : (d['redeemRate'] as num?)?.toDouble(),
      defaultPaymentMethodId    : (d['defaultPaymentMethodId'] as String?),
      qrOrderRequiresConfirmation: (d['qrOrderRequiresConfirmation'] as bool?) ?? false,
      printLabelOnKitchen       : (d['printLabelOnKitchen'] as bool?),
      printLabelOnPayment       : (d['printLabelOnPayment'] as bool?),
      labelWidth                : (d['labelWidth'] as num?)?.toDouble(),
      labelHeight               : (d['labelHeight'] as num?)?.toDouble(),
      enableShip                : (d['enableShip'] as bool?) ?? true,
      enableBooking             : (d['enableBooking'] as bool?) ?? true,
      skipKitchenPrint          : (d['skipKitchenPrint'] as bool?),
      agentId                   : (d['agentId'] as String?),
      storeName: d['storeName'] as String?,
      storeAddress: d['storeAddress'] as String?,
      storePhone: d['storePhone'] as String?,
      businessType: d['businessType'] as String?,
      fcmTokens: (d['fcmTokens'] as List<dynamic>?)?.map((e) => e.toString()).toList(),
      serverListenMode          : d['serverListenMode'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'printBillAfterPayment'     : printBillAfterPayment,
    'allowProvisionalBill'      : allowProvisionalBill,
    'notifyKitchenAfterPayment' : notifyKitchenAfterPayment,
    'showPricesOnProvisional'   : showPricesOnProvisional,
    'reportCutoffHour'          : reportCutoffHour,
    'reportCutoffMinute'        : reportCutoffMinute,
    'promptForCash'             : promptForCash,
    'earnRate'                  : earnRate,
    'redeemRate'                : redeemRate,
    'defaultPaymentMethodId'    : defaultPaymentMethodId,
    'qrOrderRequiresConfirmation': qrOrderRequiresConfirmation,
    'updatedAt'                 : FieldValue.serverTimestamp(),
    'printLabelOnKitchen'       : printLabelOnKitchen,
    'printLabelOnPayment'       : printLabelOnPayment,
    'labelWidth'                : labelWidth,
    'labelHeight'               : labelHeight,
    'enableShip'                : enableShip,
    'enableBooking'             : enableBooking,
    'skipKitchenPrint'          : skipKitchenPrint,
    'storeName': storeName,
    'storeAddress': storeAddress,
    'storePhone': storePhone,
    'businessType': businessType,
    'agentId': agentId,
    'fcmTokens': fcmTokens,
    'serverListenMode'          : serverListenMode,
  };

  StoreSettings copyWith({
    bool? printBillAfterPayment,
    bool? allowProvisionalBill,
    bool? notifyKitchenAfterPayment,
    bool? showPricesOnProvisional,
    int? reportCutoffHour,
    int? reportCutoffMinute,
    bool? promptForCash,
    double? earnRate,
    double? redeemRate,
    String? defaultPaymentMethodId,
    bool? qrOrderRequiresConfirmation,
    bool? printLabelOnKitchen,
    bool? printLabelOnPayment,
    double? labelWidth,
    double? labelHeight,
    bool? enableShip,
    bool? enableBooking,
    bool? skipKitchenPrint,
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? businessType,
    String? agentId,
    List<String>? fcmTokens,
    String? serverListenMode,
  }) {
    return StoreSettings(
      printBillAfterPayment: printBillAfterPayment ?? this.printBillAfterPayment,
      allowProvisionalBill: allowProvisionalBill ?? this.allowProvisionalBill,
      notifyKitchenAfterPayment: notifyKitchenAfterPayment ?? this.notifyKitchenAfterPayment,
      showPricesOnProvisional: showPricesOnProvisional ?? this.showPricesOnProvisional,
      reportCutoffHour: reportCutoffHour ?? this.reportCutoffHour,
      reportCutoffMinute: reportCutoffMinute ?? this.reportCutoffMinute,
      promptForCash: promptForCash ?? this.promptForCash,
      earnRate: earnRate ?? this.earnRate,
      redeemRate: redeemRate ?? this.redeemRate,
      defaultPaymentMethodId: defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      qrOrderRequiresConfirmation: qrOrderRequiresConfirmation ?? this.qrOrderRequiresConfirmation,
      printLabelOnKitchen: printLabelOnKitchen ?? this.printLabelOnKitchen,
      printLabelOnPayment: printLabelOnPayment ?? this.printLabelOnPayment,
      labelWidth: labelWidth ?? this.labelWidth,
      labelHeight: labelHeight ?? this.labelHeight,
      enableShip: enableShip ?? this.enableShip,
      enableBooking: enableBooking ?? this.enableBooking,
      skipKitchenPrint: skipKitchenPrint ?? this.skipKitchenPrint,
      agentId : agentId ?? this.agentId,
      storeName: storeName ?? this.storeName,
      storeAddress: storeAddress ?? this.storeAddress,
      storePhone: storePhone ?? this.storePhone,
      businessType: businessType ?? this.businessType,
      fcmTokens: fcmTokens ?? this.fcmTokens,
      serverListenMode: serverListenMode ?? this.serverListenMode,
    );
  }
}