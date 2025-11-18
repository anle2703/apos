import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dropdown.dart';
import 'barcode_scanner_screen.dart';
import 'add_units_screen.dart';
import '../../models/unit_model.dart';
import 'add_ingredients_screen.dart';
import '../../models/ingredient_model.dart';
import '../../services/storage_service.dart';
import '../../models/product_model.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../models/service_setup_model.dart';
import '../../models/product_group_model.dart';
import 'service_setup_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../theme/number_utils.dart';

class AddEditProductScreen extends StatefulWidget {
  final UserModel currentUser;
  final ProductModel? productToEdit;
  final List<ProductGroupModel> productGroups;

  const AddEditProductScreen({
    super.key,
    required this.currentUser,
    this.productToEdit,
    required this.productGroups,
  });

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final _productCodeController = TextEditingController();
  final _productNameController = TextEditingController();
  final _sellPriceController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _unitController = TextEditingController();
  final _stockController = TextEditingController();
  final _minStockController = TextEditingController();
  final _storageService = StorageService();

  List<UnitModel> _additionalUnits = [];
  List<SelectedIngredient> _accompanyingItems = [];
  List<SelectedIngredient> _recipeItems = [];
  List<String> _selectedPrinters = [];
  List<String> _additionalBarcodes = [];

  late List<ProductGroupModel> _productGroups;

  ServiceSetupModel? _serviceSetup;
  String? _existingImageUrl;
  String? _selectedProductType;
  String? _selectedProductGroup;

  bool get _isEditMode => widget.productToEdit != null;
  bool get _shouldShowPrinterSelector {
    if (widget.currentUser.businessType != 'fnb') {
      return false;
    }
    final isExcludedType = _selectedProductType == 'Nguyên liệu' ||
        _selectedProductType == 'Vật liệu';
    return !isExcludedType;
  }
  bool _isCumulativeCostPrice = false;
  bool _isLoading = false;

  bool _canEditIsVisible = false;
  bool _canEditCost = false;

  XFile? _imageXFile;
  bool _isVisibleInMenu = true;
  bool _manageStockSeparately = false;


  @override
  void initState() {
    super.initState();
    _productGroups = widget.productGroups;
    if (widget.currentUser.role == 'owner') {
      _canEditIsVisible = true;
      _canEditCost = true;
    } else {
      _canEditIsVisible = widget.currentUser.permissions?['products']?['canEditIsVisible'] ?? false;
      _canEditCost = widget.currentUser.permissions?['products']?['canEditCost'] ?? false;
    }
    if (_isEditMode && widget.productToEdit != null) {
      final product = widget.productToEdit!;
      _productCodeController.text = product.productCode ?? '';
      _productNameController.text = product.productName;
      _sellPriceController.text = numberFormat.format(product.sellPrice);
      _costPriceController.text = numberFormat.format(product.costPrice);
      _stockController.text = numberFormat.format(product.stock);
      _minStockController.text = numberFormat.format(product.minStock);
      _unitController.text = product.unit ?? '';
      _selectedProductType = product.productType;
      _selectedProductGroup = product.productGroup;
      _additionalBarcodes = product.additionalBarcodes;
      _selectedPrinters = List<String>.from(product.kitchenPrinters);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadIngredientData(product);
        }
      });
      _manageStockSeparately = product.manageStockSeparately;

      if (product.serviceSetup != null) {
        _serviceSetup = ServiceSetupModel.fromMap(product.serviceSetup!);
      } else {
        _serviceSetup = ServiceSetupModel();
      }
      _existingImageUrl = product.imageUrl;
      if (product.additionalUnits.isNotEmpty) {
        _additionalUnits = product.additionalUnits.map((unitData) {
          return UnitModel(
            id: unitData['id'],
            unitName: unitData['unitName'] ?? '',
            sellPrice: (unitData['sellPrice'] ?? 0).toDouble(),
            costPrice: (unitData['costPrice'] ?? 0).toDouble(),
            stock: (unitData['stock'] ?? 0).toDouble(),
            conversionFactor: (unitData['conversionFactor'] ?? 1.0).toDouble(),
          );
        }).toList();
      }
      _isVisibleInMenu = widget.productToEdit!.isVisibleInMenu;

    }else {
      _selectedPrinters = ['Máy in A'];
    _serviceSetup ??= ServiceSetupModel();
    }
  }

  @override
  void dispose() {
    _productCodeController.dispose();
    _productNameController.dispose();
    _sellPriceController.dispose();
    _costPriceController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _minStockController.dispose();

    super.dispose();
  }

  Future<void> _refreshGroups() async {
    final groups = await _firestoreService.getProductGroups(widget.currentUser.storeId, forceRefresh: true);
    if (mounted) {
      setState(() {
        _productGroups = groups;
      });
    }
  }

  double _calculateCumulativeCost() {
    if (_recipeItems.isEmpty) return 0.0;

    double totalCost = 0.0;
    for (var ingredient in _recipeItems) {
      double itemCost = 0.0;
      // Kiểm tra đơn vị được chọn có phải là đơn vị cơ bản không
      if (ingredient.selectedUnit == ingredient.product.unit) {
        itemCost = ingredient.product.costPrice;
      } else {
        // Tìm giá vốn từ danh sách đơn vị phụ
        final additionalUnit = ingredient.product.additionalUnits.firstWhere(
          (u) => u['unitName'] == ingredient.selectedUnit,
          orElse: () =>
              <String, dynamic>{}, // Trả về map rỗng nếu không tìm thấy
        );
        if (additionalUnit.isNotEmpty) {
          // Lấy giá vốn của đơn vị phụ
          itemCost = (additionalUnit['costPrice'] as num?)?.toDouble() ?? 0.0;
        }
      }
      totalCost += itemCost * ingredient.quantity;
    }
    return totalCost;
  }

  Future<String?> _scanBarcode() async {
    try {
      return await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (context) => const BarcodeScannerScreen()),
      );
    } on PlatformException {
      ToastService()
          .show(message: 'Không thể truy cập camera.', type: ToastType.error);
      return null;
    }
  }

  void _showCumulativeCostDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Tùy chọn giá vốn'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    title: const Text('Giá vốn cộng dồn'),
                    value: _isCumulativeCostPrice,
                    onChanged: (bool value) {
                      // Cập nhật UI của dialog
                      setStateInDialog(() => _isCumulativeCostPrice = value);
                      // Cập nhật UI của màn hình chính
                      setState(() {
                        _isCumulativeCostPrice = value;
                        if (_isCumulativeCostPrice) {
                          final cumulativeCost = _calculateCumulativeCost();
                          _costPriceController.text = formatNumber(cumulativeCost); // dùng formatNumber
                        } else {
                          _costPriceController.text = '0';
                        }

                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Giá vốn sẽ được tự động cộng dồn từ giá vốn của các thành phần thay vì nhập trực tiếp.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Đóng'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickImage() async {
    final pickedFile = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (pickedFile != null) {
      setState(() {
        _imageXFile = pickedFile;
      });
    }
  }

  Future<void> _showAddBarcodesDialog() async {
    List<TextEditingController> controllers =
    List.generate(3, (_) => TextEditingController());
    for (int i = 0; i < _additionalBarcodes.length && i < 3; i++) {
      controllers[i].text = _additionalBarcodes[i];
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateInDialog) {
            return AlertDialog(
              title: const Text('Thêm mã vạch phụ'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: CustomTextFormField(
                      controller: controllers[index],
                      decoration: InputDecoration(
                        labelText: 'Mã vạch ${index + 1}',
                        prefixIcon: IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: AppTheme.primaryColor),
                          onPressed: () async {
                            final code = await _scanBarcode();
                            if (code != null) {
                              setStateInDialog(() => controllers[index].text = code);
                            }
                          },
                        ),
                      ),
                    ),
                  );
                }),
              ),
              actions: <Widget>[
                TextButton(
                    child: const Text('Hủy'),
                    onPressed: () => Navigator.of(context).pop()),
                ElevatedButton(
                  child: const Text('Lưu'),
                  onPressed: () {
                    // Lọc ra các mã vạch hợp lệ (không trống)
                    final newBarcodes = controllers
                        .map((c) => c.text.trim())
                        .where((code) => code.isNotEmpty)
                        .toList();

                    setState(() {
                      _additionalBarcodes = newBarcodes;
                    });

                    Navigator.of(context).pop();
                    ToastService().show(
                      message: 'Đã lưu ${newBarcodes.length} mã vạch phụ',
                      type: ToastType.success,
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showAddUnitsDialog() async {
    final baseUnit = _unitController.text.trim();
    if (baseUnit.isEmpty) {
      ToastService().show(
        message: 'Hãy nhập đơn vị tính cơ bản trước.',
        type: ToastType.warning,
      );
      return;
    }

    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (context) => AddUnitsScreen(
          baseUnitName: baseUnit, // ✅ dùng đúng biến baseUnit ở trên
          productType: _selectedProductType,
          initialUnits: _additionalUnits,
          manageStockSeparately: _manageStockSeparately, // ✅ truyền vào
        ),
      ),
    );

    if (result != null) {
      setState(() {
        _additionalUnits =
        List<UnitModel>.from(result['units'] ?? []);
        _manageStockSeparately =
            result['manageStockSeparately'] ?? false;
      });

      ToastService().show(
        message: 'Đã cập nhật ${_additionalUnits.length} đơn vị tính phụ.',
        type: ToastType.success,
      );
    }
  }

  Future<void> _showAddGroupDialog(List<String> currentGroups) async {
    final newGroupController = TextEditingController();
    final navigator = Navigator.of(context);
    final toastService = ToastService();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm nhóm mới'),
        content: CustomTextFormField(
          controller: newGroupController,
          decoration: const InputDecoration(labelText: 'Tên nhóm'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => navigator.pop(),
              child: const Text('Hủy')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                minimumSize: Size.zero,
                padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            onPressed: () async {
              final newGroup = newGroupController.text.trim();
              if (newGroup.isNotEmpty && !currentGroups.contains(newGroup)) {

                // Bọc trong try-catch để xử lý lỗi
                try {
                  await _firestoreService.addProductGroup(newGroup, widget.currentUser.storeId);
                  await _refreshGroups();

                  if (mounted) {
                    setState(() {
                      _selectedProductGroup = newGroup;
                    });
                  }
                  navigator.pop(); // Chỉ pop khi thành công
                } catch (e) {
                  toastService.show(message: "Thêm nhóm thất bại: $e", type: ToastType.error);
                  // Không pop khi có lỗi để người dùng có thể thử lại
                }
              } else {
                toastService.show(
                    message: 'Tên nhóm không hợp lệ hoặc đã tồn tại.',
                    type: ToastType.warning);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> _showServiceSetupScreen() async {
    final result = await Navigator.of(context).push<ServiceSetupModel>(
      MaterialPageRoute(
        builder: (context) => ServiceSetupScreen(
          currentUser: widget.currentUser,
          // Truyền dữ liệu hiện tại vào màn hình mới
          initialSetup: _serviceSetup ?? ServiceSetupModel(),
        ),
      ),
    );

    // Nhận kết quả trả về sau khi người dùng nhấn Lưu
    if (result != null) {
      setState(() {
        _serviceSetup = result;
      });
      ToastService().show(message: 'Đã cập nhật thiết lập dịch vụ.', type: ToastType.success);
    }
  }

  Future<void> _saveProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final navigator = Navigator.of(context);
    final toastService = ToastService();

    setState(() => _isLoading = true);

    try {
      String productCodeFromController = _productCodeController.text.trim();
      String finalProductCode = productCodeFromController;

      if (!_isEditMode && productCodeFromController.isEmpty) {
        String prefix;
        switch (_selectedProductType) {
          case 'Hàng hóa':   prefix = 'HH'; break;
          case 'Thành phẩm/Combo': prefix = 'TP'; break;
          case 'Dịch vụ/Tính giờ':    prefix = 'DV'; break;
          case 'Topping/Bán kèm':    prefix = 'BK'; break;
          case 'Nguyên liệu': prefix = 'NL'; break;
          case 'Vật liệu':   prefix = 'VL'; break;
          default:           prefix = 'SP'; break;
        }
        finalProductCode = await _firestoreService.generateNextProductCode(
          widget.currentUser.storeId,
          prefix,
        );
      }

      if (productCodeFromController.isNotEmpty) {
        final isDuplicate = await _firestoreService.isProductCodeDuplicate(
          storeId: widget.currentUser.storeId,
          productCode: finalProductCode,
          // Nếu đang sửa, truyền ID sản phẩm hiện tại để loại trừ nó ra
          currentProductId: _isEditMode ? widget.productToEdit!.id : null,
        );

        if (isDuplicate) {
          toastService.show(
            message: 'Mã sản phẩm "$finalProductCode" đã tồn tại.',
            type: ToastType.error,
          );
          setState(() => _isLoading = false);
          return; // Dừng hàm tại đây nếu mã bị trùng
        }
      }

      String? imageUrl;
      // Ưu tiên 1: Nếu người dùng chọn ảnh mới, luôn dùng ảnh đó.
      if (_imageXFile != null) {
        final imageBytes = await _imageXFile!.readAsBytes();
        imageUrl = await _storageService.uploadStoreProductImage(
          imageBytes: imageBytes,
          storeId: widget.currentUser.storeId,
          fileName: finalProductCode,
        );
      }
      // Nếu không có ảnh mới được chọn, xử lý theo từng chế độ
      else {
        if (_isEditMode) {
          // CHỈNH SỬA
          // Nếu có ảnh cũ hợp lệ thì giữ lại
          if (widget.productToEdit?.imageUrl != null &&
              widget.productToEdit!.imageUrl!.trim().isNotEmpty) {
            imageUrl = widget.productToEdit!.imageUrl;
          } else {
            // Chỉnh sửa, nhưng CHƯA có ảnh -> Dùng logic TÌM KIẾM
            imageUrl = await _storageService.findMatchingSharedImage(
              _productNameController.text.trim(),
            );
          }
        } else {
          // THÊM MỚI -> Dùng logic TÌM KIẾM
          imageUrl = await _storageService.findMatchingSharedImage(
            _productNameController.text.trim(),
          );
        }
      }

      final manualCostPrice = parseVN(_costPriceController.text);
      final finalCostPrice = _isCumulativeCostPrice
          ? _calculateCumulativeCost()
          : manualCostPrice;

      List<Map<String, dynamic>> compiledMaterialsList = [];
      if (_selectedProductType == 'Thành phẩm/Combo' || _selectedProductType == 'Topping/Bán kèm') {
        compiledMaterialsList = await _compileMaterials(_recipeItems);
      }

      final Map<String, dynamic> productData = {
        'productName': _productNameController.text.trim(),
        'productCode': finalProductCode,
        'additionalBarcodes': _additionalBarcodes,
        'productType': _selectedProductType,
        'productGroup': _selectedProductGroup,
        'sellPrice': parseVN(_sellPriceController.text),
        'costPrice': finalCostPrice,
        'stock': parseVN(_stockController.text),
        'minStock': parseVN(_minStockController.text),
        'isCumulativeCostPrice': _isCumulativeCostPrice,
        'unit': _unitController.text.trim(),
        'kitchenPrinters': _selectedPrinters,
        'imageUrl': imageUrl,
        'storeId': widget.currentUser.storeId,
        'isVisibleInMenu': _isVisibleInMenu,
        'manageStockSeparately': _manageStockSeparately,
        'compiledMaterials': compiledMaterialsList,

      };

      productData['accompanyingItems'] = _accompanyingItems.map((item) => item.toMap()).toList();
      productData['recipeItems'] = _recipeItems.map((item) => item.toMap()).toList();

      productData['additionalUnits'] = _additionalUnits.map((unit) => {
        'id': unit.id,
        'unitName': unit.unitName,
        'sellPrice': unit.sellPrice,
        'costPrice': unit.costPrice,
        'stock': unit.stock,
        'conversionFactor': unit.conversionFactor,
      }).toList();

      productData['serviceSetup'] = _serviceSetup?.toMap();

      if (_isEditMode) {
        await _firestoreService.updateProduct(
          widget.productToEdit!.id, // luôn dùng id cũ
          productData,
        );
        toastService.show(message: 'Cập nhật sản phẩm thành công!', type: ToastType.success);
        navigator.pop();
      } else {
        productData['createdAt'] = FieldValue.serverTimestamp();
        productData['ownerUid'] = widget.currentUser.uid;
        await _firestoreService.addProduct(productData);
        toastService.show(message: 'Thêm mới sản phẩm thành công!', type: ToastType.success);
        navigator.pop();
      }
    } catch (e) {
      final action = _isEditMode ? 'Cập nhật' : 'Thêm';
      // Dùng biến đã lưu
      toastService.show(
        message: '$action sản phẩm thất bại: $e',
        type: ToastType.error,
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadIngredientData(ProductModel product) async {
    if (product.accompanyingItems.isEmpty && product.recipeItems.isEmpty) return;

    final allProductsStream = _firestoreService.getAllProductsStream(widget.currentUser.storeId);
    final allProducts = await allProductsStream.first;
    final productMap = {for (var p in allProducts) p.id: p};

    List<SelectedIngredient> mapToIngredients(List<dynamic> items) {
      final List<SelectedIngredient> result = [];
      for (var itemData in items) {
        final product = productMap[itemData['productId']];
        if (product != null) {
          result.add(SelectedIngredient(
            product: product,
            quantity: (itemData['quantity'] as num).toDouble(),
            selectedUnit: itemData['selectedUnit'],
          ));
        }
      }
      return result;
    }

    if (product.accompanyingItems.isNotEmpty) {
      _accompanyingItems = mapToIngredients(product.accompanyingItems);
    }
    if (product.recipeItems.isNotEmpty) {
      _recipeItems = mapToIngredients(product.recipeItems);
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<List<Map<String, dynamic>>> _compileMaterials(List<SelectedIngredient> recipeItems) async {
    final Map<String, double> compiledMap = {};
    for (final ingredient in recipeItems) {
      final ingredientProduct = ingredient.product;
      final ingredientQuantity = ingredient.quantity;
      double conversionFactor = 1.0;
      if (ingredient.selectedUnit != ingredientProduct.unit) {
        final unitData = ingredientProduct.additionalUnits
            .firstWhere((u) => u['unitName'] == ingredient.selectedUnit, orElse: () => {});
        conversionFactor = (unitData['conversionFactor'] as num?)?.toDouble() ?? 1.0;
      }
      final double baseQuantity = ingredientQuantity * conversionFactor;
      final productType = ingredientProduct.productType;
      if (productType == 'Hàng hóa' || productType == 'Nguyên liệu' || productType == 'Vật liệu') {
        final productId = ingredientProduct.id;
        compiledMap[productId] = (compiledMap[productId] ?? 0) + baseQuantity;
      } else {
        final childCompiledMaterials = ingredientProduct.compiledMaterials;
        for (final material in childCompiledMaterials) {
          final productId = material['productId'] as String;
          final quantityPerChild = (material['quantity'] as num?)?.toDouble() ?? 0.0;
          final totalMaterialQuantity = quantityPerChild * baseQuantity;
          compiledMap[productId] = (compiledMap[productId] ?? 0) + totalMaterialQuantity;
        }
      }
    }
    return compiledMap.entries.map((e) {
      return {'productId': e.key, 'quantity': e.value};
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.productToEdit == null ? 'Thêm mới' : 'Chỉnh sửa',
        ),
        actions: [
          if (_canEditIsVisible)
            Builder(
            builder: (context) {
              final bool isDesktop = Theme.of(context).platform == TargetPlatform.windows ||
                  Theme.of(context).platform == TargetPlatform.linux ||
                  Theme.of(context).platform == TargetPlatform.macOS;
              final bool isPosAndroid = false;
              final showText = isDesktop || isPosAndroid;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showText)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        'Cho phép bán',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.black),
                      ),
                    ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch.adaptive(
                      value: _isVisibleInMenu,
                      onChanged: (v) {
                        setState(() => _isVisibleInMenu = v);
                        ToastService().show(
                          message: v ? "Đã bật Cho phép bán" : "Không cho phép bán",
                          type: v ? ToastType.success : ToastType.warning,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 2),
                ],
              );
            },
          ),
          _isLoading
              ? const Padding(
            padding: EdgeInsets.only(top: 16.0, bottom: 16.0, left: 16.0, right: 8.0),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
          )
              : Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: IconButton(
              icon: const Icon(Icons.save, color: AppTheme.primaryColor, size: 25),
              onPressed: _saveProduct,
              tooltip: 'Lưu Hàng hóa',
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const double mobileBreakpoint = 700;
              bool isDesktop = constraints.maxWidth >= mobileBreakpoint;
              return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
            },
          ),
        ),
      ),
    );
  }

  Widget _buildImagePicker() {
    return Center(
      child: InkWell(
        onTap: _pickImage,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Builder(
              builder: (context) {
                // 1) Ảnh mới chọn
                if (_imageXFile != null) {
                  return Image.file(File(_imageXFile!.path), fit: BoxFit.cover);
                }

                // 2) Chế độ sửa và đã có ảnh riêng
                if (_isEditMode &&
                    _existingImageUrl != null &&
                    _existingImageUrl!.isNotEmpty) {
                  return CachedNetworkImage(
                    imageUrl: _existingImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) =>
                        Container(color: Colors.grey.shade200),
                    errorWidget: (context, url, error) =>
                    const Icon(Icons.image_not_supported_outlined,
                        color: Colors.grey),
                  );
                }

                // 3) Trường hợp còn lại (tạo mới, hoặc sửa mà chưa có ảnh riêng)
                // -> chỉ hiện placeholder, không check storage ở đây
                return const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_a_photo_outlined, color: Colors.grey),
                    SizedBox(height: 4),
                    Text('Chọn ảnh', style: TextStyle(fontSize: 12)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProductTypeDropdown() {
    return AppDropdown(
      value: _selectedProductType,
      labelText: 'Loại sản phẩm',
      prefixIcon: Icons.category_outlined,
      items: [
        'Hàng hóa',
        'Thành phẩm/Combo',
        'Dịch vụ/Tính giờ',
        'Topping/Bán kèm',
        'Nguyên liệu',
        'Vật liệu'
      ]
          .map((label) => DropdownMenuItem(
              value: label,
              child: Text(label, overflow: TextOverflow.ellipsis)))
          .toList(),
      onChanged: (value) {
        setState(() {
          _selectedProductType = value;
        });
      },
      validator: (value) => value == null ? 'Vui lòng chọn loại' : null,
    );
  }

  Widget _buildProductCodeField() {
    bool isGoods = _selectedProductType == 'Hàng hóa';
    void handleScan() async {
      final code = await _scanBarcode();
      if (code != null && mounted) {
        setState(() {
          _productCodeController.text = code;
        });
      }
    }

    Widget prefixIcon = IconButton(
      icon: Icon(
        Icons.qr_code_scanner,
        color: (Platform.isAndroid || Platform.isIOS)
            ? AppTheme.primaryColor
            : Colors.grey,
      ),
      onPressed: (Platform.isAndroid || Platform.isIOS) ? handleScan : null,
    );

    Widget? suffixIcon;
    if (isGoods) {
      suffixIcon = IconButton(
        icon: const Icon(Icons.add, color: AppTheme.primaryColor),
        onPressed: _showAddBarcodesDialog,
      );
    }

    return CustomTextFormField(
      controller: _productCodeController,
      decoration: InputDecoration(
        labelText: 'Mã sản phẩm (SKU)',
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildProductGroupDropdown() {
    final groups = _productGroups;
    final groupNames = groups.map((g) => g.name).toList();
    final String? dropdownValue = (_selectedProductGroup != null && _selectedProductGroup!.isEmpty)
        ? null
        : _selectedProductGroup;

    return AppDropdown(
      value: dropdownValue, // Sử dụng giá trị đã qua xử lý
      labelText: 'Nhóm sản phẩm',
      prefixIcon: Icons.folder_open_outlined,
      items: [
        ...groups.map((group) => DropdownMenuItem(
            value: group.name,
            child: Text(group.name, overflow: TextOverflow.ellipsis))),
        const DropdownMenuItem(
            value: 'add_new',
            child: Text('+ Thêm nhóm mới...',
                style: TextStyle(fontStyle: FontStyle.italic))),
      ],
      onChanged: (value) {
        if (value == 'add_new') {
          _showAddGroupDialog(groupNames);
        } else {
          setState(() => _selectedProductGroup = value);
        }
      },
    );
  }

  Widget _buildProductNameField() {
    return CustomTextFormField(
      controller: _productNameController,
      decoration: const InputDecoration(
          labelText: 'Tên sản phẩm', prefixIcon: Icon(Icons.label_outline)),
      validator: (value) => value!.isEmpty ? 'Không được để trống' : null,
    );
  }

  Widget _buildSellPriceField() {
    bool isSellPriceDisabled = _selectedProductType == 'Nguyên liệu' ||
        _selectedProductType == 'Vật liệu';

    if (isSellPriceDisabled) {
      return InkWell(
        onTap: () {
          ToastService().show(
              message: 'Nguyên liệu và Vật liệu không cần nhập giá bán.',
              type: ToastType.warning);
        },
        child: InputDecorator(
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.attach_money),
          ),
          child: Text(
            'K áp dụng',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey[600]),
          ),
        ),
      );
    }

    InputDecoration decoration = const InputDecoration(
      labelText: 'Giá bán',
      prefixIcon: Icon(Icons.attach_money),
    );

    if (_selectedProductType == 'Dịch vụ/Tính giờ' && _serviceSetup!.isTimeBased) {
      decoration = const InputDecoration(
        labelText: 'Giá bán/giờ',
        prefixIcon: Icon(Icons.attach_money),
      );
    }

    return CustomTextFormField(
      controller: _sellPriceController,
      decoration: decoration,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
    );
  }

  Widget _buildCostPriceField() {
    if (!_canEditCost) {
      return CustomTextFormField(
        decoration: const InputDecoration(
          labelText: 'Cần cấp quyền',
          prefixIcon: Icon(Icons.money_off),
          enabled: false,
        ),
      );
    }

    if (_selectedProductType == 'Thành phẩm/Combo') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTextFormField(
            controller: _costPriceController,
            decoration: InputDecoration(
              labelText: 'Giá vốn',
              prefixIcon: IconButton(
                // Giữ icon mặc định và đổi màu thành màu chính của app
                icon: const Icon(Icons.money_off, color: AppTheme.primaryColor),
                onPressed:
                    _showCumulativeCostDialog, // Vẫn giữ chức năng mở popup
                tooltip: 'Tùy chọn giá vốn cộng dồn',
              ),
            ),
            readOnly: _isCumulativeCostPrice,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [ThousandDecimalInputFormatter()],
            onTap: _isCumulativeCostPrice
                ? () => ToastService().show(
              message: 'Giá vốn đang ở chế độ cộng dồn từ thành phần.',
              type: ToastType.warning,
            )
                : null,
          ),
          if (_isCumulativeCostPrice)
            Padding(
              padding: const EdgeInsets.only(top: 8.0, left: 16),
              child: Text(
                'Giá vốn cộng dồn đang bật',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.red),
              ),
            ),
        ],
      );
    }

    return CustomTextFormField(
      controller: _costPriceController,
      decoration: const InputDecoration(
          labelText: 'Giá vốn', prefixIcon: Icon(Icons.money_off)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
    );
  }

  Widget _buildUnitField() {
    bool isChangeableUnit = _selectedProductType == 'Hàng hóa' ||
        _selectedProductType == 'Thành phẩm/Combo';
    return CustomTextFormField(
      controller: _unitController,
      decoration: InputDecoration(
        labelText: 'Đơn vị tính',
        prefixIcon: IconButton(
          icon: Icon(
            isChangeableUnit ? Icons.add : Icons.straighten,
            color: isChangeableUnit ? AppTheme.primaryColor : Colors.grey,
          ),
          onPressed: isChangeableUnit ? _showAddUnitsDialog : null,
        ),
      ),
    );
  }

  Widget _buildStockField() {
    if (_selectedProductType == 'Thành phẩm/Combo'|| _selectedProductType == 'Topping/Bán kèm') {
      final totalItems = _recipeItems.length + _accompanyingItems.length;
      final hasItems = totalItems > 0;

      return InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: () async {
          final result = await Navigator.of(context)
              .push<Map<String, List<SelectedIngredient>>>(
            MaterialPageRoute(
              builder: (context) => AddIngredientsScreen(
                currentUser: widget.currentUser,
                initialAccompanyingItems: _accompanyingItems,
                initialRecipeItems: _recipeItems,
                productType: _selectedProductType,
              ),
            ),
          );
          if (result != null) {
            setState(() {
              _accompanyingItems = result['accompanying'] ?? [];
              _recipeItems = result['recipe'] ?? [];
              if (_isCumulativeCostPrice) {
                final cumulativeCost = _calculateCumulativeCost();
                _costPriceController.text = numberFormat.format(cumulativeCost);
              }
            });
            ToastService().show(message: 'Đã cập nhật thành phần.', type: ToastType.success);
          }
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Thành phần',
            prefixIcon: const Icon(Icons.add, color: AppTheme.primaryColor),
            floatingLabelBehavior:
            hasItems ? FloatingLabelBehavior.always : FloatingLabelBehavior.never,
          ),
          child: Text(
            hasItems ? 'Đã chọn $totalItems' : 'Thành phần',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: hasItems ? Colors.black : Colors.grey[600],
            ),
          ),
        ),
      );
    }

    if (_selectedProductType == 'Dịch vụ/Tính giờ') {
      bool hasCommission = _serviceSetup != null &&
          _serviceSetup!.commissionLevels.values.any((c) => c.value > 0);
      bool isTimeBased = _serviceSetup?.isTimeBased == true;
      final hasSetup = hasCommission || isTimeBased;

      Icon prefixIcon;
      if (isTimeBased) {
        prefixIcon = const Icon(Icons.access_time, color: AppTheme.primaryColor);
      } else if (hasCommission) {
        prefixIcon = const Icon(Icons.percent, color: AppTheme.primaryColor);
      } else {
        prefixIcon = const Icon(Icons.settings_rounded, color: AppTheme.primaryColor);
      }

      return InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        onTap: _showServiceSetupScreen,
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Thiết lập',
            prefixIcon: prefixIcon,
            floatingLabelBehavior:
            hasSetup ? FloatingLabelBehavior.always : FloatingLabelBehavior.never,
          ),
          child: Text(
            hasSetup ? 'Đã thiết lập' : 'Thiết lập',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: hasSetup ? Colors.black : Colors.grey[600],
            ),
          ),
        ),
      );

    }

    return CustomTextFormField(
      controller: _stockController,
      decoration: InputDecoration(
        labelText: 'Tồn kho',
        prefixIcon: IconButton(
          icon: const Icon(Icons.inventory_2_outlined, color: AppTheme.primaryColor),
          onPressed: () async {

            final result = await showDialog<double>(
              context: context,
              builder: (context) {
                final controller = TextEditingController(
                  text: _minStockController.text,
                );
                return AlertDialog(
                  title: const Text('Nhập tồn kho tối thiểu'),
                  content: TextField(
                    controller: controller,
                    decoration: const InputDecoration(labelText: 'Số lượng tối thiểu'),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [ThousandDecimalInputFormatter()],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        final value = parseVN(controller.text); // ✅ dùng parseVN
                        Navigator.pop(context, value);
                      },
                      child: const Text('Lưu'),
                    ),
                  ],
                );
              },
            );
            if (result != null) {
              setState(() => _minStockController.text = formatNumber(result)); // ✅ dùng formatNumber
              ToastService().show(
                message: 'Đã lưu tồn kho tối thiểu: ${formatNumber(result)}',
                type: ToastType.success,
              );
            }
          },
        ),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [ThousandDecimalInputFormatter()],
    );
  }

  Widget _buildPrinterSelector() {
    final List<String> printers = [
      'Máy in A',
      'Máy in B',
      'Máy in C',
      'Máy in D'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.print_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Text('Máy in báo chế biến', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8.0,
          runSpacing: 4.0,
          children: printers.map((printer) {
            final isSelected = _selectedPrinters.contains(printer);
            return ChoiceChip(
              label: Text(printer),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedPrinters.add(printer);
                  } else {
                    _selectedPrinters.remove(printer);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildImagePicker(),
        const SizedBox(height: 24),
        _buildProductTypeDropdown(),
        const SizedBox(height: 16),
        _buildProductGroupDropdown(),
        const SizedBox(height: 16),
        _buildProductCodeField(),
        const SizedBox(height: 16),
        _buildProductNameField(),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSellPriceField()),
            const SizedBox(width: 16),
            Expanded(child: _buildCostPriceField()),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildUnitField()),
            const SizedBox(width: 16),
            Expanded(child: _buildStockField()),
          ],
        ),
        if (_shouldShowPrinterSelector) ...[
          const SizedBox(height: 24),
          _buildPrinterSelector(),
        ],
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImagePicker(),
            const SizedBox(width: 24),
            Expanded(
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildProductTypeDropdown()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildProductGroupDropdown()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildProductCodeField()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildProductNameField()),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Divider(
          height: 16,
          thickness: 0.8,
          color: Colors.grey.shade200,
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _buildSellPriceField()),
            const SizedBox(width: 16),
            Expanded(child: _buildCostPriceField()),
            const SizedBox(width: 16),
            Expanded(child: _buildUnitField()),
            const SizedBox(width: 16),
            Expanded(child: _buildStockField()),
          ],
        ),
        if (_shouldShowPrinterSelector) ...[
          const SizedBox(height: 24),
          _buildPrinterSelector(),
        ],
      ],
    );
  }
}