/// โมเดลข้อมูลลูกค้าหนึ่งคน ([CustomerItem]) — ผูกกับตาราง `customers` จริง
class CustomerItem {
  final String username;
  final String fullName;
  final String company;
  final String phone;
  final String email;
  final String address;
  final String houseNo;
  final String moo;
  final String tambon;
  final String amphoe;
  final String changwat;
  final String postalCode;

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
  });

  factory CustomerItem.fromMap(Map<String, dynamic> map) {
    // ⭐ [แก้ไข] BEFORE: เดิม cast ค่า String จาก Database ตรง ๆ
    // final name = (map['name'] as String?) ?? '';
    // final surname = (map['surname'] as String?) ?? '';
    // final fullName = '$name $surname'.trim();
    // return CustomerItem(
    //   username: (map['username'] as String?) ?? '',
    //   fullName: fullName.isNotEmpty ? fullName : '-',
    //   company: (map['company'] as String?) ?? '-',
    //   phone: (map['phone'] as String?) ?? '-',
    //   email: (map['email'] as String?) ?? '-',
    //   address: (map['address'] as String?) ?? '-',
    //   houseNo: (map['house_no'] as String?) ?? '',
    //   moo: (map['moo'] as String?) ?? '',
    //   tambon: (map['tambon'] as String?) ?? '',
    //   amphoe: (map['amphoe'] as String?) ?? '',
    //   changwat: (map['changwat'] as String?) ?? '',
    //   postalCode: (map['postal_code'] as String?) ?? '',
    // );

    // ⭐ [แก้ไข] AFTER: แปลงค่าจาก Firebase ด้วย toString แบบ null-safe
    final name = map['name']?.toString() ?? '';
    final surname = map['surname']?.toString() ?? '';
    final fullName = '$name $surname'.trim();
    return CustomerItem(
      username: map['username']?.toString() ?? '',
      fullName: fullName.isNotEmpty ? fullName : '-',
      company: map['company']?.toString() ?? '-',
      phone: map['phone']?.toString() ?? '-',
      email: map['email']?.toString() ?? '-',
      address: map['address']?.toString() ?? '-',
      houseNo: map['house_no']?.toString() ?? '',
      moo: map['moo']?.toString() ?? '',
      tambon: map['tambon']?.toString() ?? '',
      amphoe: map['amphoe']?.toString() ?? '',
      changwat: map['changwat']?.toString() ?? '',
      postalCode: map['postal_code']?.toString() ?? '',
    );
  }

  String get formattedAddress {
    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (moo.isNotEmpty) 'หมู่ $moo',
      if (tambon.isNotEmpty) 'ตำบล$tambon',
      if (amphoe.isNotEmpty) 'อำเภอ$amphoe',
      if (changwat.isNotEmpty) 'จังหวัด$changwat',
      if (postalCode.isNotEmpty) postalCode,
    ];
    if (parts.isNotEmpty) return parts.join(' ');
    return address.isNotEmpty && address != '-' ? address : '-';
  }
}
