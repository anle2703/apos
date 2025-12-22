// File: lib/screens/reports/tabs/retail_sales_ledger_tab.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import '../../../models/user_model.dart';
import '../../../models/bill_model.dart';
import '../../../theme/number_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../services/toast_service.dart';
import '../../../services/settings_service.dart';
import '../../../models/store_settings_model.dart';
import '../../../services/firestore_service.dart';
import '../../../bills/bill_history_screen.dart';
import '../../tax_management_screen.dart' show kAllTaxRates;

class LedgerItemRow {
  final String billId;
  final DateTime date;
  final String billCode;
  final String productName;
  final String unit;
  final double quantity;
  final double price;
  final double subtotal;
  final String taxGroupName;
  final String? note;
  final double taxAmount;

  LedgerItemRow({
    required this.billId,
    required this.date,
    required this.billCode,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.taxGroupName,
    this.note,
    required this.taxAmount,
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

class RetailSalesLedgerTab extends StatefulWidget {
  final UserModel currentUser;
  final Function(bool) onLoadingChanged;

  const RetailSalesLedgerTab({
    super.key,
    required this.currentUser,
    required this.onLoadingChanged,
  });

  @override
  State<RetailSalesLedgerTab> createState() => RetailSalesLedgerTabState();
}

class RetailSalesLedgerTabState extends State<RetailSalesLedgerTab>
    with AutomaticKeepAliveClientMixin {
  TimeRange _selectedRange = TimeRange.today;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;

  // Dữ liệu báo cáo
  final List<LedgerItemRow> _allLedgerItems = [];
  List<LedgerItemRow> _filteredLedgerItems = [];
  List<String> _taxGroupOptions = ['Tất cả'];
  String? _filterTaxGroup;

  // Dữ liệu cài đặt thuế
  final Map<String, String> _productTaxRateMap = {};
  final Map<String, String> _taxKeyToNameMap = {};

  // Bộ lọc
  final TextEditingController _searchController = TextEditingController();
  String _calcMethod = 'direct';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetchData();
  }

  @override
  void dispose() {
    _settingsSub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void exportReport() {
    if (_filteredLedgerItems.isEmpty) {
      ToastService()
          .show(message: "Không có dữ liệu để xuất.", type: ToastType.warning);
      return;
    }
    _exportToExcel();
  }

  void showFilterModal() {
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;
    String? tempFilterTaxGroup = _filterTaxGroup;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Hàng hóa bán ra',
                      style: Theme.of(context).textTheme.headlineMedium),
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Tìm theo tên hàng hóa, mã HĐ',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                    ),
                    onChanged: (value) => setModalState(() {}),
                  ),
                  // Lọc thời gian
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
                        _selectCustomDateTimeRange().then((pickedRange) {
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
                          final start =
                              DateFormat('dd/MM/yy').format(tempStartDate!);
                          final end =
                              DateFormat('dd/MM/yy').format(tempEndDate!);
                          return Text('$start - $end',
                              overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getTimeRangeText(range));
                      }).toList();
                    },
                  ),
                  AppDropdown<String>(
                    labelText: 'Nhóm Thuế',
                    prefixIcon: Icons.percent,
                    value: tempFilterTaxGroup ?? 'Tất cả',
                    items: _taxGroupOptions.map((group) {
                      return DropdownMenuItem<String>(
                        value: group,
                        child: Text(group),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setModalState(() {
                        tempFilterTaxGroup = val;
                      });
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRange = TimeRange.today;
                            _searchController.clear();
                            // Reset thuế
                            _filterTaxGroup = null;
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
                                      (_startDate != tempStartDate ||
                                          _endDate != tempEndDate));

                          setState(() {
                            _selectedRange = tempSelectedRange;
                            _startDate = tempStartDate;
                            _endDate = tempEndDate;
                            // Cập nhật biến lọc thuế
                            _filterTaxGroup = tempFilterTaxGroup;
                          });

                          if (dateChanged) {
                            _updateDateRangeAndFetch();
                          } else {
                            _applyFilters();
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

  void _setLoading(bool loading) {
    if (!mounted) return;
    setState(() {
      _isLoading = loading;
    });
    widget.onLoadingChanged(loading);
  }

  Future<void> _loadSettingsAndFetchData() async {
    final settingsService = SettingsService();
    final firestoreService = FirestoreService();
    final settingsId = widget.currentUser.storeId;
    bool isFirstLoad = true;

    try {
      final settings = await firestoreService.getStoreTaxSettings(widget.currentUser.storeId);
      if (settings != null) {
        // 1. Lấy phương pháp tính
        _calcMethod = settings['calcMethod'] ?? 'direct';

        // 2. Load Map sản phẩm (Key đúng là taxAssignmentMap)
        final rawMap = settings['taxAssignmentMap'] as Map<String, dynamic>? ?? {};
        _productTaxRateMap.clear();
        rawMap.forEach((taxKey, productIds) {
          if (productIds is List) {
            for (final productId in productIds) {
              _productTaxRateMap[productId as String] = taxKey;
            }
          }
        });

        // 3. Tạo Map tên hiển thị
        _taxKeyToNameMap.clear();
        // Load cả 2 bảng để đảm bảo hiển thị đúng dù lịch sử có lẫn lộn
        kAllTaxRates.forEach((key, value) {
          _taxKeyToNameMap[key] = value['name'] as String;
        });
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

        setState(() {
          _reportCutoffTime = newCutoff;
        });

        if (isFirstLoad || cutoffChanged) {
          _updateDateRangeAndFetch();
          isFirstLoad = false;
        }
      }, onError: (e) {
        debugPrint("Lỗi watchStoreSettings: $e");
        if (mounted) {
          _setLoading(false);
          ToastService()
              .show(message: "Lỗi tải cài đặt: $e", type: ToastType.error);
        }
      });
    } catch (e) {
      debugPrint("Lỗi tải cài đặt thuế: $e");
      if (mounted) {
        _setLoading(false);
        ToastService()
            .show(message: "Lỗi tải cài đặt thuế: $e", type: ToastType.error);
      }
    }
  }

  void _updateDateRangeAndFetch() {
    if (_selectedRange == TimeRange.custom) {
      if (_startDate == null || _endDate == null) {
        _selectedRange = TimeRange.today; // Mặc định nếu custom mà thiếu ngày
      }
    }

    if (_selectedRange != TimeRange.custom) {
      final now = DateTime.now();
      final cutoff = _reportCutoffTime;
      DateTime startOfReportDay(DateTime date) {
        return DateTime(
            date.year, date.month, date.day, cutoff.hour, cutoff.minute);
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
          _startDate = startOfReportDay(effectiveDate);
          _endDate = endOfReportDay(effectiveDate);
          break;
        case TimeRange.yesterday:
          final yesterday = effectiveDate.subtract(const Duration(days: 1));
          _startDate = startOfReportDay(yesterday);
          _endDate = endOfReportDay(yesterday);
          break;
        case TimeRange.thisWeek:
          final startOfWeek = effectiveDate.subtract(
              Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(
              Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _startDate = startOfReportDay(startOfWeek);
          _endDate = endOfReportDay(endOfWeek);
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay =
              effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay =
              endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          break;
        case TimeRange.thisMonth:
          final startOfMonth =
              DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth =
              DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth =
              DateTime(effectiveDate.year, effectiveDate.month, 0);
          final startOfLastMonth =
              DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
          _startDate = startOfReportDay(startOfLastMonth);
          _endDate = endOfReportDay(endOfLastMonth);
          break;
        case TimeRange.custom:
          // Đã được xử lý ở trên
          break;
      }
    }

    if (_startDate != null && _endDate != null) {
      _fetchLedgerData();
    }
  }

  Future<void> _fetchLedgerData() async {
    if (_startDate == null || _endDate == null) return;
    _setLoading(true);

    _allLedgerItems.clear();
    final db = FirebaseFirestore.instance;
    final storeId = widget.currentUser.storeId;

    final Set<String> uniqueTaxGroups = {};
    final String defaultTaxKey = (_calcMethod == 'deduction') ? 'VAT_0' : 'HKD_0';
    try {
      final billsSnapshot = await db
          .collection('bills')
          .where('storeId', isEqualTo: storeId)
          .where('status', isEqualTo: 'completed')
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .orderBy('createdAt', descending: true)
          .get();

      for (final doc in billsSnapshot.docs) {
        final bill = BillModel.fromFirestore(doc);
        final items = List<Map<String, dynamic>>.from(bill.items);

        for (final item in items) {
          final productData = item['product'] as Map<String, dynamic>? ?? {};
          final productId = productData['id'] as String?;

          final String productName = (item['productName'] as String?) ??
              (productData['productName'] as String?) ??
              'N/A';

          final String unit = (item['selectedUnit'] as String?) ??
              (item['unit'] as String?) ??
              (productData['unit'] as String?) ??
              'Đơn vị';

          final String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;

          // Lấy tên hiển thị (VD: 10% hoặc 1.5%)
          String fullTaxName = _taxKeyToNameMap[taxKey] ?? '0%';
          final String shortTaxName = fullTaxName.split('(').first.trim();
          uniqueTaxGroups.add(shortTaxName);

          // --- BẮT ĐẦU SỬA ĐOẠN NÀY ---
          final double quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
          final double price = (item['price'] as num?)?.toDouble() ?? 0.0;
          final double itemSubtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;

          // 1. Lấy tiền thuế đã lưu
          double itemTaxVal = (item['taxAmount'] as num?)?.toDouble() ?? 0.0;

          // 2. Fallback: Nếu bill cũ chưa lưu taxAmount (=0) thì tự tính lại để báo cáo không bị số 0
          if (itemTaxVal == 0 && itemSubtotal > 0) {
            final double rate = kAllTaxRates[taxKey]?['rate'] ?? 0.0;
            if (rate > 0) {
              itemTaxVal = itemSubtotal * rate;
            }
          }

          final row = LedgerItemRow(
            billId: doc.id,
            date: bill.createdAt,
            billCode: bill.billCode,
            productName: productName,
            unit: unit,
            quantity: quantity,
            price: price,
            subtotal: itemSubtotal, // Cột Doanh thu (chưa thuế)
            taxAmount: itemTaxVal,  // Cột Tiền thuế
            taxGroupName: shortTaxName, // % Thuế
            note: (item['note'] as String?) ?? '',
          );
          _allLedgerItems.add(row);
        }
      }

      // Cập nhật danh sách tùy chọn lọc
      final sortedGroups = uniqueTaxGroups.toList()..sort();
      _taxGroupOptions = ['Tất cả', ...sortedGroups];

      _applyFilters();
    } catch (e) {
      debugPrint("Lỗi tải Bảng Kê Bán Lẻ: $e");
      if (mounted) {
        ToastService()
            .show(message: "Lỗi tải báo cáo: $e", type: ToastType.error);
      }
    } finally {
      _setLoading(false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();

    _filteredLedgerItems = _allLedgerItems.where((item) {
      // Lọc tìm kiếm
      final bool matchesQuery = query.isEmpty ||
          item.productName.toLowerCase().contains(query) ||
          item.billCode.toLowerCase().contains(query);

      // Lọc nhóm thuế
      final bool matchesTax = _filterTaxGroup == null ||
          _filterTaxGroup == 'Tất cả' ||
          item.taxGroupName == _filterTaxGroup;

      return matchesQuery && matchesTax;
    }).toList();

    if (mounted) setState(() {});
  }

  Future<void> _openBillDetail(String billId) async {
    try {
      final db = FirebaseFirestore.instance;
      final billDoc = await db.collection('bills').doc(billId).get();
      final storeInfo =
          await FirestoreService().getStoreDetails(widget.currentUser.storeId);

      if (billDoc.exists && storeInfo != null && mounted) {
        final bill = BillModel.fromFirestore(billDoc);

        // Mở dialog hóa đơn (có nút in/xem PDF)
        showDialog(
          context: context,
          builder: (_) => BillReceiptDialog(
            bill: bill,
            currentUser: widget.currentUser,
            storeInfo: storeInfo,
          ),
        );
      } else {
        ToastService().show(
            message: "Không tìm thấy dữ liệu hóa đơn.", type: ToastType.error);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi mở hóa đơn: $e", type: ToastType.error);
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];

      final String reportDate =
          DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
      final String dateRange =
          'Từ: ${DateFormat('dd/MM/yyyy HH:mm').format(_startDate!)} - Đến: ${DateFormat('dd/MM/yyyy HH:mm').format(_endDate!)}';

      final CellStyle titleStyle = CellStyle(
        bold: true,
        fontSize: 18,
        horizontalAlign: HorizontalAlign.Center,
      );

      sheet.appendRow([TextCellValue('BẢNG KÊ BÁN LẺ HÀNG HÓA, DỊCH VỤ')]);
      sheet.cell(CellIndex.indexByString('A1')).cellStyle = titleStyle;
      sheet.merge(CellIndex.indexByString('A1'), CellIndex.indexByString('H1'));

      sheet.appendRow([TextCellValue(dateRange)]);
      sheet.merge(CellIndex.indexByString('A2'), CellIndex.indexByString('H2'));

      sheet.appendRow([TextCellValue('Ngày tạo: $reportDate')]);
      sheet.merge(CellIndex.indexByString('A3'), CellIndex.indexByString('H3'));

      sheet.appendRow([]); // Dòng trống

      final headers = [
        'Ngày HĐ',
        'Mã HĐ',
        'Tên Hàng Hóa, Dịch Vụ',
        'ĐVT',
        'Số Lượng',
        'Đơn Giá',
        'Thành Tiền (Doanh Thu)',
        'Nhóm Thuế',
        'Ghi Chú'
      ];
      sheet.appendRow(headers.map((h) => TextCellValue(h)).toList());

      for (final item in _filteredLedgerItems) {
        sheet.appendRow([
          TextCellValue(DateFormat('dd/MM/yyyy HH:mm').format(item.date)),
          TextCellValue(item.billCode),
          TextCellValue(item.productName),
          TextCellValue(item.unit),
          DoubleCellValue(item.quantity),
          DoubleCellValue(item.price),
          DoubleCellValue(item.subtotal),
          TextCellValue(item.taxGroupName),
          TextCellValue(item.note ?? ''),
        ]);
      }

      final String fileName =
          'BangKeBanLe_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final fileBytes = excel.save();

      if (fileBytes != null) {
        final String? result = await FilePicker.platform.saveFile(
          dialogTitle: 'Lưu file Excel',
          fileName: fileName,
          bytes: Uint8List.fromList(fileBytes),
          type: FileType.custom,
          allowedExtensions: ['xlsx'],
        );
        if (result != null) {
          ToastService().show(
              message: "Đã lưu file thành công!", type: ToastType.success);
        }
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi xuất Excel: $e", type: ToastType.error);
    }
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

  Future<List<DateTime>?> _selectCustomDateTimeRange() async {
    if (!mounted) return null;
    final pickedRange = await showOmniDateTimeRangePicker(
      context: context,
      startInitialDate: _startDate ?? DateTime.now(),
      endInitialDate: _endDate,
      startFirstDate: DateTime(2020),
      startLastDate: DateTime.now().add(const Duration(days: 365)),
      endFirstDate: _startDate ?? DateTime(2020),
      endLastDate: DateTime.now().add(const Duration(days: 365)),
      is24HourMode: true,
      isShowSeconds: false,
      type: OmniDateTimePickerType.dateAndTime,
    );

    if (pickedRange != null && pickedRange.length == 2) {
      setState(() {
        _startDate = pickedRange[0];
        _endDate = pickedRange[1];
        _selectedRange = TimeRange.custom;
      });
      return pickedRange;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final bool isDesktop = MediaQuery.of(context).size.width > 850;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          // CHỈ HIỆN HEADER BẢNG TRÊN DESKTOP
          if (isDesktop)
            SliverPersistentHeader(
              pinned: true,
              delegate: _SliverHeaderDelegate(
                child: _buildHeaderRow(),
                minHeight: 55.0,
                maxHeight: 55.0,
              ),
            ),

          // DANH SÁCH
          if (_filteredLedgerItems.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Text(
                  'Không có dữ liệu cho khoảng thời gian này.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                    (context, index) {
                  final item = _filteredLedgerItems[index];
                  // Truyền biến isDesktop vào hàm render
                  return _buildDataRow(item, index, isDesktop);
                },
                childCount: _filteredLedgerItems.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      color: AppTheme.scaffoldBackgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        children: [
          // Tổng Flex = 13 (2+3+2+2+2+2)
          _buildHeaderCell('Thời gian', 2),
          _buildHeaderCell('Sản phẩm', 3), // Giảm flex xuống 3 để nhường chỗ
          _buildHeaderCell('SL x Giá', 2, align: TextAlign.right), // Thêm cột này
          _buildHeaderCell('Doanh thu', 2, align: TextAlign.right),
          _buildHeaderCell('Tiền thuế', 2, align: TextAlign.right),
          _buildHeaderCell('Tổng cộng', 2, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex, {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black87, // Màu đậm hơn chút cho dễ đọc
            fontSize: 16), // <-- TĂNG SIZE 13 -> 15
        textAlign: align,
      ),
    );
  }

  Widget _buildDataRow(LedgerItemRow item, int index, bool isDesktop) {
    final bool isEven = index % 2 == 0;
    final rowColor = isEven ? Colors.white : AppTheme.scaffoldBackgroundColor;

    if (!isDesktop) {
      return Card(
        elevation: 2, // Tạo bóng đổ nhẹ
        margin: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0), // Tách rời các sản phẩm
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HÀNG 1: Tên (Trái) --- Thời gian & Mã Bill (Phải) ---
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tên Hàng Hóa
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.productName} (${item.unit})',
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                        if (item.note != null && item.note!.isNotEmpty)
                          Text(
                            "(${item.note})",
                            style: const TextStyle(
                                fontSize: 14,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Thời gian & Mã Bill
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Thời gian: Có năm, chữ to hơn (13 -> 15)
                        Text(
                          DateFormat('HH:mm dd/MM/yyyy').format(item.date),
                          style: const TextStyle(fontSize: 14, color: Colors.black54),
                          textAlign: TextAlign.right,
                        ),
                        const SizedBox(height: 4),
                        InkWell(
                          onTap: () => _openBillDetail(item.billId),
                          child: Text(
                            item.billCode,
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppTheme.primaryColor,
                              decorationColor: AppTheme.primaryColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),
              // Divider ngăn cách Tên và Số liệu
              Divider(height: 1, thickness: 0.5, color: Colors.grey.shade300),
              const SizedBox(height: 8),

              // --- HÀNG 2: SL x Giá | Thành tiền | Thuế (Cùng 1 dòng) ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 1. SL x Đơn giá
                  Expanded(
                    flex: 4,
                    child: Text(
                      '${formatNumber(item.quantity)} x ${formatNumber(item.price)}',
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                    ),
                  ),

                  // 2. Thành tiền (Màu bình thường)
                  Expanded(
                    flex: 3,
                    child: Text(
                      formatNumber(item.subtotal),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87),
                      textAlign: TextAlign.right,
                    ),
                  ),

                  // 3. Nhóm thuế
                  Expanded(
                    flex: 2,
                    child: Text(
                      item.taxGroupName,
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      );
    }

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Thời gian (Flex 2)
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd/MM/yy HH:mm').format(item.date), style: const TextStyle(fontSize: 14, color: Colors.black54)),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _openBillDetail(item.billId),
                  child: Text(item.billCode, style: const TextStyle(fontSize: 14, color: AppTheme.primaryColor, decorationColor: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // 2. Sản phẩm (Flex 3)
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                // --- SỬA LỖI: Không hiện ĐVT nếu trống ---
                  item.unit.isNotEmpty && item.unit != 'null'
                      ? '${item.productName} (${item.unit})'
                      : item.productName,
                  // -----------------------------------------
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)
              ),
            ),
          ),

          // 3. SL x Giá (Flex 2)
          Expanded(
            flex: 2,
            child: Text(
              '${formatNumber(item.quantity)} x ${formatNumber(item.price)}',
              style: const TextStyle(fontSize: 14, color: Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),

          // 4. Doanh thu (Flex 2) - BỎ IN ĐẬM
          Expanded(
            flex: 2,
            child: Text(
              formatNumber(item.subtotal),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal, // <-- Sửa thành normal
                  color: Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),

          // 5. Tiền thuế (Flex 2) - BỎ IN ĐẬM, SỬA FORMAT %
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatNumber(item.taxAmount),
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.normal, // <-- Sửa thành normal
                      color: Colors.black87), // <-- Đổi màu đen (hoặc giữ đỏ nếu muốn nhấn mạnh)
                  textAlign: TextAlign.right,
                ),
                  Text(
                      item.taxGroupName.replaceAll('.', ','),
                      // ------------------------------------------------
                      style: const TextStyle(
                          fontSize: 14, // <-- Tăng size bằng với SL/Giá (15)
                          color: Colors.black54
                      ),
                      textAlign: TextAlign.right
                  ),
              ],
            ),
          ),

          // 6. Tổng cộng (Flex 2) - ĐỔI MÀU ĐEN
          Expanded(
            flex: 2,
            child: Text(
              formatNumber(item.subtotal + item.taxAmount),
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87 // <-- Đổi từ PrimaryColor sang Đen
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _SliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double minHeight;
  final double maxHeight;

  _SliverHeaderDelegate({
    required this.child,
    required this.minHeight,
    required this.maxHeight,
  });

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          child,
          Container(height: 1.0, color: Colors.grey.shade300) // Dòng kẻ
        ],
      ),
    );
  }

  @override
  double get minExtent => minHeight;

  @override
  double get maxExtent => maxHeight;

  @override
  bool shouldRebuild(covariant _SliverHeaderDelegate oldDelegate) {
    return child != oldDelegate.child ||
        minHeight != oldDelegate.minHeight ||
        maxHeight != oldDelegate.maxHeight;
  }
}
