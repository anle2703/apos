// File: lib/screens/tables/add_edit_table_screen.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/product_model.dart';
import '../../models/table_group_model.dart';
import '../../models/table_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/custom_text_form_field.dart';

class AddEditTableScreen extends StatefulWidget {
  final UserModel currentUser;
  final TableModel? tableToEdit;
  final List<TableGroupModel> tableGroups;

  const AddEditTableScreen({
    super.key,
    required this.currentUser,
    this.tableToEdit,
    required this.tableGroups,
  });

  @override
  State<AddEditTableScreen> createState() => _AddEditTableScreenState();
}

class _AddEditTableScreenState extends State<AddEditTableScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  final _nameOrKeywordController = TextEditingController();
  // SỬA 1: Controller này giờ chỉ dùng cho Số lượng hoặc STT (khi sửa)
  final _quantityOrSttController = TextEditingController();

  late List<TableGroupModel> _currentTableGroups;
  String? _selectedTableGroup;
  String? _selectedServiceId;
  List<ProductModel> _timeBasedServices = [];
  bool _isLoadingServices = true;
  bool _isSaving = false;
  bool _isBulkCreateMode = false;
  bool get _isEditMode => widget.tableToEdit != null;

  @override
  void initState() {
    super.initState();
    _currentTableGroups = widget.tableGroups;
    _fetchTimeBasedServices();

    if (_isEditMode) {
      final table = widget.tableToEdit!;
      _nameOrKeywordController.text = table.tableName;
      _quantityOrSttController.text = table.stt.toString();

      final validGroupNames = _currentTableGroups.map((g) => g.name).toSet();

      if (table.tableGroup.isNotEmpty && validGroupNames.contains(table.tableGroup)) {
        _selectedTableGroup = table.tableGroup;
      } else {
        _selectedTableGroup = null;
      }

      _selectedServiceId = table.serviceId;
    }
  }

  @override
  void dispose() {
    _nameOrKeywordController.dispose();
    _quantityOrSttController.dispose();
    super.dispose();
  }

  Future<void> _fetchTimeBasedServices() async {
    try {
      final services = await _firestoreService.getTimeBasedServices(widget.currentUser.storeId);

      if (_isEditMode) {
        final serviceIds = services.map((s) => s.id).toSet();
        if (_selectedServiceId != null && !serviceIds.contains(_selectedServiceId)) {
          _selectedServiceId = null;
        }
      }

      if (mounted) {
        setState(() {
          _timeBasedServices = services;
          _isLoadingServices = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingServices = false);
        ToastService().show(message: "Lỗi tải dịch vụ: $e", type: ToastType.error);
      }
    }
  }

  Future<void> _refreshGroups() async {
    final groups = await _firestoreService.getTableGroups(widget.currentUser.storeId, forceRefresh: true);
    if (mounted) {
      setState(() {
        _currentTableGroups = groups;
      });
    }
  }

  Future<void> _showAddGroupDialog() async {
    final newGroupController = TextEditingController();
    final navigator = Navigator.of(context);
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm nhóm mới'),
        // --- SỬA LỖI TẠI ĐÂY ---
        // Bao bọc bởi SingleChildScrollView để tránh lỗi tràn khi bàn phím hiện
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min, // Quan trọng: Chỉ lấy chiều cao vừa đủ nội dung
            children: [
              CustomTextFormField(
                controller: newGroupController,
                decoration: const InputDecoration(labelText: 'Tên nhóm'),
                autofocus: true,
              ),
            ],
          ),
        ),
        // -----------------------
        actions: [
          TextButton(onPressed: () => navigator.pop(), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final newGroup = newGroupController.text.trim();
              if (newGroup.isNotEmpty) {
                try {
                  await _firestoreService.addTableGroup(newGroup, widget.currentUser.storeId);
                  await _refreshGroups();
                  if (!mounted) return;
                  setState(() => _selectedTableGroup = newGroup);
                  navigator.pop();
                } catch (e) {
                  ToastService().show(message: "Thêm nhóm thất bại: $e", type: ToastType.error);
                }
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      if (_isBulkCreateMode && !_isEditMode) {
        await _saveBulkTables();
      } else {
        await _saveSingleTable();
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      ToastService().show(message: 'Thao tác thất bại: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveSingleTable() async {
    // SỬA: Gọi hàm mới để tìm STT lớn nhất tổng thể
    final sttValue = _isEditMode
        ? int.tryParse(_quantityOrSttController.text) ?? 0
        : (await _firestoreService.findHighestTableSTT(widget.currentUser.storeId) + 1);

    final tableData = {
      'tableName': _nameOrKeywordController.text.trim(),
      'tableGroup': _selectedTableGroup,
      'stt': sttValue,
      'serviceId': _selectedServiceId,
      'storeId': widget.currentUser.storeId,
    };

    if (_isEditMode) {
      await _firestoreService.updateTable(widget.tableToEdit!.id, tableData);
      ToastService().show(message: 'Cập nhật thành công!', type: ToastType.success);
    } else {
      await _firestoreService.addTable(tableData);
      ToastService().show(message: 'Thêm mới thành công!', type: ToastType.success);
    }
  }

  Future<void> _saveBulkTables() async {
    final keyword = _nameOrKeywordController.text.trim();
    final quantity = int.tryParse(_quantityOrSttController.text) ?? 0;

    if (quantity <= 0) {
      throw Exception("Số lượng phải lớn hơn 0.");
    }

    // BƯỚC 1: Tìm STT lớn nhất TOÀN HỆ THỐNG để gán tuần tự
    final highestSTT = await _firestoreService.findHighestTableSTT(widget.currentUser.storeId);

    // BƯỚC 2: Tìm số lớn nhất THEO TÊN (keyword) để đặt tên nối tiếp
    final highestTableNameNumber = await _firestoreService.findHighestTableNumber(widget.currentUser.storeId, keyword);

    final batch = FirebaseFirestore.instance.batch();

    for (int i = 0; i < quantity; i++) {
      // Tên bàn sẽ bắt đầu từ số lớn nhất của tên + 1
      final currentTableNumber = highestTableNameNumber + 1 + i;
      // STT sẽ bắt đầu từ STT lớn nhất hệ thống + 1
      final currentSTT = highestSTT + 1 + i;

      final docRef = FirebaseFirestore.instance.collection('tables').doc();
      final tableData = {
        // Tên bàn là "Bàn 6", "Bàn 7"...
        'tableName': '$keyword $currentTableNumber',
        'tableGroup': _selectedTableGroup,
        // STT là 9, 10...
        'stt': currentSTT,
        'serviceId': null,
        'storeId': widget.currentUser.storeId,
      };
      batch.set(docRef, tableData);
    }

    await batch.commit();
    ToastService().show(message: 'Đã tạo hàng loạt $quantity phòng/bàn!', type: ToastType.success);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditMode ? 'Chỉnh sửa Phòng/Bàn' : 'Thêm mới Phòng/Bàn'),
        actions: [
          if (_isEditMode)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _confirmDeleteTable,
              tooltip: 'Xóa phòng bàn',
            ),
          _isSaving
              ? const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator()))
              : IconButton(
            icon: const Icon(Icons.save, color: Color(0xFF02D0C1)),
            onPressed: _save,
            tooltip: 'Lưu',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_isEditMode)
                SwitchListTile(
                  title: const Text('Tạo hàng loạt'),
                  value: _isBulkCreateMode,
                  onChanged: (value) {
                    setState(() {
                      _isBulkCreateMode = value;
                    });
                  },
                ),

              const SizedBox(height: 16),

              LayoutBuilder(
                builder: (context, constraints) {
                  bool isDesktop = constraints.maxWidth >= 800;
                  return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteTable() async {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    try {
      final isOccupied = await _firestoreService.isTableOccupied(
        widget.tableToEdit!.id,
        widget.currentUser.storeId,
      );
      if (!mounted) return;

      if (isOccupied) {
        ToastService().show(
          message: 'Không thể xóa bàn đang có khách.',
          type: ToastType.warning,
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ToastService().show(
        message: 'Lỗi kiểm tra trạng thái bàn: $e',
        type: ToastType.error,
      );
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Xác nhận xóa'),
          content: Text('Bạn có chắc muốn xóa phòng/bàn "${widget.tableToEdit?.tableName}" không?'),
          actions: <Widget>[
            TextButton(
              child: const Text('Hủy'),
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
            ),
            TextButton(
              child: const Text('Xóa', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                try {
                  await _firestoreService.deleteTable(widget.tableToEdit!.id);
                  if (!mounted) return;
                  ToastService().show(
                    message: 'Xóa thành công!',
                    type: ToastType.success,
                  );
                  navigator.pop();
                  navigator.pop(true);
                } catch(e) {
                  if (!mounted) return;
                  ToastService().show(
                    message: 'Lỗi khi xóa: $e',
                    type: ToastType.success,
                  );
                  navigator.pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildNameField() {
    return CustomTextFormField(
      controller: _nameOrKeywordController,
      decoration: InputDecoration(
        labelText: _isBulkCreateMode && !_isEditMode ? 'Từ khóa bắt đầu (VD: Bàn)' : 'Tên phòng/bàn',
        prefixIcon: const Icon(Icons.abc),
      ),
      validator: (value) => value!.isEmpty ? 'Không được để trống' : null,
    );
  }

  Widget _buildGroupDropdown() {
    // 1. Lọc trùng lặp: Chỉ lấy các tên nhóm duy nhất
    // Sử dụng Set để đảm bảo không có 2 tên nhóm giống nhau
    final Set<String> uniqueGroupNames = {};
    final List<DropdownMenuItem<String>> dropdownItems = [];

    for (var group in _currentTableGroups) {
      // Chỉ thêm vào list hiển thị nếu tên này chưa từng xuất hiện
      if (!uniqueGroupNames.contains(group.name)) {
        uniqueGroupNames.add(group.name);
        dropdownItems.add(
          DropdownMenuItem(
            value: group.name,
            child: Text(group.name),
          ),
        );
      }
    }

    // 2. Thêm mục "Thêm nhóm mới" vào cuối
    dropdownItems.add(
      const DropdownMenuItem(
        value: 'add_new',
        child: Text(
          '+ Thêm nhóm mới...',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    );

    // 3. Kiểm tra an toàn: Nếu _selectedTableGroup đang chọn một giá trị
    // mà giá trị đó không còn nằm trong list (do vừa bị xóa hoặc lọc), reset về null
    // để tránh lỗi "There should be exactly one item..."
    String? safeSelectedValue = _selectedTableGroup;
    if (safeSelectedValue != null &&
        safeSelectedValue != 'add_new' &&
        !uniqueGroupNames.contains(safeSelectedValue)) {
      safeSelectedValue = null;
    }

    return AppDropdown(
      value: safeSelectedValue,
      labelText: 'Nhóm phòng/bàn',
      prefixIcon: Icons.folder_open_outlined,
      items: dropdownItems,
      onChanged: (value) {
        if (value == 'add_new') {
          _showAddGroupDialog();
        } else {
          setState(() => _selectedTableGroup = value);
        }
      },
    );
  }

  Widget _buildSttFieldForEdit() {
    return CustomTextFormField(
      controller: _quantityOrSttController,
      decoration: const InputDecoration(
        labelText: 'Số thứ tự',
        prefixIcon: Icon(Icons.format_list_numbered),
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (value) => value!.isEmpty ? 'Không được để trống' : null,
    );
  }

  Widget _buildServiceOrQuantityField() {
    if (_isBulkCreateMode && !_isEditMode) {
      return CustomTextFormField(
        controller: _quantityOrSttController,
        decoration: const InputDecoration(
          labelText: 'Số lượng',
          prefixIcon: Icon(Icons.production_quantity_limits),
        ),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (value) => value!.isEmpty ? 'Không được để trống' : null,
      );
    }

    return _isLoadingServices
        ? const Center(child: CircularProgressIndicator())
        : AppDropdown<String?>(
      value: _selectedServiceId,
      labelText: 'Loại dịch vụ tính giờ (Tùy chọn)',
      prefixIcon: Icons.timer_outlined,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text("Không áp dụng"),
        ),
        ..._timeBasedServices.map((service) =>
            DropdownMenuItem(value: service.id, child: Text(service.productName))),
      ],
      onChanged: (value) => setState(() => _selectedServiceId = value),
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _buildNameField(),
        const SizedBox(height: 16),
        _buildGroupDropdown(),
        const SizedBox(height: 16),
        // SỬA 1: Chỉ hiển thị STT khi chỉnh sửa
        if (_isEditMode) ...[
          _buildSttFieldForEdit(),
          const SizedBox(height: 16),
        ],
        _buildServiceOrQuantityField(),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildNameField()),
        const SizedBox(width: 16),
        Expanded(child: _buildGroupDropdown()),
        const SizedBox(width: 16),
        // SỬA 1: Chỉ hiển thị STT khi chỉnh sửa
        if (_isEditMode) ...[
          Expanded(child: _buildSttFieldForEdit()),
          const SizedBox(width: 16),
        ],
        Expanded(child: _buildServiceOrQuantityField()),
      ],
    );
  }
}