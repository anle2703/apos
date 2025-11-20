import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  final _db = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscurePassword = true;
  bool _autoIssueOnPayment = false;

  // Biến logic ngầm
  String _invoiceType = 'vat';

  late final TextEditingController _taxCodeController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _templateCodeController;
  late final TextEditingController _invoiceSeriesController;

  @override
  void initState() {
    super.initState();
    _taxCodeController = TextEditingController();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
    _templateCodeController = TextEditingController();
    _invoiceSeriesController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
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

      // 1. Xác định loại hóa đơn ngầm
      final taxDoc = await _db.collection('store_tax_settings').doc(widget.currentUser.storeId).get();
      if (taxDoc.exists) {
        final taxData = taxDoc.data()!;
        final String calcMethod = taxData['calcMethod'] ?? 'direct';
        final String entityType = taxData['entityType'] ?? 'hkd';

        if (entityType == 'dn' || calcMethod == 'deduction') {
          _invoiceType = 'vat';
        } else {
          _invoiceType = 'sale';
        }
      } else {
        _invoiceType = 'sale'; // Mặc định
      }

      // 2. Load cấu hình MISA
      final config = await _misaService.getMisaConfig(ownerUid);
      if (config != null) {
        _taxCodeController.text = config.taxCode;
        _usernameController.text = config.username;
        _passwordController.text = config.password;
        _templateCodeController.text = config.templateCode;
        _invoiceSeriesController.text = config.invoiceSeries;
        _autoIssueOnPayment = config.autoIssueOnPayment;
      }
    } catch (e) {
      ToastService().show(message: "Lỗi tải cấu hình: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isSaving) return;

    setState(() => _isSaving = true);
    try {
      final config = MisaConfig(
        taxCode: _taxCodeController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        templateCode: _templateCodeController.text.trim(),
        invoiceSeries: _invoiceSeriesController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
        invoiceType: _invoiceType, // Lưu ngầm
      );

      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      await _misaService.saveMisaConfig(config, ownerUid);

      ToastService().show(message: "Đã lưu cấu hình MISA", type: ToastType.success);
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
      final token = await _misaService.loginToMisa(
        _taxCodeController.text.trim(),
        _usernameController.text.trim(),
        _passwordController.text.trim(),
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(message: "Kết nối MISA thành công!", type: ToastType.success);
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
      appBar: AppBar(title: const Text('Cấu hình MISA meInvoice')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Nhập thông tin tài khoản MISA meInvoice.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _taxCodeController,
              decoration: const InputDecoration(labelText: 'Mã số thuế', prefixIcon: Icon(Icons.business)),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Tên đăng nhập (MISA)', prefixIcon: Icon(Icons.person)),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mật khẩu (MISA)',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 24),

            const Text('Thông tin Mẫu số & Ký hiệu', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 12),

            CustomTextFormField(
              controller: _templateCodeController,
              decoration: const InputDecoration(labelText: 'Mẫu số (Template Code)', prefixIcon: Icon(Icons.description)),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _invoiceSeriesController,
              decoration: const InputDecoration(labelText: 'Ký hiệu (Series)', prefixIcon: Icon(Icons.abc)),
              validator: (v) => v!.isEmpty ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 24),

            CheckboxListTile(
              title: const Text("Tự động xuất HĐ khi thanh toán"),
              value: _autoIssueOnPayment,
              onChanged: (v) => setState(() => _autoIssueOnPayment = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppTheme.primaryColor,
            ),

            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _isTesting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
                    label: const Text('Kiểm tra'),
                    onPressed: _isTesting ? null : _testConnection,
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.save),
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