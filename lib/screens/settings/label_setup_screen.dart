import 'dart:convert';
import 'dart:typed_data';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/label_template_model.dart';
import '../../services/label_printing_service.dart';
import '../../models/order_item_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../services/printing_service.dart';
import '../../models/configured_printer_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/custom_text_form_field.dart';

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
  String _selectedSizeOption = '50x30'; // Biến tạm để quản lý dropdown

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
        // Mặc định ban đầu
        _settings = LabelTemplateModel();
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
      _settings = LabelTemplateModel();
      _syncDropdownWithSize();
    });
    ToastService().show(message: "Đã khôi phục mặc định", type: ToastType.success);
  }

  // Tìm và thay thế hàm _testPrint trong file label_setup_screen.dart

  Future<void> _testPrint() async {
    if (_isPrinting) return;
    setState(() => _isPrinting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('printer_assignments');
      if (jsonString == null) throw Exception("Chưa cấu hình máy in.");

      final List<dynamic> jsonList = jsonDecode(jsonString);
      final configuredPrinters = jsonList.map((j) => ConfiguredPrinter.fromJson(j)).toList();

      // 1. Lưu cài đặt hiện tại xuống bộ nhớ để Service đọc được kích thước mới nhất
      await _saveSettings();

      // 2. Tạo dữ liệu giả ĐÚNG bằng số lượng tem trên 1 hàng
      // Nếu tem đôi (2 cột) -> Tạo 2 item. Tem 3 -> 3 item.
      final dummyItem = _createDummyItem();
      final List<Map<String, dynamic>> dummyItemsMap = [];

      // Vòng lặp tạo đúng số lượng tem cần thiết để lấp đầy 1 hàng ngang
      for (int i = 0; i < _settings.labelColumns; i++) {
        dummyItemsMap.add(dummyItem.toMap());
      }

      final printService = PrintingService(tableName: "TEST", userName: "Admin");

      await printService.printLabels(
        items: dummyItemsMap,
        tableName: _isRetailMode ? "Bán lẻ" : "Bàn Test",
        createdAt: DateTime.now(),
        configuredPrinters: configuredPrinters,
        width: _settings.labelWidth,
        height: _settings.labelHeight,
        // QUAN TRỌNG: Truyền tham số này để ép kiểu in đúng layout
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
            additionalUnits: [], costPrice: 0, stock: 0, minStock: 0,
            storeId: '', ownerUid: '',
            accompanyingItems: [], recipeItems: [], compiledMaterials: [], kitchenPrinters: []
        ),
        quantity: 1,
        price: 25000,
        selectedUnit: _isRetailMode ? 'Gói' : 'Ly L',
        toppings: _isRetailMode ? {} : {
          ProductModel(id: 't1', productName: 'Trân châu trắng', sellPrice: 5000,
              additionalBarcodes: [], additionalUnits: [], accompanyingItems: [], recipeItems: [], compiledMaterials: [], kitchenPrinters: [], costPrice: 0, stock: 0, minStock: 0, storeId: '', ownerUid: ''): 1
        },
        note: _isRetailMode ? '' : '50% đường, ít đá',
        addedAt: Timestamp.now(),
        addedBy: 'Admin',
        lineId: 'line_1',
        commissionStaff: {}
    );
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
          if (constraints.maxWidth > 800) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildPaperSettings(),
                      _buildDivider(),
                      _buildCommonMargins(),
                      _buildDivider(),
                      _isRetailMode ? _buildRetailSettings() : _buildFnBSettings(),
                    ],
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Container(
                    color: Colors.grey[300],
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(40),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 400),
                        child: AspectRatio(
                          aspectRatio: _settings.labelWidth / _settings.labelHeight,
                          child: _buildPreviewWidget(),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          } else {
            return Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
                  alignment: Alignment.center,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: AspectRatio(
                      aspectRatio: _settings.labelWidth / _settings.labelHeight,
                      child: _buildPreviewWidget(),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildPaperSettings(),
                      _buildDivider(),
                      _buildCommonMargins(),
                      _buildDivider(),
                      _isRetailMode ? _buildRetailSettings() : _buildFnBSettings(),
                    ],
                  ),
                ),
              ],
            );
          }
        },
      ),
    );
  }

  Widget _buildPreviewWidget() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black.withAlpha(75), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: PdfPreview(
        build: (format) => _generatePreviewData(),
        useActions: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        dpi: 300,
        scrollViewDecoration: const BoxDecoration(color: Colors.transparent),
        pdfPreviewPageDecoration: const BoxDecoration(color: Colors.white),
      ),
    );
  }

  Future<Uint8List> _generatePreviewData() async {
    final dummyItem = _createDummyItem();
    final dummyData = LabelData(
      item: dummyItem,
      tableName: _isRetailMode ? "Bán lẻ" : "Bàn 5",
      createdAt: DateTime.now(),
      dailySeq: 101,
      copyIndex: 1,
      totalCopies: 1,
    );

    List<LabelData> previewList = [dummyData];
    // Nếu > 1 cột thì thêm data giả để người dùng thấy layout nhiều cột
    if (_settings.labelColumns > 1) {
      previewList.add(dummyData);
      if (_settings.labelColumns > 2) previewList.add(dummyData);
    }

    return await LabelPrintingService.generateLabelPdf(
      labelsOnPage: previewList,
      pageWidthMm: _settings.labelWidth,
      pageHeightMm: _settings.labelHeight,
      settings: _settings,
      isRetailMode: _isRetailMode,
      forceWhiteBackground: true,
    );
  }

  // --- WIDGETS ---

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Divider(height: 4, thickness: 0.5, color: Colors.grey),
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
                  DropdownMenuItem(value: '50x30', child: Text('50x30 mm')),
                  DropdownMenuItem(value: '70x22', child: Text('70x22 mm')),
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
                      _settings.labelColumns = 2; // Mặc định 70x22 thường in 2 tem
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
        const Text("Căn lề (mm) - Max 20", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        _buildSlider("Trên", _settings.marginTop, 0, 20, (v) => setState(() => _settings.marginTop = v)),
        _buildSlider("Dưới", _settings.marginBottom, 0, 20, (v) => setState(() => _settings.marginBottom = v)),
        _buildSlider("Trái", _settings.marginLeft, 0, 20, (v) => setState(() => _settings.marginLeft = v)),
        _buildSlider("Phải", _settings.marginRight, 0, 20, (v) => setState(() => _settings.marginRight = v)),
      ],
    );
  }

  Widget _buildFnBSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Cấu hình FnB", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue)),
        const SizedBox(height: 10),

        _buildSectionHeader("Hàng 1: Tên bàn / Thời gian"),
        _buildSlider("Cỡ chữ Bàn", _settings.fnbHeaderSize, 5, 20, (v) => setState(() => _settings.fnbHeaderSize = v)),
        _buildSwitch("Bàn In đậm", _settings.fnbHeaderBold, (v) => setState(() => _settings.fnbHeaderBold = v)),
        _buildSlider("Cỡ chữ Giờ", _settings.fnbTimeSize, 5, 20, (v) => setState(() => _settings.fnbTimeSize = v)),
        _buildSwitch("Giờ In đậm", _settings.fnbTimeBold, (v) => setState(() => _settings.fnbTimeBold = v)),
        _buildDivider(),

        _buildSectionHeader("Hàng 2: Tên sản phẩm"),
        _buildSlider("Cỡ chữ", _settings.fnbProductSize, 5, 20, (v) => setState(() => _settings.fnbProductSize = v)),
        _buildSwitch("In đậm", _settings.fnbProductBold, (v) => setState(() => _settings.fnbProductBold = v)),
        _buildDivider(),

        _buildSectionHeader("Hàng 3: Topping & Ghi chú"),
        _buildSlider("Cỡ chữ", _settings.fnbNoteSize, 5, 20, (v) => setState(() => _settings.fnbNoteSize = v)),
        _buildSwitch("In đậm", _settings.fnbNoteBold, (v) => setState(() => _settings.fnbNoteBold = v)),
        _buildDivider(),

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
        const Text("Cấu hình Bán lẻ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green)),
        const SizedBox(height: 10),

        _buildSectionHeader("Hàng 1: Tên cửa hàng"),
        TextFormField(
          initialValue: _settings.retailStoreName,
          decoration: const InputDecoration(labelText: "Nội dung", border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => setState(() => _settings.retailStoreName = v),
        ),
        const SizedBox(height: 8),
        _buildSlider("Cỡ chữ", _settings.retailHeaderSize, 5, 20, (v) => setState(() => _settings.retailHeaderSize = v)),
        _buildSwitch("In đậm", _settings.retailHeaderBold, (v) => setState(() => _settings.retailHeaderBold = v)),
        _buildDivider(),

        _buildSectionHeader("Hàng 2: Tên sản phẩm"),
        _buildSlider("Cỡ chữ", _settings.retailProductSize, 5, 20, (v) => setState(() => _settings.retailProductSize = v)),
        _buildSwitch("In đậm", _settings.retailProductBold, (v) => setState(() => _settings.retailProductBold = v)),
        _buildDivider(),

        _buildSectionHeader("Hàng 3: Mã vạch & Mã SP"),
        _buildSlider("Cao Barcode", _settings.retailBarcodeHeight, 10, 40, (v) => setState(() => _settings.retailBarcodeHeight = v)),
        _buildSlider("Rộng Barcode", _settings.retailBarcodeWidth, 20, 120, (v) => setState(() => _settings.retailBarcodeWidth = v)),
        _buildSlider("Cỡ chữ Mã SP", _settings.retailCodeSize, 5, 20, (v) => setState(() => _settings.retailCodeSize = v)),
        _buildSwitch("Mã SP In đậm", _settings.retailCodeBold, (v) => setState(() => _settings.retailCodeBold = v)),
        _buildDivider(),

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
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.grey)),
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