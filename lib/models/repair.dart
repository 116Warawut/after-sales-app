import 'package:after_sales/utils/firebase_number.dart';

class Repair {
  final int? id;
  final String? ticketNo;
  final String? customerUsername;
  final String? technicianUsername;
  final String? adminUsername;
  final String? adminName;
  final String? adminCode;
  final int? machineId;
  final String? machine;
  final String? date;
  final String? location;
  final String? status;
  final String? detail;
  final String? reportSummary;
  final String? billId;
  final double totalPrice;
  final int isPaid;
  final double progress;
  final String? createdAt;

  Repair({
    this.id,
    this.ticketNo,
    this.customerUsername,
    this.technicianUsername,
    this.adminUsername,
    this.adminName,
    this.adminCode,
    this.machineId,
    this.machine,
    this.date,
    this.location,
    this.status,
    this.detail,
    this.reportSummary,
    this.billId,
    this.totalPrice = 0.0,
    this.isPaid = 0,
    this.progress = 0.0,
    this.createdAt,
  });

  /// Helper แปลงสถานะการชำระเงินเป็น boolean
  bool get isPaidBool => isPaid == 1;

  // แปลงข้อมูลจาก SQLite Map -> Repair Model
  // ⭐ [แก้ไข] BEFORE: เดิม cast ชนิดข้อมูลจาก Database ตรง ๆ
  // ซึ่งอาจ throw หาก Firebase ส่งตัวเลขเป็น double หรือข้อมูลบางช่องเป็น null
  // factory Repair.fromJson(Map<String, dynamic> json) {
  //   return Repair(
  //     id: json['id'] as int?,
  //     ticketNo: json['ticketNo'] as String?,
  //     customerUsername: json['customer_username'] as String?,
  //     technicianUsername: json['technician_username'] as String?,
  //     adminUsername: json['admin_username'] as String?,
  //     adminName: json['admin_name'] as String?,
  //     adminCode: json['admin_code'] as String?,
  //     machineId: json['machine_id'] as int?,
  //     machine: json['machine'] as String?,
  //     date: json['date'] as String?,
  //     location: json['location'] as String?,
  //     status: json['status'] as String?,
  //     detail: json['detail'] as String?,
  //     reportSummary: json['report_summary'] as String?,
  //     billId: json['bill_id'] as String?,
  //     totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0.0,
  //     isPaid: json['is_paid'] as int? ?? 0,
  //     progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
  //     createdAt: json['created_at'] as String?,
  //   );
  // }

  // ⭐ [แก้ไข] AFTER 2: เปลี่ยนไปใช้ toIntOrNull/toDoubleOrNull (lib/utils/
  // firebase_number.dart) แทน `as num?` ตรง ๆ อีกชั้น เพราะพบว่าบาง record
  // (โดยเฉพาะที่เจอ error ฝั่ง iOS) เก็บ id/machine_id/is_paid เป็น String
  // (เช่น "18") ไม่ใช่ num เลย ซึ่ง `as num?` เดิมก็ยัง throw เหมือนกัน
  factory Repair.fromJson(Map<String, dynamic> json) {
    return Repair(
      // 🐛 [แก้บัค] เดิมใช้ toIntOrNull(json['id']) เชื่อ field 'id' ข้างในตรง ๆ
      // ซึ่งอาจไม่ตรงกับคีย์จริงใน Firebase ของ record นี้ ทำให้พอเอา id ไปเปิด
      // หน้ารายละเอียดต่อ (CustomerJobDetailPage) แล้วเปิดไปเจอ record คนละใบ
      // (ข้อมูลว่างเปล่า) — ใช้ resolveRecordId() ที่ยึดคีย์จริง (_fbKey) เป็น
      // หลักแทน ดูเหตุผลเต็ม ๆ ใน utils/firebase_number.dart
      id: resolveRecordId(json),
      ticketNo: json['ticketNo']?.toString(),
      customerUsername: json['customer_username']?.toString(),
      technicianUsername: json['technician_username']?.toString(),
      adminUsername: json['admin_username']?.toString(),
      adminName: json['admin_name']?.toString(),
      adminCode: json['admin_code']?.toString(),
      machineId: toIntOrNull(json['machine_id']),
      machine: json['machine']?.toString(),
      date: json['date']?.toString(),
      location: json['location']?.toString(),
      status: json['status']?.toString(),
      detail: json['detail']?.toString(),
      reportSummary: json['report_summary']?.toString(),
      billId: json['bill_id']?.toString(),
      totalPrice: toDoubleOr(json['total_price'], 0.0),
      isPaid: toIntOr(json['is_paid'], 0),
      progress: toDoubleOr(json['progress'], 0.0),
      createdAt: json['created_at']?.toString(),
    );
  }

  // แปลง Repair Model -> SQLite Map (สำหรับ INSERT / UPDATE)
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'ticketNo': ticketNo,
      'customer_username': customerUsername,
      'technician_username': technicianUsername,
      'admin_username': adminUsername,
      'admin_name': adminName,
      'admin_code': adminCode,
      'machine_id': machineId,
      'machine': machine,
      'date': date,
      'location': location,
      'status': status,
      'detail': detail,
      'report_summary': reportSummary,
      'bill_id': billId,
      'total_price': totalPrice,
      'is_paid': isPaid,
      'progress': progress,
      'created_at': createdAt,
    };
  }
}
