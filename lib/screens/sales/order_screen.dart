import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/order_item_model.dart';
import '../../models/order_model.dart';
import '../../models/product_group_model.dart';
import '../../models/product_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import 'dart:async';
import '../../products/barcode_scanner_screen.dart';
import '../../models/print_job_model.dart';
import '../../services/print_queue_service.dart';
import '/screens/sales/payment_screen.dart';
import '../../theme/number_utils.dart';
import '../../models/customer_model.dart';
import '../../services/settings_service.dart';
import '../../models/store_settings_model.dart';
import '../../services/pricing_service.dart';
import '../../widgets/customer_selector.dart';
import '../../widgets/edit_order_item_dialog.dart';
import '../../theme/string_extensions.dart';
import '../../models/quick_note_model.dart';
import '../quick_notes_screen.dart';
import '../../tables/table_transfer_screen.dart';
import 'package:flutter/services.dart';
import '../../services/discount_service.dart';
import '../../models/discount_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/shift_service.dart';

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

  double get _totalAmount => _displayCart.values.fold(0, (total, item) {
        final isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;
        if (isTimeBased) {
          return total + item.price;
        } else {
          return total + item.subtotal;
        }
      });
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _priceUpdateTimer;
  final Map<String, OrderItem> _cart = {};
  final Map<String, OrderItem> _localChanges = {};
  final Map<String, TimePricingResult> _timeBasedDataCache = {};
  final Set<String> _manuallyDiscountedItems = {};
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

    for (final entry in _localChanges.entries) {
      final localItem = entry.value;
      // Lấy món tương ứng đang nằm trong giỏ hàng gốc (đã lưu trên Server)
      final serverItem = _cart[entry.key];

      // TRƯỜNG HỢP 1: Món mới hoàn toàn (chưa có trên Server) -> Cần lưu
      if (serverItem == null) return true;

      // TRƯỜNG HỢP 2: Số lượng thay đổi so với Server -> Cần lưu
      // (Ví dụ: Server có 2, Local chỉnh lên 3 -> Cần lưu)
      if (localItem.quantity != serverItem.quantity) return true;

      // Lưu ý: Ta KHÔNG kiểm tra sentQuantity ở đây nữa.
      // Dù sentQuantity = 0 nhưng nếu quantity khớp với Server thì coi như đã lưu.
    }

    return false;
  }

  final _discountService = DiscountService();
  List<DiscountModel> _activeDiscounts = [];
  StreamSubscription<List<DiscountModel>>? _discountsSub;
  bool _suppressInitialToast = false;

  bool get isDesktop => MediaQuery.of(context).size.width >= 1100;
  bool _allowProvisionalBill = true;
  bool _printBillAfterPayment = true;
  bool _showPricesOnProvisional = true;
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
  bool _isPaymentLoading = false;
  Map<String, dynamic>? _storeTaxSettings;
  final Map<String, String> _productTaxMap = {};
  StreamSubscription? _manualUpdateSub;
  List<Map<String, dynamic>> _activeBuyXGetYPromos = [];
  StreamSubscription? _buyXGetYSub;
  bool _hasCompletedPayment = false;
  List<ProductGroupModel>? _cachedGroups;
  bool _canSell = false;
  bool _canCancelItem = false;
  bool _canChangeTable = false;
  bool _canEditNotes = false;
  String? _currentShiftId;

  @override
  void initState() {
    super.initState();
    _loadCurrentShift();
    _loadTaxSettings();
    _settingsService = SettingsService();
    _firestoreService
        .getProductGroups(widget.currentUser.storeId)
        .then((groups) {
      if (mounted) {
        setState(() {
          _menuGroups = groups;
          final hasOrphanProducts = _menuProducts
              .any((p) => p.productGroup == null || p.productGroup!.isEmpty);
          if (hasOrphanProducts && !_menuGroups.any((g) => g.name == 'Khác')) {
            _menuGroups
                .add(ProductGroupModel(id: 'khac', name: 'Khác', stt: 999));
          }
          _cachedGroups = _menuGroups;
        });
      }
    });
    if (widget.currentUser.role == 'owner') {
      _canSell = true;
      _canCancelItem = true;
      _canChangeTable = true;
      _canEditNotes = true;
    } else {
      _canSell = widget.currentUser.permissions?['sales']?['canSell'] ?? false;
      _canCancelItem =
          widget.currentUser.permissions?['sales']?['canCancelItem'] ?? false;
      _canChangeTable =
          widget.currentUser.permissions?['sales']?['canChangeTable'] ?? false;
      _canEditNotes =
          widget.currentUser.permissions?['sales']?['canEditNotes'] ?? false;
    }
    // 1. Lắng nghe Settings
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _settingsSub = _settingsService.watchStoreSettings(settingsId).listen((s) {
      if (!mounted) return;
      setState(() {
        _allowProvisionalBill = s.allowProvisionalBill;
        _printBillAfterPayment = s.printBillAfterPayment;
        _showPricesOnProvisional = s.showPricesOnProvisional;
        _promptForCash = s.promptForCash ?? true;
        _skipKitchenPrint = s.skipKitchenPrint ?? false;
        _printLabelOnKitchen = s.printLabelOnKitchen ?? false;
        _labelWidth = s.labelWidth ?? 50.0;
        _labelHeight = s.labelHeight ?? 30.0;
      });
    }, onError: (e, st) {
      debugPrint('watchStoreSettings error: $e');
    }, cancelOnError: true);

    // 2. Setup Keyboard & Order Stream
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

    // 3. Setup Product & Search
    _productsStream =
        _firestoreService.getAllProductsStream(widget.currentUser.storeId);

    _searchController.addListener(() {
      if (!mounted) return;
      setState(() => _searchQuery = _searchController.text.toLowerCase());
    });

    if (widget.initialOrder != null) {
      _numberOfCustomers = widget.initialOrder!.numberOfCustomers ?? 1;
    }

    // 4. Timer cập nhật giá theo giờ (mỗi phút)
    _priceUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _updateTimeBasedPrices();
    });

    // 5. Lắng nghe sự kiện update Discount thủ công
    _manualUpdateSub = DiscountService.onDiscountsChanged.listen((_) {
      if (mounted) {
        debugPrint(">>> [EVENT] Nhận tín hiệu Cập Nhật Giảm Giá chủ động!");
        _manuallyDiscountedItems.clear();
        _recalculateCartDiscounts();
      }
    });

    // 6. Load data phụ (Staff, QuickNotes)
    _fetchStaff();
    _listenQuickNotes();

    // 7. Lắng nghe chương trình Giảm giá (Discounts)
    _discountsSub = _discountService
        .getActiveDiscountsStream(widget.currentUser.storeId)
        .listen((discounts) {
      if (mounted) {
        setState(() {
          _activeDiscounts = discounts;
        });
        _manuallyDiscountedItems.clear();
        _recalculateCartDiscounts();
      }
    });

    // 8. [MỚI] Lắng nghe chương trình Mua X Tặng Y
    _buyXGetYSub = _firestoreService
        .getActiveBuyXGetYPromotionsStream(widget.currentUser.storeId)
        .listen((promos) {
      if (mounted) {
        setState(() {
          _activeBuyXGetYPromos = promos;
        });
        // Tính toán lại ngay khi load xong khuyến mãi
        _applyBuyXGetYLogic();
      }
    });

    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PaymentScreen.preloadData(widget.currentUser.storeId, ownerUid);
    });
  }

  Future<void> _loadCurrentShift() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _currentShiftId = prefs.getString('current_shift_id');
      });
      debugPrint(">>> OrderScreen: Ca hiện tại là $_currentShiftId");
    } catch (e) {
      debugPrint("Lỗi lấy ca làm việc: $e");
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _settingsSub?.cancel();
    _quickNotesSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _priceUpdateTimer?.cancel();
    _discountsSub?.cancel();
    _manualUpdateSub?.cancel();

    // [QUAN TRỌNG] Hủy lắng nghe Mua X Tặng Y để tránh lỗi
    _buyXGetYSub?.cancel();

    super.dispose();
  }

  void _applyBuyXGetYLogic() {
    if (_activeBuyXGetYPromos.isEmpty) return;

    final Map<String, OrderItem> cartSnapshot = {..._cart, ..._localChanges};

    cartSnapshot.removeWhere((key, item) => item.status == 'cancelled');

    final Map<String, OrderItem> updates = {};

    for (final promo in _activeBuyXGetYPromos) {
      final String buyId = promo['buyProductId'];
      final double buyQtyReq = (promo['buyQuantity'] as num).toDouble();
      final String? buyUnitReq = promo['buyUnit'];

      final String giftId = promo['giftProductId'];
      final double giftQtyReward = (promo['giftQuantity'] as num).toDouble();
      final double giftPrice = (promo['giftPrice'] as num).toDouble();
      final String giftNote = "Tặng kèm ${promo['name']}";

      // 1. Tính tổng số lượng hàng MUA
      double currentBuyQty = 0;
      for (final item in cartSnapshot.values) {
        if (item.product.id == buyId && item.note != giftNote) {
          if (buyUnitReq != null && buyUnitReq.isNotEmpty) {
            if (item.selectedUnit == buyUnitReq) {
              currentBuyQty += item.quantity;
            }
          } else {
            currentBuyQty += item.quantity;
          }
        }
      }

      // 2. Tính toán quà tặng
      int sets = 0;
      if (buyQtyReq > 0) sets = (currentBuyQty / buyQtyReq).floor();
      double totalGiftNeeded = sets * giftQtyReward;

      // 3. Tìm món quà đang có trong giỏ (để cập nhật hoặc xóa)
      String? existingGiftLineId;
      OrderItem? existingGiftItem;

      final allItems = {..._cart, ..._localChanges};
      for (final entry in allItems.entries) {
        if (entry.value.product.id == giftId &&
            entry.value.note == giftNote &&
            entry.value.status != 'cancelled') {
          existingGiftLineId = entry.key;
          existingGiftItem = entry.value;
          break;
        }
      }

      // 4. Đồng bộ
      if (totalGiftNeeded > 0) {
        if (existingGiftItem != null) {
          if (existingGiftItem.quantity != totalGiftNeeded ||
              existingGiftItem.price != giftPrice) {
            updates[existingGiftLineId!] = existingGiftItem.copyWith(
              quantity: totalGiftNeeded,
              price: giftPrice,
              discountValue: 0,
              discountUnit: 'VNĐ',
            );
          }
        } else {
          final productModel =
              _menuProducts.firstWhereOrNull((p) => p.id == giftId);
          if (productModel != null) {
            final newItem = OrderItem(
              product: productModel,
              price: giftPrice,
              quantity: totalGiftNeeded,
              selectedUnit: promo['giftUnit'] ?? productModel.unit ?? '',
              addedBy: "System",
              addedAt: Timestamp.now(),
              discountValue: 0,
              discountUnit: 'VNĐ',
              note: giftNote,
              commissionStaff: {},
            );
            updates[newItem.lineId] = newItem;
          }
        }
      } else {
        if (existingGiftLineId != null) {
          updates[existingGiftLineId] =
              existingGiftItem!.copyWith(quantity: 0, status: 'cancelled');
        }
      }
    }

    if (updates.isNotEmpty) {
      setState(() {
        _localChanges.addAll(updates);
      });
    }
  }

  Future<void> _loadTaxSettings() async {
    try {
      final settings = await _firestoreService
          .getStoreTaxSettings(widget.currentUser.storeId);
      if (mounted && settings != null) {
        setState(() {
          _storeTaxSettings = settings;
          final rawMap =
              settings['taxAssignmentMap'] as Map<String, dynamic>? ?? {};
          _productTaxMap.clear();
          rawMap.forEach((taxKey, productIds) {
            if (productIds is List) {
              for (var pid in productIds) {
                _productTaxMap[pid.toString()] = taxKey;
              }
            }
          });
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải cấu hình thuế: $e");
    }
  }

  void _recalculateCartDiscounts({bool triggerSetState = true}) {
    bool hasDiscountChanges = false;
    final Map<String, OrderItem> updates = {};
    final allItems = {..._cart, ..._localChanges};

    // 1. TÍNH TOÁN CÁC THAY ĐỔI VỀ GIẢM GIÁ
    for (final entry in allItems.entries) {
      final key = entry.key;
      if (_manuallyDiscountedItems.contains(key)) continue;
      final item = entry.value;

      if (item.status == 'cancelled') continue;
      if (item.note != null && item.note!.startsWith("Tặng kèm (")) continue;

      final discountItem = _discountService.findBestDiscountForProduct(
        product: item.product,
        activeDiscounts: _activeDiscounts,
        customer: _selectedCustomer,
        checkTime: item.addedAt.toDate(),
      );

      final double currentItemVal = item.discountValue ?? 0;
      final String currentItemUnit = item.discountUnit ?? '%';

      double newCalculatedAmount = 0;
      String newUnit = '%';

      if (discountItem != null) {
        final double configValue = discountItem.value;
        final bool isPercent = discountItem.isPercent;
        newUnit = isPercent ? '%' : 'VNĐ';

        if (isPercent) {
          newCalculatedAmount = configValue;
        } else {
          final isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;
          if (isTimeBased) {
            newCalculatedAmount = configValue;
          } else {
            newCalculatedAmount = configValue;
          }
        }
      }

      bool valueChanged = (currentItemVal - newCalculatedAmount).abs() > 0.001;
      bool unitChanged = currentItemUnit != newUnit;

      if (valueChanged || unitChanged) {
        updates[key] = item.copyWith(
          discountValue: newCalculatedAmount,
          discountUnit: newUnit,
        );
        hasDiscountChanges = true;
      }
    }

    if (hasDiscountChanges || updates.isNotEmpty) {
      _localChanges.addAll(updates);
    }

    // Gọi hàm tính tiền giờ nhưng CHUYỀN triggerSetState xuống
    _updateTimeBasedPrices(triggerSetState: triggerSetState);

    // Xử lý logic cho món thường nếu cần vẽ lại
    if (triggerSetState && hasDiscountChanges) {
      bool hasTimeBasedItem = _displayCart.values
          .any((i) => i.product.serviceSetup?['isTimeBased'] == true);
      if (!hasTimeBasedItem && mounted) setState(() {});
    }
  }

  void _updateTimeBasedPrices({bool triggerSetState = true}) {
    if (!mounted) return;
    bool needsUpdate = false;

    _displayCart.forEach((lineId, item) {
      final serviceSetup = item.product.serviceSetup;

      if (serviceSetup != null &&
          serviceSetup['isTimeBased'] == true &&
          !item.isPaused) {
        // 1. Tính toán thời gian & block gốc từ Service
        final pricingResult =
            TimeBasedPricingService.calculatePriceWithBreakdown(
          product: item.product,
          startTime: item.addedAt,
          isPaused: item.isPaused,
          pausedAt: item.pausedAt,
          totalPausedDurationInSeconds: item.totalPausedDurationInSeconds,
        );

        // 2. Lấy thông tin khuyến mãi hiện tại của Item
        double currentDiscountVal = item.discountValue ?? 0;
        String currentDiscountUnit = item.discountUnit ?? '%';

        // 3. [QUAN TRỌNG] TÍNH LẠI GIÁ (REAL COST) DỰA TRÊN GIÁ NIÊM YẾT MỚI
        // Chúng ta sẽ tạo lại danh sách blocks với giá đã giảm để hiển thị và lưu trữ
        double realTotalCost = 0;
        List<TimeBlock> updatedBlocks = [];

        for (var block in pricingResult.blocks) {
          double effectiveRate = block.ratePerHour;
          double blockCost = 0;

          // Kiểm tra xem đây có phải là Block giá cố định (Giá tối thiểu) không?
          bool isFixedPriceBlock = (block.ratePerHour == 0 && block.cost > 0);

          if (isFixedPriceBlock) {
            // --- [SỬA] TRƯỜNG HỢP 1: BLOCK GIÁ CỐ ĐỊNH (TỐI THIỂU) ---
            // Yêu cầu: KHÔNG áp dụng tăng/giảm giá cho phần này.
            // Giữ nguyên giá gốc từ cài đặt.
            blockCost = block.cost;
          } else {
            // --- TRƯỜNG HỢP 2: BLOCK TÍNH GIỜ BÌNH THƯỜNG ---

            // Áp dụng tăng/giảm giá vào ĐƠN GIÁ GIỜ (Rate)
            // discountVal != 0 nghĩa là có tăng (âm) hoặc giảm (dương)
            if (currentDiscountVal != 0) {
              if (currentDiscountUnit == 'VNĐ') {
                // Trừ tiền mặt trực tiếp vào đơn giá giờ
                effectiveRate = block.ratePerHour - currentDiscountVal;
              } else {
                // Trừ %
                effectiveRate =
                    block.ratePerHour * (1 - currentDiscountVal / 100);
              }
            }
            // Đảm bảo không âm (nếu giảm quá tay)
            if (effectiveRate < 0) effectiveRate = 0;

            // Tính thành tiền: (Giá mới / 60) * số phút
            blockCost = (effectiveRate / 60.0) * block.minutes;
          }

          realTotalCost += blockCost;

          updatedBlocks.add(TimeBlock(
            label: block.label,
            startTime: block.startTime,
            endTime: block.endTime,
            ratePerHour: effectiveRate,
            // Lưu rate đã giảm (để hiển thị)
            minutes: block.minutes,
            cost: blockCost, // Lưu cost đã tính chuẩn
          ));
        }

        double finalPriceToStore = realTotalCost.round().toDouble();

        if ((finalPriceToStore - item.price).abs() > 1.0 ||
            pricingResult.totalMinutesBilled !=
                (item.priceBreakdown.isNotEmpty
                    ? item.priceBreakdown.fold(0, (tong, b) => tong + b.minutes)
                    : 0)) {
          final updatedItem = item.copyWith(
            price: finalPriceToStore,
            priceBreakdown: updatedBlocks,
            discountValue: currentDiscountVal,
            discountUnit: currentDiscountUnit,
          );

          _timeBasedDataCache[lineId] = pricingResult;

          if (_localChanges.containsKey(lineId)) {
            _localChanges[lineId] = updatedItem;
            needsUpdate = true;
          } else if (_cart.containsKey(lineId)) {
            _localChanges[lineId] = updatedItem;
            needsUpdate = true;
          }
        }
      }
    });

    // [QUAN TRỌNG] Chỉ gọi setState nếu triggerSetState = true
    if (needsUpdate && triggerSetState) {
      setState(() {});
      _saveOrder(onlyTimeBasedUpdates: true);
    }
  }

  String _getTaxDisplayString(ProductModel product) {
    if (_storeTaxSettings == null) return '';

    // 1. Xác định phương pháp tính (Trực tiếp hay Khấu trừ)
    final String calcMethod = _storeTaxSettings!['calcMethod'] ??
        'direct'; // 'direct' hoặc 'deduction'
    // 2. Lấy mã thuế của sản phẩm (nếu không có thì mặc định)
    final String? taxKey = _productTaxMap[product.id];

    if (taxKey == null) return '';

    if (calcMethod == 'deduction') {
      // Phương pháp Khấu trừ (VAT)
      switch (taxKey) {
        case 'VAT_10':
          return '(VAT 10%)';
        case 'VAT_8':
          return '(VAT 8%)';
        case 'VAT_5':
          return '(VAT 5%)';
        case 'VAT_0':
          return '(VAT 0%)';
        default:
          return '';
      }
    } else {
      // Phương pháp Trực tiếp (LST - Lệ suất thuế / Tỷ lệ %)
      switch (taxKey) {
        case 'HKD_RETAIL':
          return '(LST 1.5%)';
        case 'HKD_PRODUCTION':
          return '(LST 4.5%)';
        case 'HKD_SERVICE':
          return '(LST 7%)';
        case 'HKD_LEASING':
          return '(LST 10%)';
        default:
          return '';
      }
    }
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
        selection: TextSelection.collapsed(
            offset: newText.length), // Đưa con trỏ về cuối
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
        key == LogicalKeyboardKey.f1 ||
        key == LogicalKeyboardKey.f2 ||
        key == LogicalKeyboardKey.f3 ||
        key == LogicalKeyboardKey.f4 ||
        key == LogicalKeyboardKey.f5 ||
        key == LogicalKeyboardKey.f6 ||
        key == LogicalKeyboardKey.f7 ||
        key == LogicalKeyboardKey.f8 ||
        key == LogicalKeyboardKey.f9 ||
        key == LogicalKeyboardKey.f10 ||
        key == LogicalKeyboardKey.f11 ||
        key == LogicalKeyboardKey.f12;
  }

  Future<void> _listenQuickNotes() async {
    _quickNotesSub = _firestoreService
        .getQuickNotes(widget.currentUser.storeId)
        .listen((notes) {
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
        p.additionalBarcodes
            .any((b) => b.toLowerCase() == query.toLowerCase()));

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
          duration: const Duration(seconds: 1));
    } else {
      ToastService()
          .show(message: "Không tìm thấy mã: $query", type: ToastType.warning);
      if (!_isPaymentView) {
        _searchFocusNode.requestFocus();
      }
    }
  }

  Widget _buildTableTransferButton() {
    return IconButton(
      icon: const Icon(Icons.call_split_outlined,
          color: AppTheme.primaryColor, size: 30),
      tooltip: 'Tách/Gộp/Chuyển Bàn',
      onPressed: (_currentOrder == null)
          ? null
          : () async {
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
    _saveOrder(onlyTimeBasedUpdates: true);
  }

  Future<void> _addItemToCart(ProductModel product) async {
    final serviceSetup = product.serviceSetup;

    if (serviceSetup != null && serviceSetup['isTimeBased'] == true) {
      if (_displayCart.values.any((item) => item.product.id == product.id)) {
        ToastService().show(
            message: "Dịch vụ này đã được tính giờ.", type: ToastType.warning);
        return;
      }

      final startTime = Timestamp.now();

      // 1. Tính giá khởi điểm
      final initialResult = TimeBasedPricingService.calculatePriceWithBreakdown(
        product: product,
        startTime: startTime,
        isPaused: false,
        pausedAt: null,
        totalPausedDurationInSeconds: 0,
      );

      // 2. [FIX] TÌM KHUYẾN MÃI NGAY LẬP TỨC (Trước khi tạo Item)
      final discountItem = _discountService.findBestDiscountForProduct(
        product: product,
        activeDiscounts: _activeDiscounts,
        customer: _selectedCustomer,
        checkTime: startTime.toDate(), // Dùng giờ bắt đầu để check
      );

      double discountVal = 0;
      String discountUnit = '%';

      if (discountItem != null) {
        discountVal = discountItem.value;
        discountUnit = discountItem.isPercent ? '%' : 'VNĐ';
      }

      // 3. Tạo Item với thông tin giảm giá đã tìm được
      final newItem = OrderItem(
        product: product,
        price: initialResult.totalPrice,
        priceBreakdown: initialResult.blocks,
        quantity: 1,
        // Lúc đầu set là 1, sau này update timer sẽ thành số giờ
        sentQuantity: 1,
        addedBy: widget.currentUser.name ?? 'N/A',
        addedAt: startTime,

        // [FIX] Gán giá trị giảm giá vào ngay lúc tạo
        discountValue: discountVal,
        discountUnit: discountUnit,

        note: null,
        commissionStaff: {},
      );

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
          ToastService().show(
              message: "Không thể lưu dịch vụ tính giờ.",
              type: ToastType.error);
          return;
        }
      } else {
        await _saveTimeBasedServiceOnly(newItem);
      }

      return;
    }

    final relevantNotes = _quickNotes.where((note) {
      return note.productIds.isEmpty || note.productIds.contains(product.id);
    }).toList();

    final bool needsOptionDialog = product.additionalUnits.isNotEmpty ||
        product.accompanyingItems.isNotEmpty ||
        relevantNotes.isNotEmpty;

    OrderItem newItem;

    final discountItem = _discountService.findBestDiscountForProduct(
      product: product,
      activeDiscounts: _activeDiscounts,
      customer: _selectedCustomer,
      checkTime: DateTime.now(),
    );

    if (needsOptionDialog) {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => _ProductOptionsDialog(
          product: product,
          allProducts: _menuProducts,
          relevantQuickNotes: relevantNotes,
        ),
      );
      if (result == null) return;

      final selectedUnit = result['selectedUnit'] as String;
      final priceForUnit = result['price'] as double;
      final selectedToppings =
          result['selectedToppings'] as Map<ProductModel, double>;
      final selectedNoteText = result['selectedNote'] as String?;

      double originalPrice = priceForUnit;
      double discountVal = 0;
      String discountUnit = '%';

      if (discountItem != null) {
        if (discountItem.isPercent) {
          discountVal = discountItem.value;
          discountUnit = '%';
        } else {
          discountVal = discountItem.value;
          discountUnit = 'VNĐ';
        }
      }

      newItem = OrderItem(
        product: product,
        selectedUnit: selectedUnit,
        price: originalPrice,
        // VẪN LƯU GIÁ GỐC
        toppings: selectedToppings,
        addedBy: widget.currentUser.name ?? 'N/A',
        addedAt: Timestamp.now(),
        discountValue: discountVal,
        // CHỈ LƯU GIÁ TRỊ GIẢM
        discountUnit: discountUnit,
        note: selectedNoteText.nullIfEmpty,
        commissionStaff: {},
      );
    } else {
      // Logic không có dialog
      double originalPrice = product.sellPrice;
      double discountVal = 0;
      String discountUnit = '%';

      if (discountItem != null) {
        if (discountItem.isPercent) {
          discountVal = discountItem.value;
          discountUnit = '%';
        } else {
          discountVal = discountItem.value;
          discountUnit = 'VNĐ';
        }
      }

      newItem = OrderItem(
        product: product,
        price: originalPrice,
        // VẪN LƯU GIÁ GỐC
        selectedUnit: product.unit ?? '',
        addedBy: widget.currentUser.name ?? 'N/A',
        addedAt: Timestamp.now(),
        discountValue: discountVal,
        // CHỈ LƯU GIÁ TRỊ GIẢM
        discountUnit: discountUnit,
        note: null,
        commissionStaff: {},
      );
    }

    final gk = newItem.groupKey;
    setState(() {
      final existingEntry = _displayCart.entries
          .firstWhereOrNull((entry) => entry.value.groupKey == gk);
      if (existingEntry != null) {
        final existingItem = existingEntry.value;
        final existingKey = existingEntry.key;
        _localChanges[existingKey] =
            existingItem.copyWith(quantity: existingItem.quantity + 1);
      } else {
        _localChanges[newItem.lineId] = newItem;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyBuyXGetYLogic();
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

      if (!serverSnapshot.exists ||
          ['paid', 'cancelled'].contains(serverData?['status'])) {
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
          'createdByName':
              widget.currentUser.name ?? widget.currentUser.phoneNumber,
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

        if (!serverSnapshot.exists ||
            ['paid', 'cancelled'].contains(serverData?['status'])) {
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
            'createdByName':
                widget.currentUser.name ?? widget.currentUser.phoneNumber,
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

        final serverItems =
            List<Map<String, dynamic>>.from(serverData!['items'] ?? []);
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
        ToastService().show(
            message: "Lỗi lưu dịch vụ: ${e.toString()}", type: ToastType.error);
      }
    }
  }

  double _rawSubtotalFromMap(Map<String, dynamic> m) {
    final q = (m['quantity'] as num?)?.toDouble() ?? 0.0;
    final p = (m['price'] as num?)?.toDouble() ?? 0.0;
    final productData = (m['product'] as Map<String, dynamic>?) ?? {};
    if (productData['serviceSetup']?['isTimeBased'] == true) {
      return (m['price'] as num?)?.toDouble() ?? 0.0;
    }

    final isTimeBased = productData['serviceSetup']?['isTimeBased'] == true;
    final discVal = (m['discountValue'] as num?)?.toDouble() ?? 0.0;
    final discUnit = (m['discountUnit'] as String?) ?? '%';

    if (isTimeBased) {
      return p;
    }

    double basePrice = p;
    double discountedPrice = basePrice;

    if (discVal != 0) {
      if (discUnit == '%') {
        // Công thức: Giá * (1 - %/100). Nếu % là số âm (VD -10) -> Giá * 1.1 (Tăng 10%)
        discountedPrice = basePrice * (1 - discVal / 100);
      } else {
        // Công thức: Giá - Tiền. Nếu Tiền là số âm (VD -5000) -> Giá + 5000 (Tăng)
        discountedPrice = (basePrice - discVal).clamp(0, double.maxFinite);
      }
    }

    // Tính toán cho món thường + topping
    double toppingsTotalPerUnit = 0.0;
    final tops = m['toppings'];
    if (tops is List) {
      for (final t in tops) {
        if (t is Map) {
          final tp = (t['price'] as num?)?.toDouble() ?? 0.0;
          final tq = (t['quantity'] as num?)?.toDouble() ?? 0.0;
          toppingsTotalPerUnit += tp * tq;
        }
      }
    }

    return q * (discountedPrice + toppingsTotalPerUnit);
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
    final item = _displayCart[lineId];
    if (item != null && item.note != null && item.note!.contains("Tặng kèm")) {
      ToastService().show(
          message: "Đây là hàng tặng kèm tự động. Hãy sửa số lượng món mua.",
          type: ToastType.warning);
      return;
    }

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
    _applyBuyXGetYLogic();
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

    // 1. QUÉT TOÀN BỘ GIỎ HÀNG ĐỂ TÌM MÓN CHƯA BÁO BẾP (ADD)
    // Logic cũ chỉ quét _localChanges, Logic mới quét _displayCart
    final allItems = _displayCart.values.toList();
    final itemsNeedCooking = allItems.where((item) {
      // Chỉ lấy món chưa hủy và số lượng thực tế > số lượng đã gửi
      return item.status != 'cancelled' && item.quantity > item.sentQuantity;
    }).toList();

    // 2. QUÉT CÁC MÓN CẦN HỦY (CANCEL)
    // Với món hủy, ta vẫn dựa vào _localChanges vì hành động hủy là hành động tức thời
    final itemsNeedCancelling = _localChanges.values.where((item) {
      // Logic hủy: status là cancelled HOẶC số lượng giảm đi so với bản đã lưu (trong _cart gốc)
      if (item.status == 'cancelled') return true;

      final originalItem = _cart[item.lineId];
      if (originalItem != null && item.quantity < originalItem.sentQuantity) {
        return true;
      }
      return false;
    }).toList();

    if (itemsNeedCooking.isEmpty && itemsNeedCancelling.isEmpty) {
      // Nếu localChanges vẫn còn rác (ví dụ update note nhưng ko đổi số lượng), vẫn cho lưu nhưng ko in
      if (_localChanges.isNotEmpty) {
        await _saveOrder();
        if (popOnFinish && mounted) Navigator.of(context).pop();
        return true;
      }

      ToastService().show(
          message: "Tất cả món đã được gửi bếp.", type: ToastType.warning);
      return true;
    }

    // 3. CHUẨN BỊ PAYLOAD ĐỂ IN & CẬP NHẬT FIRESTORE
    final List<Map<String, dynamic>> addItemsPayload = [];
    final List<Map<String, dynamic>> cancelItemsPayload = [];

    // 3a. Xử lý món THÊM (In toàn bộ phần chênh lệch)
    for (final item in itemsNeedCooking) {
      final double diff = item.quantity - item.sentQuantity;
      if (diff > 0) {
        // Cập nhật vào _localChanges: Đánh dấu là đã gửi (sentQuantity = quantity)
        // Để khi _saveOrder chạy, nó sẽ lưu trạng thái này lên Server
        _localChanges[item.lineId] = item.copyWith(sentQuantity: item.quantity);

        // Tạo payload in
        final payload = item.toMap();
        payload['quantity'] = diff; // Chỉ in phần chênh lệch
        addItemsPayload.add({'isCancel': false, ...payload});
      }
    }

    // 3b. Xử lý món HỦY
    for (final item in itemsNeedCancelling) {
      double diff = 0;
      if (item.status == 'cancelled') {
        // Nếu hủy cả dòng -> In số lượng đã gửi trước đó (nếu có)
        final originalItem = _cart[item.lineId];
        diff = originalItem?.sentQuantity ?? item.quantity; // Fallback
      } else {
        // Nếu giảm số lượng -> In phần chênh lệch giảm
        final originalItem = _cart[item.lineId];
        if (originalItem != null) {
          diff = originalItem.sentQuantity - item.quantity;
        }
      }

      if (diff > 0) {
        final payload = item.toMap();
        payload['quantity'] = diff;
        cancelItemsPayload.add({'isCancel': true, ...payload});
      }
    }

    // 4. LƯU ĐƠN LÊN SERVER
    // Lúc này _localChanges đã được cập nhật sentQuantity mới ở bước 3a
    final success = await _saveOrder();
    if (!success || _currentOrder == null) return false;

    // 5. GỬI LỆNH IN
    if (performPrint) {
      final bool isOnlineOrder = widget.table.id.startsWith('ship_') ||
          widget.table.id.startsWith('schedule_');

      Map<String, dynamic>? kitchenPayload;
      Map<String, dynamic>? cancelPayload;
      Map<String, dynamic>? labelPayload;

      // Payload Bếp (Thêm món)
      if (!_skipKitchenPrint && addItemsPayload.isNotEmpty) {
        kitchenPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': addItemsPayload,
          'printType': 'add'
        };
        if (isOnlineOrder && _customerNameFromOrder != null) {
          kitchenPayload['customerName'] = _customerNameFromOrder;
        }
      }

      // Payload Bếp (Hủy món)
      if (!_skipKitchenPrint && cancelItemsPayload.isNotEmpty) {
        cancelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': cancelItemsPayload,
          'printType': 'cancel'
        };
      }

      // Payload Tem (Label)
      if (_printLabelOnKitchen && addItemsPayload.isNotEmpty) {
        labelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'items': addItemsPayload,
          'labelWidth': _labelWidth,
          'labelHeight': _labelHeight,
        };
      }

      // THỰC HIỆN IN
      if (labelPayload != null) {
        PrintQueueService().addJob(PrintJobType.label, labelPayload);
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (kitchenPayload != null) {
        PrintQueueService().addJob(PrintJobType.kitchen, kitchenPayload);
      }

      if (cancelPayload != null) {
        if (kitchenPayload != null) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        PrintQueueService().addJob(PrintJobType.cancel, cancelPayload);
      }

      // Thông báo
      if (addItemsPayload.isNotEmpty || cancelItemsPayload.isNotEmpty) {
        String msg = "Đã gửi báo chế biến.";
        if (_skipKitchenPrint) msg = "Đã tắt in báo chế biến.";
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
      ToastService().show(
          message: "Chưa có sản phẩm nào để in.", type: ToastType.warning);
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

    // --- SỬA ĐỔI: ĐẢM BẢO CA LÀM VIỆC LUÔN TỒN TẠI TRƯỚC KHI THANH TOÁN ---
    try {
      await ShiftService().ensureShiftOpen(
        widget.currentUser.storeId,
        widget.currentUser.uid,
        widget.currentUser.name ?? 'NV',
        widget.currentUser.ownerUid ?? widget.currentUser.uid,
      );
    } catch (e) {
      debugPrint("Lỗi khởi tạo ca làm việc: $e");
    }
    // ----------------------------------------------------------------------

    final prefs = await SharedPreferences.getInstance();
    final String? latestShiftId = prefs.getString('current_shift_id');

    // Kiểm tra kỹ thêm 1 lần nữa
    if (latestShiftId == null) {
      ToastService().show(
          message: "Lỗi: Không thể tạo ca làm việc. Vui lòng thử lại.",
          type: ToastType.error
      );
      return;
    }

    if (mounted) {
      setState(() {
        _currentShiftId = latestShiftId;
      });
    }
    debugPrint(">>> [Payment] Shift ID lúc thanh toán: $_currentShiftId");

    setState(() => _isPaymentLoading = true);

    try {
      if (_currentOrder == null) {
        final DocumentReference orderRef =
            _firestoreService.getOrderReference(widget.table.id);
        final String newOrderId = orderRef.id;

        final List<Map<String, dynamic>> optimisticItems =
            _displayCart.values.map((item) {
          return item.toMap();
        }).toList();

        final double currentTotal = _totalAmount;

        final Map<String, dynamic> optimisticData = {
          'id': newOrderId,
          'tableId': widget.table.id,
          'tableName': widget.table.tableName,
          'storeId': widget.currentUser.storeId,
          'status': 'active',
          'startTime': Timestamp.now(),
          'items': optimisticItems,
          'totalAmount': currentTotal,
          'customerId': _selectedCustomer?.id,
          'customerName': _selectedCustomer?.name,
          'customerPhone': _selectedCustomer?.phone,
          'numberOfCustomers': _numberOfCustomers,
          'version': 1,
          'createdAt': Timestamp.now(),
          'createdByUid': widget.currentUser.uid,
          'createdByName':
              widget.currentUser.name ?? widget.currentUser.phoneNumber,
        };

        final optimisticOrder = OrderModel.fromMap(optimisticData);

        _currentOrder = optimisticOrder;

        final serverData = Map<String, dynamic>.from(optimisticData);
        serverData['createdAt'] = FieldValue.serverTimestamp();
        serverData['startTime'] = FieldValue.serverTimestamp();

        orderRef.set(serverData).then((_) {
          debugPrint(
              ">>> [Background] Đã tạo đơn mới ngầm thành công: $newOrderId");
        }).catchError((e) {
          debugPrint(">>> [Background] Lỗi tạo đơn ngầm: $e");
        });
      } else {
        await _saveOrder();
      }

      final savedState = _paymentStateCache[_currentOrder!.id];
      _isFinalizingPayment = true;

      final upToDateOrder = _currentOrder!.copyWith(
        items: _displayCart.values.map((item) {
          return item.toMap();
        }).toList(),
        totalAmount: _totalAmount,
      );

      if (mounted) {
        setState(() {
          _localChanges.forEach((key, item) {
            _cart[key] = item;
          });

          _localChanges.clear();

          if (_cart.isEmpty && _currentOrder != null) {
            final itemsMap = {
              for (var item in _currentOrder!.items)
                OrderItem.fromMap(item as Map<String, dynamic>,
                        allProducts: _menuProducts)
                    .lineId: OrderItem.fromMap(item, allProducts: _menuProducts)
            };
            _cart.addAll(itemsMap);
          }
        });
      }
      if (!mounted) return;
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
              initialState: savedState,
              promptForCash: _promptForCash,
              currentShiftId: _currentShiftId,
            ),
          ),
        );

        _isFinalizingPayment = false;
        if (result == true || result is PaymentResult) {
          debugPrint(">>> [ORDER] Thanh toán thành công. Dọn dẹp...");

          _hasCompletedPayment = true;

          setState(() {
            _localChanges.clear();
            _cart.clear();
            _currentOrder = null;
          });

          if (_currentOrder != null) {
            _paymentStateCache.remove(_currentOrder!.id);
          }

          if (mounted) Navigator.of(context).pop();
        } else if (result is PaymentState) {
          if (_currentOrder != null) {
            _paymentStateCache[_currentOrder!.id] = result;
          }
        }
      }
    } catch (e) {
      debugPrint("Lỗi chuẩn bị thanh toán: $e");
      ToastService().show(message: "Lỗi: $e", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isPaymentLoading = false);
      }
    }
  }

  Widget _buildQuickNotesIconButton() {
    return IconButton(
      icon: const Icon(Icons.note_add_outlined,
          color: AppTheme.primaryColor, size: 30),
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
        canPop: _hasCompletedPayment,
        onPopInvokedWithResult: (didPop, result) async {
          if (didPop) return;

          final bool isBookingTable = widget.table.id.startsWith('schedule_');
          final bool shouldWarn = (!isBookingTable && _hasUnsentItems) ||
              (isBookingTable && _localChanges.isNotEmpty);

          if (shouldWarn) {
            final wantsToExit = await _showExitConfirmationDialog();
            if (wantsToExit == true) {
              _localChanges.clear(); // Xóa các món đang lưu local
              if (context.mounted) Navigator.of(context).pop(result);
            }
          }
          // 2. LOGIC TỰ ĐỘNG LƯU NGẦM (Chỉ áp dụng cho bàn thường khi sửa món cũ)
          else if (_localChanges.isNotEmpty && !isBookingTable) {
            // Gọi hàm lưu chạy ngầm (không await để UI thoát ngay)
            _saveOrder().then((success) {
              if (!success) {
                debugPrint("Lưu ngầm thất bại (User đã thoát)");
              } else {
                debugPrint("Đã lưu ngầm thành công sau khi thoát");
              }
            });

            // Cho phép thoát ngay lập tức
            if (context.mounted) Navigator.of(context).pop(result);
          }
          // 3. KHÔNG CÓ THAY ĐỔI GÌ -> THOÁT LUÔN
          else {
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

            if (_cachedGroups != null) {
              // Lọc các nhóm có chứa sản phẩm hiện tại
              _menuGroups = _cachedGroups!
                  .where(
                      (g) => _menuProducts.any((p) => p.productGroup == g.name))
                  .toList();

              // Kiểm tra xem có sản phẩm nào không thuộc nhóm nào không (Orphan)
              final bool hasOrphanProducts = _menuProducts.any(
                  (p) => p.productGroup == null || p.productGroup!.isEmpty);

              // Nếu có, thêm nhóm "Khác" vào cuối
              if (hasOrphanProducts) {
                // Chỉ thêm nếu chưa có
                if (!_menuGroups.any((g) => g.name == 'Khác')) {
                  _menuGroups.add(ProductGroupModel(
                      id: 'khac_group_id', name: 'Khác', stt: 99999));
                }
              }
            }

            return StreamBuilder<DocumentSnapshot>(
              stream: _orderStream,
              builder: (context, orderSnapshot) {
                if (orderSnapshot.connectionState == ConnectionState.active &&
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

                return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
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

    // 1. Dựng lại giỏ hàng từ Firestore (Code cũ giữ nguyên)
    for (var itemData in firestoreItems) {
      OrderItem newItem = OrderItem.fromMap(
        (itemData as Map).cast<String, dynamic>(),
        allProducts: currentProducts,
      );

      // Lưu ý: Đã bỏ đoạn check thủ công gây lag ở đây như bạn đã làm

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
          discountValue: newItem.discountValue,
          discountUnit: newItem.discountUnit,
        );
        mergedCart[existingKey] = updatedItem;
      } else {
        mergedCart[newItem.lineId] = newItem;
      }
    }

    if (mounted) {
      // [SỬA ĐỔI QUAN TRỌNG TẠI ĐÂY]

      // Bước 1: Cập nhật dữ liệu vào biến _cart TRƯỚC (chưa hiển thị)
      _cart.clear();
      _cart.addAll(mergedCart);

      _manuallyDiscountedItems.clear();

      for (var entry in _cart.entries) {
        final item = entry.value;

        // 1. Tính thử xem nếu chạy tự động thì ra bao nhiêu
        final discountItem = _discountService.findBestDiscountForProduct(
          product: item.product,
          activeDiscounts: _activeDiscounts,
          customer: _selectedCustomer,
          checkTime: item.addedAt.toDate(),
        );

        double autoVal = 0;
        String autoUnit = '%';

        if (discountItem != null) {
          autoVal = discountItem.value;
          autoUnit = discountItem.isPercent ? '%' : 'VNĐ';
        }

        // 2. So sánh giá trị đang lưu trong DB (item.discountValue) với giá trị tự động (autoVal)
        // Nếu khác nhau => Nghĩa là người dùng đã sửa tay => Add vào danh sách chặn
        final double currentVal = item.discountValue ?? 0;
        final String currentUnit = item.discountUnit ?? '%';

        // So sánh có sai số nhỏ (cho số double)
        final bool isValueDiff = (currentVal - autoVal).abs() > 0.001;
        final bool isUnitDiff = currentUnit != autoUnit;

        if (isValueDiff || isUnitDiff) {
          _manuallyDiscountedItems.add(entry.key);
        }
      }

      // Bước 2: CHẠY TÍNH TOÁN NGẦM (Không gọi setState trong các hàm con này)
      _updateTimeBasedPrices(triggerSetState: false);
      _recalculateCartDiscounts(triggerSetState: false);
      _applyBuyXGetYLogic();
      setState(() {
      });
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
          if (_canChangeTable) ...[
            _buildTableTransferButton(),
            const SizedBox(width: 8),
          ],
          if (_canEditNotes) ...[
            _buildQuickNotesIconButton(),
            const SizedBox(width: 8),
          ],
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
                                items: _displayCart.values
                                    .map((item) => item.toMap())
                                    .toList(),
                                totalAmount: _totalAmount,
                              ),
                              currentUser: widget.currentUser,
                              subtotal: _totalAmount,
                              customer: _selectedCustomer,
                              customerAddress: _customerAddressFromOrder,
                              printBillAfterPayment: _printBillAfterPayment,
                              initialState: _currentOrder != null
                                  ? _paymentStateCache[_currentOrder!.id]
                                  : null,
                              promptForCash: _promptForCash,
                              currentShiftId: _currentShiftId,
                              onCancel: () {
                                setState(() {
                                  _isPaymentView = false;
                                });
                                _isFinalizingPayment = false;
                              },
                              onConfirmPayment: (result) {
                                debugPrint(
                                    ">>> [DESKTOP] Thanh toán thành công.");

                                _hasCompletedPayment = true; // Bật cờ

                                // Dọn dẹp dữ liệu
                                setState(() {
                                  _localChanges.clear();
                                  _cart.clear();
                                  _currentOrder = null;
                                  _isPaymentView = false;
                                });

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
                            ))
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
                      tooltip: 'Lưu đơn',
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
                      groupMatch =
                          (p.productGroup == null || p.productGroup!.isEmpty);
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
                  if (_canChangeTable) _buildTableTransferButton(),
                  if (_canEditNotes) _buildQuickNotesIconButton(),
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
          // [FIX QUAN TRỌNG] Tính lại giảm giá ngay sau khi có thông tin chi tiết khách hàng (Nhóm khách, v.v.)
          _recalculateCartDiscounts();
        }
      });
    } else {
      setState(() {
        _selectedCustomer = null;
        _lastCustomerIdFromOrder = null;
      });
      _recalculateCartDiscounts();
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
                  groupMatch =
                      (p.productGroup == null || p.productGroup!.isEmpty);
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
    final bool isVirtualTable = widget.table.id.startsWith('ship_') ||
        widget.table.id.startsWith('schedule_');

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
                        color: isVirtualTable ? Colors.grey.shade200 : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            // [SỬA] Bọc AbsorbPointer để chặn click nếu là bàn ảo
                            child: AbsorbPointer(
                              absorbing: isVirtualTable,
                              child: Opacity(
                                // Làm mờ nhẹ nếu bị khóa
                                opacity: isVirtualTable ? 0.6 : 1.0,
                                child: CustomerSelector(
                                  currentCustomer: _selectedCustomer,
                                  firestoreService: _firestoreService,
                                  storeId: widget.currentUser.storeId,
                                  onCustomerSelected: _handleCustomerSelection,
                                ),
                              ),
                            ),
                          ),

                          // [SỬA] Logic khóa luôn nút tăng giảm số lượng khách nếu muốn (Optional)
                          // Nếu chỉ muốn khóa đổi tên khách thì giữ nguyên Row dưới,
                          // còn nếu muốn khóa cả số lượng khách thì bọc cả Row này vào AbsorbPointer tương tự.
                          Row(
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                iconSize: 22,
                                icon:
                                    const Icon(Icons.remove, color: Colors.red),
                                onPressed: () => _updateNumberOfCustomers(
                                    _numberOfCustomers - 1),
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
                                onPressed: () => _updateNumberOfCustomers(
                                    _numberOfCustomers + 1),
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
                            color: AppTheme.primaryColor,
                            size: 22,
                          ),
                          onPressed: _addDefaultServiceToCart,
                        ),
                      IconButton(
                        icon: const Icon(Icons.delete_forever,
                            color: Colors.red, size: 22),
                        tooltip: 'Xóa toàn bộ đơn hàng',
                        onPressed: _displayCart.isEmpty
                            ? null
                            : _confirmClearEntireCart,
                      ),
                    ],
                  )
                ],
              );
            },
          ),
        ),
        LayoutBuilder(builder: (context, constraints) {
          return Builder(
            builder: (context) {
              var guestPhone = _customerPhoneFromOrder;
              var guestAddress = _customerAddressFromOrder;
              final guestNote = _customerNoteFromOrder;

              final bool isShipOrder = widget.table.id.startsWith('ship_');
              final bool isScheduleOrder =
                  widget.table.id.startsWith('schedule_');
              final bool isOnlineOrder = isShipOrder || isScheduleOrder;

              if (!isOnlineOrder) {
                guestPhone = null;
                guestAddress = null;
              }

              // 1. Không hiển thị tên cho đơn online (Đã bị loại bỏ bởi logic trên)
              final bool showPhone =
                  (guestPhone != null && guestPhone.isNotEmpty);
              // 2. Đổi icon cho đơn đặt lịch
              final bool showAddressOrTime =
                  (guestAddress != null && guestAddress.isNotEmpty);

              // 3. Hiển thị ghi chú
              final bool showNote = (guestNote != null && guestNote.isNotEmpty);

              final bool hasInfo = showPhone || showAddressOrTime || showNote;

              if (hasInfo) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  // Padding 16
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    width: double.infinity,
                    // Mở rộng hết cỡ (do padding bên ngoài)
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withAlpha(20),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showPhone || showAddressOrTime || showNote)
                          // 4. Dùng Wrap để SĐT, Địa chỉ, Ghi chú tự xuống dòng
                          Wrap(
                            spacing: 16.0, // Khoảng cách ngang
                            runSpacing: 8.0, // Khoảng cách dọc nếu xuống dòng
                            children: [
                              if (showPhone)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  // Quan trọng
                                  children: [
                                    Icon(Icons.phone_outlined,
                                        size: 16, color: Colors.grey.shade700),
                                    const SizedBox(width: 8),
                                    Text(guestPhone,
                                        style: textTheme.bodyMedium),
                                  ],
                                ),
                              if (showAddressOrTime)
                                Builder(builder: (context) {
                                  final IconData addressIcon = isScheduleOrder
                                      ? Icons.calendar_month_outlined
                                      : Icons.location_on_outlined;
                                  return Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(addressIcon,
                                          size: 16,
                                          color: Colors.grey.shade700),
                                      // Không còn lỗi Undefined
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                              maxWidth:
                                                  constraints.maxWidth - 60),
                                          child: Text(guestAddress!,
                                              style: textTheme.bodyMedium),
                                        ),
                                      )
                                    ],
                                  );
                                }),
                              if (showNote)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Icon(Icons.note_alt_outlined,
                                        size: 16, color: Colors.red),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            maxWidth:
                                                constraints.maxWidth - 60),
                                        child: Text(guestNote,
                                            style: textTheme.bodyMedium
                                                ?.copyWith(color: Colors.red)),
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
        }),
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
        // --- ĐOẠN ĐÃ SỬA ---
        Container(
          padding: const EdgeInsets.all(16.0),
          decoration:
              BoxDecoration(color: Theme.of(context).cardColor, boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ]),
          child: Column(
            children: [
              if (!_isPaymentView) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // [SỬA] Thêm hiển thị tổng số lượng món
                    Text(
                        'Tổng cộng (${formatNumber(_displayCart.values.fold(0.0, (tong, item) => tong + item.quantity))}):',
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
                        onPressed: widget.table.id.startsWith('schedule_')
                            ? () async {
                          await _saveOrder();
                          ToastService().show(
                              message: "Đã lưu thông tin đặt bàn.",
                              type: ToastType.success);
                        }
                            : (_hasUnsentItems ? _sendToKitchen : null),
                        child: const Text('LƯU ĐƠN'),
                      ),
                    ),
                    if (_canSell) ...[
                      const SizedBox(width: 8),
                      if (_allowProvisionalBill && !widget.table.id.startsWith('schedule_')) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _displayCart.isNotEmpty
                                ? _handlePrintProvisionalBill
                                : null,
                            child: const Text('KIỂM MÓN'),
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
                          // SỬA: Phân biệt nút Thanh toán và Nhận khách
                          onPressed: _displayCart.isNotEmpty
                              ? (widget.table.id.startsWith('schedule_')
                              ? _handleBookingCheckIn // Hàm mới xử lý nhận khách
                              : _handlePayment)
                              : null,
                          child: _isPaymentLoading
                              ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                              : Text(widget.table.id.startsWith('schedule_')
                              ? 'NHẬN KHÁCH'
                              : 'THANH TOÁN'),
                        ),
                      ),
                    ],
                  ],
                ),
              ]
            ],
          ),
        )
      ],
    );
  }

  Future<void> _handleBookingCheckIn() async {
    final saveSuccess = await _saveOrder();
    if (!saveSuccess) {
      ToastService().show(message: "Lỗi lưu đơn, không thể nhận khách lúc này.", type: ToastType.error);
      return;
    }
    if (!mounted) return;
    if (_currentOrder == null) return;

    // 2. Mở màn hình chuyển bàn với chế độ "Nhận khách" (chỉ hiện tab chuyển)
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TableTransferScreen(
          currentUser: widget.currentUser,
          sourceOrder: _currentOrder!,
          sourceTable: widget.table,
          isBookingCheckIn: true,
        ),
      ),
    );

    // 3. Xử lý sau khi chuyển thành công (Tự động in bếp)
    if (result != null && result is Map && result['success'] == true) {
      final TableModel targetTable = result['targetTable'];
      if (widget.table.id.startsWith('schedule_')) {
        try {
          final webOrderId = widget.table.id.replaceFirst('schedule_', '');
          await _firestoreService.updateWebOrderStatus(webOrderId, 'completed');
        } catch (e) {
          debugPrint("Lỗi cập nhật trạng thái Web Order: $e");
        }
      }
      await _processAutoKitchenPrintForTargetTable(targetTable);

      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _processAutoKitchenPrintForTargetTable(TableModel targetTable) async {
    try {
      // 1. Lấy đơn hàng mới tại bàn đích
      final targetOrderSnapshot = await _firestoreService.getOrderStreamForTable(targetTable.id).first;
      if (!targetOrderSnapshot.exists) return;

      final targetOrderData = targetOrderSnapshot.data() as Map<String, dynamic>;
      final targetOrder = OrderModel.fromMap(targetOrderData);

      // 2. Lọc các món chưa in (sentQuantity < quantity)
      // Lưu ý: Do chuyển từ Booking (chưa update sentQuantity) sang, nên hầu hết sẽ thỏa mãn
      final List<OrderItem> itemsToPrint = [];
      final List<Map<String, dynamic>> updatedItemsMap = [];
      bool hasUpdates = false;

      for (var itemMap in targetOrder.items) {
        final item = OrderItem.fromMap(itemMap as Map<String, dynamic>, allProducts: _menuProducts);

        if (item.status != 'cancelled' && item.quantity > item.sentQuantity) {
          // Thêm vào danh sách cần in (chỉ in phần chênh lệch)
          final diff = item.quantity - item.sentQuantity;
          if (diff > 0) {
            final printItem = item.copyWith(quantity: diff); // Chỉ in số lượng mới
            itemsToPrint.add(printItem);
          }

          // Cập nhật sentQuantity trong DB để không in lại lần sau
          updatedItemsMap.add(item.copyWith(sentQuantity: item.quantity).toMap());
          hasUpdates = true;
        } else {
          updatedItemsMap.add(itemMap);
        }
      }

      if (itemsToPrint.isEmpty) return;

      // 3. Gửi lệnh in
      if (!_skipKitchenPrint) {
        final printPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': targetTable.tableName, // Tên bàn thật
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': itemsToPrint.map((e) => {'isCancel': false, ...e.toMap()}).toList(),
          'printType': 'add',
          // Có thể thêm customerName nếu cần thiết
          'customerName': targetOrder.customerName
        };

        // In bếp
        PrintQueueService().addJob(PrintJobType.kitchen, printPayload);

        // In tem (nếu bật)
        if (_printLabelOnKitchen) {
          final labelPayload = {
            'storeId': widget.currentUser.storeId,
            'tableName': targetTable.tableName,
            'items': itemsToPrint.map((e) => {'isCancel': false, ...e.toMap()}).toList(),
            'labelWidth': _labelWidth,
            'labelHeight': _labelHeight,
          };
          PrintQueueService().addJob(PrintJobType.label, labelPayload);
        }

        ToastService().show(message: "Đã tự động gửi báo chế biến cho bàn ${targetTable.tableName}", type: ToastType.success);
      }

      // 4. Cập nhật lại đơn hàng trên Firestore (Set sentQuantity = quantity)
      if (hasUpdates) {
        final orderRef = _firestoreService.getOrderReference(targetOrder.id);
        await orderRef.update({
          'items': updatedItemsMap,
          'version': FieldValue.increment(1),
        });
      }

    } catch (e) {
      debugPrint("Lỗi tự động in bếp sau khi nhận khách: $e");
      ToastService().show(message: "Lỗi in bếp tự động: $e", type: ToastType.error);
    }
  }



  void _handleCustomerSelection(CustomerModel? newCustomer) {
    if (_selectedCustomer?.id == newCustomer?.id) return;
    _selectedCustomer = newCustomer;

    _recalculateCartDiscounts(triggerSetState: false);

    setState(() {});

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

    final serviceProduct =
        _menuProducts.firstWhereOrNull((product) => product.id == serviceId);

    if (serviceProduct != null) {
      if (serviceProduct.serviceSetup?['isTimeBased'] == true) {
        final alreadyInCart = _displayCart.values
            .any((item) => item.product.id == serviceProduct.id);
        if (alreadyInCart) {
          ToastService().show(
              message: "Dịch vụ này đã có trong giỏ hàng.",
              type: ToastType.warning);
          return;
        }
      }
      await _addItemToCart(serviceProduct);
    } else {
      ToastService().show(
          message:
              'Không tìm thấy dịch vụ mặc định ($serviceId) trong thực đơn.',
          type: ToastType.error);
    }
  }

  Widget _buildSearchBar() {
    final bool shouldAutoFocus =
        !_isPaymentView && !Platform.isAndroid && !Platform.isIOS;

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
                icon: const Icon(Icons.clear,
                    size: 20, color: AppTheme.primaryColor),
                onPressed: () {
                  _searchController.clear();
                  _searchFocusNode.requestFocus();
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
    final hasSentItems = _cart.values.any((item) => item.sentQuantity > 0);

    if (hasSentItems && !_canCancelItem) {
      ToastService().show(
          message: "Đơn đã lưu. Bạn không có quyền hủy đơn.",
          type: ToastType.warning);
      return;
    }

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
      if (oldItem.product.serviceSetup?['isTimeBased'] == true) continue;
      final latestProduct = latestProductMap[oldItem.product.id];

      if (latestProduct != null) {
        if (oldItem.price != latestProduct.sellPrice ||
            oldItem.product.productName != latestProduct.productName) {
          hasPriceChanges = true;

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

    if (item != null && item.note != null && item.note!.contains("Tặng kèm")) {
      ToastService().show(
          message: "Vui lòng xóa món mua chính, quà tặng sẽ tự hủy.",
          type: ToastType.warning);
      return;
    }

    if (item == null) return;

    if (item.sentQuantity > 0 && !_canCancelItem) {
      ToastService().show(
          message: "Bạn không có quyền hủy món đã lưu.",
          type: ToastType.warning);
      return;
    }

    final bool isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;
    final bool wasSaved = _cart.containsKey(cartId);

    if (!wasSaved) {
      setState(() {
        _localChanges.remove(cartId);
      });
      _applyBuyXGetYLogic();
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận Hủy'),
        content:
            Text('Bạn có chắc muốn hủy "${item.product.productName}" không?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Không')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Xác Nhận Hủy',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed != true) return;

    final bool needsCancelPrint = item.sentQuantity > 0 && !isTimeBased;
    Map<String, dynamic>? cancelPayload;

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

      if (needsCancelPrint && _currentOrder != null) {
        final itemPrintMap = itemToCancel.toMap();
        itemPrintMap['quantity'] = item.sentQuantity;
        cancelPayload = {
          'storeId': widget.currentUser.storeId,
          'tableName': _currentOrder!.tableName,
          'userName': widget.currentUser.name ?? 'Unknown',
          'items': [itemPrintMap],
        };
      }

      setState(() {
        _localChanges[cartId] = itemToCancel.copyWith(
          quantity: 0,
          status: 'cancelled',
        );
      });

      _applyBuyXGetYLogic();

      final success = await _saveOrder();

      if (success && cancelPayload != null) {
        PrintQueueService().addJob(PrintJobType.cancel, cancelPayload);
        ToastService()
            .show(message: "Đã gửi lệnh hủy món.", type: ToastType.success);
      }
    } catch (e) {
      debugPrint("Lỗi khi hủy món: $e");
      ToastService().show(
          message: "Lỗi khi hủy món: ${e.toString()}", type: ToastType.error);
    }
  }

  Future<bool> _saveOrder({bool onlyTimeBasedUpdates = false}) async {
    // [FIX TUYỆT ĐỐI] Nếu đã thanh toán, CHẶN MỌI THAO TÁC LƯU
    if (_hasCompletedPayment) {
      return true;
    }

    final bool useMergeStrategy =
        kIsWeb || !Platform.isIOS && !Platform.isAndroid;
    if (useMergeStrategy) {
      return await _saveOrderWithMerge(
          onlyTimeBasedUpdates: onlyTimeBasedUpdates);
    } else {
      return await _saveOrderWithTransaction(
          onlyTimeBasedUpdates: onlyTimeBasedUpdates);
    }
  }

  Future<bool> _saveOrderWithMerge({bool onlyTimeBasedUpdates = false}) async {
    if (_hasCompletedPayment) return true;
    if (_currentOrder != null &&
        ['paid', 'cancelled'].contains(_currentOrder!.status)) {
      return true;
    }

    // [FIX 2] Lọc dữ liệu trước khi lưu
    Map<String, OrderItem> localChangesToProcess;
    if (onlyTimeBasedUpdates) {
      // Chỉ lấy các món tính giờ từ bộ nhớ tạm
      localChangesToProcess = Map.from(_localChanges)
        ..removeWhere(
            (key, item) => item.product.serviceSetup?['isTimeBased'] != true);
    } else {
      // Lấy tất cả (hành vi cũ)
      localChangesToProcess = Map<String, OrderItem>.from(_localChanges);
    }

    if (localChangesToProcess.isEmpty) {
      return true;
    }

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
        finalCart = {for (var item in grouped.values) item.lineId: item};
        return (items: itemsToSave, total: totalAmount);
      }

      if (!serverSnapshot.exists ||
          ['paid', 'cancelled'].contains(
              (serverSnapshot.data() as Map<String, dynamic>?)?['status'])) {
        final result = groupAndCalculate(localChangesToProcess);
        if (result.items.isEmpty) return true;

        final currentVersion = ((serverSnapshot.data()
                    as Map<String, dynamic>?)?['version'] as num?)
                ?.toInt() ??
            0;
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
          'createdByName':
              widget.currentUser.name ?? widget.currentUser.phoneNumber,
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
        mergedItems.addAll(localChangesToProcess);
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
          if (onlyTimeBasedUpdates) {
            _localChanges.removeWhere((key, item) =>
                item.product.serviceSetup?['isTimeBased'] == true);
          } else {
            _localChanges.clear();
          }

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

  Future<bool> _saveOrderWithTransaction(
      {bool onlyTimeBasedUpdates = false}) async {
    if (_hasCompletedPayment) return true;
    if (_currentOrder != null &&
        ['paid', 'cancelled'].contains(_currentOrder!.status)) {
      return true;
    }
    if (_localChanges.isEmpty) return true;

    Map<String, OrderItem> localChangesToProcess;
    if (onlyTimeBasedUpdates) {
      localChangesToProcess = Map.from(_localChanges)
        ..removeWhere(
            (key, item) => item.product.serviceSetup?['isTimeBased'] != true);
    } else {
      localChangesToProcess = Map<String, OrderItem>.from(_localChanges);
    }

    if (localChangesToProcess.isEmpty) return true;

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
          Map<String, OrderItem> finalCart =
              Map<String, OrderItem>.from(localChangesToProcess);
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
          mergedItems.addAll(localChangesToProcess);

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
              'items':
                  mergedByGroupKey.values.map((item) => item.toMap()).toList(),
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
            finalCartAfterSave = {
              for (var item in mergedByGroupKey.values) item.lineId: item
            };
          }
        }
      });

      if (mounted) {
        setState(() {
          if (finalCartAfterSave.isEmpty) {
            _currentOrder = null;
          }
          // Chỉ xóa những món đã xử lý
          if (onlyTimeBasedUpdates) {
            _localChanges.removeWhere((key, item) =>
                item.product.serviceSetup?['isTimeBased'] == true);
          } else {
            _localChanges.clear();
          }

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
              'Một thiết bị khác vừa lưu thay đổi. Vui lòng kiểm tra lại đơn hàng và bấm "LƯU ĐƠN" hoặc "THANH TOÁN" lại một lần nữa.'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
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
            'Trong đơn hàng có sản phẩm CHƯA LƯU. Nếu thoát, các món này sẽ bị xóa khỏi đơn hàng!'),
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

    // Tính tổng số lượng món này đã chọn trong giỏ
    final cartItemsForProduct = _displayCart.values
        .where((item) => item.product.id == product.id)
        .toList();
    final quantityInCart = cartItemsForProduct.fold<double>(
        0.0, (total, item) => total + item.quantity);

    // Số lượng đã gửi bếp (để hiện nút xóa nếu chưa gửi)
    final sentQuantity = cartItemsForProduct.fold<double>(
        0.0, (total, item) => total + item.sentQuantity);

    return GestureDetector(
      onTap: () => _addItemToCart(product),
      child: Stack(
        clipBehavior: Clip.none, // Để badge hiện ra ngoài nếu cần
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Tên món (Trên cùng - Giống Retail)
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
                // 2. Hình ảnh
                Expanded(
                  child: (product.imageUrl != null &&
                          product.imageUrl!.isNotEmpty)
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4.0),
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
                          size: 40, color: Colors.grey),
                ),
                // 3. Giá & Tồn kho
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (showStock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            NumberFormat('#,##0.##').format(product.stock),
                            style: TextStyle(
                              color: Colors.grey[700],
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          formatNumber(product.sellPrice),
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

          // [MỚI] Badge Số lượng (Góc phải trên - Giống Retail)
          if (quantityInCart > 0)
            Positioned(
              top: -6,
              right: -6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3)
                  ],
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Center(
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
            ),

          // Nút Xóa nhanh trên Mobile (Chỉ hiện nếu chưa gửi bếp)
          if (isMobile && quantityInCart > sentQuantity)
            Positioned(
              top: -6,
              left: -6,
              child: GestureDetector(
                onTap: () => _clearProductFromCart(product.id),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade700,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 3)
                    ],
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 16),
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

    // --- 1. TÍNH TOÁN CÁC GIÁ TRỊ HIỂN THỊ ---

    // Lấy GIÁ NIÊM YẾT CHUẨN
    double originalUnitPrice =
    _getBasePriceForUnit(item.product, item.selectedUnit);
    // Giá đang bán (có thể là giá đã sửa tay đơn giá)
    double sellingPrice = item.price;

    // Tính giá sau tăng/giảm để hiển thị ở cột Thành tiền
    double discountedUnitPrice = sellingPrice;

    // [SỬA LỖI] Thay điều kiện > 0 thành != 0 để chấp nhận cả Tăng giá (số âm)
    if (item.discountValue != null && item.discountValue != 0) {
      if (item.discountUnit == '%') {
        // Công thức: Giá * (1 - %/100).
        // Ví dụ Tăng 10% (-10): Giá * (1 - (-0.1)) = Giá * 1.1 -> Đúng
        discountedUnitPrice = sellingPrice * (1 - item.discountValue! / 100);
      } else {
        // Công thức: Giá - Tiền.
        // Ví dụ Tăng 10k (-10000): Giá - (-10000) = Giá + 10000 -> Đúng
        discountedUnitPrice = sellingPrice - item.discountValue!;
      }
    }

    // Làm tròn
    discountedUnitPrice = discountedUnitPrice.roundToDouble();
    if (discountedUnitPrice < 0) discountedUnitPrice = 0;

    // [SỬA LỖI] Logic hiển thị giá gốc gạch ngang (áp dụng cho cả Tăng và Giảm)
    bool showOriginalPrice =
        (item.discountValue != null && item.discountValue != 0) ||
            (sellingPrice != originalUnitPrice);

    final String taxText = _getTaxDisplayString(item.product);
    final bool isGift = item.note != null && item.note!.contains("Tặng kèm");
    return Card(
      child: InkWell(
        onTap: () {
          if (isGift) {
            ToastService().show(
                message: "Đây là quà tặng kèm, không thể chỉnh sửa trực tiếp.",
                type: ToastType.warning);
            return;
          }
          _showEditItemDialog(cartId, item);
        },
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === DÒNG 1: HEADER ===
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
                      TextSpan(
                        children: [
                          // Tên món
                          TextSpan(
                            text: item.product.productName,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isCancelled
                                  ? Colors.grey
                                  : AppTheme.textColor,
                              decoration: isCancelled
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                            ),
                          ),
                          // Đơn vị
                          if (item.selectedUnit.isNotEmpty)
                            TextSpan(
                              text: ' (${item.selectedUnit}) ',
                              style: textTheme.bodyMedium?.copyWith(
                                color: isCancelled
                                    ? Colors.grey
                                    : Colors.grey.shade700,
                              ),
                            ),
                          // Thuế
                          if (taxText.isNotEmpty)
                            TextSpan(
                              text: '$taxText ',
                              style: textTheme.bodyMedium?.copyWith(
                                color: Colors.blue,
                              ),
                            ),

                          // --- [SỬA ĐỔI]: GIAO DIỆN GIÁ GỐC GIỐNG RETAIL ---
                          if (showOriginalPrice)
                            TextSpan(
                              text: formatNumber(originalUnitPrice),
                              style: textTheme.bodyMedium?.copyWith(
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.red,
                                color: Colors.red,
                              ),
                            ),

                          if (item.discountValue != null && item.discountValue != 0) ...[
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Builder(
                                  builder: (context) {
                                    // Tính toán logic màu sắc ở đây
                                    final double val = item.discountValue!;
                                    final bool isIncrease = val < 0;
                                    final double absVal = val.abs();

                                    final Color badgeBgColor = isIncrease ? Colors.green.shade50 : Colors.red.shade50;
                                    final Color badgeBorderColor = isIncrease ? Colors.green.shade100 : Colors.red.shade100;
                                    final Color badgeTextColor = isIncrease ? Colors.green.shade700 : Colors.red;
                                    final String prefix = isIncrease ? '+' : '-';

                                    return Container(
                                      margin: const EdgeInsets.only(left: 6),
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                          color: badgeBgColor,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: badgeBorderColor)
                                      ),
                                      child: Text(
                                        item.discountUnit == '%'
                                            ? "$prefix${formatNumber(absVal)}%"
                                            : "$prefix${formatNumber(absVal)}",
                                        style: TextStyle(
                                            color: badgeTextColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    );
                                  }
                              ),
                            ),
                          ],
                        ],
                      ),
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

              if (item.toppings.isNotEmpty ||
                  (item.note != null && item.note!.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (item.toppings.isNotEmpty)
                        _buildToppingsList(item.toppings, currencyFormat),
                      if (item.note != null && item.note!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '${item.note}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.red,
                                ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
              // === DÒNG 2: GIÁ ĐÃ GIẢM x SL = THÀNH TIỀN ===
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Đơn giá ĐÃ GIẢM (Hiển thị giá cuối cùng khách phải trả)
                  SizedBox(
                    width: 100,
                    child: Text(
                      currencyFormat.format(discountedUnitPrice),
                      style: textTheme.bodyMedium?.copyWith(
                        color: isCancelled ? Colors.grey : null,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  // Bộ đếm số lượng
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
                                border: Border.all(
                                    color: Colors.grey.shade300, width: 0.5)),
                            alignment: Alignment.center,
                            constraints: const BoxConstraints(
                              minWidth: 40,
                              maxWidth: 65,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4.0, vertical: 1.0),
                            child: Text(
                              formatNumber(item.quantity),
                              style: textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: isCancelled ? Colors.grey : null,
                                decoration: isCancelled
                                    ? TextDecoration.lineThrough
                                    : TextDecoration.none,
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

                  // Thành tiền
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

    // 1. Lấy kết quả tính toán khối thời gian gốc
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

    // --- 2. CHUẨN BỊ THÔNG SỐ KHUYẾN MÃI ---
    String badgeText = '';

    // [SỬA] Khai báo mặc định để tránh lỗi Undefined name
    double percentDiscount = 0;
    double reductionPerHour = 0;

    Color badgeColor = Colors.red;
    Color badgeBgColor = Colors.red.shade50;
    Color badgeBorderColor = Colors.red.shade100;

    if (item.discountValue != null && item.discountValue != 0) {
      final double val = item.discountValue!;
      final bool isIncrease = val < 0; // Nhỏ hơn 0 là Tăng giá (Số âm)
      final double absVal = val.abs();

      // Setup màu sắc
      badgeColor = isIncrease ? Colors.green.shade700 : Colors.red;
      badgeBgColor = isIncrease ? Colors.green.shade50 : Colors.red.shade50;
      badgeBorderColor = isIncrease ? Colors.green.shade100 : Colors.red.shade100;

      final String prefix = isIncrease ? '+' : '-';

      if (item.discountUnit == '%') {
        double rawPercent = absVal;
        if (rawPercent > 100) rawPercent = 100;

        // [QUAN TRỌNG] Nếu tăng giá, percentDiscount phải là số âm để công thức (1 - discount) thành (1 - (-x)) = (1 + x)
        percentDiscount = (isIncrease ? -rawPercent : rawPercent) / 100.0;

        badgeText = "$prefix${formatNumber(rawPercent)}%";
      } else {
        // Nếu tăng giá, reductionPerHour là số âm
        reductionPerHour = (isIncrease ? -absVal : absVal);

        badgeText = "$prefix${formatNumber(absVal)}/h";
      }
    }

    // [QUAN TRỌNG] Biến này dùng để cộng dồn tiền hiển thị
    double totalDisplayCost = 0;

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
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: item.product.productName,
                          style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textColor),
                        ),
                        if (badgeText.isNotEmpty)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: badgeBgColor, // Dùng biến đã tính
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: badgeBorderColor)), // Dùng biến đã tính
                              child: Text(
                                badgeText,
                                style: TextStyle(
                                    color: badgeColor, // Dùng biến đã tính
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
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
                    child: Text('Ghi chú: ${item.note}',
                        style:
                            textTheme.bodyMedium?.copyWith(color: Colors.red)),
                  ),
                ),

              // === DÒNG 2: CHI TIẾT (BLOCKS) ===
              if (result.blocks.isNotEmpty) ...[
                ...result.blocks.map((block) {
                  final isLastBlock = block == result.blocks.last;
                  final blockEndTimeToShow =
                      isLastBlock ? billableEndTime : block.endTime;

                  double displayRate = block.ratePerHour;
                  double displayCost = 0;

                  // [SỬA LỖI TẠI ĐÂY - LOGIC HIỂN THỊ]
                  bool isFixedPriceBlock =
                      (block.ratePerHour == 0 && block.cost > 0);

                  if (isFixedPriceBlock) {
                    displayCost = block.cost;
                  } else {
                    // Block tính giờ -> Áp dụng discount
                    // [SỬA] Bây giờ percentDiscount và reductionPerHour đã được định nghĩa ở scope ngoài
                    if (item.discountUnit == '%') {
                      displayRate = block.ratePerHour * (1 - percentDiscount);
                    } else {
                      displayRate = block.ratePerHour - reductionPerHour;
                    }
                    if (displayRate < 0) displayRate = 0;
                    displayCost = (displayRate / 60.0) * block.minutes;
                  }

                  // Làm tròn số hiển thị
                  displayRate = displayRate.roundToDouble();
                  displayCost = displayCost.roundToDouble();

                  totalDisplayCost += displayCost;

                  String detailText;
                  if (isFixedPriceBlock) {
                    detailText =
                        "[Min] ${formatNumber(displayCost)}đ/${formatMinutes(block.minutes)}";
                  } else {
                    detailText =
                        "${formatMinutes(block.minutes)} x ${formatNumber(displayRate)}đ/h";
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: isDesktop
                        ? Row(
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
                                    detailText,
                                    style: textTheme.bodyMedium,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  currencyFormat.format(displayCost),
                                  textAlign: TextAlign.end,
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          )
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
                                    Text(detailText,
                                        style: textTheme.bodyMedium),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      currencyFormat.format(displayCost),
                                      style: textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ]),
                            ],
                          ),
                  );
                }),
                const Divider(height: 8, thickness: 0.5, color: Colors.grey),
              ],

              // === FOOTER (HIỂN THỊ TỔNG) ===
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
                                  fontWeight: FontWeight.bold,
                                  color: Colors.red)),
                          const TextSpan(
                              text: ' - ',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey)),
                          TextSpan(
                              text: timeFormat.format(billableEndTime),
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.primaryColor)),
                        ],
                      ),
                    ),

                    // [FIX CHÍNH] HIỂN THỊ totalDisplayCost THAY VÌ item.subtotal
                    // Để đảm bảo con số này khớp tuyệt đối với các dòng bên trên cộng lại
                    Text(
                      currencyFormat.format(totalDisplayCost),
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
      _staffList =
          await _firestoreService.getUsersByStore(widget.currentUser.storeId);
    } catch (e) {
      debugPrint("Lỗi tải danh sách nhân viên: $e");
      ToastService()
          .show(message: "Lỗi tải danh sách nhân viên.", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoadingStaff = false);
      }
    }
  }

  Future<void> _showEditItemDialog(String cartId, OrderItem item) async {
    final relevantNotes = _quickNotes.where((note) {
      return note.productIds.isEmpty ||
          note.productIds.contains(item.product.id);
    }).toList();

    // 1. Chuẩn bị dữ liệu tính giờ (để lấy số giờ chơi)
    TimePricingResult? timeResult;
    if (item.product.serviceSetup?['isTimeBased'] == true) {
      timeResult = _timeBasedDataCache[item.lineId] ??
          TimeBasedPricingService.calculatePriceWithBreakdown(
            product: item.product,
            startTime: item.addedAt,
            isPaused: item.isPaused,
            pausedAt: item.pausedAt,
            totalPausedDurationInSeconds: item.totalPausedDurationInSeconds,
          );
    }

    // 2. Mở Dialog và chờ kết quả
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
      final newCommissionStaff =
          result['commissionStaff'] as Map<String, String?>;
      final double newQuantity = result['quantity'] as double;
      final Timestamp? newStartTime = result['startTime'] as Timestamp?;

      // LẤY GIÁ TRỊ THÔ TỪ DIALOG (Người dùng nhập gì lấy nấy)
      double rawInputVal = result['discountValue'] as double;
      String newDiscountUnit = result['discountUnit'] as String;

      double finalDiscountValToSave = 0;

      // --- LOGIC XỬ LÝ ĐƠN GIẢN HÓA ---

      if (newDiscountUnit == '%') {
        // TRƯỜNG HỢP 1: GIẢM THEO %
        // Người dùng nhập 20 -> Lưu 20. Không quan tâm trước đó là gì.
        finalDiscountValToSave = rawInputVal;

        // Chặn lỗi nhập quá 100%
        if (finalDiscountValToSave > 100) finalDiscountValToSave = 100;
      } else {
        // TRƯỜNG HỢP 2: GIẢM THEO VNĐ
        if (timeResult != null) {
          finalDiscountValToSave = rawInputVal;
        } else {
          finalDiscountValToSave = rawInputVal;
        }
      }
      // ----------------------------------

      if (newQuantity < item.sentQuantity) {
        ToastService().show(
            message:
                "Không thể đặt SL (${formatNumber(newQuantity)}) ít hơn số đã lưu (${formatNumber(item.sentQuantity)}).",
            type: ToastType.warning,
            duration: const Duration(seconds: 3));
        return;
      }

      // Cập nhật giá mới nhất (nếu là dịch vụ)
      double currentPrice = item.price;
      List<TimeBlock> currentBlocks = item.priceBreakdown;
      if (timeResult != null) {
        currentPrice = timeResult.totalPrice;
        currentBlocks = timeResult.blocks;
      } else {
        currentPrice = result['price'] as double;
      }
      if (finalDiscountValToSave == 0) {
        _manuallyDiscountedItems.remove(cartId);
      } else {
        _manuallyDiscountedItems.add(cartId);
      }
      _localChanges[cartId] = item.copyWith(
        price: currentPrice,
        priceBreakdown: currentBlocks,
        quantity: newQuantity,
        discountValue: finalDiscountValToSave,
        // Lưu giá trị đã xử lý
        discountUnit: newDiscountUnit,
        selectedUnit: result['selectedUnit'],
        note: () => newNote,
        commissionStaff: () =>
            newCommissionStaff.isNotEmpty ? newCommissionStaff : null,
        addedAt: newStartTime ?? item.addedAt,
      );
      if (timeResult != null && newStartTime != null) {
        _updateTimeBasedPrices(triggerSetState: false);
      }
      _applyBuyXGetYLogic();
    });
  }

  double _getBasePriceForUnit(ProductModel product, String selectedUnit) {
    if ((product.unit ?? '') == selectedUnit) {
      return product.sellPrice;
    }

    final additionalUnitData = product.additionalUnits.firstWhereOrNull(
        (unitData) => (unitData['unitName'] as String?) == selectedUnit);

    if (additionalUnitData != null) {
      return (additionalUnitData['sellPrice'] as num?)?.toDouble() ??
          product.sellPrice;
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
    final String noteText =
        _selectedQuickNotes.map((n) => n.noteText).join(', ');

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
        text: (NumberFormat('#,##0.##')
            .format(_selectedToppings[topping.id] ?? 0)));
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
