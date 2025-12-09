import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/customer_model.dart';
import '../../models/order_model.dart';
import '../../models/user_model.dart';
import '../../services/toast_service.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../models/print_job_model.dart';
import '../../services/print_queue_service.dart';
import '../../widgets/app_dropdown.dart';
import 'package:flutter/services.dart';
import '../../models/voucher_model.dart';
import '../../services/inventory_service.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/payment_method_model.dart';
import 'vietqr_popup.dart';
import '../../services/settings_service.dart';
import '../../services/e_invoice_service.dart';
import '../invoice/e_invoice_provider.dart';
import '../../screens/tax_management_screen.dart'
    show kDirectRates, kDeductionRates;
import 'package:intl/intl.dart';
import 'dart:math';
import '../../models/surcharge_model.dart';
import '../../services/pricing_service.dart';

class PaymentState {
  final double discountAmount;
  final bool isDiscountPercent;
  final String voucherCode;
  final double pointsUsed;
  final List<SurchargeItem> surcharges;

  PaymentState({
    this.discountAmount = 0,
    this.isDiscountPercent = false,
    this.voucherCode = '',
    this.pointsUsed = 0,
    this.surcharges = const [],
  });
}

class PaymentResult {
  final double totalPayable;
  final double discountAmount;
  final String discountType;
  final List<SurchargeItem> surcharges;
  final double taxPercent;
  final double totalTaxAmount;
  final double totalTncnAmount;
  final Map<String, double> payments;
  final double customerPointsUsed;
  final double changeAmount;
  final bool printReceipt;
  final Map<String, dynamic>? bankDetailsForPrinting;

  PaymentResult({
    required this.totalPayable,
    required this.discountAmount,
    required this.discountType,
    required this.surcharges,
    required this.taxPercent,
    required this.totalTaxAmount,
    required this.totalTncnAmount,
    required this.payments,
    required this.customerPointsUsed,
    required this.changeAmount,
    required this.printReceipt,
    this.bankDetailsForPrinting,
  });
}

class SurchargeItem {
  String name;
  double amount;
  bool isPercent;

  SurchargeItem(
      {required this.name, required this.amount, this.isPercent = false});
}

class PaymentScreen extends StatelessWidget {
  final OrderModel order;
  final UserModel currentUser;
  final CustomerModel? customer;
  final String? customerAddress;
  final double subtotal;
  final bool printBillAfterPayment;
  final bool showPricesOnReceipt;
  final PaymentState? initialState;
  final bool promptForCash;
  final bool isRetailMode;
  final String? initialPaymentMethodId;

  static void clearCache() {
    _PaymentPanelState.resetCache();
  }

  const PaymentScreen({
    super.key,
    required this.order,
    required this.currentUser,
    this.customer,
    this.customerAddress,
    required this.subtotal,
    this.printBillAfterPayment = true,
    this.showPricesOnReceipt = true,
    this.initialState,
    this.promptForCash = true,
    this.isRetailMode = false,
    this.initialPaymentMethodId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Thanh toán: ${order.tableName}')),
      body: _PaymentPanel(
        order: order,
        currentUser: currentUser,
        subtotal: subtotal,
        customer: customer,
        customerAddress: customerAddress,
        printBillAfterPayment: printBillAfterPayment,
        showPricesOnReceipt: showPricesOnReceipt,
        initialState: initialState,
        promptForCash: promptForCash,
        isRetailMode: isRetailMode,
        initialPaymentMethodId: initialPaymentMethodId,
        onCancel: () {},
        onConfirmPayment: (result) {},
      ),
    );
  }

  static Future<void> preloadData(String storeId, String ownerUid) async {
    debugPrint(">>> [Preload] Bắt đầu tải trước dữ liệu thanh toán...");

    if (_PaymentPanelState._cachedPaymentMethods != null &&
        _PaymentPanelState._cachedStoreTaxSettings != null &&
        _PaymentPanelState._cachedDefaultMethodId != null &&
        _PaymentPanelState._cachedStoreDetails != null &&
        _PaymentPanelState._cachedStoreSettingsObj != null &&
        _PaymentPanelState._cachedSurcharges != null) {
      debugPrint(">>> [Preload] Dữ liệu đã có sẵn, bỏ qua.");
      return;
    }

    try {
      final firestore = FirestoreService();

      // 1. Tải PTTT
      if (_PaymentPanelState._cachedPaymentMethods == null) {
        final snapshot = await firestore.getPaymentMethods(storeId).first;
        final methods = snapshot.docs
            .map((doc) => PaymentMethodModel.fromFirestore(doc))
            .toList();

        final cashMethod = PaymentMethodModel(
          id: 'cash_default',
          storeId: storeId,
          name: 'Tiền mặt',
          type: PaymentMethodType.cash,
          active: true,
        );
        _PaymentPanelState._cachedPaymentMethods = [cashMethod, ...methods];
      }

      // 2. Tải các thông tin khác (Thuế, Voucher, Cài đặt, Thông tin Shop)
      if (_PaymentPanelState._cachedStoreTaxSettings == null ||
          _PaymentPanelState._cachedDefaultMethodId == null ||
          _PaymentPanelState._cachedStoreDetails == null) {
        final results = await Future.wait([
          firestore.getStoreTaxSettings(storeId),
          // 0: Thuế
          FirebaseFirestore.instance
              .collection('promotions')
              .doc('${storeId}_PromoSettings')
              .get(),
          // 1: Voucher
          firestore.loadPointsSettings(storeId),
          // 2: Điểm
          FirebaseFirestore.instance.collection('users').doc(ownerUid).get(),
          // 3: User Config (Default Method)
          firestore.getStoreDetails(storeId),
          // 4: [MỚI] Store Details
          SettingsService().getStoreSettings(ownerUid),
          // 5: [MỚI] Store Settings Object
          firestore.getActiveSurcharges(storeId),
        ]);

        _PaymentPanelState._cachedStoreTaxSettings =
        results[0] as Map<String, dynamic>?;

        // Xử lý Voucher (Index 1)
        final promoSnapshot = results[1] as DocumentSnapshot;
        if (promoSnapshot.exists) {
          final data = promoSnapshot.data() as Map<String, dynamic>;
          final code = data['defaultVoucherCode'];
          _PaymentPanelState._cachedDefaultVoucherCode = code;
          if (code != null && code.isNotEmpty) {
            final voucher = await firestore.validateVoucher(code, storeId);
            _PaymentPanelState._cachedDefaultVoucher = voucher;
          }
        }

        // Xử lý Điểm (Index 2)
        final pointsData = results[2] as Map<String, dynamic>;
        _PaymentPanelState._cachedEarnRate = pointsData['earnRate'] ?? 0.0;
        _PaymentPanelState._cachedRedeemRate = pointsData['redeemRate'] ?? 0.0;

        // Xử lý Default Payment Method (Index 3)
        final userSnapshot = results[3] as DocumentSnapshot;
        if (userSnapshot.exists) {
          final userData = userSnapshot.data() as Map<String, dynamic>;
          _PaymentPanelState._cachedDefaultMethodId =
          userData['defaultPaymentMethodId'];
        }

        // [MỚI] Xử lý Store Details & Settings (Index 4 & 5)
        _PaymentPanelState._cachedStoreDetails =
        results[4] as Map<String, String>?;
        _PaymentPanelState._cachedStoreSettingsObj = results[5];
        _PaymentPanelState._cachedSurcharges = results[6] as List<SurchargeModel>;

      }
      debugPrint(
          ">>> [Preload] Hoàn tất! PTTT Mặc định: ${_PaymentPanelState._cachedDefaultMethodId}");
      debugPrint(">>> [Preload] Đã tải ${_PaymentPanelState._cachedSurcharges?.length} phụ thu.");
    } catch (e) {
      debugPrint(">>> [Preload] Lỗi: $e");
    }
  }

  static String? getCachedDefaultMethodId() {
    return _PaymentPanelState.sharedDefaultMethodId;
  }
}

class PaymentView extends StatelessWidget {
  final OrderModel order;
  final UserModel currentUser;
  final CustomerModel? customer;
  final String? customerAddress;
  final double subtotal;
  final VoidCallback onCancel;
  final Function(dynamic) onConfirmPayment;
  final bool showPricesOnReceipt;
  final bool printBillAfterPayment;
  final PaymentState? initialState;
  final Function(PaymentState)? onPrintAndExit;
  final bool promptForCash;
  final bool isRetailMode;
  final String? initialPaymentMethodId;

  const PaymentView({
    super.key,
    required this.order,
    required this.currentUser,
    this.customer,
    this.customerAddress,
    required this.subtotal,
    required this.onCancel,
    required this.onConfirmPayment,
    this.showPricesOnReceipt = true,
    this.printBillAfterPayment = true,
    this.initialState,
    this.onPrintAndExit,
    this.promptForCash = true,
    this.isRetailMode = false,
    this.initialPaymentMethodId,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: _PaymentPanel(
        order: order,
        currentUser: currentUser,
        subtotal: subtotal,
        customer: customer,
        customerAddress: customerAddress,
        onCancel: onCancel,
        onConfirmPayment: onConfirmPayment,
        printBillAfterPayment: printBillAfterPayment,
        showPricesOnReceipt: showPricesOnReceipt,
        initialState: initialState,
        onPrintAndExit: onPrintAndExit,
        promptForCash: promptForCash,
        isRetailMode: isRetailMode,
        initialPaymentMethodId: initialPaymentMethodId,
      ),
    );
  }
}

class _PaymentPanel extends StatefulWidget {
  final OrderModel order;
  final UserModel currentUser;
  final double subtotal;
  final CustomerModel? customer;
  final String? customerAddress;
  final VoidCallback onCancel;
  final Function(dynamic) onConfirmPayment;
  final bool printBillAfterPayment;
  final bool showPricesOnReceipt;
  final PaymentState? initialState;
  final Function(PaymentState)? onPrintAndExit;
  final bool promptForCash;
  final bool isRetailMode;
  final String? initialPaymentMethodId;

  const _PaymentPanel({
    required this.order,
    required this.currentUser,
    required this.subtotal,
    this.customer,
    this.customerAddress,
    required this.onCancel,
    required this.onConfirmPayment,
    required this.printBillAfterPayment,
    required this.showPricesOnReceipt,
    this.initialState,
    this.onPrintAndExit,
    required this.promptForCash,
    required this.isRetailMode,
    this.initialPaymentMethodId,
  });

  @override
  State<_PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<_PaymentPanel> {
  late final TextEditingController _discountController;
  late final TextEditingController _voucherController;
  late final TextEditingController _pointsController;
  late final TextEditingController _cashInputController;
  final Map<String, TextEditingController> _paymentControllers = {};
  static Map<String, dynamic>? _cachedStoreTaxSettings;
  static List<PaymentMethodModel>? _cachedPaymentMethods;
  static double? _cachedEarnRate;
  static double? _cachedRedeemRate;
  static String? _cachedDefaultMethodId;
  static String? _cachedDefaultVoucherCode;
  static VoucherModel? _cachedDefaultVoucher;

  static String? get sharedDefaultMethodId => _cachedDefaultMethodId;
  static Map<String, String>? _cachedStoreDetails;
  static dynamic _cachedStoreSettingsObj;
  static List<SurchargeModel>? _cachedSurcharges;
  static void resetCache() {
    _cachedStoreTaxSettings = null;
    _cachedPaymentMethods = null;
    _cachedEarnRate = null;
    _cachedRedeemRate = null;
    _cachedDefaultMethodId = null;
    _cachedDefaultVoucherCode = null;
    _cachedDefaultVoucher = null;
    _cachedStoreDetails = null;
    _cachedStoreSettingsObj = null;
    _cachedSurcharges = null;
  }

  final Map<String, String> _productTaxRateMap = {};

  double _calculatedVatAmount = 0.0;
  double _calculatedTncnAmount = 0.0;
  String _calcMethod = 'direct';
  bool _isDiscountPercent = false;
  final bool _printReceipt = true;
  final FirestoreService _firestoreService = FirestoreService();
  List<PaymentMethodModel> _availableMethods = [];

  PaymentMethodModel? _cashMethod;
  final Set<String> _selectedMethodIds = {};
  final Map<String, double> _paymentAmounts = {};
  final EInvoiceService _eInvoiceService = EInvoiceService();
  bool _autoIssueEInvoice = false;

  double _totalPayable = 0;
  double _changeAmount = 0;
  double _debtAmount = 0;

  VoucherModel? _appliedVoucher;
  double _voucherDiscountValue = 0;

  double _pointsMonetaryValue = 0;
  List<SurchargeItem> _surcharges = [];
  bool _isProcessingPayment = false;
  double _earnRate = 0.0;
  double _redeemRate = 0.0;
  bool _settingsLoaded = false;
  bool _methodsLoaded = false;
  String? _defaultPaymentMethodId;
  Timer? _debounce;
  Timer? _voucherDebounce;
  final Set<String> _confirmedBankMethods = {};

  @override
  void initState() {
    super.initState();
    // 1. Khởi tạo Controllers từ initialState (nếu có)
    final initialState = widget.initialState;
    if (initialState != null) {
      _discountController = TextEditingController(
          text: formatNumber(initialState.discountAmount));
      _voucherController =
          TextEditingController(text: initialState.voucherCode);
      _pointsController = TextEditingController(); // Points thường load lại sau
      _isDiscountPercent = initialState.isDiscountPercent;
      _surcharges = initialState.surcharges
          .map((s) => SurchargeItem(
          name: s.name, amount: s.amount, isPercent: s.isPercent))
          .toList();
    } else {
      _discountController = TextEditingController();
      _voucherController = TextEditingController();
      _pointsController = TextEditingController();
    }
    _cashInputController = TextEditingController();

    _addListeners();

    // 2. TỐI ƯU: Không gọi await ở đây.
    // Thử tính toán ngay với dữ liệu mặc định để UI có số liệu hiển thị ngay lập tức
    _calculateTotal(initialLoad: true);

    // 3. TỐI ƯU: Đẩy việc load dữ liệu ra sau khi frame đầu tiên được vẽ
    // Giúp animation chuyển màn hình mượt mà, không bị khựng
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAllInitialDataOptimized();
    });
  }

  Future<void> _loadAllInitialDataOptimized() async {
    // 1. LUÔN LUÔN Tải cấu hình E-Invoice (Dù có Cache hay không)
    // Đưa đoạn này lên đầu hàm để đảm bảo nó luôn được chạy
    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _eInvoiceService.getConfigStatus(ownerUid).then((configStatus) {
      if (mounted) {
        setState(() {
          // Nếu đã cấu hình thì lấy giá trị autoIssueOnPayment, ngược lại là false
          _autoIssueEInvoice = configStatus.isConfigured && configStatus.autoIssueOnPayment;
          debugPrint(">>> [E-INVOICE STATUS] Auto Issue: $_autoIssueEInvoice");
        });
      }
    });

    // 2. Kiểm tra Cache các dữ liệu khác (Logic cũ)
    if (_cachedPaymentMethods != null &&
        _cachedStoreTaxSettings != null &&
        _cachedEarnRate != null &&
        _cachedStoreDetails != null &&
        _cachedStoreSettingsObj != null) {
      _applyCachedData();
      return; // Code cũ return ở đây, làm đoạn E-Invoice bên dưới không chạy được
    }

    // 3. Nếu chưa có Cache -> Tải lại (Logic cũ)
    final futures = <Future>[];

    if (_cachedPaymentMethods == null) {
      futures.add(_loadPaymentMethods(forceRefresh: true));
    }

    if (_cachedStoreTaxSettings == null ||
        _cachedEarnRate == null ||
        _cachedStoreDetails == null) {
      futures.add(_loadSettings(forceRefresh: true));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      if (mounted) _applyCachedData();
    }
  }

  void _applyCachedData() {
    if (!mounted) return;
    setState(() {
      // --- Xử lý Thuế (Logic cũ của _loadStoreTaxSettings nằm ở đây) ---
      if (_cachedStoreTaxSettings != null) {
        final rawMap = _cachedStoreTaxSettings!['taxAssignmentMap']
        as Map<String, dynamic>? ??
            {};
        _productTaxRateMap.clear();
        rawMap.forEach((taxKey, productIds) {
          if (productIds is List) {
            for (final productId in productIds) {
              _productTaxRateMap[productId as String] = taxKey;
            }
          }
        });
        if (_cachedStoreTaxSettings!.containsKey('calcMethod')) {
          _calcMethod = _cachedStoreTaxSettings!['calcMethod'];
        } else {
          final entityType = _cachedStoreTaxSettings!['entityType'] ?? 'hkd';
          _calcMethod = (entityType == 'dn') ? 'deduction' : 'direct';
        }
      }

      // --- Xử lý Điểm (Logic cũ của _loadPointsSettings nằm ở đây) ---
      _earnRate = _cachedEarnRate ?? 0.0;
      _redeemRate = _cachedRedeemRate ?? 0.0;
      _defaultPaymentMethodId = _cachedDefaultMethodId;
      _settingsLoaded = true;

      // --- Xử lý PTTT ---
      if (_cachedPaymentMethods != null) {
        _cashMethod = _cachedPaymentMethods!.firstWhere(
                (m) => m.type == PaymentMethodType.cash,
            orElse: () => _createDefaultCashMethod());
        _availableMethods = _cachedPaymentMethods!;
        _methodsLoaded = true;
        _setupDefaultSelection();
      }

      if (_appliedVoucher == null && _cachedDefaultVoucher != null) {
        // 1. Điền mã lên giao diện
        _voucherController.text = _cachedDefaultVoucher!.code;

        // 2. Gán Voucher Model vào biến State ngay lập tức
        _appliedVoucher = _cachedDefaultVoucher;

        // 3. Tính ngay giá trị giảm (quan trọng nhất)
        if (_appliedVoucher!.isPercent) {
          _voucherDiscountValue =
              widget.subtotal * (_appliedVoucher!.value / 100);
        } else {
          _voucherDiscountValue = _appliedVoucher!.value;
        }

        debugPrint(
            ">>> [Instant Apply] Đã áp dụng Voucher từ Cache: $_voucherDiscountValue");
      }
      // Fallback: Trường hợp hiếm hoi có mã nhưng chưa có Model thì mới dùng cách cũ
      else if (_voucherController.text.isEmpty &&
          _cachedDefaultVoucherCode != null &&
          _cachedDefaultVoucherCode!.isNotEmpty) {
        _voucherController.text = _cachedDefaultVoucherCode!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyVoucher(silent: true);
        });
      }

      if (_cachedSurcharges != null && _surcharges.isEmpty) {
        // Chỉ thêm nếu danh sách hiện tại đang trống (tránh duplicate khi hot reload)
        _surcharges = _cachedSurcharges!.map((s) => SurchargeItem(
          name: s.name,
          amount: s.value,
          isPercent: s.isPercent,
        )).toList();
      }

      // Tính lại tổng tiền ngay lập tức
      _calculateTotal(initialLoad: true);
    });
  }

  Future<void> _loadSettings({bool forceRefresh = false}) async {
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

      final results = await Future.wait([
        SettingsService().getStoreSettings(ownerUid),
        FirestoreService().loadPointsSettings(widget.currentUser.storeId),
        _firestoreService.getStoreTaxSettings(widget.currentUser.storeId),
        _firestoreService.getStoreDetails(widget.currentUser.storeId),
      ]);

      // [SỬA ĐỔI] Đọc cài đặt voucher từ collection 'promotions' thay vì 'stores'
      final promoSettingsSnapshot = await FirebaseFirestore.instance
          .collection('promotions')
          .doc('${widget.currentUser.storeId}_PromoSettings')
          .get();

      _cachedStoreSettingsObj = results[0]; // [MỚI]
      final pointsSettings = results[1] as Map<String, dynamic>;
      _cachedStoreTaxSettings = results[2] as Map<String, dynamic>?;
      _cachedStoreDetails = results[3] as Map<String, String>?; // [MỚI]

      _cachedEarnRate = pointsSettings['earnRate'] ?? 0.0;
      _cachedRedeemRate = pointsSettings['redeemRate'] ?? 0.0;
      final settingsObj = results[0] as dynamic;
      _cachedDefaultMethodId = settingsObj.defaultPaymentMethodId;

      // [SỬA ĐỔI] Lấy defaultVoucherCode từ document mới
      if (promoSettingsSnapshot.exists) {
        final data = promoSettingsSnapshot.data();
        final String? freshCode = data?['defaultVoucherCode'];

        // TRƯỜNG HỢP 1: Database đã xóa voucher mặc định, nhưng Cache vẫn còn
        if ((freshCode == null || freshCode.isEmpty) &&
            _cachedDefaultVoucher != null) {
          debugPrint(
              ">>> [Sync] Voucher mặc định đã bị xóa trên server. Đang gỡ bỏ...");

          _cachedDefaultVoucherCode = null;
          _cachedDefaultVoucher = null;

          if (mounted && _appliedVoucher != null) {
            setState(() {
              _voucherController.clear();
              _appliedVoucher = null;
              _voucherDiscountValue = 0;
              _calculateTotal();
            });
            ToastService().show(
                message: "Voucher mặc định đã bị hủy.",
                type: ToastType.warning);
          }
        }

        // TRƯỜNG HỢP 2: Có mã voucher
        else if (freshCode != null && freshCode.isNotEmpty) {
          _cachedDefaultVoucherCode = freshCode;

          // Nếu Cache đang null HOẶC Cache đang giữ mã cũ -> Tải cái mới để lưu vào RAM
          if (_cachedDefaultVoucher == null ||
              _cachedDefaultVoucher!.code != freshCode) {
            final voucherResult = await FirestoreService()
                .validateVoucher(freshCode, widget.currentUser.storeId);
            _cachedDefaultVoucher = voucherResult;

            // Nếu đang mở màn hình thì cập nhật UI luôn
            if (mounted && voucherResult != null) {
              _applyCachedData();
            }
          }
        }
      } else {
        _cachedDefaultVoucherCode = null;
        _cachedDefaultVoucher = null;
      }
    } catch (e) {
      debugPrint("Error loading settings: $e");
    }
  }

  PaymentMethodModel _createDefaultCashMethod() {
    return PaymentMethodModel(
      id: 'cash_default',
      storeId: widget.currentUser.storeId,
      name: 'Tiền mặt',
      type: PaymentMethodType.cash,
      active: true,
    );
  }

  Future<void> _loadPaymentMethods({bool forceRefresh = false}) async {
    try {
      // SỬA LỖI Ở ĐÂY: Thay .get() bằng .first
      final snapshot = await _firestoreService
          .getPaymentMethods(widget.currentUser.storeId)
          .first;

      final firestoreMethods = snapshot.docs
          .map((doc) => PaymentMethodModel.fromFirestore(doc))
          .toList();
      final cashMethod = _createDefaultCashMethod();

      // Cập nhật Cache Static
      _cachedPaymentMethods = [cashMethod, ...firestoreMethods];
    } catch (e) {
      debugPrint("Lỗi tải PTTT: $e");
      _cachedPaymentMethods = [_createDefaultCashMethod()];
    }
  }

  void _setupDefaultSelection() {
    // Nếu chưa có danh sách PTTT thì thoát
    if (_cashMethod == null || _availableMethods.isEmpty) return;

    // 1. Xác định PTTT MỤC TIÊU (Cái mà mình muốn chọn)
    String targetId = widget.initialPaymentMethodId ??
        _cachedDefaultMethodId ??
        _cashMethod!.id;

    // Kiểm tra xem Mục tiêu có tồn tại trong danh sách đã tải chưa?
    final bool targetExists = _availableMethods.any((m) => m.id == targetId);

    // Nếu Mục tiêu (ví dụ: Bank) chưa tải xong -> Tạm thời phải dùng Tiền mặt
    if (!targetExists) {
      targetId = _cashMethod!.id;
    }

    // 2. KIỂM TRA: Có cần đổi không?
    bool shouldSwitch = false;

    if (_selectedMethodIds.isEmpty) {
      // Trường hợp A: Chưa chọn gì -> Chọn ngay
      shouldSwitch = true;
    } else if (_selectedMethodIds.length == 1) {
      final currentSelectedId = _selectedMethodIds.first;

      // Lấy thông tin phương thức đang được chọn
      // (Tìm trong list, nếu không thấy thì nó chính là cái Fake Cash)
      final currentMethod = _availableMethods.firstWhere(
              (m) => m.id == currentSelectedId,
          orElse: () => _createDefaultCashMethod());

      // Trường hợp B:
      // - Đang chọn loại là TIỀN MẶT (Bất kể ID giả hay thật)
      // - VÀ Mục tiêu lại KHÁC cái đang chọn (VD: Cài đặt là Chuyển khoản)
      if (currentMethod.type == PaymentMethodType.cash) {
        if (targetId != currentSelectedId) {
          shouldSwitch = true;
        }
      }
    }

    if (!shouldSwitch) return;

    // 3. THỰC HIỆN ĐỔI (Không cần setState vì hàm này được gọi trong luồng build/init)
    _selectedMethodIds.clear();
    _selectedMethodIds.add(targetId);

    // Reset tiền nong
    _paymentAmounts.clear();
    _calculateTotal(initialLoad: true);

    double amountToSet = 0;
    final bool isTargetCash = (targetId == _cashMethod!.id);

    if (isTargetCash) {
      amountToSet = widget.promptForCash ? 0.0 : _totalPayable;
    } else {
      amountToSet = _totalPayable;
    }

    _paymentAmounts[targetId] = amountToSet;

    // Cập nhật ô nhập tiền mặt
    if (isTargetCash) {
      _cashInputController.text = formatNumber(amountToSet);
    } else {
      _cashInputController.clear();
    }

    debugPrint(">>> [Auto Switch] Đã đổi từ Tiền mặt sang: $targetId");
  }

  @override
  void didUpdateWidget(covariant _PaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.subtotal != oldWidget.subtotal ||
        widget.customer?.id != oldWidget.customer?.id) {
      _calculateTotal(syncPayment: true);
    }
  }

  void _addListeners() {
    // Chiết khấu & Điểm thay đổi -> Cần Sync lại số tiền thanh toán (TRUE)
    _discountController.addListener(_onStructureChanged);
    _pointsController.addListener(_onStructureChanged);

    // Nhập tiền mặt -> KHÔNG Sync, giữ nguyên số nhập (FALSE)
    _cashInputController.addListener(_onCashInputChanged);

    _voucherController.addListener(() {
      if (_voucherDebounce?.isActive ?? false) _voucherDebounce!.cancel();
      _voucherDebounce = Timer(const Duration(milliseconds: 800), _applyVoucher);
    });
  }

  void _onStructureChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _calculateTotal(syncPayment: true));
  }

  void _onCashInputChanged() {
    if (_selectedMethodIds.contains(_cashMethod!.id)) {
      final cashAmount = parseVN(_cashInputController.text);
      _paymentAmounts[_cashMethod!.id] = cashAmount;
    }
    // Gọi tính toán nhưng KHÔNG sync lại tiền
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _calculateTotal(syncPayment: false));
  }

  @override
  void dispose() {
    _discountController.dispose();
    _voucherController.dispose();
    _pointsController.dispose();
    _cashInputController.dispose();
    _debounce?.cancel();
    _voucherDebounce?.cancel();
    for (var controller in _paymentControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _applyVoucher({bool silent = false}) async {
    final code = _voucherController.text.trim();

    if (code.isEmpty) {
      if (_appliedVoucher != null) {
        setState(() {
          _appliedVoucher = null;
          _voucherDiscountValue = 0;
        });
        _calculateTotal(syncPayment: true);
      }
      return;
    }

    final voucher = await FirestoreService()
        .validateVoucher(code, widget.currentUser.storeId);

    if (!mounted) return;

    if (voucher != null) {
      setState(() {
        _appliedVoucher = voucher;
        if (voucher.isPercent) {
          _voucherDiscountValue = widget.subtotal * (voucher.value / 100);
        } else {
          _voucherDiscountValue = voucher.value;
        }
      });
    } else {
      setState(() {
        _appliedVoucher = null;
        _voucherDiscountValue = 0;
      });

      if (silent) {
        if (code == _cachedDefaultVoucherCode) {
          debugPrint(">>> Voucher mặc định ($code) đã hết hạn. Đang gỡ bỏ...");

          _voucherController.clear();

          // [SỬA ĐỔI] Gỡ bỏ mặc định trong collection 'promotions'
          try {
            await FirebaseFirestore.instance
                .collection('promotions')
                .doc('${widget.currentUser.storeId}_PromoSettings')
                .update({'defaultVoucherCode': null});
          } catch (e) {
            debugPrint("Lỗi khi xóa voucher mặc định hỏng: $e");
          }

          _cachedDefaultVoucherCode = null;
        }
      } else {
        ToastService().show(
            message: "Voucher không hợp lệ hoặc đã hết hạn.",
            type: ToastType.error);
      }
    }
    _calculateTotal(syncPayment: true);
  }

  double _calculateDiscount() {
    final discountInput = parseVN(_discountController.text);
    if (_isDiscountPercent && discountInput > 100) return widget.subtotal;
    return _isDiscountPercent
        ? (widget.subtotal * discountInput / 100)
        : discountInput;
  }

  (double, double) _getCalculatedTaxes(double totalDistributableDiscount) {
    if (_cachedStoreTaxSettings == null) {
      return (0.0, 0.0);
    }

    double totalTax = 0.0;

    final bool isDeduction = _calcMethod == 'deduction';
    final rateMap = isDeduction ? kDeductionRates : kDirectRates;
    final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

    // Tổng doanh thu chịu thuế (Giá trị hàng hóa chưa chiết khấu tổng đơn)
    final double totalRevenue = widget.subtotal;

    if (totalRevenue <= 0) {
      return (0.0, 0.0);
    }

    for (final item in widget.order.items) {
      final productMap = (item['product'] as Map<String, dynamic>?) ?? {};
      final productId = productMap['id'] as String?;

      String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;
      if (!rateMap.containsKey(taxKey)) {
        taxKey = defaultTaxKey;
      }

      // itemSubtotal là giá trị đã trừ chiết khấu cấp sản phẩm (nếu có)
      final double itemSubtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      // taxRate là tỷ lệ % thuế (ví dụ: 0.1 cho 10%)
      final double taxRate = rateMap[taxKey]?['rate'] ?? 0.0;

      // 1. Tính Tỷ lệ doanh thu của sản phẩm này trên tổng doanh thu
      final double itemRatio = itemSubtotal / totalRevenue;

      // 2. Phân bổ phần Chiết khấu tổng đơn cho sản phẩm này
      final double allocatedDiscount = totalDistributableDiscount * itemRatio;

      // 3. Tính Doanh thu chịu thuế cuối cùng (Giá đã giảm)
      final double taxableRevenue = itemSubtotal - allocatedDiscount;

      // 4. Tính Thuế VAT mới
      final double itemTaxAmount = taxableRevenue * taxRate;

      totalTax += itemTaxAmount;
    }

    // Chỉ trả về tổng thuế (VAT) đã điều chỉnh
    return (totalTax.roundToDouble(), 0.0);
  }

  void _calculateTotal({bool initialLoad = false, bool syncPayment = false}) {
    if (!initialLoad && (!_settingsLoaded || !_methodsLoaded)) return;

    final discountAmount = _calculateDiscount();
    final int maxPoints = widget.customer?.points ?? 0;

    int pointsUsed = parseVN(_pointsController.text).toInt();
    if (pointsUsed > maxPoints) {
      pointsUsed = maxPoints;
      if (!initialLoad) {
        _pointsController.text = formatNumber(pointsUsed.toDouble());
      }
    }

    final double pointsValue = pointsUsed * _redeemRate;
    final double totalDistributableDiscount = discountAmount + pointsValue + _voucherDiscountValue;

    final (newVatAmount, newTncnAmount) = _getCalculatedTaxes(totalDistributableDiscount);

    final subtotal = widget.subtotal;
    final totalSurcharge = _calculateTotalSurcharge();
    final double finalTotalBase = subtotal - totalDistributableDiscount;
    final double taxToAdd = newVatAmount + newTncnAmount;
    final double finalTotal = finalTotalBase + totalSurcharge + taxToAdd;

    final newTotalPayable = finalTotal > 0 ? finalTotal.roundToDouble() : 0.0;

    // [QUAN TRỌNG] Chỉ tự động gán tiền nếu có lệnh syncPayment
    if (syncPayment && !initialLoad && _selectedMethodIds.length == 1) {
      final methodId = _selectedMethodIds.first;
      final method = _availableMethods.firstWhere((m) => m.id == methodId,
          orElse: () => _cashMethod!);

      bool shouldAutoSync = method.type != PaymentMethodType.cash || !widget.promptForCash;

      if (shouldAutoSync) {
        _paymentAmounts[methodId] = newTotalPayable;
        final newText = formatNumber(newTotalPayable); // Format tiền

        // 1. Xử lý Tiền mặt (Giữ nguyên logic cũ)
        if (method.type == PaymentMethodType.cash) {
          if (_cashInputController.text != newText) {
            _cashInputController.removeListener(_onCashInputChanged);
            _cashInputController.text = newText;
            _cashInputController.addListener(_onCashInputChanged);
          }
        }
        // 2. [MỚI] Xử lý các PTTT khác (Bank, Ví...)
        else {
          if (_paymentControllers.containsKey(methodId)) {
            final controller = _paymentControllers[methodId]!;
            if (controller.text != newText) {
              // Cập nhật text hiển thị mà không trigger sự kiện onChanged
              // (Do onChanged của CustomTextFormField thường ko gán listener trực tiếp như Native)
              // Nhưng ở đây ta chỉ cần set text là đủ.
              controller.text = newText;
            }
          }
        }
      }
    }

    double newChange = 0;
    double newDebt = newTotalPayable;

    if (!initialLoad) {
      final double totalPaid = _paymentAmounts.values.fold(0.0, (a, b) => a + b);
      final double cashPaid = _paymentAmounts[_cashMethod!.id] ?? 0.0;
      final double otherPayments = totalPaid - cashPaid;

      if (totalPaid >= newTotalPayable) {
        final cashOverpayment = cashPaid - (newTotalPayable - otherPayments);
        newChange = cashOverpayment > 0 ? cashOverpayment.roundToDouble() : 0.0;
        newDebt = 0;
      } else {
        newChange = 0;
        newDebt = (newTotalPayable - totalPaid).roundToDouble();
      }
    }

    if (mounted) {
      setState(() {
        _calculatedVatAmount = newVatAmount;
        _calculatedTncnAmount = newTncnAmount;
        _pointsMonetaryValue = pointsValue;
        _totalPayable = newTotalPayable;
        if (!initialLoad) {
          _changeAmount = newChange;
          _debtAmount = newDebt;
        }
      });
    }
  }

  double _calculateTotalSurcharge() {
    return _surcharges.fold<double>(0.0, (acc, item) {
      if (item.isPercent && item.amount > 100) return acc;
      final surcharge =
      item.isPercent ? widget.subtotal * (item.amount / 100) : item.amount;
      return acc + surcharge.toDouble();
    });
  }

  Future<void> _confirmPayment({bool? forcePrint}) async {
    if (_isProcessingPayment) return;

    // 1. Tính toán lại lần cuối
    _calculateTotal();

    // 2. Kiểm tra logic tiền mặt
    if (widget.promptForCash &&
        _selectedMethodIds.contains(_cashMethod!.id) &&
        _debtAmount > 0) {
      final double otherPayments = _paymentAmounts.entries
          .where((e) => e.key != _cashMethod!.id)
          .fold(0.0, (a, b) => a + b.value);
      final double cashNeeded = _totalPayable - otherPayments;
      final double cashPaid = _paymentAmounts[_cashMethod!.id] ?? 0.0;

      if (cashNeeded > 0 && cashPaid < cashNeeded) {
        ToastService().show(
            message: 'Vui lòng xác nhận tiền mặt',
            type: ToastType.warning);

        final bool isDebtConfirmed = await _showCashDialog();

        _calculateTotal();

        if (_debtAmount > 0 && !isDebtConfirmed) {
          return;
        }
      }
    }

    // 3. Kiểm tra xác nhận chuyển khoản (QR)
    while (true) {
      PaymentMethodModel? firstUnconfirmedBankMethod;
      for (final method in _availableMethods) {
        final amount = _paymentAmounts[method.id] ?? 0;
        if (method.type == PaymentMethodType.bank &&
            method.qrDisplayOnScreen &&
            amount > 0 &&
            !_confirmedBankMethods.contains(method.id)) {
          firstUnconfirmedBankMethod = method;
          break;
        }
      }
      if (firstUnconfirmedBankMethod != null) {
        ToastService().show(
            message:
            'Vui lòng xác nhận đã nhận thanh toán qua ${firstUnconfirmedBankMethod.name}',
            type: ToastType.warning);
        final bool wasConfirmed =
        await _showQrPopup(firstUnconfirmedBankMethod);
        if (!wasConfirmed) return;
      } else {
        break;
      }
    }

    if (_totalPayable > 0 && _paymentAmounts.isEmpty) {
      ToastService().show(
          message: 'Vui lòng chọn ít nhất 1 PTTT', type: ToastType.warning);
      return;
    }
    if (_debtAmount > 0 && widget.customer == null) {
      ToastService().show(
          message: 'Không đủ tiền và không có khách hàng để ghi nợ.',
          type: ToastType.error);
      return;
    }

    setState(() {
      _isProcessingPayment = true;
    });

    try {
      // 1. Lấy biến cài đặt từ cache
      final settings = _cachedStoreSettingsObj;

      // 2. Lấy giá trị cấu hình (mặc định là false nếu không tìm thấy)
      final bool shouldNotifyKitchen = settings?.notifyKitchenAfterPayment ?? false;

      // 3. Chỉ in nếu: (Có bật cấu hình) VÀ (Không phải bán lẻ)
      if (shouldNotifyKitchen && !widget.isRetailMode) {
        await _sendUnsentItemsToKitchen();
      }

      // 1. TẠO BILL CODE CLIENT-SIDE
      final now = DateTime.now();
      final String billCodeTimestamp = DateFormat('ddMMyyHHmm').format(now);
      final String randomSuffix = Random().nextInt(1000).toString().padLeft(3, '0');
      final String shortBillCode = 'HD$billCodeTimestamp$randomSuffix';
      final String newBillId = '${widget.currentUser.storeId}_$shortBillCode';

      // 2. CHUẨN BỊ DỮ LIỆU
      final validPayments =
      Map.fromEntries(_paymentAmounts.entries.where((e) => e.value > 0));

      String? firstBankMethodId;
      try {
        firstBankMethodId =
            validPayments.keys.firstWhere((id) => id != _cashMethod!.id);
      } catch (e) {
        firstBankMethodId = null;
      }
      final firstBankMethod = firstBankMethodId != null
          ? _availableMethods.firstWhere((m) => m.id == firstBankMethodId)
          : null;

      Map<String, dynamic>? bankDetails;
      if (firstBankMethod != null && firstBankMethod.qrDisplayOnBill) {
        bankDetails = {
          'bankBin': firstBankMethod.bankBin,
          'bankAccount': firstBankMethod.bankAccount,
          'bankAccountName': firstBankMethod.bankAccountName,
        };
      }

      final paymentMapWithNames = validPayments.map((id, amount) {
        final name = _availableMethods.firstWhere((m) => m.id == id).name;
        return MapEntry(name, amount);
      });

      final result = PaymentResult(
        totalPayable: _totalPayable,
        discountAmount: _calculateDiscount(),
        discountType: _isDiscountPercent ? '%' : 'VND',
        surcharges: _surcharges,
        taxPercent: 0.0,
        totalTaxAmount: _calculatedVatAmount,
        totalTncnAmount: _calculatedTncnAmount,
        payments: paymentMapWithNames,
        customerPointsUsed: parseVN(_pointsController.text),
        changeAmount: _changeAmount,
        printReceipt: _printReceipt,
        bankDetailsForPrinting: bankDetails,
      );

      // Chuẩn bị Items
      final bool isDeduction = _calcMethod == 'deduction';
      final rateMap = isDeduction ? kDeductionRates : kDirectRates;
      final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

      final List<Map<String, dynamic>> billItems =
      widget.order.items.map((item) {
        final Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
        final productData = item['product'] as Map<String, dynamic>? ?? {};

        final serviceSetup = productData['serviceSetup'] as Map<String, dynamic>?;
        final isTimeBased = serviceSetup?['isTimeBased'] == true;
        if (isTimeBased) {
          final priceBreakdown =
          List<Map<String, dynamic>>.from(item['priceBreakdown'] ?? []);
          int totalMinutes = 0;
          for (var block in priceBreakdown) {
            totalMinutes += (block['minutes'] as num?)?.toInt() ?? 0;
          }
          if (totalMinutes > 0) {
            newItem['quantity'] = totalMinutes / 60.0;
          }
        }

        final productId = productData['id'] as String?;
        String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;
        if (!rateMap.containsKey(taxKey)) taxKey = defaultTaxKey;
        final double rate = rateMap[taxKey]?['rate'] ?? 0.0;

        newItem['taxAmount'] =
            ((item['subtotal'] as num?)?.toDouble() ?? 0.0) * rate;
        newItem['taxRate'] = rate;
        newItem['taxKey'] = taxKey;

        return newItem;
      }).toList();

      final double totalProfit = _calculateTotalProfit();
      int pointsEarned = 0;
      if (widget.customer != null && _earnRate > 0) {
        pointsEarned = (_totalPayable / _earnRate).floor();
      }

      // Xử lý Staff Commissions
      final List<Map<String, dynamic>> staffCommissions = [];
      for (var item in billItems) {
        final productData = (item['product'] as Map<String, dynamic>?) ?? {};
        final productType = productData['productType'] as String?;
        final isTimeBased = productData['serviceSetup']?['isTimeBased'] == true;
        final commissionStaff =
            (item['commissionStaff'] as Map<String, dynamic>?) ?? {};

        if (productType == "Dịch vụ/Tính giờ" &&
            !isTimeBased &&
            commissionStaff.isNotEmpty &&
            commissionStaff.values.any((id) => id != null)) {
          staffCommissions.add({
            'productName': productData['productName'] ?? 'N/A',
            'productId': productData['id'] ?? 'N/A',
            'lineId': item['lineId'] ?? 'N/A',
            'price': (item['price'] as num?)?.toDouble() ?? 0.0,
            'quantity': (item['quantity'] as num?)?.toDouble() ?? 0.0,
            'discountValue': (item['discountValue'] as num?)?.toDouble() ?? 0.0,
            'discountUnit': item['discountUnit'] as String? ?? '%',
            'subtotal': item['subtotal'] ?? 0.0,
            'staff': commissionStaff,
          });
        }
      }

      String finalTableNameForBill = widget.order.tableName;

      if (widget.isRetailMode) {
        final lowerName = finalTableNameForBill.toLowerCase();

        if (lowerName.contains("giao hàng") || lowerName.contains("ship")) {
          finalTableNameForBill = "Giao hàng";
        } else if (lowerName.contains("đặt lịch") || lowerName.contains("booking")) {
          finalTableNameForBill = "Đặt lịch";
        } else {
          finalTableNameForBill = "Tại quầy";
        }
      }

      final billData = {
        'orderId': widget.order.id,
        'storeId': widget.order.storeId,
        'tableName': finalTableNameForBill,
        'items': billItems,
        'subtotal': widget.subtotal,
        'totalPayable': _totalPayable,
        'discount': result.discountAmount,
        'discountType': result.discountType,
        'discountInput': parseVN(_discountController.text),
        'surcharges': result.surcharges
            .map((s) =>
        {'name': s.name, 'amount': s.amount, 'isPercent': s.isPercent})
            .toList(),
        'taxPercent': 0.0,
        'taxAmount': _calculatedVatAmount,
        'tncnAmount': _calculatedTncnAmount,
        'payments': result.payments,
        'changeAmount': _changeAmount,
        'debtAmount': _debtAmount,
        'printReceipt': result.printReceipt,
        'createdAt': FieldValue.serverTimestamp(),
        'clientCreatedAt': now,
        'createdByUid': widget.currentUser.uid,
        'createdByName':
        widget.currentUser.name ?? widget.currentUser.phoneNumber,
        'voucherCode': _appliedVoucher?.code,
        'voucherDiscount': _voucherDiscountValue,
        'customerPointsUsed': result.customerPointsUsed,
        'customerPointsValue': _pointsMonetaryValue,
        'pointsEarned': pointsEarned,
        'totalProfit': totalProfit,
        'staffCommissions': staffCommissions,
        'bankDetails': result.bankDetailsForPrinting,
        'customerId': widget.customer?.id,
        'customerName': widget.customer?.name,
        'customerPhone': widget.customer?.phone,
        'guestAddress': widget.customerAddress,
        'eInvoiceInfo': null, // Mặc định là null
        'billCode': shortBillCode,
        'status': 'completed',
      };

      // --- [MỚI] GỌI API HÓA ĐƠN ĐIỆN TỬ (CHỜ KẾT QUẢ) ---
      EInvoiceResult? eInvoiceResult;

      if (_autoIssueEInvoice) {
        try {
          // Hàm này trả về dữ liệu hoặc throw lỗi, không bao giờ trả về null
          eInvoiceResult = await _eInvoiceService.createInvoice(
            billData,
            widget.customer,
            widget.currentUser.ownerUid ?? widget.currentUser.uid,
          );
          billData['eInvoiceInfo'] = eInvoiceResult.toJson();

        } catch (e) {
          debugPrint("Lỗi HĐĐT (Vẫn cho phép thanh toán): $e");
          ToastService().show(message: "Không thể xuất HĐĐT: ${e.toString()}", type: ToastType.warning);
        }
      }

      final bool shouldPrint = forcePrint ?? _printReceipt;

      // 1. Gởi lệnh in (Kèm eInvoiceResult để hiện QR)
      if (shouldPrint) {
        _sendReceiptToPrintQueue(
          firestore: FirestoreService(),
          billItems: billItems,
          result: result,
          billData: billData,
          eInvoiceResult: eInvoiceResult, // <--- QUAN TRỌNG: Truyền kết quả vào đây
          newBillId: newBillId,
        ).catchError(
                (e) => debugPrint("Lỗi in ngầm: $e"));
      }

      // 2. Callback xác nhận
      widget.onConfirmPayment(result);

      // 3. Đóng màn hình
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }

      // 4. Lưu dữ liệu chạy ngầm (Kèm preCreatedEInvoiceResult để không tạo lại)
      _performFullBackgroundSave(
        newBillId: newBillId,
        billData: billData,
        billItems: billItems,
        result: result,
        ownerUid: widget.currentUser.ownerUid ?? widget.currentUser.uid,
        pointsEarned: pointsEarned,
        preCreatedEInvoiceResult: eInvoiceResult, // <--- QUAN TRỌNG: Truyền vào đây
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
        ToastService().show(message: 'Lỗi: $e', type: ToastType.error);
      }
    }
  }

  Future<void> _printShipBillOnly() async {
    if (_isProcessingPayment) return;

    // 1. Tính toán lại số liệu
    _calculateTotal();

    setState(() {
      _isProcessingPayment = true;
    });

    try {
      // 2. Tạo mã Bill tạm thời
      final now = DateTime.now();
      final String billCodeTimestamp = DateFormat('ddMMyyHHmm').format(now);
      final String randomSuffix = Random().nextInt(1000).toString().padLeft(3, '0');
      final String shortBillCode = 'SHIP$billCodeTimestamp$randomSuffix';
      final String newBillId = '${widget.currentUser.storeId}_$shortBillCode';

      // 3. Chuẩn bị dữ liệu in
      final validPayments =
      Map.fromEntries(_paymentAmounts.entries.where((e) => e.value > 0));

      String? firstBankMethodId;
      try {
        firstBankMethodId =
            validPayments.keys.firstWhere((id) => id != _cashMethod!.id);
      } catch (e) {
        firstBankMethodId = null;
      }
      final firstBankMethod = firstBankMethodId != null
          ? _availableMethods.firstWhere((m) => m.id == firstBankMethodId)
          : null;

      Map<String, dynamic>? bankDetails;
      if (firstBankMethod != null && firstBankMethod.qrDisplayOnBill) {
        bankDetails = {
          'bankBin': firstBankMethod.bankBin,
          'bankAccount': firstBankMethod.bankAccount,
          'bankAccountName': firstBankMethod.bankAccountName,
        };
      }

      final paymentMapWithNames = validPayments.map((id, amount) {
        final name = _availableMethods.firstWhere((m) => m.id == id).name;
        return MapEntry(name, amount);
      });

      // Tạo object kết quả
      final result = PaymentResult(
        totalPayable: _totalPayable,
        discountAmount: _calculateDiscount(),
        discountType: _isDiscountPercent ? '%' : 'VND',
        surcharges: _surcharges,
        taxPercent: 0.0,
        totalTaxAmount: _calculatedVatAmount,
        totalTncnAmount: _calculatedTncnAmount,
        payments: paymentMapWithNames,
        customerPointsUsed: parseVN(_pointsController.text),
        changeAmount: _changeAmount,
        printReceipt: true,
        bankDetailsForPrinting: bankDetails,
      );

      // Chuẩn bị Items
      final bool isDeduction = _calcMethod == 'deduction';
      final rateMap = isDeduction ? kDeductionRates : kDirectRates;
      final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

      final List<Map<String, dynamic>> billItems =
      widget.order.items.map((item) {
        final Map<String, dynamic> newItem = Map<String, dynamic>.from(item);
        final productData = item['product'] as Map<String, dynamic>? ?? {};

        final productId = productData['id'] as String?;
        String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;
        if (!rateMap.containsKey(taxKey)) taxKey = defaultTaxKey;
        final double rate = rateMap[taxKey]?['rate'] ?? 0.0;

        newItem['taxAmount'] =
            ((item['subtotal'] as num?)?.toDouble() ?? 0.0) * rate;
        newItem['taxRate'] = rate;
        newItem['taxKey'] = taxKey;

        return newItem;
      }).toList();

      String finalAddress = widget.customerAddress ?? '';
      if (finalAddress.isEmpty) {
        finalAddress = widget.order.guestAddress ?? '';
      }
      if (finalAddress.isEmpty && widget.customer != null) {
        finalAddress = widget.customer!.address ?? ''; // Fallback cuối cùng
      }

      // Logic tương tự cho SĐT
      String finalPhone = widget.customer?.phone ?? '';
      if (finalPhone.isEmpty) {
        finalPhone = widget.order.customerPhone ?? '';
      }

      final bool isCashPayment = _selectedMethodIds.contains(_cashMethod!.id);

      // Dữ liệu Bill (Bổ sung SĐT, Địa chỉ và cờ hideDebt)
      final billData = {
        'customerName': widget.customer?.name ?? widget.order.customerName,
        'customerPhone': widget.customer?.phone ?? widget.order.customerPhone, // Thêm SĐT
        'guestAddress': widget.customerAddress ?? widget.order.guestAddress,   // Thêm Địa chỉ
        'hideDebt': isCashPayment, // Cờ để ẩn dư nợ
      };

      // 4. Gửi lệnh in
      await _sendReceiptToPrintQueue(
        firestore: FirestoreService(),
        billItems: billItems,
        result: result,
        billData: billData,
        eInvoiceResult: null,
        newBillId: newBillId,
      );

      ToastService().show(message: "Đã gửi lệnh in Bill Giao hàng.", type: ToastType.success);

    } catch (e) {
      ToastService().show(message: 'Lỗi in: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isProcessingPayment = false);
      }
    }
  }

  Future<void> _performFullBackgroundSave({
    required String newBillId,
    required Map<String, dynamic> billData,
    required List<Map<String, dynamic>> billItems,
    required PaymentResult result,
    required String ownerUid,
    required int pointsEarned,
    EInvoiceResult? preCreatedEInvoiceResult,
  }) async {
    final firestore = FirestoreService();

    try {
      // 1. Cập nhật Order (SỬA ĐỔI QUAN TRỌNG)
      // Thay vì updateOrder (chỉ update), ta dùng set với merge: true để an toàn cho đơn bán lẻ chưa tồn tại
      final orderRef = FirebaseFirestore.instance.collection('orders').doc(widget.order.id);

      await orderRef.set({
        'status': 'paid',
        'billId': newBillId,
        'paidAt': FieldValue.serverTimestamp(),
        'paidByUid': widget.currentUser.uid,
        'paidByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
        'finalAmount': _totalPayable,
        'debtAmount': _debtAmount,
        'items': billItems,
        'updatedAt': FieldValue.serverTimestamp(),
        'version': widget.order.version + 1,

        // Các trường cần thiết để tạo mới nếu chưa có
        'storeId': widget.order.storeId,
        'tableName': widget.order.tableName,
        'totalAmount': widget.order.totalAmount,
        'createdAt': widget.order.createdAt ?? FieldValue.serverTimestamp(),
        'createdByUid': widget.order.createdByUid,
        'createdByName': widget.order.createdByName,
        'customerId': widget.order.customerId,
        'customerName': widget.order.customerName,
        'customerPhone': widget.order.customerPhone,
      }, SetOptions(merge: true));

      // 2. Lưu Bill vào Firestore
      // Nếu đã có kết quả HĐĐT từ trước (được truyền vào), cập nhật luôn vào billData
      if (preCreatedEInvoiceResult != null) {
        billData['eInvoiceInfo'] = preCreatedEInvoiceResult.toJson();
      }

      await firestore.setBill(newBillId, billData);

      // 3. Dọn dẹp bàn & Web Order
      await firestore.unlinkMergedTables(widget.order.tableId);
      final String webOrderId = widget.order.id;
      final String expectedTableId = 'ship_$webOrderId';
      if (widget.order.tableId == expectedTableId) {
        try {
          await FirebaseFirestore.instance
              .collection('web_orders')
              .doc(webOrderId)
              .update({
            'status': 'Đã hoàn tất',
            'completedAt': FieldValue.serverTimestamp(),
            'completedBy':
            widget.currentUser.name ?? widget.currentUser.phoneNumber,
          });
          await firestore.deleteTable(widget.order.tableId);
        } catch (_) {}
      }

      // 4. Trừ kho (Inventory)
      try {
        await InventoryService()
            .processStockDeductionForOrder(billItems, widget.order.storeId);
      } catch (e) {
        debugPrint("Background Inventory Error: $e");
      }

      // 5. Cập nhật Voucher & Điểm
      if (_appliedVoucher != null && _appliedVoucher!.quantity != null) {
        firestore.updateVoucher(_appliedVoucher!.id, {
          'quantity': FieldValue.increment(-1),
          'usedCount': FieldValue.increment(1),
        });
      }
      if (widget.customer != null) {
        final int pointsUsed = parseVN(_pointsController.text).toInt();
        final int pointsChange = pointsEarned - pointsUsed;

        if (pointsChange != 0) {
          firestore.updateCustomerPoints(widget.customer!.id, pointsChange);
        }
        if (_debtAmount > 0) {
          firestore.updateCustomerDebt(widget.customer!.id, _debtAmount);
        }
        try {
          await FirebaseFirestore.instance
              .collection('customers')
              .doc(widget.customer!.id)
              .update({
            'totalSpent': FieldValue.increment(result.totalPayable), // Cộng dồn tiền
            'lastVisit': FieldValue.serverTimestamp(), // Cập nhật ngày ghé thăm
          });
        } catch (e) {
          debugPrint("Lỗi cập nhật TotalSpent: $e");
        }
      }

      // 6. Xuất Hóa đơn điện tử (Logic Mới)
      // Chỉ tạo mới nếu chưa có kết quả (tức là preCreatedEInvoiceResult là null)
      if (_autoIssueEInvoice && preCreatedEInvoiceResult == null) {
        try {
          final eResult = await _eInvoiceService.createInvoice(
            billData,
            widget.customer,
            ownerUid,
          );
          await firestore
              .updateBill(newBillId, {'eInvoiceInfo': eResult.toJson()});
        } catch (e) {
          debugPrint("Background E-Invoice Error: $e");
        }
      }
    } catch (e) {
      debugPrint("CRITICAL BACKGROUND SAVE ERROR: $e");
    }
  }

  Future<void> _sendReceiptToPrintQueue({
    required FirestoreService firestore,
    required List<Map<String, dynamic>> billItems,
    required PaymentResult result,
    required Map<String, dynamic> billData,
    required EInvoiceResult? eInvoiceResult, // <--- Đảm bảo có tham số này
    required String newBillId,
  }) async {
    debugPrint(">>> [DEBUG PAYMENT] Chuẩn bị in song song (Optimized)...");

    try {
      Map<String, String>? storeInfo = _cachedStoreDetails;
      dynamic settings = _cachedStoreSettingsObj;

      if (storeInfo == null || settings == null) {
        final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
        final results = await Future.wait([
          firestore.getStoreDetails(widget.currentUser.storeId),
          SettingsService().getStoreSettings(ownerUid),
        ]);
        storeInfo = results[0] as Map<String, String>?;
        settings = results[1];
      }

      final bool shouldPrintLabel = (settings?.printLabelOnPayment ?? false) && !widget.isRetailMode;

      // 1. IN TEM
      if (shouldPrintLabel) {
        final labelItems = billItems.where((item) {
          final product = item['product'] as Map<String, dynamic>? ?? {};
          final serviceSetup = product['serviceSetup'] as Map<String, dynamic>?;
          return serviceSetup?['isTimeBased'] != true;
        }).toList();

        if (labelItems.isNotEmpty) {
          final double w = settings?.labelWidth ?? 50.0;
          final double h = settings?.labelHeight ?? 30.0;
          final String billCode = newBillId.split('_').last;

          PrintQueueService().addJob(PrintJobType.label, {
            'storeId': widget.currentUser.storeId,
            'tableName': billCode,
            'items': labelItems,
            'labelWidth': w,
            'labelHeight': h,
          });
        }
      }

      if (shouldPrintLabel) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      // 2. IN BILL (Quan trọng: Gọi hàm build payload mới)
      if (widget.printBillAfterPayment && _printReceipt && storeInfo != null) {
        final receiptPayload = _buildReceiptPayload(
          storeInfo: storeInfo,
          billItems: billItems,
          result: result,
          billData: billData,
          eInvoiceResult: eInvoiceResult, // <--- Truyền xuống đây
          newBillId: newBillId,
        );
        PrintQueueService().addJob(PrintJobType.receipt, receiptPayload);
      }

      ToastService().show(message: "Đã gửi lệnh in.", type: ToastType.success);
    } catch (e) {
      debugPrint(">>> [DEBUG PAYMENT] Lỗi quy trình in: $e");
    }
  }

  Map<String, dynamic> _buildReceiptPayload({
    required Map<String, String> storeInfo,
    required List<Map<String, dynamic>> billItems,
    required PaymentResult result,
    required Map<String, dynamic> billData,
    required EInvoiceResult? eInvoiceResult, // <--- Đảm bảo có tham số này
    required String newBillId,
  }) {
    final List<Map<String, dynamic>> formattedSurcharges =
    result.surcharges.map((s) {
      if (s.isPercent) {
        final double calculatedAmount = widget.subtotal * (s.amount / 100);
        return {
          'name': '${s.name} (${formatNumber(s.amount)}%)',
          'amount': calculatedAmount,
          'isPercent': true,
        };
      } else {
        return {
          'name': s.name,
          'amount': s.amount,
          'isPercent': false,
        };
      }
    }).toList();

    final double discountInput = parseVN(_discountController.text);
    String discountName = 'Chiết khấu';
    if (result.discountType == '%') {
      discountName = 'Chiết khấu (${formatNumber(discountInput)}%)';
    }

    // Debug log để kiểm tra xem có dữ liệu HĐĐT không
    if (eInvoiceResult != null) {
      debugPrint(">>> [PAYLOAD] Đang đóng gói HĐĐT vào lệnh in: ${eInvoiceResult.lookupUrl}");
    } else {
      debugPrint(">>> [PAYLOAD] Không có thông tin HĐĐT để in.");
    }
    final double debtToPrint = (billData['hideDebt'] == true) ? 0.0 : _debtAmount;
    return {
      'storeId': widget.currentUser.storeId,
      'tableName': widget.isRetailMode ? '' : widget.order.tableName,
      'userName': widget.currentUser.name ?? 'Unknown',
      'items': billItems,
      'storeInfo': storeInfo,
      'showPrices': true,
      'title': 'HÓA ĐƠN',
      'summary': {
        'subtotal': widget.subtotal,
        'discount': result.discountAmount,
        'discountType': result.discountType,
        'discountInput': discountInput,
        'discountName': discountName,
        'surcharges': formattedSurcharges,
        'taxPercent': result.taxPercent,
        'taxAmount': result.totalTaxAmount,
        'tncnAmount': result.totalTncnAmount,
        'payments': result.payments,
        'customerPointsUsed': result.customerPointsUsed,
        'changeAmount': result.changeAmount,
        'debtAmount': debtToPrint,
        'totalPayable': _totalPayable,
        'startTime': widget.order.startTime,
        'voucherCode': _appliedVoucher?.code,
        'voucherDiscount': _voucherDiscountValue,
        'customer': {
          'name': billData['customerName'] ?? 'Khách lẻ',
          'phone': billData['customerPhone'] ?? '',
          'guestAddress': billData['guestAddress'] ?? '',
        },
        'bankDetails': result.bankDetailsForPrinting,
        'eInvoiceCode': eInvoiceResult?.reservationCode,
        'eInvoiceFullUrl': eInvoiceResult?.lookupUrl,
        'eInvoiceMst': eInvoiceResult?.mst,
        'billCode': newBillId.split('_').last,
        'items': billItems,
        'isRetailMode': widget.isRetailMode,
      },
      'isRetailMode': widget.isRetailMode,
      'billCode': newBillId.split('_').last,
    };
  }

  // Tìm hàm _showCashDialog và thay thế bằng nội dung này
  Future<bool> _showCashDialog() async {
    final result = await showDialog<Map<String, dynamic>>( // [SỬA] Kiểu trả về là Map
      context: context,
      builder: (_) => CashDenominationDialog(
        totalPayable: _debtAmount > 0 ? _debtAmount : _totalPayable,
        initialCash: parseVN(_cashInputController.text),
        hasCustomer: widget.customer != null, // [THÊM] Truyền thông tin có khách hay không
      ),
    );

    if (result != null) {
      final double val = result['value'] as double;
      final bool isDebtConfirmed = result['isDebtConfirmed'] as bool;

      _cashInputController.text = formatNumber(val);
      _onCashInputChanged(); // Trigger tính lại tiền thừa/thiếu

      return isDebtConfirmed; // Trả về true nếu bấm Ghi nợ
    }
    return false;
  }

  Future<void> _sendUnsentItemsToKitchen() async {
    final firestore = FirestoreService();

    // 1. Tìm các món chưa được gửi đi (logic này đã đúng)
    final allItems =
    widget.order.items.map((e) => Map<String, dynamic>.from(e)).toList();
    final unsentItemsMaps = allItems.where((itemMap) {
      final double q = ((itemMap['quantity'] ?? 0) as num).toDouble();
      final double sent = ((itemMap['sentQuantity'] ?? 0) as num).toDouble();
      final String status = (itemMap['status'] as String?) ?? 'active';
      return status != 'cancelled' && q > sent;
    }).toList();

    if (unsentItemsMaps.isEmpty) return;

    // 2. Chuẩn bị payload để in báo bếp (logic này đã đúng)
    final itemsForKitchen = unsentItemsMaps.map((itemMap) {
      final double q = ((itemMap['quantity'] ?? 0) as num).toDouble();
      final double sent = ((itemMap['sentQuantity'] ?? 0) as num).toDouble();
      return {...itemMap, 'quantity': (q - sent)};
    }).toList();

    PrintQueueService().addJob(PrintJobType.kitchen, {
      'storeId': widget.currentUser.storeId,
      'tableName': widget.order.tableName,
      'userName': widget.currentUser.name ?? 'Unknown',
      'items': itemsForKitchen,
    });

    // 3. CẬP NHẬT FIRESTORE VỚI VERSIONING (ĐÃ SỬA LỖI)
    final updatedItems = allItems.map((itemMap) {
      final wasUnsent = unsentItemsMaps
          .any((unsent) => unsent['lineId'] == itemMap['lineId']);
      return wasUnsent
          ? {...itemMap, 'sentQuantity': itemMap['quantity']}
          : itemMap;
    }).toList();

    // Đọc lại đơn hàng để lấy version mới nhất, tránh xung đột
    final orderDoc = await firestore.getOrderReference(widget.order.id).get();
    if (!orderDoc.exists) {
      throw Exception("Đơn hàng không còn tồn tại để báo bếp.");
    }
    final currentVersion =
        (orderDoc.data() as Map<String, dynamic>)['version'] as int? ?? 1;

    await firestore.updateOrder(widget.order.id, {
      'items': updatedItems,
      'updatedAt': FieldValue.serverTimestamp(),
      'version': currentVersion + 1,
    });

    ToastService()
        .show(message: "Báo bếp thành công.", type: ToastType.success);
  }

  Future<void> _printAndExit() async {
    try {
      // BƯỚC 1: KIỂM TRA VÀ TỰ ĐỘNG BÁO BẾP
      final bool hasUnsentItems = widget.order.items.any((item) {
        final double q = ((item['quantity'] ?? 0) as num).toDouble();
        final double sent = ((item['sentQuantity'] ?? 0) as num).toDouble();
        final String status = (item['status'] as String?) ?? 'active';
        return status != 'cancelled' && q > sent;
      });

      if (hasUnsentItems) {
        await _sendUnsentItemsToKitchen(); // Gọi hàm trợ giúp mới
      }

      // BƯỚC 2: IN TẠM TÍNH CHI TIẾT
      await _printDetailedProvisionalBill();

      // BƯỚC 3: LƯU TRẠNG THÁI VÀ THOÁT (LOGIC CŨ)
      final currentState = PaymentState(
        discountAmount: parseVN(_discountController.text),
        isDiscountPercent: _isDiscountPercent,
        voucherCode: _voucherController.text,
        pointsUsed: parseVN(_pointsController.text),
        surcharges: _surcharges,
      );

      ToastService().show(
        message: 'Đã gửi lệnh in tạm tính',
        type: ToastType.success,
      );

      if (widget.onPrintAndExit != null) {
        widget.onPrintAndExit!(currentState);
      } else {
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      debugPrint("Lỗi trong quá trình in tạm tính: $e");
      ToastService()
          .show(message: "Đã xảy ra lỗi, không thể in.", type: ToastType.error);
    }
  }

  Widget _buildCard({
    required String title,
    Widget? trailing,
    required Widget child,
  }) {
    final theme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: theme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold, color: Colors.black)),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _printDetailedProvisionalBill() async {
    try {
      final firestore = FirestoreService();
      final storeInfo =
      await firestore.getStoreDetails(widget.currentUser.storeId);
      if (storeInfo == null) {
        throw Exception("Không tìm thấy thông tin cửa hàng.");
      }

      final orderRef = firestore.getOrderReference(widget.order.id);
      final orderDoc = await orderRef.get();
      if (orderDoc.exists) {
        final currentVersion =
            (orderDoc.data() as Map<String, dynamic>)['version'] as int? ?? 1;
        await orderRef.update({
          'provisionalBillPrintedAt': FieldValue.serverTimestamp(),
          'provisionalBillSource': 'payment_screen',
          'version': currentVersion + 1,
        });
      }

      Map<String, dynamic>? bankDetailsForProvisional;

      if (_defaultPaymentMethodId != null &&
          _defaultPaymentMethodId != _cashMethod?.id) {
        try {
          final defaultMethod = _availableMethods.firstWhere(
                (m) => m.id == _defaultPaymentMethodId,
          );

          if (defaultMethod.qrDisplayOnProvisionalBill) {
            bankDetailsForProvisional = {
              'bankBin': defaultMethod.bankBin,
              'bankAccount': defaultMethod.bankAccount,
            };
          }
        } catch (e) {
          debugPrint("Lỗi tìm PTTT mặc định: $e");
        }
      }

      // --- BẮT ĐẦU SỬA: Tính toán chi tiết thuế cho từng món ---
      // Lấy cấu hình thuế hiện tại
      final bool isDeduction = _calcMethod == 'deduction';
      final rateMap = isDeduction ? kDeductionRates : kDirectRates;
      final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

      // Map lại items để thêm taxRate và taxKey
      final List<Map<String, dynamic>> detailedItems =
      widget.order.items.map((item) {
        final Map<String, dynamic> newItem = Map<String, dynamic>.from(item);

        final productData = item['product'] as Map<String, dynamic>? ?? {};
        final productId = productData['id'] as String?;

        // Tìm mã thuế của sản phẩm
        String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;

        // Fallback nếu key không tồn tại trong bảng thuế hiện tại
        if (!rateMap.containsKey(taxKey)) {
          taxKey = defaultTaxKey;
        }

        final double rate = rateMap[taxKey]?['rate'] ?? 0.0;

        // Gán thông tin thuế vào item để PrintingService đọc được
        newItem['taxRate'] = rate;
        newItem['taxKey'] = taxKey;

        return newItem;
      }).toList();

      final double discountInput = parseVN(_discountController.text);
      String discountName = 'Chiết khấu';
      if (_isDiscountPercent) {
        discountName = 'Chiết khấu (${formatNumber(discountInput)}%)';
      }

      final summaryData = {
        'subtotal': widget.subtotal,
        'discount': _calculateDiscount(),
        'discountType': _isDiscountPercent ? '%' : 'VND',
        'discountInput': parseVN(_discountController.text),
        'discountName': discountName,
        'customerPointsUsed': parseVN(_pointsController.text),
        'taxAmount': _calculatedVatAmount,
        'tncnAmount': _calculatedTncnAmount,
        'taxPercent': 0.0,
        'surcharges': _surcharges
            .map((s) => {
          'name': s.isPercent
              ? '${s.name} (${formatNumber(s.amount)}%)'
              : s.name,
          'amount': s.isPercent
              ? widget.subtotal * (s.amount / 100)
              : s.amount,
          'isPercent': s.isPercent
        })
            .toList(),
        'totalPayable': _totalPayable,
        'startTime': widget.order.startTime,
        'customer': {
          'name': widget.customer?.name,
          'phone': widget.customer?.phone,
          'guestAddress': widget.customerAddress ?? '',
        },
        'payments': {},
        'changeAmount': 0.0,
        'useDetailedLayout': true,
        'bankDetails': bankDetailsForProvisional,
        'items': detailedItems,
        'voucherCode': _appliedVoucher?.code,
        'voucherDiscount': _voucherDiscountValue,
      };

      final printData = {
        'storeId': widget.currentUser.storeId,
        'tableName': widget.order.tableName,
        'userName': widget.currentUser.name ?? 'Unknown',
        'items': detailedItems,
        'showPrices': true,
        'storeInfo': storeInfo,
        'title': 'TẠM TÍNH',
        'summary': summaryData,
      };

      PrintQueueService().addJob(PrintJobType.detailedProvisional, printData);
    } catch (e) {
      debugPrint("Lỗi in tạm tính chi tiết: $e");
      ToastService().show(message: e.toString(), type: ToastType.error);
    }
  }

  Future<bool> _showQrPopup(PaymentMethodModel bankMethod) async {
    _calculateTotal();
    final double amountInInput = _paymentAmounts[bankMethod.id] ?? 0;
    final double amountToPay = amountInInput > 0 ? amountInInput : _debtAmount;

    if (amountToPay <= 0) {
      ToastService().show(
          message: 'Vui lòng nhập số tiền cho PTTT này trước khi tạo mã QR.',
          type: ToastType.warning);
      return false; // Trả về false vì không thể mở popup
    }

    final String staffName = widget.currentUser.name ?? 'NV';
    final String transferContent = '$staffName - ${widget.order.tableName}';

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return VietQRPopup(
          amount: amountToPay,
          orderId: transferContent,
          bankMethod: bankMethod,
        );
      },
    );

    if (result == true) {
      setState(() {
        _confirmedBankMethods.add(bankMethod.id);
      });
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final totalDiscount =
        _calculateDiscount() + _pointsMonetaryValue + _voucherDiscountValue;
    final totalTaxAndSurcharges = _calculatedVatAmount +
        _calculatedTncnAmount +
        _calculateTotalSurcharge();

    return Column(children: [
      Expanded(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.customer != null)
              _buildCard(
                  title: "Khách hàng",
                  child: _CustomerInfoPanel(customer: widget.customer!)),
            _buildCard(
              title: "Tổng thành tiền",
              trailing: Text('${formatNumber(widget.subtotal)} đ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.black)),
              child: const SizedBox.shrink(),
            ),
            _buildCard(
              title: "Chiết khấu & Giảm giá",
              trailing: Text('- ${formatNumber(totalDiscount)} đ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.black, fontWeight: FontWeight.bold)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth > 600;
                  if (isWide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 120,
                          child: AppDropdown<bool>(
                            labelText: "Loại",
                            isDense: true,
                            value: _isDiscountPercent,
                            items: const [
                              DropdownMenuItem(
                                  value: false, child: Text('VND')),
                              DropdownMenuItem(value: true, child: Text('%')),
                            ],
                            onChanged: (val) {
                              setState(() {
                                _isDiscountPercent = val ?? false;
                                _calculateTotal(syncPayment: true);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CustomTextFormField(
                            controller: _discountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              ThousandDecimalInputFormatter(),
                              if (_isDiscountPercent)
                                CenteredRangeTextInputFormatter(
                                    min: 0, max: 100),
                            ],
                            decoration: const InputDecoration(
                                labelText: 'Chiết khấu',
                                prefixIcon: Icon(Icons.discount_outlined),
                                isDense: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomTextFormField(
                            controller: _voucherController,
                            keyboardType: TextInputType.text,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                                labelText: 'Voucher',
                                prefixIcon: Icon(Icons.card_giftcard_outlined)),
                            onChanged: (_) => _calculateTotal(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: CustomTextFormField(
                            controller: _pointsController,
                            keyboardType: TextInputType.number,
                            inputFormatters: [ThousandDecimalInputFormatter()],
                            decoration: InputDecoration(
                                hintText: _redeemRate > 0
                                    ? '-${formatNumber(_redeemRate)}đ/Điểm'
                                    : 'Chưa thiết lập',
                                labelText: 'Điểm thưởng',
                                prefixIcon: const Icon(Icons.star)),
                            onChanged: (_) => _calculateTotal(),
                          ),
                        ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: AppDropdown<bool>(
                              labelText: "Loại",
                              value: _isDiscountPercent,
                              items: const [
                                DropdownMenuItem(
                                    value: false, child: Text('VND')),
                                DropdownMenuItem(value: true, child: Text('%')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _isDiscountPercent = val ?? false;
                                  _calculateTotal();
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CustomTextFormField(
                              controller: _discountController,
                              keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                              inputFormatters: [
                                ThousandDecimalInputFormatter(),
                                if (_isDiscountPercent)
                                  CenteredRangeTextInputFormatter(
                                      min: 0, max: 100),
                              ],
                              decoration: const InputDecoration(
                                  labelText: 'Chiết khấu',
                                  prefixIcon: Icon(Icons.discount_outlined)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CustomTextFormField(
                              controller: _voucherController,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                  labelText: 'Voucher',
                                  prefixIcon:
                                  Icon(Icons.card_giftcard_outlined)),
                              onChanged: (_) => _calculateTotal(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextFormField(
                              controller: _pointsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                ThousandDecimalInputFormatter()
                              ],
                              decoration: InputDecoration(
                                  hintText: _redeemRate > 0
                                      ? '-${formatNumber(_redeemRate)}đ/Điểm'
                                      : 'Chưa thiết lập',
                                  labelText: 'Điểm thưởng',
                                  prefixIcon: const Icon(Icons.star)),
                              onChanged: (_) => _calculateTotal(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            _buildCard(
              title: "Thuế & Phụ thu",
              trailing: Text('+ ${formatNumber(totalTaxAndSurcharges)} đ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.black)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_calculatedVatAmount > 0)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: Icon(Icons.request_quote_outlined,
                          color: Colors.grey.shade600),
                      title: Text(
                          _calcMethod == 'deduction' ? 'Thuế VAT' : 'Thuế Gộp'),
                      trailing: Text(
                        '${formatNumber(_calculatedVatAmount)} đ',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  const SizedBox(height: 12),
                  _buildSurchargeInputs(),
                ],
              ),
            ),
            _buildCard(
              title: "Số tiền khách phải trả",
              trailing: Text('${formatNumber(_totalPayable)} đ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold, color: Colors.red)),
              child: const SizedBox.shrink(),
            ),
            _buildCard(
              title: "Thanh toán",
              child: Column(
                children: [
                  _buildPaymentMethods(),
                  const SizedBox(height: 12),
                  _buildPaymentInputs(),
                ],
              ),
            ),
            _buildCard(
              title: _debtAmount > 0 ? "Dư nợ" : "Tiền thừa",
              trailing: Text(
                  '${formatNumber(_debtAmount > 0 ? _debtAmount : _changeAmount)} đ',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _debtAmount > 0 ? Colors.red : Colors.green)),
              child: const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      _buildActionButtons()
    ]);
  }

  Widget _buildPaymentInputs() {
    if (_selectedMethodIds.isEmpty) return const SizedBox.shrink();

    final sortedIds = _selectedMethodIds.toList()
      ..sort((a, b) {
        if (a == _cashMethod!.id) return -1;
        if (b == _cashMethod!.id) return 1;
        return 0;
      });

    return Column(
      children: sortedIds.map((id) {
        final method = _availableMethods.firstWhere((m) => m.id == id);

        // --- XỬ LÝ TIỀN MẶT (GIỮ NGUYÊN) ---
        if (method.type == PaymentMethodType.cash) {
          return CustomTextFormField(
            controller: _cashInputController,
            readOnly: widget.promptForCash,
            onTap: (widget.promptForCash && _totalPayable > 0)
                ? _showCashDialog
                : null,
            decoration: InputDecoration(
              labelText: 'Tiền mặt',
              prefixIcon: Icon(_getIconForMethodType(method.type)),
              suffixIcon: IconButton(
                icon: const Icon(
                  Icons.calculate_outlined,
                  color: AppTheme.primaryColor,
                ),
                onPressed: _showCashDialog,
                tooltip: 'Gợi ý tiền',
              ),
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandDecimalInputFormatter()],
          );
        }

        // --- XỬ LÝ CÁC PHƯƠNG THỨC KHÁC (SỬA ĐỔI) ---

        // 1. Khởi tạo Controller nếu chưa có
        if (!_paymentControllers.containsKey(method.id)) {
          _paymentControllers[method.id] = TextEditingController(
              text: formatNumber(_paymentAmounts[method.id] ?? 0)
          );
        }

        // [QUAN TRỌNG] Dòng này để sửa lỗi "Undefined name 'controller'"
        final controller = _paymentControllers[method.id];

        return Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: CustomTextFormField(
            // Key phải cố định theo ID
            key: ValueKey(method.id),

            // Controller đã được khai báo ở trên
            controller: controller,

            decoration: InputDecoration(
              labelText: method.name,
              prefixIcon: Icon(_getIconForMethodType(method.type)),
              suffixIcon: (method.type == PaymentMethodType.bank &&
                  method.qrDisplayOnScreen)
                  ? _confirmedBankMethods.contains(method.id)
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : IconButton(
                icon: const Icon(Icons.qr_code_scanner_outlined,
                    color: AppTheme.primaryColor),
                onPressed: () => _showQrPopup(method),
                tooltip: 'Quét QR',
              )
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandDecimalInputFormatter()],
            onChanged: (value) {
              _paymentAmounts[method.id] = parseVN(value);

              if (_confirmedBankMethods.contains(method.id)) {
                setState(() {
                  _confirmedBankMethods.remove(method.id);
                });
              }
              // Gọi hàm tính toán không sync
              _onPaymentInputChanged();
            },
          ),
        );
      }).toList(),
    );
  }

  void _onPaymentInputChanged() {
    // Chỉ dùng để trigger tính lại dư nợ, KHÔNG gán lại giá trị ô nhập (syncPayment: false)
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => _calculateTotal(syncPayment: false));
  }

  Widget _buildSurchargeInputs() {
    if (_surcharges.isEmpty) {
      return TextButton.icon(
        icon: const Icon(Icons.add, size: 18),
        label: const Text('Thêm phụ thu'),
        onPressed: () {
          setState(() {
            _surcharges
                .add(SurchargeItem(name: '', amount: 0, isPercent: false));
            _calculateTotal(syncPayment: true);
          });
        },
      );
    }

    return Column(
      children: [
        ..._surcharges.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;

          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide =
                    constraints.maxWidth > 600;
                if (isWide) {
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: CustomTextFormField(
                          initialValue: item.name,
                          decoration: const InputDecoration(
                            labelText: 'Nội dung phụ thu',
                            prefixIcon: Icon(Icons.add_shopping_cart),
                          ),
                          onChanged: (v) => item.name = v,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 120,
                        child: AppDropdown<bool>(
                          labelText: "Loại",
                          value: item.isPercent,
                          items: const [
                            DropdownMenuItem(value: false, child: Text('VND')),
                            DropdownMenuItem(value: true, child: Text('%')),
                          ],
                          onChanged: (val) {
                            setState(() {
                              item.isPercent = val ?? false;
                              _calculateTotal(syncPayment: true);
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: CustomTextFormField(
                          initialValue:
                          item.amount == 0 ? '' : formatNumber(item.amount),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            ThousandDecimalInputFormatter(),
                            if (item.isPercent)
                              CenteredRangeTextInputFormatter(min: 0, max: 100),
                          ],
                          decoration:
                          const InputDecoration(labelText: 'Giá trị'),
                          onChanged: (val) {
                            final parsed = parseVN(val).toDouble();
                            setState(() {
                              item.amount = parsed;
                              _calculateTotal(syncPayment: true);
                            });
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xoá',
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () {
                          setState(() {
                            _surcharges.removeAt(index);
                            _calculateTotal(syncPayment: true);
                          });
                        },
                      ),
                    ],
                  );
                } else {
                  // === Mobile: vẫn để dọc ===
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextFormField(
                              initialValue: item.name,
                              decoration: const InputDecoration(
                                labelText: 'Nội dung phụ thu',
                                prefixIcon: Icon(Icons.add_shopping_cart),
                              ),
                              onChanged: (v) => item.name = v,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            tooltip: 'Xoá',
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () {
                              setState(() {
                                _surcharges.removeAt(index);
                                _calculateTotal(syncPayment: true);
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          SizedBox(
                            width: 120,
                            child: AppDropdown<bool>(
                              labelText: "Loại",
                              value: item.isPercent,
                              items: const [
                                DropdownMenuItem(
                                    value: false, child: Text('VND')),
                                DropdownMenuItem(value: true, child: Text('%')),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  item.isPercent = val ?? false;
                                  _calculateTotal(syncPayment: true);
                                });
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: CustomTextFormField(
                              initialValue: item.amount == 0
                                  ? ''
                                  : formatNumber(item.amount),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                ThousandDecimalInputFormatter()
                              ],
                              decoration:
                              const InputDecoration(labelText: 'Giá trị'),
                              onChanged: (val) {
                                final parsed = parseVN(val).toDouble();
                                setState(() {
                                  item.amount = parsed;
                                  _calculateTotal(syncPayment: true);
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }
              },
            ),
          );
        }),
        TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Thêm phụ thu khác'),
          onPressed: () {
            setState(() {
              _surcharges
                  .add(SurchargeItem(name: '', amount: 0, isPercent: false));
              _calculateTotal(syncPayment: true);
            });
          },
        ),
      ],
    );
  }

  Widget _buildPaymentMethods() {
    if (!_methodsLoaded) {
      return const Center(child: Text('Đang tải PTTT...'));
    }

    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      child: Wrap(
        spacing: 8.0,
        runSpacing: 8.0,
        alignment: WrapAlignment.center,
        children: _availableMethods.map((method) {
          final isSelected = _selectedMethodIds.contains(method.id);

          return ChoiceChip(
            label: Text(
              method.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isSelected ? AppTheme.primaryColor : AppTheme.textColor,
              ),
            ),
            selected: isSelected,
            showCheckmark: false,
            backgroundColor: Colors.white,
            selectedColor: AppTheme.primaryColor.withAlpha(38),
            avatar: Icon(
              _getIconForMethodType(method.type),
              size: 20,
              color: isSelected ? AppTheme.primaryColor : Colors.grey[700],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.0),
            ),
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primaryColor.withAlpha(8)
                  : Colors.grey.shade300,
            ),
            onSelected: (selected) {
              _calculateTotal();
              final currentDebt = _debtAmount;

              setState(() {
                if (selected) {
                  final otherPayments = Map.from(_paymentAmounts)
                    ..remove(method.id);
                  final bool alreadyPaidFull = (currentDebt <= 0) &&
                      otherPayments.values.any((v) => (v as double) > 0);

                  if (alreadyPaidFull) {
                    ToastService().show(
                        message: 'Đã đủ tiền, không cần thêm PTTT.',
                        type: ToastType.warning);
                    return;
                  }

                  _selectedMethodIds.add(method.id);

                  double amountToSet;
                  final double remainingAmount = (currentDebt > 0)
                      ? currentDebt
                      : (_totalPayable > 0 ? _totalPayable : 0);

                  if (method.type == PaymentMethodType.cash) {
                    if (widget.promptForCash) {
                      amountToSet = 0;
                      if (remainingAmount > 0) {
                        Future.delayed(Duration.zero, _showCashDialog);
                      }
                    } else {
                      amountToSet = remainingAmount;
                    }
                  } else {
                    amountToSet = remainingAmount;
                  }

                  if ((_paymentAmounts[method.id] ?? 0) == 0) {
                    _paymentAmounts[method.id] = amountToSet;

                    if (method.type == PaymentMethodType.cash) {
                      _cashInputController.removeListener(_onCashInputChanged);
                      _cashInputController.text = formatNumber(amountToSet);
                      _cashInputController.addListener(_onCashInputChanged);
                    }
                  }
                } else {
                  _selectedMethodIds.remove(method.id);
                  _paymentAmounts.remove(method.id);

                  if (method.type == PaymentMethodType.cash) {
                    _cashInputController.removeListener(_onCashInputChanged);
                    _cashInputController.clear();
                    _cashInputController.addListener(_onCashInputChanged);
                  }
                  if (_confirmedBankMethods.contains(method.id)) {
                    _confirmedBankMethods.remove(method.id);
                  }
                }

                _calculateTotal();
              });
            },
          );
        }).toList(),
      ),
    );
  }

  IconData _getIconForMethodType(PaymentMethodType type) {
    switch (type) {
      case PaymentMethodType.cash:
        return Icons.money_outlined;
      case PaymentMethodType.bank:
        return Icons.account_balance_outlined;
      case PaymentMethodType.card:
        return Icons.credit_card_outlined;
      case PaymentMethodType.other:
        return Icons.payment_outlined;
    }
  }

  Widget _buildActionButtons() {
    final bool isMobile = MediaQuery.of(context).size.width < 800;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withAlpha(12),
                blurRadius: 10,
                offset: const Offset(0, -5))
          ],
          border:
          Border(top: BorderSide(color: Colors.grey.shade200, width: 1.0))),

      // KIỂM TRA CHẾ ĐỘ ĐỂ HIỆN NÚT TƯƠNG ỨNG
      child: widget.isRetailMode
          ? _buildRetailButtons(isMobile) // Nếu là Retail -> Hiện bộ nút mới
          : _buildFnBButtons(isMobile), // Nếu là F&B -> Hiện bộ nút cũ
    );
  }

  Widget _buildFnBButtons(bool isMobile) {
    return Row(
      children: [
        if (!isMobile) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _isProcessingPayment ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Hủy'),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _isProcessingPayment ? null : _printAndExit,
            icon: const Icon(Icons.print_outlined, size: 20),
            label: const Text('Tạm Tính'),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: ElevatedButton(
            // F&B gọi không tham số -> in theo cấu hình
            onPressed: _isProcessingPayment ? null : () => _confirmPayment(),
            style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _isProcessingPayment
                ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 3))
                : const Text('Xác Nhận Thanh Toán'),
          ),
        ),
      ],
    );
  }

  Widget _buildRetailButtons(bool isMobile) {
    // Kiểm tra xem đây có phải là đơn Giao hàng không
    final bool isShipOrder = widget.order.tableName.toLowerCase().contains('giao hàng');

    return Row(
      children: [
        if (!isMobile) ...[
          Expanded(
            child: OutlinedButton(
              onPressed: _isProcessingPayment ? null : widget.onCancel,
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
              child: const Text('Hủy'),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // Nút Thanh toán (Giữ nguyên: Luôn thanh toán nhưng KHÔNG in)
        Expanded(
          child: ElevatedButton(
            onPressed: _isProcessingPayment
                ? null
                : () => _confirmPayment(forcePrint: false),
            style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
            child: const Text('Thanh toán'),
          ),
        ),
        const SizedBox(width: 8),

        // Nút Bên Phải (Thay đổi logic tùy theo là Ship hay Tại quầy)
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: _isProcessingPayment
                ? null
                : () {
              if (isShipOrder) {
                // Nếu là Ship -> Chỉ In Bill (Gọi hàm mới)
                _printShipBillOnly();
              } else {
                // Nếu là Tại quầy -> Thanh toán & In (Logic cũ)
                _confirmPayment(forcePrint: true);
              }
            },
            icon: const Icon(Icons.print),
            label: _isProcessingPayment
                ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 3))
                : Text(isShipOrder ? 'In Bill (Ship)' : 'Thanh toán & In'), // Đổi tên nút
            style: ElevatedButton.styleFrom(
                backgroundColor: isShipOrder ? Colors.orange : AppTheme.primaryColor, // Đổi màu cam cho dễ phân biệt nếu muốn
                padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
        ),
      ],
    );
  }

  double _calculateTotalProfit() {
    // 1. Tính TỔNG GIÁ VỐN (Total COGS)
    double totalCost = 0.0;

    for (final itemMap in widget.order.items) {
      final product = itemMap['product'] as Map<String, dynamic>? ?? {};

      // Giá vốn nhập trong danh mục (Với DV giờ thì đây là Chi phí/Giờ)
      final double costPrice = (product['costPrice'] as num?)?.toDouble() ?? 0.0;

      final isTimeBased = product['serviceSetup']?['isTimeBased'] == true;

      if (isTimeBased) {
        // [SỬA LẠI LOGIC TÍNH GIÁ VỐN DỊCH VỤ TÍNH GIỜ]
        // Công thức: Chi phí = (Giá vốn 1 giờ / 60) * Tổng số phút sử dụng

        double totalMinutes = 0;
        final priceBreakdown = itemMap['priceBreakdown'];

        if (priceBreakdown is List) {
          for (final block in priceBreakdown) {
            // Kiểm tra kiểu dữ liệu để lấy số phút an toàn
            if (block is Map) {
              totalMinutes += (block['minutes'] as num?)?.toDouble() ?? 0;
            } else if (block is TimeBlock) {
              // Trường hợp itemMap giữ object TimeBlock (hiếm nhưng có thể xảy ra)
              totalMinutes += block.minutes.toDouble();
            }
          }
        }

        // Tính chi phí hoạt động dựa trên thời gian thực tế
        totalCost += (costPrice / 60.0) * totalMinutes;

      } else {
        // Hàng hóa thường: Giá vốn * Số lượng
        final double quantity = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
        totalCost += costPrice * quantity;
      }
    }

    // 2. Tính TỔNG GIẢM GIÁ CẤP HÓA ĐƠN
    final double totalBillDiscount = _calculateDiscount() +
        _voucherDiscountValue +
        _pointsMonetaryValue;

    // 3. Tính DOANH THU THUẦN (Net Revenue) từ hàng hóa
    // widget.subtotal: Là tổng tiền hàng (đã trừ giảm giá từng món, chưa gồm thuế/phụ thu)
    final double netRevenue = widget.subtotal - totalBillDiscount;

    // 4. Lợi nhuận = Doanh thu thuần - Tổng giá vốn
    return netRevenue - totalCost;
  }
}

class _CustomerInfoPanel extends StatelessWidget {
  final CustomerModel? customer;

  const _CustomerInfoPanel({this.customer});

  @override
  Widget build(BuildContext context) {
    if (customer == null) {
      return ListTile(
        leading: const Icon(Icons.person, color: Colors.grey),
        title: Text('Khách lẻ',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold)),
        contentPadding: EdgeInsets.zero,
      );
    }
    final int points = customer!.points;
    final double debt = customer!.debt ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withAlpha(15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(customer!.name,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _InfoTile(
                  icon: Icons.receipt_long,
                  label: 'Dư nợ:',
                  value: '${formatNumber(debt)} đ'),
              _InfoTile(
                  icon: Icons.star,
                  label: 'Điểm thưởng:',
                  value: formatNumber(points.toDouble())),
            ],
          )
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600, size: 20),
        const SizedBox(width: 4),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: Colors.grey.shade600)),
        const SizedBox(width: 4),
        Text(value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Colors.grey.shade600, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class CashDenominationDialog extends StatefulWidget {
  final double totalPayable;
  final double initialCash;
  final bool hasCustomer;
  const CashDenominationDialog(
      {super.key, required this.totalPayable, required this.initialCash, required this.hasCustomer,});

  @override
  State<CashDenominationDialog> createState() => _CashDenominationDialogState();
}

class _CashDenominationDialogState extends State<CashDenominationDialog> {
  final List<int> denominations = [
    500000,
    200000,
    100000,
    50000,
    20000,
    10000,
    5000,
    2000,
    1000
  ];
  final Map<int, int> _quantities = {};
  double _totalCash = 0;
  bool _isPopping = false;

  @override
  void initState() {
    super.initState();
    _totalCash = 0;
  }

  void _recalculateTotal() {
    double total = 0;
    _quantities.forEach((denomination, quantity) {
      total += (denomination * quantity).toDouble();
    });
    setState(() => _totalCash = total);
  }

  void _addDenomination(int den) {
    setState(() {
      final currentQty = _quantities[den] ?? 0;
      _quantities[den] = currentQty + 1;
    });
    _recalculateTotal();
  }

  void _reset() {
    setState(() {
      _quantities.clear();
    });
    _recalculateTotal();
  }

  void _safePop(Map<String, dynamic>? result) {
    if (_isPopping) return; // Nếu đang đóng thì chặn lại ngay
    _isPopping = true;
    if (mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width >= 600;

    // Tính toán width mong muốn
    final double dialogWidth = isDesktop ? 350 : (size.width * 0.9);

    final double change = _totalCash - widget.totalPayable;
    final double changeToDisplay = change > 0 ? change : 0;

    return AlertDialog(
      title: const Text('Tiền mặt khách đưa'),

      // Giữ nguyên setting padding này để popup bung rộng
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      contentPadding: const EdgeInsets.fromLTRB(0, 20, 0, 24),

      content: Container(
        width: dialogWidth,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Phải trả: ${formatNumber(widget.totalPayable)} đ',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tổng nhận: ${formatNumber(_totalCash)} đ',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.primaryColor, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Tiền thừa: ${formatNumber(changeToDisplay)} đ',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
            const SizedBox(height: 16),

            // --- PHẦN GRIDVIEW ĐÃ SỬA ---
            SizedBox(
              // Giảm chiều cao xuống một chút cho gọn (vì nút đã nhỏ lại)
              height: isDesktop ? 250 : 200,
              child: GridView.builder(
                // Xóa logic if/else vì giờ cả Desktop và Mobile đều dùng 3 cột
                itemCount: denominations.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, // <--- SỬA THÀNH 3 CỘT
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  // Tăng tỷ lệ này lên để nút thấp xuống (nhỏ lại về chiều cao)
                  // 2.4 nghĩa là Chiều rộng = 2.4 lần Chiều cao
                  childAspectRatio: 2.4,
                ),
                itemBuilder: (context, index) {
                  final den = denominations[index];
                  final qty = _quantities[den] ?? 0;
                  return _denominationCell(den, qty);
                },
              ),
            ),
            // -----------------------------
          ],
        ),
      ),
      actions: [
        if (widget.hasCustomer)
          TextButton(
            onPressed: () =>
                _safePop({'value': _totalCash, 'isDebtConfirmed': true}),
            child: const Text('Ghi nợ',
                style:
                TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        TextButton(
          onPressed: _reset,
          child: const Text('Reset'),
        ),
        TextButton(
            onPressed: () => _safePop(null),
            child: const Text('Hủy')),
        ElevatedButton(
            onPressed: () =>
                _safePop({'value': _totalCash, 'isDebtConfirmed': false}),
            child: const Text('Xong')),
      ],
    );
  }

  Widget _denominationCell(int den, int qty) {
    return GestureDetector(
      onTap: () => _addDenomination(den),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
            elevation: 1,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade300),
            ),
            child: Center(
              child: Text(
                formatNumber(den.toDouble()),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textColor,
                  fontSize: 18,
                ),
              ),
            ),
          ),
          if (qty > 0)
            Positioned(
              top: -5,
              right: -5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  '$qty',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CenteredRangeTextInputFormatter extends TextInputFormatter {
  final double min;
  final double max;

  CenteredRangeTextInputFormatter({required this.min, required this.max});

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }
    final double? value = double.tryParse(newValue.text.replaceAll(',', ''));
    if (value == null) {
      return oldValue;
    }
    if (value > max) {
      return oldValue;
    }
    return newValue;
  }
}