import 'package:shared_preferences/shared_preferences.dart';

class SessionStorage {
  SessionStorage._();

  static const String _keyUsername = 'saved_username';
  static const String _keyRole = 'saved_role';

  // บันทึกผู้ใช้ที่เพิ่งล็อกอินสำเร็จไว้ในเครื่อง — เรียกทันทีหลังล็อกอินผ่าน
  static Future<void> save(String username, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyRole, role);
  }

  // ดึงข้อมูลผู้ใช้ที่เคยบันทึกไว้ — เรียกตอนเปิดแอปเพื่อเช็กว่าเคยล็อกอินค้างไว้ไหม
  // คืนค่า null ถ้าไม่เคยล็อกอินไว้เลย หรือเคยออกจากระบบไปแล้ว
  static Future<({String username, String role})?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final username = prefs.getString(_keyUsername);
    final role = prefs.getString(_keyRole);
    if (username == null || username.isEmpty || role == null || role.isEmpty) {
      return null;
    }
    return (username: username, role: role);
  }

  // ลบข้อมูลที่บันทึกไว้ — เรียกตอนกดออกจากระบบ กันเครื่องนี้ auto-login เข้า
  // บัญชีเดิมอีกหลังจากที่ผู้ใช้ตั้งใจออกจากระบบไปแล้ว
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyRole);
  }
}
