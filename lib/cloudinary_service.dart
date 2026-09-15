// =============================================================================
// ☁️ Cloudinary Upload Service
// อัปโหลดรูปภาพขึ้น Cloudinary ผ่าน "unsigned upload preset" — ยิง multipart POST
// จากแอป Flutter ตรง ๆ ได้เลย ไม่ต้องมี backend เซิร์ฟเวอร์คั่นกลาง และไม่ต้องฝัง
// API secret ไว้ในแอป (ปลอดภัยกว่า signed upload)
//
// 🔧 ต้องตั้งค่า 2 ค่านี้ก่อนใช้งานจริง (ดูวิธีหาค่าด้านล่าง):
//   1. cloudName    — ชื่อบัญชี Cloudinary
//   2. uploadPreset — preset ที่สร้างไว้และตั้ง Signing Mode เป็น "Unsigned"
//
// วิธีหาค่า:
//   1. สมัคร/ล็อกอิน https://cloudinary.com (แผนฟรี ไม่ต้องผูกบัตร)
//   2. หน้า Dashboard มุมขวาบนจะโชว์ "Cloud name" — คัดลอกมาใส่ cloudName
//   3. ไปที่ Settings (ไอคอนเฟือง) > Upload > เลื่อนลงหา "Upload presets"
//      กด "Add upload preset" ตั้ง Signing Mode เป็น "Unsigned" แล้ว Save
//      ชื่อ preset ที่ตั้ง (หรือชื่อ auto-generate ให้) เอามาใส่ uploadPreset
//
// รูปทุกจุดในแอป (โปรไฟล์ / แนบฟอร์มแจ้งซ่อม / รูปในแชท / รูปเครื่องจักร / รูป
// รายงานผลของช่าง) เรียกใช้ฟังก์ชันเดียวกันนี้ทั้งหมด แก้ค่า 2 ตัวข้างล่างที่เดียว
// ก็ใช้ได้ทั้งแอป
// =============================================================================
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class CloudinaryService {
  CloudinaryService._();

  // 🔧 แก้ 2 ค่านี้ให้ตรงกับบัญชี Cloudinary ของโปรเจกต์คุณ
  static const String cloudName = 'tlc7uqvz';
  static const String uploadPreset = 'after-sales';

  static Uri get _uploadUri =>
      Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/image/upload');

  // ⚠️ เดิมเช็กด้วยการเทียบค่ากับข้อความ placeholder ตรง ๆ (เช่น
  // cloudName != 'YOUR_CLOUD_NAME') ซึ่งพอมีคนแก้ค่าจริงด้วยการ "แทนที่ทั้งไฟล์"
  // (find & replace) มันดันไปแก้ข้อความในเงื่อนไขนี้ด้วยโดยไม่ได้ตั้งใจ กลายเป็นเทียบ
  // ค่ากับตัวเอง (ผลลัพธ์เป็น false ตลอด ต่อให้ตั้งค่าไปแล้วก็ยังฟ้อง "ยังไม่ได้ตั้งค่า")
  // เปลี่ยนมาเช็กแค่ "ไม่ว่างเปล่า" แทน จะไม่มีทางพังซ้ำแบบนี้อีกไม่ว่าจะตั้งค่าเป็นอะไร
  static bool get isConfigured =>
      cloudName.trim().isNotEmpty && uploadPreset.trim().isNotEmpty;

  /// อัปโหลดรูปจาก [file] (ผลลัพธ์จาก image_picker) ขึ้น Cloudinary
  /// คืนค่าเป็น URL ของรูป (https://res.cloudinary.com/...) ที่ทุกเครื่องเปิดดูได้
  ///
  /// โยน [Exception] ออกมาถ้าอัปโหลดไม่สำเร็จ — ผู้เรียกควรครอบด้วย try/catch
  /// แล้วโชว์ error ให้ผู้ใช้เห็น (เน็ตหลุด / ยังไม่ได้ตั้งค่า cloudName ฯลฯ)
  static Future<String> uploadImage(XFile file) async {
    if (!isConfigured) {
      throw Exception(
        'ยังไม่ได้ตั้งค่า Cloudinary — แก้ cloudName/uploadPreset '
        'ใน lib/cloudinary_service.dart ก่อนใช้งาน',
      );
    }

    final bytes = await file.readAsBytes();

    final request = http.MultipartRequest('POST', _uploadUri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: file.name),
      );

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'อัปโหลดรูปไม่สำเร็จ (รหัส ${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final url = data['secure_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('ไม่พบ URL รูปในผลลัพธ์ที่ Cloudinary ส่งกลับมา');
    }
    return url;
  }

  /// อัปโหลดหลายรูปพร้อมกัน คืนค่าเป็นรายการ URL เรียงตามลำดับเดิม
  /// ถ้ารูปไหนอัปโหลดไม่สำเร็จ จะโยน Exception ทันที (ไม่ส่งเฉพาะรูปที่สำเร็จบางส่วน
  /// กันข้อมูลไม่ครบ เช่นแนบรูป 6 รูปแต่ได้ URL แค่ 4 รูป)
  static Future<List<String>> uploadImages(List<XFile> files) async {
    final urls = <String>[];
    for (final file in files) {
      urls.add(await uploadImage(file));
    }
    return urls;
  }
}
