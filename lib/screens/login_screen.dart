// File: lib/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../services/auth_service.dart';
import '../services/toast_service.dart';
import '../theme/responsive_helper.dart';
import 'signup_screen.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../widgets/custom_text_form_field.dart';
import 'auth_gate.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
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

    // Ẩn bàn phím
    FocusScope.of(context).unfocus();

    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> resultData;

      // BƯỚC 1: GỌI SERVER ĐỂ KIỂM TRA SĐT LÀ AI
      if (isDesktop) {
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
        // Mobile gọi qua SDK
        final result = await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable('loginEmployee')
            .call({'phoneNumber': phoneNumber, 'password': password});
        resultData = Map<String, dynamic>.from(result.data);
      }

      // BƯỚC 2: XỬ LÝ KẾT QUẢ TRẢ VỀ
      UserCredential? userCredential;

      if (resultData['isOwner'] == true) {
        // === LUỒNG CHỦ: Đăng nhập bằng Email/Pass chuẩn của Firebase ===
        final String ownerEmail = resultData['email'];
        // Dùng mật khẩu người dùng vừa nhập để login Auth
        userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: ownerEmail,
          password: password,
        );
      } else {
        // === LUỒNG NHÂN VIÊN: Đăng nhập bằng Custom Token ===
        final String token = resultData['token'];
        userCredential = await FirebaseAuth.instance.signInWithCustomToken(token);
      }

      // BƯỚC 3: HOÀN TẤT
      if (userCredential.user != null) {
        // Lưu UID
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
      // Việt hóa một số lỗi Auth thường gặp của chủ
      if (msg.contains("INVALID_LOGIN_CREDENTIALS") || msg.contains("wrong-password")) {
        msg = "Sai mật khẩu!";
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
                  Icon(Icons.shopping_bag_outlined,
                      size: 80, color: primaryColor),
                  const SizedBox(height: 20),
                  Text(
                    'Phần mềm quản lý bán hàng APOS',
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
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly, // Chỉ cho nhập số
                      LengthLimitingTextInputFormatter(10),   // Chặn tối đa 10 ký tự
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
                            if (!isDesktop && !Platform.isIOS)
                              OutlinedButton.icon(
                                icon: const FaIcon(FontAwesomeIcons.google,
                                    color: Colors.red, size: 18),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
