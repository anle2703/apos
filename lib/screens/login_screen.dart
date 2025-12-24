// File: lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../theme/responsive_helper.dart';
import 'signup_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb; // Quan trọng
import '../../widgets/custom_text_form_field.dart';
import 'auth_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // SỬA: Thêm check kIsWeb để tránh crash trên trình duyệt
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  // SỬA: Tạo biến kiểm tra iOS an toàn cho Web
  bool get isIOS => !kIsWeb && Platform.isIOS;

  final AuthService _authService = AuthService();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
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
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();

    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> resultData;

      if (isDesktop || kIsWeb) { // SỬA: Web cũng dùng HTTP request
        // Lưu ý: Nếu Cloud Function chặn CORS thì web sẽ cần config lại,
        // nhưng tạm thời giữ luồng logic này.
        const String functionUrl = 'https://loginemployee-ve2xhbykka-as.a.run.app';

        final url = Uri.parse(functionUrl);
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({"data": {"phoneNumber": phoneNumber, "password": password}}),
        );

        final decoded = jsonDecode(response.body);
        if (response.statusCode == 200) {
          resultData = decoded['result'];
        } else {
          String errorMsg = decoded['error']?['message'] ?? 'Lỗi kết nối';
          throw Exception(errorMsg);
        }
      } else {
        final result = await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable('loginEmployee')
            .call({'phoneNumber': phoneNumber, 'password': password});
        resultData = Map<String, dynamic>.from(result.data);
      }

      UserCredential? userCredential;

      if (resultData['isOwner'] == true) {
        final String ownerEmail = resultData['email'];
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: ownerEmail,
          password: password,
        );
      } else {
        final String token = resultData['token'];
        userCredential = await FirebaseAuth.instance.signInWithCustomToken(token);
      }

      if (userCredential.user != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('employee_uid', userCredential.user!.uid);

        if (!mounted) return;
        ToastService().show(message: "Đăng nhập thành công!", type: ToastType.success);

        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthGate()),
              (route) => false,
        );
      }

    } catch (e) {
      String msg = e.toString().replaceAll("Exception: ", "");
      if (msg.contains("INVALID_LOGIN_CREDENTIALS") ||
          msg.contains("wrong-password") ||
          msg.contains("user-not-found") ||
          msg.contains("unknown-error") ||
          msg.contains("internal-error")) {
        msg = "Sai SĐT hoặc mật khẩu!";
      }
      ToastService().show(message: msg, type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _signInWithGoogle() async {
    setState(() => _isLoading = true);
    await _authService.signInWithGoogle();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  final Map<String, String> _supportInfo = {
    'phone': '0935417776',
    'facebook': 'https://www.facebook.com/phanmemapos',
    'zalo': '0935417776',
  };

  Future<void> _handleContactAction(String type, String value) async {
    if (value.isEmpty) return;

    try {
      if (type == 'facebook') {
        String urlString = value;
        if (!urlString.startsWith('http')) {
          urlString = 'https://www.facebook.com/$value';
        }
        final Uri uri = Uri.parse(urlString);

        if (!isDesktop) {
          bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched) {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
          }
        } else {
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
        return;
      }

      if (type == 'phone') {
        if (isDesktop || kIsWeb) { // SỬA: Web cũng hiện popup thay vì gọi
          _showInfoPopup('Số điện thoại', value);
          return;
        }

        final Uri uri = Uri(scheme: 'tel', path: value);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
        } else {
          if (mounted) _showInfoPopup('Số điện thoại', value);
        }
        return;
      }

      if (type == 'zalo') {
        if (isDesktop || kIsWeb) { // SỬA: Web cũng hiện popup
          _showInfoPopup('Zalo', value);
          return;
        }

        final Uri uri = Uri.parse("https://zalo.me/$value");
        bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (!launched) {
          if (mounted) _showInfoPopup('Zalo', value);
        }
        return;
      }
    } catch (e) {
      if (mounted) _showInfoPopup('Thông tin liên hệ', value);
    }
  }

  void _showInfoPopup(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: Row(
          children: [
            Expanded(child: Text(content, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.blue),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.of(ctx).pop();
                ToastService().show(message: 'Đã sao chép $content', type: ToastType.success);
              },
            )
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Đóng'))],
      ),
    );
  }

  Widget _buildCompactIcon({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool isZalo = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: isZalo
            ? Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            Text(
              'Zalo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(offset: const Offset(1, 1), blurRadius: 2, color: color)],
              ),
            ),
          ],
        )
            : Icon(icon, color: color, size: 28),
      ),
    );
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
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: Image.asset(
                      'assets/images/logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  Text(
                    '"Quản lý nhẹ tay - Lợi nhuận thấy ngay!"',
                    textAlign: TextAlign.center,
                    style: responsiveTextStyle(textTheme.titleMedium)?.copyWith(color: primaryColor, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  CustomTextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Vui lòng nhập số điện thoại';
                      }
                      if (!value.startsWith('0')) {
                        return 'SĐT phải bắt đầu bằng số 0';
                      }
                      if (value.length < 10) {
                        return 'Vui lòng nhập đủ 10 số';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                        labelText: 'Số điện thoại',
                        prefixIcon: Icon(Icons.phone_android)),
                    textInputAction: TextInputAction.next,
                    onFieldSubmitted: (_) {
                      FocusScope.of(context).requestFocus(_passwordFocusNode);
                    },
                  ),
                  const SizedBox(height: 16),
                  CustomTextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    focusNode: _passwordFocusNode,
                    decoration: const InputDecoration(
                        labelText: 'Mật khẩu',
                        prefixIcon: Icon(Icons.lock_outline)),
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!_isLoading) _signIn();
                    },
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
                      // SỬA: Dùng !isIOS đã định nghĩa ở trên để tránh lỗi Web
                      if (kIsWeb || (!isDesktop && !isIOS))
                        OutlinedButton.icon(
                          label: const Text('Đăng ký/Đăng nhập bằng Google'),
                          icon: const FaIcon(FontAwesomeIcons.google,
                              color: Colors.red, size: 16),
                          onPressed: _signInWithGoogle,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Column(
                    children: [
                      // SỬA: Check !isIOS an toàn cho Web
                      if (!isIOS) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text("Chưa có tài khoản?", style: textTheme.bodyMedium),
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => const SignupScreen()));
                              },
                              child: Text(
                                "Đăng ký ngay",
                                style: textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.bold, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],

                      Text('Liên hệ hỗ trợ:',
                        style: textTheme.bodyMedium?.copyWith(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildCompactIcon(
                              icon: Icons.phone,
                              color: Colors.blue,
                              onTap: () => _handleContactAction('phone', _supportInfo['phone']!)),
                          const SizedBox(width: 20),

                          _buildCompactIcon(
                              icon: Icons.facebook,
                              color: const Color(0xFF1877F2),
                              onTap: () => _handleContactAction('facebook', _supportInfo['facebook']!)),
                          const SizedBox(width: 20),

                          _buildCompactIcon(
                            icon: Icons.circle,
                            color: const Color(0xFF0068FF),
                            onTap: () => _handleContactAction('zalo', _supportInfo['zalo']!),
                            isZalo: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}