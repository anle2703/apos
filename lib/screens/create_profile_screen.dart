import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/toast_service.dart';
import 'home_screen.dart';
import '../../widgets/custom_text_form_field.dart';

class CreateProfileScreen extends StatefulWidget {
  final User user;

  const CreateProfileScreen({super.key, required this.user});

  @override
  State<CreateProfileScreen> createState() => _CreateProfileScreenState();
}

class _CreateProfileScreenState extends State<CreateProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final _storeNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _storeNameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _cancelAndSignOut() async {
    setState(() => _isLoading = true);
    await _authService.signOut();
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

  void _submitProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    final shopName = _storeNameController.text.trim();
    final shopId = _generateStoreId(shopName);
    final phoneNumber = _phoneController.text.trim();
    bool shopIdExists =
        await _firestoreService.isFieldInUse(field: 'storeId', value: shopId);
    if (shopIdExists) {
      if (mounted){
        ToastService().show(
            message: 'Tên cửa hàng này đã tạo ra một ID bị trùng.',
            type: ToastType.error);
      setState(() => _isLoading = false);
      return;}
    }

    bool phoneExists = await _firestoreService.isFieldInUse(
        field: 'phoneNumber', value: phoneNumber);
    if (phoneExists) {
      if (mounted){
        ToastService().show(
            message: 'Số điện thoại này đã được sử dụng.',
            type: ToastType.error);
      setState(() => _isLoading = false);
      return;}
    }

    try {
      bool linkSuccess =
          await _authService.linkPasswordToAccount(_passwordController.text);
      if (!linkSuccess) {
        if (mounted){
          ToastService().show(
              message: 'Không thể tạo mật khẩu. Email này có thể đã được dùng.',
              type: ToastType.error);
        setState(() => _isLoading = false);
        return;}
      }
      await _firestoreService.createUserProfile(
        uid: widget.user.uid,
        email: widget.user.email!,
        storeId: shopId,
        storeName: shopName,
        phoneNumber: phoneNumber,
        role: 'owner',
        name: 'admin',
      );
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
            (route) => false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ToastService().show(
            message: 'Lỗi khi tạo hồ sơ: ${e.toString()}',
            type: ToastType.error);
      }
    }
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Vui lòng tạo một mật khẩu';
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
      appBar: AppBar(title: const Text('Hoàn tất Hồ sơ')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Chào mừng, ${widget.user.email}!',
                    textAlign: TextAlign.center,
                    style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text('Vui lòng nhập các thông tin sau để tiếp tục.',
                    textAlign: TextAlign.center, style: textTheme.titleMedium),
                const SizedBox(height: 30),
                CustomTextFormField(
                  controller: _storeNameController,
                  decoration: const InputDecoration(
                      labelText: 'Tên cửa hàng',
                      prefixIcon: Icon(Icons.store_outlined)),
                  validator: (value) =>
                      value!.isEmpty ? 'Không được để trống' : null,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _phoneController,
                  decoration: const InputDecoration(
                      labelText: 'Số điện thoại',
                      prefixIcon: Icon(Icons.phone_outlined)),
                  keyboardType: TextInputType.phone,
                  validator: _validatePhoneNumber,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                      labelText: 'Tạo mật khẩu đăng nhập',
                      prefixIcon: Icon(Icons.lock_open_outlined)),
                  obscureText: true,
                  validator: _validatePassword,
                ),
                const SizedBox(height: 16),
                CustomTextFormField(
                  controller: _confirmPasswordController,
                  decoration: const InputDecoration(
                      labelText: 'Xác nhận mật khẩu',
                      prefixIcon: Icon(Icons.lock_outline)),
                  obscureText: true,
                  validator: _validateConfirmPassword,
                ),
                const SizedBox(height: 30),
                _isLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ElevatedButton(
                            onPressed: _submitProfile,
                            child: const Text('Lưu và Bắt đầu'),
                          ),
                          const SizedBox(height: 12),
                          // NÚT HỦY ĐƯỢC THÊM VÀO
                          OutlinedButton(
                            onPressed: _cancelAndSignOut,
                            child: const Text('Hủy và Quay lại'),
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
