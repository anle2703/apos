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
import '../../widgets/app_dropdown.dart';
import 'dart:io';
import '../../widgets/custom_text_form_field.dart';
import 'package:printing/printing.dart';
import 'label_setup_screen.dart';
import '../../services/native_printer_service.dart';
import 'receipt_setup_screen.dart';

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
  bool _isScanning = false;
  bool _isSaving = false;
  bool _printBillAfterPayment = true;
  bool _notifyKitchenAfterPayment = false;
  bool _allowProvisionalBill = false;
  bool _promptForCash = true;

  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  bool _printLabelOnKitchen = false;
  bool _printLabelOnPayment = false;
  double _labelWidth = 50.0;
  double _labelHeight = 30.0;

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

  String _selectedCategory = 'printer_connection'; // Default category

  @override
  void initState() {
    super.initState();
    _serverIpController.text = '192.168.1.';
    _settingsService = SettingsService();
    if (widget.currentUser.role == 'owner') {
      _selectedCategory = 'store_info';
    } else {
      _selectedCategory = 'print_options';
    }
    _loadAllSettings();
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
      _scannedPrinters.clear();
    });

    debugPrint(">>> BẮT ĐẦU QUÉT MÁY IN...");

    if (isDesktop) {
      try {
        final systemPrinters = await Printing.listPrinters();
        for (var p in systemPrinters) {
          _scannedPrinters.add(ScannedPrinter(
            device: pos_printer.PrinterDevice(
                name: p.name, address: p.name, vendorId: 'DRIVER_WINDOWS'),
            type: pos_printer.PrinterType.usb,
          ));
        }
      } catch (e) {
        debugPrint("Lỗi Windows: $e");
      }
    }

    if (!isDesktop) {
      final nativeService = NativePrinterService();

      try {
        final devices = await nativeService.getPrinters();
        for (var device in devices) {
          final String realId = device.identifier; // Địa chỉ động (ví dụ: /dev/usb/001)
          final String vid = device.vendorId.toString();
          final String pid = device.productId.toString();

          // Tạo tên hiển thị kèm VID:PID để bạn dễ phân biệt khi chọn
          final String displayName = "${device.name} (USB $vid:$pid)";

          final p = pos_printer.PrinterDevice(
            name: displayName, // Lưu tên gốc vào đây (thư viện sẽ dùng tên này)
            address: realId,   // Địa chỉ động để kết nối
            vendorId: vid,
            productId: pid,
          );

          final scanned = ScannedPrinter(device: p, type: pos_printer.PrinterType.usb);

          if (mounted) {
            setState(() {
              // Logic check trùng lặp dựa trên ID mới (USB:VID:PID:NAME)
              final uniqueId = _getPrinterUniqueId(scanned);
              if (!_scannedPrinters.any((p) => _getPrinterUniqueId(p) == uniqueId)) {
                _scannedPrinters.add(scanned);
              }
            });
          }
        }
      } catch (e) {
        debugPrint("Lỗi quét Native: $e");
      }

      _printerManager
          .discovery(type: pos_printer.PrinterType.network)
          .listen((printer) {
        if (mounted) {
          setState(() {
            if (!_scannedPrinters
                .any((p) => p.device.address == printer.address)) {
              _scannedPrinters.add(ScannedPrinter(
                  device: printer, type: pos_printer.PrinterType.network));
            }
          });
        }
      });
    }

    Future.delayed(const Duration(seconds: 1), () async {
      if (mounted) {
        bool hasChanged = false;

        setState(() {
          _isScanning = false;

          // Duyệt qua các máy in ĐÃ ĐƯỢC GÁN (ví dụ: Máy in Bếp, Thu ngân...)
          _printerAssignments.forEach((role, config) {
            if (config != null && config.physicalPrinter.type == pos_printer.PrinterType.usb) {

              final savedVid = config.physicalPrinter.device.vendorId.toString();
              final savedPid = config.physicalPrinter.device.productId.toString();

              // 1. Thử tìm chính xác theo Unique ID (Logic cũ)
              final savedId = _getPrinterUniqueId(config.physicalPrinter);
              var foundPrinter = _scannedPrinters.firstWhereOrNull(
                      (p) => _getPrinterUniqueId(p) == savedId);

              // 2. Nếu không tìm thấy theo ID (do đổi tên), tìm theo VID + PID (Logic mới quan trọng)
              if (foundPrinter == null) {
                foundPrinter = _scannedPrinters.firstWhereOrNull((p) {
                  final pVid = p.device.vendorId.toString();
                  final pPid = p.device.productId.toString();
                  return pVid == savedVid && pPid == savedPid;
                });
                if (foundPrinter != null) {
                  debugPrint(">>> UI: Tìm thấy máy in $role qua VID/PID (Tên có thể đã đổi).");
                }
              }

              // 3. Nếu tìm thấy máy in tương ứng
              if (foundPrinter != null) {
                // Kiểm tra xem Address có khác không
                if (config.physicalPrinter.device.address != foundPrinter.device.address) {
                  debugPrint(">>> UI Auto-update address cho $role: ${config.physicalPrinter.device.address} -> ${foundPrinter.device.address}");

                  // Cập nhật lại config với máy in mới tìm thấy
                  _printerAssignments[role] = ConfiguredPrinter(
                      logicalName: role,
                      physicalPrinter: foundPrinter // Dùng object mới quét được (có address mới)
                  );
                  hasChanged = true;
                }
              }
            }
          });
        });

        // Lưu lại nếu có thay đổi
        if (hasChanged) {
          try {
            final prefs = await SharedPreferences.getInstance();
            final List<Map<String, dynamic>> listToSave = _printerAssignments.values
                .where((p) => p != null)
                .map((p) => p!.toJson())
                .toList();
            await prefs.setString('printer_assignments', jsonEncode(listToSave));
            debugPrint(">>> Đã lưu địa chỉ máy in mới xuống bộ nhớ thành công.");

            ToastService().show(
                message: "Đã tự động cập nhật cổng kết nối máy in!",
                type: ToastType.success
            );
          } catch (e) {
            debugPrint(">>> Lỗi khi lưu cập nhật máy in tự động: $e");
          }
        }
      }
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
    if (printer.type == pos_printer.PrinterType.usb) {
      final vid = printer.device.vendorId;
      final pid = printer.device.productId;
      final name = printer.device.name;

      if (vid != null && pid != null && vid.isNotEmpty && pid.isNotEmpty) {
        // Định danh: USB:VID:PID:NAME
        // Bỏ qua serial vì thư viện không hỗ trợ
        return 'USB:$vid:$pid:$name';
      }
    }
    return '${printer.device.name}|${printer.device.vendorId ?? ''}|${printer.device.productId ?? ''}';
  }

  Widget _buildStoreInfoContent() {
    if (widget.currentUser.role != 'owner') {
      return const Center(child: Text("Chỉ chủ cửa hàng mới được truy cập mục này."));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
      ],
    );
  }

  Widget _buildPrintOptionsContent() {
    // Kiểm tra xem có phải mô hình Retail không
    final bool isRetail = widget.currentUser.businessType == 'retail';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Tùy chọn in'),

        // Dòng này luôn hiện cho cả Retail và F&B
        SwitchListTile(
          title: const Text('In hóa đơn sau khi Thanh toán'),
          value: _printBillAfterPayment,
          onChanged: (bool value) =>
              setState(() => _printBillAfterPayment = value),
          secondary: const Icon(Icons.print_outlined),
        ),

        // Các tùy chọn bên dưới chỉ hiện nếu KHÔNG PHẢI là Retail
        if (!isRetail) ...[
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
            onChanged: (bool value) => setState(() => _skipKitchenPrint = value),
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
            title: const Text('Hiển thị giá tiền trên phiếu tạm tính nhanh'),
            subtitle: const Text('Tắt để chuyển sang in phiếu kiểm món.'),
            value: _showPricesOnBill,
            onChanged: (bool value) => setState(() => _showPricesOnBill = value),
            secondary: const Icon(Icons.price_change_outlined),
          ),
        ],
      ],
    );
  }

  Widget _buildGeneralSettingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Thiết lập chung'),
        SwitchListTile(
          title: const Text('Yêu cầu thu ngân phải xác nhận mệnh giá tiền mặt'),
          value: _promptForCash,
          onChanged: (bool value) => setState(() => _promptForCash = value),
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
    );
  }

  Widget _buildPrinterConnectionContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Kết nối & Thiết bị'),
        ListTile(
          leading: const Icon(Icons.lan_outlined),
          title: const Text('IP của thiết bị này'),
          subtitle: Text(_deviceIp),
        ),
        SwitchListTile(
          title: const Text('Kích hoạt chế độ máy chủ'),
          subtitle: const Text('Bật để nhận lệnh in từ các thiết bị khác.'),
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
                style:
                TextButton.styleFrom(foregroundColor: AppTheme.primaryColor),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPrinterAssignments(),
        ]
      ],
    );
  }

  // --- LAYOUT METHODS ---

  Widget _buildMobileLayout() {
    final role = widget.currentUser.role;
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        if (role == 'owner') ...[
          _buildStoreInfoContent(),
          const SizedBox(height: 16),
          const Divider(height: 2, thickness: 0.5, color: Colors.grey),
        ],
        if (role == 'owner' || role == 'manager') ...[
          _buildPrintOptionsContent(),
          const SizedBox(height: 16),
          const Divider(height: 2, thickness: 0.5, color: Colors.grey),
          _buildGeneralSettingsContent(),
        ],
        const SizedBox(height: 16),
        const Divider(height: 8, thickness: 0.5, color: Colors.grey),
        _buildPrinterConnectionContent(),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    final role = widget.currentUser.role;
    final isOwner = role == 'owner';
    final isManager = role == 'manager';
    final canAccessSettings = isOwner || isManager;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LEFT MENU
        SizedBox(
          width: 280,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              if (isOwner)
                _buildMenuTile('store_info', 'Thông tin cửa hàng', Icons.store),
              if (canAccessSettings) ...[
                _buildMenuTile(
                    'general_settings', 'Thiết lập chung', Icons.settings),
                _buildMenuTile(
                    'print_options', 'Tùy chọn in', Icons.print_outlined),
              ],
              _buildMenuTile('printer_connection', 'Kết nối máy in',
                  Icons.compare_arrows),
            ],
          ),
        ),

        Expanded(
          child: Container(
            color: Colors.grey.shade50,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: _buildRightPanelContent(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMenuTile(String key, String title, IconData icon) {
    final isSelected = _selectedCategory == key;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor.withAlpha(25) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(icon,
            color: isSelected ? AppTheme.primaryColor : Colors.grey[700]),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? AppTheme.primaryColor : Colors.black87,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        onTap: () {
          setState(() {
            _selectedCategory = key;
          });
        },
      ),
    );
  }

  Widget _buildRightPanelContent() {
    switch (_selectedCategory) {
      case 'store_info':
        return _buildStoreInfoContent();
      case 'general_settings':
        return _buildGeneralSettingsContent();
      case 'print_options':
        return _buildPrintOptionsContent();
      case 'printer_connection':
        return _buildPrinterConnectionContent();
      default:
        return _buildPrinterConnectionContent();
    }
  }

  @override
  Widget build(BuildContext context) {
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth > 1000) {
              return _buildDesktopLayout();
            } else {
              return _buildMobileLayout();
            }
          },
        ),
      ),
    );
  }

  Widget _buildPrinterAssignments() {
    // 1. Xác định ID của máy in đang được gán làm "Máy in Tem"
    String? assignedLabelPrinterId;
    final labelConfig = _printerAssignments['label_printer'];
    if (labelConfig != null) {
      assignedLabelPrinterId = _getPrinterUniqueId(labelConfig.physicalPrinter);
    }

    // 2. Xác định danh sách ID của các máy in đang làm nhiệm vụ "In Bill" (Thu ngân + Các Bếp)
    // (Trừ máy in Tem ra)
    final Set<String> assignedBillPrinterIds = {};
    _printerAssignments.forEach((key, value) {
      if (key != 'label_printer' && value != null) {
        assignedBillPrinterIds.add(_getPrinterUniqueId(value.physicalPrinter));
      }
    });

    final bool isRetail = widget.currentUser.businessType == 'retail';

    final List<String> visibleRoles = _printerRoles.where((role) {
      if (isRetail) {
        // Retail: Chỉ hiện Thu ngân và Tem
        return role == 'cashier_printer' || role == 'label_printer';
      }
      // FnB: Hiện tất cả (bao gồm Bếp A, B, C, D)
      return true;
    }).toList();

    return Column(
      children: visibleRoles.map((roleKey) {
        final assignedPrinterConfig = _printerAssignments[roleKey];
        final currentSelectedId = assignedPrinterConfig != null
            ? _getPrinterUniqueId(assignedPrinterConfig.physicalPrinter)
            : null;

        final availablePrinters = _scannedPrinters.where((p) {
          final pId = _getPrinterUniqueId(p);

          if (pId == currentSelectedId) return true;

          if (roleKey == 'label_printer') {
            if (assignedBillPrinterIds.contains(pId)) return false;
          } else {
            if (pId == assignedLabelPrinterId) return false;
          }

          return true;
        }).toList();

        final bool isPrinterAvailable = _scannedPrinters
            .any((p) => _getPrinterUniqueId(p) == currentSelectedId);

        final validValue = isPrinterAvailable ? currentSelectedId : null;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: AppDropdown(
                      labelText: _printerRoleLabels[roleKey] ?? roleKey,
                      value: validValue,
                      items: availablePrinters.map((p) {
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

                        // Tìm máy in trong danh sách vừa quét
                        final selectedPrinter = _scannedPrinters.firstWhereOrNull(
                                (p) => _getPrinterUniqueId(p) == newValueId);

                        if (selectedPrinter != null) {
                          setState(() {
                            // Lưu máy in với thông tin mới nhất (bao gồm address động mới)
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
              if (roleKey == 'cashier_printer') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (context) => ReceiptSetupScreen(
                                    currentUser: widget.currentUser)),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Cấu hình mẫu in',
                            labelStyle: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                              color: Colors.grey[600],
                            ),
                            suffixIcon: const Padding(
                              padding: EdgeInsets.only(right: 12.0),
                              child: Icon(Icons.arrow_forward_ios,
                                  size: 16, color: AppTheme.primaryColor),
                            ),
                            contentPadding:
                            const EdgeInsets.fromLTRB(12, 16, 12, 16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              BorderSide(color: Colors.grey.shade300),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                          ),
                          child: Text(
                            "Thiết lập mẫu in",
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.settings_suggest_outlined,
                          color: Colors.grey),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) => ReceiptSetupScreen(
                                  currentUser: widget.currentUser)),
                        );
                      },
                    ),
                  ],
                ),
              ],
              if (roleKey == 'label_printer') ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (context) => LabelSetupScreen(
                                    currentUser: widget.currentUser)),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: 'Thiết kế mẫu tem',
                            labelStyle: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                              color: Colors.grey[600],
                            ),
                            prefixIcon: null,
                            suffixIcon: const Padding(
                              padding: EdgeInsets.only(right: 12.0),
                              child: Icon(Icons.arrow_forward_ios,
                                  size: 16, color: AppTheme.primaryColor),
                            ),
                            contentPadding:
                            const EdgeInsets.fromLTRB(12, 16, 12, 16),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide:
                              BorderSide(color: Colors.grey.shade300),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                          ),
                          child: Text(
                            "Thiết lập mẫu in tem",
                            style: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf_outlined,
                          color: Colors.grey),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (context) => LabelSetupScreen(
                                  currentUser: widget.currentUser)),
                        );
                      },
                    ),
                  ],
                ),
              ],
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