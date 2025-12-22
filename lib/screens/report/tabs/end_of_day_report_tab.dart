// lib/screens/reports/tabs/end_of_day_report_tab.dart
// (Toàn bộ tệp của bạn, với các phần được sửa đổi)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:collection/collection.dart';
import '../../../services/toast_service.dart';
import '../../../models/user_model.dart';
import '../../../services/settings_service.dart';
import '../../../models/store_settings_model.dart';
import '../../../theme/number_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dropdown.dart';
import 'package:app_4cash/services/firestore_service.dart';
import '../../../services/print_queue_service.dart';
import '../../../models/print_job_model.dart';
import '../../../widgets/end_of_day_report_widget.dart';
import 'package:screenshot/screenshot.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

enum TimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom
}

class EndOfDayReportTab extends StatefulWidget {
  final UserModel currentUser;
  final Function(bool) onLoadingChanged;

  const EndOfDayReportTab({
    super.key,
    required this.currentUser,
    required this.onLoadingChanged,
  });

  @override
  State<EndOfDayReportTab> createState() => EndOfDayReportTabState();
}

class EndOfDayReportTabState extends State<EndOfDayReportTab>
    with AutomaticKeepAliveClientMixin {
  TimeRange _selectedRange = TimeRange.today;
  bool _isLoading = true;

  DateTime? _calendarStartDate;
  DateTime? _calendarEndDate;
  DateTime? _startDate;
  DateTime? _endDate;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;

  final TextEditingController _openingBalanceController =
  TextEditingController();
  double _openingBalance = 0.0;
  final NumberFormat _numberFormat = NumberFormat.decimalPattern('vi_VN');

  int _totalOrders = 0;
  double _totalDiscount = 0;
  double _totalBillDiscount = 0;
  double _totalVoucher = 0;
  double _totalPointsValue = 0;
  double _totalTax = 0;
  double _totalSurcharges = 0;
  double _totalRevenue = 0;
  double _totalCash = 0;
  double _totalOtherPayments = 0;
  double _totalDebt = 0;
  double _actualRevenue = 0;
  double _totalOtherRevenue = 0;
  double _totalOtherExpense = 0;
  double _closingBalance = 0;
  double _totalReturnRevenue = 0;

  List<Map<String, dynamic>> _shiftDataList = [];
  Map<String, dynamic> _rootProductsSold = {};

  final Map<String, double> _shiftOpeningBalances = {};
  final Map<String, TextEditingController> _shiftBalanceControllers = {};
  String? _firstReportId;

  final Set<String> _rootReportFields = {
    'billCount',
    'totalRevenue',
    'totalProfit',
    'totalDebt',
    'totalDiscount',
    'totalBillDiscount',
    'totalVoucherDiscount',
    'totalPointsValue',
    'totalTax',
    'totalSurcharges',
    'totalCash',
    'totalOtherPayments',
    'totalOtherRevenue',
    'totalOtherExpense',
    'totalReturnRevenue'
  };

  bool get isLoading => _isLoading;
  Map<String, double> _rootPaymentMethods = {};
  bool get isOwnerOrManager =>
      widget.currentUser.role == 'owner' ||
          widget.currentUser.role == 'manager';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _openingBalanceController.text = _numberFormat.format(_openingBalance);
    _loadSettingsAndFetchData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _openingBalanceController.dispose();
    for (final controller in _shiftBalanceControllers.values) {
      controller.dispose();
    }
    _shiftBalanceControllers.clear();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetchData() async {
    final settingsService = SettingsService();
    final settingsId = widget.currentUser.storeId;
    try {
      final settings =
      await settingsService.watchStoreSettings(settingsId).first;
      if (!mounted) return;
      setState(() {
        _reportCutoffTime = TimeOfDay(
          hour: settings.reportCutoffHour ?? 0,
          minute: settings.reportCutoffMinute ?? 0,
        );
      });
      _updateDateRangeAndFetch();
    } catch (e) {
      debugPrint("Lỗi tải cài đặt ban đầu (Cuối Ngày): $e");
      if (mounted) {
        _setLoading(false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi tải cài đặt: $e")));
      }
    }
    _settingsSub =
        settingsService.watchStoreSettings(settingsId).listen((settings) {
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
          debugPrint("Lỗi stream cài đặt (Cuối Ngày): $e");
        });
  }

  void _updateDateRangeAndFetch() {
    if (_selectedRange == TimeRange.custom) {
      if (_calendarStartDate == null || _calendarEndDate == null) {
        _selectedRange =
            TimeRange.today;
      }
    }

    final now = DateTime.now();
    final cutoff = _reportCutoffTime;

    DateTime startOfReportDay(DateTime date) {
      final calendarDay = DateTime(date.year, date.month, date.day);
      return calendarDay
          .add(Duration(hours: cutoff.hour, minutes: cutoff.minute));
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
    effectiveDate =
        DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);

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
          final startOfWeek = effectiveDate.subtract(
              Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(
              Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _startDate = startOfReportDay(startOfWeek);
          _endDate = endOfReportDay(endOfWeek);
          _calendarStartDate = startOfWeek;
          _calendarEndDate = endOfWeek;
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay =
          effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay =
          endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          _calendarStartDate = startOfLastWeekDay;
          _calendarEndDate = endOfLastWeekDay;
          break;
        case TimeRange.thisMonth:
          final startOfMonth =
          DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth = DateTime(effectiveDate.year,
              effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          _calendarStartDate = startOfMonth;
          _calendarEndDate = endOfMonth;
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth = DateTime(effectiveDate.year,
              effectiveDate.month, 0);
          final startOfLastMonth =
          DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
          _startDate = startOfReportDay(startOfLastMonth);
          _endDate = endOfReportDay(endOfLastMonth);
          _calendarStartDate = startOfLastMonth;
          _calendarEndDate = endOfLastMonth;
          break;
      }
    } else {
      if (_calendarStartDate != null) {
        _startDate = startOfReportDay(_calendarStartDate!);
      }
      if (_calendarEndDate != null) {
        _endDate = endOfReportDay(_calendarEndDate!);
      }
    }

    if (_startDate != null && _endDate != null) {
      _fetchEndOfDayReport();
    } else {
      _setLoading(false);
    }
  }

  void _setLoading(bool loading) {
    if (!mounted) return;
    Future.microtask(() {
      if (mounted) {
        setState(() {
          _isLoading = loading;
        });
        widget.onLoadingChanged(loading);
      }
    });
  }

  Future<void> _fetchEndOfDayReport() async {
    if (_calendarStartDate == null || _calendarEndDate == null) {
      _setLoading(false);
      return;
    }
    _setLoading(true);

    final Map<String, double> oldBalances = Map.from(_shiftOpeningBalances);
    final Map<String, TextEditingController> oldControllers = {};
    _shiftBalanceControllers.forEach((key, controller) {
      oldControllers[key] = TextEditingController(text: controller.text);
    });

    setState(() {
      _totalOrders = 0;
      _totalDiscount = 0;
      _totalBillDiscount = 0;
      _totalVoucher = 0;
      _totalPointsValue = 0;
      _totalTax = 0;
      _totalSurcharges = 0;
      _totalRevenue = 0;
      _totalCash = 0;
      _totalOtherPayments = 0;
      _totalDebt = 0;
      _actualRevenue = 0;
      _totalOtherRevenue = 0;
      _totalOtherExpense = 0;
      _totalReturnRevenue = 0;
      _closingBalance = 0;
      _shiftDataList = [];
      _rootProductsSold = {};
      _rootPaymentMethods = {};
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final storeId = widget.currentUser.storeId;
      final DateFormat formatter = DateFormat('yyyy-MM-dd');
      final String firstDayString = formatter.format(_calendarStartDate!);
      final String firstReportId = '${storeId}_$firstDayString';
      setState(() {
        _firstReportId = firstReportId;
      });
      const batchSize = 30;
      final List<String> dateStringsToFetch =
      _getDateStringsInRange(_calendarStartDate!, _calendarEndDate!);
      List<QueryDocumentSnapshot> reportDocs = [];

      if (dateStringsToFetch.isNotEmpty) {
        final List<String> dailyReportIds = dateStringsToFetch
            .map((dateStr) => '${storeId}_$dateStr')
            .toSet()
            .toList();

        for (int i = 0; i < dailyReportIds.length; i += batchSize) {
          final batchIds = dailyReportIds.sublist(
              i,
              i + batchSize > dailyReportIds.length
                  ? dailyReportIds.length
                  : i + batchSize);
          if (batchIds.isNotEmpty) {
            final snapshot = await firestore
                .collection('daily_reports')
                .where(FieldPath.documentId, whereIn: batchIds)
                .get();
            reportDocs.addAll(snapshot.docs);
          }
        }
      }
      _processReportData(reportDocs, oldBalances, oldControllers, firstReportId);
    } catch (e) {
      debugPrint("Lỗi khi tải báo cáo cuối ngày: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi tải báo cáo: $e")));
      }
    } finally {
      _setLoading(false);
    }
  }

  DateTime _getReportDayForTimestamp(DateTime timestamp) {
    final cutoff = _reportCutoffTime;
    final dateCutoff = DateTime(timestamp.year, timestamp.month, timestamp.day,
        cutoff.hour, cutoff.minute);

    if (timestamp.isBefore(dateCutoff)) {
      return dateCutoff.subtract(const Duration(days: 1));
    } else {
      return dateCutoff;
    }
  }

  DateTime _getStartOfReportDay(DateTime timestamp) {
    final cutoff = _reportCutoffTime;
    final reportDay = _getReportDayForTimestamp(timestamp);
    return DateTime(reportDay.year, reportDay.month, reportDay.day, cutoff.hour,
        cutoff.minute);
  }

  DateTime _getEndOfReportDay(DateTime timestamp) {
    final DateTime startOfThisReportDay = _getStartOfReportDay(timestamp);
    return startOfThisReportDay
        .add(const Duration(days: 1))
        .subtract(const Duration(milliseconds: 1));
  }

  void _processReportData(
      List<QueryDocumentSnapshot> reportDocs,
      Map<String, double> oldBalances,
      Map<String, TextEditingController> oldControllers,
      String firstReportId,
      ) {
    final Map<String, double> totalData = {
      for (var field in _rootReportFields) field: 0.0
    };
    final List<Map<String, dynamic>> allShifts = [];
    final Set<String> newShiftIds = {};
    final Map<String, dynamic> aggregatedRootProducts = {};
    final Map<String, double> aggregatedPaymentMethods = {};
    double firstDayOpeningBalance = 0.0;

    for (final doc in reportDocs) {
      final data = doc.data() as Map<String, dynamic>;

      if (doc.id == firstReportId) {
        firstDayOpeningBalance = (data['openingBalance'] as num?)?.toDouble() ?? 0.0;
      }

      for (final key in data.keys) {
        if (_rootReportFields.contains(key) && data[key] is num) {
          totalData[key] =
              (totalData[key] ?? 0.0) + (data[key] as num).toDouble();
        }
      }
      final paymentMethodsMap = data['paymentMethods'] as Map<String, dynamic>?;
      if (paymentMethodsMap != null) {
        paymentMethodsMap.forEach((method, amount) {
          aggregatedPaymentMethods[method] = (aggregatedPaymentMethods[method] ?? 0.0) + (amount as num).toDouble();
        });
      }

      final rootProducts = (data['products'] as Map<String, dynamic>?) ?? {};
      for (final pEntry in rootProducts.entries) {
        final String pId = pEntry.key;
        final pData = pEntry.value as Map<String, dynamic>;
        final num qty = pData['quantitySold'] as num? ?? 0;
        final num rev = pData['totalRevenue'] as num? ?? 0;
        final num disc = pData['totalDiscount'] as num? ?? 0;

        if (aggregatedRootProducts.containsKey(pId)) {
          final existing = aggregatedRootProducts[pId];
          existing['quantitySold'] = (existing['quantitySold'] as num) + qty;
          existing['totalRevenue'] = (existing['totalRevenue'] as num) + rev;
          existing['totalDiscount'] = (existing['totalDiscount'] as num? ?? 0) + disc;
        } else {
          aggregatedRootProducts[pId] = Map<String, dynamic>.from(pData);
        }
      }

      final shiftsMap = data['shifts'] as Map<String, dynamic>?;
      if (shiftsMap != null) {
        for (final entry in shiftsMap.entries) {
          final String shiftId = entry.key;
          newShiftIds.add(shiftId);
          final dynamic shiftValue = entry.value;

          if (shiftValue is Map<String, dynamic>) {
            final String reportDateKey = doc.id.split('_').last;
            shiftValue['reportDateKey'] = reportDateKey;
            shiftValue['shiftId'] = shiftId;
            allShifts.add(shiftValue);

            final double savedOpeningBalance =
                (shiftValue['openingBalance'] as num?)?.toDouble() ?? 0.0;
            final double currentBalance =
                oldBalances[shiftId] ?? savedOpeningBalance;
            _shiftOpeningBalances[shiftId] = currentBalance;

            if (oldControllers.containsKey(shiftId)) {
              _shiftBalanceControllers[shiftId] = oldControllers[shiftId]!;
              final cleanOldText = oldControllers[shiftId]!
                  .text
                  .replaceAll('.', '');
              if (double.tryParse(cleanOldText) != savedOpeningBalance) {
                oldControllers[shiftId]!.text =
                    _numberFormat.format(currentBalance);
              }
            } else {
              _shiftBalanceControllers[shiftId] = TextEditingController(
                  text: _numberFormat.format(currentBalance));
            }
          }
        }
      }
    }

    for (final oldId in oldControllers.keys) {
      if (!newShiftIds.contains(oldId)) {
        oldControllers[oldId]?.dispose();
      }
    }
    _shiftOpeningBalances.removeWhere((key, value) => !newShiftIds.contains(key));


    allShifts.sort((a, b) {
      final aTime = (a['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);
      final bTime = (b['startTime'] as Timestamp?)?.toDate() ?? DateTime(0);
      return bTime.compareTo(aTime);
    });

    final Map<String, DateTime> lastEndTimePerUser = {};
    final List<Map<String, dynamic>> processedShifts = [];

    for (final shiftData in allShifts) {
      final String userId = (shiftData['userId'] as String?) ?? 'unknown';
      final Timestamp? actualStartTimeStamp =
      shiftData['startTime'] as Timestamp?;
      final Timestamp? actualEndTimeStamp = shiftData['endTime'] as Timestamp?;
      final String status = shiftData['status'] as String? ?? 'closed';

      DateTime? calculatedStartTime;
      DateTime? calculatedEndTime;

      if (actualStartTimeStamp != null) {
        final DateTime actualStartTime = actualStartTimeStamp.toDate();
        final DateTime? lastEnd = lastEndTimePerUser[userId];
        final DateTime startOfThisReportDay =
        _getStartOfReportDay(actualStartTime);

        if (lastEnd != null) {
          final DateTime startOfLastReportDay = _getStartOfReportDay(lastEnd);
          if (startOfThisReportDay.isAtSameMomentAs(startOfLastReportDay)) {
            calculatedStartTime = lastEnd;
          } else {
            calculatedStartTime = startOfThisReportDay;
          }
        } else {
          calculatedStartTime = startOfThisReportDay;
        }

        if (status == 'closed') {
          calculatedEndTime = actualEndTimeStamp?.toDate() ?? actualStartTime;
        } else {
          final DateTime now = DateTime.now();
          final DateTime startOfThisReportDay = _getStartOfReportDay(actualStartTime);
          final DateTime startOfCurrentReportDay = _getStartOfReportDay(now);

          if (startOfThisReportDay.isBefore(startOfCurrentReportDay)) {
            calculatedEndTime = _getEndOfReportDay(actualStartTime);
          } else {
            calculatedEndTime = now;
          }
        }
        lastEndTimePerUser[userId] = calculatedEndTime;
      }

      processedShifts.add({
        ...shiftData,
        'calculatedStartTime': calculatedStartTime,
        'calculatedEndTime': calculatedEndTime,
      });
    }

    final actualRev = (totalData['totalCash'] ?? 0.0) +
        (totalData['totalOtherPayments'] ?? 0.0);
    final closingBal = firstDayOpeningBalance +
        actualRev +
        (totalData['totalOtherRevenue'] ?? 0.0) -
        (totalData['totalOtherExpense'] ?? 0.0);

    setState(() {
      _totalOrders = totalData['billCount']?.toInt() ?? 0;
      _totalDiscount = totalData['totalDiscount'] ?? 0.0;
      _totalBillDiscount = totalData['totalBillDiscount'] ?? 0.0;
      _totalVoucher = totalData['totalVoucherDiscount'] ?? 0.0;
      _totalPointsValue = totalData['totalPointsValue'] ?? 0.0;
      _totalTax = totalData['totalTax'] ?? 0.0;
      _totalSurcharges = totalData['totalSurcharges'] ?? 0.0;
      _totalRevenue = totalData['totalRevenue'] ?? 0.0;
      _totalCash = totalData['totalCash'] ?? 0.0;
      _totalOtherPayments = totalData['totalOtherPayments'] ?? 0.0;
      _totalDebt = totalData['totalDebt'] ?? 0.0;
      _actualRevenue = actualRev;
      _totalOtherRevenue = totalData['totalOtherRevenue'] ?? 0.0;
      _totalOtherExpense = totalData['totalOtherExpense'] ?? 0.0;
      _totalReturnRevenue = totalData['totalReturnRevenue'] ?? 0.0;
      _closingBalance = closingBal;
      _shiftDataList = processedShifts;
      _rootProductsSold = aggregatedRootProducts;
      _rootPaymentMethods = aggregatedPaymentMethods;
    });
    _openingBalanceController.text = _numberFormat.format(firstDayOpeningBalance);
  }

  void _recalculateClosingBalance() {
    setState(() {
      _closingBalance = _openingBalance +
          _actualRevenue +
          _totalOtherRevenue -
          _totalOtherExpense;
    });
  }

  List<String> _getDateStringsInRange(DateTime startDate, DateTime endDate) {
    final List<String> dateStrings = [];
    DateTime currentDate =
    DateTime(startDate.year, startDate.month, startDate.day);
    final DateTime finalDate =
    DateTime(endDate.year, endDate.month, endDate.day);
    final DateFormat formatter = DateFormat('yyyy-MM-dd');
    while (currentDate.isBefore(finalDate) ||
        currentDate.isAtSameMomentAs(finalDate)) {
      dateStrings.add(formatter.format(currentDate));
      currentDate = currentDate.add(const Duration(days: 1));
    }
    return dateStrings;
  }

  String _getTimeRangeText(TimeRange range) {
    switch (range) {
      case TimeRange.custom:
        return 'Tùy chọn...';
      case TimeRange.today:
        return 'Hôm nay';
      case TimeRange.yesterday:
        return 'Hôm qua';
      case TimeRange.thisWeek:
        return 'Tuần này';
      case TimeRange.lastWeek:
        return 'Tuần trước';
      case TimeRange.thisMonth:
        return 'Tháng này';
      case TimeRange.lastMonth:
        return 'Tháng trước';
    }
  }

  void showFilterModal() {
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _calendarStartDate;
    DateTime? tempEndDate = _calendarEndDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext modalContext, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Báo Cáo Cuối Ngày',
                      style: Theme.of(ctx).textTheme.headlineMedium),
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
                        showOmniDateTimeRangePicker(
                          context: ctx,
                          startInitialDate: tempStartDate ?? DateTime.now(),
                          endInitialDate: tempEndDate,
                          startFirstDate: DateTime(2020),
                          startLastDate:
                          DateTime.now().add(const Duration(days: 365)),
                          endFirstDate: tempStartDate ?? DateTime(2020),
                          endLastDate:
                          DateTime.now().add(const Duration(days: 365)),
                          is24HourMode: true,
                          isShowSeconds: false,
                          type: OmniDateTimePickerType
                              .date,
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
                    selectedItemBuilder: (sctx) {
                      return TimeRange.values.map<Widget>((range) {
                        if (range == TimeRange.custom &&
                            tempSelectedRange == TimeRange.custom &&
                            tempStartDate != null &&
                            tempEndDate != null) {
                          final start =
                          DateFormat('dd/MM/yyyy').format(tempStartDate!);
                          final end =
                          DateFormat('dd/MM/yyyy').format(tempEndDate!);
                          return Text('$start - $end',
                              overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getTimeRangeText(range));
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
                          bool dateChanged =
                              (_selectedRange != tempSelectedRange) ||
                                  (_selectedRange == TimeRange.custom &&
                                      (_calendarStartDate != tempStartDate ||
                                          _calendarEndDate != tempEndDate));

                          setState(() {
                            _selectedRange = tempSelectedRange;
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

  void generateCombinedPdfAndShowDialog() {
    if (!isOwnerOrManager || _isLoading) return;

    final Map<String, dynamic> totalReportData = {
      'reportTitle': 'BÁO CÁO TỔNG KẾT',
      'employeeName': widget.currentUser.name,
      'startDate': _calendarStartDate?.toIso8601String(),
      'endDate': _calendarEndDate?.toIso8601String(),
      'totalOrders': _totalOrders,
      'totalDiscount': _totalDiscount,
      'totalBillDiscount': _totalBillDiscount,
      'totalVoucher': _totalVoucher,
      'totalPointsValue': _totalPointsValue,
      'totalTax': _totalTax,
      'totalSurcharges': _totalSurcharges,
      'totalRevenue': _totalRevenue,
      'totalCash': _totalCash,
      'totalOtherPayments': _totalOtherPayments,
      'totalDebt': _totalDebt,
      'actualRevenue': _actualRevenue,
      'openingBalance': _openingBalance,
      'totalOtherRevenue': _totalOtherRevenue,
      'totalOtherExpense': _totalOtherExpense,
      'closingBalance': _closingBalance,
      'productsSold': _rootProductsSold,
      'paymentMethods': _rootPaymentMethods,
      'totalReturnRevenue': _totalReturnRevenue,
    };

    final List<Map<String, dynamic>> shiftReportsData =
    _shiftDataList.map((shiftData) {
      final double shiftCash =
          (shiftData['totalCash'] as num?)?.toDouble() ?? 0.0;
      final double shiftOtherPayments =
          (shiftData['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;
      final double shiftOtherRevenue =
          (shiftData['totalOtherRevenue'] as num?)?.toDouble() ?? 0.0;
      final double shiftOtherExpense =
          (shiftData['totalOtherExpense'] as num?)?.toDouble() ?? 0.0;

      final String shiftId = (shiftData['shiftId'] as String?) ?? '';
      final double shiftOpeningBalance = _shiftOpeningBalances[shiftId] ?? 0.0;

      final double shiftActualRevenue = shiftCash + shiftOtherPayments;
      final double shiftClosingBalance = shiftOpeningBalance +
          shiftActualRevenue +
          shiftOtherRevenue -
          shiftOtherExpense;
      final String employeeName =
          (shiftData['userName'] as String?) ?? 'Không rõ';
      final String status = (shiftData['status'] as String?) ?? 'closed';

      final DateTime? calculatedStartTime = _parseDateTime(shiftData['calculatedStartTime']);
      final DateTime? calculatedEndTime = _parseDateTime(shiftData['calculatedEndTime']);
      final double shiftReturnRevenue = (shiftData['totalReturnRevenue'] as num?)?.toDouble() ?? 0.0;
      return {
        'reportTitle': 'CA THU NGÂN: $employeeName',
        'employeeName': employeeName,
        'totalOrders': (shiftData['billCount'] as num?)?.toInt() ?? 0,
        'totalDiscount': (shiftData['totalDiscount'] as num?)?.toDouble() ?? 0.0,
        'totalBillDiscount': (shiftData['totalBillDiscount'] as num?)?.toDouble() ?? 0.0,
        'totalVoucher': (shiftData['totalVoucherDiscount'] as num?)?.toDouble() ?? 0.0,
        'totalPointsValue': (shiftData['totalPointsValue'] as num?)?.toDouble() ?? 0.0,
        'totalTax': (shiftData['totalTax'] as num?)?.toDouble() ?? 0.0,
        'totalSurcharges': (shiftData['totalSurcharges'] as num?)?.toDouble() ?? 0.0,
        'totalRevenue': (shiftData['totalRevenue'] as num?)?.toDouble() ?? 0.0,
        'totalCash': shiftCash,
        'totalOtherPayments': shiftOtherPayments,
        'totalDebt': (shiftData['totalDebt'] as num?)?.toDouble() ?? 0.0,
        'actualRevenue': shiftActualRevenue,
        'openingBalance': shiftOpeningBalance,
        'totalOtherRevenue': shiftOtherRevenue,
        'totalOtherExpense': shiftOtherExpense,
        'closingBalance': shiftClosingBalance,
        'shiftStatus': status,
        'calculatedStartTime': calculatedStartTime?.toIso8601String(),
        'calculatedEndTime': calculatedEndTime?.toIso8601String(),
        'productsSold': (shiftData['products'] as Map<String, dynamic>?) ?? {},
        'paymentMethods': (shiftData['paymentMethods'] as Map<String, dynamic>?) ?? {},
        'totalReturnRevenue': shiftReturnRevenue,
      };
    }).toList();

    showDialog(
      context: context,
      builder: (_) => _EndOfDayReportDialog(
        totalReportData: totalReportData,
        shiftReportsData: shiftReportsData,
        currentUser: widget.currentUser,
        reportCutoffTime: _reportCutoffTime,
        effectiveNow: DateTime.now(),
      ),
    );
  }

  void _showTotalReportPdfDialog() {
    if (!isOwnerOrManager || _isLoading) return;

    final Map<String, dynamic> totalReportData = {
      'reportTitle': 'BÁO CÁO TỔNG KẾT',
      'employeeName': widget.currentUser.name,
      'startDate': _calendarStartDate?.toIso8601String(),
      'endDate': _calendarEndDate?.toIso8601String(),
      'totalOrders': _totalOrders,
      'totalDiscount': _totalDiscount,
      'totalBillDiscount': _totalBillDiscount,
      'totalVoucher': _totalVoucher,
      'totalPointsValue': _totalPointsValue,
      'totalTax': _totalTax,
      'totalSurcharges': _totalSurcharges,
      'totalRevenue': _totalRevenue,
      'totalCash': _totalCash,
      'totalOtherPayments': _totalOtherPayments,
      'totalDebt': _totalDebt,
      'actualRevenue': _actualRevenue,
      'openingBalance': _openingBalance,
      'totalOtherRevenue': _totalOtherRevenue,
      'totalOtherExpense': _totalOtherExpense,
      'closingBalance': _closingBalance,
      'productsSold': _rootProductsSold,
      'paymentMethods': _rootPaymentMethods,
      'totalReturnRevenue': _totalReturnRevenue,
    };

    final List<Map<String, dynamic>> shiftReportsData = [];

    showDialog(
      context: context,
      builder: (_) => _EndOfDayReportDialog(
        totalReportData: totalReportData,
        shiftReportsData: shiftReportsData,
        currentUser: widget.currentUser,
        reportCutoffTime: _reportCutoffTime,
        effectiveNow: DateTime.now(),
      ),
    );
  }

  void _showShiftPdfDialog(Map<String, dynamic> shiftData) {
    final double shiftCash =
        (shiftData['totalCash'] as num?)?.toDouble() ?? 0.0;
    final double shiftOtherPayments =
        (shiftData['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;
    final double shiftOtherRevenue =
        (shiftData['totalOtherRevenue'] as num?)?.toDouble() ?? 0.0;
    final double shiftOtherExpense =
        (shiftData['totalOtherExpense'] as num?)?.toDouble() ?? 0.0;
    final double shiftReturnRevenue = (shiftData['totalReturnRevenue'] as num?)?.toDouble() ?? 0.0;
    final String shiftId = (shiftData['shiftId'] as String?) ?? '';
    final double shiftOpeningBalance = _shiftOpeningBalances[shiftId] ?? 0.0;

    final double shiftActualRevenue = shiftCash + shiftOtherPayments;
    final double shiftClosingBalance = shiftOpeningBalance +
        shiftActualRevenue +
        shiftOtherRevenue -
        shiftOtherExpense;
    final String employeeName =
        (shiftData['userName'] as String?) ?? 'Không rõ';
    final String status = (shiftData['status'] as String?) ?? 'closed';

    final DateTime? calculatedStartTime = _parseDateTime(shiftData['calculatedStartTime']);
    final DateTime? calculatedEndTime = _parseDateTime(shiftData['calculatedEndTime']);

    final Map<String, dynamic> singleShiftReportData = {
      'reportTitle': 'TỔNG KẾT CA: $employeeName',
      'totalOrders': (shiftData['billCount'] as num?)?.toInt() ?? 0,
      'totalDiscount': (shiftData['totalDiscount'] as num?)?.toDouble() ?? 0.0,
      'totalBillDiscount': (shiftData['totalBillDiscount'] as num?)?.toDouble() ?? 0.0,
      'totalVoucher':
      (shiftData['totalVoucherDiscount'] as num?)?.toDouble() ?? 0.0,
      'totalPointsValue':
      (shiftData['totalPointsValue'] as num?)?.toDouble() ?? 0.0,
      'totalTax': (shiftData['totalTax'] as num?)?.toDouble() ?? 0.0,
      'totalSurcharges':
      (shiftData['totalSurcharges'] as num?)?.toDouble() ?? 0.0,
      'totalRevenue': (shiftData['totalRevenue'] as num?)?.toDouble() ?? 0.0,
      'totalReturnRevenue': shiftReturnRevenue,
      'totalCash': shiftCash,
      'totalOtherPayments': shiftOtherPayments,
      'totalDebt': (shiftData['totalDebt'] as num?)?.toDouble() ?? 0.0,
      'actualRevenue': shiftActualRevenue,
      'openingBalance': shiftOpeningBalance,
      'totalOtherRevenue': shiftOtherRevenue,
      'totalOtherExpense': shiftOtherExpense,
      'closingBalance': shiftClosingBalance,
      'shiftStatus': status,
      'calculatedStartTime': calculatedStartTime?.toIso8601String(),
      'calculatedEndTime': calculatedEndTime?.toIso8601String(),
      'productsSold': (shiftData['products'] as Map<String, dynamic>?) ?? {},
      'paymentMethods': (shiftData['paymentMethods'] as Map<String, dynamic>?) ?? {},
    };

    showDialog(
      context: context,
      builder: (_) => _EndOfDayReportDialog(
        totalReportData: null,
        shiftReportsData: [singleShiftReportData],
        currentUser: widget.currentUser,
        reportCutoffTime: _reportCutoffTime,
        effectiveNow: DateTime.now(),
      ),
    );
  }

  void _onCloseShift(Map<String, dynamic> shiftData) async {
    if (_isLoading) return;
    final String? shiftId = shiftData['shiftId'] as String?;
    final String? reportDateKey = shiftData['reportDateKey'] as String?;
    final String storeId = widget.currentUser.storeId;
    if (shiftId == null || reportDateKey == null) {
      ToastService().show(
          message: "Lỗi: Không tìm thấy ID ca hoặc ngày báo cáo.",
          type: ToastType.error);
      return;
    }
    _setLoading(true);
    try {
      final firestore = FirebaseFirestore.instance;
      final WriteBatch batch = firestore.batch();
      final endTime = Timestamp.now();

      final double currentOpeningBalance = _shiftOpeningBalances[shiftId] ?? 0.0;

      final shiftRef = firestore.collection('employee_shifts').doc(shiftId);
      batch.update(shiftRef, {
        'status': 'closed',
        'endTime': endTime,
        'openingBalance': currentOpeningBalance
      });

      final reportId = '${storeId}_$reportDateKey';
      final reportRef = firestore.collection('daily_reports').doc(reportId);
      batch.update(reportRef, {
        'shifts.$shiftId.status': 'closed',
        'shifts.$shiftId.endTime': endTime,
        'shifts.$shiftId.openingBalance': currentOpeningBalance
      });

      await batch.commit();
      ToastService()
          .show(message: "Đã kết ca thành công!", type: ToastType.success);

      final Map<String, dynamic> updatedShiftData = Map.from(shiftData);
      updatedShiftData['status'] = 'closed';
      updatedShiftData['endTime'] = endTime;
      updatedShiftData['calculatedEndTime'] = endTime.toDate();
      updatedShiftData['openingBalance'] = currentOpeningBalance;

      _showShiftPdfDialog(updatedShiftData);
      _fetchEndOfDayReport();
    } catch (e) {
      debugPrint("Lỗi khi kết ca: $e");
      ToastService().show(message: "Lỗi khi kết ca: $e", type: ToastType.error);
      _setLoading(false);
    }
  }

  DateTime? _parseDateTime(dynamic dt) {
    if (dt == null) return null;
    if (dt is DateTime) return dt;
    if (dt is String) return DateTime.tryParse(dt);
    if (dt is Timestamp) return dt.toDate();
    return null;
  }

  Future<void> _updateShiftOpeningBalance(String? reportDateKey, String? shiftId, double newBalance) async {
    if (reportDateKey == null || shiftId == null) {
      ToastService().show(message: "Lỗi: Không tìm thấy ID ca", type: ToastType.error);
      return;
    }

    final storeId = widget.currentUser.storeId;
    final firestore = FirebaseFirestore.instance;
    final WriteBatch batch = firestore.batch();

    try {
      final reportId = '${storeId}_$reportDateKey';
      final reportRef = firestore.collection('daily_reports').doc(reportId);
      batch.update(reportRef, {'shifts.$shiftId.openingBalance': newBalance});

      final shiftRef = firestore.collection('employee_shifts').doc(shiftId);
      batch.update(shiftRef, {'openingBalance': newBalance});

      await batch.commit();

    } catch (e) {
      debugPrint("Lỗi cập nhật quỹ đầu ca: $e");
      ToastService().show(message: "Lỗi lưu quỹ đầu ca: $e", type: ToastType.error);
    }
  }

  Future<void> _updateOpeningBalance(double newBalance) async {
    if (_firstReportId == null) {
      ToastService().show(message: "Lỗi: Không tìm thấy ID báo cáo", type: ToastType.error);
      return;
    }

    final firestore = FirebaseFirestore.instance;
    try {
      final reportRef = firestore.collection('daily_reports').doc(_firstReportId!);

      await reportRef.set(
        {'openingBalance': newBalance},
        SetOptions(merge: true),
      );

    } catch (e) {
      debugPrint("Lỗi cập nhật quỹ đầu kỳ: $e");
      ToastService().show(message: "Lỗi lưu quỹ đầu kỳ: $e", type: ToastType.error);
    }
  }

  String _buildTimeRangeString(DateTime start, DateTime end) {
    final DateFormat formatter = DateFormat('HH:mm dd/MM');
    final String startTime = formatter.format(start);
    final String endTime;

    if (end.isAfter(DateTime.now())) {
      endTime = formatter.format(DateTime.now());
    } else {
      endTime = formatter.format(end);
    }
    return "($startTime - $endTime)";
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _fetchEndOfDayReport,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
          builder: (context, constraints) {
            final bool isWide = constraints.maxWidth > 800;

            final List<Widget> totalCard = [];
            if (isOwnerOrManager && _totalOrders > 0) {
              totalCard.add(_buildTotalReportCard(isWide));
            }

            final List<Widget> shiftCards = _buildEmployeeShiftCards(isWide);

            final List<Widget> emptyMessages = [];
            if (!isOwnerOrManager && _shiftDataList.isEmpty) {
              emptyMessages.add(const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48.0),
                  child: Text(
                      "Không có dữ liệu ca cho khoảng thời gian này."),
                ),
              ));
            }
            if (isOwnerOrManager &&
                _totalOrders == 0 &&
                _shiftDataList.isEmpty) {
              emptyMessages.add(const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48.0),
                  child: Text(
                      "Không có dữ liệu cho khoảng thời gian này."),
                ),
              ));
            }

            if (totalCard.isEmpty && shiftCards.isEmpty) {
              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: emptyMessages,
              );
            }

            // --- SỬA: Dùng ListView cho cả mobile và desktop ---
            if (!isWide) {
              // Mobile: Dùng ListView (1 cột)
              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  ...totalCard,
                  if (totalCard.isNotEmpty && shiftCards.isNotEmpty)
                    const SizedBox(height: 16),
                  ...shiftCards,
                  if (emptyMessages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ...emptyMessages,
                  ]
                ],
              );
            } else {
              // Desktop: Dùng ListView bọc Grid (2 cột)
              // Toàn bộ trang sẽ cuộn
              return ListView(
                padding: const EdgeInsets.all(16.0),
                children: [
                  _buildResponsiveGrid([...totalCard, ...shiftCards]),
                  ...emptyMessages,
                ],
              );
            }
            // --- KẾT THÚC SỬA ---
          },
        ),
      ),
    );
  }

  Widget _buildResponsiveGrid(List<Widget> cards) {
    if (cards.isEmpty) return const SizedBox.shrink();

    List<Widget> rows = [];
    for (int i = 0; i < cards.length; i += 2) {
      Widget card1 = cards[i];
      Widget? card2 = (i + 1 < cards.length) ? cards[i + 1] : null;

      // --- SỬA: Gỡ bỏ Expanded, chỉ dùng Row ---
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start, // Các thẻ align top
          children: [
            Expanded(child: card1),
            const SizedBox(width: 16), // Luôn có khoảng cách
            if (card2 != null)
              Expanded(child: card2)
            else
              Expanded(child: SizedBox()), // Cột 2 rỗng để giữ layout
          ],
        ),
      );
      // --- KẾT THÚC SỬA ---

      if (i + 2 < cards.length) {
        rows.add(const SizedBox(height: 16));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  List<Widget> _buildEmployeeShiftCards(bool isWide) {
    List<Widget> cards = [];
    final isOwner = isOwnerOrManager;
    final currentUserId = widget.currentUser.uid;

    for (final shiftData in _shiftDataList) {
      final String shiftUserId = (shiftData['userId'] as String?) ?? '';

      final int orders = (shiftData['billCount'] as num?)?.toInt() ?? 0;
      final bool isOpen = (shiftData['status'] as String?) == 'open';

      if (orders == 0 && !isOpen) {
        continue;
      }

      if (!isOwner && shiftUserId != currentUserId) {
        continue;
      }

      cards.add(_buildSingleShiftCard(shiftData, isWide));
    }
    return cards;
  }

  Widget _buildSingleShiftCard(Map<String, dynamic> data, bool isWide) {
    final int orders = (data['billCount'] as num?)?.toInt() ?? 0;
    final double discount = (data['totalDiscount'] as num?)?.toDouble() ?? 0.0;
    final double billDiscount = (data['totalBillDiscount'] as num?)?.toDouble() ?? 0.0;
    final double voucher =
        (data['totalVoucherDiscount'] as num?)?.toDouble() ?? 0.0;
    final double points = (data['totalPointsValue'] as num?)?.toDouble() ?? 0.0;
    final double tax = (data['totalTax'] as num?)?.toDouble() ?? 0.0;
    final double surcharges =
        (data['totalSurcharges'] as num?)?.toDouble() ?? 0.0;
    final double revenue = (data['totalRevenue'] as num?)?.toDouble() ?? 0.0;
    final double cash = (data['totalCash'] as num?)?.toDouble() ?? 0.0;
    final double otherPayments =
        (data['totalOtherPayments'] as num?)?.toDouble() ?? 0.0;
    final Map<String, dynamic> shiftPaymentMethods = (data['paymentMethods'] as Map<String, dynamic>?) ?? {};
    final double debt = (data['totalDebt'] as num?)?.toDouble() ?? 0.0;
    final double otherRevenue =
        (data['totalOtherRevenue'] as num?)?.toDouble() ?? 0.0;
    final double otherExpense =
        (data['totalOtherExpense'] as num?)?.toDouble() ?? 0.0;
    final productsSold = (data['products'] as Map<String, dynamic>?) ?? {};
    final double returnRevenue = (data['totalReturnRevenue'] as num?)?.toDouble() ?? 0.0;
    final String employeeName = (data['userName'] as String?) ?? 'Không rõ';
    final String status = (data['status'] as String?) ?? 'closed';
    final bool isOpen = status == 'open';

    final statusTag = Container(
      padding:
      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:
        isOpen ? AppTheme.primaryColor.withAlpha(25) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isOpen ? 'ĐANG MỞ' : 'ĐÃ ĐÓNG',
        style: TextStyle(
          color:
          isOpen ? AppTheme.primaryColor : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );

    final String shiftId = (data['shiftId'] as String?) ?? '';
    final String reportDateKey = (data['reportDateKey'] as String?) ?? '';
    final TextEditingController? balanceController = _shiftBalanceControllers[shiftId];

    final DateTime? startTime = data['calculatedStartTime'] as DateTime?;
    final DateTime? endTime = data['calculatedEndTime'] as DateTime?;

    final double openingBal = _shiftOpeningBalances[shiftId] ?? 0.0;
    final double actualRev = cash + otherPayments;
    final double closingBal = openingBal + actualRev + otherRevenue - otherExpense;
    final bool hasData =
        orders > 0 || revenue > 0 || otherRevenue > 0 || otherExpense > 0 || openingBal > 0;

    final divider = Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300);
    final boldDivider = Divider(height: 1, thickness: 1, color: Colors.grey.shade700);

    double cashFromMap = 0;
    List<Widget> paymentWidgets = [];

    if (shiftPaymentMethods.isNotEmpty) {
      final sortedKeys = shiftPaymentMethods.keys.toList()..sort();

      for (var method in sortedKeys) {
        final double amount = (shiftPaymentMethods[method] as num).toDouble();

        if (method == 'Tiền mặt') {
          cashFromMap = amount;
        } else {
          if (amount.abs() > 0.001) {
            paymentWidgets.add(Column(
              children: [
                _buildReportRow(method, amount),
                divider,
              ],
            ));
          }
        }
      }
    } else {
      cashFromMap = cash;
      if (otherPayments != 0) {
        paymentWidgets.add(Column(children: [_buildReportRow('Thanh toán khác', otherPayments), divider]));
      }
    }
    final Widget cardContent = Column(
      children: [
        if (!hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(child: Text("Không có dữ liệu cho ca này.")),
          )
        else
          Column(
            children: [
              _buildReportRow('Đơn hàng', orders.toDouble(),
                  isCurrency: false),
              divider,
              _buildReportRow('Chiết khấu/sản phẩm', discount),
              divider,
              _buildReportRow('Chiết khấu/tổng đơn', billDiscount),
              divider,
              _buildReportRow('Voucher', voucher),
              divider,
              _buildReportRow('Điểm thưởng', points),
              divider,
              _buildReportRow('Thuế', tax),
              divider,
              _buildReportRow('Phụ thu', surcharges),
              divider,
              _buildReportRow('Tổng doanh thu bán', revenue, isBold: true),
              // 2. Nếu có trả hàng thì hiển thị dòng trừ và dòng Net
              if (returnRevenue > 0) ...[
                divider,
                _buildReportRow('(-) Trả hàng', returnRevenue, color: Colors.red),
                divider,
                // Tính Net = Gross - Return
                _buildReportRow('(=) Doanh thu thuần', revenue - returnRevenue, isBold: true, color: AppTheme.primaryColor),
              ],
              boldDivider,
              _buildReportRow('Tiền mặt', cashFromMap),
              divider,
              if (paymentWidgets.isNotEmpty) ...paymentWidgets,
              _buildReportRow('Ghi nợ', debt),
              divider,
              _buildReportRow('Thực thu', actualRev, isBold: true),
              boldDivider,
              (isOpen && balanceController != null)
                  ? _buildShiftOpeningBalanceRow(
                  balanceController,
                  openingBal,
                      (newValue) {
                    final cleanValue = newValue.replaceAll('.', '');
                    setState(() {
                      _shiftOpeningBalances[shiftId] =
                          double.tryParse(cleanValue) ?? 0.0;
                    });
                  },
                      () {
                    final double currentValue =
                        _shiftOpeningBalances[shiftId] ?? 0.0;
                    balanceController.text =
                        _numberFormat.format(currentValue);
                    _updateShiftOpeningBalance(
                        reportDateKey, shiftId, currentValue);
                    FocusScope.of(context).unfocus();
                  })
                  : _buildReportRow('Quỹ đầu ca', openingBal),
              divider,
              _buildReportRow('Thu khác (Phiếu thu)', otherRevenue,
                  color: Colors.black),
              divider,
              _buildReportRow('Chi khác (Phiếu chi)', otherExpense,
                  color: Colors.black),
              divider,
              _buildReportRow('Tồn cuối ca', closingBal,
                  isBold: true, color: Colors.black),
              boldDivider,
              _buildSoldProductsList(productsSold),
            ],
          ),
      ],
    );
    // KẾT THÚC TÁCH NỘI DUNG

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isOpen
            ? BorderSide(color: AppTheme.primaryColor.withAlpha(155), width: 2)
            : BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // --- SỬA: Gỡ bỏ Positioned.fill và dùng Column đơn giản ---
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    if (isWide)
                      Row(
                        children: [
                          Opacity(
                            opacity: 0,
                            child: IgnorePointer(child: statusTag),
                          ),
                          Expanded(
                            child: Center(
                              child: Text(
                                'Ca thu ngân: $employeeName',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          statusTag,
                        ],
                      )
                    else
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Text(
                              'Ca thu ngân: $employeeName',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold, color: Colors.black),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          statusTag,
                        ],
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4.0, bottom: 0),
                      child: Center(
                        child: Column(
                          children: [
                            Text(
                              startTime != null
                                  ? 'Ngày: ${DateFormat('dd/MM/yyyy').format(startTime)}'
                                  : 'Ngày: N/A',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.grey.shade600),
                              textAlign: TextAlign.center,
                            ),
                            if (startTime != null && endTime != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _buildTimeRangeString(startTime, endTime),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ]
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- SỬA: Gỡ bỏ if (isWide) và Expanded, chỉ dùng Padding ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 80.0), // 80.0 là khoảng trống cho nút bấm
                child: cardContent,
              )
              // --- KẾT THÚC SỬA ---
            ],
          ),
          // --- KẾT THÚC SỬA ---

          // NÚT BẤM (NỔI LÊN TRÊN)
          Positioned(
            bottom: 16.0,
            left: 16.0,
            right: 16.0,
            child: Center(
              child: ElevatedButton.icon(
                icon: Icon(isOpen
                    ? Icons.check_circle_outline
                    : Icons.print_outlined),
                label: Text(isOpen ? 'Kết Ca' : 'In Lại Báo Cáo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOpen
                      ? AppTheme.primaryColor
                      : Colors.grey.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                ),
                onPressed: () =>
                isOpen ? _onCloseShift(data) : _showShiftPdfDialog(data),
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildTotalReportCard(bool isWide) {
    final bool hasData = _totalOrders > 0 ||
        _totalRevenue > 0 ||
        _totalCash > 0 ||
        _totalOtherPayments > 0 ||
        _totalDebt > 0 ||
        _totalOtherRevenue > 0 ||
        _totalOtherExpense > 0 ||
        _openingBalance > 0;
    final divider = Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300);
    final boldDivider = Divider(height: 1, thickness: 1, color: Colors.grey.shade700);

    double totalCashFromMap = 0;
    List<Widget> totalPaymentWidgets = [];
    if (_rootPaymentMethods.isNotEmpty) {
      final sortedKeys = _rootPaymentMethods.keys.toList()..sort();
      for (var method in sortedKeys) {
        final double amount = _rootPaymentMethods[method]!;
        if (method == 'Tiền mặt') {
          totalCashFromMap = amount;
        } else {
          if (amount.abs() > 0.001) {
            totalPaymentWidgets.add(Column(
              children: [
                _buildReportRow(method, amount),
                divider,
              ],
            ));
          }
        }
      }
    } else {
      totalCashFromMap = _totalCash;
      if (_totalOtherPayments != 0) {
        totalPaymentWidgets.add(Column(children: [_buildReportRow('Thanh toán khác', _totalOtherPayments), divider]));
      }
    }
    final Widget cardContent = Column(
      children: [
        if (!hasData)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Center(
                child: Text("Không có dữ liệu cho khoảng thời gian này.")),
          )
        else
          Column(
            children: [
              _buildReportRow('Đơn hàng', _totalOrders.toDouble(),
                  isCurrency: false),
              divider,
              _buildReportRow('Chiết khấu/sản phẩm', _totalDiscount),
              divider,
              _buildReportRow('Chiết khấu/tổng đơn', _totalBillDiscount),
              divider,
              _buildReportRow('Voucher', _totalVoucher),
              divider,
              _buildReportRow('Điểm thưởng', _totalPointsValue),
              divider,
              _buildReportRow('Thuế', _totalTax),
              divider,
              _buildReportRow('Phụ thu', _totalSurcharges),
              divider,
              _buildReportRow('Tổng doanh thu bán', _totalRevenue, isBold: true),
              if (_totalReturnRevenue > 0) ...[
                divider,
                _buildReportRow('(-) Trả hàng', _totalReturnRevenue, color: Colors.red),
                divider,
                _buildReportRow('(=) Doanh thu thuần', _totalRevenue - _totalReturnRevenue, isBold: true, color: AppTheme.primaryColor),
              ],
              boldDivider,
              _buildReportRow('Tiền mặt', totalCashFromMap),
              divider,
              if (totalPaymentWidgets.isNotEmpty) ...totalPaymentWidgets,
              _buildReportRow('Ghi nợ', _totalDebt),
              divider,
              _buildReportRow('Thực thu', _actualRevenue, isBold: true),
              boldDivider,
              _buildOpeningBalanceRow(),
              divider,
              _buildReportRow('Thu khác (Phiếu thu)', _totalOtherRevenue,
                  color: Colors.black),
              divider,
              _buildReportRow('Chi khác (Phiếu chi)', _totalOtherExpense,
                  color: Colors.black),
              divider,
              _buildReportRow('Tồn quỹ cuối kỳ', _closingBalance,
                  isBold: true, color: Colors.black),
              boldDivider,
              _buildSoldProductsList(_rootProductsSold),
            ],
          ),
      ],
    );
    // KẾT THÚC TÁCH NỘI DUNG

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // --- SỬA: Gỡ bỏ Positioned.fill và dùng Column đơn giản ---
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding( // Header
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Center(
                      child: Text('Báo Cáo Tổng',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    if (_calendarStartDate != null && _calendarEndDate != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0, bottom: 0),
                        child: Center(
                          child: Column(
                            children: [
                              Text(
                                _calendarStartDate == _calendarEndDate
                                    ? 'Ngày: ${DateFormat('dd/MM/yyyy').format(_calendarStartDate!)}'
                                    : 'Từ ${DateFormat('dd/MM/yyyy').format(_calendarStartDate!)} đến ${DateFormat('dd/MM/yyyy').format(_calendarEndDate!)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                              if (_startDate != null && _endDate != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _buildTimeRangeString(_startDate!, _endDate!),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: Colors.grey.shade600),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // KẾT THÚC HEADER

              // --- SỬA: Gỡ bỏ if (isWide) và Expanded, chỉ dùng Padding ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 80.0), // 80.0 là khoảng trống cho nút bấm
                child: cardContent,
              )
              // --- KẾT THÚC SỬA ---
            ],
          ),
          // --- KẾT THÚC SỬA ---

          // NÚT BẤM (NỔI LÊN TRÊN)
          if (hasData)
            Positioned(
              bottom: 16.0,
              left: 16.0,
              right: 16.0,
              child: Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('In Báo Cáo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  onPressed: _showTotalReportPdfDialog,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSoldProductsList(Map<String, dynamic> productsSold) {
    if (productsSold.isEmpty) {
      return const SizedBox.shrink();
    }

    final productList = productsSold.values.toList();

    final grouped = groupBy(productList, (item) => item['productGroup'] ?? 'Khác');

    final sortedGroupKeys = grouped.keys.toList()..sort();

    final groupTiles = sortedGroupKeys.map((groupName) {
      final itemsInGroup = grouped[groupName]!;

      // 1. Lọc ra các sản phẩm có số lượng bán > 0
      final filteredItems = itemsInGroup.where((item) {
        final double qty = (item['quantitySold'] as num?)?.toDouble() ?? 0.0;
        return qty > 0;
      }).toList();

      // 2. Nếu không có sản phẩm nào (đã lọc) trong nhóm này, bỏ qua (không hiển thị nhóm)
      if (filteredItems.isEmpty) return null;

      // 3. [SỬA] Tính tổng của nhóm DỰA TRÊN DANH SÁCH ĐÃ LỌC
      final double groupQty = filteredItems.fold(0, (tong, item) => tong + (item['quantitySold'] as num));
      final double groupRevenue = filteredItems.fold(0, (tong, item) => tong + (item['totalRevenue'] as num));
      final double groupDiscount = filteredItems.fold(0, (tong, item) => tong + (item['totalDiscount'] as num? ?? 0.0));

      return ExpansionTile(
        tilePadding: const EdgeInsets.only(left: 16.0, right: 8.0),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                groupName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'SL: ${formatNumber(groupQty)} | TC: ${formatNumber(groupRevenue)} đ',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                ),
                if (groupDiscount > 0)
                  Text(
                    'CK: ${formatNumber(groupDiscount)} đ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black),
                  ),
              ],
            ),
          ],
        ),
        // 4. [SỬA] Hiển thị danh sách con DỰA TRÊN DANH SÁCH ĐÃ LỌC (filteredItems)
        children: filteredItems.map((item) {
          final String name = item['productName'] ?? 'N/A';
          final double qty = (item['quantitySold'] as num?)?.toDouble() ?? 0.0;
          final double revenue = (item['totalRevenue'] as num?)?.toDouble() ?? 0.0;
          final double discount = (item['totalDiscount'] as num?)?.toDouble() ?? 0.0;
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 32.0, right: 16.0),
            title: Text(name, style: const TextStyle(fontSize: 14)),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'SL: ${formatNumber(qty)} | TC: ${formatNumber(revenue)} đ',
                  style: const TextStyle(fontSize: 14, color: Colors.black),
                ),
                if (discount > 0)
                  Text(
                    'CK: ${formatNumber(discount)} đ',
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                  ),
              ],
            ),
          );
        }).toList(),
      );
    }).whereType<ExpansionTile>().toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 0.0),
        title: Text(
          'Danh Sách Sản Phẩm Đã Bán',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        children: groupTiles,
      ),
    );
  }

  Widget _buildOpeningBalanceRow() {
    final labelStyle = TextStyle(fontSize: 16, color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text("Quỹ đầu kỳ", style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: _openingBalanceController,
              textAlign: TextAlign.right,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.black87),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                suffixText: ' đ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColor)),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                ThousandsInputFormatter(),
              ],
              onTap: () {
                _openingBalanceController.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: _openingBalanceController.text.length,
                );
              },
              onChanged: (value) {
                final cleanValue = value.replaceAll('.', '');
                _openingBalance = double.tryParse(cleanValue) ?? 0.0;
                _recalculateClosingBalance();
              },
              onEditingComplete: () {
                _openingBalanceController.text =
                    _numberFormat.format(_openingBalance);
                FocusScope.of(context).unfocus();
                _updateOpeningBalance(_openingBalance);
              },
              onTapOutside: (e) {
                _openingBalanceController.text =
                    _numberFormat.format(_openingBalance);
                FocusScope.of(context).unfocus();
                _updateOpeningBalance(_openingBalance);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShiftOpeningBalanceRow(
      TextEditingController controller,
      double currentBalanceValue,
      Function(String) onChanged,
      Function() onEditingComplete,
      ) {
    final labelStyle = TextStyle(fontSize: 16, color: Colors.grey.shade700);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text("Quỹ đầu ca", style: labelStyle),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: controller,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.normal, color: Colors.black87),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                suffixText: ' đ',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.primaryColor)),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                ThousandsInputFormatter(),
              ],
              onTap: () {
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              },
              onChanged: (value) {
                onChanged(value);
              },
              onEditingComplete: onEditingComplete,
              onTapOutside: (e) => onEditingComplete(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportRow(String label, double value,
      {bool isCurrency = true, bool isBold = false, Color? color}) {
    final valueStyle = TextStyle(
      fontSize: 16,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
      color: color ?? Colors.black,
    );
    final labelStyle = TextStyle(
      fontSize: 16,
      color: Colors.grey.shade700,
      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    );

    // [SỬA ĐỔI] Hiển thị "0 đ" nếu giá trị là 0
    String displayValue;
    if (value.abs() < 0.001) {
      displayValue = isCurrency ? '0 đ' : '0'; // <-- FIX
    } else {
      displayValue = isCurrency ? '${formatNumber(value)} đ' : formatNumber(value);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: labelStyle),
          ),
          const SizedBox(width: 16),
          Text(
            displayValue, // <-- Dùng giá trị đã được làm sạch
            style: valueStyle,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

class _EndOfDayReportDialog extends StatefulWidget {
  final Map<String, dynamic>? totalReportData;
  final List<Map<String, dynamic>>? shiftReportsData;
  final UserModel currentUser;
  final TimeOfDay reportCutoffTime;
  final DateTime effectiveNow;

  const _EndOfDayReportDialog({
    this.totalReportData,
    this.shiftReportsData,
    required this.currentUser,
    required this.reportCutoffTime,
    required this.effectiveNow,
  });

  @override
  State<_EndOfDayReportDialog> createState() => _EndOfDayReportDialogState();
}

class _EndOfDayReportDialogState extends State<_EndOfDayReportDialog> {
  ImageProvider? _imageProvider;
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  Map<String, String>? _storeInfo;
  final ScreenshotController _screenshotController = ScreenshotController();
  bool get _isDesktop =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      _storeInfo = await FirestoreService().getStoreDetails(widget.currentUser.storeId);
      if (_storeInfo == null) {
        throw Exception('Không thể tải thông tin cửa hàng.');
      }

      Map<String, dynamic> dataToPrint;
      List<Map<String, dynamic>> shiftDataList = [];

      if (widget.totalReportData != null) {
        // IN BÁO CÁO TỔNG
        dataToPrint = widget.totalReportData!;
        shiftDataList = widget.shiftReportsData ?? [];
      } else if (widget.shiftReportsData != null && widget.shiftReportsData!.isNotEmpty) {
        // IN BÁO CÁO CA
        dataToPrint = widget.shiftReportsData!.first;
        // Khi in ca lẻ, không cần danh sách ca con
        shiftDataList = [];
      } else {
        dataToPrint = {};
      }

      final widgetToCapture = Container(
        color: Colors.white,
        child: EndOfDayReportWidget(
          storeInfo: _storeInfo!,
          totalReportData: dataToPrint, // Truyền data đã chọn
          shiftReportsData: shiftDataList,
          userName: widget.currentUser.name ?? 'Unknown',
        ),
      );

      // 3. Chụp ảnh Widget
      final Uint8List imageBytes = await _screenshotController.captureFromWidget(
        widgetToCapture,
        delay: const Duration(milliseconds: 100),
        pixelRatio: 2.5,
        targetSize: const Size(550, double.infinity),
      );

      // 4. Tạo PDF bao bọc ảnh (để dùng cho tính năng Lưu PDF / Chia sẻ)
      final pdf = pw.Document();
      final image = pw.MemoryImage(imageBytes);

      pdf.addPage(pw.Page(
          pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity, marginAll: 0),
          build: (ctx) {
            return pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain));
          }
      ));
      final pdfData = await pdf.save();

      if (mounted) {
        setState(() {
          _pdfBytes = pdfData;
          _imageProvider = MemoryImage(imageBytes); // Hiển thị ảnh preview ngay
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        debugPrint("Lỗi tạo ảnh báo cáo: $e");
        ToastService().show(message: "Lỗi tạo ảnh báo cáo: $e", type: ToastType.error);
      }
    }
  }

  Future<void> _printReport() async {
    if (_isLoading || _storeInfo == null) return;
    try {
      final data = {
        'storeId': widget.currentUser.storeId,
        'storeInfo': _storeInfo,
        'userName': widget.currentUser.name ?? 'Không rõ',
        'totalReportData': widget.totalReportData,
        'shiftReportsData': widget.shiftReportsData,
      };

      PrintQueueService().addJob(PrintJobType.endOfDayReport, data);

      ToastService().show(message: "Đã gửi lệnh in", type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi khi in: $e", type: ToastType.error);
    }
  }

  String _getFileName() {
    final dataForTitle =
        widget.totalReportData ?? widget.shiftReportsData?.first;
    if (dataForTitle == null) {
      return 'BaoCao_${DateFormat('ddMMyy').format(DateTime.now())}.pdf';
    }

    final title = (dataForTitle['reportTitle'] as String?) ?? 'BaoCao';
    final bool isShiftReport = widget.totalReportData == null &&
        widget.shiftReportsData != null;

    final startDateString = dataForTitle['startDate'] ?? dataForTitle['calculatedStartTime'];
    final DateTime startDate = startDateString != null ? (DateTime.tryParse(startDateString) ?? DateTime.now()) : DateTime.now();

    if (isShiftReport || title.contains('CA')) {
      final employeeName =
          (dataForTitle['employeeName'] as String?) ?? 'NhanVien';
      final datePart = DateFormat('ddMMyy').format(startDate);
      return 'BaoCaoCa_${employeeName.replaceAll(' ', '')}_$datePart.pdf';
    } else {
      final datePart = DateFormat('ddMMyy').format(startDate);
      return 'BaoCao_TongKet_$datePart.pdf';
    }
  }

  Future<void> _shareReceipt() async {
    if (_pdfBytes == null) return;
    await Printing.sharePdf(bytes: _pdfBytes!, filename: _getFileName());
  }

  Future<void> _savePdf() async {
    if (_pdfBytes == null) return;
    try {
      final String? filePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu Báo cáo PDF',
        fileName: _getFileName(),
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (filePath != null) {
        final file = File(filePath);
        await file.writeAsBytes(_pdfBytes!);
        ToastService().show(
            message: "Đã lưu báo cáo thành công!", type: ToastType.success);
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi lưu file: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding:
      const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 380,
          maxHeight: screenHeight * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.0)),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _imageProvider == null
                    ? const Center(child: Text("Lỗi tạo ảnh báo cáo."))
                    : SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 10),
                    child: Image(image: _imageProvider!),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: 380,
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.0)),
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(
                    onPressed: _pdfBytes == null ? null : _printReport,
                    child: const Text("In báo cáo"),
                  ),
                  TextButton(
                    onPressed: _pdfBytes == null
                        ? null
                        : (_isDesktop ? _savePdf : _shareReceipt),
                    child: Text(_isDesktop ? "Lưu PDF" : "Chia sẻ"),
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

class ThousandsInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {

    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    String newText = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (newText.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final number = int.parse(newText);
    final formatter = NumberFormat.decimalPattern('vi_VN');
    final String newString = formatter.format(number);

    return TextEditingValue(
      text: newString,
      selection: TextSelection.collapsed(offset: newString.length),
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