import 'dart:async' show unawaited;
import 'package:firebase_database/firebase_database.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/utils/serial_number.dart';
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

/// คำนวณสถานะที่แท้จริงของงานซ่อมตามวันที่นัดหมายอัตโนมัติ
String getEffectiveRepairStatus(Map<String, dynamic> repair) {
  final rawStatus = (repair['status'] as String?)?.trim() ?? 'รอจัดสรรช่าง';

  if (rawStatus == 'มีปัญหา' ||
      rawStatus.contains('ปัญหา') ||
      rawStatus == 'เสร็จแล้ว' ||
      rawStatus == 'เสร็จสิ้น' ||
      rawStatus.contains('ยกเลิก')) {
    return rawStatus == 'เสร็จแล้ว' ? 'เสร็จสิ้น' : rawStatus;
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
      return 'กำลังซ่อม';
    case DateComparison.past:
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

  // คัดลอกไปวางแทนที่ฟังก์ชัน _byId เดิมใน lib/services.dart
Future<Map<String, dynamic>?> _byId(String table, dynamic id) async {
  if (id == null) return null;
  final key = _k(id);
  if (key.isEmpty) return null;

  // 1. ลองค้นหาด้วยคีย์ปกติ (เช่น k37)
  DataSnapshot snap = await _root.child('$table/$key').get();

  // 2. ถ้าไม่พบ ให้ลองสลับรูปแบบคีย์ (ตัด 'k' ออก หรือเติม 'k' เข้าไป)
  if (!snap.exists || snap.value == null) {
    final rawId = id.toString().trim();
    final altKey = (rawId.startsWith('k') || rawId.startsWith('K'))
        ? rawId.substring(1)
        : 'k$rawId';
    
    snap = await _root.child('$table/$altKey').get();
    
    // 3. ถ้ายังไม่พบอีก ให้ลองค้นหาด้วยรหัสเดิมแบบตรงๆ
    if (!snap.exists || snap.value == null) {
      snap = await _root.child('$table/$rawId').get();
    }
  }

  if (!snap.exists || snap.value == null) return null;
  
  final row = Map<String, dynamic>.from(snap.value as Map);
  row['_fbKey'] = snap.key ?? key;
  row['id'] ??= snap.key ?? key;
  if (table == 'repairs') {
    row['status'] = getEffectiveRepairStatus(row);
  }
  return row;
}
  Future<List<Map<String, dynamic>>> _all(String table) async {
    final snap = await _root.child(table).get();
    if (!snap.exists || snap.value == null) return [];
    final out = <Map<String, dynamic>>[];
    final raw = snap.value;
    if (raw is Map) {
      for (final entry in raw.entries) {
        final v = entry.value;
        if (v is Map) {
          final row = Map<String, dynamic>.from(v);
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
          final row = Map<String, dynamic>.from(v);
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
            final row = Map<String, dynamic>.from(v);
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
            final row = Map<String, dynamic>.from(v);
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
      final snap = await _root.child('admins').get();
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

    final role = account['role'] as String;
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

  Future<List<Map<String, dynamic>>> getRepairsByCustomer(String username) =>
      _where('repairs', (r) => r['customer_username'] == username, desc: true);

  Stream<List<Map<String, dynamic>>> watchRepairsByCustomer(
          String username) =>
      _streamWhere('repairs', (r) => r['customer_username'] == username,
          desc: true);

  Future<List<Map<String, dynamic>>> getRepairsByTechnician(String username) =>
      _where('repairs', (r) => r['technician_username'] == username,
          desc: true);

  Stream<List<Map<String, dynamic>>> watchRepairsByTechnician(
          String username) =>
      _streamWhere('repairs', (r) => r['technician_username'] == username,
          desc: true);

  Future<List<Map<String, dynamic>>> getRepairsByMachine(int machineId) =>
      _where('repairs', (r) => _toInt(r['machine_id']) == machineId,
          desc: true);

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
      case DateComparison.today:
        initialStatus = 'กำลังซ่อม';
        progress = 0.1;
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

    String? approvalKey(Map<String, dynamic> r) =>
        (r['approved_at'] as String?) ?? (r['created_at'] as String?);

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

    // 🐛 [แก้ไข] เดิม approvalKey คืนค่า '' (string ว่าง) เวลาไม่มีทั้ง
    // approved_at และ created_at ซึ่งพอเทียบด้วย compareTo แล้ว string ว่าง
    // จะเรียงมาก่อน string อื่นเสมอ (เทียบตัวอักษรทีละตัว ว่างแพ้ทุกตัวอักษร)
    // ทำให้งาน "ไม่มีเวลา" แซงคิวไปอยู่อันดับ 1 เสมอไม่ว่าจริง ๆ จะอนุมัติ
    // ทีหลังงานอื่นแค่ไหนก็ตาม — เปลี่ยนมาให้งานที่ไม่มีเวลาบันทึกไว้เลย
    // ("null") ไปอยู่ท้ายคิวแทน (คิวจริงควรมี created_at เสมออยู่แล้วตอน
    // สร้าง record จุดนี้กันไว้เผื่อข้อมูลเก่า/ผิดปกติที่ไม่มีฟิลด์นี้)
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
    final inProgress = all.where((r) => r['status'] == 'กำลังซ่อม' || r['status'] == 'กำลังดำเนินการ').length;
    final overdue = all.where((r) => r['status'] == 'เกินกำหนดเวลา').length;
    final completed = all
        .where((r) => r['status'] == 'เสร็จแล้ว' || r['status'] == 'เสร็จสิ้น')
        .length;

    double totalRevenue = 0.0;
    for (var r in all) {
      if (r['is_paid'] == 1 || r['is_paid'] == true) {
        totalRevenue += (r['total_price'] as num? ?? 0).toDouble();
      }
    }

    return {
      'total': all.length,
      'pending': unassigned,
      'scheduled_pending': scheduledPending,
      'in_progress': inProgress,
      'overdue': overdue,
      'completed': completed,
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

  // 🐛 [แก้บัค] เดิมฟังก์ชันนี้เขียนแค่ 'rating_stars' + 'rating_technician_username'
  // ไม่มี 'rating'/'rating_comment' เลย ทำให้ไม่ตรงกับฟิลด์ที่หน้าจอจริง
  // (_submitRating ใน customer_job_detail.dart) ใช้งานอยู่ — ถ้าถูกเรียกใช้จริง
  // ในอนาคตจะได้ข้อมูลไม่ครบ (เว็บ/รายงานที่คาดหวัง rating, rating_comment จะ
  // ไม่เห็นค่า) จึงปรับให้เขียนฟิลด์ชุดเดียวกับ flow จริงเป๊ะ ๆ พร้อมรับ comment
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

  Future<int> markRepairProblem(
    dynamic id, {
    required String techUsername,
    String? note,
  }) async {
    if (id == null) throw const FormatException('รหัสงานซ่อมไม่ถูกต้อง');
    final repair = await getRepairById(id);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final currentStatus = (repair['status'] as String?) ?? 'กำลังซ่อม';
    return await _updateById('repairs', id, {
      'status': 'มีปัญหา',
      'status_before_problem': currentStatus,
      'problem_note': (note?.trim().isNotEmpty ?? false) ? note!.trim() : '',
      'problem_reported_by': techUsername,
      'problem_reported_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> resolveRepairProblem(dynamic id) async {
    if (id == null) throw const FormatException('รหัสงานซ่อมไม่ถูกต้อง');
    final repair = await getRepairById(id);
    if (repair == null) throw StateError('ไม่พบงานซ่อมนี้');
    final previousStatus =
        (repair['status_before_problem'] as String?) ?? 'กำลังซ่อม';
    return await _updateById('repairs', id, {
      'status': previousStatus,
      'status_before_problem': null,
      'problem_note': null,
    });
  }

  Future<int> updateRepairBill(
    dynamic id, {
    required String billId,
    required double totalPrice,
    String? invoiceNo,
  }) async {
    if (id == null || billId.trim().isEmpty || totalPrice < 0) {
      throw const FormatException('ข้อมูลใบแจ้งหนี้ไม่ถูกต้อง');
    }
    if (await getRepairById(id) == null) {
      throw StateError('ไม่พบงานซ่อมสำหรับออกใบแจ้งหนี้');
    }
    final now = DateTime.now().toIso8601String();
    return await _updateById('repairs', id, {
      'bill_id': billId.trim(),
      'invoice_no': (invoiceNo?.trim().isNotEmpty ?? false)
          ? invoiceNo!.trim()
          : 'INV-${billId.trim()}',
      'invoice_date': now,
      'total_price': totalPrice,
    });
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
      final currentStock = (current as num?)?.toInt() ?? 0;
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

    // 🔴 รวมการแจ้งเตือนแชทของห้องเดียวกัน (target_id เดียวกัน) ที่ยังไม่อ่านให้เหลือรายการเดียวใน Firebase
    if (type == 'CHAT' && targetId.isNotEmpty) {
      final allNotifs = await _all('notifications');
      final matching = allNotifs.where((r) {
        final u = r['user_username']?.toString().trim() ?? '';
        final t = r['type']?.toString().trim().toUpperCase() ?? '';
        final tid = r['target_id']?.toString().trim() ?? '';
        final isRead = r['is_read'] == 1 || r['is_read'] == true;
        return u == username && t == 'CHAT' && tid == targetId && !isRead;
      }).toList();

      if (matching.isNotEmpty) {
        final first = matching.first;
        final key = first['_fbKey']?.toString() ?? _k(first['id']);
        if (key.isNotEmpty) {
          await _root.child('notifications/$key').update({
            'title': title,
            'message': message,
            'created_at': record['created_at'],
            'is_read': 0,
          });
          id = _toInt(first['id']) ?? 0;
        }

        // ลบแถวแชทซ้ำอันอื่นออกทั้งหมด
        for (var i = 1; i < matching.length; i++) {
          final dupKey = matching[i]['_fbKey']?.toString() ?? _k(matching[i]['id']);
          if (dupKey.isNotEmpty) {
            await _root.child('notifications/$dupKey').remove();
          }
        }
      } else {
        id = await _insert('notifications', record);
      }
    } else {
      id = await _insert('notifications', record);
    }

    final pushUsername = record['user_username'] as String?;
    final pushTitle = record['title'] as String?;
    final pushMessage = record['message'] as String?;
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