// File: lib/screens/subscription_expired_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/auth_service.dart';
import 'auth_gate.dart';

class SubscriptionExpiredScreen extends StatelessWidget {
  final DateTime expiryDate;
  const SubscriptionExpiredScreen({super.key, required this.expiryDate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_off_outlined, size: 80, color: Colors.red),
              const SizedBox(height: 20),
              Text(
                'Tài khoản đã hết hạn',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Gói phần mềm của bạn đã hết hạn vào lúc:\n${DateFormat('HH:mm dd/MM/yyyy').format(expiryDate)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 30),
              const Text(
                'Vui lòng liên hệ quản trị viên để gia hạn.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 30),
              ElevatedButton(
                onPressed: () async {
                  await AuthService().signOut();
                  if(context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (context) => const AuthGate()),
                          (route) => false,
                    );
                  }
                },
                child: const Text('Đăng xuất'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}