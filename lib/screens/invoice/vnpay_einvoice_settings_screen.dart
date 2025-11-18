import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/vnpay_invoice_service.dart';
import '../../services/toast_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_text_form_field.dart';

class VnpayEInvoiceSettingsScreen extends StatefulWidget {
  final UserModel currentUser;
  const VnpayEInvoiceSettingsScreen({super.key, required this.currentUser});

  @override
  State<VnpayEInvoiceSettingsScreen> createState() =>
      _VnpayEInvoiceSettingsScreenState();
}

class _VnpayEInvoiceSettingsScreenState
    extends State<VnpayEInvoiceSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _vnpayService = VnpayEInvoiceService();
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscureSecret = true;
  bool _autoIssueOnPayment = false;

  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  late final TextEditingController _taxCodeController;
  late final TextEditingController _invoiceSymbolController;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController();
    _clientSecretController = TextEditingController();
    _taxCodeController = TextEditingController();
    _invoiceSymbolController = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _taxCodeController.dispose();
    _invoiceSymbolController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      final config = await _vnpayService.getVnpayConfig(ownerUid);
      if (config != null) {
        _clientIdController.text = config.clientId;
        _clientSecretController.text = config.clientSecret;
        _taxCodeController.text = config.sellerTaxCode;
        _invoiceSymbolController.text = config.invoiceSymbol;
        _autoIssueOnPayment = config.autoIssueOnPayment;
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
      final config = VnpayConfig(
        clientId: _clientIdController.text.trim(),
        clientSecret: _clientSecretController.text.trim(),
        sellerTaxCode: _taxCodeController.text.trim(),
        invoiceSymbol: _invoiceSymbolController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
      );
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;
      await _vnpayService.saveVnpayConfig(config, ownerUid);
      ToastService()
          .show(message: "Đã lưu cấu hình VNPay", type: ToastType.success);
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
      final token = await _vnpayService.loginToVnpay(
        _clientIdController.text.trim(),
        _clientSecretController.text.trim(),
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(
          message: "Kết nối thành công!",
          type: ToastType.success,
        );
      } else {
        ToastService().show(
          message: "Kết nối thất bại: Client ID hoặc Client Secret không đúng.",
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
        title: const Text('Cấu hình VNPay eInvoice'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Vui lòng nhập thông tin tài khoản API do VNPay cung cấp. Các thông tin này sẽ được lưu trữ an toàn trên máy chủ.',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            CustomTextFormField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _clientSecretController,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                labelText: 'Client Secret',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureSecret
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureSecret = !_obscureSecret;
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
              controller: _taxCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã số thuế Người bán (taxCode)',
                hintText: 'ví dụ: 0100109106',
                prefixIcon: Icon(Icons.business_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 16),
            CustomTextFormField(
              controller: _invoiceSymbolController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu Hóa đơn (invoiceSymbol)',
                hintText: 'ví dụ: C23TYY',
                prefixIcon: Icon(Icons.abc_outlined),
              ),
              validator: (value) => (value == null || value.isEmpty)
                  ? 'Không được để trống'
                  : null,
            ),
            const SizedBox(height: 24),
            CheckboxListTile(
              title: const Text("Tự động xuất HĐĐT khi thanh toán"),
              subtitle: const Text(
                  "Nếu bật, HĐĐT sẽ tự động được tạo khi bấm 'Xác Nhận Thanh Toán' tại quầy."),
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
              label:
              Text(_isTesting ? 'Đang thử...' : 'Kiểm tra kết nối'),
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