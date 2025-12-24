import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart'; // Import thư viện vẽ QR
import '../../models/payment_method_model.dart';
import '../../theme/number_utils.dart';
import '../../widgets/vietqr_generator.dart'; // Import file tiện ích
import '../../widgets/bank_list.dart'; // Import danh sách ngân hàng để lấy tên

class VietQRPopup extends StatelessWidget {
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
  Widget build(BuildContext context) {
    // 1. Tạo chuỗi dữ liệu VietQR
    final String qrData = VietQrGenerator.generate(
      bankBin: bankMethod.bankBin ?? '',
      bankAccount: bankMethod.bankAccount ?? '',
      amount: amount.toInt().toString(),
      description: orderId,
    );

    // Lấy tên ngân hàng
    final bankName = vietnameseBanks
        .firstWhere((b) => b.bin == bankMethod.bankBin, orElse: () => BankInfo(name: '', shortName: 'Ngân hàng', bin: ''))
        .shortName;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding: const EdgeInsets.all(24),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'QUÉT MÃ THANH TOÁN',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            '${formatNumber(amount)} đ',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 20),

          // 2. Hiển thị mã QR bằng QrImageView
          SizedBox(
            width: 250,
            height: 250,
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 250.0,
              backgroundColor: Colors.white,
            ),
          ),

          const SizedBox(height: 20),
          Text(
            '${bankMethod.bankAccount} - ${bankMethod.bankAccountName}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          Text(
            bankName,
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            'Nội dung: $orderId',
            style: const TextStyle(fontSize: 14, fontStyle: FontStyle.italic, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Đóng'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Đã nhận tiền'),
        ),
      ],
    );
  }
}
