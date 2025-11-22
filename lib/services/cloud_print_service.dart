// lib/services/cloud_print_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:flutter/foundation.dart';

import '../models/configured_printer_model.dart';
import '../models/order_item_model.dart';
import 'printing_service.dart';
import '../models/cash_flow_transaction_model.dart';

class CloudPrintService {
  static final CloudPrintService _instance = CloudPrintService._internal();
  factory CloudPrintService() => _instance;
  CloudPrintService._internal();

  HttpServer? _runningServer;
  StreamSubscription<QuerySnapshot>? _cloudPrintSub;

  String? _currentMode;
  String? _currentStoreId;

  Future<void> stopListener() async {
    if (_runningServer != null) {
      await _runningServer!.close(force: true);
      debugPrint(">>> Máy chủ in đã dừng (nội bộ).");
      _runningServer = null;
    }

    await _cloudPrintSub?.cancel();
    if (_cloudPrintSub != null) {
      debugPrint(">>> Cloud print listener đã dừng (internet).");
      _cloudPrintSub = null;
    }
  }

  Future<void> startListener(String storeId, String mode) async {
    if ((_currentMode == mode) && (_currentStoreId == storeId)) {
      debugPrint(">>> Listener đã chạy với mode: $mode cho store: $storeId, bỏ qua.");
      return;
    }

    _currentMode = mode;
    _currentStoreId = storeId;

    await stopListener();

    debugPrint(">>> Cập nhật listener mode: $mode");

    if (mode == 'internet') {
      await _initCloudPrintListener(storeId);
    } else {
      await _initPrintServer();
    }
  }

  Future<void> _initCloudPrintListener(String storeId) async {
    debugPrint(">>> KHỞI TẠO CLOUD PRINT LISTENER cho store: $storeId...");

    _cloudPrintSub = FirebaseFirestore.instance
        .collection('print_jobs')
        .where('storeId', isEqualTo: storeId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) return;

      Future.microtask(() async {
        debugPrint(">>> Có ${snapshot.docs.length} lệnh in mới từ cloud cho store $storeId!");

        for (final doc in snapshot.docs) {
          try {
            await doc.reference.update({'status': 'processing'});

            final data = doc.data();

            final service = PrintingService(
              tableName: data['tableName']?.toString() ?? 'Unknown',
              userName: data['userName']?.toString() ?? 'System',
            );

            final items = (data['items'] as List).map((m) => OrderItem.fromMap(m)).toList();

            final configuredPrinters = await _getConfiguredPrintersFromPrefs();
            if (configuredPrinters == null) {
              throw Exception('Chưa cấu hình máy in trên thiết bị máy chủ.');
            }

            final jobType = data['type'] as String?;
            final customerName = data['customerName'] as String?;

            if (jobType == 'kitchen' || jobType == 'cancel') {
              // 1. CHUẨN BỊ DỮ LIỆU (Phân loại món theo máy in)
              final labelsToKeys = const {
                'Máy in Thu ngân': 'cashier_printer',
                'Máy in A': 'kitchen_printer_a',
                'Máy in B': 'kitchen_printer_b',
                'Máy in C': 'kitchen_printer_c',
                'Máy in D': 'kitchen_printer_d',
                'Máy in Tem': 'label_printer',
              };

              final Map<String, List<OrderItem>> jobsByPrinter = {};
              for (final item in items) {
                for (final printerLabel in item.product.kitchenPrinters) {
                  final roleKey = labelsToKeys[printerLabel] ?? '';
                  if (roleKey.isNotEmpty) {
                    jobsByPrinter.putIfAbsent(roleKey, () => []).add(item);
                  }
                }
              }

              // 2. VÒNG LẶP IN BẾP
              bool allSuccess = true;
              for (var entry in jobsByPrinter.entries) {
                final printerRole = entry.key;
                final itemsForPrinter = entry.value;
                bool success = false;

                if (jobType == 'kitchen') {
                  success = await service.printKitchenTicket(
                    itemsToPrint: itemsForPrinter,
                    targetPrinterRole: printerRole,
                    configuredPrinters: configuredPrinters,
                    customerName: customerName,
                  );
                } else {
                  success = await service.printCancelTicket(
                    itemsToCancel: itemsForPrinter,
                    targetPrinterRole: printerRole,
                    configuredPrinters: configuredPrinters,
                  );
                }
                if (!success) allSuccess = false;
              }

              if (!allSuccess) {
                throw Exception("Một vài lệnh in bếp/hủy từ Cloud đã thất bại.");
              }

              // 3. LOGIC TỰ ĐỘNG IN TEM TẠI SERVER
              if (jobType == 'kitchen') {
                debugPrint(">>> [DEBUG SERVER] Bắt đầu kiểm tra in tem tự động...");

                final ownerQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .where('storeId', isEqualTo: storeId)
                    .where('role', isEqualTo: 'owner')
                    .limit(1)
                    .get();

                bool shouldPrintLabel = false;
                double w = 50.0;
                double h = 30.0;

                if (ownerQuery.docs.isNotEmpty) {
                  final sData = ownerQuery.docs.first.data();
                  // Đọc cài đặt từ user data
                  shouldPrintLabel = sData['printLabelOnKitchen'] ?? false;
                  w = (sData['labelWidth'] as num?)?.toDouble() ?? 50.0;
                  h = (sData['labelHeight'] as num?)?.toDouble() ?? 30.0;
                }

                // Nếu bật in tem -> Thực thi
                if (shouldPrintLabel) {
                  try {
                    final rawItems = items.map((e) => e.toMap()).toList();
                    await service.printLabels(
                      items: rawItems,
                      tableName: data['tableName'],
                      createdAt: (data['createdAt'] as Timestamp).toDate(),
                      configuredPrinters: configuredPrinters,
                      width: w,
                      height: h,
                    );
                  } catch (e) {
                    debugPrint(">>> [DEBUG SERVER] Lỗi khi gọi hàm printLabels: $e");
                  }
                }
              }
            } else if (jobType == 'provisional') {
              final storeInfo = (data['storeInfo'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()));
              final showPrices = data['showPrices'] as bool;

              final ok = await service.printProvisionalBill(
                storeInfo: storeInfo,
                items: items,
                summary: data['summary'] as Map<String, dynamic>,
                showPrices: showPrices,
                configuredPrinters: configuredPrinters,
              );
              if (!ok) throw Exception("In tạm tính từ Cloud thất bại.");

            } else if (jobType == 'detailedProvisional') {
              final storeInfo = (data['storeInfo'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()));
              final showPrices = data['showPrices'] as bool? ?? true;

              final ok = await service.printProvisionalBill(
                storeInfo: storeInfo,
                items: items,
                summary: data['summary'] as Map<String, dynamic>,
                showPrices: showPrices,
                configuredPrinters: configuredPrinters,
                useDetailedLayout: (data['summary'] as Map<String, dynamic>?)?['useDetailedLayout'] as bool? ?? true,
              );
              if (!ok) throw Exception("In tạm tính chi tiết từ Cloud thất bại.");

            } else if (jobType == 'receipt') {
              final storeInfo = (data['storeInfo'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()));

              Map<String, dynamic> summary;
              if (data['summary'] is Map) {
                summary = Map<String, dynamic>.from(data['summary']);
              } else {
                summary = {
                  'subtotal'     : (data['subtotal'] as num?)?.toDouble(),
                  'discount'     : (data['discount'] as num?)?.toDouble(),
                  'discountType' : data['discountType'],
                  'taxPercent'   : (data['taxPercent'] as num?)?.toDouble(),
                  'totalPayable' : (data['totalPayable'] as num?)?.toDouble(),
                  'changeAmount' : (data['changeAmount'] as num?)?.toDouble(),
                  'pointsValue'  : (data['pointsValue'] as num?)?.toDouble(),
                  'surcharges'   : data['surcharges'] is List ? data['surcharges'] : const [],
                  'payments'     : data['payments'] is Map  ? data['payments']  : const {},
                };
              }

              final ok = await service.printReceiptBill(
                storeInfo: storeInfo,
                items: items,
                summary: summary,
                configuredPrinters: configuredPrinters,
              );
              if (!ok) throw Exception("In hóa đơn (receipt) từ Cloud thất bại.");

            } else if (jobType == 'cashFlow') {
              final storeInfo = (data['storeInfo'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()));

              final txData = data['transaction'] as Map<String, dynamic>;
              final txId = data['transactionId'] as String;
              final transaction = CashFlowTransaction.fromMap(txData, txId);

              final cashFlowService = PrintingService(
                  tableName: "Thu/Chi",
                  userName: transaction.user
              );

              final ok = await cashFlowService.printCashFlowTicket(
                storeInfo: storeInfo,
                transaction: transaction,
                openingDebt: data['openingDebt'] as double?,
                closingDebt: data['closingDebt'] as double?,
                configuredPrinters: configuredPrinters,
              );
              if (!ok) throw Exception("In phiếu thu/chi từ Cloud thất bại.");
            } else if (jobType == 'endOfDayReport') {
              final storeInfo = (data['storeInfo'] as Map)
                  .map((k, v) => MapEntry(k.toString(), v.toString()));

              final totalData = (data['totalReportData'] as Map).cast<String, dynamic>();
              final shiftData = (data['shiftReportsData'] as List).map((i) => (i as Map).cast<String, dynamic>()).toList();

              final reportService = PrintingService(
                  tableName: "Báo Cáo",
                  userName: data['userName']
              );

              final ok = await reportService.printEndOfDayReport(
                storeInfo: storeInfo,
                totalReportData: totalData,
                shiftReportsData: shiftData,
                configuredPrinters: configuredPrinters,
              );
              if (!ok) throw Exception("In Báo Cáo Tổng Kết từ Cloud thất bại.");
            } else if (jobType == 'tableManagement') {
              final prefs = await SharedPreferences.getInstance();
              final storeInfoString = prefs.getString('store_info');
              final Map<String, String> storeInfo = storeInfoString != null
                  ? Map<String, String>.from(jsonDecode(storeInfoString))
                  : {};

              final ok = await service.printTableManagementNotification(
                storeInfo: storeInfo,
                actionTitle: data['actionTitle'] as String,
                message: data['message'] as String,
                userName: data['userName'] as String,
                timestamp: DateTime.parse(data['timestamp'] as String),
                configuredPrinters: configuredPrinters,
              );
              if (!ok) throw Exception("In thông báo QL Bàn từ Cloud thất bại.");
            } else if (jobType == 'label') {
              // --- SỬA LỖI NULL TẠI ĐÂY ---

              // 1. Xử lý an toàn cho tableName (nếu null thì gán giá trị mặc định)
              final String tableName = data['tableName']?.toString() ?? 'Tem';

              final printingService = PrintingService(
                  tableName: tableName,
                  userName: data['userName'] ?? 'System'
              );

              // 2. Parse items
              final rawItems = data['items'] as List;
              final itemsMap = rawItems.map((e) => e as Map<String, dynamic>).toList();

              // 3. Xử lý an toàn cho createdAt (nếu null hoặc sai kiểu thì lấy giờ hiện tại)
              DateTime createdAt;
              if (data['createdAt'] != null && data['createdAt'] is Timestamp) {
                createdAt = (data['createdAt'] as Timestamp).toDate();
              } else {
                createdAt = DateTime.now();
              }

              final ok = await printingService.printLabels(
                items: itemsMap,
                tableName: tableName,
                createdAt: createdAt,
                configuredPrinters: configuredPrinters,
                width: (data['labelWidth'] as num?)?.toDouble() ?? 50.0,
                height: (data['labelHeight'] as num?)?.toDouble() ?? 30.0,
              );

              if (!ok) throw Exception("In Tem từ Cloud thất bại.");
            } else {
              throw Exception('Loại lệnh in không xác định: $jobType');
            }

            await doc.reference.update({
              'status': 'completed',
              'processedAt': FieldValue.serverTimestamp(),
            });
          } catch (e, st) {
            debugPrint("--- LỖI IN CLOUD CHI TIẾT ---");
            debugPrint("JOB ID: ${doc.id}");
            debugPrint("LỖI: ${e.toString()}");
            debugPrint("STACKTRACE: $st");
            debugPrint("-----------------------------");
            await doc.reference.update({'status': 'failed', 'error': e.toString()});
          }
        }
      });
    });
  }

  Future<List<ConfiguredPrinter>?> _getConfiguredPrintersFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('printer_assignments');
    if (jsonString == null) return null;
    final List<dynamic> jsonList = jsonDecode(jsonString);
    return jsonList.map((json) => ConfiguredPrinter.fromJson(json)).toList();
  }

  List<Map<String, dynamic>> _normalizeItemsData(List itemsData) {
    for (var itemMap in itemsData) {
      if (itemMap is Map<String, dynamic>) {
        // Chuyển đổi 'addedAt' nếu nó là String
        if (itemMap['addedAt'] is String) {
          try {
            itemMap['addedAt'] = Timestamp.fromDate(DateTime.parse(itemMap['addedAt']));
          } catch (_) { /* Bỏ qua nếu parse lỗi */ }
        }

        // Chuyển đổi các mốc thời gian trong 'priceBreakdown'
        if (itemMap['priceBreakdown'] is List) {
          for (var block in (itemMap['priceBreakdown'] as List)) {
            if (block is Map<String, dynamic>) {
              if (block['startTime'] is String) {
                try {
                  block['startTime'] = Timestamp.fromDate(DateTime.parse(block['startTime']));
                } catch (_) {}
              }
              if (block['endTime'] is String) {
                try {
                  block['endTime'] = Timestamp.fromDate(DateTime.parse(block['endTime']));
                } catch (_) {}
              }
            }
          }
        }
      }
    }
    return itemsData.map((e) => e as Map<String, dynamic>).toList();
  }

  Future<void> _initPrintServer() async {
    final router = shelf_router.Router();

    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('printer_assignments');
    if (jsonString == null) {
      debugPrint('!!! CHƯA cấu hình máy in → server không thể in.');
      return;
    }
    final List<dynamic> jsonList = jsonDecode(jsonString);
    final configuredPrinters = jsonList.map((json) => ConfiguredPrinter.fromJson(json)).toList();

    router.post('/print/kitchen', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

        final normalizedItems = _normalizeItemsData(data['items'] as List);
        final itemsToPrint = normalizedItems.map((m) => OrderItem.fromMap(m)).toList();
        final printingService = PrintingService(tableName: data['tableName'], userName: data['userName']);
        final targetRole = data['targetPrinterRole'] as String;
        final customerName = data['customerName'] as String?;

        final success = await printingService.printKitchenTicket(
          itemsToPrint: itemsToPrint,
          targetPrinterRole: targetRole,
          configuredPrinters: configuredPrinters,
          customerName: customerName,
        );
        return success ? Response.ok('OK') : Response.internalServerError(body: 'In thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server kitchen: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/provisional', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

        final normalizedItems = _normalizeItemsData(data['items'] as List);
        final items = normalizedItems.map((m) => OrderItem.fromMap(m)).toList();
        final storeInfo = (data['storeInfo'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        final showPrices = data['showPrices'] as bool;

        final printingService = PrintingService(tableName: data['tableName'], userName: data['userName']);

        final success = await printingService.printProvisionalBill(
          storeInfo: storeInfo,
          items: items,
          summary: data['summary'] as Map<String, dynamic>,
          showPrices: showPrices,
          configuredPrinters: configuredPrinters,
        );
        return success ? Response.ok('OK') : Response.internalServerError(body: 'In thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server provisional: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/detailedProvisional', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

        final normalizedItems = _normalizeItemsData(data['items'] as List);
        final items = normalizedItems.map((m) => OrderItem.fromMap(m)).toList();
        final storeInfo = (data['storeInfo'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        final showPrices = data['showPrices'] as bool;

        final printingService = PrintingService(tableName: data['tableName'], userName: data['userName']);

        final success = await printingService.printProvisionalBill(
          storeInfo: storeInfo,
          items: items,
          summary: data['summary'] as Map<String, dynamic>,
          showPrices: showPrices,
          configuredPrinters: configuredPrinters,
          useDetailedLayout: (data['summary'] as Map<String, dynamic>?)?['useDetailedLayout'] as bool? ?? true,
        );
        return success ? Response.ok('OK') : Response.internalServerError(body: 'In thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server detailed provisional: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/cancel', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

        final normalizedItems = _normalizeItemsData(data['items'] as List);
        final itemsToCancel = normalizedItems.map((m) => OrderItem.fromMap(m)).toList();
        final printingService = PrintingService(tableName: data['tableName'], userName: data['userName']);

        final targetRole = data['targetPrinterRole'] as String;
        final success = await printingService.printCancelTicket(
          itemsToCancel: itemsToCancel,
          targetPrinterRole: targetRole,
          configuredPrinters: configuredPrinters,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In hủy món thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server cancel: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/receipt', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;

        final normalizedItems = _normalizeItemsData(data['items'] as List);
        final items = normalizedItems.map((m) => OrderItem.fromMap(m)).toList();
        final storeInfo = (data['storeInfo'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));

        Map<String, dynamic> summary;
        if (data['summary'] is Map) {
          summary = Map<String, dynamic>.from(data['summary']);
        } else {
          summary = {
            'subtotal'     : (data['subtotal'] as num?)?.toDouble(),
            'discount'     : (data['discount'] as num?)?.toDouble(),
            'discountType' : data['discountType'],
            'taxPercent'   : (data['taxPercent'] as num?)?.toDouble(),
            'totalPayable' : (data['totalPayable'] as num?)?.toDouble(),
            'changeAmount' : (data['changeAmount'] as num?)?.toDouble(),
            'pointsValue'  : (data['pointsValue'] as num?)?.toDouble(),
            'surcharges'   : data['surcharges'] is List ? data['surcharges'] : const [],
            'payments'     : data['payments'] is Map  ? data['payments']  : const {},
          };
        }

        final printingService = PrintingService(tableName: data['tableName'], userName: data['userName']);
        final success = await printingService.printReceiptBill(
          storeInfo: storeInfo,
          items: items,
          summary: summary,
          configuredPrinters: configuredPrinters,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In hóa đơn thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server receipt: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/cashFlow', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final configuredPrinters = await _getConfiguredPrintersFromPrefs() ?? [];

        final storeInfo = (data['storeInfo'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));

        final txData = data['transaction'] as Map<String, dynamic>;
        final txId = data['transactionId'] as String;
        final transaction = CashFlowTransaction.fromMap(txData, txId);

        final printingService = PrintingService(
            tableName: "Thu/Chi",
            userName: transaction.user
        );

        final success = await printingService.printCashFlowTicket(
          storeInfo: storeInfo,
          transaction: transaction,
          openingDebt: data['openingDebt'] as double?,
          closingDebt: data['closingDebt'] as double?,
          configuredPrinters: configuredPrinters,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In phiếu thu/chi thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server cashFlow: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/endOfDayReport', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final configuredPrinters = await _getConfiguredPrintersFromPrefs() ?? [];

        final storeInfo = (data['storeInfo'] as Map).map((k, v) => MapEntry(k.toString(), v.toString()));
        final totalData = (data['totalReportData'] as Map).cast<String, dynamic>();
        final shiftData = (data['shiftReportsData'] as List).map((i) => (i as Map).cast<String, dynamic>()).toList();

        final printingService = PrintingService(
            tableName: "Báo Cáo",
            userName: data['userName']
        );

        final success = await printingService.printEndOfDayReport(
          storeInfo: storeInfo,
          totalReportData: totalData,
          shiftReportsData: shiftData,
          configuredPrinters: configuredPrinters,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In Báo Cáo Tổng Kết thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server endOfDayReport: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    router.post('/print/tableManagement', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final configuredPrinters = await _getConfiguredPrintersFromPrefs() ?? [];

        final prefs = await SharedPreferences.getInstance();
        final storeInfoString = prefs.getString('store_info');
        final Map<String, String> storeInfo = storeInfoString != null
            ? Map<String, String>.from(jsonDecode(storeInfoString))
            : {};

        final printingService = PrintingService(
            tableName: "Chuyển/Gộp/Tách Bàn",
            userName: data['userName']
        );

        final success = await printingService.printTableManagementNotification(
          storeInfo: storeInfo,
          actionTitle: data['actionTitle'] as String,
          message: data['message'] as String,
          userName: data['userName'] as String,
          timestamp: DateTime.parse(data['timestamp'] as String),
          configuredPrinters: configuredPrinters,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In thông báo QL Bàn thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server tableManagement: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });
    router.post('/print/label', (Request request) async {
      try {
        final data = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
        final configuredPrinters = await _getConfiguredPrintersFromPrefs() ?? [];

        // FIX: Kiểm tra tableName (nếu null thì fallback)
        final String tableName = data['tableName']?.toString() ?? 'Tem';

        final printingService = PrintingService(
            tableName: tableName,
            userName: 'System' // Tem không quan trọng user
        );

        // Chuẩn hóa dữ liệu items
        final normalizedItems = _normalizeItemsData(data['items'] as List);

        // FIX: Kiểm tra createdAt an toàn
        DateTime createdAt;
        if (data['createdAt'] != null) {
          try {
            createdAt = DateTime.parse(data['createdAt'].toString());
          } catch (_) {
            createdAt = DateTime.now();
          }
        } else {
          createdAt = DateTime.now();
        }

        final bool isRetail = data['isRetailMode'] ?? false;
        final success = await printingService.printLabels(
          items: normalizedItems,
          tableName: tableName,
          createdAt: createdAt,
          configuredPrinters: configuredPrinters,
          width: (data['labelWidth'] as num?)?.toDouble() ?? 50.0,
          height: (data['labelHeight'] as num?)?.toDouble() ?? 30.0,
          isRetailMode: isRetail,
        );

        return success ? Response.ok('OK') : Response.internalServerError(body: 'In Tem thất bại');
      } catch (e, st) {
        debugPrint(">>> Lỗi in server label: $e\n$st");
        return Response.internalServerError(body: e.toString());
      }
    });

    _runningServer = await shelf_io.serve(router.call, InternetAddress.anyIPv4, 8080);
    debugPrint('>>> MÁY CHỦ IN đang chạy tại: http://${_runningServer!.address.host}:${_runningServer!.port}');
  }
}