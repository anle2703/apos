import 'package:flutter/material.dart';
// Đã xóa import cloud_firestore vì không cần nữa
import '../../models/user_model.dart';
import '../../services/viettel_invoice_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_form_field.dart';

class ViettelEInvoiceSettingsScreen extends StatefulWidget {
  final UserModel currentUser;
  const ViettelEInvoiceSettingsScreen({super.key, required this.currentUser});

  @override
  State<ViettelEInvoiceSettingsScreen> createState() =>
      _ViettelEInvoiceSettingsScreenState();
}

class _ViettelEInvoiceSettingsScreenState
    extends State<ViettelEInvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Service
  final _viettelService = ViettelEInvoiceService();

  // Trạng thái UI
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  bool _autoIssueOnPayment = false;

  // Controllers
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _templateCodeController;
  late final TextEditingController _invoiceSeriesController;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _templateCodeController = TextEditingController();
    _invoiceSeriesController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
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

      // Đọc cấu hình Viettel từ Service
      final config = await _viettelService.getViettelConfig(ownerUid);

      if (config != null) {
        _usernameController.text = config.username;
        _passwordController.text = config.password;
        _templateCodeController.text = config.templateCode;
        _invoiceSeriesController.text = config.invoiceSeries;

        if (mounted) {
          setState(() {
            _autoIssueOnPayment = config.autoIssueOnPayment;
          });
        }
      }
    } catch (e) {
      ToastService()
          .show(message: "Lỗi tải cấu hình: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      // SỬA: Tạo config không còn tham số invoiceType
      final config = ViettelConfig(
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        templateCode: _templateCodeController.text.trim(),
        invoiceSeries: _invoiceSeriesController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
        // Đã xóa dòng invoiceType gây lỗi
      );

      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      await _viettelService.saveViettelConfig(config, ownerUid);

      ToastService().show(message: "Đã lưu cấu hình Viettel", type: ToastType.success);

      // Tùy chọn: Đóng màn hình sau khi lưu thành công
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
      final token = await _viettelService.loginToViettel(
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(message: "Kết nối thành công!", type: ToastType.success);
      } else {
        ToastService().show(message: "Kết nối thất bại: Sai thông tin.", type: ToastType.error);
      }
    } catch (e) {
      // Hiển thị lỗi chi tiết từ Service (đã update ở bước trước)
      ToastService().show(message: "Lỗi: ${e.toString()}", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình Viettel SInvoice')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Vui lòng nhập thông tin tài khoản Viettel SInvoice.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),

            CustomTextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Tên đăng nhập (Username)',
                hintText: 'Ví dụ: 0100109106-507',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mật khẩu (Password)',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            const Text('Thông tin hóa đơn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _templateCodeController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu Mẫu hóa đơn (Template)',
                hintText: 'Ví dụ: 1/001',
                prefixIcon: Icon(Icons.description_outlined),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _invoiceSeriesController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu Hóa đơn (Series)',
                hintText: 'Ví dụ: K23TXM',
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