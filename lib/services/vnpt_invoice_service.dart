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

  VnptConfig({
    required this.portalUrl,
    required this.appId,
    required this.appKey,
    required this.username,
    required this.password,
    required this.templateCode,
    required this.invoiceSeries,
    this.autoIssueOnPayment = false,
  });
}

class VnptEInvoiceService implements EInvoiceProvider {
  final _db = FirebaseFirestore.instance;
  static const String _configCollection = 'e_invoice_configs';
  static const String _mainConfigCollection = 'e_invoice_main_configs';
  static const String _taxSettingsCollection = 'store_tax_settings';

  final _dio = Dio();

  Future<void> saveVnptConfig(VnptConfig config, String storeId) async {
    try {
      final encodedPassword = base64Encode(utf8.encode(config.password));
      final encodedAppKey = base64Encode(utf8.encode(config.appKey));

      await _db.collection(_configCollection).doc(storeId).set({
        'portalUrl': config.portalUrl,
        'appId': config.appId,
        'appKey': encodedAppKey,
        'username': config.username,
        'password': encodedPassword,
        'templateCode': config.templateCode,
        'invoiceSeries': config.invoiceSeries,
        'autoIssueOnPayment': config.autoIssueOnPayment,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      await _db.collection(_mainConfigCollection).doc(storeId).set({
        'activeProvider': 'vnpt',
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

    } catch (e) {
      debugPrint("Lỗi khi lưu cấu hình VNPT: $e");
      throw Exception('Không thể lưu cấu hình VNPT.');
    }
  }

  Future<VnptConfig?> getVnptConfig(String storeId) async {
    try {
      final doc = await _db.collection(_configCollection).doc(storeId).get();

      // 1. NẾU CHƯA CÓ DỮ LIỆU -> Trả về null để UI biết là "Chưa cấu hình"
      // Đây không phải lỗi, đây là logic bình thường.
      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;

      // 2. NẾU CÓ DỮ LIỆU -> Parse cẩn thận, tránh null safety
      return VnptConfig(
        portalUrl: data['portalUrl'] ?? '',
        appId: data['appId'] ?? '',
        appKey: data['appKey'] != null ? utf8.decode(base64Decode(data['appKey'])) : '',
        username: data['username'] ?? '',
        password: data['password'] != null ? utf8.decode(base64Decode(data['password'])) : '',
        templateCode: data['templateCode'] ?? '',
        invoiceSeries: data['invoiceSeries'] ?? '',
        autoIssueOnPayment: data['autoIssueOnPayment'] ?? false,
      );
    } catch (e) {
      // 3. NẾU CÓ LỖI THỰC SỰ (Mạng, Parse sai base64...) -> Báo lỗi ra
      debugPrint("Lỗi SYSTEM lấy config VNPT: $e");
      throw Exception('Lỗi hệ thống khi tải VNPT: $e');
    }
  }

  @override
  Future<EInvoiceConfigStatus> getConfigStatus(String storeId) async {
    final config = await getVnptConfig(storeId);
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

  Future<String?> _getValidToken(String storeId) async {
    final config = await getVnptConfig(storeId);
    if (config == null || config.username.isEmpty) {
      throw Exception('Chưa cấu hình VNPT HĐĐT.');
    }
    return await loginToVnpt(
        config.portalUrl, config.appId, config.appKey, config.username, config.password);
  }

  Future<String> _determineInvoiceTypeFromSettings(String storeId) async {
    try {
      final docSnapshot = await _db.collection(_taxSettingsCollection).doc(storeId).get();

      if (!docSnapshot.exists) {
        return "2";
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
      debugPrint("Lỗi lấy cấu hình thuế VNPT: $e");
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
        throw Exception('Không thể lấy token xác thực HĐĐT.');
      }

      final config = (await getVnptConfig(storeId))!;

      // Xác định loại hóa đơn
      final String determinedType = await _determineInvoiceTypeFromSettings(storeId);
      debugPrint(">>> VNPT Service: Loại hóa đơn: $determinedType (1=VAT, 2=Sale)");

      final payload = _buildPayloadWithAllocation(billData, customer, config, determinedType);
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
  Future<void> sendEmail(String storeId, Map<String, dynamic> rawResponse) async {
    final String? fkey = rawResponse['fkey'] as String?;
    final String? email = rawResponse['email_nguoimua'] as String?;

    if (fkey == null || email == null || email.isEmpty) return;

    final token = await _getValidToken(storeId);
    final config = (await getVnptConfig(storeId))!;

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
    } on DioException catch (e) {
      debugPrint("Lỗi API VNPT (gửi email): $e");
    }
  }

  Map<String, dynamic> _buildPayloadWithAllocation(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      VnptConfig config,
      String invoiceType
      ) {

    final List<dynamic> billItems = billData['items'] ?? [];
    final double billDiscount = (billData['discount'] as num?)?.toDouble() ?? 0.0;

    // Tính tổng hàng để phân bổ
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

    final List<Map<String, dynamic>> dsHangHoa = [];
    double totalAmountNet = 0;
    double totalTaxVal = 0;

    for (var item in billItems) {
      if (item['status'] == 'cancelled') continue;

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

      // b. Phân bổ giảm giá Bill
      double allocatedBillDisc = 0;
      if (totalGoodsValue > 0 && billDiscount > 0) {
        allocatedBillDisc = (lineTotalAfterSpec / totalGoodsValue) * billDiscount;
      }

      // Tổng giảm giá
      double totalLineDiscount = itemSpecificDiscAmount + allocatedBillDisc;

      // c. Giá trị thực thu (Net Amount)
      double itemNetAmount = rawLineTotal - totalLineDiscount;
      itemNetAmount = itemNetAmount.roundToDouble();

      // d. Đơn giá thực thu
      double effectiveUnitPrice = itemNetAmount;
      if (quantity > 0) {
        effectiveUnitPrice = itemNetAmount / quantity;
      }

      // e. Tính Thuế
      String taxRateString = "KCT";
      double itemVatAmount = 0;

      if (invoiceType == "1") {
        final double rawRate = (item['taxRate'] as num?)?.toDouble() ?? 0.0;
        final double percent = rawRate * 100;

        if ((percent - 10).abs() < 0.1) {taxRateString = "10";}
        else if ((percent - 8).abs() < 0.1) {taxRateString = "8";}
        else if ((percent - 5).abs() < 0.1) {taxRateString = "5";}
        else if ((percent - 0).abs() < 0.1) {taxRateString = "0";}
        else {taxRateString = "KCT";}

        if (taxRateString != "KCT") {
          double rateVal = double.parse(taxRateString) / 100;
          itemVatAmount = (itemNetAmount * rateVal).roundToDouble();
        }
      } else {
        taxRateString = "KCT";
      }

      dsHangHoa.add({
        "stt": dsHangHoa.length + 1,
        "ten": itemName,
        "dvt": unitName,
        "soluong": quantity,
        "dongia": effectiveUnitPrice, // Đơn giá đã giảm
        "thanhtien": itemNetAmount,   // Thành tiền đã giảm
        "thuesuat": taxRateString,
      });

      totalAmountNet += itemNetAmount;
      totalTaxVal += itemVatAmount;
    }

    final double finalPayment = totalAmountNet + totalTaxVal;
    String rawTaxId = customer?.taxId?.trim() ?? "";
    final bool hasValidTaxId = rawTaxId.length >= 10;
    String finalAddress = customer?.address ?? "Không có địa chỉ";
    if (hasValidTaxId && customer?.companyAddress != null && customer!.companyAddress!.trim().isNotEmpty) {
      finalAddress = customer.companyAddress!.trim();
    }
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
        "tendv": hasValidTaxId ? (customer?.companyName?.trim() ?? "") : "",
        "mst": hasValidTaxId ? rawTaxId : "",
        "diachi": finalAddress,
        "sdt": customer?.phone ?? billData['customerPhone'],
        "email": customer?.email,
      },
      "danhsachhanghoa": dsHangHoa,
      "tongtien": {
        "tongthanhtien": totalAmountNet.roundToDouble(),
        "tienchietkhau": 0, // Đã trừ vào giá
        "tienthue": totalTaxVal.roundToDouble(),
        "tongtienthanhtoan": finalPayment.roundToDouble(),
        "sotienbangchu": ""
      }
    };
  }
}