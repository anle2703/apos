import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/customer_model.dart';
import '../../widgets/app_dropdown.dart';
import '../../models/customer_group_model.dart';

class AddEditCustomerDialog extends StatefulWidget {
  final FirestoreService firestoreService;
  final String storeId;
  final CustomerModel? customer;
  final String? initialName;
  final String? initialPhone;
  final String? initialAddress;
  final bool isPhoneReadOnly;

  const AddEditCustomerDialog({
    super.key,
    required this.firestoreService,
    required this.storeId,
    this.customer,
    this.initialName,
    this.initialPhone,
    this.initialAddress,
    this.isPhoneReadOnly = false,
  });

  @override
  State<AddEditCustomerDialog> createState() => _AddEditCustomerDialogState();
}

class _AddEditCustomerDialogState extends State<AddEditCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _citizenIdController = TextEditingController();
  final _addressController = TextEditingController();
  final _companyNameController = TextEditingController();
  final _taxIdController = TextEditingController();
  final _companyAddressController = TextEditingController();
  bool _isSaving = false;
  bool get _isEditMode => widget.customer != null;
  final _newGroupController = TextEditingController();
  List<CustomerGroupModel> _customerGroups = [];
  String? _selectedGroupId;
  bool _showNewGroupField = false;
  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    await _loadCustomerGroups();
    if (_isEditMode) {
      final c = widget.customer!;
      _nameController.text = c.name;
      _phoneController.text = c.phone;
      _emailController.text = c.email ?? '';
      _citizenIdController.text = c.citizenId ?? '';
      _addressController.text = c.address ?? '';
      _companyNameController.text = c.companyName ?? '';
      _taxIdController.text = c.taxId ?? '';
      _companyAddressController.text = c.companyAddress ?? '';
      _selectedGroupId = c.customerGroupId;
    } else {
      _nameController.text = widget.initialName ?? '';
      _phoneController.text = widget.initialPhone ?? '';
      _addressController.text = widget.initialAddress ?? '';
    }
    if (mounted) {setState(() {});}
  }

  Future<void> _loadCustomerGroups() async {
    setState(() => _isLoadingGroups = true);
    try {
      _customerGroups = await widget.firestoreService.getCustomerGroups(widget.storeId);
    } catch (e) {
      debugPrint("Lỗi tải nhóm: $e");
      if (mounted) ToastService().show(message: "Không thể tải danh sách nhóm.", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _citizenIdController.dispose();
    _addressController.dispose();
    _companyNameController.dispose();
    _taxIdController.dispose();
    _companyAddressController.dispose();
    super.dispose();
  }

  List<String> _generateSearchKeys(String name, String phone) {
    final List<String> keys = [];

    if (name.isNotEmpty) {
      final nameLower = name.toLowerCase();
      final words = nameLower.split(' ').where((word) => word.isNotEmpty);
      keys.addAll(words);
    }

    if (phone.isNotEmpty) {
      keys.add(phone);
      if (phone.length >= 3) {
        keys.add(phone.substring(phone.length - 3));
      }
    }

    return keys.toSet().toList();
  }

  Future<void> _saveForm() async {
    if (!_formKey.currentState!.validate() || _isSaving) return;
    if (_showNewGroupField) {
      final newGroupName = _newGroupController.text.trim();
      if (newGroupName.isEmpty) {
        ToastService().show(message: 'Vui lòng nhập tên nhóm mới.', type: ToastType.warning);
        return;
      }
      final isDuplicate = _customerGroups.any(
              (group) => group.name.toLowerCase() == newGroupName.toLowerCase()
      );
      if (isDuplicate) {
        ToastService().show(
          message: 'Tên nhóm "$newGroupName" đã tồn tại. Vui lòng chọn tên khác.',
          type: ToastType.warning,
        );
        return;
      }
    }

    setState(() => _isSaving = true);

    try {
      final String phone = _phoneController.text.trim();
      if (!_isEditMode || (_isEditMode && phone != widget.customer!.phone)) {
        final isDuplicate = await widget.firestoreService.isCustomerPhoneDuplicate(
          phone: phone, storeId: widget.storeId,
        );
        if (isDuplicate) {
          ToastService().show(message: 'Số điện thoại này đã tồn tại.', type: ToastType.warning);
          setState(() => _isSaving = false);
          return;
        }
      }

      String? customerGroupId = _selectedGroupId;
      String? customerGroupName;

      if (_showNewGroupField) {
        final newGroupName = _newGroupController.text.trim();
        customerGroupId = await widget.firestoreService.addCustomerGroup(newGroupName, widget.storeId);
        customerGroupName = newGroupName;
      } else if (customerGroupId != null) {
        customerGroupName = _customerGroups.firstWhere((g) => g.id == customerGroupId).name;
      }

      final customerData = {
        'name': _nameController.text.trim(),
        'phone': phone,
        'email': _emailController.text.trim(),
        'citizenId': _citizenIdController.text.trim(),
        'address': _addressController.text.trim(),
        'companyName': _companyNameController.text.trim(),
        'taxId': _taxIdController.text.trim(),
        'companyAddress': _companyAddressController.text.trim(),
        'searchKeys': _generateSearchKeys(_nameController.text.trim(), phone),
        'customerGroupId': customerGroupId,
        'customerGroupName': customerGroupName,
        'storeId': widget.storeId,
        'points': _isEditMode ? widget.customer!.points : 0,
        'debt': _isEditMode ? widget.customer!.debt : 0.0,
        'totalSpent': _isEditMode ? widget.customer!.totalSpent : 0.0,
      };

      if (_isEditMode) {
        await widget.firestoreService.updateCustomer(widget.customer!.id, customerData);

        final fullData = Map<String, dynamic>.from(customerData);
        fullData['id'] = widget.customer!.id;

        final updatedCustomer = CustomerModel.fromMap(fullData);
        if (mounted) Navigator.of(context).pop(updatedCustomer);
      } else {
        final newCustomer = await widget.firestoreService.addCustomer(customerData);
        if (mounted) Navigator.of(context).pop(newCustomer);
      }

    } catch (e) {
      ToastService().show(message: 'Lỗi: ${e.toString()}', type: ToastType.error);
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const spacing = SizedBox(height: 8);
    final List<DropdownMenuItem<String>> dropdownItems = _customerGroups
        .map((group) => DropdownMenuItem(value: group.id, child: Text(group.name)))
        .toList();
    dropdownItems.add(const DropdownMenuItem(
      value: '_new_',
      child: Text('Tạo nhóm mới...'),
    ));

    return AlertDialog(
      title: const Text('Thông tin Khách hàng'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Khách hàng cá nhân:', style: textTheme.titleMedium?.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.black12),
                spacing,
                if (_isLoadingGroups)
                  const Center(child: CircularProgressIndicator())
                else
                  AppDropdown<String>(
                    labelText: 'Nhóm khách hàng',
                    prefixIcon: Icons.groups_outlined,
                    value: _selectedGroupId,
                    items: dropdownItems,
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
                      labelText: 'Tên nhóm mới',
                      prefixIcon: Icon(Icons.add_circle_outline),
                    ),
                  ),
                ],
                spacing,
                CustomTextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên Khách hàng (*)',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) =>
                  value!.isEmpty ? 'Vui lòng nhập tên' : null,
                ),
                spacing,
                CustomTextFormField(
                  controller: _phoneController,
                  readOnly: widget.isPhoneReadOnly,
                  decoration: InputDecoration(
                    labelText: 'Số điện thoại (*)',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    filled: widget.isPhoneReadOnly,
                    fillColor: widget.isPhoneReadOnly ? Colors.grey[200] : null,
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Vui lòng nhập số điện thoại';
                    }
                    if (value.length != 10) {
                      return 'Số điện thoại phải có 10 chữ số.';
                    }
                    if (!value.startsWith('0')) {
                      return 'Số điện thoại phải bắt đầu bằng số 0.';
                    }
                    return null;
                  },
                ),
                spacing,
                CustomTextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email (xuất HĐĐT)',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return null;
                    }
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) {
                      return 'Email không hợp lệ.';
                    }
                    return null;
                  },
                ),
                spacing,
                CustomTextFormField(
                  controller: _citizenIdController,
                  decoration: const InputDecoration(
                    labelText: 'CCCD',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                spacing,
                CustomTextFormField(
                  controller: _addressController,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ cá nhân',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Khách hàng doanh nghiệp:', style: textTheme.titleMedium?.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
                const Divider(color: Colors.black12),
                spacing,
                CustomTextFormField(
                  controller: _companyNameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên công ty',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                ),
                spacing,
                CustomTextFormField(
                  controller: _taxIdController,
                  decoration: const InputDecoration(
                    labelText: 'Mã số thuế',
                    prefixIcon: Icon(Icons.receipt_long_outlined),
                  ),
                ),
                spacing,
                CustomTextFormField(
                  controller: _companyAddressController,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ công ty',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(null),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: _saveForm,
          child: _isSaving
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          )
              : const Text('Lưu'),
        ),
      ],
    );
  }
}