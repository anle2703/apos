import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class NativePrinter {
  final String identifier;
  final String name;
  final int vendorId;
  final int productId;

  NativePrinter({
    required this.identifier,
    required this.name,
    required this.vendorId,
    required this.productId,
  });

  factory NativePrinter.fromMap(Map<dynamic, dynamic> map) {
    return NativePrinter(
      identifier: map['identifier'] ?? '',
      name: map['productName'] ?? 'USB Printer',
      vendorId: map['vendorId'] ?? 0,
      productId: map['productId'] ?? 0,
    );
  }
}

class NativePrinterService {
  static const MethodChannel _channel = MethodChannel('com.example.app_4cash/usb_printer');

  Future<List<NativePrinter>> getPrinters() async {
    try {
      final List<dynamic> result = await _channel.invokeMethod('getDeviceList');
      return result.map((e) => NativePrinter.fromMap(e)).toList();
    } catch (e) {
      debugPrint("Lỗi quét Native: $e");
      return [];
    }
  }

  // HÀM IN: Gửi lệnh ngay lập tức
  Future<bool> print(String identifier, Uint8List data) async {
    try {
      debugPrint(">>> NativePrint: Bắn lệnh in tới $identifier");
      await _channel.invokeMethod('printData', {
        'identifier': identifier,
        'data': data,
      });
      return true;
    } catch (e) {
      debugPrint(">>> NativePrint Lỗi: $e");
      // QUAN TRỌNG: Phải ném lỗi ra ngoài để PrintQueueService biết đường sửa lỗi
      rethrow;
    }
  }
}