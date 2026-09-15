// ==========================================
// SECTION 1: IMPORTS
// ==========================================
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

// ==========================================
// SECTION 2: DATA MODEL
// ==========================================

/// โมเดลข้อมูลช่างหนึ่งคน ([TechnicianItem]) — ผูกกับตาราง `technicians` จริง
class TechnicianItem {
  final String username;
  final String techName;
  final String employeeId;
  final String roleLabel;
  final String vehicle;
  final String phone;
  final String houseNo;
  final String moo;
  final String tambon;
  final String amphoe;
  final String changwat;
  final String postalCode;
  final String address;
  // 🔴 [แก้บั๊ก] เพิ่มฟิลด์ photoUrl — เดิม TechnicianItem ไม่มีฟิลด์นี้เลย ทำให้
  // แม้ตาราง technicians ใน Firebase จะมี photo_url เก็บอยู่จริง (จากตอนช่าง
  // เปลี่ยนรูปโปรไฟล์ในหน้า profile_technician.dart) หน้า "จัดการช่าง" ของแอดมิน
  // ก็ไม่มีทางอ่านค่านี้ออกมาแสดงได้ เลยเห็นเป็นไอคอนช่างเปล่า ๆ ตลอด
  final String photoUrl;

  const TechnicianItem({
    required this.username,
    required this.techName,
    required this.employeeId,
    required this.roleLabel,
    required this.vehicle,
    required this.phone,
    this.houseNo = '',
    this.moo = '',
    this.tambon = '',
    this.amphoe = '',
    this.changwat = '',
    this.postalCode = '',
    this.address = '',
    this.photoUrl = '',
  });

  factory TechnicianItem.fromMap(Map<String, dynamic> map) {
    return TechnicianItem(
      username: (map['username'] as String?) ?? '',
      techName: (map['tech_name'] as String?) ?? '-',
      employeeId: (map['employee_id'] as String?) ?? '-',
      roleLabel: (map['role_label'] as String?) ?? 'ช่างเทคนิค',
      vehicle: (map['vehicle'] as String?) ?? '-',
      phone: (map['phone'] as String?) ?? '-',
      houseNo: (map['house_no'] as String?) ?? '',
      moo: (map['moo'] as String?) ?? '',
      tambon: (map['tambon'] as String?) ?? '',
      amphoe: (map['amphoe'] as String?) ?? '',
      changwat: (map['changwat'] as String?) ?? '',
      postalCode: (map['postal_code'] as String?) ?? '',
      address: (map['address'] as String?) ?? '',
      // 🔴 [แก้บั๊ก] อ่าน photo_url จากข้อมูลดิบมาเก็บด้วย (ดูเหตุผลด้านบน)
      photoUrl: (map['photo_url'] as String?) ?? '',
    );
  }
}

// 🆕 [ใหม่] สร้างรหัสพนักงานช่างถัดไปแบบอัตโนมัติ — อ่านตัวเลขต่อท้าย "Tec-" ของ
// ทุกคนที่มีอยู่ ("Tec-02" -> 2) เอาค่ามากที่สุด +1 แล้ว pad เป็น 2 หลัก
// (เช่น มี Tec-02 อยู่แล้ว คนต่อไปจะได้ "Tec-03") ถ้ายังไม่มีใครใช้รูปแบบนี้เลย
// (รายชื่อว่าง หรือรหัสเดิมเป็นฟอร์แมตอื่น) จะเริ่มที่ "Tec-01"
String _nextTechnicianEmployeeId(List<TechnicianItem> technicians) {
  const prefix = 'Tec-';
  final pattern = RegExp(r'^tec-(\d+)$', caseSensitive: false);
  var maxNumber = 0;
  for (final t in technicians) {
    final match = pattern.firstMatch(t.employeeId.trim());
    if (match == null) continue;
    final n = int.tryParse(match.group(1)!) ?? 0;
    if (n > maxNumber) maxNumber = n;
  }
  final next = maxNumber + 1;
  return '$prefix${next.toString().padLeft(2, '0')}';
}

// ==========================================
// SECTION 3: MAIN SCREEN WIDGET
// ==========================================

/// {@template manage_technician}
/// หน้าจัดการรายชื่อช่างสำหรับแอดมิน ([ManageTechnicianPage])
///
/// รองรับ: ค้นหา, ดูรายชื่อช่างทั้งหมด, เพิ่มช่างใหม่, แก้ไข/ลบช่าง
/// เชื่อมกับตาราง `technicians` ผ่าน [DatabaseHelper] โดยตรง
/// {@endtemplate}
class ManageTechnicianPage extends StatefulWidget {
  const ManageTechnicianPage({super.key});

  @override
  State<ManageTechnicianPage> createState() => _ManageTechnicianPageState();
}

class _ManageTechnicianPageState extends State<ManageTechnicianPage> {
  bool _isLoading = true;
  List<TechnicianItem> _allTechnicians = [];
  String _query = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTechnicians() async {
    setState(() => _isLoading = true);
    try {
      final rows = await db.DatabaseHelper.instance.getAllTechnicians();
      if (!mounted) return;
      setState(() {
        _allTechnicians =
            rows.map((row) => TechnicianItem.fromMap(row)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading technicians: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('โหลดรายชื่อช่างไม่สำเร็จ');
    }
  }

  List<TechnicianItem> get _filteredTechnicians {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allTechnicians;
    return _allTechnicians.where((t) {
      return t.techName.toLowerCase().contains(q) ||
          t.username.toLowerCase().contains(q) ||
          t.employeeId.toLowerCase().contains(q);
    }).toList();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddDialog() async {
    // 🆕 [ใหม่] คำนวณรหัสพนักงานถัดไปจากรายชื่อช่างที่โหลดมาแล้ว แล้วส่งเข้าไป
    // ให้ฟอร์มตั้งเป็นค่าเริ่มต้นแบบอัตโนมัติ (ดู _nextTechnicianEmployeeId ด้านบน)
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _TechnicianFormDialog(
        nextEmployeeId: _nextTechnicianEmployeeId(_allTechnicians),
      ),
    );
    if (result == true) {
      await _loadTechnicians();
      _showSnack('เพิ่มช่างเรียบร้อย');
    }
  }

  Future<void> _openEditDialog(TechnicianItem tech) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _TechnicianFormDialog(existing: tech),
    );
    if (result == true) {
      await _loadTechnicians();
      _showSnack('บันทึกการแก้ไขเรียบร้อย');
    }
  }

  Future<void> _confirmDelete(TechnicianItem tech) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบช่าง "${tech.techName}" ใช่หรือไม่?'),
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
        await db.DatabaseHelper.instance.deleteTechnician(tech.username);
        await _loadTechnicians();
        _showSnack('ลบ "${tech.techName}" เรียบร้อยแล้ว');
      } catch (e) {
        debugPrint('Error deleting technician: $e');
        _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
      }
    }
  }

  // ==========================================
  // SECTION 4: BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final technicians = _filteredTechnicians;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _openAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'จัดการช่าง', showBack: true),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาชื่อช่าง หรือ Username...',
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
                  : technicians.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบรายชื่อช่าง',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadTechnicians,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: technicians.length,
                            itemBuilder: (context, index) {
                              final tech = technicians[index];
                              return _TechnicianCard(
                                technician: tech,
                                onEdit: () => _openEditDialog(tech),
                                onDelete: () => _confirmDelete(tech),
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

class _TechnicianCard extends StatelessWidget {
  final TechnicianItem technician;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TechnicianCard({
    required this.technician,
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
              // 🔴 [แก้บั๊ก] เดิมช่องนี้เป็นไอคอนช่างเปล่า ๆ ตายตัวเสมอ ไม่เคยเช็ค
              // technician.photoUrl เลย (สาเหตุจริง ๆ คือ TechnicianItem ยังไม่มี
              // ฟิลด์ photoUrl มาก่อน — แก้ไปแล้วด้านบนในไฟล์นี้) ตอนนี้ถ้ามีรูป
              // ให้แสดงรูปจริงแทนไอคอน ถ้าไม่มีค่อย fallback เป็นไอคอนเดิม
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: technician.photoUrl.isEmpty
                    ? Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.engineering_outlined,
                            color: AppColors.primary, size: 22),
                      )
                    : LocalOrNetworkImage(
                        path: technician.photoUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      technician.techName,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${technician.username} • รหัส ${technician.employeeId}',
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
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.badge_outlined, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                technician.roleLabel,
                style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(width: 12),
              Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                technician.phone,
                style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    color: Colors.grey.shade700),
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
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบ'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SECTION 6: เพิ่ม/แก้ไขช่าง (Dialog Form)
// ==========================================

class _TechnicianFormDialog extends StatefulWidget {
  final TechnicianItem? existing;
  // 🆕 [ใหม่] รหัสพนักงานที่คำนวณไว้ล่วงหน้าสำหรับตอน "เพิ่มช่างใหม่" เท่านั้น
  // (ตอนแก้ไขช่างเดิมจะไม่ส่งค่านี้มา ใช้ existing.employeeId ตามปกติ)
  final String? nextEmployeeId;

  const _TechnicianFormDialog({this.existing, this.nextEmployeeId});

  @override
  State<_TechnicianFormDialog> createState() => _TechnicianFormDialogState();
}

class _TechnicianFormDialogState extends State<_TechnicianFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _employeeIdController;
  late final TextEditingController _phoneController;
  late final TextEditingController _vehicleController;
  late final TextEditingController _houseNoController;
  late final TextEditingController _mooController;
  late final TextEditingController _tambonController;
  late final TextEditingController _amphoeController;
  late final TextEditingController _changwatController;
  late final TextEditingController _zipController;

  bool _isSaving = false;

  // 🆕 [ใหม่] ให้แอดมินใส่/เปลี่ยนรูปโปรไฟล์ของช่างได้จากในไดอะล็อกนี้เลย
  // — เดิมฟอร์มนี้ไม่มีช่องรูปเลย ทำให้แอดมินต้องรอให้ช่างเปลี่ยนรูปเองในแอปเท่านั้น
  // ใช้ ImagePicker + cropProfileImage + uploadPickedImage ชุดเดียวกับหน้าโปรไฟล์
  // ช่าง (profile_technician.dart) เพื่อให้พฤติกรรมการครอป/อัปโหลดตรงกันทั้งระบบ
  final ImagePicker _picker = ImagePicker();
  String _photoUrl = '';
  bool _isUploadingPhoto = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _photoUrl = existing?.photoUrl ?? '';
    _usernameController = TextEditingController(text: existing?.username ?? '');
    _passwordController = TextEditingController();
    _nameController = TextEditingController(text: existing?.techName ?? '');
    _employeeIdController = TextEditingController(
      // 🆕 [ใหม่] ตอนเพิ่มช่างใหม่ (ไม่มี existing) ให้ใส่รหัสที่คำนวณอัตโนมัติมา
      // เป็นค่าเริ่มต้น — ตอนแก้ไขยังคงใช้รหัสเดิมของช่างคนนั้นเหมือนเดิม
      text: existing?.employeeId ?? widget.nextEmployeeId ?? '',
    );
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _vehicleController = TextEditingController(text: existing?.vehicle ?? '');
    _houseNoController = TextEditingController(text: existing?.houseNo ?? '');
    _mooController = TextEditingController(text: existing?.moo ?? '');
    _tambonController = TextEditingController(text: existing?.tambon ?? '');
    _amphoeController = TextEditingController(text: existing?.amphoe ?? '');
    _changwatController = TextEditingController(text: existing?.changwat ?? '');
    _zipController = TextEditingController(text: existing?.postalCode ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _employeeIdController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _houseNoController.dispose();
    _mooController.dispose();
    _tambonController.dispose();
    _amphoeController.dispose();
    _changwatController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  // 🆕 [ใหม่] เลือกรูป -> ครอปเป็นวงกลม -> อัปโหลดขึ้น Cloudinary ทันทีที่เลือก
  // (อัปโหลดเลยเหมือนหน้าโปรไฟล์ช่าง/ลูกค้า/แอดมิน ไม่รอกดปุ่ม "บันทึก" ของฟอร์ม
  // เพื่อให้ error จากขั้นตอนอัปโหลดแยกออกจาก error ตอนบันทึกข้อมูลฟอร์ม)
  Future<void> _pickPhoto() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      final cropped = await cropProfileImage(picked);
      if (cropped == null) return;
      if (!mounted) return;
      setState(() => _isUploadingPhoto = true);
      final photoUrl = await uploadPickedImage(cropped);
      if (!mounted) return;
      setState(() {
        _photoUrl = photoUrl;
        _isUploadingPhoto = false;
      });
    } catch (e) {
      debugPrint('Error picking technician photo: $e');
      if (!mounted) return;
      setState(() => _isUploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final newUsername = _usernameController.text.trim();
    final oldUsername = widget.existing?.username;

    // ตรวจสอบ Username ซ้ำเมื่อเพิ่มใหม่ หรือเมื่อแก้ไขแล้วเปลี่ยนเป็นชื่ออื่น
    if (!_isEditing || newUsername != oldUsername) {
      final exists =
          await db.DatabaseHelper.instance.checkUsernameExists(newUsername);
      if (exists) {
        if (!mounted) return;
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username นี้ถูกใช้งานแล้ว')),
        );
        return;
      }
    }

    final addressFields = {
      'house_no': _houseNoController.text.trim(),
      'moo': _mooController.text.trim(),
      'tambon': _tambonController.text.trim(),
      'amphoe': _amphoeController.text.trim(),
      'changwat': _changwatController.text.trim(),
      'postal_code': _zipController.text.trim(),
    };

    try {
      if (_isEditing) {
        final updateData = {
          'tech_name': _nameController.text.trim(),
          'employee_id': _employeeIdController.text.trim(),
          'phone': _phoneController.text.trim(),
          'vehicle': _vehicleController.text.trim(),
          // 🆕 [ใหม่] แนบ photo_url ที่แอดมินเลือก/เปลี่ยนไปด้วยทุกครั้งที่บันทึก
          'photo_url': _photoUrl,
          ...addressFields,
        };

        // หากมีการกรอกรหัสผ่านใหม่ ให้แนบไปอัปเดต (ถ้าเว้นว่างไว้จะคงรหัสเดิม)
        final password = _passwordController.text.trim();
        if (password.isNotEmpty) {
          updateData['password'] = password;
        }

        await db.DatabaseHelper.instance.updateTechnicianProfile(
          oldUsername!,
          updateData,
          newUsername: newUsername != oldUsername ? newUsername : null,
        );
      } else {
        await db.DatabaseHelper.instance.registerTechnician({
          'username': newUsername,
          'password': _passwordController.text.trim(),
          'tech_name': _nameController.text.trim(),
          'employee_id': _employeeIdController.text.trim(),
          'phone': _phoneController.text.trim(),
          'vehicle': _vehicleController.text.trim(),
          'role_label': 'ช่างเทคนิค',
          // 🆕 [ใหม่] รองรับกรณีแอดมินใส่รูปให้ตั้งแต่ตอนเพิ่มช่างใหม่เลย
          'photo_url': _photoUrl,
          ...addressFields,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving technician: $e');
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
      title: Text(_isEditing ? 'แก้ไขข้อมูลช่าง' : 'เพิ่มช่างใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🆕 [ใหม่] ช่องรูปโปรไฟล์ช่าง — แอดมินกดที่ไอคอนกล้องเพื่อเลือก/
              // เปลี่ยนรูปได้เลยจากในไดอะล็อกนี้ (ดู _pickPhoto ด้านบน)
              _TechnicianPhotoPicker(
                photoUrl: _photoUrl,
                isUploading: _isUploadingPhoto,
                onEdit: _isUploadingPhoto ? null : _pickPhoto,
              ),
              const SizedBox(height: 16),
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
                decoration: InputDecoration(
                  labelText: _isEditing
                      ? 'Password ใหม่ (เว้นว่างถ้าไม่เปลี่ยน)'
                      : 'Password',
                ),
                obscureText: true,
                validator: (v) {
                  if (!_isEditing && (v == null || v.trim().isEmpty)) {
                    return 'กรุณากรอก Password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _employeeIdController,
                // 🆕 [ใหม่] ตอนเพิ่มช่างใหม่ รหัสพนักงานถูกสร้างอัตโนมัติแล้ว
                // (ดู _nextTechnicianEmployeeId) เลยล็อกไม่ให้แก้ไข กันพิมพ์ผิด/
                // ซ้ำ/ไม่เรียงเลข — ตอนแก้ไขช่างเดิมยังแก้ไขได้ตามปกติ
                readOnly: !_isEditing,
                style:
                    !_isEditing ? TextStyle(color: Colors.grey.shade600) : null,
                decoration: InputDecoration(
                  labelText: 'รหัสพนักงาน',
                  helperText: !_isEditing ? 'สร้างอัตโนมัติ' : null,
                  filled: !_isEditing,
                  fillColor: !_isEditing ? Colors.grey.shade100 : null,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _vehicleController,
                decoration: const InputDecoration(labelText: 'ยานพาหนะ'),
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ที่อยู่',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _houseNoController,
                      decoration:
                          const InputDecoration(labelText: 'บ้านเลขที่'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _mooController,
                      decoration: const InputDecoration(labelText: 'หมู่'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tambonController,
                decoration: const InputDecoration(labelText: 'ตำบล'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amphoeController,
                decoration: const InputDecoration(labelText: 'อำเภอ'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _changwatController,
                      decoration: const InputDecoration(labelText: 'จังหวัด'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _zipController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'รหัสไปรษณีย์'),
                    ),
                  ),
                ],
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

// ==========================================
// SECTION 7: ตัวเลือกรูปโปรไฟล์ช่าง (ใช้ในไดอะล็อกเพิ่ม/แก้ไขช่าง)
// ==========================================

/// {@template technician_photo_picker}
/// วงกลมแสดงรูปโปรไฟล์ช่าง พร้อมปุ่มกล้องมุมขวาล่างสำหรับเลือก/เปลี่ยนรูป
/// (หน้าตาเดียวกับ _AvatarSection ในหน้าโปรไฟล์ช่าง เพื่อให้ผู้ใช้คุ้นตา)
/// — ระหว่างกำลังอัปโหลดจะแสดง spinner ทับรูปไว้ และปิดการกดซ้ำ
/// {@endtemplate}
class _TechnicianPhotoPicker extends StatelessWidget {
  final String photoUrl;
  final bool isUploading;
  final VoidCallback? onEdit;

  const _TechnicianPhotoPicker({
    required this.photoUrl,
    required this.isUploading,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Stack(
        children: [
          ClipOval(
            child: photoUrl.isEmpty
                ? Container(
                    width: 96,
                    height: 96,
                    color: Colors.grey.shade200,
                    child: Icon(
                      Icons.engineering_outlined,
                      size: 44,
                      color: Colors.grey.shade400,
                    ),
                  )
                : LocalOrNetworkImage(
                    path: photoUrl,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
          ),
          if (isUploading)
            Positioned.fill(
              child: ClipOval(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.35),
                  child: const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onEdit,
                child: const Padding(
                  padding: EdgeInsets.all(7),
                  child: Icon(
                    Icons.camera_alt,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
