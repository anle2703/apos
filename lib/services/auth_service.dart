// lib/services/auth_service.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'firestore_service.dart';
import 'toast_service.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirestoreService _firestoreService = FirestoreService();

  Stream<User?> get user => _auth.authStateChanges();

  Future<dynamic> signInWithPhoneNumberPassword(
      String phoneNumber, String password) async {

    // --- BƯỚC 1: Thử đăng nhập cho OWNER ---
    try {
      final email = await _firestoreService.getEmailFromPhoneNumber(phoneNumber);
      // Nếu có email tức là owner, tiến hành đăng nhập bằng Firebase Auth
      if (email != null) {
        final userCredential = await _auth.signInWithEmailAndPassword(email: email, password: password);
        // Nếu thành công, trả về đối tượng User của Firebase
        return userCredential.user;
      }
    } on FirebaseAuthException {
      // Nếu sai mật khẩu owner, ta bỏ qua lỗi để tiếp tục kiểm tra nhân viên
    } catch (e) {
      debugPrint("AuthService Error: $e");
    }

    // --- BƯỚC 2: Nếu không phải owner, thử đăng nhập cho NHÂN VIÊN ---
    try {
      // Hàm này sẽ tự tìm user, mã hóa mật khẩu nhập vào và so sánh
      final employee = await _firestoreService.getEmployeeByPhone(phoneNumber, password);

      if (employee != null) {
        // [SỬA ĐỔI QUAN TRỌNG]
        // Bỏ đoạn check active ở đây.
        // Lý do: Chúng ta cần trả về object employee (dù active=false) 
        // để màn hình Login/AuthGate kiểm tra lý do khóa (hết hạn hay bị admin khóa).

        /* ĐOẠN CŨ ĐÃ XÓA:
        if (!employee.active) {
          ToastService().show(message: 'Tài khoản đã bị vô hiệu hóa.', type: ToastType.error);
          return null;
        }
        */

        // Trả về đối tượng UserModel (kể cả khi active = false)
        return employee;
      }
    } catch (e) {
      ToastService().show(message: 'Đã xảy ra lỗi: $e', type: ToastType.error);
      return null;
    }

    // --- BƯỚC 3: Nếu cả 2 đều thất bại ---
    ToastService().show(message: 'Số điện thoại hoặc mật khẩu không đúng.', type: ToastType.error);
    return null;
  }

  /// Đăng ký tài khoản bằng email + password
  Future<User?> signUpWithEmailPassword(
      String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } on FirebaseAuthException catch (e) {
      ToastService().show(
          message: e.message ?? 'Không thể tạo tài khoản.',
          type: ToastType.error);
      return null;
    } catch (e) {
      ToastService().show(
          message: 'Đã xảy ra lỗi. Vui lòng thử lại.',
          type: ToastType.error);
      return null;
    }
  }

  /// Đăng nhập Google (dành cho mobile, google_sign_in v5.x)
  Future<User?> signInWithGoogle() async {
    try {
      // B1: Chọn tài khoản Google
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        return null;
      }

      // B2: Lấy token
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;

      // B3: Tạo credential cho Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // B4: Đăng nhập Firebase
      final userCredential = await _auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      ToastService().show(
        message: 'Đăng nhập Google thất bại: $e',
        type: ToastType.error,
      );
      return null;
    }
  }

  /// Liên kết thêm password vào tài khoản
  Future<bool> linkPasswordToAccount(String password) async {
    try {
      final user = _auth.currentUser;
      if (user == null || user.email == null) {
        return false;
      }
      final credential =
      EmailAuthProvider.credential(email: user.email!, password: password);
      await user.linkWithCredential(credential);
      return true;
    } on FirebaseAuthException catch (e) {
      ToastService().show(
          message: e.message ?? 'Không thể liên kết mật khẩu.',
          type: ToastType.error);
      return false;
    } catch (e) {
      ToastService().show(
          message: 'Đã xảy ra lỗi. Vui lòng thử lại.',
          type: ToastType.error);
      return false;
    }
  }

  /// Đăng xuất
  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final isGoogleUser = user.providerData
            .any((provider) => provider.providerId == GoogleAuthProvider.PROVIDER_ID);

        if (isGoogleUser) {
          await GoogleSignIn().signOut();
        }
      }
    } catch (e) {
      debugPrint('Lỗi trong quá trình đăng xuất Google: $e');
    } finally {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('employee_uid');

      await _auth.signOut();
      await stopPrintServer();
    }
  }
}