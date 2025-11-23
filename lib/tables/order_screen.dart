import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';
import '../models/product_group_model.dart';
import '../models/product_model.dart';
import '../models/table_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/toast_service.dart';
import '../theme/app_theme.dart';
import 'dart:async';
import '../products/barcode_scanner_screen.dart';
import '../models/print_job_model.dart';
import '../services/print_queue_service.dart';
import '/screens/sales/payment_screen.dart';
import '../theme/number_utils.dart';
import '../models/customer_model.dart';
import '../services/settings_service.dart';
import '../models/store_settings_model.dart';
import '../services/pricing_service.dart';
import '../widgets/customer_selector.dart';
import '../widgets/edit_order_item_dialog.dart';
import '../theme/string_extensions.dart';
import '../models/quick_note_model.dart';
import '../screens/quick_notes_screen.dart';
import '../tables/table_transfer_screen.dart';
import 'package:flutter/services.dart';

class OrderScreen extends StatefulWidget {
  final UserModel currentUser;
  final TableModel table;
  final OrderModel? initialOrder;

  const OrderScreen(
      {super.key,
        required this.currentUser,
        required this.table,
        this.initialOrder});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _firestoreService = FirestoreService();
  late final SettingsService _settingsService;
  StreamSubscription<StoreSettings>? _settingsSub;
  StreamSubscription<List<QuickNoteModel>>? _quickNotesSub;

  double get _totalAmount =>
      _displayCart.values.fold(0, (total, item) => total + item.subtotal);
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _priceUpdateTimer;
  final Map<String, OrderItem> _cart = {};
  final Map<String, OrderItem> _localChanges = {};
  final Map<String, TimePricingResult> _timeBasedDataCache = {};
  int _numberOfCustomers = 1;

  Map<String, OrderItem> get _displayCart {
    final mergedCart = Map<String, OrderItem>.from(_cart);
    mergedCart.addAll(_localChanges);

    mergedCart.removeWhere((key, item) => item.status == 'cancelled');

    return mergedCart;
  }

  final _searchController = TextEditingController();
  OrderModel? _currentOrder;
  List<ProductGroupModel> _menuGroups = [];
  List<ProductModel> _menuProducts = [];
  List<Map<String, dynamic>> _lastFirestoreItems = [];
  List<ProductModel> _lastKnownProducts = [];
  bool _isMenuView = true;
  bool _isPaymentView = false;
  bool get _hasUnsentItems {
    if (_localChanges.isEmpty) return false;

    for (final item in _localChanges.values) {
      if (item.hasUnsentChanges) {
        return true;
      }
    }

    return false;
  }
  bool _suppressInitialToast = false;
  bool get isDesktop => MediaQuery.of(context).size.width >= 1100;
  bool _allowProvisionalBill = true;
  bool _printBillAfterPayment = true;
  bool _notifyKitchenAfterPayment = false;
  bool _showPricesOnProvisional = true;
  bool _showPricesOnReceipt = true;
  bool _skipKitchenPrint = false;
  String? _lastCustomerIdFromOrder;
  String _searchQuery = '';
  Stream<DocumentSnapshot>? _orderStream;
  Stream<List<ProductModel>>? _productsStream;
  CustomerModel? _selectedCustomer;
  String? _customerNameFromOrder;
  String? _customerPhoneFromOrder;
  String? _customerAddressFromOrder;
  bool _isFinalizingPayment = false;
  static final Map<String, PaymentState> _paymentStateCache = {};
  List<UserModel> _staffList = [];
  bool _isLoadingStaff = false;
  bool _promptForCash = true;
  List<QuickNoteModel> _quickNotes = [];
  String? _customerNoteFromOrder;
  bool _printLabelOnKitchen = false;
  double _labelWidth = 50.0;
  double _labelHeight = 30.0;

  @override
  void initState() {
    super.initState();
    _settingsService = SettingsService();
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _settingsSub = _settingsService.watchStoreSettings(settingsId).listen((s) {
      if (!mounted) return;
      setState(() {
        _allowProvisionalBill = s.allowProvisionalBill;
        _printBillAfterPayment = s.printBillAfterPayment;
        _notifyKitchenAfterPayment = s.notifyKitchenAfterPayment;
        _showPricesOnProvisional = s.showPricesOnProvisional;
        _showPricesOnReceipt = s.showPricesOnReceipt;
        _promptForCash = s.promptForCash ?? true;
        _skipKitchenPrint = s.skipKitchenPrint ?? false;
        _printLabelOnKitchen = s.printLabelOnKitchen ?? false;
        _labelWidth = s.labelWidth ?? 50.0;
        _labelHeight = s.labelHeight ?? 30.0;
      });
    }, onError: (e, st) {
      debugPrint('watchStoreSettings error: $e');
    }, cancelOnError: true);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    _currentOrder = widget.initialOrder;
    _isMenuView = widget.initialOrder == null;
    if (widget.initialOrder != null) _suppressInitialToast = true;

    if (_currentOrder != null) {
      _orderStream = FirebaseFirestore.instance
          .collection('orders')
          .doc(_currentOrder!.id)
          .snapshots();
    } else {
      _orderStream = _firestoreService.getOrderStreamForTable(widget.table.id);
    }

    _productsStream =
        _firestoreService.getAllProductsStream(widget.currentUser.storeId);

    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });

    if (widget.initialOrder != null) {
      _numberOfCustomers = widget.initialOrder!.numberOfCustomers ?? 1;
    }

    _priceUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateTimeBasedPrices();
    });

    _fetchStaff();
    _listenQuickNotes();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _settingsSub?.cancel();
    _quickNotesSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _priceUpdateTimer?.cancel();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    // 1. Kiểm tra màn hình hiện tại có hợp lệ không
    if (!mounted || ModalRoute.of(context)?.isCurrent != true) return false;

    // --- SỬA Ở ĐÂY: Nếu đang ở màn hình thanh toán (bên phải), không can thiệp phím tắt ---
    if (_isPaymentView) return false;
    // --------------------------------------------------------------------------------------

    // 2. Kiểm tra xem người dùng có đang nhập liệu ở ô khác...
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus != null &&
        currentFocus.context != null &&
        currentFocus.context!.widget is EditableText &&
        currentFocus != _searchFocusNode) {
      return false;
    }

    // 3. Nếu ô tìm kiếm ĐANG được chọn (Focus) -> Để hệ thống tự xử lý, không can thiệp
    if (_searchFocusNode.hasFocus) {
      return false;
    }

    // --- XỬ LÝ KHI Ô TÌM KIẾM KHÔNG CÓ FOCUS ---

    // TRƯỜNG HỢP A: Phím Enter -> Thực hiện tìm kiếm/thêm món
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_searchController.text.isNotEmpty) {
        _handleBarcodeScan(_searchController.text);
        return true; // Đã xử lý
      }
      return false;
    }

    // TRƯỜNG HỢP B: Phím Xóa (Backspace) -> Xóa ký tự cuối
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      final text = _searchController.text;
      if (text.isNotEmpty) {
        final newText = text.substring(0, text.length - 1);
        _searchController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
        return true;
      }
      return false;
    }

    // TRƯỜNG HỢP C: Ký tự bình thường (Số/Chữ) -> Điền vào ô tìm kiếm
    if (event.character != null &&
        event.character!.isNotEmpty &&
        !_isControlKey(event.logicalKey)) {

      final newText = _searchController.text + event.character!;
      _searchController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length), // Đưa con trỏ về cuối
      );
      return true; // Đã xử lý
    }

    return false;
  }

  bool _isControlKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.shift ||
        key == LogicalKeyboardKey.control ||
        key == LogicalKeyboardKey.alt ||
        key == LogicalKeyboardKey.meta ||
        key == LogicalKeyboardKey.tab ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.f1 || key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 || key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 || key == LogicalKeyboardKey.f6 ||
        key == LogicalKeyboardKey.f7 || key == LogicalKeyboardKey.f8 ||
        key == LogicalKeyboardKey.f9 || key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.f11 || key == LogicalKeyboardKey.f12;
  }

  Future<void> _listenQuickNotes() async {
    _quickNotesSub = _firestoreService.getQuickNotes(widget.currentUser.storeId).listen((notes) {
      if (mounted) {
        setState(() {
          _quickNotes = notes;
        });
      }
    }, onError: (e) {
      debugPrint('Lỗi khi lắng nghe quick notes: $e');
    });
  }

  void _handleBarcodeScan(String value) async {
    if (value.trim().isEmpty) {
      if (!_isPaymentView && !_searchFocusNode.hasFocus) {
        _searchFocusNode.requestFocus();
      }
      return;
    }

    final query = value.trim();

    final foundProduct = _menuProducts.firstWhereOrNull((p) =>
    p.productCode == query ||
        p.additionalBarcodes.contains(query) ||
        (p.productCode?.toLowerCase() == query.toLowerCase()) ||
        p.additionalBarcodes.any((b) => b.toLowerCase() == query.toLowerCase())
    );

    if (foundProduct != null) {
      await _addItemToCart(foundProduct);

      if (_searchController.text.isNotEmpty) {
        _searchController.clear();
      }

      if (!_isPaymentView) {
        _searchFocusNode.requestFocus();
      }

      ToastService().show(
          message: "Đã thêm: ${foundProduct.productName}",
          type: ToastType.success,
          duration: const Duration(seconds: 1)
      );
    } else {
      ToastService().show(
          message: "Không tìm thấy mã: $query",
          type: ToastType.warning
      );
      if (!_isPaymentView) {
        _searchFocusNode.requestFocus();
      }
    }
  }

  Widget _buildTableTransferButton() {
    return IconButton(
      icon: const Icon(Icons.call_split_outlined, color: AppTheme.primaryColor, size: 30),
      tooltip: 'Tách/Gộp/Chuyển Bàn',
      onPressed: (_currentOrder == null) ? null : () async {
        final result = await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TableTransferScreen(
              currentUser: widget.currentUser,
              sourceOrder: _currentOrder!,
              sourceTable: widget.table,
            ),
          ),
        );

        if (result == true && mounted) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  void _updateTimeBasedPrices() {
    if (!mounted) return;
    bool needsUpdate = false;

    _displayCart.forEach((lineId, item) {
      final serviceSetup = item.product.serviceSetup;
      if (serviceSetup != null &&
          serviceSetup['isTimeBased'] == true &&
          !item.isPaused) {
        final pricingResult =
        TimeBasedPricingService.calculatePriceWithBreakdown(
          product: item.product,
          startTime: item.addedAt,
          isPaused: item.isPaused,
          pausedAt: item.pausedAt,
          totalPausedDurationInSeconds: item.totalPausedDurationInSeconds,
        );

        // So sánh giá mới và cũ để quyết định có cần setState hay không
        if ((pricingResult.totalPrice - item.price).abs() > 0.01) {
          final updatedItem = item.copyWith(
            price: pricingResult.totalPrice,
            priceBreakdown: pricingResult.blocks,
          );

          // Cập nhật lại cache để giao diện nhận được dữ liệu mới
          _timeBasedDataCache[lineId] = pricingResult;

          // Cập nhật vào đúng nơi (cart đã lưu hoặc local changes)
          if (_localChanges.containsKey(lineId)) {
            _localChanges[lineId] = updatedItem;
          } else if (_cart.containsKey(lineId)) {
            _cart[lineId] = updatedItem;
          }

          needsUpdate = true;
        }
      }
    });

    if (needsUpdate) {
      setState(() {});
    }
  }

  void _togglePauseTimeBasedItem(String lineId) {
    OrderItem? item = _localChanges[lineId] ?? _cart[lineId];
    if (item == null || item.product.serviceSetup?['isTimeBased'] != true) {
      return;
    }
    if (item.isPaused) {
      // --- TIẾP TỤC TÍNH GIỜ ---
      final pausedDuration =
          DateTime.now().difference(item.pausedAt!.toDate()).inSeconds;
      item = item.copyWith(
        isPaused: false,
        pausedAt: () => null,
        totalPausedDurationInSeconds:
        item.totalPausedDurationInSeconds + pausedDuration,
      );
    } else {
      // --- TẠM DỪNG ---
      final result = TimeBasedPricingService.calculatePriceWithBreakdown(
          product: item.product,
          startTime: item.addedAt,
          totalPausedDurationInSeconds: item.totalPausedDurationInSeconds);
      item = item.copyWith(
        price: result.totalPrice,
        priceBreakdown: result.blocks,
        isPaused: true,
        pausedAt: () => Timestamp.now(),
      );
    }

    setState(() {
      _localChanges[lineId] = item!;
    });
    _saveOrder();
  }

  Future<void> _addItemToCart(ProductModel product) async {
    final serviceSetup = product.serviceSetup;
    if (serviceSetup != null && serviceSetup['isTimeBased'] == true) {
      if (_displayCart.values.any((item) => item.product.id == product.id)) {
        ToastService().show(message: "Dịch vụ này đã được tính giờ.", type: ToastType.warning);
        return;
      }

      final startTime = Timestamp.now();
      final initialResult = TimeBasedPricingService.calculatePriceWithBreakdown(
        product: product,
        startTime: startTime,
        isPaused: false,
        pausedAt: null,
        totalPausedDurationInSeconds: 0,
      );

      final newItem = OrderItem(
        product: product,
        price: initialResult.totalPrice,
        priceBreakdown: initialResult.blocks,
        quantity: 1,
        sentQuantity: 1,
        addedBy: widget.currentUser.name ?? 'N/A',
        addedAt: startTime,
        discountValue: 0,
        discountUnit: '%',
        note: null,
        commissionStaff: {},
      );

      // Cập nhật UI ngay
      setState(() {
        _localChanges[newItem.lineId] = newItem;
        _timeBasedDataCache[newItem.lineId] = initialResult;
      });

      if (isDesktop) {
        final saved = await _saveTimeBasedServiceOnlyWithMerge(newItem);
        if (!saved) {
          if (mounted) {
            setState(() {
              _localChanges.remove(newItem.lineId);
              _timeBasedDataCache.remove(newItem.lineId);
            });
          }
          ToastService().show(message: "Không thể lưu dịch vụ tính giờ.", type: ToastType.error);
          return;
        }
      } else {
        // MOBILE: dùng đường mobile riêng để không mất món chưa báo bếp
        await _saveTimeBasedServiceOnly(newItem);
      }

      return; // kết thúc nhánh dịch vụ tính giờ
    }

    // --- LOGIC MỚI: Xử lý Ghi chú nhanh và Tùy chọn ---
    final relevantNotes = _quickNotes.where((note) {
      return note.productIds.isEmpty || note.productIds.contains(product.id);
    }).toList();

    // Điều kiện mở dialog: Tùy chọn đơn vị, Topping, HOẶC Ghi chú nhanh
    final bool needsOptionDialog = product.additionalUnits.isNotEmpty || product.accompanyingItems.isNotEmpty || relevantNotes.isNotEmpty;

    OrderItem newItem;

    if (needsOptionDialog) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ProductOptionsDialog(
          product: product,
          allProducts: _menuProducts,
          relevantQuickNotes: relevantNotes, // TRUYỀN GHI CHÚ
        ),
      );
      if (result == null) return;

      final selectedUnit = result['selectedUnit'] as String;
      final priceForUnit = result['price'] as double;
      final selectedToppings = result['selectedToppings'] as Map<ProductModel, double>;
      final selectedNoteText = result['selectedNote'] as String?; // LẤY GHI CHÚ

      newItem = OrderItem(
        product: product, selectedUnit: selectedUnit, price: priceForUnit,
        toppings: selectedToppings, addedBy: widget.currentUser.name ?? 'N/A', addedAt: Timestamp.now(),
        discountValue: 0,
        discountUnit: '%',
        note: selectedNoteText.nullIfEmpty, // GÁN GHI CHÚ (quan trọng cho groupKey)
        commissionStaff: {},
      );
    } else {
      newItem = OrderItem(
        product: product, price: product.sellPrice, selectedUnit: product.unit ?? '',
        addedBy: widget.currentUser.name ?? 'N/A', addedAt: Timestamp.now(),
        discountValue: 0,
        discountUnit: '%',
        note: null,
        commissionStaff: {},
      );
    }

    final gk = newItem.groupKey;
    setState(() {
      final existingEntry = _displayCart.entries.firstWhereOrNull((entry) => entry.value.groupKey == gk);
      if (existingEntry != null) {
        final existingItem = existingEntry.value;
        final existingKey = existingEntry.key;
        _localChanges[existingKey] = existingItem.copyWith(quantity: existingItem.quantity + 1);
      } else {
        _localChanges[newItem.lineId] = newItem;
      }
    });
  }

  Future<bool> _saveTimeBasedServiceOnlyWithMerge(OrderItem serviceItem) async {
    try {
      final DocumentReference orderRef;
      final DocumentSnapshot serverSnapshot;

      if (_currentOrder != null) {
        orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
        serverSnapshot = await orderRef.get();
      } else {
        orderRef = _firestoreService.getOrderReference(widget.table.id);
        serverSnapshot = await orderRef.get();
      }

      final serverData = serverSnapshot.data() as Map<String, dynamic>?;

      if (!serverSnapshot.exists || ['paid', 'cancelled'].contains(serverData?['status'])) {
        final itemsToSave = [serviceItem.toMap()];
        final total = serviceItem.subtotal;
        final currentVersion = (serverData?['version'] as num?)?.toInt() ?? 0;

        final newOrderData = {
          'id': orderRef.id,
          'tableId': widget.table.id,
          'tableName': widget.table.tableName,
          'status': 'active',
          'startTime': Timestamp.now(),
          'items': itemsToSave,
          'totalAmount': total,
          'storeId': widget.currentUser.storeId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': widget.currentUser.uid,
          'createdByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
          'customerId': _selectedCustomer?.id,
          'customerName': _selectedCustomer?.name,
          'customerPhone': _selectedCustomer?.phone,
          'numberOfCustomers': _numberOfCustomers,
          'version': currentVersion + 1,
        };

        await orderRef.set(newOrderData);

        // SỬA LỖI CRASH: Tạo model cục bộ với timestamp của client
        final localOrderData = Map<String, dynamic>.from(newOrderData);
        localOrderData['createdAt'] = Timestamp.now();
        _currentOrder = OrderModel.fromMap(localOrderData);
      } else {
        // Cập nhật đơn hàng hiện có
        final serverItems =
        List<Map<String, dynamic>>.from(serverData!['items'] ?? []);
        serverItems.add(serviceItem.toMap());

        final newTotalAmount = serverItems.fold<double>(0.0, (tong, m) {
          return tong + _rawSubtotalFromMap(m);
        });

        final currentVersion = (serverData['version'] as num?)?.toInt() ?? 0;

        await orderRef.update({
          'items': serverItems,
          'totalAmount': newTotalAmount,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      if (mounted) {
        setState(() {
          _localChanges.remove(serviceItem.lineId);
          _cart[serviceItem.lineId] = serviceItem;
        });
      }
      return true;
    } catch (e) {
      debugPrint("Lỗi khi lưu dịch vụ tính giờ (Merge): $e");
      if (mounted) {
        ToastService().show(
            message: "Lỗi lưu dịch vụ: ${e.toString()}", type: ToastType.error);
      }
      return false;
    }
  }

  Future<void> _saveTimeBasedServiceOnly(OrderItem serviceItem) async {
    try {
      final DocumentReference orderRef;
      if (_currentOrder != null) {
        orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
      } else {
        orderRef = _firestoreService.getOrderReference(widget.table.id);
      }
      await _firestoreService.runTransaction((transaction) async {
        final serverSnapshot = await transaction.get(orderRef);
        final serverData = serverSnapshot.data() as Map<String, dynamic>?;

        if (!serverSnapshot.exists || ['paid', 'cancelled'].contains(serverData?['status'])) {
          final itemsToSave = [serviceItem.toMap()];
          final total = serviceItem.subtotal;
          final currentVersion = (serverData?['version'] as num?)?.toInt() ?? 0;

          final newOrderData = {
            'id': orderRef.id,
            'tableId': widget.table.id,
            'tableName': widget.table.tableName,
            'status': 'active',
            'startTime': Timestamp.now(),
            'items': itemsToSave,
            'totalAmount': total,
            'storeId': widget.currentUser.storeId,
            'createdAt': FieldValue.serverTimestamp(),
            'createdByUid': widget.currentUser.uid,
            'createdByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
            'customerId': _selectedCustomer?.id,
            'customerName': _selectedCustomer?.name,
            'customerPhone': _selectedCustomer?.phone,
            'numberOfCustomers': _numberOfCustomers,
            'version': currentVersion + 1,
          };

          transaction.set(orderRef, newOrderData);
          _currentOrder = OrderModel.fromMap(newOrderData);
          return;
        }

        final serverItems = List<Map<String, dynamic>>.from(serverData!['items'] ?? []);
        serverItems.add(serviceItem.toMap());

        final newTotalAmount = serverItems.fold<double>(0.0, (tong, m) {
          return tong + _rawSubtotalFromMap(m);
        });

        final currentVersion = (serverData['version'] as num?)?.toInt() ?? 0;

        transaction.update(orderRef, {
          'items': serverItems,
          'totalAmount': newTotalAmount,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        setState(() {
          _localChanges.remove(serviceItem.lineId);
          _cart[serviceItem.lineId] = serviceItem;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localChanges.remove(serviceItem.lineId);
        });
        ToastService().show(message: "Lỗi lưu dịch vụ: ${e.toString()}", type: ToastType.error);
      }
    }
  }

  double _rawSubtotalFromMap(Map<String, dynamic> m) {
    final q = (m['quantity'] as num?)?.toDouble() ?? 0.0;
    final p = (m['price'] as num?)?.toDouble() ?? 0.0;

    // --- Lấy dữ liệu mới ---
    final productData = (m['product'] as Map<String, dynamic>?) ?? {};
    final isTimeBased = productData['serviceSetup']?['isTimeBased'] == true;
    final discVal = (m['discountValue'] as num?)?.toDouble() ?? 0.0;
    final discUnit = (m['discountUnit'] as String?) ?? '%';
    // ------------------------

    double basePrice = p; // p là tổng tiền (time-based) hoặc đơn giá (normal)
    double discountedPrice = basePrice;

    if (discVal > 0) {
      if (discUnit == '%') {
        discountedPrice = basePrice * (1 - discVal / 100);
      } else { // 'VND'
        discountedPrice = (basePrice - discVal).clamp(0, double.maxFinite);
      }
    }

    if (isTimeBased) {
      return discountedPrice; // Trả về tổng tiền đã chiết khấu
    }

    // Tính toán cho món thường (giống code cũ)
    double toppingsTotal = 0.0;
    final tops = m['toppings'];
    if (tops is List) {
      for (final t in tops) {
        if (t is Map) {
          final tp = (t['price'] as num?)?.toDouble() ?? 0.0;
          final tq = (t['quantity'] as num?)?.toDouble() ?? 0.0;
          toppingsTotal += tp * tq;
        }
      }
    }

    // Trả về (đơn giá đã CK * SL) + topping
    return q * discountedPrice + toppingsTotal;
  }

  Future<void> _scanBarcode() async {
    final barcodeScanRes = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );
    if (!mounted) return;
    if (barcodeScanRes != null) {
      _searchController.text = barcodeScanRes;
    }
  }

  void _updateQuantity(String lineId, double change) {
    final currentItem = _displayCart[lineId];
    if (currentItem == null) return;
    final newQuantity = currentItem.quantity + change;
    if (newQuantity < 0) return;
    setState(() {
      final originalItem = _cart[lineId];
      if (originalItem != null && newQuantity == originalItem.quantity) {
        _localChanges.remove(lineId);
      } else {
        _localChanges[lineId] = currentItem.copyWith(quantity: newQuantity);
      }
    });
  }

  Future<bool> _sendToKitchen({
    bool navigateToCartViewOnSuccess = false,
    bool popOnFinish = true,
    bool performPrint = true,
  }) async {
    if (_isFinalizingPayment) {
      ToastService().show(
          message: "Đang trong quá trình thanh toán.", type: ToastType.warning);
      return false;
    }

    final bool isBookingTable = widget.table.id.startsWith('schedule_');
    final bool hasItemsInCartWithZeroSent = _cart.values.any((item) => item.sentQuantity == 0 && item.quantity > 0);

    if (_localChanges.isEmpty && (!isBookingTable || !hasItemsInCartWithZeroSent)) {
      ToastService().show(
          message: "Chưa có món mới để gởi báo bếp.", type: ToastType.warning);
      return true;
    }

    final oldCart = Map<String, OrderItem>.from(_cart);

    if (isBookingTable && hasItemsInCartWithZeroSent && _localChanges.isEmpty) {
      _cart.forEach((key, item) {
        if (item.sentQuantity == 0 && item.quantity > 0) {
          _localChanges[key] = item;
        }
      });
    }

    final changedEntries = _localChanges.entries.map((e) {
      if (e.value.status != 'cancelled') {
        final updated = e.value.copyWith(sentQuantity: e.value.quantity);
        return MapEntry(e.key, updated);
      }
      return e;
    }).toList();

    for (final e in changedEntries) {
      _localChanges[e.key] = e.value;
    }

    final success = await _saveOrder();
    if (!success || _currentOrder == null) return false;

    final List<Map<String, dynamic>> addItems = [];
    final List<Map<String, dynamic>> cancelItems = [];

    for (final e in changedEntries) {
      if (e.value.status == 'cancelled') continue;
      final item = e.value;
      final oldSentQty = oldCart[item.lineId]?.sentQuantity ?? 0;
      final newQty = item.quantity;
      final change = newQty - oldSentQty;

      if (change == 0) continue;
      if (change > 0) {
        final payload = item.toMap();
        payload['quantity'] = change;
        addItems.add({'isCancel': false, ...payload});
      } else {
        final delta = -change;
        final payload = item.toMap();
        payload['quantity'] = delta;
        cancelItems.add({'isCancel': true, ...payload});
      }
    }

    if (performPrint) {
      final bool isOnlineOrder = widget.table.id.startsWith('ship_') || widget.table.id.startsWith('schedule_');

      // 1. CHUẨN BỊ DỮ LIỆU (Payload)
      Map<String, dynamic>? kitchenPayload;
      Map<String, dynamic>? cancelPayload;
      Map<String, dynamic>? labelPayload;

      // Payload Bếp (Thêm món)
      if (!_skipKitchenPrint && addItems.isNotEmpty) {
        kitchenPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': addItems,
          'printType': 'add'
        };
        if (isOnlineOrder && _customerNameFromOrder != null) {
          kitchenPayload['customerName'] = _customerNameFromOrder;
        }
      }

      // Payload Bếp (Hủy món)
      if (!_skipKitchenPrint && cancelItems.isNotEmpty) {
        cancelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': cancelItems,
          'printType': 'cancel'
        };
      }

      // Payload Tem (Label)
      if (_printLabelOnKitchen && addItems.isNotEmpty) {
        labelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'items': addItems,
          'labelWidth': _labelWidth,
          'labelHeight': _labelHeight,
        };
      }

      // 2. BẮN LỆNH IN (CÓ DELAY)

      // ƯU TIÊN 1: IN TEM (Nhẹ, Nhanh)
      if (labelPayload != null) {
        debugPrint(">>> [ORDER] Bắn lệnh Tem trước");
        PrintQueueService().addJob(PrintJobType.label, labelPayload);

        // --- QUAN TRỌNG: Nghỉ 100ms để lệnh Tem chui lọt xuống Android trước ---
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // ƯU TIÊN 2: IN BẾP (Nặng do render PDF)
      if (kitchenPayload != null) {
        debugPrint(">>> [ORDER] Bắn lệnh Bếp");
        PrintQueueService().addJob(PrintJobType.kitchen, kitchenPayload);
      }

      // ƯU TIÊN 3: IN HỦY
      if (cancelPayload != null) {
        // Nếu có cả lệnh Bếp và Hủy, cũng nên delay xíu cho chắc
        if (kitchenPayload != null) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        PrintQueueService().addJob(PrintJobType.cancel, cancelPayload);
      }

      // Thông báo UI
      if (addItems.isEmpty && cancelItems.isEmpty) {
        ToastService().show(message: "Không có thay đổi để báo bếp.", type: ToastType.warning);
      } else {
        String msg = "Đã gửi báo chế biến.";
        if (_skipKitchenPrint) msg += " (Không in phiếu bếp)";
        ToastService().show(message: msg, type: ToastType.success);
      }
    }

    if (navigateToCartViewOnSuccess) {
      setState(() => _isMenuView = false);
    } else {
      if (popOnFinish && mounted) {
        Navigator.of(context).pop();
      }
    }
    return true;
  }

  Future<void> _handlePrintProvisionalBill() async {
    final itemsToPrint =
    _displayCart.values.where((item) => item.quantity > 0).toList();
    if (itemsToPrint.isEmpty) {
      ToastService()
          .show(message: "Chưa có món nào để in.", type: ToastType.warning);
      return;
    }

    try {
      if (_hasUnsentItems) {
        await _sendToKitchen(popOnFinish: false);
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_currentOrder == null) {
        ToastService().show(
            message: "Lỗi: Không tìm thấy đơn hàng để in.",
            type: ToastType.error);
        return;
      }

      _performPrintProvisionalBillInBackground(itemsToPrint);
      ToastService()
          .show(message: "Đã gửi lệnh in tạm tính.", type: ToastType.success);

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint("Lỗi trong quá trình xử lý in tạm tính: $e");
      ToastService().show(
          message: "Đã xảy ra lỗi, không thể hoàn tất thao tác.",
          type: ToastType.error);
    }
  }

  Future<void> _performPrintProvisionalBillInBackground(
      List<OrderItem> itemsToPrint) async {
    try {
      final storeInfo =
      await _firestoreService.getStoreDetails(widget.currentUser.storeId);
      if (storeInfo == null) {
        throw Exception("Không tìm thấy thông tin cửa hàng.");
      }

      final summaryData = {
        'subtotal': _totalAmount,
        'customer': {
          'name': _selectedCustomer?.name,
          'phone': _selectedCustomer?.phone,
          'address': _selectedCustomer?.address,
          'guestAddress': _customerAddressFromOrder ?? '',
        },
      };

      final printData = {
        'storeId': widget.currentUser.storeId,
        'tableName': _currentOrder?.tableName ?? widget.table.tableName,
        'userName': widget.currentUser.name ?? 'Unknown',
        'items': itemsToPrint.map((item) => item.toMap()).toList(),
        'storeInfo': storeInfo,
        'showPrices': _showPricesOnProvisional,
        'summary': summaryData,
      };

      if (_currentOrder != null) {
        final orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
        final orderDoc = await orderRef.get();
        if (orderDoc.exists) {
          final currentVersion =
              (orderDoc.data() as Map<String, dynamic>)['version'] as int? ?? 1;
          await orderRef.update({
            'provisionalBillPrintedAt': FieldValue.serverTimestamp(),
            'provisionalBillSource': 'order_screen',
            'version': currentVersion + 1,
          });
        }
      }

      PrintQueueService().addJob(PrintJobType.provisional, printData);
    } catch (e) {
      debugPrint("Lỗi khi chuẩn bị in tạm tính (background): ${e.toString()}");
      ToastService().show(
          message: "Lỗi khi cập nhật thời gian in: ${e.toString()}",
          type: ToastType.error);
    }
  }

  Future<void> _handlePayment() async {
    if (_displayCart.isEmpty) {
      ToastService().show(
          message: "Chưa có món nào để thanh toán.", type: ToastType.warning);
      return;
    }

    bool saved = true;
    if (_hasUnsentItems) {
      saved = await _sendToKitchen(
        popOnFinish: false,
        navigateToCartViewOnSuccess: false,
        performPrint: _notifyKitchenAfterPayment,
      );
    } else {
      saved = await _saveOrder();
    }

    if (!saved || _currentOrder == null) {
      ToastService().show(
          message: "Không thể chuẩn bị dữ liệu thanh toán.",
          type: ToastType.error);
      return;
    }
    if (!mounted) return;

    final savedState = _paymentStateCache[_currentOrder!.id];
    _isFinalizingPayment = true;

    final upToDateOrder = _currentOrder!.copyWith(
      items: _displayCart.values.map((item) => item.toMap()).toList(),
      totalAmount: _totalAmount,
    );

    if (isDesktop) {
      setState(() {
        _isPaymentView = true;
      });
    } else {
      final result = await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PaymentScreen(
            order: upToDateOrder,
            currentUser: widget.currentUser,
            subtotal: _totalAmount,
            customer: _selectedCustomer,
            customerAddress: _customerAddressFromOrder,
            printBillAfterPayment: _printBillAfterPayment,
            showPricesOnReceipt: _showPricesOnReceipt,
            initialState: savedState,
            promptForCash: _promptForCash,
          ),
        ),
      );

      _isFinalizingPayment = false;
      if (result is PaymentState) {
        _paymentStateCache[_currentOrder!.id] = result;
      } else if (result == true) {
        _paymentStateCache.remove(_currentOrder!.id);
      }
    }
  }

  Widget _buildQuickNotesIconButton() {
    return IconButton(
      icon: const Icon(Icons.note_add_outlined, color: AppTheme.primaryColor, size: 30),
      tooltip: 'Quản lý ghi chú nhanh',
      onPressed: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => QuickNotesScreen(
              currentUser: widget.currentUser,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;
          final bool isBookingTable = widget.table.id.startsWith('schedule_');

          if (_hasUnsentItems && !isBookingTable) {
            final wantsToExit = await _showExitConfirmationDialog();
            if (wantsToExit == true) {
              _localChanges.clear();
              if (context.mounted) Navigator.of(context).pop();
            }
          } else if (_localChanges.isNotEmpty) {
            if (isBookingTable) {
              _saveOrder();
              if (context.mounted) Navigator.of(context).pop(result);
            } else {
              await _saveOrder();
              if (context.mounted) Navigator.of(context).pop(result);
            }
          } else {
            if (context.mounted) Navigator.of(context).pop(result);
          }
        },
        child: StreamBuilder<List<ProductModel>>(
          stream: _productsStream,
          builder: (context, productSnapshot) {
            if (productSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                  body: Center(child: CircularProgressIndicator()));
            }
            if (productSnapshot.hasError || !productSnapshot.hasData) {
              return Scaffold(
                  body: Center(
                      child:
                      Text('Lỗi tải thực đơn: ${productSnapshot.error}')));
            }
            _menuProducts = productSnapshot.data!
                .where((p) =>
            p.productType != 'Nguyên liệu' &&
                p.productType != 'Vật liệu' &&
                p.isVisibleInMenu == true)
                .toList();
            final bool productsHaveChanged = !const DeepCollectionEquality()
                .equals(_menuProducts.map((p) => p.toMap()).toList(),
                _lastKnownProducts.map((p) => p.toMap()).toList());

            if (productsHaveChanged && _lastKnownProducts.isNotEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _updateCartWithNewPrices();
              });
            }
            _lastKnownProducts = _menuProducts;

            return FutureBuilder<List<ProductGroupModel>>(
              future: _firestoreService
                  .getProductGroups(widget.currentUser.storeId),
              builder: (context, groupSnapshot) {
                if (groupSnapshot.connectionState == ConnectionState.done &&
                    groupSnapshot.hasData) {
                  _menuGroups = groupSnapshot.data!
                      .where((g) =>
                      _menuProducts.any((p) => p.productGroup == g.name))
                      .toList();
                }
                return FutureBuilder<List<ProductGroupModel>>(
                  future: _firestoreService
                      .getProductGroups(widget.currentUser.storeId),
                  builder: (context, groupSnapshot) {
                    if (groupSnapshot.connectionState == ConnectionState.done &&
                        groupSnapshot.hasData) {

                      // 1. Lọc các nhóm có sản phẩm (như cũ)
                      _menuGroups = groupSnapshot.data!
                          .where((g) =>
                          _menuProducts.any((p) => p.productGroup == g.name))
                          .toList();

                      // 2. (THÊM MỚI) Kiểm tra xem có sản phẩm nào không có nhóm không
                      final bool hasOrphanProducts = _menuProducts.any(
                              (p) => p.productGroup == null || p.productGroup!.isEmpty);

                      // 3. (THÊM MỚI) Nếu có, thêm nhóm "Khác" vào cuối danh sách
                      if (hasOrphanProducts) {
                        final otherGroup = ProductGroupModel(
                            id: 'khac_group_id',
                            name: 'Khác',
                            stt: 99999
                        );
                        if (!_menuGroups.any((g) => g.name == 'Khác')) {
                          _menuGroups.add(otherGroup);
                        }
                      }
                    }

                    // Phần còn lại của code giữ nguyên
                    return StreamBuilder<DocumentSnapshot>(
                      stream: _orderStream,
                      builder: (context, orderSnapshot) {
                        if (orderSnapshot.connectionState ==
                            ConnectionState.active &&
                            orderSnapshot.hasData) {
                          final doc = orderSnapshot.data!;
                          List<Map<String, dynamic>> newItemsFromFirestore = [];

                          if (doc.exists &&
                              (doc.data() as Map<String, dynamic>)['status'] ==
                                  'active') {
                            final data = doc.data() as Map<String, dynamic>;
                            _currentOrder = OrderModel.fromFirestore(doc);

                            _customerNameFromOrder = data['customerName'] as String?;
                            _customerPhoneFromOrder = data['customerPhone'] as String?;
                            _customerAddressFromOrder = data['guestAddress'] as String?;
                            _customerNoteFromOrder = data['guestNote'] as String?;

                            final String? cid = data['customerId'] as String?;
                            if (cid != _lastCustomerIdFromOrder) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _updateSelectedCustomer(cid, data);
                              });
                            }

                            newItemsFromFirestore = List<Map<String, dynamic>>.from(
                                (data['items'] ?? []) as List);
                          } else {
                            if (_displayCart.isEmpty) {
                              _currentOrder = null;
                            }
                            _customerNameFromOrder = null;
                            _customerPhoneFromOrder = null;
                            _customerAddressFromOrder = null;
                            _customerNoteFromOrder = null;
                          }

                          final bool hasChanges = !const DeepCollectionEquality()
                              .equals(newItemsFromFirestore, _lastFirestoreItems);

                          if (hasChanges) {
                            _lastFirestoreItems = newItemsFromFirestore;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (!mounted) return;
                              _rebuildCartFromFirestore(newItemsFromFirestore);
                              if (_suppressInitialToast) {
                                _suppressInitialToast = false;
                              }
                            });
                          }
                        }

                        return isDesktop
                            ? _buildDesktopLayout()
                            : _buildMobileLayout();
                      },
                    );
                  },
                );
              },
            );
          },
        ));
  }

  Future<void> _rebuildCartFromFirestore(List<dynamic> firestoreItems) async {
    final currentProducts = _menuProducts;
    if (currentProducts.isEmpty && firestoreItems.isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _rebuildCartFromFirestore(firestoreItems);
      });
      return;
    }

    final Map<String, OrderItem> mergedCart = {};

    for (var itemData in firestoreItems) {
      final newItem = OrderItem.fromMap(
        (itemData as Map).cast<String, dynamic>(),
        allProducts: currentProducts,
      );

      final existingEntry = mergedCart.entries.firstWhereOrNull(
            (entry) => entry.value.groupKey == newItem.groupKey,
      );

      if (existingEntry != null) {
        final existingItem = existingEntry.value;
        final existingKey = existingEntry.key;

        final updatedItem = existingItem.copyWith(
          quantity: existingItem.quantity + newItem.quantity,
          sentQuantity: existingItem.sentQuantity + newItem.sentQuantity,
          addedAt: (existingItem.addedAt.seconds < newItem.addedAt.seconds)
              ? existingItem.addedAt
              : newItem.addedAt,
        );

        mergedCart[existingKey] = updatedItem;

      } else {
        mergedCart[newItem.lineId] = newItem;
      }
    }

    if (mounted) {
      setState(() {
        _cart.clear();
        _cart.addAll(mergedCart);
      });
      if (widget.table.id.startsWith('schedule_')) {
        final Map<String, OrderItem> itemsToMove = {};
        _cart.forEach((key, item) {
          if (item.sentQuantity == 0 && item.quantity > 0) {
            itemsToMove[key] = item;
          }
        });
        if (itemsToMove.isNotEmpty) {
          setState(() {
            _localChanges.addAll(itemsToMove);
          });
        }
      }
      _updateTimeBasedPrices();
    }
  }

  Widget _buildDesktopLayout() {
    final groupNames = ['Tất cả', ..._menuGroups.map((g) => g.name)];
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.table.tableName),
        automaticallyImplyLeading: true,
        actions: [
          _buildTableTransferButton(),
          const SizedBox(width: 8),
          _buildQuickNotesIconButton(),
          const SizedBox(width: 8),
          SizedBox(
            width: 300,
            child: _buildSearchBar(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: DefaultTabController(
        length: groupNames.length,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 4,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: Theme.of(context).cardColor,
                    shape: cardShape,
                    shadows: kElevationToShadow[1],
                  ),
                  child: _buildCartView(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 6,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: ShapeDecoration(
                    color: Theme.of(context).cardColor,
                    shape: cardShape,
                    shadows: kElevationToShadow[1],
                  ),
                  child: _isPaymentView
                      ? (_currentOrder == null
                      ? const Center(child: CircularProgressIndicator())
                      : PaymentView(
                    order: _currentOrder!.copyWith(
                      items: _displayCart.values.map((item) => item.toMap()).toList(),
                      totalAmount: _totalAmount,
                    ),
                    currentUser: widget.currentUser,
                    subtotal: _totalAmount,
                    customer: _selectedCustomer,
                    customerAddress: _customerAddressFromOrder,
                    printBillAfterPayment: _printBillAfterPayment,
                    showPricesOnReceipt: _showPricesOnReceipt,
                    initialState: _currentOrder != null ? _paymentStateCache[_currentOrder!.id] : null,
                    promptForCash: _promptForCash,
                    onCancel: () {
                      setState(() { _isPaymentView = false; });
                      _isFinalizingPayment = false;
                    },
                    onConfirmPayment: (result) {
                      final orderId = _currentOrder?.id;
                      if (orderId != null) {
                        _paymentStateCache.remove(orderId);
                      }
                      _isFinalizingPayment = false;
                      if (mounted) Navigator.of(context).pop();
                    },
                    onPrintAndExit: (currentState) {
                      final orderId = _currentOrder?.id;
                      if (orderId == null) return;
                      _paymentStateCache[orderId] = currentState;
                      _isFinalizingPayment = false;
                      if (mounted) Navigator.of(context).pop();
                    },
                  )
                  )
                      : _buildMenuView(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout() {
    final groupNames = ['Tất cả', ..._menuGroups.map((g) => g.name)];

    return DefaultTabController(
      length: groupNames.length,
      child: _isMenuView
          ? Scaffold(
        appBar: AppBar(
          actions: [
            if (_hasUnsentItems)
              IconButton(
                icon:
                const Icon(Icons.delete, size: 25, color: Colors.red),
                tooltip: 'Xóa tất cả sản phẩm đang chọn',
                onPressed: _confirmClearCart,
              ),
            if (_hasUnsentItems)
              IconButton(
                icon: const Icon(
                  Icons.notification_add,
                  color: AppTheme.primaryColor,
                  size: 25,
                ),
                tooltip: 'Báo chế biến',
                onPressed: () => _sendToKitchen(),
              ),
            _buildMobileCartIcon(),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(100.0),
            child: Column(
              children: [
                _buildMobileSearchBar(),
                TabBar(
                  isScrollable: true,
                  tabs:
                  groupNames.map((name) => Tab(text: name)).toList(),
                ),
              ],
            ),
          ),
        ),
        body: TabBarView(
          children: groupNames.map((groupName) {
            final products = _menuProducts.where((p) {
              bool groupMatch;
              if (groupName == 'Tất cả') {
                groupMatch = true;
              } else if (groupName == 'Khác') {
                groupMatch = (p.productGroup == null || p.productGroup!.isEmpty);
              } else {
                groupMatch = (p.productGroup == groupName);
              }
              final searchMatch = _searchQuery.isEmpty ||
                  p.productName.toLowerCase().contains(_searchQuery) ||
                  (p.productCode?.toLowerCase().contains(_searchQuery) ??
                      false) ||
                  p.additionalBarcodes.any((barcode) =>
                      barcode.toLowerCase().contains(_searchQuery));
              return groupMatch && searchMatch;
            }).toList();
            return GridView.builder(
              padding: const EdgeInsets.all(8.0),
              gridDelegate:
              const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                childAspectRatio: 0.85,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: products.length,
              itemBuilder: (context, index) =>
                  _buildProductCard(products[index], isMobile: true),
            );
          }).toList(),
        ),
      )
          : Scaffold(
        appBar: AppBar(
          title: Text(widget.table.tableName),
          actions: [
            _buildTableTransferButton(),
            _buildQuickNotesIconButton(),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner_outlined,
                  size: 30, color: AppTheme.primaryColor),
              tooltip: 'Quét mã vạch thêm món',
              onPressed: _scanBarcodeAndAddToCart,
            ),
            IconButton(
              icon: const Icon(
                Icons.add_shopping_cart,
                color: AppTheme.primaryColor,
                size: 30,
              ),
              tooltip: 'Thêm món',
              onPressed: () => setState(() => _isMenuView = true),
            )
          ],
        ),
        body: _buildCartView(),
      ),
    );
  }

  void _updateSelectedCustomer(String? customerId, Map<String, dynamic> data) {
    if (!mounted) return;

    if (customerId != null && customerId.isNotEmpty) {
      final String? cname = data['customerName'] as String?;
      final String? cphone = data['customerPhone'] as String?;

      setState(() {
        _selectedCustomer = CustomerModel(
          id: customerId,
          storeId: widget.currentUser.storeId,
          name: cname ?? 'Đang tải...',
          phone: cphone ?? '',
          points: 0,
          debt: 0.0,
          searchKeys: [],
        );
        _lastCustomerIdFromOrder = customerId;
      });

      _firestoreService.getCustomerById(customerId).then((fullCustomer) {
        if (mounted && fullCustomer != null) {
          setState(() {
            _selectedCustomer = fullCustomer;
          });
        }
      });
    } else {
      setState(() {
        _selectedCustomer = null;
        _lastCustomerIdFromOrder = null;
      });
    }
  }

  Widget _buildMobileSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 8.0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(
          color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
        ),
        decoration: InputDecoration(
          hintText: 'Tìm theo tên hoặc mã SP...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () => _searchController.clear(),
          )
              : IconButton(
            icon: const Icon(Icons.qr_code_scanner,
                color: AppTheme.primaryColor, size: 25),
            onPressed: _scanBarcode,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(30.0),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[200],
          contentPadding:
          const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildMobileCartIcon() {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.shopping_cart_outlined,
              color: AppTheme.primaryColor, size: 30),
          onPressed: () => setState(() => _isMenuView = false),
        ),
        if (_displayCart.isNotEmpty)
          Positioned(
            top: -0,
            right: 15,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(8),
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 16,
              ),
              child: Text(
                _displayCart.values
                    .fold<double>(0.0, (total, item) => total + item.quantity)
                    .toInt()
                    .toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMenuView() {
    final groupNames = ['Tất cả', ..._menuGroups.map((g) => g.name)];
    // BỎ CARD VÀ TRẢ VỀ TRỰC TIẾP COLUMN
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: TabBar(
            isScrollable: true,
            tabs: groupNames.map((name) => Tab(text: name)).toList(),
          ),
        ),
        Expanded(
          child: TabBarView(
            children: groupNames.map((groupName) {
              final displayedProducts = _menuProducts.where((p) {
                bool groupMatch;
                if (groupName == 'Tất cả') {
                  groupMatch = true;
                } else if (groupName == 'Khác') {
                  groupMatch = (p.productGroup == null || p.productGroup!.isEmpty);
                } else {
                  groupMatch = (p.productGroup == groupName);
                }
                final searchMatch = _searchQuery.isEmpty ||
                    p.productName.toLowerCase().contains(_searchQuery) ||
                    (p.productCode?.toLowerCase().contains(_searchQuery) ??
                        false);
                return groupMatch && searchMatch;
              }).toList();
              return GridView.builder(
                padding: const EdgeInsets.all(12.0),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 0.85,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: displayedProducts.length,
                itemBuilder: (context, index) => _buildProductCard(
                    displayedProducts[index],
                    isMobile: false),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildCartView() {
    final textTheme = Theme.of(context).textTheme;
    final cartEntries = _displayCart.entries.toList().reversed.toList();
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final customerMaxWidth = isDesktop
                  ? constraints.maxWidth * 0.60
                  : constraints.maxWidth * 0.73;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: customerMaxWidth,
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: CustomerSelector(
                              currentCustomer: _selectedCustomer,
                              firestoreService: _firestoreService,
                              storeId: widget.currentUser.storeId,
                              onCustomerSelected: _handleCustomerSelection,
                            ),                          ),
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                iconSize: 22,
                                icon: const Icon(Icons.remove, color: Colors.red),
                                onPressed: () =>
                                    _updateNumberOfCustomers(_numberOfCustomers - 1),
                              ),
                              Text(
                                '$_numberOfCustomers',
                                style: textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                iconSize: 22,
                                icon: const Icon(Icons.add,
                                    color: AppTheme.primaryColor),
                                onPressed: () =>
                                    _updateNumberOfCustomers(_numberOfCustomers + 1),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.table.serviceId.isNotEmpty)
                        IconButton(
                          tooltip: 'Thêm dịch vụ tính giờ',
                          icon: const Icon(
                            Icons.more_time,
                            color: AppTheme.primaryColor, size: 22,
                          ),
                          onPressed: _addDefaultServiceToCart,
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red, size: 22),
                        tooltip: 'Xóa toàn bộ đơn hàng',
                        onPressed:
                        _displayCart.isEmpty ? null : _confirmClearEntireCart,
                      ),
                    ],
                  )
                ],
              );
            },
          ),
        ),

        LayoutBuilder(
            builder: (context, constraints) {
              return Builder(
                builder: (context) {
                  // PHẢI DÙNG var ĐỂ CÓ THỂ THAY ĐỔI GIÁ TRỊ SAU
                  var guestName = _customerNameFromOrder;
                  var guestPhone = _customerPhoneFromOrder;
                  var guestAddress = _customerAddressFromOrder;
                  final guestNote = _customerNoteFromOrder; // Note vẫn giữ nguyên

                  final bool isShipOrder = widget.table.id.startsWith('ship_');
                  final bool isScheduleOrder = widget.table.id.startsWith('schedule_');
                  final bool isOnlineOrder = isShipOrder || isScheduleOrder;

                  // --- SỬA LỖI LOGIC: Chỉ giữ lại Name/Phone/Address nếu là đơn ONLINE ---
                  if (!isOnlineOrder) {
                    // Nếu là bàn thường, loại bỏ thông tin khách hàng chi tiết
                    guestName = null;
                    guestPhone = null;
                    guestAddress = null;
                  }
                  // -----------------------------------------------------------------------

                  // 1. Không hiển thị tên cho đơn online (Đã bị loại bỏ bởi logic trên)
                  final bool showName = (guestName != null && guestName.isNotEmpty);
                  final bool showPhone = (guestPhone != null && guestPhone.isNotEmpty);
                  // 2. Đổi icon cho đơn đặt lịch
                  final bool showAddressOrTime = (guestAddress != null && guestAddress.isNotEmpty);

                  // 3. Hiển thị ghi chú
                  final bool showNote = (guestNote != null && guestNote.isNotEmpty);

                  final bool hasInfo = showName || showPhone || showAddressOrTime || showNote;

                  if (hasInfo) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), // Padding 16
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        width: double.infinity, // Mở rộng hết cỡ (do padding bên ngoài)
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showName)
                              Row(
                                children: [
                                  Icon(Icons.person_outline, size: 16, color: Colors.grey.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(guestName, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold))),
                                ],
                              ),

                            if (showName && (showPhone || showAddressOrTime || showNote))
                              const SizedBox(height: 8),

                            // 4. Dùng Wrap để SĐT, Địa chỉ, Ghi chú tự xuống dòng
                            Wrap(
                              spacing: 16.0, // Khoảng cách ngang
                              runSpacing: 8.0,  // Khoảng cách dọc nếu xuống dòng
                              children: [
                                if (showPhone)
                                  Row(
                                    mainAxisSize: MainAxisSize.min, // Quan trọng
                                    children: [
                                      Icon(Icons.phone_outlined, size: 16, color: Colors.grey.shade700),
                                      const SizedBox(width: 8),
                                      Text(guestPhone, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                                    ],
                                  ),

                                if (showAddressOrTime)
                                  Builder(
                                      builder: (context) {
                                        final IconData addressIcon = isScheduleOrder ? Icons.calendar_month_outlined : Icons.location_on_outlined;
                                        return Row(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.center,
                                          children: [
                                            Icon(addressIcon, size: 16, color: Colors.grey.shade700), // Không còn lỗi Undefined
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: ConstrainedBox(
                                                constraints: BoxConstraints(maxWidth: constraints.maxWidth - 60),
                                                child: Text(guestAddress!, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                                              ),
                                            )
                                          ],
                                        );
                                      }
                                  ),
                                if (showNote)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.note_alt_outlined, size: 16, color: Colors.grey.shade700),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(maxWidth: constraints.maxWidth - 60),
                                          child: Text(
                                              guestNote,
                                              style: textTheme.bodyMedium?.copyWith(
                                                  color: Colors.red,
                                                  fontStyle: FontStyle.italic
                                              )
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              );
            }
        ),

        const Divider(height: 1, thickness: 0.5, color: Colors.grey),
        Expanded(
          child: _displayCart.isEmpty
              ? Center(
              child: Text('Chưa có món nào được chọn.',
                  style: textTheme.bodyMedium))
              : ListView.builder(
            padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 8.0),
            itemCount: cartEntries.length,
            itemBuilder: (context, index) {
              final entry = cartEntries[index];
              final cartId = entry.key;
              final item = entry.value;
              return _buildCartItemCard(cartId, item, currencyFormat);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withAlpha(12),
                    blurRadius: 10,
                    offset: const Offset(0, -5))
              ]),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tổng cộng:',
                      style: textTheme.displaySmall?.copyWith(fontSize: 18)),
                  Text(
                    currencyFormat.format(_totalAmount),
                    style: textTheme.displaySmall?.copyWith(
                        fontSize: 18,
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _hasUnsentItems ? _sendToKitchen : null,
                      child: const Text('Chế Biến'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_allowProvisionalBill) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _displayCart.isNotEmpty
                            ? _handlePrintProvisionalBill
                            : null,
                        icon: const Icon(Icons.print_outlined, size: 20),
                        label: const Text('Tạm Tính'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 12),
                      ),
                      onPressed:
                      _displayCart.isNotEmpty ? _handlePayment : null,
                      child: const Text('Thanh Toán'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        )
      ],
    );
  }

  void _handleCustomerSelection(CustomerModel? newCustomer) {
    if (_selectedCustomer?.id == newCustomer?.id) return;

    setState(() {
      _selectedCustomer = newCustomer;
    });

    if (_currentOrder != null) {
      final orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
      final dataToUpdate = {
        'customerId': _selectedCustomer?.id,
        'customerName': _selectedCustomer?.name,
        'customerPhone': _selectedCustomer?.phone,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      try {
        if (isDesktop) {
          // Desktop: Dùng Get-then-Update
          orderRef.get().then((doc) {
            if (doc.exists) {
              final currentVersion =
                  (doc.data() as Map<String, dynamic>)['version'] as int? ?? 0;
              dataToUpdate['version'] = currentVersion + 1;
              orderRef.update(dataToUpdate);
            }
          });
        } else {
          // Mobile/Web: Dùng Transaction
          _firestoreService.runTransaction((transaction) async {
            final doc = await transaction.get(orderRef);
            if (doc.exists) {
              final currentVersion =
                  (doc.data() as Map<String, dynamic>)['version'] as int? ?? 0;
              dataToUpdate['version'] = currentVersion + 1;
              transaction.update(orderRef, dataToUpdate);
            }
          });
        }
      } catch (e) {
        ToastService().show(
            message: "Lỗi cập nhật khách hàng: ${e.toString()}",
            type: ToastType.error);
      }
    }
  }

  Future<void> _addDefaultServiceToCart() async {
    final serviceId = widget.table.serviceId;
    if (serviceId.isEmpty) {
      return;
    }

    final serviceProduct = _menuProducts.firstWhereOrNull(
            (product) => product.id == serviceId
    );

    if (serviceProduct != null) {
      if (serviceProduct.serviceSetup?['isTimeBased'] == true) {
        final alreadyInCart = _displayCart.values.any((item) => item.product.id == serviceProduct.id);
        if (alreadyInCart) {
          ToastService().show(message: "Dịch vụ này đã có trong giỏ hàng.", type: ToastType.warning);
          return;
        }
      }
      await _addItemToCart(serviceProduct);
    } else {
      ToastService().show(
          message: 'Không tìm thấy dịch vụ mặc định ($serviceId) trong thực đơn.',
          type: ToastType.error
      );
    }
  }

  Widget _buildSearchBar() {
    final bool shouldAutoFocus = !_isPaymentView && !Platform.isAndroid && !Platform.isIOS;

    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: shouldAutoFocus,

      textInputAction: TextInputAction.done,
      onSubmitted: (value) => _handleBarcodeScan(value),

      decoration: InputDecoration(
        hintText: 'Quét mã hoặc tìm tên...',
        prefixIcon: const Icon(Icons.search),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.grey[100],
        contentPadding: EdgeInsets.zero,
        suffixIcon: _searchController.text.isNotEmpty
            ? IconButton(
          icon: const Icon(Icons.clear, size: 20, color: AppTheme.primaryColor),
          onPressed: () {
            _searchController.clear();
            _searchFocusNode.requestFocus(); // Focus lại khi bấm nút xóa tay
          },
        )
            : null,
      ),
    );
  }

  Future<void> _updateNumberOfCustomers(int newCount) async {
    if (newCount < 1) return;

    setState(() {
      _numberOfCustomers = newCount;
    });

    if (_currentOrder == null) return;

    try {
      final orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
      final doc = await orderRef.get();
      if (doc.exists) {
        final currentVersion =
            (doc.data() as Map<String, dynamic>)['version'] as int? ?? 0;
        await orderRef.update({
          'numberOfCustomers': newCount,
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi cập nhật số khách: $e", type: ToastType.error);
      setState(() {
        _numberOfCustomers = _currentOrder?.numberOfCustomers ?? 1;
      });
    }
  }

  Future<void> _scanBarcodeAndAddToCart() async {
    final barcodeScanRes = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );
    if (!mounted || barcodeScanRes == null) return;

    final foundProduct = _menuProducts.firstWhereOrNull((p) =>
    p.productCode == barcodeScanRes ||
        p.additionalBarcodes.contains(barcodeScanRes));

    if (foundProduct != null) {
      await _addItemToCart(foundProduct);
      setState(() {
        _isMenuView = false;
      });
    } else {
      ToastService().show(
          message: 'Không tìm thấy sản phẩm với mã vạch này.',
          type: ToastType.warning);
    }
  }

  Future<void> _confirmClearCart() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận'),
        content: const Text(
            'Bạn có chắc muốn xóa tất cả các sản phẩm đang chọn không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Hủy')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xóa', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (result != true) return;

    _revertUnsentChanges();
  }

  void _revertUnsentChanges() {
    setState(() {
      _localChanges.clear();
    });
  }

  Future<void> _confirmClearEntireCart() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận HỦY ĐƠN'),
        content: const Text('Bạn có chắc muốn xóa TOÀN BỘ đơn hàng này không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Không')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child:
              const Text('Hủy đơn', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (result != true) return;

    await _cancelOrder();

    if (mounted) {
      setState(() {
        _cart.clear();
        _localChanges.clear();
        _currentOrder = null;
        _lastFirestoreItems = [];
        _selectedCustomer = null;
        _numberOfCustomers = 1;
      });
    }
  }

  Future<void> _updateCartWithNewPrices() async {
    if (!mounted) return;

    bool hasPriceChanges = false;
    final latestProductMap = {for (var p in _menuProducts) p.id: p};

    final Map<String, OrderItem> priceUpdates = {};

    for (final entry in _displayCart.entries) {
      final cartId = entry.key;
      final oldItem = entry.value;
      final latestProduct = latestProductMap[oldItem.product.id];

      if (latestProduct != null) {
        // So sánh giá bán và tên sản phẩm
        if (oldItem.price != latestProduct.sellPrice ||
            oldItem.product.productName != latestProduct.productName) {
          hasPriceChanges = true;

          // KIẾN TRÚC MỚI: Chuẩn bị một bản cập nhật cho "Giấy Nháp" (_localChanges)
          priceUpdates[cartId] = oldItem.copyWith(
            product: latestProduct,
            price: latestProduct.sellPrice,
          );
        }
      }
    }

    if (hasPriceChanges) {
      setState(() {
        _localChanges.addAll(priceUpdates);
      });

      ToastService().show(
          message: "Giá một số sản phẩm trong giỏ đã được tự động cập nhật.",
          type: ToastType.warning);
      await _saveOrder();
    }
  }

  Future<void> _handleRemoveOrCancelItem(String cartId) async {
    final item = _displayCart[cartId];
    if (item == null) return;

    final bool isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;
    final bool wasSaved = _cart.containsKey(cartId);

    if (!wasSaved) {
      setState(() {
        _localChanges.remove(cartId);
      });
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận Hủy'),
        content: Text('Bạn có chắc muốn hủy "${item.product.productName}" không?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Không')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Xác Nhận Hủy', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    // --- LOGIC ĐÃ SỬA ---

    // 1. Kiểm tra xem có cần in hủy hay không TRƯỚC KHI LƯU
    final bool needsCancelPrint = item.sentQuantity > 0 && !isTimeBased;
    Map<String, dynamic>? cancelPayload; // Lưu payload tạm thời

    try {
      OrderItem itemToCancel = item;
      if (isTimeBased) {
        final result = TimeBasedPricingService.calculatePriceWithBreakdown(
            product: item.product,
            startTime: item.addedAt,
            isPaused: item.isPaused,
            pausedAt: item.pausedAt,
            totalPausedDurationInSeconds: item.totalPausedDurationInSeconds);
        itemToCancel = item.copyWith(price: result.totalPrice);
      }

      // 2. Chuẩn bị payload TRƯỚC KHI LƯU, vì _currentOrder có thể bị null SAU KHI LƯU
      // (Chúng ta biết _currentOrder không null ở đây vì wasSaved == true)
      if (needsCancelPrint && _currentOrder != null) {
        final itemPrintMap = itemToCancel.toMap();

        // Gửi đi SỐ LƯỢNG ĐÃ BÁO BẾP
        itemPrintMap['quantity'] = item.sentQuantity;

        cancelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': [itemPrintMap],
        };
      }

      // 3. Cập nhật trạng thái local và LƯU VÀO DATABASE
      setState(() {
        _localChanges[cartId] = itemToCancel.copyWith(
          quantity: 0,
          status: 'cancelled',
        );
      });

      final success = await _saveOrder(); // Hàm này CÓ THỂ set _currentOrder = null

      // 4. Kiểm tra kết quả lưu VÀ payload đã chuẩn bị
      if (success && cancelPayload != null) {
        // Chỉ khi lưu thành công VÀ có payload, chúng ta mới gửi lệnh in
        PrintQueueService().addJob(PrintJobType.cancel, cancelPayload);
        ToastService().show(message: "Đã gửi lệnh hủy món.", type: ToastType.success);
      }

    } catch (e) {
      debugPrint("Lỗi khi hủy món: $e");
      ToastService().show(message: "Lỗi khi hủy món: ${e.toString()}", type: ToastType.error);
    }
  }

  Future<bool> _saveOrder() async {
    final bool useMergeStrategy =
        kIsWeb || !Platform.isIOS && !Platform.isAndroid;
    if (useMergeStrategy) {
      return await _saveOrderWithMerge();
    } else {
      return await _saveOrderWithTransaction();
    }
  }

  Future<bool> _saveOrderWithMerge() async {
    if (_currentOrder != null &&
        ['paid', 'cancelled'].contains(_currentOrder!.status)) {
      return true;
    }
    final localChanges = Map<String, OrderItem>.from(_localChanges);
    if (localChanges.isEmpty) return true;

    Map<String, OrderItem> finalCart = {};

    try {
      final DocumentReference orderRef;
      if (_currentOrder != null) {
        orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
      } else {
        orderRef = _firestoreService.getOrderReference(widget.table.id);
      }

      final serverSnapshot = await orderRef.get();

      ({List<Map<String, dynamic>> items, double total}) groupAndCalculate(
          Map<String, OrderItem> itemsToProcess) {
        final Map<String, OrderItem> grouped = {};
        for (final item in itemsToProcess.values) {
          if (item.quantity <= 0) continue;
          final key = item.groupKey;
          if (grouped.containsKey(key)) {
            final existing = grouped[key]!;
            grouped[key] = existing.copyWith(
              quantity: existing.quantity + item.quantity,
              sentQuantity: existing.sentQuantity + item.sentQuantity,
              addedAt: (existing.addedAt.seconds < item.addedAt.seconds)
                  ? existing.addedAt
                  : item.addedAt,
            );
          } else {
            grouped[key] = item;
          }
        }
        final totalAmount =
        grouped.values.fold(0.0, (tong, item) => tong + item.subtotal);
        final itemsToSave = grouped.values.map((e) => e.toMap()).toList();
        finalCart = { for (var item in grouped.values) item.lineId: item};
        return (items: itemsToSave, total: totalAmount);
      }

      if (!serverSnapshot.exists || ['paid', 'cancelled'].contains(
          (serverSnapshot.data() as Map<String, dynamic>?)?['status'])) {
        final result = groupAndCalculate(localChanges);
        if (result.items.isEmpty) return true;

        final currentVersion = ((serverSnapshot.data() as Map<String,
            dynamic>?)?['version'] as num?)?.toInt() ?? 0;
        final newOrderData = {
          'id': orderRef.id,
          'tableId': widget.table.id,
          'tableName': widget.table.tableName,
          'status': 'active',
          'startTime': Timestamp.now(),
          'items': result.items,
          'totalAmount': result.total,
          'storeId': widget.currentUser.storeId,
          'createdAt': FieldValue.serverTimestamp(),
          'createdByUid': widget.currentUser.uid,
          'createdByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
          'customerId': _selectedCustomer?.id,
          'customerName': _selectedCustomer?.name,
          'customerPhone': _selectedCustomer?.phone,
          'guestAddress': _customerAddressFromOrder,
          'numberOfCustomers': _numberOfCustomers,
          'version': currentVersion + 1,
        };
        await orderRef.set(newOrderData);
        _currentOrder = OrderModel.fromMap(newOrderData);
      } else {
        final serverData = serverSnapshot.data() as Map<String, dynamic>;
        final currentVersion = (serverData['version'] as num?)?.toInt() ?? 0;

        final serverItemsMap = {
          for (var item in (serverData['items'] as List<dynamic>? ?? [])
              .map((e) => OrderItem.fromMap(e, allProducts: _menuProducts)))
            item.lineId: item
        };

        final mergedItems = Map<String, OrderItem>.from(serverItemsMap);
        mergedItems.addAll(localChanges);

        final result = groupAndCalculate(mergedItems);

        if (result.items.isEmpty) {
          await _firestoreService.updateOrder(orderRef.id, {
            'status': 'cancelled',
            'items': [],
            'totalAmount': 0.0,
            'updatedAt': FieldValue.serverTimestamp(),
            'numberOfCustomers': _numberOfCustomers,
            'version': currentVersion + 1,
          });
          _currentOrder = null;
          finalCart.clear();
        } else {
          final updatedOrderData = {
            'items': result.items,
            'totalAmount': result.total,
            'updatedAt': FieldValue.serverTimestamp(),
            'customerId': _selectedCustomer?.id,
            'customerName': _selectedCustomer?.name,
            'customerPhone': _selectedCustomer?.phone,
            'guestAddress': _customerAddressFromOrder,
            'numberOfCustomers': _numberOfCustomers,
            'version': currentVersion + 1,
          };
          await _firestoreService.updateOrder(orderRef.id, updatedOrderData);
        }
      }

      if (mounted) {
        setState(() {
          _localChanges.clear();
          _cart.clear();
          _cart.addAll(finalCart);
        });
      }
      return true;
    } catch (e) {
      debugPrint("==== SAVE ORDER FAILED ====");
      debugPrint("Error Type: ${e.runtimeType}");
      debugPrint("Error Message: ${e.toString()}");
      debugPrint("=========================");

      final errorMessage = e.toString().toLowerCase();
      if (e is FirebaseException && e.code == 'permission-denied' ||
          errorMessage.contains('permission denied') ||
          errorMessage.contains('permission_denied')) {
        _handleConcurrencyError();
      } else {
        ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
      }
      return false;
    }
  }

  Future<bool> _saveOrderWithTransaction() async {
    if (_currentOrder != null &&
        ['paid', 'cancelled'].contains(_currentOrder!.status)) {
      return true;
    }
    if (_localChanges.isEmpty) return true;

    Map<String, OrderItem> finalCartAfterSave = {};

    try {
      final DocumentReference orderRef;
      if (_currentOrder != null) {
        orderRef = _firestoreService.getOrderReference(_currentOrder!.id);
      } else {
        orderRef = _firestoreService.getOrderReference(widget.table.id);
      }

      await _firestoreService.runTransaction((transaction) async {
        final serverSnapshot = await transaction.get(orderRef);
        final serverData = serverSnapshot.data() as Map<String, dynamic>?;
        final serverStatus = serverData?['status'];

        if (!serverSnapshot.exists ||
            ['paid', 'cancelled'].contains(serverStatus)) {
          Map<String, OrderItem> finalCart = Map<String, OrderItem>.from(_localChanges);
          finalCart.removeWhere((key, item) => item.quantity <= 0);
          if (finalCart.isEmpty) {
            finalCartAfterSave = {};
            return;
          }

          final currentVersion = (serverData?['version'] as num?)?.toInt() ?? 0;
          final itemsToSave =
          finalCart.values.map((item) => item.toMap()).toList();
          final finalTotalAmount = finalCart.values
              .fold(0.0, (total, item) => total + item.subtotal);

          final newOrderData = {
            'id': orderRef.id,
            'tableId': widget.table.id,
            'tableName': widget.table.tableName,
            'status': 'active',
            'startTime': Timestamp.now(),
            'items': itemsToSave,
            'totalAmount': finalTotalAmount,
            'storeId': widget.currentUser.storeId,
            'createdAt': FieldValue.serverTimestamp(),
            'createdByUid': widget.currentUser.uid,
            'createdByName':
            widget.currentUser.name ?? widget.currentUser.phoneNumber,
            'customerId': _selectedCustomer?.id,
            'customerName': _selectedCustomer?.name,
            'customerPhone': _selectedCustomer?.phone,
            'guestAddress': _customerAddressFromOrder,
            'version': currentVersion + 1,
            'numberOfCustomers': _numberOfCustomers,
          };
          transaction.set(orderRef, newOrderData);
          _currentOrder = OrderModel.fromMap(newOrderData);
          finalCartAfterSave = finalCart;
        } else {
          if (serverStatus != 'active') {
            throw Exception("Đơn hàng này đã đóng.");
          }
          final currentVersion = (serverData!['version'] as num?)?.toInt() ?? 0;
          final serverItems = (serverData['items'] as List<dynamic>? ?? [])
              .map((e) => OrderItem.fromMap(e, allProducts: _menuProducts));
          final serverItemsMap = {
            for (var item in serverItems) item.lineId: item
          };

          final mergedItems = Map<String, OrderItem>.from(serverItemsMap);
          mergedItems.addAll(_localChanges);

          final Map<String, OrderItem> mergedByGroupKey = {};
          for (final item in mergedItems.values) {
            final String key = item.groupKey;
            final existingItem = mergedByGroupKey[key];

            if (existingItem != null) {
              final updatedItem = existingItem.copyWith(
                quantity: existingItem.quantity + item.quantity,
                sentQuantity: existingItem.sentQuantity + item.sentQuantity,
                addedAt: (existingItem.addedAt.seconds < item.addedAt.seconds)
                    ? existingItem.addedAt
                    : item.addedAt,
              );
              mergedByGroupKey[key] = updatedItem;
            } else {
              mergedByGroupKey[key] = item;
            }
          }

          if (mergedByGroupKey.values.every((item) => item.quantity <= 0)) {
            transaction.update(orderRef, {
              'status': 'cancelled',
              'items': mergedByGroupKey.values.map((item) => item.toMap()).toList(),
              'totalAmount': 0.0,
              'updatedAt': FieldValue.serverTimestamp(),
              'version': currentVersion + 1,
            });
            finalCartAfterSave = {};
          } else {
            final itemsToSave =
            mergedByGroupKey.values.map((item) => item.toMap()).toList();

            final finalTotalAmount = mergedByGroupKey.values
                .fold(0.0, (total, item) => total + item.subtotal);

            final updatedOrderData = {
              'items': itemsToSave,
              'totalAmount': finalTotalAmount,
              'updatedAt': FieldValue.serverTimestamp(),
              'customerId': _selectedCustomer?.id,
              'customerName': _selectedCustomer?.name,
              'customerPhone': _selectedCustomer?.phone,
              'guestAddress': _customerAddressFromOrder,
              'version': currentVersion + 1,
              'numberOfCustomers': _numberOfCustomers,
            };
            transaction.update(orderRef, updatedOrderData);
            finalCartAfterSave = { for (var item in mergedByGroupKey.values) item.lineId: item };
          }
        }
      });

      if (mounted) {
        setState(() {
          if (finalCartAfterSave.isEmpty) {
            _currentOrder = null;
          }
          _localChanges.clear();
          _cart.clear();
          _cart.addAll(finalCartAfterSave);
        });
      }
      return true;
    } catch (e) {
      if (e is FirebaseException && e.code == 'permission-denied' ||
          e.toString().toUpperCase().contains('PERMISSION_DENIED')) {
        _handleConcurrencyError();
      } else {
        ToastService().show(message: "Lưu thất bại: $e", type: ToastType.error);
      }
      return false;
    }
  }

  void _handleConcurrencyError() {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('⚠️ Bàn vừa được cập nhật'),
          content: const Text(
              'Một thiết bị khác vừa lưu thay đổi. Vui lòng kiểm tra lại đơn hàng và bấm "Chế Biến" hoặc "Thanh Toán" lại một lần nữa.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Không cần setState. StreamBuilder sẽ tự động làm mới giao diện
                // với dữ liệu mới nhất từ server, trong khi _localChanges vẫn giữ
                // món ăn mà người dùng vừa thêm.
              },
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _cancelOrderWithTransaction() async {
    final OrderModel? orderToCancel = _currentOrder;
    if (orderToCancel == null) {
      ToastService()
          .show(message: "Đã xóa các món đang chọn.", type: ToastType.success);
      return;
    }
    try {
      final itemsSentToKitchen =
      _cart.values.where((item) => item.sentQuantity > 0).toList();
      if (itemsSentToKitchen.isNotEmpty) {
        final itemsToCancelPayload = itemsSentToKitchen.map((item) {
          final printItemMap = item.toMap();
          printItemMap['quantity'] = item.sentQuantity;
          return printItemMap;
        }).toList();
        final printData = {
          'storeId': widget.currentUser.storeId,
          'tableName': orderToCancel.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': itemsToCancelPayload,
        };
        PrintQueueService().addJob(PrintJobType.cancel, printData);
      }

      final orderRef = _firestoreService.getOrderReference(orderToCancel.id);
      await _firestoreService.runTransaction((transaction) async {
        final serverSnapshot = await transaction.get(orderRef);
        if (!serverSnapshot.exists) {
          return;
        }
        final serverData = serverSnapshot.data() as Map<String, dynamic>;
        final currentVersion = (serverData['version'] as num?)?.toInt() ?? 0;
        transaction.update(orderRef, {
          'status': 'cancelled',
          'version': currentVersion + 1,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
      await _firestoreService.unlinkMergedTables(orderToCancel.tableId);
      ToastService().show(
          message: "Đã hủy đơn hàng thành công.", type: ToastType.success);
    } catch (e, stackTrace) {
      debugPrint('Lỗi khi hủy đơn (Transaction): $e');
      debugPrint(stackTrace.toString());
      ToastService().show(
          message: "Lỗi khi hủy đơn: ${e.toString()}", type: ToastType.error);
    }
  }

  Future<void> _cancelOrderWithMerge() async {
    final OrderModel? orderToCancel = _currentOrder;
    if (orderToCancel == null) {
      ToastService()
          .show(message: "Đã xóa các món đang chọn.", type: ToastType.success);
      return;
    }
    try {
      final itemsSentToKitchen =
      _cart.values.where((item) => item.sentQuantity > 0).toList();
      if (itemsSentToKitchen.isNotEmpty) {

        final itemsToCancelPayload = itemsSentToKitchen.map((item) {
          final printItemMap = item.toMap();
          printItemMap['quantity'] = item.sentQuantity;
          return printItemMap;
        }).toList();
        final printData = {
          'storeId': widget.currentUser.storeId,
          'tableName': orderToCancel.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': itemsToCancelPayload,
        };
        PrintQueueService().addJob(PrintJobType.cancel, printData);
      }

      final orderRef = _firestoreService.getOrderReference(orderToCancel.id);
      final serverSnapshot = await orderRef.get();

      if (!serverSnapshot.exists) {
        ToastService().show(
            message: "Đơn hàng không tồn tại để hủy.", type: ToastType.warning);
        return;
      }

      final serverData = serverSnapshot.data() as Map<String, dynamic>;
      final currentVersion = (serverData['version'] as num?)?.toInt() ?? 0;

      await orderRef.update({
        'status': 'cancelled',
        'version': currentVersion + 1,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _firestoreService.unlinkMergedTables(orderToCancel.tableId);
      ToastService().show(
          message: "Đã hủy đơn hàng thành công.", type: ToastType.success);
    } catch (e, stackTrace) {
      debugPrint('Lỗi khi hủy đơn (Merge): $e');
      debugPrint(stackTrace.toString());
      ToastService().show(
          message: "Lỗi khi hủy đơn: ${e.toString()}", type: ToastType.error);
    }
  }

  Future<void> _cancelOrder() async {
    if (isDesktop) {
      await _cancelOrderWithMerge();
    } else {
      await _cancelOrderWithTransaction();
    }
  }

  Future<bool?> _showExitConfirmationDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận thoát'),
        content: const Text(
            'Trong đơn hàng có sản phẩm CHƯA BÁO CHẾ BIẾN. Nếu thoát, các món này sẽ bị xóa khỏi đơn hàng!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Thoát', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Xem lại'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearProductFromCart(String productId) async {
    setState(() {
      _localChanges.removeWhere((key, item) => item.product.id == productId);

      final Map<String, OrderItem> revertedItemsInCart = {};
      for (final entry in _cart.entries) {
        if (entry.value.product.id == productId) {
          final revertedItem =
          entry.value.copyWith(quantity: entry.value.sentQuantity);
          if (revertedItem.quantity > 0) {
            revertedItemsInCart[entry.key] = revertedItem;
          }
        } else {
          revertedItemsInCart[entry.key] = entry.value;
        }
      }
      _cart.clear();
      _cart.addAll(revertedItemsInCart);
    });
  }

  Widget _buildProductCard(ProductModel product, {bool isMobile = false}) {
    const stockManagedTypes = {'Hàng hóa'};
    final bool showStock = stockManagedTypes.contains(product.productType);

    final cartItemsForProduct = _displayCart.values
        .where((item) => item.product.id == product.id)
        .toList();
    final quantityInCart = cartItemsForProduct.fold<double>(
        0.0, (total, item) => total + item.quantity);
    final sentQuantity = cartItemsForProduct.fold<double>(
        0.0, (total, item) => total + item.sentQuantity);

    return GestureDetector(
      onTap: () => _addItemToCart(product),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Text(
                    product.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                Expanded(
                  child: (product.imageUrl != null &&
                      product.imageUrl!.isNotEmpty)
                      ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12.0),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl!,
                      fit: BoxFit.contain,
                      placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2.0)),
                      errorWidget: (context, url, error) => const Icon(
                          Icons.image_not_supported,
                          color: Colors.grey),
                    ),
                  )
                      : const Icon(Icons.fastfood,
                      size: 50, color: Colors.grey),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showStock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            NumberFormat('#,##0.##').format(product.stock),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${formatNumber(product.sellPrice)} đ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryColor,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (quantityInCart > 0)
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  formatNumber(quantityInCart),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (isMobile && quantityInCart > sentQuantity)
            Positioned(
              top: -2,
              left: -2,
              child: GestureDetector(
                onTap: () => _clearProductFromCart(product.id),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 17,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCartItemCard(
      String cartId, OrderItem item, NumberFormat currencyFormat) {
    final bool isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;

    return isTimeBased
        ? _buildTimeBasedItemCard(cartId, item, currencyFormat)
        : _buildNormalItemCard(cartId, item, currencyFormat);
  }

  Widget _buildNormalItemCard(
      String cartId, OrderItem item, NumberFormat currencyFormat) {
    final textTheme = Theme.of(context).textTheme;
    final change = item.unsentChange;
    final bool isCancelled = item.quantity == 0 && item.sentQuantity > 0;

    String discountText = '';
    if (item.discountValue != null && item.discountValue! > 0) {
      if (item.discountUnit == '%') {
        discountText = "(-${formatNumber(item.discountValue!)}%)";
      } else {
        discountText = "(-${formatNumber(item.discountValue!)}đ)";
      }
    }

    final double basePriceForUnit = _getBasePriceForUnit(item.product, item.selectedUnit);
    final bool priceHasChanged = (item.price - basePriceForUnit).abs() > 0.01;

    return Card(
      child: InkWell(
        onTap: () => _showEditItemDialog(cartId, item),
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    item.sentQuantity > 0
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_on_outlined,
                    color: item.sentQuantity > 0
                        ? (item.hasUnsentChanges
                        ? Colors.orange.shade700
                        : AppTheme.primaryColor)
                        : Colors.grey,
                    size: 20,
                  ),
                  if (item.hasUnsentChanges && !isCancelled) ...[
                    const SizedBox(width: 4),
                    Text(
                      change > 0
                          ? "+${formatNumber(change)}"
                          : formatNumber(change),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '${item.product.productName} ',
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color:
                            isCancelled ? Colors.grey : AppTheme.textColor,
                            decoration: isCancelled
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: Colors.grey,
                            decorationThickness: 2.0,
                          ),
                        ),
                        if (item.selectedUnit.isNotEmpty)
                          TextSpan(
                            text: '(${item.selectedUnit}) ',
                            style: textTheme.bodyMedium?.copyWith(
                              color: isCancelled
                                  ? Colors.grey
                                  : Colors.grey.shade700,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: Colors.grey,
                              decorationThickness: 2.0,
                            ),
                          ),
                        if (priceHasChanged && !isCancelled)
                          TextSpan(
                            text: currencyFormat.format(basePriceForUnit),
                            style: textTheme.bodyMedium?.copyWith(
                              color: Colors.red,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.red,
                            ),
                          ),
                        if (discountText.isNotEmpty)
                          TextSpan(
                            text: ' $discountText',
                            style: textTheme.bodyMedium?.copyWith(
                                color: Colors.red,
                            ),
                          ),
                      ]),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    splashRadius: 20,
                    icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                    onPressed: () => _handleRemoveOrCancelItem(cartId),
                  ),
                ],
              ),

              if (item.toppings.isNotEmpty || (item.note != null && item.note!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.toppings.isNotEmpty)
                        _buildToppingsList(item.toppings, currencyFormat),
                      if (item.note != null && item.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            '${item.note}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.red,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    child: Row(
                      children: [
                        Text(
                          currencyFormat.format(item.price),
                          style: textTheme.bodyMedium?.copyWith(
                            color: isCancelled ? Colors.grey : (priceHasChanged ? Colors.orange.shade700 : null),
                            fontWeight: priceHasChanged ? FontWeight.bold : null,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    decoration: BoxDecoration(
                      color:
                      isCancelled ? Colors.transparent : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: Icon(Icons.remove,
                              size: 18, color: Colors.red.shade400),
                          onPressed: () => _updateQuantity(cartId, -1),
                        ),

                        InkWell(
                          onTap: () => _showEditItemDialog(cartId, item),
                          child: Container(
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12.0),
                                border: Border.all(color: Colors.grey.shade300, width: 0.5)
                            ),
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              maxWidth: 65,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 1.0),
                            child: Text(
                              formatNumber(item.quantity),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isCancelled ? Colors.grey : null,
                                decoration: isCancelled
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
                                decorationColor: Colors.grey,
                                decorationThickness: 2.0,
                              ),
                            ),
                          ),
                        ),

                        IconButton(
                          visualDensity: VisualDensity.compact,
                          splashRadius: 18,
                          icon: const Icon(Icons.add,
                              size: 18, color: AppTheme.primaryColor),
                          onPressed: () => _updateQuantity(cartId, 1),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 120,
                    child: Text(
                      currencyFormat.format(item.subtotal),
                      textAlign: TextAlign.right,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isCancelled ? Colors.grey : null,
                        decoration: isCancelled
                            ? TextDecoration.lineThrough
                            : TextDecoration.none,
                        decorationColor: Colors.grey,
                        decorationThickness: 2.0,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToppingsList(
      Map<ProductModel, double> toppings, NumberFormat currencyFormat) {
    if (toppings.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2.0),
      child: Wrap(
        spacing: 16.0,
        runSpacing: 4.0,
        children: toppings.entries.map((entry) {
          final topping = entry.key;
          final quantity = entry.value;
          return Text(
            '+ ${topping.productName} (${currencyFormat.format(topping.sellPrice)} x ${NumberFormat('#,##0.##').format(quantity)})',
            style: Theme.of(context).textTheme.bodyMedium,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTimeBasedItemCard(
      String cartId, OrderItem item, NumberFormat currencyFormat) {
    final textTheme = Theme.of(context).textTheme;
    final timeFormat = DateFormat('HH:mm dd/MM');

    final result = _timeBasedDataCache[item.lineId] ??
        TimeBasedPricingService.calculatePriceWithBreakdown(
          product: item.product,
          startTime: item.addedAt,
          isPaused: item.isPaused,
          pausedAt: item.pausedAt,
          totalPausedDurationInSeconds: item.totalPausedDurationInSeconds,
        );

    final startTime = item.addedAt.toDate();
    final billableEndTime =
    startTime.add(Duration(minutes: result.totalMinutesBilled));

    String formatMinutes(int totalMinutes) {
      if (totalMinutes <= 0) return "0'";
      final hours = totalMinutes ~/ 60;
      final minutes = totalMinutes % 60;
      if (hours > 0) {
        return "${hours}h${minutes.toString().padLeft(2, '0')}'";
      }
      return "$minutes'";
    }

    String discountText = '';
    if (item.discountValue != null && item.discountValue! > 0) {
      if (item.discountUnit == '%') {
        discountText = "(-${formatNumber(item.discountValue!)}%)";
      } else {
        discountText = "(-${formatNumber(item.discountValue!)}đ)";
      }
    }

    return Card(
        child: InkWell(
          onTap: () => _showEditItemDialog(cartId, item),
          borderRadius: BorderRadius.circular(12.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  // ... (Row icon pause/play và tên món) ...
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                      icon: Icon(
                        item.isPaused
                            ? Icons.play_circle_filled
                            : Icons.pause_circle_filled,
                        color: item.isPaused
                            ? Colors.orange.shade700
                            : AppTheme.primaryColor,
                        size: 24,
                      ),
                      onPressed: () => _togglePauseTimeBasedItem(cartId),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text.rich( // Đổi thành Text.rich
                        TextSpan(children: [
                          TextSpan(
                            text: item.product.productName,
                            style: textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.textColor),
                          ),
                          // --- HIỂN THỊ CHIẾT KHẤU ---
                          if (discountText.isNotEmpty)
                            TextSpan(
                              text: ' $discountText',
                              style: textTheme.bodyMedium?.copyWith(
                                  color: Colors.red.shade700,
                                  fontStyle: FontStyle.italic
                              ),
                            ),
                        ]),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      splashRadius: 20,
                      icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                      onPressed: () => _handleRemoveOrCancelItem(cartId),
                    ),
                  ],
                ),

                if (item.note != null && item.note!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12, top: 2, bottom: 4),
                      child: Text(
                        'Ghi chú: ${item.note}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.red.shade700,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ),

            if (result.blocks.isNotEmpty) ...[
              ...result.blocks.map((block) {
                final isLastBlock = block == result.blocks.last;
                final blockEndTimeToShow =
                isLastBlock ? billableEndTime : block.endTime;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2.0),
                  child: isDesktop
                      ? Row(
                    // Bố cục cho Desktop (giữ nguyên từ code của bạn)
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(
                        isLastBlock
                            ? Icons.timer_outlined
                            : Icons.access_time,
                        color: isLastBlock
                            ? AppTheme.primaryColor
                            : Colors.grey.shade600,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 4,
                        child: Text.rich(
                          TextSpan(
                            style: textTheme.bodyMedium,
                            children: [
                              TextSpan(
                                  text:
                                  '${timeFormat.format(block.startTime)} -> '),
                              TextSpan(
                                  text: timeFormat
                                      .format(blockEndTimeToShow)),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: Text(
                            "${formatMinutes(block.minutes)} x ${formatNumber(block.ratePerHour)}đ/h",
                            style: textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(
                          currencyFormat.format(block.cost),
                          textAlign: TextAlign.end,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  )
                  // --- SỬA ĐỔI: Bố cục 2 dòng cho Mobile ---
                      : Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        isLastBlock
                            ? Icons.timer_outlined
                            : Icons.access_time,
                        color: isLastBlock
                            ? AppTheme.primaryColor
                            : Colors.grey.shade600,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Dòng 1: Khoảng thời gian
                            Text.rich(
                              TextSpan(
                                style: textTheme.bodyMedium,
                                children: [
                                  TextSpan(
                                      text:
                                      '${timeFormat.format(block.startTime)} -> '),
                                  TextSpan(
                                      text: timeFormat
                                          .format(blockEndTimeToShow)),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Dòng 2: Thời gian x Đơn giá
                            Text(
                              "${formatMinutes(block.minutes)} x ${formatNumber(block.ratePerHour)} đ/h",
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Thành tiền của block (không bold)
                      Text(
                        currencyFormat.format(block.cost),
                        style: textTheme.bodyMedium,
                      ),
                    ],
                  ),
                );
              }),
              const Divider(
                height: 8,
                thickness: 0.5,
                color: Colors.grey,
              ),
              // Thêm Divider ở đây
            ],

            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const SizedBox(width: 8),
                  Text.rich(
                    TextSpan(
                      style: textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: timeFormat.format(startTime),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.red),
                        ),
                        const TextSpan(
                          text: ' - ',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, color: Colors.grey),
                        ),
                        TextSpan(
                          text: timeFormat.format(billableEndTime),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    // SỬA LẠI: Dùng item.subtotal
                    currencyFormat.format(item.subtotal),
                    style: textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
              ],
            ),
          ),
        ),
    );
  }

  Future<void> _fetchStaff() async {
    if (_isLoadingStaff) return;
    setState(() => _isLoadingStaff = true);
    try {
      _staffList = await _firestoreService.getUsersByStore(widget.currentUser.storeId);
    } catch (e) {
      debugPrint("Lỗi tải danh sách nhân viên: $e");
      ToastService().show(message: "Lỗi tải danh sách nhân viên.", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingStaff = false);
      }
    }
  }

  Future<void> _showEditItemDialog(String cartId, OrderItem item) async {
    final relevantNotes = _quickNotes.where((note) {
      return note.productIds.isEmpty || note.productIds.contains(item.product.id);
    }).toList();

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => EditOrderItemDialog(
        initialItem: item,
        staffList: _staffList,
        isLoadingStaff: _isLoadingStaff,
        relevantQuickNotes: relevantNotes,
      ),
    );

    if (result == null) return;

    setState(() {
      final newNote = (result['note'] as String?).nullIfEmpty;
      final newCommissionStaff = result['commissionStaff'] as Map<String, String?>;

      final double newQuantity = result['quantity'] as double;

      if (newQuantity < item.sentQuantity) {
        ToastService().show(
            message: "Không thể đặt SL (${formatNumber(newQuantity)}) ít hơn số đã báo chế biến (${formatNumber(item.sentQuantity)}).",
            type: ToastType.warning,
            duration: const Duration(seconds: 3)
        );
        return;
      }

      _localChanges[cartId] = item.copyWith(
        price: result['price'] as double,
        quantity: newQuantity,
        discountValue: result['discountValue'] as double,
        discountUnit: result['discountUnit'] as String,
        note: () => newNote,
        commissionStaff: () => newCommissionStaff.isNotEmpty ? newCommissionStaff : null,
      );
    });
  }

  double _getBasePriceForUnit(ProductModel product, String selectedUnit) {
    if ((product.unit ?? '') == selectedUnit) {
      return product.sellPrice;
    }

    final additionalUnitData = product.additionalUnits.firstWhereOrNull(
            (unitData) => (unitData['unitName'] as String?) == selectedUnit
    );

    if (additionalUnitData != null) {
      return (additionalUnitData['sellPrice'] as num?)?.toDouble() ?? product.sellPrice;
    }

    return product.sellPrice;
  }
}

class _ProductOptionsDialog extends StatefulWidget {
  final ProductModel product;
  final List<ProductModel> allProducts;
  final List<QuickNoteModel> relevantQuickNotes;

  const _ProductOptionsDialog({
    required this.product,
    required this.allProducts,
    required this.relevantQuickNotes,
  });

  @override
  State<_ProductOptionsDialog> createState() => _ProductOptionsDialogState();
}

class _ProductOptionsDialogState extends State<_ProductOptionsDialog> {
  late String _selectedUnit;
  late Map<String, dynamic> _baseUnitData;
  late List<Map<String, dynamic>> _allUnitOptions;
  List<ProductModel> _accompanyingProducts = [];
  final Map<String, double> _selectedToppings = {};
  final List<QuickNoteModel> _selectedQuickNotes = []; // THÊM DÒNG NÀY

  @override
  void initState() {
    super.initState();
    _baseUnitData = {
      'unitName': widget.product.unit ?? '',
      'sellPrice': widget.product.sellPrice
    };
    _allUnitOptions = [_baseUnitData, ...widget.product.additionalUnits];
    _selectedUnit = _baseUnitData['unitName'] as String;

    final productMap = {for (var p in widget.allProducts) p.id: p};
    _accompanyingProducts = widget.product.accompanyingItems
        .map((item) => productMap[item['productId']])
        .where((p) => p != null)
        .cast<ProductModel>()
        .toList();
  }

  void _onConfirm() {
    final selectedUnitData =
    _allUnitOptions.firstWhere((u) => u['unitName'] == _selectedUnit);
    final priceForSelectedUnit =
    (selectedUnitData['sellPrice'] as num).toDouble();

    final Map<ProductModel, double> toppingsMap = {};
    _selectedToppings.forEach((productId, quantity) {
      if (quantity > 0) {
        final product =
        _accompanyingProducts.firstWhere((p) => p.id == productId);
        toppingsMap[product] = quantity;
      }
    });

    // Gộp ghi chú nhanh thành một chuỗi
    final String noteText = _selectedQuickNotes.map((n) => n.noteText).join(', ');

    Navigator.of(context).pop({
      'selectedUnit': _selectedUnit,
      'price': priceForSelectedUnit,
      'selectedToppings': toppingsMap,
      'selectedNote': noteText, // TRẢ VỀ GHI CHÚ
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

  Future<void> _showToppingQuantityInput(ProductModel topping) async {
    final controller = TextEditingController(
        text: (NumberFormat('#,##0.##').format(_selectedToppings[topping.id] ?? 0)));
    final navigator = Navigator.of(context);

    final newQuantity = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Nhập SL cho ${topping.productName}'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          inputFormatters: [ThousandDecimalInputFormatter()],
          decoration: const InputDecoration(labelText: 'Số lượng'),
        ),
        actions: [
          TextButton(
              onPressed: () => navigator.pop(), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () => navigator.pop(parseVN(controller.text)),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (newQuantity != null) {
      setState(() {
        _selectedToppings[topping.id] = newQuantity < 0 ? 0 : newQuantity;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnits = widget.product.additionalUnits.isNotEmpty;
    final hasToppings = _accompanyingProducts.isNotEmpty;
    final hasNotes = widget.relevantQuickNotes.isNotEmpty;

    return AlertDialog(
      title: Text(widget.product.productName, textAlign: TextAlign.center),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasUnits) ...[
                const Text('Chọn đơn vị tính:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SegmentedButton<String>(
                  segments: _allUnitOptions.map((unitData) {
                    final unitName = unitData['unitName'] as String;
                    return ButtonSegment<String>(
                      value: unitName,
                      label: Text(unitName),
                    );
                  }).toList(),
                  selected: {_selectedUnit},
                  onSelectionChanged: (newSelection) {
                    setState(() {
                      _selectedUnit = newSelection.first;
                    });
                  },
                  multiSelectionEnabled: false,
                  emptySelectionAllowed: false,
                  style: ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    padding: WidgetStateProperty.all(
                        const EdgeInsets.symmetric(horizontal: 12)),
                  ),
                ),
                Divider(
                  height: 24,
                  thickness: 0.8,
                  color: Colors.grey.shade200,
                ),
              ],
              if (hasToppings) ...[
                const Text('Chọn Topping/Bán kèm:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _accompanyingProducts.map((topping) {
                    final quantity = _selectedToppings[topping.id] ?? 0;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  topping.productName,
                                  style: const TextStyle(
                                      color: AppTheme.textColor),
                                ),
                                Text(
                                  '+${NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(topping.sellPrice)}',
                                  style: const TextStyle(
                                      color: AppTheme.textColor),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: Icon(Icons.remove,
                                      size: 18, color: Colors.red.shade400),
                                  onPressed: () =>
                                      _updateToppingQuantity(topping.id, -1),
                                  splashRadius: 18,
                                ),
                                InkWell(
                                  onTap: () =>
                                      _showToppingQuantityInput(topping),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 1),
                                    child: Text(
                                      NumberFormat('#,##0.##').format(quantity),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add,
                                      size: 18, color: AppTheme.primaryColor),
                                  onPressed: () =>
                                      _updateToppingQuantity(topping.id, 1),
                                  splashRadius: 18,
                                ),
                              ],
                            ),
                          )
                        ],
                      ),
                    );
                  }).toList(),
                ),
                Divider(
                  height: 24,
                  thickness: 0.8,
                  color: Colors.grey.shade200,
                ),
              ],

              // --- KHỐI GHI CHÚ NHANH MỚI ---
              if (hasNotes) ...[
                const Text('Ghi chú nhanh:',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: widget.relevantQuickNotes.map((note) {
                    final isSelected = _selectedQuickNotes.contains(note);
                    return ChoiceChip(
                      label: Text(note.noteText),
                      selected: isSelected,
                      selectedColor: AppTheme.primaryColor.withAlpha(50),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedQuickNotes.add(note);
                          } else {
                            _selectedQuickNotes.remove(note);
                          }
                        });
                      },
                    );
                  }).toList(),
                )
              ]
              // --- KẾT THÚC KHỐI GHI CHÚ NHANH ---
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy')),
        ElevatedButton(onPressed: _onConfirm, child: const Text('Xác nhận')),
      ],
    );
  }
}
