import 'package:flutter/material.dart';
import '../models/user_model.dart';

class DashboardScreen extends StatelessWidget {
  final UserModel currentUser;
  const DashboardScreen({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            currentUser.businessType == 'fnb' ? Icons.restaurant_menu : Icons.shopping_bag,
            size: 80,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 20),
          Text(
            'Chào mừng đến với ${currentUser.storeName}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ],
      ),
    );
  }
}