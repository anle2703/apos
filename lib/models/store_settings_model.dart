import 'package:cloud_firestore/cloud_firestore.dart';

class StoreSettings {
  final bool printBillAfterPayment;
  final bool allowProvisionalBill;
  final bool notifyKitchenAfterPayment;
  final bool showPricesOnReceipt;
  final bool showPricesOnProvisional;
  final int? reportCutoffHour;
  final int? reportCutoffMinute;
  final bool? promptForCash;
  final double? earnRate;
  final double? redeemRate;
  final String? defaultPaymentMethodId;
  final bool? qrOrderRequiresConfirmation;

  const StoreSettings({
    required this.printBillAfterPayment,
    required this.allowProvisionalBill,
    required this.notifyKitchenAfterPayment,
    required this.showPricesOnReceipt,
    required this.showPricesOnProvisional,
    this.reportCutoffHour,
    this.reportCutoffMinute,
    this.promptForCash,
    this.earnRate,
    this.redeemRate,
    this.defaultPaymentMethodId,
    this.qrOrderRequiresConfirmation,

  });

  factory StoreSettings.fromMap(Map<String, dynamic>? m) {
    final d = m ?? const {};
    return StoreSettings(
      printBillAfterPayment     : (d['printBillAfterPayment']     as bool?) ?? true,
      allowProvisionalBill      : (d['allowProvisionalBill']      as bool?) ?? true,
      notifyKitchenAfterPayment : (d['notifyKitchenAfterPayment'] as bool?) ?? false,
      showPricesOnReceipt       : (d['showPricesOnReceipt']       as bool?) ?? true,
      showPricesOnProvisional   : (d['showPricesOnProvisional']   as bool?) ?? true,
      reportCutoffHour          : (d['reportCutoffHour'] as int?),
      reportCutoffMinute        : (d['reportCutoffMinute'] as int?),
      promptForCash             : (d['promptForCash'] as bool?) ?? true,
      earnRate                  : (d['earnRate'] as num?)?.toDouble(),
      redeemRate                : (d['redeemRate'] as num?)?.toDouble(),
      defaultPaymentMethodId    : (d['defaultPaymentMethodId'] as String?),
      qrOrderRequiresConfirmation: (d['qrOrderRequiresConfirmation'] as bool?) ?? false,

    );
  }

  Map<String, dynamic> toMap() => {
    'printBillAfterPayment'     : printBillAfterPayment,
    'allowProvisionalBill'      : allowProvisionalBill,
    'notifyKitchenAfterPayment' : notifyKitchenAfterPayment,
    'showPricesOnReceipt'       : showPricesOnReceipt,
    'showPricesOnProvisional'   : showPricesOnProvisional,
    'reportCutoffHour'          : reportCutoffHour,
    'reportCutoffMinute'        : reportCutoffMinute,
    'promptForCash'             : promptForCash,
    'earnRate'                  : earnRate,
    'redeemRate'                : redeemRate,
    'defaultPaymentMethodId'    : defaultPaymentMethodId,
    'updatedAt'                 : FieldValue.serverTimestamp(),

  };

  StoreSettings copyWith({
    bool? printBillAfterPayment,
    bool? allowProvisionalBill,
    bool? notifyKitchenAfterPayment,
    bool? showPricesOnReceipt,
    bool? showPricesOnProvisional,
    int? reportCutoffHour,
    int? reportCutoffMinute,
    bool? promptForCash,
    double? earnRate,
    double? redeemRate,
    String? defaultPaymentMethodId,
    bool? qrOrderRequiresConfirmation,

  }) {
    return StoreSettings(
      printBillAfterPayment: printBillAfterPayment ?? this.printBillAfterPayment,
      allowProvisionalBill: allowProvisionalBill ?? this.allowProvisionalBill,
      notifyKitchenAfterPayment: notifyKitchenAfterPayment ?? this.notifyKitchenAfterPayment,
      showPricesOnReceipt: showPricesOnReceipt ?? this.showPricesOnReceipt,
      showPricesOnProvisional: showPricesOnProvisional ?? this.showPricesOnProvisional,
      reportCutoffHour: reportCutoffHour ?? this.reportCutoffHour,
      reportCutoffMinute: reportCutoffMinute ?? this.reportCutoffMinute,
      promptForCash: promptForCash ?? this.promptForCash,
      earnRate: earnRate ?? this.earnRate,
      redeemRate: redeemRate ?? this.redeemRate,
      defaultPaymentMethodId: defaultPaymentMethodId ?? this.defaultPaymentMethodId,
      qrOrderRequiresConfirmation: qrOrderRequiresConfirmation ?? this.qrOrderRequiresConfirmation,
    );
  }
}