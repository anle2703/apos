import 'dart:convert';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/label_template_model.dart';
import '../../models/order_item_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../services/printing_service.dart';
import '../../models/configured_printer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/label_widget.dart';

class LabelSetupScreen extends StatefulWidget {
  final UserModel currentUser;

  const LabelSetupScreen({super.key, required this.currentUser});

  @override
  State<LabelSetupScreen> createState() => _LabelSetupScreenState();
}

class _LabelSetupScreenState extends State<LabelSetupScreen> {
  LabelTemplateModel _settings = LabelTemplateModel();
  bool _isRetailMode = false;
  bool _isLoading = true;
  bool _isPrinting = false;
  String _selectedSizeOption = '50x30';

  @override
  void initState() {
    super.initState();
    _isRetailMode = widget.currentUser.businessType == 'retail';
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('label_template_settings');

    setState(() {
      if (jsonStr != null) {
        _settings = LabelTemplateModel.fromJson(jsonStr);
        _syncDropdownWithSize();
      } else {
        _settings = LabelTemplateModel(labelWidth: 50, labelHeight: 30);
        _syncDropdownWithSize();
      }
      _isLoading = false;
    });
  }

  void _syncDropdownWithSize() {
    if (_settings.labelWidth == 50 && _settings.labelHeight == 30) {
      _selectedSizeOption = '50x30';
    } else if (_settings.labelWidth == 70 && _settings.labelHeight == 22) {
      _selectedSizeOption = '70x22';
    } else {
      _selectedSizeOption = 'custom';
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('label_template_settings', json.encode(_settings.toMap()));
    await prefs.setDouble('label_width_setting', _settings.labelWidth);
    await prefs.setDouble('label_height_setting', _settings.labelHeight);

    if (mounted) {
      ToastService().show(message: "Đã lưu cài đặt!", type: ToastType.success);
    }
  }

  Future<void> _resetToSmartDefaults() async {
    setState(() {
      _settings = LabelTemplateModel(labelWidth: 50, labelHeight: 30, labelColumns: 1);
      _syncDropdownWithSize();
    });
    ToastService().show(message: "Đã khôi phục mặc định", type: ToastType.success);
  }

  Future<void> _testPrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('printer_assignments');
      if (jsonString == null) throw Exception("Chưa cấu hình máy in.");

      final List<dynamic> jsonList = jsonDecode(jsonString);
      final configuredPrinters = jsonList.map((j) => ConfiguredPrinter.fromJson(j)).toList();

      await _saveSettings();

      final dummyItem = _createDummyItem();
      final List<Map<String, dynamic>> dummyItemsMap = [];

      // Tạo đúng số lượng tem trên 1 hàng để test in đủ khổ
      for (int i = 0; i < _settings.labelColumns; i++) {
        dummyItemsMap.add(dummyItem.toMap());
      }

      final printService = PrintingService(tableName: "TEST", userName: "Admin");

      await printService.printLabels(
        items: dummyItemsMap,
        tableName: _isRetailMode ? "Bán lẻ" : "Bàn Test",
        billCode: "HD001",
        createdAt: DateTime.now(),
        configuredPrinters: configuredPrinters,
        width: _settings.labelWidth,
        height: _settings.labelHeight,
        isRetailMode: _isRetailMode,
      );

      ToastService().show(message: "Đã gửi lệnh in ${_settings.labelColumns} tem", type: ToastType.success);
    } catch (e) {
      ToastService().show(message: "Lỗi in thử: $e", type: ToastType.error);
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  OrderItem _createDummyItem() {
    return OrderItem(
        product: ProductModel(
            id: 'demo_id',
            productName: _isRetailMode ? 'Snack Lay\'s Vị Tự Nhiên' : 'Trà Sữa Trân Châu Đường Đen',
            sellPrice: 25000,
            productCode: 'SP893',
            additionalBarcodes: ['893456789012'],
            additionalUnits: [],
            costPrice: 0,
            stock: 0,
            minStock: 0,
            storeId: '',
            ownerUid: '',
            accompanyingItems: [],
            recipeItems: [],
            compiledMaterials: [],
            kitchenPrinters: []),
        quantity: 1,
        price: 25000,
        selectedUnit: _isRetailMode ? 'Gói' : 'Ly L',
        toppings: _isRetailMode
            ? {}
            : {
                ProductModel(
                    id: 't1',
                    productName: 'Trân châu trắng',
                    sellPrice: 5000,
                    additionalBarcodes: [],
                    additionalUnits: [],
                    accompanyingItems: [],
                    recipeItems: [],
                    compiledMaterials: [],
                    kitchenPrinters: [],
                    costPrice: 0,
                    stock: 0,
                    minStock: 0,
                    storeId: '',
                    ownerUid: ''): 1
              },
        note: _isRetailMode ? '' : '50% đường, ít đá',
        addedAt: Timestamp.now(),
        addedBy: 'Admin',
        lineId: 'line_1',
        commissionStaff: {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: Text('Mẫu tem (${_isRetailMode ? "Bán lẻ" : "F&B"})'),
        actions: [
          IconButton(icon: const Icon(Icons.restore, color: AppTheme.primaryColor, size: 30), onPressed: _resetToSmartDefaults),
          IconButton(icon: const Icon(Icons.print, color: AppTheme.primaryColor, size: 30), onPressed: _testPrint),
          IconButton(icon: const Icon(Icons.save, color: AppTheme.primaryColor, size: 30), onPressed: _saveSettings),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Responsive layout
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _buildPreviewPanel(),
                ),
                Expanded(
                  flex: 5,
                  child: _buildSettingsPanel(),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Expanded(
                  flex: 4, // Preview chiếm 40% màn hình mobile
                  child: _buildPreviewPanel(),
                ),
                Expanded(
                  flex: 6, // Settings chiếm 60%
                  child: _buildSettingsPanel(),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  // Panel Cài đặt (Bên trái hoặc Bên dưới)
  Widget _buildSettingsPanel() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPaperSettings(),
        _buildCommonMargins(),
        _isRetailMode ? _buildRetailSettings() : _buildFnBSettings(),
      ],
    );
  }

  // Panel Xem trước (Bên phải hoặc Bên trên) - Dùng Widget thật
  Widget _buildPreviewPanel() {
    return Container(
      color: Colors.grey[300],
      // Màu nền xám để nổi bật tem trắng
      width: double.infinity,
      height: double.infinity,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal, // Cho phép cuộn ngang nếu tem quá dài
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("Xem trước (Tỉ lệ thực tế)", style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),

                // HIỂN THỊ WIDGET THẬT (Giống hệt lúc in)
                // Bọc trong Container có shadow để giống tờ giấy
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))],
                  ),
                  child: _buildLivePreview(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Hàm tạo Widget xem trước (Sử dụng LabelRowWidget)
  Widget _buildLivePreview() {
    final dummyItem = _createDummyItem();

    // Tạo dữ liệu giả giống PrintingService
    List<LabelItemData?> previewItems = [];
    for (int i = 0; i < _settings.labelColumns; i++) {
      previewItems.add(LabelItemData(
          item: dummyItem,
          headerTitle: _isRetailMode ? "HD001" : "Bàn 5",
          index: i + 1,
          total: _settings.labelColumns,
          dailySeq: 101));
    }

    // Tính toán kích thước pixel (8 dots/mm)
    double targetWidthPx = _settings.labelWidth * 8.0;
    double targetHeightPx = _settings.labelHeight * 8.0;

    return SizedBox(
      width: targetWidthPx,
      height: targetHeightPx,
      child: LabelRowWidget(
        items: previewItems,
        widthMm: _settings.labelWidth,
        heightMm: _settings.labelHeight,
        gapMm: 2.0,
        isRetailMode: _isRetailMode,
        settings: _settings,
      ),
    );
  }

  Widget _buildPaperSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Kích thước giấy in", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AppDropdown<String>(
                labelText: 'Khổ giấy',
                value: _selectedSizeOption,
                items: const [
                  DropdownMenuItem(value: '50x30', child: Text('50x30 mm (1 tem)')),
                  DropdownMenuItem(value: '70x22', child: Text('70x22 mm (2 tem)')),
                  DropdownMenuItem(value: 'custom', child: Text('Tùy chỉnh...')),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedSizeOption = val!;
                    if (val == '50x30') {
                      _settings.labelWidth = 50;
                      _settings.labelHeight = 30;
                      _settings.labelColumns = 1;
                    } else if (val == '70x22') {
                      _settings.labelWidth = 70;
                      _settings.labelHeight = 22;
                      _settings.labelColumns = 2;
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AppDropdown<int>(
                labelText: 'Số tem/hàng',
                value: _settings.labelColumns,
                items: const [
                  DropdownMenuItem(value: 1, child: Text('1 tem')),
                  DropdownMenuItem(value: 2, child: Text('2 tem')),
                  DropdownMenuItem(value: 3, child: Text('3 tem')),
                ],
                onChanged: (val) {
                  setState(() => _settings.labelColumns = val!);
                },
              ),
            ),
          ],
        ),
        if (_selectedSizeOption == 'custom')
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: Row(
              children: [
                Expanded(
                    child: CustomTextFormField(
                  key: ValueKey(_settings.labelWidth),
                  initialValue: _settings.labelWidth.toInt().toString(),
                  decoration: const InputDecoration(labelText: 'Rộng (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _settings.labelWidth = (double.tryParse(v) ?? 50)),
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: CustomTextFormField(
                  key: ValueKey(_settings.labelHeight),
                  initialValue: _settings.labelHeight.toInt().toString(),
                  decoration: const InputDecoration(labelText: 'Cao (mm)', isDense: true),
                  keyboardType: TextInputType.number,
                  onChanged: (v) => setState(() => _settings.labelHeight = (double.tryParse(v) ?? 30)),
                )),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildCommonMargins() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text("Căn lề (mm)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primaryColor)),
        _buildSlider("Trên", _settings.marginTop, 0, 10, (v) => setState(() => _settings.marginTop = v)),
        _buildSlider("Dưới", _settings.marginBottom, 0, 10, (v) => setState(() => _settings.marginBottom = v)),
        _buildSlider("Trái", _settings.marginLeft, 0, 10, (v) => setState(() => _settings.marginLeft = v)),
        _buildSlider("Phải", _settings.marginRight, 0, 10, (v) => setState(() => _settings.marginRight = v)),
      ],
    );
  }

  Widget _buildFnBSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 1: Tên bàn / Thời gian"),
        _buildSlider("Cỡ chữ Bàn", _settings.fnbHeaderSize, 5, 20, (v) => setState(() => _settings.fnbHeaderSize = v)),
        _buildSwitch("Bàn In đậm", _settings.fnbHeaderBold, (v) => setState(() => _settings.fnbHeaderBold = v)),
        _buildSlider("Cỡ chữ Giờ", _settings.fnbTimeSize, 5, 20, (v) => setState(() => _settings.fnbTimeSize = v)),
        _buildSwitch("Giờ In đậm", _settings.fnbTimeBold, (v) => setState(() => _settings.fnbTimeBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 2: Tên sản phẩm"),
        _buildSlider("Cỡ chữ", _settings.fnbProductSize, 5, 20, (v) => setState(() => _settings.fnbProductSize = v)),
        _buildSwitch("In đậm", _settings.fnbProductBold, (v) => setState(() => _settings.fnbProductBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 3: Topping & Ghi chú"),
        _buildSlider("Cỡ chữ", _settings.fnbNoteSize, 5, 20, (v) => setState(() => _settings.fnbNoteSize = v)),
        _buildSwitch("In đậm", _settings.fnbNoteBold, (v) => setState(() => _settings.fnbNoteBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 4: Giá & STT"),
        _buildSlider("Cỡ chữ", _settings.fnbFooterSize, 5, 20, (v) => setState(() => _settings.fnbFooterSize = v)),
        _buildSwitch("In đậm", _settings.fnbFooterBold, (v) => setState(() => _settings.fnbFooterBold = v)),
      ],
    );
  }

  Widget _buildRetailSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader("Hàng 1: Tên cửa hàng"),
        TextFormField(
          initialValue: _settings.retailStoreName,
          decoration: const InputDecoration(labelText: "Nội dung", border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => _settings.retailStoreName = v),
        ),
        const SizedBox(height: 12),
        _buildSlider("Cỡ chữ", _settings.retailHeaderSize, 5, 20, (v) => setState(() => _settings.retailHeaderSize = v)),
        _buildSwitch("In đậm", _settings.retailHeaderBold, (v) => setState(() => _settings.retailHeaderBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 2: Tên sản phẩm"),
        _buildSlider("Cỡ chữ", _settings.retailProductSize, 5, 20, (v) => setState(() => _settings.retailProductSize = v)),
        _buildSwitch("In đậm", _settings.retailProductBold, (v) => setState(() => _settings.retailProductBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 3: Mã vạch & Mã SP"),
        _buildSlider(
            "Cao Barcode", _settings.retailBarcodeHeight, 10, 40, (v) => setState(() => _settings.retailBarcodeHeight = v)),
        _buildSlider(
            "Rộng Barcode", _settings.retailBarcodeWidth, 20, 120, (v) => setState(() => _settings.retailBarcodeWidth = v)),
        _buildSlider("Cỡ chữ Mã SP", _settings.retailCodeSize, 5, 20, (v) => setState(() => _settings.retailCodeSize = v)),
        _buildSwitch("Mã SP In đậm", _settings.retailCodeBold, (v) => setState(() => _settings.retailCodeBold = v)),
        const SizedBox(height: 12),
        _buildSectionHeader("Hàng 4: Giá & ĐVT"),
        _buildSlider("Cỡ chữ Giá", _settings.retailPriceSize, 5, 20, (v) => setState(() => _settings.retailPriceSize = v)),
        _buildSwitch("Giá In đậm", _settings.retailPriceBold, (v) => setState(() => _settings.retailPriceBold = v)),
        _buildSwitch("ĐVT In đậm", _settings.retailUnitBold, (v) => setState(() => _settings.retailUnitBold = v)),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
    );
  }

  Widget _buildSlider(String label, double val, double min, double max, Function(double) onChanged) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text("$label: ${val.toStringAsFixed(0)}")),
        Expanded(
          child: Slider(
            value: val,
            min: min,
            max: max,
            divisions: (max - min).toInt(),
            label: val.toStringAsFixed(0),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitch(String label, bool val, Function(bool) onChanged) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text(label)),
        Switch(value: val, onChanged: onChanged),
      ],
    );
  }
}
