import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../models/product_group_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_search_delegate.dart';
import 'add_edit_product_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/custom_text_form_field.dart';
import 'product_import_export_screen.dart';

class ProductListScreen extends StatefulWidget {
  final UserModel currentUser;

  const ProductListScreen({super.key, required this.currentUser});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  late Future<List<ProductGroupModel>> _productGroupsFuture;

  bool _canAddProduct = false;
  bool _canEditProduct = false;
  bool _canViewCost = false;
  bool _canManageGroups = false;
  bool _canImportExport = false;

  @override
  void initState() {
    super.initState();
    if (widget.currentUser.role == 'owner') {
      _canAddProduct = true;
      _canEditProduct = true;
      _canViewCost = true;
      _canManageGroups = true;
      _canImportExport = true;
    } else {
      _canAddProduct = widget.currentUser.permissions?['products']?['canAddProduct'] ?? false;
      _canEditProduct = widget.currentUser.permissions?['products']?['canEditProduct'] ?? false;
      _canViewCost = widget.currentUser.permissions?['products']?['canViewCost'] ?? false;
      _canManageGroups = widget.currentUser.permissions?['products']?['canManageProductGroups'] ?? false;
      _canImportExport = widget.currentUser.permissions?['products']?['canImportExport'] ?? false;
    }
    _loadData();
  }

  void _loadData() {
    _productGroupsFuture =
        _firestoreService.getProductGroups(widget.currentUser.storeId);
  }

  void _refreshData() {
    setState(() {
      _productGroupsFuture = _firestoreService
          .getProductGroups(widget.currentUser.storeId, forceRefresh: true);
    });
  }

  Future<void> _showSearchDialog(List<ProductGroupModel> productGroups) async {
    final selectedProduct = await ProductSearchScreen.showSingleSelect(
      context: context,
      currentUser: widget.currentUser,
    );

    if (selectedProduct != null && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AddEditProductScreen(
            currentUser: widget.currentUser,
            productToEdit: selectedProduct,
            productGroups: productGroups,
          ),
        ),
      );
      _refreshData();
    }
  }

  void _showGroupManagementSheet(List<ProductGroupModel> groups) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
                    'Quản lý Nhóm hàng',
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
                                  icon: const Icon(Icons.edit,
                                      color: Colors.blue, size: 25),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _showEditGroupDialog(group);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.red, size: 25),
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

  void _showEditGroupDialog(ProductGroupModel group) {
    final nameController = TextEditingController(text: group.name);
    final sttController = TextEditingController(text: group.stt.toString());
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cập nhật Nhóm hàng'),
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
                final navigator = Navigator.of(context);
                final toastService = ToastService();

                if (formKey.currentState!.validate()) {
                  try {
                    await _firestoreService.updateProductGroup(
                      group.id,
                      nameController.text.trim(),
                      int.parse(sttController.text),
                    );
                    toastService.show(
                        message: 'Cập nhật thành công',
                        type: ToastType.success);
                    _refreshData();
                    navigator.pop();
                  } catch (e) {
                    toastService.show(
                        message: 'Lỗi: $e', type: ToastType.error);
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

  Future<void> _confirmDeleteGroup(ProductGroupModel group) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Bạn có chắc muốn xóa nhóm "${group.name}" không?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              final navigator = Navigator.of(context);
              final toastService = ToastService();

              try {
                await _firestoreService.deleteProductGroup(
                  group.id,
                  group.name,
                  widget.currentUser.storeId,
                );
                toastService.show(
                    message: 'Xóa nhóm thành công.', type: ToastType.success);
                _refreshData();
                navigator.pop();
              } catch (e) {
                String errorMessage = e.toString();
                if (errorMessage.startsWith("Exception: ")) {
                  errorMessage = errorMessage.substring(11);
                }
                toastService.show(message: errorMessage, type: ToastType.error);
                navigator.pop();
              }
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _openImportExportScreen() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ProductImportExportScreen(
          currentUser: widget.currentUser,
        ),
      ),
    );
    _refreshData();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ProductGroupModel>>(
      future: _productGroupsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(title: const Text('Danh sách sản phẩm')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            appBar: AppBar(title: const Text('Danh sách sản phẩm')),
            body: Center(child: Text('Đã có lỗi xảy ra: ${snapshot.error}')),
          );
        }

        final productGroups = snapshot.data ?? [];
        // --- SỬA: THÊM NHÓM 'Khác' VÀO CUỐI ---
        final groupNames = ['Tất cả', ...productGroups.map((g) => g.name), 'Khác'];
        // --------------------------------------

        return DefaultTabController(
          length: groupNames.length,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Danh sách sản phẩm'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_sharp, size: 30),
                  color: AppTheme.primaryColor,
                  onPressed: () => _showSearchDialog(productGroups),
                  tooltip: 'Tìm kiếm',
                ),
                if (_canImportExport)
                IconButton(
                  icon: const Icon(Icons.import_export, size: 30),
                  color: AppTheme.primaryColor,
                  onPressed: _openImportExportScreen,
                  tooltip: 'Nhập/Xuất file Excel',
                ),
                if (_canAddProduct)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outlined, size: 30),
                    color: AppTheme.primaryColor,
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (context) => AddEditProductScreen(
                              currentUser: widget.currentUser,
                              productGroups: productGroups,
                            )),
                      );
                      _refreshData();
                    },
                    tooltip: 'Thêm mới sản phẩm',
                  ),
                if (_canManageGroups)
                  Padding(
                    padding: const EdgeInsets.only(right: 4.0),
                    child: IconButton(
                      icon: const Icon(Icons.settings, size: 30),
                      color: AppTheme.primaryColor,
                      onPressed: () {
                        if (productGroups.isNotEmpty) {
                          _showGroupManagementSheet(productGroups);
                        } else {
                          ToastService().show(
                              message: 'Chưa có nhóm nào được tạo.',
                              type: ToastType.warning);
                        }
                      },
                      tooltip: 'Quản lý nhóm',
                    ),
                  ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabs: groupNames.map((name) => Tab(text: name)).toList(),
              ),
            ),
            body: TabBarView(
              children: groupNames.map((name) {
                return _buildProductListForGroup(name, productGroups);
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  // --- SỬA: Logic lọc sản phẩm cho tab 'Khác' ---
  Widget _buildProductListForGroup(
      String tabName, List<ProductGroupModel> productGroups) {

    // Nếu là 'Tất cả' hoặc 'Khác' thì lấy toàn bộ danh sách về trước (queryGroup = null)
    // Nếu là nhóm cụ thể thì query theo tên nhóm
    String? queryGroup;
    if (tabName != 'Tất cả' && tabName != 'Khác') {
      queryGroup = tabName;
    }

    return StreamBuilder<List<ProductModel>>(
      stream: _firestoreService.getProductsStream(widget.currentUser.storeId,
          group: queryGroup),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Đã có lỗi xảy ra: ${snapshot.error}'));
        }

        // Lấy dữ liệu
        var products = snapshot.data ?? [];

        // Nếu là tab 'Khác', lọc Client-side các sản phẩm không có nhóm
        if (tabName == 'Khác') {
          products = products.where((p) => p.productGroup == null || p.productGroup!.trim().isEmpty).toList();
        }

        if (products.isEmpty) {
          return const Center(
              child: Text('Chưa có sản phẩm nào trong nhóm này.'));
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return _ProductListItem(
              product: product,
              productGroups: productGroups,
              currentUser: widget.currentUser,
              onRefresh: _refreshData,
              canEdit: _canEditProduct,
              canViewCost: _canViewCost,
            );
          },
        );
      },
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final ProductModel product;
  final List<ProductGroupModel> productGroups;
  final UserModel currentUser;
  final VoidCallback onRefresh;
  final bool canEdit;
  final bool canViewCost;

  const _ProductListItem({
    required this.product,
    required this.productGroups,
    required this.currentUser,
    required this.onRefresh,
    required this.canEdit,
    required this.canViewCost,
  });

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat('#,##0.####', 'vi_VN');
    final textTheme = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: () async {
          if (canEdit) {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => AddEditProductScreen(
                  currentUser: currentUser,
                  productToEdit: product,
                  productGroups: productGroups,
                ),
              ),
            );
            onRefresh();
          } else {
            ToastService().show(
                message: 'Bạn chưa được cấp quyền sử dụng tính năng này.',
                type: ToastType.warning);
          }
        },
        borderRadius: BorderRadius.circular(12.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildProductImage(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.productName,
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textColor,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(children: [
                      const Icon(Icons.qr_code_scanner,
                          size: 16, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        product.productCode ?? 'Không có mã',
                        style: textTheme.bodyMedium,
                      ),
                    ]),
                    Row(children: [
                      if (product.sellPrice > 0) ...[
                        Row(
                          children: [
                            const Icon(Icons.attach_money,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              numberFormat.format(product.sellPrice),
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 8),
                      if (product.costPrice > 0 && canViewCost) ...[
                        Row(
                          children: [
                            const Icon(Icons.money_off,
                                size: 16, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              numberFormat.format(product.costPrice),
                              style: textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ],
                    ]),
                    Row(
                      children: [
                        if (product.unit != null &&
                            product.unit!.isNotEmpty) ...[
                          const Icon(Icons.straighten_outlined,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(product.unit!, style: textTheme.bodyMedium),
                        ],
                        if (product.productType != 'Thành phẩm/Combo' &&
                            product.productType != 'Dịch vụ/Tính giờ' &&
                            product.productType != 'Topping/Bán kèm') ...[
                          const SizedBox(width: 12),
                          const Icon(Icons.inventory_2_outlined,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text(
                            numberFormat.format(product.stock),
                            style: textTheme.bodyMedium,
                          ),
                        ],
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

  Widget _buildProductImage() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 90,
        height: 90,
        child: (product.imageUrl != null && product.imageUrl!.isNotEmpty)
            ? CachedNetworkImage(
          imageUrl: product.imageUrl!,
          fit: BoxFit.cover,
          placeholder: (context, url) =>
              Container(color: Colors.grey.shade200),
          errorWidget: (context, url, error) => const Icon(
            Icons.image_not_supported_outlined,
            color: Colors.grey,
          ),
        )
            : const Icon(Icons.inventory_2_outlined,
            color: Colors.grey, size: 40),
      ),
    );
  }
}