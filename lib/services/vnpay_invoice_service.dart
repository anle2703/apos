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
  final bool isSandbox;

  VnpayConfig({
    required this.clientId,
    required this.clientSecret,
    required this.sellerTaxCode,
    required this.invoiceSymbol,
    this.autoIssueOnPayment = false,
    this.paymentMethodCode = "TM/CK",
    this.isSandbox = false,
  });
}

class VnpayEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  // Đường dẫn cấu hình thuế
  static const String _taxSettingsCollection = 'store_tax_settings';

  final _dio = Dio();
  final _uuid = const Uuid();

  static const String _prodUrl = 'https://api.vnpayinvoice.vn';
  static const String _testUrl = 'https://invoice-api.vnpaytest.vn';
  static const String _testTaxCode = '0102182292-999';

  bool _shouldUseSandbox(VnpayConfig config) {
    if (config.sellerTaxCode == _testTaxCode) return true;
    return config.isSandbox;
  }

  String _getBaseUrl(bool useSandbox) {
    return useSandbox ? _testUrl : _prodUrl;
  }

  String _getLookupUrl() {
    return "https://portal.vnpayinvoice.vn/";
  }

  Future<void> saveVnpayConfig(VnpayConfig config, String storeId) async {
    try {
      final encodedSecret = base64Encode(utf8.encode(config.clientSecret));

      await _db.collection(_configCollection).doc(storeId).set({
        'clientId': config.clientId,
        'clientSecret': encodedSecret,
        'sellerTaxCode': config.sellerTaxCode,
        'invoiceSymbol': config.invoiceSymbol,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'paymentMethodCode': config.paymentMethodCode,
        'isSandbox': config.isSandbox,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection(_mainConfigCollection).doc(storeId).set({
        'activeProvider': 'vnpay',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình VNPAY: $e");
      throw Exception('Không thể lưu cấu hình VNPAY.');
    }
  }

  Future<VnpayConfig?> getVnpayConfig(String storeId) async {
    try {
      final doc = await _db.collection(_configCollection).doc(storeId).get();

      // 1. Chưa có config
      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;

      // 2. Có config
      return VnpayConfig(
        clientId: data['clientId'] ?? '',
        clientSecret: data['clientSecret'] != null ? utf8.decode(base64Decode(data['clientSecret'])) : '',
        sellerTaxCode: data['sellerTaxCode'] ?? '',
        invoiceSymbol: data['invoiceSymbol'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
        paymentMethodCode: data['paymentMethodCode'] ?? "TM/CK",
        isSandbox: data['isSandbox'] ?? false,
      );
    } catch (e) {
      // 3. Lỗi hệ thống
      debugPrint("Lỗi SYSTEM lấy config VNPAY: $e");
      throw Exception('Lỗi hệ thống khi tải VNPAY: $e');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String storeId) async {
    final config = await getVnpayConfig(storeId);
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

  Future<String?> _getValidToken(String storeId, VnpayConfig config) async {
    final bool useSandbox = _shouldUseSandbox(config);
    return await loginToVnpay(config.clientId, config.clientSecret, useSandbox);
  }

  // Logic xác định loại hóa đơn
  Future<String> _determineInvoiceTypeFromSettings(String storeId) async {
    try {
      final docSnapshot = await _db.collection(_taxSettingsCollection).doc(storeId).get();

      if (!docSnapshot.exists) {
        return "2"; // Mặc định Bán hàng
      }

      final data = docSnapshot.data() as Map<String, dynamic>;

      final String calcMethod = data['calcMethod'] ?? 'direct';
      if (calcMethod == 'deduction') {
        return "1"; // GTGT
      }

      final String entityType = data['entityType'] ?? 'hkd';
      final String revenueRange = data['revenueRange'] ?? 'medium';

      if (entityType == 'dn') return "1";

      if (entityType == 'hkd') {
        if (revenueRange == 'high') return "1"; // HKD > 3 tỷ
        return "2";
      }

      return "2";
    } catch (e) {
      debugPrint("Lỗi lấy cấu hình thuế VNPAY: $e");
      return "2";
    }
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String storeId) async {
    try {
      final config = (await getVnpayConfig(storeId))!;
      final bool useSandbox = _shouldUseSandbox(config);

      final token = await _getValidToken(storeId, config);
      if (token == null) {
        throw Exception('Lỗi xác thực. Kiểm tra lại Client ID/Secret.');
      }

      // 1. Xác định loại hóa đơn
      final String determinedType = await _determineInvoiceTypeFromSettings(storeId);
      debugPrint(">>> VNPay Service: Loại hóa đơn: $determinedType (1=VAT, 2=Sale)");

      // 2. Chọn Endpoint
      String endpoint = (determinedType == '1')
          ? "/api/v6/vat/original" // Hóa đơn GTGT
          : "/api/v6/sale/original"; // Hóa đơn Bán hàng

      final String apiUrl = "${_getBaseUrl(useSandbox)}$endpoint";

      // 3. Build Payload
      final payload = _buildPayloadWithAllocation(billData, customer, config, determinedType);

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
  Future<void> sendEmail(String storeId, Map<String, dynamic> rawResponse) async {
    return Future.value();
  }

  // --- LOGIC: TÍNH GIÁ ĐÃ CHIẾT KHẤU & SỬA LỖI TÊN SẢN PHẨM ---
  Map<String, dynamic> _buildPayloadWithAllocation(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      VnpayConfig config,
      String invoiceType
      ) {

    // 1. TÍNH TỔNG GIÁ TRỊ HÀNG ĐỂ PHÂN BỔ (GIỮ NGUYÊN)
    final List<dynamic> billItems = billData['items'] ?? [];
    final double billDiscount = (billData['discount'] as num?)?.toDouble() ?? 0.0;

    double totalGoodsValue = 0.0;
    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;
      final double q = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final double p = (item['price'] as num?)?.toDouble() ?? 0.0;

      final double itemSpecificDisc = (item['discountValue'] as num?)?.toDouble() ?? 0.0;
      double lineVal;
      if (item['discountUnit'] == '%') {
        lineVal = (p * q) * (1 - itemSpecificDisc / 100);
      } else {
        lineVal = (p * q) - itemSpecificDisc;
      }
      totalGoodsValue += lineVal;
    }

    // 2. XỬ LÝ DÒNG HÀNG
    final List<Map<String, dynamic>> products = [];
    final List<Map<String, dynamic>> taxTypes = [];
    final Map<String, double> taxGroupMap = {};
    final Map<String, double> taxGroupAmountMap = {};

    int ordinal = 1;

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      // --- SỬA LỖI TÊN SẢN PHẨM ---
      // Ưu tiên lấy tên hiển thị, nếu không có thì lấy trong object product
      final productMap = item['product'] as Map<String, dynamic>?;
      final String itemName = item['productName']
          ?? productMap?['productName']
          ?? 'Sản phẩm';

      final String unitName = item['unitName']
          ?? item['selectedUnit'] // Lấy ĐVT đã chọn (Lon/Chai)
          ?? productMap?['unitName']
          ?? 'cái';
      // ---------------------------

      final double quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final double originalPrice = (item['price'] as num?)?.toDouble() ?? 0.0;

      // a. Tính giảm giá dòng
      final double rawLineTotal = originalPrice * quantity;
      double itemSpecificDiscAmount = 0;
      final double specDiscVal = (item['discountValue'] as num?)?.toDouble() ?? 0.0;

      if (specDiscVal > 0) {
        if (item['discountUnit'] == '%') {
          itemSpecificDiscAmount = rawLineTotal * (specDiscVal / 100);
        } else {
          itemSpecificDiscAmount = specDiscVal;
        }
      }

      double lineTotalAfterSpec = rawLineTotal - itemSpecificDiscAmount;

      // b. Phân bổ giảm giá Bill
      double allocatedBillDisc = 0;
      if (totalGoodsValue > 0 && billDiscount > 0) {
        allocatedBillDisc = (lineTotalAfterSpec / totalGoodsValue) * billDiscount;
      }

      // Tổng giảm giá cho dòng này
      double totalLineDiscount = itemSpecificDiscAmount + allocatedBillDisc;

      // c. Giá trị thực thu (Net Amount)
      double itemNetAmount = rawLineTotal - totalLineDiscount;
      itemNetAmount = itemNetAmount.roundToDouble();

      // --- SỬA LỖI GIÁ GỐC: TÍNH ĐƠN GIÁ ĐÃ GIẢM ---
      // Thay vì gửi giá gốc, ta gửi "Đơn giá sau giảm" để khách hàng thấy giá rẻ hơn
      // và discountAmount = 0 (vì đã trừ thẳng vào giá rồi)
      double effectiveUnitPrice = itemNetAmount;
      if (quantity > 0) {
        effectiveUnitPrice = itemNetAmount / quantity;
      }
      // ----------------------------------------------

      // d. Tính Thuế
      String taxString = "KCT";
      double itemTaxAmount = 0;

      if (invoiceType == "1") {
        final double rawRate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
        final double percent = rawRate * 100;

        if ((percent - 10).abs() < 0.1) {taxString = "10%";}
        else if ((percent - 8).abs() < 0.1) {taxString = "8%";}
        else if ((percent - 5).abs() < 0.1) {taxString = "5%";}
        else if ((percent - 0).abs() < 0.1) {taxString = "0%";}
        else {taxString = "KCT";}

        if (taxString.contains("%")) {
          double rateVal = double.parse(taxString.replaceAll('%', '')) / 100;
          itemTaxAmount = (itemNetAmount * rateVal);
        }
      } else {
        taxString = "";
        itemTaxAmount = 0;
      }

      // e. Tạo Product Object cho VNPay
      final Map<String, dynamic> prod = {
        "ordinalNumber": ordinal++,
        "name": itemName,
        "property": 1,
        "unit": unitName,
        "quantity": quantity,

        // --- QUAN TRỌNG: GỬI GIÁ ĐÃ GIẢM ---
        "price": effectiveUnitPrice, // Đơn giá thực thu
        "amountWithoutDiscount": itemNetAmount, // Thành tiền thực thu
        "discountAmount": 0, // Đã trừ vào giá rồi nên discount gửi là 0
        "amount": itemNetAmount, // Thành tiền tính thuế
        // ------------------------------------

        "amountAfterTax": itemNetAmount + itemTaxAmount.round(),
      };

      if (invoiceType == "1") {
        prod["tax"] = taxString;
        prod["taxAmount"] = itemTaxAmount.round();

        taxGroupMap[taxString] = (taxGroupMap[taxString] ?? 0) + itemNetAmount;
        taxGroupAmountMap[taxString] = (taxGroupAmountMap[taxString] ?? 0) + itemTaxAmount;
      }

      products.add(prod);
    }

    // 3. TỔNG HỢP
    double totalAmountNet = 0;
    double totalTaxVal = 0;

    if (invoiceType == "1") {
      taxGroupMap.forEach((taxStr, amount) {
        double taxVal = taxGroupAmountMap[taxStr] ?? 0;
        taxTypes.add({
          "tax": taxStr,
          "amount": amount,
          "taxAmount": taxVal.round(),
        });
        totalAmountNet += amount;
        totalTaxVal += taxVal;
      });
    } else {
      for (var p in products) {
        totalAmountNet += (p['amount'] as num).toDouble();
      }
    }

    // 4. PAYLOAD FINAL
    String vnpayPaymentMethod = config.paymentMethodCode.isEmpty ? "TM/CK" : config.paymentMethodCode;
    final bool hasEmail = customer?.email != null && customer!.email!.isNotEmpty;
    final double totalPayable = totalAmountNet + totalTaxVal;

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
        "buyerTaxCode": customer?.taxId ?? "",
        "buyerName": customer?.name ?? "Khách lẻ",
        "buyerFullName": customer?.companyName ?? "",
        "buyerAddress": customer?.companyAddress ?? customer?.address ?? "",
        "buyerEmail": customer?.email,
        "isSendMail": hasEmail,
        "totalAmountWithoutDiscount": totalAmountNet.round(),
        "totalDiscountAmount": 0,
        "totalAmount": totalAmountNet.round(),
        "totalTaxAmount": totalTaxVal.round(),
        "totalAmountAfterTax": totalPayable.round(),
        "products": products,
      }
    };

    if (invoiceType == "1") {
      payload['invoice']['taxTypes'] = taxTypes;
    }

    return payload;
  }
}