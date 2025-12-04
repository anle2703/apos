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

// 1. [MỚI] Class helper để định nghĩa một Tab
class _ReportTabInfo {
  final String title;
  final Widget view;
  final List<Widget> Function(BuildContext) actionsBuilder;

  _ReportTabInfo({
    required this.title,
    required this.view,
    required this.actionsBuilder,
  });
}

class ReportScreen extends StatefulWidget {
  final UserModel currentUser;
  const ReportScreen({super.key, required this.currentUser});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Keys
  final _endOfDayReportKey = GlobalKey<EndOfDayReportTabState>();
  final _inventoryReportKey = GlobalKey<InventoryReportTabState>();
  final _cashFlowReportKey = GlobalKey<CashFlowReportTabState>();
  final _salesReportKey = GlobalKey<SalesReportTabState>();
  final _retailLedgerKey = GlobalKey<RetailSalesLedgerTabState>();

  bool _isSalesLoading = true;
  bool _isEndOfDayLoading = true;
  bool _isRetailLedgerLoading = true;

  // 2. [MỚI] Danh sách các Tab ĐƯỢC PHÉP hiển thị
  List<_ReportTabInfo> _visibleTabs = [];

  @override
  void initState() {
    super.initState();
    _initTabsBasedOnPermissions(); // Khởi tạo danh sách tab trước

    _tabController = TabController(length: _visibleTabs.length, vsync: this);
    _tabController.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });

    // Fix lỗi render sai khi init state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  // 3. [MỚI] Hàm xử lý Logic phân quyền từng Tab
  void _initTabsBasedOnPermissions() {
    final role = widget.currentUser.role;
    final perms = widget.currentUser.permissions ?? {};

    // Helper: Check quyền cụ thể trong permissions map (Owner luôn có quyền)
    bool hasPerm(String group, String key) {
      if (role == 'owner') return true;
      return perms[group]?[key] ?? false;
    }

    // --- 1. LOGIC PHÂN QUYỀN MỚI ---

    bool canViewSales = hasPerm('reports', 'canViewSales');
    bool canViewCashFlow = (role != 'order');
    bool canViewEndOfDay = (role != 'order');
    bool canViewInventory = hasPerm('reports', 'canViewInventory');
    bool canViewRetailLedger = hasPerm('reports', 'canViewRetailLedger');

    List<_ReportTabInfo> allPossibleTabs = [
      if (canViewSales)
        _ReportTabInfo(
          title: 'Tổng quan',
          view: SalesReportTab(
            key: _salesReportKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) setState(() => _isSalesLoading = isLoading);
            },
          ),
          actionsBuilder: (ctx) => _buildSalesActions(ctx),
        ),

      if (canViewCashFlow)
        _ReportTabInfo(
          title: 'Thu Chi',
          view: CashFlowReportTab(
            key: _cashFlowReportKey,
            currentUser: widget.currentUser,
          ),
          actionsBuilder: (ctx) => _buildCashFlowActions(ctx),
        ),

      if (canViewEndOfDay)
        _ReportTabInfo(
          title: 'Tổng kết cuối ngày',
          view: EndOfDayReportTab(
            key: _endOfDayReportKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) setState(() => _isEndOfDayLoading = isLoading);
            },
          ),
          actionsBuilder: (ctx) => _buildEndOfDayActions(ctx),
        ),

      if (canViewInventory)
        _ReportTabInfo(
          title: 'Tồn Kho',
          view: InventoryReportTab(
            key: _inventoryReportKey,
            currentUser: widget.currentUser,
          ),
          actionsBuilder: (ctx) => _buildInventoryActions(ctx),
        ),

      if (canViewRetailLedger)
        _ReportTabInfo(
          title: 'Hàng hóa bán ra',
          view: RetailSalesLedgerTab(
            key: _retailLedgerKey,
            currentUser: widget.currentUser,
            onLoadingChanged: (bool isLoading) {
              if (mounted) setState(() => _isRetailLedgerLoading = isLoading);
            },
          ),
          actionsBuilder: (ctx) => _buildRetailLedgerActions(ctx),
        ),
    ];

    _visibleTabs = allPossibleTabs;
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _handleExport() {
    // [CẬP NHẬT] Logic export cần check loại tab hiện tại là gì thay vì index cứng
    if (_visibleTabs.isEmpty) return;

    // Lấy widget hiện tại đang hiển thị
    final currentWidget = _visibleTabs[_tabController.index].view;

    if (currentWidget is InventoryReportTab) {
      _inventoryReportKey.currentState?.exportReport();
    } else if (currentWidget is RetailSalesLedgerTab) {
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
        icon: _isSalesLoading
            ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(Icons.filter_list,
            color: AppTheme.primaryColor, size: 30),
        tooltip: 'Lọc báo cáo',
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
    return [
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
          endOfDayState?.showFilterModal();
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
          onPressed: _handleExport,
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
    // 4. [MỚI] Xử lý trường hợp không có quyền xem báo cáo nào
    if (_visibleTabs.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Báo Cáo')),
        body: const Center(
          child: Text('Bạn không có quyền xem bất kỳ báo cáo nào.'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo Cáo'),
        actions: [
          // 5. [MỚI] Lấy actionsBuilder từ tab hiện tại trong danh sách visible
          if (_visibleTabs.isNotEmpty)
            ..._visibleTabs[_tabController.index].actionsBuilder(context),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          // 6. [MỚI] Build tabs từ danh sách động
          tabs: _visibleTabs.map((t) => Tab(text: t.title)).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        // 7. [MỚI] Build views từ danh sách động
        children: _visibleTabs.map((t) => t.view).toList(),
      ),
    );
  }
}