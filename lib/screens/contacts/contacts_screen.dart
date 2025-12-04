// lib/screens/contacts/contacts_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_4cash/models/customer_model.dart';
import 'package:app_4cash/services/firestore_service.dart';
import 'package:app_4cash/screens/contacts/add_edit_customer_dialog.dart';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';
import 'package:app_4cash/models/customer_group_model.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'customer_detail_screen.dart';
import 'supplier_detail_screen.dart';
import '../../models/supplier_model.dart';
import 'add_edit_supplier_dialog.dart';
import '../../services/supplier_service.dart';
import 'package:app_4cash/widgets/custom_text_form_field.dart';

class ContactsScreen extends StatefulWidget {
  final UserModel currentUser;

  const ContactsScreen({super.key, required this.currentUser});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final GlobalKey<_CustomerListTabState> _customerTabKey =
      GlobalKey<_CustomerListTabState>();
  final GlobalKey<_SupplierListTabState> _supplierTabKey =
      GlobalKey<_SupplierListTabState>();

  bool _canAddContacts = false;
  bool _canManagerGroup = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {});
    });
    if (widget.currentUser.role == 'owner') {
      _canAddContacts = true;
      _canManagerGroup = true;
    } else {
      _canAddContacts = widget.currentUser.permissions?['contacts']
              ?['canAddContacts'] ??
          false;
      _canManagerGroup = widget.currentUser.permissions?['contacts']
              ?['canManagerGroup'] ??
          false;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _manageCurrentGroup() {
    if (_tabController.index == 0) {
      _customerTabKey.currentState?.showGroupManagement();
    } else {
      _supplierTabKey.currentState?.showGroupManagement();
    }
  }

  void _openAddDialogForCurrentTab() {
    if (_tabController.index == 0) {
      _customerTabKey.currentState?.showAddCustomerDialog();
    } else {
      _supplierTabKey.currentState?.showAddSupplierDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Đối tác'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Khách Hàng'),
            Tab(text: 'Nhà Cung Cấp'),
          ],
        ),
        actions: [
          if (_canAddContacts) ...[
            IconButton(
              icon: const Icon(Icons.add_circle_outlined,
                  size: 30, color: AppTheme.primaryColor),
              tooltip: _tabController.index == 0
                  ? 'Thêm Khách Hàng'
                  : 'Thêm Nhà Cung Cấp',
              onPressed: _openAddDialogForCurrentTab,
            ),
            const SizedBox(width: 8),
          ],
          if (_canManagerGroup) ...[
            IconButton(
              icon: const Icon(Icons.settings,
                  size: 30, color: AppTheme.primaryColor),
              tooltip: 'Quản lý nhóm',
              onPressed: _manageCurrentGroup,
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          CustomerListTab(
              key: _customerTabKey, currentUser: widget.currentUser),
          SupplierListTab(
              key: _supplierTabKey, currentUser: widget.currentUser),
        ],
      ),
    );
  }
}

class CustomerListTab extends StatefulWidget {
  final UserModel currentUser;

  const CustomerListTab({super.key, required this.currentUser});

  @override
  State<CustomerListTab> createState() => _CustomerListTabState();
}

class _CustomerListTabState extends State<CustomerListTab> {
  final TextEditingController _searchController = TextEditingController();
  final FirestoreService _firestoreService = FirestoreService();
  late final String _storeId;

  List<CustomerGroupModel> _customerGroups = [];
  String? _selectedFilterGroupId;
  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _storeId = widget.currentUser.storeId;
    _loadCustomerGroups();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _loadCustomerGroups() async {
    setState(() => _isLoadingGroups = true);
    try {
      _customerGroups = await _firestoreService.getCustomerGroups(_storeId);
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> showAddCustomerDialog({CustomerModel? customer}) async {
    // 1. SỬA LỖI GỐC: Khai báo kiểu trả về chính xác là CustomerModel.
    final result = await showDialog<CustomerModel>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddEditCustomerDialog(
        firestoreService: _firestoreService,
        storeId: _storeId,
        customer: customer,
      ),
    );

    // result là CustomerModel (đã lưu vào DB) hoặc null (nếu bấm Hủy).
    if (result == null || !mounted) return;

    // 2. LOẠI BỎ logic lưu DB dư thừa và lỗi đọc Map.
    try {
      // Xác định thông báo dựa trên việc thêm mới hay cập nhật
      final String message =
          (customer != null) ? 'Cập nhật thành công!' : 'Thêm mới thành công!';

      ToastService().show(message: message, type: ToastType.success);

      // Dùng result.customerGroupId để kiểm tra sự thay đổi nhóm (thay cho newGroupCreated)
      // Nếu ID nhóm hiện tại khác ID nhóm ban đầu (hoặc là ID mới), reload nhóm.
      if (result.customerGroupId != customer?.customerGroupId) {
        await _loadCustomerGroups();
      }

      // Cập nhật trạng thái UI (ví dụ: danh sách khách hàng)
      setState(() {});
    } catch (e) {
      // Bắt lỗi nếu có vấn đề về UI/Toast sau khi lưu
      ToastService()
          .show(message: "Lưu khách hàng thất bại: $e", type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
            padding: const EdgeInsets.all(16.0),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth > 600;

                final searchField = TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Tìm theo tên hoặc SĐT...',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 16),
                  ),
                );

                final groupFilter = AppDropdown<String>(
                  labelText: 'Lọc theo nhóm',
                  prefixIcon: Icons.filter_list,
                  // Hoặc Icons.filter_list
                  value: _selectedFilterGroupId,
                  // Luôn dùng giá trị đang chọn (ban đầu là null)
                  items: _isLoadingGroups
                      ? [
                          const DropdownMenuItem(
                              value: null, child: Text('Đang tải nhóm...')),
                        ]
                      : [
                          const DropdownMenuItem(
                              value: null, child: Text('Tất cả nhóm')),
                          ..._customerGroups.map((group) => DropdownMenuItem(
                              value: group.id,
                              child: Text(group.name,
                                  overflow: TextOverflow.ellipsis)))
                        ],
                  onChanged: _isLoadingGroups
                      ? null
                      : (String? newValue) {
                          setState(() {
                            _selectedFilterGroupId = newValue;
                          });
                        },
                );

                if (isDesktop) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 12),
                      Expanded(child: groupFilter),
                    ],
                  );
                } else {
                  return Column(
                    children: [
                      searchField,
                      const SizedBox(height: 12),
                      groupFilter,
                    ],
                  );
                }
              },
            )),
        Expanded(
          child: StreamBuilder<List<CustomerModel>>(
            stream: _firestoreService.searchCustomers(
              _searchController.text.trim(),
              _storeId,
              groupId: _selectedFilterGroupId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Lỗi: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                  child: Text('Không tìm thấy khách hàng nào.'),
                );
              }
              final customers = snapshot.data!;
              customers
                  .sort((a, b) => (b.debt ?? 0.0).compareTo(a.debt ?? 0.0));
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return _buildCustomerCard(customer);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerCard(CustomerModel customer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => CustomerDetailScreen(
              customerId: customer.id,
              currentUser: widget.currentUser,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              bool isMobile =
                  constraints.maxWidth < 500; // Tăng breakpoint một chút
              if (isMobile) {
                return _buildMobileLayout(customer);
              } else {
                return _buildDesktopLayout(customer);
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(CustomerModel customer) {
    final textStyleLabel = TextStyle(color: Colors.black, fontSize: 16);
    final textStyleValue =
        const TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.blueAccent.withAlpha(25),
          foregroundColor: Colors.blueAccent,
          child: const Icon(Icons.person_outline),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                customer.phone,
                style: TextStyle(color: Colors.black, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Text('Dư nợ: ', style: textStyleLabel),
                Text(
                  '${NumberFormat('#,##0', 'vi_VN').format(customer.debt ?? 0)} đ',
                  style: textStyleValue.copyWith(
                    color: (customer.debt ?? 0) > 0 ? Colors.red : Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Điểm thưởng: ', style: textStyleLabel),
                Text(
                  NumberFormat('#,##0', 'vi_VN').format(customer.points),
                  style: textStyleValue.copyWith(
                    color: Colors.green,
                  ),
                ),
              ],
            )
          ],
        )
      ],
    );
  }

  Widget _buildMobileLayout(CustomerModel customer) {
    final textStyleLabel = TextStyle(color: Colors.black, fontSize: 16);
    final textStyleValue =
        const TextStyle(fontWeight: FontWeight.bold, fontSize: 16);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          backgroundColor: Colors.blueAccent.withAlpha(25),
          foregroundColor: Colors.blueAccent,
          child: const Icon(Icons.person_outline),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                customer.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 2),
              Text(customer.phone, style: textStyleLabel),
              const SizedBox(height: 6),

              // Hàng Dư nợ (giá trị nằm sát nhãn)
              Row(
                children: [
                  Text('Dư nợ: ', style: textStyleLabel), // Thêm khoảng trắng
                  Text(
                    '${NumberFormat('#,##0', 'vi_VN').format(customer.debt ?? 0)} đ',
                    style: textStyleValue.copyWith(
                      color:
                          (customer.debt ?? 0) > 0 ? Colors.red : Colors.green,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              // Hàng Điểm thưởng (giá trị nằm sát nhãn)
              Row(
                children: [
                  Text('Điểm thưởng: ', style: textStyleLabel),
                  // Thêm khoảng trắng
                  Text(
                    NumberFormat('#,##0', 'vi_VN').format(customer.points),
                    style: textStyleValue.copyWith(color: Colors.green),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  void showGroupManagement() {
    if (_customerGroups.isEmpty) {
      ToastService().show(
          message: 'Chưa có nhóm Khách hàng nào được tạo.',
          type: ToastType.warning);
      return;
    }
    _showCustomerGroupManagementSheet(_customerGroups);
  }

  /// Hiển thị BottomSheet quản lý nhóm
  void _showCustomerGroupManagementSheet(List<CustomerGroupModel> groups) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Quản lý Nhóm Khách Hàng',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 16.0, right: 8.0),
                          title: Text(group.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          trailing: SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Colors.blue),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _showEditCustomerGroupDialog(group);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _confirmDeleteCustomerGroup(group);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) => _loadCustomerGroups()); // Tải lại nhóm sau khi đóng
  }

  /// Hiển thị Dialog sửa tên nhóm
  void _showEditCustomerGroupDialog(CustomerGroupModel group) {
    final nameController = TextEditingController(text: group.name);
    final formKey = GlobalKey<FormState>();
    final navigator = Navigator.of(context);
    bool isSaving = false; // Thêm cờ

    showDialog(
      context: context,
      builder: (context) {
        // *** SỬA LỖI: Dùng StatefulBuilder để cập nhật nút saving ***
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Cập nhật Nhóm KH'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomTextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Tên nhóm'),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Không được để trống'
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isSaving = true);
                          try {
                            final newName = nameController.text.trim();
                            // 1. Cập nhật document nhóm
                            await _firestoreService.updateCustomerGroup(
                              group.id,
                              newName,
                            );

                            // 2. Cập nhật tất cả khách hàng thuộc nhóm này
                            await _firestoreService
                                .updateCustomerGroupNameInCustomers(
                                    group.id, newName, _storeId);

                            ToastService().show(
                                message: 'Cập nhật thành công',
                                type: ToastType.success);
                            await _loadCustomerGroups(); // Await
                            navigator.pop();
                          } catch (e) {
                            ToastService().show(
                                message: 'Lỗi: $e', type: ToastType.error);
                            setDialogState(() => isSaving = false);
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Lưu'),
              ),
            ],
          );
        });
      },
    );
  }

  /// Hiển thị Dialog xác nhận xóa nhóm
  Future<void> _confirmDeleteCustomerGroup(CustomerGroupModel group) async {
    final navigator = Navigator.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa nhóm "${group.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // !!! LƯU Ý: Bạn cần tạo hàm 'deleteCustomerGroup' trong FirestoreService
                await _firestoreService.deleteCustomerGroup(group.id, _storeId);
                ToastService().show(
                  message: 'Xóa nhóm thành công.',
                  type: ToastType.warning,
                );
                await _loadCustomerGroups(); // Await
                navigator.pop();
              } catch (e) {
                String errorMessage =
                    e.toString().replaceFirst("Exception: ", "");
                ToastService().show(
                  message: errorMessage,
                  type: ToastType.warning,
                );
                navigator.pop();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class SupplierListTab extends StatefulWidget {
  final UserModel currentUser;

  const SupplierListTab({super.key, required this.currentUser});

  @override
  State<SupplierListTab> createState() => _SupplierListTabState();
}

class _SupplierListTabState extends State<SupplierListTab> {
  final TextEditingController _searchController = TextEditingController();
  final SupplierService _supplierService = SupplierService();
  late final String _storeId;

  List<SupplierGroupModel> _supplierGroups = [];
  String? _selectedFilterGroupId;
  bool _isLoadingGroups = true;

  @override
  void initState() {
    super.initState();
    _storeId = widget.currentUser.storeId;
    _loadSupplierGroups();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _loadSupplierGroups() async {
    setState(() => _isLoadingGroups = true);
    try {
      _supplierGroups = await _supplierService.getSupplierGroups(_storeId);
    } catch (e) {
      debugPrint("Lỗi tải nhóm NCC: $e");
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> showAddSupplierDialog({SupplierModel? supplier}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AddEditSupplierDialog(
        supplier: supplier,
        storeId: _storeId,
      ),
    );
    if (result == true && mounted) {
      // *** SỬA LỖI STATE: Await load groups ***
      await _loadSupplierGroups();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isDesktop = constraints.maxWidth > 600;

              final searchField = TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên hoặc SĐT...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                ),
              );

              final groupFilter = _isLoadingGroups
                  ? const Center(
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : AppDropdown<String>(
                      labelText: 'Lọc theo nhóm',
                      prefixIcon: Icons.filter_list,
                      value: _selectedFilterGroupId,
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Tất cả nhóm')),
                        ..._supplierGroups.map((group) => DropdownMenuItem(
                            value: group.id, child: Text(group.name)))
                      ],
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedFilterGroupId = newValue;
                        });
                      },
                    );

              if (isDesktop) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    Expanded(child: groupFilter),
                  ],
                );
              } else {
                return Column(
                  children: [
                    searchField,
                    const SizedBox(height: 12),
                    groupFilter,
                  ],
                );
              }
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<List<SupplierModel>>(
            stream: _supplierService.searchSuppliersStream(
              _searchController.text.trim(),
              _storeId,
              groupId: _selectedFilterGroupId,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Lỗi: ${snapshot.error}'));
              }
              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return const Center(
                    child: Text('Không tìm thấy nhà cung cấp nào.'));
              }
              final suppliers = snapshot.data!;

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: suppliers.length,
                itemBuilder: (context, index) {
                  final supplier = suppliers[index];
                  return _buildSupplierCard(supplier);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSupplierCard(SupplierModel supplier) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => SupplierDetailScreen(
              supplierId: supplier.id,
              currentUser: widget.currentUser,
            ),
          ));
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: Colors.blueAccent.withAlpha(25),
                foregroundColor: Colors.blueAccent,
                child: const Icon(Icons.storefront_outlined),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      supplier.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      supplier.phone,
                      style: TextStyle(color: Colors.black, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Dư nợ: ',
                          style: TextStyle(color: Colors.black, fontSize: 16),
                        ),
                        Text(
                          '${NumberFormat('#,##0', 'vi_VN').format(supplier.debt)} đ',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                supplier.debt > 0 ? Colors.red : Colors.green,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void showGroupManagement() {
    if (_supplierGroups.isEmpty) {
      ToastService().show(
          message: 'Chưa có nhóm NCC nào được tạo.', type: ToastType.warning);
      return;
    }
    _showSupplierGroupManagementSheet(_supplierGroups);
  }

  /// Hiển thị BottomSheet quản lý nhóm
  void _showSupplierGroupManagementSheet(List<SupplierGroupModel> groups) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          maxChildSize: 0.8,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Quản lý Nhóm Nhà Cung Cấp',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: groups.length,
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return Card(
                        child: ListTile(
                          contentPadding:
                              const EdgeInsets.only(left: 16.0, right: 8.0),
                          title: Text(group.name,
                              style: Theme.of(context).textTheme.titleMedium),
                          trailing: SizedBox(
                            width: 96,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: Colors.blue),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _showEditSupplierGroupDialog(group);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _confirmDeleteSupplierGroup(group);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ).then((_) => _loadSupplierGroups()); // Tải lại nhóm sau khi đóng
  }

  /// Hiển thị Dialog sửa tên nhóm
  void _showEditSupplierGroupDialog(SupplierGroupModel group) {
    final nameController = TextEditingController(text: group.name);
    final formKey = GlobalKey<FormState>();
    final navigator = Navigator.of(context);
    bool isSaving = false; // Thêm cờ

    showDialog(
      context: context,
      builder: (context) {
        // *** SỬA LỖI: Dùng StatefulBuilder ***
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Cập nhật Nhóm NCC'),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomTextFormField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Tên nhóm'),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Không được để trống'
                        : null,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.of(context).pop(),
                child: const Text('Hủy'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setDialogState(() => isSaving = true); // Bật cờ
                          try {
                            final newName = nameController.text.trim();
                            // 1. Cập nhật document nhóm
                            await _supplierService.updateSupplierGroup(
                              group.id,
                              newName,
                            );

                            // 2. Cập nhật tất cả NCC thuộc nhóm này
                            await _supplierService
                                .updateSupplierGroupNameInSuppliers(
                                    group.id, newName, _storeId);

                            ToastService().show(
                                message: 'Cập nhật thành công',
                                type: ToastType.success);
                            await _loadSupplierGroups(); // Await
                            navigator.pop();
                          } catch (e) {
                            ToastService().show(
                                message: 'Lỗi: $e', type: ToastType.error);
                            setDialogState(() => isSaving = false); // Tắt cờ
                          }
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Lưu'),
              ),
            ],
          );
        });
      },
    );
  }

  /// Hiển thị Dialog xác nhận xóa nhóm
  Future<void> _confirmDeleteSupplierGroup(SupplierGroupModel group) async {
    final navigator = Navigator.of(context);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa nhóm "${group.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await _supplierService.deleteSupplierGroup(group.id, _storeId);
                ToastService().show(
                  message: 'Xóa nhóm thành công.',
                  type: ToastType.warning,
                );
                await _loadSupplierGroups(); // Await
                navigator.pop();
              } catch (e) {
                String errorMessage =
                    e.toString().replaceFirst("Exception: ", "");
                ToastService().show(
                  message: errorMessage,
                  type: ToastType.warning,
                );
                navigator.pop();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
