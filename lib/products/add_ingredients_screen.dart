import 'package:flutter/material.dart';
import '../../models/ingredient_model.dart';
import '../../models/user_model.dart';
import 'package:dropdown_button2/dropdown_button2.dart';
import '../../widgets/product_search_delegate.dart';
import '../../theme/app_theme.dart';
import '../../theme/number_utils.dart';
import '../../widgets/custom_text_form_field.dart';

class AddIngredientsScreen extends StatefulWidget {
  final UserModel currentUser;
  final List<SelectedIngredient> initialAccompanyingItems;
  final List<SelectedIngredient> initialRecipeItems;
  final String? productType;

  const AddIngredientsScreen({
    super.key,
    required this.currentUser,
    required this.initialAccompanyingItems,
    required this.initialRecipeItems,
    this.productType,
  });

  @override
  State<AddIngredientsScreen> createState() => _AddIngredientsScreenState();
}

class _AddIngredientsScreenState extends State<AddIngredientsScreen> {
  late List<SelectedIngredient> _accompanyingItems;
  late List<SelectedIngredient> _recipeItems;

  @override
  void initState() {
    super.initState();
    _accompanyingItems = widget.initialAccompanyingItems
        .map((e) => SelectedIngredient(
            product: e.product,
            quantity: e.quantity,
            selectedUnit: e.selectedUnit))
        .toList();
    _recipeItems = widget.initialRecipeItems
        .map((e) => SelectedIngredient(
            product: e.product,
            quantity: e.quantity,
            selectedUnit: e.selectedUnit))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final bool isEditingToppingRecipe = widget.productType == 'Topping/Bán kèm';

    if (isEditingToppingRecipe) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(context).pop({
            'accompanying': <SelectedIngredient>[],
            'recipe': _recipeItems,
          });
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Định lượng'),
            actions: [],
          ),
          body: _IngredientTab(
            currentUser: widget.currentUser,
            allowedProductTypes: const [
              'Nguyên liệu',
            ],
            isRecipeTab: true,
            selectedItems: _recipeItems,
            onItemsUpdated: (updatedList) {
              setState(() => _recipeItems = updatedList);
            },
          ),
        ),
      );
    }
    return DefaultTabController(
      length: 2,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (didPop) return;
          Navigator.of(context).pop({
            'accompanying': _accompanyingItems,
            'recipe': _recipeItems,
          });
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Thành phần'),
            actions: [
            ],
            bottom: const TabBar(
              tabs: [
                Tab(text: 'Topping/Bán kèm'),
                Tab(text: 'Thành phần/Định lượng'),
              ],
            ),
          ),
          body: TabBarView(
            children: [
              _IngredientTab(
                currentUser: widget.currentUser,
                allowedProductTypes: const ['Topping/Bán kèm'],
                isRecipeTab: false,
                selectedItems: _accompanyingItems,
                onItemsUpdated: (updatedList) {
                  setState(() => _accompanyingItems = updatedList);
                },
              ),
              _IngredientTab(
                currentUser: widget.currentUser,
                allowedProductTypes: const [
                  'Hàng hóa',
                  'Thành phẩm/Combo',
                  'Nguyên liệu',
                  'Vật liệu'
                ],
                isRecipeTab: true,
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

class _IngredientTab extends StatelessWidget {
  final UserModel currentUser;
  final List<String> allowedProductTypes;
  final bool isRecipeTab;
  final List<SelectedIngredient> selectedItems;
  final ValueChanged<List<SelectedIngredient>> onItemsUpdated;

  const _IngredientTab({
    required this.currentUser,
    required this.allowedProductTypes,
    required this.isRecipeTab,
    required this.selectedItems,
    required this.onItemsUpdated,
  });

  Future<void> _showProductSelectionDialog(BuildContext context) async {
    final result = await ProductSearchScreen.showMultiSelect(
      context: context,
      currentUser: currentUser,
      allowedProductTypes: allowedProductTypes,
      previouslySelected: selectedItems.map((e) => e.product).toList(),
      groupByCategory: isRecipeTab,
    );

    if (result != null) {
      final newList = result.map((product) {
        final existingItem = selectedItems.firstWhere(
          (item) => item.product.id == product.id,
          orElse: () => SelectedIngredient(
              product: product, selectedUnit: product.unit ?? 'Đơn vị'),
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
          ? const Center(child: Text('Chưa có sản phẩm nào. Nhấn + để thêm.'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: selectedItems.length,
              itemBuilder: (context, index) {
                return _SelectedItemCard(
                  key: ValueKey(selectedItems[index].id),
                  ingredient: selectedItems[index],
                  isRecipeTab: isRecipeTab,
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
        iconSize: 40.0,
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
  final bool isRecipeTab;
  final VoidCallback onDelete;

  const _SelectedItemCard(
      {super.key,
      required this.ingredient,
      required this.isRecipeTab,
      required this.onDelete});

  @override
  State<_SelectedItemCard> createState() => _SelectedItemCardState();
}

class _SelectedItemCardState extends State<_SelectedItemCard> {
  late TextEditingController _quantityController;

  @override
  void initState() {
    super.initState();
    // THAY ĐỔI: Dùng hàm formatNumber từ utils
    _quantityController =
        TextEditingController(text: formatNumber(widget.ingredient.quantity));
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  void _updateQuantity(double change) {
    // THAY ĐỔI: Dùng hàm parseVN từ utils
    double currentQuantity = parseVN(_quantityController.text);
    double newQuantity = currentQuantity + change;
    if (newQuantity < 0) newQuantity = 0;

    setState(() {
      widget.ingredient.quantity = newQuantity;
      // THAY ĐỔI: Dùng hàm formatNumber từ utils
      _quantityController.text = formatNumber(newQuantity);
      _quantityController.selection = TextSelection.fromPosition(
          TextPosition(offset: _quantityController.text.length));
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).primaryColor;

    List<String> units = [widget.ingredient.product.unit ?? 'Đơn vị'];
    if (widget.ingredient.product.additionalUnits.isNotEmpty) {
      units.addAll(widget.ingredient.product.additionalUnits
          .map((u) => u['unitName'] as String));
    }

    if (!units.contains(widget.ingredient.selectedUnit)) {
      widget.ingredient.selectedUnit = units.first;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: widget.isRecipeTab
            ? LayoutBuilder(builder: (context, constraints) {
                return _buildResponsiveLayout(units, textTheme, primaryColor);
              })
            : _buildAccompanyingLayout(textTheme),
      ),
    );
  }

  Widget _buildAccompanyingLayout(TextTheme textTheme) {
    return Row(
      children: [
        Expanded(child: _buildProductInfo(textTheme)),
        IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: widget.onDelete),
      ],
    );
  }

  Widget _buildResponsiveLayout(
      List<String> units, TextTheme textTheme, Color primaryColor) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        if (width > 750) {
          // 🔹 Mức 1: đủ rộng (desktop, tablet ngang)
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
          // 🔹 Mức 2: trung bình
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
          // 🔹 Mức 3: hẹp (mobile nhỏ)
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
                  Icon(Icons.inventory_2_outlined,
                      size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(formatNumber(product.stock), style: infoStyle),
                ],
              ),
            if (product.sellPrice > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.attach_money, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(formatNumber(product.sellPrice), style: infoStyle),
                ],
              ),
            if (product.costPrice > 0)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.money_off, size: 16, color: Colors.grey),
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
                icon: const Icon(
                  Icons.remove,
                  size: 20,
                  color: Colors.red,
                ),
                onPressed: () => _updateQuantity(-1),
                splashRadius: 20,
              ),
              Expanded(
                child: CustomTextFormField(
                  controller: _quantityController,
                  textAlign: TextAlign.center,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  // THAY ĐỔI: Dùng formatter mới từ utils
                  inputFormatters: [ThousandDecimalInputFormatter()],
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
                  onChanged: (value) {
                    // THAY ĐỔI: Dùng hàm parseVN từ utils
                    widget.ingredient.quantity = parseVN(value);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.add,
                  size: 20,
                  color: AppTheme.primaryColor,
                ),
                onPressed: () => _updateQuantity(1),
                splashRadius: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
