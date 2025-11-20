import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'package:flutter/foundation.dart';

class VnptConfig {
  final String portalUrl;
  final String appId;
  final String appKey;
  final String username;
  final String password;
  final String templateCode;
  final String invoiceSeries;
  final bool autoIssueOnPayment;
  final String invoiceType; // 'vat' hoặc 'sale'

  VnptConfig({
    required this.portalUrl,
    required this.appId,
    required this.appKey,
    required this.username,
    required this.password,
    required this.templateCode,
    required this.invoiceSeries,
    this.autoIssueOnPayment = false,
    this.invoiceType = 'vat',
  });
}

class VnptEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  final _dio = Dio();

  Future<void> saveVnptConfig(VnptConfig config, String ownerUid) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));
      final dataToSave = {
        'provider': 'vnpt',
        'portalUrl': config.portalUrl,
        'appId': config.appId,
        'appKey': config.appKey,
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'invoiceType': config.invoiceType,
      };

      await _db.collection(_configCollection).doc(ownerUid).set(dataToSave);
      await _db.collection(_mainConfigCollection).doc(ownerUid).set({
        'activeProvider': 'vnpt'
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình VNPT: $e");
      throw Exception('Không thể lưu cấu hình VNPT.');
    }
  }

  Future<VnptConfig?> getVnptConfig(String ownerUid) async {
    try {
      final doc = await _db.collection(_configCollection).doc(ownerUid).get();
      if (!doc.exists) return null;

      final data = doc.data() as Map<String, dynamic>;
      if (data['provider'] != 'vnpt') return null;

      String decodedPassword;
      try {
        decodedPassword = utf8.decode(base64Decode(data['password'] ?? ''));
      } catch (e) {
        decodedPassword = '';
      }

      return VnptConfig(
        portalUrl: data['portalUrl'] ?? '',
        appId: data['appId'] ?? '',
        appKey: data['appKey'] ?? '',
        username: data['username'] ?? '',
        password: decodedPassword,
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
        invoiceType: data['invoiceType'] ?? 'vat',
      );
    } catch (e) {
      debugPrint ("Lỗi khi tải cấu hình VNPT: $e");
      throw Exception('Không thể tải cấu hình VNPT.');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid) async {
    final config = await getVnptConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      return EInvoiceConfigStatus(isConfigured: false);
    }
    return EInvoiceConfigStatus(
      isConfigured: true,
      autoIssueOnPayment: config.autoIssueOnPayment,
    );
  }

  Future<String?> loginToVnpt(
      String portalUrl, String appId, String appKey, String username, String password) async {
    try {
      final String apiUrl = "$portalUrl/auth/api/authenticate";
      final response = await _dio.post(
        apiUrl,
        data: {
          'app_id': appId,
          'app_key': appKey,
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
            'Lỗi ${e.response?.statusCode}: ${e.response?.data?['message'] ?? 'Sai thông tin'}');
      } else {
        throw Exception('Lỗi mạng. Vui lòng kiểm tra lại.');
      }
    }
  }

  Future<String?> _getValidToken(String ownerUid) async {
    final config = await getVnptConfig(ownerUid);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình VNPT HĐĐT.');
    }
    return await loginToVnpt(
        config.portalUrl, config.appId, config.appKey, config.username, config.password);
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

      final config = (await getVnptConfig(ownerUid))!;
      final payload = _buildVnptPayload(billData, customer, config);
      final String apiUrl = "${config.portalUrl}/business/api/invoice/phathanhd";

      final response = await _dio.post(
        apiUrl,
        data: jsonEncode(payload),
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      if (response.statusCode == 200 && response.data['result'] != null) {
        final resultData = response.data['result'] as Map<String, dynamic>;
        return EInvoiceResult(
          providerName: 'VNPT',
          invoiceNo: resultData['sohoadon'] as String,
          reservationCode: resultData['matracuu'] as String,
          lookupUrl: resultData['linktracuu'] as String,
          mst: resultData['mst_bban'] as String,
          rawResponse: resultData,
        );
      } else {
        throw Exception(response.data['message'] ?? 'Lỗi không xác định từ VNPT');
      }
    } on DioException catch (e) {
      final errorData = e.response?.data;
      if (errorData != null && errorData['message'] != null) {
        throw Exception('Lỗi VNPT: ${errorData['message']}');
      }
      throw Exception('Lỗi mạng khi tạo HĐĐT: ${e.message}');
    } catch (e) {
      throw Exception('Lỗi cục bộ khi tạo HĐĐT: ${e.toString()}');
    }
  }


  @override
  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse) async {
    final String? fkey = rawResponse['fkey'] as String?;
    final String? email = rawResponse['email_nguoimua'] as String?;

    if (fkey == null || email == null || email.isEmpty) {
      debugPrint("Không tìm thấy fkey hoặc email để gửi.");
      return;
    }

    final token = await _getValidToken(ownerUid);
    final config = (await getVnptConfig(ownerUid))!;

    try {
      final String apiUrl = "${config.portalUrl}/business/api/invoice/send-email-invoice";
      await _dio.post(
        apiUrl,
        data: { 'fkey': [fkey] },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      debugPrint("Đã gửi yêu cầu email HĐĐT VNPT cho $fkey");
    } on DioException catch (e) {
      debugPrint("Lỗi API VNPT (gửi email): $e");
    }
  }

  Map<String, dynamic> _buildVnptPayload(Map<String, dynamic> billData,
      CustomerModel? customer, VnptConfig config) {

    // --- LOGIC THUẾ CHUẨN ---
    final double taxPercent = (billData['taxPercent'] as num?)?.toDouble() ?? 0.0;
    String taxRateString = "KCT";

    if (config.invoiceType == 'vat') {
      if (taxPercent == 0) {taxRateString = "0";}
      else if (taxPercent == 5) {taxRateString = "5";}
      else if (taxPercent == 8) {taxRateString = "8";}
      else if (taxPercent == 10) {taxRateString = "10";}
      else {taxRateString = "10";}
    }

    final List<Map<String, dynamic>> dsHangHoa = [];
    final List<dynamic> billItems = billData['items'] ?? [];

    double totalTaxAmount = 0;

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1.0;
      final unitPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
      final itemTotal = (quantity * unitPrice).roundToDouble();

      // Tính thuế nếu là GTGT
      if (config.invoiceType == 'vat' && taxRateString != "KCT") {
        totalTaxAmount += (itemTotal * taxPercent / 100);
      }

      dsHangHoa.add({
        "stt": dsHangHoa.length + 1,
        "ten": item['productName'] ?? 'Sản phẩm',
        "dvt": item['unitName'] ?? 'cái',
        "soluong": quantity,
        "dongia": unitPrice,
        "thanhtien": itemTotal,
        "thuesuat": taxRateString, // Gửi chuỗi thuế đúng
      });
    }

    final double discount = (billData['discount'] as num?)?.toDouble() ?? 0.0;
    final double subtotal = (billData['subtotal'] as num?)?.toDouble() ?? 0.0;
    final double taxableAmount = (subtotal - discount).roundToDouble();

    // Nếu là GTGT -> Tổng thanh toán = Hàng + Thuế
    // Nếu là Bán hàng -> Tổng thanh toán = Hàng (đã gồm thuế)
    final double finalPayment = config.invoiceType == 'vat'
        ? (taxableAmount + totalTaxAmount).roundToDouble()
        : taxableAmount;

    return {
      "thongtinchung": {
        "mau": config.templateCode,
        "kyhieu": config.invoiceSeries,
        "loaihd": 1,
        "httt": "TM",
        "tinhchat": 1,
        "tygia": 1,
        "donvithu": "VND"
      },
      "thongtinnguoimua": {
        "ten": customer?.name ?? billData['customerName'] ?? "Khách lẻ",
        "tendv": customer?.companyName,
        "mst": customer?.taxId,
        "diachi": customer?.companyAddress ?? customer?.address ?? "Không có địa chỉ",
        "sdt": customer?.phone ?? billData['customerPhone'],
        "email": customer?.email,
      },
      "danhsachhanghoa": dsHangHoa,
      "tongtien": {
        "tongthanhtien": taxableAmount,
        "tienchietkhau": discount.roundToDouble(),
        "tienthue": totalTaxAmount.roundToDouble(), // Tiền thuế
        "tongtienthanhtoan": finalPayment,
        "sotienbangchu": "" // Để trống, VNPT tự sinh
      }
    };
  }
}