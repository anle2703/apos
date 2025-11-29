import 'package:flutter/material.dart';
import '../models/order_item_model.dart';
import '../models/user_model.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/custom_text_form_field.dart';
import '../theme/number_utils.dart';
import '../models/quick_note_model.dart';

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

  late double _initialQuantity;
  late TextEditingController _addQtyController;
  late TextEditingController _subtractQtyController;
  late TextEditingController _totalQtyController;

  @override
  void initState() {
    super.initState();

    final item = widget.initialItem;
    _priceController = TextEditingController(text: formatNumber(item.price));
    _discountValueController =
        TextEditingController(text: formatNumber(item.discountValue ?? 0));
    _noteController = TextEditingController(text: item.note ?? '');
    String rawUnit = item.discountUnit ?? '%';
    if (rawUnit == 'VND') rawUnit = 'VNĐ';
    _discountUnit = rawUnit;

    _isCommissionableService = item.product.productType == "Dịch vụ/Tính giờ" &&
        (item.product.serviceSetup?['isTimeBased'] == false);

    if (_isCommissionableService) {
      _selectedLevel1 = item.commissionStaff?['level1'];
      _selectedLevel2 = item.commissionStaff?['level2'];
      _selectedLevel3 = item.commissionStaff?['level3'];
    }

    _initialQuantity = item.quantity;
    _addQtyController = TextEditingController();
    _subtractQtyController = TextEditingController();
    _totalQtyController =
        TextEditingController(text: formatNumber(_initialQuantity));
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

  void _onConfirm() {
    final double price = parseVN(_priceController.text);
    final double discountValue = parseVN(_discountValueController.text);
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
      'note': note.isEmpty ? null : note,
      'commissionStaff': commissionStaff,
    });
  }

  // [SỬA] - Gửi bạn hàm build đã được cập nhật
  @override
  Widget build(BuildContext context) {
    final bool canEditPrice =
        widget.initialItem.product.serviceSetup?['isTimeBased'] != true;

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
            CustomTextFormField(
              controller: _priceController,
              decoration: InputDecoration(
                labelText: 'Đơn giá',
                enabled: canEditPrice,
              ),
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [ThousandDecimalInputFormatter()],
              readOnly: !canEditPrice,
            ),
            const SizedBox(height: 8),
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
                Expanded(
                  flex: 3,
                  child: CustomTextFormField(
                    controller: _discountValueController,
                    decoration: const InputDecoration(labelText: 'Chiết khấu'),
                    keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandDecimalInputFormatter()],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: AppDropdown(
                    labelText: 'Đơn vị',
                    value: _discountUnit,
                    items: ['%', 'VNĐ']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() => _discountUnit = v);
                      }
                    },
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
