// lib/screens/users/permissions_screen.dart

import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/services/firestore_service.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'package:flutter/material.dart';

class PermissionsScreen extends StatefulWidget {
  final UserModel employee;

  const PermissionsScreen({super.key, required this.employee});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late Map<String, dynamic> _currentPermissions;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Khởi tạo quyền từ user model, nếu chưa có thì tạo map rỗng
    _currentPermissions = widget.employee.permissions ?? {};
  }

  // Hàm helper để lấy giá trị của một quyền cụ thể
  bool _getPermissionValue(String group, String key) {
    return _currentPermissions[group]?[key] ?? false;
  }

  // Hàm helper để cập nhật giá trị của một quyền
  void _setPermissionValue(String group, String key, bool value) {
    setState(() {
      // Nếu group chưa tồn tại, tạo mới
      _currentPermissions[group] = _currentPermissions[group] ?? {};
      _currentPermissions[group][key] = value;
    });
  }

  Future<void> _savePermissions() async {
    setState(() => _isLoading = true);
    final navigator = Navigator.of(context);
    try {
      await _firestoreService.updateUserField(
        widget.employee.uid,
        {'permissions': _currentPermissions},
      );
      ToastService().show(message: 'Cập nhật quyền thành công!', type: ToastType.success);
      navigator.pop();
    } catch (e) {
      ToastService().show(message: 'Lỗi khi lưu: $e', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Phân quyền cho ${widget.employee.name ?? ''}'),
        actions: [
          _isLoading
              ? const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)),
          )
              : IconButton(
            icon: const Icon(Icons.save),
            onPressed: _savePermissions,
            tooltip: 'Lưu thay đổi',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPermissionGroup(
            title: 'Bán Hàng',
            permissions: {
              'canSell': 'Thực hiện bán hàng, thanh toán',
              'canCancelItem': 'Hủy món đã báo chế biến',
              'canChangeTable': 'Chuyển/gộp bàn',
              'canEditNotes': 'Quản lý ghi chú nhanh',
              'canHuyBill': 'Hủy hóa đơn',
            },
            groupKey: 'sales',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Sản Phẩm',
            permissions: {
              'canAddProduct': 'Thêm sản phẩm',
              'canEditProduct': 'Chỉnh sửa sản phẩm',
              'canDeleteProduct': 'Xóa sản phẩm',
              'canEditIsVisible': 'Ẩn sản phẩm',
              'canImportExport': 'Nhập/xuất danh sách sản phẩm',
              'canViewCost': 'Xem giá vốn',
              'canEditCost': 'Sửa giá vốn',
              'canManageProductGroups': 'Quản lý nhóm sản phẩm',
              'canPrintLabel': 'In tem sản phẩm (Bán lẻ)',
              'canEditTax': 'Thiết lập thuế & HĐĐT',
            },
            groupKey: 'products',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Nhập hàng',
            permissions: {
              'canViewPurchaseOrder': 'Xem Phiếu nhập hàng',
              'canAddPurchaseOrder': 'Thêm Phiếu nhập hàng',
              'canEditPurchaseOrder': 'Sửa Phiếu nhập hàng',
              'canCancelPurchaseOrder': 'Hủy Phiếu nhập hàng',
            },
            groupKey: 'purchaseOrder',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Khuyến mãi',
            permissions: {
              'canViewPromotions': 'Xem Khuyến mãi',
              'canSetupPromotions': 'Cài đặt Khuyến mãi',
            },
            groupKey: 'promotions',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Phòng bàn',
            permissions: {
              'canViewListTable': 'Xem danh sách Phòng bàn',
              'canAddListTable': 'Thêm Phòng bàn',
              'canEditListTable': 'Sửa Phòng bàn',
              'canManagerGroupListTable': 'Quản lý nhóm Phòng bàn',
            },
            groupKey: 'listTable',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Đối tác',
            permissions: {
              'canViewContacts': 'Xem danh sách đối tác',
              'canAddContacts': 'Thêm đối tác',
              'canEditContacts': 'Sửa đối tác',
              'canManagerGroup': 'Quản lý nhóm đối tác',
              'canThuChi': 'Thu/trả nợ cho đối tác',
            },
            groupKey: 'contacts',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Nhân viên',
            permissions: {
              'canViewEmployee': 'Xem danh sách Nhân viên',
              'canAddEmployee': 'Thêm Nhân viên',
              'canEditEmployee': 'Sửa Nhân viên',
              'canDisableEmployee': 'Vô hiệu hóa/xóa Nhân viên',
            },
            groupKey: 'employee',
          ),
          const SizedBox(height: 16),
          _buildPermissionGroup(
            title: 'Báo Cáo',
            permissions: {
              'canViewSales': 'Xem báo cáo tổng quan',
              'canViewInventory': 'Xem báo cáo tồn kho',
              'canViewRetailLedger': 'Xem báo cáo hàng hóa bán ra',
            },
            groupKey: 'reports',
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionGroup({
    required String title,
    required Map<String, String> permissions,
    required String groupKey,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: Theme.of(context).primaryColor,
              ),
            ),
            const Divider(height: 24),
            ...permissions.entries.map((entry) {
              return SwitchListTile(
                title: Text(entry.value),
                value: _getPermissionValue(groupKey, entry.key),
                onChanged: (newValue) {
                  _setPermissionValue(groupKey, entry.key, newValue);
                },
                contentPadding: EdgeInsets.zero,
              );
            }),
          ],
        ),
      ),
    );
  }
}