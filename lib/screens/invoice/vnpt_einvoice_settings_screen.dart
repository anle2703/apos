import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/vnpt_invoice_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_form_field.dart';

class VnptEInvoiceSettingsScreen extends StatefulWidget {
  final UserModel currentUser;
  const VnptEInvoiceSettingsScreen({super.key, required this.currentUser});

  @override
  State<VnptEInvoiceSettingsScreen> createState() =>
      _VnptEInvoiceSettingsScreenState();
}

class _VnptEInvoiceSettingsScreenState
    extends State<VnptEInvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vnptService = VnptEInvoiceService();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  bool _obscureAppKey = true;
  bool _autoIssueOnPayment = false;

  late final TextEditingController _portalUrlController;
  late final TextEditingController _appIdController;
  late final TextEditingController _appKeyController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _templateCodeController;
  late final TextEditingController _invoiceSeriesController;

  @override
  void initState() {
    super.initState();
    _portalUrlController = TextEditingController();
    _appIdController = TextEditingController();
    _appKeyController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _templateCodeController = TextEditingController();
    _invoiceSeriesController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _portalUrlController.dispose();
    _appIdController.dispose();
    _appKeyController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _templateCodeController.dispose();
    _invoiceSeriesController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final storeId = widget.currentUser.storeId;
      final config = await _vnptService.getVnptConfig(storeId);
      if (config != null) {
        _portalUrlController.text = config.portalUrl;
        _appIdController.text = config.appId;
        _appKeyController.text = config.appKey;
        _usernameController.text = config.username;
        _passwordController.text = config.password;
        _templateCodeController.text = config.templateCode;
        _invoiceSeriesController.text = config.invoiceSeries;

        if (mounted) setState(() => _autoIssueOnPayment = config.autoIssueOnPayment);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải cấu hình: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final config = VnptConfig(
        portalUrl: _portalUrlController.text.trim(),
        appId: _appIdController.text.trim(),
        appKey: _appKeyController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        templateCode: _templateCodeController.text.trim(),
        invoiceSeries: _invoiceSeriesController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
      );

      final storeId = widget.currentUser.storeId;
      await _vnptService.saveVnptConfig(config, storeId);

      ToastService().show(message: "Đã lưu cấu hình VNPT", type: ToastType.success);
      if (mounted) Navigator.of(context).pop();

    } catch (e) {
      ToastService().show(message: "Lỗi khi lưu: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isTesting = true);
    try {
      final token = await _vnptService.loginToVnpt(
        _portalUrlController.text.trim(),
        _appIdController.text.trim(),
        _appKeyController.text.trim(),
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(message: "Kết nối thành công!", type: ToastType.success);
      } else {
        ToastService().show(message: "Kết nối thất bại: Sai thông tin.", type: ToastType.error);
      }
    } catch (e) {
      ToastService().show(message: "Lỗi: ${e.toString()}", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình VNPT e-Invoice')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            // ... (Giữ nguyên UI của bạn) ...
            const Text(
              'Vui lòng nhập thông tin tài khoản API do VNPT cung cấp.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            CustomTextFormField(
              controller: _portalUrlController,
              decoration: const InputDecoration(
                labelText: 'Portal URL',
                hintText: 'VD: https://congtya-invoice.vnpt-invoice.com.vn',
                helperText: 'Link trang web bạn đăng nhập để xem hóa đơn',
                prefixIcon: Icon(Icons.http_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _appIdController,
              decoration: const InputDecoration(
                labelText: 'App ID',
                hintText: 'Lấy từ trang quản trị VNPT',
                prefixIcon: Icon(Icons.key_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _appKeyController,
              obscureText: _obscureAppKey,
              decoration: InputDecoration(
                labelText: 'App Key',
                hintText: 'Lấy từ trang quản trị VNPT',
                prefixIcon: const Icon(Icons.shield_outlined),
                suffixIcon: IconButton(
                  icon: Icon(_obscureAppKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureAppKey = !_obscureAppKey),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Tên đăng nhập (Admin)',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mật khẩu',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 24),
            const Text('Thông tin hóa đơn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _templateCodeController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu Mẫu (Template Code)',
                hintText: '1C23TNB',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _invoiceSeriesController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu Hóa đơn (Series)',
                hintText: 'C23TAA',
                prefixIcon: Icon(Icons.abc_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              title: const Text("Tự động xuất HĐĐT khi thanh toán"),
              value: _autoIssueOnPayment,
              onChanged: (v) => setState(() => _autoIssueOnPayment = v ?? false),
              activeColor: AppTheme.primaryColor,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _isTesting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.sync_outlined),
                    label: Text(_isTesting ? 'Đang thử...' : 'Kiểm tra'),
                    onPressed: _isTesting ? null : _testConnection,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: const Text('Lưu cấu hình'),
                    onPressed: _isSaving ? null : _saveSettings,
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}