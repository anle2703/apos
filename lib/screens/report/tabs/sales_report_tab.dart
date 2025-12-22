// File: lib/screens/reports/order/sales_report_tab.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';

import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/theme/number_utils.dart';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';
import 'dart:async';
import 'package:app_4cash/services/settings_service.dart';
import 'package:app_4cash/models/store_settings_model.dart';
import 'package:app_4cash/models/bill_model.dart';

enum TimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom
}

class SalesReportTab extends StatefulWidget {
  final UserModel currentUser;
  final Function(bool) onLoadingChanged;

  const SalesReportTab({
    super.key,
    required this.currentUser,
    required this.onLoadingChanged,
  });

  @override
  State<SalesReportTab> createState() => SalesReportTabState();
}

class SalesReportTabState extends State<SalesReportTab> {
  TimeRange _selectedRange = TimeRange.today;
  bool _isLoading = true;

  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? _calendarStartDate;
  DateTime? _calendarEndDate;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;
  double _totalReturnTax = 0;
  double _totalReturnProfit = 0;
  double _totalTax = 0;
  double _totalReturnRevenue = 0;
  double _totalReturnDebt = 0;
  double _totalRevenue = 0;
  double _totalProfit = 0;
  double _totalCash = 0;
  double _otherPayments = 0;
  double _totalDebt = 0;
  int _totalOrders = 0;
  Map<String, double> _topSellingProducts = {};

  Map<String, double> _dailyRevenue = {};
  Map<String, double> _dailyProfit = {};
  Map<int, double> _hourlyRevenue = {};
  Map<int, double> _hourlyProfit = {};

  bool _isSingleDayReport = false;

  bool get isLoading => _isLoading;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetchData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetchData() async {
    final settingsService = SettingsService();
    final settingsId = widget.currentUser.storeId;

    try {
      final settings = await settingsService.watchStoreSettings(settingsId).first;
      if (!mounted) return;

      setState(() {
        _reportCutoffTime = TimeOfDay(
          hour: settings.reportCutoffHour ?? 0,
          minute: settings.reportCutoffMinute ?? 0,
        );
      });

      _updateDateRangeAndFetch();

    } catch (e) {
      debugPrint("Lỗi tải cài đặt ban đầu: $e");
      if (mounted) {
        setState(() => _isLoading = false);
        widget.onLoadingChanged(false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Lỗi tải cài đặt: $e")));
      }
    }

    _settingsSub = settingsService.watchStoreSettings(settingsId).listen((settings) {
      if (!mounted) return;
      final newCutoff = TimeOfDay(
        hour: settings.reportCutoffHour ?? 0,
        minute: settings.reportCutoffMinute ?? 0,
      );

      final bool cutoffChanged = newCutoff.hour != _reportCutoffTime.hour ||
          newCutoff.minute != _reportCutoffTime.minute;

      if (cutoffChanged) {
        setState(() {
          _reportCutoffTime = newCutoff;
        });
        _updateDateRangeAndFetch();
      }
    }, onError: (e) {
      debugPrint("Lỗi stream cài đặt: $e");
    });
  }

  void _updateDateRangeAndFetch() {
    if (_selectedRange == TimeRange.custom) {
      if (_calendarStartDate == null || _calendarEndDate == null) {
        _selectedRange = TimeRange.today;
      }
    }

    final now = DateTime.now();
    final cutoff = _reportCutoffTime;

    DateTime startOfReportDay(DateTime date) {
      final calendarDay = DateTime(date.year, date.month, date.day);
      return calendarDay.add(Duration(hours: cutoff.hour, minutes: cutoff.minute));
    }

    DateTime endOfReportDay(DateTime date) {
      return startOfReportDay(date).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    }

    DateTime todayCutoffTime = startOfReportDay(now);
    DateTime effectiveDate = now;
    if (now.isBefore(todayCutoffTime)) {
      effectiveDate = now.subtract(const Duration(days: 1));
    }
    effectiveDate = DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);


    if (_selectedRange != TimeRange.custom) {
      switch (_selectedRange) {
        case TimeRange.custom:
          break;
        case TimeRange.today:
          _startDate = startOfReportDay(effectiveDate);
          _endDate = endOfReportDay(effectiveDate);
          _calendarStartDate = effectiveDate;
          _calendarEndDate = effectiveDate;
          break;
        case TimeRange.yesterday:
          final yesterday = effectiveDate.subtract(const Duration(days: 1));
          _startDate = startOfReportDay(yesterday);
          _endDate = endOfReportDay(yesterday);
          _calendarStartDate = yesterday;
          _calendarEndDate = yesterday;
          break;
        case TimeRange.thisWeek:
          final startOfWeek = effectiveDate.subtract(Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _startDate = startOfReportDay(startOfWeek);
          _endDate = endOfReportDay(endOfWeek);
          _calendarStartDate = startOfWeek;
          _calendarEndDate = endOfWeek;
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay = effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay = endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          _calendarStartDate = startOfLastWeekDay;
          _calendarEndDate = endOfLastWeekDay;
          break;
        case TimeRange.thisMonth:
          final startOfMonth = DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          _calendarStartDate = startOfMonth;
          _calendarEndDate = endOfMonth;
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth = DateTime(effectiveDate.year, effectiveDate.month, 0);
          final startOfLastMonth = DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
          _startDate = startOfReportDay(startOfLastMonth);
          _endDate = endOfReportDay(endOfLastMonth);
          _calendarStartDate = startOfLastMonth;
          _calendarEndDate = endOfLastMonth;
          break;
      }
    } else {
      // Dành cho CUSTOM
      // _calendarStartDate và _calendarEndDate đã được gán bởi showFilterModal
      // Chỉ cần tính _startDate và _endDate
      if (_calendarStartDate != null) {
        _startDate = startOfReportDay(_calendarStartDate!);
      }
      if (_calendarEndDate != null) {
        _endDate = endOfReportDay(_calendarEndDate!);
      }
    }

    if (_startDate != null && _endDate != null) {
      _fetchAllReports();
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
    TimeRange tempSelectedRange = _selectedRange;
    // Dùng _calendarStartDate và _calendarEndDate cho picker
    DateTime? tempStartDate = _calendarStartDate;
    DateTime? tempEndDate = _calendarEndDate;

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
                  Text('Lọc Báo Cáo', style: Theme.of(context).textTheme.headlineMedium),

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
                          type: OmniDateTimePickerType.date,
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
                          final start = DateFormat('dd/MM/yyyy').format(tempStartDate!);
                          final end = DateFormat('dd/MM/yyyy').format(tempEndDate!);
                          return Text('$start - $end', overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getItemText(range));
                      }).toList();
                    },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRange = TimeRange.today;
                            _updateDateRangeAndFetch();
                          });
                          Navigator.of(ctx).pop();
                        },
                        child: const Text('Xóa bộ lọc'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () {

                          bool dateChanged = (_selectedRange != tempSelectedRange) ||
                              (_selectedRange == TimeRange.custom && (_calendarStartDate != tempStartDate || _calendarEndDate != tempEndDate));

                          setState(() {
                            _selectedRange = tempSelectedRange;
                            // Gán ngày dương lịch (00:00) cho state
                            _calendarStartDate = tempStartDate;
                            _calendarEndDate = tempEndDate;
                          });

                          if (dateChanged) {
                            _updateDateRangeAndFetch();
                          }
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

  Future<void> _fetchAllReports() async {
    // Dùng calendar dates để check null
    if (_calendarStartDate == null || _calendarEndDate == null) {
      setState(() => _isLoading = false);
      widget.onLoadingChanged(false);
      return;
    }

    setState(() { _isLoading = true; });
    widget.onLoadingChanged(true);

    // Kiểm tra 1 ngày bằng calendar dates
    _isSingleDayReport = _calendarStartDate!.isAtSameMomentAs(_calendarEndDate!);


    try {
      final firestore = FirebaseFirestore.instance;
      final storeId = widget.currentUser.storeId;
      const batchSize = 30;
      List<Future<void>> queries = [];

      // 1. (KPIs & Top Selling) Query daily_reports
      // Dùng calendar dates
      final List<String> dateStringsToFetch = _getDateStringsInRange(
          _calendarStartDate!,
          _calendarEndDate!
      );

      if (dateStringsToFetch.isEmpty) {
        _processAllReports([], []); // Sửa: Bỏ productReportDocs
        return;
      }
      final List<String> dailyReportIds = dateStringsToFetch.map((dateStr) => '${storeId}_$dateStr').toSet().toList();
      List<QueryDocumentSnapshot> mainReportDocs = [];

      for (int i = 0; i < dailyReportIds.length; i += batchSize) {
        final batchIds = dailyReportIds.sublist(i, i + batchSize > dailyReportIds.length ? dailyReportIds.length : i + batchSize);
        if (batchIds.isNotEmpty) {
          queries.add(
              firestore.collection('daily_reports')
                  .where(FieldPath.documentId, whereIn: batchIds)
                  .get()
                  .then((snapshot) => mainReportDocs.addAll(snapshot.docs))
          );
        }
      }

      // 2. (Biểu đồ giờ) Query bills NẾU là 1 ngày
      List<QueryDocumentSnapshot> billDocs = [];
      if (_isSingleDayReport) {
        // Dùng _startDate và _endDate (đã có giờ chốt sổ)
        queries.add(
            firestore.collection('bills')
                .where('storeId', isEqualTo: storeId)
                .where('status', isEqualTo: 'completed')
                .where('createdAt', isGreaterThanOrEqualTo: _startDate) // (e.g., 26/10 12:10)
                .where('createdAt', isLessThanOrEqualTo: _endDate)   // (e.g., 27/10 12:09)
                .get()
                .then((snapshot) => billDocs.addAll(snapshot.docs))
        );
      }

      // 3. Chạy tất cả
      await Future.wait(queries);

      _processAllReports(mainReportDocs, billDocs); // Sửa: Bỏ productReportDocs

    } catch (e) {
      debugPrint("Lỗi khi tải báo cáo: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi tải báo cáo: $e")));
      }
    } finally {
      if (mounted){
        setState(() { _isLoading = false; });
        widget.onLoadingChanged(false);
      }
    }
  }

  List<String> _getDateStringsInRange(DateTime startDate, DateTime endDate) {
    final List<String> dateStrings = [];
    DateTime currentDate = DateTime(startDate.year, startDate.month, startDate.day);
    final DateTime finalDate = DateTime(endDate.year, endDate.month, endDate.day);

    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    while (currentDate.isBefore(finalDate) || currentDate.isAtSameMomentAs(finalDate)) {
      dateStrings.add(formatter.format(currentDate));
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return dateStrings;
  }

  void _processAllReports(
      List<QueryDocumentSnapshot> mainReports,
      List<QueryDocumentSnapshot> billDocs
      ) {

    double totalRevenue = 0, totalProfit = 0, totalDebt = 0, totalCash = 0, otherPayments = 0;
    double totalTax = 0;
    double totalReturnRevenue = 0;
    double totalReturnTax = 0;
    double totalReturnProfit = 0;
    int totalOrders = 0;
    double totalReturnDebt = 0;
    final Map<String, double> dailyRevenue = {}, dailyProfit = {}, topSellingProducts = {};

    for (final doc in mainReports) {
      final data = doc.data() as Map<String, dynamic>;
      final dateTimestamp = data['date'] as Timestamp?;
      if (dateTimestamp == null) continue;

      final dateLocal = dateTimestamp.toDate();
      final dayKey = DateFormat('dd/MM').format(dateLocal);

      // --- [SỬA LẠI ĐOẠN NÀY] ---
      // 1. Lấy dữ liệu Gốc (Gross) từ DB
      final dailyRevGross = (data['totalRevenue'] as num?)?.toDouble() ?? 0.0;
      final dailyProfGross = (data['totalProfit'] as num?)?.toDouble() ?? 0.0;
      final dailyTaxGross = (data['totalTax'] as num?)?.toDouble() ?? 0.0;
      final dailyDebtGross = (data['totalDebt'] as num?)?.toDouble() ?? 0.0;

      // 2. Lấy dữ liệu Trả (Return) từ DB
      final dailyReturnRev = (data['totalReturnRevenue'] as num?)?.toDouble() ?? 0.0;
      final dailyReturnTax = (data['totalReturnTax'] as num?)?.toDouble() ?? 0.0;
      final dailyReturnProf = (data['totalReturnProfit'] as num?)?.toDouble() ?? 0.0;
      final dailyReturnDebt = (data['totalReturnDebt'] as num?)?.toDouble() ?? 0.0;

      // 3. Tính Net (Thuần) = Gốc - Trả
      final dailyRevNet = dailyRevGross - dailyReturnRev;
      final dailyProfNet = dailyProfGross - dailyReturnProf;
      final dailyTaxNet = dailyTaxGross - dailyReturnTax;
      final dailyDebtNet = dailyDebtGross - dailyReturnDebt;

      // 4. Cộng dồn vào biến tổng (Dùng số NET)
      totalRevenue += dailyRevNet;
      totalProfit += dailyProfNet;
      totalTax += dailyTaxNet;

      // Cộng dồn phần trả hàng riêng
      totalReturnRevenue += dailyReturnRev;
      totalReturnTax += dailyReturnTax;
      totalReturnProfit += dailyReturnProf;

      totalDebt += dailyDebtNet;       // Tổng Nợ thuần
      totalReturnDebt += dailyReturnDebt;

      // Cập nhật biểu đồ (Dùng số NET để biểu đồ chính xác)
      dailyRevenue.update(dayKey, (value) => value + dailyRevNet, ifAbsent: () => dailyRevNet);
      dailyProfit.update(dayKey, (value) => value + dailyProfNet, ifAbsent: () => dailyProfNet);
      // --------------------------

      totalOrders += (data['billCount'] as num?)?.toInt() ?? 0;
      totalCash += (data['totalCash'] as num?)?.toDouble() ?? 0.0;
      otherPayments += (data['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;

      final rootProducts = (data['products'] as Map<String, dynamic>?) ?? {};
      for (final pEntry in rootProducts.entries) {
        final pData = pEntry.value as Map<String, dynamic>;
        final productName = pData['productName'] as String?;
        final quantity = (pData['quantitySold'] as num?)?.toDouble() ?? 0.0;

        if (productName != null && quantity > 0) {
          topSellingProducts.update(productName, (value) => value + quantity, ifAbsent: () => quantity);
        }
      }
    }

    // 2. Xử lý Biểu đồ giờ (từ bills)
    final Map<int, double> hourlyRevenue = {};
    final Map<int, double> hourlyProfit = {};
    if (_isSingleDayReport) {
      for (int i = 0; i < 24; i++) {
        hourlyRevenue[i] = 0.0;
        hourlyProfit[i] = 0.0;
      }
      for (final doc in billDocs) {
        final bill = BillModel.fromFirestore(doc);
        final hour = bill.createdAt.hour;
        final revenue = bill.totalPayable;
        final profit = bill.totalProfit;

        hourlyRevenue.update(hour, (value) => value + revenue, ifAbsent: () => revenue);
        hourlyProfit.update(hour, (value) => value + profit, ifAbsent: () => profit);
      }
    }

    // 3. Xử lý Top Selling (ĐÃ BỊ XÓA VÀ GỘP VÀO BƯỚC 1)

    final sortedProducts = Map.fromEntries(topSellingProducts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)));

    setState(() {
      _totalRevenue = totalRevenue;
      _totalProfit = totalProfit;
      _totalDebt = totalDebt;
      _totalOrders = totalOrders;
      _totalCash = totalCash;
      _otherPayments = otherPayments;
      _totalTax = totalTax;
      _totalReturnTax = totalReturnTax;
      _totalReturnProfit = totalReturnProfit;
      _totalReturnRevenue = totalReturnRevenue;
      _dailyRevenue = dailyRevenue;
      _dailyProfit = dailyProfit;
      _hourlyRevenue = hourlyRevenue;
      _hourlyProfit = hourlyProfit;
      _topSellingProducts = sortedProducts;
      _totalDebt = totalDebt;
      _totalReturnDebt = totalReturnDebt;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
      onRefresh: _fetchAllReports,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildRevenueChart(),
          const SizedBox(height: 16),
          _buildKpiSection(),
          const SizedBox(height: 16),
          _buildTopSellingProducts(),
        ],
      ),
    );
  }

  Widget _buildRevenueChart() {
    final profitColor = Colors.amber.shade700;
    final revenueColor = AppTheme.primaryColor;

    Widget chartWidget;
    bool hasData = false;

    if (_isSingleDayReport) {
      // --- BIỂU ĐỒ THEO GIỜ ---
      final chartDataPoints = _hourlyRevenue.entries
          .where((e) => e.value > 0 || (_hourlyProfit[e.key] ?? 0) > 0)
          .toList();
      hasData = chartDataPoints.isNotEmpty;

      chartWidget = BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final hourKey = chartDataPoints[group.x.toInt()].key;
                final revenue = _hourlyRevenue[hourKey] ?? 0.0;
                final profit = _hourlyProfit[hourKey] ?? 0.0;
                return BarTooltipItem(
                  '$hourKey:00 - $hourKey:59\nDT: ${formatNumber(revenue)} đ\nLN: ${formatNumber(profit)} đ',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          barGroups: List.generate(chartDataPoints.length, (index) {
            final entry = chartDataPoints[index];
            final revenue = entry.value;
            final profit = _hourlyProfit[entry.key] ?? 0.0;
            return BarChartGroupData(x: index, barRods: [
              BarChartRodData(
                  toY: revenue,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  rodStackItems: [
                    BarChartRodStackItem(0, profit, profitColor),
                    BarChartRodStackItem(profit, revenue, revenueColor),
                  ]),
            ]);
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      if (value.toInt() < chartDataPoints.length) {
                        return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text('${chartDataPoints[value.toInt()].key}h'));
                      }
                      return const Text('');
                    },
                    reservedSize: 30)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      );

    } else {
      // --- BIỂU ĐỒ THEO NGÀY ---
      final chartDataPoints = _dailyRevenue.entries.toList().reversed.toList();
      hasData = chartDataPoints.isNotEmpty;

      chartWidget = BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => Colors.blueGrey,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final dayKey = chartDataPoints[group.x.toInt()].key;
                final revenue = _dailyRevenue[dayKey] ?? 0.0;
                final profit = _dailyProfit[dayKey] ?? 0.0;
                return BarTooltipItem(
                  'DT: ${formatNumber(revenue)} đ\nLN: ${formatNumber(profit)} đ',
                  const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                );
              },
            ),
          ),
          barGroups: List.generate(chartDataPoints.length, (index) {
            final entry = chartDataPoints[index];
            final revenue = entry.value;
            final profit = _dailyProfit[entry.key] ?? 0.0;
            return BarChartGroupData(x: index, barRods: [
              BarChartRodData(
                  toY: revenue,
                  width: 16,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  rodStackItems: [
                    BarChartRodStackItem(0, profit, profitColor),
                    BarChartRodStackItem(profit, revenue, revenueColor),
                  ]),
            ]);
          }),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (double value, TitleMeta meta) {
                      if (value.toInt() < chartDataPoints.length) {
                        return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: Text(chartDataPoints[value.toInt()].key));
                      }
                      return const Text('');
                    },
                    reservedSize: 30)),
            leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Biểu đồ', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 24),
            SizedBox(
              height: 250,
              child: hasData
                  ? chartWidget
                  : const Center(
                  child: Text("Không có dữ liệu cho khoảng thời gian này.")),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tổng kết', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            const double desktopBreakpoint = 1000.0;
            const double spacing = 12.0;
            final int crossAxisCount =
            constraints.maxWidth > desktopBreakpoint ? 4 : 2;

            final double cardWidth =
                (constraints.maxWidth - (spacing * (crossAxisCount - 1))) /
                    crossAxisCount;

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                _KpiCard(
                    width: cardWidth,
                    title: 'Tổng Đơn',
                    value: _totalOrders.toDouble(),
                    icon: Icons.receipt_long,
                    color: Colors.green,
                    suffix: null),
                _KpiCard(
                    width: cardWidth,
                    title: 'Trả Hàng',
                    value: _totalReturnRevenue,
                    icon: Icons.assignment_return_outlined,
                    color: Colors.orange),
                _KpiCard(
                    width: cardWidth,
                    title: 'Tiền Mặt',
                    value: _totalCash,
                    icon: Icons.money,
                    color: Colors.deepOrange),
                _KpiCard(
                    width: cardWidth,
                    title: 'Thanh Toán Khác',
                    value: _otherPayments,
                    icon: Icons.credit_card,
                    color: Colors.blue),
                _KpiCard(
                    width: cardWidth,
                    title: 'Ghi Nợ',
                    value: _totalDebt,
                    grossValue: _totalDebt + _totalReturnDebt,
                    returnValue: _totalReturnDebt,
                    icon: Icons.receipt,
                    color: Colors.purpleAccent),
                _KpiCard(
                    width: cardWidth,
                    title: 'Thuế',
                    value: _totalTax,
                    grossValue: _totalTax + _totalReturnTax,
                    returnValue: _totalReturnTax,
                    icon: Icons.calculate,
                    color: Colors.red),
                _KpiCard(
                    width: cardWidth,
                    title: 'Doanh Thu',
                    value: _totalRevenue,
                    grossValue: _totalRevenue + _totalReturnRevenue,
                    returnValue: _totalReturnRevenue,
                    icon: Icons.trending_up,
                    color: AppTheme.primaryColor),
                _KpiCard(
                    width: cardWidth,
                    title: 'Lợi Nhuận',
                    value: _totalProfit,
                    grossValue: _totalProfit + (_totalReturnProfit),
                    returnValue: _totalReturnProfit,
                    icon: Icons.monetization_on,
                    color: Colors.amber.shade700),
              ],
            );
          },
        )
      ],
    );
  }

  Widget _buildTopSellingProducts() {
    final sellingProducts =
    _topSellingProducts.entries.where((entry) => entry.value > 0).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sản phẩm bán chạy',
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        sellingProducts.isEmpty
            ? const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(child: Text("Chưa có sản phẩm nào được bán.")))
            : Card(
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16)),
          elevation: 2,
          child: Column(
            children: sellingProducts.map((entry) {
              return ListTile(
                title: Text(entry.key,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700)),
                trailing: Text('SL: ${formatNumber(entry.value)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade700)),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _KpiCard extends StatelessWidget {
  final String title;
  final double value;
  final double? grossValue;
  final double? returnValue;
  final IconData icon;
  final Color color;
  final String? suffix;
  final double width;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.width,
    required this.icon,
    required this.color,
    this.grossValue,
    this.returnValue,
    this.suffix = 'đ',
  });

  @override
  Widget build(BuildContext context) {
    final formattedNet = formatNumber(value);
    final formattedGross = grossValue != null ? formatNumber(grossValue!) : null;
    final formattedReturn = returnValue != null ? formatNumber(returnValue!) : null;

    final bool hasDetail = (returnValue != null && returnValue! > 0);

    return SizedBox(
      width: width,
      height: 85,
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // --- CỤM TIÊU ĐỀ & CHI TIẾT (GROSS/RETURN) ---
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Tiêu đề + Icon
                  Row(
                    children: [
                      Icon(icon, color: color, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          title.toUpperCase(),
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),

                  // [FIX 3] Thiết kế lại dòng Gross/Return: Nhỏ, gọn, sát tiêu đề
                  if (hasDetail)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 2),
                      child: Row(
                        children: [
                          if (formattedGross != null)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: formattedGross, style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                              ]),
                              style: const TextStyle(fontSize: 12),
                            ),

                          if (formattedGross != null && formattedReturn != null)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: " - ", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ]),
                              style: const TextStyle(fontSize: 12),
                            ),

                          if (formattedReturn != null)
                            Text.rich(
                              TextSpan(children: [
                                TextSpan(text: formattedReturn, style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                              ]),
                              style: const TextStyle(fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                ],
              ),

              // --- GIÁ TRỊ NET (DOANH THU THỰC) ---
              Align(
                alignment: Alignment.bottomLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    suffix != null ? '$formattedNet $suffix' : formattedNet,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade900,
                      fontSize: 18,
                      height: 1.0,
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