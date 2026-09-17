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
    final name = (map['name']?.toString()) ?? '';
    final surname = (map['surname']?.toString()) ?? '';
    final fullName = '$name $surname'.trim();
    return CustomerItem(
      username: (map['username']?.toString()) ?? '',
      fullName: fullName.isNotEmpty ? fullName : '-',
      company: (map['company']?.toString()) ?? '-',
      phone: (map['phone']?.toString()) ?? '-',
      email: (map['email']?.toString()) ?? '-',
      address: (map['address']?.toString()) ?? '-',
      houseNo: (map['house_no']?.toString()) ?? '',
      moo: (map['moo']?.toString()) ?? '',
      tambon: (map['tambon']?.toString()) ?? '',
      amphoe: (map['amphoe']?.toString()) ?? '',
      changwat: (map['changwat']?.toString()) ?? '',
      postalCode: (map['postal_code']?.toString()) ?? '',
      // 🔴 [แก้บั๊ก] อ่าน photo_url จากข้อมูลดิบมาเก็บด้วย (ดูเหตุผลด้านบน)
      photoUrl: (map['photo_url']?.toString()) ?? '',
    );
  }
}
