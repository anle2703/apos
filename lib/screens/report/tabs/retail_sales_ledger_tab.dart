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

// Import hằng số thuế từ màn hình cài đặt
import '../../tax_management_screen.dart' show kHkdGopRates, kVatRates;

/// Model dữ liệu cho một dòng trong bảng kê
class LedgerItemRow {
  final DateTime date;
  final String billCode;
  final String productName;
  final String unit;
  final double quantity;
  final double price;
  final double subtotal; // Thành tiền (Doanh thu)
  final String taxGroupName; // Nhóm thuế suất
  final String? note;

  LedgerItemRow({
    required this.date,
    required this.billCode,
    required this.productName,
    required this.unit,
    required this.quantity,
    required this.price,
    required this.subtotal,
    required this.taxGroupName,
    this.note,
  });
}

// Enum TimeRange (sao chép từ các file báo cáo khác)
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

class RetailSalesLedgerTabState extends State<RetailSalesLedgerTab> with AutomaticKeepAliveClientMixin {

  TimeRange _selectedRange = TimeRange.today;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;

  // Dữ liệu báo cáo
  final List<LedgerItemRow> _allLedgerItems = [];
  List<LedgerItemRow> _filteredLedgerItems = [];

  // Dữ liệu cài đặt thuế
  final Map<String, String> _productTaxRateMap = {};
  final Map<String, String> _taxKeyToNameMap = {};

  // Bộ lọc
  final TextEditingController _searchController = TextEditingController();

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

  /// Public method cho nút Export của parent widget
  void exportReport() {
    if (_filteredLedgerItems.isEmpty) {
      ToastService().show(message: "Không có dữ liệu để xuất.", type: ToastType.warning);
      return;
    }
    _exportToExcel();
  }

  /// Public method cho nút Filter của parent widget
  void showFilterModal() {
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;

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
                  Text('Lọc Bảng Kê Bán Lẻ', style: Theme.of(context).textTheme.headlineMedium),

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
                        if (range == TimeRange.custom && tempSelectedRange == TimeRange.custom && tempStartDate != null && tempEndDate != null) {
                          final start = DateFormat('dd/MM/yy').format(tempStartDate!);
                          final end = DateFormat('dd/MM/yy').format(tempEndDate!);
                          return Text('$start - $end', overflow: TextOverflow.ellipsis);
                        }
                        return Text(_getTimeRangeText(range));
                      }).toList();
                    },
                  ),

                  // Lọc tìm kiếm
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

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRange = TimeRange.today;
                            _searchController.clear();
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
                              (_selectedRange == TimeRange.custom && (_startDate != tempStartDate || _endDate != tempEndDate));

                          setState(() {
                            _selectedRange = tempSelectedRange;
                            _startDate = tempStartDate;
                            _endDate = tempEndDate;
                          });

                          if (dateChanged) {
                            _updateDateRangeAndFetch();
                          } else {
                            _applyFilters(); // Chỉ lọc tìm kiếm
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
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    bool isFirstLoad = true;

    try {
      // Tải cài đặt thuế (chỉ 1 lần)
      final settings = await firestoreService.getStoreTaxSettings(widget.currentUser.storeId);
      if (settings != null) {
        final rawMap = settings['taxRateProductMap'] as Map<String, dynamic>? ?? {};
        _productTaxRateMap.clear();
        rawMap.forEach((taxKey, productIds) {
          if (productIds is List) {
            for (final productId in productIds) {
              _productTaxRateMap[productId as String] = taxKey;
            }
          }
        });

        _taxKeyToNameMap.clear();
        kHkdGopRates.forEach((key, value) {
          _taxKeyToNameMap[key] = value['name'] as String;
        });
        kVatRates.forEach((key, value) {
          _taxKeyToNameMap[key] = value['name'] as String;
        });
      }

      // Theo dõi giờ chốt sổ
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

        if (isFirstLoad || cutoffChanged) {
          _updateDateRangeAndFetch();
          isFirstLoad = false;
        }
      }, onError: (e) {
        debugPrint("Lỗi watchStoreSettings: $e");
        if (mounted) {
          _setLoading(false);
          ToastService().show(message: "Lỗi tải cài đặt: $e", type: ToastType.error);
        }
      });
    } catch (e) {
      debugPrint("Lỗi tải cài đặt thuế: $e");
      if (mounted) {
        _setLoading(false);
        ToastService().show(message: "Lỗi tải cài đặt thuế: $e", type: ToastType.error);
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
        return DateTime(date.year, date.month, date.day, cutoff.hour, cutoff.minute);
      }
      DateTime endOfReportDay(DateTime date) {
        return startOfReportDay(date).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
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
          final startOfMonth = DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth = DateTime(effectiveDate.year, effectiveDate.month, 0);
          final startOfLastMonth = DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
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
    final String defaultTaxKey = kVatRates.keys.firstWhere((k) => k.contains('0'), orElse: () => 'VAT_0');

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

          final String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;
          final String taxGroupName = _taxKeyToNameMap[taxKey] ?? '0%';

          final row = LedgerItemRow(
            date: bill.createdAt,
            billCode: bill.billCode,
            productName: (item['productName'] as String?) ?? 'N/A',
            unit: (item['selectedUnit'] as String?) ?? 'N/A',
            quantity: (item['quantity'] as num?)?.toDouble() ?? 0.0,
            price: (item['price'] as num?)?.toDouble() ?? 0.0,
            subtotal: (item['subtotal'] as num?)?.toDouble() ?? 0.0,
            taxGroupName: taxGroupName,
            note: (item['note'] as String?) ?? '',
          );
          _allLedgerItems.add(row);
        }
      }
      _applyFilters();
    } catch (e) {
      debugPrint("Lỗi tải Bảng Kê Bán Lẻ: $e");
      if (mounted) {
        ToastService().show(message: "Lỗi tải báo cáo: $e", type: ToastType.error);
      }
    } finally {
      _setLoading(false);
    }
  }

  void _applyFilters() {
    final query = _searchController.text.toLowerCase();

    _filteredLedgerItems = _allLedgerItems.where((item) {
      if (query.isEmpty) return true;

      return item.productName.toLowerCase().contains(query) ||
          item.billCode.toLowerCase().contains(query);

    }).toList();

    if(mounted) setState(() {});
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];

      final String reportDate = DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
      final String dateRange = 'Từ: ${DateFormat('dd/MM/yyyy HH:mm').format(_startDate!)} - Đến: ${DateFormat('dd/MM/yyyy HH:mm').format(_endDate!)}';

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

      final String fileName = 'BangKeBanLe_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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
          ToastService().show(message: "Đã lưu file thành công!", type: ToastType.success);
        }
      }
    } catch (e) {
      ToastService().show(message: "Lỗi khi xuất Excel: $e", type: ToastType.error);
    }
  }

  // --- Các hàm Helper cho Bộ lọc Thời gian ---

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

  // --- Giao diện (Build) ---

  @override
  Widget build(BuildContext context) {
    // Phải gọi super.build(context) khi dùng AutomaticKeepAliveClientMixin
    super.build(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
        slivers: [
          // Header dính
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverHeaderDelegate(
              child: _buildHeaderRow(),
              minHeight: 40.0,
              maxHeight: 40.0,
            ),
          ),

          // Danh sách
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
                  return _buildDataRow(item, index);
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
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          _buildHeaderCell('Ngày / Mã HĐ', 3),
          _buildHeaderCell('Hàng Hóa / ĐVT', 4),
          _buildHeaderCell('SL / Đ.Giá', 2, align: TextAlign.right),
          _buildHeaderCell('Thành Tiền', 3, align: TextAlign.right),
          _buildHeaderCell('Nhóm Thuế', 3, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildDataRow(LedgerItemRow item, int index) {
    final bool isEven = index % 2 == 0;
    final rowColor = isEven ? Colors.white : AppTheme.scaffoldBackgroundColor;

    return Container(
      color: rowColor,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ngày / Mã HĐ
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('dd/MM/yy HH:mm').format(item.date),
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 2),
                Text(
                  item.billCode,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
              ],
            ),
          ),

          // Hàng Hóa / ĐVT
          Expanded(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  if (item.note != null && item.note!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Text(
                        "(${item.note})",
                        style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // SL / Đ.Giá
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${formatNumber(item.quantity)} ${item.unit}',
                    style: const TextStyle(fontSize: 14, color: Colors.black),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${formatNumber(item.price)}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),

          // Thành Tiền
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Text(
                formatNumber(item.subtotal),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
                textAlign: TextAlign.right,
              ),
            ),
          ),

          // Nhóm Thuế
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Text(
                item.taxGroupName,
                style: const TextStyle(fontSize: 14, color: Colors.black54),
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(String text, int flex, {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54, fontSize: 13),
        textAlign: align,
      ),
    );
  }
}

// Helper class cho Header dính (Sticky Header)
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
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