// ==========================================
// SECTION 1: IMPORTS
// ==========================================
import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

// ==========================================
// SECTION 2: DATA MODEL
// ==========================================

/// โมเดลข้อมูลแอดมินหนึ่งคน ([AdminItem]) — ผูกกับตาราง `admins` จริง
class AdminItem {
  final String username;
  final String adminName;
  final String adminCode;
  // 🔴 [ใหม่] 'main' = แอดมินหลัก (ทำได้ทุกอย่าง) / 'general' = แอดมินทั่วไป
  // (เพิ่มแอดมินคนอื่น/จัดสรรงานให้แอดมินคนอื่นไม่ได้) — ค่าว่างหรือค่าอื่นที่ไม่ใช่
  // 'general' ถือเป็น 'main' เสมอ กันแอดมินเก่าก่อนมีฟีเจอร์นี้โดนล็อกสิทธิ์เอง
  final String adminType;

  bool get isMainAdmin => adminType != 'general';

  const AdminItem({
    required this.username,
    required this.adminName,
    required this.adminCode,
    this.adminType = 'main',
  });

  factory AdminItem.fromMap(Map<String, dynamic> map) {
    return AdminItem(
      username: (map['username'] as String?) ?? '',
      adminName: (map['admin_name'] as String?) ?? '-',
      adminCode: (map['admin_code'] as String?) ?? '-',
      adminType: (map['admin_type'] as String?) ?? 'main',
    );
  }
}

// 🆕 [ใหม่] สร้างรหัสแอดมินถัดไปแบบอัตโนมัติ — อ่านตัวเลขต่อท้าย "AD-" ของทุกคน
// ที่มีอยู่ ("AD-001" -> 1) เอาค่ามากที่สุด +1 แล้ว pad เป็น 3 หลัก (เช่น มี
// AD-001 อยู่แล้ว คนต่อไปจะได้ "AD-002") ถ้ายังไม่มีใครใช้รูปแบบนี้เลยจะเริ่มที่
// "AD-001" — ตรรกะเดียวกับฝั่งเว็บ (SettingsPage.jsx nextAdminCode) ห้ามแก้ไข
// ให้ต่างกัน
String _nextAdminCode(List<AdminItem> admins) {
  const prefix = 'AD-';
  final pattern = RegExp(r'^ad-(\d+)$', caseSensitive: false);
  var maxNumber = 0;
  for (final a in admins) {
    final match = pattern.firstMatch(a.adminCode.trim());
    if (match == null) continue;
    final n = int.tryParse(match.group(1)!) ?? 0;
    if (n > maxNumber) maxNumber = n;
  }
  final next = maxNumber + 1;
  return '$prefix${next.toString().padLeft(3, '0')}';
}

// ==========================================
// SECTION 3: MAIN SCREEN WIDGET
// ==========================================

/// {@template manage_admin}
/// หน้าจัดการรายชื่อแอดมินสำหรับผู้ดูแลระบบ ([ManageAdminPage])
///
/// รองรับ: ค้นหา, ดูรายชื่อแอดมินทั้งหมด, เพิ่มแอดมินใหม่, แก้ไข/ลบแอดมิน
/// (กันลบบัญชีของตัวเองที่กำลังใช้งานอยู่ เพื่อไม่ให้ล็อกตัวเองออกจากระบบ)
/// เชื่อมกับตาราง `admins` ผ่าน [DatabaseHelper] โดยตรง
/// {@endtemplate}
class ManageAdminPage extends StatefulWidget {
  const ManageAdminPage({super.key});

  @override
  State<ManageAdminPage> createState() => _ManageAdminPageState();
}

class _ManageAdminPageState extends State<ManageAdminPage> {
  bool _isLoading = true;
  List<AdminItem> _allAdmins = [];
  String _query = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadAdmins();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAdmins() async {
    setState(() => _isLoading = true);
    try {
      final rows = await db.DatabaseHelper.instance.getAllAdmins();
      if (!mounted) return;
      setState(() {
        _allAdmins = rows.map((row) => AdminItem.fromMap(row)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading admins: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('โหลดรายชื่อแอดมินไม่สำเร็จ');
    }
  }

  List<AdminItem> get _filteredAdmins {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allAdmins;
    return _allAdmins.where((a) {
      return a.adminName.toLowerCase().contains(q) ||
          a.username.toLowerCase().contains(q) ||
          a.adminCode.toLowerCase().contains(q);
    }).toList();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddDialog() async {
    // 🆕 [ใหม่] คำนวณรหัสถัดไป + เช็คว่าตอนนี้ยังไม่มีแอดมินเลยหรือไม่ (ถ้าใช่
    // คนที่กำลังจะสร้างนี้จะกลายเป็น "แอดมินหลัก" อัตโนมัติแบบล็อกถาวร — ดู
    // _AdminFormDialogState._save() และ nextAdminCode ด้านบน) ตรรกะเดียวกับ
    // ฝั่งเว็บ (SettingsPage.jsx) เป๊ะ ๆ
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminFormDialog(
        nextAdminCode: _nextAdminCode(_allAdmins),
        isFirstAdmin: _allAdmins.isEmpty,
      ),
    );
    if (result == true) {
      await _loadAdmins();
      _showSnack('เพิ่มแอดมินเรียบร้อย');
    }
  }

  Future<void> _openEditDialog(AdminItem admin) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _AdminFormDialog(existing: admin),
    );
    if (result == true) {
      await _loadAdmins();
      _showSnack('บันทึกการแก้ไขเรียบร้อย');
    }
  }

  Future<void> _confirmDelete(AdminItem admin) async {
    if (admin.username == db.Session.currentUsername) {
      _showSnack('ไม่สามารถลบบัญชีของตัวเองที่กำลังใช้งานอยู่ได้');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบแอดมิน "${admin.adminName}" ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await db.DatabaseHelper.instance.deleteAdmin(admin.username);
        await _loadAdmins();
        _showSnack('ลบ "${admin.adminName}" เรียบร้อยแล้ว');
      } catch (e) {
        debugPrint('Error deleting admin: $e');
        _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
      }
    }
  }

  // ==========================================
  // SECTION 4: BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final admins = _filteredAdmins;

    return Scaffold(
      backgroundColor: AppColors.background,
      // 🔴 [ใหม่] แอดมินทั่วไปห้ามเพิ่มแอดมิน — ซ่อนปุ่ม + เพื่อกันไว้อีกชั้น แม้ว่า
      // ปกติแอดมินทั่วไปจะเข้าหน้านี้ไม่ได้อยู่แล้วเพราะซ่อนเมนูไว้ตั้งแต่
      // home_admin.dart (เผื่อกรณีมีทางเข้าอื่นในอนาคต)
      floatingActionButton: db.Session.isMainAdmin
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: _openAddDialog,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'จัดการแอดมิน', showBack: true),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาชื่อแอดมิน, รหัส หรือ Username...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : admins.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบรายชื่อแอดมิน',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadAdmins,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: admins.length,
                            itemBuilder: (context, index) {
                              final admin = admins[index];
                              final isSelf =
                                  admin.username == db.Session.currentUsername;
                              return _AdminCard(
                                admin: admin,
                                isSelf: isSelf,
                                onEdit: () => _openEditDialog(admin),
                                onDelete: () => _confirmDelete(admin),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SECTION 5: SUB-WIDGETS
// ==========================================

class _AdminCard extends StatelessWidget {
  final AdminItem admin;
  final bool isSelf;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AdminCard({
    required this.admin,
    required this.isSelf,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.admin_panel_settings_outlined,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          admin.adminName,
                          style: const TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (isSelf) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'คุณ',
                              style: TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                fontSize: 10,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                        // 🔴 [ใหม่] badge บอกระดับแอดมิน — โชว์เฉพาะแอดมินทั่วไป
                        // เพื่อไม่ให้รกตา (แอดมินหลักเป็นค่า default อยู่แล้วไม่ต้อง
                        // เน้นซ้ำ)
                        if (!admin.isMainAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'แอดมินทั่วไป',
                              style: TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                fontSize: 10,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${admin.username} • รหัส ${admin.adminCode}',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('แก้ไข'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: isSelf ? null : onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบ'),
                style: TextButton.styleFrom(
                  foregroundColor: isSelf ? Colors.grey : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SECTION 6: เพิ่ม/แก้ไขแอดมิน (Dialog Form)
// ==========================================

class _AdminFormDialog extends StatefulWidget {
  final AdminItem? existing;
  // 🆕 [ใหม่] ค่าที่คำนวณไว้ล่วงหน้าสำหรับตอน "เพิ่มแอดมินใหม่" เท่านั้น (ตอน
  // แก้ไขแอดมินเดิมจะไม่ส่งค่านี้มา ใช้ข้อมูลจาก existing ตามปกติ)
  final String? nextAdminCode;
  final bool isFirstAdmin;

  const _AdminFormDialog({
    this.existing,
    this.nextAdminCode,
    this.isFirstAdmin = false,
  });

  @override
  State<_AdminFormDialog> createState() => _AdminFormDialogState();
}

class _AdminFormDialogState extends State<_AdminFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;

  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _passwordController = TextEditingController();
    _nameController = TextEditingController(text: existing?.adminName ?? '');
    _codeController = TextEditingController(
      // 🆕 [ใหม่] ตอนเพิ่มแอดมินใหม่ ใส่รหัสที่คำนวณอัตโนมัติมาเป็นค่าเริ่มต้น
      // — ตอนแก้ไขยังคงใช้รหัสเดิมของแอดมินคนนั้นเหมือนเดิม
      text: existing?.adminCode ?? widget.nextAdminCode ?? '',
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        // 🆕 [ใหม่] ไม่แนบ 'admin_type' ตอนแก้ไขเด็ดขาด — กันไม่ให้ระดับแอดมิน
        // (แอดมินหลัก/ทั่วไป) ถูกเปลี่ยนผ่านฟอร์มนี้ได้ ตั้งได้ครั้งเดียวตอนสร้าง
        // บัญชีเท่านั้นตามที่ขอ (ตรรกะเดียวกับฝั่งเว็บ SettingsPage.jsx)
        await db.DatabaseHelper.instance.updateAdminProfile(
          widget.existing!.username,
          {
            'admin_name': _nameController.text.trim(),
            'admin_code': _codeController.text.trim(),
          },
        );
      } else {
        final username = _usernameController.text.trim();
        final exists =
            await db.DatabaseHelper.instance.checkUsernameExists(username);
        if (exists) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username นี้ถูกใช้งานแล้ว')),
          );
          return;
        }
        // 🆕 [ใหม่] แอดมินคนแรกสุดของระบบ (ตอนกด "เพิ่มแอดมิน" ยังไม่มีใครเลย)
        // เท่านั้นที่จะได้เป็น "แอดมินหลัก" โดยอัตโนมัติ คนต่อ ๆ ไปเป็นแอดมิน
        // ทั่วไปเสมอ ไม่มีทางเลือกให้ตั้งเองจาก UI — ล็อกถาวร เปลี่ยนภายหลังไม่ได้
        await db.DatabaseHelper.instance.registerAdmin({
          'username': username,
          'password': _passwordController.text.trim(),
          'admin_name': _nameController.text.trim(),
          'admin_code': _codeController.text.trim(),
          'admin_type': widget.isFirstAdmin ? 'main' : 'general',
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving admin: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'แก้ไขข้อมูลแอดมิน' : 'เพิ่มแอดมินใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEditing) ...[
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'กรุณากรอก Username'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'กรุณากรอก Password'
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'ชื่อแอดมิน'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                // 🆕 [ใหม่] ตอนเพิ่มแอดมินใหม่ รหัสถูกสร้างอัตโนมัติแล้ว เลยล็อก
                // ไม่ให้แก้ไข กันพิมพ์ผิด/ซ้ำ/ไม่เรียงเลข — ตอนแก้ไขแอดมินเดิม
                // ยังแก้ไขได้ตามปกติ (ไม่กระทบระดับแอดมินเพราะแยกฟิลด์กันแล้ว)
                readOnly: !_isEditing,
                style:
                    !_isEditing ? TextStyle(color: Colors.grey.shade600) : null,
                decoration: InputDecoration(
                  labelText: 'รหัสแอดมิน',
                  helperText: !_isEditing ? 'สร้างอัตโนมัติ' : null,
                  filled: !_isEditing,
                  fillColor: !_isEditing ? Colors.grey.shade100 : null,
                ),
              ),
              // 🔴 [ใหม่] ระดับแอดมิน — แสดงผลอย่างเดียว แก้ไขไม่ได้จากฟอร์มนี้แล้ว
              // (แอดมินคนแรกสุดของระบบเท่านั้นที่เป็นแอดมินหลัก ตั้งตอนสร้างบัญชี
              // ครั้งเดียว เปลี่ยนภายหลังไม่ได้ตามที่ขอ — ตรงกับฝั่งเว็บเป๊ะ ๆ)
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ระดับแอดมิน',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Text(
                  _isEditing
                      ? (widget.existing!.isMainAdmin
                          ? 'แอดมินหลัก (ล็อกไว้ เปลี่ยนไม่ได้)'
                          : 'แอดมินทั่วไป (เลื่อนขั้นไม่ได้)')
                      : (widget.isFirstAdmin
                          ? 'แอดมินหลัก (อัตโนมัติ — เป็นแอดมินคนแรกของระบบ)'
                          : 'แอดมินทั่วไป (อัตโนมัติ)'),
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('บันทึก', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
