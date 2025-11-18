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
  TableStatusFilter _currentStatusFilter = TableStatusFilter.all;
  late Stream<Map<String, dynamic>> _combinedStream;

  final AudioPlayer _audioPlayer = AudioPlayer();
  Timer? _notificationTimer;
  StreamSubscription? _pendingOrdersSubscription;
  int _pendingOrderCount = 0;
  StreamSubscription? _newActiveOrdersSubscription;

  Stream<Map<String, dynamic>> _getCombinedStream() {
    final tablesStream = _firestoreService.getAllTablesStream(widget.currentUser.storeId);
    final ordersStream = _firestoreService.getActiveOrdersStream(widget.currentUser.storeId);

    final activeOrdersRawStream = FirebaseFirestore.instance
        .collection('orders')
        .where('storeId', isEqualTo: widget.currentUser.storeId)
        .where('status', isEqualTo: 'active')
        .snapshots()
        .map((snapshot) => { for (var doc in snapshot.docs) doc.id : doc.data() });

    return Rx.combineLatest6(
      tablesStream,
      _firestoreService.getAllTablesStream(widget.currentUser.storeId),
      ordersStream,
      _firestoreService.getTableGroups(widget.currentUser.storeId).asStream(),
      Stream.periodic(const Duration(minutes: 1)).startWith(null),
      activeOrdersRawStream,
          ( List<TableModel> allTablesRaw,
          List<TableModel> tables,
          List<OrderModel> orders,
          List<TableGroupModel> groups,
          _,
          Map<String, Map<String, dynamic>> ordersRawDataMap
          ) {

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
      },
    );
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
    // Đảm bảo set source 1 lần khi khởi tạo
    _audioPlayer.setSource(AssetSource('tiengchuong.wav')); // <-- Dùng file WAV
    _audioPlayer.setReleaseMode(ReleaseMode.stop); // Dừng sau khi phát xong

    final query = FirebaseFirestore.instance
        .collection('web_orders')
        .where('storeId', isEqualTo: widget.currentUser.storeId)
        .where('status', isEqualTo: 'pending');

    _pendingOrdersSubscription = query.snapshots().listen((snapshot) {
      final newCount = snapshot.docs.length;

      if (newCount > 0 && _pendingOrderCount == 0) {
        // Có đơn mới (chuyển từ 0 -> 1+)
        _startNotificationSound();
      } else if (newCount == 0) {
        // Không còn đơn nào
        _stopNotificationSound();
      }

      // Cập nhật UI
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

          // --- SỬA LỖI: Thao tác trực tiếp trên Map, không cần OrderItem ---

          final List<Map<String, dynamic>> itemsToPrint = [];
          bool hasChanges = false; // Cờ để xem có cần update DB không

          // 1. Tạo danh sách item MỚI (đã cập nhật) để ghi lại vào DB
          final List<Map<String, dynamic>> updatedItemsForDB = items.map((item) {
            final map = Map<String, dynamic>.from(item as Map<String, dynamic>);
            final num sentQty = map['sentQuantity'] ?? 0;
            final num qty = map['quantity'] ?? 0;

            // 1. Chỉ in khi số lượng mới > số lượng đã in
            if (qty > sentQty) {
              final num changeToPrint = qty - sentQty; // Số lượng chênh lệch
              hasChanges = true;

              // 2. Tạo payload để in (chỉ in số lượng chênh lệch)
              final Map<String, dynamic> printPayload = Map<String, dynamic>.from(map);
              printPayload['quantity'] = changeToPrint;
              itemsToPrint.add(printPayload);

              // 3. Cập nhật 'sentQuantity' trong bản đồ để lưu vào DB
              map['sentQuantity'] = qty;
            }
            return map;
          }).toList();

          // 2. Nếu có món mới, Gửi in VÀ Cập nhật DB
          if (hasChanges) {

            PrintQueueService().addJob(PrintJobType.kitchen, {
              'storeId': orderData['storeId'],
              'tableName': orderData['tableName'],
              'userName': orderData['createdByName'] ?? 'Guest',
              'items': itemsToPrint, // Chỉ gửi các món mới
              'printType': 'add',
            });

            // 3. Cập nhật DB
            doc.reference.update({
              'kitchenPrinted': true,
              'items': updatedItemsForDB
            });

          } else if (orderData['kitchenPrinted'] != true) {
            // Không có món mới, chỉ cần đánh dấu là đã check
            doc.reference.update({'kitchenPrinted': true});
          }
          // --- KẾT THÚC SỬA ---

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

        double liveTotalProvisionalAmount = 0;
        for (var order in activeOrders) {
          double currentOrderTotal = 0;
          bool hasTimeBasedItem = false;

          for (var itemData in order.items) {
            final itemMap = itemData as Map<String, dynamic>;

            final product = ProductModel.fromMap(itemMap['product']);
            final serviceSetup = product.serviceSetup;

            if (serviceSetup != null && serviceSetup['isTimeBased'] == true) {
              hasTimeBasedItem = true;
              final startTime = itemMap['addedAt'] as Timestamp;
              final isPaused = itemMap['isPaused'] as bool? ?? false;
              final pausedAt = itemMap['pausedAt'] as Timestamp?;
              final totalPausedDuration =
                  (itemMap['totalPausedDurationInSeconds'] as num?)?.toInt() ??
                      0;

              final timeResult =
                  TimeBasedPricingService.calculatePriceWithBreakdown(
                product: product,
                startTime: startTime,
                isPaused: isPaused,
                pausedAt: pausedAt,
                totalPausedDurationInSeconds: totalPausedDuration,
              );
              currentOrderTotal += timeResult.totalPrice;
            } else {
              currentOrderTotal +=
                  (itemMap['subtotal'] as num?)?.toDouble() ?? 0.0;
            }
          }
          liveTotalProvisionalAmount += currentOrderTotal;

          if (hasTimeBasedItem) {
            order.totalAmount = currentOrderTotal;
          }
        }

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

  String _formatDuration(Duration d, {bool isCountdown = false}) {
    // Luôn dùng abs() để tính toán, sau đó kiểm tra cờ isNegative
    final totalMinutes = d.abs().inMinutes;

    if (totalMinutes < 1) {
      if (isCountdown) return "Sắp đến";
      // Nếu không phải đếm ngược, nghĩa là đã qua
      return d.isNegative ? "Vừa trễ" : "Vừa xong";
    }

    final days = totalMinutes ~/ 1440;
    final hours = (totalMinutes % 1440) ~/ 60;
    final minutes = totalMinutes % 60;

    final List<String> parts = [];
    if (days > 0) {
      parts.add('${days}d');
    }
    if (hours > 0) {
      parts.add('${hours}h');
    }
    // Luôn hiển thị phút
    parts.add("${minutes.toString().padLeft(2, '0')}'");

    final timeString = parts.join(' ');

    if (isCountdown) {
      return 'Còn $timeString';
    }

    // Nếu không đếm ngược, kiểm tra xem có bị trễ (âm) không
    if (d.isNegative) {
      return 'Trễ $timeString';
    }

    // Mặc định là thời gian đã qua
    return timeString;
  }

  Color _generateColorFromId(String id) {
    final hash = id.hashCode;
    final hue = hash.abs() % 360;
    final saturation = 0.4 + (hash.abs() % 40) / 100.0; // 0.4 -> 0.8
    final lightness = 0.4 + (hash.abs() % 20) / 100.0; // 0.4 -> 0.6

    return HSLColor.fromAHSL(1.0, hue.toDouble(), saturation, lightness)
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final table = tableInfo.table; // Bàn gốc (1)

    // --- LOGIC MỚI: XÁC ĐỊNH BÀN, ĐƠN HÀNG ĐỂ HIỂN THỊ ---
    final String? masterTableId = table.mergedWithTableId;
    final bool isMergedSlave = masterTableId != null && masterTableId.isNotEmpty;

    OrderModel? displayOrder;
    Map<String, dynamic>? displayRawData;
    TableModel? masterTable;
    String? effectiveMergeId; // ID để tô màu
    TableModel tableToOpen = table; // Bàn sẽ mở khi tap

    if (isMergedSlave) {
      // 1. Đây là Bàn "Phụ" (Bàn 2)
      masterTable = allTablesRaw.firstWhereOrNull((t) => t.id == masterTableId);
      if (masterTable != null) {
        displayOrder = allActiveOrders.firstWhereOrNull(
                (o) => o.tableId == masterTableId);
        if (displayOrder != null) {
          displayRawData = allActiveOrdersRawDataMap[displayOrder.id];
        }
        effectiveMergeId = masterTableId;
        tableToOpen = masterTable; // Khi tap sẽ mở bàn chủ
      } else {
        // Lỗi: Bàn chủ không tồn tại, hiển thị như bàn bình thường
        displayOrder = tableInfo.order;
        displayRawData = tableInfo.rawData;
      }
    } else {
      // 2. Đây là Bàn "Thường" hoặc "Chủ" (Bàn 1)
      displayOrder = tableInfo.order;
      displayRawData = tableInfo.rawData;
      tableToOpen = table; // Khi tap mở chính nó

      final bool isMergedMaster = allTablesRaw.any((t) => t.mergedWithTableId == table.id);
      if (isMergedMaster && displayOrder != null) { // Chỉ là master nếu có khách
        effectiveMergeId = table.id; // Lấy ID của chính nó để tô màu
      }
    }

    final bool isMerged = effectiveMergeId != null;
    final Color? mergeColor = isMerged ? _generateColorFromId(effectiveMergeId) : null;

    final bool isOccupied = displayOrder != null;
    final order = displayOrder; // Đơn hàng để hiển thị
    final rawData = displayRawData; // Dữ liệu thô để hiển thị
    final bool isOnlineGroup = table.tableGroup == 'Online';
    final bool isScheduleOrder = isOnlineGroup && table.id.startsWith('schedule_');
    final bool isShipOrder = isOnlineGroup && table.id.startsWith('ship_');

    String duration = '';
    String entryTime = '';
    bool isCountdown = false;
    DateTime? appointmentTime;

    if (isOccupied && order != null) {
      final difference = DateTime.now().difference(order.startTime.toDate());
      duration = _formatDuration(difference, isCountdown: false);
      entryTime = DateFormat('HH:mm dd/MM/yy', 'vi_VN')
          .format(order.startTime.toDate());

      // Logic đếm ngược (chỉ áp dụng cho bàn GỐC là bàn hẹn)
      if (isScheduleOrder) {
        final String? appointmentString = rawData?['guestAddress'] as String?;
        if (appointmentString != null && appointmentString.isNotEmpty) {
          try {
            // Thử parse định dạng mới "HH:mm dd/MM/yy"
            final format = DateFormat('HH:mm dd/MM/yy', 'vi_VN');
            appointmentTime = format.parseStrict(appointmentString);
            entryTime = appointmentString; // Hiển thị giờ hẹn

            final countdownDifference = appointmentTime.difference(DateTime.now());
            isCountdown = !countdownDifference.isNegative;
            duration = _formatDuration(countdownDifference, isCountdown: isCountdown);

          } catch (e) {
            // Lỗi parse, thử định dạng cũ "HH:mm - dd/MM/yyyy"
            try {
              final oldFormat = DateFormat('HH:mm - dd/MM/yyyy', 'vi_VN');
              appointmentTime = oldFormat.parseStrict(appointmentString);
              // Format lại sang định dạng mới để hiển thị
              entryTime = DateFormat('HH:mm dd/MM/yy', 'vi_VN').format(appointmentTime);

              final countdownDifference = appointmentTime.difference(DateTime.now());
              isCountdown = !countdownDifference.isNegative;
              duration = _formatDuration(countdownDifference, isCountdown: isCountdown);

            } catch (e2) {
              debugPrint("Lỗi parse thời gian hẹn (cả 2 định dạng): $appointmentString ($e)");
              entryTime = "Lỗi giờ hẹn";
              duration = "Lỗi đếm";
            }
          }
        } else {
          entryTime = "Không có giờ hẹn";
        }
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

    // Hiển thị tên khách (từ đơn hàng master)
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
        // --- SỬA LOGIC ONTAP ---
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => OrderScreen(
            currentUser: currentUser,
            table: tableToOpen, // Mở bàn chủ
            initialOrder: displayOrder, // Mở đơn chủ
          ),
        ));
        // --- KẾT THÚC SỬA ---
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
                    color: isOccupied ? (mergeColor ?? occupiedColorBase) : Colors.grey,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: Text(
                    table.tableName, // Luôn hiển thị tên bàn gốc
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
                          text: displayText, // Hiển thị tên khách (từ đơn chủ)
                        ),
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
                      color: Colors.grey.withAlpha((255 * 0.1).round()),
                      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                            isCountdown ? Icons.timelapse : Icons.timer_outlined,
                            size: 16,
                            color: isCountdown
                                ? Colors.blue
                                : (isScheduleOrder)
                                ? Colors.red
                                : Colors.black54
                        ),
                        const SizedBox(width: 4),
                        Text(
                            duration,
                            style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isCountdown
                                    ? Colors.blue
                                    : (isScheduleOrder)
                                    ? Colors.red
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

          // --- SỬA LOGIC ICON GỘP BÀN ---
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