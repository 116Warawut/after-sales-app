/// ==========================================
/// 🔢 หมายเลข Serial Number ของเครื่องจักร
/// ==========================================
/// รวม logic การตรวจสอบ/ดึงหมายเลข Serial Number ไว้ที่เดียว เพื่อให้ทั้งฝั่ง
/// ฟอร์มกรอกเอง, หน้าสแกน QR Code, และชั้นฐานข้อมูล (services.dart) ใช้กฎเดียวกัน
///
/// โครงสร้าง 2-2-4 (รวม 8 ตัวอักษร): [รหัสรุ่น 2 ตัวอักษร][ปี ค.ศ. 2 หลัก]
/// [ลำดับ 4 หลัก] เช่น "PM260145" = รุ่น PM / ผลิตปี 2026 / เครื่องที่ 145
///
/// - รหัสรุ่น 2 ตัวแรก: ตัวอักษร A-Z อิสระ 2 ตัว (ไม่ตรวจว่ามีอยู่ในระบบจริง)
/// - เลขลำดับ 4 หลักท้าย: ให้ผู้ใช้กรอก/สแกนเองเหมือนเดิม ระบบแค่บังคับรูปแบบ
///   (ไม่ได้รันเลขอัตโนมัติ)
library;

/// จำนวนตัวอักษรของรหัสรุ่น (ส่วนแรก)
const int kModelCodeLength = 2;

/// จำนวนหลักของปี ค.ศ. แบบย่อ (ส่วนที่สอง)
const int kYearCodeLength = 2;

/// จำนวนหลักของเลขลำดับ (ส่วนที่สาม)
const int kSequenceLength = 4;

/// จำนวนตัวอักษรทั้งหมดของหมายเลข Serial Number (2 + 2 + 4 = 8)
const int kSerialNumberLength =
    kModelCodeLength + kYearCodeLength + kSequenceLength;

/// ข้อความแจ้งเตือนมาตรฐานเมื่อรูปแบบ Serial Number ไม่ถูกต้อง
const String serialNumberFormatError =
    'หมายเลข Serial Number ต้องมี $kSerialNumberLength ตัวอักษร รูปแบบ '
    '[ตัวอักษร $kModelCodeLength ตัว][ปี ค.ศ. $kYearCodeLength หลัก]'
    '[ลำดับ $kSequenceLength หลัก] เช่น PM260145';

// [ตัวอักษร A-Z x2][ตัวเลข x2][ตัวเลข x4] — ตรวจแบบไม่สนตัวพิมพ์เล็ก/ใหญ่
// (ค่าที่ผ่านการ normalize ด้วย normalizeSerialNumber แล้วจะเป็นตัวพิมพ์ใหญ่เสมอ)
final RegExp _exactSerialPattern = RegExp(r'^[A-Z]{2}\d{2}\d{4}$');
final RegExp _embeddedSerialPattern = RegExp(r'[A-Za-z]{2}\d{2}\d{4}');

/// แปลงค่าให้เป็นรูปแบบมาตรฐานก่อนตรวจ/บันทึก/เทียบซ้ำ — ตัดช่องว่างหัวท้าย
/// และแปลงตัวอักษรเป็นตัวพิมพ์ใหญ่ทั้งหมด (กัน "pm260145" กับ "PM260145" ถูกมองว่าต่างกัน)
String normalizeSerialNumber(String value) => value.trim().toUpperCase();

/// ตรวจสอบว่าค่าที่ได้ (จากการกรอกเองหรือสแกน) เป็นหมายเลข Serial Number
/// ที่ถูกต้องตามโครงสร้าง 2-2-4 หรือไม่
bool isValidSerialNumber(String value) =>
    _exactSerialPattern.hasMatch(normalizeSerialNumber(value));

/// พยายาม "แยก" หมายเลข Serial Number ออกจากข้อความดิบที่อ่านได้จาก QR Code
///
/// รองรับทั้งกรณี QR Code เก็บแค่รหัส 8 ตัวอักษรตรง ๆ และกรณีฝังเลข Serial
/// อยู่ในข้อความ/ลิงก์อื่น เช่น "SN:PM260145" หรือ
/// "https://example.com/machine/PM260145" — จะดึงรูปแบบ 2-2-4 แรกที่เจอ
/// แล้วแปลงเป็นตัวพิมพ์ใหญ่ให้อัตโนมัติ
///
/// คืนค่า null ถ้าในข้อความไม่มีรูปแบบ 2-2-4 อยู่เลย (แปลว่า QR Code นี้
/// ไม่ใช่ QR ของหมายเลข Serial Number ให้ผู้ใช้ลองสแกนอันอื่น/พิมพ์เอง)
String? extractSerialNumberFromQr(String rawValue) {
  final trimmed = rawValue.trim();
  if (trimmed.isEmpty) return null;

  final normalized = normalizeSerialNumber(trimmed);
  if (_exactSerialPattern.hasMatch(normalized)) return normalized;

  final match = _embeddedSerialPattern.firstMatch(trimmed);
  if (match == null) return null;
  return normalizeSerialNumber(match.group(0)!);
}
