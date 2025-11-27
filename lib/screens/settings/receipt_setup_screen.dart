import 'dart:convert';
import 'package:app_4cash/theme/app_theme.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/receipt_template_model.dart';
import '../../models/user_model.dart';
import '../../models/product_model.dart';
import '../../models/order_item_model.dart';
import '../../services/toast_service.dart';
import '../../widgets/app_dropdown.dart';
import '../../widgets/receipt_widget.dart';
import '../../widgets/kitchen_ticket_widget.dart';
import '../../services/printing_service.dart';
import '../../models/configured_printer_model.dart';
import '../../widgets/table_notification_widget.dart';

class ReceiptSetupScreen extends StatefulWidget {
  final UserModel currentUser;
  const ReceiptSetupScreen({super.key, required this.currentUser});

  @override
  State<ReceiptSetupScreen> createState() => _ReceiptSetupScreenState();
}

class _ReceiptSetupScreenState extends State<ReceiptSetupScreen> {
  ReceiptTemplateModel _settings = ReceiptTemplateModel();
  bool _isLoading = true;
  bool _isPrinting = false;

  String _previewMode = 'bill'; // 'bill', 'provisional_simple', 'check_dish', 'kitchen'

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('receipt_template_settings');
    setState(() {
      if (jsonStr != null) {
        _settings = ReceiptTemplateModel.fromJson(jsonStr);
      }
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('receipt_template_settings', json.encode(_settings.toMap()));
    if (mounted) {
      ToastService().show(message: "Đã lưu cài đặt!", type: ToastType.success);
    }
  }

  Future<void> _resetToDefaults() async {
    setState(() {
      _settings = ReceiptTemplateModel();
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

      final printService = PrintingService(tableName: "Test", userName: "Admin");
      final dummyItems = _createDummyItems();

      if (_previewMode == 'kitchen') {
        await printService.printKitchenTicket(
            itemsToPrint: dummyItems,
            targetPrinterRole: 'kitchen_printer_a',
            configuredPrinters: configuredPrinters,
            customerName: "Anh Nam"
        );
      } else {
        final bool showPrices = _previewMode != 'check_dish';
        final bool isSimple = _previewMode == 'provisional_simple';

        // SỬA: Đã xóa biến 'title' không sử dụng để hết Warning

        final dummySummary = {
          'subtotal': 155000.0,
          'discount': 15500.0,
          'taxAmount': 0.0,
          'surcharges': [{'name': 'Phụ thu Tết', 'amount': 10000.0}],
          'totalPayable': 149500.0,
          'changeAmount': 50500.0,
          'customer': {'name': 'Lê Thành An', 'phone': '0935417776'},
          'payments': {'Tiền mặt': 150000},
        };

        if (_previewMode == 'bill') {
          await printService.printReceiptBill(
            storeInfo: {'name': 'Phần mềm APOS', 'address': '999 Quang Trung - Tp Quảng Ngãi', 'phone': '0935417776'},
            items: dummyItems,
            summary: dummySummary,
            configuredPrinters: configuredPrinters,
          );
        } else {
          await printService.printProvisionalBill(
            storeInfo: {'name': 'Phần mềm APOS', 'address': '999 Quang Trung - Tp Quảng Ngãi', 'phone': '0935417776'},
            items: dummyItems,
            summary: dummySummary,
            showPrices: showPrices,
            configuredPrinters: configuredPrinters,
            useDetailedLayout: !isSimple,
          );
        }
      }

      ToastService().show(message: "Đã gửi lệnh in thử", type: ToastType.success);

    } catch (e) {
      ToastService().show(message: "Lỗi in thử: $e", type: ToastType.error);
    } finally {
      setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình Mẫu in'),
        actions: [
          IconButton(icon: const Icon(Icons.restore, color: AppTheme.primaryColor, size: 30), onPressed: _resetToDefaults, tooltip: 'Mặc định'),
          IconButton(icon: const Icon(Icons.print, color: AppTheme.primaryColor, size: 30), onPressed: _testPrint, tooltip: 'In thử'),
          IconButton(icon: const Icon(Icons.save, color: AppTheme.primaryColor, size: 30), onPressed: _saveSettings, tooltip: 'Lưu'),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          bool isWide = constraints.maxWidth > 800;
          return isWide
              ? Row(
            children: [
              Expanded(flex: 5, child: _buildPreviewPanel()),
              Expanded(flex: 5, child: _buildSettingsPanel()),
            ],
          )
              : Column(
            children: [
              Expanded(flex: 4, child: _buildPreviewPanel()),
              Expanded(flex: 6, child: _buildSettingsPanel()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPreviewPanel() {
    return Container(
      color: Colors.grey[200],
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text("Xem trước mẫu in", style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),

            Container(
              constraints: const BoxConstraints(maxWidth: 380),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [BoxShadow(color: Colors.black.withAlpha(25), blurRadius: 10, offset: const Offset(0, 5))],
              ),
              child: FittedBox(
                fit: BoxFit.contain,
                child: _buildPreviewWidget(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewWidget() {
    if (_previewMode == 'kitchen') {
      return _buildKitchenPreview();
    }
    if (_previewMode == 'table_event') { // <--- THÊM LOGIC NÀY
      return TableNotificationWidget(
        storeInfo: {'name': 'CÀ PHÊ GÓC PHỐ'},
        actionTitle: 'CHUYỂN BÀN',
        message: 'Từ Bàn 10 -> Bàn 15',
        userName: 'Thu ngân 01',
        timestamp: DateTime.now(),
        templateSettings: _settings,
      );
    }
    final dummyItems = _createDummyItems();
    final dummySummary = {
      'subtotal': 155000.0,
      'discount': 15500.0,
      'taxAmount': 0.0,
      'surcharges': [{'name': 'Phụ thu Tết', 'amount': 10000.0}],
      'totalPayable': 149500.0,
      'changeAmount': 50500.0,
      'customer': {'name': 'Lê Thành An', 'phone': '0935417776'},
      'payments': {'Tiền mặt': 150000},
    };

    final bool showPrices = _previewMode != 'check_dish';
    final bool isSimple = _previewMode == 'provisional_simple';
    final String title = _previewMode == 'bill' ? 'HÓA ĐƠN' : (_previewMode == 'check_dish' ? 'KIỂM MÓN' : 'TẠM TÍNH');

    return ReceiptWidget(
      title: title,
      storeInfo: const {
        'name': 'Phần mềm APOS',
        'address': '999 Quang Trung - Tp Quảng Ngãi',
        'phone': '0935417776'
      },
      items: dummyItems,
      summary: dummySummary,
      userName: 'Thu ngân 01',
      tableName: 'Bàn 10',
      showPrices: showPrices,
      isSimplifiedMode: isSimple,
      templateSettings: _settings,
    );
  }

  Widget _buildKitchenPreview() {
    return KitchenTicketWidget(
      title: "BÁO BẾP",
      tableName: "Bàn 10",
      items: _createDummyItems(),
      userName: "Thu ngân 01",
      customerName: "Anh Nam",
      isCancelTicket: false,
      templateSettings: _settings,
    );
  }

  Widget _buildSettingsPanel() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: AppDropdown<String>(
              labelText: 'Chọn mẫu xem trước',
              value: _previewMode,
              items: const [
                DropdownMenuItem(value: 'bill', child: Text('Hóa đơn thanh toán (Chi tiết)')),
                DropdownMenuItem(value: 'provisional_simple', child: Text('Tạm tính (Nhanh)')),
                DropdownMenuItem(value: 'check_dish', child: Text('Kiểm món (Không giá)')),
                DropdownMenuItem(value: 'kitchen', child: Text('Báo bếp')),
                DropdownMenuItem(value: 'table_event', child: Text('Chuyển/Gộp bàn')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _previewMode = val);
              },
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: _previewMode == 'kitchen'
                  ? _buildKitchenSettings()
                  : _buildBillSettings(),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildBillSettings() {
    return [
      _buildSectionTitle("Thông tin chung & Header"),
      _buildSwitchTile("Hiển thị Tên cửa hàng", _settings.billShowStoreName, (v) => setState(() => _settings.billShowStoreName = v)),
      _buildSliderTile("Cỡ chữ Tên quán", _settings.billHeaderSize, 10, 30, (v) => setState(() => _settings.billHeaderSize = v)),

      _buildSwitchTile("Hiển thị Địa chỉ", _settings.billShowStoreAddress, (v) => setState(() => _settings.billShowStoreAddress = v)),
      _buildSliderTile("Cỡ chữ Địa chỉ", _settings.billAddressSize, 8, 30, (v) => setState(() => _settings.billAddressSize = v)), // Mới

      _buildSwitchTile("Hiển thị SĐT/Hotline", _settings.billShowStorePhone, (v) => setState(() => _settings.billShowStorePhone = v)),
      _buildSliderTile("Cỡ chữ SĐT", _settings.billPhoneSize, 8, 30, (v) => setState(() => _settings.billPhoneSize = v)), // Mới
      const SizedBox(height: 8),

      _buildSectionTitle("Thông tin đơn hàng"),
      _buildSliderTile("Cỡ chữ Tiêu đề", _settings.billTitleSize, 10, 30, (v) => setState(() => _settings.billTitleSize = v)),
      _buildSwitchTile("Hiển thị tên Thu ngân", _settings.billShowCashierName, (v) => setState(() => _settings.billShowCashierName = v)),
      _buildSwitchTile("Hiển thị tên Khách hàng", _settings.billShowCustomerName, (v) => setState(() => _settings.billShowCustomerName = v)),
      _buildSliderTile("Cỡ chữ TT (Khách/NV/Giờ)", _settings.billTextSize, 10, 30, (v) => setState(() => _settings.billTextSize = v)),
      const SizedBox(height: 8),
      _buildSectionTitle("Danh sách món"),
      _buildSliderTile("Cỡ chữ Tên món", _settings.billItemNameSize, 10, 30, (v) => setState(() => _settings.billItemNameSize = v)),
      _buildSliderTile("Cỡ chữ Chi tiết (Giá/SL)", _settings.billItemDetailSize, 10, 30, (v) => setState(() => _settings.billItemDetailSize = v)),
      const SizedBox(height: 8),
      _buildSectionTitle("Tổng kết & Footer"),
      _buildSwitchTile("Hiển thị dòng Thuế", _settings.billShowTax, (v) => setState(() => _settings.billShowTax = v)),
      _buildSwitchTile("Hiển thị Phụ thu", _settings.billShowSurcharge, (v) => setState(() => _settings.billShowSurcharge = v)),
      _buildSwitchTile("Hiển thị Chiết khấu", _settings.billShowDiscount, (v) => setState(() => _settings.billShowDiscount = v)),
      _buildSliderTile("Cỡ chữ Tổng tiền", _settings.billTotalSize, 10, 30, (v) => setState(() => _settings.billTotalSize = v)),
      _buildSwitchTile("Hiển thị Phương thức TT", _settings.billShowPaymentMethod, (v) => setState(() => _settings.billShowPaymentMethod = v)),

      _buildSwitchTile("Hiển thị Footer (Lời cảm ơn)", _settings.billShowFooter, (v) => setState(() => _settings.billShowFooter = v)),
      const SizedBox(height: 8),
      if (_settings.billShowFooter) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TextFormField(
            initialValue: _settings.footerText1,
            decoration: const InputDecoration(labelText: 'Dòng cảm ơn 1', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _settings.footerText1 = v),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: TextFormField(
            initialValue: _settings.footerText2,
            decoration: const InputDecoration(labelText: 'Dòng cảm ơn 2', isDense: true, border: OutlineInputBorder()),
            onChanged: (v) => setState(() => _settings.footerText2 = v),
          ),
        ),
      ]
    ];
  }

  List<Widget> _buildKitchenSettings() {
    return [
      _buildSectionTitle("Thông tin phiếu"),
      _buildSliderTile("Cỡ chữ Tiêu đề", _settings.kitchenTitleSize, 10, 30, (v) => setState(() => _settings.kitchenTitleSize = v)),
      _buildSwitchTile("Hiển thị Giờ in", _settings.kitchenShowTime, (v) => setState(() => _settings.kitchenShowTime = v)),
      _buildSwitchTile("Hiển thị tên Nhân viên", _settings.kitchenShowStaff, (v) => setState(() => _settings.kitchenShowStaff = v)),
      _buildSwitchTile("Hiển thị tên Khách", _settings.kitchenShowCustomer, (v) => setState(() => _settings.kitchenShowCustomer = v)),
      _buildSliderTile("Cỡ chữ TT (Khách/NV/Giờ)", _settings.kitchenInfoSize, 10, 30, (v) => setState(() => _settings.kitchenInfoSize = v)),

      _buildSectionTitle("Nội dung món"),
      _buildSliderTile("Cỡ chữ Header (STT/Món/SL)", _settings.kitchenTableHeaderSize, 10, 30, (v) => setState(() => _settings.kitchenTableHeaderSize = v)),
      _buildSliderTile("Cỡ chữ Số lượng (SL)", _settings.kitchenQtySize, 10, 30, (v) => setState(() => _settings.kitchenQtySize = v)),
      _buildSliderTile("Cỡ chữ Tên món", _settings.kitchenItemNameSize, 10, 30, (v) => setState(() => _settings.kitchenItemNameSize = v)),
      _buildSliderTile("Cỡ chữ Ghi chú/Topping", _settings.kitchenNoteSize, 10, 30, (v) => setState(() => _settings.kitchenNoteSize = v)),
    ];
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primaryColor, fontSize: 13)),
    );
  }

  Widget _buildSwitchTile(String title, bool value, Function(bool) onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      dense: true,
    );
  }

  Widget _buildSliderTile(String title, double value, double min, double max, Function(double) onChanged) {
    double validValue = value;
    if (validValue < min) validValue = min;
    if (validValue > max) validValue = max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontSize: 14)),
            Text("${validValue.toInt()}", style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        Slider(
          value: validValue,
          min: min,
          max: max,
          divisions: (max - min).toInt(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  List<OrderItem> _createDummyItems() {
    // SỬA: Xóa tham số subtotal, để OrderItem tự tính
    return [
      OrderItem(
        product: ProductModel(id: '1', productName: 'Cà phê sữa đá', sellPrice: 25000, productCode: 'CF01', additionalBarcodes: [], additionalUnits: [], costPrice: 0, stock: 0, minStock: 0, storeId: '', ownerUid: '', accompanyingItems: [], recipeItems: [], compiledMaterials: [], kitchenPrinters: []),
        quantity: 2,
        price: 25000,
        selectedUnit: 'Ly',
        toppings: {},
        note: 'Ít ngọt',
        addedAt: Timestamp.now(),
        addedBy: 'Admin',
        lineId: '1',
        commissionStaff: {},
      ),
      OrderItem(
        product: ProductModel(id: '2', productName: 'Trà đào cam sả', sellPrice: 35000, productCode: 'TD01', additionalBarcodes: [], additionalUnits: [], costPrice: 0, stock: 0, minStock: 0, storeId: '', ownerUid: '', accompanyingItems: [], recipeItems: [], compiledMaterials: [], kitchenPrinters: []),
        quantity: 1,
        price: 35000,
        selectedUnit: 'Ly',
        toppings: {},
        note: '',
        addedAt: Timestamp.now(),
        addedBy: 'Admin',
        lineId: '2',
        commissionStaff: {},
      ),
    ];
  }
}