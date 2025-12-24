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
import 'package:app_4cash/screens/sales/order_screen.dart';
import '../contacts/add_edit_customer_dialog.dart';
import '../../theme/string_extensions.dart';
import '../../widgets/product_search_delegate.dart';
import 'package:collection/collection.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import '../../tables/qr_order_management_screen.dart';

enum WebOrderStatusFilter { all, pending, confirmed, completed, cancelled }

enum WebOrderTypeFilter { all, atTable, ship, schedule }

enum TimeRange { today, yesterday, thisWeek, lastWeek, thisMonth, lastMonth, custom }

class WebOrderListScreen extends StatefulWidget {
  final UserModel currentUser;

  const WebOrderListScreen({super.key, required this.currentUser});

  @override
  State<WebOrderListScreen> createState() => _WebOrderListScreenState();
}

class _WebOrderListScreenState extends State<WebOrderListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _enableShipQr = true;
  bool _enableBookingQr = true;
  final String _qrOrderBaseUrl = "https://cash-bae5d.web.app/order";
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
        .first
        .timeout(const Duration(seconds: 5), onTimeout: () => []);

    _ordersStreamController = StreamController<List<Map<String, dynamic>>>();
    _ordersStream = _ordersStreamController.stream;

    _loadSettingsAndFetchData();
    _loadQrSettings();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _ordersStreamController.close();
    _settingsSub?.cancel(); // <-- Thêm
    super.dispose();
  }

  void _loadQrSettings() {
    final settingsId = widget.currentUser.storeId;
    SettingsService().watchStoreSettings(settingsId).listen((settings) {
      if (mounted) {
        setState(() {
          _enableShipQr = settings.enableShip ?? true;
          _enableBookingQr = settings.enableBooking ?? true;
        });
      }
    });
  }

  Future<void> _saveQrToFile(GlobalKey qrKey, String fileName) async {
    try {
      RenderRepaintBoundary boundary = qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      Uint8List pngBytes = byteData.buffer.asUint8List();

      final safeFileName = fileName.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
      final String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Lưu mã QR',
        fileName: '$safeFileName.png',
        bytes: pngBytes,
        type: FileType.custom,
        allowedExtensions: ['png'],
      );

      if (outputFile != null) {
        ToastService().show(message: "Đã lưu mã QR.", type: ToastType.success);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi lưu ảnh: $e", type: ToastType.error);
    }
  }

  Future<void> _showQrDetailDialog(String type) async {
    final bool isShip = type == 'ship';
    final String title = isShip ? "QR Đặt Giao Hàng" : "QR Đặt Lịch Hẹn";
    final String qrUrl = '$_qrOrderBaseUrl?store=${widget.currentUser.storeId}&type=$type';
    final GlobalKey qrKey = GlobalKey();

    bool localEnabled = isShip ? _enableShipQr : _enableBookingQr;
    bool isProcessing = false;

    await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(builder: (context, setStateDialog) {
            return AlertDialog(
              contentPadding: const EdgeInsets.all(16),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),
                  if (localEnabled)
                    SizedBox(
                      width: 250,
                      height: 250,
                      child: RepaintBoundary(
                        key: qrKey,
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: qrUrl,
                            version: QrVersions.auto,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else
                    const SizedBox(
                      height: 200,
                      width: 250,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.visibility_off, size: 50, color: Colors.grey),
                            SizedBox(height: 8),
                            Text("QR đang tắt", style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: (!localEnabled || isProcessing)
                            ? null
                            : () {
                                _saveQrToFile(qrKey, "QR_${isShip ? 'Ship' : 'Booking'}");
                              },
                        icon: const Icon(Icons.save_alt, size: 18),
                        label: const Text("Lưu ảnh"),
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primaryColor, foregroundColor: Colors.white),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Text(localEnabled ? "Đang Bật" : "Đang Tắt",
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold, color: localEnabled ? Colors.green : Colors.grey)),
                            Switch(
                                value: localEnabled,
                                activeTrackColor: AppTheme.primaryColor.withAlpha(125),
                                activeThumbColor: AppTheme.primaryColor,
                                onChanged: isProcessing
                                    ? null
                                    : (val) async {
                                        setStateDialog(() => isProcessing = true);
                                        try {
                                          final settingsId = widget.currentUser.storeId;
                                          final key = isShip ? 'enableShip' : 'enableBooking';
                                          await SettingsService().updateStoreSettings(settingsId, {key: val});

                                          setStateDialog(() {
                                            localEnabled = val;
                                            isProcessing = false;
                                          });
                                          setState(() {
                                            if (isShip) {
                                              _enableShipQr = val;
                                            } else {
                                              _enableBookingQr = val;
                                            }
                                          });
                                        } catch (e) {
                                          setStateDialog(() => isProcessing = false);
                                        }
                                      }),
                          ],
                        ),
                      ),
                    ],
                  )
                ],
              ),
            );
          });
        });
  }

  void _showQrMenu() {
    showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
        builder: (ctx) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("Mã QR Online", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  ListTile(
                    leading: const Icon(Icons.local_shipping, color: Colors.orange, size: 30),
                    title: const Text("QR Đặt Giao Hàng (Ship)", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_enableShipQr ? "Đang bật" : "Đang tắt"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showQrDetailDialog('ship');
                    },
                  ),
                  const Divider(height: 1, thickness: 0.5, color: Colors.grey),
                  ListTile(
                    leading: const Icon(Icons.calendar_month, color: Colors.blue, size: 30),
                    title: const Text("QR Đặt Lịch Hẹn (Booking)", style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(_enableBookingQr ? "Đang bật" : "Đang tắt"),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showQrDetailDialog('schedule');
                    },
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ));
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

  Future<void> _syncCustomerToWebOrder(String orderId, CustomerModel customer) async {
    try {
      await FirebaseFirestore.instance.collection('web_orders').doc(orderId).update({
        'customerName': customer.name,
        'customerId': customer.id,
        'billing.first_name': customer.name,
        // Cập nhật cả trong cấu trúc billing
        'shipping.first_name': customer.name,
      });
    } catch (e) {
      debugPrint("Lỗi đồng bộ tên khách vào WebOrder: $e");
    }
  }

  Future<void> _confirmShipOrder(WebOrderModel order, String? note) async {
    try {
      if ((widget.currentUser.businessType ?? '').toLowerCase() == 'retail') {
        // 1. Tìm hoặc Tạo khách
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
            ToastService().show(message: "Cần thông tin khách hàng.", type: ToastType.warning);
            return;
          }
          customer = newCustomer;
        }

        // [MỚI] 2. Đồng bộ tên khách hàng chuẩn vào Web Order (Để Card cập nhật hiển thị)
        await _syncCustomerToWebOrder(order.id, customer);

        // 3. Cập nhật trạng thái
        final bool success = await _updateOrderStatus(order.id, 'confirmed');
        if (!success) return;

        // 4. Lưu sang Cloud (Dùng tên chuẩn từ biến customer)
        final String cloudOrderId = order.id;
        final savedOrderData = {
          'id': cloudOrderId,
          'tableId': cloudOrderId,
          'tableName': 'Giao hàng',
          'status': 'saved',
          'startTime': order.createdAt,
          'items': order.items.map((e) => e.toMap()).toList(),
          'totalAmount': order.totalAmount,
          'storeId': order.storeId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': widget.currentUser.uid,
          'createdByName': widget.currentUser.name ?? 'Admin',
          'numberOfCustomers': 1,
          'version': 1,
          'customerId': customer.id,
          'customerName': customer.name,
          'customerPhone': customer.phone,
          'guestAddress': order.customerAddress,
          'guestNote': note,
          'isWebOrder': true,
        };

        await _firestoreService.getOrderReference(cloudOrderId).set(savedOrderData);

        ToastService().show(message: 'Đã xác nhận & Lưu đơn (Khách: ${customer.name})', type: ToastType.success);
        return;
      }

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
          ToastService().show(message: "Đã hủy thao tác.", type: ToastType.warning);
          return;
        }
        customer = newCustomer;
        ToastService().show(message: "Đã thêm khách hàng mới.", type: ToastType.success);
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

      ToastService().show(message: 'Đã xác nhận, in bếp và tạo bàn ảo.', type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi khi xác nhận: $e", type: ToastType.error);
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
        ToastService().show(message: "Lỗi: Không tìm thấy đơn hàng tương ứng.", type: ToastType.error);
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
    final settingsId = widget.currentUser.storeId;
    try {
      final settings = await settingsService.watchStoreSettings(settingsId).first;
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi tải cài đặt: $e")));
      }
    } finally {
      if (mounted) setState(() => _isLoadingFilter = false);
    }

    _settingsSub = settingsService.watchStoreSettings(settingsId).listen((settings) {
      if (!mounted) return;
      final newCutoff = TimeOfDay(
        hour: settings.reportCutoffHour ?? 0,
        minute: settings.reportCutoffMinute ?? 0,
      );

      final bool cutoffChanged = newCutoff.hour != _reportCutoffTime.hour || newCutoff.minute != _reportCutoffTime.minute;

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
      return calendarDay.add(Duration(hours: cutoff.hour, minutes: cutoff.minute));
    }

    DateTime endOfReportDay(DateTime date) {
      return startOfReportDay(date).add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));
    }

    DateTime todayCutoffTime = startOfReportDay(now);
    DateTime effectiveDate = now;
    if (now.isBefore(todayCutoffTime)) {
      effectiveDate = now.subtract(const Duration(days: 1));
    }
    effectiveDate = DateTime(effectiveDate.year, effectiveDate.month, effectiveDate.day);

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
          final startOfWeek = effectiveDate.subtract(Duration(days: effectiveDate.weekday - DateTime.monday));
          final endOfWeek = effectiveDate.add(Duration(days: DateTime.daysPerWeek - effectiveDate.weekday));
          _startDate = startOfReportDay(startOfWeek);
          _endDate = endOfReportDay(endOfWeek);
          _calendarStartDate = startOfWeek;
          _calendarEndDate = endOfWeek;
          break;
        case TimeRange.lastWeek:
          final endOfLastWeekDay = effectiveDate.subtract(Duration(days: effectiveDate.weekday));
          final startOfLastWeekDay = endOfLastWeekDay.subtract(const Duration(days: 6));
          _startDate = startOfReportDay(startOfLastWeekDay);
          _endDate = endOfReportDay(endOfLastWeekDay);
          _calendarStartDate = startOfLastWeekDay;
          _calendarEndDate = endOfLastWeekDay;
          break;
        case TimeRange.thisMonth:
          final startOfMonth = DateTime(effectiveDate.year, effectiveDate.month, 1);
          final endOfMonth = DateTime(effectiveDate.year, effectiveDate.month + 1, 0);
          _startDate = startOfReportDay(startOfMonth);
          _endDate = endOfReportDay(endOfMonth);
          _calendarStartDate = startOfMonth;
          _calendarEndDate = endOfMonth;
          break;
        case TimeRange.lastMonth:
          final endOfLastMonth = DateTime(effectiveDate.year, effectiveDate.month, 0);
          final startOfLastMonth = DateTime(endOfLastMonth.year, endOfLastMonth.month, 1);
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

    if (_startDate == null || _endDate == null) {
      if (!_ordersStreamController.isClosed) {
        _ordersStreamController.add([]);
      }
      return;
    }

    try {
      final allProducts = await _productsFuture;

      if (!mounted) return;

      Query query = FirebaseFirestore.instance.collection('web_orders').where('storeId', isEqualTo: widget.currentUser.storeId);

      // 1. Áp dụng bộ lọc Trạng thái (Giữ nguyên)
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
            statusString = 'completed';
            break;
          case WebOrderStatusFilter.cancelled:
            statusString = 'cancelled';
            break;
          case WebOrderStatusFilter.all:
            statusString = '';
            break;
        }
        if (_selectedStatus == WebOrderStatusFilter.completed) {
          query = query.where('status', whereIn: ['completed', 'Đã hoàn tất']);
        } else {
          query = query.where('status', isEqualTo: statusString);
        }
      }

      // 2. Áp dụng bộ lọc Loại đơn (Giữ nguyên)
      if (_selectedType != WebOrderTypeFilter.all) {
        String typeString;
        switch (_selectedType) {
          case WebOrderTypeFilter.atTable:
            typeString = 'at_table';
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

      // 3. [THAY ĐỔI LỚN] KHÔNG LỌC NGÀY TRÊN FIRESTORE
      _orderSubscription = query.snapshots().map((snapshot) {
        List<Map<String, dynamic>> results = snapshot.docs.map((doc) {
          final model = WebOrderModel.fromFirestore(doc, allProducts);
          final data = doc.data() as Map<String, dynamic>;
          return {
            'model': model,
            'rawData': data,
            'confirmedBy': data['confirmedBy'] as String?,
            'note': data['note'] as String?,
            'confirmedAt': data['confirmedAt'] as Timestamp?,
            'numberOfCustomers': data['customerInfo']?['numberOfCustomers'] as int?,
          };
        }).toList();

        results = results.where((item) {
          final model = item['model'] as WebOrderModel;

          // 1. Chờ xử lý -> Luôn hiện
          if (model.status == 'pending') return true;

          // 2. Lịch hẹn sắp tới (Schedule + Confirmed) -> Luôn hiện tất cả (không lọc ngày)
          if (model.type == 'schedule' && model.status == 'confirmed') {
            return true;
          }

          // 3. Các loại khác (Ship, Tại bàn, Lịch sử đã xong/hủy...)
          // -> Lọc theo ngày tạo (createdAt)
          return _isWithinRange(model.createdAt.toDate());
        }).toList();

        // --- SỬA LẠI LOGIC SẮP XẾP ---
        results.sort((a, b) {
          final modelA = a['model'] as WebOrderModel;
          final modelB = b['model'] as WebOrderModel;

          // Nhóm 1: Chờ xử lý luôn lên đầu
          if (modelA.status == 'pending' && modelB.status != 'pending') {
            return -1;
          }
          if (modelA.status != 'pending' && modelB.status == 'pending') {
            return 1;
          }

          // Nhóm 2: Lịch hẹn sắp tới (Schedule + Confirmed)
          // Sắp xếp ngày hẹn GẦN NHẤT lên trên (Tăng dần)
          bool isScheduleA = modelA.type == 'schedule' && modelA.status == 'confirmed';
          bool isScheduleB = modelB.type == 'schedule' && modelB.status == 'confirmed';

          if (isScheduleA && isScheduleB) {
            try {
              // Parse giờ hẹn từ customerAddress (Format: HH:mm dd/MM/yyyy)
              final dateA = DateFormat('HH:mm dd/MM/yyyy').parse(modelA.customerAddress);
              final dateB = DateFormat('HH:mm dd/MM/yyyy').parse(modelB.customerAddress);
              return dateA.compareTo(dateB); // Tăng dần (Gần nhất lên đầu)
            } catch (_) {
              // Nếu lỗi format thì dùng ngày tạo (Mới nhất lên đầu)
              return modelB.createdAt.compareTo(modelA.createdAt);
            }
          }

          // Ưu tiên nhóm lịch hẹn lên trên nhóm lịch sử
          if (isScheduleA && !isScheduleB) return -1;
          if (!isScheduleA && isScheduleB) return 1;

          // Nhóm 3: Còn lại (Lịch sử) -> Mới nhất lên đầu (Giảm dần theo createdAt)
          return modelB.createdAt.compareTo(modelA.createdAt);
        });

        return results;
      }).listen((data) {
        if (mounted && !_ordersStreamController.isClosed) {
          _ordersStreamController.add(data);
        }
      }, onError: (e) {
        debugPrint("Lỗi Stream WebOrder: $e");
        if (mounted && !_ordersStreamController.isClosed) {
          _ordersStreamController.add([]);
        }
      });
    } catch (e) {
      debugPrint("Lỗi _loadDependentStream: $e");
      if (mounted && !_ordersStreamController.isClosed) {
        _ordersStreamController.add([]);
      }
    }
  }

  bool _isWithinRange(DateTime date) {
    if (_startDate == null || _endDate == null) return true;
    return date.isAfter(_startDate!.subtract(const Duration(seconds: 1))) &&
        date.isBefore(_endDate!.add(const Duration(seconds: 1)));
  }

  Future<bool> _updateOrderStatus(String orderId, String newStatus) async {
    try {
      await FirebaseFirestore.instance.collection('web_orders').doc(orderId).update({
        'status': newStatus,
        'confirmedBy': widget.currentUser.name,
        'confirmedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      ToastService().show(message: 'Lỗi (cập nhật web_order): $e', type: ToastType.error);
      return false;
    }
  }

  Future<void> _confirmAtTableOrder(WebOrderModel order) async {
    if (order.tableId == null || order.tableId!.isEmpty) {
      ToastService().show(message: "Lỗi: Đơn hàng này thiếu ID Bàn.", type: ToastType.error);
      return;
    }

    final List<ProductModel> allProducts;
    try {
      allProducts = await _productsFuture;
    } catch (e) {
      ToastService().show(message: "Lỗi: Không thể tải danh sách sản phẩm.", type: ToastType.error);
      return;
    }

    try {
      final orderRef = _firestoreService.getOrderReference(order.tableId!);
      final serverSnapshot = await orderRef.get();
      final serverData = serverSnapshot.data() as Map<String, dynamic>?;

      final Map<String, OrderItem> oldServerItemsMap = {};
      if (serverSnapshot.exists && serverData != null && serverData['status'] == 'active') {
        final serverItemsList = (serverData['items'] as List<dynamic>? ?? []);
        for (var itemData in serverItemsList) {
          try {
            final item = OrderItem.fromMap((itemData as Map).cast<String, dynamic>(), allProducts: allProducts);
            final key = item.groupKey;
            if (oldServerItemsMap.containsKey(key)) {
              oldServerItemsMap[key] = oldServerItemsMap[key]!.copyWith(
                quantity: oldServerItemsMap[key]!.quantity + item.quantity,
                sentQuantity: oldServerItemsMap[key]!.sentQuantity + item.sentQuantity,
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
      for (final webItem in order.items) {
        // webItem là OrderItem từ WebOrderModel
        try {
          // webItem đã là một OrderItem, không cần tạo lại
          final deltaItem = webItem;

          final key = deltaItem.groupKey;
          if (deltaItemsMap.containsKey(key)) {
            final existingItem = deltaItemsMap[key]!;
            final String? mergedNote =
                [existingItem.note, deltaItem.note].where((n) => n != null && n.isNotEmpty).join(', ').nullIfEmpty;

            deltaItemsMap[key] = existingItem.copyWith(
              quantity: existingItem.quantity + deltaItem.quantity,
              note: () => mergedNote,
            );
          } else {
            deltaItemsMap[key] = deltaItem;
          }
        } catch (e) {
          debugPrint("Lỗi parse món ăn từ web_order: $e. Món: ${webItem.product.productName}");
        }
      }

      final List<Map<String, dynamic>> itemsToPrintAdd = [];
      final List<Map<String, dynamic>> itemsToPrintCancel = [];
      final Map<String, OrderItem> finalItemsToSaveMap = Map.from(oldServerItemsMap);

      for (final deltaEntry in deltaItemsMap.entries) {
        final key = deltaEntry.key;
        final deltaItem = deltaEntry.value;
        final double deltaQty = deltaItem.quantity;
        final currentItem = finalItemsToSaveMap[key];

        if (currentItem != null) {
          final newQty = currentItem.quantity + deltaQty;
          if (newQty > 0) {
            final String? mergedNote =
                [currentItem.note, deltaItem.note].where((n) => n != null && n.isNotEmpty).join(', ').nullIfEmpty;
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
          itemsToPrintCancel.add({'isCancel': true, ...deltaItem.copyWith(quantity: -deltaQty).toMap()});
        }
      }

      final itemsToSave = finalItemsToSaveMap.values.map((e) => e.toMap()).toList();

      final newTotalAmount = finalItemsToSaveMap.values.fold(0.0, (tong, item) => tong + item.subtotal);
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
        if (!serverSnapshot.exists || ['paid', 'cancelled'].contains(serverData?['status'])) {
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

      ToastService().show(message: "Đã xác nhận và gửi báo bếp!", type: ToastType.success);
    } catch (e, st) {
      debugPrint("Lỗi khi xác nhận đơn 'at_table': $e");
      debugPrint(st.toString());
      ToastService().show(message: "Lỗi khi xác nhận: ${e.toString()}", type: ToastType.error);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 20),
              child: Wrap(
                runSpacing: 16,
                children: [
                  Text('Lọc Đơn Hàng', style: Theme.of(context).textTheme.headlineMedium),

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
                          startLastDate: DateTime.now().add(const Duration(days: 365)),
                          endFirstDate: tempStartDate ?? DateTime(2020),
                          endLastDate: DateTime.now().add(const Duration(days: 365)),
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
                          final start = DateFormat('dd/MM/yy').format(tempStartDate!);
                          final end = DateFormat('dd/MM/yyyy').format(tempEndDate!);
                          return Text('$start - $end', overflow: TextOverflow.ellipsis);
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
                          bool dateChanged = (_selectedRange != tempSelectedRange) ||
                              (_selectedRange == TimeRange.custom &&
                                  (_calendarStartDate != tempStartDate || _calendarEndDate != tempEndDate));
                          bool statusChanged = _selectedStatus != tempSelectedStatus;
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
        icon: const Icon(Icons.qr_code_2, color: AppTheme.primaryColor, size: 30),
        tooltip: 'Mã QR Online',
        onPressed: () {
          // Kiểm tra loại hình kinh doanh để xử lý
          if (widget.currentUser.businessType == 'fnb') {
            // Nếu là FnB -> Mở màn hình Quản lý QR Bàn
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => QrOrderManagementScreen(
                  currentUser: widget.currentUser,
                ),
              ),
            );
          } else {
            // Nếu là Retail (hoặc khác) -> Mở menu QR Ship/Booking như cũ
            _showQrMenu();
          }
        },
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: const Icon(Icons.add_circle_outlined, color: AppTheme.primaryColor, size: 30),
        tooltip: 'Tạo đơn mới',
        onPressed: _openCreateManualOrder,
      ),
      const SizedBox(width: 8),
      IconButton(
        icon: _isLoadingFilter
            ? const SizedBox(
                width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor))
            : const Icon(Icons.filter_list, color: AppTheme.primaryColor, size: 30),
        tooltip: 'Lọc đơn hàng',
        onPressed: _isLoadingFilter ? null : showFilterModal,
      ),
      const SizedBox(width: 8),
    ];
  }

  void _openCreateManualOrder() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateManualWebOrderScreen(
          currentUser: widget.currentUser,
        ),
        fullscreenDialog: true, // Mở dạng popup full màn hình
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đơn Online'),
        actions: _buildFilterActions(),
      ),
      body: FutureBuilder<List<ProductModel>>(
        future: _productsFuture,
        builder: (context, productSnapshot) {
          if (productSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (productSnapshot.hasError || !productSnapshot.hasData) {
            return Center(child: Text('Lỗi nghiêm trọng: Không thể tải sản phẩm. ${productSnapshot.error}'));
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
                return const Center(child: Text('Không tìm thấy đơn hàng nào.'));
              }

              final allOrdersData = orderSnapshot.data!;

              // --- PHÂN LOẠI 3 NHÓM ---

              // Nhóm 1: Chờ xử lý (Pending)
              final pendingOrders = allOrdersData.where((data) => (data['model'] as WebOrderModel).status == 'pending').toList();

              // Nhóm 2: Lịch hẹn sắp tới (Schedule + Confirmed)
              final scheduledOrders = allOrdersData.where((data) {
                final m = data['model'] as WebOrderModel;
                return m.type == 'schedule' && m.status == 'confirmed';
              }).toList();

              // Nhóm 3: Lịch sử / Đã xử lý (Các đơn còn lại)
              final historyOrders = allOrdersData.where((data) {
                final m = data['model'] as WebOrderModel;
                // Loại bỏ những đơn đã thuộc 2 nhóm trên
                bool isPending = m.status == 'pending';
                bool isScheduled = m.type == 'schedule' && m.status == 'confirmed';
                return !isPending && !isScheduled;
              }).toList();

              // Nếu đang lọc theo trạng thái cụ thể, hiển thị danh sách phẳng
              if (_selectedStatus != WebOrderStatusFilter.all) {
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: allOrdersData.length,
                  itemBuilder: (context, index) {
                    final data = allOrdersData[index];
                    return _buildOrderCard(
                      data['model'] as WebOrderModel,
                      data['rawData'] as Map<String, dynamic>,
                      data['confirmedBy'] as String?,
                      data['note'] as String?,
                      data['confirmedAt'] as Timestamp?,
                      data['numberOfCustomers'] as int?,
                    );
                  },
                );
              }

              // HIỂN THỊ 3 SECTION
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                children: [
                  // SECTION 1: CHỜ XỬ LÝ
                  if (pendingOrders.isNotEmpty) ...[
                    _buildSectionHeader('Chờ xử lý (${pendingOrders.length})', Colors.red), // Màu đỏ cho nổi bật
                    ...pendingOrders.map((data) => _buildOrderCard(
                          data['model'] as WebOrderModel,
                          data['rawData'] as Map<String, dynamic>,
                          data['confirmedBy'] as String?,
                          data['note'] as String?,
                          data['confirmedAt'] as Timestamp?,
                          data['numberOfCustomers'] as int?,
                        )),
                  ],

                  // SECTION 2: LỊCH HẸN (MỚI)
                  if (scheduledOrders.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                      // Padding rộng hơn chút để tách nhóm
                      child: Row(
                        children: [
                          Icon(Icons.calendar_month, color: Colors.blue, size: 20),
                          SizedBox(width: 8),
                          Text(
                            "Lịch hẹn sắp tới",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                        ],
                      ),
                    ),
                    ...scheduledOrders.map((data) => _buildOrderCard(
                          data['model'] as WebOrderModel,
                          data['rawData'] as Map<String, dynamic>,
                          data['confirmedBy'] as String?,
                          data['note'] as String?,
                          data['confirmedAt'] as Timestamp?,
                          data['numberOfCustomers'] as int?,
                        )),
                  ],

                  // SECTION 3: LỊCH SỬ / ĐÃ XỬ LÝ
                  if (historyOrders.isNotEmpty) ...[
                    _buildSectionHeader('Lịch sử đơn hàng (${historyOrders.length})', Colors.grey.shade700),
                    ...historyOrders.map((data) => _buildOrderCard(
                          data['model'] as WebOrderModel,
                          data['rawData'] as Map<String, dynamic>,
                          data['confirmedBy'] as String?,
                          data['note'] as String?,
                          data['confirmedAt'] as Timestamp?,
                          data['numberOfCustomers'] as int?,
                        )),
                  ],

                  // Nếu tất cả đều trống
                  if (pendingOrders.isEmpty && scheduledOrders.isEmpty && historyOrders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: Center(
                          child: Text("Không có đơn hàng nào trong khoảng thời gian này.", style: TextStyle(color: Colors.grey))),
                    )
                ],
              );
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
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
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

  Widget _buildOrderCard(WebOrderModel order, Map<String, dynamic> rawData, String? confirmedBy, String? note,
      Timestamp? confirmedAt, int? numberOfCustomers) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final timeFormat = DateFormat('HH:mm dd/MM/yyyy');
    final isPending = order.status == 'pending';
    final bool isRetail = widget.currentUser.businessType == 'retail';
    final bool isFnb = (widget.currentUser.businessType ?? '').contains("fnb");

    // --- LOGIC XỬ LÝ DỮ LIỆU HIỂN THỊ (FIX LỖI NA) ---
    String getDisplayData(String rootKey, String? modelValue, {String? nestedKey}) {
      if (rawData[rootKey] != null && rawData[rootKey].toString().isNotEmpty) {
        return rawData[rootKey].toString();
      }
      if (nestedKey != null) {
        final billing = rawData['billing'] as Map<String, dynamic>?;
        final shipping = rawData['shipping'] as Map<String, dynamic>?;

        if (billing != null && billing[nestedKey] != null) {
          return billing[nestedKey].toString();
        }
        if (shipping != null && shipping[nestedKey] != null) {
          return shipping[nestedKey].toString();
        }
      }
      if (modelValue != null && modelValue != 'NA' && modelValue.isNotEmpty) {
        return modelValue;
      }
      return '';
    }

    final String displayPhone = getDisplayData('customerPhone', order.customerPhone, nestedKey: 'phone');
    final String displayName = getDisplayData('customerName', order.customerName, nestedKey: 'first_name');
    final String displayAddressOrTime = getDisplayData('customerAddress', order.customerAddress, nestedKey: 'address_1');

    // ----------------------------------------------------

    IconData typeIcon;
    String titleText;
    Widget line2Widget;
    Widget line3Widget;
    List<Widget> detailsWidgets;

    final double totalToShow = order.totalAmount;
    final String timeString = timeFormat.format(order.createdAt.toDate());

    String statusText;
    Color statusColor;
    IconData statusIcon;

    if (isPending) {
      statusText = 'Chờ xử lý';
      statusColor = AppTheme.primaryColor;
      statusIcon = Icons.question_mark_outlined;
    } else if (order.status == 'confirmed') {
      if (isRetail) {
        // --- LOGIC RETAIL ---
        if (order.type == 'ship') {
          statusText = 'Đang giao hàng';
          statusIcon = Icons.local_shipping;
          statusColor = Colors.orange; // Retail Ship -> Cam
        } else {
          statusText = 'Đã xác nhận';
          statusIcon = Icons.event_available;
          statusColor = Colors.blue; // Retail Schedule -> Blue
        }
      } else {
        // --- LOGIC FNB ---
        if (order.type == 'schedule') {
          statusText = 'Đã xác nhận';
          statusIcon = Icons.check_circle;
          statusColor = Colors.blue.shade700;
        } else {
          statusText = 'Đã báo chế biến';
          statusIcon = Icons.notifications_active_outlined;
          statusColor = Colors.grey;
        }
      }
    } else if (['completed', 'Đã hoàn tất'].contains(order.status)) {
      if (order.type == 'schedule') {
        statusText = 'Đã nhận khách'; // Đổi text cho booking
      } else {
        statusText = 'Đã hoàn tất';
      }
      statusIcon = Icons.check_circle;
      statusColor = Colors.grey;
    } else if (order.status == 'cancelled' || order.status == 'Đã từ chối') {
      statusText = 'Đã hủy';
      statusIcon = Icons.cancel;
      statusColor = Colors.red;
    } else {
      statusText = order.status;
      statusIcon = Icons.info;
      statusColor = Colors.grey;
    }

    // DÒNG 3: TRẠNG THÁI
    if (isPending) {
      line3Widget = const SizedBox.shrink();
    } else {
      final String confirmedAtString = confirmedAt != null ? timeFormat.format(confirmedAt.toDate()) : '';
      line3Widget = Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.person_outline, size: 16, color: Colors.grey.shade700),
            const SizedBox(width: 4),
            Text(confirmedBy ?? 'N/A', style: const TextStyle(fontSize: 15, color: Colors.black87)),
          ]),
          if (confirmedAtString.isNotEmpty)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.access_time_outlined, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 4),
              Text(confirmedAtString, style: const TextStyle(fontSize: 15, color: Colors.black87)),
            ]),
          _buildStatusChip(statusText, statusColor),
        ],
      );
    }

    // CHI TIẾT SẢN PHẨM
    final itemsListWidgets = [
      ...order.items.map((item) {
        String quantityString = formatNumber(item.quantity);
        bool hasNote = item.note != null && item.note!.isNotEmpty;
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          visualDensity: const VisualDensity(horizontal: 0, vertical: -4),
          minVerticalPadding: 0,
          title: Text('$quantityString x ${item.product.productName}', style: const TextStyle(color: Colors.black, fontSize: 15)),
          subtitle: hasNote
              ? Text(item.note!, style: const TextStyle(color: Colors.red, fontStyle: FontStyle.italic, fontSize: 14))
              : null,
          trailing: Text(currencyFormat.format(item.subtotal), style: const TextStyle(color: Colors.black, fontSize: 15)),
        );
      }),
      const Divider(height: 8, thickness: 0.5, color: Colors.grey),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Tổng cộng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
          Text(currencyFormat.format(totalToShow),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black)),
        ],
      ),
    ];

    // CẤU HÌNH HIỂN THỊ THEO LOẠI ĐƠN
    switch (order.type) {
      case 'ship':
        typeIcon = Icons.delivery_dining_outlined;
        titleText = 'Giao hàng - $displayPhone';

        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(Icons.person, displayName.isNotEmpty ? displayName : 'Khách lẻ'),
            _buildInfoRow(Icons.payments_outlined, currencyFormat.format(totalToShow)),
          ],
        );

        detailsWidgets = [
          _buildInfoRow(Icons.location_on_outlined, displayAddressOrTime.isNotEmpty ? displayAddressOrTime : 'Chưa có địa chỉ'),
          const SizedBox(height: 4),
          _buildInfoRow(Icons.access_time, 'Đặt lúc: $timeString'),
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
          if ((note == null || note.isEmpty) && isPending)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.primaryColor),
              icon: const Icon(Icons.add_comment_outlined, size: 16),
              label: const Text('Thêm ghi chú'),
              onPressed: () => _showEditNoteDialog(order.id, note),
            ),
          ...itemsListWidgets,
        ];
        break;

      case 'schedule':
        typeIcon = Icons.calendar_month_outlined;

        String finalName = displayName.isNotEmpty ? displayName : 'Khách đặt lịch';
        if (isFnb && numberOfCustomers != null && numberOfCustomers > 0) {
          finalName = '($numberOfCustomers) $finalName';
        }

        titleText = 'Đặt lịch - $displayPhone';

        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(Icons.people_alt_outlined, finalName),
            _buildInfoRow(Icons.calendar_month_outlined, displayAddressOrTime),
          ],
        );

        detailsWidgets = [
          _buildInfoRow(Icons.access_time, 'Đặt lúc: $timeString'),
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
          if ((note == null || note.isEmpty) && isPending)
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: AppTheme.primaryColor),
              icon: const Icon(Icons.add_comment_outlined, size: 16),
              label: const Text('Thêm ghi chú'),
              onPressed: () => _showEditNoteDialog(order.id, note),
            ),
          ...itemsListWidgets,
        ];
        break;

      case 'at_table':
      default:
        typeIcon = Icons.qr_code_scanner_outlined;
        titleText = 'Khách order - ${order.tableName}';
        line2Widget = Wrap(
          spacing: 12.0,
          runSpacing: 4.0,
          children: [
            _buildInfoRow(Icons.payments_outlined, currencyFormat.format(totalToShow)),
            _buildInfoRow(Icons.access_time, timeString),
          ],
        );
        detailsWidgets = [
          if (note != null && note.isNotEmpty) _buildInfoRow(Icons.edit, note, color: Colors.red),
          ...itemsListWidgets,
        ];
        break;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600.0;

    Widget cardContent = ExpansionTile(
      key: ValueKey('${order.id}_${order.id == _expandedOrderId}'),
      initiallyExpanded: order.id == _expandedOrderId,
      onExpansionChanged: (isExpanding) {
        setState(() {
          _expandedOrderId = isExpanding ? order.id : null;
        });
      },
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      leading: CircleAvatar(
        backgroundColor: statusColor,
        child: Icon(typeIcon, color: Colors.white),
      ),
      title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          line2Widget,
          if (!isPending) ...[const SizedBox(height: 6), line3Widget],
        ],
      ),
      trailing: isMobile ? const SizedBox.shrink() : Icon(statusIcon, color: statusColor, size: 20),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...detailsWidgets,

              // --- BUTTON ACTIONS ---
              if (isPending) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Từ chối'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                        onPressed: () => _showConfirmationDialog(
                          title: 'Từ chối',
                          content: 'Bạn có chắc muốn từ chối yêu cầu này?',
                          onConfirm: () async {
                            final bool success = await _updateOrderStatus(order.id, 'cancelled');
                            if (success) {
                              ToastService().show(message: 'Đã từ chối yêu cầu.', type: ToastType.success);
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
                            ? (isRetail ? 'Xác nhận' : 'Báo bếp')
                            : 'Xác nhận'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isRetail
                              ? Colors.blue
                              : (!(widget.currentUser.businessType ?? '').contains("fnb")
                                  ? Colors.blue.shade700
                                  : AppTheme.primaryColor),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          if (order.type == 'at_table') {
                            _showConfirmationDialog(
                                title: 'Xác nhận', content: 'Gửi báo chế biến?', onConfirm: () => _confirmAtTableOrder(order));
                          } else if (order.type == 'ship') {
                            _showConfirmationDialog(
                                title: 'Xác nhận',
                                content: isRetail ? 'Xác nhận đơn giao hàng?' : 'Gửi báo chế biến?',
                                onConfirm: () => _confirmShipOrder(order, note));
                          } else {
                            _showConfirmationDialog(
                                title: 'Xác nhận',
                                content: 'Xác nhận thông tin Đặt lịch hẹn?',
                                onConfirm: () => _confirmScheduleOrder(order, numberOfCustomers, note));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ] else if (order.status == 'confirmed') ...[
                // --- ACTIONS CHO ĐƠN ĐÃ XÁC NHẬN ---
                if (isRetail) ...[
                  const SizedBox(height: 16),
                  Row(children: [
                    // NÚT HỦY
                    Expanded(
                        child: OutlinedButton.icon(
                      icon: const Icon(Icons.cancel),
                      label: const Text("Hủy đơn"),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                      onPressed: () => _showConfirmationDialog(
                          title: "Hủy đơn",
                          content: "Bạn có chắc muốn hủy đơn này không?",
                          onConfirm: () async {
                            await _updateOrderStatus(order.id, 'cancelled');
                            if (order.type == 'ship') {
                              await FirebaseFirestore.instance.collection('orders').doc(order.id).delete();
                            }
                          }),
                    )),

                    // [ĐÃ SỬA] Nếu là đơn Ship -> Không hiện nút In ở đây nữa (chỉ hiện Hủy).
                    // Nếu là Booking -> Hiện nút Hoàn tất.
                    if (order.type == 'schedule') ...[
                      const SizedBox(width: 12),
                      Expanded(
                          child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text("Hoàn tất"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                        onPressed: () {
                          _showConfirmationDialog(
                            title: "Hoàn tất",
                            content: "Xác nhận khách đã đến và tạo đơn bán hàng?",
                            // Truyền thêm rawData['customerId'] vào tham số thứ 2
                            onConfirm: () => _completeScheduleOrderRetail(order, rawData),
                          );
                        },
                      ))
                    ]
                  ])
                ] else if (order.type == 'ship' || order.type == 'schedule') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      // 1. NÚT HỦY ĐƠN (Mới thêm)
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.cancel),
                          label: const Text("Hủy đơn"),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          onPressed: () => _handleCancelFnBConfirmed(order),
                        ),
                      ),

                      // 2. NÚT XEM ĐƠN (Giữ lại nếu là Ship để xem món)
                      if (order.type == 'ship') ...[
                        const SizedBox(width: 12),
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
                    ],
                  ),
                ]
              ]
            ],
          ),
        ),
      ],
    );

    // [WRAPPER CHO RETAIL SHIP STATUS]
    if (isRetail && order.type == 'ship' && order.status == 'confirmed') {
      return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').doc(order.id).snapshots(),
          builder: (context, snapshot) {
            // Nếu không tìm thấy document trong 'orders' (đã bị xóa do thanh toán hoặc xóa tay)
            // Hoặc document có status != saved
            if (snapshot.hasData && (!snapshot.data!.exists)) {
              // Tự động hiển thị style màu Xám (Đã hoàn tất)
              return _buildCompletedCardVisual(
                  order, rawData, confirmedBy, note, confirmedAt, typeIcon, titleText, line2Widget, detailsWidgets);
            }

            // Nếu vẫn còn đơn saved -> Hiển thị Card Cam bình thường
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: cardContent),
            );
          });
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      child: Theme(data: Theme.of(context).copyWith(dividerColor: Colors.transparent), child: cardContent),
    );
  }

  Widget _buildCompletedCardVisual(WebOrderModel order, Map<String, dynamic> rawData, String? confirmedBy, String? note,
      Timestamp? confirmedAt, IconData typeIcon, String titleText, Widget line2Widget, List<Widget> detailsWidgets) {
    final timeFormat = DateFormat('HH:mm dd/MM/yyyy');
    final confirmedAtString = confirmedAt != null ? timeFormat.format(confirmedAt.toDate()) : '';

    String statusLabel = 'Đã hoàn tất';
    if (order.type == 'schedule') {
      statusLabel = 'Đã nhận khách';
    }
    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        elevation: 2,
        clipBehavior: Clip.antiAlias,
        child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey('${order.id}_completed'),
              title: Text(titleText, style: const TextStyle(fontWeight: FontWeight.bold)),
              leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.check, color: Colors.white)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                line2Widget,
                const SizedBox(height: 6),
                Wrap(spacing: 8, children: [
                  Text(confirmedBy ?? 'N/A'),
                  if (confirmedAtString.isNotEmpty) Text(confirmedAtString),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.grey.withAlpha(25), borderRadius: BorderRadius.circular(12)),
                    child:
                        Text(statusLabel, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13)),
                  )
                ])
              ]),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: detailsWidgets),
                )
              ],
            )));
  }

  Future<void> _confirmScheduleOrder(WebOrderModel order, int? numberOfCustomers, String? note) async {
    if ((widget.currentUser.businessType ?? '').toLowerCase() == 'retail') {
      // 1. Tìm hoặc Tạo khách hàng
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
          ToastService().show(message: "Cần thông tin khách hàng để xác nhận.", type: ToastType.warning);
          return;
        }
        customer = newCustomer;
      }

      // 2. [QUAN TRỌNG] Update ngược lại tên khách vào Web Order để Card hiển thị đúng
      await _syncCustomerToWebOrder(order.id, customer);

      // 3. Cập nhật trạng thái sang Confirmed
      final bool success = await _updateOrderStatus(order.id, 'confirmed');
      if (success) {
        if (note != null && note != order.note) {
          await _updateOrderNote(order.id, note);
        }
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

      ToastService().show(message: 'Đã xác nhận và tạo bàn ảo (Booking).', type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi khi xác nhận: $e", type: ToastType.error);
    }
  }

  Future<void> _completeScheduleOrderRetail(WebOrderModel order, Map<String, dynamic> rawData) async {
    try {
      // 1. LẤY DỮ LIỆU TRỰC TIẾP TỪ RAW DATA (Để tránh lỗi Model mapping ra 'N/A')
      String? finalCustomerId = rawData['customerId'] as String?;
      String finalName = rawData['customerName']?.toString() ?? order.customerName;
      String finalPhone = rawData['customerPhone']?.toString() ?? order.customerPhone;

      // [FIX] Lấy địa chỉ/giờ hẹn trực tiếp từ rawData
      // Web Order manual lưu giờ hẹn vào 'customerAddress' và 'billing.address_1'
      String finalAddress = rawData['customerAddress']?.toString() ?? order.customerAddress;

      // Fallback: Nếu vẫn rỗng hoặc 'N/A', thử lấy trong billing
      if (finalAddress.isEmpty || finalAddress == 'N/A') {
        final billing = rawData['billing'] as Map<String, dynamic>?;
        if (billing != null && billing['address_1'] != null) {
          finalAddress = billing['address_1'].toString();
        }
      }

      // Lấy note trực tiếp luôn cho chắc
      String finalNote = rawData['note']?.toString() ?? order.note ?? '';

      // 2. LOGIC DỰ PHÒNG TÌM KHÁCH (Nếu thiếu ID)
      if (finalCustomerId == null || finalCustomerId.isEmpty) {
        CustomerModel? found = await _findCustomerByPhone(finalPhone);
        if (found != null) {
          finalCustomerId = found.id;
          if (finalName == 'NA' || finalName.isEmpty) {
            finalName = found.name;
          }
        }
      }

      if (finalName == 'NA' || finalName.isEmpty) {
        finalName = 'Khách lẻ';
      }

      // 3. CẬP NHẬT TRẠNG THÁI WEB ORDER
      await _updateOrderStatus(order.id, 'completed');

      // 4. TẠO ĐƠN SAVED (RETAIL)
      final newOrderId = 'booking_${order.id}';

      final savedOrderData = {
        'id': newOrderId,
        'tableId': newOrderId,
        'tableName': 'Đặt lịch',
        'status': 'saved',
        'startTime': FieldValue.serverTimestamp(),
        'items': order.items.map((e) => e.toMap()).toList(),
        'totalAmount': order.totalAmount,
        'storeId': order.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'createdByUid': widget.currentUser.uid,
        'createdByName': widget.currentUser.name ?? 'Admin',
        'numberOfCustomers': 1,
        'version': 1,

        'customerId': finalCustomerId,
        'customerName': finalName,
        'customerPhone': finalPhone,

        // [QUAN TRỌNG] Lưu giá trị đã lấy từ rawData
        'guestAddress': finalAddress,
        'guestNote': finalNote,

        'isWebOrder': true,
        'originalWebOrderId': order.id,
      };

      await _firestoreService.getOrderReference(newOrderId).set(savedOrderData);

      ToastService().show(message: 'Đã hoàn tất & Lưu đơn ra màn hình chính.', type: ToastType.success);
    } catch (e) {
      debugPrint("Lỗi hoàn tất: $e");
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    }
  }

  Future<void> _updateOrderNote(String orderId, String newNote) async {
    try {
      await FirebaseFirestore.instance.collection('web_orders').doc(orderId).update({
        'note': newNote,
        'confirmedBy': widget.currentUser.name, // Cập nhật người sửa cuối
        'confirmedAt': FieldValue.serverTimestamp(), // Cập nhật thời gian
      });
      ToastService().show(message: 'Cập nhật ghi chú thành công.', type: ToastType.success);
    } catch (e) {
      ToastService().show(message: 'Lỗi cập nhật ghi chú: $e', type: ToastType.error);
    }
  }

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

  Future<void> _handleCancelFnBConfirmed(WebOrderModel order) async {
    _showConfirmationDialog(
      title: "Hủy đơn",
      content: "Bạn có chắc muốn hủy đơn này? Bàn ảo sẽ bị xóa và đơn hàng sẽ bị hủy.",
      onConfirm: () async {
        try {
          // 1. Cập nhật Web Order -> cancelled
          await _updateOrderStatus(order.id, 'cancelled');

          // 2. Xác định ID bàn ảo
          // Logic: Ship -> ship_{id}, Schedule -> schedule_{id}
          final String prefix = order.type == 'ship' ? 'ship_' : 'schedule_';
          final String virtualTableId = '$prefix${order.id}';

          // 3. Xóa bàn ảo khỏi collection 'tables'
          // Cần try-catch riêng vì có thể bàn đã bị xóa trước đó
          try {
            await _firestoreService.deleteTable(virtualTableId);
          } catch (e) {
            debugPrint("Lỗi xóa bàn ảo (có thể không tồn tại): $e");
          }

          // 4. Hủy đơn hàng trong collection 'orders'
          // (Lưu ý: ID đơn hàng bán chính là ID của web order theo logic xác nhận)
          await _firestoreService.updateOrderStatus(order.id, 'cancelled');

          ToastService().show(message: "Đã hủy đơn và xóa bàn ảo thành công.", type: ToastType.success);
        } catch (e) {
          debugPrint("Lỗi khi hủy đơn FnB: $e");
          ToastService().show(message: "Lỗi hệ thống: $e", type: ToastType.error);
        }
      },
    );
  }
}

class ManualOrderItemCard extends StatefulWidget {
  final OrderItem item;
  final int index;
  final Function(OrderItem) onUpdate;
  final VoidCallback onRemove;
  final VoidCallback onTap;

  const ManualOrderItemCard({
    super.key,
    required this.item,
    required this.index,
    required this.onUpdate,
    required this.onRemove,
    required this.onTap,
  });

  @override
  State<ManualOrderItemCard> createState() => _ManualOrderItemCardState();
}

class _ManualOrderItemCardState extends State<ManualOrderItemCard> {
  late TextEditingController _noteController;
  late TextEditingController _qtyController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.item.note);
    _qtyController = TextEditingController(text: formatNumber(widget.item.quantity));
  }

  @override
  void didUpdateWidget(covariant ManualOrderItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.quantity != oldWidget.item.quantity) {
      final String newText = formatNumber(widget.item.quantity);
      if (_qtyController.text != newText) {
        _qtyController.text = newText;
      }
    }
    if (widget.item.note != oldWidget.item.note) {
      if (_noteController.text != widget.item.note) {
        _noteController.text = widget.item.note ?? '';
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    _qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    // [SỬA] Tổng tiền hiển thị = (Đơn giá đã gồm topping) * Số lượng
    final double lineTotal = item.price * item.quantity;

    // Lấy danh sách ĐVT
    final List<String> availableUnits = [];
    if (item.product.unit != null && item.product.unit!.isNotEmpty) {
      availableUnits.add(item.product.unit!);
    }
    for (var u in item.product.additionalUnits) {
      if (u['unitName'] != null) availableUnits.add(u['unitName']);
    }
    if (availableUnits.isEmpty) availableUnits.add('Cái');
    final uniqueUnits = availableUnits.toSet().toList();

    // --- WIDGETS CON ---
    Widget buildUnitSelector() {
      return SizedBox(
        height: 40,
        child: AppDropdown<String>(
          labelText: 'Đơn vị',
          value: uniqueUnits.contains(item.selectedUnit) ? item.selectedUnit : uniqueUnits.first,
          isDense: true,
          items: uniqueUnits.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (val) {
            if (val != null) {
              double newPrice = item.product.sellPrice;
              if (val == item.product.unit) {
                newPrice = item.product.sellPrice;
              } else {
                final u = item.product.additionalUnits.firstWhere((element) => element['unitName'] == val, orElse: () => {});
                if (u.isNotEmpty) newPrice = (u['sellPrice'] as num).toDouble();
              }
              // Khi đổi ĐVT, reset topping về rỗng và giá về giá gốc
              widget.onUpdate(item.copyWith(selectedUnit: val, price: newPrice, toppings: {}));
            }
          },
        ),
      );
    }

    Widget buildQtyInput() {
      // Chiều rộng vùng chứa nút (48px cho Desktop, 32px cho Mobile)
      final double btnWidth = isDesktop ? 35.0 : 30.0;

      return Container(
        height: 40,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Nút TRỪ
            SizedBox(
              width: btnWidth,
              height: 40, // Chiều cao bằng container
              child: IconButton(
                icon: const Icon(Icons.remove, color: Colors.red, size: 18),
                padding: EdgeInsets.zero,
                // Bỏ padding mặc định để icon căn giữa chuẩn
                style: IconButton.styleFrom(
                  shape: const CircleBorder(), // [QUAN TRỌNG] Ép hiệu ứng thành hình tròn
                ),
                onPressed: () {
                  if (item.quantity > 1) {
                    widget.onUpdate(item.copyWith(quantity: item.quantity - 1));
                  }
                },
              ),
            ),

            // Ô NHẬP SỐ LƯỢNG
            Expanded(
              child: TextFormField(
                controller: _qtyController,
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.only(bottom: 12),
                  isDense: true,
                ),
                onChanged: (val) {
                  final double? newQty = double.tryParse(val.replaceAll(',', ''));
                  if (newQty != null && newQty > 0) {
                    widget.onUpdate(item.copyWith(quantity: newQty));
                  }
                },
              ),
            ),

            // Nút CỘNG
            SizedBox(
              width: btnWidth,
              height: 40,
              child: IconButton(
                icon: const Icon(Icons.add, color: AppTheme.primaryColor, size: 18),
                padding: EdgeInsets.zero,
                style: IconButton.styleFrom(
                  shape: const CircleBorder(), // [QUAN TRỌNG] Ép hiệu ứng thành hình tròn
                ),
                onPressed: () {
                  widget.onUpdate(item.copyWith(quantity: item.quantity + 1));
                },
              ),
            ),
          ],
        ),
      );
    }

    Widget buildNoteInput() {
      return TextField(
        controller: _noteController,
        decoration: InputDecoration(
          hintText: 'Ghi chú...',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
          prefixIcon: const Icon(Icons.edit_note, size: 18, color: Colors.grey),
        ),
        style: const TextStyle(fontSize: 13),
        onChanged: (val) {
          widget.onUpdate(item.copyWith(note: () => val.trim().isEmpty ? null : val.trim()));
        },
      );
    }

    Widget buildSelectedToppings() {
      if (item.toppings.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: item.toppings.entries.map((e) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Text(
                '+ ${e.key.productName} (x${formatNumber(e.value)})',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            );
          }).toList(),
        ),
      );
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: isDesktop
              ? Column(
                  // DESKTOP
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child:
                              Text(item.product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        const SizedBox(width: 16),
                        Text("${formatNumber(lineTotal)} đ",
                            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: widget.onRemove,
                          icon: const Icon(Icons.close, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (item.toppings.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Align(alignment: Alignment.centerLeft, child: buildSelectedToppings()),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(flex: 2, child: buildUnitSelector()),
                        const SizedBox(width: 8),
                        Expanded(flex: 2, child: buildQtyInput()),
                        const SizedBox(width: 8),
                        Expanded(flex: 6, child: buildNoteInput()),
                      ],
                    )
                  ],
                )
              : Column(
                  // MOBILE
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child:
                              Text(item.product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                        IconButton(
                          onPressed: widget.onRemove,
                          icon: const Icon(Icons.close, color: Colors.grey),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                    if (item.toppings.isNotEmpty) buildSelectedToppings(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text("${formatNumber(lineTotal)} đ",
                            style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: buildNoteInput(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: buildUnitSelector()),
                        const SizedBox(width: 8),
                        Expanded(child: buildQtyInput()),
                      ],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class CreateManualWebOrderScreen extends StatefulWidget {
  final UserModel currentUser;

  const CreateManualWebOrderScreen({super.key, required this.currentUser});

  @override
  State<CreateManualWebOrderScreen> createState() => _CreateManualWebOrderScreenState();
}

class _CreateManualWebOrderScreenState extends State<CreateManualWebOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  bool _isSubmitting = false;

  // Mặc định không báo lỗi đỏ ngay, chỉ khi bấm Submit mới hiện
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;

  WebOrderTypeFilter _orderType = WebOrderTypeFilter.ship;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  final _customerCountController = TextEditingController(text: '1');

  DateTime? _bookingTime;

  final List<OrderItem> _selectedItems = [];
  Timer? _debounceTimer;
  CustomerModel? _foundCustomer;

  double get _totalAmount => _selectedItems.fold(0, (tong, item) => tong + (item.price * item.quantity));

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(_onPhoneChanged);
  }

  @override
  void dispose() {
    _phoneController.removeListener(_onPhoneChanged);
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    _customerCountController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onPhoneChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 800), () async {
      final phone = _phoneController.text.trim();
      if (phone.length >= 10) {
        final query = await FirebaseFirestore.instance
            .collection('customers')
            .where('storeId', isEqualTo: widget.currentUser.storeId)
            .where('phone', isEqualTo: phone)
            .limit(1)
            .get();

        if (query.docs.isNotEmpty && mounted) {
          final customer = CustomerModel.fromFirestore(query.docs.first);
          setState(() {
            _foundCustomer = customer;
            // Tự điền tên
            if (_nameController.text.isEmpty) {
              _nameController.text = customer.name;
            }
            // Nếu là Ship và chưa nhập địa chỉ -> Điền địa chỉ cũ
            if (_orderType == WebOrderTypeFilter.ship && customer.address != null && _addressController.text.isEmpty) {
              _addressController.text = customer.address!;
            }
          });
          ToastService().show(message: "Đã tìm thấy khách hàng cũ.", type: ToastType.success);
        } else {
          setState(() {
            _foundCustomer = null;
          });
        }
      }
    });
  }

  Future<void> _pickProducts() async {
    final previouslySelected = _selectedItems.map((e) => e.product).toList();
    final results = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: previouslySelected,
      groupByCategory: true,
      // [SỬA] Chỉ cho phép chọn các loại này, loại trừ 'Nguyên liệu', 'Vật liệu'
      allowedProductTypes: ['Hàng hóa', 'Dịch vụ/Tính giờ', 'Thành phẩm/Combo', 'Topping/Bán kèm'],
    );

    if (results != null) {
      setState(() {
        for (var product in results) {
          if (!_selectedItems.any((item) => item.product.id == product.id)) {
            _selectedItems.add(OrderItem(
              product: product,
              quantity: 1,
              price: product.sellPrice,
              selectedUnit: product.unit ?? '',
              addedAt: Timestamp.now(),
              addedBy: widget.currentUser.name ?? 'Staff',
              discountValue: 0,
              commissionStaff: {},
              note: null,
            ));
          }
        }
      });
    }
  }

  Future<void> _processActiveOrderLogic({
    required String orderId,
    required Map<String, dynamic> webOrderData,
    required CustomerModel customer,
    required bool isShip,
    required String guestAddress,
  }) async {
    // Check Retail
    final bool isRetail = widget.currentUser.businessType == 'retail';

    // 1. Gửi lệnh in bếp (Chỉ FnB Ship mới in bếp ngay, Retail in sau khi xác nhận/in bill)
    if (isShip && !isRetail) {
      PrintQueueService().addJob(PrintJobType.kitchen, {
        'storeId': widget.currentUser.storeId,
        'tableName': 'Giao hàng',
        'userName': widget.currentUser.name ?? 'Thu ngân',
        'items': _selectedItems.map((e) => e.toMap()).toList(),
        'customerName': customer.name,
        'printType': 'add',
      });
    }

    final String prefix = isShip ? 'ship_' : 'schedule_';
    final String tableName = isShip ? 'Giao hàng' : (isRetail ? 'Đặt lịch' : 'Booking');

    final String virtualTableId = isRetail ? orderId : '$prefix$orderId';
    final int stt = isShip ? -999 : -998;

    // 2. Tạo Bàn ảo (Chỉ cần thiết cho FnB, nhưng tạo cho Retail cũng không sao để giữ place)
    if (!isRetail) {
      final virtualTableData = {
        'id': virtualTableId,
        'tableName': tableName,
        'storeId': widget.currentUser.storeId,
        'stt': stt,
        'serviceId': '',
        'tableGroup': 'Online',
      };
      await _firestoreService.setTable(virtualTableId, virtualTableData);
    }

    // 3. Tạo Order
    // [LOGIC GIÁ] Trừ tiền topping ra để lấy lại giá gốc vì OrderScreen sẽ tự cộng lại
    final itemsForActiveOrder = _selectedItems.map((item) {
      double toppingTotal = 0;
      if (item.toppings.isNotEmpty) {
        item.toppings.forEach((p, qty) {
          toppingTotal += p.sellPrice * qty;
        });
      }
      final double basePrice = item.price - toppingTotal;

      return item
          .copyWith(
              price: basePrice,
              // Retail Ship/Schedule đều chưa trừ kho (sentQuantity=0) cho đến khi thanh toán
              // FnB Ship thì trừ luôn (sentQuantity = quantity)
              sentQuantity: (isShip && !isRetail) ? item.quantity : 0)
          .toMap();
    }).toList();

    // [QUAN TRỌNG] Retail dùng 'saved', FnB dùng 'active'
    final String status = isRetail ? 'saved' : 'active';

    if (isRetail && !isShip) {
      // Nếu là Retail Đặt lịch -> Thoát, không tạo order saved, chỉ giữ web_order
      return;
    }

    final orderData = {
      'id': orderId,
      'tableId': virtualTableId,
      'tableName': isShip ? 'Giao hàng' : tableName,
      'status': status,
      'startTime': webOrderData['createdAt'],
      'items': itemsForActiveOrder,
      'totalAmount': _totalAmount,
      'storeId': widget.currentUser.storeId,
      'createdAt': webOrderData['createdAt'],
      'createdByUid': widget.currentUser.uid,
      'createdByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
      'numberOfCustomers': webOrderData['customerInfo']['numberOfCustomers'] ?? 1,
      'version': 1,
      'customerId': customer.id,
      'customerName': customer.name,
      'customerPhone': customer.phone,
      'guestAddress': guestAddress,
      'guestNote': _noteController.text.trim(),
      'isWebOrder': true,
    };

    await _firestoreService.getOrderReference(orderId).set(orderData, SetOptions(merge: true));
  }

  Future<void> _submitOrder() async {
    // 1. Chặn nếu đang xử lý
    if (_isSubmitting) return;

    setState(() {
      _autovalidateMode = AutovalidateMode.always;
    });

    if (!_formKey.currentState!.validate()) {
      ToastService().show(message: "Vui lòng kiểm tra lại thông tin.", type: ToastType.warning);
      return;
    }

    final bool isShip = _orderType == WebOrderTypeFilter.ship;

    if (!isShip && _bookingTime == null) {
      ToastService().show(message: "Vui lòng chọn giờ hẹn", type: ToastType.warning);
      return;
    }

    if (_selectedItems.isEmpty) {
      ToastService().show(message: "Vui lòng chọn ít nhất 1 sản phẩm", type: ToastType.warning);
      return;
    }

    // 2. Bắt đầu Loading
    setState(() => _isSubmitting = true);

    try {
      final String typeString = isShip ? 'ship' : 'schedule';

      CustomerModel? finalCustomer = _foundCustomer;

      if (finalCustomer == null) {
        final newCustomer = await showDialog<CustomerModel>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AddEditCustomerDialog(
            firestoreService: _firestoreService,
            storeId: widget.currentUser.storeId,
            initialName: _nameController.text.trim(),
            initialPhone: _phoneController.text.trim(),
            initialAddress: isShip ? _addressController.text.trim() : '',
          ),
        );

        if (newCustomer == null) {
          ToastService().show(message: "Vui lòng tạo khách hàng để tiếp tục.", type: ToastType.warning);
          if (mounted) setState(() => _isSubmitting = false);
          return;
        }
        finalCustomer = newCustomer;
      }

      // Tách biệt 2 biến địa chỉ/thời gian
      String webOrderAddress; // Dùng cho Card (Danh sách Web Order) -> yyyy
      String virtualTableAddress; // Dùng cho Bàn ảo (POS) -> yy

      if (!isShip) {
        // Booking: Tạo 2 định dạng khác nhau
        webOrderAddress = DateFormat('HH:mm dd/MM/yyyy').format(_bookingTime!); // Card hiện yyyy
        virtualTableAddress = DateFormat('HH:mm dd/MM/yy').format(_bookingTime!); // Bàn ảo hiện yy
      } else {
        // Ship: Dùng chung địa chỉ
        webOrderAddress = _addressController.text.trim();
        virtualTableAddress = webOrderAddress;
      }

      int customerCount = 1;
      if (!isShip) {
        customerCount = int.tryParse(_customerCountController.text) ?? 1;
      }

      final String staffName = widget.currentUser.name ?? widget.currentUser.phoneNumber;
      final newDocRef = FirebaseFirestore.instance.collection('web_orders').doc();
      final String orderId = newDocRef.id;

      // [SỬA LẠI ĐOẠN NÀY] Khai báo trực tiếp map contactInfo để dùng
      final Map<String, dynamic> contactInfoMap = {
        'first_name': finalCustomer.name,
        'phone': finalCustomer.phone,
        'address_1': webOrderAddress,
      };

      final webOrderData = {
        'id': orderId,
        'storeId': widget.currentUser.storeId,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'confirmed', // Đặt lịch thủ công là đã xác nhận luôn
        'type': typeString,
        'customerName': finalCustomer.name,
        'customerPhone': finalCustomer.phone,
        'customerId': finalCustomer.id, // Lưu ID khách

        // Lưu yyyy vào Web Order để hiển thị trên Card
        'customerAddress': webOrderAddress,

        'note': _noteController.text.trim(),

        // Sử dụng biến map vừa tạo ở trên
        'billing': contactInfoMap,
        'shipping': contactInfoMap,

        'customerInfo': {
          'numberOfCustomers': customerCount,
        },
        'items': _selectedItems.map((e) => e.toMap()).toList(),
        'totalAmount': _totalAmount,
        'source': 'manual',
        'createdBy': staffName,
        'confirmedBy': staffName,
        'confirmedAt': FieldValue.serverTimestamp(),
      };

      await newDocRef.set(webOrderData);

      await _processActiveOrderLogic(
        orderId: orderId,
        webOrderData: webOrderData,
        customer: finalCustomer,
        isShip: isShip,
        guestAddress: virtualTableAddress,
      );

      if (isShip) {
        ToastService().show(message: "Đã tạo đơn giao hàng.", type: ToastType.success);
      } else {
        ToastService().show(message: "Đã tạo lịch hẹn.", type: ToastType.success);
      }

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _isSubmitting = false);
      ToastService().show(message: "Lỗi lưu đơn: $e", type: ToastType.error);
    }
  }

  Widget _buildPhoneField() {
    return TextFormField(
      controller: _phoneController,
      decoration: const InputDecoration(
        labelText: "SĐT *",
        prefixIcon: Icon(Icons.phone),
        border: OutlineInputBorder(),
        isDense: true,
        counterText: "",
      ),
      keyboardType: TextInputType.phone,
      maxLength: 10,
      validator: (val) {
        if (val == null || val.isEmpty) return 'Nhập SĐT';

        if (!val.startsWith('0')) return 'SĐT phải bắt đầu bằng số 0';

        if (val.length < 9) return 'SĐT không hợp lệ';

        return null;
      },
    );
  }

  Widget _buildNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: "Tên khách",
        prefixIcon: Icon(Icons.person),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      textCapitalization: TextCapitalization.words,
      // Không bắt buộc validate ở đây vì nếu chưa có sẽ hiện popup tạo
    );
  }

  Widget _buildAddressField() {
    return TextFormField(
      controller: _addressController,
      decoration: const InputDecoration(
        labelText: "Địa chỉ giao hàng *",
        prefixIcon: Icon(Icons.location_on_outlined),
        border: OutlineInputBorder(),
        isDense: true,
      ),
      maxLines: 1,
      validator: (val) => (val == null || val.trim().isEmpty) ? 'Nhập địa chỉ' : null,
    );
  }

  Widget _buildPaxField() {
    return TextFormField(
      controller: _customerCountController,
      keyboardType: TextInputType.number,
      decoration: const InputDecoration(
        labelText: "Số khách",
        prefixIcon: Icon(Icons.people),
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildTimePicker() {
    return FormField<DateTime>(
      validator: (value) {
        if (_bookingTime == null) return 'Chọn giờ';

        // [THÊM MỚI] Kiểm tra thời gian phải sau hiện tại
        if (_bookingTime!.isBefore(DateTime.now())) {
          return 'Giờ hẹn phải sau thời điểm hiện tại';
        }

        return null;
      },
      builder: (FormFieldState<DateTime> state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () async {
                final now = DateTime.now(); // Lấy mốc thời gian thực tế lúc bấm

                final newTime = await showOmniDateTimePicker(
                  context: context,
                  initialDate: _bookingTime ?? now,
                  // Nếu chưa chọn thì start từ Now

                  // [QUAN TRỌNG] Chặn chọn ngày quá khứ ngay trong popup
                  firstDate: now,

                  lastDate: now.add(const Duration(days: 365)),
                  is24HourMode: true,
                );

                if (newTime != null) {
                  setState(() => _bookingTime = newTime);
                  state.didChange(newTime); // Cập nhật state cho FormField

                  // Nếu đang hiển thị lỗi thì validate lại ngay để xóa lỗi
                  if (state.hasError) {
                    state.validate();
                  }
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: "Giờ hẹn *",
                  prefixIcon: const Icon(Icons.access_time_filled, color: AppTheme.primaryColor),
                  border: const OutlineInputBorder(),
                  isDense: true,
                  errorText: state.errorText, // Hiển thị lỗi từ validator
                ),
                child: Text(
                  _bookingTime != null ? DateFormat('HH:mm dd/MM/yyyy').format(_bookingTime!) : "Chọn giờ...",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: _bookingTime != null ? FontWeight.bold : FontWeight.normal,
                    color: _bookingTime != null ? Colors.black : Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildNoteField() {
    return TextFormField(
      controller: _noteController,
      decoration: const InputDecoration(
        labelText: "Ghi chú",
        prefixIcon: Icon(Icons.note_alt_outlined),
        border: OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Future<void> _showEditItemDialog(int index, OrderItem item) async {
    // Nếu sản phẩm không có topping thì báo luôn
    if (item.product.accompanyingItems.isEmpty) {
      ToastService().show(message: "Sản phẩm này không có topping/bán kèm.", type: ToastType.warning);
      return;
    }

    final allProducts = await _firestoreService.getAllProductsStream(widget.currentUser.storeId).first;

    if (!mounted) return;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _ProductOptionsDialog(
        product: item.product,
        allProducts: allProducts,
        initialToppings: item.toppings,
      ),
    );

    if (result != null) {
      final newToppings = result['selectedToppings'] as Map<ProductModel, double>;

      // 1. Lấy giá gốc theo ĐVT (VD: 35k)
      final double basePrice = _getBasePriceForUnit(item.product, item.selectedUnit);

      // 2. Tính tổng tiền Topping (VD: 20k)
      double toppingsTotal = 0;
      newToppings.forEach((product, qty) {
        toppingsTotal += product.sellPrice * qty;
      });

      // 3. [SỬA QUAN TRỌNG] Cộng dồn tiền Topping vào Giá bán luôn (35k + 20k = 55k)
      final double finalPrice = basePrice + toppingsTotal;

      setState(() {
        _selectedItems[index] = item.copyWith(
          price: finalPrice, // Lưu giá 55k
          toppings: newToppings,
        );
      });
    }
  }

  double _getBasePriceForUnit(ProductModel product, String selectedUnit) {
    if ((product.unit ?? '') == selectedUnit) {
      return product.sellPrice;
    }
    final additionalUnitData =
        product.additionalUnits.firstWhereOrNull((unitData) => (unitData['unitName'] as String?) == selectedUnit);
    if (additionalUnitData != null) {
      return (additionalUnitData['sellPrice'] as num?)?.toDouble() ?? product.sellPrice;
    }
    return product.sellPrice;
  }

  @override
  Widget build(BuildContext context) {
    final bool isShip = _orderType == WebOrderTypeFilter.ship;
    final bool isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Tạo Đơn / Đặt Lịch"),
        actions: [
          // [SỬA] Hiển thị Loading hoặc Nút bấm
          _isSubmitting
              ? const Padding(
                  padding: EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                )
              : TextButton(
                  // Nếu đang xử lý thì disable nút (null)
                  onPressed: _isSubmitting ? null : _submitOrder,
                  child: const Text("XÁC NHẬN", style: TextStyle(fontWeight: FontWeight.bold)),
                )
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                autovalidateMode: _autovalidateMode, // Chỉ bật khi bấm submit
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SEGMENT BUTTON
                    SegmentedButton<WebOrderTypeFilter>(
                      segments: const [
                        ButtonSegment(
                          value: WebOrderTypeFilter.ship,
                          label: Text("Giao hàng"),
                          icon: Icon(Icons.local_shipping_outlined),
                        ),
                        ButtonSegment(
                          value: WebOrderTypeFilter.schedule,
                          label: Text("Đặt lịch"),
                          icon: Icon(Icons.calendar_month_outlined),
                        ),
                      ],
                      selected: {_orderType},
                      onSelectionChanged: (Set<WebOrderTypeFilter> newSelection) {
                        setState(() {
                          _orderType = newSelection.first;
                          _autovalidateMode = AutovalidateMode.disabled; // Reset validate khi chuyển tab
                        });
                      },
                      showSelectedIcon: false,
                      style: ButtonStyle(
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // FORM NHẬP LIỆU
                    if (isShip)
                      // === SHIP ===
                      isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 2, child: _buildPhoneField()),
                                const SizedBox(width: 8),
                                Expanded(flex: 4, child: _buildAddressField()),
                                const SizedBox(width: 8),
                                Expanded(flex: 4, child: _buildNoteField()),
                              ],
                            )
                          : Column(
                              children: [
                                _buildPhoneField(),
                                const SizedBox(height: 12),
                                _buildAddressField(),
                                const SizedBox(height: 12),
                                _buildNoteField(),
                              ],
                            )
                    else
                      // === BOOKING ===
                      isDesktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 1, child: _buildPhoneField()),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: _buildNameField()),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: _buildPaxField()),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: _buildTimePicker()),
                                const SizedBox(width: 8),
                                Expanded(flex: 1, child: _buildNoteField()),
                              ],
                            )
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _buildPhoneField()),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildNameField()),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(child: _buildPaxField()),
                                    const SizedBox(width: 8),
                                    Expanded(child: _buildTimePicker()),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _buildNoteField(),
                              ],
                            ),

                    const Divider(
                      height: 24,
                      thickness: 0.5,
                      color: Colors.grey,
                    ),

                    // DANH SÁCH MÓN
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Sản phẩm (${_selectedItems.length})",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: _pickProducts,
                          icon: const Icon(Icons.add),
                          label: const Text("Thêm món"),
                        ),
                      ],
                    ),

                    if (_selectedItems.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
                        child: const Text("Chưa có sản phẩm nào", style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _selectedItems.length,
                        itemBuilder: (context, index) {
                          return ManualOrderItemCard(
                            item: _selectedItems[index],
                            index: index,
                            onRemove: () {
                              setState(() {
                                _selectedItems.removeAt(index);
                              });
                            },
                            onUpdate: (updatedItem) {
                              setState(() {
                                _selectedItems[index] = updatedItem;
                              });
                            },
                            onTap: () => _showEditItemDialog(index, _selectedItems[index]),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),

          // BOTTOM BAR
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.white, boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4, offset: const Offset(0, -2))]),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Tổng tiền:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text(
                  NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(_totalAmount),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final ProductModel product;
  final List<ProductModel> allProducts;
  final Map<ProductModel, double>? initialToppings;

  const _ProductOptionsDialog({
    required this.product,
    required this.allProducts,
    this.initialToppings,
  });

  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  List<ProductModel> _accompanyingProducts = [];
  final Map<String, double> _selectedToppings = {};

  @override
  void initState() {
    super.initState();

    // 1. Khởi tạo danh sách Topping từ ID
    final productMap = {for (var p in widget.allProducts) p.id: p};
    _accompanyingProducts = widget.product.accompanyingItems
        .map((item) => productMap[item['productId']])
        .where((p) => p != null)
        .cast<ProductModel>()
        .toList();

    // 2. Fill lại số lượng Topping cũ (nếu có)
    if (widget.initialToppings != null) {
      widget.initialToppings!.forEach((p, qty) {
        final matchingProduct = _accompanyingProducts.firstWhereOrNull((ap) => ap.id == p.id);
        if (matchingProduct != null) {
          _selectedToppings[matchingProduct.id] = qty;
        }
      });
    }
  }

  void _onConfirm() {
    // Chỉ trả về danh sách Topping đã chọn
    final Map<ProductModel, double> toppingsMap = {};

    _selectedToppings.forEach((productId, quantity) {
      if (quantity > 0) {
        final product = _accompanyingProducts.firstWhereOrNull((p) => p.id == productId);
        if (product != null) {
          toppingsMap[product] = quantity;
        }
      }
    });

    Navigator.of(context).pop({
      'selectedToppings': toppingsMap,
    });
  }

  void _updateToppingQuantity(String productId, double change) {
    setState(() {
      double currentQuantity = _selectedToppings[productId] ?? 0;
      double newQuantity = currentQuantity + change;
      if (newQuantity < 0) newQuantity = 0;
      _selectedToppings[productId] = newQuantity;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasToppings = _accompanyingProducts.isNotEmpty;

    return AlertDialog(
      title: Text(widget.product.productName, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasToppings) ...[
                const Text('Chọn Topping / Bán kèm:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Column(
                  children: _accompanyingProducts.map((topping) {
                    final quantity = _selectedToppings[topping.id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              "${topping.productName} (+${formatNumber(topping.sellPrice)})",
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, color: Colors.red, size: 18),
                                  onPressed: () => _updateToppingQuantity(topping.id, -1),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  padding: EdgeInsets.zero,
                                ),
                                Text(
                                  formatNumber(quantity),
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, color: AppTheme.primaryColor, size: 18),
                                  onPressed: () => _updateToppingQuantity(topping.id, 1),
                                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                  padding: EdgeInsets.zero,
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ] else
                const Center(
                    child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text("Sản phẩm này không có Topping.", style: TextStyle(color: Colors.grey)),
                )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
        ElevatedButton(onPressed: _onConfirm, child: const Text('Xác nhận')),
      ],
    );
  }
}
