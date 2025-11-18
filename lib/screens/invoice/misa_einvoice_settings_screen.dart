// Tên file: misa_einvoice_settings_screen.dart
import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/misa_invoice_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_form_field.dart';

class MisaEInvoiceSettingsScreen extends StatefulWidget {
  final UserModel currentUser;
  const MisaEInvoiceSettingsScreen({super.key, required this.currentUser});

  @override
  State<MisaEInvoiceSettingsScreen> createState() =>
      _MisaEInvoiceSettingsScreenState();
}

class _MisaEInvoiceSettingsScreenState
    extends State<MisaEInvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _misaService = MisaEInvoiceService();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  bool _autoIssueOnPayment = false;

  late final TextEditingController _apiUrlController;
  // late final TextEditingController _appIdController; // XÓA
  late final TextEditingController _taxCodeController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _templateCodeController;
  late final TextEditingController _invoiceSeriesController;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController();
    // _appIdController = TextEditingController(); // XÓA
    _taxCodeController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _templateCodeController = TextEditingController();
    _invoiceSeriesController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    // _appIdController.dispose(); // XÓA
    _taxCodeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _templateCodeController.dispose();
    _invoiceSeriesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      final config = await _misaService.getMisaConfig(ownerUid);
      if (config != null) {
        _apiUrlController.text = config.apiUrl;
        // _appIdController.text = config.appId; // XÓA
        _taxCodeController.text = config.taxCode;
        _usernameController.text = config.username;
        _passwordController.text = config.password;
        _templateCodeController.text = config.templateCode;
        _invoiceSeriesController.text = config.invoiceSeries;
        _autoIssueOnPayment = config.autoIssueOnPayment;
      } else {
        // Đặt giá trị mặc định cho người dùng mới
        _apiUrlController.text = 'https://api.meinvoice.vn';
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi tải cấu hình: $e", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final config = MisaConfig(
        apiUrl: _apiUrlController.text.trim(),
        // appId: _appIdController.text.trim(), // XÓA
        taxCode: _taxCodeController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        templateCode: _templateCodeController.text.trim(),
        invoiceSeries: _invoiceSeriesController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
      );
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      await _misaService.saveMisaConfig(config, ownerUid);
      ToastService()
          .show(message: "Đã lưu cấu hình MISA", type: ToastType.success);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi khi lưu: $e", type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_isTesting) return;

    setState(() => _isTesting = true);
    try {
      final token = await _misaService.loginToMisa(
        _apiUrlController.text.trim(),
        // _appIdController.text.trim(), // XÓA
        _taxCodeController.text.trim(),
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(
          message: "Kết nối thành công!",
          type: ToastType.success,
        );
      } else {
        ToastService().show(
          message: "Kết nối thất bại: Sai thông tin cấu hình.",
          type: ToastType.error,
        );
      }
    } catch (e) {
      ToastService().show(
        message: "Kết nối thất bại: ${e.toString()}",
        type: ToastType.error,
      );
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấu hình MISA meInvoice'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Vui lòng nhập thông tin tài khoản API do MISA cung cấp.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            CustomTextFormField(
              controller: _apiUrlController,
              decoration: const InputDecoration(
                labelText: 'API URL',
                hintText: 'https://api.meinvoice.vn (Live) hoặc https://testapi.meinvoice.vn (Test)',
                prefixIcon: Icon(Icons.http_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            // TRƯỜNG APP ID ĐÃ BỊ XÓA
            CustomTextFormField(
              controller: _taxCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã số thuế',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Tên đăng nhập (MISA)',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mật khẩu (MISA)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            const Text(
              'Thông tin hóa đơn',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor),
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _templateCodeController,
              decoration: const InputDecoration(
                labelText: 'Mẫu số (templateCode)',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _invoiceSeriesController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu (invoiceSeries)',
                prefixIcon: Icon(Icons.abc_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              title: const Text("Tự động xuất HĐĐT khi thanh toán"),
              subtitle: const Text("Nếu bật, HĐĐT sẽ tự động được tạo khi bấm 'Xác Nhận Thanh Toán' tại quầy."),
              value: _autoIssueOnPayment,
              onChanged: (bool? value) {
                setState(() {
                  _autoIssueOnPayment = value ?? false;
                });
              },
              activeColor: AppTheme.primaryColor,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: _isTesting
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync_outlined),
              label: Text(_isTesting ? 'Đang thử...' : 'Kiểm tra kết nối'),
              onPressed: _isTesting ? null : _testConnection,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: _isSaving
                  ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 3))
                  : const Icon(Icons.save_outlined),
              label: Text(_isSaving ? 'Đang lưu...' : 'Lưu cấu hình'),
              onPressed: _isSaving ? null : _saveSettings,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}