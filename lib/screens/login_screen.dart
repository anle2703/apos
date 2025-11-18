import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../theme/responsive_helper.dart';
import 'signup_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import '../../widgets/custom_text_form_field.dart';
import 'home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get isDesktop => !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  final AuthService _authService = AuthService();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  final FocusNode _passwordFocusNode = FocusNode();

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _signIn() async {
    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    if (password.isEmpty || !phoneNumber.startsWith('0') || phoneNumber.length != 10) {
      ToastService().show(
          message: 'Vui lòng nhập đúng định dạng số điện thoại và mật khẩu.',
          type: ToastType.warning
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await _authService.signInWithPhoneNumberPassword(
      phoneNumber,
      password,
    );

    if (!mounted) return;

    if (result != null) {
      if (result is User) {
      } else if (result is UserModel) {

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('employee_uid', result.uid);
        await startPrintServerForUser(result);
        if (!context.mounted) return;
        final BuildContext safeContext = context;
        Navigator.of(safeContext).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (context) => HomeScreen(user: result),
          ),
              (route) => false,
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _signInWithGoogle() async {
    setState(() => _isLoading = true);
    await _authService.signInWithGoogle();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.shopping_bag_outlined, size: 80, color: primaryColor),
                const SizedBox(height: 20),
                Text(
                  '4CASH Chào mừng trở lại!',
                  textAlign: TextAlign.center,
                  style: responsiveTextStyle(textTheme.displaySmall),
                ),
                const SizedBox(height: 10),
                Text(
                  'Vui lòng đăng nhập để tiếp tục',
                  textAlign: TextAlign.center,
                  style: responsiveTextStyle(textTheme.titleMedium),
                ),
                const SizedBox(height: 40),
                CustomTextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_android)),
                ),
                const SizedBox(height: 16),
                KeyboardListener(
                  focusNode: _passwordFocusNode,
                  onKeyEvent: (KeyEvent event) {
                    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
                      if (!_isLoading) {
                        _signIn();
                      }
                    }
                  },
                  child: CustomTextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                    // Không cần onSubmitted ở đây nữa
                  ),
                ),
                const SizedBox(height: 30),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _signIn,
                      child: const Text('Đăng nhập'),
                    ),
                    const SizedBox(height: 12),
                    if (!isDesktop)
                      OutlinedButton.icon(
                        icon: const FaIcon(FontAwesomeIcons.google, color: Colors.red, size: 18),
                        label: const Text('Đăng nhập với Google'),
                        onPressed: _signInWithGoogle,
                      ),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Chưa có tài khoản?", style: textTheme.bodyMedium),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SignupScreen()));
                      },
                      child: Text(
                        "Đăng ký ngay",
                        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}