// File: lib/screens/sales/table_selection_screen.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import '../../models/order_model.dart';
import '../../models/table_group_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import './order_screen.dart';
import '../../models/print_job_model.dart';
import '../../services/print_queue_service.dart';
import '/screens/sales/failed_jobs_sheet.dart';
import '../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../services/pricing_service.dart';
import '../../models/product_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/sales/web_order_list_screen.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:collection/collection.dart';
// [THÊM] Import Discount Service và Model để tính giá real-time
import '../../services/discount_service.dart';
import '../../models/discount_model.dart';

enum TableStatusFilter { all, occupied, empty }

class TableWithOrderInfo {
  final TableModel table;
  final OrderModel? order;
  final Map<String, dynamic>? rawData;

  TableWithOrderInfo({required this.table, this.order, this.rawData});

  bool get isOccupied => order != null;
}

class TableSelectionScreen extends StatefulWidget {
  final UserModel currentUser;

  const TableSelectionScreen({super.key, required this.currentUser});

  @override
  State<TableSelectionScreen> createState() => _TableSelectionScreenState();
}

class _TableSelectionScreenState extends State<TableSelectionScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final DiscountService _discountService = DiscountService(); // [THÊM]
  TableStatusFilter _currentStatusFilter = TableStatusFilter.all;
  late Stream<Map<String, dynamic>> _combinedStream;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _notificationTimer;
  StreamSubscription? _pendingOrdersSubscription;
  int _pendingOrderCount = 0;
  StreamSubscription? _newActiveOrdersSubscription;

  Stream<Map<String, dynamic>> _getCombinedStream() {
    // 1. Khởi tạo Stream
    final tablesStream = _firestoreService.getAllTablesStream(widget.currentUser.storeId);
    final ordersStream = _firestoreService.getActiveOrdersStream(widget.currentUser.storeId);
    final discountsStream = _discountService.getActiveDiscountsStream(widget.currentUser.storeId);

    final activeOrdersRawStream = FirebaseFirestore.instance
        .collection('orders')
        .where('storeId', isEqualTo: widget.currentUser.storeId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => { for (var doc in snapshot.docs) doc.id : doc.data() });

    // 2. GOM DỮ LIỆU THÔ (Chưa tính toán gì ở bước này để chạy nhanh nhất)
    return Rx.combineLatest7(
      tablesStream,
      _firestoreService.getAllTablesStream(widget.currentUser.storeId),
      ordersStream,
      _firestoreService.getTableGroups(widget.currentUser.storeId).asStream(),
      Stream.periodic(const Duration(minutes: 1)).startWith(null),
      activeOrdersRawStream,
      discountsStream,
          (List<TableModel> allTablesRaw,
          List<TableModel> tables,
          List<OrderModel> orders,
          List<TableGroupModel> groups,
          _,
          Map<String, Map<String, dynamic>> ordersRawDataMap,
          List<DiscountModel> activeDiscounts,
          ) {
        // Đóng gói dữ liệu thô và đẩy sang bước tiếp theo
        return {
          'allTablesRaw': allTablesRaw,
          'tables': tables,
          'orders': orders,
          'groups': groups,
          'ordersRawDataMap': ordersRawDataMap,
          'activeDiscounts': activeDiscounts,
        };
      },
    )
    // [QUAN TRỌNG 1] Debounce: Chờ 200ms để gom các thay đổi liên tục và né animation lúc chuyển màn hình
        .debounceTime(const Duration(milliseconds: 300))

    // [QUAN TRỌNG 2] asyncMap: Thực hiện tính toán nặng ở đây
        .asyncMap((data) async {
      final allTablesRaw = data['allTablesRaw'] as List<TableModel>;
      final tables = data['tables'] as List<TableModel>;
      final orders = data['orders'] as List<OrderModel>;
      final groups = data['groups'] as List<TableGroupModel>;
      final ordersRawDataMap = data['ordersRawDataMap'] as Map<String, Map<String, dynamic>>;
      final activeDiscounts = data['activeDiscounts'] as List<DiscountModel>;

      final Map<String, DiscountItem?> discountCache = {};

      // VÒNG LẶP TÍNH TOÁN (CÓ CHIA NHỎ TASK)
      int processedCount = 0;
      for (var order in orders) {
        // [KỸ THUẬT TIME SLICING]
        // Cứ sau mỗi 3 đơn hàng được tính toán, tạm dừng 0ms để nhường CPU cho UI vẽ Frame.
        // Điều này giúp animation không bị khựng dù đang tính toán nặng.
        processedCount++;
        if (processedCount % 1 == 0) {
          await Future.delayed(Duration(milliseconds: 1));
        }

        double recalculatedTotal = 0;

        for (var itemData in order.items) {
          final itemMap = itemData as Map<String, dynamic>;
          final product = ProductModel.fromMap(itemMap['product']);

          // Bỏ qua tính toán nếu là hàng tặng
          final String? note = itemMap['note'];
          if (note != null && note.startsWith("Tặng kèm")) {
            final double price = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
            final double qty = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
            recalculatedTotal += price * qty;
            continue;
          }

          double currentBaseTotal = 0;
          double discountAmount = 0;

          // A. Tính giá gốc
          if (product.serviceSetup?['isTimeBased'] == true) {
            final startTime = itemMap['addedAt'] as Timestamp;
            final isPaused = itemMap['isPaused'] as bool? ?? false;
            final pausedAt = itemMap['pausedAt'] as Timestamp?;
            final totalPausedDuration = (itemMap['totalPausedDurationInSeconds'] as num?)?.toInt() ?? 0;

            final timeResult = TimeBasedPricingService.calculatePriceWithBreakdown(
              product: product,
              startTime: startTime,
              isPaused: isPaused,
              pausedAt: pausedAt,
              totalPausedDurationInSeconds: totalPausedDuration,
            );
            currentBaseTotal = timeResult.totalPrice;
          } else {
            final double price = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
            final double quantity = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
            currentBaseTotal = price * quantity;
          }

          // B. Tìm Discount (Có Cache)
          DiscountItem? discountRule;
          if (discountCache.containsKey(product.id)) {
            discountRule = discountCache[product.id];
          } else {
            discountRule = _discountService.findBestDiscountForProduct(
              product: product,
              activeDiscounts: activeDiscounts,
              customer: null,
              checkTime: (itemMap['addedAt'] as Timestamp).toDate(),
            );
            discountCache[product.id] = discountRule;
          }

          if (discountRule != null) {
            if (discountRule.isPercent) {
              discountAmount = currentBaseTotal * (discountRule.value / 100);
            } else {
              if (product.serviceSetup?['isTimeBased'] == true) {
                // Tính lại giờ cho discount VNĐ
                final startTime = itemMap['addedAt'] as Timestamp;
                final isPaused = itemMap['isPaused'] as bool? ?? false;
                final pausedAt = itemMap['pausedAt'] as Timestamp?;
                final totalPausedDuration = (itemMap['totalPausedDurationInSeconds'] as num?)?.toInt() ?? 0;
                final timeResult = TimeBasedPricingService.calculatePriceWithBreakdown(
                  product: product,
                  startTime: startTime,
                  isPaused: isPaused,
                  pausedAt: pausedAt,
                  totalPausedDurationInSeconds: totalPausedDuration,
                );
                double totalHours = timeResult.totalMinutesBilled / 60.0;
                discountAmount = totalHours * discountRule.value;
              } else {
                final double quantity = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
                discountAmount = quantity * discountRule.value;
              }
            }
          } else {
            // Fallback giảm giá thủ công
            final double storedDiscountVal = (itemMap['discountValue'] as num?)?.toDouble() ?? 0.0;
            final String storedDiscountUnit = (itemMap['discountUnit'] as String?) ?? '%';
            if (storedDiscountVal > 0) {
              if (storedDiscountUnit == '%') {
                discountAmount = currentBaseTotal * (storedDiscountVal / 100);
              } else {
                discountAmount = storedDiscountVal;
              }
            }
          }

          double itemFinalPrice = (currentBaseTotal - discountAmount).clamp(0, double.infinity);
          recalculatedTotal += itemFinalPrice;
        }
        order.totalAmount = recalculatedTotal;
      }

      // 4. Mapping dữ liệu cuối cùng
      final orderMap = {for (var order in orders) order.tableId: order};

      final tablesWithInfo = tables.map((table) {
        final orderModel = orderMap[table.id];
        Map<String, dynamic>? rawData;
        if (orderModel != null) {
          rawData = ordersRawDataMap[orderModel.id];
        }
        return TableWithOrderInfo(table: table, order: orderModel, rawData: rawData);
      }).toList();

      final bool hasOnlineTables = tables.any((t) => t.tableGroup == 'Online');
      List<TableGroupModel> finalGroups = List.from(groups);
      if (hasOnlineTables && !groups.any((g) => g.name == 'Online')) {
        final onlineGroup = TableGroupModel(
            id: 'virtual_online_group',
            name: 'Online',
            stt: -1,
            storeId: widget.currentUser.storeId
        );
        finalGroups.insert(0, onlineGroup);
      }

      return {
        'allTablesRaw': allTablesRaw,
        'tablesWithInfo': tablesWithInfo,
        'groups': finalGroups,
        'activeOrders': orders,
        'allActiveOrdersRawDataMap': ordersRawDataMap,
      };
    });
  }

  @override
  void initState() {
    super.initState();
    _combinedStream = _getCombinedStream();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initPendingOrdersListener();
        _initNewActiveOrdersListener();
      }
    });
  }

  @override
  void dispose() {
    _newActiveOrdersSubscription?.cancel();
    _pendingOrdersSubscription?.cancel();
    _stopNotificationSound();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _initPendingOrdersListener() {
    _audioPlayer.setSource(AssetSource('tiengchuong.wav'));
    _audioPlayer.setReleaseMode(ReleaseMode.stop);

    final query = FirebaseFirestore.instance
        .collection('web_orders')
        .where('storeId', isEqualTo: widget.currentUser.storeId)
        .where('status', isEqualTo: 'pending');

    _pendingOrdersSubscription = query.snapshots().listen((snapshot) {
      final newCount = snapshot.docs.length;

      if (newCount > 0 && _pendingOrderCount == 0) {
        _startNotificationSound();
      } else if (newCount == 0) {
        _stopNotificationSound();
      }

      if (mounted) {
        setState(() {
          _pendingOrderCount = newCount;
        });
      }
    });
  }

  void _initNewActiveOrdersListener() {
    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('storeId', isEqualTo: widget.currentUser.storeId)
        .where('status', isEqualTo: 'active')
        .where('createdByUid', isGreaterThanOrEqualTo: 'guest_')
        .where('createdByUid', isLessThan: 'guest' '\uf8ff')
        .where('kitchenPrinted', isEqualTo: false);

    _newActiveOrdersSubscription = query.snapshots().listen((snapshot) {
      if (snapshot.docs.isEmpty) return;

      for (final doc in snapshot.docs) {
        try {
          final orderData = doc.data();
          final items = (orderData['items'] as List?) ?? [];
          final List<Map<String, dynamic>> itemsToPrint = [];
          bool hasChanges = false;

          final List<Map<String, dynamic>> updatedItemsForDB = items.map((item) {
            final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
            final num sentQty = map['sentQuantity'] ?? 0;
            final num qty = map['quantity'] ?? 0;

            if (qty > sentQty) {
              final num changeToPrint = qty - sentQty;
              hasChanges = true;
              final Map<String, dynamic> printPayload = Map<String, dynamic>.from(map);
              printPayload['quantity'] = changeToPrint;
              itemsToPrint.add(printPayload);
              map['sentQuantity'] = qty;
            }
            return map;
          }).toList();

          if (hasChanges) {
            PrintQueueService().addJob(PrintJobType.kitchen, {
              'storeId': orderData['storeId'],
              'tableName': orderData['tableName'],
              'userName': orderData['createdByName'] ?? 'Guest',
              'items': itemsToPrint,
              'printType': 'add',
            });

            doc.reference.update({
              'kitchenPrinted': true,
              'items': updatedItemsForDB
            });
          } else if (orderData['kitchenPrinted'] != true) {
            doc.reference.update({'kitchenPrinted': true});
          }
        } catch (e) {
          debugPrint("Lỗi tự động in bếp: $e");
          doc.reference.update({'kitchenPrinted': 'error'});
        }
      }
    });
  }

  void _startNotificationSound() {
    _notificationTimer?.cancel();

    _audioPlayer.stop().then((_) {
      if (mounted) {
        _audioPlayer.play(AssetSource('tiengchuong.wav'));
      }
    });
    _notificationTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _audioPlayer.stop().then((_) {
          if (mounted) {
            _audioPlayer.play(AssetSource('tiengchuong.wav'));
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  void _stopNotificationSound() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
    _audioPlayer.stop();
  }

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;
    const double mobileBreakpoint = 650.0;
    final bool isMobile = screenWidth < mobileBreakpoint;

    return StreamBuilder<Map<String, dynamic>>(
      stream: _combinedStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(body: Center(child: Text('Lỗi: ${snapshot.error}')));
        }
        if (!snapshot.hasData || snapshot.data == null) {
          return const Scaffold(body: Center(child: Text('Không có dữ liệu.')));
        }
        final List<TableWithOrderInfo> allTables =
        snapshot.data!['tablesWithInfo'];
        final List<TableModel> allTablesRaw = snapshot.data!['allTablesRaw'];
        final List<TableGroupModel> groups = snapshot.data!['groups'];
        List<OrderModel> activeOrders = snapshot.data!['activeOrders'];
        final Map<String, Map<String, dynamic>> allActiveOrdersRawDataMap =
        snapshot.data!['allActiveOrdersRawDataMap'];

        // Tổng tiền hiển thị ở App Bar (đã được tính lại real-time trong Stream)
        double liveTotalProvisionalAmount = activeOrders.fold(0, (tong, order) => tong + order.totalAmount);

        final groupNames = ['Tất cả', ...groups.map((g) => g.name)];
        final occupiedCount = activeOrders.length;
        final double toolbarContentHeight =
        isMobile ? (kToolbarHeight + 40.0) : (kToolbarHeight + 16.0);

        return DefaultTabController(
          length: groupNames.length,
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: toolbarContentHeight,
              automaticallyImplyLeading: false,
              title: isMobile
                  ? _buildMobileAppBarContent(occupiedCount, allTables.length,
                  liveTotalProvisionalAmount)
                  : _buildDesktopAppBarContent(occupiedCount, allTables.length,
                  liveTotalProvisionalAmount),
              bottom: TabBar(
                isScrollable: true,
                tabs: groupNames.map((name) => Tab(text: name)).toList(),
              ),
            ),
            body: TabBarView(
              children: groupNames.map((groupName) {
                List<TableWithOrderInfo> filteredList =
                allTables.where((tableInfo) {
                  final bool groupMatch = (groupName == 'Tất cả') ||
                      (tableInfo.table.tableGroup == groupName);
                  if (!groupMatch) return false;
                  switch (_currentStatusFilter) {
                    case TableStatusFilter.occupied:
                      return tableInfo.isOccupied;
                    case TableStatusFilter.empty:
                      return !tableInfo.isOccupied;
                    case TableStatusFilter.all:
                      return true;
                  }
                }).toList();

                if (filteredList.isEmpty) {
                  return const Center(child: Text('Không có bàn nào phù hợp.'));
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16.0),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 1.0,
                    crossAxisSpacing: 20,
                    mainAxisSpacing: 20,
                  ),
                  itemCount: filteredList.length,
                  itemBuilder: (context, index) {
                    return _TableCard(
                      tableInfo: filteredList[index],
                      currentUser: widget.currentUser,
                      allTablesRaw: allTablesRaw,
                      allActiveOrders: activeOrders,
                      allActiveOrdersRawDataMap: allActiveOrdersRawDataMap,
                    );
                  },
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopAppBarContent(
      int occupiedCount, int totalCount, double totalAmount) {
    return Row(
      children: [
        _buildStatusFilterDropdown(),
        const SizedBox(width: 16),
        _buildTableInfoTitle(occupiedCount, totalCount, totalAmount),
        const Spacer(),
        ..._buildAppBarActions(),
      ],
    );
  }

  Widget _buildMobileAppBarContent(
      int occupiedCount, int totalCount, double totalAmount) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildStatusFilterDropdown(),
            const Spacer(),
            ..._buildAppBarActions(),
          ],
        ),
        const SizedBox(height: 8),
        _buildTableInfoTitle(occupiedCount, totalCount, totalAmount),
      ],
    );
  }

  Widget _buildStatusFilterDropdown() {
    return SizedBox(
      width: 170,
      child: AppDropdown<TableStatusFilter>(
        labelText: 'Trạng thái',
        value: _currentStatusFilter,
        isDense: true,
        items: const [
          DropdownMenuItem(value: TableStatusFilter.all, child: Text('Tất cả')),
          DropdownMenuItem(
              value: TableStatusFilter.occupied, child: Text('Có khách')),
          DropdownMenuItem(
              value: TableStatusFilter.empty, child: Text('Bàn trống')),
        ],
        onChanged: (value) {
          setState(() {
            _currentStatusFilter = value ?? TableStatusFilter.all;
          });
        },
      ),
    );
  }

  Widget _buildTableInfoTitle(
      int occupiedCount, int totalCount, double totalAmount) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.table_restaurant_rounded, size: 25, color: AppTheme.primaryColor),
        const SizedBox(width: 4),
        Text(
          '$occupiedCount/$totalCount',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Icon(Icons.attach_money, size: 25, color: AppTheme.primaryColor),
        Flexible(
          child: Text(
            NumberFormat.currency(locale: 'vi_VN', symbol: 'đ')
                .format(totalAmount),
            style: textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAppBarActions() {
    return [
      Badge(
        backgroundColor: Colors.red,
        offset: const Offset(-2, 2),
        label: Text(
          _pendingOrderCount.toString(),
          style: const TextStyle(color: Colors.white),
        ),
        isLabelVisible: _pendingOrderCount > 0,
        child: IconButton(
          icon: const Icon(Icons.phonelink_outlined,
              color: AppTheme.primaryColor, size: 30),
          tooltip: 'Đơn hàng Online',
          onPressed: () {
            _stopNotificationSound();

            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => WebOrderListScreen(
                  currentUser: widget.currentUser,
                ),
              ),
            );
          },
        ),
      ),
      ValueListenableBuilder<List<PrintJob>>(
        valueListenable: PrintQueueService().failedJobsNotifier,
        builder: (context, failedJobs, _) => Badge(
          backgroundColor: Colors.red,
          offset: const Offset(-2, 2),
          label: Text(
            failedJobs.length.toString(),
            style: const TextStyle(color: Colors.white),
          ),
          isLabelVisible: failedJobs.isNotEmpty,
          child: IconButton(
            icon: const Icon(Icons.print_disabled_outlined,
                color: AppTheme.primaryColor, size: 30),
            tooltip: 'Lệnh in lỗi',
            onPressed: () => failedJobs.isNotEmpty
                ? _showFailedJobsSheet()
                : ToastService().show(
                message: "Không có lệnh in lỗi.", type: ToastType.warning),
          ),
        ),
      ),
    ];
  }

  void _showFailedJobsSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FailedJobsSheet(),
    );
  }
}

class _TableCard extends StatelessWidget {
  final TableWithOrderInfo tableInfo;
  final UserModel currentUser;
  final List<TableModel> allTablesRaw;
  final List<OrderModel> allActiveOrders;
  final Map<String, Map<String, dynamic>> allActiveOrdersRawDataMap;

  const _TableCard({
    required this.tableInfo,
    required this.currentUser,
    required this.allTablesRaw,
    required this.allActiveOrders,
    required this.allActiveOrdersRawDataMap,
  });

  // [HÀM MỚI] Tính chênh lệch phút bỏ qua giây (VD: 13:01 -> 13:06 = 5 phút)
  int _diffInMinutes(DateTime from, DateTime to) {
    // Tạo DateTime mới chỉ giữ lại đến phút (giây = 0)
    final start = DateTime(from.year, from.month, from.day, from.hour, from.minute);
    final end = DateTime(to.year, to.month, to.day, to.hour, to.minute);
    return end.difference(start).inMinutes;
  }

  // [SỬA] Logic hiển thị: Bàn thường (đếm thời gian), Booking (đếm ngược/trễ)
  String _formatDurationCustom(DateTime startTime, {bool isCountdown = false}) {
    final now = DateTime.now();

    // Nếu là đếm ngược (Booking), startTime là giờ hẹn.
    // Nếu là đếm xuôi (Bàn thường), startTime là giờ vào.

    if (!isCountdown) {
      // --- LOGIC BÀN THƯỜNG ---
      // Tính từ lúc vào đến bây giờ. Luôn dương.
      final int minutesDiff = _diffInMinutes(startTime, now);
      return _formatMinutesToLabel(minutesDiff);
    } else {
      // --- LOGIC BOOKING ---
      // Tính chênh lệch: Hiện tại - Giờ hẹn
      final int diff = _diffInMinutes(startTime, now);

      if (diff > 0) {
        // Hiện tại lớn hơn giờ hẹn -> Trễ
        return "Trễ ${_formatMinutesToLabel(diff)}";
      } else if (diff == 0) {
        return "Đến giờ";
      } else {
        // Hiện tại nhỏ hơn giờ hẹn -> Còn sớm (Lấy trị tuyệt đối)
        return "Còn ${_formatMinutesToLabel(diff.abs())}";
      }
    }
  }

  String _formatMinutesToLabel(int totalMinutes) {
    final days = totalMinutes ~/ 1440;
    final hours = (totalMinutes % 1440) ~/ 60;
    final minutes = totalMinutes % 60;

    final List<String> parts = [];
    if (days > 0) parts.add('${days}d');
    if (hours > 0) parts.add('${hours}h');
    parts.add("${minutes.toString().padLeft(2, '0')}'");

    return parts.join(' ');
  }

  Color _generateColorFromId(String id) {
    final hash = id.hashCode;
    final hue = hash.abs() % 360;
    final saturation = 0.4 + (hash.abs() % 40) / 100.0;
    final lightness = 0.4 + (hash.abs() % 20) / 100.0;
    return HSLColor.fromAHSL(1.0, hue.toDouble(), saturation, lightness).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final table = tableInfo.table;
    final String? masterTableId = table.mergedWithTableId;
    final bool isMergedSlave = masterTableId != null && masterTableId.isNotEmpty;

    OrderModel? displayOrder;
    Map<String, dynamic>? displayRawData;
    TableModel? masterTable;
    String? effectiveMergeId;
    TableModel tableToOpen = table;

    if (isMergedSlave) {
      masterTable = allTablesRaw.firstWhereOrNull((t) => t.id == masterTableId);
      if (masterTable != null) {
        displayOrder = allActiveOrders.firstWhereOrNull((o) => o.tableId == masterTableId);
        if (displayOrder != null) {
          displayRawData = allActiveOrdersRawDataMap[displayOrder.id];
        }
        effectiveMergeId = masterTableId;
        tableToOpen = masterTable;
      } else {
        displayOrder = tableInfo.order;
        displayRawData = tableInfo.rawData;
      }
    } else {
      displayOrder = tableInfo.order;
      displayRawData = tableInfo.rawData;
      tableToOpen = table;
      final bool isMergedMaster = allTablesRaw.any((t) => t.mergedWithTableId == table.id);
      if (isMergedMaster && displayOrder != null) {
        effectiveMergeId = table.id;
      }
    }

    final bool isMerged = effectiveMergeId != null;
    final Color? mergeColor = isMerged ? _generateColorFromId(effectiveMergeId) : null;
    final bool isOccupied = displayOrder != null;
    final order = displayOrder;
    final rawData = displayRawData;
    final bool isOnlineGroup = table.tableGroup == 'Online';
    final bool isScheduleOrder = isOnlineGroup && table.id.startsWith('schedule_');
    final bool isShipOrder = isOnlineGroup && table.id.startsWith('ship_');

    String duration = '';
    String entryTime = '';
    bool isCountdown = false;
    DateTime? appointmentTime;

    if (isOccupied && order != null) {
      // 1. Logic thời gian vào / Giờ hẹn
      if (isScheduleOrder) {
        final String? appointmentString = rawData?['guestAddress'] as String?;
        if (appointmentString != null && appointmentString.isNotEmpty) {
          try {
            final format = DateFormat('HH:mm dd/MM/yy', 'vi_VN');
            appointmentTime = format.parseStrict(appointmentString);
            entryTime = appointmentString;
            isCountdown = true;
            // Với booking: tính từ giờ hẹn
            duration = _formatDurationCustom(appointmentTime, isCountdown: true);
          } catch (e) {
            // Thử định dạng cũ
            try {
              final oldFormat = DateFormat('HH:mm - dd/MM/yyyy', 'vi_VN');
              appointmentTime = oldFormat.parseStrict(appointmentString);
              entryTime = DateFormat('HH:mm dd/MM/yy', 'vi_VN').format(appointmentTime);
              isCountdown = true;
              duration = _formatDurationCustom(appointmentTime, isCountdown: true);
            } catch (e2) {
              entryTime = "Lỗi giờ hẹn";
              duration = "--";
            }
          }
        } else {
          entryTime = "Không có giờ hẹn";
          duration = "--";
        }
      } else {
        // Bàn thường: Tính từ lúc tạo đơn
        entryTime = DateFormat('HH:mm dd/MM/yy', 'vi_VN').format(order.startTime.toDate());
        isCountdown = false;
        duration = _formatDurationCustom(order.startTime.toDate(), isCountdown: false);
      }
    }

    final Color occupiedColorBase;
    if (isScheduleOrder) {
      occupiedColorBase = Colors.blue;
    } else if (isShipOrder) {
      occupiedColorBase = Colors.orange;
    } else {
      occupiedColorBase = AppTheme.primaryColor;
    }

    final Color occupiedColor = Color.alphaBlend(
        occupiedColorBase.withAlpha((255 * 0.1).round()),
        Theme.of(context).cardColor);

    final String displayText;
    if (isOccupied && (isOnlineGroup || (rawData?['customerName'] as String?)?.isNotEmpty == true)) {
      final String? customerName = rawData?['customerName'] as String?;
      if (customerName != null && customerName.isNotEmpty) {
        displayText = customerName;
      } else {
        displayText = 'Đơn Online';
      }
    } else if (isOccupied && order != null) {
      displayText = '${order.numberOfCustomers ?? 1} khách';
    } else {
      displayText = 'Bàn trống';
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => OrderScreen(
            currentUser: currentUser,
            table: tableToOpen,
            initialOrder: displayOrder,
          ),
        ));
      },
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              color: isOccupied ? occupiedColor : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isOccupied
                    ? (mergeColor ?? occupiedColorBase.withAlpha((122).round()))
                    : Colors.grey.shade200,
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                    color: Colors.grey.withAlpha((25).round()),
                    spreadRadius: 1,
                    blurRadius: 5,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isOccupied ? (mergeColor ?? occupiedColorBase) : Colors.grey.shade400,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: Text(
                    table.tableName,
                    textAlign: TextAlign.center,
                    style: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: isOccupied && order != null
                          ? [
                        _buildInfoRow(
                          context,
                          icon: isScheduleOrder
                              ? Icons.people_alt_outlined
                              : (isShipOrder
                              ? Icons.local_shipping_outlined
                              : Icons.people_alt_outlined),
                          text: displayText,
                        ),
                        // HIỂN THỊ TỔNG TIỀN ĐÃ ĐƯỢC CẬP NHẬT REAL-TIME
                        _buildInfoRow(context, icon: Icons.payments_outlined, text: NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(order.totalAmount)),
                        _buildInfoRow(
                            context,
                            icon: isScheduleOrder ? Icons.calendar_month_outlined : Icons.access_time_outlined,
                            text: entryTime
                        ),
                      ]
                          : [
                        Center(child: Text('Bàn trống', style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600)))
                      ],
                    ),
                  ),
                ),
                if (isOccupied)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.withAlpha((25).round()),
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            isCountdown ? Icons.timelapse : Icons.timer_outlined,
                            size: 16,
                            color: isCountdown
                                ? (duration.contains("Trễ") ? Colors.red : Colors.blue)
                                : Colors.black54
                        ),
                        const SizedBox(width: 4),
                        Text(
                            duration,
                            style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isCountdown
                                    ? (duration.contains("Trễ") ? Colors.red : Colors.blue)
                                    : null
                            )
                        ),
                      ],
                    ),
                  )
              ],
            ),
          ),
          if (order?.provisionalBillPrintedAt != null)
            Builder(
              builder: (context) {
                Color iconColor = Colors.blue;
                if (order?.provisionalBillSource == 'payment_screen') {
                  iconColor = Colors.red;
                }
                return Positioned(
                  top: -5,
                  right: -8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            spreadRadius: 1)
                      ],
                    ),
                    child:
                    Icon(Icons.print_rounded, color: iconColor, size: 20),
                  ),
                );
              },
            ),
          if (isMerged)
            Positioned(
              top: -5,
              left: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        spreadRadius: 1)
                  ],
                ),
                child:
                Icon(Icons.link_rounded, color: mergeColor, size: 20),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context,
      {required IconData icon, String? text, Widget? child}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Icon(icon,
            color: AppTheme.textColor.withAlpha((255 * 0.7).round()), size: 16),
        const SizedBox(width: 6),
        Expanded(
          child: child ??
              Text(
                text ?? '',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
              ),
        ),
      ],
    );
  }
}