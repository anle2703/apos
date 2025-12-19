// File: lib/screens/auth_gate.dart

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/table_model.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'create_profile_screen.dart';
import 'package:app_4cash/main.dart';
import '../services/settings_service.dart';
import '../models/store_settings_model.dart';
import 'sales/guest_order_screen.dart';
import '../screens/subscription_expired_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Widget _handleWebAppUrl(BuildContext context) {
    final Uri uri = Uri.base;
    final queryParams = uri.queryParameters;

    // Tất cả QR đều cần storeId
    final String? storeId = queryParams['store'];
    if (storeId == null) {
      // Không phải link QR, vào luồng đăng nhập
      return _buildAuthStream(context);
    }

    // Trường hợp 1: Order tại bàn (có token)
    final String? token = queryParams['token'];
    if (token != null) {
      return QrOrderLoader(token: token, storeId: storeId);
    }

    // Trường hợp 2: Book Ship / Schedule (có type)
    final String? type = queryParams['type'];
    if (type == 'ship' || type == 'schedule') {
      // SỬA LỖI 1: Thêm '!' vào 'type'
      return QrWebOrderLoader(storeId: storeId, type: type!);
    }

    // Mặc định: vào luồng đăng nhập
    return _buildAuthStream(context);
  }

  Widget _buildAuthStream(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          // 1. Nếu có session của Owner, vào thẳng ProfileCheck
          return ProfileCheck(user: snapshot.data!);
        }
        // 2. Nếu không, kiểm tra session của Nhân viên
        return const EmployeeSessionChecker();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return _handleWebAppUrl(context);
    } else {
      return _buildAuthStream(context);
    }
  }
}

class EmployeeSessionChecker extends StatelessWidget {
  const EmployeeSessionChecker({super.key});

  Future<Widget> _checkEmployeeSession() async {
    final prefs = await SharedPreferences.getInstance();
    final employeeUid = prefs.getString('employee_uid');

    // Chưa đăng nhập -> Login
    if (employeeUid == null) {
      return const LoginScreen();
    }

    final firestoreService = FirestoreService();
    final userProfile = await firestoreService.getUserProfile(employeeUid);

    // 1. Không tìm thấy user trong DB -> Xóa session -> Về Login
    if (userProfile == null) {
      await prefs.remove('employee_uid');
      return const LoginScreen();
    }

    // 2. User bị khóa (Active = false)
    if (!userProfile.active) {
      debugPrint(">>> [AuthGate] Nhân viên ${userProfile.name} bị khóa. Reason: ${userProfile.inactiveReason}");

      bool isExpired = false;
      DateTime expiryDate = DateTime.now();

      // A. Kiểm tra lý do từ DB (Nếu Cloud Function đã chạy và ghi lý do)
      if (userProfile.inactiveReason == 'store_expired' ||
          userProfile.inactiveReason == 'expired_subscription') {
        isExpired = true;
      }

      // B. Kiểm tra chéo ngày hết hạn của Owner (Đảm bảo chính xác 100%)
      if (userProfile.ownerUid != null) {
        try {
          final owner = await firestoreService.getUserProfile(userProfile.ownerUid!);
          if (owner != null && owner.subscriptionExpiryDate != null) {
            final ownerExpiry = owner.subscriptionExpiryDate!.toDate();
            if (DateTime.now().isAfter(ownerExpiry)) {
              isExpired = true;
              expiryDate = ownerExpiry;
            }
          }
        } catch (e) {
          debugPrint(">>> [AuthGate] Lỗi check owner: $e");
        }
      }

      if (isExpired) {
        // NẾU HẾT HẠN -> Trả về màn hình Hết hạn
        return SubscriptionExpiredScreen(expiryDate: expiryDate);
      } else {
        // NẾU BỊ KHÓA TAY (bởi Admin) -> Xóa session -> Về Login
        await prefs.remove('employee_uid');
        return const LoginScreen();
      }
    }

    // 3. Tài khoản Hợp lệ -> Vào Home
    startPrintServerForUser(userProfile);
    return HomeScreen(user: userProfile);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _checkEmployeeSession(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        // Điều hướng đến màn hình đã được quyết định ở trên (Home, Login hoặc Expired)
        return snapshot.data ?? const LoginScreen();
      },
    );
  }
}

class ProfileCheck extends StatefulWidget {
  final User user;
  const ProfileCheck({super.key, required this.user});

  @override
  State<ProfileCheck> createState() => _ProfileCheckState();
}

class _ProfileCheckState extends State<ProfileCheck> {
  @override
  void initState() {
    super.initState();
    _handleAuthUser();
  }

  Future<void> _handleAuthUser() async {
    final firestoreService = FirestoreService();
    final userProfile = await firestoreService.getUserProfile(widget.user.uid);

    if (!mounted) return;
    if (userProfile == null) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
            builder: (context) => CreateProfileScreen(user: widget.user)),
            (route) => false,
      );
      return;
    }
    if (userProfile.role == 'owner' && userProfile.subscriptionExpiryDate != null) {
      final expiry = userProfile.subscriptionExpiryDate!.toDate();
      if (DateTime.now().isAfter(expiry)) {
        // Nếu đã hết hạn, chuyển hướng sang màn hình báo lỗi
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => SubscriptionExpiredScreen(expiryDate: expiry)),
              (route) => false,
        );
        return;
      }
    }

    await startPrintServerForUser(userProfile);

    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => HomeScreen(user: userProfile)),
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class QrOrderLoader extends StatelessWidget {
  final String token;
  final String storeId;

  const QrOrderLoader({super.key, required this.token, required this.storeId});

  @override
  Widget build(BuildContext context) {
    final tableFuture = FirebaseFirestore.instance
        .collection('tables')
        .where('storeId', isEqualTo: storeId)
        .where('qrToken', isEqualTo: token)
        .limit(1)
        .get();

    final ownerFuture = FirebaseFirestore.instance
        .collection('users')
        .where('storeId', isEqualTo: storeId)
        .where('role', isEqualTo: 'owner')
        .limit(1)
        .get();

    final settingsFuture = ownerFuture.then((ownerSnap) {
      if (ownerSnap.docs.isEmpty) throw Exception("Không tìm thấy chủ sở hữu");
      final ownerId = ownerSnap.docs.first.id;
      return SettingsService().watchStoreSettings(ownerId).first;
    });

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([tableFuture, ownerFuture, settingsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildErrorScreen(
              'Lỗi kết nối. Vui lòng thử lại. ${snapshot.error}');
        }

        final tableSnapshot = snapshot.data![0] as QuerySnapshot;
        final ownerSnapshot = snapshot.data![1] as QuerySnapshot;
        final settings = snapshot.data![2] as StoreSettings;

        if (tableSnapshot.docs.isEmpty) {
          return _buildErrorScreen('Mã QR không hợp lệ hoặc đã hết hạn.');
        }

        if (ownerSnapshot.docs.isEmpty) {
          return _buildErrorScreen('Lỗi cấu hình cửa hàng (ERR:OWNR).');
        }

        final table = TableModel.fromFirestore(tableSnapshot.docs.first);
        final ownerUser = UserModel.fromFirestore(ownerSnapshot.docs.first);

        final guestUser = ownerUser.copyWith(
          uid: 'guest_${DateTime.now().millisecondsSinceEpoch}',
          role: 'guest',
          name: 'Khách order',
          permissions: {},
          email: null,
          phoneNumber: null,
          password: null,
          ownerUid: null,
        );

        return GuestOrderScreen(
          currentUser: guestUser,
          table: table,
          initialOrder: null,
          settings: settings,
        );
      },
    );
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      body: Center(
        child: Text(
          message,
          style: const TextStyle(fontSize: 18, color: Colors.red),
        ),
      ),
    );
  }
}

class QrWebOrderLoader extends StatelessWidget {
  final String storeId;
  final String type; // 'ship' hoặc 'schedule'

  const QrWebOrderLoader({super.key, required this.storeId, required this.type});

  @override
  Widget build(BuildContext context) {
    final ownerFuture = FirebaseFirestore.instance
        .collection('users')
        .where('storeId', isEqualTo: storeId)
        .where('role', isEqualTo: 'owner')
        .limit(1)
        .get();

    final settingsFuture = ownerFuture.then((ownerSnap) {
      if (ownerSnap.docs.isEmpty) {
        throw Exception("Không tìm thấy chủ sở hữu (storeId: $storeId)");
      }
      final ownerId = ownerSnap.docs.first.id;
      return SettingsService().watchStoreSettings(ownerId).first;
    });

    return FutureBuilder<List<dynamic>>(
      future: Future.wait([ownerFuture, settingsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError || !snapshot.hasData) {
          return _buildErrorScreen(
              'Lỗi kết nối hoặc cấu hình cửa hàng. ${snapshot.error}');
        }

        final ownerSnapshot = snapshot.data![0] as QuerySnapshot;
        final settings = snapshot.data![1] as StoreSettings;

        if (ownerSnapshot.docs.isEmpty) {
          return _buildErrorScreen('Lỗi cấu hình cửa hàng (ERR:OWNR).');
        }

        final ownerUser = UserModel.fromFirestore(ownerSnapshot.docs.first);
        final String guestName =
        (type == 'ship') ? 'Đặt giao hàng' : 'Đặt lịch hẹn';

        final guestUser = ownerUser.copyWith(
          uid: 'guest_${type}_${DateTime.now().millisecondsSinceEpoch}',
          role: 'guest',
          name: guestName,
          permissions: {},
          email: null,
          phoneNumber: null,
          password: null,
          ownerUid: null,
        );

        // SỬA LỖI 2: Thay 'TableModel.fromMap' bằng 'TableModel'
        final placeholderTable = TableModel(
          id: 'web_${type}_order',
          tableName: guestName,
          storeId: storeId,
          tableGroup: 'Web Order',
          stt: 999,
          qrToken: null,
          serviceId: '',
        );

        return GuestOrderScreen(
          currentUser: guestUser,
          table: placeholderTable,
          initialOrder: null,
          settings: settings,
        );
      },
    );
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            message,
            style: const TextStyle(fontSize: 18, color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}