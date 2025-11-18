import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../models/payment_method_model.dart';
import '../../widgets/bank_list.dart';

class VietQRPopup extends StatefulWidget {
  final double amount;
  final String orderId;
  final PaymentMethodModel bankMethod;

  const VietQRPopup({
    super.key,
    required this.amount,
    required this.orderId,
    required this.bankMethod,
  });

  @override
  State<VietQRPopup> createState() => _VietQRPopupState();
}

class _VietQRPopupState extends State<VietQRPopup> {
  String? _vietQRUrl;
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = 'Lỗi không xác định';

  @override
  void initState() {
    super.initState();
    _generateQRUrl();
  }

  /// Xây dựng URL cho dịch vụ VietQR
  String? _buildVietQRString() {
    final amount = widget.amount.toInt().toString();
    final addInfo = Uri.encodeComponent(widget.orderId);

    final bankBin = widget.bankMethod.bankBin;
    final bankAccount = widget.bankMethod.bankAccount;

    if (bankBin == null || bankBin.isEmpty) {
      _errorMessage = 'PTTT này chưa được gán Mã BIN.';
      return null;
    }
    if (bankAccount == null || bankAccount.isEmpty) {
      _errorMessage = 'PTTT này chưa nhập Số tài khoản.';
      return null;
    }

    // Tra cứu shortName (vd: 'vietinbank') từ Mã BIN
    final bankInfo = vietnameseBanks.firstWhere(
          (b) => b.bin == bankBin,
      orElse: () => BankInfo(name: 'Không tìm thấy', shortName: '', bin: ''),
    );

    if (bankInfo.shortName.isEmpty) {
      _errorMessage = 'Mã BIN $bankBin không được hỗ trợ hoặc không đúng.';
      return null;
    }

    // --- DÙNG API "COMPACT" (SẠCH LOGO THỪA) ---
    return 'https://img.vietqr.io/image/${bankInfo.shortName}-$bankAccount-compact.png?amount=$amount&addInfo=$addInfo';
  }

  /// Gọi và xác thực URL của VietQR
  Future<void> _generateQRUrl() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    final url = _buildVietQRString();

    if (url == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          // _errorMessage đã được set
        });
      }
      return;
    }

    debugPrint("Đang gọi VietQR URL (bản compact): $url");

    try {
      final response =
      await http.head(Uri.parse(url)).timeout(const Duration(seconds: 10));

      if (mounted) {
        if (response.statusCode == 200) {
          setState(() {
            _vietQRUrl = url;
            _isLoading = false;
            _hasError = false;
          });
        } else {
          _errorMessage =
          'Lỗi 404: Không tìm thấy STK/Ngân hàng. Vui lòng kiểm tra lại.';
          throw Exception(
              'VietQR service returned status ${response.statusCode}');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
          if (e is! Exception) {
            _errorMessage = e.toString();
          }
        });
        debugPrint("Lỗi tạo QR: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Quét QR - ${widget.bankMethod.name}',
        textAlign: TextAlign.center,
      ),
      // --- THAY ĐỔI: Thêm khoảng trống dưới tiêu đề ---
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      // --- THAY ĐỔI: Xóa padding content ---
      contentPadding: EdgeInsets.zero,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // --- THAY ĐỔI: Chỉ giữ lại Container chứa QR ---
          Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              //
              image: _vietQRUrl != null && !_isLoading && !_hasError
                  ? DecorationImage(
                image: NetworkImage(_vietQRUrl!),
                fit: BoxFit.contain,
              )
                  : null,
            ),
            clipBehavior: Clip.antiAlias,
            child: _buildQRStatus(),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsPadding: const EdgeInsets.all(16),
      actions: [
        SizedBox(
          width: 120,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Đóng'),
          ),
        ),
        SizedBox(
          width: 150,
          child: ElevatedButton(
            onPressed: _isLoading || _hasError
                ? null
                : () {
              Navigator.of(context).pop(true);
            },
            child: const Text('Đã thanh toán'),
          ),
        ),
      ],
    );
  }

  Widget _buildQRStatus() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_hasError) {
      return Container(
        color: Colors.white.withAlpha(200),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  _errorMessage, // Hiển thị lỗi cụ thể
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}