// File: lib/screens/reports/tabs/cash_flow_report_tab.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';

import '../../../models/bill_model.dart';
import '../../../models/cash_flow_transaction_model.dart';
import '../../../models/purchase_order_model.dart';
import '../../../models/user_model.dart';
import '../../../services/toast_service.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/number_utils.dart';
import '../../../widgets/app_dropdown.dart';
import 'package:app_4cash/services/firestore_service.dart';
import '../../../widgets/cash_flow_receipt_dialog.dart';
import 'dart:async';
import '../../../services/settings_service.dart';
import '../../../models/store_settings_model.dart';
import '../../../bills/bill_history_screen.dart';

class UnifiedTransaction {
  final String id;
  final TransactionType type;
  final TransactionSource source;
  final DateTime date;
  final String code;
  final double amount;
  final String description;
  final String user;
  final String? partnerName;
  final String? note;
  final String status;
  final String? cancelledBy;

  UnifiedTransaction({
    required this.id,
    required this.type,
    required this.source,
    required this.date,
    required this.code,
    required this.amount,
    required this.description,
    required this.user,
    this.partnerName,
    this.note,
    required this.status,
    this.cancelledBy,
  });
}

enum TimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom
}

class CashFlowReportTab extends StatefulWidget {
  final UserModel currentUser;
  const CashFlowReportTab({super.key, required this.currentUser});

  @override
  CashFlowReportTabState createState() => CashFlowReportTabState();
}

class CashFlowReportTabState extends State<CashFlowReportTab> {
  final List<UnifiedTransaction> _allTransactions = [];
  List<UnifiedTransaction> _filteredTransactions = [];

  double _totalRevenue = 0;
  double _totalExpense = 0;
  double get _closingBalance => _totalRevenue - _totalExpense;

  TimeRange _selectedRange = TimeRange.today;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;

  TransactionType _filterType = TransactionType.all;
  String? _filterPartner;
  String? _filterEmployee;
  String? _filterReason;

  bool isLoadingFilterOptions = false;
  List<String> _partnerOptions = ['Tất cả'];
  List<String> _employeeOptions = ['Tất cả'];
  List<String> _reasonOptions = ['Tất cả'];
  late Future<Map<String, String>?> _storeInfoFuture;
  Map<String, String>? _storeInfo;

  void refreshData() {
    _fetchAllTransactions();
  }

  @override
  void initState() {
    super.initState();
    _storeInfoFuture = FirestoreService().getStoreDetails(widget.currentUser.storeId);
    _loadSettingsAndFetchData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetchData() async {
    final settingsService = SettingsService();
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    bool isFirstLoad = true; // Cờ để chỉ fetch dữ liệu lần đầu

    _settingsSub = settingsService.watchStoreSettings(settingsId).listen((settings) {
      if (!mounted) return;

      final newCutoff = TimeOfDay(
        hour: settings.reportCutoffHour ?? 0,
        minute: settings.reportCutoffMinute ?? 0,
      );

      final bool cutoffChanged = newCutoff.hour != _reportCutoffTime.hour ||
          newCutoff.minute != _reportCutoffTime.minute;

      setState(() {
        _reportCutoffTime = newCutoff;
      });

      // Nếu là lần đầu tiên listener này chạy, HOẶC giờ chốt thay đổi
      if (isFirstLoad || cutoffChanged) {
        _updateDateRangeAndFetch();
        isFirstLoad = false; // Bỏ cờ
      }
    }, onError: (e) {
      // Nếu stream lỗi, dừng spinner và báo lỗi
      debugPrint("Lỗi watchStoreSettings: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        ToastService().show(
          message: "Lỗi tải cài đặt chốt báo cáo: $e",
          type: ToastType.error,
        );
      }
    });
  }

  void _updateDateRangeAndFetch() {
    if (_selectedRange == TimeRange.custom) {
      // Dải tùy chọn được xử lý riêng
      // Đảm bảo _startDate và _endDate không null khi là custom
      if (_startDate == null || _endDate == null) {
        // Mặc định về hôm nay nếu chưa chọn
        _selectedRange = TimeRange.today;
      }
    }

    // Luôn tính toán lại dải ngày nếu không phải là custom
    if (_selectedRange != TimeRange.custom) {
      final now = DateTime.now();
      final cutoff = _reportCutoffTime;

      DateTime startOfReportDay(DateTime date) {
        return DateTime(date.year, date.month, date.day, cutoff.hour, cutoff.minute);
      }

      DateTime endOfReportDay(DateTime date) {
        // Khớp với logic file gốc (23:59:59)
        return startOfReportDay(date).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
      }

      DateTime todayCutoffTime = startOfReportDay(now);
      DateTime effectiveDate = now;
      if (now.isBefore(todayCutoffTime)) {
        effectiveDate = now.subtract(const Duration(days: 1));
      }

      switch (_selectedRange) {
        case TimeRange.custom:
          break;
        case TimeRange.today:
          _startDate = startOfReportDay(effectiveDate);
          _endDate = endOfReportDay(effectiveDate);
          break;
        case TimeRange.yesterday:
          final yesterday = effectiveDate.subtract(const Duration(days: 1));
          _startDate = startOfReportDay(yesterday);
          _endDate = endOfReportDay(yesterday);
          break;
        case TimeRange.thisWeek:
          final startOfWeek = effectiveDate.subtract(Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _startDate = startOfReportDay(startOfWeek);
          _endDate = endOfReportDay(endOfWeek);
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay = effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay = endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          break;
        case TimeRange.thisMonth:
          _startDate = DateTime(effectiveDate.year, effectiveDate.month, 1, cutoff.hour, cutoff.minute);
          final startOfNextMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 1, cutoff.hour, cutoff.minute);
          _endDate = startOfNextMonth.subtract(const Duration(seconds: 1));
          break;
        case TimeRange.lastMonth:
          final startOfThisMonth = DateTime(effectiveDate.year, effectiveDate.month, 1, cutoff.hour, cutoff.minute);
          _endDate = startOfThisMonth.subtract(const Duration(seconds: 1));
          final startOfLastMonthDate = DateTime(effectiveDate.year, effectiveDate.month - 1, 1);
          _startDate = DateTime(startOfLastMonthDate.year, startOfLastMonthDate.month, 1, cutoff.hour, cutoff.minute);
          break;
      }
    }

    if (_startDate != null && _endDate != null) {
      _fetchAllTransactions();
    }
  }


  Future<void> _fetchAllTransactions() async {
    if (_startDate == null || _endDate == null) return;
    setState(() {
      _isLoading = true;
    });

    _loadFilterOptions();

    try {
      final storeId = widget.currentUser.storeId;
      final db = FirebaseFirestore.instance;

      final billsQuery = db
          .collection('bills')
          .where('storeId', isEqualTo: storeId)
          .where('status', whereIn: ['completed', 'return'])
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .orderBy('createdAt')
          .get();

      final poQuery = db
          .collection('purchase_orders')
          .where('storeId', isEqualTo: storeId)
          .where('status', whereIn: ['Hoàn thành', 'Nợ'])
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .orderBy('createdAt')
          .get();

      final manualQuery = db
          .collection('manual_cash_transactions')
          .where('storeId', isEqualTo: storeId)
          .where('date', isGreaterThanOrEqualTo: _startDate)
          .where('date', isLessThanOrEqualTo: _endDate)
          .orderBy('date')
          .get();

      // Chỉ await các query dữ liệu chính
      final queryResults = await Future.wait([billsQuery, poQuery, manualQuery]);

      // Xử lý dữ liệu chính
      _processTransactions(
          queryResults[0].docs,
          queryResults[1].docs,
          queryResults[2].docs
      );

    } catch (e) {
      debugPrint("================ LỖI FIRESTORE (LINK INDEX Ở DƯỚI) ================");
      debugPrint(e.toString());
      debugPrint("==================================================================");

      if (mounted) {
        ToastService().show(
          message: 'LỖI INDEX: $e. Hãy kiểm tra DEBUG CONSOLE để lấy link tạo Index!',
          type: ToastType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _processTransactions(
      List<QueryDocumentSnapshot> billDocs,
      List<QueryDocumentSnapshot> poDocs,
      List<QueryDocumentSnapshot> manualDocs,
      ) {
    _allTransactions.clear();
    double totalRev = 0;
    double totalExp = 0;

    for (final doc in billDocs) {
      final bill = BillModel.fromFirestore(doc);
      final double actualCashAmount = bill.totalPayable - bill.debtAmount;
      if (actualCashAmount.abs() < 0.001) continue;
      final String codeUpper = bill.billCode.trim().toUpperCase();

      // 1. BILL TRẢ HÀNG (Mã bắt đầu bằng RT) -> CHI
      if (codeUpper.startsWith('RT')) {
        _allTransactions.add(UnifiedTransaction(
          id: bill.id,
          type: TransactionType.expense,
          source: TransactionSource.bill,
          date: bill.createdAt,
          code: bill.billCode,
          amount: actualCashAmount, // Số dương
          description: 'Hoàn tiền trả hàng',
          user: bill.createdByName ?? 'N/A',
          partnerName: bill.customerName ?? 'Khách lẻ',
          status: 'completed',
          cancelledBy: null,
        ));
        totalExp += actualCashAmount;
      }

      // 2. BILL BÁN HÀNG (Mã KHÔNG phải RT, và không bị Hủy) -> THU
      else if (bill.status != 'cancelled') {
        _allTransactions.add(UnifiedTransaction(
          id: bill.id,
          type: TransactionType.revenue,
          source: TransactionSource.bill,
          date: bill.createdAt,
          code: bill.billCode,
          amount: actualCashAmount,
          description: 'Thu tiền bán hàng',
          user: bill.createdByName ?? 'N/A',
          partnerName: bill.customerName ?? 'Khách lẻ',
          note: null,
          status: bill.status,
          cancelledBy: null,
        ));
        totalRev += actualCashAmount;
      }
    }

    for (final doc in poDocs) {
      final po = PurchaseOrderModel.fromFirestore(doc);
      if (po.paidAmount > 0) {
        _allTransactions.add(UnifiedTransaction(
            id: po.id, type: TransactionType.expense, source: TransactionSource.purchaseOrder,
            date: po.createdAt, code: po.code, amount: po.paidAmount,
            description: 'Chi tiền nhập hàng', user: po.createdBy, partnerName: po.supplierName,
            note: null, status: 'completed', cancelledBy: null
        ));
        totalExp += po.paidAmount;
      }
    }

    for (final doc in manualDocs) {
      final manual = CashFlowTransaction.fromFirestore(doc);
      _allTransactions.add(UnifiedTransaction(
          id: manual.id, type: manual.type, source: TransactionSource.manual,
          date: manual.date, code: manual.id, amount: manual.amount,
          description: manual.reason, user: manual.user,
          partnerName: manual.type == TransactionType.revenue ? manual.customerName : manual.supplierName,
          note: manual.note, status: manual.status, cancelledBy: manual.cancelledBy
      ));
      if (manual.status == 'completed') {
        if (manual.type == TransactionType.revenue) {totalRev += manual.amount;}
        else {totalExp += manual.amount;}
      }
    }

    _allTransactions.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _totalRevenue = totalRev;
      _totalExpense = totalExp;
      _applyFilters(); // Quan trọng: Phải gọi lại cái này để cập nhật list hiển thị
    });
  }

  void _applyFilters() {
    _filteredTransactions = _allTransactions.where((transaction) {
      if (_filterType != TransactionType.all && transaction.type != _filterType) {
        return false;
      }
      if (_filterPartner != null && transaction.partnerName != _filterPartner) {
        if (transaction.partnerName == null || transaction.partnerName == 'Khách lẻ') return false;
        if (_filterPartner == 'Khách lẻ' && transaction.partnerName != null && transaction.partnerName != 'Khách lẻ') return false;
        if (_filterPartner != 'Khách lẻ' && transaction.partnerName != _filterPartner) return false;
      }
      if (_filterEmployee != null && transaction.user != _filterEmployee) {
        return false;
      }
      if (_filterReason != null && transaction.description != _filterReason) {
        return false;
      }
      return true;
    }).toList();

    if(mounted) setState(() {});
  }

  Future<void> _loadFilterOptions() async {
    if (isLoadingFilterOptions) return;

    setState(() => isLoadingFilterOptions = true);

    try {
      final storeId = widget.currentUser.storeId;
      final db = FirebaseFirestore.instance;

      final customerFuture = db.collection('customers')
          .where('storeId', isEqualTo: storeId)
          .get();
      final supplierFuture = db.collection('suppliers')
          .where('storeId', isEqualTo: storeId)
          .get();
      final employeeFuture = db.collection('users')
          .where('storeId', isEqualTo: storeId)
          .get();
      final reasonFuture = db.collection('cash_flow_reasons')
          .where('storeId', isEqualTo: storeId)
          .get();

      // Đợi tất cả hoàn thành
      final results = await Future.wait([
        customerFuture,
        supplierFuture,
        employeeFuture,
        reasonFuture,
      ]);

      // Xử lý kết quả (trong try để bắt lỗi)
      final customerDocs = results[0].docs;
      final supplierDocs = results[1].docs;
      final employeeDocs = results[2].docs;
      final reasonDocs = results[3].docs;

      final partners = <String>{'Khách lẻ'};
      partners.addAll(customerDocs.map((doc) => doc.data()['name'] as String? ?? '').where((n) => n.isNotEmpty));
      partners.addAll(supplierDocs.map((doc) => doc.data()['name'] as String? ?? '').where((n) => n.isNotEmpty));

      final employees = <String>{};
      employees.addAll(employeeDocs.map((doc) => doc.data()['name'] as String? ?? '').where((n) => n.isNotEmpty));

      final reasons = <String>{
        'Thu tiền bán hàng',
        'Chi tiền nhập hàng',
        'Thu nợ bán hàng',
        'Trả nợ nhập hàng',
      };
      reasons.addAll(reasonDocs.map((doc) => doc.data()['name'] as String? ?? '').where((n) => n.isNotEmpty));

      final sortedPartners = partners.toList()..sort();
      _partnerOptions = ['Tất cả', ...sortedPartners];

      final sortedEmployees = employees.toList()..sort();
      _employeeOptions = ['Tất cả', ...sortedEmployees];

      final sortedReasons = reasons.toList()..sort();
      _reasonOptions = ['Tất cả', ...sortedReasons];

    } catch (e) {
      debugPrint("Lỗi tải tùy chọn bộ lọc: $e");
      if (mounted) {
        ToastService().show(message: "Lỗi tải tùy chọn lọc: $e", type: ToastType.error);
      }
      _partnerOptions = ['Tất cả'];
      _employeeOptions = ['Tất cả'];
      _reasonOptions = ['Tất cả'];
    } finally {
      if (mounted) {
        setState(() => isLoadingFilterOptions = false);
      }
    }
  }

  String _getItemText(TimeRange range) {
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

  void showFilterModal() {
    // Lưu trạng thái tạm thời
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;

    TransactionType tempFilterType = _filterType;
    String? tempFilterPartner = _filterPartner;
    String? tempFilterEmployee = _filterEmployee;
    String? tempFilterReason = _filterReason;

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
                  Text('Lọc Phiếu Thu Chi', style: Theme.of(context).textTheme.headlineMedium),

                  // --- BỘ LỌC THỜI GIAN (ĐÃ CHUYỂN VÀO ĐÂY) ---
                  AppDropdown<TimeRange>(
                    labelText: 'Khoảng thời gian',
                    prefixIcon: Icons.calendar_today,
                    value: tempSelectedRange,
                    items: TimeRange.values.map((range) {
                      return DropdownMenuItem<TimeRange>(
                        value: range,
                        child: Text(_getItemText(range)),
                      );
                    }).toList(),
                    onChanged: (TimeRange? newValue) {
                      if (newValue == TimeRange.custom) {
                        // Gọi chọn ngày tùy chọn
                        showOmniDateTimeRangePicker(
                          context: context,
                          startInitialDate: tempStartDate ?? DateTime.now(),
                          endInitialDate: tempEndDate,
                          startFirstDate: DateTime(2020),
                          startLastDate: DateTime.now().add(const Duration(days: 365)),
                          endFirstDate: tempStartDate ?? DateTime(2020),
                          endLastDate: DateTime.now().add(const Duration(days: 365)),
                          is24HourMode: true,
                          isShowSeconds: false,
                          type: OmniDateTimePickerType.dateAndTime,
                        ).then((pickedRange) {
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
                        if (range == TimeRange.custom && tempSelectedRange == TimeRange.custom && tempStartDate != null && tempEndDate != null) {
                          final start = DateFormat('dd/MM/yy HH:mm').format(tempStartDate!);
                          final end = DateFormat('dd/MM/yy HH:mm').format(tempEndDate!);
                          return Text('$start - $end', overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getItemText(range));
                      }).toList();
                    },
                  ),
                  // --- KẾT THÚC BỘ LỌC THỜI GIAN ---

                  AppDropdown<TransactionType>(
                    labelText: 'Loại Phiếu',
                    value: tempFilterType,
                    items: const [
                      DropdownMenuItem(value: TransactionType.all, child: Text('Tất cả')),
                      DropdownMenuItem(value: TransactionType.revenue, child: Text('Phiếu Thu')),
                      DropdownMenuItem(value: TransactionType.expense, child: Text('Phiếu Chi')),
                    ],
                    onChanged: (value) => setModalState(() => tempFilterType = value ?? TransactionType.all),
                  ),

                  // Lọc theo Người nộp/nhận
                  AppDropdown<String>(
                    labelText: 'Người nộp/nhận',
                    value: tempFilterPartner,
                    items: _partnerOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempFilterPartner = (value == 'Tất cả') ? null : value),
                  ),

                  // Lọc theo Nhân viên
                  AppDropdown<String>(
                    labelText: 'Nhân viên thực hiện',
                    value: tempFilterEmployee,
                    items: _employeeOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempFilterEmployee = (value == 'Tất cả') ? null : value),
                  ),

                  // Lọc theo Nội dung
                  AppDropdown<String>(
                    labelText: 'Nội dung',
                    value: tempFilterReason,
                    items: _reasonOptions.map((item) => DropdownMenuItem(value: item, child: Text(item))).toList(),
                    onChanged: (value) => setModalState(() => tempFilterReason = (value == 'Tất cả') ? null : value),
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          // Xóa bộ lọc (trừ thời gian, reset về Hôm nay)
                          setState(() {
                            _filterType = TransactionType.all;
                            _filterPartner = null;
                            _filterEmployee = null;
                            _filterReason = null;

                            // Reset thời gian về hôm nay
                            _selectedRange = TimeRange.today;
                            _updateDateRangeAndFetch(); // Tải lại theo ngày hôm nay
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Xóa bộ lọc'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {
                          // Kiểm tra xem thời gian có thay đổi không
                          bool dateChanged = (_selectedRange != tempSelectedRange) ||
                              (_selectedRange == TimeRange.custom && (_startDate != tempStartDate || _endDate != tempEndDate));

                          setState(() {
                            // Cập nhật state chính
                            _selectedRange = tempSelectedRange;
                            _startDate = tempStartDate;
                            _endDate = tempEndDate;

                            _filterType = tempFilterType;
                            _filterPartner = tempFilterPartner;
                            _filterEmployee = tempFilterEmployee;
                            _filterReason = tempFilterReason;

                            if (dateChanged) {
                              _updateDateRangeAndFetch(); // Tải lại dữ liệu nếu ngày thay đổi
                            } else {
                              _applyFilters(); // Chỉ áp dụng lọc nếu ngày không đổi
                            }
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
      body: FutureBuilder<Map<String, String>?>(
        future: _storeInfoFuture,
        builder: (context, storeSnapshot) {
          if (storeSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (storeSnapshot.hasError || storeSnapshot.data == null) {
            return const Center(
                child: Text("Lỗi: Không thể tải thông tin cửa hàng."));
          }

          _storeInfo = storeSnapshot.data!;

          return RefreshIndicator(
            onRefresh: _fetchAllTransactions,
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        _buildSummarySection(),
                      ],
                    ),
                  ),
                ),
                // Phần danh sách cuộn
                _isLoading
                    ? const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
                    : _filteredTransactions.isEmpty
                    ? const SliverFillRemaining(
                  child: Center(
                    child: Text(
                      'Không có giao dịch nào khớp với bộ lọc.',
                      textAlign: TextAlign.center,
                      style:
                      TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                )
                    : SliverPadding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16.0),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                          (context, index) {
                        return _TransactionCard(
                          transaction: _filteredTransactions[index],
                          currentUser: widget.currentUser,
                          storeInfo: _storeInfo!,
                        );
                      },
                      childCount: _filteredTransactions.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummarySection() {
    final children = [
      _SummaryCard(
          title: 'Tổng Thu',
          amount: _totalRevenue,
          color: AppTheme.primaryColor,
          icon: Icons.arrow_downward),
      _SummaryCard(
          title: 'Tổng Chi',
          amount: _totalExpense,
          color: Colors.red,
          icon: Icons.arrow_upward),
      _SummaryCard(
          title: 'Tồn Quỹ',
          amount: _closingBalance,
          color: Colors.green,
          icon: Icons.account_balance_wallet_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const double mobileBreakpoint = 600;
        bool isMobile = constraints.maxWidth < mobileBreakpoint;

        if (isMobile) {
          final List<Widget> spacedChildren = [];
          for (int i = 0; i < children.length; i++) {
            spacedChildren.add(children[i]);
            if (i < children.length - 1) {
              spacedChildren.add(const SizedBox(height: 8.0));
            }
          }
          return Column(
            children: spacedChildren,
          );
        } else {
          return Row(
            children: children
                .map((card) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6.0),
                child: card,
              ),
            ))
                .toList(),
          );
        }
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final double amount;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.title,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title.toUpperCase(),
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700,
                        fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${formatNumber(amount)} đ',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final UnifiedTransaction transaction;
  final UserModel currentUser;
  final Map<String, String> storeInfo;

  const _TransactionCard({
    required this.transaction,
    required this.currentUser,
    required this.storeInfo,
  });

  void _showManualTxDialog(BuildContext context) async {
    if (transaction.source != TransactionSource.manual) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('manual_cash_transactions')
          .doc(transaction.id)
          .get();

      if (!doc.exists) {
        ToastService()
            .show(message: "Không tìm thấy phiếu gốc.", type: ToastType.error);
        return;
      }
      final fullTransaction = CashFlowTransaction.fromFirestore(doc);
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (_) => CashFlowReceiptDialog(
            transaction: fullTransaction,
            currentUser: currentUser,
            storeInfo: storeInfo,
          ),
        ).then((_) {
          if (context.mounted) {
            final state =
            context.findAncestorStateOfType<CashFlowReportTabState>();
            state?.refreshData();
          }
        });
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi tải chi tiết: $e", type: ToastType.error);
    }
  }

  Future<void> _showBillDetail(BuildContext context) async {
    try {
      // Hiện loading nhẹ hoặc người dùng đợi
      final doc = await FirebaseFirestore.instance
          .collection('bills')
          .doc(transaction.id) // ID của transaction chính là ID của Bill
          .get();

      if (!doc.exists) {
        ToastService().show(message: "Không tìm thấy hóa đơn gốc.", type: ToastType.error);
        return;
      }

      final bill = BillModel.fromFirestore(doc);

      if (context.mounted) {
        // Sử dụng BillReceiptDialog từ file bill_history_screen.dart
        showDialog(
          context: context,
          builder: (_) => BillReceiptDialog(
            bill: bill,
            currentUser: currentUser,
            storeInfo: storeInfo,
          ),
        );
      }
    } catch (e) {
      debugPrint("Lỗi tải hóa đơn: $e");
      ToastService().show(message: "Lỗi tải chi tiết: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final bool isCancelled = transaction.status == 'cancelled';
    final bool isRevenue = transaction.type == TransactionType.revenue;
    final bool isReturnBill = transaction.source == TransactionSource.bill && transaction.type == TransactionType.expense;

    final Color color;
    final IconData icon;

    if (isCancelled) {
      color = Colors.grey.shade600;
      icon = Icons.close;
    } else if (isReturnBill) {
      color = Colors.deepOrange;
      icon = Icons.assignment_return;
    } else {
      color = isRevenue ? AppTheme.primaryColor : Colors.red;
      icon = isRevenue ? Icons.arrow_downward : Icons.arrow_upward;
    }

    final hasNote = transaction.note != null && transaction.note!.isNotEmpty;
    final hasPartner =
        transaction.partnerName != null && transaction.partnerName!.isNotEmpty;

    final bool isManual = transaction.source == TransactionSource.manual;
    final bool isBill = transaction.source == TransactionSource.bill; // Check xem có phải Bill không

    String displayCode = transaction.code;
    if (isManual && transaction.code.contains('_')) {
      displayCode = transaction.code.split('_').last;
    }

    final String displayedUser =
    isCancelled ? (transaction.cancelledBy ?? 'Đã hủy') : transaction.user;

    final IconData userIcon =
    isCancelled ? Icons.cancel_outlined : Icons.person_outline;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: isCancelled ? 0.5 : 1.5,
      color: isCancelled ? Colors.grey.shade200 : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        // --- CẬP NHẬT SỰ KIỆN ONTAP ---
        onTap: () {
          if (isManual) {
            _showManualTxDialog(context);
          } else if (isBill) {
            _showBillDetail(context); // Gọi hàm xem bill
          }
        },
        // --------------------------------
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  color: color.withAlpha(isCancelled ? 60 : 40),
                  child: Icon(
                    icon,
                    color: color,
                    size: 20,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 12.0, right: 14.0, top: 12.0, bottom: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // --- HÀNG 1: MÃ PHIẾU / SỐ TIỀN ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                displayCode,
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isCancelled ? color : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: isCancelled
                                  ? Text(
                                'ĐÃ HỦY',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                  fontSize: 16,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                                  : Text(
                                // Logic dấu: Return hoặc Expense -> Trừ, Revenue -> Cộng
                                '${(isReturnBill || !isRevenue) ? '-' : '+'}${formatNumber(transaction.amount)} đ',
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(
                                  fontSize: 16,
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),

                        // --- HÀNG 2: TÊN KHÁCH / THỜI GIAN ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                hasPartner
                                    ? transaction.partnerName!
                                    : (isRevenue ? 'Khách lẻ' : 'N/A'),
                                style: theme.textTheme.titleMedium,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: Text(
                                DateFormat('HH:mm dd/MM/yyyy')
                                    .format(transaction.date),
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // --- HÀNG 3: NỘI DUNG / TÊN NHÂN VIÊN ---
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color:
                                  color.withAlpha(isCancelled ? 30 : 25)),
                              child: Text(
                                transaction.description,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            Padding(
                              padding:
                              const EdgeInsets.only(left: 8.0, top: 2.0),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(userIcon, size: 20, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      displayedUser,
                                      style: theme.textTheme.titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // --- HÀNG 4: GHI CHÚ (NẾU CÓ) ---
                        if (hasNote)
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(
                              'Ghi chú: ${transaction.note}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.black,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.left,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension ColorExtension on Color {
  Color darken([double amount = .1]) {
    assert(amount >= 0 && amount <= 1);
    final hsl = HSLColor.fromColor(this);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }
}