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
  final String paymentMethodCode;
  final String invoiceType; // 'vat' (GTGT) hoặc 'sale' (Bán hàng)
  final bool isSandbox;

  VnpayConfig({
    required this.clientId,
    required this.clientSecret,
    required this.sellerTaxCode,
    required this.invoiceSymbol,
    this.autoIssueOnPayment = false,
    this.paymentMethodCode = "TM/CK",
    this.invoiceType = "vat",
    this.isSandbox = false,
  });
}

class VnpayEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  final _dio = Dio();
  final _uuid = const Uuid();

  // --- ĐỊNH NGHĨA URL API ---
  static const String _prodUrl = 'https://api.vnpayinvoice.vn';
  static const String _testUrl = 'https://invoice-api.vnpaytest.vn';

  // MST Test mặc định của VNPAY
  static const String _testTaxCode = '0102182292-999';

  // --- LOGIC TỰ ĐỘNG CHUYỂN MÔI TRƯỜNG ---
  bool _shouldUseSandbox(VnpayConfig config) {
    if (config.sellerTaxCode == _testTaxCode) return true;
    return config.isSandbox;
  }

  String _getBaseUrl(bool useSandbox) {
    return useSandbox ? _testUrl : _prodUrl;
  }

  // --- ĐÃ SỬA: LUÔN DÙNG LINK PORTAL ---
  String _getLookupUrl() {
    // Theo yêu cầu: Luôn trả về link này dù là môi trường nào
    return "https://portal.vnpayinvoice.vn/";
  }

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
        'paymentMethodCode': config.paymentMethodCode,
        'invoiceType': config.invoiceType,
        'isSandbox': config.isSandbox,
      };

      await _db.collection(_configCollection).doc(ownerUid).set(dataToSave);
      await _db.collection(_mainConfigCollection).doc(ownerUid).set({
        'activeProvider': 'vnpay'
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("Lỗi lưu cấu hình VNPay: $e");
      throw Exception('Lỗi lưu cấu hình.');
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
        paymentMethodCode: data['paymentMethodCode'] ?? 'TM/CK',
        invoiceType: data['invoiceType'] ?? 'vat',
        isSandbox: data['isSandbox'] ?? false,
      );
    } catch (e) {
      return null;
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

  Future<String?> loginToVnpay(String clientId, String clientSecret, bool isSandboxMode) async {
    final baseUrl = _getBaseUrl(isSandboxMode);
    try {
      final response = await _dio.post(
        '$baseUrl/user/client/token',
        data: {'clientId': clientId, 'clientSecret': clientSecret},
        options: Options(sendTimeout: const Duration(seconds: 10)),
      );
      if (response.statusCode == 200 && response.data?['code'] == '00') {
        return response.data['data']?['accessToken'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        throw Exception('Không thể kết nối tới Server VNPAY ($baseUrl). Vui lòng kiểm tra mạng.');
      }
      if (e.response != null) {
        throw Exception(
            'Lỗi ${e.response?.statusCode}: ${e.response?.data?['message'] ?? 'Sai thông tin đăng nhập'}');
      }
      throw Exception('Lỗi kết nối: ${e.message}');
    }
  }

  Future<String?> _getValidToken(String ownerUid, VnpayConfig config) async {
    final bool useSandbox = _shouldUseSandbox(config);
    return await loginToVnpay(config.clientId, config.clientSecret, useSandbox);
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid) async {
    try {
      final config = (await getVnpayConfig(ownerUid))!;

      final bool useSandbox = _shouldUseSandbox(config);

      final token = await _getValidToken(ownerUid, config);
      if (token == null) {
        throw Exception('Lỗi xác thực. Kiểm tra lại Client ID/Secret.');
      }

      String endpoint = (config.invoiceType == 'vat')
          ? "/api/v6/vat/original"
          : "/api/v6/sale/original";

      final String apiUrl = "${_getBaseUrl(useSandbox)}$endpoint";

      final payload = (config.invoiceType == 'vat')
          ? _buildVatPayload(billData, customer, config)
          : _buildSalePayload(billData, customer, config);

      final response = await _dio.post(
        apiUrl,
        data: payload,
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      if (response.statusCode == 200 && response.data?['code'] == '00') {
        final resultData = response.data['data'] as Map<String, dynamic>;

        return EInvoiceResult(
          providerName: 'VNPay',
          invoiceNo: resultData['invoiceNumber'].toString(),
          reservationCode: resultData['lookupCode'] as String,
          // SỬ DỤNG HÀM MỚI ĐÃ CỐ ĐỊNH LINK
          lookupUrl: _getLookupUrl(),
          mst: config.sellerTaxCode,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['message'] ?? 'Lỗi VNPAY trả về');
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;
      if (errorData != null && errorData['message'] != null) {
        throw Exception('Lỗi VNPay: ${errorData['message']}');
      }
      throw Exception('Lỗi kết nối khi tạo hóa đơn: ${e.message}');
    } catch (e) {
      throw Exception('Lỗi tạo HĐĐT: ${e.toString()}');
    }
  }

  @override
  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse) async {
    // VNPay tự động gửi email nếu 'isSendMail: true' trong payload
    return Future.value();
  }

  Map<String, dynamic> _buildVatPayload(Map<String, dynamic> billData,
      CustomerModel? customer, VnpayConfig config) {

    final List<Map<String, dynamic>> products = [];
    final List<dynamic> billItems = billData['items'] ?? [];
    int ordinal = 1;

    final double taxPercent = (billData['taxPercent'] as num?)?.toDouble() ?? 0.0;
    String taxRateString = "10%";

    if (taxPercent == 0) {taxRateString = "0%";}
    else if (taxPercent == 5) {taxRateString = "5%";}
    else if (taxPercent == 8) {taxRateString = "8%";}
    else if (taxPercent == 10) {taxRateString = "10%";}
    else {taxRateString = "KCT";}

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = (quantity * unitPrice);

      double itemTaxAmount = 0;
      if (taxRateString.contains("%")) {
        itemTaxAmount = (itemTotal * taxPercent / 100);
      }

      products.add({
        "ordinalNumber": ordinal++,
        "name": item['productName'] ?? 'Sản phẩm',
        "property": 1,
        "unit": item['unitName'] ?? 'cái',
        "quantity": quantity,
        "price": unitPrice,
        "amountWithoutDiscount": itemTotal,
        "amount": itemTotal,
        "taxAmount": itemTaxAmount,
        "amountAfterTax": itemTotal + itemTaxAmount,
        "tax": taxRateString,
      });
    }

    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    final double taxableAmount = (subtotal - discount).roundToDouble();
    final double taxAmount = (billData['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable = (billData['totalPayable'] as num?)?.toDouble() ?? 0.0;

    final List<Map<String, dynamic>> taxTypes = [];
    taxTypes.add({
      "tax": taxRateString,
      "amount": taxableAmount,
      "taxAmount": taxAmount.round(),
    });

    return _buildCommonPayload(billData, customer, config, products,
        totalAmount: taxableAmount,
        totalTax: taxAmount.round().toDouble(),
        totalPayable: totalPayable.round().toDouble(),
        taxTypes: taxTypes);
  }

  Map<String, dynamic> _buildSalePayload(Map<String, dynamic> billData,
      CustomerModel? customer, VnpayConfig config) {

    final List<Map<String, dynamic>> products = [];
    final List<dynamic> billItems = billData['items'] ?? [];
    int ordinal = 1;

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
        "amountAfterTax": itemTotal,
      });
    }

    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable = (billData['totalPayable'] as num?)?.toDouble() ?? 0.0;

    return _buildCommonPayload(billData, customer, config, products,
        totalAmount: (subtotal - discount).roundToDouble(),
        totalTax: 0,
        totalPayable: totalPayable.round().toDouble(),
        taxTypes: null
    );
  }

  Map<String, dynamic> _buildCommonPayload(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      VnpayConfig config,
      List<Map<String, dynamic>> products,
      {required double totalAmount, required double totalTax, required double totalPayable, List<Map<String, dynamic>>? taxTypes}) {

    String vnpayPaymentMethod = config.paymentMethodCode.isEmpty ? "TM/CK" : config.paymentMethodCode;
    final bool hasEmail = customer?.email != null && customer!.email!.isNotEmpty;
    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;

    final Map<String, dynamic> payload = {
      "taxCode": config.sellerTaxCode,
      "autoRelease": true,
      "autoSign": true,
      "autoSendCQT": true,
      "invoice": {
        "requestId": _uuid.v4(),
        "invoiceCreatedDate": DateFormat('yyyy-MM-dd').format(DateTime.now()),
        "invoiceSymbol": config.invoiceSymbol,
        "paymentMethod": vnpayPaymentMethod,
        "currencyUnit": "VND",
        "currencyExchangeRate": 1,
        "buyerTaxCode": customer?.taxId,
        "buyerName": customer?.companyName ?? customer?.name ?? "Khách lẻ",
        "buyerAddress": customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "buyerEmail": customer?.email,
        "isSendMail": hasEmail,
        "totalAmountWithoutDiscount": subtotal.round(),
        "totalDiscountAmount": discount.round(),
        "totalAmount": totalAmount,
        "totalTaxAmount": totalTax,
        "totalAmountAfterTax": totalPayable,
        "products": products,
      }
    };

    if (taxTypes != null) {
      payload['invoice']['taxTypes'] = taxTypes;
    }

    return payload;
  }
}