// =============================================================================
// 💾 Session Storage — จำผู้ใช้ที่ล็อกอินไว้ในเครื่อง ข้ามการปิด-เปิดแอป
// =============================================================================
// เดิมตัวแปร Session (ใน services.dart) เก็บข้อมูลผู้ใช้ไว้แค่ใน "หน่วยความจำ"
// เท่านั้น พอปิดแอป (process ถูกเคลียร์) ข้อมูลนี้หายไปหมด เปิดแอปใหม่ทีไรต้อง
// ล็อกอินใหม่ทุกครั้ง
//
// ไฟล์นี้เพิ่มการจำ "ใครล็อกอินอยู่" ไว้ในเครื่องจริง ๆ ผ่าน SharedPreferences
// (พื้นที่เก็บข้อมูลเล็ก ๆ ที่ยังอยู่แม้ปิดแอปไปแล้ว) ทำให้:
//   1. เปิดแอปมาแล้วเข้าหน้าแรกของ role นั้นได้เลย ไม่ต้องพิมพ์รหัสผ่านซ้ำทุกครั้ง
//   2. เครื่องยังคง "ผูกอยู่กับผู้ใช้คนเดิม" ตลอด (สำคัญกับ push notification —
//      OneSignal จะได้รู้ว่าเครื่องนี้เป็นของใคร ส่งแจ้งเตือนมาได้ต่อเนื่อง ไม่ขาดตอน
//      ตอนที่แอปถูกปิดไปแล้วเปิดใหม่)
//
// 🔧 ต้องเพิ่ม dependency ใน pubspec.yaml ก่อนใช้งาน:
//   shared_preferences: ^2.3.2
// =============================================================================
import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  SessionStorage._();

  static const String _keyUsername = 'saved_username';
  static const String _keyRole = 'saved_role';

  /// บันทึกผู้ใช้ที่เพิ่งล็อกอินสำเร็จไว้ในเครื่อง — เรียกทันทีหลังล็อกอินผ่าน
  static Future<void> save(String username, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyRole, role);
  }

  /// ดึงข้อมูลผู้ใช้ที่เคยบันทึกไว้ — เรียกตอนเปิดแอปเพื่อเช็กว่าเคยล็อกอินค้างไว้ไหม
  /// คืนค่า null ถ้าไม่เคยล็อกอินไว้เลย หรือเคยออกจากระบบไปแล้ว
  static Future<({String username, String role})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_keyUsername);
    final role = prefs.getString(_keyRole);
    if (username == null || username.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return (username: username, role: role);
  }

  /// ลบข้อมูลที่บันทึกไว้ — เรียกตอนกดออกจากระบบ กันเครื่องนี้ auto-login เข้า
  /// บัญชีเดิมอีกหลังจากที่ผู้ใช้ตั้งใจออกจากระบบไปแล้ว
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyRole);
  }
}
