// lib/bills/bill_history_screen.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../theme/app_theme.dart';
import '../theme/number_utils.dart';
import '../models/order_item_model.dart';
import '../models/user_model.dart';
import '../models/bill_model.dart';
import '../services/firestore_service.dart';
import '../services/toast_service.dart';
import '../models/print_job_model.dart';
import '../services/print_queue_service.dart';
import '../widgets/app_dropdown.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/receipt_template_model.dart';
import '../widgets/receipt_widget.dart';
import 'dart:async';
import '../models/store_settings_model.dart';
import '../services/settings_service.dart';
import '../widgets/vietqr_generator.dart';

enum TimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom
}

class BillService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<List<BillModel>> getBillsStream({
    required String storeId,
    DateTime? startDate,
    DateTime? endDate,
    String? tableName,
    String? employeeName,
    String? customerName,
    String? status,
    String? debtStatus,
  }) {
    Query query = _db
        .collection('bills')
        .where('storeId', isEqualTo: storeId)
        .orderBy('createdAt', descending: true);

    if (startDate != null) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
    }
    if (endDate != null) {
      query = query.where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endDate.add(const Duration(days: 1))));
    }
    if (tableName != null && tableName.isNotEmpty) {
      query = query.where('tableName', isEqualTo: tableName);
    }
    if (employeeName != null && employeeName.isNotEmpty) {
      query = query.where('createdByName', isEqualTo: employeeName);
    }
    if (customerName != null && customerName.isNotEmpty) {
      query = query.where('customerName', isEqualTo: customerName);
    }
    if (status != null && status.isNotEmpty) {
      final dbStatus = (status == 'Đã hủy') ? 'cancelled' : 'completed';
      query = query.where('status', isEqualTo: dbStatus);
    }
    if (debtStatus != null && debtStatus.isNotEmpty) {
      if (debtStatus == 'Có') {
        query = query.where('debtAmount', isGreaterThan: 0);
      } else if (debtStatus == 'Không') {
        query = query.where('debtAmount', isEqualTo: 0);
      }
    }

    return query.limit(100).snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => BillModel.fromFirestore(doc)).toList());
  }

  Future<Map<String, List<String>>> getDistinctFilterValues(String storeId) async {
    try {
      final snapshot = await _db.collection('bills')
          .where('storeId', isEqualTo: storeId)
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();

      if (snapshot.docs.isEmpty) {
        return {'tables': [], 'users': [], 'customers': []};
      }

      final tables = snapshot.docs.map((doc) => doc.data()['tableName'] as String?).nonNulls.toSet();
      final users = snapshot.docs.map((doc) => doc.data()['createdByName'] as String?).nonNulls.toSet();
      final customers = snapshot.docs.map((doc) => doc.data()['customerName'] as String?).nonNulls
          .where((name) => name.isNotEmpty).toSet();

      return {
        'tables': tables.toList()..sort(),
        'users': users.toList()..sort(),
        'customers': customers.toList()..sort(),
      };
    } catch (e) {
      debugPrint('Lỗi khi lấy dữ liệu bộ lọc hóa đơn: $e');
      return {'tables': [], 'users': [], 'customers': []};
    }
  }

  Future<void> cancelBillAndReverseTransactions(BillModel bill, String storeId) async {
    final writeBatch = _db.batch();

    final billRef = _db.collection('bills').doc(bill.id);
    writeBatch.update(billRef, {'status': 'cancelled'});

    if (bill.customerId != null && bill.customerId!.isNotEmpty) {
      final customerRef = _db.collection('customers').doc(bill.customerId);
      final int pointsChangeToReverse = bill.customerPointsUsed.round() - bill.pointsEarned.round();
      writeBatch.update(customerRef, {
        'points': FieldValue.increment(pointsChangeToReverse),
        'debt': FieldValue.increment(-bill.debtAmount),
        'totalSpent': FieldValue.increment(-bill.totalPayable),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    if (bill.voucherCode != null && bill.voucherCode!.isNotEmpty) {
      final voucherQuery = await _db.collection('promotions')
          .where('code', isEqualTo: bill.voucherCode)
          .where('storeId', isEqualTo: storeId)
          .limit(1).get();
      if (voucherQuery.docs.isNotEmpty) {
        final voucherRef = voucherQuery.docs.first.reference;
        writeBatch.update(voucherRef, {
          'quantity': FieldValue.increment(1),
          'usedCount': FieldValue.increment(-1),
        });
      }
    }

    final String? reportDateString = bill.reportDateKey;
    final String? shiftId = bill.shiftId;

    if (reportDateString == null || reportDateString.isEmpty) {
      throw Exception('Bill thiếu reportDateKey. Không thể hủy an toàn.');
    }
    if (shiftId == null || shiftId.isEmpty) {
      throw Exception('Bill thiếu shiftId. Không thể hủy an toàn.');
    }

    final String reportId = '${storeId}_$reportDateString';
    final dailyReportRef = _db.collection('daily_reports').doc(reportId);
    final String shiftKeyPrefix = 'shifts.$shiftId';

    double cashPaymentToReverse = 0.0;
    double otherPaymentsToReverse = 0.0;

    bill.payments.forEach((paymentMethodKey, paymentAmount) {
      final double amount = (paymentAmount as num?)?.toDouble() ?? 0.0;
      if (amount <= 0) return;
      if (paymentMethodKey == 'Tiền mặt') {
        cashPaymentToReverse += amount;
      } else {
        otherPaymentsToReverse += amount;
      }
    });

    final double totalSurchargesToReverse = bill.surcharges.fold(0.0, (tong, e) {
      if (e['isPercent'] == true) {
        return tong + (bill.subtotal * (e['amount'] ?? 0) / 100);
      }
      return tong + (e['amount'] ?? 0);
    });

    final double totalBillDiscountToReverse = (bill.discountType == 'VND')
        ? bill.discountInput
        : (bill.subtotal * bill.discountInput / 100);

    final Map<String, dynamic> dailyReportUpdates = {
      'billCount': FieldValue.increment(-1),
      'totalRevenue': FieldValue.increment(-bill.totalPayable),
      'totalProfit': FieldValue.increment(-bill.totalProfit),
      'totalDebt': FieldValue.increment(-bill.debtAmount),
      'totalTax': FieldValue.increment(-bill.taxAmount),
      'totalDiscount': FieldValue.increment(-bill.discount), // CK Món
      'totalBillDiscount': FieldValue.increment(-totalBillDiscountToReverse), // CK Tổng
      'totalVoucherDiscount': FieldValue.increment(-bill.voucherDiscount),
      'totalPointsValue': FieldValue.increment(-bill.customerPointsValue),
      'totalSurcharges': FieldValue.increment(-totalSurchargesToReverse),

      '$shiftKeyPrefix.billCount': FieldValue.increment(-1),
      '$shiftKeyPrefix.totalRevenue': FieldValue.increment(-bill.totalPayable),
      '$shiftKeyPrefix.totalProfit': FieldValue.increment(-bill.totalProfit),
      '$shiftKeyPrefix.totalDebt': FieldValue.increment(-bill.debtAmount),
      '$shiftKeyPrefix.totalTax': FieldValue.increment(-bill.taxAmount),
      '$shiftKeyPrefix.totalDiscount': FieldValue.increment(-bill.discount), // CK Món
      '$shiftKeyPrefix.totalBillDiscount': FieldValue.increment(-totalBillDiscountToReverse), // CK Tổng
      '$shiftKeyPrefix.totalVoucherDiscount': FieldValue.increment(-bill.voucherDiscount),
      '$shiftKeyPrefix.totalPointsValue': FieldValue.increment(-bill.customerPointsValue),
      '$shiftKeyPrefix.totalSurcharges': FieldValue.increment(-totalSurchargesToReverse),
    };

    for (var item in bill.items) {
      if (item is! Map<String, dynamic>) continue;
      final productId = (item['product'] as Map<String, dynamic>?)?['id'] as String?;
      if (productId == null) continue;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final itemSubtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      final itemDiscount = (item['totalDiscount'] as num?)?.toDouble() ?? 0.0;

      dailyReportUpdates['products.$productId.quantitySold'] = FieldValue.increment(-quantity);
      dailyReportUpdates['products.$productId.totalRevenue'] = FieldValue.increment(-itemSubtotal);
      dailyReportUpdates['products.$productId.totalDiscount'] = FieldValue.increment(-itemDiscount);
      dailyReportUpdates['$shiftKeyPrefix.products.$productId.quantitySold'] = FieldValue.increment(-quantity);
      dailyReportUpdates['$shiftKeyPrefix.products.$productId.totalRevenue'] = FieldValue.increment(-itemSubtotal);
      dailyReportUpdates['$shiftKeyPrefix.products.$productId.totalDiscount'] = FieldValue.increment(-itemDiscount);
    }

    if (cashPaymentToReverse > 0) {
      dailyReportUpdates['totalCash'] = FieldValue.increment(-cashPaymentToReverse);
      dailyReportUpdates['$shiftKeyPrefix.totalCash'] = FieldValue.increment(-cashPaymentToReverse);
    }
    if (otherPaymentsToReverse > 0) {
      dailyReportUpdates['totalOtherPayments'] = FieldValue.increment(-otherPaymentsToReverse);
      dailyReportUpdates['$shiftKeyPrefix.totalOtherPayments'] = FieldValue.increment(-otherPaymentsToReverse);
    }

    writeBatch.update(dailyReportRef, dailyReportUpdates);

    await writeBatch.commit();

    await _performRecursiveStockRefund(bill, storeId);
  }

  Future<void> deleteBillPermanently(String billId) async {
    if (billId.isEmpty) {
      throw ArgumentError('Bill ID không được rỗng.');
    }
    try {
      final billRef = _db.collection('bills').doc(billId);
      final doc = await billRef.get();
      if (doc.exists && doc.data()?['status'] == 'cancelled') {
        await billRef.delete();
        debugPrint('Đã xóa vĩnh viễn hóa đơn ID: $billId');
      } else if (doc.exists) {
        throw Exception('Chỉ có thể xóa hóa đơn đã bị hủy.');
      } else {
        debugPrint('Hóa đơn ID $billId không tồn tại để xóa.');
      }
    } catch (e) {
      debugPrint('Lỗi khi xóa vĩnh viễn hóa đơn $billId: $e');
      rethrow;
    }
  }

  Future<void> _getStockUpdatesForProduct(
      String productId,
      double quantityToReverse,
      Map<String, double> stockToUpdate,
      ) async {
    if (quantityToReverse <= 0) return;

    final doc = await _db.collection('products').doc(productId).get();
    if (!doc.exists) {
      debugPrint(">>> HOÀN KHO: Không tìm thấy sản phẩm $productId, bỏ qua.");
      return;
    }

    final data = doc.data() as Map<String, dynamic>;
    final productType = data['productType'] as String?;

    if (productType == 'Thành phẩm/Combo' || productType == 'Topping/Bán kèm') {

      final compiledMaterials = List<Map<String, dynamic>>.from(data['compiledMaterials'] ?? []);

      if (compiledMaterials.isNotEmpty) {
        for (final material in compiledMaterials) {
          final materialId = material['productId'] as String?;
          final materialQty = (material['quantity'] as num?)?.toDouble() ?? 0.0;
          if (materialId == null || materialQty <= 0) continue;

          final double totalMaterialToRefund = materialQty * quantityToReverse;

          stockToUpdate[materialId] = (stockToUpdate[materialId] ?? 0) + totalMaterialToRefund;
        }
      } else {

      }
    } else {
      stockToUpdate[productId] = (stockToUpdate[productId] ?? 0) + quantityToReverse;
    }
  }

  Future<void> _performRecursiveStockRefund(
      BillModel bill, String storeId) async {

    final Map<String, double> stockToUpdate = {};

    try {
      for (final item in bill.items) {
        if (item is! Map<String, dynamic>) continue;

        final productMap = (item['product'] as Map<String, dynamic>?);
        if (productMap == null) continue;

        final productId = productMap['id'] as String?;
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        if (productId == null || quantity <= 0) continue;

        await _getStockUpdatesForProduct(productId, quantity, stockToUpdate);

        final toppings = (item['toppings'] as List<dynamic>?) ?? [];
        for (final topping in toppings) {
          if (topping is! Map<String, dynamic>) continue;

          final toppingProductMap = (topping['product'] as Map<String, dynamic>?);
          if (toppingProductMap == null) continue;

          final toppingProductId = toppingProductMap['id'] as String?;
          final toppingQuantity = (topping['quantity'] as num?)?.toDouble() ?? 0.0;

          if (toppingProductId != null && toppingQuantity > 0) {
            final double totalToppingQuantity = toppingQuantity * quantity;
            await _getStockUpdatesForProduct(
              toppingProductId,
              totalToppingQuantity,
              stockToUpdate,
            );
          }
        }
      }

      if (stockToUpdate.isEmpty) {
        debugPrint(">>> HOÀN KHO: Không có 'Hàng hóa' nào để hoàn.");
        return;
      }

      final stockBatch = _db.batch();
      stockToUpdate.forEach((productId, quantity) {
        if (quantity > 0) {
          final productRef = _db.collection('products').doc(productId);
          stockBatch.update(productRef, {'stock': FieldValue.increment(quantity)});
        }
      });

      await stockBatch.commit();
      debugPrint(">>> HOÀN KHO: Đã hoàn ${stockToUpdate.length} mã hàng hóa.");

    } catch (e) {
      debugPrint("LỖI NGHIÊM TRỌNG KHI HOÀN KHO: $e");
    }
  }
}

class BillHistoryScreen extends StatefulWidget {
  final UserModel currentUser;
  const BillHistoryScreen({super.key, required this.currentUser});

  @override
  State<BillHistoryScreen> createState() => _BillHistoryScreenState();
}

class _BillHistoryScreenState extends State<BillHistoryScreen> {
  late Future<Map<String, String>?> _storeInfoFuture;
  final BillService _billService = BillService();
  TimeRange _selectedRange = TimeRange.today;
  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  String? _selectedTable;
  String? _selectedEmployee;
  String? _selectedCustomer;
  String? _selectedStatus;
  String? _selectedDebtStatus;
  Stream<List<BillModel>>? _billsStream;
  bool _isLoadingFilters = true;
  List<String> _tableOptions = [];
  List<String> _userOptions = [];
  List<String> _customerOptions = [];
  final List<String> _statusOptions = ['Tất cả', 'Hoàn thành', 'Đã hủy'];
  final List<String> _debtOptions = ['Tất cả', 'Có', 'Không'];
  StreamSubscription<StoreSettings>? _settingsSub;


  @override
  void initState() {
    super.initState();
    _storeInfoFuture = FirestoreService().getStoreDetails(widget.currentUser.storeId);

    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;

    _settingsSub = SettingsService().watchStoreSettings(settingsId).listen((settings) {
      if (!mounted) return;

      final newCutoff = TimeOfDay(
        hour: settings.reportCutoffHour ?? 0,
        minute: settings.reportCutoffMinute ?? 0,
      );

      if (newCutoff != _reportCutoffTime) {
        setState(() {
          _reportCutoffTime = newCutoff;
          _updateDateRange();
          _updateBillsStream();
        });
      }
    });

    _updateDateRange();
    _updateBillsStream();
    _loadFilterData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel(); // <--- THÊM DÒNG NÀY
    super.dispose();
  }

  void _updateDateRange() {
    if (_selectedRange == TimeRange.custom) {
      if (_selectedStartDate == null || _selectedEndDate == null) {
        _selectedRange = TimeRange.today;
      }
    }

    if (_selectedRange != TimeRange.custom) {
      final now = DateTime.now();
      final cutoff = _reportCutoffTime;

      DateTime startOfReportDay(DateTime date) {
        return DateTime(date.year, date.month, date.day, cutoff.hour, cutoff.minute);
      }

      DateTime endOfReportDay(DateTime date) {
        return startOfReportDay(date)
            .add(const Duration(days: 1))
            .subtract(const Duration(milliseconds: 1));
      }

      DateTime todayCutoffTime = startOfReportDay(now);
      DateTime effectiveDate = now;
      if (now.isBefore(todayCutoffTime)) {
        effectiveDate = now.subtract(const Duration(days: 1));
      }

      switch (_selectedRange) {
        case TimeRange.today:
          _selectedStartDate = startOfReportDay(effectiveDate);
          _selectedEndDate = endOfReportDay(effectiveDate);
          break;
        case TimeRange.yesterday:
          final yesterday = effectiveDate.subtract(const Duration(days: 1));
          _selectedStartDate = startOfReportDay(yesterday);
          _selectedEndDate = endOfReportDay(yesterday);
          break;
        case TimeRange.thisWeek:
          final startOfWeek = effectiveDate.subtract(Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _selectedStartDate = startOfReportDay(startOfWeek);
          _selectedEndDate = endOfReportDay(endOfWeek);
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay = effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay = endOfLastWeekDay.subtract(const Duration(days: 6));
          _selectedStartDate = startOfReportDay(startOfLastWeekDay);
          _selectedEndDate = endOfReportDay(endOfLastWeekDay);
          break;
        case TimeRange.thisMonth:
          final startOfMonth = DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _selectedStartDate = startOfReportDay(startOfMonth);
          _selectedEndDate = endOfReportDay(endOfMonth);
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth = DateTime(effectiveDate.year, effectiveDate.month, 0);
          final startOfLastMonth = DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
          _selectedStartDate = startOfReportDay(startOfLastMonth);
          _selectedEndDate = endOfReportDay(endOfLastMonth);
          break;
        case TimeRange.custom:
          break;
      }
    }
  }

  String _getTimeRangeText(TimeRange range) {
    switch (range) {
      case TimeRange.custom: return 'Tùy chọn...';
      case TimeRange.today: return 'Hôm nay';
      case TimeRange.yesterday: return 'Hôm qua';
      case TimeRange.thisWeek: return 'Tuần này';
      case TimeRange.lastWeek: return 'Tuần trước';
      case TimeRange.thisMonth: return 'Tháng này';
      case TimeRange.lastMonth: return 'Tháng trước';
    }
  }

  Future<List<DateTime>?> _selectCustomDateTimeRange(DateTime? initialStart, DateTime? initialEnd) async {
    return await showOmniDateTimeRangePicker(
      context: context,
      startInitialDate: initialStart ?? DateTime.now(),
      endInitialDate: initialEnd,
      startFirstDate: DateTime(2020),
      startLastDate: DateTime.now().add(const Duration(days: 365)),
      endFirstDate: initialStart ?? DateTime(2020),
      endLastDate: DateTime.now().add(const Duration(days: 365)),
      is24HourMode: true,
      isShowSeconds: false,
      type: OmniDateTimePickerType.dateAndTime,
    );
  }

  void _updateBillsStream() {
    _billsStream = _billService.getBillsStream(
      storeId: widget.currentUser.storeId,
      startDate: _selectedStartDate,
      endDate: _selectedEndDate,
      tableName: _selectedTable,
      employeeName: _selectedEmployee,
      customerName: _selectedCustomer,
      status: _selectedStatus,
      debtStatus: _selectedDebtStatus,
    );
  }

  Future<void> _loadFilterData() async {
    try {
      final filterData = await _billService.getDistinctFilterValues(widget.currentUser.storeId);
      if (mounted) {
        setState(() {
          _tableOptions = ['Tất cả', ...filterData['tables']!];
          _userOptions = ['Tất cả', ...filterData['users']!];
          _customerOptions = ['Tất cả', ...filterData['customers']!];
          _isLoadingFilters = false;
        });
      }
    } catch (e) {
      debugPrint("Lỗi khi tải dữ liệu bộ lọc: $e");
      if (mounted) {
        setState(() => _isLoadingFilters = false);
        ToastService().show(message: 'Không thể tải các tùy chọn bộ lọc.', type: ToastType.error);
      }
    }
  }

  void _showFilterModal() {
    // Lưu trạng thái tạm thời
    TimeRange tempSelectedRange = _selectedRange; // <--- Dùng biến này
    DateTime? tempStartDate = _selectedStartDate;
    DateTime? tempEndDate = _selectedEndDate;

    // Các biến khác giữ nguyên
    String? tempTable = _selectedTable;
    String? tempEmployee = _selectedEmployee;
    String? tempCustomer = _selectedCustomer;
    String? tempStatus = _selectedStatus;
    String? tempDebtStatus = _selectedDebtStatus;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Hóa Đơn', style: Theme.of(context).textTheme.headlineMedium),

                  // === THAY THẾ LISTTILE CŨ BẰNG DROPDOWN MỚI ===
                  AppDropdown<TimeRange>(
                    labelText: 'Khoảng thời gian',
                    prefixIcon: Icons.calendar_today,
                    value: tempSelectedRange,
                    items: TimeRange.values.map((range) {
                      return DropdownMenuItem<TimeRange>(
                        value: range,
                        child: Text(_getTimeRangeText(range)),
                      );
                    }).toList(),
                    onChanged: (TimeRange? newValue) {
                      if (newValue == TimeRange.custom) {
                        _selectCustomDateTimeRange(tempStartDate, tempEndDate).then((pickedRange) {
                          if (pickedRange != null && pickedRange.length == 2) {
                            setModalState(() {
                              tempStartDate = pickedRange[0];
                              tempEndDate = pickedRange[1];
                              tempSelectedRange = TimeRange.custom;
                            });
                          }
                        });
                      } else if (newValue != null) {
                        setModalState(() {
                          tempSelectedRange = newValue;
                        });
                      }
                    },
                    selectedItemBuilder: (context) {
                      return TimeRange.values.map((range) {
                        if (range == TimeRange.custom &&
                            tempSelectedRange == TimeRange.custom &&
                            tempStartDate != null &&
                            tempEndDate != null) {
                          final start = DateFormat('dd/MM/yy').format(tempStartDate!);
                          final end = DateFormat('dd/MM/yy').format(tempEndDate!);
                          return Text('$start - $end', overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getTimeRangeText(range));
                      }).toList();
                    },
                  ),
                  // ===============================================

                  // Các dropdown khác giữ nguyên
                  Row(children: [
                    Expanded(child: AppDropdown<String>(
                      labelText: 'Trạng thái', value: tempStatus,
                      items: _statusOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                      onChanged: (value) => setModalState(() => tempStatus = (value == 'Tất cả') ? null : value),
                    )),
                    const SizedBox(width: 16),
                    Expanded(child: AppDropdown<String>(
                      labelText: 'Dư nợ', value: tempDebtStatus,
                      items: _debtOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                      onChanged: (value) => setModalState(() => tempDebtStatus = (value == 'Tất cả') ? null : value),
                    )),
                  ]),
                  // ... (Giữ nguyên các AppDropdown Table, Employee, Customer) ...
                  AppDropdown<String>(
                    labelText: 'Tên bàn', value: tempTable,
                    items: _tableOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempTable = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Nhân viên', value: tempEmployee,
                    items: _userOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempEmployee = (value == 'Tất cả') ? null : value),
                  ),
                  AppDropdown<String>(
                    labelText: 'Khách hàng', value: tempCustomer,
                    items: _customerOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempCustomer = (value == 'Tất cả') ? null : value),
                  ),

                  // Nút hành động
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            // --- SỬA NÚT XÓA: Reset về Hôm nay ---
                            _selectedRange = TimeRange.today;
                            _updateDateRange(); // Tính lại ngày

                            _selectedTable = null;
                            _selectedEmployee = null; _selectedCustomer = null; _selectedStatus = null;
                            _selectedDebtStatus = null;

                            _updateBillsStream();
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Xóa bộ lọc'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            // --- SỬA NÚT ÁP DỤNG: Cập nhật Range ---
                            _selectedRange = tempSelectedRange;

                            // Nếu là custom thì lấy ngày từ modal, ngược lại thì tính toán tự động
                            if (_selectedRange == TimeRange.custom) {
                              _selectedStartDate = tempStartDate;
                              _selectedEndDate = tempEndDate;
                            } else {
                              // Tính toán lại ngày dựa trên Range vừa chọn (Hôm qua, Tuần này...)
                              _updateDateRange();
                            }

                            _selectedTable = tempTable; _selectedEmployee = tempEmployee;
                            _selectedCustomer = tempCustomer; _selectedStatus = tempStatus;
                            _selectedDebtStatus = tempDebtStatus;

                            _updateBillsStream();
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Áp dụng'),
                      ),
                    ],
                  )
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Danh sách đơn hàng"),
        actions: [
          IconButton(
            icon: _isLoadingFilters
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.filter_list, color: AppTheme.primaryColor, size: 30),
            tooltip: 'Lọc',
            onPressed: _isLoadingFilters ? null : _showFilterModal,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: FutureBuilder<Map<String, String>?>(
        future: _storeInfoFuture,
        builder: (context, storeSnapshot) {
          if (storeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (storeSnapshot.hasError || storeSnapshot.data == null) {
            return const Center(child: Text("Lỗi: Không thể tải thông tin cửa hàng."));
          }
          final storeInfo = storeSnapshot.data!;

          return StreamBuilder<List<BillModel>>(
            stream: _billsStream,
            builder: (context, billSnapshot) {
              if (billSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (billSnapshot.hasError) {
                debugPrint("LỖI FIRESTORE CẦN TẠO INDEX: ${billSnapshot.error}");
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Lỗi truy vấn Firestore:",
                          style: AppTheme.boldTextStyle.copyWith(fontSize: 18, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          "Lỗi này thường xảy ra khi thiếu chỉ mục (Index) cho bộ lọc bạn đang chọn. Hãy làm theo các bước sau:",
                        ),
                        const SizedBox(height: 12),
                        const Text("1. Kiểm tra cửa sổ Debug Console trong VS Code / Android Studio, bạn sẽ thấy một đường link."),
                        const Text("2. Click vào đường link đó để Firebase tự động tạo index."),
                        const SizedBox(height: 12),
                        const Text(
                          "Nếu không thấy link, bạn có thể sao chép toàn bộ nội dung dưới đây và dán vào trình duyệt:",
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          color: Colors.grey.shade200,
                          child: SelectableText(
                            billSnapshot.error.toString(),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (!billSnapshot.hasData || billSnapshot.data!.isEmpty) {
                return const Center(
                  child: Text('Không tìm thấy hóa đơn nào khớp với bộ lọc.', textAlign: TextAlign.center),
                );
              }
              final bills = billSnapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: bills.length,
                itemBuilder: (context, index) {
                  return _BillCard(
                    bill: bills[index],
                    currentUser: widget.currentUser,
                    storeInfo: storeInfo,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _BillCard extends StatelessWidget {
  final BillModel bill;
  final UserModel currentUser;
  final Map<String, String> storeInfo;

  const _BillCard({required this.bill, required this.currentUser, required this.storeInfo});

  void _showDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => BillReceiptDialog(bill: bill, currentUser: currentUser, storeInfo: storeInfo),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCancelled = bill.status != 'completed';
    final hasDebt = bill.debtAmount > 0;
    final bool hasEInvoice = bill.hasEInvoice;
    final Color statusColor = isCancelled ? Colors.red : (hasDebt ? Colors.orange : AppTheme.primaryColor);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 6, color: statusColor.withAlpha(180)),
              Expanded(
                child: InkWell(
                  onTap: () => _showDetail(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HÀNG 1: TÊN BÀN + GIÁ TIỀN ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1. Tên Bàn / Mã đơn (Bên trái)
                            Expanded(
                              child: Builder(builder: (context) {
                                final String safeTableName = (bill.tableName).trim();
                                final String safeCustomerName = (bill.customerName ?? '').trim();

                                bool isRetailBill = false;
                                if (safeTableName.toLowerCase().startsWith('đơn hàng') ||
                                    safeTableName.isEmpty) {
                                  isRetailBill = true;
                                }
                                if (safeTableName.isNotEmpty &&
                                    safeTableName == safeCustomerName) {
                                  isRetailBill = true;
                                }

                                final String displayTitle = isRetailBill
                                    ? bill.billCode
                                    : '$safeTableName - ${bill.billCode}';

                                return Text(
                                  displayTitle,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                );
                              }),
                            ),

                            // 2. Giá tiền (Bên phải)
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                '${formatNumber(bill.totalPayable)} đ',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontSize: 17,
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 4),

                        // --- HÀNG 2: KHÁCH HÀNG + NGÀY GIỜ (FULL WIDTH) ---
                        // Đã đưa ra ngoài Row để không bị ép cột
                        Text(
                          '${bill.customerName ?? 'Khách lẻ'} • ${DateFormat('HH:mm dd/MM/yyyy').format(bill.createdAt)}',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),

                        const SizedBox(height: 8),

                        // --- HÀNG 3: TRẠNG THÁI (FULL WIDTH) ---
                        Wrap(
                          spacing: 8.0,
                          runSpacing: 4.0,
                          children: [
                            Chip(
                              label: Text(
                                isCancelled ? "ĐÃ HỦY" : "HOÀN THÀNH",
                                style: AppTheme.boldTextStyle
                                    .copyWith(color: statusColor, fontSize: 12),
                              ),
                              backgroundColor: statusColor.withAlpha(30),
                              padding: EdgeInsets.zero,
                              visualDensity: VisualDensity.compact,
                              side: BorderSide.none,
                            ),
                            if (hasDebt)
                              Chip(
                                label: Text(
                                  "DƯ NỢ: ${formatNumber(bill.debtAmount)} đ",
                                  style: AppTheme.boldTextStyle
                                      .copyWith(color: statusColor, fontSize: 12),
                                ),
                                backgroundColor: statusColor.withAlpha(30),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              ),
                            if (hasEInvoice)
                              Chip(
                                label: Text(
                                  "ĐÃ XUẤT HĐĐT",
                                  style: AppTheme.boldTextStyle
                                      .copyWith(color: statusColor, fontSize: 12),
                                ),
                                backgroundColor: statusColor.withAlpha(30),
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                side: BorderSide.none,
                              ),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BillReceiptDialog extends StatefulWidget {
  final BillModel bill;
  final UserModel currentUser;
  final Map<String, String> storeInfo;

  const BillReceiptDialog({
    super.key,
    required this.bill,
    required this.currentUser,
    required this.storeInfo,
  });

  @override
  State<BillReceiptDialog> createState() => _BillReceiptDialogState();
}

class _BillReceiptDialogState extends State<BillReceiptDialog> {
  final ScreenshotController _screenshotController = ScreenshotController();
  ReceiptTemplateModel? _templateSettings;

  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool _canHuyBill = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.role == 'owner') {
      _canHuyBill = true;
    } else {
      _canHuyBill = widget.currentUser.permissions?['sales']?['canHuyBill'] ?? false;
    }
  }


  Map<String, dynamic> _buildSummaryMap() {
    final eInvoiceInfo = widget.bill.eInvoiceInfo;

    // 1. Xử lý hiển thị Phụ thu
    final List<Map<String, dynamic>> formattedSurcharges = widget.bill.surcharges.map((s) {
      final String name = s['name'] ?? '';
      final double amount = (s['amount'] as num?)?.toDouble() ?? 0.0;
      final bool isPercent = s['isPercent'] == true;

      if (isPercent) {
        final double calculatedAmount = widget.bill.subtotal * (amount / 100);
        return {
          'name': '$name (${formatNumber(amount)}%)',
          'amount': calculatedAmount,
          'isPercent': true,
        };
      } else {
        return {
          'name': name,
          'amount': amount,
          'isPercent': false,
        };
      }
    }).toList();

    // 2. Xử lý hiển thị Chiết khấu (Logic MỚI THÊM)
    String discountName = 'Chiết khấu';
    if (widget.bill.discountType == '%') {
      discountName = 'Chiết khấu (${formatNumber(widget.bill.discountInput)}%)';
    }

    return {
      'billCode': widget.bill.billCode,
      'subtotal': widget.bill.subtotal,

      // Các trường liên quan đến chiết khấu
      'discount': widget.bill.discount,
      'discountType': widget.bill.discountType,
      'discountInput': widget.bill.discountInput,
      'discountName': discountName, // <--- KEY MỚI ĐỂ IN TÊN KÈM %

      'surcharges': formattedSurcharges,
      'taxPercent': widget.bill.taxPercent,
      'taxAmount': widget.bill.taxAmount,
      'totalPayable': widget.bill.totalPayable,
      'startTime': Timestamp.fromDate(widget.bill.startTime),
      'createdAt': Timestamp.fromDate(widget.bill.createdAt),
      'customer': {
        'name': widget.bill.customerName,
        'phone': widget.bill.customerPhone,
        'guestAddress': widget.bill.guestAddress,
      },
      'customerPointsUsed': widget.bill.customerPointsUsed,
      'voucherCode': widget.bill.voucherCode,
      'voucherDiscount': widget.bill.voucherDiscount,
      'payments': widget.bill.payments,
      'changeAmount': widget.bill.changeAmount,
      'bankDetails': widget.bill.bankDetails,
      'eInvoiceCode': eInvoiceInfo?['reservationCode'],
      'eInvoiceUrl': (eInvoiceInfo != null) ? 'vinvoice.viettel.vn' : null,
      'eInvoiceFullUrl': eInvoiceInfo?['lookupUrl'],
      'eInvoiceMst': eInvoiceInfo?['mst'],
      'items': widget.bill.items,
    };
  }

  Future<Uint8List?> _capturePdf() async {
    try {
      // 1. Chụp ảnh Widget
      final Uint8List? imageBytes = await _screenshotController.capture(
        delay: const Duration(milliseconds: 20),
        pixelRatio: 2.5,
      );
      if (imageBytes == null) return null;

      // 2. Tạo PDF chứa ảnh
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 0),
        build: (ctx) {
          return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
        },
      ));
      return await pdf.save();
    } catch (e) {
      debugPrint("Lỗi tạo PDF từ widget: $e");
      return null;
    }
  }

  Future<void> _handleCancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận Hủy'),
          content: const Text('Bạn có chắc chắn muốn hủy hóa đơn này? Hành động này sẽ hoàn tác lại toàn bộ giao dịch và không thể khôi phục.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
            ),
            TextButton(
              child: const Text('HỦY HÓA ĐƠN', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await BillService().cancelBillAndReverseTransactions(widget.bill, widget.currentUser.storeId);
      ToastService().show(message: "Hóa đơn đã được hủy và hoàn tác", type: ToastType.success);
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint("LỖI KHI HỦY BILL: $e");
      ToastService().show(message: "Lỗi khi hủy hóa đơn: $e", type: ToastType.error);
    }
  }

  Future<void> _confirmAndDeleteBill(BuildContext context) async {
    if (widget.bill.status != 'cancelled') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xóa Hóa đơn vĩnh viễn'),
          content: const Text('Bạn có chắc chắn muốn XÓA VĨNH VIỄN hóa đơn này? Hành động này không thể khôi phục.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            TextButton(
              child: const Text('XÓA VĨNH VIỄN', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      await _performDeleteBill(context);
    }
  }

  Future<void> _performDeleteBill(BuildContext context) async {
    try {
      await BillService().deleteBillPermanently(widget.bill.id);
      if (context.mounted) {
        ToastService().show(message: 'Đã xóa vĩnh viễn hóa đơn!', type: ToastType.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      ToastService().show(message: 'Lỗi khi xóa hóa đơn: $e', type: ToastType.error);
    }
  }

  Future<void> _reprintReceipt() async {
    final jobData = {
      'storeId': widget.currentUser.storeId, 'tableName': widget.bill.tableName,
      'userName': widget.bill.createdByName ?? 'N/A', 'storeInfo': widget.storeInfo,
      'items': widget.bill.items, 'summary': _buildSummaryMap(),
    };
    await PrintQueueService().addJob(PrintJobType.receipt, jobData);
    ToastService().show(message: "Đã gửi lại lệnh in hóa đơn", type: ToastType.success);
  }

  Future<void> _shareReceipt() async {
    final bytes = await _capturePdf();
    if (bytes == null) {
      ToastService().show(message: "Lỗi tạo file chia sẻ", type: ToastType.error);
      return;
    }
    await Printing.sharePdf(bytes: bytes, filename: 'HoaDon_${widget.bill.billCode}.pdf');
  }

  Future<void> _savePdf() async {
    final bytes = await _capturePdf();
    if (bytes == null) {
      ToastService().show(message: "Lỗi tạo file PDF", type: ToastType.error);
      return;
    }
    try {
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu hóa đơn PDF', fileName: 'HoaDon_${widget.bill.billCode}.pdf',
        type: FileType.custom, allowedExtensions: ['pdf'],
      );
      if (filePath != null) {
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        ToastService().show(message: "Đã lưu hóa đơn thành công!", type: ToastType.success);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi khi lưu file: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isCancelled = widget.bill.status == 'cancelled';

    // --- 1. CHUẨN BỊ DỮ LIỆU ---
    final String safeTableName = (widget.bill.tableName).trim();
    final String safeCustomerName = (widget.bill.customerName ?? '').trim();

    // --- 2. LOGIC NHẬN DIỆN BÁN LẺ (RETAIL) ---
    bool isRetailBill = false;

    // Trường hợp A: Tên bàn mặc định của Retail ("Đơn hàng 1", "Đơn hàng...")
    if (safeTableName.toLowerCase().startsWith('đơn hàng') || safeTableName.isEmpty) {
      isRetailBill = true;
    }

    if (safeTableName.isNotEmpty && safeTableName == safeCustomerName) {
      isRetailBill = true;
    }

    String? qrDataString;
    if (widget.bill.bankDetails != null && widget.bill.totalPayable > 0) {
      final bank = widget.bill.bankDetails!;
      qrDataString = VietQrGenerator.generate(
        bankBin: bank['bankBin'] ?? '',
        bankAccount: bank['bankAccount'] ?? '',
        amount: widget.bill.totalPayable.toInt().toString(),
        description: "TT ${widget.bill.billCode}",
      );
    }

    final Widget receiptWidget = ReceiptWidget(
      title: 'HÓA ĐƠN',
      storeInfo: widget.storeInfo,
      items: widget.bill.items.whereType<Map<String, dynamic>>()
          .map((itemData) => OrderItem.fromMap(itemData)).toList(),
      summary: _buildSummaryMap(),
      userName: widget.bill.createdByName ?? 'N/A',

      tableName: isRetailBill ? '' : widget.bill.tableName,

      showPrices: true,
      isSimplifiedMode: false,
      templateSettings: _templateSettings,
      qrData: qrDataString,
    );

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 350,
          maxHeight: screenHeight * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias, // Bo góc mượt mà
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12.0)),
                child: Screenshot(
                  controller: _screenshotController,
                  child: SingleChildScrollView(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 20),

                      // --- SỬA Ở ĐÂY: THU NHỎ GIAO DIỆN ---
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown, // Tự động thu nhỏ nếu quá to
                          child: SizedBox(
                            width: 550, // Ép chiều rộng chuẩn của Bill để layout không bị vỡ
                            child: receiptWidget,
                          ),
                        ),
                      ),
                      // -------------------------------------

                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 350, // Đồng bộ width với Dialog
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12.0)),
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  if (isCancelled)
                    TextButton(
                      onPressed: () => _confirmAndDeleteBill(context),
                      child: const Text("Xóa bill", style: TextStyle(color: Colors.red)),
                    )
                  else
                    if (_canHuyBill)
                    TextButton(
                      onPressed: () => _handleCancel(context),
                      child: const Text("Hủy", style: TextStyle(color: Colors.red)),
                    ),
                  TextButton(
                    onPressed: _reprintReceipt,
                    child: const Text("In"),
                  ),
                  TextButton(
                    onPressed: _isDesktop ? _savePdf : _shareReceipt,
                    child: Text(_isDesktop ? "Lưu" : "Chia sẻ"),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Đóng"),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}