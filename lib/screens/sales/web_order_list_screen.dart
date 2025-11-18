// File: lib/screens/sales/web_order_list_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../models/web_order_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import 'dart:async';
import '../../models/print_job_model.dart';
import '../../services/print_queue_service.dart';
import '../../models/order_item_model.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';
import 'package:app_4cash/services/settings_service.dart';
import 'package:app_4cash/models/store_settings_model.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import '../../models/customer_model.dart';
import '../../models/order_model.dart';
import '../../models/table_model.dart';
import 'package:app_4cash/tables/order_screen.dart';
import '../contacts/add_edit_customer_dialog.dart';
import '../../theme/string_extensions.dart';

enum WebOrderStatusFilter { all, pending, confirmed, completed, cancelled }

enum WebOrderTypeFilter { all, atTable, ship, schedule }

enum TimeRange {
  today,
  yesterday,
  thisWeek,
  lastWeek,
  thisMonth,
  lastMonth,
  custom
}

class WebOrderListScreen extends StatefulWidget {
  final UserModel currentUser;

  const WebOrderListScreen({super.key, required this.currentUser});

  @override
  State<WebOrderListScreen> createState() => _WebOrderListScreenState();
}

class _WebOrderListScreenState extends State<WebOrderListScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  late Future<List<ProductModel>> _productsFuture;

  String? _expandedOrderId;

  late Stream<List<Map<String, dynamic>>> _ordersStream;
  late StreamController<List<Map<String, dynamic>>> _ordersStreamController;
  StreamSubscription? _orderSubscription;

  WebOrderStatusFilter _selectedStatus = WebOrderStatusFilter.all;
  WebOrderTypeFilter _selectedType = WebOrderTypeFilter.all;
  TimeRange _selectedRange = TimeRange.today;

  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _calendarStartDate;
  DateTime? _calendarEndDate;
  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);
  StreamSubscription<StoreSettings>? _settingsSub;

  bool _isLoadingFilter = false;

  @override
  void initState() {
    super.initState();
    _productsFuture = _firestoreService
        .getAllProductsStream(widget.currentUser.storeId)
        .first;

    _ordersStreamController =
        StreamController<List<Map<String, dynamic>>>.broadcast();
    _ordersStream = _ordersStreamController.stream;

    // Tải Cài đặt, Cài đặt sẽ kích hoạt tải Stream
    _loadSettingsAndFetchData();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _ordersStreamController.close();
    _settingsSub?.cancel(); // <-- Thêm
    super.dispose();
  }

  Future<CustomerModel?> _findCustomerByPhone(String phone) async {
    if (phone.isEmpty) return null;
    try {
      final query = await FirebaseFirestore.instance
          .collection('customers')
          .where('storeId', isEqualTo: widget.currentUser.storeId)
          .where('phone', isEqualTo: phone)
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        return CustomerModel.fromFirestore(query.docs.first);
      }
    } catch (e) {
      debugPrint("Lỗi tìm khách bằng SĐT: $e");
    }
    return null;
  }

  Future<void> _confirmShipOrder(WebOrderModel order, String? note) async {
    try {
      CustomerModel? customer = await _findCustomerByPhone(order.customerPhone);

      if (customer == null) {
        if (!mounted) return;
        final newCustomer = await showDialog<CustomerModel>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AddEditCustomerDialog(
            firestoreService: _firestoreService,
            storeId: widget.currentUser.storeId,
            initialName: order.customerName,
            initialPhone: order.customerPhone,
            initialAddress: order.customerAddress,
            isPhoneReadOnly: true,
          ),
        );

        if (newCustomer == null) {
          ToastService()
              .show(message: "Đã hủy thao tác.", type: ToastType.warning);
          return;
        }
        customer = newCustomer;
        ToastService()
            .show(message: "Đã thêm khách hàng mới.", type: ToastType.success);
      }
      // --- KẾT THÚC LOGIC MỚI ---

      // 1. Cập nhật trạng thái web_order
      final bool success = await _updateOrderStatus(order.id, 'confirmed');
      if (!success) return;

      // 2. Gửi lệnh in bếp
      PrintQueueService().addJob(PrintJobType.kitchen, {
        'storeId': widget.currentUser.storeId,
        'tableName': 'Đơn Online',
        'userName': widget.currentUser.name ?? 'Thu ngân',
        'items': order.items.map((e) => e.toMap()).toList(),
        'customerName': customer.name,
      });

      final virtualTableId = 'ship_${order.id}';
      final virtualTableName = 'Giao Hàng';

      // 3. Tạo/Cập nhật Bàn ảo (TableModel) trong collection 'tables'
      final virtualTableData = {
        'id': virtualTableId,
        'tableName': virtualTableName,
        'storeId': order.storeId,
        'stt': -999,
        'serviceId': '',
        'tableGroup': 'Online',
      };
      await _firestoreService.setTable(virtualTableId, virtualTableData);

      // 4. Tạo/Cập nhật OrderModel (trong collection 'orders')
      final orderRef = _firestoreService.getOrderReference(order.id);
      final items = order.items.map((item) {
        return item.copyWith(sentQuantity: item.quantity).toMap();
      }).toList();

      final orderData = {
        'id': order.id,
        'tableId': virtualTableId,
        'tableName': virtualTableName,
        'status': 'active',
        'startTime': order.createdAt,
        'items': items,
        'totalAmount': order.totalAmount,
        'storeId': order.storeId,
        'createdAt': order.createdAt,
        'createdByUid': widget.currentUser.uid,
        'createdByName': widget.currentUser.name ?? 'Thu ngân',
        'numberOfCustomers': 1,
        'version': 1,
        'customerId': customer.id,
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'guestAddress': order.customerAddress,
        'guestNote': note,
      };
      await orderRef.set(orderData, SetOptions(merge: true));

      ToastService().show(
          message: 'Đã xác nhận, in bếp và tạo bàn ảo.',
          type: ToastType.success);
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi xác nhận: $e", type: ToastType.error);
    }
  }

  Future<void> _openShipOrderInOrderScreen(WebOrderModel webOrder) async {
    if (!mounted) return;

    try {
      // 1. Tạo lại đối tượng bàn ảo (để truyền đi)
      final virtualTable = TableModel(
        id: 'ship_${webOrder.id}',
        tableName: 'Giao Hàng',
        storeId: webOrder.storeId,
        stt: -999,
        serviceId: '',
        tableGroup: 'Online',
      );

      // 2. Tải OrderModel (đã được tạo bởi _confirmShipOrder)
      final orderRef = _firestoreService.getOrderReference(webOrder.id);
      final orderSnap = await orderRef.get();

      if (!orderSnap.exists) {
        ToastService().show(
            message: "Lỗi: Không tìm thấy đơn hàng tương ứng.",
            type: ToastType.error);
        return;
      }

      final orderToOpen = OrderModel.fromFirestore(orderSnap);

      // 3. Điều hướng sang OrderScreen
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => OrderScreen(
            currentUser: widget.currentUser,
            table: virtualTable,
            initialOrder: orderToOpen,
          ),
        ));
      }
    } catch (e, st) {
      debugPrint("Lỗi khi mở đơn hàng ship: $e\n$st");
      ToastService().show(message: "Lỗi khi mở đơn: $e", type: ToastType.error);
    }
  }

  Future<void> _loadSettingsAndFetchData() async {
    setState(() => _isLoadingFilter = true);
    final settingsService = SettingsService();
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;

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

      // Lần đầu, tính toán ngày và tải stream
      _updateDateRangeAndFetch();
    } catch (e) {
      debugPrint("Lỗi tải cài đặt: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Lỗi tải cài đặt: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
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
        _updateDateRangeAndFetch(); // Tải lại nếu giờ chốt sổ thay đổi
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
          final endOfMonth =
              DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          _calendarStartDate = startOfMonth;
          _calendarEndDate = endOfMonth;
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth =
              DateTime(effectiveDate.year, effectiveDate.month, 0);
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
      _loadDependentStream();
    }
  }

  Future<void> _loadDependentStream() async {
    await _orderSubscription?.cancel();

    // Đảm bảo ngày đã được tính
    if (_startDate == null || _endDate == null) {
      _ordersStreamController.add([]); // Gửi danh sách rỗng
      return;
    }

    try {
      final allProducts = await _productsFuture;
      if (!mounted) return;

      Query query = FirebaseFirestore.instance
          .collection('web_orders')
          .where('storeId', isEqualTo: widget.currentUser.storeId);

      // Lọc theo Trạng thái
      if (_selectedStatus != WebOrderStatusFilter.all) {
        String statusString;
        switch (_selectedStatus) {
          case WebOrderStatusFilter.pending:
            statusString = 'pending';
            break;
          case WebOrderStatusFilter.confirmed:
            statusString = 'confirmed';
            break;
          case WebOrderStatusFilter.completed:
            statusString = 'Đã hoàn tất';
            break;
          case WebOrderStatusFilter.cancelled:
            statusString = 'cancelled';
            break;
          case WebOrderStatusFilter.all:
            statusString = '';
            break;
        }
        query = query.where('status', isEqualTo: statusString);
      }

      // Lọc theo Loại đơn
      if (_selectedType != WebOrderTypeFilter.all) {
        String typeString;
        switch (_selectedType) {
          case WebOrderTypeFilter.atTable:
            typeString = 'at_table'; // Gửi 'at_table' lên database
            break;
          case WebOrderTypeFilter.ship:
            typeString = 'ship';
            break;
          case WebOrderTypeFilter.schedule:
            typeString = 'schedule';
            break;
          case WebOrderTypeFilter.all:
            typeString = '';
            break;
        }
        query = query.where('type', isEqualTo: typeString);
      }

      query = query.where('createdAt', isGreaterThanOrEqualTo: _startDate);
      query = query.where('createdAt', isLessThanOrEqualTo: _endDate);

      query = query.orderBy('createdAt', descending: true);

      _orderSubscription = query
          .snapshots()
          .map((snapshot) => snapshot.docs.map((doc) {
        final model = WebOrderModel.fromFirestore(doc, allProducts);
        final data = doc.data() as Map<String, dynamic>;
        final confirmedBy = data['confirmedBy'] as String?;
        final note = data['note'] as String?;
        final confirmedAt = data['confirmedAt'] as Timestamp?;
        final numberOfCustomers = data['customerInfo']?['numberOfCustomers'] as int?;
        return {'model': model, 'confirmedBy': confirmedBy, 'note': note, 'confirmedAt': confirmedAt, 'numberOfCustomers': numberOfCustomers};
      }).toList())
          .listen((data) {
        if (mounted) {
          _ordersStreamController.add(data);
        }
      }, onError: (e) {
        if (mounted) {
          _ordersStreamController.addError(e);
        }
      });
    } catch (e) {
      if (mounted) {
        _ordersStreamController.addError(e);
      }
    }
  }

  Future<bool> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('web_orders')
          .doc(orderId)
          .update({
        'status': newStatus,
        'confirmedBy': widget.currentUser.name,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      ToastService()
          .show(message: 'Lỗi (cập nhật web_order): $e', type: ToastType.error);
      return false;
    }
  }

  Future<void> _confirmAtTableOrder(WebOrderModel order) async {
    if (order.tableId == null || order.tableId!.isEmpty) {
      ToastService().show(
          message: "Lỗi: Đơn hàng này thiếu ID Bàn.", type: ToastType.error);
      return;
    }

    final List<ProductModel> allProducts;
    try {
      allProducts = await _productsFuture;
    } catch (e) {
      ToastService().show(
          message: "Lỗi: Không thể tải danh sách sản phẩm.",
          type: ToastType.error);
      return;
    }

    try {
      final orderRef = _firestoreService.getOrderReference(order.tableId!);
      final serverSnapshot = await orderRef.get();
      final serverData = serverSnapshot.data() as Map<String, dynamic>?;

      final Map<String, OrderItem> oldServerItemsMap = {};
      if (serverSnapshot.exists &&
          serverData != null &&
          serverData['status'] == 'active') {
        final serverItemsList = (serverData['items'] as List<dynamic>? ?? []);
        for (var itemData in serverItemsList) {
          try {
            final item = OrderItem.fromMap(
                (itemData as Map).cast<String, dynamic>(),
                allProducts: allProducts);
            final key = item.groupKey;
            if (oldServerItemsMap.containsKey(key)) {
              oldServerItemsMap[key] = oldServerItemsMap[key]!.copyWith(
                quantity: oldServerItemsMap[key]!.quantity + item.quantity,
                sentQuantity:
                    oldServerItemsMap[key]!.sentQuantity + item.sentQuantity,
              );
            } else {
              oldServerItemsMap[key] = item;
            }
          } catch (e) {
            debugPrint("Lỗi parse món ăn từ server: $e. Món: $itemData");
          }
        }
      }

      final Map<String, OrderItem> deltaItemsMap = {};
      for (final webItem in order.items) { // webItem là OrderItem từ WebOrderModel
        try {
          // webItem đã là một OrderItem, không cần tạo lại
          final deltaItem = webItem;

          final key = deltaItem.groupKey;
          if (deltaItemsMap.containsKey(key)) {
            final existingItem = deltaItemsMap[key]!;
            final String? mergedNote = [existingItem.note, deltaItem.note]
                .where((n) => n != null && n.isNotEmpty)
                .join(', ')
                .nullIfEmpty;

            deltaItemsMap[key] = existingItem.copyWith(
              quantity: existingItem.quantity + deltaItem.quantity,
              note: () => mergedNote,
            );
          } else {
            deltaItemsMap[key] = deltaItem;
          }
        } catch (e) {
          debugPrint(
              "Lỗi parse món ăn từ web_order: $e. Món: ${webItem.product.productName}");
        }
      }

      final List<Map<String, dynamic>> itemsToPrintAdd = [];
      final List<Map<String, dynamic>> itemsToPrintCancel = [];
      final Map<String, OrderItem> finalItemsToSaveMap =
      Map.from(oldServerItemsMap);

      for (final deltaEntry in deltaItemsMap.entries) {
        final key = deltaEntry.key;
        final deltaItem = deltaEntry.value;
        final double deltaQty = deltaItem.quantity;
        final currentItem = finalItemsToSaveMap[key];

        if (currentItem != null) {
          final newQty = currentItem.quantity + deltaQty;
          if (newQty > 0) {
            final String? mergedNote = [currentItem.note, deltaItem.note]
                .where((n) => n != null && n.isNotEmpty)
                .join(', ')
                .nullIfEmpty;
            finalItemsToSaveMap[key] = currentItem.copyWith(
              quantity: newQty,
              sentQuantity: currentItem.sentQuantity + deltaQty,
              note: () => mergedNote,
            );
          } else {
            finalItemsToSaveMap.remove(key);
          }
        } else if (deltaQty > 0) {
          finalItemsToSaveMap[key] = deltaItem.copyWith(sentQuantity: deltaQty);
        }

        if (deltaQty > 0) {
          itemsToPrintAdd.add({'isCancel': false, ...deltaItem.toMap()});
        } else if (deltaQty < 0) {
          itemsToPrintCancel.add({
            'isCancel': true,
            ...deltaItem.copyWith(quantity: -deltaQty).toMap()
          });
        }
      }

      final itemsToSave =
          finalItemsToSaveMap.values.map((e) => e.toMap()).toList();

      final newTotalAmount = finalItemsToSaveMap.values
          .fold(0.0, (tong, item) => tong + item.subtotal);
      final currentVersion = (serverData?['version'] as num?)?.toInt() ?? 0;
      final bool kitchenPrinted = true;

      if (itemsToSave.isEmpty && serverSnapshot.exists) {
        await orderRef.update({
          'status': 'cancelled',
          'items': [],
          'totalAmount': 0.0,
          'updatedAt': FieldValue.serverTimestamp(),
          'version': currentVersion + 1,
        });
      } else if (itemsToSave.isNotEmpty) {
        if (!serverSnapshot.exists ||
            ['paid', 'cancelled'].contains(serverData?['status'])) {
          final newOrderData = {
            'id': orderRef.id,
            'tableId': order.tableId!,
            'tableName': order.tableName,
            'status': 'active',
            'startTime': Timestamp.now(),
            'items': itemsToSave,
            'totalAmount': newTotalAmount,
            'storeId': order.storeId,
            'createdAt': FieldValue.serverTimestamp(),
            'createdByUid': widget.currentUser.uid,
            'createdByName': widget.currentUser.name ?? 'Thu ngân',
            'numberOfCustomers': 1,
            'version': currentVersion + 1,
            'kitchenPrinted': kitchenPrinted,
          };
          await orderRef.set(newOrderData);
        } else {
          await orderRef.update({
            'items': itemsToSave,
            'totalAmount': newTotalAmount,
            'updatedAt': FieldValue.serverTimestamp(),
            'version': currentVersion + 1,
            'kitchenPrinted': kitchenPrinted,
          });
        }
      }

      if (itemsToPrintAdd.isNotEmpty) {
        PrintQueueService().addJob(PrintJobType.kitchen, {
          'storeId': order.storeId,
          'tableName': order.tableName,
          'userName': widget.currentUser.name ?? 'Thu ngân',
          'items': itemsToPrintAdd,
          'printType': 'add'
        });
      }
      if (itemsToPrintCancel.isNotEmpty) {
        PrintQueueService().addJob(PrintJobType.cancel, {
          'storeId': order.storeId,
          'tableName': order.tableName,
          'userName': widget.currentUser.name ?? 'Thu ngân',
          'items': itemsToPrintCancel,
          'printType': 'cancel'
        });
      }

      await _updateOrderStatus(order.id, 'confirmed');

      ToastService().show(
          message: "Đã xác nhận và gửi báo bếp!", type: ToastType.success);
    } catch (e, st) {
      debugPrint("Lỗi khi xác nhận đơn 'at_table': $e");
      debugPrint(st.toString());
      ToastService().show(
          message: "Lỗi khi xác nhận: ${e.toString()}", type: ToastType.error);
    }
  }

  String _getItemText(TimeRange range) {
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

  String _getStatusFilterText(WebOrderStatusFilter filter) {
    switch (filter) {
      case WebOrderStatusFilter.all:
        return 'Tất cả trạng thái';
      case WebOrderStatusFilter.pending:
        return 'Chờ xử lý';
      case WebOrderStatusFilter.confirmed:
        return 'Đã xác nhận';
      case WebOrderStatusFilter.completed:
        return 'Đã hoàn tất (Ship)';
      case WebOrderStatusFilter.cancelled:
        return 'Đã xử lý';
    }
  }

  String _getOrderTypeFilterText(WebOrderTypeFilter filter) {
    switch (filter) {
      case WebOrderTypeFilter.all:
        return 'Tất cả loại đơn';
      case WebOrderTypeFilter.atTable:
        return 'Đơn tại bàn (QR)';
      case WebOrderTypeFilter.ship:
        return 'Đơn giao hàng (Ship)';
      case WebOrderTypeFilter.schedule:
        return 'Đơn đặt lịch';
    }
  }

  void showFilterModal() {
    WebOrderStatusFilter tempSelectedStatus = _selectedStatus;
    WebOrderTypeFilter tempSelectedType = _selectedType;
    TimeRange tempSelectedRange = _selectedRange;
    DateTime? tempStartDate = _calendarStartDate;
    DateTime? tempEndDate = _calendarEndDate;

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
                  Text('Lọc Đơn Hàng',
                      style: Theme.of(context).textTheme.headlineMedium),

                  // Lọc Thời Gian
                  AppDropdown<TimeRange>(
                    labelText: 'Khoảng thời gian',
                    prefixIcon: Icons.date_range_outlined,
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
                          startLastDate:
                              DateTime.now().add(const Duration(days: 365)),
                          endFirstDate: tempStartDate ?? DateTime(2020),
                          endLastDate:
                              DateTime.now().add(const Duration(days: 365)),
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
                        return Text(_getItemText(range));
                      }).toList();
                    },
                  ),

                  // Lọc Trạng Thái
                  AppDropdown<WebOrderStatusFilter>(
                    labelText: 'Trạng thái',
                    prefixIcon: Icons.flag_outlined,
                    value: tempSelectedStatus,
                    items: WebOrderStatusFilter.values.map((filter) {
                      return DropdownMenuItem<WebOrderStatusFilter>(
                        value: filter,
                        child: Text(_getStatusFilterText(filter)),
                      );
                    }).toList(),
                    onChanged: (WebOrderStatusFilter? newValue) {
                      if (newValue != null) {
                        setModalState(() {
                          tempSelectedStatus = newValue;
                        });
                      }
                    },
                  ),

                  // Lọc Loại Đơn
                  AppDropdown<WebOrderTypeFilter>(
                    labelText: 'Loại đơn hàng',
                    prefixIcon: Icons.shopping_bag_outlined,
                    value: tempSelectedType,
                    items: WebOrderTypeFilter.values.map((filter) {
                      return DropdownMenuItem<WebOrderTypeFilter>(
                        value: filter,
                        child: Text(_getOrderTypeFilterText(filter)),
                      );
                    }).toList(),
                    onChanged: (WebOrderTypeFilter? newValue) {
                      if (newValue != null) {
                        setModalState(() {
                          tempSelectedType = newValue;
                        });
                      }
                    },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            // Đặt lại giá trị mặc định
                            _selectedRange = TimeRange.today;
                            _selectedStatus = WebOrderStatusFilter.all;
                            _selectedType = WebOrderTypeFilter.all;
                            _updateDateRangeAndFetch(); // Tải lại
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
                          bool statusChanged =
                              _selectedStatus != tempSelectedStatus;
                          bool typeChanged = _selectedType != tempSelectedType;

                          setState(() {
                            _selectedRange = tempSelectedRange;
                            _calendarStartDate = tempStartDate;
                            _calendarEndDate = tempEndDate;
                            _selectedStatus = tempSelectedStatus;
                            _selectedType = tempSelectedType;
                          });

                          if (dateChanged || statusChanged || typeChanged) {
                            _updateDateRangeAndFetch(); // Tải lại
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

  List<Widget> _buildFilterActions() {
    return [
      IconButton(
        icon: _isLoadingFilter
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.primaryColor))
            : const Icon(Icons.filter_list,
                color: AppTheme.primaryColor, size: 30),
        tooltip: 'Lọc đơn hàng',
        onPressed: _isLoadingFilter ? null : showFilterModal,
      ),
      const SizedBox(width: 8),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Online Booking'),
        actions: _buildFilterActions(),
      ),
      body: FutureBuilder<List<ProductModel>>(
        future: _productsFuture,
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (productSnapshot.hasError || !productSnapshot.hasData) {
            return Center(
                child: Text(
                    'Lỗi nghiêm trọng: Không thể tải sản phẩm. ${productSnapshot.error}'));
          }

          return StreamBuilder<List<Map<String, dynamic>>>(
            stream: _ordersStream,
            builder: (context, orderSnapshot) {
              if (orderSnapshot.connectionState == ConnectionState.waiting) {
                if (!_isLoadingFilter) {
                  return const Center(child: CircularProgressIndicator());
                }
                return const SizedBox.shrink();
              }
              if (orderSnapshot.hasError) {
                String errorMsg = orderSnapshot.error.toString();
                if (errorMsg.contains('operation requires an index')) {
                  errorMsg =
                      "Lỗi: Cần tạo chỉ mục (index) trong Firestore.\n Vui lòng kiểm tra log (Debug Console) để xem link tạo tự động.";
                } else {
                  debugPrint('Lỗi tải đơn hàng: ${orderSnapshot.error}');
                }
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(errorMsg, textAlign: TextAlign.center),
                  ),
                );
              }
              if (!orderSnapshot.hasData || orderSnapshot.data!.isEmpty) {
                return const Center(
                    child: Text('Không tìm thấy đơn hàng nào.'));
              }

              final allOrdersData = orderSnapshot.data!;

              // --- SỬA LOGIC: PHÂN TÁCH LẠI DANH SÁCH ---

              // 1. Phân tách danh sách dựa trên dữ liệu đã lọc
              final pendingOrders = allOrdersData
                  .where((data) =>
                      (data['model'] as WebOrderModel).status == 'pending')
                  .toList();

              final otherOrders = allOrdersData
                  .where((data) =>
                      (data['model'] as WebOrderModel).status != 'pending')
                  .toList();

              // 2. Chỉ hiển thị các section nếu bộ lọc trạng thái là "Tất cả"
              if (_selectedStatus != WebOrderStatusFilter.all) {
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: allOrdersData.length,
                  itemBuilder: (context, index) {
                    final data = allOrdersData[index];
                    return _buildOrderCard(
                      data['model'] as WebOrderModel,
                      data['confirmedBy'] as String?,
                      data['note'] as String?,
                      data['confirmedAt'] as Timestamp?,
                      data['numberOfCustomers'] as int?,
                    );
                  },
                );
              }

              // 3. Hiển thị 2 section (nếu bộ lọc là "Tất cả")
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                children: [
                  if (pendingOrders.isNotEmpty) ...[
                    _buildSectionHeader('Chờ xử lý (${pendingOrders.length})',
                        AppTheme.primaryColor),
                    ...pendingOrders.map((data) => _buildOrderCard(
                          data['model'] as WebOrderModel,
                          data['confirmedBy'] as String?,
                          data['note'] as String?,
                          data['confirmedAt'] as Timestamp?,
                          data['numberOfCustomers'] as int?,
                        )),
                  ],
                  if (otherOrders.isNotEmpty) ...[
                    _buildSectionHeader('Đã xử lý (${otherOrders.length})',
                        Colors.grey.shade700),
                    ...otherOrders.map((data) => _buildOrderCard(
                          data['model'] as WebOrderModel,
                          data['confirmedBy'] as String?,
                          data['note'] as String?,
                          data['confirmedAt'] as Timestamp?,
                          data['numberOfCustomers'] as int?,
                        )),
                  ],
                ],
              );
              // --- KẾT THÚC SỬA LOGIC ---
            },
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(String title, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style:
            TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color ?? Colors.grey.shade700),
        const SizedBox(width: 4),
        // Dùng Flexible để text tự xuống dòng nếu quá dài
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 15, color: color ?? Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderCard(WebOrderModel order, String? confirmedBy, String? note, Timestamp? confirmedAt, int? numberOfCustomers) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final timeFormat = DateFormat('HH:mm dd/MM/yyyy');
    final isPending = order.status == 'pending';

    final bool isFnb= widget.currentUser.businessType == "fnb";

    IconData typeIcon;
    String titleText;
    Widget line2Widget;
    Widget line3Widget;
    List<Widget> detailsWidgets;

    final double totalToShow = order.totalAmount;
    final String timeString = timeFormat.format(order.createdAt.toDate());
    final String statusText;
    final Color statusColor;
    final IconData statusIcon;

    if (isPending) {
      statusText = 'Chờ xử lý';
      // SỬA: Đổi màu cho FNB Schedule
      statusColor = AppTheme.primaryColor;
      statusIcon = Icons.question_mark_outlined;

    } else if (order.status == 'confirmed') {
      if (order.type == 'schedule') {
        statusText = 'Đã xác nhận';
        statusIcon = Icons.check_circle;
        statusColor = !isFnb ? Colors.blue.shade700 : Colors.grey;
      } else {
        statusText = 'Đã báo chế biến';
        statusIcon = Icons
            .notifications_active_outlined;
        statusColor = Colors.grey;
      }
    } else if (order.status == 'Đã hoàn tất') {
      statusText = 'Đã hoàn tất';
      statusIcon = Icons.money_outlined;
      statusColor = Colors.grey;
    } else {
      // 'cancelled'
      statusText = 'Đã từ chối';
      statusIcon = Icons.cancel;
      statusColor = Colors.red;
    }

    // --- 2. XÂY DỰNG DÒNG 3 (TRẠNG THÁI) ---
    if (isPending) {
      line3Widget = const SizedBox.shrink(); // Đơn chờ xử lý không có dòng 3
    } else {
      final String confirmedAtString = confirmedAt != null
          ? timeFormat.format(confirmedAt.toDate())
          : '';
      line3Widget = Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(confirmedBy ?? 'N/A',
                style: const TextStyle(fontSize: 15, color: Colors.black87)),
          ]),
          if (confirmedAtString.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.access_time_outlined,
                  size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(confirmedAtString,
                  style: const TextStyle(fontSize: 15, color: Colors.black87)),
            ]),
          _buildStatusChip(statusText, statusColor),
        ],
      );
    }

    // --- 3. XÂY DỰNG CHI TIẾT (KHI MỞ RỘNG) ---
    final itemsListWidgets = [
      ...order.items.map((item) {
        String quantityString = formatNumber(item.quantity);
        bool hasNote = item.note != null && item.note!.isNotEmpty;

        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          minVerticalPadding: 0,
          title: Text(
            '$quantityString x ${item.product.productName}',
            style: const TextStyle(color: Colors.black, fontSize: 15),
          ),
          subtitle: hasNote
              ? Text(
            item.note!,
            style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic, fontSize: 14),
          )
              : null,
          trailing: Text(
            currencyFormat.format(item.subtotal), // SỬA: Dùng subtotal
            style: const TextStyle(color: Colors.black, fontSize: 15),
          ),
        );
      }),
      const Divider(
        height: 8,
        thickness: 0.5,
        color: Colors.grey,
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Tổng cộng',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black)),
          Text(currencyFormat.format(totalToShow), // Dùng totalToShow đã sửa
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black)),
        ],
      ),
    ];

    // --- 4. XÂY DỰNG TIÊU ĐỀ, DÒNG 2, VÀ CHI TIẾT (THEO TỪNG LOẠI) ---
    switch (order.type) {
      case 'ship':
        typeIcon = Icons.delivery_dining_outlined;
        titleText = 'Đơn online - ${order.customerPhone}';
        // Dòng 2: Tiền - Thời gian gởi
        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(
                Icons.payments_outlined, currencyFormat.format(totalToShow)),
            _buildInfoRow(Icons.edit_calendar_outlined, timeString),
          ],
        );
        // Details: Địa chỉ, Ghi chú, Chi tiết
        detailsWidgets = [
          _buildInfoRow(Icons.location_on_outlined, order.customerAddress),
          // SỬA: Thêm InkWell để sửa note
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: isPending ? () => _showEditNoteDialog(order.id, note) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: _buildInfoRow(Icons.edit, note, color: Colors.red),
              ),
            ),
          ],
          // SỬA: Thêm nút "Thêm ghi chú" nếu chưa có
          if (note == null || note.isEmpty) ...[
            if (isPending)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.primaryColor),
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                label: const Text('Thêm ghi chú'),
                onPressed: () => _showEditNoteDialog(order.id, note),
              ),
          ],
          ...itemsListWidgets,
        ];
        break;

      case 'schedule':
        typeIcon = Icons.calendar_month_outlined;

        // --- SỬA LOGIC HIỂN THỊ ---
        // 1. Tên/SL Khách
        String customerName = order.customerName;
        if (widget.currentUser.businessType == "fnb" &&
            numberOfCustomers != null &&
            numberOfCustomers > 0) {
          customerName = '($numberOfCustomers) $customerName';
        }
        // 2. Tiêu đề (dòng 1) -> Dùng SĐT
        titleText = 'Lịch hẹn - ${order.customerPhone}';

        // 3. Dòng 2 -> Dùng Tên/SL Khách và Giờ hẹn
        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(Icons.people_alt_outlined, customerName),
            _buildInfoRow(Icons.calendar_month_outlined, order.customerAddress),
          ],
        );
        // Details: Thời gian gởi, Ghi chú, Chi tiết
        detailsWidgets = [
          _buildInfoRow(
              Icons.edit_calendar_outlined, timeString),
          // SỬA: Thêm InkWell để sửa note
          if (note != null && note.isNotEmpty) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: isPending ? () => _showEditNoteDialog(order.id, note) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: _buildInfoRow(Icons.edit, note, color: Colors.red),
              ),
            ),
          ],
          // SỬA: Thêm nút "Thêm ghi chú" nếu chưa có
          if (note == null || note.isEmpty) ...[
            if (isPending)
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.primaryColor),
                icon: const Icon(Icons.add_comment_outlined, size: 16),
                label: const Text('Thêm ghi chú'),
                onPressed: () => _showEditNoteDialog(order.id, note),
              ),
          ],
          ...itemsListWidgets,
        ];
        break;

      case 'at_table':
      default:
        typeIcon = Icons.qr_code_scanner_outlined;
        titleText = 'Khách order - ${order.tableName}';
        // Dòng 2: Tiền - Thời gian gởi
        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(
                Icons.payments_outlined, currencyFormat.format(totalToShow)),
            _buildInfoRow(Icons.edit_calendar_outlined, timeString),
          ],
        );
        // Details: Ghi chú, Chi tiết
        detailsWidgets = [
          if (note != null && note.isNotEmpty) ...[
            _buildInfoRow(Icons.edit, note, color: Colors.red),
          ],
          ...itemsListWidgets,
        ];
        break;
    }

    // --- 5. LẮP RÁP THẺ ---

    final screenWidth = MediaQuery.of(context).size.width;
    const double mobileBreakpoint = 600.0;
    final bool isMobile = screenWidth < mobileBreakpoint;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: ValueKey('${order.id}_${order.id == _expandedOrderId}'),
        initiallyExpanded: order.id == _expandedOrderId,
        onExpansionChanged: (isExpanding) {
          setState(() {
            if (isExpanding) {
              _expandedOrderId = order.id;
            } else if (_expandedOrderId == order.id) {
              _expandedOrderId = null;
            }
          });
        },
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding:
        const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        leading: CircleAvatar(
          backgroundColor: statusColor,
          child: Icon(typeIcon, color: Colors.white),
        ),
        title: Text(
          titleText,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            line2Widget, // Dòng 2
            if (!isPending) ...[
              const SizedBox(height: 6),
              line3Widget, // Dòng 3
            ],
          ],
        ),
        trailing: isMobile ? const SizedBox.shrink() : Icon(statusIcon, color: statusColor, size: 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
            // Giảm padding top
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...detailsWidgets,

                if (isPending) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Từ chối'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => _showConfirmationDialog(
                            title: 'Từ chối',
                            content: 'Bạn có chắc muốn từ chối yêu cầu này?',
                            onConfirm: () async {
                              final bool success = await _updateOrderStatus(
                                  order.id, 'cancelled');
                              if (success) {
                                ToastService().show(
                                    message: 'Đã từ chối yêu cầu.',
                                    type: ToastType.success);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline),
                          label: Text((order.type == 'at_table' || order.type == 'ship')
                              ? 'Báo bếp'
                              : 'Xác nhận'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: !isFnb ? Colors.blue.shade700 : AppTheme.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () {
                            if (order.type == 'at_table') {
                              _showConfirmationDialog(
                                title: 'Xác nhận',
                                content: 'Gửi báo chế biến?',
                                onConfirm: () => _confirmAtTableOrder(order),
                              );
                            } else if (order.type == 'ship') {
                              _showConfirmationDialog(
                                title: 'Xác nhận',
                                content: 'Gửi báo chế biến?',
                                onConfirm: () => _confirmShipOrder(order, note),                         );
                            } else {
                              _showConfirmationDialog(
                                title: 'Xác nhận',
                                content: 'Xác nhận thông tin Đặt lịch hẹn?',
                                onConfirm: () => _confirmScheduleOrder(order, numberOfCustomers, note),                              );
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                if (order.type == 'ship' && order.status == 'confirmed')
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.fact_check_outlined),
                            label: const Text('Xem đơn'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _openShipOrderInOrderScreen(order),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmScheduleOrder(WebOrderModel order, int? numberOfCustomers, String? note) async {
    if (widget.currentUser.businessType != "fnb") {
      final bool success = await _updateOrderStatus(order.id, 'confirmed');
      if (success) {
        ToastService().show(message: 'Đã xác nhận lịch hẹn.', type: ToastType.success);
      }
      return;
    }

    try {
      CustomerModel? customer = await _findCustomerByPhone(order.customerPhone);

      if (customer == null) {
        if (!mounted) return;
        final newCustomer = await showDialog<CustomerModel>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AddEditCustomerDialog(
            firestoreService: _firestoreService,
            storeId: widget.currentUser.storeId,
            initialName: order.customerName,
            initialPhone: order.customerPhone,
            initialAddress: '',
            isPhoneReadOnly: true,
          ),
        );

        if (newCustomer == null) {
          ToastService().show(message: "Đã hủy thao tác.", type: ToastType.warning);
          return;
        }
        customer = newCustomer;
        ToastService().show(message: "Đã thêm khách hàng mới.", type: ToastType.success);
      }

      final bool success = await _updateOrderStatus(order.id, 'confirmed');
      if (!success) return;

      final virtualTableId = 'schedule_${order.id}';
      final virtualTableName = 'Booking';

      final virtualTableData = {
        'id': virtualTableId,
        'tableName': virtualTableName,
        'storeId': order.storeId,
        'stt': -998,
        'serviceId': '',
        'tableGroup': 'Online',
      };
      await _firestoreService.setTable(virtualTableId, virtualTableData);

      final orderRef = _firestoreService.getOrderReference(order.id);
      final items = order.items.map((item) {
        return item.copyWith(sentQuantity: 0).toMap();
      }).toList();

      final orderData = {
        'id': order.id,
        'tableId': virtualTableId,
        'tableName': virtualTableName,
        'status': 'active',
        'startTime': order.createdAt,
        'items': items,
        'totalAmount': order.totalAmount,
        'storeId': order.storeId,
        'createdAt': order.createdAt,
        'createdByUid': widget.currentUser.uid,
        'createdByName': widget.currentUser.name ?? 'Thu ngân',
        'numberOfCustomers': numberOfCustomers ?? 1,
        'version': 1,
        'customerId': customer.id,
        'customerName': customer.name,
        'customerPhone': customer.phone,
        'guestAddress': order.customerAddress,
        'guestNote': note,
      };
      await orderRef.set(orderData, SetOptions(merge: true));

      ToastService().show(
          message: 'Đã xác nhận và tạo bàn ảo (Booking).',
          type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi khi xác nhận: $e", type: ToastType.error);
    }
  }

  // --- HÀM MỚI ---
  Future<void> _updateOrderNote(String orderId, String newNote) async {
    try {
      await FirebaseFirestore.instance
          .collection('web_orders')
          .doc(orderId)
          .update({
        'note': newNote,
        'confirmedBy': widget.currentUser.name, // Cập nhật người sửa cuối
        'confirmedAt': FieldValue.serverTimestamp(), // Cập nhật thời gian
      });
      ToastService().show(message: 'Cập nhật ghi chú thành công.', type: ToastType.success);
    } catch (e) {
      ToastService().show(message: 'Lỗi cập nhật ghi chú: $e', type: ToastType.error);
    }
  }

  // --- HÀM MỚI ---
  Future<void> _showEditNoteDialog(String orderId, String? currentNote) async {
    final controller = TextEditingController(text: currentNote);
    final navigator = Navigator.of(context);

    final newNote = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sửa Ghi Chú Đơn Hàng'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Ghi chú',
              hintText: 'Nhập ghi chú của khách hàng...',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () {
                navigator.pop(controller.text.trim());
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );

    if (newNote != null) {
      if (newNote != currentNote) {
        await _updateOrderNote(orderId, newNote);
      }
    }
  }

  void _showConfirmationDialog({
    required String title,
    required String content,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Không'),
          ),
          ElevatedButton(
            onPressed: () {
              onConfirm();
              Navigator.of(context).pop();
            },
            child: const Text('Có'),
          ),
        ],
      ),
    );
  }
}
