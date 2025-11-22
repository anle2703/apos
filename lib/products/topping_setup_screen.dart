import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../../models/user_model.dart';
import '../../models/ingredient_model.dart';
import '../../models/product_model.dart';
import '../../theme/app_theme.dart';
import '../../widgets/product_search_delegate.dart';
import '../../theme/number_utils.dart';
import '../../widgets/custom_text_form_field.dart';

class ToppingSetupScreen extends StatefulWidget {
  final UserModel currentUser;
  final List<SelectedIngredient> initialAccompanyingItems;
  final List<SelectedIngredient> initialRecipeItems;
  final String? productType;
  final List<ProductModel> initialParentProducts;

  const ToppingSetupScreen({
    super.key,
    required this.currentUser,
    required this.initialAccompanyingItems,
    required this.initialRecipeItems,
    this.productType,
    required this.initialParentProducts,
  });

  @override
  State<ToppingSetupScreen> createState() => _ToppingSetupScreenState();
}

class _ToppingSetupScreenState extends State<ToppingSetupScreen> {
  late List<SelectedIngredient> _accompanyingItems;
  late List<SelectedIngredient> _recipeItems;
  late List<ProductModel> _selectedParentProducts;

  @override
  void initState() {
    super.initState();
    _accompanyingItems = List.from(widget.initialAccompanyingItems);
    _recipeItems = widget.initialRecipeItems
        .map((e) => SelectedIngredient(
        product: e.product,
        quantity: e.quantity,
        selectedUnit: e.selectedUnit))
        .toList();
    _selectedParentProducts = List.from(widget.initialParentProducts);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(context).pop({
            'accompanying': _accompanyingItems,
            'recipe': _recipeItems,
            'parentProducts': _selectedParentProducts,
          });
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Thiết lập Topping'),
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Sản phẩm áp dụng'),
                Tab(text: 'Định lượng (Công thức)'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _ParentProductTab(
                currentUser: widget.currentUser,
                selectedProducts: _selectedParentProducts,
                onProductsUpdated: (updatedList) {
                  setState(() => _selectedParentProducts = updatedList);
                },
              ),
              _RecipeTab(
                currentUser: widget.currentUser,
                selectedItems: _recipeItems,
                onItemsUpdated: (updatedList) {
                  setState(() => _recipeItems = updatedList);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeTab extends StatelessWidget {
  final UserModel currentUser;
  final List<SelectedIngredient> selectedItems;
  final ValueChanged<List<SelectedIngredient>> onItemsUpdated;

  const _RecipeTab({
    required this.currentUser,
    required this.selectedItems,
    required this.onItemsUpdated,
  });

  Future<void> _showProductSelectionDialog(BuildContext context) async {
    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: currentUser,
      allowedProductTypes: ['Nguyên liệu', 'Vật liệu'],
      previouslySelected: selectedItems.map((e) => e.product).toList(),
      groupByCategory: true,
    );

    if (result != null) {
      final newList = result.map((product) {
        // Giữ lại thông tin cũ nếu đã chọn, nếu mới thì tạo mới
        final existingItem = selectedItems.firstWhere(
              (item) => item.product.id == product.id,
          orElse: () => SelectedIngredient(
              product: product, selectedUnit: product.unit ?? 'Trống'),
        );
        return existingItem;
      }).toList();
      onItemsUpdated(newList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: selectedItems.isEmpty
          ? const Center(
          child: Text(
            'Chưa có định lượng.\nNhấn + để thêm Nguyên liệu/Vật liệu.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ))
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: selectedItems.length,
        itemBuilder: (context, index) {
          return _SelectedItemCard(
            key: ValueKey(selectedItems[index].id),
            ingredient: selectedItems[index],
            onDelete: () {
              final updatedList =
              List<SelectedIngredient>.from(selectedItems)
                ..removeAt(index);
              onItemsUpdated(updatedList);
            },
          );
        },
      ),
      floatingActionButton: IconButton(
        icon: const Icon(Icons.add_circle),
        iconSize: 40.0, // Icon to giống file mẫu
        color: AppTheme.primaryColor,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onPressed: () => _showProductSelectionDialog(context),
      ),
    );
  }
}

class _SelectedItemCard extends StatefulWidget {
  final SelectedIngredient ingredient;
  final VoidCallback onDelete;

  const _SelectedItemCard({
    super.key,
    required this.ingredient,
    required this.onDelete,
  });

  @override
  State<_SelectedItemCard> createState() => _SelectedItemCardState();
}

class _SelectedItemCardState extends State<_SelectedItemCard> {
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    _quantityController =
        TextEditingController(text: formatNumber(widget.ingredient.quantity));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _updateQuantity(double change) {
    double currentQuantity = parseVN(_quantityController.text);
    double newQuantity = currentQuantity + change;
    if (newQuantity < 0) newQuantity = 0;

    setState(() {
      widget.ingredient.quantity = newQuantity;
      _quantityController.text = formatNumber(newQuantity);
      _quantityController.selection = TextSelection.fromPosition(
          TextPosition(offset: _quantityController.text.length));
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).primaryColor;

    // Lấy danh sách đơn vị tính
    List<String> units = [widget.ingredient.product.unit ?? 'Trống'];
    if (widget.ingredient.product.additionalUnits.isNotEmpty) {
      units.addAll(widget.ingredient.product.additionalUnits
          .map((u) => u['unitName'] as String));
    }

    // Đảm bảo unit được chọn hợp lệ
    if (!units.contains(widget.ingredient.selectedUnit)) {
      widget.ingredient.selectedUnit = units.first;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Sử dụng Responsive layout tương tự AddIngredientsScreen
            return _buildResponsiveLayout(units, textTheme, primaryColor);
          },
        ),
      ),
    );
  }

  Widget _buildResponsiveLayout(
      List<String> units, TextTheme textTheme, Color primaryColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width > 750) {
          // Desktop / Tablet ngang
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _buildProductInfo(textTheme),
                ),
              ),
              const SizedBox(width: 16),
              _buildUnitDropdown(units, textTheme, primaryColor),
              const SizedBox(width: 16),
              _buildQuantityInput(textTheme),
              const SizedBox(width: 16),
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: widget.onDelete,
              ),
            ],
          );
        } else if (width > 450) {
          // Tablet dọc / Màn hình vừa
          return Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _buildProductInfo(textTheme),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildUnitDropdown(units, textTheme, primaryColor),
                  const SizedBox(width: 16),
                  _buildQuantityInput(textTheme),
                ],
              ),
            ],
          );
        } else {
          // Mobile
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: _buildProductInfo(textTheme),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: widget.onDelete,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildUnitDropdown(units, textTheme, primaryColor),
              const SizedBox(height: 8),
              _buildQuantityInput(textTheme),
            ],
          );
        }
      },
    );
  }

  Widget _buildProductInfo(TextTheme textTheme) {
    final product = widget.ingredient.product;
    final infoStyle =
    textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.productName,
            style: textTheme.titleMedium
                ?.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 16.0,
          runSpacing: 4.0,
          children: [
            if (product.stock > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(formatNumber(product.stock), style: infoStyle),
                ],
              ),
            if (product.costPrice > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.money_off, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(formatNumber(product.costPrice), style: infoStyle),
                ],
              ),
          ],
        )
      ],
    );
  }

  Widget _buildUnitDropdown(
      List<String> units, TextTheme textTheme, Color primaryColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Đơn vị: ',
            style: textTheme.titleMedium?.copyWith(color: Colors.black)),
        const SizedBox(width: 8),
        SizedBox(
          height: 40.0,
          width: 150,
          child: DropdownButtonHideUnderline(
            child: DropdownButton2<String>(
              isExpanded: true,
              value: widget.ingredient.selectedUnit,
              buttonStyleData: ButtonStyleData(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                  color: Colors.white,
                ),
              ),
              dropdownStyleData: DropdownStyleData(
                maxHeight: 200,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              menuItemStyleData: const MenuItemStyleData(
                height: 40,
              ),
              items: units
                  .map((u) => DropdownMenuItem(
                  value: u,
                  child: Text(u, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => widget.ingredient.selectedUnit = value);
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuantityInput(TextTheme textTheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Trừ tồn:',
            style: textTheme.titleMedium?.copyWith(color: Colors.black)),
        const SizedBox(width: 8),
        Container(
          height: 40.0,
          width: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.0),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove, size: 20, color: Colors.red),
                onPressed: () => _updateQuantity(-1),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 35),
              ),
              Expanded(
                child: CustomTextFormField(
                  controller: _quantityController,
                  textAlign: TextAlign.center,
                  keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [ThousandDecimalInputFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    widget.ingredient.quantity = parseVN(value);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add,
                    size: 20, color: AppTheme.primaryColor),
                onPressed: () => _updateQuantity(1),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ParentProductTab extends StatelessWidget {
  final UserModel currentUser;
  final List<ProductModel> selectedProducts;
  final ValueChanged<List<ProductModel>> onProductsUpdated;

  const _ParentProductTab({
    required this.currentUser,
    required this.selectedProducts,
    required this.onProductsUpdated,
  });

  Future<void> _showParentProductSelection(BuildContext context) async {
    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: currentUser,
      previouslySelected: selectedProducts,
      allowedProductTypes: ['Thành phẩm/Combo'],
      groupByCategory: true,
    );

    if (result != null) {
      onProductsUpdated(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: selectedProducts.isEmpty
          ? const Center(
        child: Text(
          'Topping này chưa được gán cho sản phẩm nào.\nNhấn + để chọn sản phẩm áp dụng.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: selectedProducts.length,
        itemBuilder: (context, index) {
          final product = selectedProducts[index];
          return Card(
            child: ListTile(
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: _buildImageSafe(product.imageUrl),
              ),
              title: Text(product.productName,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(product.productCode ?? 'Chưa có mã'),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  final updatedList =
                  List<ProductModel>.from(selectedProducts)
                    ..removeAt(index);
                  onProductsUpdated(updatedList);
                },
              ),
            ),
          );
        },
      ),
      floatingActionButton: IconButton(
        icon: const Icon(Icons.add_circle),
        iconSize: 40.0,
        color: AppTheme.primaryColor,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        onPressed: () => _showParentProductSelection(context),
      ),
    );
  }

  Widget _buildImageSafe(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        color: Colors.grey[200],
        width: 40,
        height: 40,
        child: const Icon(Icons.local_pizza, size: 20, color: Colors.grey),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: 40,
      height: 40,
      fit: BoxFit.cover,
      errorWidget: (context, url, error) => Container(
        color: Colors.grey[200],
        child: const Icon(Icons.error, size: 20),
      ),
    );
  }
}