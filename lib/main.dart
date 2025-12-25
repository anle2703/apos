// lib/main.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_pos_printer_platform_image_3_sdt/flutter_pos_printer_platform_image_3_sdt.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'models/user_model.dart';
import 'services/printing_service.dart';
import 'services/cloud_print_service.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'theme/app_theme.dart';
import 'widgets/toast_manager.dart';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

final PrintingService globalPrintingService =
PrintingService(tableName: '', userName: '');

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> _createNotificationChannel() async {
  if (!kIsWeb && Platform.isAndroid) {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel_v4', // ID Kênh V4
      'Thông báo thanh toán', // Tên hiển thị trong Cài đặt
      description: 'Thông báo khi có đơn hàng mới',
      importance: Importance.max, // Bắt buộc Max để có popup
      playSound: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }
}

void main() async {
  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // [SỬA LỖI 1]: Thêm kiểm tra Platform cho Crashlytics
    // Windows không phải Web, nên nếu chỉ check !kIsWeb thì Windows vẫn lọt vào đây
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
    }

    // [SỬA LỖI 2]: FirebaseMessaging cũng chưa hỗ trợ Windows, cần bọc lại
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      await _createNotificationChannel();
    }

    // Phần App Check này bạn ĐÃ LÀM ĐÚNG, giữ nguyên
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await FirebaseAppCheck.instance.activate(
        androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
        appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
      );
    }

    await initializeDateFormatting('vi_VN', null);

    runApp(const MyApp());
  }, (error, stack) {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    } else {
      debugPrint(">>> Error: $error");
      debugPrint(">>> Stack: $stack");
    }
  });
}

Future<void> startPrintServerForUser(UserModel user) async {
  if (kIsWeb && user.role == 'guest') return;
  try {
    final prefs = await SharedPreferences.getInstance();
    final bool isServerMode = prefs.getBool('is_print_server') ?? false;

    if (!isServerMode) {
      return;
    }

    if (user.storeId.isNotEmpty) {
      final serverListenMode = user.serverListenMode ?? 'server';
      debugPrint(">>> OK! Bắt đầu lắng nghe lệnh in cho store [${user.storeId}] ở chế độ '$serverListenMode'");
      await CloudPrintService().startListener(user.storeId, serverListenMode);
    } else {
      debugPrint(">>> LỖI: Người dùng không có storeId. Không thể bắt đầu listener.");
    }
  } catch (e) {
    debugPrint(">>> LỖI KHÔNG MONG MUỐN KHI KHỞI ĐỘNG SERVER IN: $e");
  }
}

Future<void> stopPrintServer() async {
  debugPrint(">>> Lệnh đăng xuất/thoát: Dừng listener in.");
  await CloudPrintService().stopListener();
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    debugPrint(">>> MyApp disposing: Dừng tất cả dịch vụ.");
    globalPrintingService.disconnectPrinter(PrinterType.network);
    globalPrintingService.disconnectPrinter(PrinterType.bluetooth);
    globalPrintingService.disconnectPrinter(PrinterType.usb);
    stopPrintServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Phần mềm bán hàng APOS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('vi', ''),
        Locale('en', ''),
      ],
      locale: const Locale('vi'),
      builder: (context, child) =>
          ToastManager(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}