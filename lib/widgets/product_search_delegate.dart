import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/product_group_model.dart';
import '../models/user_model.dart';
import '../services/firestore_service.dart';
import '../../theme/app_theme.dart';
import '../products/barcode_scanner_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/number_utils.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;

class ProductSearchScreen {
  static Future<ProductModel?> showSingleSelect({
    required BuildContext context,
    required UserModel currentUser,
    List<String>? allowedProductTypes,
  }) async {
    return await Navigator.of(context).push<ProductModel>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _ProductSearchContent(
          currentUser: currentUser,
          allowedProductTypes: allowedProductTypes,
          isMultiSelect: false,
          groupByCategory: false,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.ease;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }

  static Future<List<ProductModel>?> showMultiSelect({
    required BuildContext context,
    required UserModel currentUser,
    List<ProductModel> previouslySelected = const [],
    List<String>? allowedProductTypes,
    bool groupByCategory = false,
  }) async {
    return await Navigator.of(context).push<List<ProductModel>>(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => _ProductSearchContent(
          currentUser: currentUser,
          allowedProductTypes: allowedProductTypes,
          isMultiSelect: true,
          previouslySelected: previouslySelected,
          groupByCategory: groupByCategory,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.ease;
          var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    );
  }
}

class _ProductSearchContent extends StatefulWidget {
  final UserModel currentUser;
  final List<String>? allowedProductTypes;
  final bool isMultiSelect;
  final List<ProductModel> previouslySelected;
  final bool groupByCategory;

  const _ProductSearchContent({
    required this.currentUser,
    this.allowedProductTypes,
    required this.isMultiSelect,
    this.previouslySelected = const [],
    this.groupByCategory = false,
  });

  @override
  State<_ProductSearchContent> createState() => _ProductSearchContentState();
}

class _ProductSearchContentState extends State<_ProductSearchContent> {
  final FirestoreService _firestoreService = FirestoreService();
  final _searchController = TextEditingController();
  late List<ProductModel> _tempSelectedItems;
  List<ProductModel> _allProducts = [];
  List<ProductGroupModel> _allGroups = [];
  bool _isLoading = true;
  int? _lastTabIndex;
  DateTime? _lastTabTapAt;

  @override
  void initState() {
    super.initState();
    _tempSelectedItems = List.from(widget.previouslySelected);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    try {
      final results = await Future.wait([
        _firestoreService.getAllProductsStream(widget.currentUser.storeId).first,
        if (widget.groupByCategory)
          _firestoreService.getProductGroups(widget.currentUser.storeId)
        else
          Future.value(<ProductGroupModel>[])
      ]);

      if (mounted) {
        setState(() {
          _allProducts = results[0] as List<ProductModel>;
          _allGroups = results[1] as List<ProductGroupModel>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final barcodeScanRes = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const BarcodeScannerScreen(),
      ),
    );
    if (!mounted) return;
    if (barcodeScanRes != null) {
      _searchController.text = barcodeScanRes;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // ✅ SỬA ĐỔI 1: Thay đổi tiêu đề
        title: Text(widget.isMultiSelect ? 'Chọn sản phẩm' : 'Tìm sản phẩm'),
        actions: [
          if (widget.isMultiSelect)
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(_tempSelectedItems),
                child: const Text('Xác nhận'),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, child) {
                return TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Bấm nhanh 2 lần vào tên nhóm để chọn tất cả',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12.0),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    suffixIcon: value.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20, color: AppTheme.primaryColor),
                            onPressed: () => _searchController.clear(),
                          )
                        : ((defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)
                            ? IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor),
                                onPressed: _scanBarcode,
                              )
                            : null),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : (_allProducts.isEmpty
                    ? const Center(child: Text('Không có sản phẩm nào.'))
                    : ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _searchController,
                        builder: (context, value, child) {
                          final filteredProducts = _getFilteredProducts();

                          return widget.groupByCategory
                              ? _buildTabbedProductList(filteredProducts)
                              : _buildFlatProductList(filteredProducts);
                        },
                      )),
          ),
        ],
      ),
    );
  }

  List<ProductModel> _getFilteredProducts() {
    final searchQuery = _searchController.text.toLowerCase().trim();

    return _allProducts.where((product) {
      final typeFilterPassed = widget.allowedProductTypes == null ||
          widget.allowedProductTypes!.isEmpty ||
          (product.productType != null && widget.allowedProductTypes!.contains(product.productType));
      if (!typeFilterPassed) return false;

      if (searchQuery.isEmpty) return true;

      final nameMatches = product.productName.toLowerCase().contains(searchQuery);

      final codeMatches = product.productCode?.toLowerCase().contains(searchQuery) ?? false;

      final barcodeMatches = product.additionalBarcodes.any(
        (barcode) => barcode.toLowerCase().contains(searchQuery),
      );

      return nameMatches || codeMatches || barcodeMatches;
    }).toList();
  }

  // ✅ SỬA ĐỔI 2.1: Hàm xử lý logic double-tap
  void _handleTabDoubleTap(String tabName) {
    if (!widget.isMultiSelect) return;

    final filteredProducts = _getFilteredProducts();
    final productsForTab =
        (tabName == 'Tất cả') ? filteredProducts : filteredProducts.where((p) => p.productGroup == tabName).toList();

    if (productsForTab.isEmpty) return;

    final bool allSelected = productsForTab.every((product) => _tempSelectedItems.any((selected) => selected.id == product.id));

    setState(() {
      if (allSelected) {
        for (var product in productsForTab) {
          _tempSelectedItems.removeWhere((item) => item.id == product.id);
        }
      } else {
        for (var product in productsForTab) {
          if (!_tempSelectedItems.any((item) => item.id == product.id)) {
            _tempSelectedItems.add(product);
          }
        }
      }
    });
  }

  Widget _buildFlatProductList(List<ProductModel> filteredProducts) {
    if (filteredProducts.isEmpty) {
      return Center(child: Text('Không tìm thấy kết quả cho "${_searchController.text}"'));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      itemCount: filteredProducts.length,
      itemBuilder: (context, index) {
        final product = filteredProducts[index];
        final isSelected = _tempSelectedItems.any((item) => item.id == product.id);
        return _buildUnifiedListItem(
          product: product,
          isSelected: isSelected,
        );
      },
    );
  }

  Widget _buildTabbedProductList(List<ProductModel> filteredProducts) {
    final Map<String, List<ProductModel>> groupedProducts = {};
    for (final product in filteredProducts) {
      final groupName = product.productGroup != null && product.productGroup!.isNotEmpty ? product.productGroup! : 'Khác';
      (groupedProducts[groupName] ??= []).add(product);
    }
    final List<ProductGroupModel> nonEmptyGroups = [];
    for (var group in _allGroups) {
      if (groupedProducts.containsKey(group.name)) {
        nonEmptyGroups.add(group);
      }
    }
    if (groupedProducts.containsKey('Khác')) {
      nonEmptyGroups.add(ProductGroupModel(id: 'Khác', name: 'Khác', stt: 9999));
    }
    nonEmptyGroups.sort((a, b) => a.stt.compareTo(b.stt));
    final tabNames = ['Tất cả', ...nonEmptyGroups.map((g) => g.name)];

    return DefaultTabController(
      length: tabNames.length,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            onTap: (index) {
              final now = DateTime.now();
              final sameTab = (_lastTabIndex == index);
              final isDouble =
                  sameTab && _lastTabTapAt != null && now.difference(_lastTabTapAt!) < const Duration(milliseconds: 300);

              if (isDouble) {
                _handleTabDoubleTap(tabNames[index]);
              }

              _lastTabIndex = index;
              _lastTabTapAt = now;
            },
            tabs: tabNames.map((name) => Tab(text: name)).toList(),
          ),
          Expanded(
            child: TabBarView(
              children: tabNames.map((tabName) {
                final productsForTab = (tabName == 'Tất cả') ? filteredProducts : groupedProducts[tabName] ?? [];
                if (productsForTab.isEmpty) {
                  return Center(
                    child: Text(tabName == 'Tất cả' ? 'Không tìm thấy kết quả phù hợp.' : 'Không có sản phẩm trong nhóm này.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  itemCount: productsForTab.length,
                  itemBuilder: (context, index) {
                    final product = productsForTab[index];
                    final isSelected = _tempSelectedItems.any((item) => item.id == product.id);
                    return _buildUnifiedListItem(product: product, isSelected: isSelected);
                  },
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnifiedListItem({
    required ProductModel product,
    required bool isSelected,
  }) {
    Widget leadingImage = SizedBox(
      width: 64,
      height: 64,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: product.imageUrl != null && product.imageUrl!.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: product.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(color: Colors.grey.shade200),
                errorWidget: (context, url, error) => const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
              )
            : const Icon(Icons.inventory_2_outlined, color: Colors.grey),
      ),
    );

    Widget productInfo() {
      final hasUnit = (product.unit != null && product.unit!.trim().isNotEmpty);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            product.productName,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.bold,
                ),
            maxLines: 2, // Giới hạn 2 dòng cho tên dài
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),

          // HÀNG 1: Mã sản phẩm & Tồn kho
          Row(
            children: [
              // Mã sản phẩm
              const Icon(Icons.qr_code_scanner, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Flexible(
                // Dùng Flexible để mã dài không bị lỗi
                child: Text(
                  product.productCode ?? '---',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              const SizedBox(width: 12), // Khoảng cách giữa Mã và Tồn

              // Tồn kho
              const Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                'Tồn: ${formatNumber(product.stock)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: product.stock <= 0 ? Colors.red : Colors.grey.shade700,
                    fontWeight: product.stock <= 0 ? FontWeight.bold : FontWeight.normal),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // HÀNG 2: Giá bán & ĐVT
          Row(
            children: [
              // Giá bán
              Text(
                formatNumber(product.sellPrice),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700, fontSize: 14),
              ),

              if (hasUnit) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.grey.shade300)),
                  child: Text(
                    product.unit!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade800),
                  ),
                )
              ]
            ],
          ),
        ],
      );
    }

    return InkWell(
      onTap: () {
        if (widget.isMultiSelect) {
          setState(() {
            if (isSelected) {
              _tempSelectedItems.removeWhere((item) => item.id == product.id);
            } else {
              _tempSelectedItems.add(product);
            }
          });
        } else {
          Navigator.of(context).pop(product);
        }
      },
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                leadingImage,
                const SizedBox(width: 12),
                Expanded(child: productInfo()),
                if (widget.isMultiSelect)
                  Checkbox(
                    value: isSelected,
                    onChanged: (bool? value) {
                      setState(() {
                        if (value == true) {
                          if (!_tempSelectedItems.any((item) => item.id == product.id)) {
                            _tempSelectedItems.add(product);
                          }
                        } else {
                          _tempSelectedItems.removeWhere((item) => item.id == product.id);
                        }
                      });
                    },
                    activeColor: AppTheme.primaryColor,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
