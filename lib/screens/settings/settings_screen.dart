// File: lib/screens/settings/settings_screen.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart'
    as pos_printer;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';
import '../../models/configured_printer_model.dart';
import '../../models/user_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../services/cloud_print_service.dart';
import '../../services/settings_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../widgets/app_dropdown.dart';
import 'dart:io';
import '../../widgets/custom_text_form_field.dart';
import 'package:printing/printing.dart';

class SettingsScreen extends StatefulWidget {
  final UserModel currentUser;

  const SettingsScreen({super.key, required this.currentUser});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _firestoreService = FirestoreService();
  final _printerManager = pos_printer.PrinterManager.instance;
  final List<ScannedPrinter> _scannedPrinters = [];
  final _serverIpController = TextEditingController();
  final _storeNameController = TextEditingController();
  final _storePhoneController = TextEditingController();
  final _storeAddressController = TextEditingController();

  TimeOfDay _reportCutoffTime = const TimeOfDay(hour: 0, minute: 0);

  Map<String, ConfiguredPrinter?> _printerAssignments = {};
  late final SettingsService _settingsService;

  bool _isThisDeviceTheServer = false;
  bool _showPricesOnBill = false;
  bool _isSunmiDevice = false;
  bool _isScanning = false;
  bool _isSaving = false;
  bool _printBillAfterPayment = true;
  bool _notifyKitchenAfterPayment = false;
  bool _allowProvisionalBill = true;
  bool _promptForCash = true;

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  bool _printLabelOnKitchen = false;
  bool _printLabelOnPayment = false;
  double _labelWidth = 50.0;
  double _labelHeight = 30.0;
  String _selectedLabelSizeOption = '50x30';

  String _serverListenModeOnDevice = 'server';
  String? _activeServerListenMode;
  String _deviceIp = 'Đang tìm IP...';
  String _clientPrintMode = 'direct';
  bool _skipKitchenPrint = false;

  final List<String> _printerRoles = const [
    'cashier_printer',
    'kitchen_printer_a',
    'kitchen_printer_b',
    'kitchen_printer_c',
    'kitchen_printer_d',
    'label_printer'
  ];
  final Map<String, String> _printerRoleLabels = const {
    'cashier_printer': 'Máy in Thu ngân',
    'kitchen_printer_a': 'Máy in A',
    'kitchen_printer_b': 'Máy in B',
    'kitchen_printer_c': 'Máy in C',
    'kitchen_printer_d': 'Máy in D',
    'label_printer': 'Máy in Tem',
  };

  @override
  void initState() {
    super.initState();
    _serverIpController.text = '192.168.1.';
    _settingsService = SettingsService();
    _loadAllSettings();
    _checkDeviceType();
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    await _loadDeviceIp();
    await _loadSavedSettings();
  }

  Future<void> _loadDeviceIp() async {
    String ipAddress = 'Không tìm thấy IP hợp lệ';
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            ipAddress = addr.address;
            break;
          }
        }
        if (ipAddress != 'Không tìm thấy IP hợp lệ') {
          break;
        }
      }
    } catch (e) {
      ipAddress = 'Lỗi khi lấy IP';
      debugPrint('Lỗi lấy IP: $e');
    }
    if (mounted) {
      setState(() {
        _deviceIp = ipAddress;
      });
    }
  }

  Future<void> _checkDeviceType() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.manufacturer.toLowerCase() == 'sunmi') {
        setState(() {
          _isSunmiDevice = true;
        });
      }
    }
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    final userDoc = await _firestoreService.getUserProfile(ownerUid);

    final settingsId = ownerUid;
    try {
      final s = await _settingsService.watchStoreSettings(settingsId).first;

      if (mounted) {
        setState(() {
          _printBillAfterPayment = s.printBillAfterPayment;
          _notifyKitchenAfterPayment = s.notifyKitchenAfterPayment;
          _allowProvisionalBill = s.allowProvisionalBill;
          _showPricesOnBill = s.showPricesOnProvisional;
          _promptForCash = s.promptForCash ?? true;
          _reportCutoffTime = TimeOfDay(
              hour: s.reportCutoffHour ?? 0, minute: s.reportCutoffMinute ?? 0);
          _skipKitchenPrint = s.skipKitchenPrint ?? false;
          _printLabelOnKitchen = s.printLabelOnKitchen ?? false;
          _printLabelOnPayment = s.printLabelOnPayment ?? false;
          _labelWidth = s.labelWidth ?? 50.0;
          _labelHeight = s.labelHeight ?? 30.0;

          if (_labelWidth == 50 && _labelHeight == 30) {
            _selectedLabelSizeOption = '50x30';
          } else if (_labelWidth == 70 && _labelHeight == 22) {
            _selectedLabelSizeOption = '70x22';
          } else {
            _selectedLabelSizeOption = 'custom';
          }
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải cài đặt cửa hàng: $e");
    }

    _clientPrintMode = prefs.getString('client_print_mode') ?? 'direct';
    _isThisDeviceTheServer = prefs.getBool('is_print_server') ?? false;
    String? savedIp = prefs.getString('print_server_ip');
    if (savedIp != null && savedIp.isNotEmpty) {
      _serverIpController.text = savedIp;
    } else {
      _serverIpController.text = '192.168.1.';
    }

    if (mounted && userDoc != null) {
      setState(() {
        _storeNameController.text = userDoc.storeName ?? '';
        _storePhoneController.text = userDoc.storePhone ?? '';
        _storeAddressController.text = userDoc.storeAddress ?? '';
        _activeServerListenMode = userDoc.serverListenMode;
        _serverListenModeOnDevice = userDoc.serverListenMode ?? 'server';
      });
    }

    final jsonString = prefs.getString('printer_assignments');
    if (jsonString != null) {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      if (mounted) {
        setState(() {
          final assignments =
              jsonList.map((json) => ConfiguredPrinter.fromJson(json)).toList();
          _printerAssignments = {for (var v in assignments) v.logicalName: v};

          _printerAssignments.values.where((p) => p != null).forEach((p) {
            if (!_scannedPrinters.contains(p!.physicalPrinter)) {
              _scannedPrinters.add(p.physicalPrinter);
            }
          });
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

      final Map<String, dynamic> userUpdateData = {
        'storeName': _storeNameController.text.trim(),
        'storePhone': _storePhoneController.text.trim(),
        'storeAddress': _storeAddressController.text.trim(),
      };

      if (_isThisDeviceTheServer) {
        userUpdateData['serverListenMode'] = _serverListenModeOnDevice;
      }

      await _firestoreService.updateUserField(ownerUid, userUpdateData);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('client_print_mode', _clientPrintMode);
      await prefs.setBool('is_print_server', _isThisDeviceTheServer);
      await prefs.setString('print_server_ip', _serverIpController.text.trim());

      final settingsService = SettingsService();

      // Logic tính kích thước tem
      if (_labelWidth == 50 && _labelHeight == 30) {
        _selectedLabelSizeOption = '50x30';
      } else if (_labelWidth == 70 && _labelHeight == 22) {
        _selectedLabelSizeOption = '70x22';
      } else {
        _selectedLabelSizeOption = 'custom';
      }

      await settingsService.updateStoreSettings(
        widget.currentUser.ownerUid ?? widget.currentUser.uid,
        {
          'printBillAfterPayment': _printBillAfterPayment,
          'notifyKitchenAfterPayment': _notifyKitchenAfterPayment,
          'allowProvisionalBill': _allowProvisionalBill,
          'showPricesOnProvisional': _showPricesOnBill,
          'reportCutoffHour': _reportCutoffTime.hour,
          'reportCutoffMinute': _reportCutoffTime.minute,
          'promptForCash': _promptForCash,
          'skipKitchenPrint': _skipKitchenPrint,
          'printLabelOnKitchen': _printLabelOnKitchen,
          'printLabelOnPayment': _printLabelOnPayment,
          'labelWidth': _labelWidth,
          'labelHeight': _labelHeight,
        },
      );

      final List<Map<String, dynamic>> listToSave = _printerAssignments.values
          .where((p) => p != null)
          .map((p) => p!.toJson())
          .toList();
      await prefs.setString('printer_assignments', jsonEncode(listToSave));

      ToastService().show(message: "Đã lưu cài đặt!", type: ToastType.success);
      if (_isThisDeviceTheServer) {
        await CloudPrintService().startListener(
            widget.currentUser.storeId, _serverListenModeOnDevice);
      } else {
        await CloudPrintService().stopListener();
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
      ToastService().show(
          message: "Lỗi khi lưu cài đặt: ${e.toString()}",
          type: ToastType.error);
    }
  }

  Future<void> _selectReportCutoffTime() async {
    final newTime = await showTimePicker(
      context: context,
      initialTime: _reportCutoffTime,
      helpText: 'CHỌN GIỜ CHỐT BÁO CÁO',
    );
    if (newTime != null && mounted) {
      setState(() {
        _reportCutoffTime = newTime;
      });
    }
  }

  void _discoverPrinters() async {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
    });

    final Set<ScannedPrinter> tempPrinters = {};

    debugPrint(">>> BẮT ĐẦU QUÉT MÁY IN...");

    if (isDesktop) {
      try {
        final systemPrinters = await Printing.listPrinters();
        debugPrint(">>> WINDOWS TRẢ VỀ ${systemPrinters.length} MÁY IN:");
        for (var p in systemPrinters) {
          tempPrinters.add(ScannedPrinter(
            device: pos_printer.PrinterDevice(
              name: p.name,
              address: p.name,
              vendorId: 'DRIVER_WINDOWS',
            ),
            type: pos_printer.PrinterType.usb,
          ));
        }
      } catch (e) {
        debugPrint(">>> LỖI KHI ĐỌC DRIVER WINDOWS: $e");
        ToastService()
            .show(message: "Lỗi đọc Driver Windows: $e", type: ToastType.error);
      }
    }

    if (_isSunmiDevice) {
      tempPrinters.add(ScannedPrinter(
        device: pos_printer.PrinterDevice(
          name: 'Máy in Sunmi Tích hợp',
          address: 'sunmi_internal',
          vendorId: 'SUNMI',
        ),
        type: pos_printer.PrinterType.usb,
      ));
    }

    if (mounted) {
      setState(() {
        _scannedPrinters.clear();
        _scannedPrinters.addAll(tempPrinters);
      });
    }

    // Chỉ lắng nghe USB/Network nếu không phải Desktop hoặc cần thiết
    // Lưu ý: Trên mobile, discovery có thể gây lag nếu setState quá nhiều lần liên tục
    if (!isDesktop) {
      _printerManager
          .discovery(type: pos_printer.PrinterType.usb)
          .listen((printer) {
        final scanned =
        ScannedPrinter(device: printer, type: pos_printer.PrinterType.usb);
        // Kiểm tra kỹ trước khi setState để giảm tải UI
        if (!_scannedPrinters.any((p) =>
        p.device.name == printer.name &&
            p.device.address == printer.address)) {
          if (mounted) setState(() => _scannedPrinters.add(scanned));
        }
      });

      _printerManager
          .discovery(type: pos_printer.PrinterType.network)
          .listen((printer) {
        final scanned = ScannedPrinter(
            device: printer, type: pos_printer.PrinterType.network);
        if (!_scannedPrinters.any((p) => p.device.address == printer.address)) {
          if (mounted) setState(() => _scannedPrinters.add(scanned));
        }
      });
    }

    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isScanning = false);
      debugPrint(">>> KẾT THÚC QUÉT.");
    });
  }

  Future<void> _addManualPrinter() async {
    final ipController = TextEditingController(text: '192.168.1.');
    final ip = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm máy in LAN thủ công'),
        content: TextField(
          controller: ipController,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: 'Địa chỉ IP của máy in',
              hintText: 'Ví dụ: 192.168.1.101'),
          keyboardType: TextInputType.text,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Hủy')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(ipController.text.trim()),
              child: const Text('Thêm')),
        ],
      ),
    );

    if (ip != null && ip.isNotEmpty) {
      final newPrinterDevice =
          pos_printer.PrinterDevice(name: 'LAN Printer ($ip)', address: ip);
      final newScannedPrinter = ScannedPrinter(
          device: newPrinterDevice, type: pos_printer.PrinterType.network);

      if (mounted) {
        setState(() {
          if (!_scannedPrinters.contains(newScannedPrinter)) {
            _scannedPrinters.add(newScannedPrinter);
          }
        });
      }
      ToastService().show(
          message: 'Đã thêm máy in vào danh sách lựa chọn.',
          type: ToastType.success);
    }
  }

  String _getPrinterUniqueId(ScannedPrinter printer) {
    return '${printer.device.name}|${printer.device.address ?? ''}|${printer.device.vendorId ?? ''}|${printer.device.productId ?? ''}';
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.currentUser.role;

    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt'), actions: [
        if (_isSaving)
          const Padding(
            padding: EdgeInsets.only(right: 16.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.primaryColor,
                ),
              ),
            ),
          )
        else
          IconButton(
              icon: const Icon(Icons.save,
                  color: AppTheme.primaryColor, size: 30),
              onPressed: _saveSettings)
      ]),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            if (role == 'owner') ...[
              _buildSectionTitle('Thông tin Cửa hàng'),
              CustomTextFormField(
                  controller: _storeNameController,
                  decoration: const InputDecoration(labelText: 'Tên cửa hàng')),
              const SizedBox(height: 16),
              CustomTextFormField(
                  controller: _storePhoneController,
                  decoration:
                      const InputDecoration(labelText: 'Số điện thoại')),
              const SizedBox(height: 16),
              CustomTextFormField(
                  controller: _storeAddressController,
                  decoration: const InputDecoration(labelText: 'Địa chỉ')),
            ],
            if (role == 'owner' || role == 'manager') ...[
              const SizedBox(height: 16),
              const Divider(height: 2, thickness: 0.5, color: Colors.grey),
              _buildSectionTitle('Tùy chọn in:'),
              SwitchListTile(
                title: const Text('In hóa đơn sau khi Thanh toán'),
                value: _printBillAfterPayment,
                onChanged: (bool value) =>
                    setState(() => _printBillAfterPayment = value),
                secondary: const Icon(Icons.print_outlined),
              ),
              SwitchListTile(
                title: const Text('In tem sau khi Thanh toán'),
                value: _printLabelOnPayment,
                onChanged: (val) => setState(() => _printLabelOnPayment = val),
                secondary: const Icon(Icons.new_label_outlined),
              ),
              SwitchListTile(
                title: const Text('In tem khi báo Chế biến'),
                value: _printLabelOnKitchen,
                onChanged: (val) => setState(() => _printLabelOnKitchen = val),
                secondary: const Icon(Icons.label_outline),
              ),
              SwitchListTile(
                title: const Text('In báo chế biến trước khi thanh toán'),
                value: _notifyKitchenAfterPayment,
                onChanged: (bool value) =>
                    setState(() => _notifyKitchenAfterPayment = value),
                secondary: const Icon(Icons.fastfood_outlined),
              ),
              SwitchListTile(
                title: const Text('Không in báo chế biến khi gởi món'),
                subtitle: const Text(
                    'Nếu bật sẽ không in báo chế biến từ các máy in A B C D.'),
                value: _skipKitchenPrint,
                onChanged: (bool value) =>
                    setState(() => _skipKitchenPrint = value),
                secondary: const Icon(Icons.print_disabled_outlined),
              ),
              SwitchListTile(
                title: const Text('Cho phép in tạm tính nhanh hoặc kiểm món'),
                value: _allowProvisionalBill,
                onChanged: (bool value) =>
                    setState(() => _allowProvisionalBill = value),
                secondary: const Icon(Icons.receipt_outlined),
              ),
              SwitchListTile(
                title:
                    const Text('Hiển thị giá tiền trên phiếu tạm tính nhanh'),
                subtitle: const Text('Tắt để chuyển sang in phiếu kiểm món.'),
                value: _showPricesOnBill,
                onChanged: (bool value) =>
                    setState(() => _showPricesOnBill = value),
                secondary: const Icon(Icons.price_change_outlined),
              ),
              const SizedBox(height: 16),
              const Divider(height: 2, thickness: 0.5, color: Colors.grey),
              _buildSectionTitle('Thiết lập:'),
              SwitchListTile(
                title: const Text(
                    'Yêu cầu thu ngân phải xác nhận mệnh giá tiền mặt'),
                value: _promptForCash,
                onChanged: (bool value) =>
                    setState(() => _promptForCash = value),
                secondary: const Icon(Icons.calculate_outlined),
              ),
              ListTile(
                isThreeLine: true,
                leading: const Icon(Icons.access_time),
                title: const Text('Giờ chốt sổ báo cáo hàng ngày'),
                subtitle: Text(
                    'Báo cáo hàng ngày chỉ áp dụng từ thời đểm thay đổi cài đặt giờ chốt sổ trở về sau.'),
                trailing: Text(
                  _reportCutoffTime.format(context),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppTheme.primaryColor, fontSize: 20),
                ),
                onTap: _selectReportCutoffTime,
              ),
            ],
            const SizedBox(width: 16),
            const Divider(height: 8, thickness: 0.5, color: Colors.grey,),
            _buildSectionTitle('Kết nối máy in:'),
            ListTile(
              leading: const Icon(Icons.lan_outlined),
              title: const Text('IP của thiết bị này'),
              subtitle: Text(_deviceIp),
            ),
            SwitchListTile(
              title: const Text('Kích hoạt chế độ máy chủ'),
              subtitle: const Text(
                  'Bật để nhận lệnh in từ các thiết bị khác.'),
              value: _isThisDeviceTheServer,
              onChanged: (bool value) =>
                  setState(() => _isThisDeviceTheServer = value),
              secondary: const Icon(Icons.connected_tv),
            ),
            if (_isThisDeviceTheServer) ...[
              _buildSectionTitle('Chọn chế độ cho phép kết nối'),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'server', label: Text('Nội bộ (LAN)')),
                    ButtonSegment(
                        value: 'internet', label: Text('Internet (Cloud)')),
                  ],
                  selected: {_serverListenModeOnDevice},
                  onSelectionChanged: (newSelection) => setState(
                      () => _serverListenModeOnDevice = newSelection.first),
                ),
              ),
            ],
            if (!_isThisDeviceTheServer) ...[
              _buildSectionTitle('Chế độ in:'),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'direct', label: Text('Trực tiếp')),
                  ButtonSegment(value: 'server', label: Text('LAN')),
                  ButtonSegment(value: 'internet', label: Text('Internet')),
                ],
                selected: {_clientPrintMode},
                onSelectionChanged: (newSelection) {
                  final mode = newSelection.first;
                  if (mode == 'server' || mode == 'internet') {
                    if (_activeServerListenMode == null) {
                      ToastService().show(
                        message: 'Chưa có máy chủ nào được cấu hình.',
                        type: ToastType.warning,
                      );
                      return;
                    }
                    if (mode != _activeServerListenMode) {
                      final serverModeText = _activeServerListenMode == 'server'
                          ? 'Nội bộ (LAN)'
                          : 'Internet (Cloud)';
                      ToastService().show(
                        message:
                            'Máy chủ đang hoạt động ở chế độ "$serverModeText". Bạn không thể chọn chế độ khác.',
                        type: ToastType.error,
                      );
                      return;
                    }
                  }
                  setState(() => _clientPrintMode = mode);
                },
              ),
              const SizedBox(height: 16),
              if (_clientPrintMode == 'server')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextFormField(
                      controller: _serverIpController,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ IP của Máy chủ Nội bộ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chỉ những thiết bị có kết nối chung mạng wifi với máy chủ mới có thể gởi lệnh in!',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: Colors.red),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            if (_isThisDeviceTheServer || _clientPrintMode == 'direct') ...[
              _buildSectionTitle('Gán máy in'),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: _isScanning
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: Text(_isScanning ? 'Đang quét...' : 'Quét máy in'),
                    onPressed: _isScanning ? null : _discoverPrinters,
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('Thêm máy in LAN'),
                    onPressed: _addManualPrinter,
                    style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryColor),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildPrinterAssignments(),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildPrinterAssignments() {
    return Column(
      children: _printerRoles.map((roleKey) {
        final assignedPrinterConfig = _printerAssignments[roleKey];
        final selectedPrinterId = assignedPrinterConfig != null
            ? _getPrinterUniqueId(assignedPrinterConfig.physicalPrinter)
            : null;

        // Kiểm tra xem máy in đã lưu có còn tồn tại trong danh sách quét không
        final bool isPrinterAvailable = _scannedPrinters
            .any((p) => _getPrinterUniqueId(p) == selectedPrinterId);

        final validValue = isPrinterAvailable ? selectedPrinterId : null;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dòng 1: Chọn máy in + Nút xóa
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: AppDropdown(
                      labelText: _printerRoleLabels[roleKey] ?? roleKey,
                      value: validValue,
                      items: _scannedPrinters.map((p) {
                        return DropdownMenuItem(
                          value: _getPrinterUniqueId(p),
                          child: Text(
                            p.device.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (newValueId) {
                        if (newValueId == null) return;
                        final selectedPrinter =
                        _scannedPrinters.firstWhereOrNull(
                                (p) => _getPrinterUniqueId(p) == newValueId);

                        if (selectedPrinter != null) {
                          setState(() {
                            _printerAssignments[roleKey] = ConfiguredPrinter(
                              logicalName: roleKey,
                              physicalPrinter: selectedPrinter,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  // Nút Xóa
                  IconButton(
                    icon: const Icon(Icons.clear, color: Colors.grey),
                    onPressed: () {
                      if (_printerAssignments[roleKey] != null) {
                        setState(() => _printerAssignments[roleKey] = null);
                      }
                    },
                  ),
                ],
              ),

              // Dòng 2: Chọn kích thước tem (Chỉ hiện nếu là Label Printer và không phải Desktop)
              if (roleKey == 'label_printer' && !isDesktop) ...[
                const SizedBox(height: 16), // Khoảng cách giữa dòng chọn máy in và chọn khổ giấy
                Row(
                  children: [
                    Expanded(
                      child: AppDropdown<String>(
                        labelText: 'Kích thước tem',
                        value: _selectedLabelSizeOption,
                        items: const [
                          DropdownMenuItem(value: '50x30', child: Text('50x30mm')),
                          DropdownMenuItem(value: '70x22', child: Text('70x22mm')),
                          DropdownMenuItem(
                              value: 'custom', child: Text('Tùy chỉnh...')),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedLabelSizeOption = val!;
                            if (val == '50x30') {
                              _labelWidth = 50;
                              _labelHeight = 30;
                            } else if (val == '70x22') {
                              _labelWidth = 70;
                              _labelHeight = 22;
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),

                // Dòng 3: Nhập tay kích thước (Nếu chọn Tùy chỉnh)
                if (_selectedLabelSizeOption == 'custom')
                  Padding(
                    padding: const EdgeInsets.only(top: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                            child: CustomTextFormField(
                              initialValue: _labelWidth.toInt().toString(),
                              decoration: const InputDecoration(
                                  labelText: 'Rộng (mm)', isDense: true),
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              onChanged: (v) {
                                _labelWidth = (int.tryParse(v) ?? 50).toDouble();
                              },
                            )),
                        const SizedBox(width: 16),
                        Expanded(
                            child: CustomTextFormField(
                              initialValue: _labelHeight.toInt().toString(),
                              decoration: const InputDecoration(
                                  labelText: 'Cao (mm)', isDense: true),
                              keyboardType: const TextInputType.numberWithOptions(decimal: false),
                              onChanged: (v) {
                                _labelHeight = (int.tryParse(v) ?? 30).toDouble();
                              },
                            )),
                        // Bù khoảng trống để input không bị lệch so với layout chung
                        const SizedBox(width: 48),
                      ],
                    ),
                  ),
              ]
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}
