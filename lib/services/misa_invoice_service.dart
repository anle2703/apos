// Tên file: misa_invoice_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class MisaConfig {
  final String apiUrl;
  final String taxCode;
  final String username;
  final String password;
  final String templateCode;
  final String invoiceSeries;
  final bool autoIssueOnPayment;

  MisaConfig({
    required this.apiUrl,
    required this.taxCode,
    required this.username,
    required this.password,
    required this.templateCode,
    required this.invoiceSeries,
    this.autoIssueOnPayment = false,
  });
}

class MisaEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  final _dio = Dio();
  final _uuid = const Uuid();

  // *** THAY ĐỔI QUAN TRỌNG: APP ID CỦA BẠN SẼ ĐỂ Ở ĐÂY ***
  // Bạn cần liên hệ MISA để lấy App ID và thay vào đây
  static const String _misaAppId = 'YOUR_APP_ID_FROM_MISA';

  Future<void> saveMisaConfig(MisaConfig config, String ownerUid) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));
      final dataToSave = {
        'provider': 'misa',
        'apiUrl': config.apiUrl,
        'taxCode': config.taxCode,
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'appId': _misaAppId, // Tự động lưu App ID của bạn
      };

      await _db.collection(_configCollection).doc(ownerUid).set(dataToSave);
      await _db.collection(_mainConfigCollection).doc(ownerUid).set({
        'activeProvider': 'misa'
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình MISA: $e");
      throw Exception('Không thể lưu cấu hình MISA.');
    }
  }

  Future<MisaConfig?> getMisaConfig(String ownerUid) async {
    try {
      final doc = await _db.collection(_configCollection).doc(ownerUid).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      if (data['provider'] != 'misa') return null;

      String decodedPassword;
      try {
        decodedPassword = utf8.decode(base64Decode(data['password'] ?? ''));
      } catch (e) {
        decodedPassword = '';
      }

      return MisaConfig(
        apiUrl: data['apiUrl'] ?? '',
        taxCode: data['taxCode'] ?? '',
        username: data['username'] ?? '',
        password: decodedPassword,
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
      );
    } catch (e) {
      debugPrint ("Lỗi khi tải cấu hình MISA: $e");
      throw Exception('Không thể tải cấu hình MISA.');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid) async {
    final config = await getMisaConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }
    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToMisa(
      String apiUrl, String taxCode, String username, String password) async {
    try {
      final String authUrl = "$apiUrl/api/integration/auth/token";
      final response = await _dio.post(
        authUrl,
        data: {
          'tax_code': taxCode,
          'app_id': _misaAppId, // Sử dụng App ID nội bộ
          'username': username,
          'password': password,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['access_token'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Lỗi MISA ${e.response?.statusCode}: ${e.response?.data?['Message'] ?? e.response?.data?['error_description'] ?? 'Sai thông tin'}');
      } else {
        throw Exception('Lỗi mạng. Vui lòng kiểm tra lại.');
      }
    }
  }

  Future<String?> _getValidToken(String ownerUid) async {
    final config = await getMisaConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình MISA HĐĐT.');
    }
    return await loginToMisa(
        config.apiUrl, config.taxCode, config.username, config.password);
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid) async {
    // ... (Không thay đổi hàm này) ...
    try {
      final token = await _getValidToken(ownerUid);
      if (token == null) {
        throw Exception('Không thể lấy token xác thực MISA.');
      }

      final config = (await getMisaConfig(ownerUid))!;
      final transactionId = _uuid.v4();
      final payload = _buildMisaPayload(billData, customer, config, transactionId);
      final String apiUrl = "${config.apiUrl}/api/integration/invoice/publish";

      final response = await _dio.post(
        apiUrl,
        data: jsonEncode(payload),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final resultData = response.data as Map<String, dynamic>;

        final String reservationCode = resultData['TransactionID'] as String;
        final String invoiceNo = resultData['InvoiceNo'] as String;
        final String lookupUrl = 'https://meinvoice.vn/tra-cuu'; // Link tra cứu chung của MISA

        return EInvoiceResult(
          providerName: 'MISA',
          invoiceNo: invoiceNo,
          reservationCode: reservationCode,
          lookupUrl: lookupUrl,
          mst: config.taxCode,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['Message'] ?? 'Lỗi không xác định từ MISA');
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;
      if (errorData != null && errorData['Message'] != null) {
        throw Exception('Lỗi MISA: ${errorData['Message']} (Code: ${errorData['ErrorCode']})');
      }
      throw Exception('Lỗi mạng khi tạo HĐĐT: ${e.message}');
    } catch (e) {
      throw Exception('Lỗi cục bộ khi tạo HĐĐT: ${e.toString()}');
    }
  }

  @override
  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse) async {
    // ... (Không thay đổi hàm này) ...
    final String? transactionId = rawResponse['TransactionID'] as String?;
    if (transactionId == null) {
      debugPrint("Không tìm thấy TransactionID (MISA) để gửi email.");
      return;
    }

    final token = await _getValidToken(ownerUid);
    final config = (await getMisaConfig(ownerUid))!;

    try {
      final String apiUrl = "${config.apiUrl}/api/integration/invoice/send-email";

      await _dio.post(
        apiUrl,
        queryParameters: { 'tax_code': config.taxCode },
        data: jsonEncode([transactionId]), // MISA yêu cầu body là một list [transactionId]
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      debugPrint("Đã gửi yêu cầu email HĐĐT MISA cho $transactionId");
    } on DioException catch (e) {
      debugPrint("Lỗi API MISA (gửi email): $e");
    }
  }

  Map<String, dynamic> _buildMisaPayload(Map<String, dynamic> billData,
      CustomerModel? customer, MisaConfig config, String transactionId) {
    // ... (Không thay đổi hàm này) ...
    final List<Map<String, dynamic>> items = [];
    final List<dynamic> billItems = billData['items'] ?? [];
    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = (quantity * unitPrice).roundToDouble();

      items.add({
        "ItemName": item['productName'] ?? 'Sản phẩm',
        "UnitName": item['unitName'] ?? 'cái',
        "Quantity": quantity,
        "UnitPrice": unitPrice,
        "Amount": itemTotal,
        "TaxRate": -2, // -2 = Không chịu thuế
      });
    }

    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    final double taxAmount = (billData['taxAmount'] as num?)?.toDouble() ?? 0.0;
    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double totalPayable = (billData['totalPayable'] as num?)?.toDouble() ?? 0.0;

    // Lấy PTTT đầu tiên
    final Map<String, dynamic> billPayments = billData['payments'] ?? {};
    String paymentMethod = "Tiền mặt";
    if (billPayments.isNotEmpty) {
      paymentMethod = billPayments.keys.first;
    }

    return {
      "TransactionID": transactionId,
      "RefID": _uuid.v4(),
      "TaxCode": config.taxCode,
      "InvoiceTemplate": {
        "TemplateCode": config.templateCode,
        "InvoiceSeries": config.invoiceSeries
      },
      "Customer": {
        "CustomerName": customer?.name ?? billData['customerName'] ?? "Khách lẻ",
        "Buyer": customer?.companyName ?? customer?.name ?? billData['customerName'] ?? "Khách lẻ",
        "TaxCode": customer?.taxId,
        "Address": customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "Email": customer?.email,
        "Phone": customer?.phone ?? billData['customerPhone'],
      },
      "Items": items,
      "PaymentMethod": paymentMethod,
      "TotalSaleAmount": subtotal.roundToDouble(),
      "DiscountAmount": discount.roundToDouble(),
      "TotalTaxAmount": taxAmount.roundToDouble(),
      "TotalAmount": totalPayable.roundToDouble(),
      "AutoRenderTotalAmountInWords": true, // Tự động render thành chữ
    };
  }
}