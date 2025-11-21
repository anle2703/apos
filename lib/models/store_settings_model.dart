// File: lib/models/store_settings_model.dart

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

  // --- CÁC TRƯỜNG CHO TEM NHÃN ---
  final bool? printLabelOnKitchen;
  final bool? printLabelOnPayment;
  final double? labelWidth;
  final double? labelHeight;

  // --- TRƯỜNG MỚI: TẮT IN BẾP ---
  final bool? skipKitchenPrint;
  // ------------------------------

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
    this.printLabelOnKitchen,
    this.printLabelOnPayment,
    this.labelWidth,
    this.labelHeight,

    // Thêm vào constructor
    this.skipKitchenPrint,
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

      printLabelOnKitchen       : (d['printLabelOnKitchen'] as bool?),
      printLabelOnPayment       : (d['printLabelOnPayment'] as bool?),
      labelWidth                : (d['labelWidth'] as num?)?.toDouble(),
      labelHeight               : (d['labelHeight'] as num?)?.toDouble(),

      // Đọc từ Map
      skipKitchenPrint          : (d['skipKitchenPrint'] as bool?),
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
    'qrOrderRequiresConfirmation': qrOrderRequiresConfirmation,
    'updatedAt'                 : FieldValue.serverTimestamp(),

    'printLabelOnKitchen'       : printLabelOnKitchen,
    'printLabelOnPayment'       : printLabelOnPayment,
    'labelWidth'                : labelWidth,
    'labelHeight'               : labelHeight,

    // Ghi vào Map
    'skipKitchenPrint'          : skipKitchenPrint,
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
    bool? printLabelOnKitchen,
    bool? printLabelOnPayment,
    double? labelWidth,
    double? labelHeight,

    // Thêm tham số
    bool? skipKitchenPrint,
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
      printLabelOnKitchen: printLabelOnKitchen ?? this.printLabelOnKitchen,
      printLabelOnPayment: printLabelOnPayment ?? this.printLabelOnPayment,
      labelWidth: labelWidth ?? this.labelWidth,
      labelHeight: labelHeight ?? this.labelHeight,

      // Logic copy
      skipKitchenPrint: skipKitchenPrint ?? this.skipKitchenPrint,
    );
  }
}