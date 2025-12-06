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

  // Service
  final _vnpayService = VnpayEInvoiceService();

  // Trạng thái UI
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _obscureSecret = true;
  bool _autoIssueOnPayment = false;

  // Biến logic
  bool _isSandbox = false;

  // Controllers
  late final TextEditingController _clientIdController;
  late final TextEditingController _clientSecretController;
  late final TextEditingController _taxCodeController;
  late final TextEditingController _invoiceSymbolController;
  late final TextEditingController _paymentMethodController;

  @override
  void initState() {
    super.initState();
    _clientIdController = TextEditingController();
    _clientSecretController = TextEditingController();
    _taxCodeController = TextEditingController();
    _invoiceSymbolController = TextEditingController();
    _paymentMethodController = TextEditingController(text: 'TM/CK');
    _loadSettings();
  }

  @override
  void dispose() {
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _taxCodeController.dispose();
    _invoiceSymbolController.dispose();
    _paymentMethodController.dispose();
    super.dispose();
  }

  // Tự động xác định môi trường Test/Prod dựa trên MST
  void _detectEnvironment() {
    final taxCode = _taxCodeController.text.trim();
    // MST Test mặc định của VNPAY
    if (taxCode == '0102182292-999') {
      setState(() => _isSandbox = true);
    } else {
      setState(() => _isSandbox = false);
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

      // Đọc cấu hình VNPAY từ Service
      final config = await _vnpayService.getVnpayConfig(ownerUid);

      if (config != null) {
        _clientIdController.text = config.clientId;
        _clientSecretController.text = config.clientSecret;
        _taxCodeController.text = config.sellerTaxCode;
        _invoiceSymbolController.text = config.invoiceSymbol;
        _paymentMethodController.text = config.paymentMethodCode;

        if (mounted) {
          setState(() {
            _autoIssueOnPayment = config.autoIssueOnPayment;
            _isSandbox = config.isSandbox;
          });
        }
        // Chạy lại logic detect để đảm bảo UI đúng
        _detectEnvironment();
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
      _detectEnvironment(); // Cập nhật trạng thái sandbox trước khi lưu

      final ownerUid = widget.currentUser.ownerUid ?? widget.currentUser.uid;

      // Tạo object config (Đã xóa invoiceType)
      final config = VnpayConfig(
        clientId: _clientIdController.text.trim(),
        clientSecret: _clientSecretController.text.trim(),
        sellerTaxCode: _taxCodeController.text.trim(),
        invoiceSymbol: _invoiceSymbolController.text.trim(),
        autoIssueOnPayment: _autoIssueOnPayment,
        paymentMethodCode: _paymentMethodController.text.trim(),
        isSandbox: _isSandbox,
        // Đã xóa invoiceType gây lỗi
      );

      await _vnpayService.saveVnpayConfig(config, ownerUid);

      ToastService().show(message: "Đã lưu cấu hình VNPay", type: ToastType.success);

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
      _detectEnvironment();

      final token = await _vnpayService.loginToVnpay(
        _clientIdController.text.trim(),
        _clientSecretController.text.trim(),
        _isSandbox,
      );

      if (token != null && token.isNotEmpty) {
        ToastService().show(
          message: "Kết nối thành công!",
          type: ToastType.success,
        );
      } else {
        ToastService().show(
          message: "Kết nối thất bại: Client ID hoặc Secret không đúng.",
          type: ToastType.error,
        );
      }
    } catch (e) {
      ToastService().show(message: "Lỗi kết nối: ${e.toString()}", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cấu hình VNPay eInvoice')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20.0),
          children: [
            const Text(
              'Thông tin tài khoản kết nối (Client ID / Secret)',
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _taxCodeController,
              decoration: const InputDecoration(
                labelText: 'Mã số thuế (Tax Code)',
                hintText: 'Ví dụ: 0102182292-999 (Test)',
                prefixIcon: Icon(Icons.business),
              ),
              onChanged: (val) => _detectEnvironment(),
              validator: (value) => (value == null || value.isEmpty) ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _clientSecretController,
              obscureText: _obscureSecret,
              decoration: InputDecoration(
                labelText: 'Client Secret',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureSecret ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _obscureSecret = !_obscureSecret),
                ),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 24),

            const Text('Thông tin hóa đơn', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.primaryColor)),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _invoiceSymbolController,
              decoration: const InputDecoration(
                labelText: 'Ký hiệu (Symbol)',
                hintText: 'Ví dụ: C25TSD',
                prefixIcon: Icon(Icons.abc),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Bắt buộc' : null,
            ),
            const SizedBox(height: 16),

            CustomTextFormField(
              controller: _paymentMethodController,
              decoration: const InputDecoration(
                labelText: 'Hình thức thanh toán',
                hintText: 'TM/CK',
                prefixIcon: Icon(Icons.payment),
              ),
            ),

            const SizedBox(height: 24),
            CheckboxListTile(
              title: const Text("Tự động xuất HĐ khi thanh toán"),
              value: _autoIssueOnPayment,
              onChanged: (val) => setState(() => _autoIssueOnPayment = val ?? false),
              activeColor: AppTheme.primaryColor,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
            ),

            if (_isSandbox)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  "Đang ở chế độ SANDBOX (Test)",
                  style: TextStyle(color: Colors.orange[800], fontStyle: FontStyle.italic),
                ),
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