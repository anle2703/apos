import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../models/store_settings_model.dart';
import '../services/settings_service.dart';

class DashboardScreen extends StatefulWidget {
  final UserModel currentUser;
  const DashboardScreen({super.key, required this.currentUser});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _storeName = '';
  final SettingsService _settingsService = SettingsService();

  @override
  void initState() {
    super.initState();
    _loadStoreInfo();
  }

  Future<void> _loadStoreInfo() async {
    try {
      StoreSettings settings = await _settingsService.getStoreSettings(widget.currentUser.storeId);
      if (settings.storeName != null && settings.storeName!.isNotEmpty && mounted) {
        setState(() {
          _storeName = settings.storeName!;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải thông tin cửa hàng: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.currentUser.businessType == 'fnb' ? Icons.restaurant_menu : Icons.shopping_bag,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 20),
          Text(
            'Chào mừng đến với $_storeName',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}