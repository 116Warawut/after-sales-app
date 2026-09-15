import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/call_screen.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/webrtc_service.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class PushNotificationService {
  PushNotificationService._();

  static const String appId = '86c13e32-650f-4a2b-9188-6f764ba8994b';
  static const String _workerUrl =
      'https://aftersales-push-proxy.omenkungzaza121.workers.dev';
  static const String _appSecret = 'kATyjLNoUIs7ebkEHzX9NY24HWSH3dCf';

  static bool get isConfigured => _appSecret.trim().isNotEmpty;

  static Future<void> initialize() async {
    OneSignal.initialize(appId);
    await OneSignal.Notifications.requestPermission(true);

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      final data = event.notification.additionalData;
      if (data != null && data['type'] == 'INCOMING_CALL') {
        event.preventDefault();
      }
    });

    // 🚀 ดักจับการกดแจ้งเตือนจากแถบ Notification ด้านบน (นอกแอป)
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      if (data == null) return;

      final type = data['type']?.toString().toUpperCase();

      if (type == 'INCOMING_CALL') {
        final actionId = event.result.actionId;
        final callId = data['callId']?.toString() ?? '';

        if (actionId == 'decline') {
          if (callId.isNotEmpty) {
            WebRtcService().rejectCall(callId);
          }
        } else {
          _navigateToCallScreen(data);
        }
      } else if (type == 'CHAT') {
        // เมื่อกดแจ้งเตือนแชท เปิดเข้า ChatScreen ของงานนั้นทันที
        final repairId = data['target_id']?.toString() ??
            data['repair_id']?.toString() ??
            '';
        if (repairId.isNotEmpty) {
          _navigateToChatScreen(repairId);
        }
      }
    });
  }

  static void _navigateToCallScreen(Map<String, dynamic> data) {
    final context = navigatorKey.currentContext;
    if (context == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen.receiveCall(
          callId: data['callId']?.toString() ?? '',
          callerUsername: data['callerUsername']?.toString() ?? '',
          callerName: data['callerName']?.toString() ?? 'สายเรียกเข้า',
          callerPhotoUrl: data['callerPhotoUrl']?.toString(),
        ),
      ),
    );
  }

  static void _navigateToChatScreen(String repairId) {
    if (repairId.isEmpty) return;

    void performNavigation() {
      final context = navigatorKey.currentContext;
      if (context == null) return;

      UserRole role = UserRole.customer;
      if (db.Session.currentRole == 'TECHNICIAN') {
        role = UserRole.technician;
      } else if (db.Session.currentRole == 'ADMIN') {
        role = UserRole.admin;
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            role: role,
            repairId: repairId,
          ),
        ),
      );
    }

    // รองรับทั้งเปิดแอปอยู่แล้วและ Cold Start หลังคลิกแจ้งเตือน
    if (navigatorKey.currentContext != null) {
      performNavigation();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 300), performNavigation);
      });
    }
  }

  static Future<void> linkUser(String username) async {
    if (username.isEmpty) return;
    try {
      await OneSignal.login(username);
    } catch (e) {
      debugPrint('PushNotificationService.linkUser error: $e');
    }
  }

  static Future<void> unlinkUser() async {
    try {
      await OneSignal.logout();
    } catch (e) {
      debugPrint('PushNotificationService.unlinkUser error: $e');
    }
  }

  /// ส่ง Email OTP ผ่าน Cloudflare Worker -> SendGrid
  static Future<bool> sendEmailOtp({
    required String email,
    required String otp,
    String purpose = 'RESET_PASSWORD',
  }) async {
    if (!isConfigured) return false;

    try {
      final url = Uri.parse(_workerUrl);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_appSecret',
        },
        body: jsonEncode({
          'type': 'EMAIL_OTP',
          'email': email,
          'otp': otp,
          'purpose': purpose,
        }),
      );

      debugPrint('Email OTP status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 202;
    } catch (e) {
      debugPrint('PushNotificationService.sendEmailOtp error: $e');
      return false;
    }
  }

  /// ส่งอีเมลแจ้งเตือนไปยัง "อีเมลเดิม" หลังเปลี่ยนอีเมลของบัญชีสำเร็จ
  static Future<bool> sendEmailChangeNotice({
    required String oldEmail,
    required String newEmail,
  }) async {
    if (!isConfigured) return false;

    try {
      final url = Uri.parse(_workerUrl);
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_appSecret',
        },
        body: jsonEncode({
          'type': 'EMAIL_CHANGE_NOTICE',
          'oldEmail': oldEmail,
          'newEmail': newEmail,
        }),
      );

      debugPrint('Email change notice status: ${response.statusCode}, body: ${response.body}');
      return response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 202;
    } catch (e) {
      debugPrint('PushNotificationService.sendEmailChangeNotice error: $e');
      return false;
    }
  }

  /// ส่ง Push Notification พร้อมตั้งค่า Priority และ Channel ให้ Pop-up
  static Future<void> sendToUser({
    required String username,
    required String title,
    required String message,
    Map<String, dynamic>? additionalData,
    String? collapseId,
  }) async {
    if (!isConfigured) return;

    try {
      final isCall = additionalData?['type'] == 'INCOMING_CALL';
      final url = Uri.parse(_workerUrl);

      final Map<String, dynamic> bodyData = {
        'app_id': appId,
        'include_aliases': {
          'external_id': [username],
        },
        'target_channel': 'push',
        'headings': {'en': title, 'th': title},
        'contents': {'en': message, 'th': message},
        'priority': 10,
        'android_visibility': 1,
        'android_sound': 'default',
        'android_accent_color': 'FFD8232A',
        if (collapseId != null) 'collapse_id': collapseId,
        if (collapseId != null) 'android_group': collapseId,
        if (additionalData != null) 'data': additionalData,
      };

      if (isCall) {
        bodyData['buttons'] = [
          {'id': 'accept', 'text': 'รับสาย'},
          {'id': 'decline', 'text': 'ปฏิเสธ'},
        ];
      }

      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': 'Bearer $_appSecret',
        },
        body: jsonEncode(bodyData),
      );

      debugPrint('Worker Push status: ${response.statusCode}, body: ${response.body}');
    } catch (e) {
      debugPrint('PushNotificationService.sendToUser error: $e');
    }
  }
}