// File: lib/screens/signup_screen.dart

import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/toast_service.dart';
import '../theme/responsive_helper.dart';
import '../widgets/custom_text_form_field.dart';
import 'home_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});
  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _firestoreService = FirestoreService();
  final _toastService = ToastService();

  final _emailController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _agentIdController = TextEditingController();

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _shopNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _agentIdController.dispose();
    super.dispose();
  }

  String _generateStoreId(String storeName) {
    String slug = storeName.toLowerCase();
    slug = slug.replaceAll(RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'), 'a');
    slug = slug.replaceAll(RegExp(r'[èéẹẻẽêềếệểễ]'), 'e');
    slug = slug.replaceAll(RegExp(r'[ìíịỉĩ]'), 'i');
    slug = slug.replaceAll(RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'), 'o');
    slug = slug.replaceAll(RegExp(r'[ùúụủũưừứựửữ]'), 'u');
    slug = slug.replaceAll(RegExp(r'[ỳýỵỷỹ]'), 'y');
    slug = slug.replaceAll(RegExp(r'đ'), 'd');
    slug = slug.replaceAll(RegExp(r'[^a-z0-9]'), '');
    return slug;
  }

  void _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    final email = _emailController.text.trim();
    final shopName = _shopNameController.text.trim();
    final shopId = _generateStoreId(shopName);
    final phoneNumber = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    String? finalAgentId;

    try {
      // --- 1. KIỂM TRA MÃ ĐẠI LÝ ---
      if (_agentIdController.text.trim().isNotEmpty) {
        final rawAgentId = _generateStoreId(_agentIdController.text.trim());
        final agentDoc = await FirebaseFirestore.instance
            .collection('app_config')
            .doc(rawAgentId)
            .get();

        if (!agentDoc.exists) {
          _toastService.show(
              message: 'Mã đại lý "$rawAgentId" không tồn tại.',
              type: ToastType.error);
          setState(() => _isLoading = false);
          return;
        }
        finalAgentId = rawAgentId;
      }

      // --- 2. KIỂM TRA TRÙNG STORE ID ---
      bool shopIdExists = await _firestoreService.isFieldInUse(field: 'storeId', value: shopId);
      if (shopIdExists) {
        throw Exception('Tên cửa hàng này tạo ra ID "$shopId" đã bị trùng. Vui lòng chọn tên khác.');
      }

      // --- 3. [KHÔI PHỤC] KIỂM TRA TRÙNG SỐ ĐIỆN THOẠI ---
      bool phoneExists = await _firestoreService.isFieldInUse(field: 'phoneNumber', value: phoneNumber);
      if (phoneExists) {
        throw Exception('Số điện thoại này đã được sử dụng bởi một tài khoản khác.');
      }

      // --- 4. TẠO TÀI KHOẢN AUTH ---
      final user = await _authService.signUpWithEmailPassword(email, password);

      if (user != null) {
        // --- 5. TẠO PROFILE FIRESTORE ---
        await _firestoreService.createUserProfile(
          uid: user.uid,
          email: user.email!,
          storeId: shopId,
          storeName: shopName,
          phoneNumber: phoneNumber,
          role: 'owner',
          name: 'admin',
          agentId: finalAgentId,
          storePhone: phoneNumber,
        );

        // --- 6. RELOAD TOKEN (Để fix lỗi permission) ---
        await user.reload();
        await user.getIdToken(true);

        if (mounted) {
          _toastService.show(
              message: 'Đăng ký thành công!',
              type: ToastType.success
          );

          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
                (route) => false,
          );
        }
      }
    } catch (e) {
      String errorMessage = 'Đăng ký thất bại.';
      if (e.toString().contains('email-already-in-use') || e.toString().contains('email-already-exists')) {
        errorMessage = 'Email này đã được sử dụng.';
      } else {
        errorMessage = e.toString().replaceAll("Exception: ", "");
      }

      if (mounted) {
        _toastService.show(message: errorMessage, type: ToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ... (Giữ nguyên các hàm validate)
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập mật khẩu';
    if (value.length < 6) return 'Mật khẩu phải có ít nhất 6 ký tự';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng xác nhận mật khẩu';
    if (value != _passwordController.text) return 'Mật khẩu không khớp';
    return null;
  }

  String? _validatePhoneNumber(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng nhập số điện thoại';
    if (!value.startsWith('0')) return 'Số điện thoại phải bắt đầu bằng số 0';
    if (value.length != 10) return 'Số điện thoại phải có đúng 10 ký tự';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo tài khoản mới')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Điền thông tin của bạn',
                  textAlign: TextAlign.center,
                  style: responsiveTextStyle(textTheme.headlineMedium),
                ),
                const SizedBox(height: 30),
                CustomTextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(labelText: 'Tên cửa hàng', prefixIcon: Icon(Icons.store_outlined)),
                  validator: (v) => v!.isEmpty ? 'Không được để trống' : null,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(labelText: 'Số điện thoại', prefixIcon: Icon(Icons.phone_outlined)),
                  keyboardType: TextInputType.phone,
                  validator: _validatePhoneNumber,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Mật khẩu (tối thiểu 6 ký tự)', prefixIcon: Icon(Icons.lock_open_outlined)),
                  obscureText: true,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(labelText: 'Xác nhận mật khẩu', prefixIcon: Icon(Icons.lock_outline)),
                  obscureText: true,
                  validator: _validateConfirmPassword,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _agentIdController,
                  decoration: const InputDecoration(
                    labelText: 'Mã đại lý (Nếu có)',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 30),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                  onPressed: _signUp,
                  child: const Text('Hoàn tất Đăng ký'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}