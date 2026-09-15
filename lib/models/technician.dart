import 'package:after_sales/app_styles.dart';
import 'package:after_sales/utils/firebase_number.dart';
import 'package:flutter/material.dart';

class Technician {
  final int? id;
  final String name;
  final String username;
  final String code;
  final String role;
  final int isBusy;
  final String initials;
  final Color avatarColor;

  // 🌟 กำหนดค่าเริ่มต้น (='') เพื่อแก้ปัญหา Null Safety (tech.name error)
  Technician({
    this.id,
    this.name = '',
    this.username = '',
    this.code = '',
    this.role = '',
    this.isBusy = 0,
    this.initials = '',
    this.avatarColor = Colors.grey,
  });

  /// สร้าง Technician จากข้อมูลตาราง `technicians` ใน services.dart
  /// (คอลัมน์จริง: id, tech_name, role_label, employee_id, vehicle,
  ///  company, address, phone, username, password, current_lat, current_lng, photo_url)
  ///
  /// หมายเหตุ: ตาราง technicians ไม่มีคอลัมน์เก็บสถานะ "ว่าง/ไม่ว่าง" โดยตรง
  /// ให้คำนวณจากภายนอก (เช่น เช็คจากตาราง repairs ว่ามีงานค้างอยู่หรือไม่)
  /// แล้วส่งเข้ามาทาง [isBusyOverride]
  factory Technician.fromMap(
    Map<String, dynamic> map,
    int index, {
    bool isBusyOverride = false,
  }) {
    // ✅ อ่านชื่อจากคอลัมน์จริง 'tech_name' (สำรอง 'name' ไว้เผื่อ mock data)
    final nameStr = map['tech_name']?.toString() ??
        map['name']?.toString() ??
        'ไม่ระบุชื่อ';

    final roleStr = map['role_label']?.toString() ??
        map['role']?.toString() ??
        'ช่างทั่วไป';

    // ⭐ [แก้ไข] BEFORE: เดิม cast is_busy เป็น int ตรง ๆ ซึ่งอาจ throw
    // หาก Firebase ส่งค่าเป็น double หรือ String
    // final isBusyValue = isBusyOverride ? 1 : (map['is_busy'] as int? ?? 0);

    // ⭐ [แก้ไข] AFTER 2: เปลี่ยนไปใช้ toIntOrNull (lib/utils/firebase_number.dart)
    // แทน `as num?` ตรง ๆ เพราะ 'is_busy' บาง record อาจเก็บมาเป็น String ก็ได้
    final isBusyValue = isBusyOverride ? 1 : (toIntOrNull(map['is_busy']) ?? 0);

    String roleFormatted;
    if (roleStr.contains('แอร์')) {
      roleFormatted = 'ช่างแอร์';
    } else if (roleStr.contains('ไฟฟ้า')) {
      roleFormatted = 'ช่างไฟฟ้า';
    } else if (roleStr != 'ช่างทั่วไป') {
      // ถ้ามี role_label เฉพาะทางอื่นอยู่แล้ว (เช่น "ช่างเครื่องปริ้น") ให้ใช้ตามจริง
      roleFormatted = roleStr;
    } else {
      roleFormatted = index % 2 == 0 ? 'ช่างแอร์' : 'ช่างไฟฟ้า';
    }

    // ✅ อ่านรหัสพนักงานจากคอลัมน์จริง 'employee_id' (สำรอง 'code' ไว้เผื่อ mock data)
    final codeStr = map['employee_id']?.toString() ?? map['code']?.toString();

    return Technician(
      id: toIntOrNull(map['id']),
      username: map['username']?.toString() ?? 'unknown_$index',
      name: nameStr,
      code: (codeStr != null && codeStr.isNotEmpty)
          ? 'รหัส: $codeStr'
          : 'รหัส: ${3661051541100 + (toIntOrNull(map['id']) ?? index)}',
      role: roleFormatted,
      isBusy: isBusyValue,
      initials: generateInitials(nameStr),
      avatarColor:
          isBusyValue == 1 ? AppColors.textHint : generateAvatarColor(index),
    );
  }

  bool get isAvailable => isBusy == 0;
  bool get busy => isBusy == 1;

  static String generateInitials(String name) {
    final cleanName =
        name.replaceAll(RegExp(r'^(นาย|นาง|นางสาว|ช่าง)\s*'), '').trim();
    final parts = cleanName.split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}';
    } else if (parts.isNotEmpty && parts[0].length >= 2) {
      return parts[0].substring(0, 2);
    }
    return 'ชก';
  }

  static Color generateAvatarColor(int index) {
    const palette = [
      AppColors.yellowText,
      AppColors.accentTeal,
      AppColors.greenText,
      AppColors.accentPurple,
      AppColors.primary,
    ];
    return palette[index % palette.length];
  }
}
