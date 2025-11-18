import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import 'viettel_einvoice_settings_screen.dart';
import 'vnpt_einvoice_settings_screen.dart';
import 'misa_einvoice_settings_screen.dart';
import 'vnpay_einvoice_settings_screen.dart';

class EInvoiceSettingsScreen extends StatelessWidget {
  final UserModel currentUser;
  const EInvoiceSettingsScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kết nối Hóa đơn Điện tử'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Chọn nhà cung cấp dịch vụ hóa đơn điện tử bạn muốn kết nối. Bạn chỉ có thể kích hoạt một nhà cung cấp tại một thời điểm.',
            style: TextStyle(fontSize: 15, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          _buildProviderCard(
            context,
            logoAsset: 'assets/logos/viettel_logo.png',
            title: 'Viettel SInvoice',
            description: 'Kết nối với dịch vụ SInvoice của Viettel.',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => ViettelEInvoiceSettingsScreen(
                  currentUser: currentUser,
                ),
              ));
            },
          ),
          _buildProviderCard(
            context,
            logoAsset: 'assets/logos/vnpt_logo.png',
            title: 'VNPT e-Invoice',
            description: 'Kết nối với dịch vụ e-Invoice của VNPT.',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => VnptEInvoiceSettingsScreen(
                  currentUser: currentUser,
                ),
              ));
            },
          ),
          _buildProviderCard(
            context,
            logoAsset: 'assets/logos/misa_logo.png',
            title: 'MISA meInvoice',
            description: 'Kết nối với dịch vụ meInvoice của MISA.',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => MisaEInvoiceSettingsScreen(
                  currentUser: currentUser,
                ),
              ));
            },
          ),
          _buildProviderCard(
            context,
            logoAsset: 'assets/logos/vnpay_logo.png',
            title: 'VNPay eInvoice',
            description: 'Kết nối với dịch vụ eInvoice của VNPay.',
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => VnpayEInvoiceSettingsScreen(
                  currentUser: currentUser,
                ),
              ));
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
      BuildContext context, {
        required String logoAsset,
        required String title,
        required String description,
        required VoidCallback onTap,
      }) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        leading: Image.asset(
          logoAsset,
          width: 48,
          height: 48,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.business, color: Colors.grey[600]),
            );
          },
        ),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        subtitle:
        Text(description, style: const TextStyle(color: Colors.black54)),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      ),
    );
  }
}