// File: lib/screens/sales/table_transfer_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../models/order_model.dart';
import '../../models/table_model.dart';
import '../../models/product_model.dart';
import '../../models/order_item_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../theme/string_extensions.dart';
import '../../services/print_queue_service.dart';
import '../../models/print_job_model.dart';

class TableTransferScreen extends StatefulWidget {
  final UserModel currentUser;
  final OrderModel sourceOrder;
  final TableModel sourceTable;
  final bool isBookingCheckIn;

  const TableTransferScreen({
    super.key,
    required this.currentUser,
    required this.sourceOrder,
    required this.sourceTable,
    this.isBookingCheckIn = false,
  });

  @override
  State<TableTransferScreen> createState() => _TableTransferScreenState();
}

class _TableTransferScreenState extends State<TableTransferScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _firestoreService = FirestoreService();

  late Future<Map<String, dynamic>> _loadDataFuture;
  List<TableModel> _allTables = [];
  List<OrderModel> _allActiveOrders = [];
  Map<String, OrderModel> _allActiveOrdersMap = {};
  List<ProductModel> _allProducts = [];

  Map<String, OrderItem> _sourceItemsForSplit = {};
  final Map<String, OrderItem> _itemsToMove = {};
  TableModel? _selectedSplitTargetTable;
  bool _isProcessing = false;

  TableModel? _selectedTransferTargetTable;

  final Set<TableModel> _selectedMergeSourceTables = {};
  final List<OrderModel> _selectedMergeSourceOrders = [];

  @override
  void initState() {
    super.initState();
    final tabCount = widget.isBookingCheckIn ? 1 : 3;
    _tabController = TabController(length: tabCount, vsync: this);
    _loadDataFuture = _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _loadData() async {
    try {
      _allProducts = await _firestoreService
          .getAllProductsStream(widget.currentUser.storeId)
          .first;
      _allTables = await _firestoreService
          .getAllTablesStream(widget.currentUser.storeId)
          .first;
      _allActiveOrders = await _firestoreService
          .getActiveOrdersStream(widget.currentUser.storeId)
          .first;

      _allActiveOrdersMap = {
        for (var o in _allActiveOrders) o.tableId: o
      };

      // Khởi tạo danh sách món ăn cho việc Tách Bàn
      _sourceItemsForSplit = {
        for (var itemMap in widget.sourceOrder.items)
          itemMap['lineId'] as String: OrderItem.fromMap(
              (itemMap as Map).cast<String, dynamic>(),
              allProducts: _allProducts)
      };
      _sourceItemsForSplit.removeWhere(
              (key, item) => item.status == 'cancelled' || item.quantity <= 0);

      return {
        'products': _allProducts,
        'tables': _allTables,
        'orders': _allActiveOrders,
      };
    } catch (e) {
      debugPrint("Lỗi tải dữ liệu chuyển phòng/bàn: $e");
      throw Exception("Không thể tải dữ liệu: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600; // Đặt breakpoint cho mobile

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isBookingCheckIn
            ? 'Nhận khách: ${widget.sourceTable.tableName}'
            : 'Quản lý Phòng/bàn: ${widget.sourceTable.tableName}'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: widget.isBookingCheckIn
              ? [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.swap_horiz, size: 20),
                  SizedBox(width: 8),
                  Text('Chọn Phòng/bàn nhận khách'),
                ],
              ),
            ),
          ]
              : [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.swap_horiz, size: 20),
                  SizedBox(width: 8),
                  Text('Chuyển Phòng/bàn'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.merge_type, size: 20),
                  SizedBox(width: 8),
                  Text('Gộp Phòng/bàn'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.call_split, size: 20),
                  SizedBox(width: 8),
                  Text('Tách Phòng/bàn'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _loadDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Lỗi tải dữ liệu: ${snapshot.error}'));
          }

          final occupiedTableIds =
          _allActiveOrders.map((o) => o.tableId).toSet();

          // --- LỌC BÀN ĐANG GỘP ---
          // 1. Lấy ID của tất cả các bàn chủ (master)
          final Set<String> masterTableIds = _allTables
              .where((t) => t.mergedWithTableId != null)
              .map((t) => t.mergedWithTableId!)
              .toSet();

          // 2. Lọc ra danh sách bàn "sạch" (không phải là bàn gộp phụ, cũng không phải bàn gộp chủ)
          final List<TableModel> availableTables = _allTables.where((table) {
            final bool isSlave = table.mergedWithTableId != null;
            final bool isMaster = masterTableIds.contains(table.id);
            final bool isCurrentTable = table.id == widget.sourceTable.id;

            return !isSlave && !isMaster && !isCurrentTable;
          }).toList();
          // --- KẾT THÚC LỌC ---

          // 3. Tính toán danh sách bàn trống và bàn có khách từ danh sách "sạch"
          final List<TableModel> emptyTables = availableTables
              .where((t) => !occupiedTableIds.contains(t.id))
              .toList();

          final List<TableModel> occupiedTables = availableTables
              .where((t) => occupiedTableIds.contains(t.id))
              .toList();

          return TabBarView(
            controller: _tabController,
            children: widget.isBookingCheckIn
                ? [
              _buildTransferTableView(context, emptyTables, isMobile),
            ]
                : [
              _buildTransferTableView(context, emptyTables, isMobile),
              _buildMergeTableView(context, occupiedTables, isMobile),
              _buildSplitTableView(context, emptyTables, isMobile),
            ],
          );
        },
      ),
    );
  }

  Future<void> _printTableManagementNotification(
      String actionTitle, String message) async {
    try {
      final jobData = {
        'storeId': widget.currentUser.storeId,
        'userName': widget.currentUser.name ?? 'N/A',
        'actionTitle': actionTitle, // Ví dụ: "CHUYỂN BÀN"
        'message': message, // Ví dụ: "Từ: Bàn 1 -> Đến: Bàn 2"
        'timestamp': DateTime.now().toIso8601String(),
        'tableName': 'Chuyển/Gộp/Tách',
        'items': [],
      };

      // Gửi lệnh in với loại job mới
      await PrintQueueService().addJob(PrintJobType.tableManagement, jobData);
    } catch (e) {
      debugPrint("Lỗi in thông báo quản lý Phòng/bàn: $e");
      // Lỗi âm thầm, không cần thông báo cho người dùng
    }
  }

  Widget _buildSplitTableView(
      BuildContext context, List<TableModel> emptyTables, bool isMobile) {

    final slaveTables = _allTables
        .where((t) => t.mergedWithTableId == widget.sourceTable.id)
        .toList();

    final List<TableModel> splitTargetTables = [...emptyTables, ...slaveTables];

    final panelA = _buildItemListPanel(
      context,
      'Chọn món muốn tách từ: ${widget.sourceTable.tableName}',
      _sourceItemsForSplit,
      _onSourceItemTapped,
      isMobile: isMobile,
    );

    final panelB = _buildItemListPanel(
      context,
      'Danh sách món tách:',
      _itemsToMove,
      _onTargetItemTapped,
      isTargetList: true,
      isMobile: isMobile,
    );

    final panelC = _buildTableGridSelector(
      context,
      'Chọn Phòng/bàn nhận tách món:',
      splitTargetTables,
      _selectedSplitTargetTable,
          (table) {
        setState(() => _selectedSplitTargetTable = table);
      },
      hasShadow: true,
      isMobile: isMobile,
    );

    if (isMobile) {
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                children: [
                  panelA,
                  const SizedBox(height: 8),
                  panelB,
                  const SizedBox(height: 8),
                  panelC,
                ],
              ),
            ),
          ),
          _buildConfirmButton(
            'Tách Phòng/bàn',
            _itemsToMove.isNotEmpty && _selectedSplitTargetTable != null
                ? _performSplit
                : null,
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panelA),
                const SizedBox(width: 16),
                Expanded(child: panelB),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 250,
            child: panelC,
          ),
        ),
        _buildConfirmButton(
          'Tách Phòng/bàn',
          _itemsToMove.isNotEmpty && _selectedSplitTargetTable != null
              ? _performSplit
              : null,
        ),
      ],
    );
  }

  Widget _buildMergeTableView(
      BuildContext context, List<TableModel> occupiedTables, bool isMobile) {

    final panelA = _buildMultiTableGridSelector(
      context,
      'Chọn các Phòng/bàn muốn gộp:',
      occupiedTables,
      _selectedMergeSourceTables,
          (table) {
        setState(() {
          if (_selectedMergeSourceTables.contains(table)) {
            _selectedMergeSourceTables.remove(table);
            _selectedMergeSourceOrders
                .removeWhere((o) => o.tableId == table.id);
          } else {
            final order = _allActiveOrdersMap[table.id];
            if (order != null) {
              _selectedMergeSourceTables.add(table);
              _selectedMergeSourceOrders.add(order);
            } else {
              ToastService().show(
                  message: "Lỗi: Phòng/bàn này không có đơn hàng.",
                  type: ToastType.error);
            }
          }
        });
      },
      hasShadow: true,
      isMobile: isMobile,
    );

    final panelB = Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          _buildOrderPreviewCard("Vào Phòng/bàn:", widget.sourceOrder,
              isTarget: true, isMobile: isMobile),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.add_circle_outline_rounded,
                    size: 28, color: Colors.grey.shade400),
                const SizedBox(width: 8),
                Text("Các Phòng/bàn sẽ được gộp vào:",
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.grey.shade700)),
              ],
            ),
          ),

          isMobile
              ? _buildMergeSourceList(context, _selectedMergeSourceOrders, isMobile)
              : Expanded(
              child: _buildMergeSourceList(
                  context, _selectedMergeSourceOrders, isMobile)),
        ],
      ),
    );

    return Column(
      children: [
        Expanded(
          child: isMobile
              ? SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                panelA,
                const SizedBox(height: 8),
                panelB,
              ],
            ),
          )
              : Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: panelA),
                const SizedBox(width: 16),
                Expanded(child: panelB),
              ],
            ),
          ),
        ),
        _buildConfirmButton(
          'Gộp (${_selectedMergeSourceTables.length}) Phòng/bàn',
          _selectedMergeSourceTables.isNotEmpty ? _performMerge : null,
        ),
      ],
    );
  }

  Widget _buildItemListPanel(
      BuildContext context,
      String title,
      Map<String, OrderItem> items,
      Function(OrderItem) onTap,
      {bool isTargetList = false,
        bool isMobile = false}) {
    final currencyFormat =
    NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final itemEntries = items.entries.toList();

    final listContent = itemEntries.isEmpty
        ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(isTargetList
              ? 'Chạm vào món bên trái để tách'
              : 'Không còn món nào',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ))
        : ListView.builder(
      shrinkWrap: isMobile,
      physics: isMobile ? const NeverScrollableScrollPhysics() : null,
      itemCount: itemEntries.length,
      itemBuilder: (context, index) {
        final item = itemEntries[index].value;
        return ListTile(
          title: Text(
              '${formatNumber(item.quantity)} x ${item.product.productName}'),
          subtitle: Text(currencyFormat.format(item.subtotal)),
          onTap: () => onTap(item),
        );
      },
    );

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Colors.grey),
          isMobile ? listContent : Expanded(child: listContent),
        ],
      ),
    );
  }

  Widget _buildMultiTableGridSelector(
      BuildContext context,
      String title,
      List<TableModel> tables,
      Set<TableModel> selectedTables,
      Function(TableModel) onSelect, {
        bool hasShadow = false,
        bool isMobile = false,
      }) {

    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 120,
      childAspectRatio: isMobile ? 2.2 : 2.8,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

    final gridContent = tables.isEmpty
        ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Không có Phòng/bàn nào phù hợp',
              style: TextStyle(color: Colors.grey.shade600)),
        ))
        : GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: gridDelegate,
      shrinkWrap: isMobile,
      physics: isMobile ? const NeverScrollableScrollPhysics() : null,
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final isSelected = selectedTables.contains(table);
        return ChoiceChip(
          label: SizedBox(
            width: double.infinity,
            child: Text(table.tableName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : AppTheme.textColor)),
          ),
          selected: isSelected,
          selectedColor: AppTheme.primaryColor,
          backgroundColor: Colors.white,
          showCheckmark: false,
          onSelected: (selected) =>
              onSelect(table),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primaryColor
                  : Colors.grey.shade300,
            ),
          ),
        );
      },
    );

    return Card(
      elevation: hasShadow ? 2 : 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Colors.grey),
          isMobile ? gridContent : Expanded(child: gridContent),
        ],
      ),
    );
  }

  // --- WIDGET CHO TAB CHUYỂN BÀN (TRANSFER) ---

  Widget _buildTransferTableView(
      BuildContext context, List<TableModel> emptyTables, bool isMobile) {
    final bool isVirtualTable = widget.sourceTable.tableGroup == 'Online';
    final List<TableModel> targetTables = isVirtualTable
        ? emptyTables.where((t) => t.tableGroup != 'Online').toList()
        : emptyTables;

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                _buildOrderPreviewCard(
                    "Chuyển từ Phòng/bàn:", widget.sourceOrder,
                    isMobile: isMobile),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Icon(Icons.arrow_downward_rounded,
                      size: 28, color: Colors.grey.shade500),
                ),
                Expanded(
                  child: _buildTableGridSelector(
                    context,
                    'Chọn Phòng/bàn chuyển đến:',
                    targetTables,
                    _selectedTransferTargetTable,
                        (table) {
                      setState(() => _selectedTransferTargetTable = table);
                    },
                    hasShadow: true,
                    isMobile: isMobile, // <-- Sửa: truyền isMobile
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildConfirmButton(
          'Chuyển Phòng/bàn',
          _selectedTransferTargetTable != null ? _performTransfer : null,
        ),
      ],
    );
  }

  // --- HÀM MỚI (Helper cho Tab Gộp) ---
  Widget _buildMergeSourceList(
      BuildContext context, List<OrderModel> orders, bool isMobile) {
    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            "Chưa chọn Phòng/bàn nào từ bên trái.",
            style: TextStyle(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      shrinkWrap: isMobile, // <-- SỬA
      physics: isMobile ? const NeverScrollableScrollPhysics() : null, // <-- SỬA
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
        return _buildOrderPreviewCard("Từ Phòng/bàn", order,
            isTarget: false, isMini: true, isMobile: isMobile);
      },
    );
  }

  Widget _buildOrderPreviewCard(String title, OrderModel order,
      {bool isTarget = false, bool isMini = false, bool isMobile = false}) {
    final currencyFormat =
    NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    if (isMini) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: Colors.grey.shade300)),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  order.tableName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  currencyFormat.format(order.totalAmount),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final bool isCompact = isMobile && !isMini;
    final titleStyle = Theme.of(context)
        .textTheme
        .titleLarge
        ?.copyWith(fontWeight: FontWeight.bold);
    final compactTitleStyle = Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.bold);

    return Padding(
      padding: EdgeInsets.zero,
      child: Card(
        elevation: 2,
        color: null,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isTarget
                ? BorderSide.none
                : BorderSide(
                color: Colors.grey.shade300)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.tableName,
                    style: isCompact ? compactTitleStyle : titleStyle, // Sửa
                  ),
                  Text(
                    currencyFormat.format(order.totalAmount),
                    style: isCompact ? compactTitleStyle : titleStyle, // Sửa
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTableGridSelector(
      BuildContext context,
      String title,
      List<TableModel> tables,
      TableModel? selectedTable,
      Function(TableModel) onSelect, {
        bool hasShadow = false,
        bool isMobile = false, // <-- SỬA
      }) {

    // --- SỬA: Điều chỉnh aspect ratio cho mobile ---
    final gridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
      maxCrossAxisExtent: 120,
      childAspectRatio: isMobile ? 2.2 : 2.8, // <-- SỬA
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
    );

    // --- SỬA: Tách riêng nội dung grid ---
    final gridContent = tables.isEmpty
        ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text('Không có Phòng/bàn nào phù hợp',
              style: TextStyle(color: Colors.grey.shade600)),
        ))
        : GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: gridDelegate,
      shrinkWrap: isMobile, // <-- SỬA
      physics: isMobile ? const NeverScrollableScrollPhysics() : null, // <-- SỬA
      itemCount: tables.length,
      itemBuilder: (context, index) {
        final table = tables[index];
        final isSelected = selectedTable?.id == table.id;
        return ChoiceChip(
          label: SizedBox(
            width: double.infinity,
            child: Text(table.tableName,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : AppTheme.textColor)),
          ),
          selected: isSelected,
          selectedColor: AppTheme.primaryColor,
          backgroundColor: Colors.white,
          showCheckmark: false,
          onSelected: (selected) => onSelect(table),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8.0),
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primaryColor
                  : Colors.grey.shade300,
            ),
          ),
        );
      },
    );

    return Card(
      elevation: hasShadow ? 2 : 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: isMobile ? MainAxisSize.min : MainAxisSize.max, // <-- SỬA
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1, thickness: 0.5, color: Colors.grey),
          // --- SỬA: Dùng logic co giãn ---
          isMobile ? gridContent : Expanded(child: gridContent),
        ],
      ),
    );
  }


  Widget _buildConfirmButton(String text, Future<void> Function()? onPressed) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
        ),
        onPressed: _isProcessing
            ? null
            : () async {
          setState(() => _isProcessing = true);
          try {
            // Gọi hàm onPressed, đã được bọc trong async
            await onPressed?.call();
          } catch (e) {
            // Bắt lỗi chung nếu hàm onPressed ném ra
            ToastService().show(
                message: "Đã xảy ra lỗi: $e", type: ToastType.error);
          } finally {
            if (mounted) {
              setState(() => _isProcessing = false);
            }
          }
        },
        child: _isProcessing
            ? const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 3, color: Colors.white))
            : Text(text),
      ),
    );
  }

  void _onSourceItemTapped(OrderItem sourceItem) {
    if (sourceItem.quantity <= 0) return;
    _showSplitQuantityDialog(sourceItem);
  }

  void _onTargetItemTapped(OrderItem targetItem) {
    // Khi chạm vào món đã tách, trả nó về bàn gốc
    setState(() {
      _itemsToMove.remove(targetItem.lineId);

      final sourceItemEntry = _sourceItemsForSplit.entries.firstWhereOrNull(
              (entry) => entry.value.groupKey == targetItem.groupKey);

      if (sourceItemEntry != null) {
        // Nếu món đó còn ở bàn gốc, cộng dồn SL
        _sourceItemsForSplit[sourceItemEntry.key] =
            sourceItemEntry.value.copyWith(
              quantity: sourceItemEntry.value.quantity + targetItem.quantity,
            );
      } else {
        // Nếu không (ví dụ: đã tách hết), thêm nó lại
        _sourceItemsForSplit[targetItem.lineId] = targetItem;
      }
    });
  }

  Future<void> _showSplitQuantityDialog(OrderItem item) async {
    final controller = TextEditingController(text: '1');
    final maxQuantity = item.quantity;
    final navigator = Navigator.of(context);

    final quantityToMove = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Tách món: ${item.product.productName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Số lượng tại Phòng/bàn: ${formatNumber(maxQuantity)}'),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Số lượng cần tách'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => navigator.pop(), child: const Text('Hủy')),
            ElevatedButton(
              onPressed: () {
                final val = parseVN(controller.text);
                if (val <= 0) {
                  ToastService()
                      .show(message: "Số lượng phải > 0", type: ToastType.warning);
                } else if (val > maxQuantity) {
                  ToastService().show(
                      message: "Không thể tách quá ${formatNumber(maxQuantity)}",
                      type: ToastType.warning);
                } else {
                  navigator.pop(val);
                }
              },
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    );

    if (quantityToMove == null || quantityToMove <= 0) return;

    setState(() {
      // 1. Tạo món mới để tách đi
      final newItemToMove = item.copyWith(quantity: quantityToMove);

      // 2. Kiểm tra xem món đó đã có trong danh sách tách chưa (theo groupKey)
      final existingTargetEntry = _itemsToMove.entries.firstWhereOrNull(
              (entry) => entry.value.groupKey == newItemToMove.groupKey);

      if (existingTargetEntry != null) {
        // Nếu có, cộng dồn SL
        _itemsToMove[existingTargetEntry.key] =
            existingTargetEntry.value.copyWith(
              quantity: existingTargetEntry.value.quantity + quantityToMove,
            );
      } else {
        // Nếu chưa, thêm mới
        _itemsToMove[newItemToMove.lineId] = newItemToMove;
      }

      // 3. Giảm SL ở bàn gốc
      final double newSourceQuantity = item.quantity - quantityToMove;
      if (newSourceQuantity <= 0) {
        _sourceItemsForSplit.remove(item.lineId);
      } else {
        _sourceItemsForSplit[item.lineId] =
            item.copyWith(quantity: newSourceQuantity);
      }
    });
  }

  Future<void> _performSplit() async {
    final navigator = Navigator.of(context);
    final targetTable = _selectedSplitTargetTable;
    if (targetTable == null || _itemsToMove.isEmpty) return;

    try {
      final batch = _firestoreService.batch();
      final sourceOrderRef =
      _firestoreService.getOrderReference(widget.sourceOrder.id);
      final targetOrderRef = _firestoreService.getOrderReference(targetTable.id);
      final bool isSplittingToSlave = _allTables.any(
              (t) => t.id == targetTable.id && t.mergedWithTableId == widget.sourceTable.id);
      final sourceSnap = await sourceOrderRef.get();
      final targetSnap = await targetOrderRef.get();

      if (!sourceSnap.exists) {
        throw Exception("Đơn hàng gốc không tồn tại");
      }
      if (!isSplittingToSlave && targetSnap.exists &&
          (targetSnap.data() as Map<String, dynamic>)['status'] == 'active') {
        throw Exception("${targetTable.tableName} đã có khách!");
      }
      // 1. Cập nhật Bàn Gốc (Source)
      final sourceData = sourceSnap.data() as Map<String, dynamic>;
      final currentVersion = (sourceData['version'] as num?)?.toInt() ?? 0;
      final itemsRemaining =
      _sourceItemsForSplit.values.map((e) => e.toMap()).toList();
      final newSourceTotal = _sourceItemsForSplit.values
          .fold(0.0, (tong, item) => tong + item.subtotal);

      if (itemsRemaining.isEmpty) {
        // Nếu tách hết, hủy bàn gốc
        batch.update(sourceOrderRef, {
          'status': 'cancelled',
          'note': 'Tách hết món sang ${targetTable.tableName}',
          'items': [],
          'totalAmount': 0.0,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        // Nếu còn, cập nhật lại
        batch.update(sourceOrderRef, {
          'items': itemsRemaining,
          'totalAmount': newSourceTotal,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // 2. Tạo Bàn Mới (Target)
      final itemsToMove = _itemsToMove.values.map((e) => e.toMap()).toList();
      final newTargetTotal =
      _itemsToMove.values.fold(0.0, (tong, item) => tong + item.subtotal);
      final targetVersion =
          ((targetSnap.data() as Map<String, dynamic>?)?['version'] as num?)
              ?.toInt() ??
              0;

      batch.set(targetOrderRef, {
        'id': targetOrderRef.id,
        'tableId': targetTable.id,
        'tableName': targetTable.tableName,
        'status': 'active',
        'startTime': Timestamp.now(), // Giờ mới
        'items': itemsToMove,
        'totalAmount': newTargetTotal,
        'storeId': widget.currentUser.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': widget.currentUser.uid,
        'createdByName': widget.currentUser.name ?? 'N/A',
        'numberOfCustomers': 1, // Mặc định 1 khách cho bàn mới
        'version': targetVersion + 1,
        'customerId': sourceData['customerId'], // Copy info khách
        'customerName': sourceData['customerName'],
        'customerPhone': sourceData['customerPhone'],
      });

      if (isSplittingToSlave) {
        final targetTableRef = _firestoreService.getTableReference(targetTable.id);
        batch.update(targetTableRef, {
          'mergedWithTableId': null
        });
      }
      await batch.commit();

      try {
        final String itemsText = _itemsToMove.values
            .map((e) =>
        '${e.product.productName} (x${formatNumber(e.quantity)})')
            .join(', ');
        _printTableManagementNotification("TÁCH PHÒNG/BÀN",
            "$itemsText Tách Từ ${widget.sourceTable.tableName} -> Đến ${targetTable.tableName}");
      } catch (e) {
        debugPrint("Lỗi tạo nội dung in tách Phòng/bàn: $e");
      }

      ToastService()
          .show(message: "Tách Phòng/bàn thành công!", type: ToastType.success);
      navigator.pop(true);
    } catch (e) {
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }

  Future<void> _performTransfer() async {
    final navigator = Navigator.of(context);
    final targetTable = _selectedTransferTargetTable;
    if (targetTable == null) return;

    try {
      final batch = _firestoreService.batch();
      final sourceOrderRef =
      _firestoreService.getOrderReference(widget.sourceOrder.id);
      final targetOrderRef = _firestoreService.getOrderReference(targetTable.id);
      final bool isVirtualTable = widget.sourceTable.tableGroup == 'Online';
      final sourceTableRef = _firestoreService.getTableReference(widget.sourceTable.id);

      final sourceSnap = await sourceOrderRef.get();
      final targetSnap = await targetOrderRef.get();

      if (!sourceSnap.exists) {
        throw Exception("Đơn hàng gốc không tồn tại");
      }
      if (targetSnap.exists &&
          (targetSnap.data() as Map<String, dynamic>)['status'] == 'active') {
        throw Exception("${targetTable.tableName} đã có khách!");
      }

      final sourceData = sourceSnap.data() as Map<String, dynamic>;
      final currentVersion = (sourceData['version'] as num?)?.toInt() ?? 0;
      final targetVersion =
          ((targetSnap.data() as Map<String, dynamic>?)?['version'] as num?)
              ?.toInt() ??
              0;

      // 1. Cập nhật Bàn Gốc (Source) -> Hủy
      batch.update(sourceOrderRef, {
        'status': 'cancelled',
        'note': 'Chuyển sang ${targetTable.tableName}',
        'version': currentVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 2. Tạo/Cập nhật Bàn Mới (Target) -> Copy toàn bộ
      final newOrderData = Map<String, dynamic>.from(sourceData);
      newOrderData.addAll({
        'id': targetOrderRef.id,
        'tableId': targetTable.id,
        'tableName': targetTable.tableName,
        'status': 'active',
        'version': targetVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
        'note': null, // Xóa ghi chú "chuyển bàn" cũ
      });
      batch.set(targetOrderRef, newOrderData);

      // 3. Nếu bàn gốc là bàn ảo, xóa nó khỏi collection 'tables'
      if (isVirtualTable) {
        batch.delete(sourceTableRef);
      }

      final slaveTables = _allTables
          .where((t) => t.mergedWithTableId == widget.sourceTable.id)
          .toList();

      for (final slaveTable in slaveTables) {
        final slaveTableRef = _firestoreService.getTableReference(slaveTable.id);
        batch.update(slaveTableRef, {
          'mergedWithTableId': targetTable.id,
        });
      }

      await batch.commit();

      if (!widget.isBookingCheckIn) {
        _printTableManagementNotification("CHUYỂN PHÒNG/BÀN",
            "Từ ${widget.sourceTable.tableName} -> Đến ${targetTable.tableName}");
      }
      ToastService()
          .show(message: "Chuyển Phòng/bàn thành công!", type: ToastType.success);
      navigator.pop({
        'success': true,
        'targetTable': targetTable,
      });
    } catch (e) {
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }

  Future<void> _performMerge() async {
    final navigator = Navigator.of(context);
    if (_selectedMergeSourceOrders.isEmpty) return;

    try {
      final batch = _firestoreService.batch();

      // Bàn Đích (A)
      final sourceOrderRef =
      _firestoreService.getOrderReference(widget.sourceOrder.id);
      final sourceSnap = await sourceOrderRef.get();
      if (!sourceSnap.exists) {
        throw Exception("Đơn hàng gốc (Phòng/bàn đích) không tồn tại");
      }
      final sourceData = sourceSnap.data() as Map<String, dynamic>;

      // 1. Lấy danh sách món ăn gốc của Bàn A
      final List<dynamic> sourceItemsList = sourceData['items'] as List<dynamic>? ?? [];
      final finalItemsMap = {
        for (final itemMap in sourceItemsList.cast<Map<String, dynamic>>()) // <-- Ép kiểu danh sách
          OrderItem.fromMap(itemMap, // <-- Không cần ép kiểu
              allProducts: _allProducts)
              .groupKey: OrderItem.fromMap(
              itemMap, // <-- Không cần ép kiểu
              allProducts: _allProducts)
      };

      // 2. Lấy số khách gốc của Bàn A
      num newCustomerCount = (sourceData['numberOfCustomers'] as num? ?? 1);

      // 3. Lặp qua TẤT CẢ các bàn nguồn (B, C, D...) đã chọn
      for (final orderToMergeFrom in _selectedMergeSourceOrders) {
        final mergeOrderRef =
        _firestoreService.getOrderReference(orderToMergeFrom.id);
        final mergeTableRef =
        _firestoreService.getTableReference(orderToMergeFrom.tableId); // <-- Lấy Table Ref
        final mergeSnap = await mergeOrderRef.get();

        if (!mergeSnap.exists) {
          throw Exception("Đơn hàng của ${orderToMergeFrom.tableName} không tồn tại");
        }

        final mergeData = mergeSnap.data() as Map<String, dynamic>;

        // 3a. Hợp nhất món ăn
        final List<dynamic> itemsToMergeList = mergeData['items'] as List<dynamic>? ?? [];
        final itemsToMerge = itemsToMergeList
            .cast<Map<String, dynamic>>()
            .map((itemMap) => OrderItem.fromMap(
            itemMap,
            allProducts: _allProducts))
            .toList();

        for (final item in itemsToMerge) {
          final key = item.groupKey;
          if (finalItemsMap.containsKey(key)) {
            final existing = finalItemsMap[key]!;

            // Logic gộp ghi chú
            final String? mergedNote = [existing.note, item.note]
                .where((n) => n != null && n.isNotEmpty)
                .join(', ')
                .nullIfEmpty;

            // Logic gộp nhân viên (nếu có)
            final Map<String, String?> mergedStaff = Map.from(existing.commissionStaff ?? {});
            mergedStaff.addAll(item.commissionStaff ?? {});

            finalItemsMap[key] = existing.copyWith(
              quantity: existing.quantity + item.quantity,
              sentQuantity: existing.sentQuantity + item.sentQuantity,
              // Lấy thời gian thêm món sớm hơn
              addedAt: (existing.addedAt.seconds < item.addedAt.seconds)
                  ? existing.addedAt
                  : item.addedAt,
              // Gán ghi chú và nhân viên đã gộp
              note: () => mergedNote,
              commissionStaff: () => mergedStaff.isNotEmpty ? mergedStaff : null,
            );
          } else {
            finalItemsMap[key] = item;
          }
        }

        // 3b. Cộng dồn số khách
        newCustomerCount += (mergeData['numberOfCustomers'] as num? ?? 1);

        // 3c. Hủy Bàn Nguồn (Order B, C, D...)
        final mergeVersion = (mergeData['version'] as num?)?.toInt() ?? 0;
        batch.update(mergeOrderRef, {
          'status': 'cancelled',
          'note': 'Gộp vào bàn ${widget.sourceTable.tableName}',
          'version': mergeVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        // 3d. LIÊN KẾT Bàn Nguồn (Table B, C, D...)
        batch.update(mergeTableRef, {
          'mergedWithTableId': widget.sourceTable.id, // <-- Gán liên kết
        });
      } // Kết thúc vòng lặp for

      // 4. Cập nhật Bàn Đích (A) với TẤT CẢ món ăn và số khách
      final newTotal = finalItemsMap.values
          .fold(0.0, (tong, item) => tong + item.subtotal);
      final sourceVersion = (sourceData['version'] as num?)?.toInt() ?? 0;

      batch.update(sourceOrderRef, {
        'items': finalItemsMap.values.map((e) => e.toMap()).toList(),
        'totalAmount': newTotal,
        'numberOfCustomers': newCustomerCount,
        'version': sourceVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 5. Commit tất cả thay đổi
      await batch.commit();

      try {
        final String sourceTableNames =
        _selectedMergeSourceOrders.map((o) => o.tableName).join(', ');
        _printTableManagementNotification("GỘP BÀN",
            "Gộp $sourceTableNames -> Vào ${widget.sourceTable.tableName}");
      } catch (e) {
        debugPrint("Lỗi tạo nội dung in gộp bàn: $e");
      }

      ToastService()
          .show(message: "Gộp bàn thành công!", type: ToastType.success);
      navigator.pop(true); // Trả về true để order_screen biết cần đóng
    } catch (e) {
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }
}