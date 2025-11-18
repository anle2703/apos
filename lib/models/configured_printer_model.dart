// File: lib/models/configured_printer_model.dart

import 'package:app_4cash/screens/settings/settings_screen.dart';
import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart' as pos_printer;

class ConfiguredPrinter {
  final String logicalName;
  final ScannedPrinter physicalPrinter;

  ConfiguredPrinter({
    required this.logicalName,
    required this.physicalPrinter,
  });

  factory ConfiguredPrinter.fromJson(Map<String, dynamic> json) {
    final physicalPrinterMap = json['physicalPrinter'] as Map<String, dynamic>;
    final deviceInfo = physicalPrinterMap['device'] as Map<String, dynamic>;

    final device = pos_printer.PrinterDevice(
      name: deviceInfo['name'], address: deviceInfo['address'],
      vendorId: deviceInfo['vendorId'], productId: deviceInfo['productId'],
    );

    final type = pos_printer.PrinterType.values.firstWhere((e) => e.name == physicalPrinterMap['type']);

    return ConfiguredPrinter(
      logicalName: json['logicalName'],
      physicalPrinter: ScannedPrinter(device: device, type: type),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'logicalName': logicalName,
      'physicalPrinter': {
        'device': {
          'name': physicalPrinter.device.name, 'address': physicalPrinter.device.address,
          'vendorId': physicalPrinter.device.vendorId, 'productId': physicalPrinter.device.productId,
        },
        'type': physicalPrinter.type.name,
      },
    };
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