import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/customer_model.dart';
import '../screens/invoice/e_invoice_provider.dart';
import 'viettel_invoice_service.dart';
import 'vnpt_invoice_service.dart';
import 'misa_invoice_service.dart';
import 'vnpay_invoice_service.dart';
import 'package:flutter/foundation.dart';

class EInvoiceService {
  final _db = FirebaseFirestore.instance;
  static const String _mainConfigCollection = 'e_invoice_main_configs';

  Future<EInvoiceProvider?> _getActiveProvider(String ownerUid) async {
    final doc = await _db.collection(_mainConfigCollection).doc(ownerUid).get();
    if (!doc.exists) return null;

    final providerName = doc.data()?['activeProvider'] as String?;

    switch (providerName) {
      case 'viettel':
        return ViettelEInvoiceService();
      case 'vnpt':
        return VnptEInvoiceService();
      case 'misa':
        return MisaEInvoiceService();
      case 'vnpay':
        return VnpayEInvoiceService();
      default:
        return null;
    }
  }

  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid) async {
    final provider = await _getActiveProvider(ownerUid);
    if (provider != null) {
      return await provider.getConfigStatus(ownerUid);
    }
    return EInvoiceConfigStatus();
  }

  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid) async {
    final provider = await _getActiveProvider(ownerUid);
    if (provider == null) {
      throw Exception("Chưa cấu hình nhà cung cấp HĐĐT.");
    }

    final EInvoiceResult result =
    await provider.createInvoice(billData, customer, ownerUid);

    if (customer?.email != null && customer!.email!.isNotEmpty) {
      try {
        await provider.sendEmail(ownerUid, result.rawResponse);
      } catch (e) {
        debugPrint("Lỗi tự động gửi email HĐĐT: $e");
      }
    }

    return result;
  }
}