import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:after_sales/screens/first.dart';
import 'package:after_sales/screens/customer/home_customer.dart';
import 'package:after_sales/screens/technician/home_technician.dart';
import 'package:after_sales/screens/admin/home_admin.dart';
import 'package:after_sales/screens/customer/history_customer.dart';
import 'package:after_sales/screens/customer/profile_customer.dart';
import 'package:after_sales/screens/call_screen.dart';
import 'package:after_sales/webrtc_service.dart';
import 'package:after_sales/widgets.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/session_storage.dart';
import 'package:after_sales/app_styles.dart';
import 'package:flutter/services.dart';

StreamSubscription? _callSubscription;

void setupIncomingCallListener(String username) {
  _callSubscription?.cancel();
  if (username.isEmpty) return;

  _callSubscription = WebRtcService.listenIncomingCall(
    myUsername: username,
    onIncomingCall: (callData) {
      final context = navigatorKey.currentContext;
      if (context != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CallScreen.receiveCall(
              callId: callData['callId'] ?? '',
              callerUsername: callData['callerUsername'] ?? 'ไม่ระบุ',
              callerName: callData['callerName'] ?? 'สายเรียกเข้า',
              callerPhotoUrl: callData['callerPhotoUrl'],
            ),
          ),
        );
      }
    },
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint('Firebase init error: $e');
  }

  try {
    // ป้องกันการค้างจาก Security Rules
    await db.DatabaseHelper.instance.init().timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('DatabaseHelper init skipped/error: $e');
  }

  try {
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('PushNotification init error: $e');
  }

  Widget initialHome = const FirstPage();
  try {
    final saved = await SessionStorage.load();
    if (saved != null) {
      Map<String, dynamic>? savedUserData;
      if (saved.role.toUpperCase() == 'ADMIN') {
        savedUserData =
            await db.DatabaseHelper.instance.getAdminProfile(saved.username);
      }
      db.Session.signIn(saved.username, saved.role, userData: savedUserData);
      PushNotificationService.linkUser(saved.username);
      setupIncomingCallListener(saved.username);

      switch (saved.role) {
        case 'ADMIN':
          initialHome = const HomeAdmin();
          break;
        case 'TECHNICIAN':
          initialHome = const HomeTechnician();
          break;
        case 'CUSTOMER':
          initialHome = const HomeCustomer();
          break;
      }
    }
  } catch (e) {
    debugPrint('Session load error: $e');
  }

  runApp(MainApp(initialHome: initialHome));
}
class MainApp extends StatelessWidget {
  final Widget initialHome;

  const MainApp({super.key, this.initialHome = const FirstPage()});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // 🔴 [แก้ไข] ตั้งค่า locale เป็นไทย เพื่อให้ showDatePicker (ปฏิทินเลือกวันนัด)
      // แสดงชื่อเดือนภาษาไทยและปี พ.ศ. ให้ตรงกับรูปแบบวันที่ที่ใช้บันทึก/แสดงผลในแอป
      locale: const Locale('th', 'TH'),
      supportedLocales: const [
        Locale('th', 'TH'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Center(
          child: SizedBox(
            width: 390,
            height: 844,
            child: child,
          ),
        );
      },
      home: initialHome,
      routes: {
        '/home': (context) => const HomeCustomer(),
        '/history': (context) => const HistoryCustomer(),
        '/chat': (context) => const PlaceholderPage(
              title: 'ข้อความ',
              icon: Icons.chat_bubble_outline,
            ),
        '/notifications': (context) => const PlaceholderPage(
              title: 'แจ้งเตือน',
              icon: Icons.notifications_none,
            ),
        '/profile': (context) => const UserProfilePage(),
      },
    );
  }
}