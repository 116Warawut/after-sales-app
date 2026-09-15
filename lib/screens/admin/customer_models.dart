/// โมเดลข้อมูลลูกค้าหนึ่งคน ([CustomerItem]) — ผูกกับตาราง `customers` จริง
/// แยกออกมาเป็นไฟล์ของตัวเอง เพื่อให้ manage_customer.dart และ
/// customer_edit_page.dart ใช้ร่วมกันได้โดยไม่เกิด circular import
class CustomerItem {
  final String username;
  final String fullName;
  final String company;
  final String phone;
  final String email;
  final String address;
  // ⭐ [แก้ไข] BEFORE: เดิม CustomerItem เก็บที่อยู่รวมไว้ใน address เท่านั้น
  // ทำให้หน้าจอที่ต้องอ่าน houseNo, moo, tambon, amphoe, changwat และ postalCode
  // เกิด error เพราะไม่มีฟิลด์เหล่านี้ในโมเดล
  //
  // final String address;

  // ⭐ [แก้ไข] เพิ่มฟิลด์ที่อยู่แบบแยกส่วนให้ตรงกับข้อมูลในตาราง customers
  // เดิม CustomerItem มีเฉพาะ address แต่หน้าจัดการลูกค้าและหน้าแก้ไขลูกค้า
  // อ่านข้อมูลจาก house_no, moo, tambon, amphoe, changwat และ postal_code
  final String houseNo;
  final String moo;
  final String tambon;
  final String amphoe;
  final String changwat;
  final String postalCode;

  // 🔴 [แก้บั๊ก] เพิ่มฟิลด์ photoUrl — เดิม CustomerItem ไม่มีฟิลด์นี้เลย ทำให้
  // แม้ตาราง customers ใน Firebase จะมี photo_url เก็บอยู่จริง (จากตอนลูกค้า
  // เปลี่ยนรูปโปรไฟล์ในหน้า profile_customer.dart) หน้า "จัดการลูกค้า" ของแอดมิน
  // ก็ไม่มีทางอ่านค่านี้ออกมาแสดงได้ เลยเห็นเป็นไอคอนคนเปล่า ๆ ตลอด
  final String photoUrl;

  const CustomerItem({
    required this.username,
    required this.fullName,
    required this.company,
    required this.phone,
    required this.email,
    required this.address,
    this.houseNo = '',
    this.moo = '',
    this.tambon = '',
    this.amphoe = '',
    this.changwat = '',
    this.postalCode = '',
    this.photoUrl = '',
  });

  factory CustomerItem.fromMap(Map<String, dynamic> map) {
    final name = (map['name'] as String?) ?? '';
    final surname = (map['surname'] as String?) ?? '';
    final fullName = '$name $surname'.trim();
    return CustomerItem(
      username: (map['username'] as String?) ?? '',
      fullName: fullName.isNotEmpty ? fullName : '-',
      company: (map['company'] as String?) ?? '-',
      phone: (map['phone'] as String?) ?? '-',
      email: (map['email'] as String?) ?? '-',
      address: (map['address'] as String?) ?? '-',
      houseNo: (map['house_no'] as String?) ?? '',
      moo: (map['moo'] as String?) ?? '',
      tambon: (map['tambon'] as String?) ?? '',
      amphoe: (map['amphoe'] as String?) ?? '',
      changwat: (map['changwat'] as String?) ?? '',
      postalCode: (map['postal_code'] as String?) ?? '',
      // 🔴 [แก้บั๊ก] อ่าน photo_url จากข้อมูลดิบมาเก็บด้วย (ดูเหตุผลด้านบน)
      photoUrl: (map['photo_url'] as String?) ?? '',
    );
  }
}
