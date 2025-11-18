import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../services/toast_service.dart';
import '../../widgets/product_search_delegate.dart';
import '../../widgets/app_dropdown.dart';
import '../../services/inventory_service.dart';
import '../../models/purchase_order_item_model.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/supplier_model.dart';
import '../../widgets/supplier_search_dialog.dart';
import 'confirmation_screen.dart';
import '../../models/purchase_order_model.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  final UserModel currentUser;
  final PurchaseOrderModel? existingPurchaseOrder;

  const CreatePurchaseOrderScreen({super.key,
    required this.currentUser,
    this.existingPurchaseOrder,
  });

  @override
  State<CreatePurchaseOrderScreen> createState() =>
      _CreatePurchaseOrderScreenState();
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _thousandFormatter = ThousandDecimalInputFormatter();
  final ValueNotifier<double> _subtotalNotifier = ValueNotifier(0);
  final ValueNotifier<double> _totalNotifier = ValueNotifier(0);
  final ValueNotifier<double> _debtNotifier = ValueNotifier(0);
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _shippingFeeController = TextEditingController(text: '0');
  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _paidAmountController = TextEditingController(text: '0');
  final InventoryService _inventoryService = InventoryService();

  SupplierModel? _selectedSupplier;

  bool _isDiscountPercent = false;
  bool _isSaving = false;
  bool get _isEditMode => widget.existingPurchaseOrder != null;
  bool get _isCancelled => widget.existingPurchaseOrder?.status == 'Đã hủy';

  String _paymentMethod = 'Tiền mặt';

  Timer? _debounce;

  List<PurchaseOrderItem> _items = [];
  List<Map<String, dynamic>> _originalItemsForEdit = [];

  @override
  void initState() {
    super.initState();
    _shippingFeeController.addListener(_onInputChanged);
    _discountController.addListener(_onInputChanged);
    _paidAmountController.addListener(_onInputChanged);

    if (_isEditMode) {
      _populateFormForEdit();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_items.isEmpty) {
          _selectProducts();
        }
      });
    }
  }

  Future<void> _populateFormForEdit() async {
    final po = widget.existingPurchaseOrder!;

    _originalItemsForEdit = List<Map<String, dynamic>>.from(po.items);

    _notesController.text = po.notes;
    _shippingFeeController.text = formatNumber(po.shippingFee);
    _discountController.text = formatNumber(po.discount);
    _paidAmountController.text = formatNumber(po.paidAmount);
    _isDiscountPercent = po.isDiscountPercent;
    _paymentMethod = po.paymentMethod;

    if (po.supplierId != null && po.supplierId!.isNotEmpty) {
      final supplier = await _inventoryService.getSupplierById(po.supplierId!);
      if (supplier != null && mounted) {
        setState(() {
          _selectedSupplier = supplier;
        });
      }
    }

    final productIds = po.items.map((item) => item['productId'] as String).toList();
    final products = await _inventoryService.getProductsByIds(productIds);
    final productsMap = {for (var p in products) p.id: p};

    final List<PurchaseOrderItem> loadedItems = [];
    for (final itemMap in po.items) {
      final product = productsMap[itemMap['productId']];
      if (product == null) continue;

      final poItem = PurchaseOrderItem(product: product);
      if (itemMap['manageStockSeparately'] == true) {
        try {
          poItem.separateQuantities = Map<String, double>.from(
              (itemMap['separateQuantities'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()))
          );
          poItem.separatePrices = Map<String, double>.from(
              (itemMap['separatePrices'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble()))
          );
        } catch(e) {/* ignore */}
      } else {
        poItem.quantity = (itemMap['quantity'] as num? ?? 0).toDouble();
        poItem.price = (itemMap['price'] as num? ?? 0).toDouble();
        poItem.unit = itemMap['unit'] ?? product.unit ?? '';
      }
      loadedItems.add(poItem);
    }

    if (mounted) {
      setState(() {
        _items = loadedItems;
        _calculateTotals();
      });
    }
  }

  @override
  void dispose() {
    _notesController.dispose();
    _shippingFeeController.dispose();
    _discountController.dispose();
    _paidAmountController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onInputChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _calculateTotals);
  }

  double _parseInputAsDouble(String text) {
    final sanitizedText = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(sanitizedText) ?? 0.0;
  }

  void _calculateTotals() {
    final subtotalValue = _items.fold(0.0, (total, item) {
      return total +
          (item.product.manageStockSeparately == true
              ? item.separateSubtotal
              : item.subtotal);
    });
    final shippingFee = _parseInputAsDouble(_shippingFeeController.text);
    final discountInput = _parseInputAsDouble(_discountController.text);
    final paidAmount = _parseInputAsDouble(_paidAmountController.text);
    final discountAmount = _isDiscountPercent
        ? subtotalValue * (discountInput / 100)
        : discountInput;

    _subtotalNotifier.value = subtotalValue;
    _totalNotifier.value = subtotalValue + shippingFee - discountAmount;
    _debtNotifier.value = _totalNotifier.value - paidAmount;
  }

  Future<void> _selectProducts() async {
    final selectedProducts = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: _items.map((e) => e.product).toList(),
      groupByCategory: true,
      allowedProductTypes: [
        'Hàng hóa',
        'Topping/Bán kèm',
        'Nguyên liệu',
        'Vật liệu'
      ],
    );
    if (selectedProducts == null) return;
    setState(() {
      _items = selectedProducts.map((p) {
        final existingItem =
        _items.firstWhereOrNull((item) => item.product.id == p.id);
        if (existingItem != null) return existingItem;
        final newItem = PurchaseOrderItem(product: p);
        if (p.manageStockSeparately) {
          for (final unit in p.getAllUnits) {
            newItem.separateQuantities[unit] = 0;
            newItem.separatePrices[unit] = p.getCostPriceForUnit(unit);
          }
        } else {
          newItem.price = p.costPrice;
          newItem.quantity = 1;
          newItem.unit = p.unit ?? 'Cái';
        }
        return newItem;
      }).toList();
      _calculateTotals();
    });
  }

  void _updateItem(int index, {double? quantity, double? price, String? unit}) {
    if (index < 0 || index >= _items.length) return;
    final currentItem = _items[index];
    bool changed = false;
    if (currentItem.product.manageStockSeparately != true) {
      if (quantity != null && currentItem.quantity != quantity) {
        currentItem.quantity = quantity;
        changed = true;
      }
      if (price != null && currentItem.price != price) {
        currentItem.price = price;
        changed = true;
      }
      if (unit != null && currentItem.unit != unit) {
        currentItem.unit = unit;
        currentItem.price = currentItem.product.getCostPriceForUnit(unit);
        setState(() {});
        changed = true;
      }
    }
    if (changed) _onInputChanged();
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
      _calculateTotals();
    });
  }

  Future<void> _selectSupplier() async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (context) => SupplierSearchDialog(
        storeId: widget.currentUser.storeId,
      ),
    );

    if (result != null && result is SupplierModel) {
      setState(() => _selectedSupplier = result);
    }
  }

  Future<bool> _performSave(Map<String, dynamic> confirmedData) async {
    final itemsToSave = _items.where((item) {
      if (item.product.manageStockSeparately) {
        return item.separateQuantities.values.any((qty) => qty > 0);
      } else {
        return item.quantity > 0;
      }
    }).toList();

    if (itemsToSave.isEmpty) {
      if (mounted) {
        ToastService().show(
          message: 'Cần có ít nhất một sản phẩm với số lượng lớn hơn 0 để lưu.',
          type: ToastType.warning,
        );
        setState(() => _isSaving = false);
      }
      return false;
    }

    setState(() => _isSaving = true);
    try {
      final poData = {
        'supplierId': (confirmedData['supplier'] as SupplierModel?)?.id,
        'supplierName': (confirmedData['supplier'] as SupplierModel?)?.name ?? 'Nhà cung cấp lẻ',
        'notes': confirmedData['notes'],
        'shippingFee': _parseInputAsDouble(confirmedData['shippingFee']),
        'discount': _parseInputAsDouble(confirmedData['discount']),
        'isDiscountPercent': confirmedData['isDiscountPercent'],
        'paidAmount': _parseInputAsDouble(confirmedData['paidAmount']),
        'paymentMethod': confirmedData['paymentMethod'],
        'subtotal': confirmedData['subtotal'],
        'totalAmount': confirmedData['totalAmount'],
        'debtAmount': confirmedData['debtAmount'],
        'status': (confirmedData['debtAmount'] > 0 && confirmedData['paymentMethod'] != 'Ghi nợ')
            ? 'Chưa thanh toán đủ'
            : 'Hoàn thành',
        'items': itemsToSave.map((item) => item.toMap()).toList(),
        'createdByUid': _isEditMode ? widget.existingPurchaseOrder!.createdBy : widget.currentUser.uid,
        'createdByName': _isEditMode ? widget.existingPurchaseOrder!.createdBy : widget.currentUser.name,
        'storeId': widget.currentUser.storeId,
        'updatedByUid': _isEditMode ? widget.currentUser.uid : null,
        'updatedByName': _isEditMode ? widget.currentUser.name : null,
      };

      if (_isEditMode) {
        await _inventoryService.updatePurchaseOrderAndUpdateStock(
          poId: widget.existingPurchaseOrder!.id,
          poData: poData,
          oldItems: _originalItemsForEdit,
          newItems: itemsToSave,
        );
      } else {
        await _inventoryService.createPurchaseOrderAndUpdateStock(
            poData: poData, items: itemsToSave);
      }

      if (mounted) {
        ToastService().show(
          message: _isEditMode ? 'Cập nhật phiếu thành công!' : 'Tạo phiếu thành công!',
          type: ToastType.success,
        );
      }
      return true; // Trả về true nếu thành công
    } catch (e) {
      if (mounted) {
        ToastService().show(message: 'Lỗi khi lưu: $e', type: ToastType.error);
      }
      return false; // Trả về false nếu có lỗi
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _submitForm() async {
    if (_isSaving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_items.isEmpty) {
      ToastService().show(
        message: 'Vui lòng chọn ít nhất một sản phẩm.',
        type: ToastType.warning,
      );
      return;
    }

    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1000;

    if (isDesktop) {
      final paidAmount = _parseInputAsDouble(_paidAmountController.text);
      if (_selectedSupplier == null && paidAmount < _totalNotifier.value) {
        ToastService().show(
          message: 'Vui lòng chọn Nhà Cung Cấp hoặc thanh toán đủ 100% tổng tiền.',
          type: ToastType.warning,
        );
        return;
      }
    }

    final currentData = {
      'supplier': _selectedSupplier,
      'notes': _notesController.text,
      'shippingFee': _shippingFeeController.text,
      'discount': _discountController.text,
      'paidAmount': _paidAmountController.text,
      'isDiscountPercent': _isDiscountPercent,
      'paymentMethod': _paymentMethod,
      'subtotal': _subtotalNotifier.value,
      'totalAmount': _totalNotifier.value,
      'debtAmount': _debtNotifier.value,
    };

    if (isDesktop) {
      // DESKTOP: Gọi lưu và thoát 1 lần
      final success = await _performSave(currentData);
      if (success && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ConfirmationScreen(
            items: _items,
            initialSupplier: _selectedSupplier,
            initialNotes: _notesController.text,
            initialShippingFee: _shippingFeeController.text,
            initialDiscount: _discountController.text,
            initialPaidAmount: _paidAmountController.text,
            initialIsDiscountPercent: _isDiscountPercent,
            initialPaymentMethod: _paymentMethod,
            storeId: widget.currentUser.storeId,
            onConfirmAndSave: (confirmedData) async {
              final navigator = Navigator.of(context);
              final success = await _performSave(confirmedData);
              if (success && mounted) {
                navigator..pop()..pop();
              }
            },
          ),
        ),
      );
    }
  }

  Future<void> _confirmAndCancelPurchaseOrder() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Hủy Phiếu nhập hàng'),
          content: const Text(
              'Bạn có chắc chắn muốn hủy phiếu nhập hàng này? Hành động này sẽ trừ ngược lại số lượng tồn kho đã nhập.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('HỦY PHIẾU', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _performCancel();
    }
  }

  Future<void> _performCancel() async {
    if (!_isEditMode) return;
    setState(() => _isSaving = true);

    try {
      final po = widget.existingPurchaseOrder!;

      await _inventoryService.cancelPurchaseOrder(
        poId: po.id,
        itemsToReverse: po.items,
        currentUser: widget.currentUser,
        supplierId: po.supplierId,
        debtAmountToReverse: po.debtAmount,
      );

      if (mounted) {
        ToastService().show(message: 'Đã hủy phiếu nhập hàng thành công!', type: ToastType.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ToastService().show(message: 'Lỗi khi hủy phiếu: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _confirmAndDeletePurchaseOrder() async {
    // Chỉ thực hiện nếu đang ở chế độ sửa và phiếu đã bị hủy
    if (!_isEditMode || !_isCancelled) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xóa Phiếu nhập hàng vĩnh viễn'),
          content: const Text(
              'Bạn có chắc chắn muốn XÓA VĨNH VIỄN phiếu nhập hàng này? Hành động này không thể khôi phục.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Không'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('XÓA VĨNH VIỄN', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _performDelete();
    }
  }

  /// Gọi service để xóa vĩnh viễn phiếu nhập.
  Future<void> _performDelete() async {
    if (!_isEditMode || !_isCancelled) return;
    setState(() => _isSaving = true); // Dùng biến _isSaving để chặn thao tác khác

    try {
      final poId = widget.existingPurchaseOrder!.id;
      await _inventoryService.deletePurchaseOrderPermanently(poId);

      if (mounted) {
        ToastService().show(message: 'Đã xóa vĩnh viễn phiếu nhập hàng!', type: ToastType.success);
        Navigator.of(context).pop(); // Thoát khỏi màn hình sau khi xóa
      }
    } catch (e) {
      if (mounted) {
        ToastService().show(message: 'Lỗi khi xóa phiếu: $e', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1000;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(_isEditMode ? 'Sửa Phiếu Nhập Hàng' : 'Tạo Phiếu Nhập Hàng'),
        actions: [
          // LOGIC CHANGE: Hide cancel and save buttons if the order is already cancelled
          if (_isEditMode && !_isCancelled)
            IconButton(
              icon: Icon(Icons.cancel_outlined, color: Colors.red, size: 30),
              tooltip: 'Hủy phiếu nhập hàng',
              onPressed: _isSaving ? null : _confirmAndCancelPurchaseOrder,
            ),
          if (_isEditMode && _isCancelled)
            IconButton(
              icon: Icon(Icons.delete_outlined, color: Colors.red, size: 30),
              tooltip: 'Xóa vĩnh viễn phiếu nhập',
              // Gọi hàm xác nhận xóa mới tạo
              onPressed: _isSaving ? null : _confirmAndDeletePurchaseOrder,
            ),
          if (!_isCancelled)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: IconButton(
                onPressed: _isSaving ? null : _submitForm,
                icon: _isSaving
                    ? Container(
                  width: 24,
                  height: 24,
                  padding: const EdgeInsets.all(2.0),
                  child: const CircularProgressIndicator(
                    color: AppTheme.primaryColor,
                    strokeWidth: 3,
                  ),
                )
                    : Icon(isDesktop ? Icons.save_outlined : Icons.arrow_forward,
                    color: AppTheme.primaryColor, size: 30),
                tooltip: 'Lưu',
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Form(
        key: _formKey,
        child: isDesktop ? _buildDesktopLayout() : _buildMobileLayout(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        children: [
          _buildMobileProductHeader(),
          const SizedBox(height: 12),
          Expanded(
            child: RepaintBoundary(
              child: _buildProductsCard(isDesktop: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileProductHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            if (_items.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined, size: 25),
                color: Colors.red.shade400,
                tooltip: 'Xóa tất cả',
                // LOGIC CHANGE: Disable button if cancelled
                onPressed: _isCancelled ? null : _confirmRemoveAllItems,
              ),
            Text("Sản phẩm",
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 18)),
          ],
        ),
        // LOGIC CHANGE: Disable button if cancelled
        TextButton.icon(
          onPressed: _isCancelled ? null : _selectProducts,
          icon: const Icon(Icons.add_shopping_cart_outlined),
          label: const Text('Chọn SP'),
        ),
      ],
    );
  }

  Future<void> _confirmRemoveAllItems() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: const Text(
              'Bạn có chắc chắn muốn xóa tất cả sản phẩm khỏi danh sách nhập hàng?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Hủy'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
            TextButton(
              child: const Text('Xóa', style: TextStyle(color: Colors.red)),
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      setState(() {
        _items.clear();
        _calculateTotals();
      });
    }
  }

  Widget _buildDesktopLayout() {
    const double kAppPadding = 16.0;
    const double kAppPaddingHalf = 8.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                kAppPadding, kAppPadding, kAppPaddingHalf, kAppPadding),
            child: _buildProductsCard(isDesktop: true),
          ),
        ),
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                kAppPaddingHalf, kAppPadding, kAppPadding, kAppPadding),
            child: _buildSupplierAndSummaryCard(),
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierAndSummaryCard() {
    return Card(
      elevation: 2.0,
      margin: EdgeInsets.zero,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSupplierInputs(),
            const SizedBox(height: 24),
            _buildSummaryCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsCard({required bool isDesktop}) {
    final content = _items.isEmpty
        ? const Center(
        child: Padding(
            padding: EdgeInsets.symmetric(vertical: 32.0),
            child: Text('Chưa có sản phẩm nào được chọn.')))
        : ListView.separated(
      padding: EdgeInsets.zero,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _items.length,
      separatorBuilder: (context, index) => isDesktop
          ? const Divider(
        height: 1,
        thickness: 0.5,
        color: Colors.grey,
      )
          : const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _items[index];
        return _ProductListItemWidget(
          key: ValueKey(item.product.id),
          item: item,
          isDesktop: isDesktop,
          // LOGIC CHANGE: Pass the cancelled flag to disable item interactions
          isReadOnly: _isCancelled,
          thousandFormatter: _thousandFormatter,
          onPriceChanged: (newPrice) =>
              _updateItem(index, price: newPrice),
          onQuantityChanged: (newQuantity) =>
              _updateItem(index, quantity: newQuantity),
          onUnitChanged: (newUnit) => _updateItem(index, unit: newUnit),
          onRemove: () => _removeItem(index),
          onSeparatePriceChanged: (unit, newPrice) {
            setState(() => item.separatePrices[unit] = newPrice);
            _onInputChanged();
          },
          onSeparateQuantityChanged: (unit, newQuantity) {
            setState(() => item.separateQuantities[unit] = newQuantity);
            _onInputChanged();
          },
          onSeparateUnitRemoved: (unit) {
            setState(() {
              item.separatePrices.remove(unit);
              item.separateQuantities.remove(unit);

              if (item.separateQuantities.isEmpty) {
                _items.remove(item);
              }
              _calculateTotals();
            });
          },
        );
      },
    );
    if (!isDesktop) return content;
    return Card(
      elevation: 2.0,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (_items.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.delete_sweep_outlined, size: 25),
                        color: Colors.red.shade400,
                        tooltip: 'Xóa tất cả',
                        // LOGIC CHANGE: Disable button if cancelled
                        onPressed: _isCancelled ? null : _confirmRemoveAllItems,
                      ),
                    Text("Sản phẩm",
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontSize: 18)),
                  ],
                ),
                TextButton.icon(
                  // LOGIC CHANGE: Disable button if cancelled
                    onPressed: _isCancelled ? null : _selectProducts,
                    icon: const Icon(Icons.add_shopping_cart_outlined),
                    label: const Text('Chọn SP')),
              ],
            ),
            const Divider(height: 24),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard({bool isPopup = false}) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isPopup) ...[
          Text('Tổng kết',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 18)),
          const Divider(height: 24)
        ],
        ValueListenableBuilder<double>(
          valueListenable: _subtotalNotifier,
          builder: (_, val, __) => _buildSummaryRow('Tổng tiền hàng:', val),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            SizedBox(
                width: 120,
                child: AppDropdown<bool>(
                    labelText: "Loại",
                    isDense: true,
                    value: _isDiscountPercent,
                    items: const [
                      DropdownMenuItem(value: false, child: Text('VND')),
                      DropdownMenuItem(value: true, child: Text('%'))
                    ],
                    // LOGIC CHANGE: Disable dropdown if cancelled
                    onChanged: _isCancelled ? null : (val) => setState(() {
                      _isDiscountPercent = val ?? false;
                      _calculateTotals();
                    }))),
            const SizedBox(width: 8),
            Expanded(
                child: CustomTextFormField(
                    controller: _discountController,
                    // LOGIC CHANGE: Set to read-only if cancelled
                    readOnly: _isCancelled,
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [_thousandFormatter],
                    decoration: const InputDecoration(
                        isDense: true, labelText: 'Chiết khấu'))),
          ],
        ),
        const SizedBox(height: 12),
        CustomTextFormField(
            controller: _shippingFeeController,
            // LOGIC CHANGE: Set to read-only if cancelled
            readOnly: _isCancelled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [_thousandFormatter],
            decoration: const InputDecoration(
                isDense: true,
                labelText: 'Phí vận chuyển',
                prefixIcon: Icon(Icons.local_shipping_outlined, size: 20))),
        const SizedBox(height: 12),
        ValueListenableBuilder<double>(
          valueListenable: _totalNotifier,
          builder: (_, val, __) =>
              _buildSummaryRow('Tổng cộng:', val, isTotal: true),
        ),
        const SizedBox(height: 18),
        AppDropdown<String>(
            labelText: 'Hình thức thanh toán',
            isDense: true,
            value: _paymentMethod,
            items: ['Tiền mặt', 'Chuyển khoản', 'Ghi nợ']
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            // LOGIC CHANGE: Disable dropdown if cancelled
            onChanged: _isCancelled ? null : (value) {
              if (value != null) setState(() => _paymentMethod = value);
            }),
        const SizedBox(height: 12),
        CustomTextFormField(
          controller: _paidAmountController,
          // LOGIC CHANGE: Set to read-only if cancelled
          readOnly: _isCancelled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [_thousandFormatter],
          decoration: InputDecoration(
            isDense: true,
            labelText: 'Đã thanh toán',
            prefixIcon: const Icon(Icons.payment_outlined, size: 20),
            suffixIcon: IconButton(
              icon: const Icon(Icons.price_change_outlined, size: 25,
                  color: AppTheme.primaryColor),
              tooltip: 'Thanh toán bằng tổng tiền',
              // LOGIC CHANGE: Disable button if cancelled
              onPressed: _isCancelled ? null : () {
                _paidAmountController.text = formatNumber(_totalNotifier.value);
                _paidAmountController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _paidAmountController.text.length),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        ValueListenableBuilder<double>(
          valueListenable: _debtNotifier,
          builder: (_, val, __) =>
              _buildSummaryRow('Dư nợ:', val, isDebt: true),
        ),
      ],
    );
    return isPopup
        ? content
        : Card(
        elevation: 0,
        color: Colors.transparent,
        margin: EdgeInsets.zero,
        child: content);
  }

  Widget _buildSummaryRow(String label, double value,
      {bool isTotal = false, bool isDebt = false}) {
    Color valueColor = isTotal
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
            style: AppTheme.boldTextStyle
                .copyWith(fontSize: isTotal ? 20 : 16, color: valueColor)),
      ],
    );
  }

  Widget _buildSupplierInputs({bool isPopup = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isPopup) ...[
          Text('Thông tin NCC',
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 18)),
          const Divider(height: 24)
        ],
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.store_mall_directory_outlined,
              color: AppTheme.primaryColor),
          title: Text(_selectedSupplier?.name ?? 'Chọn nhà cung cấp',
              style: AppTheme.boldTextStyle),
          subtitle: Text(_selectedSupplier?.phone ?? 'Chưa có thông tin'),
          trailing: const Icon(Icons.chevron_right),
          // LOGIC CHANGE: Disable tap if cancelled
          onTap: _isCancelled ? null : _selectSupplier,
        ),
        const SizedBox(height: 16),
        CustomTextFormField(
          controller: _notesController,
          // LOGIC CHANGE: Set to read-only if cancelled
          readOnly: _isCancelled,
          decoration: const InputDecoration(
              labelText: 'Ghi chú', prefixIcon: Icon(Icons.notes_outlined)),
        ),
      ],
    );
  }
}

class _ProductListItemWidget extends StatefulWidget {
  final PurchaseOrderItem item;
  final bool isDesktop;
  final bool isReadOnly; // LOGIC CHANGE: Added to control state
  final ThousandDecimalInputFormatter thousandFormatter;
  final ValueChanged<double> onQuantityChanged;
  final ValueChanged<double> onPriceChanged;
  final ValueChanged<String> onUnitChanged;
  final VoidCallback onRemove;
  final Function(String, double) onSeparateQuantityChanged;
  final Function(String, double) onSeparatePriceChanged;
  final Function(String) onSeparateUnitRemoved;

  const _ProductListItemWidget(
      {super.key,
        required this.item,
        required this.isDesktop,
        required this.isReadOnly, // LOGIC CHANGE: Added to constructor
        required this.thousandFormatter,
        required this.onQuantityChanged,
        required this.onPriceChanged,
        required this.onUnitChanged,
        required this.onRemove,
        required this.onSeparateQuantityChanged,
        required this.onSeparatePriceChanged,
        required this.onSeparateUnitRemoved});

  @override
  State<_ProductListItemWidget> createState() => _ProductListItemWidgetState();
}

class _ProductListItemWidgetState extends State<_ProductListItemWidget> {
  late TextEditingController _quantityController;
  late TextEditingController _priceController;
  final Map<String, TextEditingController> _separateQuantityControllers = {};
  final Map<String, TextEditingController> _separatePriceControllers = {};
  final Map<String, TextEditingController> _separateLineTotalControllers = {};

  @override
  void initState() {
    super.initState();
    if (widget.item.product.manageStockSeparately) {
      _initializeSeparateControllers();
    } else {
      _initializeRegularControllers();
    }
  }

  void _initializeRegularControllers() {
    _quantityController =
        TextEditingController(text: formatNumber(widget.item.quantity));
    _priceController =
        TextEditingController(text: formatNumber(widget.item.price));
    _quantityController.addListener(() => widget.onQuantityChanged(
        double.tryParse(_quantityController.text
            .replaceAll('.', '')
            .replaceAll(',', '.')) ??
            0.0));
    _priceController.addListener(() => widget.onPriceChanged(double.tryParse(
        _priceController.text.replaceAll('.', '').replaceAll(',', '.')) ??
        0.0));
  }

  void _initializeSeparateControllers() {
    for (final unit in widget.item.product.getAllUnits) {
      _separateQuantityControllers[unit] = TextEditingController(
        text: formatNumber(widget.item.separateQuantities[unit] ?? 0),
      );
      _separatePriceControllers[unit] = TextEditingController(
        text: formatNumber(widget.item.separatePrices[unit] ?? 0),
      );
      _separateLineTotalControllers[unit] = TextEditingController(text: '0');
      void updateLineTotal() {
        final qty = double.tryParse(_separateQuantityControllers[unit]!
            .text
            .replaceAll('.', '')
            .replaceAll(',', '.')) ??
            0.0;
        final price = double.tryParse(_separatePriceControllers[unit]!
            .text
            .replaceAll('.', '')
            .replaceAll(',', '.')) ??
            0.0;
        _separateLineTotalControllers[unit]!.text = formatNumber(qty * price);
      }

      _separateQuantityControllers[unit]!.addListener(() {
        final qty = double.tryParse(_separateQuantityControllers[unit]!
            .text
            .replaceAll('.', '')
            .replaceAll(',', '.')) ??
            0.0;
        widget.onSeparateQuantityChanged(unit, qty);
        updateLineTotal();
      });
      _separatePriceControllers[unit]!.addListener(() {
        final price = double.tryParse(_separatePriceControllers[unit]!
            .text
            .replaceAll('.', '')
            .replaceAll(',', '.')) ??
            0.0;
        widget.onSeparatePriceChanged(unit, price);
        updateLineTotal();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ProductListItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.item.product.manageStockSeparately &&
        widget.item.price != oldWidget.item.price) {
      final formattedPrice = formatNumber(widget.item.price);
      if (_priceController.text != formattedPrice) {
        _priceController.value = TextEditingValue(
            text: formattedPrice,
            selection: TextSelection.collapsed(offset: formattedPrice.length));
      }
    }
  }

  @override
  void dispose() {
    if (!widget.item.product.manageStockSeparately) {
      _quantityController.dispose();
      _priceController.dispose();
    }
    for (final controller in _separateQuantityControllers.values) {
      controller.dispose();
    }
    for (final controller in _separatePriceControllers.values) {
      controller.dispose();
    }
    for (final controller in _separateLineTotalControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isDesktop) {
      return widget.item.product.manageStockSeparately
          ? _buildDesktopSeparated()
          : _buildDesktopRegular();
    } else {
      return widget.item.product.manageStockSeparately
          ? _buildMobileSeparated()
          : _buildMobileRegular();
    }
  }

  Widget _buildSmallProductImage() => SizedBox(
    width: 80,
    height: 80,
    child: RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: widget.item.product.imageUrl != null &&
            widget.item.product.imageUrl!.isNotEmpty
            ? CachedNetworkImage(
            imageUrl: widget.item.product.imageUrl!,
            fit: BoxFit.contain,
            memCacheWidth: 160)
            : Container(
            color: Colors.grey.shade200,
            child: const Icon(Icons.inventory_2_outlined,
                color: Colors.grey)),
      ),
    ),
  );

  double _getStockForUnit(String unitName) {
    if (unitName == widget.item.product.unit) return widget.item.product.stock;
    final unitData = widget.item.product.additionalUnits
        .firstWhereOrNull((u) => u['unitName'] == unitName);
    return (unitData?['stock'] as num?)?.toDouble() ?? 0.0;
  }

  Widget _buildDesktopRegular() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildSmallProductImage(),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8.0,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(widget.item.product.productName,
                                style:
                                AppTheme.boldTextStyle.copyWith(fontSize: 16)),
                            Text(
                                '(Tồn: ${formatNumber(widget.item.product.stock)})',
                                style: AppTheme.regularTextStyle),
                          ],
                        ),
                      ),
                      IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          icon: Icon(Icons.delete_outline,
                              color: Colors.red.shade400, size: 25),
                          onPressed: widget.isReadOnly ? null : widget.onRemove),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('${formatNumber(widget.item.subtotal)} đ',
                        style: AppTheme.boldTextStyle
                            .copyWith(fontSize: 16, color: AppTheme.primaryColor)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(flex: 2, child: _buildPriceInput(_priceController)),
                      const SizedBox(width: 8),
                      Expanded(
                          flex: 1, child: _buildQuantityInput(_quantityController)),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: _buildUnitDropdown(widget.item)),
                    ],
                  ),
                ],
              )),
        ],
      ),
    );
  }

  Widget _buildDesktopSeparated() {
    final availableUnits = widget.item.product.getAllUnits
        .where((unit) => widget.item.separateQuantities.containsKey(unit))
        .toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildSmallProductImage(),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: Text(widget.item.product.productName,
                                style: AppTheme.boldTextStyle
                                    .copyWith(fontSize: 16))),
                        IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(Icons.delete_outline,
                                color: Colors.red.shade400, size: 25),
                            onPressed: widget.isReadOnly ? null : widget.onRemove),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                          '${formatNumber(widget.item.separateSubtotal)} đ',
                          style: AppTheme.boldTextStyle.copyWith(
                              fontSize: 16, color: AppTheme.primaryColor)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...availableUnits.map((unit) => Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _buildUnitInputLine(unit))),
        ],
      ),
    );
  }

  Widget _buildMobileRegular() {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias, // Needed for positioned Stack children
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center, // Vertically align content
                  children: [
                    _buildSmallProductImage(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 80, // Match image height for alignment
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center, // Center text block
                          children: [
                            Text(
                              widget.item.product.productName,
                              style: AppTheme.boldTextStyle.copyWith(fontSize: 16),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text(
                                  '(Tồn: ${formatNumber(widget.item.product.stock)})',
                                  style: AppTheme.regularTextStyle,
                                ),
                                const Spacer(), // Push price to the right
                                Text(
                                  '${formatNumber(widget.item.subtotal)} đ',
                                  style: AppTheme.boldTextStyle.copyWith(
                                    fontSize: 16,
                                    color: AppTheme.primaryColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPriceInput(_priceController),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(flex: 4, child: _buildQuantityInput(_quantityController)),
                    const SizedBox(width: 8),
                    Expanded(flex: 6, child: _buildUnitDropdown(widget.item)),
                  ],
                ),
              ],
            ),
          ),
          // Positioned delete button in the top-right corner
          if (!widget.isReadOnly)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 25),
                onPressed: widget.onRemove,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMobileSeparated() {
    final availableUnits = widget.item.product.getAllUnits
        .where((unit) => widget.item.separateQuantities.containsKey(unit))
        .toList();
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildSmallProductImage(),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 80, // Match image height
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              widget.item.product.productName,
                              style: AppTheme.boldTextStyle.copyWith(fontSize: 16),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                '${formatNumber(widget.item.separateSubtotal)} đ',
                                style: AppTheme.boldTextStyle.copyWith(
                                  fontSize: 16,
                                  color: AppTheme.primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (availableUnits.isNotEmpty) const SizedBox(height: 16),
                ...availableUnits.map((unit) => Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _buildUnitInputLineMobile(unit))),
              ],
            ),
          ),
          if (!widget.isReadOnly)
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 25),
                onPressed: widget.onRemove,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnitInputLine(String unitName) {
    return Row(
      children: [
        IconButton(
            padding: const EdgeInsets.only(right: 8),
            constraints: const BoxConstraints(),
            icon: Icon(Icons.cancel, color: Colors.grey.shade600, size: 25),
            onPressed: widget.isReadOnly ? null : () => widget.onSeparateUnitRemoved(unitName)),
        Expanded(
            flex: 1,
            child: CustomTextFormField(
                readOnly: true, // Always read-only
                initialValue: formatNumber(_getStockForUnit(unitName)),
                textAlign: TextAlign.left,
                decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Tồn kho',
                    border: InputBorder.none))),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: CustomTextFormField(
                readOnly: widget.isReadOnly,
                controller: _separatePriceControllers[unitName]!,
                decoration: InputDecoration(
                    isDense: true, labelText: 'Giá $unitName'))),
        const SizedBox(width: 8),
        Expanded(
            flex: 1,
            child: CustomTextFormField(
                readOnly: widget.isReadOnly,
                controller: _separateQuantityControllers[unitName]!,
                decoration:
                InputDecoration(isDense: true, labelText: 'SL $unitName'))),
        const SizedBox(width: 8),
        Expanded(
            flex: 3,
            child: CustomTextFormField(
                readOnly: true, // Always read-only
                controller: _separateLineTotalControllers[unitName],
                textAlign: TextAlign.right,
                decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Thành tiền',
                    border: InputBorder.none))),
      ],
    );
  }

  Widget _buildUnitInputLineMobile(String unitName) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  flex: 6,
                  child: CustomTextFormField(
                      readOnly: widget.isReadOnly,
                      controller: _separatePriceControllers[unitName]!,
                      decoration: InputDecoration(
                          isDense: true, labelText: 'Giá $unitName'))),
              const SizedBox(width: 8),
              Expanded(
                  flex: 4,
                  child: CustomTextFormField(
                      readOnly: widget.isReadOnly,
                      controller: _separateQuantityControllers[unitName]!,
                      decoration: InputDecoration(
                          isDense: true, labelText: 'SL $unitName'))),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Tồn: ${formatNumber(_getStockForUnit(unitName))}',
                  style: AppTheme.regularTextStyle),
              Text(
                  'TT: ${formatNumber((widget.item.separatePrices[unitName] ?? 0) * (widget.item.separateQuantities[unitName] ?? 0))} đ',
                  style: AppTheme.regularTextStyle
                      .copyWith(fontWeight: FontWeight.w500)),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildPriceInput(TextEditingController controller) =>
      CustomTextFormField(
          controller: controller,
          readOnly: widget.isReadOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [widget.thousandFormatter],
          decoration: const InputDecoration(
              isDense: true,
              labelText: 'Giá nhập',
              prefixIcon: Icon(Icons.price_change_outlined, size: 20)));

  Widget _buildQuantityInput(TextEditingController controller) =>
      CustomTextFormField(
          controller: controller,
          readOnly: widget.isReadOnly,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [widget.thousandFormatter],
          decoration: const InputDecoration(
              isDense: true,
              labelText: 'Số lượng',
              prefixIcon: Icon(Icons.format_list_numbered, size: 20)));

  Widget _buildUnitDropdown(PurchaseOrderItem item) => AppDropdown<String>(
      isDense: true,
      labelText: 'Đơn vị',
      value: item.unit,
      items: item.product.getAllUnits
          .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
          .toList(),
      onChanged: widget.isReadOnly ? null : (value) {
        if (value != null) widget.onUnitChanged(value);
      },
      prefixIcon: Icons.category_outlined);
}