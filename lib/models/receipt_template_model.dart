import 'dart:convert';

class ReceiptTemplateModel {
  // --- Bill Settings ---
  bool billShowStoreName;
  double billHeaderSize;
  bool billShowStoreAddress;
  double billAddressSize; // Mới: Size địa chỉ
  bool billShowStorePhone;
  double billPhoneSize;   // Mới: Size SĐT

  double billTitleSize;
  // bool billShowDateTime; // (Mặc định luôn hiện)
  bool billShowCashierName;
  bool billShowCustomerName;
  double billTextSize; // Size chung cho thông tin (Khách, Giờ...)

  double billItemNameSize;
  double billItemDetailSize;

  bool billShowTax;
  bool billShowSurcharge;
  bool billShowDiscount;
  double billTotalSize;
  bool billShowPaymentMethod;

  bool billShowFooter;
  String footerText1; // Mới: Dòng cảm ơn 1
  String footerText2; // Mới: Dòng cảm ơn 2

  // --- Kitchen Settings ---
  double kitchenTitleSize;
  bool kitchenShowTime;
  bool kitchenShowStaff;
  bool kitchenShowCustomer;
  double kitchenInfoSize; // Mới: Size cụm thông tin (Khách/NV/Giờ)

  double kitchenTableHeaderSize; // Mới: Size tiêu đề bảng (STT, Món, SL)
  double kitchenQtySize;
  double kitchenItemNameSize;
  double kitchenNoteSize;

  ReceiptTemplateModel({
    this.billShowStoreName = true,
    this.billHeaderSize = 18.0,
    this.billShowStoreAddress = true,
    this.billAddressSize = 14.0,
    this.billShowStorePhone = true,
    this.billPhoneSize = 14.0,

    this.billTitleSize = 16.0,
    this.billShowCashierName = true,
    this.billShowCustomerName = true,
    this.billTextSize = 14.0,

    this.billItemNameSize = 14.0,
    this.billItemDetailSize = 13.0,

    this.billShowTax = true,
    this.billShowSurcharge = true,
    this.billShowDiscount = true,
    this.billTotalSize = 14.0,
    this.billShowPaymentMethod = true,

    this.billShowFooter = true,
    this.footerText1 = "Cảm ơn quý khách!",
    this.footerText2 = "Hẹn gặp lại!",

    this.kitchenTitleSize = 18.0,
    this.kitchenShowTime = true,
    this.kitchenShowStaff = true,
    this.kitchenShowCustomer = true,
    this.kitchenInfoSize = 14.0,

    this.kitchenTableHeaderSize = 14.0,
    this.kitchenQtySize = 14.0,
    this.kitchenItemNameSize = 14.0,
    this.kitchenNoteSize = 13.0,
  });

  Map<String, dynamic> toMap() {
    return {
      'billShowStoreName': billShowStoreName,
      'billHeaderSize': billHeaderSize,
      'billShowStoreAddress': billShowStoreAddress,
      'billAddressSize': billAddressSize,
      'billShowStorePhone': billShowStorePhone,
      'billPhoneSize': billPhoneSize,
      'billTitleSize': billTitleSize,
      'billShowCashierName': billShowCashierName,
      'billShowCustomerName': billShowCustomerName,
      'billTextSize': billTextSize,
      'billItemNameSize': billItemNameSize,
      'billItemDetailSize': billItemDetailSize,
      'billShowTax': billShowTax,
      'billShowSurcharge': billShowSurcharge,
      'billShowDiscount': billShowDiscount,
      'billTotalSize': billTotalSize,
      'billShowPaymentMethod': billShowPaymentMethod,
      'billShowFooter': billShowFooter,
      'footerText1': footerText1,
      'footerText2': footerText2,
      'kitchenTitleSize': kitchenTitleSize,
      'kitchenShowTime': kitchenShowTime,
      'kitchenShowStaff': kitchenShowStaff,
      'kitchenShowCustomer': kitchenShowCustomer,
      'kitchenInfoSize': kitchenInfoSize,
      'kitchenTableHeaderSize': kitchenTableHeaderSize,
      'kitchenQtySize': kitchenQtySize,
      'kitchenItemNameSize': kitchenItemNameSize,
      'kitchenNoteSize': kitchenNoteSize,
    };
  }

  factory ReceiptTemplateModel.fromMap(Map<String, dynamic> map) {
    return ReceiptTemplateModel(
      billShowStoreName: map['billShowStoreName'] ?? true,
      billHeaderSize: (map['billHeaderSize'] as num?)?.toDouble() ?? 24.0,
      billShowStoreAddress: map['billShowStoreAddress'] ?? true,
      billAddressSize: (map['billAddressSize'] as num?)?.toDouble() ?? 12.0,
      billShowStorePhone: map['billShowStorePhone'] ?? true,
      billPhoneSize: (map['billPhoneSize'] as num?)?.toDouble() ?? 12.0,
      billTitleSize: (map['billTitleSize'] as num?)?.toDouble() ?? 20.0,
      billShowCashierName: map['billShowCashierName'] ?? true,
      billShowCustomerName: map['billShowCustomerName'] ?? true,
      billTextSize: (map['billTextSize'] as num?)?.toDouble() ?? 12.0,
      billItemNameSize: (map['billItemNameSize'] as num?)?.toDouble() ?? 12.0,
      billItemDetailSize: (map['billItemDetailSize'] as num?)?.toDouble() ?? 12.0,
      billShowTax: map['billShowTax'] ?? true,
      billShowSurcharge: map['billShowSurcharge'] ?? true,
      billShowDiscount: map['billShowDiscount'] ?? true,
      billTotalSize: (map['billTotalSize'] as num?)?.toDouble() ?? 16.0,
      billShowPaymentMethod: map['billShowPaymentMethod'] ?? true,
      billShowFooter: map['billShowFooter'] ?? true,
      footerText1: map['footerText1'] ?? "Cảm ơn quý khách!",
      footerText2: map['footerText2'] ?? "Hẹn gặp lại!",
      kitchenTitleSize: (map['kitchenTitleSize'] as num?)?.toDouble() ?? 24.0,
      kitchenShowTime: map['kitchenShowTime'] ?? true,
      kitchenShowStaff: map['kitchenShowStaff'] ?? true,
      kitchenShowCustomer: map['kitchenShowCustomer'] ?? true,
      kitchenInfoSize: (map['kitchenInfoSize'] as num?)?.toDouble() ?? 12.0,
      kitchenTableHeaderSize: (map['kitchenTableHeaderSize'] as num?)?.toDouble() ?? 12.0,
      kitchenQtySize: (map['kitchenQtySize'] as num?)?.toDouble() ?? 16.0,
      kitchenItemNameSize: (map['kitchenItemNameSize'] as num?)?.toDouble() ?? 16.0,
      kitchenNoteSize: (map['kitchenNoteSize'] as num?)?.toDouble() ?? 12.0,
    );
  }

  String toJson() => json.encode(toMap());
  factory ReceiptTemplateModel.fromJson(String source) => ReceiptTemplateModel.fromMap(json.decode(source));
}