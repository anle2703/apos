// File: lib/screens/tables/table_list_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/table_group_model.dart';
import '../models/table_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../services/toast_service.dart';
import '../theme/app_theme.dart';
import 'add_edit_table_screen.dart';
import '../widgets/custom_text_form_field.dart';

class TableListScreen extends StatefulWidget {
  final UserModel currentUser;

  const TableListScreen({super.key, required this.currentUser});

  @override
  State<TableListScreen> createState() => _TableListScreenState();
}

class _TableListScreenState extends State<TableListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _canAddListTable = false;
  bool _canEditListTable = false;
  bool _canManagerGroupListTable = false;
  late Future<List<TableGroupModel>> _tableGroupsFuture;

  @override
  void initState() {
    super.initState();

    if (widget.currentUser.role == 'owner') {
      _canAddListTable = true;
      _canEditListTable = true;
      _canManagerGroupListTable = true;
    } else {
      _canAddListTable = widget.currentUser.permissions?['listTable']
              ?['canAddListTable'] ??
          false;
      _canEditListTable = widget.currentUser.permissions?['listTable']
              ?['canEditListTable'] ??
          false;
      _canManagerGroupListTable = widget.currentUser.permissions?['listTable']
              ?['canManagerGroupListTable'] ??
          false;
    }
    _loadData();
  }

  void _loadData() {
    _tableGroupsFuture =
        _firestoreService.getTableGroups(widget.currentUser.storeId);
  }

  void _refreshData() {
    setState(() {
      _tableGroupsFuture = _firestoreService
          .getTableGroups(widget.currentUser.storeId, forceRefresh: true);
    });
  }

  void _showGroupManagementSheet(List<TableGroupModel> groups) {
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
                    'Quản lý Nhóm Phòng/Bàn',
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
                          title: Text('${group.stt}. ${group.name}',
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

                                    _showEditGroupDialog(group);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red),
                                  onPressed: () {
                                    Navigator.of(context).pop();

                                    _confirmDeleteGroup(group);
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
    ).then((_) => _refreshData());
  }

  void _showEditGroupDialog(TableGroupModel group) {
    final nameController = TextEditingController(text: group.name);

    final sttController = TextEditingController(text: group.stt.toString());

    final formKey = GlobalKey<FormState>();
    final navigator = Navigator.of(context);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cập nhật Nhóm'),
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
                const SizedBox(height: 16.0),
                CustomTextFormField(
                  controller: sttController,
                  decoration: const InputDecoration(labelText: 'Số thứ tự'),
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  validator: (value) => value == null || value.isEmpty
                      ? 'Không được để trống'
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  try {
                    await _firestoreService.updateTableGroup(
                      group.id,
                      nameController.text.trim(),
                      int.parse(sttController.text),
                    );
                    if (!mounted) return;
                    ToastService().show(
                        message: 'Cập nhật thành công',
                        type: ToastType.success);
                    _refreshData();
                    navigator.pop();
                  } catch (e) {
                    ToastService()
                        .show(message: 'Lỗi: $e', type: ToastType.error);
                  }
                }
              },
              child: const Text('Lưu'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDeleteGroup(TableGroupModel group) async {
    // Bắt đầu với một check an toàn
    if (!mounted) return;

    // 1. CAPTURE: Lưu lại Navigator và các service cần thiết
    final navigator = Navigator.of(context);
    final firestoreService = _firestoreService;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        // Dùng dialogContext cho các hành động bên trong dialog
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa nhóm "${group.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            // Dùng context của dialog để đóng
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              try {
                await firestoreService.deleteTableGroup(
                  group.id,
                  group.name,
                  widget.currentUser.storeId,
                );
                if (!mounted) return;
                ToastService().show(
                  message: 'Xóa nhóm thành công.',
                  type: ToastType.warning,
                );
                _refreshData();
                navigator.pop();
              } catch (e) {
                if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TableGroupModel>>(
      future: _tableGroupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Danh sách Phòng/Bàn')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Danh sách Phòng/Bàn')),
            body: Center(child: Text('Đã có lỗi xảy ra: ${snapshot.error}')),
          );
        }

        final tableGroups = snapshot.data ?? [];

        final groupNames = ['Tất cả', ...tableGroups.map((g) => g.name)];

        return DefaultTabController(
          length: groupNames.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Danh sách Phòng/Bàn'),
              actions: [
                if (_canAddListTable)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outlined, size: 30),
                    color: AppTheme.primaryColor,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (context) => AddEditTableScreen(
                                  currentUser: widget.currentUser,
                                  tableGroups: tableGroups,
                                )),
                      );

                      _refreshData();
                    },
                    tooltip: 'Thêm mới Phòng/Bàn',
                  ),
                if (_canManagerGroupListTable)
                  IconButton(
                    icon: const Icon(Icons.settings, size: 30),
                    color: AppTheme.primaryColor,
                    onPressed: () {
                      if (tableGroups.isNotEmpty) {
                        _showGroupManagementSheet(tableGroups);
                      } else {
                        ToastService().show(
                            message: 'Chưa có nhóm nào được tạo.',
                            type: ToastType.warning);
                      }
                    },
                    tooltip: 'Quản lý nhóm',
                  ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabs: groupNames.map((name) => Tab(text: name)).toList(),
              ),
            ),
            body: TabBarView(
              children: groupNames.map((name) {
                final filterGroup = (name == 'Tất cả') ? null : name;

                return _buildTableGridForGroup(filterGroup, tableGroups);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableGridForGroup(
      String? group, List<TableGroupModel> tableGroups) {
    return StreamBuilder<List<TableModel>>(
      stream: _firestoreService.getTablesStream(widget.currentUser.storeId,
          group: group),
      builder: (context, tableSnapshot) {
        if (tableSnapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (tableSnapshot.hasError) {
          return Center(
              child: Text('Lỗi tải danh sách bàn: ${tableSnapshot.error}'));
        }
        if (!tableSnapshot.hasData || tableSnapshot.data!.isEmpty) {
          return const Center(
              child: Text('Chưa có phòng/bàn nào trong nhóm này.'));
        }

        final tables = tableSnapshot.data!
            .where((t) =>
        !t.id.startsWith('ship') && !t.id.startsWith('schedule'))
            .toList();

        if (tables.isEmpty) {
          return const Center(
              child: Text('Chưa có phòng/bàn nào trong nhóm này.'));
        }

        tables.sort((a, b) => a.stt.compareTo(b.stt));

        return GridView.builder(
          padding: const EdgeInsets.all(12.0),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150, // Giảm kích thước thẻ một chút
            childAspectRatio: 1, // Điều chỉnh tỷ lệ cho phù hợp
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: tables.length,
          itemBuilder: (context, index) {
            final table = tables[index];
            // Không cần lấy orderForTable nữa
            return _TableCard(
              currentUser: widget.currentUser,
              table: table,
              tableGroups: tableGroups,
              canEdit: _canEditListTable,
              onRefresh: _refreshData,
            );
          },
        );
      },
    );
  }
}

class _TableCard extends StatelessWidget {
  final UserModel currentUser;
  final TableModel table;
  final List<TableGroupModel> tableGroups;
  final VoidCallback onRefresh;
  final bool canEdit;

  const _TableCard({
    required this.currentUser,
    required this.table,
    required this.tableGroups,
    required this.onRefresh,
    required this.canEdit,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    void editAction() {
      if (canEdit) {
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (context) => AddEditTableScreen(
                currentUser: currentUser,
                tableToEdit: table,
                tableGroups: tableGroups,
              ),
            ))
            .then((_) => onRefresh());
      } else {
        ToastService().show(
            message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
            type: ToastType.warning);
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200, width: 1.0),
      ),
      elevation: 2.0,
      shadowColor: Colors.black.withAlpha(25),
      child: InkWell(
        onTap: editAction,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(
                  top: 24.0, bottom: 8.0, left: 8.0, right: 8.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    table.tableName,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.2,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    table.tableGroup,
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade600, fontSize: 13),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: const BoxDecoration(
                  color: Colors.grey,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  table.stt.toString(),
                  style: textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
