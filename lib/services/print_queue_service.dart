// File: lib/services/print_queue_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:sunmi_printer_plus/sunmi_printer_plus.dart';
import '../models/print_job_model.dart';
import '../models/configured_printer_model.dart';
import '../models/order_item_model.dart';
import 'printing_service.dart';
import 'firestore_service.dart';
import '../services/toast_service.dart';
import '../models/cash_flow_transaction_model.dart';
import '../theme/string_extensions.dart';

class PrintQueueService {
  static final PrintQueueService _instance = PrintQueueService._internal();
  factory PrintQueueService() => _instance;
  PrintQueueService._internal();

  static const _localFailedQueueKey = 'failed_print_jobs';

  final Uuid _uuid = const Uuid();
  final FirestoreService _firestoreService = FirestoreService();
  StreamSubscription? _cloudErrorSubscription;

  final ValueNotifier<List<PrintJob>> failedJobsNotifier = ValueNotifier([]);

  bool _isInitialized = false;

  Future<void> initialize(String storeId) async {
    await _loadFailedJobsFromPrefs();
    if (!_isInitialized) {
      _startListeningForCloudErrors(storeId);
      _isInitialized = true;
    }
  }

  Future<void> addJob(PrintJobType type, Map<String, dynamic> data) async {
    if (type == PrintJobType.provisional ||
        type == PrintJobType.receipt ||
        type == PrintJobType.detailedProvisional ||
        type == PrintJobType.cashFlow ||
        type == PrintJobType.endOfDayReport ||
        type == PrintJobType.tableManagement) {
      final job = PrintJob(
        id: _uuid.v4(),
        type: type,
        data: data,
        createdAt: DateTime.now(),
      );
      _processSingleJob(job);
      return;
    }

    // Kitchen / Cancel: tách theo vai trò máy in bếp
    if (type == PrintJobType.kitchen || type == PrintJobType.cancel) {
      final items = (data['items'] as List)
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();

      final Map<String, List<OrderItem>> jobsByPrinter = {};

      const labelsToKeys = {
        'Máy in Thu ngân': 'cashier_printer',
        'Máy in A': 'kitchen_printer_a',
        'Máy in B': 'kitchen_printer_b',
        'Máy in C': 'kitchen_printer_c',
        'Máy in D': 'kitchen_printer_d',
        'Máy in Tem': 'label_printer',
      };

      for (final item in items) {
        if (item.product.kitchenPrinters.isNotEmpty) {
          for (final label in item.product.kitchenPrinters) {
            final roleKey = labelsToKeys[label] ?? '';
            if (roleKey.isNotEmpty) {
              jobsByPrinter.putIfAbsent(roleKey, () => []).add(item);
            }
          }
        }
      }

      // Nếu không có món nào được gán máy in bếp, mặc định in ra máy thu ngân
      if (jobsByPrinter.isEmpty && items.isNotEmpty) {
        debugPrint("Không có món nào được chỉ định máy in bếp, sẽ in ra máy thu ngân.");
        jobsByPrinter['cashier_printer'] = items;
      }

      if (jobsByPrinter.isEmpty) {
        debugPrint("Không có món nào để tạo lệnh in bếp.");
        return;
      }

      for (final entry in jobsByPrinter.entries) {
        final printerRole = entry.key;
        final printerItems = entry.value;

        final jobDataForPrinter = Map<String, dynamic>.from(data);
        jobDataForPrinter['items'] =
            printerItems.map((i) => i.toMap()).toList();
        jobDataForPrinter['targetPrinterRole'] = printerRole;

        final job = PrintJob(
          id: _uuid.v4(),
          type: type,
          data: jobDataForPrinter,
          createdAt: DateTime.now(),
        );
        _processSingleJob(job);
      }
      return;
    }
  }

  Future<void> _processSingleJob(PrintJob job) async {
    final prefs = await SharedPreferences.getInstance();
    final printMode = prefs.getString('client_print_mode') ?? 'direct';

    bool success = false;
    try {
      if (printMode == 'internet') {
        success = await _sendJobToCloud(job);
      } else {
        success = await _executePrintLocally(job, printMode);
      }
    } catch (e) {
      debugPrint("Lỗi nghiêm trọng khi thực thi job ${job.id}: $e");
      success = false;

      String userFriendlyMessage;
      final errorString = e.toString();
      if (e is SocketException ||
          e is http.ClientException ||
          errorString.contains('Connection refused') ||
          errorString.contains('Failed host lookup') ||
          errorString.contains('timed out')) {
        userFriendlyMessage =
        'Không thể kết nối đến máy chủ in. Vui lòng kiểm tra lại IP và kết nối mạng.';
      } else {
        userFriendlyMessage = errorString.replaceFirst("Exception: ", "");
      }

      ToastService()
          .show(message: userFriendlyMessage, type: ToastType.error);
      job.data['error'] = userFriendlyMessage;
    }

    if (!success && printMode != 'internet') {
      _addFailedJob(job);
    }
  }

  Future<bool> _sendJobToCloud(PrintJob job) async {
    try {
      final data = job.data;
      final storeId = data['storeId'] as String;

      final cleanedItems = (data['items'] as List)
          .map((e) => e is Map<String, dynamic> ? e : (e as dynamic).toMap())
          .toList();

      final payload = <String, dynamic>{
        'storeId': storeId,
        'tableName': data['tableName'],
        'userName': data['userName'],
        'items': cleanedItems,
        'type': job.type.name,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      };

      if (data.containsKey('customerName')) payload['customerName'] = data['customerName'];
      if (data.containsKey('storeInfo')) payload['storeInfo'] = data['storeInfo'];

      if (data.containsKey('totalAmount')) payload['totalAmount'] = data['totalAmount'];
      if (data.containsKey('showPrices'))  payload['showPrices']  = data['showPrices'];

      if (data['summary'] is Map) {
        payload['summary'] = Map<String, dynamic>.from(data['summary']);
      }

      for (final k in const [
        'subtotal',
        'discount',
        'discountType',
        'surcharges',
        'taxPercent',
        'payments',
        'customerPointsUsed',
        'changeAmount',
        'totalPayable',
        'pointsValue',
        'customer',
        'printReceipt',
      ]) {
        if (data.containsKey(k)) payload[k] = data[k];
      }

      if (job.type == PrintJobType.endOfDayReport) {
        payload['storeInfo'] = data['storeInfo'];
        payload['totalReportData'] = data['totalReportData'];
        payload['shiftReportsData'] = data['shiftReportsData'];
      }

      payload.remove('targetPrinterRole');
      payload.remove('error');

      final docRef = await _firestoreService.createPrintJobDocument(payload, storeId);

      _startJobTimeoutCheck(docRef.id, storeId, job);
      debugPrint("Đã tạo print job trên Cloud với ID: ${docRef.id}");
      return true;
    } catch (e) {
      debugPrint("Lỗi khi gửi job lên Cloud: $e");
      return false;
    }
  }

  void _startJobTimeoutCheck(
      String docId, String storeId, PrintJob originalJob) {
    Future.delayed(const Duration(seconds: 4), () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('print_jobs')
            .doc(docId)
            .get();

        if (doc.exists && doc.data()?['status'] == 'pending') {
          debugPrint(
              ">>> Job $docId bị timeout, server có thể đang offline hoặc sai chế độ.");
          await doc.reference.update({
            'status': 'failed',
            'error': 'Client timeout: Server did not respond.'
          });

          final failedJob = originalJob.copyWith(firestoreId: docId);
          if (!failedJobsNotifier.value
              .any((j) => j.firestoreId == failedJob.firestoreId)) {
            _addFailedJob(failedJob);
          }
        }
      } catch (e) {
        debugPrint("Lỗi khi kiểm tra job timeout: $e");
      }
    });
  }

  Future<bool> _executePrintLocally(
      PrintJob job, String printMode) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('printer_assignments');
    if (jsonString == null) throw Exception('Chưa cấu hình máy in.');

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final allConfiguredPrinters =
    jsonList.map((j) => ConfiguredPrinter.fromJson(j)).toList();

    // --- BẮT ĐẦU LOGIC TÁI CẤU TRÚC ---

    // 1. Quyết định một lần duy nhất: Có phải gửi lệnh in qua Server LAN không?
    final bool isMobileAndInServerMode = printMode == 'server' &&
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux);

    if (isMobileAndInServerMode) {
      // Nếu đúng, gửi qua server và kết thúc. Áp dụng cho MỌI LOẠI JOB.
      final serverIp = (await SharedPreferences.getInstance()).getString('print_server_ip');
      if (serverIp == null || serverIp.isEmpty) {
        throw Exception("Chưa cấu hình IP máy chủ.");
      }
      return await _sendJobToServerLAN(serverIp, job);
    }

    // 2. Nếu không, tất cả các trường hợp còn lại đều là in trực tiếp (Direct Print)
    // Bao gồm: 'direct' mode trên mọi nền tảng, và 'server' mode trên PC.

    // Logic cho phiếu Bếp / Hủy
    if (job.type == PrintJobType.kitchen || job.type == PrintJobType.cancel) {
      // Ưu tiên Sunmi nếu có máy in bếp nào là Sunmi
      final useSunmi = allConfiguredPrinters.any((p) =>
      p.logicalName.startsWith('kitchen_printer_') &&
          p.physicalPrinter.device.address == 'sunmi_internal');
      if (useSunmi) {
        return await _printWithSunmiSDK(job);
      } else {
        return await _printWithGenericService(job, allConfiguredPrinters);
      }
    }

    if (job.type == PrintJobType.provisional ||
        job.type == PrintJobType.detailedProvisional ||
        job.type == PrintJobType.receipt ||
        job.type == PrintJobType.cashFlow ||
        job.type == PrintJobType.endOfDayReport ||
        job.type == PrintJobType.tableManagement) {
      final target = _getTargetPrinterForJob(job.type, allConfiguredPrinters);
      if (target == null) {
        throw Exception("Chưa cấu hình máy in thu ngân.");
      }
      if (target.physicalPrinter.device.address == 'sunmi_internal' &&
          job.type != PrintJobType.cashFlow &&
          job.type != PrintJobType.endOfDayReport &&
          job.type != PrintJobType.tableManagement) {
        return await _printWithSunmiSDK(job);
      } else {
        return await _printWithGenericService(job, allConfiguredPrinters);
      }
    }

    return true;
  }

  ConfiguredPrinter? _getTargetPrinterForJob(
      PrintJobType type, List<ConfiguredPrinter> allPrinters) {
    String? logicalName;
    if (type == PrintJobType.provisional ||
        type == PrintJobType.receipt ||
        type == PrintJobType.detailedProvisional ||
        type == PrintJobType.cashFlow ||
        type == PrintJobType.endOfDayReport ||
        type == PrintJobType.tableManagement) {
      logicalName = 'cashier_printer';
    }
    if (logicalName == null) return null;
    try {
      return allPrinters.firstWhere((p) => p.logicalName == logicalName);
    } catch (_) {
      return null;
    }
  }

  Future<bool> _printWithSunmiSDK(PrintJob job) async {
    try {
      final data = job.data;
      final items = (data['items'] as List)
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();
      final tableName = data['tableName'];
      final isCancelTicket = job.type == PrintJobType.cancel;

      final alignCenter = SunmiPrintAlign.CENTER;
      final alignLeft = SunmiPrintAlign.LEFT;
      final alignRight = SunmiPrintAlign.RIGHT;

      String title = '';
      switch (job.type) {
        case PrintJobType.kitchen:
          title = 'CHẾ BIẾN';
          break;
        case PrintJobType.provisional:
          final bool showPrices = data['showPrices'] as bool? ?? true;
          title = showPrices ? 'TẠM TÍNH' : 'KIỂM MÓN';
          break;
        case PrintJobType.detailedProvisional:
          title = 'TẠM TÍNH';
          break;
        case PrintJobType.cancel:
          title = 'HỦY MÓN';
          break;
        case PrintJobType.receipt:
          title = 'HÓA ĐƠN';
          break;
        case PrintJobType.cashFlow:
          title = 'PHIẾU THU/CHI';
          break;
        case PrintJobType.endOfDayReport:
          title = 'BÁO CÁO TỔNG KẾT';
          break;
        case PrintJobType.tableManagement: // <-- THÊM VÀO ĐÂY
          title = 'THÔNG BÁO'; // Sunmi không dùng mẫu này, nhưng để phòng hờ
          break;
      }

      await SunmiPrinter.printText('$title - $tableName',
          style: SunmiTextStyle(bold: true, align: alignCenter, fontSize: 36));
      await SunmiPrinter.lineWrap(1);

      await SunmiPrinter.printText('Nhân viên: ${data['userName']}',
          style: SunmiTextStyle(align: alignLeft));

      // Header bảng
      await SunmiPrinter.printRow(cols: [
        SunmiColumn(
            text: 'STT',
            width: 4,
            style: SunmiTextStyle(align: alignLeft, bold: true)),
        SunmiColumn(
            text: 'Tên Món',
            width: 16,
            style: SunmiTextStyle(align: alignLeft, bold: true)),
        SunmiColumn(
            text: 'SL',
            width: 12,
            style: SunmiTextStyle(align: alignRight, bold: true)),
      ]);
      await SunmiPrinter.line();

      for (var i = 0; i < items.length; i++) {
        final item = items[i];

        double quantityToPrint = item.quantity;

        if (quantityToPrint == 0) continue;

        String itemName = item.product.productName;
        if (isCancelTicket) {
          itemName = '[HỦY] $itemName';
        }

        await SunmiPrinter.printRow(cols: [
          SunmiColumn(
              text: '${i + 1}',
              width: 4,
              style: SunmiTextStyle(align: alignLeft, fontSize: 32)),
          SunmiColumn(
              text: itemName,
              width: 16,
              style: SunmiTextStyle(align: alignLeft, fontSize: 32)),
          SunmiColumn(
              text: isCancelTicket ? '-$quantityToPrint' : '$quantityToPrint',
              width: 12,
              style: SunmiTextStyle(align: alignRight, fontSize: 32)),
        ]);
        final String? note = item.note.nullIfEmpty;
        if (note != null) {
          await SunmiPrinter.printText(
            '($note)',
            style: SunmiTextStyle(align: alignLeft, fontSize: 24, bold: false),
          );
        }
        await SunmiPrinter
            .printText('--------------------------------');
      }

      if (job.type == PrintJobType.provisional) {
        await SunmiPrinter.line();
        await SunmiPrinter.printText('Tổng cộng: ${data['totalAmount']}',
            style: SunmiTextStyle(bold: true, align: alignRight));
      } else if (job.type == PrintJobType.receipt) {
        await SunmiPrinter.line();
        final total = (data['totalPayable'] ?? data['totalAmount']) ?? 0;
        await SunmiPrinter.printText('Khách phải trả: $total',
            style: SunmiTextStyle(bold: true, align: alignRight));
      }

      await SunmiPrinter.lineWrap(3);
      await SunmiPrinter.cutPaper();
      return true;
    } catch (e, st) {
      debugPrint("Lỗi Sunmi SDK: $e\n$st");
      return false;
    }
  }

  Future<bool> _printWithGenericService(PrintJob job,
      List<ConfiguredPrinter> configuredPrinters) async {
    final data = job.data;

    List<OrderItem> getItems() {
      final itemsList = (data['items'] as List?) ?? [];
      return itemsList
          .map((i) => OrderItem.fromMap(i as Map<String, dynamic>))
          .toList();
    }

    switch (job.type) {
      case PrintJobType.kitchen:
        final service = PrintingService(tableName: data['tableName'], userName: data['userName']);
        final targetRole = data['targetPrinterRole'] as String;
        final customerName = data['customerName'] as String?;
        return await service.printKitchenTicket(
          itemsToPrint: getItems(),
          targetPrinterRole: targetRole,
          configuredPrinters: configuredPrinters,
          customerName: customerName,
        );

      case PrintJobType.provisional:
        final service = PrintingService(tableName: data['tableName'], userName: data['userName']);
        return await service.printProvisionalBill(
          storeInfo: (data['storeInfo'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString())),
          items: getItems(),
          summary: data['summary'] as Map<String, dynamic>,
          showPrices: data['showPrices'] as bool,
          configuredPrinters: configuredPrinters,
          useDetailedLayout: data['useDetailedLayout'] as bool? ?? false,
        );
      case PrintJobType.detailedProvisional:
        final service = PrintingService(tableName: data['tableName'], userName: data['userName']);
        return await service.printProvisionalBill(
          storeInfo: (data['storeInfo'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString())),
          items: getItems(),
          summary: data['summary'] as Map<String, dynamic>,
          showPrices: data['showPrices'] as bool? ?? true,
          configuredPrinters: configuredPrinters,
          useDetailedLayout: true,
        );
      case PrintJobType.cancel:
        final service = PrintingService(tableName: data['tableName'], userName: data['userName']);
        final targetRole = data['targetPrinterRole'] as String;
        return await service.printCancelTicket(
          itemsToCancel: getItems(),
          targetPrinterRole: targetRole,
          configuredPrinters: configuredPrinters,
        );

      case PrintJobType.receipt:
        final service = PrintingService(tableName: data['tableName'], userName: data['userName']);
        return await service.printReceiptBill(
          storeInfo: (data['storeInfo'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
              {},
          items: getItems(),
          summary: data['summary'] as Map<String, dynamic>,
          configuredPrinters: configuredPrinters,
        );

      case PrintJobType.cashFlow:
        final txData = data['transaction'] as Map<String, dynamic>;
        final txId = data['transactionId'] as String;
        final transaction = CashFlowTransaction.fromMap(txData, txId);

        final service = PrintingService(
            tableName: "Thu/Chi",
            userName: transaction.user
        );

        return await service.printCashFlowTicket(
          storeInfo: (data['storeInfo'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
              {},
          transaction: transaction,
          openingDebt: data['openingDebt'] as double?,
          closingDebt: data['closingDebt'] as double?,
          configuredPrinters: configuredPrinters,
        );

      case PrintJobType.endOfDayReport:
        final service = PrintingService(tableName: "Báo Cáo", userName: data['userName']);

        final totalData = (data['totalReportData'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
        final shiftDataList = (data['shiftReportsData'] as List?) ?? [];

        final shiftData = shiftDataList
            .map((i) => (i as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{})
            .toList();

        return await service.printEndOfDayReport(
          storeInfo: (data['storeInfo'] as Map?)
              ?.map((k, v) => MapEntry(k.toString(), v.toString())) ??
              {},
          totalReportData: totalData,
          shiftReportsData: shiftData,
          configuredPrinters: configuredPrinters,
        );

      case PrintJobType.tableManagement:
        final service = PrintingService(tableName: "Chuyển/Gộp/Tách Bàn", userName: data['userName']);
        final prefs = await SharedPreferences.getInstance();
        final storeInfoString = prefs.getString('store_info');
        final Map<String, String> storeInfo = storeInfoString != null
            ? Map<String, String>.from(jsonDecode(storeInfoString))
            : {};

        return await service.printTableManagementNotification(
          storeInfo: storeInfo,
          actionTitle: data['actionTitle'] as String,
          message: data['message'] as String,
          userName: data['userName'] as String,
          timestamp: DateTime.parse(data['timestamp'] as String),
          configuredPrinters: configuredPrinters,
        );
    }
  }

  Future<bool> _sendJobToServerLAN(String serverIp, PrintJob job) async {
    String endpoint;
    switch (job.type) {
      case PrintJobType.kitchen:
        endpoint = '/print/kitchen';
        break;
      case PrintJobType.provisional:
        endpoint = '/print/provisional';
        break;
      case PrintJobType.detailedProvisional:
        endpoint = '/print/detailedProvisional';
        break;
      case PrintJobType.cancel:
        endpoint = '/print/cancel';
        break;
      case PrintJobType.receipt:
        endpoint = '/print/receipt';
        break;
      case PrintJobType.cashFlow:
        endpoint = '/print/cashFlow';
        break;
      case PrintJobType.endOfDayReport:
        endpoint = '/print/endOfDayReport';
        break;
      case PrintJobType.tableManagement:
        endpoint = '/print/tableManagement';
        break;
    }

    final url = Uri.parse('http://$serverIp:8080$endpoint');

    // Chuẩn hoá để tránh server cast Timestamp?
    final normalized = _normalizeJobDataForLan(job.data);

    final body = jsonEncode(normalized, toEncodable: (value) {
      if (value is Timestamp) return value.toDate().toIso8601String();
      return value;
    });


    final response = await http
        .post(
      url,
      headers: {'Content-Type': 'application/json; charset=UTF-8'},
      body: body,
    )
        .timeout(const Duration(seconds: 8));

    if (response.statusCode == 200) {
      return true;
    } else {
      throw Exception('Máy chủ LAN báo lỗi: ${response.body}');
    }
  }

  void _startListeningForCloudErrors(String storeId) {
    _cloudErrorSubscription?.cancel();
    _cloudErrorSubscription = FirebaseFirestore.instance
        .collection('print_jobs')
        .where('storeId', isEqualTo: storeId)
        .where('status', isEqualTo: 'failed')
        .snapshots()
        .listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final job = PrintJob(
          id: _uuid.v4(),
          firestoreId: doc.id,
          type: PrintJobType.values.byName(data['type']),
          data: data,
          createdAt: (data['createdAt'] as Timestamp).toDate(),
        );
        if (!failedJobsNotifier.value
            .any((j) => j.firestoreId == job.firestoreId)) {
          _addFailedJob(job);
        }
      }
    });
  }

  Future<bool> retryJob(String jobId) async {
    final idx = failedJobsNotifier.value.indexWhere((j) => j.id == jobId);
    if (idx == -1) return false;

    final job = failedJobsNotifier.value[idx];
    bool success = false;

    if (job.firestoreId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('print_jobs')
            .doc(job.firestoreId)
            .update({'status': 'pending', 'error': FieldValue.delete()});
        success = true;
      } catch (e) {
        debugPrint("Lỗi khi retry cloud job: $e");
        success = false;
      }
    } else {
      final prefs = await SharedPreferences.getInstance();
      final printMode = prefs.getString('client_print_mode') ?? 'direct';
      success =
      await _executePrintLocally(job, printMode).catchError((_) => false);
    }

    if (success) {
      _removeFailedJob(jobId);
    }
    return success;
  }

  Future<bool> retryAllJobs() async {
    final jobsToRetry = List<PrintJob>.from(failedJobsNotifier.value);
    bool allSucceeded = true;

    for (final job in jobsToRetry) {
      final ok = await retryJob(job.id);
      if (!ok) allSucceeded = false;
    }
    return allSucceeded;
  }

  Future<void> deleteJob(String jobId) async {
    final idx = failedJobsNotifier.value.indexWhere((j) => j.id == jobId);
    if (idx == -1) return;

    final job = failedJobsNotifier.value[idx];

    if (job.firestoreId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('print_jobs')
            .doc(job.firestoreId)
            .update({'status': 'archived_deleted'});
      } catch (e) {
        debugPrint("Lỗi khi xóa cloud job: $e");
      }
    }
    _removeFailedJob(jobId);
  }

  Future<void> deleteAllJobs() async {
    final jobs = List<PrintJob>.from(failedJobsNotifier.value);
    for (final j in jobs) {
      await deleteJob(j.id);
    }
  }

  void _addFailedJob(PrintJob job) async {
    final current = failedJobsNotifier.value;
    failedJobsNotifier.value = [job, ...current];

    debugPrint(
        ">>> ADD FAILED JOB: id=${job.id}, total=${failedJobsNotifier.value.length}");

    await _saveFailedJobsToPrefs();
  }

  void _removeFailedJob(String jobId) {
    final current = failedJobsNotifier.value;
    failedJobsNotifier.value =
        current.where((j) => j.id != jobId).toList();
    _saveFailedJobsToPrefs();
  }

  Future<void> _loadFailedJobsFromPrefs() async {
    debugPrint(">>> START LOAD FAILED JOBS");
    final prefs = await SharedPreferences.getInstance();
    try {
      final jsonString = prefs.getString(_localFailedQueueKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        failedJobsNotifier.value = jsonList
            .map((json) => PrintJob.fromJson(json as Map<String, dynamic>))
            .where((job) => job.firestoreId == null)
            .toList();
        debugPrint(
            ">>> LOAD FAILED JOBS: count=${failedJobsNotifier.value.length}");
      } else {
        debugPrint(">>> LOAD FAILED JOBS: không tìm thấy dữ liệu");
        failedJobsNotifier.value = [];
      }
    } catch (e) {
      debugPrint(">>> ERROR LOAD FAILED JOBS: $e");
      failedJobsNotifier.value = [];
    }
  }

  Future<void> _saveFailedJobsToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final localFailedJobs = failedJobsNotifier.value
        .where((job) => job.firestoreId == null)
        .map((job) {
      final json = job.toJson();
      json['data'] = _sanitizeJson(json['data']); // tránh Timestamp gây lỗi
      return json;
    }).toList();

    final jsonString = jsonEncode(localFailedJobs);
    final ok = await prefs.setString(_localFailedQueueKey, jsonString);
    debugPrint(
        ">>> SAVE FAILED JOBS: count=${localFailedJobs.length}, success=$ok");
  }

  dynamic _sanitizeJson(dynamic value) {
    if (value is Map) {
      return value.map((k, v) => MapEntry(k, _sanitizeJson(v)));
    } else if (value is List) {
      return value.map(_sanitizeJson).toList();
    } else if (value is Timestamp) {
      return value.toDate().toIso8601String();
    } else {
      return value;
    }
  }

  Map<String, dynamic> _normalizeJobDataForLan(Map<String, dynamic> raw) {
    dynamic toEncodable(value) {
      if (value is Timestamp) return value.toDate().toIso8601String();
      return value;
    }

    final cloned = jsonDecode(jsonEncode(raw, toEncodable: toEncodable)) as Map<String, dynamic>;

    // Đặc biệt xử lý summary.startTime để tránh server cast sang Timestamp
    final summary = cloned['summary'];
    if (summary is Map<String, dynamic>) {
      final st = summary['startTime'];
      // Lưu ra key khác để tương thích dần về sau (nếu cần)
      if (st is String) {
        summary['startTimeIso'] = st;
      } else if (st is Map || st is int) {
        // hiếm khi dùng, nhưng cứ để phòng
        summary['startTimeIso'] = st.toString();
      }
      // XÓA/GÁN NULL để server không còn cast Timestamp?
      summary['startTime'] = null;
    }

    return cloned;
  }

  void dispose() {
    _cloudErrorSubscription?.cancel();
  }
}
