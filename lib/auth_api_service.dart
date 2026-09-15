import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// ผลลัพธ์การ login ที่ผ่านการยืนยันตัวตนจริงจากเซิร์ฟเวอร์ (Cloudflare Worker)
class LoginResult {
  final String role; // 'ADMIN' | 'CUSTOMER' | 'TECHNICIAN'
  final Map<String, dynamic> userData; // ข้อมูลผู้ใช้ (ไม่มี password)

  LoginResult({required this.role, required this.userData});
}

/// เข้าสู่ระบบผ่าน Cloudflare Worker แทนการตรวจ bcrypt ในแอปเอง
///
/// Worker เป็นคนตรวจรหัสผ่านจริง (ด้วยสิทธิ์ Admin ที่ bypass Firebase Rules ได้)
/// แล้วออก Firebase Custom Token ที่มี role ฝังอยู่ในนั้น ปลอมจากในแอปไม่ได้
/// เพราะ token เซ็นด้วยกุญแจของ Service Account ที่อยู่บนเซิร์ฟเวอร์เท่านั้น
///
/// ใช้ Worker endpoint เดียวกับที่ PushNotificationService ใช้อยู่แล้ว
/// (root URL, header Authorization: Bearer, แยกประเภทคำขอด้วยฟิลด์ 'type')
class AuthApiService {
  AuthApiService._();

  static const String _workerUrl =
      'https://aftersales-push-proxy.omenkungzaza121.workers.dev';
  static const String _appSecret = 'kATyjLNoUIs7ebkEHzX9NY24HWSH3dCf';

  /// [identifier] เป็นได้ทั้ง username หรือ email (ตรงกับ verifyLogin เดิม)
  /// คืนค่า null ถ้า username/password ไม่ถูกต้อง
  /// โยน Exception ถ้าเชื่อมต่อเซิร์ฟเวอร์ไม่ได้
  static Future<LoginResult?> login(String identifier, String password) async {
    final url = Uri.parse(_workerUrl);

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $_appSecret',
      },
      body: jsonEncode({
        'type': 'LOGIN',
        'identifier': identifier,
        'password': password,
      }),
    );

    if (response.statusCode == 401) return null;

    if (response.statusCode != 200) {
      throw Exception(
          'เข้าสู่ระบบไม่สำเร็จ (status ${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final customToken = data['customToken'] as String?;
    final role = data['role'] as String?;
    final userMap = data['user'];
    if (customToken == null || role == null || userMap is! Map) return null;

    // sign in เข้า Firebase Auth จริง ทำให้มี auth.uid + auth.token.role
    // ให้ Firebase Rules เอาไปใช้เช็คสิทธิ์ได้ (ปลอมจากแอปไม่ได้อีกต่อไป)
    await FirebaseAuth.instance.signInWithCustomToken(customToken);

    return LoginResult(role: role, userData: Map<String, dynamic>.from(userMap));
  }

  static Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }
}
