import 'dart:async' show unawaited;
import 'package:firebase_database/firebase_database.dart';
import 'package:geolocator/geolocator.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/utils/serial_number.dart';
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/debug_log.dart'; // 🔴 [ชั่วคราว-Debug]
// ignore: depend_on_referenced_packages
import 'package:bcrypt/bcrypt.dart' as bcrypt;

/// ผลลัพธ์การเปรียบเทียบวันที่นัดหมายกับวันปัจจุบัน
enum DateComparison { past, today, future }

/// เปรียบเทียบวันที่นัดหมาย (รองรับรูปแบบ "d/M/yyyy" พ.ศ. และ ISO) กับวันปัจจุบัน
DateComparison compareAppointmentDate(String? dateStr) {
  if (dateStr == null || dateStr.trim().isEmpty) return DateComparison.today;
  try {
    final parts = dateStr.trim().split('/');
    if (parts.length == 3) {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final beYear = int.parse(parts[2]);
      final year = beYear > 2400 ? beYear - 543 : beYear;

      final appointmentDate = DateTime(year, month, day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (appointmentDate.isBefore(today)) {
        return DateComparison.past;
      } else if (appointmentDate.isAfter(today)) {
        return DateComparison.future;
      } else {
        return DateComparison.today;
      }
    }
    final parsed = DateTime.tryParse(dateStr);
    if (parsed != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final dateOnly = DateTime(parsed.year, parsed.month, parsed.day);
      if (dateOnly.isBefore(today)) {
        return DateComparison.past;
      } else if (dateOnly.isAfter(today)) {
        return DateComparison.future;
      } else {
        return DateComparison.today;
      }
    }
  } catch (_) {}
  return DateComparison.today;
}

/// 🗓️ เช็คว่าถึงวันนัดซ่อมแล้วหรือยัง (วันนี้ หรือเลยมาแล้ว)
///
/// 🧹 [แก้บัค] เดิมฟังก์ชันนี้ถูกก็อปวางซ้ำกันทุกตัวอักษร 3 ไฟล์
/// (technician_tracking.dart, admin_tracking.dart, customer_tracking.dart
/// ฝั่งช่าง) ทำให้เสี่ยงหลุดไม่ตรงกันได้ถ้าใครแก้จุดเดียวแล้วลืมอีก 2 จุด
/// (เคยเกิดขึ้นมาแล้วครั้งหนึ่งกับรูปแบบวันที่) ย้ายมารวมไว้ที่เดียวแทน
///
/// หมายเหตุ: ตั้งใจให้พฤติกรรมเหมือนของเดิมทุกประการ ไม่ใช่ compareAppointmentDate
/// เพราะกรณี dateStr ว่าง/null ของเดิมคืน false (ยังไม่ถึงวันนัด ปิดกั้นไว้ก่อน
/// เพื่อความปลอดภัย) ในขณะที่ compareAppointmentDate คืน "today" สำหรับกรณีนี้
/// (ใช้กับ getEffectiveRepairStatus ที่ต้องการพฤติกรรมคนละแบบ) จึงแยกฟังก์ชันไว้
bool isAppointmentTodayOrPast(String? dateStr) {
  if (dateStr == null || dateStr.trim().isEmpty) return false;
  try {
    final parts = dateStr.trim().split('/');
    if (parts.length != 3) return false;

    final day = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final buddhistYear = int.parse(parts[2]);
    final year = buddhistYear - 543;

    final appointmentDate = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return !appointmentDate.isAfter(today);
  } catch (_) {
    return true;
  }
}

/// คำนวณสถานะที่แท้จริงของงานซ่อมตามวันที่นัดหมายอัตโนมัติ
String getEffectiveRepairStatus(Map<String, dynamic> repair) {
  final rawStatusRaw = repair['status']?.toString().trim() ?? '';
  final rawStatus = rawStatusRaw.isEmpty ? 'รอจัดสรรช่าง' : rawStatusRaw;

  // 🔴 ปรับให้ normalize คืนค่าคำว่า "มีปัญหา" เสมอเมื่อตรวจพบคำว่าปัญหา
  if (rawStatus == 'มีปัญหา' ||
      rawStatus.contains('ปัญหา') ||
      rawStatus == 'เสร็จแล้ว' ||
      rawStatus == 'เสร็จสิ้น' ||
      rawStatus.contains('ยกเลิก')) {
    if (rawStatus == 'เสร็จแล้ว' || rawStatus == 'เสร็จสิ้น') return 'เสร็จสิ้น';
    if (rawStatus.contains('ยกเลิก')) return 'ยกเลิก';
    if (rawStatus.contains('ปัญหา')) return 'มีปัญหา';
    return rawStatus;
  }

  final tech = repair['technician_username']?.toString().trim();
  if (tech == null || tech.isEmpty || rawStatus == 'รอจัดสรรช่าง') {
    return 'รอจัดสรรช่าง';
  }

  final dateComp = compareAppointmentDate(repair['date']?.toString());
  switch (dateComp) {
    case DateComparison.future:
      return 'รอดำเนินการ';
    case DateComparison.today:
      if (rawStatus == 'กำลังเดินทาง' ||
          rawStatus == 'กำลังดำเนินการ' ||
          rawStatus == 'กำลังซ่อม') {
        return rawStatus;
      }
      return 'รอดำเนินการ';
    case DateComparison.past:
      // 🐛 [แก้บัค] เดิมวันนัดที่ผ่านไปแล้วคืน 'เกินกำหนดเวลา' เสมอ แม้ช่างจะกด
      // เริ่มเดินทาง/ถึงที่หมายไปแล้ว (status จริงใน DB เป็น 'กำลังเดินทาง'/
      // 'กำลังซ่อม') — เพราะ _byId()/_all() เอาค่านี้ไปเขียนทับ row['status'] ทุกครั้งที่
      // อ่าน ทำให้งานเลยกำหนดกด "เริ่มดำเนินการ" แล้วสถานะยังเด้งกลับเป็น
      // 'เกินกำหนดเวลา' ตลอด (หน้าช่างค้างที่ปุ่มเริ่มงาน) และ markTechnicianArrived()
      // โยน error "ยังไม่อยู่ในสถานะ กำลังเดินทาง" ทำให้ไปต่อไม่ได้ — ให้คงสถานะที่
      // ช่างเริ่มลงมือแล้วไว้เหมือนกรณีวันนี้ และใช้ 'เกินกำหนดเวลา' เฉพาะงานที่ยังไม่
      // ได้เริ่มเท่านั้น
      if (rawStatus == 'กำลังเดินทาง' ||
          rawStatus == 'กำลังดำเนินการ' ||
          rawStatus == 'กำลังซ่อม') {
        return rawStatus;
      }
      return 'เกินกำหนดเวลา';
  }
}

/// ==========================================
/// Session: เก็บข้อมูลผู้ใช้ที่ล็อกอินอยู่ในหน่วยความจำ
/// ==========================================
class Session {
  Session._();

  static String currentUsername = '';
  static String currentRole = '';
  static Map<String, dynamic>? currentUserData;
  static String currentAdminType = 'main';

  static bool get isMainAdmin =>
      currentRole == 'ADMIN' && currentAdminType != 'general';

  static void signIn(String username, String role,
      {Map<String, dynamic>? userData}) {
    currentUsername = username;
    currentRole = role.toUpperCase();
    currentUserData = userData;
    currentAdminType = (userData?['admin_type']?.toString() ?? 'main');
  }

  static void signOut() {
    currentUsername = '';
    currentRole = '';
    currentUserData = null;
    currentAdminType = 'main';
  }
}

/// ==========================================
/// DatabaseHelper: จัดการฐานข้อมูล Firebase Realtime Database
/// ==========================================
class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  DatabaseHelper._init();

  static const String? kDatabaseURL =
      'https://aftersales-5c4b4-default-rtdb.asia-southeast1.firebasedatabase.app';

  DatabaseReference get _root {
    final db = kDatabaseURL == null
        ? FirebaseDatabase.instance
        : FirebaseDatabase.instanceFor(
            app: FirebaseDatabase.instance.app, databaseURL: kDatabaseURL);
    return db.ref();
  }

  // ===========================================================================
  // 🍎 [แก้บัค iOS] .get() ตอบ "ไม่มีข้อมูล" ทั้งที่ข้อมูลมีอยู่จริงบนเซิร์ฟเวอร์
  // ---------------------------------------------------------------------------
  // อาการจาก DebugLog บนเครื่องจริง (iOS เท่านั้น, Android ไม่เจอ):
  //     _byId(repairs,42): ตาราง "repairs" ว่างเปล่า/อ่านไม่ได้
  // ทั้งที่ตาราง repairs มีข้อมูลอยู่จริงในฐานข้อมูล และไม่ได้ throw exception
  // ใด ๆ (ถ้าเป็น permission-denied จริง จะเข้า catch แล้ว log "EXCEPTION"
  // แทน ไม่ใช่ข้อความ "ว่างเปล่า/อ่านไม่ได้" นี้) — แปลว่า .get() "สำเร็จ" แต่
  // ตอบว่า exists=false เพราะ plugin firebase_database บน iOS ยังเชื่อมต่อ
  // (WebSocket) กับเซิร์ฟเวอร์ไม่เสร็จตอนที่เรียก โดยเฉพาะตอนเพิ่งเปิดแอป/สลับ
  // แท็บทันที ก่อนที่การเชื่อมต่อจริงจะพร้อม ตัว .get() เลยตอบจาก cache ว่างที่
  // ยังไม่เคย sync แทนที่จะรอเชื่อมต่อเสร็จก่อนค่อยตอบ (Android เจอน้อยกว่ามาก
  // เพราะปกติมักมี stream/listener อื่นเปิดค้างไว้ก่อนแล้วทำให้เชื่อมต่อพร้อมเร็วกว่า)
  //
  // วิธีแก้: ถ้า .get() ครั้งแรกตอบ exists=false ให้เช็ก '.info/connected' ก่อน
  // ถ้ายังไม่เชื่อมต่อ ให้รอสัญญาณเชื่อมต่อสำเร็จ (timeout กันค้าง) แล้วค่อยอ่านซ้ำ
  // อีกครั้งก่อนจะสรุปว่า "ไม่มีข้อมูลจริง ๆ"
  Future<DataSnapshot> _getResilient(DatabaseReference ref) async {
    var snap = await ref.get();
    if (snap.exists && snap.value != null) return snap;

    try {
      final connectedRef = FirebaseDatabase.instance.ref('.info/connected');
      final connSnap = await connectedRef.get();
      final alreadyConnected = connSnap.value == true;

      if (!alreadyConnected) {
        await connectedRef.onValue
            .firstWhere((event) => event.snapshot.value == true)
            .timeout(const Duration(seconds: 6));
      }

      // เชื่อมต่อพร้อมแล้ว (หรือเชื่อมต่ออยู่แล้วตั้งแต่ต้น) ลองอ่านซ้ำอีกครั้ง
      snap = await ref.get();
    } catch (_) {
      // รอเชื่อมต่อไม่ทันภายในเวลาที่กำหนด/เช็คไม่สำเร็จ — ปล่อยผ่านไปใช้ผลลัพธ์
      // จากการอ่านครั้งแรก (exists=false) เหมือนเดิม อย่างน้อยก็ไม่ค้างแอปทั้งหมด
    }
    return snap;
  }

  String _k(dynamic id) {
    if (id == null) return '';
    final s = id.toString().trim();
    if (s.startsWith('k') || s.startsWith('-') || s.contains(RegExp(r'[^0-9]'))) {
      return s;
    }
    return 'k$s';
  }

  int? _toInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value == null) return null;
    final str = value.toString().trim().replaceFirst(RegExp(r'^[kK]'), '');
    return int.tryParse(str);
  }

  Future<int> _nextId(String table) async {
    final ref = _root.child('counters/$table');
    final result = await ref.runTransaction((Object? current) {
      final currentValue = _toInt(current) ?? 0;
      return Transaction.success(currentValue + 1);
    });
    if (!result.committed || result.snapshot.value == null) {
      throw Exception('ไม่สามารถออกเลขที่อ้างอิงใหม่ได้ (table: $table)');
    }
    final nextId = _toInt(result.snapshot.value);
    if (nextId == null || nextId <= 0) {
      throw Exception('เลขที่อ้างอิงใหม่ไม่ถูกต้อง (table: $table)');
    }
    return nextId;
  }

  Future<int> _insert(String table, Map<String, dynamic> data) async {
    final id = await _nextId(table);
    final record = Map<String, dynamic>.from(data);
    record['id'] = id;
    await _root.child('$table/${_k(id)}').set(record);
    return id;
  }

  Future<int> _updateById(
      String table, dynamic id, Map<String, dynamic> data) async {
    if (id == null || data.isEmpty) return 0;
    final key = _k(id);
    if (key.isEmpty) return 0;
    await _root
        .child('$table/$key')
        .update(Map<String, dynamic>.from(data));
    return 1;
  }

  Future<int> _deleteById(String table, dynamic id) async {
    if (id == null) {
      throw ArgumentError(
          'ไม่พบเลขที่อ้างอิง (id) ของรายการนี้ในฐานข้อมูล — ข้อมูลอาจไม่สมบูรณ์');
    }
    final key = _k(id);
    if (key.isEmpty) {
      throw ArgumentError('ไม่พบคีย์ข้อมูลของรายการนี้');
    }
    await _root.child('$table/$key').remove();
    return 1;
  }

  Future<void> _deleteByKey(String table, String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('ไม่พบคีย์ข้อมูลของรายการนี้');
    }
    await _root.child('$table/$trimmed').remove();
  }

  // ===========================================================================
  // 🍎 [แก้บัค iOS] ตัวแปลงข้อมูลดิบจาก Firebase -> Map<String, dynamic>
  // ---------------------------------------------------------------------------
  // สาเหตุ: ฝั่ง iOS ปลั๊กอิน firebase_database ส่งค่ากลับมาจาก NSDictionary
  // ทำให้ snapshot.value เป็น Map<Object?, Object?> และ "คีย์" ที่ได้ไม่ใช่ Dart
  // String เสมอไป (บางคีย์ถูกส่งกลับมาเป็น Object ที่ .toString() แล้วตรง แต่
  // เทียบ == กับ String ไม่ตรง) การใช้ Map<String, dynamic>.from() จึงได้ Map ที่
  // "มีข้อมูลอยู่จริง" แต่พอค้นด้วย row['ticketNo'] กลับได้ null ทุกช่อง
  // -> อาการคือหน้ารายละเอียดขึ้น "-" ทุกช่อง ทั้งที่ exists = true
  //
  // วิธีแก้: ไล่ copy ทีละคีย์ด้วย key.toString() เองแทน (และทำซ้ำชั้นลูกด้วย)
  // ใช้ตัวนี้แทน Map<String, dynamic>.from() ทุกจุดที่อ่านค่าจาก Firebase
  static Map<String, dynamic> normalizeRow(Object? raw) {
    final out = <String, dynamic>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        out[k.toString()] = _normalizeValue(v);
      });
    }
    return out;
  }

  static dynamic _normalizeValue(Object? v) {
    if (v is Map) return normalizeRow(v);
    if (v is List) return v.map(_normalizeValue).toList();
    return v;
  }

  /// ค้นหาข้อมูลตาม ID
  ///
  /// 🍎 [แก้บัค iOS — สำคัญ] เดิมอ่านแบบเจาะ path ลึกตรง ๆ คือ
  ///     _root.child('repairs/k40').get()
  /// ซึ่งบน Android ได้ record ใบเดียวถูกต้อง แต่บน iOS ปลั๊กอิน
  /// firebase_database มีบั๊ก: ถ้ามี listener (onValue) ค้างอยู่ที่ node แม่
  /// เช่น 'repairs' (ซึ่งหน้าแรก/หน้ารายการซ่อมของเราเปิดค้างไว้ผ่าน
  /// _streamAll) แล้วเรียก get() ที่ลูก มันจะคืน "snapshot ของ node แม่"
  /// กลับมาแทน โดย exists ก็เป็น true ด้วย
  ///
  /// หลักฐานจาก DebugLog บนเครื่องจริง:
  ///     _byId(repairs,40): ลอง key="k40" -> exists=true
  ///     _byId(repairs,40): อ่านตรงได้ 3 ฟิลด์ -> k39,k40,k41
  /// คือขอ repairs/k40 แต่ได้ทั้งตาราง repairs (k39,k40,k41) กลับมา
  /// พอไปอ่าน row['ticketNo'] จึงได้ null ทุกช่อง -> หน้าจอขึ้น "-" หมด
  ///
  /// วิธีแก้: เลิกอ่าน path ลึก เปลี่ยนมาอ่าน "ทั้งตาราง" ครั้งเดียวแล้วเลือก
  /// record เองในฝั่ง Dart — เป็นเส้นทางเดียวกับ _all() ที่หน้ารายการซ่อม
  /// ใช้อยู่และทำงานถูกต้องบน iOS อยู่แล้ว (ตารางมีไม่กี่ร้อยแถว อ่านทั้งก้อน
  /// ไม่ได้ช้ากว่ากันอย่างมีนัยสำคัญ)
  Future<Map<String, dynamic>?> _byId(String table, dynamic id) async {
    if (id == null) return null;
    final rawId = id.toString().trim();
    if (rawId.isEmpty || rawId == 'null') return null;

    final key = _k(id);
    final altKey = (rawId.startsWith('k') || rawId.startsWith('K'))
        ? rawId.substring(1)
        : 'k$rawId';
    final numericRaw = rawId.replaceAll(RegExp(r'[^0-9]'), '');

    final table_ = <String, dynamic>{};
    try {
      final snap = await _getResilient(_root.child(table));
      if (!snap.exists || snap.value == null) {
        DebugLog.add('_byId($table,$id): ตาราง "$table" ว่างเปล่า/อ่านไม่ได้');
        return null;
      }

      final raw = snap.value;
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) table_[k.toString()] = normalizeRow(v);
        });
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v != null && v is Map) table_['$i'] = normalizeRow(v);
        }
      }
    } catch (e) {
      DebugLog.add('_byId($table,$id): EXCEPTION ตอนอ่านตาราง: $e');
      return null;
    }

    // 1) ลองจับคู่จาก "คีย์" ตรง ๆ ก่อน ตามลำดับความน่าจะเป็น
    String? hitKey;
    for (final candidate in [key, altKey, rawId, numericRaw, 'k$numericRaw']) {
      if (candidate.isEmpty) continue;
      if (table_.containsKey(candidate)) {
        hitKey = candidate;
        break;
      }
    }

    // 2) ถ้ายังไม่เจอ ค่อยสแกนเทียบจากฟิลด์ id / ticketNo ภายใน record
    if (hitKey == null) {
      for (final entry in table_.entries) {
        final row = entry.value as Map<String, dynamic>;
        final fieldIdStr = row['id']?.toString() ?? '';
        final ticketNoStr = row['ticketNo']?.toString() ?? '';
        final numFieldId = fieldIdStr.replaceAll(RegExp(r'[^0-9]'), '');
        final numTicketNo = ticketNoStr.replaceAll(RegExp(r'[^0-9]'), '');
        final numKeyStr = entry.key.replaceAll(RegExp(r'[^0-9]'), '');

        final matches = fieldIdStr == rawId ||
            ticketNoStr == rawId ||
            (numericRaw.isNotEmpty &&
                (numFieldId == numericRaw ||
                    numTicketNo == numericRaw ||
                    numKeyStr == numericRaw));

        if (matches) {
          hitKey = entry.key;
          break;
        }
      }
    }

    if (hitKey == null) {
      DebugLog.add(
          '_byId($table,$id): ไม่พบ record (คีย์ในตาราง: ${table_.keys.take(12).join(",")})');
      return null;
    }

    final row = Map<String, dynamic>.from(table_[hitKey] as Map<String, dynamic>);
    row['_fbKey'] = hitKey;
    row['id'] ??= hitKey;
    if (table == 'repairs') {
      row['status'] = getEffectiveRepairStatus(row);
    }
    DebugLog.add(
        '_byId($table,$id): พบ record คีย์ "$hitKey" (${row.length} ฟิลด์)');
    return row;
  }

  Future<List<Map<String, dynamic>>> _all(String table) async {
    final snap = await _getResilient(_root.child(table));
    if (!snap.exists || snap.value == null) return [];
    final out = <Map<String, dynamic>>[];
    final raw = snap.value;
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is Map) {
          final row = normalizeRow(v);
          row['_fbKey'] = entry.key.toString();
          row['id'] ??= entry.key.toString();
          if (table == 'repairs') {
            row['status'] = getEffectiveRepairStatus(row);
          }
          out.add(row);
        }
      }
    } else if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final v = raw[i];
        if (v != null && v is Map) {
          final row = normalizeRow(v);
          row['_fbKey'] = i.toString();
          row['id'] ??= i.toString();
          if (table == 'repairs') {
            row['status'] = getEffectiveRepairStatus(row);
          }
          out.add(row);
        }
      }
    }
    return out;
  }

  List<Map<String, dynamic>> _sortById(List<Map<String, dynamic>> rows,
      {bool desc = false}) {
    rows.sort((a, b) {
      final ai = _toInt(a['id']) ?? 0;
      final bi = _toInt(b['id']) ?? 0;
      if (ai != 0 || bi != 0) {
        return desc ? bi.compareTo(ai) : ai.compareTo(bi);
      }
      final sa = a['created_at']?.toString() ?? a['id']?.toString() ?? '';
      final sb = b['created_at']?.toString() ?? b['id']?.toString() ?? '';
      return desc ? sb.compareTo(sa) : sa.compareTo(sb);
    });
    return rows;
  }

  Future<List<Map<String, dynamic>>> _where(
      String table, bool Function(Map<String, dynamic> row) test,
      {bool desc = false}) async {
    final all = await _all(table);
    return _sortById(all.where(test).toList(), desc: desc);
  }

  Stream<List<Map<String, dynamic>>> _streamAll(String table) {
    return _root.child(table).onValue.map((event) {
      final raw = event.snapshot.value;
      final out = <Map<String, dynamic>>[];
      if (raw is Map) {
        for (final entry in raw.entries) {
          final v = entry.value;
          if (v is Map) {
            final row = normalizeRow(v);
            row['_fbKey'] = entry.key.toString();
            row['id'] ??= entry.key.toString();
            if (table == 'repairs') {
              row['status'] = getEffectiveRepairStatus(row);
            }
            out.add(row);
          }
        }
      } else if (raw is List) {
        for (var i = 0; i < raw.length; i++) {
          final v = raw[i];
          if (v != null && v is Map) {
            final row = normalizeRow(v);
            row['_fbKey'] = i.toString();
            row['id'] ??= i.toString();
            if (table == 'repairs') {
              row['status'] = getEffectiveRepairStatus(row);
            }
            out.add(row);
          }
        }
      }
      return out;
    });
  }

  Stream<List<Map<String, dynamic>>> _streamWhere(
      String table, bool Function(Map<String, dynamic> row) test,
      {bool desc = false}) {
    return _streamAll(table)
        .map((rows) => _sortById(rows.where(test).toList(), desc: desc));
  }

  Future<int> _updateWhere(
      String table,
      bool Function(Map<String, dynamic>) test,
      Map<String, dynamic> data) async {
    final rows = await _where(table, test);
    for (final row in rows) {
      final key = row['_fbKey']?.toString() ?? _k(row['id']);
      if (key.isNotEmpty) {
        await _root.child('$table/$key').update(Map<String, dynamic>.from(data));
      }
    }
    return rows.length;
  }

  Future<int> _deleteWhere(
      String table, bool Function(Map<String, dynamic>) test) async {
    final rows = await _where(table, test);
    for (final row in rows) {
      final key = row['_fbKey']?.toString() ?? _k(row['id']);
      if (key.isNotEmpty) {
        await _root.child('$table/$key').remove();
      }
    }
    return rows.length;
  }

  bool _looksHashed(String password) {
    return password.startsWith(r'$2a$') ||
        password.startsWith(r'$2b$') ||
        password.startsWith(r'$2y$');
  }

  String _hashPassword(String plainPassword) {
    return bcrypt.BCrypt.hashpw(plainPassword, bcrypt.BCrypt.gensalt());
  }

  bool _verifyPassword(String plainPassword, String storedPassword) {
    try {
      if (_looksHashed(storedPassword)) {
        return bcrypt.BCrypt.checkpw(plainPassword, storedPassword);
      }
      return plainPassword == storedPassword;
    } catch (_) {
      return false;
    }
  }

  static const List<String> _allTables = [
    'customers',
    'technicians',
    'admins',
    'repairs',
    'machines',
    'spare_parts',
    'part_requests',
    'payments',
    'chat_messages',
    'chat_read_status',
    'notifications',
  ];

  Future<void> init() async {
    try {
      // 🍎 ใช้ _getResilient เช่นกัน กัน iOS อ่านตอนเชื่อมต่อยังไม่พร้อมแล้วเข้าใจ
      // ผิดว่า "ยังไม่มีแอดมินเลย" ทั้งที่มีอยู่แล้วจริง ๆ แล้วไปสร้างแอดมิน
      // ค่าเริ่มต้น (username: ad) ซ้ำขึ้นมาอีกชุดโดยไม่จำเป็น
      final snap = await _getResilient(_root.child('admins'));
      final hasAdmin = snap.exists && snap.value != null;
      if (!hasAdmin) {
        await _seedAdminOnly();
      }
    } catch (_) {}
  }

  Future<void> _seedAdminOnly() async {
    await _insert('admins', {
      'admin_name': 'นายประสิทธิ์ โชคชัยฟาร์ม',
      'admin_code': 'AD-0012',
      'username': 'ad',
      'password': _hashPassword('12345678'),
      'phone': '02-123-4567',
    });
  }

  Future<void> resetDatabase() async {
    for (final table in _allTables) {
      await _root.child(table).remove();
    }
    await _root.child('counters').remove();
    await _seedAdminOnly();
  }

  String _tableForRole(String role) {
    final r = role.toUpperCase();
    switch (r) {
      case 'CUSTOMER':
        return 'customers';
      case 'TECHNICIAN':
        return 'technicians';
      case 'ADMIN':
        return 'admins';
      default:
        throw const FormatException('ไม่พบประเภทผู้ใช้งานที่ถูกต้อง');
    }
  }

  Future<Map<String, dynamic>?> login(
      String identifier, String password, String role) async {
    final normalized = identifier.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) return null;
    final table = _tableForRole(role);
    final rows = await _where(table, (r) {
      final u = r['username']?.toString().trim().toLowerCase() ?? '';
      final e = r['email']?.toString().trim().toLowerCase() ?? '';
      return u == normalized || (e.isNotEmpty && e == normalized);
    });
    if (rows.isEmpty) return null;

    final user = rows.first;
    final storedPassword = user['password']?.toString() ?? '';
    if (!_verifyPassword(password, storedPassword)) return null;

    if (!_looksHashed(storedPassword)) {
      final id = user['id'];
      final newHash = _hashPassword(password);
      await _updateById(table, id, {'password': newHash});
      user['password'] = newHash;
    }

    final safeUser = Map<String, dynamic>.from(user)..remove('password');
    return safeUser;
  }

  Future<Map<String, dynamic>?> verifyLogin(
      String identifier, String password) async {
    final normalized = identifier.trim().toLowerCase();
    if (normalized.isEmpty || password.isEmpty) return null;
    final account = await _findAccountByUsernameWithPassword(normalized);
    if (account == null) return null;

    final role = account['role']?.toString() ?? '';
    if (role.isEmpty) return null;
    final table = _tableForRole(role);
    final storedPassword = account['password']?.toString() ?? '';
    if (!_verifyPassword(password, storedPassword)) return null;

    if (!_looksHashed(storedPassword)) {
      final id = account['id'];
      final newHash = _hashPassword(password);
      await _updateById(table, id, {'password': newHash});
      account['password'] = newHash;
    }

    account.remove('password');
    return account;
  }

  Future<Map<String, dynamic>?> _findAccountByUsernameWithPassword(
      String identifier) async {
    final query = identifier.trim().toLowerCase();
    if (query.isEmpty) return null;

    bool matchAccount(Map<String, dynamic> r) {
      final username = r['username']?.toString().trim().toLowerCase() ?? '';
      final email = r['email']?.toString().trim().toLowerCase() ?? '';
      return (email.isNotEmpty && email == query) ||
          (username.isNotEmpty && username == query);
    }

    final customer = await _where('customers', matchAccount);
    if (customer.isNotEmpty) return {...customer.first, 'role': 'CUSTOMER'};

    final technician = await _where('technicians', matchAccount);
    if (technician.isNotEmpty) {
      return {...technician.first, 'role': 'TECHNICIAN'};
    }

    final admin = await _where('admins', matchAccount);
    if (admin.isNotEmpty) return {...admin.first, 'role': 'ADMIN'};

    return null;
  }

  Future<Map<String, dynamic>?> findAccountByUsername(String identifier) async {
    final account = await _findAccountByUsernameWithPassword(identifier);
    if (account == null) return null;
    account.remove('password');
    return account;
  }

  Future<int> updatePasswordForRole(
      String identifier, String role, String newPassword) async {
    if (identifier.trim().isEmpty || newPassword.isEmpty) {
      throw const FormatException('Username/Email และรหัสผ่านต้องไม่ว่าง');
    }
    final table = _tableForRole(role);
    final target = identifier.trim().toLowerCase();

    return await _updateWhere(
      table,
      (r) {
        final u = r['username']?.toString().trim().toLowerCase() ?? '';
        final e = r['email']?.toString().trim().toLowerCase() ?? '';
        return u == target || (e.isNotEmpty && e == target);
      },
      {'password': _hashPassword(newPassword)},
    );
  }

  Map<String, dynamic> _withHashedPassword(
    Map<String, dynamic> data, {
    bool passwordRequired = false,
  }) {
    if (!data.containsKey('password') || data['password'] == null) {
      if (passwordRequired) {
        throw const FormatException('ต้องระบุรหัสผ่าน');
      }
      return data;
    }

    final record = Map<String, dynamic>.from(data);
    final password = record['password'].toString();

    if (password.isEmpty) {
      if (passwordRequired) {
        throw const FormatException('รหัสผ่านต้องไม่ว่าง');
      }
      record.remove('password');
      return record;
    }

    record['password'] =
        _looksHashed(password) ? password : _hashPassword(password);
    return record;
  }

  Future<int> registerCustomer(Map<String, dynamic> data) =>
      _registerAccount('customers', data);

  Future<int> registerTechnician(Map<String, dynamic> data) =>
      _registerAccount('technicians', data);

  Future<int> deleteTechnician(String username) =>
      _deleteWhere('technicians', (r) => r['username'] == username);

  Future<int> deleteCustomer(String username) =>
      _deleteWhere('customers', (r) => r['username'] == username);

  Future<int> deleteAdmin(String username) =>
      _deleteWhere('admins', (r) => r['username'] == username);

  Future<int> registerAdmin(Map<String, dynamic> data) {
    if (!Session.isMainAdmin) {
      throw StateError('เฉพาะแอดมินหลักเท่านั้นที่เพิ่มแอดมินใหม่ได้');
    }
    return _registerAccount('admins', data);
  }

  Future<int> reassignRepairAdmin(int repairId, String newAdminUsername) {
    if (!Session.isMainAdmin) {
      throw StateError('เฉพาะแอดมินหลักเท่านั้นที่จัดสรรงานให้แอดมินคนอื่นได้');
    }
    return updateRepair(repairId, {'admin_username': newAdminUsername});
  }

  Future<int> _registerAccount(String table, Map<String, dynamic> data) async {
    final username = data['username']?.toString().trim() ?? '';
    if (username.isEmpty) {
      throw const FormatException('Username ต้องไม่ว่าง');
    }
    if (await checkUsernameExists(username)) {
      throw StateError('Username นี้ถูกใช้งานแล้ว');
    }

    final record = Map<String, dynamic>.from(data);
    record['username'] = username;
    return _insert(table, _withHashedPassword(record, passwordRequired: true));
  }

  Future<bool> checkUsernameExists(String username) async {
    final query = username.trim().toLowerCase();
    bool matchAccount(Map<String, dynamic> r) {
      final u = r['username']?.toString().trim().toLowerCase() ?? '';
      final e = r['email']?.toString().trim().toLowerCase() ?? '';
      return u == query || (e.isNotEmpty && e == query);
    }

    final c = await _where('customers', matchAccount);
    final t = await _where('technicians', matchAccount);
    final a = await _where('admins', matchAccount);
    return c.isNotEmpty || t.isNotEmpty || a.isNotEmpty;
  }

  Future<void> _validateUsernameChange(
      String currentUsername, String? newUsername) async {
    final trimmed = newUsername?.trim() ?? '';
    if (newUsername == null || trimmed.isEmpty || trimmed == currentUsername) {
      return;
    }
    if (await checkUsernameExists(trimmed)) {
      throw StateError('Username ใหม่ถูกใช้งานแล้ว');
    }
  }

  Future<Map<String, dynamic>?> getUserProfile(
      String username, String role) async {
    final table = _tableForRole(role);
    final rows = await _where(table, (r) => r['username'] == username);
    if (rows.isEmpty) return null;
    return _withoutPassword(rows.first);
  }

  Future<Map<String, dynamic>?> getCustomerProfile(String username) =>
      getUserProfile(username, 'CUSTOMER');
  Future<Map<String, dynamic>?> getTechnicianByUsername(String username) =>
      getUserProfile(username, 'TECHNICIAN');
  Future<Map<String, dynamic>?> getAdminProfile(String username) =>
      getUserProfile(username, 'ADMIN');

  Future<List<Map<String, dynamic>>> getAllTechnicians() async =>
      _withoutPasswords(_sortById(await _all('technicians')));

  Future<List<Map<String, dynamic>>> getAllAdmins() async =>
      _withoutPasswords(_sortById(await _all('admins')));

  Future<List<Map<String, dynamic>>> getAllCustomers() async =>
      _withoutPasswords(_sortById(await _all('customers')));

  Map<String, dynamic> _withoutPassword(Map<String, dynamic> row) {
    final safeRow = Map<String, dynamic>.from(row);
    safeRow.remove('password');
    return safeRow;
  }

  List<Map<String, dynamic>> _withoutPasswords(
      List<Map<String, dynamic>> rows) {
    return rows.map(_withoutPassword).toList();
  }

  Future<int> updateCustomerProfile(
    String username,
    Map<String, dynamic> data, {
    String? newUsername,
  }) async {
    await _validateUsernameChange(username, newUsername);
    final updateMap = _withHashedPassword(Map<String, dynamic>.from(data));
    if (newUsername != null &&
        newUsername.isNotEmpty &&
        newUsername != username) {
      updateMap['username'] = newUsername.trim();
      await _updateWhere('repairs', (r) => r['customer_username'] == username,
          {'customer_username': newUsername.trim()});
      await _updateWhere('machines', (r) => r['customer_username'] == username,
          {'customer_username': newUsername.trim()});
    }
    return await _updateWhere(
      'customers',
      (r) => r['username'] == username,
      updateMap,
    );
  }

  Future<int> updateTechnicianProfile(
    String username,
    Map<String, dynamic> data, {
    String? newUsername,
  }) async {
    await _validateUsernameChange(username, newUsername);
    final updateMap = _withHashedPassword(Map<String, dynamic>.from(data));
    if (newUsername != null &&
        newUsername.isNotEmpty &&
        newUsername != username) {
      updateMap['username'] = newUsername.trim();
      await _updateWhere('repairs', (r) => r['technician_username'] == username,
          {'technician_username': newUsername.trim()});
      await _updateWhere(
          'part_requests',
          (r) => r['technician_username'] == username,
          {'technician_username': newUsername.trim()});
    }
    return await _updateWhere(
      'technicians',
      (r) => r['username'] == username,
      updateMap,
    );
  }

  Future<int> updateAdminProfile(
    String username,
    Map<String, dynamic> data, {
    String? newUsername,
  }) async {
    await _validateUsernameChange(username, newUsername);
    final updateMap = _withHashedPassword(Map<String, dynamic>.from(data));
    if (newUsername != null &&
        newUsername.isNotEmpty &&
        newUsername != username) {
      updateMap['username'] = newUsername.trim();
    }
    return await _updateWhere(
      'admins',
      (r) => r['username'] == username,
      updateMap,
    );
  }

  Future<int> updateTechnicianLocation(
          String username, double lat, double lng) =>
      _updateWhere('technicians', (r) => r['username'] == username,
          {'current_lat': lat, 'current_lng': lng});

  Stream<Map<String, dynamic>?> watchTechnicianLocation(String username) {
    return _streamWhere('technicians', (r) => r['username'] == username)
        .map((rows) => rows.isEmpty ? null : rows.first);
  }

  Future<int> updateTechnicianPhoto(String username, String photoUrl) =>
      _updateWhere('technicians', (r) => r['username'] == username,
          {'photo_url': photoUrl});

  // ==========================================
  // 4. ระบบจัดการใบแจ้งซ่อม (REPAIRS & JOBS)
  // ==========================================

  Future<int> createRepair(Map<String, dynamic> data) async {
    final record = Map<String, dynamic>.from(data);
    final customerUsername =
        record['customer_username']?.toString().trim() ?? '';
    if (customerUsername.isEmpty) {
      throw const FormatException('ต้องระบุลูกค้าของงานซ่อม');
    }
    record['customer_username'] = customerUsername;
    record['status'] ??= 'รอจัดสรรช่าง';
    record['created_at'] ??= DateTime.now().toIso8601String();
    return await _insert('repairs', record);
  }

  // 🆕 [ใหม่] เพิ่มเงื่อนไข r['hidden'] != true ให้ทั้ง 4 ฟังก์ชันนี้ —
  // งานที่ปิด (สถานะมีคำว่า "เสร็จ") มาเกิน 3 วันแล้ว จะถูก Cloudflare Worker
  // (cron รายวัน ดูรายละเอียดที่ cloudflare-worker/src/index.js — ฟังก์ชัน
  // runChatCleanup) ตั้ง field 'hidden': true ให้ พร้อมกับลบห้องแชท
  // (chat_messages/chat_read_status) ของงานนั้นทิ้งไปเลย ไม่ใช่ลบตัว record
  // งานซ่อมทิ้ง เพื่อไม่ให้ข้อมูลใบแจ้งหนี้/การชำระเงินที่ผูกกับงานนั้นหายไป
  // ถาวร — ให้แอดมินยังเห็นงานนี้ได้ปกติ (getAllRepairs()/watchAllRepairs()
  // ไม่ได้กรอง hidden ออก) แต่ลูกค้า/ช่างเจ้าของงานจะไม่เห็นงานนี้อีกต่อไปในหน้า
  // รายการของตัวเอง
  Future<List<Map<String, dynamic>>> getRepairsByCustomer(String username) =>
      _where(
          'repairs',
          (r) => r['customer_username'] == username && r['hidden'] != true,
          desc: true);

  Stream<List<Map<String, dynamic>>> watchRepairsByCustomer(
          String username) =>
      _streamWhere(
          'repairs',
          (r) => r['customer_username'] == username && r['hidden'] != true,
          desc: true);

  Future<List<Map<String, dynamic>>> getRepairsByTechnician(String username) =>
      _where(
          'repairs',
          (r) => r['technician_username'] == username && r['hidden'] != true,
          desc: true);

  Stream<List<Map<String, dynamic>>> watchRepairsByTechnician(
          String username) =>
      _streamWhere(
          'repairs',
          (r) => r['technician_username'] == username && r['hidden'] != true,
          desc: true);

  Future<List<Map<String, dynamic>>> getRepairsByMachine(int machineId) =>
      _where('repairs', (r) => _toInt(r['machine_id']) == machineId,
          desc: true);

  /// 🔧 [แก้ mismatch] ดึงประวัติซ่อมของเครื่องจักรโดยจับคู่ได้ทั้ง machine_id และ
  /// serial_number — กันกรณีเครื่องที่แอดมินเพิ่มผ่านเว็บ ซึ่ง id เป็น push-key
  /// (string) ทำให้ฝั่งแอปแปลงเป็น int ไม่ได้ (machine.id = null) แล้วงานซ่อมของ
  /// เครื่องนั้นเก็บ machine_id เป็น null ทั้งที่มี serial_number อยู่
  Future<List<Map<String, dynamic>>> getRepairsForMachine({
    int? machineId,
    String? serialNumber,
  }) {
    final serial = normalizeSerialNumber(serialNumber ?? '');
    return _where(
      'repairs',
      (r) {
        if (machineId != null && _toInt(r['machine_id']) == machineId) {
          return true;
        }
        if (serial.isNotEmpty) {
          final rowSerial =
              normalizeSerialNumber(r['serial_number']?.toString() ?? '');
          if (rowSerial == serial) return true;
        }
        return false;
      },
      desc: true,
    );
  }

  Future<List<Map<String, dynamic>>> getAllRepairs() async =>
      _sortById(await _all('repairs'), desc: true);

  Stream<List<Map<String, dynamic>>> watchAllRepairs() =>
      _streamAll('repairs').map((rows) => _sortById(rows, desc: true));

  Future<Map<String, dynamic>?> getRepairById(dynamic id) => _byId('repairs', id);

  Future<List<Map<String, dynamic>>> searchRepairs(String query) async {
    final q = query.toLowerCase();
    return _where('repairs', (r) {
      bool has(String field) =>
          (r[field]?.toString().toLowerCase() ?? '').contains(q);
      return has('ticketNo') ||
          has('machine') ||
          has('customer_username') ||
          has('status');
    }, desc: true);
  }

  static const int maxJobsPerTechnicianPerDay = 3;

  Future<Map<String, int>> getTechnicianJobCountsForDate(
    String dateText, {
    int? excludeRepairId,
  }) async {
    final rows = await _where('repairs', (r) {
      final tech = r['technician_username']?.toString();
      if (tech == null || tech.isEmpty) return false;
      if (r['date'] != dateText) return false;
      final status = r['status']?.toString() ?? '';
      if (status.contains('ยกเลิก')) return false;
      final id = _toInt(r['id']);
      if (excludeRepairId != null && id == excludeRepairId) return false;
      return true;
    });

    final result = <String, int>{};
    for (final row in rows) {
      final username = row['technician_username']?.toString();
      if (username == null || username.isEmpty) continue;
      result[username] = (result[username] ?? 0) + 1;
    }
    return result;
  }

  Future<int> assignTechnicianToRepair({
    required dynamic repairId,
    required String techUsername,
    required String adminUsername,
    String? appointmentDate,
  }) async {
    if (repairId == null ||
        techUsername.trim().isEmpty ||
        adminUsername.trim().isEmpty) {
      throw const FormatException('ข้อมูลการมอบหมายงานไม่ถูกต้อง');
    }
    final repair = await getRepairById(repairId);
    if (repair == null) {
      throw StateError('ไม่พบงานซ่อมที่ต้องการมอบหมาย');
    }

    final dateToCheck = (appointmentDate != null && appointmentDate.isNotEmpty)
        ? appointmentDate
        : repair['date']?.toString();
    final dateComp = compareAppointmentDate(dateToCheck);

    String initialStatus;
    double progress = 0.05;
    switch (dateComp) {
      case DateComparison.future:
        initialStatus = 'รอดำเนินการ';
        progress = 0.05;
        break;
      // 🐛 [แก้บัค] เดิมตั้งสถานะเริ่มต้นเป็น 'กำลังซ่อม' ทันทีตอนมอบหมายงานที่
      // นัดวันนี้พอดี ทั้งที่ช่างยังไม่ได้เริ่มเดินทาง/ลงมือทำจริงเลย — ทำให้งาน
      // ทุกงานของวันนั้น (ถ้าช่างมีมากกว่า 1 งาน) ดูเหมือน "กำลังซ่อม" พร้อมกัน
      // หมดตั้งแต่ยังไม่ถึงคิว เปลี่ยนเป็น 'รอดำเนินการ' ก่อน แล้วค่อยขยับเป็น
      // 'กำลังเดินทาง' (เมื่อถึงคิวและช่างเปิดดูแผนที่) และ 'กำลังดำเนินการ'
      // (เมื่อช่างกดรับงานจริง) ตามลำดับจริงแทน
      case DateComparison.today:
        initialStatus = 'รอดำเนินการ';
        progress = 0.05;
        break;
      case DateComparison.past:
        initialStatus = 'เกินกำหนดเวลา';
        progress = 0.1;
        break;
    }

    final values = <String, dynamic>{
      'technician_username': techUsername.trim(),
      'admin_username': adminUsername.trim(),
      'status': initialStatus,
      'assignment_status': 'จัดสรรช่างแล้ว',
      'progress': progress,
      'approved_at': DateTime.now().toIso8601String(),
    };
    if (appointmentDate != null && appointmentDate.isNotEmpty) {
      values['date'] = appointmentDate.trim();
    }
    return await _updateById('repairs', repairId, values);
  }

  Future<({int position, int total})> getQueueInfo(dynamic repairId) async {
    final repair = await getRepairById(repairId);
    if (repair == null) return (position: 1, total: 1);

    final techUsername = repair['technician_username']?.toString();
    final date = repair['date']?.toString();
    if (techUsername == null ||
        techUsername.isEmpty ||
        date == null ||
        date.isEmpty) {
      return (position: 1, total: 1);
    }

    // 🐛 [แก้บัค] เดิมใช้ `as String?` ตรง ๆ ถ้า approved_at/created_at ของ record
    // ไหนถูกเก็บเป็นชนิดอื่น (เช่น timestamp แบบตัวเลข) จะ throw กลางทาง ทำให้
    // ระบบคิวงานของช่างคนนั้นทั้งวันพังไปด้วย (กระทบหน้าติดตามตำแหน่งช่างของ
    // ลูกค้าโดยตรง)
    String? approvalKey(Map<String, dynamic> r) =>
        r['approved_at']?.toString() ?? r['created_at']?.toString();

    final sameDayJobs = await _where('repairs', (r) {
      if (r['technician_username']?.toString() != techUsername) return false;
      if (r['date']?.toString() != date) return false;
      final status = r['status']?.toString() ?? '';
      if (status.contains('ยกเลิก') ||
          status == 'เสร็จแล้ว' ||
          status == 'เสร็จสิ้น') {
        return false;
      }
      return true;
    });

    sameDayJobs.sort((a, b) {
      final ak = approvalKey(a);
      final bk = approvalKey(b);
      if (ak == null && bk == null) return 0;
      if (ak == null) return 1;
      if (bk == null) return -1;
      return ak.compareTo(bk);
    });

    final myId = repair['id']?.toString();
    final index = sameDayJobs.indexWhere((r) => r['id']?.toString() == myId);
    if (index == -1) {
      return (position: 1, total: sameDayJobs.isEmpty ? 1 : sameDayJobs.length);
    }

    return (position: index + 1, total: sameDayJobs.length);
  }

  /// 🆕 [แก้ไข] ตั้งสถานะงานเป็น "กำลังเดินทาง" — เดิมเรียกตอนช่างเปิดหน้าติดตาม
  /// ตำแหน่งลูกค้าเฉย ๆ (แบบ side-effect เงียบ ๆ) ตอนนี้เรียกจากปุ่ม "เริ่มดำเนินการ"
  /// ในหน้ารายละเอียดงานของช่างโดยตรง (job_detail.dart) และบังคับเช็คว่าต้องถึง
  /// คิวงานนี้ก่อน (ตำแหน่งที่ 1 ของคิววันนั้น) เท่านั้นถึงจะเปลี่ยนสถานะได้ — โยน
  /// StateError ถ้ายังไม่ถึงคิว เพื่อกันช่างข้ามคิวเปลี่ยนสถานะงานอื่นก่อนงานที่ควร
  /// ทำก่อน ไม่ทับสถานะที่ก้าวหน้าไปไกลกว่านี้แล้ว (กำลังซ่อม/เสร็จแล้ว/มีปัญหา/
  /// ยกเลิก) กันย้อนสถานะกลับ
  Future<void> markTechnicianTraveling(dynamic repairId) async {
    final repair = await getRepairById(repairId);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final rawStatus = repair['status']?.toString().trim() ?? '';
    if (rawStatus == 'กำลังเดินทาง') return; // ตั้งไว้แล้ว ไม่ต้องเขียนซ้ำ
    const pastStages = {
      'กำลังดำเนินการ',
      'กำลังซ่อม',
      'เสร็จแล้ว',
      'เสร็จสิ้น',
      'มีปัญหา',
    };
    if (pastStages.contains(rawStatus) || rawStatus.contains('ยกเลิก')) return;

    final queueInfo = await getQueueInfo(repairId);
    if (queueInfo.position != 1) {
      throw StateError(
          'ยังไม่ถึงคิวงานนี้ (คิวที่ ${queueInfo.position} จาก ${queueInfo.total} งานของวันนี้)');
    }
    await _updateById('repairs', repairId, {'status': 'กำลังเดินทาง'});
  }

  /// 🆕 [ใหม่] ช่างกดยืนยันว่า "ถึงที่หมายแล้ว" — เปลี่ยนสถานะจาก "กำลังเดินทาง"
  /// เป็น "กำลังซ่อม" และแจ้งเตือนลูกค้าว่าช่างมาถึงแล้วกำลังเริ่มซ่อม อนุญาตให้
  /// กดซ้ำได้เผื่อกดถี่/เน็ตช้าถ้าสถานะเดินหน้าไปเป็น "กำลังซ่อม" อยู่แล้ว (ถือว่า
  /// สำเร็จ ไม่โยน error ซ้ำ) แต่โยน StateError ถ้างานยังไม่เคยถูกตั้งเป็น
  /// "กำลังเดินทาง" มาก่อนเลย (เช่น กดข้ามขั้นตอน)
  Future<void> markTechnicianArrived(dynamic repairId) async {
    final repair = await getRepairById(repairId);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final rawStatus = repair['status']?.toString().trim() ?? '';
    if (rawStatus == 'กำลังซ่อม' || rawStatus == 'กำลังดำเนินการ') {
      return; // ถึงขั้นตอนนี้ไปแล้ว ถือว่าสำเร็จ ไม่ต้องทำซ้ำ
    }
    if (rawStatus != 'กำลังเดินทาง') {
      throw StateError('งานนี้ยังไม่อยู่ในสถานะ "กำลังเดินทาง"');
    }

    await _updateById('repairs', repairId, {'status': 'กำลังซ่อม'});

    final customerUsername = repair['customer_username']?.toString();
    final ticketNo = repair['ticketNo']?.toString() ?? '';
    if (customerUsername != null && customerUsername.isNotEmpty) {
      await createNotification({
        'user_username': customerUsername,
        'role': 'CUSTOMER',
        'title': 'ช่างถึงที่หมายแล้ว',
        'message':
            'ช่างซ่อมถึงสถานที่ของท่านแล้ว งานซ่อม $ticketNo กำลังเริ่มดำเนินการซ่อม',
        'type': 'TECH_ARRIVED',
        'target_id': repairId,
        'is_read': 0,
      });
    }
  }

  /// 🆕 [ใหม่] เช็คระยะห่างแบบเส้นตรง (Haversine ผ่าน Geolocator) ระหว่างตำแหน่ง
  /// ช่างปัจจุบันกับหมุดลูกค้า ถ้าเข้าใกล้ในรัศมี 1 กม. ให้แจ้งเตือนลูกค้าว่า
  /// "ช่างใกล้ถึงแล้ว" — ส่งแค่ครั้งเดียวต่องาน (เก็บ flag near_notified ไว้กัน
  /// แจ้งเตือนซ้ำ ๆ ตอนช่างเข้า-ออกรัศมีระหว่างรถติดไฟแดงหน้าปากซอย)
  Future<void> notifyIfTechnicianNearby({
    required dynamic repairId,
    required double techLat,
    required double techLng,
    required double destLat,
    required double destLng,
    required String customerUsername,
    required String ticketLabel,
  }) async {
    if (customerUsername.trim().isEmpty) return;
    final repair = await getRepairById(repairId);
    if (repair == null) return;
    final alreadyNotified =
        repair['near_notified'] == true || repair['near_notified'] == 1;
    if (alreadyNotified) return;

    final distanceMeters =
        Geolocator.distanceBetween(techLat, techLng, destLat, destLng);
    if (distanceMeters > 1000) return;

    await _updateById('repairs', repairId, {'near_notified': true});
    await createNotification({
      'user_username': customerUsername,
      'role': 'CUSTOMER',
      'title': 'ช่างใกล้ถึงแล้ว',
      'message': 'ช่างซ่อมเดินทางใกล้ถึงตำแหน่งของท่านแล้ว (งาน $ticketLabel)',
      'type': 'TECH_NEARBY',
      'target_id': repairId,
      'is_read': 0,
    });
  }

  Future<Map<String, int>> getRepairSummary(String username) async {
    final all = await getRepairsByCustomer(username);
    final total = all.length;
    final completed = all
        .where((r) => r['status'] == 'เสร็จแล้ว' || r['status'] == 'เสร็จสิ้น')
        .length;
    return {
      'total': total,
      'completed': completed,
      'remaining': total - completed
    };
  }

  Future<Map<String, dynamic>> getAdminDashboardSummary() async {
    final all = await getAllRepairs();
    final unassigned = all.where((r) => r['status'] == 'รอจัดสรรช่าง').length;
    final scheduledPending = all.where((r) => r['status'] == 'รอดำเนินการ').length;
    final inProgress = all.where((r) => r['status'] == 'กำลังซ่อม' || r['status'] == 'กำลังดำเนินการ' || r['status'] == 'กำลังเดินทาง').length;
    final overdue = all.where((r) => r['status'] == 'เกินกำหนดเวลา').length;
    final completed = all
        .where((r) => r['status'] == 'เสร็จแล้ว' || r['status'] == 'เสร็จสิ้น')
        .length;
    // 🔴 เพิ่มการนับจำนวนงานที่มีปัญหา
    final problem = all
        .where((r) => r['status'] == 'มีปัญหา' || (r['status']?.toString() ?? '').contains('ปัญหา'))
        .length;

    double totalRevenue = 0.0;
    for (var r in all) {
      // 🆕 [ใหม่] ไม่นับบิลที่ยกเว้นค่าใช้จ่ายเพราะเครื่องจักรอยู่ในประกัน
      // (is_warranty_covered) รวมเป็นรายได้จริง แม้ระบบจะมาร์ก is_paid ให้
      // อัตโนมัติตอนออกบิลก็ตาม (ดู updateRepairBill() ด้านบน) เพราะลูกค้าไม่ได้
      // จ่ายเงินจริง
      final isWarrantyCovered =
          r['is_warranty_covered'] == true || r['is_warranty_covered'] == 1;
      if (!isWarrantyCovered && (r['is_paid'] == 1 || r['is_paid'] == true)) {
        totalRevenue += toDoubleOrNull(r['total_price']) ?? 0;
      }
    }

    return {
      'total': all.length,
      'pending': unassigned,
      'scheduled_pending': scheduledPending,
      'in_progress': inProgress,
      'overdue': overdue,
      'completed': completed,
      'problem': problem, // 🔴 เพิ่มฟิลด์ problem
      'total_revenue': totalRevenue,
    };
  }

  Future<int> updateRepairStatus(
    dynamic id,
    String status, {
    String? techUsername,
    String? reportSummary,
    double? progress,
  }) async {
    if (id == null || status.trim().isEmpty) {
      throw const FormatException('สถานะงานซ่อมต้องไม่ว่าง');
    }
    if (progress != null) {
      if (progress < 0 || progress > 1) {
        throw const FormatException('ความคืบหน้าต้องอยู่ระหว่าง 0 ถึง 1');
      }
    }
    Map<String, dynamic> values = {'status': status.trim()};
    if (techUsername != null) values['technician_username'] = techUsername;
    if (reportSummary != null) values['report_summary'] = reportSummary;
    if (progress != null) values['progress'] = progress;
    final result = await _updateById('repairs', id, values);

    if (status.trim() == 'เสร็จแล้ว' || status.trim() == 'เสร็จสิ้น') {
      unawaited(_maybeTriggerRatingPrompt(id));
    }
    return result;
  }

  Future<void> _maybeTriggerRatingPrompt(dynamic id) async {
    try {
      final repair = await getRepairById(id);
      if (repair == null) return;
      if (repair['rating_stars'] != null) return;
      if (repair['rating_notified'] == true) return;

      await _updateById('repairs', id, {
        'rating_eligible': true,
        'rating_notified': true,
        'rating_eligible_at': DateTime.now().toIso8601String(),
      });

      final customerUsername = repair['customer_username']?.toString() ?? '';
      final ticketNo = repair['ticketNo']?.toString() ?? '';
      if (customerUsername.isEmpty) return;

      await createNotification({
        'user_username': customerUsername,
        'role': 'CUSTOMER',
        'title': 'ให้คะแนนช่างซ่อม',
        'message': 'งานซ่อม $ticketNo เสร็จเรียบร้อยแล้ว ช่วยให้คะแนนช่างซ่อมหน่อยนะ',
        'type': 'RATE_TECHNICIAN',
        'target_id': id,
        'is_read': 0,
      });
    } catch (_) {}
  }

  Future<int> submitTechnicianRating(
    dynamic repairId,
    int stars, {
    String comment = '',
  }) async {
    if (repairId == null) throw const FormatException('รหัสงานซ่อมไม่ถูกต้อง');
    if (stars < 1 || stars > 5) {
      throw const FormatException('คะแนนต้องอยู่ระหว่าง 1 ถึง 5 ดาว');
    }
    final repair = await getRepairById(repairId);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    if (repair['rating_stars'] != null) {
      throw StateError('งานนี้ถูกประเมินไปแล้ว');
    }
    return await _updateById('repairs', repairId, {
      'rating': stars,
      'rating_stars': stars,
      'rating_comment': comment.trim(),
      'rating_technician_username': repair['technician_username'],
      'rated_at': DateTime.now().toIso8601String(),
      'rating_eligible': false,
    });
  }

  Future<Map<String, dynamic>> getTechnicianRatingStats() async {
    final all = await getAllRepairs();
    final rated =
        all.where((r) => r['rating_stars'] != null).toList(growable: false);

    final distribution = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    double sum = 0;
    final Map<String, List<int>> byTechnician = {};

    for (final r in rated) {
      final stars = (_toInt(r['rating_stars']) ?? 0).clamp(1, 5);
      distribution[stars] = (distribution[stars] ?? 0) + 1;
      sum += stars;

      final tech = (r['rating_technician_username'] ??
              r['technician_username'])
          ?.toString() ??
          '';
      if (tech.isEmpty) continue;
      byTechnician.putIfAbsent(tech, () => []).add(stars);
    }

    final technicianStats = <Map<String, dynamic>>[];
    for (final entry in byTechnician.entries) {
      final scores = entry.value;
      final avg = scores.reduce((a, b) => a + b) / scores.length;
      technicianStats.add({
        'technician_username': entry.key,
        'average': avg,
        'count': scores.length,
      });
    }
    technicianStats.sort(
        (a, b) => (b['average'] as double).compareTo(a['average'] as double));

    return {
      'total_rated': rated.length,
      'average': rated.isEmpty ? 0.0 : sum / rated.length,
      'distribution': distribution,
      'by_technician': technicianStats,
    };
  }

  Future<int> updateRepair(dynamic id, Map<String, dynamic> data) =>
      _updateById('repairs', id, data);

  // 🆕 [ใหม่] เพิ่มพารามิเตอร์ photoUrls (URL รูปที่อัปโหลดขึ้น Cloudinary แล้ว
  // จากฝั่งเรียก ไม่ใช่ path ไฟล์ในเครื่อง) เก็บเป็น String เดียวคั่นด้วยจุลภาค
  // ในฟิลด์ "problem_photos" — ใช้รูปแบบเดียวกับฟิลด์ "images" ของฟอร์มแจ้งซ่อม
  // ลูกค้า (repair_form.dart) เพื่อให้ฝั่งเว็บอ่านได้ตรงกันแบบเดียวกันทั้งแอป
  // (ดู getProblemPhotos()/getIssueReport() ใน JobDetailModal.jsx ฝั่งเว็บที่
  // แก้ให้รองรับรูปแบบนี้คู่กันแล้ว)
  Future<int> markRepairProblem(
    dynamic id, {
    required String techUsername,
    String? note,
    List<String> photoUrls = const [],
  }) async {
    if (id == null) throw const FormatException('รหัสงานซ่อมไม่ถูกต้อง');
    final repair = await getRepairById(id);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final currentStatus = repair['status']?.toString() ?? 'กำลังซ่อม';
    return await _updateById('repairs', id, {
      'status': 'มีปัญหา',
      'status_before_problem': currentStatus,
      'problem_note': (note?.trim().isNotEmpty ?? false) ? note!.trim() : '',
      'problem_photos': photoUrls.isNotEmpty ? photoUrls.join(',') : '',
      'problem_reported_by': techUsername,
      'problem_reported_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> resolveRepairProblem(dynamic id) async {
    if (id == null) throw const FormatException('รหัสงานซ่อมไม่ถูกต้อง');
    final repair = await getRepairById(id);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final previousStatus =
        repair['status_before_problem']?.toString() ?? 'กำลังซ่อม';
    return await _updateById('repairs', id, {
      'status': previousStatus,
      'status_before_problem': null,
      'problem_note': null,
      'problem_photos': null,
    });
  }

  // 🆕 [ใหม่] เพิ่มพารามิเตอร์ isWarrantyCovered — ถ้าเครื่องจักรยังอยู่ในประกัน
  // ช่างยังกรอกราคา/รายการค่าใช้จ่ายในบิลได้ตามปกติ (เก็บไว้เป็นหลักฐาน/บันทึก
  // ต้นทุนภายใน) แต่ลูกค้าไม่ต้องจ่ายเงินจริง — มาร์กบิลนี้เป็น "ชำระแล้ว" ทันที
  // โดยไม่ต้องรอลูกค้าส่งสลิปโอนเงิน/แอดมินกดยืนยันแบบบิลปกติ แล้วแยกด้วยฟิลด์
  // is_warranty_covered เพื่อไม่ให้ยอดนี้ถูกนับรวมเป็นรายได้จริงตอนสรุปที่
  // getAdminDashboardSummary() ด้านบน และเพื่อให้หน้าจอฝั่งลูกค้า/แอดมินแสดงข้อความ
  // "ไม่มีค่าใช้จ่ายเพราะมีประกัน" แทนปุ่มชำระเงิน/QR code ได้ถูกจุด
  Future<int> updateRepairBill(
    dynamic id, {
    required String billId,
    required double totalPrice,
    String? invoiceNo,
    bool isWarrantyCovered = false,
    // 🐛 [แก้บัค] เดิมฟังก์ชันนี้บันทึกแค่ยอดรวม (total_price) ลง Firebase
    // ไม่มีรายการอะไหล่/ค่าแรง ไม่มี subtotal/ส่วนลด/ภาษี เลย ทั้งที่หน้าออกบิล
    // ในแอป (admin_create_invoice.dart) คำนวณครบอยู่แล้ว — ผลคือใบแจ้งหนี้ที่
    // ออกจากแอปไปเปิดดูฝั่งเว็บ (FinancePage.jsx/JobDetailModal.jsx) เห็นแต่
    // ยอดรวมอย่างเดียว ไม่มีรายละเอียดเหมือนใบแจ้งหนี้ที่ออกจากเว็บเอง — เพิ่ม
    // พารามิเตอร์รับรายละเอียดบิลมาบันทึกด้วยชื่อฟิลด์เดียวกับที่เว็บใช้
    // (invoice_items/invoice_subtotal/invoice_discount/invoice_vat_amount/
    // invoice_wht_amount ดู nextInvoiceNumber()/handleSave() ใน
    // aftersales-web/src/pages/FinancePage.jsx) เพื่อให้บิลจากทั้งสองฝั่งอ่าน
    // ข้อมูลชุดเดียวกันได้ครบเหมือนกัน
    List<Map<String, dynamic>>? items,
    double? subtotal,
    double? discount,
    double? vatAmount,
    double? whtAmount,
  }) async {
    if (id == null || billId.trim().isEmpty || totalPrice < 0) {
      throw const FormatException('ข้อมูลใบแจ้งหนี้ไม่ถูกต้อง');
    }
    if (await getRepairById(id) == null) {
      throw StateError('ไม่พบงานซ่อมสำหรับออกใบแจ้งหนี้');
    }
    final now = DateTime.now().toIso8601String();
    final values = <String, dynamic>{
      'bill_id': billId.trim(),
      // 🐛 [แก้บัค] เดิมเติม 'INV-' นำหน้า billId ซ้ำอีกชั้น ทั้งที่ billId ที่ส่ง
      // เข้ามา (ค่าเริ่มต้นจาก _invoiceNumberController ใน
      // admin_create_invoice.dart) ก็ขึ้นต้นด้วย 'INV-' อยู่แล้ว ทำให้เลขที่บิล
      // กลายเป็น 'INV-INV-xxxxx' (เห็น "INV INV" ซ้ำกันตอนออกบิลจากแอป) — ใช้
      // billId ตรง ๆ แทน (invoiceNo ที่ส่งมาเอง ถ้ามี ยังคงเคารพค่านั้นก่อนเสมอ)
      'invoice_no': (invoiceNo?.trim().isNotEmpty ?? false)
          ? invoiceNo!.trim()
          : billId.trim(),
      'invoice_date': now,
      'total_price': totalPrice,
      'is_warranty_covered': isWarrantyCovered,
    };
    if (items != null) values['invoice_items'] = items;
    if (subtotal != null) values['invoice_subtotal'] = subtotal;
    if (discount != null) values['invoice_discount'] = discount;
    if (vatAmount != null) values['invoice_vat_amount'] = vatAmount;
    if (whtAmount != null) values['invoice_wht_amount'] = whtAmount;
    if (isWarrantyCovered) {
      values['is_paid'] = 1;
      values['receipt_no'] = 'WARRANTY-${billId.trim()}';
    }
    return await _updateById('repairs', id, values);
  }

  Future<int> markRepairPaid(dynamic id, {String? receiptNo}) async {
    final generatedReceiptNo =
        receiptNo ?? 'RC-${DateTime.now().millisecondsSinceEpoch}';
    final result = await _updateById('repairs', id, {
      'is_paid': 1,
      'receipt_no': generatedReceiptNo,
    });
    unawaited(_maybeTriggerRatingPrompt(id));
    return result;
  }

  Future<int> submitPaymentSlip(dynamic id, String slipPhotoUrl) async {
    return await _updateById('repairs', id, {
      'customer_payment_slip': slipPhotoUrl,
      'payment_slip_uploaded_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> setRepairUrgent(dynamic id, bool isUrgent) =>
      _updateById('repairs', id, {'is_urgent': isUrgent});

  Future<int> deleteRepair(dynamic id) => _deleteById('repairs', id);

  Future<void> deleteRepairByKey(String key) => _deleteByKey('repairs', key);

  Future<int> submitRepairReport({
    required dynamic repairId,
    required String formCode,
    required String beforePhotoPath,
    required String afterPhotoPath,
    required String slipPhotoPath,
    required String problemDetail,
  }) async {
    final result = await _updateById('repairs', repairId, {
      'report_form_code': formCode,
      'report_before_photo': beforePhotoPath,
      'report_after_photo': afterPhotoPath,
      'report_slip_photo': slipPhotoPath,
      'report_problem_detail': problemDetail,
      'report_submitted_at': DateTime.now().toIso8601String(),
      'status': 'เสร็จแล้ว',
      'progress': 1.0,
    });
    unawaited(_maybeTriggerRatingPrompt(repairId));
    return result;
  }

  Future<Map<String, dynamic>?> getRepairReport(dynamic repairId) async {
    final row = await getRepairById(repairId);
    if (row == null) return null;
    if (row['report_submitted_at'] == null) return null;
    return row;
  }

  // ==========================================
  // 5. ระบบจัดการเครื่องจักร (MACHINES)
  // ==========================================

  Future<List<Map<String, dynamic>>> getMachines() async =>
      _sortById(await _all('machines'), desc: true);

  Future<List<Map<String, dynamic>>> getMachinesForCustomer(String username) =>
      _where('machines', (r) => r['customer_username'] == username);

  Future<Map<String, dynamic>?> getMachineById(dynamic id) => _byId('machines', id);

  Future<Map<String, dynamic>?> getMachineBySerialNumber(
    String serialNumber, {
    String? customerUsername,
  }) async {
    final normalized = normalizeSerialNumber(serialNumber);
    if (normalized.isEmpty) return null;

    final rows = await _where('machines', (r) {
      final rowSerial = r['serial_number']?.toString() ?? '';
      if (normalizeSerialNumber(rowSerial) != normalized) return false;
      if (customerUsername != null && customerUsername.isNotEmpty) {
        return r['customer_username'] == customerUsername;
      }
      return true;
    });
    return rows.isNotEmpty ? rows.first : null;
  }

  Future<int> createMachine(Map<String, dynamic> data) async {
    await _validateMachineData(data, requireOwner: true);
    return _insert('machines', data);
  }

  Future<int> updateMachine(dynamic id, Map<String, dynamic> data) async {
    await _validateMachineData(data, excludeMachineId: id);
    return _updateById('machines', id, data);
  }

  Future<void> _validateMachineData(
    Map<String, dynamic> data, {
    bool requireOwner = false,
    dynamic excludeMachineId,
  }) async {
    final owner = data['customer_username']?.toString().trim() ?? '';
    final serial = normalizeSerialNumber(data['serial_number']?.toString() ?? '');
    final model = data['model_name']?.toString().trim() ?? '';

    if (requireOwner && owner.isEmpty) {
      throw const FormatException('ต้องระบุเจ้าของเครื่องจักร');
    }
    if (data.containsKey('serial_number') && serial.isEmpty) {
      throw const FormatException('Serial Number ต้องไม่ว่าง');
    }
    if (data.containsKey('serial_number') &&
        serial.isNotEmpty &&
        !isValidSerialNumber(serial)) {
      throw FormatException(serialNumberFormatError);
    }
    if (data.containsKey('model_name') && model.isEmpty) {
      throw const FormatException('รุ่นเครื่องจักรต้องไม่ว่าง');
    }

    if (data.containsKey('serial_number')) {
      data['serial_number'] = serial;

      final duplicate = await _where('machines', (row) {
        final rowSerial =
            normalizeSerialNumber(row['serial_number']?.toString() ?? '');
        if (rowSerial != serial) return false;
        final rowId = row['id']?.toString();
        final excludeIdStr = excludeMachineId?.toString();
        return excludeIdStr == null || rowId != excludeIdStr;
      });
      if (duplicate.isNotEmpty) {
        throw StateError('Serial Number นี้ถูกใช้งานแล้ว');
      }
    }

    final warrantyMonths = data['warranty_months'];
    if (warrantyMonths is num && warrantyMonths < 0) {
      throw const FormatException('ระยะเวลาประกันต้องไม่ติดลบ');
    }
    if (warrantyMonths is num &&
        warrantyMonths > 0 &&
        data.containsKey('warranty_start_date') &&
        data['warranty_start_date'] == null) {
      throw const FormatException('ต้องระบุวันที่เริ่มประกัน');
    }
  }

  Future<int> deleteMachine(dynamic id) => _deleteById('machines', id);

  // ==========================================
  // 6. ระบบจัดการอะไหล่ (SPARE PARTS)
  // ==========================================

  Future<List<Map<String, dynamic>>> getSpareParts() async =>
      _sortById(await _all('spare_parts'));

  Future<Map<String, dynamic>?> getSparePartById(dynamic id) =>
      _byId('spare_parts', id);

  Future<int> createSparePart(Map<String, dynamic> data) async {
    _validateSparePartData(data, requireName: true);
    return _insert('spare_parts', data);
  }

  Future<int> updateSparePart(dynamic id, Map<String, dynamic> data) async {
    if (id == null) {
      throw const FormatException('รหัสอะไหล่ไม่ถูกต้อง');
    }
    _validateSparePartData(data);
    return _updateById('spare_parts', id, data);
  }

  void _validateSparePartData(
    Map<String, dynamic> data, {
    bool requireName = false,
  }) {
    final name = data['part_name']?.toString().trim() ?? '';
    if (requireName && name.isEmpty) {
      throw const FormatException('ชื่ออะไหล่ต้องไม่ว่าง');
    }
    if (data.containsKey('part_name') && name.isEmpty) {
      throw const FormatException('ชื่ออะไหล่ต้องไม่ว่าง');
    }

    final price = data['price'];
    if (price is num && (!price.isFinite || price < 0)) {
      throw const FormatException('ราคาอะไหล่ต้องไม่ติดลบ');
    }
    if (price != null && price is! num) {
      throw const FormatException('ราคาอะไหล่ต้องเป็นตัวเลข');
    }

    final stock = data['stock'];
    if (stock is num && (!stock.isFinite || stock < 0 || stock % 1 != 0)) {
      throw const FormatException('สต็อกอะไหล่ต้องเป็นจำนวนเต็มไม่ติดลบ');
    }
    if (stock != null && stock is! num) {
      throw const FormatException('สต็อกอะไหล่ต้องเป็นตัวเลข');
    }
  }

  Future<int> updateSparePartStock(dynamic partId, int quantityUsed) async {
    if (quantityUsed <= 0 || partId == null) return 0;
    final key = _k(partId);
    final ref = _root.child('spare_parts/$key/stock');
    final result = await ref.runTransaction((Object? current) {
      final currentStock = toIntOrNull(current) ?? 0;
      if (currentStock < quantityUsed) {
        return Transaction.abort();
      }
      return Transaction.success(currentStock - quantityUsed);
    });
    return result.committed ? 1 : 0;
  }

  Future<int> deleteSparePart(dynamic id) => _deleteById('spare_parts', id);

  // ==========================================
  // 6.1 ระบบคำขอเบิกอะไหล่ (PART REQUESTS)
  // ==========================================

  Future<int> createPartRequest({
    required String technicianUsername,
    required dynamic partId,
    required String partName,
    String? partCode,
    required int quantity,
    String? note,
    dynamic repairId,
  }) {
    if (technicianUsername.trim().isEmpty || quantity <= 0) {
      throw const FormatException('ชื่อช่างและจำนวนอะไหล่ต้องถูกต้อง');
    }
    return _insert('part_requests', {
      'technician_username': technicianUsername.trim(),
      'part_id': partId,
      'part_name': partName,
      'part_code': partCode,
      'quantity': quantity,
      'status': 'รอดำเนินการ',
      'note': note,
      'repair_id': repairId,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getPartRequestsByTechnician(
          String username) =>
      _where('part_requests', (r) => r['technician_username'] == username,
          desc: true);

  Future<List<Map<String, dynamic>>> getAllPartRequests() async =>
      _sortById(await _all('part_requests'), desc: true);

  Future<List<Map<String, dynamic>>> getApprovedPartRequestsForRepair(
          dynamic repairId) =>
      _where(
        'part_requests',
        (r) =>
            r['repair_id']?.toString() == repairId?.toString() &&
            r['status'] == 'อนุมัติแล้ว',
        desc: true,
      );

  /// 🆕 [ใหม่] คำขอเบิกอะไหล่ "ทุกสถานะ" ของงานซ่อมนี้ — ใช้เช็คว่ายังมีคำขอที่
  /// รอดำเนินการ (แอดมินยังไม่อนุมัติ/ปฏิเสธ) ค้างอยู่หรือไม่ ก่อนอนุญาตให้
  /// ออกบิล (ดู _canIssueInvoice ใน assign_repair_formdetail.dart) — ต่างจาก
  /// getApprovedPartRequestsForRepair() ด้านบนที่กรองเอาเฉพาะที่อนุมัติแล้ว
  Future<List<Map<String, dynamic>>> getPartRequestsForRepair(
          dynamic repairId) =>
      _where(
        'part_requests',
        (r) => r['repair_id']?.toString() == repairId?.toString(),
        desc: true,
      );

  Future<int> updatePartRequestStatus(dynamic id, String status) =>
      _updateById('part_requests', id, {'status': status});

  Future<int> deletePartRequest(dynamic id) => _deleteById('part_requests', id);

  // ==========================================
  // 7. ระบบการชำระเงิน (PAYMENTS)
  // ==========================================

  Future<int> createPayment(Map<String, dynamic> data) async {
    final record = Map<String, dynamic>.from(data);
    final repairId = record['repair_id'];
    if (repairId == null || repairId.toString().isEmpty) {
      throw const FormatException('ต้องระบุงานซ่อมของการชำระเงิน');
    }
    if (await getRepairById(repairId) == null) {
      throw StateError('ไม่พบงานซ่อมสำหรับการชำระเงิน');
    }
    for (final field in ['amount', 'total_price']) {
      final value = record[field];
      if (value is num && (!value.isFinite || value < 0)) {
        throw const FormatException('จำนวนเงินต้องไม่ติดลบ');
      }
      if (value != null && value is! num) {
        throw const FormatException('จำนวนเงินต้องเป็นตัวเลข');
      }
    }
    record['payment_date'] ??= DateTime.now().toIso8601String();
    record['receipt_no'] ??= 'RC-${DateTime.now().millisecondsSinceEpoch}';
    return await _insert('payments', record);
  }

  Future<List<Map<String, dynamic>>> getAllPayments() async =>
      _sortById(await _all('payments'), desc: true);

  Future<Map<String, dynamic>?> getLatestPaymentForRepair(dynamic repairId) async {
    final rows = await _where(
        'payments', (r) => r['repair_id']?.toString() == repairId?.toString(),
        desc: true);
    return rows.isNotEmpty ? rows.first : null;
  }

  // ==========================================
  // 8. ระบบข้อความแชท (CHAT MESSAGES)
  // ==========================================

  Future<int> sendChatMessage(Map<String, dynamic> data) async {
    final record = Map<String, dynamic>.from(data);
    final repairId = record['repair_id'];
    final sender = record['sender_username']?.toString().trim() ?? '';
    final message = record['message']?.toString().trim() ?? '';
    final imagePath = record['image_path']?.toString().trim() ?? '';
    if (repairId == null ||
        repairId.toString().isEmpty ||
        sender.isEmpty ||
        (message.isEmpty && imagePath.isEmpty)) {
      throw const FormatException('ข้อมูลข้อความแชทไม่ถูกต้อง');
    }
    record['sender_username'] = sender;
    record['created_at'] ??= DateTime.now().toIso8601String();
    return await _insert('chat_messages', record);
  }

  Future<int> editChatMessage(dynamic messageId, String newText) async {
    if (messageId == null || newText.trim().isEmpty) {
      throw const FormatException('ข้อความใหม่ต้องไม่ว่าง');
    }
    return _updateById('chat_messages', messageId, {
      'message': newText.trim(),
      'is_edited': 1,
    });
  }

  Future<int> deleteChatMessage(dynamic messageId) {
    if (messageId == null) {
      throw const FormatException('รหัสข้อความไม่ถูกต้อง');
    }
    return _updateById('chat_messages', messageId, {
      'is_deleted': 1,
      'message': '',
      'image_path': null,
    });
  }

  Future<List<Map<String, dynamic>>> getChatMessages(dynamic repairId) =>
      _where('chat_messages', (r) => r['repair_id']?.toString() == repairId?.toString());

  Stream<List<Map<String, dynamic>>> watchChatMessages(dynamic repairId) =>
      _streamWhere('chat_messages', (r) => r['repair_id']?.toString() == repairId?.toString());

  Future<int> getUnreadChatCount(dynamic repairId, String currentUsername) async {
    final rows = await _where('chat_messages', (r) {
      return r['repair_id']?.toString() == repairId?.toString() &&
          r['sender_username'] != currentUsername &&
          (r['is_read'] == 0 || r['is_read'] == null || r['is_read'] == false);
    });
    return rows.length;
  }

  Future<Map<String, dynamic>?> getLastChatMessage(dynamic repairId) async {
    final rows = await _where(
        'chat_messages', (r) => r['repair_id']?.toString() == repairId?.toString(),
        desc: true);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> markChatAsRead(dynamic repairId, String currentUsername) async {
    final targetStr =
        repairId?.toString().replaceFirst(RegExp(r'^[kK]'), '') ?? '';
    final userNorm = currentUsername.trim().toLowerCase();

    if (targetStr.isNotEmpty) {
      await _updateWhere(
        'notifications',
        (r) {
          final u = r['user_username']?.toString().trim().toLowerCase() ?? '';
          final t = r['type']?.toString().trim().toUpperCase() ?? '';
          final tid = r['target_id']
                  ?.toString()
                  .replaceFirst(RegExp(r'^[kK]'), '') ??
              '';
          return u == userNorm && t == 'CHAT' && tid == targetStr;
        },
        {'is_read': 1},
      );
    }

    return await _updateWhere(
      'chat_messages',
      (r) {
        final rId = r['repair_id']
                ?.toString()
                .replaceFirst(RegExp(r'^[kK]'), '') ??
            '';
        final sender =
            r['sender_username']?.toString().trim().toLowerCase() ?? '';
        return rId == targetStr && sender != userNorm;
      },
      {'is_read': 1},
    );
  }

  Future<void> markChatRead(
      dynamic repairId, String username, dynamic lastReadMessageId) async {
    await _root.child('chat_read_status/${repairId}_$username').set({
      'repair_id': repairId,
      'username': username,
      'last_read_message_id': lastReadMessageId,
    });
    await markChatAsRead(repairId, username);
  }

  Future<Map<String, int>> getChatReadStatus(dynamic repairId) async {
    final all = await _all('chat_read_status');
    final result = <String, int>{};
    for (final row in all) {
      if (row['repair_id']?.toString() != repairId?.toString()) continue;
      final username = row['username']?.toString();
      if (username == null) continue;
      result[username] = _toInt(row['last_read_message_id']) ?? 0;
    }
    return result;
  }

  Future<int> deleteChatMessages(dynamic repairId) async {
    final readStatusRows = await _where('chat_read_status',
        (r) => r['repair_id']?.toString() == repairId?.toString());
    for (final row in readStatusRows) {
      final username = row['username']?.toString();
      if (username == null) continue;
      await _root.child('chat_read_status/${repairId}_$username').remove();
    }

    return await _deleteWhere(
        'chat_messages', (r) => r['repair_id']?.toString() == repairId?.toString());
  }

  Future<int> getUnreadChatRoomCount(String username, String roleKey) async {
    List<Map<String, dynamic>> repairs;
    switch (roleKey) {
      case 'CUSTOMER':
        repairs =
            await _where('repairs', (r) => r['customer_username'] == username);
        break;
      case 'TECHNICIAN':
        repairs = await _where(
            'repairs', (r) => r['technician_username'] == username);
        break;
      default:
        repairs = await _all('repairs');
    }
    if (repairs.isEmpty) return 0;

    final ids = repairs.map((r) => r['id']?.toString() ?? '').toSet();
    final messages = await _all('chat_messages');
    final unreadRoomIds = <String>{};
    for (final m in messages) {
      final repairId = m['repair_id']?.toString();
      if (repairId == null || !ids.contains(repairId)) continue;
      if (m['sender_username'] == username) continue;
      if (m['is_read'] == 1 || m['is_read'] == true) continue;
      unreadRoomIds.add(repairId);
    }
    return unreadRoomIds.length;
  }

  // ==========================================
  // 9. ระบบการแจ้งเตือน (NOTIFICATIONS)
  // ==========================================

  Future<int> createNotification(Map<String, dynamic> data) async {
    final record = Map<String, dynamic>.from(data);
    final rawPushData = record.remove('push_data');
    final pushData = rawPushData == null
        ? null
        : rawPushData is Map
            ? Map<String, dynamic>.from(rawPushData)
            : throw const FormatException('ข้อมูล push_data ไม่ถูกต้อง');

    final username = record['user_username']?.toString().trim() ?? '';
    final title = record['title']?.toString().trim() ?? '';
    final message = record['message']?.toString().trim() ?? '';
    final type = record['type']?.toString().trim().toUpperCase() ?? '';
    final targetId = record['target_id']?.toString() ?? '';

    if (username.isEmpty || title.isEmpty || message.isEmpty) {
      throw const FormatException('ข้อมูลแจ้งเตือนไม่ครบถ้วน');
    }
    record['user_username'] = username;
    record['title'] = title;
    record['message'] = message;
    record['created_at'] = DateTime.now().toIso8601String();
    record['is_read'] = 0;

    int id = 0;

    // 🐛 [แก้ race + cross-platform] เดิมรวมแจ้งเตือนแชทด้วยการ _all() ทั้งตารางแล้ว
    // ค่อยเขียน (read-modify-write ไม่ atomic) — ยิงข้อความรัว ๆ หรือหลายฝั่งพร้อมกัน
    // ทำให้ dedup หลุดแล้วได้แจ้งเตือนซ้ำ เปลี่ยนมาใช้คีย์กำหนดเอง CHAT_{user}_{target}
    // + set() ให้ทุก writer ชนที่ record เดียวกันเสมอ (คีย์เดียวกับฝั่งเว็บ
    // firebaseDb.js createNotification จึงยุบข้ามแพลตฟอร์มด้วย) ตัด k นำหน้า target
    // ออกให้ตรงกับที่เว็บส่ง Firebase key (k37) มา
    if (type == 'CHAT' && targetId.isNotEmpty) {
      final cleanTarget = targetId.replaceFirst(RegExp(r'^[kK]'), '');
      final chatKey = 'CHAT_${username}_$cleanTarget';
      record['id'] = chatKey;
      await _root.child('notifications/$chatKey').set(record);
    } else {
      id = await _insert('notifications', record);
    }

    final pushUsername = record['user_username']?.toString();
    final pushTitle = record['title']?.toString();
    final pushMessage = record['message']?.toString();
    if (pushUsername != null && pushTitle != null && pushMessage != null) {
      final Map<String, dynamic> payloadData = pushData ?? {
        'type': type,
        'target_id': targetId,
        'repair_id': targetId,
      };

      PushNotificationService.sendToUser(
        username: pushUsername,
        title: pushTitle,
        message: pushMessage,
        additionalData: payloadData,
        collapseId: type == 'CHAT' && targetId.isNotEmpty ? 'chat_$targetId' : null,
      );
    }

    return id;
  }

  Future<List<Map<String, dynamic>>> getNotificationsForUser(String username) async {
    final rows = await _where('notifications', (r) => r['user_username'] == username, desc: true);

    // 🟢 ยุบรวมการแจ้งเตือนแชทที่ยังไม่อ่านของห้องเดียวกันให้เหลือแถวเดียวบนหน้าจอเสมอ
    final seenUnreadChatRooms = <String>{};
    final result = <Map<String, dynamic>>[];

    for (final row in rows) {
      final type = row['type']?.toString().trim().toUpperCase() ?? '';
      final targetId = row['target_id']?.toString().trim() ?? '';
      final isRead = row['is_read'] == 1 || row['is_read'] == true;

      if (type == 'CHAT' && targetId.isNotEmpty && !isRead) {
        if (seenUnreadChatRooms.contains(targetId)) {
          continue; // ข้ามรายการซ้ำอันเก่า
        }
        seenUnreadChatRooms.add(targetId);
      }
      result.add(row);
    }

    return result;
  }

  Future<int> getUnreadNotificationCount(String username) async {
    final list = await getNotificationsForUser(username);
    return list.where((r) => r['is_read'] == 0 || r['is_read'] == null || r['is_read'] == false).length;
  }

  Future<int> getUnreadNotificationCountByType(
      String username, String type) async {
    final rows = await getNotificationsForUser(username);
    return rows.where((r) =>
        r['type'] == type &&
        (r['is_read'] == 0 || r['is_read'] == null || r['is_read'] == false)).length;
  }

  Future<int> markNotificationAsRead(dynamic notificationId) async {
    if (notificationId == null) return 0;
    final targetStr = notificationId.toString().trim();
    final targetClean = targetStr.replaceFirst(RegExp(r'^[kK]'), '');

    return await _updateWhere(
      'notifications',
      (r) {
        final fbKey = r['_fbKey']?.toString().trim() ?? '';
        final idStr = r['id']?.toString().trim() ?? '';
        final idClean = idStr.replaceFirst(RegExp(r'^[kK]'), '');
        return fbKey == targetStr ||
            idStr == targetStr ||
            idClean == targetClean;
      },
      {'is_read': 1},
    );
  }

  Future<int> markAllNotificationsAsRead(String username) => _updateWhere(
      'notifications', (r) => r['user_username'] == username, {'is_read': 1});

  Future<int> deleteNotification(dynamic id) async {
    if (id == null) return 0;
    final targetStr = id.toString().trim();
    final targetClean = targetStr.replaceFirst(RegExp(r'^[kK]'), '');

    return await _deleteWhere(
      'notifications',
      (r) {
        final fbKey = r['_fbKey']?.toString().trim() ?? '';
        final idStr = r['id']?.toString().trim() ?? '';
        final idClean = idStr.replaceFirst(RegExp(r'^[kK]'), '');
        return fbKey == targetStr ||
            idStr == targetStr ||
            idClean == targetClean;
      },
    );
  }

  Future<int> deleteAllNotifications(String username) =>
      _deleteWhere('notifications', (r) => r['user_username'] == username);

  Future<int> deleteExpiredNotifications(String username,
      {int days = 30}) async {
    final cutoff =
        DateTime.now().subtract(Duration(days: days)).toIso8601String();
    return await _deleteWhere(
        'notifications',
        (r) =>
            r['user_username'] == username &&
            (r['created_at']?.toString() ?? '').compareTo(cutoff) < 0);
  }
}