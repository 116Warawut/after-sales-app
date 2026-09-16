import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

// 🔴 [ชั่วคราว-Debug] เก็บ error ที่เกิดตอน main() เริ่มทำงาน เพื่อโชว์บนหน้าจอจริง
// แทนที่จะเห็นแค่ใน debugPrint (มองไม่เห็นถ้าไม่ได้ต่อ Xcode/เครื่อง Mac)
// ลบตัวแปรนี้กับส่วนที่ใช้งานทิ้งได้เมื่อ debug เสร็จแล้ว
final List<String> _startupErrors = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp();
  } catch (e, st) {
    debugPrint('Firebase init error: $e');
    _startupErrors.add('Firebase.initializeApp() ล้มเหลว:\n$e\n\n$st');
  }

  try {
    // ป้องกันการค้างจาก Security Rules
    await db.DatabaseHelper.instance.init().timeout(const Duration(seconds: 4));
  } catch (e) {
    debugPrint('DatabaseHelper init skipped/error: $e');
    _startupErrors.add('DatabaseHelper.init() ล้มเหลว/timeout:\n$e');
  }

  try {
    await PushNotificationService.initialize();
  } catch (e) {
    debugPrint('PushNotification init error: $e');
    _startupErrors.add('PushNotificationService.initialize() ล้มเหลว:\n$e');
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
    _startupErrors.add('SessionStorage.load() ล้มเหลว:\n$e');
  }

  runApp(MainApp(
    initialHome: initialHome,
    startupErrors: List.unmodifiable(_startupErrors),
  ));
}
class MainApp extends StatelessWidget {
  final Widget initialHome;
  // 🔴 [ชั่วคราว-Debug] error ที่เกิดระหว่าง main() ไว้โชว์เป็นแบนเนอร์แดงบนหน้าจอ
  final List<String> startupErrors;

  const MainApp({
    super.key,
    this.initialHome = const FirstPage(),
    this.startupErrors = const [],
  });

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
        return GestureDetector(
          // 🔴 [แก้ไข] แตะพื้นที่ว่างตรงไหนก็ได้ในแอปเพื่อหุบคีย์บอร์ด (แก้ปัญหาบน iOS
          // ที่ไม่มีปุ่ม "เสร็จ"/"Done" เหนือคีย์บอร์ดเหมือน Android)
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final currentFocus = FocusScope.of(context);
            // ถ้ากำลังแตะอยู่บนช่องกรอกข้อมูล (TextField) เอง ช่องนั้นจะขอ focus
            // ไปแล้วก่อนโค้ดนี้ทำงาน ทำให้ hasPrimaryFocus เป็น true และจะไม่ถูกหุบ
            // แต่ถ้าแตะพื้นที่ว่าง จะไม่มีอะไรขอ focus จึงหุบคีย์บอร์ดได้ตามต้องการ
            if (!currentFocus.hasPrimaryFocus &&
                currentFocus.focusedChild != null) {
              currentFocus.focusedChild!.unfocus();
            }
          },
          // 🔴 [แก้ไข] เจอบั๊ก: เดิม child ถูกครอบด้วย SizedBox ขนาดตายตัว 390x844
          // (ขนาดจอ iPhone 12/13 mini) แล้ว Center ไว้กลางจอเสมอ ไม่ว่าอุปกรณ์จริง
          // จะมีขนาดเท่าไหร่ก็ตาม พอเจอเครื่อง iOS รุ่นที่จอสูงกว่า 844pt (เช่น
          // iPhone 14/15/16 ทั่วไปและรุ่น Pro/Pro Max ซึ่งเป็นรุ่นส่วนใหญ่ที่ขายอยู่
          // ตอนนี้) กล่องขนาดตายตัวจะเล็กกว่าจอจริง เกิดแถบดำ (Letterboxing) ทั้ง
          // ขอบบนและขอบล่างตามที่เจอ และทำให้ปุ่มย้อนกลับ/องค์ประกอบที่อิง
          // MediaQuery.padding.top (Safe Area จริงของอุปกรณ์) ไปอยู่ผิดตำแหน่ง
          // เพราะเนื้อหาถูกเลื่อนลงมาจากขอบจอจริงไปแล้วชั้นหนึ่งจาก Center ครอบอีกที
          //
          // ครอบด้วยกรอบขนาดตายตัวแบบนี้มีประโยชน์แค่ตอนรัน Flutter Web (ให้ดู
          // เหมือนพรีวิวแอปมือถือตอนเปิดในเบราว์เซอร์คอมพิวเตอร์) จึงจำกัดให้ทำงาน
          // เฉพาะ kIsWeb เท่านั้น ส่วนแอปมือถือจริง (iOS/Android) ให้ child เต็มจอ
          // ตามขนาดอุปกรณ์จริงเสมอ ไม่ล็อกเป็น 390x844 อีกต่อไป
          child: kIsWeb
              ? Center(
                  child: SizedBox(
                    width: 390,
                    height: 844,
                    child: child,
                  ),
                )
              : child,
        );
      },
      // 🔴 [ชั่วคราว-Debug] แสดง error ตอน startup เป็นแบนเนอร์สีแดงคลุมทับหน้าจอ
      // ไม่ต้องต่อ Xcode ก็เห็น error จริงบนเครื่อง ลบ builder ทับนี้ทิ้งได้เมื่อ debug เสร็จ
      home: startupErrors.isEmpty
          ? initialHome
          : _StartupErrorOverlay(
              errors: startupErrors,
              child: initialHome,
            ),
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

// 🔴 [ชั่วคราว-Debug] แบนเนอร์แสดง error ที่เกิดตอน startup (Firebase/DB/Push/Session)
// ครอบอยู่ด้านบนของหน้าแรก เลื่อนอ่านได้ ไม่บล็อกการใช้แอปด้านล่าง
// ---- ลบ Widget นี้ทั้งหมดทิ้งได้เมื่อ debug เสร็จแล้ว ----
class _StartupErrorOverlay extends StatelessWidget {
  final List<String> errors;
  final Widget child;

  const _StartupErrorOverlay({required this.errors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Material(
              color: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade800,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(color: Colors.black38, blurRadius: 6),
                  ],
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.warning_amber_rounded, color: Colors.white),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'พบ Error ตอนเปิดแอป (Startup)',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (int i = 0; i < errors.length; i++) ...[
                        SelectableText(
                          '${i + 1}. ${errors[i]}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                        ),
                        if (i != errors.length - 1)
                          const Divider(color: Colors.white24, height: 16),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}