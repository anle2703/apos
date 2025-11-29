// File: lib/screens/promotions/discount_form_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/firestore_service.dart';
import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../models/discount_model.dart';
import '../../models/customer_group_model.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/product_search_delegate.dart';
import '../../services/discount_service.dart';

class DiscountFormScreen extends StatefulWidget {
  final UserModel currentUser;
  final DiscountModel? discount;

  const DiscountFormScreen({
    super.key,
    required this.currentUser,
    this.discount,
  });

  @override
  State<DiscountFormScreen> createState() => _DiscountFormScreenState();
}

class _DiscountFormScreenState extends State<DiscountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;

  // --- Logic Thời gian ---
  String _timeType = 'specific'; // 'specific', 'daily', 'weekly'
  DateTime? _startAt;
  DateTime? _endAt;

  // [CẬP NHẬT] Thay vì 1 mốc giờ, dùng danh sách mốc giờ
  List<Map<String, TimeOfDay>> _dailyTimeRanges = [];

  List<int> _selectedWeekDays = []; // 2=Mon, 8=Sun

  // --- Logic Đối tượng ---
  String _targetType = 'all'; // 'all', 'retail', 'group'
  CustomerGroupModel? _selectedGroup;
  List<CustomerGroupModel> _availableGroups = [];

  // --- Logic Sản phẩm ---
  List<DiscountItem> _selectedItems = [];
  final TextEditingController _calcValueController = TextEditingController();
  bool _isCalcPercent = true;
  bool _isIncrease = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.discount?.name ?? '');
    _initData();
    _fetchCustomerGroups();
  }

  void _initData() {
    final d = widget.discount;
    if (d != null) {
      _selectedItems = List.from(d.items);
      _timeType = d.type;
      _startAt = d.startAt;
      _endAt = d.endAt;

      // [CẬP NHẬT] Load danh sách khung giờ từ Model
      if (d.dailyTimeRanges != null) {
        for (var range in d.dailyTimeRanges!) {
          if (range['start'] != null && range['end'] != null) {
            final startParts = range['start']!.split(':');
            final endParts = range['end']!.split(':');
            _dailyTimeRanges.add({
              'start': TimeOfDay(hour: int.parse(startParts[0]), minute: int.parse(startParts[1])),
              'end': TimeOfDay(hour: int.parse(endParts[0]), minute: int.parse(endParts[1])),
            });
          }
        }
      }

      // Nếu dữ liệu cũ rỗng hoặc tạo mới mà chưa có gì, thêm 1 dòng mặc định
      if (_dailyTimeRanges.isEmpty && _timeType != 'specific') {
        _dailyTimeRanges.add({
          'start': const TimeOfDay(hour: 8, minute: 0),
          'end': const TimeOfDay(hour: 11, minute: 0)
        });
      }

      _selectedWeekDays = d.daysOfWeek ?? [];
      _targetType = d.targetType;
    } else {
      // Mặc định thêm 1 dòng giờ
      _dailyTimeRanges.add({
        'start': const TimeOfDay(hour: 8, minute: 0),
        'end': const TimeOfDay(hour: 11, minute: 0)
      });
    }
  }

  Future<void> _fetchCustomerGroups() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.currentUser.storeId)
          .collection('customer_groups')
          .get();

      if (mounted) {
        setState(() {
          _availableGroups = snapshot.docs
              .map((doc) => CustomerGroupModel.fromFirestore(doc))
              .toList();

          if (widget.discount?.targetGroupId != null) {
            try {
              _selectedGroup = _availableGroups.firstWhere((g) => g.id == widget.discount!.targetGroupId);
            } catch (_) {}
          }
        });
      }
    } catch (e) {
      debugPrint("Error fetching groups: $e");
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _calcValueController.dispose();
    super.dispose();
  }

  // --- HÀM CHỌN THỜI GIAN CỤ THỂ (NGÀY THÁNG) ---
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
      minutesInterval: 1,
      secondsInterval: 1,
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      constraints: const BoxConstraints(maxHeight: 650),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(opacity: anim1.drive(Tween(begin: 0, end: 1)), child: child);
      },
      transitionDuration: const Duration(milliseconds: 200),
      barrierDismissible: true,
    );

    if (result != null && result.length == 2) {
      final start = result[0];
      final end = result[1];

      setState(() {
        _startAt = DateTime(start.year, start.month, start.day, start.hour, start.minute, 0, 0);
        _endAt = DateTime(end.year, end.month, end.day, end.hour, end.minute, 0, 0);
      });
    }
  }

  // --- [CẬP NHẬT] HÀM CHỌN GIỜ TRONG NGÀY (MULTI RANGE) ---

  // Helper chuyển đổi TimeOfDay sang phút để so sánh
  int _minutes(TimeOfDay t) => t.hour * 60 + t.minute;
  TimeOfDay _minutesToTime(int total) => TimeOfDay(hour: total ~/ 60, minute: total % 60);

  Future<void> _pickTimeForRange(int index, bool isStart) async {
    final currentRange = _dailyTimeRanges[index];
    final initial = isStart ? currentRange['start']! : currentRange['end']!;

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? "Giờ bắt đầu" : "Giờ kết thúc",
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          // Logic: Nếu Giờ bắt đầu >= Giờ kết thúc hiện tại -> Tự động đẩy Giờ kết thúc lên
          if (_minutes(picked) >= _minutes(currentRange['end']!)) {
            final newEndMin = _minutes(picked) + 60; // Cộng thêm 1 tiếng
            if (newEndMin < 24 * 60) {
              _dailyTimeRanges[index]['end'] = _minutesToTime(newEndMin);
            } else {
              // Nếu cộng xong mà qua ngày -> Chặn ở 23:59
              _dailyTimeRanges[index]['end'] = const TimeOfDay(hour: 23, minute: 59);
            }
          }
          _dailyTimeRanges[index]['start'] = picked;
        } else {
          // Logic: Kiểm tra Giờ kết thúc
          // Yêu cầu: Không được qua ngày và phải lớn hơn giờ bắt đầu
          // TimePicker mặc định trả về giờ trong ngày (0-23h), nên ta chỉ cần so sánh với Start

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

  // --- HÀM CHỌN SẢN PHẨM & TÍNH TOÁN ---
  Future<void> _pickProducts() async {
    final prevSelected = _selectedItems.map((e) => ProductModel(
      id: e.productId,
      productName: e.productName,
      imageUrl: e.imageUrl,
      sellPrice: e.oldPrice,
      storeId: widget.currentUser.storeId,
      productCode: '', additionalBarcodes: [], additionalUnits: [],
      costPrice: 0, stock: 0, minStock: 0, ownerUid: '',
      accompanyingItems: [], recipeItems: [], compiledMaterials: [], kitchenPrinters: [],
      productType: '',
    )).toList();

    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: widget.currentUser,
      previouslySelected: prevSelected,
      groupByCategory: true,
      allowedProductTypes: const [
        'Hàng hóa', 'Thành phẩm/Combo', 'Dịch vụ/Tính giờ', 'Topping/Bán kèm',
      ],
    );

    if (result != null) {
      setState(() {
        final oldMap = {for (var item in _selectedItems) item.productId: item};
        List<DiscountItem> mergedList = [];
        for (var product in result) {
          if (oldMap.containsKey(product.id)) {
            mergedList.add(oldMap[product.id]!);
          } else {
            mergedList.add(DiscountItem(
              productId: product.id,
              productName: product.productName,
              imageUrl: product.imageUrl,
              oldPrice: product.sellPrice,
              value: 0,
              isPercent: true,
            ));
          }
        }
        _selectedItems = mergedList;
      });
    }
  }

  void _applyBulkAdjustment() {
    final valueStr = _calcValueController.text.replaceAll('.', '').replaceAll(',', '');
    final value = double.tryParse(valueStr) ?? 0.0;
    if (value <= 0) return;

    setState(() {
      final updatedList = <DiscountItem>[];
      for (var item in _selectedItems) {
        updatedList.add(DiscountItem(
          productId: item.productId,
          productName: item.productName,
          imageUrl: item.imageUrl,
          oldPrice: item.oldPrice,
          value: value,
          isPercent: _isCalcPercent,
        ));
      }
      _selectedItems = updatedList;
    });
    ToastService().show(message: "Đã cập nhật mức giảm!", type: ToastType.success);
  }

  void _showEditSingleItemPrice(int index) {
    final item = _selectedItems[index];
    final controller = TextEditingController(text: formatNumber(item.value));
    bool isPercentLocal = item.isPercent;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text("Giảm giá: ${item.productName}"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Giá gốc: ${formatNumber(item.oldPrice)}"),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: CustomTextFormField(
                          controller: controller,
                          decoration: InputDecoration(
                            labelText: isPercentLocal ? "Số % giảm" : "Số tiền giảm",
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [ThousandDecimalInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ToggleButtons(
                        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
                        isSelected: [isPercentLocal, !isPercentLocal],
                        onPressed: (idx) {
                          setDialogState(() => isPercentLocal = idx == 0);
                        },
                        children: const [Text("%"), Text("đ")],
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text("Hủy")),
                ElevatedButton(
                    onPressed: () {
                      final val = parseVN(controller.text);
                      if (isPercentLocal && val > 100) {
                        ToastService().show(message: "% không thể lớn hơn 100", type: ToastType.error);
                        return;
                      }
                      setState(() {
                        _selectedItems[index] = DiscountItem(
                          productId: item.productId,
                          productName: item.productName,
                          imageUrl: item.imageUrl,
                          oldPrice: item.oldPrice,
                          value: val,
                          isPercent: isPercentLocal,
                        );
                      });
                      Navigator.pop(context);
                    },
                    child: const Text("Xác nhận")
                ),
              ],
            );
          }
      ),
    );
  }

  Future<void> _saveDiscount() async {
    if (!_formKey.currentState!.validate()) return;
    if (_nameController.text.isEmpty) {
      ToastService().show(message: "Vui lòng nhập tên chương trình", type: ToastType.error);
      return;
    }
    if (_selectedItems.isEmpty) {
      ToastService().show(message: "Vui lòng chọn sản phẩm", type: ToastType.error);
      return;
    }

    // Validate Time
    if (_timeType == 'specific') {
      if (_startAt == null || _endAt == null) {
        ToastService().show(message: "Vui lòng chọn khoảng thời gian", type: ToastType.error);
        return;
      }
      if (_startAt!.isAfter(_endAt!)) {
        ToastService().show(message: "Thời gian kết thúc phải sau bắt đầu", type: ToastType.error);
        return;
      }
    } else {
      // Validate Daily/Weekly
      if (_timeType == 'weekly' && _selectedWeekDays.isEmpty) {
        ToastService().show(message: "Vui lòng chọn ít nhất 1 ngày trong tuần", type: ToastType.error);
        return;
      }
      // Check list khung giờ
      if (_dailyTimeRanges.isEmpty) {
        ToastService().show(message: "Vui lòng thêm ít nhất 1 khung giờ", type: ToastType.error);
        return;
      }
      for (var range in _dailyTimeRanges) {
        if (_minutes(range['end']!) <= _minutes(range['start']!)) {
          ToastService().show(message: "Lỗi khung giờ: Kết thúc phải sau Bắt đầu (Không được qua ngày)", type: ToastType.error);
          return;
        }
      }
    }

    // Validate Customer Group
    if (_targetType == 'group' && _selectedGroup == null) {
      ToastService().show(message: "Vui lòng chọn nhóm khách hàng", type: ToastType.error);
      return;
    }

    // [CẬP NHẬT] Map danh sách giờ để lưu
    List<Map<String, String>>? rangesToSave;
    if (_timeType != 'specific') {
      rangesToSave = _dailyTimeRanges.map((e) => {
        'start': "${e['start']!.hour.toString().padLeft(2, '0')}:${e['start']!.minute.toString().padLeft(2, '0')}",
        'end': "${e['end']!.hour.toString().padLeft(2, '0')}:${e['end']!.minute.toString().padLeft(2, '0')}",
      }).toList();
    }

    final discountModel = DiscountModel(
      id: widget.discount?.id ?? '',
      name: _nameController.text.trim(),
      storeId: widget.currentUser.storeId,
      items: _selectedItems,

      type: _timeType,
      startAt: _timeType == 'specific' ? _startAt : null,
      endAt: _timeType == 'specific' ? _endAt : null,

      // Lưu danh sách khung giờ
      dailyTimeRanges: rangesToSave,

      daysOfWeek: _timeType == 'weekly' ? _selectedWeekDays : null,
      targetType: _targetType,
      targetGroupId: _selectedGroup?.id,
      targetGroupName: _selectedGroup?.name,
      createdAt: widget.discount?.createdAt ?? DateTime.now(),
      isActive: true,
    );

    try {
      await FirestoreService().saveDiscount(discountModel);
      DiscountService.notifyDiscountsChanged();
      ToastService().show(message: "Lưu thành công!", type: ToastType.success);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService().show(message: "Lỗi lưu: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.discount == null ? "Tạo Giảm Giá" : "Sửa Giảm Giá"),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              onPressed: _saveDiscount,
              icon: const Icon(Icons.save, color: AppTheme.primaryColor, size: 30),
              tooltip: "Lưu lại",
            ),
          ),
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
                decoration: const InputDecoration(labelText: "Tên chương trình", prefixIcon: Icon(Icons.label)),
              ),
              const SizedBox(height: 12),

              _buildSectionTitle("Thời gian áp dụng"),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(12),
                ),
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

              const SizedBox(height: 12),

              _buildSectionTitle("Đối tượng áp dụng"),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _targetType,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.people_outline),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text("Tất cả khách hàng")),
                  DropdownMenuItem(value: 'retail', child: Text("Khách vãng lai (Lẻ)")),
                  DropdownMenuItem(value: 'group', child: Text("Nhóm khách hàng")),
                ],
                onChanged: (val) {
                  setState(() {
                    _targetType = val!;
                    if (_targetType != 'group') {
                      _selectedGroup = null;
                    }
                  });
                },
              ),
              if (_targetType == 'group') ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<CustomerGroupModel>(
                  initialValue: _selectedGroup,
                  decoration: InputDecoration(
                    labelText: "Chọn nhóm",
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _availableGroups.map((g) => DropdownMenuItem(
                    value: g,
                    child: Text(g.name),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedGroup = val),
                  hint: const Text("Chọn nhóm khách hàng"),
                )
              ],

              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildSectionTitle("Sản phẩm (${_selectedItems.length})"),
                  ElevatedButton.icon(
                    onPressed: _pickProducts,
                    icon: const Icon(Icons.add),
                    label: const Text("Thêm SP"),
                  )
                ],
              ),
              const SizedBox(height: 12),

              if (_selectedItems.isNotEmpty) _buildCalculator(),
              const SizedBox(height: 16),

              if (_selectedItems.isNotEmpty)
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: _selectedItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final item = _selectedItems[index];

                    // Logic hiển thị giá sau giảm
                    double finalDisplayPrice;
                    if (item.isPercent) {
                      finalDisplayPrice = item.oldPrice * (1 - (item.value / 100));
                    } else {
                      finalDisplayPrice = item.oldPrice - item.value;
                    }
                    if (finalDisplayPrice < 0) finalDisplayPrice = 0;

                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _showEditSingleItemPrice(index),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 60, height: 60,
                                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                                      ? CachedNetworkImage(imageUrl: item.imageUrl!, fit: BoxFit.cover)
                                      : Container(color: Colors.grey.shade200, child: const Icon(Icons.image, color: Colors.grey)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const SizedBox(height: 4),
                                    Text("Giá niêm yết: ${formatNumber(item.oldPrice)}", style: const TextStyle(color: Colors.grey, fontSize: 14)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                      formatNumber(finalDisplayPrice),
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)
                                  ),
                                  if (item.value > 0)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                                      child: Text(
                                          item.isPercent
                                              ? "Giảm ${item.value.toStringAsFixed(1)}%"
                                              : "Giảm ${formatNumber(item.value)}đ",
                                          style: TextStyle(fontSize: 10, color: Colors.red.shade700)
                                      ),
                                    )
                                ],
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGETS CON ---

  Widget _buildSectionTitle(String title) {
    return Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
  }

  Widget _buildRadioTime(String label, String value) {
    final isSelected = _timeType == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _timeType = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withValues(alpha: 0.1) : Colors.transparent,
            border: Border(bottom: BorderSide(color: isSelected ? AppTheme.primaryColor : Colors.transparent, width: 2)),
          ),
          alignment: Alignment.center,
          child: Text(
              label,
              style: TextStyle(
                  color: isSelected ? AppTheme.primaryColor : Colors.grey.shade700,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, fontSize: 16
              )
          ),
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

    // Daily & Weekly Interface
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_timeType == 'weekly') ...[
          Wrap(
            spacing: 8,
            children: List.generate(7, (index) {
              final dayVal = index + 2;
              final label = index == 6 ? "CN" : "T${index + 2}";
              final isSelected = _selectedWeekDays.contains(dayVal);
              return FilterChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedWeekDays.add(dayVal);
                    } else {
                      _selectedWeekDays.remove(dayVal);
                    }
                  });
                },
                checkmarkColor: Colors.white,
                selectedColor: AppTheme.primaryColor,
                labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
              );
            }),
          ),
          const SizedBox(height: 16),
        ],

        // --- [CẬP NHẬT] DANH SÁCH CÁC KHUNG GIỜ ---
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

        TextButton.icon(
          onPressed: _addTimeRange,
          icon: const Icon(Icons.add_alarm),
          label: const Text("Thêm khung giờ"),
        ),
      ],
    );
  }

  Widget _buildTimeBox(String label, TimeOfDay time, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
        ),
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

  Widget _buildCalculator() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        children: [
          const Row(children: [Icon(Icons.calculate, size: 18, color: Colors.blue), SizedBox(width: 8), Text("Điều chỉnh nhanh", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))]),
          const SizedBox(height: 8),
          Row(
            children: [
              ToggleButtons(
                constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                isSelected: [!_isIncrease, _isIncrease],
                onPressed: (idx) => setState(() => _isIncrease = idx == 1),
                borderRadius: BorderRadius.circular(8),
                children: const [Icon(Icons.remove, size: 18, color: Colors.red), Icon(Icons.add, size: 18, color: AppTheme.primaryColor)],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _calcValueController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandDecimalInputFormatter()],
                    decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder(), hintText: "Nhập giá trị"),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ToggleButtons(
                constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
                isSelected: [_isCalcPercent, !_isCalcPercent],
                onPressed: (idx) => setState(() => _isCalcPercent = idx == 0),
                borderRadius: BorderRadius.circular(8),
                children: const [Text("%"), Text("đ")],
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _applyBulkAdjustment,
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 12)),
                child: const Icon(Icons.check, size: 18),
              )
            ],
          )
        ],
      ),
    );
  }
}