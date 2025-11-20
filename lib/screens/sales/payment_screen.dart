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
import '../../screens/tax_management_screen.dart' show kDirectRates, kDeductionRates;

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
        onCancel: () {},
        onConfirmPayment: (result) {},
      ),
    );
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
  });

  @override
  State<_PaymentPanel> createState() => _PaymentPanelState();
}

class _PaymentPanelState extends State<_PaymentPanel> {
  late final TextEditingController _discountController;
  late final TextEditingController _voucherController;
  late final TextEditingController _pointsController;
  late final TextEditingController _cashInputController;

  Map<String, dynamic>? _storeTaxSettings;

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
    final initialState = widget.initialState;
    if (initialState != null) {
      _discountController = TextEditingController(
          text: formatNumber(initialState.discountAmount));
      _voucherController =
          TextEditingController(text: initialState.voucherCode);
      _pointsController = TextEditingController();

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
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    // 1. Tải cài đặt điểm và thuế TRƯỚC
    await Future.wait([
      _loadPointsSettings(),
      _loadStoreTaxSettings(),
    ]);

    // 2. Tính toán tổng tiền (để có _totalPayable bao gồm thuế/phụ phí)
    _calculateTotal(initialLoad: true);

    // 3. Sau đó mới tải PTTT và gán tiền
    await _loadPaymentMethods();

    if (mounted) {
      // 4. Tính toán lại lần cuối để cập nhật UI đầy đủ
      _calculateTotal();

      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      final configStatus = await _eInvoiceService.getConfigStatus(ownerUid);
      if (configStatus.isConfigured) {
        setState(() {
          _autoIssueEInvoice = configStatus.autoIssueOnPayment;
        });
      }
    }
  }

  Future<void> _loadStoreTaxSettings() async {
    try {
      _storeTaxSettings = await _firestoreService.getStoreTaxSettings(widget.currentUser.storeId);
      if (_storeTaxSettings != null) {
        // 1. Load Map sản phẩm
        final rawMap = _storeTaxSettings!['taxAssignmentMap'] as Map<String, dynamic>? ?? {}; // Đổi tên key cho đúng với TaxManager mới
        _productTaxRateMap.clear();
        rawMap.forEach((taxKey, productIds) {
          if (productIds is List) {
            for (final productId in productIds) {
              _productTaxRateMap[productId as String] = taxKey;
            }
          }
        });

        // 2. Load Phương pháp tính thuế (Quan trọng)
        // Ưu tiên lấy từ calcMethod, nếu không có thì fallback về logic cũ
        if (_storeTaxSettings!.containsKey('calcMethod')) {
          _calcMethod = _storeTaxSettings!['calcMethod'];
        } else {
          // Logic fallback cho dữ liệu cũ (nếu cần)
          final entityType = _storeTaxSettings!['entityType'] ?? 'hkd';
          _calcMethod = (entityType == 'dn') ? 'deduction' : 'direct';
        }
      }
    } catch (e) {
      debugPrint("Lỗi tải cài đặt thuế: $e");
    }
  }

  Future<void> _loadPointsSettings() async {
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

      final settings = await SettingsService().getStoreSettings(ownerUid);
      final pointsSettings = await FirestoreService()
          .loadPointsSettings(widget.currentUser.storeId);

      if (mounted) {
        setState(() {
          _earnRate = pointsSettings['earnRate'] ?? 0.0;
          _redeemRate = pointsSettings['redeemRate'] ?? 0.0;
          _defaultPaymentMethodId = settings.defaultPaymentMethodId;
          _settingsLoaded = true;
        });
      }
    } catch (e) {
      ToastService()
          .show(message: "Không thể tải cài đặt.", type: ToastType.error);
      if (mounted) {
        setState(() {
          _settingsLoaded = true;
        });
      }
    }
  }

  @override
  void didUpdateWidget(covariant _PaymentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.subtotal != oldWidget.subtotal) {
      _calculateTotal();
    }
  }

  void _addListeners() {
    _discountController.addListener(_onInputChanged);
    _pointsController.addListener(_onInputChanged);
    _cashInputController.addListener(_onCashInputChanged);
    _voucherController.addListener(() {
      if (_voucherDebounce?.isActive ?? false) _voucherDebounce!.cancel();
      _voucherDebounce =
          Timer(const Duration(milliseconds: 800), _applyVoucher);
    });
  }

  void _onInputChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), _calculateTotal);
  }

  void _onCashInputChanged() {
    if (_selectedMethodIds.contains(_cashMethod!.id)) {
      final cashAmount = parseVN(_cashInputController.text);
      _paymentAmounts[_cashMethod!.id] = cashAmount;
    }

    _onInputChanged();
  }

  @override
  void dispose() {
    _discountController.dispose();
    _voucherController.dispose();
    _pointsController.dispose();
    _cashInputController.dispose();
    _debounce?.cancel();
    _voucherDebounce?.cancel();
    super.dispose();
  }

  Future<void> _applyVoucher() async {
    final code = _voucherController.text.trim();
    if (code.isEmpty) {
      if (_appliedVoucher != null) {
        setState(() {
          _appliedVoucher = null;
          _voucherDiscountValue = 0;
        });
        _calculateTotal();
      }
      return;
    }

    final voucher = await FirestoreService()
        .validateVoucher(code, widget.currentUser.storeId);
    if (voucher != null) {
      setState(() {
        _appliedVoucher = voucher;
        if (voucher.isPercent) {
          _voucherDiscountValue = widget.subtotal * (voucher.value / 100);
        } else {
          _voucherDiscountValue = voucher.value;
        }
        ToastService().show(
            message: "Đã áp dụng voucher: ${voucher.code}",
            type: ToastType.success);
      });
    } else {
      setState(() {
        _appliedVoucher = null;
        _voucherDiscountValue = 0;
      });
      ToastService().show(
          message: "Voucher không hợp lệ hoặc đã hết hạn.",
          type: ToastType.error);
    }
    _calculateTotal();
  }

  double _calculateDiscount() {
    final discountInput = parseVN(_discountController.text);
    if (_isDiscountPercent && discountInput > 100) return widget.subtotal;
    return _isDiscountPercent
        ? (widget.subtotal * discountInput / 100)
        : discountInput;
  }

  (double, double) _getCalculatedTaxes() {
    if (_storeTaxSettings == null) {
      return (0.0, 0.0);
    }

    double totalTax = 0.0;

    final bool isDeduction = _calcMethod == 'deduction';
    final rateMap = isDeduction ? kDeductionRates : kDirectRates;
    final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

    for (final item in widget.order.items) {
      final productMap = (item['product'] as Map<String, dynamic>?) ?? {};
      final productId = productMap['id'] as String?;

      String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;

      if (!rateMap.containsKey(taxKey)) {
        taxKey = defaultTaxKey;
      }

      final double itemSubtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
      final double rate = rateMap[taxKey]?['rate'] ?? 0.0;
      totalTax += (itemSubtotal * rate);
    }

    return (totalTax.roundToDouble(), 0.0);
  }

  void _calculateTotal({bool initialLoad = false}) {
    if (!initialLoad && (!_settingsLoaded || !_methodsLoaded || _storeTaxSettings == null)) return;

    final (newVatAmount, newTncnAmount) = _getCalculatedTaxes();
    final subtotal = widget.subtotal;
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
    final totalSurcharge = _calculateTotalSurcharge();

    double taxToAdd = newVatAmount + newTncnAmount;
    final double finalTotal = (subtotal - discountAmount - pointsValue - _voucherDiscountValue + totalSurcharge + taxToAdd);
    final newTotalPayable = finalTotal > 0 ? finalTotal.roundToDouble() : 0.0;

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
        _totalPayable = newTotalPayable; // Cập nhật biến tổng tiền
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

  Future<void> _confirmPayment() async {
    if (_isProcessingPayment) return;

    _calculateTotal();

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
            message: 'Vui lòng nhập số tiền mặt khách đưa',
            type: ToastType.warning);

        await _showCashDialog();
        _calculateTotal();

        if (_debtAmount > 0) {
          return;
        }
      }
    }

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
          type: ToastType.warning,
        );

        final bool wasConfirmed =
            await _showQrPopup(firstUnconfirmedBankMethod);

        if (!wasConfirmed) {
          return;
        }
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

    EInvoiceResult? eInvoiceResult;

    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

    if (_autoIssueEInvoice) {
      String? emailForInvoice = widget.customer?.email;
      if (widget.customer != null &&
          (emailForInvoice == null || emailForInvoice.isEmpty)) {
        if (!context.mounted) return;
        final BuildContext safeContext = context;
        final emailController = TextEditingController();
        String? errorText;
        final String? newEmail = await showDialog<String>(
          context: safeContext,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (stfContext, stfSetState) {
                return AlertDialog(
                  title: const Text('Cập nhật Email Khách hàng'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Khách hàng "${widget.customer!.name}" chưa có email.'),
                      const Text(
                          'Vui lòng nhập email để nhận hóa đơn điện tử.'),
                      const SizedBox(height: 16),
                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Email',
                          hintText: 'vd: andeptrai@gmail.com',
                          errorText: errorText,
                        ),
                        onChanged: (_) => stfSetState(() => errorText = null),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      child: const Text('Hủy'),
                      onPressed: () => Navigator.of(dialogContext).pop(null),
                    ),
                    ElevatedButton(
                      child: const Text('Tiếp tục'),
                      onPressed: () {
                        final email = emailController.text.trim();
                        if (email.isEmpty) {
                          Navigator.of(dialogContext).pop('');
                        } else if (!email.contains('@')) {
                          stfSetState(() {
                            errorText = 'Email không hợp lệ';
                          });
                        } else {
                          Navigator.of(dialogContext).pop(email);
                        }
                      },
                    ),
                  ],
                );
              },
            );
          },
        );

        if (newEmail == null) {
          setState(() => _isProcessingPayment = false);
          return;
        } else if (newEmail.isNotEmpty) {
          try {
            await FirebaseFirestore.instance
                .collection('customers')
                .doc(widget.customer!.id)
                .update({'email': newEmail});

            emailForInvoice = newEmail;
            ToastService().show(
                message: "Đã cập nhật email khách hàng!",
                type: ToastType.success);
          } catch (e) {
            if (!context.mounted) return;
            final BuildContext safeContext = context;
            await showDialog(
                context: safeContext,
                builder: (ctx) => AlertDialog(
                        title: const Text("Lỗi Lưu Email"),
                        content: Text(
                            "Không thể lưu email mới: ${e.toString()}\n\nVui lòng thử lại."),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text("Đã hiểu"))
                        ]));
            setState(() => _isProcessingPayment = false);
            return;
          }
        }
      }

      try {
        final tempBillData = {
          'items': widget.order.items
              .map((item) => Map<String, dynamic>.from(item))
              .toList(),
          'subtotal': widget.subtotal,
          'totalPayable': _totalPayable,
          'discount': _calculateDiscount(),
          'taxPercent': 0.0,
          'taxAmount': _calculatedVatAmount,
          'payments': Map.fromEntries(_paymentAmounts.entries.map((entry) {
            final id = entry.key;
            final amount = entry.value;
            final name = _availableMethods.firstWhere((m) => m.id == id).name;
            return MapEntry(name, amount);
          })),
          'customerName': widget.customer?.name,
          'customerPhone': widget.customer?.phone,
        };

        eInvoiceResult = await _eInvoiceService.createInvoice(
          tempBillData,
          widget.customer,
          ownerUid,
        );

        ToastService().show(
          message:
              "Xuất HĐĐT (${eInvoiceResult.providerName}) thành công! Số HĐ: ${eInvoiceResult.invoiceNo}",
          type: ToastType.success,
        );
      } catch (e) {
        setState(() => _isProcessingPayment = false);
        if (!context.mounted) return;
        final BuildContext safeContext = context;
        final continuePayment = await showDialog<bool>(
          context: safeContext,
          builder: (context) => AlertDialog(
            title: const Text('Lỗi Xuất Hóa Đơn Điện Tử'),
            content: Text(
                'Đã xảy ra lỗi: ${e.toString()}\n\nBạn có muốn tiếp tục thanh toán mà không xuất hóa đơn điện tử không?'),
            actions: [
              TextButton(
                child: const Text('Hủy'),
                onPressed: () => Navigator.of(context).pop(false),
              ),
              ElevatedButton(
                child: const Text('Tiếp tục'),
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        );
        if (continuePayment != true) {
          return;
        }
      }
    }

    if (!_isProcessingPayment) {
      setState(() {
        _isProcessingPayment = true;
      });
    }

    try {
      final validPayments = Map.fromEntries(
        _paymentAmounts.entries.where((e) => e.value > 0),
      );

      String? firstBankMethodId;
      try {
        firstBankMethodId = validPayments.keys.firstWhere(
          (id) => id != _cashMethod!.id,
        );
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

      final bool isDeduction = _calcMethod == 'deduction';
      final rateMap = isDeduction ? kDeductionRates : kDirectRates;
      final String defaultTaxKey = isDeduction ? 'VAT_0' : 'HKD_0';

      final List<Map<String, dynamic>> billItems = widget.order.items.map((item) {
        final Map<String, dynamic> newItem = Map<String, dynamic>.from(item);

        // 1. Logic xử lý sản phẩm tính giờ (Giữ nguyên logic cũ)
        final productData = item['product'] as Map<String, dynamic>? ?? {};
        final serviceSetup = productData['serviceSetup'] as Map<String, dynamic>?;
        final isTimeBased = serviceSetup?['isTimeBased'] == true;
        if (isTimeBased) {
          final priceBreakdown = List<Map<String, dynamic>>.from(item['priceBreakdown'] ?? []);
          int totalMinutes = 0;
          for (var block in priceBreakdown) {
            totalMinutes += (block['minutes'] as num?)?.toInt() ?? 0;
          }
          if (totalMinutes > 0) {
            newItem['quantity'] = totalMinutes / 60.0;
          }
        }

        // 2. LOGIC MỚI: Lưu chi tiết thuế vào từng dòng
        final productId = productData['id'] as String?;
        String taxKey = _productTaxRateMap[productId] ?? defaultTaxKey;
        if (!rateMap.containsKey(taxKey)) taxKey = defaultTaxKey;

        final double rate = rateMap[taxKey]?['rate'] ?? 0.0;
        final double subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
        final double taxAmt = subtotal * rate; // Tiền thuế của dòng này

        newItem['taxAmount'] = taxAmt; // Lưu tiền thuế
        newItem['taxRate'] = rate;     // Lưu tỷ lệ %
        newItem['taxKey'] = taxKey;    // Lưu mã thuế (HKD_RETAIL, VAT_10...)

        return newItem;
      }).toList();

      final firestore = FirestoreService();
      final double totalProfit = _calculateTotalProfit();
      int pointsEarned = 0;
      if (widget.customer != null && _earnRate > 0) {
        pointsEarned = (_totalPayable / _earnRate).floor();
      }
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

      final billData = {
        'orderId': widget.order.id,
        'storeId': widget.order.storeId,
        'tableName': widget.order.tableName,
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
        'eInvoiceInfo': eInvoiceResult?.toJson(),
        'customerId': widget.customer?.id,
        'customerName': widget.customer?.name,
        'customerPhone': widget.customer?.phone,
        'guestAddress': widget.customerAddress,
      };

      final String newBillId = await firestore.addBill(billData);

      await firestore.updateOrder(widget.order.id, {
        'status': 'paid',
        'billId': newBillId,
        'paidAt': FieldValue.serverTimestamp(),
        'paidByUid': widget.currentUser.uid,
        'paidByName': widget.currentUser.name ?? widget.currentUser.phoneNumber,
        'finalAmount': _totalPayable,
        'debtAmount': _debtAmount,
        'items': billItems,
        'totalAmount': widget.subtotal,
        'discount': result.discountAmount,
        'discountType': result.discountType,
        'surcharges': billData['surcharges'],
        'taxPercent': result.taxPercent,
        'taxAmount': billData['taxAmount'],
        'payments': billData['payments'],
        'updatedAt': FieldValue.serverTimestamp(),
        'version': widget.order.version + 1,
        'voucherCode': _appliedVoucher?.code,
        'voucherDiscount': _voucherDiscountValue,
        'customerId': widget.customer?.id,
        'customerName': widget.customer?.name,
        'customerPhone': widget.customer?.phone,
        'guestAddress': widget.customerAddress,
      });

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
        } catch (e) {
          debugPrint("Lỗi khi hoàn tất web_order $webOrderId: $e");
        }
      }

      if (_appliedVoucher != null && _appliedVoucher!.quantity != null) {
        await firestore.updateVoucher(_appliedVoucher!.id, {
          'quantity': FieldValue.increment(-1),
          'usedCount': FieldValue.increment(1),
        });
      }

      if (widget.customer != null) {
        final int pointsUsed = parseVN(_pointsController.text).toInt();
        final int pointsChange = pointsEarned - pointsUsed;
        if (pointsChange != 0) {
          await firestore.updateCustomerPoints(
              widget.customer!.id, pointsChange);
        }
        if (_debtAmount > 0) {
          await firestore.updateCustomerDebt(widget.customer!.id, _debtAmount);
        }
      }

      try {
        await InventoryService().processStockDeductionForOrder(
            List<Map<String, dynamic>>.from(widget.order.items),
            widget.order.storeId);
      } catch (e) {
        debugPrint("Lỗi nghiêm trọng khi trừ tồn kho: $e");
        ToastService().show(
            message: "Cảnh báo: Có lỗi xảy ra khi cập nhật tồn kho.",
            type: ToastType.warning);
      }

      await _sendReceiptToPrintQueue(
        firestore: firestore,
        billItems: billItems,
        result: result,
        billData: billData,
        eInvoiceResult: eInvoiceResult,
        newBillId: newBillId,
      );

      widget.onConfirmPayment(result);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      ToastService()
          .show(message: 'Lỗi lưu thanh toán: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingPayment = false;
        });
      }
    }
  }

  Future<void> _sendReceiptToPrintQueue({
    required FirestoreService firestore,
    required List<Map<String, dynamic>> billItems,
    required PaymentResult result,
    required Map<String, dynamic> billData,
    required EInvoiceResult? eInvoiceResult,
    required String newBillId,
  }) async {
    if (!widget.printBillAfterPayment || !_printReceipt) {
      return;
    }
    try {
      final storeInfo =
          await firestore.getStoreDetails(widget.currentUser.storeId);

      if (storeInfo == null) {
        ToastService().show(
            message: 'Lỗi khi in: Không thể tải thông tin cửa hàng.',
            type: ToastType.error);
        return;
      }

      final receiptPayload = _buildReceiptPayload(
        storeInfo: storeInfo,
        billItems: billItems,
        result: result,
        billData: billData,
        eInvoiceResult: eInvoiceResult,
        newBillId: newBillId,
      );

      PrintQueueService().addJob(PrintJobType.receipt, receiptPayload);

      ToastService().show(
        message: 'Đã gửi lệnh in hóa đơn',
        type: ToastType.success,
      );
    } catch (e) {
      ToastService().show(message: 'Lỗi khi in: $e', type: ToastType.error);
    }
  }

  Map<String, dynamic> _buildReceiptPayload({
    required Map<String, String> storeInfo,
    required List<Map<String, dynamic>> billItems,
    required PaymentResult result,
    required Map<String, dynamic> billData,
    required EInvoiceResult? eInvoiceResult,
    required String newBillId,
  }) {
    return {
      'storeId': widget.currentUser.storeId,
      'tableName': widget.order.tableName,
      'userName': widget.currentUser.name ?? 'Unknown',
      'items': billItems,
      'storeInfo': storeInfo,
      'showPrices': widget.showPricesOnReceipt,
      'summary': {
        'subtotal': widget.subtotal,
        'discount': result.discountAmount,
        'discountType': result.discountType,
        'discountInput': parseVN(_discountController.text),
        'surcharges': billData['surcharges'],
        'taxPercent': result.taxPercent,
        'taxAmount': result.totalTaxAmount,
        'tncnAmount': result.totalTncnAmount,
        'payments': result.payments,
        'customerPointsUsed': result.customerPointsUsed,
        'changeAmount': result.changeAmount,
        'totalPayable': _totalPayable,
        'startTime': widget.order.startTime,
        'customer': {
          'name': billData['customerName'] ?? 'Khách lẻ',
          'phone': billData['customerPhone'],
          'guestAddress': billData['guestAddress'] ?? '',
        },
        'bankDetails': result.bankDetailsForPrinting,
        'eInvoiceCode': eInvoiceResult?.reservationCode,
        'eInvoiceFullUrl': eInvoiceResult?.lookupUrl,
        'eInvoiceMst': eInvoiceResult?.mst,
        'billCode': newBillId.split('_').last,

        // --- THÊM DÒNG NÀY ---
        // Để PrintingService xác định được loại thuế (HKD hay VAT) và hiển thị % từng món
        'items': billItems,
        // ---------------------
      },
      'billCode': newBillId.split('_').last,
    };
  }

  Future<void> _showCashDialog() async {
    final result = await showDialog<double>(
      context: context,
      builder: (_) => CashDenominationDialog(
        totalPayable: _debtAmount > 0 ? _debtAmount : _totalPayable,
        initialCash: parseVN(_cashInputController.text),
      ),
    );
    if (result != null) {
      _cashInputController.text = formatNumber(result);
      _onCashInputChanged();
    }
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
      final List<Map<String, dynamic>> detailedItems = widget.order.items.map((item) {
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
      // --- KẾT THÚC SỬA ---

      final summaryData = {
        'subtotal': widget.subtotal,
        'discount': _calculateDiscount(),
        'discountType': _isDiscountPercent ? '%' : 'VND',
        'discountInput': parseVN(_discountController.text),
        'customerPointsUsed': parseVN(_pointsController.text),
        'taxAmount': _calculatedVatAmount,
        'tncnAmount': _calculatedTncnAmount,
        'taxPercent': 0.0,
        'surcharges': _surcharges
            .map((s) =>
        {'name': s.name, 'amount': s.amount, 'isPercent': s.isPercent})
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
        // QUAN TRỌNG: Truyền danh sách items đã có thuế vào summary
        'items': detailedItems,
      };

      final printData = {
        'storeId': widget.currentUser.storeId,
        'tableName': widget.order.tableName,
        'userName': widget.currentUser.name ?? 'Unknown',
        'items': detailedItems, // Sử dụng detailedItems thay vì widget.order.items gốc
        'storeInfo': storeInfo,
        'showPrices': true,
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
                  final isWide = constraints.maxWidth > 750;
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
                                _calculateTotal();
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
                      leading: Icon(Icons.request_quote_outlined, color: Colors.grey.shade600),

                      title: Text(_calcMethod == 'deduction' ? 'Thuế VAT' : 'Thuế Gộp'),

                      trailing: Text(
                        '${formatNumber(_calculatedVatAmount)} đ',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
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

        return Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: CustomTextFormField(
            key: ValueKey(method.id),
            initialValue: formatNumber(_paymentAmounts[method.id] ?? 0),
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
              // Gọi debounce
              _onInputChanged();
            },
          ),
        );
        // --- KẾT THÚC LOGIC MỚI ---
      }).toList(),
    );
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
            _calculateTotal();
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
                    constraints.maxWidth > 750; // desktop/pos android
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
                              _calculateTotal();
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
                              _calculateTotal();
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
                            _calculateTotal();
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
                                _calculateTotal();
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
                                  _calculateTotal();
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
                                  _calculateTotal();
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
              _calculateTotal();
            });
          },
        ),
      ],
    );
  }

  Future<void> _loadPaymentMethods() async {
    final cashMethod = PaymentMethodModel(
      id: 'cash_default',
      storeId: widget.currentUser.storeId,
      name: 'Tiền mặt',
      type: PaymentMethodType.cash,
      active: true,
    );

    try {
      final snapshot = await _firestoreService
          .getPaymentMethods(widget.currentUser.storeId)
          .first;
      final firestoreMethods = snapshot.docs
          .map((doc) => PaymentMethodModel.fromFirestore(doc))
          .toList();

      if (mounted) {
        setState(() {
          _cashMethod = cashMethod;
          _availableMethods = [cashMethod, ...firestoreMethods];

          // 1. Xác định ID PTTT mặc định chính xác
          String idToSelect = _defaultPaymentMethodId ?? cashMethod.id;

          // Kiểm tra xem ID mặc định có tồn tại trong danh sách không
          final defaultMethodExists = _availableMethods.any((m) => m.id == idToSelect);
          if (!defaultMethodExists) {
            idToSelect = cashMethod.id;
          }

          // 2. Thêm vào danh sách đã chọn
          _selectedMethodIds.add(idToSelect);
          _methodsLoaded = true;

          // 3. LOGIC GÁN TIỀN BAN ĐẦU (SỬ DỤNG _totalPayable ĐÃ TÍNH Ở BƯỚC TRƯỚC)
          double amountToSet = 0;
          final bool isDefaultCash = (idToSelect == cashMethod.id);

          if (isDefaultCash) {
            // Nếu là Tiền mặt: kiểm tra promptForCash
            if (!widget.promptForCash) {
              // Nếu KHÔNG hỏi tiền mặt -> Tự động điền full tổng tiền
              amountToSet = _totalPayable;
            } else {
              // Nếu CÓ hỏi -> Để 0
              amountToSet = 0.0;
            }
          } else {
            // Nếu là Bank/Thẻ/Khác -> Luôn tự động điền full tổng tiền
            amountToSet = _totalPayable;
          }

          // 4. Gán vào map
          _paymentAmounts[idToSelect] = amountToSet;

          // 5. Cập nhật controller hiển thị nếu là tiền mặt
          if (isDefaultCash) {
            _cashInputController.text = formatNumber(amountToSet);
          }

          // 6. Gọi tính toán lại để cập nhật thuế và các thông số khác
          _calculateTotal();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _cashMethod = cashMethod;
          _availableMethods = [cashMethod];
          _selectedMethodIds.add(cashMethod.id);
          _paymentAmounts[cashMethod.id] = 0;
          _methodsLoaded = true;
        });
      }
    }
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
    final isMobile = Theme.of(context).platform == TargetPlatform.android ||
        Theme.of(context).platform == TargetPlatform.iOS;
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
      child: Row(
        children: [
          if (!isMobile) ...[
            Expanded(
              child: OutlinedButton(
                onPressed: _isProcessingPayment ? null : widget.onCancel,
                // Vô hiệu hóa khi đang xử lý
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
              onPressed: _isProcessingPayment ? null : _confirmPayment,
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
      ),
    );
  }

  double _calculateTotalProfit() {
    double totalProfit = 0;
    for (final itemMap in widget.order.items) {
      final product = itemMap['product'] as Map<String, dynamic>? ?? {};
      final costPrice = (product['costPrice'] as num?)?.toDouble() ?? 0.0;
      final salePrice = (itemMap['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (itemMap['quantity'] as num?)?.toDouble() ?? 0.0;
      final isTimeBased = product['serviceSetup']?['isTimeBased'] == true;

      if (isTimeBased) {
        totalProfit += salePrice - (costPrice * quantity);
      } else {
        totalProfit += (salePrice - costPrice) * quantity;
      }
    }
    return totalProfit;
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

  const CashDenominationDialog(
      {super.key, required this.totalPayable, required this.initialCash});

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

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 600;
    final double change = _totalCash - widget.totalPayable;
    final double changeToDisplay = change > 0 ? change : 0;

    return AlertDialog(
      title: const Text('Tiền mặt khách đưa'),
      content: SizedBox(
        width: isDesktop ? 300 : 260,
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
                  ?.copyWith(color: AppTheme.primaryColor, fontSize: 18),
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
            Flexible(
              child: isDesktop
                  ? GridView.builder(
                      shrinkWrap: true,
                      itemCount: denominations.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2,
                      ),
                      itemBuilder: (context, index) {
                        final den = denominations[index];
                        final qty = _quantities[den] ?? 0;
                        return _denominationCell(den, qty);
                      },
                    )
                  : GridView.builder(
                      shrinkWrap: true,
                      itemCount: denominations.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.2,
                      ),
                      itemBuilder: (context, index) {
                        final den = denominations[index];
                        final qty = _quantities[den] ?? 0;
                        return _denominationCell(den, qty);
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _reset,
          child: const Text('Reset'),
        ),
        const Spacer(),
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy')),
        ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_totalCash),
            child: const Text('Xác nhận')),
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
