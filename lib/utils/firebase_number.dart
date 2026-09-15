/// ==========================================
/// 🔢 แปลงค่าตัวเลขจาก Firebase แบบปลอดภัย
/// ==========================================
/// Firebase Realtime Database ไม่ได้บังคับชนิดข้อมูลอย่างเข้มงวด ทำให้ field
/// เดียวกัน (เช่น id, machine_id, stock, is_paid) อาจถูกเก็บเป็น int ในบาง
/// record แต่เป็น String ในอีก record หนึ่ง ขึ้นกับว่าหน้าไหน/โค้ดจุดไหนเป็น
/// คนเขียนค่านั้นเข้าไปตอนนั้น
///
/// การ cast ตรง ๆ ด้วย `as int?` หรือ `as double?` จะทำงานได้ก็ต่อเมื่อค่าจริง
/// เป็นชนิดนั้นเป๊ะ ๆ เท่านั้น ถ้าเจอ String (เช่น "18") จะโยน error ทันที:
/// "type 'String' is not a subtype of type 'int?'" — ซึ่งเป็นสาเหตุของ error
/// ที่เจอฝั่ง iOS เพราะบาง record ถูกบันทึกด้วยชนิดข้อมูลไม่ตรงกัน
///
/// ให้ทุกหน้าที่อ่านค่าตัวเลขจาก Firebase ใช้ฟังก์ชันในไฟล์นี้แทนการ cast ตรง ๆ
library;

/// แปลงค่า dynamic จาก Firebase ให้เป็น int แบบปลอดภัย
/// รองรับทั้งกรณีที่ค่าเป็น int, num (double), String (เช่น "18") หรือ null
int? toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// เหมือน [toIntOrNull] แต่คืนค่า [fallback] แทน null เมื่อแปลงไม่ได้
int toIntOr(dynamic v, int fallback) => toIntOrNull(v) ?? fallback;

/// แปลงค่า dynamic จาก Firebase ให้เป็น double แบบปลอดภัย
/// รองรับทั้งกรณีที่ค่าเป็น double, num (int), String (เช่น "18.5") หรือ null
double? toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// เหมือน [toDoubleOrNull] แต่คืนค่า [fallback] แทน null เมื่อแปลงไม่ได้
double toDoubleOr(dynamic v, double fallback) => toDoubleOrNull(v) ?? fallback;

/// แปลงค่า dynamic จาก Firebase ให้เป็น String แบบปลอดภัย
/// กันเคสที่ field ที่ปกติเป็น String (เช่น ticketNo, status, เบอร์โทร) ถูกเก็บ
/// เป็น int/num มาจากบาง record แล้วโดน `as String?` โยน error เช่นกัน
String? toStringOrNull(dynamic v) => v?.toString();