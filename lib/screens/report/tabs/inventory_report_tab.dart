// File: lib/screens/reports/tabs/inventory_report_tab.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import '../../../models/user_model.dart';
import '../../../bills/bill_history_screen.dart';
import '../../../models/product_model.dart';
import '../../../models/bill_model.dart';
import '../../../theme/number_utils.dart';
import '../../../theme/app_theme.dart';
import '../../../widgets/app_dropdown.dart';
import '../../../services/toast_service.dart';
import '../../../products/order/create_purchase_order_screen.dart';
import '../../../models/purchase_order_model.dart';
import 'package:collection/collection.dart';
import '../../../services/firestore_service.dart';
import '../../../products/barcode_scanner_screen.dart';
import 'package:flutter/services.dart';
import 'package:excel/excel.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:file_picker/file_picker.dart';
import 'dart:async';
import '../../../services/settings_service.dart';
import '../../../models/store_settings_model.dart';

class InventoryTransaction {
  final String docId;
  final String type;
  final DateTime date;
  final double quantity;
  final String code;
  final String reference;

  InventoryTransaction({
    required this.docId,
    required this.type,
    required this.date,
    required this.quantity,
    required this.code,
    required this.reference,
  });
}

class ProductUnitReportData {
  final ProductModel product;
  final String unitName;
  double openingStock;
  double importStock;
  double exportStock;
  double closingStock;

  String get uniqueKey => '${product.id}_$unitName';

  ProductUnitReportData({
    required this.product,
    required this.unitName,
    this.openingStock = 0,
    this.importStock = 0,
    this.exportStock = 0,
    this.closingStock = 0,
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

class InventoryReportTab extends StatefulWidget {
  final UserModel currentUser;

  const InventoryReportTab({super.key, required this.currentUser});

  @override
  State<InventoryReportTab> createState() => InventoryReportTabState();
}

class InventoryReportTabState extends State<InventoryReportTab> {
  TimeRange _selectedRange = TimeRange.today;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isLoading = true;

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;
  bool get areFiltersLoading => _areFiltersLoading;
  final Map<String, ProductUnitReportData> _reportData = {};
  List<ProductUnitReportData> _filteredReportData = [];
  final TextEditingController _searchController = TextEditingController();

  List<String> _productGroupOptions = [];
  String? _selectedProductGroup;
  bool _areFiltersLoading = true;

  String? _expandedProductUnitKey;
  bool _isDetailLoading = false;
  List<InventoryTransaction> _transactions = [];
  int? _sortColumnIndex = 6;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _loadSettingsAndFetchData();
    _loadFilterOptions();
  }

  void exportReport() {
    if (_filteredReportData.isEmpty) {
      ToastService()
          .show(message: "Không có dữ liệu để xuất.", type: ToastType.warning);
      return;
    }
    _showExportOptionsDialog();
  }

  void _sortReportList() {
    _filteredReportData.sort((a, b) {
      int compare;
      switch (_sortColumnIndex) {
        case 3: // Tồn Đầu
          compare = a.openingStock.compareTo(b.openingStock);
          break;
        case 4: // Nhập
          compare = a.importStock.compareTo(b.importStock);
          break;
        case 5: // Xuất
          compare = a.exportStock.compareTo(b.exportStock);
          break;
        case 6: // Tồn Cuối
          compare = a.closingStock.compareTo(b.closingStock);
          break;
        default: // Mặc định (hoặc case 0, 1, 2)
          compare = a.product.productName.compareTo(b.product.productName);
          if (compare == 0) {
            compare = a.unitName.compareTo(b.unitName);
          }
          return compare;
      }

      // Áp dụng chiều sắp xếp (chỉ cho các cột số)
      return _sortAscending ? compare : -compare;
    });
  }

  Widget _buildSortableHeaderCell(String text, int columnIndex, {required int flex, TextAlign align = TextAlign.center}) {
    final bool isSortedByThis = _sortColumnIndex == columnIndex;

    return Expanded(
      flex: flex,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSortedByThis) {
              _sortAscending = !_sortAscending;
            } else {
              _sortColumnIndex = columnIndex;
              _sortAscending = true;
            }
            _sortReportList();
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: (align == TextAlign.left) ? MainAxisAlignment.start : (align == TextAlign.right) ? MainAxisAlignment.end : MainAxisAlignment.center,
            children: [
              if (isSortedByThis)
                Icon(
                  _sortAscending ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                  size: 20,
                  color: AppTheme.primaryColor,
                )
              else
              const SizedBox(width: 2),

              _buildWrappedHeaderCell(text, align: align),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showExportOptionsDialog() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xuất Báo Cáo'),
        content: const Text('Chọn định dạng bạn muốn xuất:'),
        actions: [
          TextButton(
            child: const Text('Excel (.xlsx)'),
            onPressed: () {
              Navigator.of(context).pop();
              _exportToExcel();
            },
          ),
          TextButton(
            child: const Text('PDF (.pdf)'),
            onPressed: () {
              Navigator.of(context).pop();
              _exportToPdf();
            },
          ),
        ],
      ),
    );
  }

  Future<void> _exportToExcel() async {
    if (_filteredReportData.isEmpty) {
      ToastService()
          .show(message: "Không có dữ liệu để xuất.", type: ToastType.warning);
      return;
    }

    try {
      final excel = Excel.createExcel();
      final Sheet sheet = excel[excel.getDefaultSheet()!];
      final String reportDate =
          DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
      final String dateRange =
          'Từ ngày: ${DateFormat('dd/MM/yyyy').format(_startDate!)} - Đến ngày: ${DateFormat('dd/MM/yyyy').format(_endDate!)}';
      final CellStyle titleStyle = CellStyle(
        bold: true,
        fontSize: 18,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );
      sheet.appendRow([TextCellValue('BÁO CÁO XUẤT NHẬP TỒN')]);
      final cellA1 = sheet.cell(CellIndex.indexByString('A1'));
      cellA1.cellStyle = titleStyle;
      sheet.appendRow([TextCellValue(dateRange)]);
      sheet.appendRow([TextCellValue('Ngày tạo: $reportDate')]);
      sheet.appendRow([]);
      final headers = [
        'Mã SP',
        'Tên Sản Phẩm',
        'Đơn Vị',
        'Tồn Đầu Kỳ',
        'Nhập Trong Kỳ',
        'Xuất Trong Kỳ',
        'Tồn Cuối Kỳ'
      ];
      sheet.merge(
          CellIndex.indexByString('A1'),
          CellIndex.indexByColumnRow(
              columnIndex: headers.length - 1, rowIndex: 0));

      sheet.appendRow(headers.map((header) => TextCellValue(header)).toList());

      for (final data in _filteredReportData) {
        final rowData = [
          TextCellValue(data.product.productCode ?? ''),
          TextCellValue(data.product.productName),
          TextCellValue(data.unitName),
          DoubleCellValue(data.openingStock),
          DoubleCellValue(data.importStock),
          DoubleCellValue(data.exportStock),
          DoubleCellValue(data.closingStock),
        ];
        sheet.appendRow(rowData);
      }

      final String fileName =
          'BaoCaoTonKho_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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
        } else {
          ToastService()
              .show(message: "Đã hủy lưu file.", type: ToastType.warning);
        }
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi xuất Excel: $e", type: ToastType.error);
    }
  }

  Future<void> _exportToPdf() async {
    if (_filteredReportData.isEmpty) {
      ToastService()
          .show(message: "Không có dữ liệu để xuất.", type: ToastType.warning);
      return;
    }

    try {
      final pdf = pw.Document();

      final fontData =
          await rootBundle.load("assets/fonts/RobotoMono-Regular.ttf");
      final ttf = pw.Font.ttf(fontData);
      final boldFontData =
          await rootBundle.load("assets/fonts/RobotoMono-Bold.ttf");
      final boldTtf = pw.Font.ttf(boldFontData);

      final pw.ThemeData theme =
          pw.ThemeData.withFont(base: ttf, bold: boldTtf);

      final String reportDate =
          DateFormat('HH:mm dd/MM/yyyy').format(DateTime.now());
      final String dateRange =
          'Từ ngày: ${DateFormat('dd/MM/yyyy').format(_startDate!)} - Đến ngày: ${DateFormat('dd/MM/yyyy').format(_endDate!)}';

      pdf.addPage(
        pw.MultiPage(
          theme: theme,
          pageFormat: PdfPageFormat.a4,
          header: (context) => pw.Container(
              alignment: pw.Alignment.center,
              margin: const pw.EdgeInsets.only(bottom: 20.0),
              child: pw.Column(children: [
                pw.Text('BÁO CÁO XUẤT NHẬP TỒN',
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold, fontSize: 18)),
                pw.SizedBox(height: 8),
                pw.Text(dateRange, style: const pw.TextStyle(fontSize: 12)),
                pw.SizedBox(height: 4),
                pw.Text('Ngày tạo: $reportDate',
                    style: pw.TextStyle(fontSize: 10)),
              ])),
          build: (context) => [
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(),
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              // Giảm size chữ header một chút
              cellStyle: const pw.TextStyle(fontSize: 8),
              // Giảm size chữ cell một chút
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft, // Mã SP
                1: pw.Alignment.centerLeft, // Sản Phẩm
                2: pw.Alignment.center, // ĐVT
                3: pw.Alignment.centerRight, // Tồn Đầu
                4: pw.Alignment.centerRight, // Nhập
                5: pw.Alignment.centerRight, // Xuất
                6: pw.Alignment.centerRight, // Tồn Cuối
              },
              headers: [
                'Mã SP',
                'Sản Phẩm',
                'ĐVT',
                'Tồn Đầu',
                'Nhập',
                'Xuất',
                'Tồn Cuối'
              ],
              data: _filteredReportData
                  .map((data) => [
                        data.product.productCode ?? '',
                        data.product.productName,
                        data.unitName,
                        formatNumber(data.openingStock),
                        formatNumber(data.importStock),
                        formatNumber(data.exportStock),
                        formatNumber(data.closingStock),
                      ])
                  .toList(),
            ),
          ],
        ),
      );

      final String defaultFileName =
          'BaoCaoTonKho_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final Uint8List fileBytes = await pdf.save();

      final String? result = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu báo cáo PDF',
        fileName: defaultFileName,
        bytes: fileBytes,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        ToastService().show(
            message: "Đã lưu file PDF thành công!", type: ToastType.success);
      } else {
        ToastService()
            .show(message: "Đã hủy lưu file.", type: ToastType.warning);
      }
    } catch (e) {
      debugPrint("Lỗi khi xuất PDF: $e");
      ToastService()
          .show(message: "Lỗi khi xuất PDF: $e", type: ToastType.error);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadSettingsAndFetchData() async {
    final settingsService = SettingsService();
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;

    final settings = await settingsService.watchStoreSettings(settingsId).first;
    if (mounted) {
      setState(() {
        _reportCutoffTime = TimeOfDay(
          hour: settings.reportCutoffHour ?? 0,
          minute: settings.reportCutoffMinute ?? 0,
        );
      });
      _updateDateRangeAndFetch(); // Gọi fetch lần đầu
    }

    _settingsSub = settingsService.watchStoreSettings(settingsId).listen((s) {
      if (!mounted) return;
      final newCutoff = TimeOfDay(
        hour: s.reportCutoffHour ?? 0,
        minute: s.reportCutoffMinute ?? 0,
      );
      if (newCutoff.hour != _reportCutoffTime.hour || newCutoff.minute != _reportCutoffTime.minute) {
        setState(() {
          _reportCutoffTime = newCutoff;
        });
        _updateDateRangeAndFetch(); // Tải lại báo cáo nếu giờ thay đổi
      }
    });
  }

  Future<void> _scanBarcodeAndSearch() async {
    if (!mounted) return;
    final scannedCode = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
    );
    if (scannedCode != null && scannedCode.isNotEmpty) {
      _searchController.text = scannedCode;
    }
  }

  void _filterData() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _expandedProductUnitKey = null;
      _filteredReportData = _reportData.values.where((data) {

        final product = data.product;
        final matchesSearch =
            product.productName.toLowerCase().contains(query) ||
                (product.productCode ?? '').contains(query);

        final matchesGroup = _selectedProductGroup == null ||
            data.product.productGroup == _selectedProductGroup;

        return matchesSearch && matchesGroup;

      }).toList();

      _sortReportList();
    });
  }

  void showFilterModal() {
    // Lưu trạng thái tạm thời
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;
    String? tempProductGroup = _selectedProductGroup;
    // (Không cần temp cho search, vì _searchController là 1 object)

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        // Dùng StatefulBuilder để cập nhật UI bên trong modal
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {

            // --- SỬA LỖI 1: KIỂM TRA DESKTOP ---
            const double desktopBreakpoint = 750.0;
            final bool isDesktop = MediaQuery.of(context).size.width > desktopBreakpoint;
            // --- KẾT THÚC SỬA LỖI 1 ---

            final timeRangeFilter = AppDropdown<TimeRange>(
              labelText: 'Khoảng thời gian',
              prefixIcon: Icons.calendar_today_outlined,
              value: tempSelectedRange,
              items: TimeRange.values.map((range) {
                return DropdownMenuItem<TimeRange>(
                  value: range,
                  child: Text(_getTimeRangeText(range)),
                );
              }).toList(),
              onChanged: (TimeRange? newValue) {
                if (newValue == TimeRange.custom) {
                  _selectCustomDateTimeRange().then((_) {
                    // Cập nhật modal sau khi chọn ngày
                    setModalState(() {
                      tempSelectedRange = _selectedRange;
                      tempStartDate = _startDate;
                      tempEndDate = _endDate;
                    });
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
            );

            final groupFilter = AppDropdown<String>(
              labelText: 'Nhóm sản phẩm',
              prefixIcon: Icons.category_outlined,
              value: tempProductGroup,
              items: _productGroupOptions
                  .map((group) => DropdownMenuItem(value: group, child: Text(group)))
                  .toList(),
              onChanged: _areFiltersLoading
                  ? null
                  : (String? newValue) {
                setModalState(() {
                  tempProductGroup =
                  (newValue == 'Tất cả') ? null : newValue;
                });
              },
            );

            final searchFilter = TextField(
              controller: _searchController,
              // Thêm onChanged để cập nhật icon X khi gõ phím
              onChanged: (text) {
                setModalState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Tìm theo tên hoặc mã vạch...',
                prefixIcon: const Icon(Icons.search, size: 20),

                // --- SỬA LỖI 1 & 2: LOGIC ICON ---
                suffixIcon: isDesktop
                    ? null // 1. Không hiển thị icon trên desktop
                    : IconButton(
                  icon: Icon(
                    _searchController.text.isEmpty
                        ? Icons.qr_code_scanner // 2. Hiển thị icon quét
                        : Icons.clear, // 3. Hiển thị icon X
                    color: AppTheme.primaryColor,
                  ),
                  onPressed: () {
                    if (_searchController.text.isEmpty) {
                      // 4. Quét mã vạch
                      _scanBarcodeAndSearch().then((_) {
                        // Sau khi quét xong, gọi setModalState
                        // để cập nhật text và đổi icon sang 'X'
                        setModalState(() {});
                      });
                    } else {
                      // 5. Xóa text
                      _searchController.clear();
                      // Gọi setModalState để đổi icon sang 'quét mã'
                      setModalState(() {});
                    }
                  },
                ),
                // --- KẾT THÚC SỬA LỖI ---

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 16.0),
              ),
            );

            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Báo Cáo Tồn Kho', style: Theme.of(context).textTheme.headlineMedium),
                  timeRangeFilter,
                  searchFilter,
                  groupFilter,
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedRange = TimeRange.today;
                            _selectedProductGroup = null;
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
                          bool dateChanged = (_selectedRange != tempSelectedRange);

                          if (_selectedRange == TimeRange.custom && tempSelectedRange == TimeRange.custom) {
                            dateChanged = (_startDate != tempStartDate || _endDate != tempEndDate);
                          }

                          setState(() {
                            _selectedRange = tempSelectedRange;
                            _startDate = tempStartDate;
                            _endDate = tempEndDate;
                            _selectedProductGroup = tempProductGroup;
                          });

                          if (dateChanged) {
                            _updateDateRangeAndFetch();
                          } else {
                            _filterData();
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

  void _updateDateRangeAndFetch() {
    if (_selectedRange == TimeRange.custom) {
      // Dải tùy chọn được xử lý riêng
    } else {
      final now = DateTime.now();
      final cutoff = _reportCutoffTime;

      DateTime startOfReportDay(DateTime date) {
        return DateTime(date.year, date.month, date.day, cutoff.hour, cutoff.minute);
      }

      // Sửa: Phải là 999 mili giây để khớp với logic cũ của file này
      DateTime endOfReportDay(DateTime date) {
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
        // Sửa logic tuần trước cho khớp với file gốc (bắt đầu từ T2 tuần trước)
          final startOfThisWeek = effectiveDate.subtract(Duration(days: effectiveDate.weekday - DateTime.monday));
          final startOfLastWeek = startOfThisWeek.subtract(const Duration(days: 7));
          final endOfLastWeek = startOfThisWeek.subtract(const Duration(milliseconds: 1));
          _startDate = startOfReportDay(startOfLastWeek); // File gốc có vẻ tính sai (days: weekday + 6)
          _endDate = endOfLastWeek; // Giữ nguyên logic endOfLastWeek

          // Logic mới (chuẩn hơn):
          final endOfLastWeekDay = effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay = endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          break;
        case TimeRange.thisMonth:
          _startDate = DateTime(effectiveDate.year, effectiveDate.month, 1, cutoff.hour, cutoff.minute);
          final startOfNextMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 1, cutoff.hour, cutoff.minute);
          _endDate = startOfNextMonth.subtract(const Duration(milliseconds: 1)); // Sửa 23:59:59, 999
          break;
        case TimeRange.lastMonth:
          final startOfThisMonth = DateTime(effectiveDate.year, effectiveDate.month, 1, cutoff.hour, cutoff.minute);
          _endDate = startOfThisMonth.subtract(const Duration(milliseconds: 1)); // Sửa 23:59:59, 999
          final startOfLastMonthDate = DateTime(effectiveDate.year, effectiveDate.month - 1, 1);
          _startDate = DateTime(startOfLastMonthDate.year, startOfLastMonthDate.month, 1, cutoff.hour, cutoff.minute);
          break;
      }
    }

    if (_startDate != null && _endDate != null) {
      _fetchReportData();
    }
  }

  Future<void> _selectCustomDateTimeRange() async {
    if (!mounted) return;
    List<DateTime>? pickedRange = await showOmniDateTimeRangePicker(
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
        _fetchReportData();
      });
    }
  }

  Future<void> _fetchReportData() async {
    if (_startDate == null || _endDate == null) return;
    setState(() {
      _isLoading = true;
      _expandedProductUnitKey = null;
    });

    try {
      final db = FirebaseFirestore.instance;
      final storeId = widget.currentUser.storeId;
      final allProductsSnapshot = await db
          .collection('products')
          .where('storeId', isEqualTo: storeId)
          .get();
      final allProductsMap = {
        for (var doc in allProductsSnapshot.docs)
          doc.id: ProductModel.fromFirestore(doc)
      };
      final trackableProducts = allProductsMap.values
          .where((p) => [
                'Hàng hóa',
                'Nguyên liệu',
                'Vật liệu'
              ].contains(p.productType))
          .toList();

      _reportData.clear();
      for (final product in trackableProducts) {
        if (product.manageStockSeparately) {
          for (final unitName in product.getAllUnits) {
            final key = '${product.id}_$unitName';
            double closingStock = 0;
            if (unitName == product.unit) {
              closingStock = product.stock;
            } else {
              final unitData = product.additionalUnits
                  .firstWhereOrNull((u) => u['unitName'] == unitName);
              closingStock = (unitData?['stock'] as num?)?.toDouble() ?? 0.0;
            }
            _reportData[key] = ProductUnitReportData(
                product: product,
                unitName: unitName,
                closingStock: closingStock);
          }
        } else {
          final unitName = (product.unit != null && product.unit!.isNotEmpty)
              ? product.unit!
              : 'Đơn vị';

          final key = '${product.id}_$unitName';
          _reportData[key] = ProductUnitReportData(
            product: product,
            unitName: unitName,
            closingStock: product.stock,
          );
        }
      }

      // 3. SỬA LỖI: Tính lượng nhập kho, khôi phục logic đọc 'separateQuantities'
      final purchaseOrdersSnapshot = await db
          .collection('purchase_orders')
          .where('storeId', isEqualTo: storeId)
          .where('status', isNotEqualTo: 'Đã hủy')
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .get();

      for (final doc in purchaseOrdersSnapshot.docs) {
        final items =
            List<Map<String, dynamic>>.from(doc.data()['items'] ?? []);
        for (final itemMap in items) {
          final productId = itemMap['productId'];
          final product = allProductsMap[productId];
          if (product == null) continue;

          if (product.manageStockSeparately) {
            // ĐỌC DỮ LIỆU NHẬP KHO TỪ 'separateQuantities'
            final quantities =
                Map<String, num>.from(itemMap['separateQuantities'] ?? {});
            quantities.forEach((unitName, qty) {
              final key = '${productId}_$unitName';
              if (_reportData.containsKey(key)) {
                _reportData[key]!.importStock += qty.toDouble();
              }
            });
          } else {
            // Quy đổi về đơn vị cơ bản nếu không quản lý riêng
            final baseUnit = product.unit;
            if (baseUnit == null || baseUnit.isEmpty) continue;
            final key = '${productId}_$baseUnit';

            if (_reportData.containsKey(key)) {
              final quantity = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
              final unitInPO = itemMap['unit'] as String? ?? baseUnit;
              double quantityInBaseUnit = quantity;
              if (unitInPO != baseUnit) {
                final unitData = product.additionalUnits
                    .firstWhereOrNull((u) => u['unitName'] == unitInPO);
                final conversionFactor =
                    (unitData?['conversionFactor'] as num?)?.toDouble() ?? 1.0;
                quantityInBaseUnit *= conversionFactor;
              }
              _reportData[key]!.importStock += quantityInBaseUnit;
            }
          }
        }
      }

      // 4. Tính lượng xuất kho (Hàm đệ quy không đổi, đã đúng)
      final billsSnapshot = await db
          .collection('bills')
          .where('storeId', isEqualTo: storeId)
          .where('status', whereIn: ['completed', 'return']) // [FIX] Lấy cả bill 'return' (đổi trả)
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .get();

      Map<String, double> exportDeltas = {};
      for (final doc in billsSnapshot.docs) {
        final data = doc.data(); // Lấy data ra biến
        final String status = data['status'] ?? 'completed';

        // --- PHẦN A: XỬ LÝ 'items' (Chỉ áp dụng cho đơn Bán hàng - Completed) ---
        if (status == 'completed') {
          final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
          for (final itemMap in items) {
            // Logic cũ giữ nguyên
            _calculateExportDeductions(
                itemMap: itemMap,
                allProducts: allProductsMap,
                deductionsMap: exportDeltas);

            // Xử lý Topping của hàng bán
            final toppings = List<Map<String, dynamic>>.from(itemMap['toppings'] ?? []);
            final mainQty = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
            final mainReturned = (itemMap['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
            final quantityOfMainProduct = mainQty - mainReturned;

            if (quantityOfMainProduct <= 0) continue;

            for (final toppingMap in toppings) {
              final totalToppingQuantity = quantityOfMainProduct *
                  ((toppingMap['quantity'] as num?)?.toDouble() ?? 1.0);
              final toppingItemMapForDeduction = {
                'product': toppingMap['product'],
                'quantity': totalToppingQuantity,
                'selectedUnit': toppingMap['selectedUnit'],
                'toppings': [],
                'returnedQuantity': 0,
              };
              _calculateExportDeductions(
                  itemMap: toppingItemMapForDeduction,
                  allProducts: allProductsMap,
                  deductionsMap: exportDeltas);
            }
          }
        }
        final exchangeItems = List<Map<String, dynamic>>.from(data['exchangeItems'] ?? []);
        for (final exItemMap in exchangeItems) {
          // Tính toán trừ kho cho sản phẩm chính
          _calculateExportDeductions(
              itemMap: exItemMap,
              allProducts: allProductsMap,
              deductionsMap: exportDeltas
          );

          final toppings = List<Map<String, dynamic>>.from(exItemMap['toppings'] ?? []);
          final quantityOfMainProduct = (exItemMap['quantity'] as num?)?.toDouble() ?? 0.0;
          if (quantityOfMainProduct <= 0) continue;

          for (final toppingMap in toppings) {
            final toppingQtyPerUnit = (toppingMap['quantity'] as num?)?.toDouble() ?? 1.0;
            final totalToppingQuantity = quantityOfMainProduct * toppingQtyPerUnit;

            final toppingItemMapForDeduction = {
              'product': toppingMap['product'],
              'quantity': totalToppingQuantity,
              'selectedUnit': toppingMap['selectedUnit'],
              'toppings': [],
              'returnedQuantity': 0,
            };
            _calculateExportDeductions(
                itemMap: toppingItemMapForDeduction,
                allProducts: allProductsMap,
                deductionsMap: exportDeltas
            );
          }
        }
      }
      exportDeltas.forEach((uniqueKey, totalExported) {
        if (_reportData.containsKey(uniqueKey)) {
          _reportData[uniqueKey]!.exportStock += totalExported;
        }
      });

      // 5. Tính tồn đầu kỳ
      _reportData.forEach((key, data) {
        data.openingStock =
            data.closingStock - data.importStock + data.exportStock;
      });
    } catch (e) {
      debugPrint("Lỗi khi tải báo cáo XNT: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi tải báo cáo: $e")));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _filterData();
        });
      }
    }
  }

  void _calculateExportDeductions({
    required Map<String, dynamic> itemMap,
    required Map<String, ProductModel> allProducts,
    required Map<String, double> deductionsMap,
  }) {
    final productData = itemMap['product'] as Map<String, dynamic>?;
    if (productData == null) return;
    final soldProduct = allProducts[productData['id']];
    if (soldProduct == null) return;

    final qty = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
    final returned = (itemMap['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
    final quantitySold = qty - returned;

    if (quantitySold <= 0) return;

    final type = soldProduct.productType;

    // TRƯỜNG HỢP CƠ SỞ
    if (type == 'Hàng hóa' ||
        type == 'Nguyên liệu' ||
        type == 'Vật liệu') {
      final selectedUnit =
          itemMap['selectedUnit'] as String? ?? soldProduct.unit;
      if (selectedUnit == null) return;

      if (soldProduct.manageStockSeparately) {
        // ... (Logic manageStockSeparately giữ nguyên) ...
        final uniqueKey = '${soldProduct.id}_$selectedUnit';
        deductionsMap[uniqueKey] =
            (deductionsMap[uniqueKey] ?? 0) + quantitySold;
      } else {
        // [SỬA LỖI] Đồng bộ với logic tạo key trong _fetchReportData
        final baseUnit = soldProduct.unit;
        final finalBaseUnit = (baseUnit == null || baseUnit.isEmpty) ? 'Đơn vị' : baseUnit; // <-- FIX

        double quantityInBaseUnit = quantitySold;

        if (selectedUnit != finalBaseUnit) { // So sánh với đơn vị đã chuẩn hóa
          final unitData = soldProduct.additionalUnits
              .firstWhereOrNull((u) => u['unitName'] == selectedUnit);
          final conversionFactor =
              (unitData?['conversionFactor'] as num?)?.toDouble() ?? 1.0;
          quantityInBaseUnit *= conversionFactor;
        }

        final uniqueKeyForBaseUnit = '${soldProduct.id}_$finalBaseUnit'; // <-- DÙNG finalBaseUnit
        deductionsMap[uniqueKeyForBaseUnit] =
            (deductionsMap[uniqueKeyForBaseUnit] ?? 0) + quantityInBaseUnit;
      }
    }
    // TRƯỜNG HỢP ĐỆ QUY
    else if (type == 'Thành phẩm/Combo' || type == 'Topping/Bán kèm') {
      for (final recipeItem in soldProduct.recipeItems) {
        final ingredientProduct = allProducts[recipeItem['productId']];
        if (ingredientProduct == null) continue;
        final ingredientQtyInRecipe =
            (recipeItem['quantity'] as num?)?.toDouble() ?? 1.0;
        final totalIngredientQtyNeeded = quantitySold * ingredientQtyInRecipe;
        final ingredientItemMap = {
          'product': ingredientProduct.toMap(),
          'quantity': totalIngredientQtyNeeded,
          'selectedUnit': recipeItem['selectedUnit'] as String?,
        };
        _calculateExportDeductions(
            itemMap: ingredientItemMap,
            allProducts: allProducts,
            deductionsMap: deductionsMap);
      }
    }
  }

  void _onRowTapped(String productUnitKey) {
    setState(() {
      if (_expandedProductUnitKey == productUnitKey) {
        _expandedProductUnitKey = null; // Nếu đang mở thì đóng lại
        _transactions = [];
      } else {
        _expandedProductUnitKey = productUnitKey; // Mở dòng mới
        final reportItem = _reportData[productUnitKey];
        if (reportItem != null) {
          _fetchTransactionDetails(reportItem.product.id,
              reportItem.unitName); // Tải dữ liệu chi tiết
        }
      }
    });
  }

  Future<void> _fetchTransactionDetails(
      String productId, String unitName) async { // <-- Đã có productId, unitName
    if (_startDate == null || _endDate == null) return;
    setState(() {
      _isDetailLoading = true;
    });

    final List<InventoryTransaction> fetchedTransactions = [];
    final db = FirebaseFirestore.instance;
    final storeId = widget.currentUser.storeId;

    try {
      final allProductsSnapshot = await db
          .collection('products')
          .where('storeId', isEqualTo: storeId)
          .get();
      final allProductsMap = {
        for (var doc in allProductsSnapshot.docs)
          doc.id: ProductModel.fromFirestore(doc)
      };
      final targetProduct = allProductsMap[productId];
      if (targetProduct == null) throw Exception("Sản phẩm không tồn tại");

      // 1. LẤY PHIẾU NHẬP (Logic giữ nguyên)
      final poSnapshot = await db
          .collection('purchase_orders')
          .where('storeId', isEqualTo: storeId)
          .where('status', isNotEqualTo: 'Đã hủy')
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .get();

      for (final doc in poSnapshot.docs) {
        final data = doc.data();
        final items = List<Map<String, dynamic>>.from(data['items'] ?? []);
        for (final item in items) {
          if (item['productId'] == productId) {
            if (targetProduct.manageStockSeparately) {
              final quantities =
              Map<String, num>.from(item['separateQuantities'] ?? {});
              if (quantities.containsKey(unitName) &&
                  quantities[unitName]! > 0) {
                fetchedTransactions.add(InventoryTransaction(
                    docId: doc.id,
                    type: 'NH',
                    date: (data['createdAt'] as Timestamp).toDate(),
                    quantity: (quantities[unitName]!).toDouble(),
                    code: data['code'] ?? 'N/A',
                    reference: data['supplierName'] ?? 'NCC lẻ'));
              }
            } else {
              final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
              final unitInPO = item['unit'] as String? ?? targetProduct.unit!;
              double quantityInBaseUnit = quantity;
              if (unitInPO != unitName) {
                final unitData = targetProduct.additionalUnits
                    .firstWhereOrNull((u) => u['unitName'] == unitInPO);
                final conversionFactor =
                    (unitData?['conversionFactor'] as num?)?.toDouble() ?? 1.0;
                quantityInBaseUnit *= conversionFactor;
              }
              if (quantityInBaseUnit > 0) {
                fetchedTransactions.add(InventoryTransaction(
                    docId: doc.id,
                    type: 'NH',
                    date: (data['createdAt'] as Timestamp).toDate(),
                    quantity: quantityInBaseUnit,
                    code: data['code'] ?? 'N/A',
                    reference: data['supplierName'] ?? 'NCC lẻ'));
              }
            }
          }
        }
      }

      // 2. LẤY HÓA ĐƠN XUẤT
      final billsSnapshot = await db
          .collection('bills')
          .where('storeId', isEqualTo: storeId)
          .where('status', whereIn: ['completed', 'return'])
          .where('createdAt', isGreaterThanOrEqualTo: _startDate)
          .where('createdAt', isLessThanOrEqualTo: _endDate)
          .get();

      for (final doc in billsSnapshot.docs) {
        final data = doc.data(); // Chú ý: data phải là Map<String, dynamic>
        final String status = data['status'] ?? 'completed';

        // --- A. XỬ LÝ HÀNG BÁN (Chỉ khi status là completed) ---
        if (status == 'completed') {
          final itemsInBill = List<Map<String, dynamic>>.from(data['items'] ?? []);
          for (final itemMap in itemsInBill) {
            // Logic cũ: Tìm sản phẩm chính
            _findExportTransactionsInItem(
              itemMap: itemMap,
              billDoc: doc,
              targetProductId: productId,
              targetUnitName: unitName,
              allProducts: allProductsMap,
              transactions: fetchedTransactions,
              parentProductName: null,
            );

          // Gọi hàm tìm kiếm cho từng topping
          final toppings =
          List<Map<String, dynamic>>.from(itemMap['toppings'] ?? []);
          final quantityOfMainProduct =
              (itemMap['quantity'] as num?)?.toDouble() ?? 1.0;
          for (final toppingMap in toppings) {
            final totalToppingQuantity = quantityOfMainProduct *
                ((toppingMap['quantity'] as num?)?.toDouble() ?? 1.0);
            final toppingItemMapForDeduction = {
              'product': toppingMap['product'],
              'quantity': totalToppingQuantity,
              'selectedUnit': toppingMap['selectedUnit'],
              'toppings': [],
            };
            _findExportTransactionsInItem(
              itemMap: toppingItemMapForDeduction,
              billDoc: doc,
              targetProductId: productId, // <--- ĐÃ SỬA LỖI
              targetUnitName: unitName, // <--- ĐÃ SỬA LỖI
              allProducts: allProductsMap,
              transactions: fetchedTransactions,
              parentProductName: null,
            );
          }
        }
        }

        // B. [THÊM MỚI] XỬ LÝ EXCHANGE ITEMS (Đổi hàng)
        final exchangeItems = List<Map<String, dynamic>>.from(data['exchangeItems'] ?? []);
        for (final exItemMap in exchangeItems) {
          // 1. Tìm trong sản phẩm chính
          _findExportTransactionsInItem(
            itemMap: exItemMap,
            billDoc: doc,
            targetProductId: productId,
            targetUnitName: unitName,
            allProducts: allProductsMap,
            transactions: fetchedTransactions,
            parentProductName: null,
            customReference: 'Xuất đổi hàng', // Để phân biệt với bán thường
          );

          // Gọi hàm tìm kiếm cho Topping đổi
          final toppings = List<Map<String, dynamic>>.from(exItemMap['toppings'] ?? []);
          final quantityOfMainProduct = (exItemMap['quantity'] as num?)?.toDouble() ?? 1.0;
          for (final toppingMap in toppings) {
            final toppingQtyPerUnit = (toppingMap['quantity'] as num?)?.toDouble() ?? 1.0;
            final totalToppingQuantity = quantityOfMainProduct * toppingQtyPerUnit;

            final toppingItemMapForDeduction = {
              'product': toppingMap['product'],
              'quantity': totalToppingQuantity,
              'selectedUnit': toppingMap['selectedUnit'],
              'toppings': [],
            };
            _findExportTransactionsInItem(
              itemMap: toppingItemMapForDeduction,
              billDoc: doc,
              targetProductId: productId,
              targetUnitName: unitName,
              allProducts: allProductsMap,
              transactions: fetchedTransactions,
              parentProductName: null,
              customReference: 'Xuất đổi (Topping)',
            );
          }
        }
      }

      // 3. Sắp xếp
      fetchedTransactions.sort((a, b) => b.date.compareTo(a.date));
    } catch (e) {
      debugPrint("Lỗi tải chi tiết giao dịch: $e");
    } finally {
      if (mounted) {
        setState(() {
          _transactions = fetchedTransactions;
          _isDetailLoading = false;
        });
      }
    }
  }

  void _findExportTransactionsInItem({
    required Map<String, dynamic> itemMap,
    required DocumentSnapshot billDoc,
    required String targetProductId,
    required String targetUnitName,
    required Map<String, ProductModel> allProducts,
    required List<InventoryTransaction> transactions,
    String? parentProductName,
    String? customReference,
  }) {
    final productData = itemMap['product'] as Map<String, dynamic>?;
    if (productData == null) return;
    final soldProduct = allProducts[productData['id']];
    if (soldProduct == null) return;

    final String currentProductName = soldProduct.productName;
    final billData = billDoc.data() as Map<String, dynamic>;
    final billCode = billData['billCode'] ?? billDoc.id.split('_').last ?? 'N/A';
    final qty = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
    final returned = (itemMap['returnedQuantity'] as num?)?.toDouble() ?? 0.0;
    final quantitySold = qty - returned;

    if (quantitySold <= 0) return;

    final type = soldProduct.productType;

    // TRƯỜNG HỢP CƠ SỞ (BASE CASE)
    if (type == 'Hàng hóa' ||
        type == 'Nguyên liệu' ||
        type == 'Vật liệu') {
      if (soldProduct.id == targetProductId) {
        final selectedUnit =
            itemMap['selectedUnit'] as String? ?? soldProduct.unit;
        if (selectedUnit == null) return;

        double quantityToDeduct = quantitySold;

        // Xác định đơn vị và quy đổi nếu cần
        if (soldProduct.manageStockSeparately) {
          if (selectedUnit != targetUnitName) {
            return;
          } // Nếu quản lý riêng, chỉ khớp đúng đơn vị
        } else {
          // Nếu không, quy đổi về đơn vị cơ bản (targetUnitName)
          if (selectedUnit != targetUnitName) {
            final unitData = soldProduct.additionalUnits
                .firstWhereOrNull((u) => u['unitName'] == selectedUnit);
            final conversionFactor =
                (unitData?['conversionFactor'] as num?)?.toDouble() ?? 1.0;
            quantityToDeduct *= conversionFactor;
          }
        }

        // [SỬA ĐỔI LOGIC THAM CHIẾU]
        String reference;
        if (customReference != null) {
          reference = customReference;
          if (parentProductName != null) reference += " ($parentProductName)";
        } else if (parentProductName != null) {
          reference = parentProductName;
        } else {
          reference = 'Trừ tồn bán hàng';
        }

        transactions.add(InventoryTransaction(
          docId: billDoc.id,
          type: 'XH',
          date: (billData['createdAt'] as Timestamp).toDate(),
          quantity: quantityToDeduct,
          code: billCode,
          reference: reference,
        ));
      }
    }
    // TRƯỜNG HỢP ĐỆ QUY (RECURSIVE CASE)
    else if (type == 'Thành phẩm/Combo' || type == 'Topping/Bán kèm') {
      for (final recipeItem in soldProduct.recipeItems) {
        final ingredientProduct = allProducts[recipeItem['productId']];
        if (ingredientProduct == null) continue;

        final ingredientQtyInRecipe =
            (recipeItem['quantity'] as num?)?.toDouble() ?? 1.0;
        final totalIngredientQtyNeeded = quantitySold * ingredientQtyInRecipe;
        final ingredientItemMap = {
          'product': ingredientProduct.toMap(),
          'quantity': totalIngredientQtyNeeded,
          'selectedUnit': recipeItem['selectedUnit'] as String?,
        };

        _findExportTransactionsInItem(
          itemMap: ingredientItemMap,
          billDoc: billDoc,
          targetProductId: targetProductId,
          targetUnitName: targetUnitName,
          allProducts: allProducts,
          transactions: transactions,
          customReference: customReference,
          parentProductName: currentProductName,
        );
      }
    }
  }

  Future<void> _loadFilterOptions() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('products')
          .where('storeId', isEqualTo: widget.currentUser.storeId)
          .get();

      if (mounted && snapshot.docs.isNotEmpty) {
        const allowedTypes = {
          'Hàng hóa',
          'Nguyên liệu',
          'Vật liệu'
        };

        final groups = snapshot.docs
            .where((doc) {
              final type = doc.data()['productType'] as String?;
              return type != null && allowedTypes.contains(type);
            })
            .map((doc) => doc.data()['productGroup'] as String?)
            .nonNulls
            .where((group) => group.isNotEmpty)
            .toSet()
            .toList();

        groups.sort();

        setState(() {
          _productGroupOptions = ['Tất cả', ...groups];
        });
      }
    } catch (e) {
      debugPrint("Lỗi khi tải nhóm sản phẩm: $e");
      if (mounted) {
        ToastService().show(
            message: "Không thể tải danh sách nhóm sản phẩm.",
            type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() {
          _areFiltersLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToTransaction(InventoryTransaction tx) async {
    final db = FirebaseFirestore.instance;

    if (tx.type == 'NH') {
      final doc = await db.collection('purchase_orders').doc(tx.docId).get();
      if (doc.exists && mounted) {
        final po = PurchaseOrderModel.fromFirestore(doc);
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => CreatePurchaseOrderScreen(
            currentUser: widget.currentUser,
            existingPurchaseOrder: po,
          ),
        ));
      } else {
        ToastService()
            .show(message: "Không tìm thấy phiếu nhập", type: ToastType.error);
      }
    } else if (tx.type == 'XH') {
      try {
        final billDoc = await db.collection('bills').doc(tx.docId).get();
        final storeInfoFuture =
            FirestoreService().getStoreDetails(widget.currentUser.storeId);

        final results =
            await Future.wait([Future.value(billDoc), storeInfoFuture]);

        final billSnapshot = results[0] as DocumentSnapshot;
        final storeInfo = results[1] as Map<String, String>?;

        if (billSnapshot.exists && storeInfo != null && mounted) {
          final bill = BillModel.fromFirestore(billSnapshot);
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
              message: "Không tìm thấy hóa đơn hoặc thông tin cửa hàng",
              type: ToastType.error);
        }
      } catch (e) {
        ToastService()
            .show(message: "Lỗi khi mở hóa đơn: $e", type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _fetchReportData,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader()),
          const SliverToBoxAdapter(child: Divider(height: 4, thickness: 0.5, color: Colors.grey)),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredReportData.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text("Không có dữ liệu báo cáo.")),
            )
          else
            SliverPadding(
              padding:
              const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) {
                    final data = _filteredReportData[index];
                    final isExpanded =
                        data.uniqueKey == _expandedProductUnitKey;

                    final bool showProductNameHeader = index == 0 ||
                        _filteredReportData[index - 1].product.id !=
                            data.product.id;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showProductNameHeader)
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 16.0, left: 8.0, bottom: 4.0),
                            child: Text(
                              data.product.productName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        _buildReportCard(data, isExpanded),
                      ],
                    );
                  },
                  childCount: _filteredReportData.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReportCard(ProductUnitReportData data, bool isExpanded) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 2.0, horizontal: 4.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: isExpanded ? 3 : 1,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _onRowTapped(data.uniqueKey),
        child: Column(
          children: [
            Container(
              color: isExpanded
                  ? AppTheme.primaryColor.withAlpha(13)
                  : Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      data.unitName,
                      style: TextStyle(color: Colors.black, fontSize: 16),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  _buildNumberCell(data.openingStock,
                      flex: 3, color: Colors.black),
                  _buildNumberCell(data.importStock,
                      flex: 3, color: Colors.blueAccent),
                  _buildNumberCell(data.exportStock,
                      flex: 3, color: Colors.red),
                  _buildNumberCell(
                    data.closingStock,
                    flex: 3,
                    color: Colors.black,
                    align: TextAlign.right,
                  ),
                ],
              ),
            ),
            if (isExpanded) _buildDetailView(data),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberCell(
    double value, {
    required int flex,
    Color? color,
    TextAlign align = TextAlign.center,
  }) {
    if (value == 0) {
      return Expanded(
        flex: flex,
        child: Text(
          '-',
          textAlign: align,
          style: TextStyle(color: Colors.black, fontSize: 16),
        ),
      );
    }
    return Expanded(
      flex: flex,
      child: Text(
        formatNumber(value),
        textAlign: align,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildTransactionRow(InventoryTransaction tx) {
    final timeStyle = const TextStyle(fontSize: 14, color: Colors.black);
    final codeStyle = const TextStyle(fontSize: 14, color: AppTheme.primaryColor);
    final refStyle = const TextStyle(fontSize: 14, color: Colors.black);

    // Style cho số lượng
    final qtyStyle = TextStyle(
      fontSize: 14,
      color: tx.type == 'NH' ? Colors.blue : Colors.red,
    );
    final qtyString = '${tx.type == 'NH' ? '+' : '-'}${formatNumber(tx.quantity)}';

    // Kiểm tra màn hình
    final bool isDesktop = MediaQuery.of(context).size.width > 750;

    return InkWell(
      onTap: () => _navigateToTransaction(tx),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: isDesktop
            ? _buildDesktopRow(tx, timeStyle, codeStyle, refStyle, qtyString, qtyStyle)
            : _buildMobileRow(tx, timeStyle, codeStyle, refStyle, qtyString, qtyStyle),
      ),
    );
  }

  // Helper widget cho Desktop Layout
  Widget _buildDesktopRow(
      InventoryTransaction tx,
      TextStyle timeStyle,
      TextStyle codeStyle,
      TextStyle refStyle,
      String qtyString,
      TextStyle qtyStyle) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(
            DateFormat('HH:mm dd/MM/yyyy').format(tx.date), // Thời gian 1 dòng
            style: timeStyle,
            textAlign: TextAlign.left,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            tx.code,
            style: codeStyle,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(
          flex: 4,
          child: Text(
            tx.reference,
            style: refStyle,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            qtyString,
            style: qtyStyle,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  // Helper widget cho Mobile Layout
  Widget _buildMobileRow(
      InventoryTransaction tx,
      TextStyle timeStyle,
      TextStyle codeStyle,
      TextStyle refStyle,
      String qtyString,
      TextStyle qtyStyle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hàng 1: Thời gian (4) - Mã phiếu (6)
        Row(
          children: [
            Expanded(
              flex: 4,
              child: Text(
                DateFormat('HH:mm dd/MM/yyyy').format(tx.date),
                style: timeStyle.copyWith(color: Colors.grey[700], fontSize: 13),
                textAlign: TextAlign.left,
              ),
            ),
            Expanded(
              flex: 6,
              child: Text(
                tx.code,
                style: codeStyle,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        // Hàng 2: Tham chiếu (7) - Số lượng (3)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start, // Căn trên để tham chiếu dài không làm lệch số
          children: [
            Expanded(
              flex: 8,
              child: Text(
                tx.reference,
                style: refStyle,
                textAlign: TextAlign.left,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                qtyString,
                style: qtyStyle,
                textAlign: TextAlign.right
              ),
            ),
          ],
        ),
        const Divider(height: 2, thickness: 0.5, color: Colors.grey),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cột 0, 1, 2 (Sản phẩm) - Không cho sắp xếp
            Expanded(
              flex: 4,
              child: _buildWrappedHeaderCell('SẢN PHẨM', align: TextAlign.left),
            ),

            // [SỬA ĐỔI] Dùng hàm sortable cho các cột còn lại
            // Cột 3: Tồn Đầu
            _buildSortableHeaderCell('TỒN ĐẦU', 3, flex: 3),

            // Cột 4: Số Nhập
            _buildSortableHeaderCell('SỐ NHẬP', 4, flex: 3),

            // Cột 5: Số Xuất
            _buildSortableHeaderCell('SỐ XUẤT', 5, flex: 3),

            // Cột 6: Tồn Cuối
            _buildSortableHeaderCell('TỒN CUỐI', 6, flex: 3, align: TextAlign.right),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailView(ProductUnitReportData data) {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.all(16.0),
      child: _isDetailLoading
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator()))
          : Column(
              children: [
                _transactions.isEmpty
                    ? const Center(
                        child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 16.0),
                        child: Text("Không có giao dịch trong kỳ.",
                            style: TextStyle(color: Colors.black)),
                      ))
                    : Column(
                        children: [
                          _buildDetailHeader(),
                          ..._transactions
                              .map((tx) => _buildTransactionRow(tx)),
                        ],
                      ),
              ],
            ),
    );
  }

  Widget _buildWrappedHeaderCell(String text,
      {TextAlign align = TextAlign.center}) {
    final parts = text.split(' ');
    final style = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 14,
      color: Colors.black,
    );

    CrossAxisAlignment crossAxisAlignment;
    switch (align) {
      case TextAlign.left:
        crossAxisAlignment = CrossAxisAlignment.start;
        break;
      case TextAlign.right:
        crossAxisAlignment = CrossAxisAlignment.end;
        break;
      default:
        crossAxisAlignment = CrossAxisAlignment.center;
        break;
    }

    List<Widget> textWidgets = (parts.length < 2)
    // Thêm textAlign vào Text
        ? [Text(text, style: style, textAlign: align,)]
        : [
      Text(parts[0], style: style, textAlign: align,),
      Text(parts.sublist(1).join(' '), style: style, textAlign: align,),
    ];

    // [SỬA ĐỔI] Chỉ trả về Column, không có Expanded
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: crossAxisAlignment,
      children: textWidgets,
    );
  }

  Widget _buildDetailHeader() {
    // 1. Kiểm tra màn hình
    final bool isDesktop = MediaQuery.of(context).size.width > 750;

    // 2. Nếu là mobile -> Ẩn tiêu đề
    if (!isDesktop) {
      return const SizedBox.shrink();
    }

    // 3. Nếu là Desktop -> Giữ nguyên layout cũ
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child:
              _buildWrappedHeaderCell('THỜI GIAN', align: TextAlign.left),
            ),
            Expanded(
              flex: 4,
              child: _buildWrappedHeaderCell('MÃ PHIẾU'),
            ),
            Expanded(
              flex: 4,
              child: _buildWrappedHeaderCell('THAM CHIẾU'),
            ),
            Expanded(
              flex: 3,
              child:
              _buildWrappedHeaderCell('SỐ LƯỢNG', align: TextAlign.right),
            ),
          ],
        ),
      ),
    );
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
}
