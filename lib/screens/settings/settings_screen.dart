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
import '../../models/store_settings_model.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../services/cloud_print_service.dart';
import '../../services/settings_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../widgets/app_dropdown.dart';
import 'dart:io';
import '../../widgets/custom_text_form_field.dart';

class ScannedPrinter {
  final pos_printer.PrinterDevice device;
  final pos_printer.PrinterType type;

  ScannedPrinter({required this.device, required this.type});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ScannedPrinter &&
        other.device.address == device.address &&
        other.device.vendorId == device.vendorId &&
        other.device.productId == device.productId;
  }

  @override
  int get hashCode =>
      device.address.hashCode ^
      device.vendorId.hashCode ^
      device.productId.hashCode;
}

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
  StreamSubscription<StoreSettings>? _settingsSub;

  bool _isThisDeviceTheServer = false;
  bool _showPricesOnBill = false;
  bool _isSunmiDevice = false;
  bool _isScanning = false;
  bool _printBillAfterPayment = true;
  bool _notifyKitchenAfterPayment = false;
  bool _allowProvisionalBill = true;
  bool _promptForCash = true;
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);


  String _serverListenModeOnDevice = 'server';
  String? _activeServerListenMode;
  String _deviceIp = 'Đang tìm IP...';
  String _clientPrintMode = 'direct';

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
    _settingsService = SettingsService();
    final settingsId = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    _settingsSub = _settingsService.watchStoreSettings(settingsId).listen((s) {
      if (!mounted) return;
      setState(() {
        _printBillAfterPayment     = s.printBillAfterPayment;
        _notifyKitchenAfterPayment = s.notifyKitchenAfterPayment;
        _allowProvisionalBill      = s.allowProvisionalBill;
        _showPricesOnBill          = s.showPricesOnProvisional;
        _promptForCash             = s.promptForCash ?? true;
        _reportCutoffTime = TimeOfDay(
            hour: s.reportCutoffHour ?? 0,
            minute: s.reportCutoffMinute ?? 0
        );
      });
    });

    _loadAllSettings();
    _checkDeviceType();
  }

  @override
  void dispose() {
    _serverIpController.dispose();
    _storeNameController.dispose();
    _storePhoneController.dispose();
    _storeAddressController.dispose();
    _settingsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadAllSettings() async {
    await _loadDeviceIp();
    await _loadSavedSettings();
    _discoverPrinters();
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
    _clientPrintMode = prefs.getString('client_print_mode') ?? 'direct';
    _isThisDeviceTheServer = prefs.getBool('is_print_server') ?? false;
    _serverIpController.text = prefs.getString('print_server_ip') ?? '';

    final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
    final userDoc = await _firestoreService.getUserProfile(ownerUid);

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

  void _discoverPrinters() {
    if (!mounted) return;
    setState(() {
      _isScanning = true;
    });

    _scannedPrinters.clear();

    if (_isSunmiDevice) {
      final sunmiInternalPrinter = pos_printer.PrinterDevice(
        name: 'Máy in Sunmi Tích hợp',
        address: 'sunmi_internal',
      );
      _scannedPrinters.add(ScannedPrinter(
        device: sunmiInternalPrinter,
        type: pos_printer.PrinterType.usb,
      ));
    }

    _printerAssignments.values.where((p) => p != null).forEach((p) {
      if (!_scannedPrinters.contains(p!.physicalPrinter)) {
        _scannedPrinters.add(p.physicalPrinter);
      }
    });

    _printerManager
        .discovery(type: pos_printer.PrinterType.usb)
        .listen((printer) {
      final scanned =
      ScannedPrinter(device: printer, type: pos_printer.PrinterType.usb);
      if (!_scannedPrinters.contains(scanned) && mounted) {
        setState(() => _scannedPrinters.add(scanned));
      }
    });

    if (!isDesktop) {
      _printerManager
          .discovery(type: pos_printer.PrinterType.network)
          .listen((printer) {
        final scanned = ScannedPrinter(
            device: printer, type: pos_printer.PrinterType.network);
        if (!_scannedPrinters.contains(scanned) && mounted) {
          setState(() => _scannedPrinters.add(scanned));
        }
      });
    }

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  Future<void> _addManualPrinter() async {
    final ipController = TextEditingController();
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
          keyboardType: TextInputType.number,
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
        IconButton(icon: const Icon(Icons.save), onPressed: _saveSettings)
      ]),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            _buildSectionTitle('Thông tin Cửa hàng'),
            CustomTextFormField(
                controller: _storeNameController,
                decoration: const InputDecoration(labelText: 'Tên cửa hàng')),
            const SizedBox(height: 16),
            CustomTextFormField(
                controller: _storePhoneController,
                decoration: const InputDecoration(labelText: 'Số điện thoại')),
            const SizedBox(height: 16),
            CustomTextFormField(
                controller: _storeAddressController,
                decoration: const InputDecoration(labelText: 'Địa chỉ')),

            const Divider(height: 32),

            _buildSectionTitle('Vai trò & Mạng'),
            ListTile(
              leading: const Icon(Icons.lan_outlined),
              title: const Text('IP của thiết bị này'),
              subtitle: Text(_deviceIp),
            ),

            if (role == 'owner' || role == 'manager') ...[
              SwitchListTile(
                title: const Text('In bill sau khi thanh toán'),
                value: _printBillAfterPayment,
                onChanged: (bool value) =>
                    setState(() => _printBillAfterPayment = value),
                secondary: const Icon(Icons.receipt_long_outlined),
              ),
              SwitchListTile(
                title: const Text('Báo chế biến trước khi thanh toán'),
                value: _notifyKitchenAfterPayment,
                onChanged: (bool value) =>
                    setState(() => _notifyKitchenAfterPayment = value),
                secondary: const Icon(Icons.soup_kitchen_outlined),
              ),
              SwitchListTile(
                title: const Text('Cho phép in tạm tính'),
                value: _allowProvisionalBill,
                onChanged: (bool value) =>
                    setState(() => _allowProvisionalBill = value),
                secondary: const Icon(Icons.receipt_outlined),
              ),
              SwitchListTile(
                title: const Text('Hiển thị giá tiền trên Phiếu tạm tính'),
                value: _showPricesOnBill,
                onChanged: (bool value) =>
                    setState(() => _showPricesOnBill = value),
                secondary: const Icon(Icons.price_change_outlined),
              ),
              SwitchListTile(
                title: const Text('Xác nhận mệnh giá tiền mặt khách đưa khi thanh toán'),
                value: _promptForCash,
                onChanged: (bool value) =>
                    setState(() => _promptForCash = value),
                secondary: const Icon(Icons.calculate_outlined),
              ),
              ListTile(
                isThreeLine: true,
                leading: const Icon(Icons.access_time),
                title: const Text('Giờ chốt sổ báo cáo hàng ngày'),
                subtitle: Text('Báo cáo "Hôm nay" sẽ tính từ ${_reportCutoffTime.format(context)} hôm nay đến ${_reportCutoffTime.format(context)} hôm sau. Báo cáo doanh thu chỉ áp dụng từ thời đểm thay đổi cài đặt giờ chốt sổ trở về sau.'),
                trailing: Text(
                  _reportCutoffTime.format(context),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppTheme.primaryColor,
                      fontSize: 20
                  ),
                ),
                onTap: _selectReportCutoffTime,
              ),
              const Divider(height: 32),
            ],
            SwitchListTile(
              title: const Text('Kích hoạt chế độ máy chủ'),
              subtitle: const Text('Thiết bị này sẽ nhận lệnh in từ các thiết bị khác'),
              value: _isThisDeviceTheServer,
              onChanged: (bool value) =>
                  setState(() => _isThisDeviceTheServer = value),
              secondary: const Icon(Icons.connected_tv),
            ),

            if (_isThisDeviceTheServer) ...[
              const Divider(height: 32),
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
              const Divider(height: 32),
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
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ IP của Máy chủ Nội bộ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Chỉ những thiết bị có kết nối chung mạng wifi với máy chủ mới có thể gởi lệnh in!',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.red),
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

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: AppDropdown(
                  labelText: _printerRoleLabels[roleKey] ?? roleKey,
                  value: selectedPrinterId,
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
                    final selectedPrinter = _scannedPrinters.firstWhereOrNull(
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
