import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/firestore_service.dart';
import '../../services/discount_service.dart';
import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/product_search_delegate.dart';
import '../../widgets/app_dropdown.dart';

class BuyXGetYFormScreen extends StatefulWidget {
  final UserModel currentUser;
  final Map<String, dynamic>? initialData;

  const BuyXGetYFormScreen({
    super.key,
    required this.currentUser,
    this.initialData,
  });

  @override
  State<BuyXGetYFormScreen> createState() => _BuyXGetYFormScreenState();
}

class _BuyXGetYFormScreenState extends State<BuyXGetYFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  final _buyQuantityController = TextEditingController(text: '1');
  final _giftQuantityController = TextEditingController(text: '1');
  final _giftPriceController = TextEditingController(text: '0');

  ProductModel? _buyProduct;
  ProductModel? _giftProduct;

  String? _buyUnit;
  String? _giftUnit;

  bool _isLoading = false;
  bool _isActive = true;

  String _timeType = 'specific';
  DateTime? _startAt;
  DateTime? _endAt;
  final List<Map<String, TimeOfDay>> _dailyTimeRanges = [];
  final List<int> _selectedWeekDays = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  void _initData() {
    if (widget.initialData != null) {
      final data = widget.initialData!;
      _nameController.text = data['name'] ?? '';
      _isActive = data['isActive'] ?? true;
      _buyQuantityController.text = formatNumber((data['buyQuantity'] ?? 1).toDouble());
      _giftQuantityController.text = formatNumber((data['giftQuantity'] ?? 1).toDouble());
      _giftPriceController.text = formatNumber((data['giftPrice'] ?? 0).toDouble());

      _buyUnit = data['buyUnit'];
      _giftUnit = data['giftUnit'];

      _timeType = data['timeType'] ?? 'specific';
      if (data['startAt'] != null) _startAt = data['startAt'].toDate();
      if (data['endAt'] != null) _endAt = data['endAt'].toDate();

      if (data['daysOfWeek'] != null) {
        _selectedWeekDays.addAll(List<int>.from(data['daysOfWeek']));
      }

      if (data['dailyTimeRanges'] != null) {
        for (var range in data['dailyTimeRanges']) {
          final startParts = range['start'].split(':');
          final endParts = range['end'].split(':');
          _dailyTimeRanges.add({
            'start': TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1])),
            'end': TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
          });
        }
      }

      _loadFullProductDetails(data['buyProductId'], data['giftProductId']);

    } else {
      if (_dailyTimeRanges.isEmpty) {
        _dailyTimeRanges.add({
          'start': const TimeOfDay(hour: 8, minute: 0),
          'end': const TimeOfDay(hour: 22, minute: 0)
        });
      }
    }
  }

  Future<void> _loadFullProductDetails(String? buyId, String? giftId) async {
    if (buyId == null && giftId == null) return;
    final fs = FirestoreService();
    final List<Future<List<ProductModel>>> futures = [];
    if (buyId != null) futures.add(fs.getProductsByIds([buyId]));
    if (giftId != null) futures.add(fs.getProductsByIds([giftId]));

    final results = await Future.wait(futures);

    if (!mounted) return;

    setState(() {
      if (buyId != null && results.isNotEmpty && results[0].isNotEmpty) {
        _buyProduct = results[0].first;
        if (_buyUnit == null || !_isValidUnit(_buyProduct!, _buyUnit!)) {
          _buyUnit = _buyProduct!.unit;
        }
      }

      int giftIndex = (buyId != null) ? 1 : 0;
      if (giftId != null && results.length > giftIndex && results[giftIndex].isNotEmpty) {
        _giftProduct = results[giftIndex].first;
        if (_giftUnit == null || !_isValidUnit(_giftProduct!, _giftUnit!)) {
          _giftUnit = _giftProduct!.unit;
        }
      }
    });
  }

  bool _isValidUnit(ProductModel p, String unit) {
    if (p.unit == unit) return true;
    return p.additionalUnits.any((u) => u['unitName'] == unit);
  }

  Future<void> _pickProduct(bool isBuyProduct) async {
    const allowedTypes = ['Hàng hóa', 'Thành phẩm/Combo', 'Dịch vụ/Tính giờ', 'Topping/Bán kèm'];
    List<ProductModel> selected = [];

    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: selected,
      groupByCategory: true,
      allowedProductTypes: allowedTypes,
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        if (isBuyProduct) {
          _buyProduct = result.first;
          _buyUnit = _buyProduct?.unit;
        } else {
          _giftProduct = result.first;
          _giftUnit = _giftProduct?.unit;
        }
      });
    }
  }

  Widget _buildUnitDropdown({
    required ProductModel? product,
    required String? currentUnit,
    required ValueChanged<String?> onChanged,
  }) {
    if (product == null) return const SizedBox.shrink();

    final List<String> units = [
      product.unit ?? 'ĐVT',
      ...product.additionalUnits.map((e) => e['unitName'] as String),
    ];

    return AppDropdown<String>(
      value: (currentUnit != null && units.contains(currentUnit)) ? currentUnit : units.first,
      items: units.map((u) => DropdownMenuItem(
        value: u,
        child: Text(u, style: const TextStyle(fontWeight: FontWeight.bold)),
      )).toList(),
      onChanged: onChanged,
      labelText: "ĐVT",
    );
  }

  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
  TimeOfDay _minutesToTime(int total) => TimeOfDay(hour: total ~/ 60, minute: total % 60);

  Future<void> _pickTimeForRange(int index, bool isStart) async {
    final currentRange = _dailyTimeRanges[index];
    final initial = isStart ? currentRange['start']! : currentRange['end']!;

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          if (_minutes(picked) >= _minutes(currentRange['end']!)) {
            final newEndMin = _minutes(picked) + 60;
            _dailyTimeRanges[index]['end'] = newEndMin < 1440
                ? _minutesToTime(newEndMin)
                : const TimeOfDay(hour: 23, minute: 59);
          }
          _dailyTimeRanges[index]['start'] = picked;
        } else {
          if (_minutes(picked) <= _minutes(currentRange['start']!)) {
            ToastService().show(message: "Giờ kết thúc phải sau giờ bắt đầu", type: ToastType.warning);
            return;
          }
          _dailyTimeRanges[index]['end'] = picked;
        }
      });
    }
  }

  void _addTimeRange() {
    setState(() {
      _dailyTimeRanges.add({
        'start': const TimeOfDay(hour: 12, minute: 0),
        'end': const TimeOfDay(hour: 13, minute: 0),
      });
    });
  }

  void _removeTimeRange(int index) {
    setState(() {
      _dailyTimeRanges.removeAt(index);
    });
  }

  Future<void> _pickRangeDate() async {
    List<DateTime>? result = await showOmniDateTimeRangePicker(
      context: context,
      startInitialDate: _startAt ?? DateTime.now(),
      startFirstDate: DateTime(2020),
      startLastDate: DateTime(2100),
      endInitialDate: _endAt ?? DateTime.now().add(const Duration(hours: 1)),
      endFirstDate: DateTime(2020),
      endLastDate: DateTime(2100),
      is24HourMode: true,
      isShowSeconds: false,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
    );

    if (result != null && result.length == 2) {
      setState(() {
        _startAt = result[0];
        _endAt = result[1];
      });
    }
  }

  Future<void> _savePromotion() async {
    if (!_formKey.currentState!.validate()) return;
    if (_buyProduct == null || _giftProduct == null) {
      ToastService().show(message: "Vui lòng chọn đủ sản phẩm Mua và Tặng", type: ToastType.error);
      return;
    }

    _buyUnit ??= _buyProduct!.unit;
    _giftUnit ??= _giftProduct!.unit;

    setState(() => _isLoading = true);

    try {
      List<Map<String, String>>? rangesToSave;
      if (_timeType != 'specific') {
        rangesToSave = _dailyTimeRanges.map((e) => {
          'start': "${e['start']!.hour.toString().padLeft(2, '0')}:${e['start']!.minute.toString().padLeft(2, '0')}",
          'end': "${e['end']!.hour.toString().padLeft(2, '0')}:${e['end']!.minute.toString().padLeft(2, '0')}",
        }).toList();
      }

      final data = {
        'storeId': widget.currentUser.storeId,
        'name': _nameController.text.trim(),
        'isActive': _isActive,

        'buyProductId': _buyProduct!.id,
        'buyProductName': _buyProduct!.productName,
        'buyQuantity': parseVN(_buyQuantityController.text),
        'buyUnit': _buyUnit,
        'buyProductImageUrl': _buyProduct!.imageUrl,

        'giftProductId': _giftProduct!.id,
        'giftProductName': _giftProduct!.productName,
        'giftQuantity': parseVN(_giftQuantityController.text),
        'giftPrice': parseVN(_giftPriceController.text),
        'giftUnit': _giftUnit,
        'giftProductImageUrl': _giftProduct!.imageUrl,

        'timeType': _timeType,
        'startAt': _timeType == 'specific' ? _startAt : null,
        'endAt': _timeType == 'specific' ? _endAt : null,
        'dailyTimeRanges': rangesToSave,
        'daysOfWeek': _timeType == 'weekly' ? _selectedWeekDays : null,
      };

      await FirestoreService().saveBuyXGetY(
          data,
          id: widget.initialData?['id']
      );

      DiscountService.notifyDiscountsChanged();

      if (mounted) {
        ToastService().show(message: "Lưu thành công!", type: ToastType.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      ToastService().show(message: "Lỗi lưu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePromotion() async {
    if (widget.initialData == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: const Text("Bạn có chắc muốn xóa chương trình này?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Hủy")),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Xóa", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await FirestoreService().deleteBuyXGetY(widget.initialData!['id']);
      DiscountService.notifyDiscountsChanged();
      if (mounted) {
        ToastService().show(message: "Đã xóa thành công", type: ToastType.success);
        Navigator.of(context).pop();
      }
    } catch (e) {
      ToastService().show(message: "Lỗi xóa: $e", type: ToastType.error);
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialData != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? "Sửa Mua X Tặng Y" : "Tạo Mua X Tặng Y"),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _isLoading ? null : _deletePromotion,
            ),
          IconButton(
            onPressed: _isLoading ? null : _savePromotion,
            icon: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save, size: 30, color: AppTheme.primaryColor),
          )
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                    labelText: "Tên chương trình",
                    prefixIcon: Icon(Icons.campaign)
                ),
                validator: (v) => v!.isEmpty ? "Nhập tên chương trình" : null,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text("Kích hoạt"),
                value: _isActive,
                onChanged: (val) => setState(() => _isActive = val),
              ),
              const SizedBox(height: 8),
              _buildSectionHeader("Thời gian áp dụng", Icons.access_time),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(12)),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _buildRadioTime("Cụ thể", "specific"),
                        _buildRadioTime("Hàng ngày", "daily"),
                        _buildRadioTime("Hàng tuần", "weekly"),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildTimeContent(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // KHỐI MUA
              _buildSectionHeader("Điều kiện Mua (X)", Icons.shopping_cart_outlined),
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildProductSelector(
                        isBuyProduct: true,
                        product: _buyProduct,
                        onTap: () => _pickProduct(true),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildUnitDropdown(
                              product: _buyProduct,
                              currentUnit: _buyUnit,
                              onChanged: (val) => setState(() => _buyUnit = val),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: CustomTextFormField(
                              controller: _buyQuantityController,
                              // [SỬA] Bỏ contentPadding và isDense để bằng chiều cao Dropdown
                              decoration: const InputDecoration(
                                labelText: "SL Mua",
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ThousandDecimalInputFormatter()],
                              textAlign: TextAlign.center,
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // KHỐI TẶNG
              _buildSectionHeader("Quà tặng (Y)", Icons.card_giftcard),
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      _buildProductSelector(
                        isBuyProduct: false,
                        product: _giftProduct,
                        onTap: () => _pickProduct(false),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: _buildUnitDropdown(
                              product: _giftProduct,
                              currentUnit: _giftUnit,
                              onChanged: (val) => setState(() => _giftUnit = val),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 4,
                            child: CustomTextFormField(
                              controller: _giftQuantityController,
                              // [SỬA] Bỏ contentPadding và isDense
                              decoration: const InputDecoration(
                                labelText: "SL Tặng",
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ThousandDecimalInputFormatter()],
                              textAlign: TextAlign.center,
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: CustomTextFormField(
                              controller: _giftPriceController,
                              // [SỬA] Bỏ contentPadding và isDense
                              decoration: const InputDecoration(
                                labelText: "Giá trị sản phẩm Y (Thường là 0)",
                                prefixIcon: Icon(Icons.attach_money),
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [ThousandDecimalInputFormatter()],
                              textAlign: TextAlign.end,
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildProductSelector({required bool isBuyProduct, required ProductModel? product, required VoidCallback onTap}) {
    if (product == null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          width: double.infinity,
          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400, style: BorderStyle.solid), borderRadius: BorderRadius.circular(8), color: Colors.grey.shade50),
          child: Column(
            children: [
              Icon(Icons.add_circle_outline, color: Colors.grey.shade600, size: 30),
              const SizedBox(height: 8),
              Text(isBuyProduct ? "Chọn sản phẩm MUA" : "Chọn sản phẩm TẶNG", style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold))
            ],
          ),
        ),
      );
    }
    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 60, height: 60,
              child: product.imageUrl != null && product.imageUrl!.isNotEmpty
                  ? CachedNetworkImage(imageUrl: product.imageUrl!, fit: BoxFit.cover)
                  : Container(color: Colors.grey.shade200, child: const Icon(Icons.image, color: Colors.grey)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          ),
          const Icon(Icons.edit, color: Colors.blue),
        ],
      ),
    );
  }

  Widget _buildRadioTime(String label, String value) {
    final isSelected = _timeType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _timeType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withAlpha(25) : Colors.transparent,
            border: Border(bottom: BorderSide(color: isSelected ? AppTheme.primaryColor : Colors.transparent, width: 2)),
          ),
          alignment: Alignment.center,
          child: Text(label, style: TextStyle(color: isSelected ? AppTheme.primaryColor : Colors.grey.shade700, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 16)),
        ),
      ),
    );
  }

  Widget _buildTimeContent() {
    if (_timeType == 'specific') {
      final text = (_startAt != null && _endAt != null)
          ? "${DateFormat('HH:mm dd/MM/yyyy').format(_startAt!)} \nđến ${DateFormat('HH:mm dd/MM/yyyy').format(_endAt!)}"
          : "Chạm để chọn thời gian";
      return InkWell(
        onTap: _pickRangeDate,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
          child: Row(
            children: [
              const Icon(Icons.calendar_month, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15))),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_timeType == 'weekly') ...[
          const Text("Chọn ngày trong tuần:", style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Center(
            child: Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              alignment: WrapAlignment.center,
              children: List.generate(7, (index) {
                final dayVal = index + 2;
                final label = index == 6 ? "CN" : "T${index + 2}";
                final isSelected = _selectedWeekDays.contains(dayVal);
                return FilterChip(
                  label: Text(label, style: TextStyle(color: isSelected ? Colors.white : Colors.black87)),
                  selected: isSelected,
                  showCheckmark: true,
                  checkmarkColor: Colors.white,
                  selectedColor: AppTheme.primaryColor,
                  backgroundColor: Colors.grey.shade100,
                  onSelected: (val) {
                    setState(() {
                      if (val) {
                        _selectedWeekDays.add(dayVal);
                      } else {
                        _selectedWeekDays.remove(dayVal);
                      }
                    });
                  },
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
        ],

        const Text("Khung giờ áp dụng (Trong ngày):", style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _dailyTimeRanges.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final range = _dailyTimeRanges[index];
            return Row(
              children: [
                Expanded(child: _buildTimeBox("Từ", range['start']!, () => _pickTimeForRange(index, true))),
                const SizedBox(width: 8),
                Expanded(child: _buildTimeBox("Đến", range['end']!, () => _pickTimeForRange(index, false))),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeTimeRange(index),
                  tooltip: "Xóa khung giờ này",
                )
              ],
            );
          },
        ),
        TextButton.icon(onPressed: _addTimeRange, icon: const Icon(Icons.add_alarm), label: const Text("Thêm khung giờ")),
      ],
    );
  }

  Widget _buildTimeBox(String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}", style: const TextStyle(fontSize: 15)),
            const Icon(Icons.access_time, size: 18),
          ],
        ),
      ),
    );
  }
}