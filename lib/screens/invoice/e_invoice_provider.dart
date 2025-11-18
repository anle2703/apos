import '../../models/customer_model.dart';

class EInvoiceResult {
  final String providerName;
  final String invoiceNo;
  final String reservationCode;
  final String lookupUrl;
  final String mst;
  final Map<String, dynamic> rawResponse;

  EInvoiceResult({
    required this.providerName,
    required this.invoiceNo,
    required this.reservationCode,
    required this.lookupUrl,
    required this.mst,
    required this.rawResponse,
  });

  Map<String, dynamic> toJson() {
    return {
      'providerName': providerName,
      'invoiceNo': invoiceNo,
      'reservationCode': reservationCode,
      'lookupUrl': lookupUrl,
      'mst': mst,
      'rawResponse': rawResponse,
    };
  }

  factory EInvoiceResult.fromMap(Map<String, dynamic> map) {
    return EInvoiceResult(
      providerName: map['providerName'] ?? '',
      invoiceNo: map['invoiceNo'] ?? '',
      reservationCode: map['reservationCode'] ?? '',
      lookupUrl: map['lookupUrl'] ?? '',
      mst: map['mst'] ?? '',
      rawResponse: map['rawResponse'] ?? {},
    );
  }
}

class EInvoiceConfigStatus {
  final bool isConfigured;
  final bool autoIssueOnPayment;

  EInvoiceConfigStatus({
    this.isConfigured = false,
    this.autoIssueOnPayment = false,
  });
}

abstract class EInvoiceProvider {
  Future<EInvoiceResult> createInvoice(
      Map<String, dynamic> billData,
      CustomerModel? customer,
      String ownerUid,
      );

  Future<void> sendEmail(String ownerUid, Map<String, dynamic> rawResponse);

  Future<EInvoiceConfigStatus> getConfigStatus(String ownerUid);
}