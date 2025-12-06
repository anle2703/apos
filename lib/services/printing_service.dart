import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4cash/services/native_printer_service.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart' as printing_lib;
import 'package:screenshot/screenshot.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cash_flow_transaction_model.dart';
import '../models/configured_printer_model.dart';
import '../models/label_template_model.dart';
import '../models/order_item_model.dart';
import '../models/receipt_template_model.dart';
import '../widgets/kitchen_ticket_widget.dart';
import '../widgets/label_widget.dart';
import '../widgets/receipt_widget.dart';
import '../widgets/cash_flow_ticket_widget.dart';
import '../widgets/end_of_day_report_widget.dart';
import '../widgets/vietqr_generator.dart';
import '../widgets/table_notification_widget.dart';

class PrintingService {
  final String tableName;
  final String userName;

  PrintingService({required this.tableName, required this.userName});

  final Map<String, String> _keysToLabels = const {
    'cashier_printer': 'Máy in Thu ngân',
    'kitchen_printer_a': 'Máy in A',
    'kitchen_printer_b': 'Máy in B',
    'kitchen_printer_c': 'Máy in C',
    'kitchen_printer_d': 'Máy in D',
    'label_printer': 'Máy in Tem',
  };

  // --- HÀM HỖ TRỢ CŨ (ĐỂ FIX LỖI Ở CÁC FILE KHÁC) ---
  static Future<pw.Font> loadFont(
      {bool isBold = false, bool isItalic = false}) async {
    try {
      if (isBold) {
        final fontData =
        await rootBundle.load('assets/fonts/RobotoMono-Bold.ttf');
        return pw.Font.ttf(fontData);
      } else if (isItalic) {
        final fontData =
        await rootBundle.load('assets/fonts/RobotoMono-Italic.ttf');
        return pw.Font.ttf(fontData);
      } else {
        final fontData =
        await rootBundle.load('assets/fonts/RobotoMono-Regular.ttf');
        return pw.Font.ttf(fontData);
      }
    } catch (e) {
      debugPrint("Lỗi load font: $e");
      return pw.Font.courier();
    }
  }

  Future<void> disconnectPrinter(PrinterType type) async {
    await PrinterManager.instance.disconnect(type: type);
  }

  Future<ReceiptTemplateModel> _loadReceiptSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('receipt_template_settings');
    if (jsonStr != null) {
      return ReceiptTemplateModel.fromJson(jsonStr);
    }
    return ReceiptTemplateModel();
  }

  Future<bool> _printFromWidget({
    required Widget widgetToPrint,
    required ConfiguredPrinter printer,
  }) async {
    try {
      debugPrint(">>> START PRINT FROM WIDGET...");
      final ScreenshotController localController = ScreenshotController();

      // 1. Cấu hình kích thước chuẩn 80mm = 576 dots
      const double paperWidth = 576.0;

      // 2. Wrapper để căn chỉnh nội dung
      final wrapperWidget = Container(
        width: paperWidth,
        color: Colors.white,
        alignment: Alignment.topCenter, // Căn giữa nội dung 550px
        child: widgetToPrint,
      );

      final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS);

      // 3. Chụp ảnh
      // Với Desktop: Dùng pixelRatio nhỏ hơn (1.5) để tránh ảnh quá to
      // Với Mobile: Dùng pixelRatio cao (2.0) để nét
      final double pixelRatio = isDesktop ? 1.5 : 2.0;

      final Uint8List imageBytes = await localController.captureFromWidget(
        Material(
          color: Colors.white,
          child: wrapperWidget,
        ),
        delay: const Duration(milliseconds: 60),
        pixelRatio: pixelRatio,
        context: null,
        targetSize: const Size(paperWidth, double.infinity),
      );

      // A. DESKTOP: Gọi hàm xử lý riêng
      if (isDesktop) {
        return await _printImageViaDesktopDriver(printer.physicalPrinter.device, imageBytes);
      }

      // B. MOBILE / LAN: Xử lý ESC/POS
      debugPrint(">>> PROCESSING IMAGE IN ISOLATE...");
      final List<int> printCommands = await compute(_processBillImageInIsolate, {
        'bytes': imageBytes,
      });

      final device = printer.physicalPrinter.device;
      final type = printer.physicalPrinter.type;

      if (type == PrinterType.usb) {
        if (!kIsWeb && Platform.isAndroid) {
          // Logic dành riêng cho máy POS Android có tích hợp sẵn service in
          try {
            final nativeService = NativePrinterService();
            return await nativeService.print(device.address!, Uint8List.fromList(printCommands));
          } catch (e) {
            debugPrint("Lỗi in Native USB (Android): $e");
            // Fallback sang thư viện thường nếu native fail
            return await _sendToPrinterManager(printer, printCommands);
          }
        } else {
          debugPrint(">>> Cảnh báo: In USB chỉ hỗ trợ trên Android POS. Bỏ qua lệnh in.");
          return false; // Trả về false thay vì cố in gây lỗi
        }
      }
      else if (type == PrinterType.network) {
        return await _sendBytesViaSocket(device.address!, printCommands);
      } else {
        return await _sendToPrinterManager(printer, printCommands);
      }
    } catch (e) {
      debugPrint("Lỗi in từ Widget: $e");
      rethrow;
    }
  }

  // 1. IN HÓA ĐƠN
  Future<bool> printReceiptBill({
    required Map<String, String> storeInfo,
    required List<OrderItem> items,
    required Map<String, dynamic> summary,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );
      final settings = await _loadReceiptSettings();

      // --- LOGIC TẠO QR DATA ---
      String? qrDataString;

      // [SỬA] Đổi tên biến local thành displayTableName để tránh trùng tên với biến class
      // Khi đó không cần dùng 'this.tableName' nữa mà dùng 'tableName' trực tiếp.
      final String displayTableName = (summary['tableName'] ?? tableName).toString();

      try {
        final Map<String, dynamic>? bankDetails = (summary['bankDetails'] as Map<String, dynamic>?);
        final double totalPayable = (summary['totalPayable'] as num?)?.toDouble() ?? 0.0;

        if (bankDetails != null && totalPayable > 0) {
          final String bin = (bankDetails['bankBin'] ?? '').toString();
          final String acc = (bankDetails['bankAccount'] ?? '').toString();

          if (bin.isNotEmpty && acc.isNotEmpty) {
            final String amount = totalPayable.toInt().toString();

            // Sử dụng biến local mới
            final String addInfo = displayTableName.trim().isNotEmpty
                ? "TT $displayTableName"
                : "Thanh toan";

            qrDataString = VietQrGenerator.generate(
              bankBin: bin,
              bankAccount: acc,
              amount: amount,
              description: addInfo,
            );

            debugPrint(">>> Generated QR Data: $qrDataString");
          } else {
            debugPrint(">>> Thiếu BIN hoặc Số TK, không tạo QR.");
          }
        }
      } catch (e) {
        debugPrint("Lỗi tạo mã QR: $e");
      }
      // --------------------------

      final widget = ReceiptWidget(
        title: 'HÓA ĐƠN',
        storeInfo: storeInfo,
        items: items.where((i) => i.quantity > 0).toList(),
        summary: summary,
        userName: userName,
        // Truyền biến local mới vào Widget
        tableName: displayTableName,
        showPrices: true,
        isSimplifiedMode: false,
        templateSettings: settings,
        qrData: qrDataString,
      );

      return await _printFromWidget(widgetToPrint: widget, printer: cashierPrinter);
    } catch (e) {
      debugPrint('Lỗi in hóa đơn: $e');
      rethrow;
    }
  }

  // 2. IN TẠM TÍNH
  Future<bool> printProvisionalBill({
    required Map<String, String> storeInfo,
    required List<OrderItem> items,
    required Map<String, dynamic> summary,
    required bool showPrices,
    required List<ConfiguredPrinter> configuredPrinters,
    bool useDetailedLayout = false,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );
      final settings = await _loadReceiptSettings();
      final String title = showPrices ? 'TẠM TÍNH' : 'KIỂM MÓN';

      final widget = ReceiptWidget(
        title: title,
        storeInfo: storeInfo,
        items: items.where((i) => i.quantity > 0).toList(),
        summary: summary,
        userName: userName,
        tableName: tableName,
        showPrices: showPrices,
        isSimplifiedMode: !useDetailedLayout,
        templateSettings: settings,
      );

      return await _printFromWidget(
          widgetToPrint: widget, printer: cashierPrinter);
    } catch (e) {
      debugPrint('Lỗi in tạm tính: $e');
      rethrow;
    }
  }

  // 3. IN BÁO BẾP
  Future<bool> printKitchenTicket({
    required List<OrderItem> itemsToPrint,
    required String targetPrinterRole,
    required List<ConfiguredPrinter> configuredPrinters,
    String? customerName,
  }) async {
    if (itemsToPrint.isEmpty) return true;
    try {
      final targetPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == targetPrinterRole,
        orElse: () => throw Exception(
            '${_keysToLabels[targetPrinterRole] ?? targetPrinterRole} chưa được gán.'),
      );
      final settings = await _loadReceiptSettings();

      final widget = KitchenTicketWidget(
        title: 'BÁO BẾP',
        tableName: tableName,
        items: itemsToPrint,
        userName: userName,
        customerName: customerName,
        isCancelTicket: false,
        templateSettings: settings,
      );

      return await _printFromWidget(
          widgetToPrint: widget, printer: targetPrinter);
    } catch (e) {
      rethrow;
    }
  }

  // 4. IN HỦY MÓN
  Future<bool> printCancelTicket({
    required List<OrderItem> itemsToCancel,
    required String targetPrinterRole,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    if (itemsToCancel.isEmpty) return true;
    try {
      final targetPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == targetPrinterRole,
        orElse: () => throw Exception('Máy in chưa được gán.'),
      );
      final settings = await _loadReceiptSettings();

      final widget = KitchenTicketWidget(
        title: 'HỦY MÓN',
        tableName: tableName,
        items: itemsToCancel,
        userName: userName,
        isCancelTicket: true,
        templateSettings: settings,
      );

      return await _printFromWidget(
          widgetToPrint: widget, printer: targetPrinter);
    } catch (e) {
      rethrow;
    }
  }

  // 5. IN TEM
  Future<bool> printLabels({
    required List<Map<String, dynamic>> items,
    required String tableName,
    required DateTime createdAt,
    required List<ConfiguredPrinter> configuredPrinters,
    required double width,   // Tham số này sẽ bị ghi đè bởi settings
    required double height,  // Tham số này sẽ bị ghi đè bởi settings
    bool isRetailMode = false,
    String? billCode,
    String? templateSettingsJson,
  }) async {
    try {
      final labelPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'label_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Tem".'),
      );

      final bool isDesktop = !kIsWeb && (Platform.isWindows || Platform.isMacOS);

      // --- BƯỚC 1: LOAD VÀ ƯU TIÊN SETTINGS ---
      LabelTemplateModel settings;

      // 1.1. Thử load từ JSON gửi kèm (Ưu tiên cao nhất)
      if (templateSettingsJson != null && templateSettingsJson.isNotEmpty) {
        try {
          settings = LabelTemplateModel.fromJson(templateSettingsJson);
        } catch (e) {
          debugPrint("Lỗi parse templateSettingsJson: $e");
          // Fallback nếu lỗi
          settings = LabelTemplateModel(labelWidth: width, labelHeight: height);
        }
      } else {
        // 1.2. Nếu không có, load từ bộ nhớ máy (Fallback)
        final prefs = await SharedPreferences.getInstance();
        final jsonStr = prefs.getString('label_template_settings');
        if (jsonStr != null) {
          settings = LabelTemplateModel.fromJson(jsonStr);
        } else {
          // 1.3. Mặc định cuối cùng
          settings = LabelTemplateModel(labelWidth: width, labelHeight: height);
          settings.labelColumns = (width >= 65) ? 2 : 1;
        }
      }

      // --- BƯỚC 2: CHUẨN HÓA KÍCH THƯỚC (QUAN TRỌNG) ---
      // Bắt buộc dùng kích thước trong settings để đảm bảo giống hệt lúc In Test
      final double finalWidth = settings.labelWidth;
      final double finalHeight = settings.labelHeight;
      final int columns = settings.labelColumns;

      // --- BƯỚC 3: XỬ LÝ DỮ LIỆU ---
      List<LabelItemData> allLabelsQueue = [];
      int grandTotalQty = items.fold(
          0, (tong, item) => tong + (OrderItem.fromMap(item).quantity).ceil());
      final int dailySeq = await _getNextLabelSequence();

      int globalCurrentIndex = 0;

      for (var itemData in items) {
        final item = OrderItem.fromMap(itemData);
        final int itemQty = item.quantity.ceil();

        // Header
        String headerDisplay = (billCode != null && billCode.isNotEmpty) ? billCode : tableName;
        if (itemData['headerTitle'] != null) {
          headerDisplay = itemData['headerTitle'];
        }

        int startIndex = itemData['labelIndex'] ?? (globalCurrentIndex + 1);
        int totalInBatch = itemData['labelTotal'] ?? grandTotalQty;

        for (int i = 1; i <= itemQty; i++) {
          allLabelsQueue.add(LabelItemData(
            item: item,
            headerTitle: headerDisplay,
            index: startIndex,
            total: totalInBatch,
            dailySeq: dailySeq,
          ));
          startIndex++;
        }
        globalCurrentIndex += itemQty;
      }

      final ScreenshotController localController = ScreenshotController();
      List<Uint8List> desktopImageBytesList = [];
      List<int> totalTsplCommands = [];

      // Tính toán pixel dựa trên kích thước chuẩn hóa (8 dots/mm)
      double targetWidthPx = finalWidth * 8.0;
      double targetHeightPx = finalHeight * 8.0;

      for (int i = 0; i < allLabelsQueue.length; i += columns) {
        List<LabelItemData?> rowItems = [];
        for (int c = 0; c < columns; c++) {
          if (i + c < allLabelsQueue.length) {
            rowItems.add(allLabelsQueue[i + c]);
          } else {
            rowItems.add(null);
          }
        }

        // Mobile cần pixelRatio thấp hơn để tránh tràn bộ nhớ máy in cũ
        double capturePixelRatio = isDesktop ? 4.0 : 2.0;

        final Uint8List imageBytes = await localController.captureFromWidget(
          Directionality(
            textDirection: ui.TextDirection.ltr,
            child: MediaQuery(
              // Ép buộc kích thước Widget đúng theo settings
              data: MediaQueryData(size: Size(targetWidthPx, targetHeightPx)),
              child: LabelRowWidget(
                items: rowItems,
                widthMm: finalWidth,   // Dùng finalWidth
                heightMm: finalHeight, // Dùng finalHeight
                gapMm: 2.0,
                isRetailMode: isRetailMode,
                settings: settings,    // Truyền settings đã load để chỉnh font/margin
              ),
            ),
          ),
          delay: const Duration(milliseconds: 20),
          targetSize: Size(targetWidthPx, targetHeightPx),
          pixelRatio: capturePixelRatio,
        );

        if (isDesktop) {
          desktopImageBytesList.add(imageBytes);
        } else {
          final List<int> commands =
          await compute(_processLabelImageInIsolate, {
            'bytes': imageBytes,
            'width': finalWidth,   // Gửi kích thước chuẩn xuống Isolate
            'height': finalHeight, // Gửi kích thước chuẩn xuống Isolate
          });
          totalTsplCommands.addAll(commands);
        }
      }

      // --- BƯỚC 4: GỬI LỆNH IN ---

      if (isDesktop) {
        if (desktopImageBytesList.isEmpty) return true;
        final pdf = pw.Document();
        for (final imgBytes in desktopImageBytesList) {
          final image = pw.MemoryImage(imgBytes);
          pdf.addPage(pw.Page(
              pageFormat: PdfPageFormat(
                  finalWidth * PdfPageFormat.mm, finalHeight * PdfPageFormat.mm,
                  marginAll: 0),
              build: (ctx) {
                return pw.Center(child: pw.Image(image, fit: pw.BoxFit.fill));
              }));
        }
        return await _printPdfViaDesktopDriver(
            labelPrinter.physicalPrinter.device, await pdf.save());
      }

      if (totalTsplCommands.isEmpty) return true;

      if (labelPrinter.physicalPrinter.type == PrinterType.network) {
        return await _sendBytesViaSocket(
            labelPrinter.physicalPrinter.device.address!, totalTsplCommands);
      } else {
        final String? deviceId = labelPrinter.physicalPrinter.device.address;
        if (deviceId != null && deviceId.isNotEmpty) {
          final nativeService = NativePrinterService();
          return await nativeService.print(
              deviceId, Uint8List.fromList(totalTsplCommands));
        }
        return false;
      }
    } catch (e) {
      debugPrint('Lỗi in tem: $e');
      rethrow;
    }
  }

  // 6. IN PHIẾU THU/CHI (THÊM MỚI)
  Future<bool> printCashFlowTicket({
    required Map<String, String> storeInfo,
    required CashFlowTransaction transaction,
    required double? openingDebt,
    required double? closingDebt,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      // SỬA: Dùng Widget mới tách ra
      final widget = CashFlowTicketWidget(
        storeInfo: storeInfo,
        transaction: transaction,
        userName: userName,
      );

      return await _printFromWidget(widgetToPrint: widget, printer: cashierPrinter);
    } catch (e) {
      debugPrint("Lỗi in phiếu thu/chi: $e");
      rethrow;
    }
  }

  // 7. IN BÁO CÁO CUỐI NGÀY (THÊM MỚI)
  Future<bool> printEndOfDayReport({
    required Map<String, String> storeInfo,
    required Map<String, dynamic> totalReportData,
    required List<Map<String, dynamic>> shiftReportsData,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      // SỬA: Dùng Widget mới tách ra
      final widget = EndOfDayReportWidget(
        storeInfo: storeInfo,
        totalReportData: totalReportData,
        shiftReportsData: shiftReportsData,
        userName: userName,
      );

      return await _printFromWidget(widgetToPrint: widget, printer: cashierPrinter);
    } catch (e) {
      debugPrint("Lỗi in báo cáo cuối ngày: $e");
      rethrow;
    }
  }

  // 8. IN THÔNG BÁO QUẢN LÝ BÀN (THÊM MỚI)
  Future<bool> printTableManagementNotification({
    required Map<String, String> storeInfo,
    required String actionTitle,
    required String message,
    required String userName,
    required DateTime timestamp,
    required List<ConfiguredPrinter> configuredPrinters,
  }) async {
    try {
      final cashierPrinter = configuredPrinters.firstWhere(
            (p) => p.logicalName == 'cashier_printer',
        orElse: () => throw Exception('Chưa cấu hình "Máy in Thu ngân".'),
      );

      final settings = await _loadReceiptSettings();

      // Sử dụng Widget mới
      final widget = TableNotificationWidget(
        storeInfo: storeInfo,
        actionTitle: actionTitle,
        message: message,
        userName: userName,
        timestamp: timestamp,
        templateSettings: settings,
      );

      return await _printFromWidget(widgetToPrint: widget, printer: cashierPrinter);
    } catch (e) {
      debugPrint("Lỗi in thông báo bàn: $e");
      rethrow;
    }
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Future<int> _getNextLabelSequence() async {
    final prefs = await SharedPreferences.getInstance();
    final String todayStr = DateFormat('yyyyMMdd').format(DateTime.now());
    final String lastDate = prefs.getString('label_seq_date') ?? '';
    int currentSeq = prefs.getInt('label_seq_num') ?? 0;
    if (lastDate != todayStr) {
      currentSeq = 1;
      await prefs.setString('label_seq_date', todayStr);
    } else {
      currentSeq++;
    }
    await prefs.setInt('label_seq_num', currentSeq);
    return currentSeq;
  }

  Future<bool> _sendToPrinterManager(
      ConfiguredPrinter printer, List<int> bytes) async {
    final printerManager = PrinterManager.instance;
    final type = printer.physicalPrinter.type;
    final device = printer.physicalPrinter.device;

    try {
      await printerManager.disconnect(type: type);
      await Future.delayed(const Duration(milliseconds: 100));

      final model = _getPrinterModel(device, type);
      bool isConnected = await printerManager.connect(type: type, model: model);

      if (isConnected) {
        // Fix: Truyền trực tiếp bytes (List<int>) thay vì bọc trong Uint8List
        // để tránh lỗi ClassCastException trên Android Native
        await printerManager.send(type: type, bytes: bytes);
        await Future.delayed(const Duration(milliseconds: 200));
        await printerManager.disconnect(type: type);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Lỗi PrinterManager: $e");
      return false;
    }
  }

  Future<bool> _sendBytesViaSocket(String ipAddress, List<int> bytes) async {
    try {
      final socket = await Socket.connect(ipAddress, 9100,
          timeout: const Duration(seconds: 5));
      const int chunkSize = 4096;
      for (var i = 0; i < bytes.length; i += chunkSize) {
        var end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
        socket.add(bytes.sublist(i, end));
        await Future.delayed(const Duration(milliseconds: 10));
      }
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _printImageViaDesktopDriver(PrinterDevice printer, Uint8List imageBytes) async {
    try {
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      // Khổ giấy in nhiệt khả dụng trên Desktop (72mm)
      const double pdfPageWidth = 72.0 * PdfPageFormat.mm;

      // Tạo trang PDF với chiều rộng cố định, chiều dài vô tận (cuộn giấy)
      pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat(pdfPageWidth, double.infinity, marginAll: 0),
          build: (ctx) {
            // QUAN TRỌNG:
            // Dùng width = pdfPageWidth để ép ảnh về đúng kích thước 72mm
            // BoxFit.contain sẽ giữ tỷ lệ ảnh, ngăn chặn phóng to tràn lề
            return pw.Center(
                child: pw.Image(
                    image,
                    width: pdfPageWidth,
                    fit: pw.BoxFit.contain
                )
            );
          }));

      return await _printPdfViaDesktopDriver(printer, await pdf.save());
    } catch (e) {
      return false;
    }
  }

  Future<bool> _printPdfViaDesktopDriver(
      PrinterDevice printer, Uint8List pdfBytes) async {
    try {
      debugPrint(">>> IN WINDOWS DRIVER: ${printer.name}");
      final printers = await printing_lib.Printing.listPrinters();
      final targetPrinter = printers.firstWhere(
            (p) => p.name == printer.name,
        orElse: () =>
            printing_lib.Printer(url: printer.name, name: printer.name),
      );
      return await printing_lib.Printing.directPrintPdf(
        printer: targetPrinter,
        onLayout: (format) async => pdfBytes,
        usePrinterSettings: true,
      );
    } catch (e) {
      debugPrint("Lỗi In Driver Windows: $e");
      return false;
    }
  }

  BasePrinterInput _getPrinterModel(PrinterDevice printer, PrinterType type) {
    switch (type) {
      case PrinterType.network:
        return TcpPrinterInput(ipAddress: printer.address!, port: 9100);
      case PrinterType.bluetooth:
        return BluetoothPrinterInput(
            name: printer.name,
            address: printer.address!,
            isBle: false,
            autoConnect: true);
      case PrinterType.usb:
        return UsbPrinterInput(
            name: printer.name,
            vendorId: printer.vendorId,
            productId: printer.productId);
    }
  }
}

Future<List<int>> _processBillImageInIsolate(
    Map<String, dynamic> params) async {
  final Uint8List imageBytes = params['bytes'];
  final int targetWidth = 576; // Chuẩn 80mm

  img.Image? decoded = img.decodeImage(imageBytes);
  if (decoded == null) return [];

  if (decoded.width != targetWidth) {
    decoded = img.copyResize(decoded, width: targetWidth);
  }

  final int width = decoded.width;
  final int height = decoded.height;
  final int bytesPerLine = (width + 7) ~/ 8;

  List<int> buffer = [];

// Header ESC/POS
  buffer.addAll([0x1D, 0x76, 0x30, 0]);
  buffer.add(bytesPerLine % 256);
  buffer.add(bytesPerLine ~/ 256);
  buffer.add(height % 256);
  buffer.add(height ~/ 256);

  for (int y = 0; y < height; y++) {
    for (int i = 0; i < bytesPerLine; i++) {
      int byte = 0;
      for (int bit = 0; bit < 8; bit++) {
        int x = i * 8 + bit;
        if (x < width) {
          final pixel = decoded.getPixel(x, y);
          final luminance = img.getLuminance(pixel);
          if (luminance < 180) {
            byte |= (1 << (7 - bit));
          }
        }
      }
      buffer.add(byte);
    }
  }
  buffer.addAll([0x1D, 0x56, 0x41, 0x00]); // Cut
  return buffer;
}

List<int> _processLabelImageInIsolate(Map<String, dynamic> params) {
  final Uint8List imageBytes = params['bytes'];
  final double widthMm = params['width'];
  final double heightMm = params['height'];

  final decodedImage = img.decodeImage(imageBytes);
  if (decodedImage == null) return [];

  final int targetWidth = (widthMm * 8).toInt();
  final int targetHeight = (heightMm * 8).toInt();

  final resizedImage = img.copyResize(decodedImage,
      width: targetWidth,
      height: targetHeight,
      interpolation: img.Interpolation.nearest);

  List<int> commands = [];
  int w = widthMm.toInt();
  int h = heightMm.toInt();

  String cmd = 'SIZE $w mm, $h mm\r\nGAP 2 mm, 0 mm\r\nDIRECTION 1\r\nCLS\r\n';
  commands.addAll(utf8.encode(cmd));

  int widthPx = resizedImage.width;
  int heightPx = resizedImage.height;
  int widthBytes = (widthPx + 7) ~/ 8;

  String bitmapHeader = 'BITMAP 0,0,$widthBytes,$heightPx,0,';
  commands.addAll(utf8.encode(bitmapHeader));

  List<int> bitmapData = [];
  for (int y = 0; y < heightPx; y++) {
    for (int i = 0; i < widthBytes; i++) {
      int byte = 0xFF;
      for (int j = 0; j < 8; j++) {
        int x = i * 8 + j;
        if (x < widthPx) {
          final pixel = resizedImage.getPixel(x, y);
          if (pixel.luminance < 128) {
            byte &= ~(1 << (7 - j));
          }
        }
      }
      bitmapData.add(byte);
    }
  }
  commands.addAll(bitmapData);
  commands.addAll(utf8.encode('\r\nPRINT 1,1\r\n'));
  return commands;
}