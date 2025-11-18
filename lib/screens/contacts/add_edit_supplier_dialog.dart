// lib/screens/contacts/add_edit_supplier_dialog.dart

import 'package:flutter/material.dart';
import 'package:app_4cash/models/supplier_model.dart';
import 'package:app_4cash/services/supplier_service.dart';
import 'package:app_4cash/widgets/custom_text_form_field.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';
import 'package:app_4cash/services/toast_service.dart';
import '../../theme/number_utils.dart';

class AddEditSupplierDialog extends StatefulWidget {
  final SupplierModel? supplier;
  final String storeId;
  final bool returnModelOnSuccess;

  const AddEditSupplierDialog({
    super.key,
    this.supplier,
    required this.storeId,
    this.returnModelOnSuccess = false,
  });

  @override
  State<AddEditSupplierDialog> createState() => _AddEditSupplierDialogState();
}

class _AddEditSupplierDialogState extends State<AddEditSupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxCodeController = TextEditingController();
  final _supplierService = SupplierService();
  final _newGroupController = TextEditingController();
  bool _isSaving = false;
  bool get _isEditMode => widget.supplier != null;

  List<SupplierGroupModel> _supplierGroups = [];
  String? _selectedGroupId;
  bool _showNewGroupField = false;
  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadGroups();
    if (_isEditMode) {
      final s = widget.supplier!;
      _nameController.text = s.name;
      _phoneController.text = s.phone;
      _addressController.text = s.address ?? '';
      _taxCodeController.text = s.taxCode ?? '';
      _selectedGroupId = s.supplierGroupId;
    }
    if (mounted) setState(() {});
  }


  Future<void> _loadGroups() async {
    setState(() => _isLoadingGroups = true);
    try {
      _supplierGroups = await _supplierService.getSupplierGroups(widget.storeId);
    } catch (e) {
      debugPrint("Lỗi tải nhóm NCC trong dialog: $e");
      if (mounted) ToastService().show(message: "Không thể tải danh sách nhóm.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _taxCodeController.dispose();
    _newGroupController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false) || _isSaving) return;

    setState(() => _isSaving = true);

    final newName = _nameController.text.trim();
    String? excludeId;
    bool nameHasChanged = true;

    if (_isEditMode) {
      excludeId = widget.supplier!.id;
      if (newName.toLowerCase() == widget.supplier!.name.toLowerCase()) {
        nameHasChanged = false;
      }
    }

    if (nameHasChanged) {
      try {
        final bool isDuplicate = await _supplierService.checkSupplierNameExists(
          newName,
          widget.storeId,
          excludeId: excludeId,
        );

        if (isDuplicate) {
          if (mounted) {
            ToastService().show(
              message: 'Tên nhà cung cấp "$newName" đã tồn tại.',
              type: ToastType.warning,
            );
          }
          setState(() => _isSaving = false);
          return;
        }
      } catch (e) {
        if (mounted) {
          ToastService().show(message: 'Lỗi khi kiểm tra tên: $e', type: ToastType.error);
        }
        setState(() => _isSaving = false);
        return;
      }
    }

    String? finalGroupId = _selectedGroupId;
    String? finalGroupName;
    bool needsGroupRefresh = false;

    if (_showNewGroupField) {
      final newGroupName = _newGroupController.text.trim();
      if (newGroupName.isEmpty) {
        ToastService().show(message: 'Vui lòng nhập tên nhóm mới.', type: ToastType.warning);
        setState(() => _isSaving = false); 
        return;
      }
      final isDuplicate = _supplierGroups.any(
              (group) => group.name.toLowerCase() == newGroupName.toLowerCase()
      );
      if (isDuplicate) {
        ToastService().show(
          message: 'Tên nhóm "$newGroupName" đã tồn tại.',
          type: ToastType.warning,
        );
        setState(() => _isSaving = false);
        return;
      }
      try {
        finalGroupId = await _supplierService.addSupplierGroup(newGroupName, widget.storeId);
        finalGroupName = newGroupName;
        needsGroupRefresh = true;
      } catch (e) {
        ToastService().show(message: 'Lỗi khi thêm nhóm mới: $e', type: ToastType.error);
        setState(() => _isSaving = false);
        return;
      }
    } else if (finalGroupId != null) {
      finalGroupName = _supplierGroups.firstWhere((g) => g.id == finalGroupId).name;
    }

    try {
      final data = {
        'name': capitalizeWords(newName),
        'phone': _phoneController.text.trim(),
        'address': capitalizeWords(_addressController.text.trim()),
        'taxCode': _taxCodeController.text.trim().toUpperCase(),
        'storeId': widget.storeId,
        'supplierGroupId': finalGroupId,
        'supplierGroupName': finalGroupName,
      };

      if (widget.supplier == null) {
        final SupplierModel newSupplier = await _supplierService.addSupplier(data);
        if (mounted) {
          if (widget.returnModelOnSuccess) {
            Navigator.of(context).pop(newSupplier);
          } else {
            Navigator.of(context).pop(true);
          }
        }
      } else {
        if (!needsGroupRefresh && widget.supplier!.supplierGroupId != finalGroupId) {
          needsGroupRefresh = true;
        }

        await _supplierService.updateSupplier(widget.supplier!.id, data);

        SupplierModel? updatedSupplier;
        if (widget.returnModelOnSuccess) {
          updatedSupplier = await _supplierService.getSupplierById(widget.supplier!.id);
        }

        if (mounted) {
          if (widget.returnModelOnSuccess) {
            Navigator.of(context).pop(updatedSupplier);
          } else {
            Navigator.of(context).pop(needsGroupRefresh);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ToastService().show(message: 'Lỗi: $e', type: ToastType.error);
      }
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const spacing = SizedBox(height: 16);

    final List<DropdownMenuItem<String>> groupDropdownItems = _isLoadingGroups
        ? [const DropdownMenuItem(value: null, child: Text('Đang tải...'))]
        : _supplierGroups.map((group) => DropdownMenuItem(value: group.id, child: Text(group.name))).toList();

    groupDropdownItems.add(const DropdownMenuItem(
      value: '_new_',
      child: Text('Tạo nhóm mới...'),
    ));

    return AlertDialog(
      title: Text(widget.supplier == null ? 'Thêm NCC mới' : 'Sửa thông tin'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isLoadingGroups)
                  const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
                else
                  AppDropdown<String>(
                    labelText: 'Nhóm NCC',
                    prefixIcon: Icons.groups_outlined,
                    value: _selectedGroupId,
                    items: groupDropdownItems,
                    onChanged: (String? newValue) {
                      setState(() {
                        if (newValue == '_new_') {
                          _showNewGroupField = true;
                          _selectedGroupId = null;
                        } else {
                          _showNewGroupField = false;
                          _selectedGroupId = newValue;
                        }
                      });
                    },
                  ),
                if (_showNewGroupField) ...[
                  spacing,
                  CustomTextFormField(
                    controller: _newGroupController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Tên nhóm mới (*)',
                      prefixIcon: Icon(Icons.add_circle_outline),
                    ),
                    validator: (value) => (value == null || value.trim().isEmpty) ? 'Vui lòng nhập tên nhóm' : null,
                  ),
                ],
                spacing,
                CustomTextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên nhà cung cấp (*)',
                    prefixIcon: Icon(Icons.store_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Tên không được bỏ trống' : null,
                ),
                spacing,
                CustomTextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại (*)',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'SĐT không được bỏ trống' : null,
                ),
                spacing,
                CustomTextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                spacing,
                CustomTextFormField(
                  controller: _taxCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Mã số thuế',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
            child: const Text('Huỷ')
        ),
        ElevatedButton(
          onPressed: _save,
          child: _isSaving
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Lưu'),
        ),
      ],
    );
  }
}