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

final PrintingService globalPrintingService =
PrintingService(tableName: '', userName: '');

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  }

  await initializeDateFormatting('vi_VN', null);
  runApp(const MyApp());
}

Future<void> startPrintServerForUser(UserModel user) async {
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