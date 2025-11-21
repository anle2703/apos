// File: lib/models/configured_printer_model.dart

import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart';

/// Class ScannedPrinter: Được di chuyển về đây để dùng chung cho cả App
class ScannedPrinter {
  final PrinterDevice device;
  final PrinterType type;

  ScannedPrinter({required this.device, required this.type});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScannedPrinter &&
        other.device.name == device.name &&
        other.device.address == device.address &&
        other.device.vendorId == device.vendorId &&
        other.device.productId == device.productId;
  }

  @override
  int get hashCode =>
      device.name.hashCode ^
      device.address.hashCode ^
      device.vendorId.hashCode ^
      device.productId.hashCode;
}

class ConfiguredPrinter {
  final String logicalName;
  final ScannedPrinter physicalPrinter;

  ConfiguredPrinter({
    required this.logicalName,
    required this.physicalPrinter,
  });

  // Chuyển object thành JSON để lưu vào SharedPreferences
  Map<String, dynamic> toJson() {
    return {
      'logicalName': logicalName,
      'physicalPrinter': {
        'name': physicalPrinter.device.name,
        'address': physicalPrinter.device.address,
        'vendorId': physicalPrinter.device.vendorId, // Quan trọng
        'productId': physicalPrinter.device.productId,
        // Đã xóa dòng deviceId gây lỗi
        'type': physicalPrinter.type.name,
      },
    };
  }

  // Đọc JSON từ SharedPreferences để tạo lại object
  factory ConfiguredPrinter.fromJson(Map<String, dynamic> json) {
    final printerJson = json['physicalPrinter'] as Map<String, dynamic>;

    // Khôi phục loại kết nối (mặc định là network nếu lỗi)
    final typeName = printerJson['type'] as String? ?? 'network';
    final type = PrinterType.values.firstWhere(
          (e) => e.name == typeName,
      orElse: () => PrinterType.network,
    );

    return ConfiguredPrinter(
      logicalName: json['logicalName'],
      physicalPrinter: ScannedPrinter(
        device: PrinterDevice(
          name: printerJson['name'],
          address: printerJson['address'],
          vendorId: printerJson['vendorId'],
          productId: printerJson['productId'],
          // Đã xóa dòng deviceId gây lỗi
        ),
        type: type,
      ),
    );
  }

  String getPrinterLabel() {
    const Map<String, String> keysToLabels = {
      'cashier_printer': 'Máy in Thu ngân (Hóa đơn)',
      'kitchen_printer_a': 'Máy in A',
      'kitchen_printer_b': 'Máy in B',
      'kitchen_printer_c': 'Máy in C',
      'kitchen_printer_d': 'Máy in D',
      'label_printer': 'Máy in Tem',
    };
    return keysToLabels[logicalName] ?? '';
  }
}