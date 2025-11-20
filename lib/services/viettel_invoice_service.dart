import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class ViettelConfig {
  final String username;
  final String password;
  final String templateCode;
  final String invoiceSeries;
  final bool autoIssueOnPayment;
  final String invoiceType; // 'vat' hoặc 'sale'

  ViettelConfig({
    required this.username,
    required this.password,
    required this.templateCode,
    required this.invoiceSeries,
    this.autoIssueOnPayment = false,
    this.invoiceType = 'vat',
  });
}

class ViettelEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  final _dio = Dio();
  final _uuid = const Uuid();
  static const String _viettelBaseUrl = 'https://api-vinvoice.viettel.vn';

  Future<void> saveViettelConfig(ViettelConfig config, String ownerUid) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));
      final dataToSave = {
        'provider': 'viettel',
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'invoiceType': config.invoiceType,
      };

      await _db.collection(_configCollection).doc(ownerUid).set(dataToSave);
      await _db.collection(_mainConfigCollection).doc(ownerUid).set({
        'activeProvider': 'viettel'
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình Viettel: $e");
      throw Exception('Không thể lưu cấu hình Viettel.');
    }
  }

  Future<ViettelConfig?> getViettelConfig(String ownerUid) async {
    try {
      final doc = await _db.collection(_configCollection).doc(ownerUid).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      if (data['provider'] != 'viettel') return null;

      String decodedPassword;
      try {
        decodedPassword = utf8.decode(base64Decode(data['password'] ?? ''));
      } catch (e) {
        decodedPassword = '';
      }

      return ViettelConfig(
        username: data['username'] ?? '',
        password: decodedPassword,
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
        invoiceType: data['invoiceType'] ?? 'vat',
      );
    } catch (e) {
      debugPrint ("Lỗi khi tải cấu hình Viettel: $e");
      throw Exception('Không thể tải cấu hình Viettel.');
    }
  }

  // ... (Hàm getConfigStatus, loginToViettel, _getValidToken, sendEmail giữ nguyên) ...
  // Bạn copy lại từ code cũ nhé.

  // ... (Hàm createInvoice giữ nguyên logic gọi API, chỉ gọi _buildViettelPayload) ...

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid) async {
    final config = await getViettelConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }
    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToViettel(String username, String password) async {
    try {
      final response = await _dio.post(
        '$_viettelBaseUrl/auth/login',
        data: {'username': username, 'password': password},
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['access_token'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.response != null) {
        throw Exception(
            'Lỗi ${e.response?.statusCode}: ${e.response?.data?['data'] ?? e.response?.data?['message'] ?? 'Sai thông tin'}');
      } else {
        throw Exception('Lỗi mạng. Vui lòng kiểm tra lại.');
      }
    }
  }

  Future<String?> _getValidToken(String ownerUid) async {
    final config = await getViettelConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình Viettel HĐĐT.');
    }
    return await loginToViettel(config.username, config.password);
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid) async {
    try {
      final token = await _getValidToken(ownerUid);
      if (token == null) {
        throw Exception('Không thể lấy token xác thực HĐĐT.');
      }

      final config = (await getViettelConfig(ownerUid))!;
      final fullUsernameForUrl = config.username;
      final mst = config.username;

      final payload = _buildViettelPayload(billData, customer, config);

      final String apiUrl =
          "$_viettelBaseUrl/services/einvoiceapplication/api/InvoiceAPI/InvoiceWS/createInvoice/$fullUsernameForUrl";

      final response = await _dio.post(
        apiUrl,
        data: payload,
        options: Options(
          headers: {
            'Cookie': 'access_token=$token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data['result'] != null) {
        final resultData = response.data['result'] as Map<String, dynamic>;
        final reservationCode = resultData['reservationCode'] as String;

        final String lookupUrl =
            'https://vinvoice.viettel.vn/utilities/invoice-search?taxCode=$mst&reservationCode=$reservationCode';

        return EInvoiceResult(
          providerName: 'Viettel',
          invoiceNo: resultData['invoiceNo'] as String,
          reservationCode: reservationCode,
          lookupUrl: lookupUrl,
          mst: mst,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['description'] ??
            response.data['message'] ??
            'Lỗi không xác định từ Viettel');
      }
    } on DioException catch (e) {
      // ... (Xử lý lỗi giữ nguyên)
      throw Exception('Lỗi tạo hóa đơn: ${e.message}');
    } catch (e) {
      throw Exception('Lỗi cục bộ: ${e.toString()}');
    }
  }

  @override
  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse) async {
    // API 7.14 của Viettel yêu cầu `lstTransactionUuid`
    // `rawResponse` từ `createInvoice` (API 7.2) chứa `transactionID`
    final String? transactionUuid = rawResponse['transactionID'] as String?;
    if (transactionUuid == null) {
      debugPrint ("Không tìm thấy transactionID để gửi email.");
      return;
    }

    final token = await _getValidToken(ownerUid);
    final config = (await getViettelConfig(ownerUid))!;

    try {
      final String apiUrl = "$_viettelBaseUrl/services/einvoiceapplication/api/InvoiceAPI/InvoiceUtilsWS/sendHtmlMailProcess";

      await _dio.post(
        apiUrl,
        data: {
          'supplierTaxCode': config.username,
          'lstTransactionUuid': transactionUuid,
        },
        options: Options(
          headers: {
            'Cookie': 'access_token=$token',
            'Content-Type': 'application/json',
          },
        ),
      );
      debugPrint("Đã gửi yêu cầu email HĐĐT cho $transactionUuid");
    } on DioException catch (e) {
      debugPrint("Lỗi API Viettel (gửi email): $e");
      // Không ném lỗi, chỉ ghi log
    }
  }

  // --- HÀM BUILDER ĐÃ SỬA ĐỔI ---
  Map<String, dynamic> _buildViettelPayload(Map<String, dynamic> billData,
      CustomerModel? customer, ViettelConfig config) {

    // --- LOGIC THUẾ ---
    final double taxPercent = (billData['taxPercent'] as num?)?.toDouble() ?? 0.0;
    double viettelTaxPercentage = -2; // Mặc định KCT

    if (config.invoiceType == 'vat') {
      // Nếu là GTGT: Map đúng %
      if (taxPercent == 10) {viettelTaxPercentage = 10;}
      else if (taxPercent == 8) {viettelTaxPercentage = 8;}
      else if (taxPercent == 5) {viettelTaxPercentage = 5;}
      else if (taxPercent == 0) {viettelTaxPercentage = 0;}
      else {viettelTaxPercentage = 10;}
    } else {
      // Nếu là Bán hàng: Luôn là -2
      viettelTaxPercentage = -2;
    }

    // 1. Thông tin hàng hóa (itemInfo)
    final List<Map<String, dynamic>> itemInfo = [];
    final List<dynamic> billItems = billData['items'] ?? [];

    double totalTaxAmount = 0;

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = (quantity * unitPrice).roundToDouble();

      double itemTaxAmount = 0;
      if (viettelTaxPercentage >= 0) {
        itemTaxAmount = (itemTotal * taxPercent / 100).roundToDouble();
        totalTaxAmount += itemTaxAmount;
      }

      itemInfo.add({
        "selection": 1,
        "itemName": item['productName'] ?? 'Sản phẩm',
        "unitName": item['unitName'] ?? 'cái',
        "quantity": quantity,
        "unitPrice": unitPrice,
        "itemTotalAmountWithoutTax": itemTotal,
        "taxPercentage": viettelTaxPercentage, // Gửi đúng mã thuế
        "taxAmount": itemTaxAmount, // Gửi tiền thuế dòng
      });
    }

    // 2. Thông tin chiết khấu
    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    if (discount > 0) {
      itemInfo.add({
        "selection": 3,
        "itemName": "Chiết khấu tổng",
        "itemTotalAmountWithoutTax": discount.roundToDouble(),
        "taxPercentage": -2, // Chiết khấu thường không chịu thuế
        "taxAmount": 0,
        "isIncreaseItem": false,
      });
    }

    // 3. Thông tin thuế (taxBreakdowns) - QUAN TRỌNG
    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double taxableAmount = (subtotal - discount).roundToDouble();

    final List<Map<String, dynamic>> taxBreakdowns = [];

    taxBreakdowns.add({
      "taxPercentage": viettelTaxPercentage,
      "taxableAmount": taxableAmount,
      "taxAmount": totalTaxAmount,
    });

    // 4. Thông tin tổng
    // Với Viettel: totalAmountWithTax là số cuối cùng khách phải trả
    final double finalPayment = config.invoiceType == 'vat'
        ? (taxableAmount + totalTaxAmount).roundToDouble()
        : taxableAmount;

    final summarizeInfo = {
      "totalAmountWithoutTax": taxableAmount,
      "totalTaxAmount": totalTaxAmount,
      "totalAmountWithTax": finalPayment,
      "discountAmount": discount.roundToDouble(),
    };

    // 5. Hình thức thanh toán
    final Map<String, dynamic> billPayments = billData['payments'] ?? {};
    final List<Map<String, dynamic>> payments = [];
    billPayments.forEach((key, value) {
      payments.add({"paymentMethodName": key});
    });
    if (payments.isEmpty) payments.add({"paymentMethodName": "Tiền mặt"});

    return {
      "generalInvoiceInfo": {
        "invoiceType": "1", // 1 là hóa đơn thường
        "templateCode": config.templateCode,
        "invoiceSeries": config.invoiceSeries,
        "currencyCode": "VND",
        "adjustmentType": "1", // 1 là hóa đơn gốc
        "paymentStatus": true,
        "cusGetInvoiceRight": true,
        "transactionUuid": _uuid.v4(),
      },
      "buyerInfo": {
        "buyerName": customer?.name ?? billData['customerName'] ?? "Khách lẻ",
        "buyerLegalName": customer?.companyName ?? customer?.name ?? "Khách lẻ",
        "buyerTaxCode": customer?.taxId,
        "buyerAddressLine": customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "buyerPhoneNumber": customer?.phone ?? billData['customerPhone'],
        "buyerEmail": customer?.email,
        "buyerNotGetInvoice": "0",
      },
      "payments": payments,
      "itemInfo": itemInfo,
      "taxBreakdowns": taxBreakdowns,
      "summarizeInfo": summarizeInfo,
    };
  }
}