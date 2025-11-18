import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class VnpayConfig {
  final String clientId;
  final String clientSecret;
  final String sellerTaxCode;
  final String invoiceSymbol;
  final bool autoIssueOnPayment;

  VnpayConfig({
    required this.clientId,
    required this.clientSecret,
    required this.sellerTaxCode,
    required this.invoiceSymbol,
    this.autoIssueOnPayment = false,
  });
}

class VnpayEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  final _dio = Dio();
  final _uuid = const Uuid();
  static const String _vnpayBaseUrl =
      'https://invoice-api.vnpaytest.vn';

  Future<void> saveVnpayConfig(VnpayConfig config, String ownerUid) async {
    try {
      final encodedSecret = base64Encode(utf8.encode(config.clientSecret));
      final dataToSave = {
        'provider': 'vnpay',
        'clientId': config.clientId,
        'clientSecret': encodedSecret,
        'sellerTaxCode': config.sellerTaxCode,
        'invoiceSymbol': config.invoiceSymbol,
        'autoIssueOnPayment': config.autoIssueOnPayment,
      };

      await _db.collection(_configCollection).doc(ownerUid).set(dataToSave);

      await _db.collection(_mainConfigCollection).doc(ownerUid).set({
        'activeProvider': 'vnpay'
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình VNPay: $e");
      throw Exception('Không thể lưu cấu hình VNPay.');
    }
  }

  Future<VnpayConfig?> getVnpayConfig(String ownerUid) async {
    try {
      final doc = await _db.collection(_configCollection).doc(ownerUid).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      if (data['provider'] != 'vnpay') return null;

      String decodedSecret;
      try {
        decodedSecret = utf8.decode(base64Decode(data['clientSecret'] ?? ''));
      } catch (e) {
        decodedSecret = '';
      }

      return VnpayConfig(
        clientId: data['clientId'] ?? '',
        clientSecret: decodedSecret,
        sellerTaxCode: data['sellerTaxCode'] ?? '',
        invoiceSymbol: data['invoiceSymbol'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
      );
    } catch (e) {
      debugPrint("Lỗi khi tải cấu hình VNPay: $e");
      throw Exception('Không thể tải cấu hình VNPay.');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid) async {
    final config = await getVnpayConfig(ownerUid);

    if (config == null || config.clientId.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }

    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToVnpay(String clientId, String clientSecret) async {
    try {
      final response = await _dio.post(
        '$_vnpayBaseUrl/user/client/token',
        data: {'clientId': clientId, 'clientSecret': clientSecret},
      );
      if (response.statusCode == 200 && response.data?['code'] == '00') {
        return response.data['data']?['accessToken'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Lỗi ${e.response?.statusCode}: ${e.response?.data?['message'] ?? 'Sai thông tin'}');
      } else {
        throw Exception('Lỗi mạng. Vui lòng kiểm tra lại.');
      }
    }
  }

  Future<String?> _getValidToken(String ownerUid) async {
    final config = await getVnpayConfig(ownerUid);
    if (config == null || config.clientId.isEmpty) {
      throw Exception('Chưa cấu hình VNPay HĐĐT.');
    }
    return await loginToVnpay(config.clientId, config.clientSecret);
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid) async {
    try {
      final token = await _getValidToken(ownerUid);
      if (token == null) {
        throw Exception('Không thể lấy token xác thực VNPay HĐĐT.');
      }

      final config = (await getVnpayConfig(ownerUid))!;
      final payload = _buildVnpayPayload(billData, customer, config);

      final String apiUrl = "$_vnpayBaseUrl/api/v6/vat/original";

      final response = await _dio.post(
        apiUrl,
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 && response.data?['code'] == '00') {
        final resultData = response.data['data'] as Map<String, dynamic>;

        return EInvoiceResult(
          providerName: 'VNPay',
          invoiceNo: resultData['invoiceNumber'].toString(),
          reservationCode: resultData['lookupCode'] as String,
          lookupUrl:
          "https://invoice.vnpaytest.vn",
          mst: config.sellerTaxCode,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['message'] ?? 'Lỗi không xác định từ VNPay');
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;
      if (errorData != null && errorData['message'] != null) {
        throw Exception('Lỗi VNPay: ${errorData['message']}');
      }
      throw Exception('Lỗi mạng khi tạo HĐĐT: ${e.message}');
    } catch (e) {
      throw Exception('Lỗi cục bộ khi tạo HĐĐT: ${e.toString()}');
    }
  }

  @override
  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse) async {
    debugPrint(
        "VNPay tự động gửi email nếu 'isSendMail: true' được đặt khi tạo hóa đơn.");
    return Future.value();
  }

  Map<String, dynamic> _buildVnpayPayload(Map<String, dynamic> billData,
      CustomerModel? customer, VnpayConfig config) {
    final List<Map<String, dynamic>> products = [];
    final List<dynamic> billItems = billData['items'] ?? [];
    int ordinal = 1;

    final double taxPercent = (billData['taxPercent'] as num?)?.toDouble() ?? 0.0;
    String taxRateString = "KCT";
    if (taxPercent == 0) taxRateString = "0%";
    if (taxPercent == 5) taxRateString = "5%";
    if (taxPercent == 8) taxRateString = "8%";
    if (taxPercent == 10) taxRateString = "10%";

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = (quantity * unitPrice);

      products.add({
        "ordinalNumber": ordinal++,
        "name": item['productName'] ?? 'Sản phẩm',
        "property": 1,
        "unit": item['unitName'] ?? 'cái',
        "quantity": quantity,
        "price": unitPrice,
        "amountWithoutDiscount": itemTotal,
        "amount": itemTotal,
        "taxAmount": 0,
        "amountAfterTax": itemTotal,
        "tax": taxRateString,
      });
    }

    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    final double taxableAmount = (subtotal - discount).roundToDouble();
    final double taxAmount = (billData['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable =
        (billData['totalPayable'] as num?)?.toDouble() ?? 0.0;

    final List<Map<String, dynamic>> taxTypes = [];
    taxTypes.add({
      "tax": taxRateString,
      "amount": taxableAmount,
      "taxAmount": taxAmount.round(),
    });

    final String paymentMethod =
        (billData['payments'] as Map<String, dynamic>?)?.keys.firstOrNull ??
            "Tiền mặt";
    String vnpayPaymentMethod = "TM";
    if (paymentMethod.toLowerCase().contains("tiền mặt")) vnpayPaymentMethod = "TM";
    if (paymentMethod.toLowerCase().contains("chuyển khoản")) {
      vnpayPaymentMethod = "CK";
    }
    if (paymentMethod.toLowerCase().contains("thẻ")) vnpayPaymentMethod = "TM/CK";

    final bool hasEmail = customer?.email != null && customer!.email!.isNotEmpty;

    final Map<String, dynamic> payload = {
      "taxCode": config.sellerTaxCode,
      "autoRelease": true,
      "autoSign": true,
      "autoSendCQT": true,
      "invoice": {
        "requestId": _uuid.v4(),
        "invoiceCreatedDate":
        DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "invoiceSymbol": config.invoiceSymbol,
        "paymentMethod": vnpayPaymentMethod,
        "currencyUnit": "VND",
        "currencyExchangeRate": 1,
        "buyerTaxCode": customer?.taxId,
        "buyerName": customer?.companyName ?? customer?.name ?? "Khách lẻ",
        "buyerAddress":
        customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "buyerEmail": customer?.email,
        "isSendMail": hasEmail,
        "totalAmountWithoutDiscount": subtotal.round(),
        "totalDiscountAmount": discount.round(),
        "totalAmount": taxableAmount,
        "totalTaxAmount": taxAmount.round(),
        "totalAmountAfterTax": totalPayable.round(),
        "taxTypes": taxTypes,
        "products": products,
      }
    };
    return payload;
  }
}