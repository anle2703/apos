import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/purchase_order_item_model.dart';
import '../../models/supplier_model.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/supplier_search_dialog.dart';
import '../../services/toast_service.dart';

class ConfirmationScreen extends StatefulWidget {
  final List<PurchaseOrderItem> items;
  final SupplierModel? initialSupplier;
  final String initialNotes;
  final String initialShippingFee;
  final String initialDiscount;
  final String initialPaidAmount;
  final bool initialIsDiscountPercent;
  final String initialPaymentMethod;
  final Function(Map<String, dynamic> confirmedData) onConfirmAndSave;
  final String storeId;

  const ConfirmationScreen({
    super.key,
    required this.items,
    required this.onConfirmAndSave,
    this.initialSupplier,
    required this.initialNotes,
    required this.initialShippingFee,
    required this.initialDiscount,
    required this.initialPaidAmount,
    required this.initialIsDiscountPercent,
    required this.initialPaymentMethod,
    required this.storeId,
  });

  @override
  State<ConfirmationScreen> createState() => _ConfirmationScreenState();
}

class _ConfirmationScreenState extends State<ConfirmationScreen> {
  late final TextEditingController _notesController;
  late final TextEditingController _shippingFeeController;
  late final TextEditingController _discountController;
  late final TextEditingController _paidAmountController;
  final _thousandFormatter = ThousandDecimalInputFormatter();

  SupplierModel? _selectedSupplier;
  late String _paymentMethod;

  final ValueNotifier<bool> _isDiscountPercent = ValueNotifier(false);
  final ValueNotifier<double> _subtotal = ValueNotifier(0);
  final ValueNotifier<double> _totalAmount = ValueNotifier(0);
  final ValueNotifier<double> _debtAmount = ValueNotifier(0);

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selectedSupplier = widget.initialSupplier;
    _notesController = TextEditingController(text: widget.initialNotes);
    _shippingFeeController = TextEditingController(text: widget.initialShippingFee);
    _discountController = TextEditingController(text: widget.initialDiscount);
    _paidAmountController = TextEditingController(text: widget.initialPaidAmount);
    _isDiscountPercent.value = widget.initialIsDiscountPercent;
    _paymentMethod = widget.initialPaymentMethod;

    _shippingFeeController.addListener(_onInputChanged);
    _discountController.addListener(_onInputChanged);
    _paidAmountController.addListener(_onInputChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) => _calculateTotals());
  }

  @override
  void dispose() {
    _notesController.dispose();
    _shippingFeeController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    _debounce?.cancel();
    _subtotal.dispose();
    _totalAmount.dispose();
    _debtAmount.dispose();
    _isDiscountPercent.dispose();
    super.dispose();
  }

  double _parseInputAsDouble(String text) {
    final sanitized = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(sanitized) ?? 0.0;
  }

  void _onInputChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _calculateTotals);
  }

  void _calculateTotals() {
    final subtotal = widget.items.fold(0.0, (total, item) {
      return total + (item.product.manageStockSeparately ? item.separateSubtotal : item.subtotal);
    });

    final shipping = _parseInputAsDouble(_shippingFeeController.text);
    final discountInput = _parseInputAsDouble(_discountController.text);
    final paid = _parseInputAsDouble(_paidAmountController.text);
    final discount = _isDiscountPercent.value ? subtotal * (discountInput / 100) : discountInput;

    final total = subtotal + shipping - discount;
    final debt = total - paid;

    _subtotal.value = subtotal;
    _totalAmount.value = total;
    _debtAmount.value = debt;
  }

  Future<void> _selectSupplier() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => SupplierSearchDialog(
        storeId: widget.storeId,
      ),
    );
    if (result != null && result is SupplierModel) {
      setState(() => _selectedSupplier = result);
    }
  }

  void _submit() {
    final paidAmount = _parseInputAsDouble(_paidAmountController.text);
    if (_selectedSupplier == null && paidAmount < _totalAmount.value) {
      ToastService().show(
        message: 'Vui lòng chọn Nhà Cung Cấp hoặc thanh toán đủ 100% tổng tiền.',
        type: ToastType.warning,
      );
      return;
    }
    final confirmedData = {
      'supplier': _selectedSupplier,
      'notes': _notesController.text,
      'shippingFee': _shippingFeeController.text,
      'discount': _discountController.text,
      'paidAmount': _paidAmountController.text,
      'isDiscountPercent': _isDiscountPercent.value,
      'paymentMethod': _paymentMethod,
      'subtotal': _subtotal.value,
      'totalAmount': _totalAmount.value,
      'debtAmount': _debtAmount.value,
    };
    widget.onConfirmAndSave(confirmedData);
    Navigator.of(context)..pop()..pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Xác nhận & Hoàn tất'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: AppTheme.primaryColor),
            tooltip: 'Lưu',
            onPressed: _submit,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildConfirmationCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationCard() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Thông tin NCC', style: Theme.of(context).textTheme.titleLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.store_mall_directory_outlined, color: AppTheme.primaryColor),
              title: Text(_selectedSupplier?.name ?? 'Chọn nhà cung cấp', style: AppTheme.boldTextStyle),
              subtitle: Text(_selectedSupplier?.phone ?? 'Chưa có thông tin'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _selectSupplier,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú',
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            Text('Thanh toán', style: Theme.of(context).textTheme.titleLarge),
            ValueListenableBuilder<double>(
              valueListenable: _subtotal,
              builder: (_, v, __) => _buildSummaryRow('Tổng tiền hàng:', v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 120,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isDiscountPercent,
                    builder: (_, val, __) => AppDropdown<bool>(
                      labelText: "Loại",
                      isDense: true,
                      value: val,
                      items: const [
                        DropdownMenuItem(value: false, child: Text('VND')),
                        DropdownMenuItem(value: true, child: Text('%')),
                      ],
                      onChanged: (newVal) {
                        if (newVal != null) {
                          _isDiscountPercent.value = newVal;
                          _calculateTotals();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CustomTextFormField(
                    controller: _discountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_thousandFormatter],
                    scrollPadding: const EdgeInsets.only(bottom: 180),
                    decoration: const InputDecoration(isDense: true, labelText: 'Chiết khấu'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            CustomTextFormField(
              controller: _shippingFeeController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_thousandFormatter],
              scrollPadding: const EdgeInsets.only(bottom: 180),
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Phí vận chuyển',
                prefixIcon: Icon(Icons.local_shipping_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<double>(
              valueListenable: _totalAmount,
              builder: (_, v, __) => _buildSummaryRow('Tổng cộng:', v, isTotal: true),
            ),
            const SizedBox(height: 12),
            AppDropdown<String>(
              labelText: 'Hình thức thanh toán',
              isDense: true,
              value: _paymentMethod,
              items: ['Tiền mặt', 'Chuyển khoản', 'Ghi nợ']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _paymentMethod = value);
              },
            ),
            const SizedBox(height: 12),
            CustomTextFormField(
              controller: _paidAmountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [_thousandFormatter],
              scrollPadding: const EdgeInsets.only(bottom: 180),
              decoration: InputDecoration(
                isDense: true,
                labelText: 'Đã thanh toán',
                prefixIcon: const Icon(Icons.payment_outlined, size: 20),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.price_change_outlined, color: AppTheme.primaryColor),
                  tooltip: 'Thanh toán bằng tổng tiền',
                  onPressed: () {
                    _paidAmountController.text = formatNumber(_totalAmount.value);
                    _paidAmountController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _paidAmountController.text.length),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<double>(
              valueListenable: _debtAmount,
              builder: (_, v, __) => _buildSummaryRow('Dư nợ:', v, isDebt: true),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(String label, double value, {bool isTotal = false, bool isDebt = false}) {
    final color = isTotal
        ? AppTheme.primaryColor
        : (isDebt && value > 0 ? Colors.red.shade700 : AppTheme.textColor);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: isTotal
                ? AppTheme.boldTextStyle.copyWith(fontSize: 18)
                : AppTheme.regularGreyTextStyle.copyWith(fontSize: 16)),
        Text('${formatNumber(value)} đ',
            style: AppTheme.boldTextStyle.copyWith(
              fontSize: isTotal ? 20 : 16,
              color: color,
            )),
      ],
    );
  }
}