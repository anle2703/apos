import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class MisaConfig {
  final String taxCode;
  final String username;
  final String password;
  final String templateCode;
  final String invoiceSeries;
  final bool autoIssueOnPayment;

  MisaConfig({
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
  static const String _taxSettingsCollection = 'store_tax_settings';

  final _dio = Dio();
  final _uuid = const Uuid();

  static const String _misaBaseUrl = 'https://api.meinvoice.vn';
  static const String _misaAppId = '4bfc97cc-80e6-41d9-9a9b-9bbe71069a3d';

  Future<void> saveMisaConfig(MisaConfig config, String storeId) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));

      await _db.collection(_configCollection).doc(storeId).set({
        'taxCode': config.taxCode,
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection(_mainConfigCollection).doc(storeId).set({
        'activeProvider': 'misa',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình MISA: $e");
      throw Exception('Không thể lưu cấu hình MISA.');
    }
  }

  Future<MisaConfig?> getMisaConfig(String storeId) async {
    try {
      final doc = await _db.collection(_configCollection).doc(storeId).get();

      // 1. Chưa có config -> Return null (để hiện form trống)
      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;

      // 2. Có config -> Parse
      return MisaConfig(
        taxCode: data['taxCode'] ?? '',
        username: data['username'] ?? '',
        password: data['password'] != null ? utf8.decode(base64Decode(data['password'])) : '',
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
      );
    } catch (e) {
      // 3. Lỗi hệ thống -> Throw
      debugPrint("Lỗi SYSTEM lấy config MISA: $e");
      throw Exception('Lỗi hệ thống khi tải MISA: $e');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String storeId) async {
    final config = await getMisaConfig(storeId);
    if (config == null || config.username.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }
    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToMisa(String taxCode, String username, String password) async {
    try {
      final String authUrl = "$_misaBaseUrl/api/integration/auth/token";
      final response = await _dio.post(
        authUrl,
        data: {
          'tax_code': taxCode,
          'app_id': _misaAppId,
          'username': username,
          'password': password,
        },
        options: Options(sendTimeout: const Duration(seconds: 15)),
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data['access_token'] as String?;
      }
      return null;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError) {
        throw Exception('Không thể kết nối tới MISA ($_misaBaseUrl). Kiểm tra mạng.');
      }
      if (e.response != null) {
        throw Exception(
            'Lỗi MISA ${e.response?.statusCode}: ${e.response?.data?['Message'] ?? 'Sai thông tin đăng nhập'}');
      } else {
        throw Exception('Lỗi mạng: ${e.message}');
      }
    }
  }

  Future<String?> _getValidToken(String storeId) async {
    final config = await getMisaConfig(storeId);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình MISA HĐĐT.');
    }
    return await loginToMisa(config.taxCode, config.username, config.password);
  }

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
        if (revenueRange == 'high') return "1";
        return "2";
      }

      return "2";
    } catch (e) {
      debugPrint("Lỗi lấy cấu hình thuế MISA: $e");
      return "2";
    }
  }

  @override
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String storeId) async {
    try {
      final token = await _getValidToken(storeId);
      if (token == null) {
        throw Exception('Không thể lấy token xác thực MISA.');
      }

      final config = (await getMisaConfig(storeId))!;
      final transactionId = _uuid.v4();

      // Xác định loại hóa đơn
      final String determinedType = await _determineInvoiceTypeFromSettings(storeId);
      debugPrint(">>> MISA Service: Loại hóa đơn: $determinedType (1=VAT, 2=Sale)");

      // Build payload phân bổ
      final payload = _buildPayloadWithAllocation(billData, customer, config, transactionId, determinedType);

      final String apiUrl = "$_misaBaseUrl/api/integration/invoice/publish";

      final response = await _dio.post(
        apiUrl,
        data: jsonEncode(payload),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 45),
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final resultData = response.data as Map<String, dynamic>;

        if (resultData.containsKey('Success') && resultData['Success'] == false) {
          throw Exception(resultData['Data'] ?? resultData['Message'] ?? 'Lỗi tạo hóa đơn MISA');
        }

        final String reservationCode = resultData['TransactionID'] as String? ?? transactionId;
        final String invoiceNo = resultData['InvoiceNo'] as String? ?? 'Chưa cấp số';
        final String lookupUrl = 'https://meinvoice.vn/tra-cuu';

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
  Future<void> sendEmail(String storeId, Map<String, dynamic> rawResponse) async {
    final String? transactionId = rawResponse['TransactionID'] as String?;
    if (transactionId == null) return;

    final token = await _getValidToken(storeId);
    final config = (await getMisaConfig(storeId))!;

    try {
      final String apiUrl = "$_misaBaseUrl/api/integration/invoice/send-email";

      await _dio.post(
        apiUrl,
        queryParameters: { 'tax_code': config.taxCode },
        data: jsonEncode([transactionId]),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
    } on DioException catch (e) {
      debugPrint("Lỗi API MISA (gửi email): $e");
    }
  }

  Map<String, dynamic> _buildPayloadWithAllocation(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      MisaConfig config,
      String transactionId,
      String invoiceType
      ) {

    final List<dynamic> billItems = billData['items'] ?? [];
    final double billDiscount = (billData['discount'] as num?)?.toDouble() ?? 0.0;

    // Tính tổng tiền hàng để phân bổ
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

    final List<Map<String, dynamic>> items = [];
    double totalAmountNet = 0; // Tổng tiền hàng sau giảm giá
    double totalTaxVal = 0; // Tổng tiền thuế

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      // Lấy tên và ĐVT chuẩn
      final productMap = item['product'] as Map<String, dynamic>?;
      final String itemName = item['productName'] ?? productMap?['productName'] ?? 'Sản phẩm';
      final String unitName = item['unitName'] ?? item['selectedUnit'] ?? productMap?['unitName'] ?? 'cái';

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

      // b. Phân bổ giảm giá Bill (5.000đ)
      double allocatedBillDisc = 0;
      if (totalGoodsValue > 0 && billDiscount > 0) {
        allocatedBillDisc = (lineTotalAfterSpec / totalGoodsValue) * billDiscount;
      }

      // Tổng giảm giá
      double totalLineDiscount = itemSpecificDiscAmount + allocatedBillDisc;

      // c. Giá trị thực thu (Net Amount)
      double itemNetAmount = rawLineTotal - totalLineDiscount;
      itemNetAmount = itemNetAmount.roundToDouble();

      // Tính lại tổng giảm giá theo số làm tròn
      totalLineDiscount = rawLineTotal - itemNetAmount;

      // d. Đơn giá thực thu (Effective Unit Price)
      double effectiveUnitPrice = itemNetAmount;
      if (quantity > 0) {
        effectiveUnitPrice = itemNetAmount / quantity;
      }

      // e. Tính Thuế
      int misaTaxRate = -2;
      double itemVatAmount = 0;

      if (invoiceType == "1") {
        // Hóa đơn GTGT
        final double rawRate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
        final double percent = rawRate * 100;

        if ((percent - 10).abs() < 0.1) {misaTaxRate = 10;}
        else if ((percent - 8).abs() < 0.1) {misaTaxRate = 8;}
        else if ((percent - 5).abs() < 0.1) {misaTaxRate = 5;}
        else if ((percent - 0).abs() < 0.1) {misaTaxRate = 0;}
        else {misaTaxRate = -1;} // KKKNT

        if (misaTaxRate >= 0) {
          itemVatAmount = (itemNetAmount * misaTaxRate / 100).roundToDouble();
        }
      } else {
        misaTaxRate = -2; // KCT
      }

      // f. Add vào danh sách
      items.add({
        "ItemName": itemName,
        "UnitName": unitName,
        "Quantity": quantity,
        "UnitPrice": effectiveUnitPrice, // Đơn giá đã trừ CK
        "Amount": itemNetAmount,         // Thành tiền đã trừ CK
        "TaxRate": misaTaxRate,
        "VATAmount": itemVatAmount,
        "DiscountAmount": 0, // Đã trừ vào giá rồi
      });

      totalAmountNet += itemNetAmount;
      totalTaxVal += itemVatAmount;
    }

    final double totalPayable = totalAmountNet + totalTaxVal;

    final Map<String, dynamic> billPayments = billData['payments'] ?? {};
    String paymentMethod = "Tiền mặt";
    if (billPayments.isNotEmpty) {
      String rawMethod = billPayments.keys.first;
      if (rawMethod.toLowerCase().contains("chuyển khoản")) {
        paymentMethod = "Chuyển khoản";
      } else if (rawMethod.toLowerCase().contains("tiền mặt")) {
        paymentMethod = "Tiền mặt";
      } else {
        paymentMethod = "Tiền mặt/Chuyển khoản";
      }
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

      // Các trường tổng hợp (quan trọng để khớp thuế)
      "TotalSaleAmount": totalAmountNet.roundToDouble(), // Tổng tiền hàng sau giảm
      "DiscountAmount": 0, // Đã trừ vào từng dòng rồi
      "TotalTaxAmount": totalTaxVal.roundToDouble(),
      "TotalAmount": totalPayable.roundToDouble(),

      "AutoRenderTotalAmountInWords": true,
      "IsGetFromLocalData": false,
    };
  }
}