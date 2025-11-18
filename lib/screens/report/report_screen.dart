// File: lib/screens/reports/report_screen.dart

import 'package:app_4cash/theme/app_theme.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'tabs/cash_flow_report_tab.dart';
import 'tabs/end_of_day_report_tab.dart';
import 'tabs/inventory_report_tab.dart';
import 'tabs/sales_report_tab.dart';
import 'package:app_4cash/models/cash_flow_transaction_model.dart';
import 'package:app_4cash/widgets/cash_flow_dialog_helper.dart';
import 'tabs/retail_sales_ledger_tab.dart';

class ReportScreen extends StatefulWidget {
  final UserModel currentUser;
  const ReportScreen({super.key, required this.currentUser});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _endOfDayReportKey = GlobalKey<EndOfDayReportTabState>();
  final _inventoryReportKey = GlobalKey<InventoryReportTabState>();
  final _cashFlowReportKey = GlobalKey<CashFlowReportTabState>();
  final _salesReportKey = GlobalKey<SalesReportTabState>();
  final _retailLedgerKey = GlobalKey<RetailSalesLedgerTabState>();

  bool _isSalesLoading = true;
  bool _isEndOfDayLoading = true;
  bool _isRetailLedgerLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleExport() {
    if (_tabController.index == 3) {
      _inventoryReportKey.currentState?.exportReport();
    } else if (_tabController.index == 4) {
      _retailLedgerKey.currentState?.exportReport();
    }
  }

  List<Widget> _buildRetailLedgerActions(BuildContext context) {
    final state = _retailLedgerKey.currentState;
    if (state != null) {
      return [
        IconButton(
          icon: const Icon(Icons.download_for_offline,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Xuất báo cáo (Excel)',
          onPressed: _handleExport,
        ),
        IconButton(
          icon: _isRetailLedgerLoading
              ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.filter_list,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Lọc báo cáo',
          onPressed: _isRetailLedgerLoading ? null : state.showFilterModal,
        ),
        const SizedBox(width: 8),
      ];
    }
    return [];
  }

  List<Widget> _buildSalesActions(BuildContext context) {
    return [
      IconButton(
        // SỬ DỤNG BIẾN TẠI ĐÂY:
        icon: _isSalesLoading
            ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.filter_list,
            color: AppTheme.primaryColor, size: 30),
        tooltip: 'Lọc báo cáo',
        // VÀ SỬ DỤNG BIẾN TẠI ĐÂY:
        onPressed: _isSalesLoading ? null : () {
          final state = _salesReportKey.currentState;
          if (state != null) {
            state.showFilterModal();
          }
        },
      ),
      const SizedBox(width: 8),
    ];
  }

  List<Widget> _buildCashFlowActions(BuildContext context) {
    final state = _cashFlowReportKey.currentState;
    if (state != null) {
      return [
        IconButton(
          icon: const Icon(Icons.add_circle_outlined,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Tạo phiếu thu',
          onPressed: () async {
            final bool success =
            await CashFlowDialogHelper.showAddTransactionDialog(
              context: context,
              currentUser: widget.currentUser,
              type: TransactionType.revenue,
            );
            if (success && state.mounted) {
              state.refreshData();
            }
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const Icon(Icons.remove_circle,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Tạo phiếu chi',
          onPressed: () async {
            final bool success =
            await CashFlowDialogHelper.showAddTransactionDialog(
              context: context,
              currentUser: widget.currentUser,
              type: TransactionType.expense,
            );
            if (success && state.mounted) {
              state.refreshData();
            }
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: state.isLoadingFilterOptions
              ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.filter_list,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Lọc phiếu thu chi',
          onPressed:
          state.isLoadingFilterOptions ? null : state.showFilterModal,
        ),
        const SizedBox(width: 8),
      ];
    }
    return [];
  }

  List<Widget> _buildEndOfDayActions(BuildContext context) {
    final endOfDayState = _endOfDayReportKey.currentState;
    final bool canPrint = endOfDayState?.isOwnerOrManager ?? false;

    return [
      // --- THÊM LẠI NÚT IN (chỉ Owner/Manager thấy) ---
      if (canPrint)
        IconButton(
          icon: _isEndOfDayLoading
              ? const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print_outlined, // Icon in
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'In tất cả Báo Cáo', // Tooltip mới
          onPressed: _isEndOfDayLoading
              ? null
              : () {
            // Gọi hàm tạo PDF tổng hợp trong EndOfDayReportTabState
            endOfDayState?. generateCombinedPdfAndShowDialog(); // Gọi hàm đã tạo
          },
        ),
      // --- KẾT THÚC THÊM NÚT IN ---

      // --- NÚT LỌC (Giữ nguyên) ---
      IconButton(
        icon: _isEndOfDayLoading
            ? const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.filter_list,
            color: AppTheme.primaryColor, size: 30),
        tooltip: 'Lọc báo cáo',
        onPressed: _isEndOfDayLoading
            ? null
            : () {
          endOfDayState?.showFilterModal(); // Gọi hàm lọc trong EndOfDayReportTabState
        },
      ),
      const SizedBox(width: 8),
    ];
  }

  List<Widget> _buildInventoryActions(BuildContext context) {
    final state = _inventoryReportKey.currentState;
    if (state != null) {
      return [
        IconButton(
          icon: const Icon(Icons.download_for_offline,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Xuất báo cáo (Excel/PDF)',
          onPressed: _handleExport, // Đã sửa hàm _handleExport ở trên
        ),
        IconButton(
          icon: state.areFiltersLoading
              ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(Icons.filter_list,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Lọc báo cáo',
          onPressed: state.areFiltersLoading ? null : state.showFilterModal,
        ),
        const SizedBox(width: 8),
      ];
    }
    return [];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo Cáo'),
        actions: [
          if (_tabController.index == 0) ..._buildSalesActions(context),
          if (_tabController.index == 1) ..._buildCashFlowActions(context),
          if (_tabController.index == 2) ..._buildEndOfDayActions(context),
          if (_tabController.index == 3) ..._buildInventoryActions(context),
          if (_tabController.index == 4) ..._buildRetailLedgerActions(context),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Tổng quan'),
            Tab(text: 'Thu Chi'),
            Tab(text: 'Tổng kết'),
            Tab(text: 'Tồn Kho'),
            Tab(text: 'Bảng Kê Bán Lẻ'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SalesReportTab(
            key: _salesReportKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) {
                setState(() {
                  _isSalesLoading = isLoading;
                });
              }
            },
          ),
          CashFlowReportTab(
            key: _cashFlowReportKey,
            currentUser: widget.currentUser,
          ),
          EndOfDayReportTab(
            key: _endOfDayReportKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) { setState(() { _isEndOfDayLoading = isLoading; }); }
            },
          ),
          InventoryReportTab(
            key: _inventoryReportKey,
            currentUser: widget.currentUser,
          ),
          // View mới
          RetailSalesLedgerTab(
            key: _retailLedgerKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) { setState(() { _isRetailLedgerLoading = isLoading; }); }
            },
          ),
        ],
      ),
    );
  }
}