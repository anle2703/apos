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
  static bool isManualProcess = false;
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
        if (AuthGate.isManualProcess) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 20),
                  Text("Đang xử lý đăng ký...", style: TextStyle(fontSize: 16)),
                ],
              ),
            ),
          );
        }
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
    // Sử dụng FutureBuilder để xử lý trạng thái
    return FutureBuilder<List<dynamic>>(
      // Dùng Future.wait nhưng bọc try-catch bên trong builder hoặc đảm bảo Rules đã mở
      future: Future.wait([
        // 1. Lấy thông tin bàn
        FirebaseFirestore.instance
            .collection('tables')
            .where('storeId', isEqualTo: storeId)
            .where('qrToken', isEqualTo: token)
            .limit(1)
            .get(),
        // 2. Lấy cài đặt cửa hàng (Code SettingsService của bạn đã đúng)
        SettingsService().getStoreSettings(storeId),
      ]),
      builder: (context, snapshot) {
        // ĐANG TẢI
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        // CÓ LỖI (VÍ DỤ: CHẶN QUYỀN ĐỌC) -> HIỆN LỖI CHỨ KHÔNG TRẮNG MÀN HÌNH
        if (snapshot.hasError) {
          debugPrint("Lỗi QR Loader: ${snapshot.error}");
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 50, color: Colors.red),
                    const SizedBox(height: 10),
                    const Text("Không thể tải dữ liệu.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text("Lỗi: ${snapshot.error}", textAlign: TextAlign.center),
                    const SizedBox(height: 20),
                    const Text("Gợi ý: Kiểm tra Firestore Rules đã mở quyền đọc cho 'tables' và 'store_settings' chưa."),
                  ],
                ),
              ),
            ),
          );
        }

        // XỬ LÝ DỮ LIỆU
        try {
          final tableSnapshot = snapshot.data![0] as QuerySnapshot;
          final settings = snapshot.data![1] as StoreSettings;

          if (tableSnapshot.docs.isEmpty) {
            return const Scaffold(body: Center(child: Text("Mã QR không hợp lệ (Bàn không tồn tại).")));
          }

          final table = TableModel.fromFirestore(tableSnapshot.docs.first);

          // Tạo user ảo cho khách
          final guestUser = UserModel(
            uid: 'guest_${DateTime.now().millisecondsSinceEpoch}',
            role: 'guest',
            name: 'Khách order',
            phoneNumber: '',
            storeId: storeId,
            storeName: settings.storeName ?? 'Cửa hàng',
            businessType: settings.businessType ?? 'fnb',
            active: true,
            permissions: {},
            createdAt: Timestamp.now(),
          );

          return GuestOrderScreen(
            currentUser: guestUser,
            table: table,
            initialOrder: null,
            settings: settings,
          );
        } catch (e) {
          return Scaffold(body: Center(child: Text("Lỗi xử lý dữ liệu: $e")));
        }
      },
    );
  }
}

class QrWebOrderLoader extends StatelessWidget {
  final String storeId;
  final String type; // 'ship' hoặc 'schedule'

  const QrWebOrderLoader({super.key, required this.storeId, required this.type});

  @override
  Widget build(BuildContext context) {
    final settingsFuture = SettingsService().getStoreSettings(storeId);

    return FutureBuilder<StoreSettings>(
      future: settingsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          return _buildErrorScreen('Lỗi tải cấu hình: ${snapshot.error}');
        }

        // SỬA Ở ĐÂY: Truyền tham số bắt buộc nếu data null
        final settings = snapshot.data ?? const StoreSettings(
          printBillAfterPayment: true,
          allowProvisionalBill: true,
          notifyKitchenAfterPayment: false,
          showPricesOnProvisional: false,
        );

        try {
          final String guestName = (type == 'ship') ? 'Đặt giao hàng' : 'Đặt lịch hẹn';

          final guestUser = UserModel(
            uid: 'guest_${type}_${DateTime.now().millisecondsSinceEpoch}',
            role: 'guest',
            name: guestName,
            phoneNumber: '',
            storeId: storeId,
            businessType: settings.businessType ?? 'fnb',
            active: true,
            permissions: {},
            createdAt: Timestamp.now(),
          );

          final placeholderTable = TableModel(
            id: 'web_${type}_order',
            tableName: guestName,
            storeId: storeId,
            tableGroup: 'Web Order',
            stt: 999,
            serviceId: '',
          );

          return GuestOrderScreen(
            currentUser: guestUser,
            table: placeholderTable,
            initialOrder: null,
            settings: settings,
          );
        } catch (e) {
          return _buildErrorScreen('Lỗi khởi tạo màn hình: $e');
        }
      },
    );
  }

  Widget _buildErrorScreen(String message) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.warning_amber_rounded, size: 50, color: Colors.orange),
              const SizedBox(height: 10),
              Text(
                message,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}