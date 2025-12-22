// lib/screens/home_screen.dart

import 'dart:async';
import 'package:app_4cash/products/order/purchase_orders_list_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../../services/toast_service.dart';
import '../products/product_list_screen.dart';
import '../bills/bill_history_screen.dart';
import 'auth_gate.dart';
import '../tables/table_list_screen.dart';
import '../tables/table_selection_screen.dart';
import 'settings/settings_screen.dart';
import '../services/print_queue_service.dart';
import 'promotions/promotions_screen.dart';
import 'users/employee_management_screen.dart';
import 'report/report_screen.dart';
import 'contacts/contacts_screen.dart';
import '../screens/payment_methods_screen.dart';
import 'invoice/e_invoice_settings_screen.dart';
import 'tax_management_screen.dart';
import 'sales/retail_order_screen.dart';
import '../products/labels/product_label_print_screen.dart';
import '../services/shift_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'subscription_expired_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/settings_service.dart';

class HomeScreen extends StatefulWidget {
  final UserModel? user;

  const HomeScreen({super.key, this.user});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel_v4', // id bắt buộc phải khớp với server gửi về
  'Thông báo thanh toán', // title hiện trong setting điện thoại
  description: 'Kênh thông báo nhận tiền và đơn hàng',
  importance: Importance.max, // QUAN TRỌNG: Để hiện popup (heads-up)
  playSound: true,
);

class _HomeScreenState extends State<HomeScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final AuthService _authService = AuthService();
  final SettingsService _settingsService = SettingsService();

  UserModel? _currentUser;
  int _selectedIndex = 2;
  Future<void>? _initializationFuture;
  StreamSubscription? _userStatusSubscription;
  StreamSubscription? _ownerStatusSubscription;
  bool _canViewPurchaseOrder = false;
  bool _canViewPromotions = false;
  bool _canViewListTable = false;
  bool _canViewEmployee = false;
  bool _canPrintLabel = false;
  bool _canEditTax = false;
  bool _isShowingTypePicker = false;
  bool _canViewContacts = false;
  bool _isNotificationSetup = false;
  Map<String, dynamic>? _contactInfo;
  String _appVersion = '';
  final Map<String, dynamic> _adminContact = {
    'phone': '0935417776',
    'facebook': 'https://www.facebook.com/anlee2502',
    'zalo': '0935417776',
  };
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    _initializationFuture = _initializeUserAndSettings();
    _getAppVersion();
    _setupNotificationSystem();
  }

  Future<void> _getAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _appVersion = info.version;
      });
    }
  }

  @override
  void dispose() {
    PrintQueueService().dispose();
    _userStatusSubscription?.cancel();
    _ownerStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _setupNotificationSystem() async {
    if (_isNotificationSetup || _currentUser == null) return;
    _isNotificationSetup = true;

    final prefs = await SharedPreferences.getInstance();
    bool isDeviceEnabled = prefs.getBool('device_notify_enabled') ?? false;

    // Nếu đã tắt trong cài đặt -> Xóa token khỏi store_settings
    if (!isDeviceEnabled) {
      try {
        String? token = await FirebaseMessaging.instance.getToken();
        if (token != null) {
          await _settingsService.updateStoreSettings(
              _currentUser!.storeId,
              {'fcmTokens': FieldValue.arrayRemove([token])}
          );
        }
      } catch (e) {
        debugPrint("Lỗi xóa token cache: $e");
      }
      return;
    }

    FirebaseMessaging messaging = FirebaseMessaging.instance;

    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('>>> [DEBUG] Người dùng từ chối quyền thông báo!');
      return;
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await _localNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        debugPrint(">>> [DEBUG] Bấm vào thông báo: ${details.payload}");
        if (details.payload == 'low_stock') {
          _navigateToInventoryReport();
        }
      },
    );

    try {
      String? token = await FirebaseMessaging.instance.getToken();
      await _settingsService.updateStoreSettings(
          _currentUser!.storeId,
          {'fcmTokens': FieldValue.arrayUnion([token])}
      );
    } catch (e) {
      debugPrint(">>> [DEBUG] Lỗi đồng bộ Token: $e");
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint(
          ">>> [DEBUG] TIN NHẮN ĐẾN KHI APP MỞ: ${message.notification?.title}");

      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;

      if (notification != null && android != null) {
        // Thêm check android != null
        _localNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            // Bỏ const vì channel.id không phải hằng số biên dịch
            android: AndroidNotificationDetails(
              channel.id, // Sử dụng ID từ channel đã tạo phía trên
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
              largeIcon:
                  const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            ),
          ),
        );
      }
    });

    // 5. Xử lý khi bấm vào thông báo từ Background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      if (message.data['type'] == 'low_stock') {
        _navigateToInventoryReport();
      }
    });
  }

  void _navigateToInventoryReport() {
    setState(() {
      // 1. Thay đổi số này thành Index của màn hình Báo cáo trong BottomNavigationBar của bạn
      _selectedIndex = 3;
    });

    // 2. Chuyển tab con sang "Tồn kho"
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReportScreen.selectedTabNotifier.value = 3;
    });
  }

  Future<void> _initializeUserAndSettings() async {
    UserModel? loadedUser;

    if (widget.user != null) {
      loadedUser = widget.user;
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        loadedUser = await _firestoreService.getUserProfile(uid);
      }
    }

    if (loadedUser == null) return;

    if (mounted) {
      setState(() {
        _currentUser = loadedUser;
        _checkAndShowBusinessTypePicker();
      });
    }

    if (_currentUser != null) {
      try {
        final settings = await _settingsService.getStoreSettings(_currentUser!.storeId);

        if (settings.businessType != null && settings.businessType!.isNotEmpty) {
          if (mounted) {
            setState(() {
              _currentUser = _currentUser!.copyWith(businessType: settings.businessType);
            });
          }
        } else {
          if(mounted) _checkAndShowBusinessTypePicker();
        }

        final String? agentId = settings.agentId;

        if (agentId != null && agentId.isNotEmpty) {
          final doc = await FirebaseFirestore.instance.collection('app_config').doc(agentId).get();
          if (doc.exists && doc.data() != null) {
            if (mounted) setState(() => _contactInfo = doc.data());
          } else {
            if (mounted) setState(() => _contactInfo = _adminContact);
          }
        } else {
          if (mounted) setState(() => _contactInfo = _adminContact);
        }
      } catch (e) {
        debugPrint("Lỗi lấy thông tin đại lý/settings: $e");
        if (mounted) setState(() => _contactInfo = _adminContact);
      }
    }

    _listenForUserStatusChanges();

    if (_currentUser != null) {
      await PrintQueueService().initialize(_currentUser!.storeId);
    }

    if (_currentUser!.role != 'guest') {
      final String realOwnerUid = _currentUser!.role == 'owner'
          ? _currentUser!.uid
          : (_currentUser!.ownerUid ?? _currentUser!.uid);

      ShiftService().ensureShiftOpen(
        _currentUser!.storeId,
        _currentUser!.uid,
        _currentUser!.name ?? 'Nhân viên',
        realOwnerUid,
      );
    }
  }

  Future<void> _handleContactAction(String type, String value) async {
    if (value.isEmpty) {
      ToastService().show(
          message: 'Chưa cập nhật thông tin này.', type: ToastType.warning);
      return;
    }

    // 1. Kiểm tra xem đang chạy trên Mobile hay Desktop
    bool isMobile = false;
    try {
      isMobile = Platform.isAndroid || Platform.isIOS;
    } catch (e) {
      isMobile = false; // Fallback (ví dụ chạy web)
    }

    try {
      // --- XỬ LÝ FACEBOOK ---
      if (type == 'facebook') {
        String urlString = value;
        if (!urlString.startsWith('http')) {
          urlString = 'https://www.facebook.com/$value';
        }
        final Uri uri = Uri.parse(urlString);

        if (isMobile) {
          // Mobile: Thử mở bằng App Facebook trước (externalApplication)
          // Nếu không được (chưa cài App) -> Tự động fallback sang trình duyệt
          bool launched =
              await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (!launched) {
            await launchUrl(uri, mode: LaunchMode.platformDefault);
          }
        } else {
          // Desktop: Mở trình duyệt luôn
          await launchUrl(uri, mode: LaunchMode.platformDefault);
        }
        return;
      }

      // --- XỬ LÝ SỐ ĐIỆN THOẠI ---
      if (type == 'phone') {
        if (!isMobile) {
          // Desktop: Luôn hiện Popup
          _showInfoPopup('Số điện thoại', value);
          return;
        }

        // Mobile: Thử gọi điện
        final Uri uri = Uri(scheme: 'tel', path: value);
        bool canCall = await canLaunchUrl(uri);

        if (canCall) {
          await launchUrl(uri);
        } else {
          // Mobile không gọi được (ví dụ iPad, máy ảo) -> Hiện Popup
          if (mounted) _showInfoPopup('Số điện thoại', value);
        }
        return;
      }

      // --- XỬ LÝ ZALO ---
      if (type == 'zalo') {
        if (!isMobile) {
          // Desktop: Luôn hiện Popup
          _showInfoPopup('Zalo', value);
          return;
        }

        // Mobile: Dùng link https chuẩn
        final Uri uri = Uri.parse("https://zalo.me/$value");

        bool launched =
            await launchUrl(uri, mode: LaunchMode.externalApplication);

        if (!launched) {
          if (mounted) _showInfoPopup('Zalo', value);
        }
        return;
      }
    } catch (e) {
      debugPrint("Lỗi Contact: $e");
      // Fallback an toàn cuối cùng: Hiện popup nếu là sdt/zalo
      if (mounted && (type == 'phone' || type == 'zalo')) {
        _showInfoPopup(type == 'zalo' ? 'Zalo' : 'Thông tin liên hệ', value);
      }
    }
  }

  void _showInfoPopup(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 18)),
        content: Row(
          children: [
            Expanded(
                child: Text(content,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold))),
            IconButton(
              icon: const Icon(Icons.copy, color: Colors.blue),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.of(ctx).pop();
                ToastService().show(
                    message: 'Đã sao chép $content', type: ToastType.success);
              },
            )
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Đóng'))
        ],
      ),
    );
  }

  Future<void> _checkAndShowBusinessTypePicker() async {
    if (_currentUser == null) return;
    if (_currentUser!.role != 'owner') return;
    if (_isShowingTypePicker) return;

    if (_currentUser!.businessType != null && _currentUser!.businessType!.isNotEmpty) {
      return;
    }

    try {
      final settings = await _settingsService.getStoreSettings(_currentUser!.storeId);

      if (settings.businessType != null && settings.businessType!.isNotEmpty) {
        if (mounted) {
          setState(() {
            _currentUser = _currentUser!.copyWith(businessType: settings.businessType);
          });
        }
        return;
      }
    } catch (e) {
      debugPrint("Store Settings chưa tồn tại (User mới), chuẩn bị hiện Popup: $e");
    }

    _isShowingTypePicker = true;

    await Future.delayed(const Duration(milliseconds: 500));

    if (mounted) {
      if (_currentUser!.businessType != null && _currentUser!.businessType!.isNotEmpty) {
        _isShowingTypePicker = false;
        return;
      }
      _showBusinessTypePicker(context);
    }
  }

  void _processExpiredUser(Timestamp? expiryTimestamp) {
    if (expiryTimestamp == null) return;

    final expiry = expiryTimestamp.toDate();
    if (DateTime.now().isAfter(expiry)) {
      _userStatusSubscription?.cancel(); // Dừng lắng nghe user
      _ownerStatusSubscription?.cancel(); // Dừng lắng nghe owner
      _ownerStatusSubscription = null;
      _authService.signOut().then((_) {
        if (mounted) {
          Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(
                  builder: (context) =>
                      SubscriptionExpiredScreen(expiryDate: expiry)),
              (route) => false);
        }
      });
    }
  }

  void _startListeningToOwnerStatus(String ownerUid) {
    if (_ownerStatusSubscription != null) return;

    _ownerStatusSubscription =
        _firestoreService.streamUserProfile(ownerUid).listen((ownerProfile) {
      if (ownerProfile != null) {
        _processExpiredUser(ownerProfile.subscriptionExpiryDate);
      }
    });
  }

  void _listenForUserStatusChanges() {
    _userStatusSubscription?.cancel();
    _ownerStatusSubscription?.cancel();
    _ownerStatusSubscription = null;

    if (_currentUser != null) {
      final navigator = Navigator.of(context);

      _userStatusSubscription = _firestoreService
          .streamUserProfile(_currentUser!.uid)
          .listen((userProfile) {
        // --- [SỬA LỖI CRASH WINDOWS TẠI ĐÂY] ---
        // Bao bọc logic bằng Future.delayed để ép nó chạy trên UI Thread
        Future.delayed(Duration.zero, () {
          if (!mounted) return; // Kiểm tra lại mounted sau khi delay

          if (userProfile == null) {
            _authService.signOut().then((_) {
              navigator.pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const AuthGate()),
                  (route) => false);
            });
            return;
          }

          if (!userProfile.active) {
            bool isExpired = false;
            if (userProfile.inactiveReason == 'store_expired' ||
                userProfile.inactiveReason == 'expired_subscription') {
              isExpired = true;
            } else if (userProfile.role == 'owner' &&
                userProfile.subscriptionExpiryDate != null &&
                DateTime.now()
                    .isAfter(userProfile.subscriptionExpiryDate!.toDate())) {
              isExpired = true;
            }

            if (isExpired) {
              // A. Xử lý cho NHÂN VIÊN
              if (userProfile.role != 'owner' && userProfile.ownerUid != null) {
                _firestoreService
                    .getUserProfile(userProfile.ownerUid!)
                    .then((owner) {
                  DateTime expiryDisplay = DateTime.now();
                  if (owner != null && owner.subscriptionExpiryDate != null) {
                    expiryDisplay = owner.subscriptionExpiryDate!.toDate();
                  }
                  _executeLogoutAndShowExpiry(navigator, expiryDisplay);
                });
                return;
              }

              // B. Xử lý cho CHỦ
              if (userProfile.role == 'owner' &&
                  userProfile.subscriptionExpiryDate != null) {
                final expiryDisplay =
                    userProfile.subscriptionExpiryDate!.toDate();
                _executeLogoutAndShowExpiry(navigator, expiryDisplay);
                return;
              }
            }

            ToastService().show(
                message: 'Tài khoản của bạn đã bị quản trị viên vô hiệu hóa.',
                type: ToastType.error,
                duration: const Duration(seconds: 4));

            Future.delayed(const Duration(milliseconds: 500), () {
              _authService.signOut().then((_) {
                navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const AuthGate()),
                    (route) => false);
              });
            });
            return;
          }

          if (userProfile.role == 'owner') {
            _processExpiredUser(userProfile.subscriptionExpiryDate);
          } else if (userProfile.ownerUid != null) {
            _startListeningToOwnerStatus(userProfile.ownerUid!);
          }

          // Cập nhật quyền hạn
          if (userProfile.role == 'owner') {
            _canViewPurchaseOrder = true;
            _canViewPromotions = true;
            _canViewListTable = true;
            _canViewEmployee = true;
            _canPrintLabel = true;
            _canEditTax = true;
            _canViewContacts = true;
          } else {
            _canViewPurchaseOrder = userProfile.permissions?['purchaseOrder']
                    ?['canViewPurchaseOrder'] ??
                false;
            _canViewPromotions = userProfile.permissions?['promotions']
                    ?['canViewPromotions'] ??
                false;
            _canViewListTable = userProfile.permissions?['listTable']
                    ?['canViewListTable'] ??
                false;
            _canViewEmployee = userProfile.permissions?['employee']
                    ?['canViewEmployee'] ??
                false;
            _canPrintLabel =
                userProfile.permissions?['products']?['canPrintLabel'] ?? false;
            _canEditTax =
                userProfile.permissions?['products']?['canEditTax'] ?? false;
            _canViewContacts = userProfile.permissions?['contacts']
                    ?['canViewContacts'] ??
                false;
          }

          if (mounted) {
            setState(() {
              _currentUser = userProfile.copyWith(
                businessType:
                    userProfile.businessType ?? _currentUser?.businessType,
              );
            });
            _checkAndShowBusinessTypePicker();
          }
        });
      });
    }
  }

  void _executeLogoutAndShowExpiry(
      NavigatorState navigator, DateTime expiryDate) {
    _userStatusSubscription?.cancel();
    _ownerStatusSubscription?.cancel();
    _ownerStatusSubscription = null;

    _authService.signOut().then((_) {
      if (mounted) {
        navigator.pushAndRemoveUntil(
            MaterialPageRoute(
                builder: (context) =>
                    SubscriptionExpiredScreen(expiryDate: expiryDate)),
            (route) => false);
      }
    });
  }

  void _showBusinessTypePicker(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return BusinessTypePickerPopup(
          onConfirm: (type, useSampleData) async {
            // --- BƯỚC 1: CẬP NHẬT RAM ---
            if (mounted) {
              setState(() {
                _currentUser = _currentUser!.copyWith(businessType: type);
              });
            }
            try {
              // Lưu settings
              await _settingsService.updateStoreSettings(
                  _currentUser!.storeId,
                  {'businessType': type}
              );

              if (useSampleData) {
                ToastService().show(
                    message: 'Đang khởi tạo dữ liệu mẫu...',
                    type: ToastType.warning
                );

                await _firestoreService.copySampleDataFromTemplate(_currentUser!.storeId);

                ToastService().show(
                    message: 'Đã thêm dữ liệu mẫu thành công!',
                    type: ToastType.success
                );
              }
            } catch (e) {
              debugPrint("Lỗi khởi tạo store: $e");
            }
          },
        );
      },
    ).then((_) {
      // Đảm bảo reset cờ khi popup đóng
      _isShowingTypePicker = false;
    });
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      if (_currentUser?.role == 'order') {
        ToastService().show(
          message: 'Bạn không có quyền truy cập lịch sử Đơn hàng.',
          type: ToastType.warning,
        );
        return; // Dừng lại, không chuyển tab
      }
    }

    // Nếu thỏa mãn điều kiện thì mới chuyển tab
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildCurrentPage() {
    if (_currentUser == null) {
      return const Center(child: CircularProgressIndicator());
    }

    // [CẤU TRÚC MỚI]: 0:Sản phẩm, 1:Đơn hàng, 2:Bán hàng, 3:Báo cáo, 4:Khác
    switch (_selectedIndex) {
      case 0: // Vị trí 1 cũ -> Giờ là Sản phẩm
        return ProductListScreen(currentUser: _currentUser!);
      case 1: // Vị trí 2 cũ -> Giờ là Đơn hàng
        return BillHistoryScreen(currentUser: _currentUser!);
      case 2: // Vị trí 0 cũ -> Giờ là Bán hàng (Ở Giữa)
        if (_currentUser!.businessType == 'fnb') {
          return TableSelectionScreen(currentUser: _currentUser!);
        } else {
          return RetailOrderScreen(currentUser: _currentUser!);
        }
      case 3:
        return ReportScreen(currentUser: _currentUser!);
      case 4:
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: false,
            titleSpacing: 0,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,

            title: (_currentUser?.role == 'owner' &&
                    _currentUser?.subscriptionExpiryDate != null)
                ? Builder(builder: (context) {
                    final expiry =
                        _currentUser!.subscriptionExpiryDate!.toDate();

                    // Format thời gian
                    final hour = expiry.hour.toString().padLeft(2, '0');
                    final minute = expiry.minute.toString().padLeft(2, '0');
                    final day = expiry.day.toString().padLeft(2, '0');
                    final month = expiry.month.toString().padLeft(2, '0');
                    final year = expiry.year;

                    // Logic màu
                    final daysLeft = expiry.difference(DateTime.now()).inDays;
                    final isUrgent = daysLeft <= 30;
                    final Color displayColor =
                        isUrgent ? Colors.red : Theme.of(context).primaryColor;

                    // Container đóng vai trò là dải nền cắt ngang
                    return Container(
                      width: double.infinity,
                      // Full chiều ngang
                      height: kToolbarHeight,
                      // Chiều cao bằng đúng AppBar (56.0)
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      // Padding nội dung bên trong
                      color: displayColor.withAlpha(12),
                      // Màu nền mờ
                      alignment: Alignment.centerLeft,
                      // Căn nội dung sang trái
                      child: Row(
                        children: [
                          Icon(Icons.workspace_premium, color: displayColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Hạn sử dụng: $hour:$minute $day/$month/$year',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: displayColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  })
                : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Tài khoản: ${_currentUser?.name ?? "Lỗi hiển thị tên TK"}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          body: ListView(
            children: [
              if (_contactInfo != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8), // Padding nhỏ
                  child: Row(
                    children: [
                      // Tiêu đề nhỏ gọn bên trái
                      Text(
                        'V$_appVersion - Liên hệ hỗ trợ:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Icon Phone
                      _buildCompactIcon(
                          icon: Icons.phone,
                          color: Colors.blue,
                          onTap: () => _handleContactAction(
                              'phone', _contactInfo!['phone'] ?? '')),
                      const SizedBox(width: 8),

                      // Icon Facebook
                      _buildCompactIcon(
                          icon: Icons.facebook,
                          color: Colors.blue[800]!, // Màu xanh đậm FB
                          onTap: () => _handleContactAction(
                              'facebook', _contactInfo!['facebook'] ?? '')),
                      const SizedBox(width: 8),

                      // Icon Zalo (Dùng Icon chat + Chữ Z để giả lập)
                      _buildCompactIcon(
                        icon: Icons.circle,
                        color: const Color(0xFF0068FF),
                        onTap: () => _handleContactAction(
                            'zalo', _contactInfo!['zalo'] ?? ''),
                        isZalo: true, // Cờ đánh dấu để xử lý hiển thị đặc biệt
                      ),
                    ],
                  ),
                ),
              const Divider(height: 1, thickness: 0.5, color: Colors.grey),
              // --- KẾT THÚC ĐOẠN UI MỚI ---
              if (_currentUser?.role != 'order') ...[
                ListTile(
                  leading: const Icon(Icons.add_business_outlined),
                  title: const Text('Quản lý nhập hàng'),
                  onTap: () {
                    if (_currentUser != null && _canViewPurchaseOrder) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => PurchaseOrdersListScreen(
                                currentUser: _currentUser!)),
                      );
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser?.businessType == 'retail')
                  ListTile(
                    leading: const Icon(Icons.print_outlined),
                    title: const Text('In tem sản phẩm'),
                    onTap: () {
                      if (_currentUser != null && _canPrintLabel) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => ProductLabelPrintScreen(
                                  currentUser: _currentUser!)),
                        );
                      } else {
                        ToastService().show(
                            message:
                                'Bạn chưa được cấp quyền sử dụng tính năng này.',
                            type: ToastType.warning);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.sell_outlined),
                  title: const Text('Phụ thu & Khuyến mãi'),
                  onTap: () {
                    if (_currentUser != null && _canViewPromotions) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) =>
                                PromotionsScreen(currentUser: _currentUser!)),
                      );
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser?.businessType == 'fnb')
                  ListTile(
                    leading: const Icon(Icons.chair_outlined),
                    title: const Text('Quản lý phòng bàn'),
                    onTap: () {
                      if (_currentUser != null && _canViewListTable) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => TableListScreen(
                              currentUser: _currentUser!,
                            ),
                          ),
                        );
                      } else {
                        ToastService().show(
                            message:
                                'Bạn chưa được cấp quyền sử dụng tính năng này.',
                            type: ToastType.warning);
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.people_alt_outlined),
                  title: const Text('Quản lý nhân viên'),
                  onTap: () {
                    if (_currentUser != null && _canViewEmployee) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => EmployeeManagementScreen(
                            currentUser: _currentUser!,
                          ),
                        ),
                      );
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.business_center_outlined),
                  title: const Text('Quản lý đối tác'),
                  onTap: () {
                    if (_currentUser != null && _canViewContacts) {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => ContactsScreen(
                            currentUser: _currentUser!,
                          ),
                        ),
                      );
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                if (_currentUser!.role == 'owner')
                  ListTile(
                    leading: const Icon(Icons.payment_outlined),
                    title: const Text('Phương thức thanh toán'),
                    onTap: () {
                      if (_currentUser != null) {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              PaymentMethodsScreen(currentUser: _currentUser!),
                        ));
                      }
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.calculate_outlined),
                  title: const Text('Thuế & Kê khai'),
                  onTap: () {
                    if (_currentUser != null && _canEditTax) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            TaxManagementScreen(currentUser: _currentUser!),
                      ));
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Kết nối HĐĐT'),
                  onTap: () {
                    if (_currentUser != null && _canEditTax) {
                      Navigator.of(context).push(MaterialPageRoute(
                        builder: (context) =>
                            EInvoiceSettingsScreen(currentUser: _currentUser!),
                      ));
                    } else {
                      ToastService().show(
                          message:
                              'Bạn chưa được cấp quyền sử dụng tính năng này.',
                          type: ToastType.warning);
                    }
                  },
                ),
                const Divider(height: 4, thickness: 0.5, color: Colors.grey),
              ],

              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Cài đặt'),
                onTap: () {
                  if (_currentUser != null) {
                    Navigator.of(context)
                        .push(MaterialPageRoute(
                      builder: (context) =>
                          SettingsScreen(currentUser: _currentUser!),
                    ))
                        .then((_) {
                      setState(() {
                        _initializationFuture = _initializeUserAndSettings();
                      });
                    });
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Đăng xuất'),
                onTap: () async {
                  final navigator = Navigator.of(context);
                  await _authService.signOut();
                  navigator.pushAndRemoveUntil(
                    MaterialPageRoute(builder: (context) => const AuthGate()),
                    (route) => false,
                  );
                },
              ),
            ],
          ),
        );
      default:
        // Default trả về Bán hàng để an toàn
        if (_currentUser!.businessType == 'fnb') {
          return TableSelectionScreen(currentUser: _currentUser!);
        } else {
          return RetailOrderScreen(currentUser: _currentUser!);
        }
    }
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
        padding: const EdgeInsets.all(6), // Padding nhỏ quanh icon
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          shape: BoxShape.circle,
        ),
        child: isZalo
            ? Stack(
                alignment: Alignment.center,
                children: [
                  Icon(icon, color: color, size: 23), // Icon nhỏ size 20
                  Text(
                    'Zalo',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 7,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                            offset: const Offset(1, 1),
                            blurRadius: 2,
                            color: color)
                      ],
                    ),
                  ),
                ],
              )
            : Icon(icon,
                color: color, size: 23), // Icon bình thường nhỏ size 20
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initializationFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError) {
          return Scaffold(
            body: Center(child: Text('Đã xảy ra lỗi: ${snapshot.error}')),
          );
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            const double mobileBreakpoint = 700;
            if (constraints.maxWidth < mobileBreakpoint) {
              return _buildMobileLayout();
            } else {
              return _buildDesktopLayout();
            }
          },
        );
      },
    );
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _onItemTapped,
            labelType: NavigationRailLabelType.all,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0),
              child: Icon(Icons.shopping_bag_outlined,
                  size: 40, color: Theme.of(context).primaryColor),
            ),
            destinations: const <NavigationRailDestination>[
              // Index 0: Sản phẩm
              NavigationRailDestination(
                  icon: Icon(Icons.inventory_2),
                  selectedIcon: Icon(Icons.inventory_2_outlined),
                  label: Text('Sản phẩm')),
              // Index 1: Đơn hàng
              NavigationRailDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long),
                  label: Text('Đơn hàng')),
              // Index 2: Bán hàng (Ở giữa)
              NavigationRailDestination(
                  icon: Icon(Icons.add_shopping_cart_outlined),
                  selectedIcon: Icon(Icons.add_shopping_cart),
                  label: Text('Bán hàng')),
              // Index 3: Báo cáo
              NavigationRailDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: Text('Báo cáo')),
              // Index 4: Khác
              NavigationRailDestination(
                  icon: Icon(Icons.more_horiz_outlined),
                  selectedIcon: Icon(Icons.more_horiz),
                  label: Text('Khác')),
            ],
          ),
          Expanded(
            child: _buildCurrentPage(),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      body: _buildCurrentPage(),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          // Index 0: Sản phẩm
          BottomNavigationBarItem(
              icon: Icon(Icons.inventory_2_outlined),
              activeIcon: Icon(Icons.inventory_2),
              label: 'Sản phẩm'),
          // Index 1: Đơn hàng
          BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Đơn hàng'),
          // Index 2: Bán hàng (Ở giữa) - Có thể làm icon to hơn hoặc màu khác nếu muốn
          BottomNavigationBarItem(
              icon: Icon(Icons.add_shopping_cart_outlined),
              activeIcon: Icon(Icons.add_shopping_cart),
              label: 'Bán hàng'),
          // Index 3: Báo cáo
          BottomNavigationBarItem(
              icon: Icon(Icons.bar_chart_outlined),
              activeIcon: Icon(Icons.bar_chart),
              label: 'Báo cáo'),
          // Index 4: Khác
          BottomNavigationBarItem(
              icon: Icon(Icons.more_horiz_outlined),
              activeIcon: Icon(Icons.more_horiz),
              label: 'Khác'),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

class BusinessTypePickerPopup extends StatefulWidget {
  // Cập nhật: onConfirm nhận thêm bool useSampleData
  final Function(String type, bool useSampleData) onConfirm;

  const BusinessTypePickerPopup({super.key, required this.onConfirm});

  @override
  State<BusinessTypePickerPopup> createState() =>
      _BusinessTypePickerPopupState();
}

class _BusinessTypePickerPopupState extends State<BusinessTypePickerPopup> {
  String? _selectedType;
  bool _useSampleData = true; // Mặc định bật
  bool _isUpdating = false;

  @override
  Widget build(BuildContext context) {
    // Lấy chiều rộng màn hình để chỉnh layout
    final screenWidth = MediaQuery.of(context).size.width;
    final bool isMobile = screenWidth < 600;

    return AlertDialog(
      title: const Text('Chọn Ngành nghề Kinh doanh', textAlign: TextAlign.center),
      content: Container(
        // Giới hạn chiều rộng để popup không quá to trên desktop
        width: isMobile ? double.maxFinite : 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lựa chọn này sẽ giúp tối ưu hóa giao diện và tính năng cho cửa hàng của bạn.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),

              // Row chứa 2 lựa chọn
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildTypeCard(
                        context,
                        icon: Icons.restaurant_menu,
                        title: 'F&B (Ăn uống)',
                        value: 'fnb',
                        description: 'Cafe, Nhà hàng, Bi-a, Karaoke, Khách sạn,...',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTypeCard(
                        context,
                        icon: Icons.storefront,
                        title: 'Bán lẻ',
                        value: 'retail',
                        description: 'Tạp hóa, Minimart, Shop thời trang, Cửa hàng điện thoại,...',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              const Divider(),

              // Switch sử dụng dữ liệu mẫu
              SwitchListTile(
                value: _useSampleData,
                onChanged: _isUpdating ? null : (val) {
                  setState(() => _useSampleData = val);
                },
                title: const Text(
                  'Sử dụng dữ liệu mẫu',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Tự động tạo danh mục và hàng hóa mẫu để bạn trải nghiệm ngay.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                activeColor: Theme.of(context).primaryColor,
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: (_selectedType == null || _isUpdating)
              ? null
              : () {
            setState(() => _isUpdating = true);

            // 1. Đóng Popup NGAY LẬP TỨC
            Navigator.of(context).pop();

            // 2. Gửi dữ liệu về HomeScreen để xử lý sau
            widget.onConfirm(_selectedType!, _useSampleData);
          },
          child: _isUpdating
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Bắt đầu ngay'),
        ),
      ],
    );
  }

  Widget _buildTypeCard(BuildContext context,
      {required IconData icon,
        required String title,
        required String value,
        required String description}) {
    final bool isSelected = _selectedType == value;
    final color = Theme.of(context).primaryColor;

    return InkWell(
      onTap: _isUpdating ? null : () => setState(() => _selectedType = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(25) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: isSelected ? color : Colors.grey[600]),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isSelected ? color : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
