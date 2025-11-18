// lib/screens/users/employee_management_screen.dart

import 'package:app_4cash/models/user_model.dart';
import 'package:app_4cash/services/firestore_service.dart';
import 'package:app_4cash/services/toast_service.dart';
import 'package:app_4cash/widgets/custom_text_form_field.dart';
import 'package:flutter/material.dart';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:app_4cash/widgets/app_dropdown.dart';
import 'permissions_screen.dart';

class EmployeeManagementScreen extends StatefulWidget {
  final UserModel currentUser;

  const EmployeeManagementScreen({super.key, required this.currentUser});

  @override
  State<EmployeeManagementScreen> createState() =>
      _EmployeeManagementScreenState();
}

class _EmployeeManagementScreenState extends State<EmployeeManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  bool _canEditEmployee = false;
  bool _canAddEmployee = false;
  bool _canDisableEmployee = false;

  final Map<String, String> _roleLabels = {
    'manager': 'Quản lý',
    'cashier': 'Thu ngân',
    'order': 'Nhân viên',
    'owner': 'Chủ cửa hàng',
  };

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.role == 'owner') {
      _canAddEmployee = true;
      _canEditEmployee = true;
      _canDisableEmployee = true;
    } else {
      _canAddEmployee = widget.currentUser.permissions?['employee']?['canAddEmployee'] ?? false;
      _canEditEmployee = widget.currentUser.permissions?['employee']?['canEditEmployee'] ?? false;
      _canDisableEmployee = widget.currentUser.permissions?['employee']?['canDisableEmployee'] ?? false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Quản lý nhân viên'),
        actions: [
          if (_canAddEmployee)
            IconButton(
            icon: Icon(
              Icons.add_circle,
              size: 30,
              color: Theme.of(context).primaryColor,
            ),
            onPressed: () => _showAddEmployeeDialog(context),
            tooltip: 'Thêm nhân viên',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: StreamBuilder<List<UserModel>>(
        stream: _firestoreService
            .getAllUsersInStoreStream(widget.currentUser.storeId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('Chưa có nhân viên nào.'));
          }

          final allUsers = snapshot.data!;
          allUsers.sort((a, b) {
            if (a.role == 'owner') return -1;
            if (b.role == 'owner') return 1;
            return (a.name ?? '').compareTo(b.name ?? '');
          });

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: allUsers.length,
            itemBuilder: (context, index) {
              final user = allUsers[index];
              final isOwner = user.role == 'owner';

              return Card(
                clipBehavior: Clip.hardEdge,
                child: InkWell(
                  onTap: () => _showEditUserDialog(context, user),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8.0, vertical: 12.0),
                    child: ListTile(
                      leading: _buildRoleIcon(user.role),
                      title: Row(
                        children: [
                          Text(
                            user.name ?? 'Chưa có tên',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          _buildStatusBadge(user.active),
                        ],
                      ),
                      subtitle: Text(
                        '${_roleLabels[user.role] ?? user.role.toUpperCase()} - ${user.phoneNumber}',
                          style: Theme.of(context).textTheme.titleMedium),
                      trailing: isOwner
                          ? null
                          : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.admin_panel_settings_outlined, size: 25, color: AppTheme.primaryColor,),
                            tooltip: 'Phân quyền',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => PermissionsScreen(employee: user),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildRoleIcon(String role) {
    IconData iconData;
    Color color;

    switch (role) {
      case 'owner':
        iconData = Icons.verified_user;
        color = Colors.amber.shade700;
        break;
      case 'manager':
        iconData = Icons.supervisor_account;
        color = AppTheme.primaryColor;
        break;
      case 'cashier':
        iconData = Icons.point_of_sale;
        color = Colors.blue.shade600;
        break;
      default: // order
        iconData = Icons.person;
        color = Colors.grey.shade600;
    }

    return CircleAvatar(
      backgroundColor: color.withAlpha(25),
      child: Icon(iconData, color: color, size: 24),
    );
  }

  Widget _buildStatusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? Colors.green : Colors.grey).withAlpha(38),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Hoạt động' : 'Vô hiệu hóa',
        style: TextStyle(
          color: isActive ? Colors.green.shade800 : Colors.grey.shade700,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, UserModel user) {
    if (_canEditEmployee) {
      if (user.role == 'owner') {
        _showEditOwnerDialog(context, user);
      } else {
        _showEditEmployeeDialog(context, user);
      }
    } else {
      ToastService().show(
          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
          type: ToastType.warning);
    }
  }

  void _showEditOwnerDialog(BuildContext context, UserModel owner) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: owner.name);
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Đổi tên hiển thị'),
              content: Form(
                key: formKey,
                child: CustomTextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Tên mới'),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Không được để trống'
                      : null,
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isLoading = true);
                            final navigator = Navigator.of(dialogContext);

                            try {
                              await _firestoreService.updateUserField(owner.uid,
                                  {'name': nameController.text.trim()});
                              if (mounted) {
                                ToastService().show(
                                    message: 'Cập nhật tên thành công!',
                                    type: ToastType.success);
                                navigator.pop();
                              }
                            } catch (e) {
                              ToastService().show(
                                  message: 'Lỗi: $e', type: ToastType.error);
                            } finally {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditEmployeeDialog(BuildContext context, UserModel user) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user.name);
    final phoneController = TextEditingController(text: user.phoneNumber);
    final passwordController = TextEditingController();
    String selectedRole = user.role;
    bool isActive = user.active;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Chỉnh sửa tài khoản'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomTextFormField(
                        controller: nameController,
                        decoration:
                            const InputDecoration(labelText: 'Tên nhân viên'),
                        validator: (v) =>
                            v!.isEmpty ? 'Vui lòng nhập tên' : null,
                      ),
                      const SizedBox(height: 16),
                      CustomTextFormField(
                        controller: phoneController,
                        decoration:
                            const InputDecoration(labelText: 'Số điện thoại'),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v!.isEmpty) return 'Vui lòng nhập SĐT';
                          if (!v.startsWith('0') || v.length != 10){
                            return 'SĐT không hợp lệ';}
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppDropdown<String>(
                        labelText: 'Vai trò',
                        value: selectedRole,
                        items: _roleLabels.entries
                            .where((entry) => entry.key != 'owner')
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            selectedRole = value;
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      CustomTextFormField(
                        controller: passwordController,
                        decoration: const InputDecoration(
                            labelText: 'Mật khẩu mới',
                            hintText: 'Để trống nếu không đổi',
                        ),
                        obscureText: true,
                        validator: (v) {
                          if (v!.isNotEmpty && v.length < 6){
                            return 'Mật khẩu cần ít nhất 6 ký tự';}
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Đang hoạt động'),
                        value: isActive,
                        onChanged: (value) {
                          if (_canDisableEmployee) {
                            setDialogState(() => isActive = value);
                          } else {
                            ToastService().show(
                                message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                                type: ToastType.warning);
                          }
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                // THÊM ĐOẠN NÀY VÀO:
                TextButton(
                  onPressed: () {
                    if (_canDisableEmployee) {
                      _confirmAndDeleteUser(dialogContext, user);
                    } else {
                      ToastService().show(
                          message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.all(Colors.red),
                    overlayColor: WidgetStateProperty.resolveWith<Color?>(
                          (Set<WidgetState> states) {
                        if (states.contains(WidgetState.hovered)) {
                          return Colors.red.withAlpha(25);
                        }
                        return null;
                      },
                    ),
                  ),
                  child: const Text('Xóa TK'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isLoading = true);
                            final navigator = Navigator.of(dialogContext);
                            try {
                              final newName = nameController.text.trim();
                              final newPhone = phoneController.text.trim();
                              final newPassword =
                                  passwordController.text.trim();

                              if (newPhone != user.phoneNumber) {
                                bool phoneExists =
                                    await _firestoreService.isPhoneNumberInUse(
                                        phone: newPhone,
                                        storeId: user.storeId,
                                        currentUserId: user.uid);
                                if (phoneExists) {
                                  ToastService().show(
                                      message:
                                          'SĐT này đã được người khác sử dụng.',
                                      type: ToastType.error);
                                  setDialogState(() => isLoading = false);
                                  return;
                                }
                              }

                              await _firestoreService
                                  .updateUserField(user.uid, {
                                'name': newName,
                                'phoneNumber': newPhone,
                                'role': selectedRole,
                                'active': isActive,
                              });

                              if (newPassword.isNotEmpty) {
                                await _firestoreService.updateUserPassword(
                                    user.uid, newPassword);
                              }

                              if (mounted) {
                                ToastService().show(
                                    message: 'Cập nhật thành công!',
                                    type: ToastType.success);
                                navigator.pop();
                              }
                            } catch (e) {
                              ToastService().show(
                                  message: 'Lỗi: $e', type: ToastType.error);
                            } finally {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmAndDeleteUser(BuildContext editDialogContext, UserModel user) {
    showDialog(
      context: editDialogContext,
      builder: (confirmContext) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text(
            'Bạn có chắc chắn muốn xóa tài khoản "${user.name ?? 'nhân viên này'}" không? Hành động này không thể hoàn tác.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(confirmContext).pop(),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              final navigator = Navigator.of(confirmContext);
              final editNavigator = Navigator.of(editDialogContext);

              try {
                // Khoảng nghỉ bất đồng bộ xảy ra ở đây
                await _firestoreService.deleteUser(user.uid);

                // Kiểm tra mounted vẫn là một thói quen tốt
                if (mounted) {
                  ToastService().show(
                      message: 'Đã xóa tài khoản thành công.',
                      type: ToastType.success);
                  // Dùng navigator đã được lấy ra từ trước
                  navigator.pop();
                  editNavigator.pop();
                }
              } catch (e) {
                ToastService()
                    .show(message: 'Lỗi khi xóa: $e', type: ToastType.error);
              }
            },
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }

  void _showAddEmployeeDialog(BuildContext context) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'order';
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tạo tài khoản nhân viên'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomTextFormField(
                        controller: nameController,
                        decoration:
                            const InputDecoration(labelText: 'Họ và tên'),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Vui lòng nhập tên'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      CustomTextFormField(
                        controller: phoneController,
                        decoration: const InputDecoration(
                            labelText: 'Số điện thoại',
                            hintText: 'Sử dụng để đăng nhập'
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (value) {
                          if (value == null || value.isEmpty){
                            return 'Vui lòng nhập SĐT';}
                          if (!value.startsWith('0') || value.length != 10){
                            return 'SĐT không hợp lệ';}
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      CustomTextFormField(
                        controller: passwordController,
                        decoration:
                            const InputDecoration(labelText: 'Mật khẩu'),
                        obscureText: true,
                        validator: (value) {
                          if (value == null || value.isEmpty){
                            return 'Vui lòng nhập mật khẩu';}
                          if (value.length < 6){
                            return 'Mật khẩu cần ít nhất 6 ký tự';}
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      AppDropdown<String>(
                        labelText: 'Vai trò',
                        value: selectedRole,
                        items: _roleLabels.entries
                            .where((entry) => entry.key != 'owner')
                            .map((entry) => DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value),
                                ))
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => selectedRole = value);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (formKey.currentState!.validate()) {
                            setDialogState(() => isLoading = true);

                            final firestoreService = FirestoreService();

                            final name = nameController.text.trim();
                            final phone = phoneController.text.trim();
                            final password = passwordController.text.trim();
                            final storeId = widget.currentUser.storeId;
                            final navigator = Navigator.of(context);

                            try {
                              await firestoreService.createEmployeeProfile(
                                storeId: storeId,
                                name: name,
                                phoneNumber: phone,
                                password: password,
                                role: selectedRole,
                                ownerUid:
                                    widget.currentUser.uid,
                              );

                              if (mounted) {
                                ToastService().show(
                                    message: 'Tạo tài khoản nhân viên thành công!',
                                    type: ToastType.success);
                                navigator.pop();
                              }
                            } catch (e) {
                              ToastService().show(
                                  message: 'Đã xảy ra lỗi: $e',
                                  type: ToastType.error);
                            } finally {
                              setDialogState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Tạo'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
