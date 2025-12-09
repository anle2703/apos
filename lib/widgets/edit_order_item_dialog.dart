import 'package:flutter/material.dart';
import '../models/order_item_model.dart';
import '../models/user_model.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/custom_text_form_field.dart';
import '../theme/number_utils.dart';
import '../models/quick_note_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:omni_datetime_picker/omni_datetime_picker.dart';
import '../theme/app_theme.dart';

class EditOrderItemDialog extends StatefulWidget {
  final OrderItem initialItem;
  final List<UserModel> staffList;
  final bool isLoadingStaff;
  final List<QuickNoteModel> relevantQuickNotes;

  const EditOrderItemDialog({
    super.key,
    required this.initialItem,
    required this.staffList,
    required this.isLoadingStaff,
    this.relevantQuickNotes = const [],
  });

  @override
  State<EditOrderItemDialog> createState() => _EditOrderItemDialogState();
}

class _EditOrderItemDialogState extends State<EditOrderItemDialog> {
  late TextEditingController _priceController;
  late TextEditingController _discountValueController;
  late TextEditingController _noteController;
  late String _discountUnit;
  bool _isCommissionableService = false;
  String? _selectedLevel1;
  String? _selectedLevel2;
  String? _selectedLevel3;
  late String _selectedUnit;
  late List<Map<String, dynamic>> _availableUnits;

  late double _initialQuantity;
  late TextEditingController _addQtyController;
  late TextEditingController _subtractQtyController;
  late TextEditingController _totalQtyController;
  DateTime _startTime = DateTime.now();
  bool _isTimeBased = false;
  bool _isIncrease = false;

  @override
  void initState() {
    super.initState();
    final item = widget.initialItem;
    _availableUnits = [
      {'unitName': item.product.unit ?? 'Cơ bản', 'sellPrice': item.product.sellPrice}
    ];
    if (item.product.additionalUnits.isNotEmpty) {
      _availableUnits.addAll(item.product.additionalUnits);
    }
    _selectedUnit = item.selectedUnit.isNotEmpty ? item.selectedUnit : (item.product.unit ?? '');
    if (!_availableUnits.any((u) => u['unitName'] == _selectedUnit) && _availableUnits.isNotEmpty) {
      _selectedUnit = _availableUnits.first['unitName'];
    }
    _priceController = TextEditingController(text: formatNumber(item.price));
    double currentDiscount = item.discountValue ?? 0;
    if (currentDiscount < 0) {
      _isIncrease = true;
      currentDiscount = currentDiscount.abs();
    } else {
      _isIncrease = false;
    }
    _discountValueController = TextEditingController(text: formatNumber(currentDiscount));
    _noteController = TextEditingController(text: item.note ?? '');
    String rawUnit = item.discountUnit ?? '%';
    if (rawUnit == 'VND') rawUnit = 'VNĐ';
    _discountUnit = rawUnit;

    _isTimeBased = item.product.serviceSetup?['isTimeBased'] == true;
    _isCommissionableService = item.product.productType == "Dịch vụ/Tính giờ" && !_isTimeBased;

    if (_isTimeBased) {
      _startTime = item.addedAt.toDate();
    }

    if (_isCommissionableService) {
      _selectedLevel1 = item.commissionStaff?['level1'];
      _selectedLevel2 = item.commissionStaff?['level2'];
      _selectedLevel3 = item.commissionStaff?['level3'];
    }

    _initialQuantity = item.quantity;
    _addQtyController = TextEditingController();
    _subtractQtyController = TextEditingController();
    _totalQtyController = TextEditingController(text: formatNumber(_initialQuantity));
  }

  @override
  void dispose() {
    _priceController.dispose();
    _discountValueController.dispose();
    _noteController.dispose();
    _addQtyController.dispose();
    _subtractQtyController.dispose();
    _totalQtyController.dispose();
    super.dispose();
  }

  void _onUnitChanged(String? newUnit) {
    if (newUnit == null || newUnit == _selectedUnit) return;

    // Tìm giá của đơn vị mới
    final unitData = _availableUnits.firstWhere(
          (u) => u['unitName'] == newUnit,
      orElse: () => _availableUnits.first,
    );
    final double newPrice = (unitData['sellPrice'] as num).toDouble();

    setState(() {
      _selectedUnit = newUnit;
      _priceController.text = formatNumber(newPrice);
    });
  }

  void _onConfirm() {
    final double price = parseVN(_priceController.text);
    double rawDiscountVal = parseVN(_discountValueController.text);
    final double discountValue = _isIncrease ? -rawDiscountVal : rawDiscountVal;
    final String note = _noteController.text.trim();
    double newQuantity = _initialQuantity;
    final double totalQty = parseVN(_totalQtyController.text);
    final double addQty = parseVN(_addQtyController.text);
    final double subtractQty = parseVN(_subtractQtyController.text);

    if (_totalQtyController.text.isNotEmpty && totalQty != _initialQuantity) {
      newQuantity = totalQty;
    } else if (_addQtyController.text.isNotEmpty && addQty > 0) {
      newQuantity += addQty;
    } else if (_subtractQtyController.text.isNotEmpty && subtractQty > 0) {
      newQuantity -= subtractQty;
    }

    if (newQuantity < 0) newQuantity = 0;

    final Map<String, String?> commissionStaff = {};
    if (_isCommissionableService) {
      commissionStaff['level1'] = _selectedLevel1;
      commissionStaff['level2'] = _selectedLevel2;
      commissionStaff['level3'] = _selectedLevel3;
    }

    Navigator.of(context).pop({
      'price': price,
      'quantity': newQuantity,
      'discountValue': discountValue,
      'discountUnit': _discountUnit,
      'selectedUnit': _selectedUnit,
      'note': note.isEmpty ? null : note,
      'commissionStaff': commissionStaff,
      'startTime': _isTimeBased ? Timestamp.fromDate(_startTime) : null,
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      // 1. Thêm scrollable: true de AlertDialg tu quan ly cuon
      //    Title va Content se cuon cung nhau
      scrollable: true,
      title: Text(widget.initialItem.product.productName,
          textAlign: TextAlign.center),

      // 3. Thu nho padding cho khu vuc nut bam
      actionsPadding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 16.0),

      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, minWidth: 400),
        // 2. Xoa SingleChildScrollView o day
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isTimeBased) ...[
              Text('Giờ vào:',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final DateTime? picked = await showOmniDateTimePicker(
                    context: context,
                    initialDate: _startTime,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 1)),
                    is24HourMode: true,
                    isShowSeconds: false,
                    minutesInterval: 1,
                    borderRadius: const BorderRadius.all(Radius.circular(16)),
                  );
                  if (picked != null) {
                    setState(() => _startTime = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.access_time, color: AppTheme.primaryColor),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('HH:mm dd/MM/yyyy').format(_startTime),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Icon(Icons.edit, size: 18, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_availableUnits.length > 1) ...[
              AppDropdown<String>(
                labelText: 'Đơn vị tính',
                value: _selectedUnit,
                items: _availableUnits.map((u) {
                  return DropdownMenuItem<String>(
                    value: u['unitName'] as String,
                    child: Text(u['unitName'] as String),
                  );
                }).toList(),
                onChanged: _onUnitChanged,
              ),
              const SizedBox(height: 12),
            ],
            if (widget.initialItem.product.serviceSetup?['isTimeBased'] != true) ...[
              CustomTextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Đơn giá',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandDecimalInputFormatter()],
              ),
              const SizedBox(height: 8),
            ],
            if (widget.initialItem.product.serviceSetup?['isTimeBased'] !=
                true) ...[
              Text('Chỉnh sửa số lượng',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: CustomTextFormField(
                      controller: _addQtyController,
                      decoration:
                      const InputDecoration(labelText: 'SL tăng (+)'),
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandDecimalInputFormatter()],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CustomTextFormField(
                      controller: _subtractQtyController,
                      decoration:
                      const InputDecoration(labelText: 'SL giảm (-)'),
                      keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandDecimalInputFormatter()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              CustomTextFormField(
                controller: _totalQtyController,
                decoration: const InputDecoration(labelText: 'SL tổng (=)'),
                keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [ThousandDecimalInputFormatter()],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Cụm nút Tăng/Giảm (Custom Container)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  height: 48, // Chiều cao cố định khớp với Input
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12), // Bo góc 12 theo yêu cầu
                    border: Border.all(color: Colors.grey.shade400), // Viền xám mờ
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // NÚT TRỪ (-)
                      InkWell(
                        onTap: () => setState(() => _isIncrease = false),
                        borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                        child: Container(
                          width: 45, // Độ rộng nút
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Nếu đang chọn Giảm (False) thì hiện nền đỏ nhạt
                            color: !_isIncrease ? Colors.red.shade50 : null,
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          ),
                          child: Icon(
                              Icons.remove,
                              color: !_isIncrease ? Colors.red : Colors.grey.shade600
                          ),
                        ),
                      ),

                      // ĐƯỜNG KẺ ĐỨNG NGĂN CÁCH MỜ
                      Container(
                        width: 1,
                        height: 45, // Chiều cao ngắn hơn container để tạo cảm giác thanh thoát
                        color: Colors.grey.shade300,
                      ),

                      // NÚT CỘNG (+)
                      InkWell(
                        onTap: () => setState(() => _isIncrease = true),
                        borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                        child: Container(
                          width: 45, // Độ rộng nút
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Nếu đang chọn Tăng (True) thì hiện nền xanh nhạt
                            color: _isIncrease ? AppTheme.primaryColor.withValues(alpha: 0.1) : null,
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          ),
                          child: Icon(
                              Icons.add,
                              color: _isIncrease ? AppTheme.primaryColor : Colors.grey.shade600
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 2. Ô nhập giá trị (Input)
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 48, // Ép chiều cao khớp với nút bên cạnh
                    child: CustomTextFormField(
                      controller: _discountValueController,
                      decoration: InputDecoration(
                        labelText: _isIncrease ? 'Mức Tăng' : 'Mức Giảm',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        // Đảm bảo Input cũng bo góc 12
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade400),
                        ),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [ThousandDecimalInputFormatter()],
                    ),
                  ),
                ),

                // 3. Chọn đơn vị
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48, // Ép chiều cao khớp
                    child: AppDropdown(
                      labelText: 'Đơn vị',
                      value: _discountUnit,
                      items: ['%', 'VNĐ'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _discountUnit = v);
                      },
                      // Lưu ý: Bạn cần kiểm tra AppDropdown có hỗ trợ borderRadius không.
                      // Nếu AppDropdown dùng InputDecoration mặc định của Theme thì nó sẽ tự bo theo theme.
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            CustomTextFormField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: 'Ghi chú'),
              maxLines: 1,
            ),
            _buildQuickNotesList(),
            if (_isCommissionableService) ...[
              const SizedBox(height: 8),
              Text('Hoa hồng nhân viên:',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (widget.isLoadingStaff)
                const Center(child: CircularProgressIndicator())
              else if (widget.staffList.isEmpty)
                const Text('Không tìm thấy danh sách nhân viên.')
              else ...[
                  _buildStaffDropdown(
                    'Nhân viên cấp 1',
                    _selectedLevel1,
                        (val) => setState(() => _selectedLevel1 = val),
                  ),
                  const SizedBox(height: 8),
                  _buildStaffDropdown(
                    'Nhân viên cấp 2',
                    _selectedLevel2,
                        (val) => setState(() => _selectedLevel2 = val),
                  ),
                  const SizedBox(height: 8),
                  _buildStaffDropdown(
                    'Nhân viên cấp 3',
                    _selectedLevel3,
                        (val) => setState(() => _selectedLevel3 = val),
                  ),
                ]
            ]
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _onConfirm,
          child: const Text('Xác nhận'),
        ),
      ],
    );
  }

  Widget _buildQuickNotesList() {
    if (widget.relevantQuickNotes.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ghi chú nhanh:',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: widget.relevantQuickNotes.map((note) {
              return InputChip(
                label: Text(note.noteText),
                onPressed: () {
                  final currentText = _noteController.text.trim();
                  if (currentText.isEmpty) {
                    _noteController.text = note.noteText;
                  } else {
                    _noteController.text = '$currentText, ${note.noteText}';
                  }
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffDropdown(
    String label,
    String? selectedStaffId,
    ValueChanged<String?> onChanged,
  ) {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: null,
        child: Text('Chưa chọn'),
      ),
      ...widget.staffList.map((staff) {
        return DropdownMenuItem<String>(
          value: staff.uid,
          child: Text(staff.name ?? staff.email ?? 'N/A'),
        );
      }),
    ];

    final validSelectedId =
        widget.staffList.any((staff) => staff.uid == selectedStaffId)
            ? selectedStaffId
            : null;

    return AppDropdown(
      labelText: label,
      value: validSelectedId,
      items: items,
      onChanged: onChanged,
    );
  }
}
