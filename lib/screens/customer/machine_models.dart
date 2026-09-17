import 'package:flutter/foundation.dart';

/// สถานะประกันของเครื่องจักร คำนวณสดจาก [Machine.warrantyStartDate] +
/// [Machine.warrantyMonths] ทุกครั้งที่เรียกใช้ (ไม่มีวันข้อมูลค้าง)
enum WarrantyState {
  none, // ไม่มีข้อมูลประกัน (แอดมินยังไม่ได้กรอก)
  active, // อยู่ในประกัน เหลือมากกว่า 30 วัน
  expiringSoon, // อยู่ในประกัน แต่เหลือ ≤30 วัน
  expired, // หมดประกันแล้ว
}

/// จำนวนวันที่ถือว่า "ใกล้หมดประกัน" (ใช้เตือนแอดมินให้ติดต่อลูกค้าล่วงหน้า)
const int kWarrantyExpiringSoonDays = 30;

/// Shared data model สำหรับข้อมูลเครื่องจักร
/// เชื่อมต่อกับฐานข้อมูล SQLite ผ่าน DatabaseHelper / services.dart
@immutable
class Machine {
  final int? id;
  final String label; // e.g. 'A', 'B', 'C' — ป้ายชื่อย่อ
  final String serialNumber;
  final String modelName;
  final String photoUrl; // path รูปภาพเครื่องจักร (local file path หรือ URL)

  // 🔴 [แก้ไข] เดิมเก็บ warrantyActive/warrantyStatusText/warrantyExpiryText เป็น
  // ข้อความตายตัวที่แอดมินต้องพิมพ์เอง เสี่ยงข้อมูลค้างไม่ตรงความจริง เปลี่ยนเป็นเก็บแค่
  // "วันที่เริ่มประกัน" + "ระยะเวลากี่เดือน" แล้วคำนวณสถานะ/ข้อความสดด้านล่างแทน
  final DateTime? warrantyStartDate;
  final int? warrantyMonths;

  final Address address;

  const Machine({
    this.id,
    required this.label,
    required this.serialNumber,
    required this.modelName,
    this.photoUrl = '',
    this.warrantyStartDate,
    this.warrantyMonths,
    required this.address,
  });

  /// วันหมดอายุประกัน (คำนวณจากวันเริ่ม + จำนวนเดือน) — null ถ้าไม่มีข้อมูลประกัน
  DateTime? get warrantyEndDate {
    final start = warrantyStartDate;
    final months = warrantyMonths;
    if (start == null || months == null || months <= 0) return null;

    final totalMonths = start.month + months;
    final endYear = start.year + (totalMonths - 1) ~/ 12;
    final endMonth = (totalMonths - 1) % 12 + 1;
    // กันวันที่ไม่มีจริงในเดือนปลายทาง (เช่น 31 ม.ค. + 1 เดือน จะไม่มี 31 ก.พ.)
    final daysInEndMonth = DateTime(endYear, endMonth + 1, 0).day;
    final endDay = start.day > daysInEndMonth ? daysInEndMonth : start.day;
    return DateTime(endYear, endMonth, endDay);
  }

  /// จำนวนวันที่เหลือก่อนหมดประกัน (ติดลบ = หมดไปแล้วกี่วัน) — null ถ้าไม่มีข้อมูลประกัน
  int? get warrantyDaysRemaining {
    final end = warrantyEndDate;
    if (end == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return endDay.difference(today).inDays;
  }

  WarrantyState get warrantyState {
    final daysLeft = warrantyDaysRemaining;
    if (daysLeft == null) return WarrantyState.none;
    if (daysLeft < 0) return WarrantyState.expired;
    if (daysLeft <= kWarrantyExpiringSoonDays) return WarrantyState.expiringSoon;
    return WarrantyState.active;
  }

  /// true = ยังอยู่ในระยะประกัน (รวมช่วงใกล้หมดอายุ), false = หมดแล้วหรือไม่มีข้อมูล
  bool get warrantyActive =>
      warrantyState == WarrantyState.active ||
      warrantyState == WarrantyState.expiringSoon;

  /// ข้อความสั้นสำหรับแสดงในรายการ (การ์ดลิสต์เครื่องจักร)
  String get warrantyStatusText {
    switch (warrantyState) {
      case WarrantyState.none:
        return 'ไม่มีข้อมูลประกัน';
      case WarrantyState.expired:
        final days = -warrantyDaysRemaining!;
        return 'ประกันหมดอายุแล้ว ($days วันก่อน)';
      case WarrantyState.expiringSoon:
        return 'ประกันใกล้หมดอายุ (เหลือ $warrantyDaysRemaining วัน)';
      case WarrantyState.active:
        final days = warrantyDaysRemaining!;
        final months = days ~/ 30;
        return months > 0
            ? 'ประกัน: เหลือประมาณ $months เดือน'
            : 'ประกัน: เหลือ $days วัน';
    }
  }

  /// ข้อความละเอียดสำหรับหน้ารายละเอียด (วันหมดอายุจริง)
  String get warrantyExpiryText {
    final end = warrantyEndDate;
    if (end == null) return 'ไม่มีข้อมูลวันหมดประกัน';
    final formatted = _formatThaiDate(end);
    return warrantyState == WarrantyState.expired
        ? 'หมดประกันไปแล้วเมื่อ $formatted'
        : 'หมดประกันวันที่ $formatted';
  }

  static const _thaiMonths = [
    '',
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];

  static String _formatThaiDate(DateTime d) {
    final buddhistYear = d.year + 543;
    return '${d.day} ${_thaiMonths[d.month]} $buddhistYear';
  }

  /// แปลงจาก row ของตาราง `machines` ใน SQLite (Map<String, dynamic>)
  factory Machine.fromMap(Map<String, dynamic> map) {
    DateTime? parsedStart;
    final rawStart = map['warranty_start_date'];
    if (rawStart is String && rawStart.isNotEmpty) {
      parsedStart = DateTime.tryParse(rawStart);
    }

    int? parsedMonths;
    final rawMonths = map['warranty_months'];
    if (rawMonths is int) {
      parsedMonths = rawMonths;
    } else if (rawMonths != null) {
      parsedMonths = int.tryParse(rawMonths.toString());
    }

    return Machine(
      id: map['id'] is int
          ? map['id'] as int
          : int.tryParse(map['id']?.toString() ?? ''),
      label: (map['label']?.toString())?.trim().isNotEmpty == true
          ? (map['label'].toString()).trim()
          : '-',
      serialNumber: (map['serial_number']?.toString())?.trim().isNotEmpty == true
          ? (map['serial_number'].toString()).trim()
          : '-',
      modelName: (map['model_name']?.toString())?.trim().isNotEmpty == true
          ? (map['model_name'].toString()).trim()
          : '-',
      photoUrl: (map['photo_url']?.toString())?.trim() ?? '',
      warrantyStartDate: parsedStart,
      warrantyMonths: parsedMonths,
      address: Address.fromMap(map),
    );
  }

  /// แปลงกลับเป็น Map สำหรับ insert/update กับตาราง `machines` ใน SQLite
  Map<String, dynamic> toMap({String? customerUsername}) {
    return {
      if (id != null) 'id': id,
      if (customerUsername != null) 'customer_username': customerUsername,
      'label': label,
      'serial_number': serialNumber,
      'model_name': modelName,
      'photo_url': photoUrl,
      'warranty_start_date': warrantyStartDate?.toIso8601String(),
      'warranty_months': warrantyMonths,
      ...address.toMap(),
    };
  }

  /// คัดลอก Object และแก้ไขบางค่า (มีประโยชน์มากเมื่อทำ State Management)
  Machine copyWith({
    int? id,
    String? label,
    String? serialNumber,
    String? modelName,
    String? photoUrl,
    DateTime? warrantyStartDate,
    int? warrantyMonths,
    bool clearWarranty = false,
    Address? address,
  }) {
    return Machine(
      id: id ?? this.id,
      label: label ?? this.label,
      serialNumber: serialNumber ?? this.serialNumber,
      modelName: modelName ?? this.modelName,
      photoUrl: photoUrl ?? this.photoUrl,
      warrantyStartDate: clearWarranty
          ? null
          : (warrantyStartDate ?? this.warrantyStartDate),
      warrantyMonths:
          clearWarranty ? null : (warrantyMonths ?? this.warrantyMonths),
      address: address ?? this.address,
    );
  }

  @override
  String toString() {
    return 'Machine(id: $id, label: $label, modelName: $modelName, serialNumber: $serialNumber, warrantyState: $warrantyState)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Machine &&
        other.id == id &&
        other.label == label &&
        other.serialNumber == serialNumber &&
        other.modelName == modelName &&
        other.photoUrl == photoUrl &&
        other.warrantyStartDate == warrantyStartDate &&
        other.warrantyMonths == warrantyMonths &&
        other.address == address;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      label,
      serialNumber,
      modelName,
      photoUrl,
      warrantyStartDate,
      warrantyMonths,
      address,
    );
  }
}

/// Model สำหรับที่อยู่ติดตั้งเครื่องจักร
@immutable
class Address {
  final String houseNo;
  final String moo;
  final String tambon;
  final String amphoe;
  final String changwat;
  final String zipCode;

  const Address({
    required this.houseNo,
    required this.moo,
    required this.tambon,
    required this.amphoe,
    required this.changwat,
    required this.zipCode,
  });

  factory Address.fromMap(Map<String, dynamic> map) {
    return Address(
      houseNo: (map['house_no']?.toString())?.trim() ?? '-',
      moo: (map['moo']?.toString())?.trim() ?? '-',
      tambon: (map['tambon']?.toString())?.trim() ?? '-',
      amphoe: (map['amphoe']?.toString())?.trim() ?? '-',
      changwat: (map['changwat']?.toString())?.trim() ?? '-',
      zipCode: (map['zip_code']?.toString())?.trim() ?? '-',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'house_no': houseNo,
      'moo': moo,
      'tambon': tambon,
      'amphoe': amphoe,
      'changwat': changwat,
      'zip_code': zipCode,
    };
  }

  /// คัดลอก Address Object
  Address copyWith({
    String? houseNo,
    String? moo,
    String? tambon,
    String? amphoe,
    String? changwat,
    String? zipCode,
  }) {
    return Address(
      houseNo: houseNo ?? this.houseNo,
      moo: moo ?? this.moo,
      tambon: tambon ?? this.tambon,
      amphoe: amphoe ?? this.amphoe,
      changwat: changwat ?? this.changwat,
      zipCode: zipCode ?? this.zipCode,
    );
  }

  /// จัดฟอร์แมตที่อยู่อย่างชาญฉลาด (ถ้าไม่มีหมู่ หรือเป็น '-' จะข้ามให้โดยอัตโนมัติ)
  String get fullAddress {
    final parts = <String>[];

    if (houseNo.isNotEmpty && houseNo != '-') parts.add(houseNo);
    if (moo.isNotEmpty && moo != '-') parts.add('หมู่ $moo');
    if (tambon.isNotEmpty && tambon != '-') parts.add('ต.$tambon');
    if (amphoe.isNotEmpty && amphoe != '-') parts.add('อ.$amphoe');
    if (changwat.isNotEmpty && changwat != '-') parts.add('จ.$changwat');
    if (zipCode.isNotEmpty && zipCode != '-') parts.add(zipCode);

    return parts.isNotEmpty ? parts.join(' ') : 'ไม่ระบุสถานที่ติดตั้ง';
  }

  @override
  String toString() => fullAddress;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Address &&
        other.houseNo == houseNo &&
        other.moo == moo &&
        other.tambon == tambon &&
        other.amphoe == amphoe &&
        other.changwat == changwat &&
        other.zipCode == zipCode;
  }

  @override
  int get hashCode {
    return Object.hash(houseNo, moo, tambon, amphoe, changwat, zipCode);
  }
}
