import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/technician/tac_id_card.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';


/// Technician profile model - โหลด/บันทึกจริงกับตาราง `technicians` ผ่าน DatabaseHelper
class TechnicianProfile {
  String username;
  String techName;
  String employeeId;
  String roleLabel;
  String vehicle;
  String company;
  String address;
  // 🔴 [แก้ไข] เพิ่มฟิลด์ที่อยู่แบบแยกส่วน (บ้านเลขที่/หมู่/ตำบล/อำเภอ/จังหวัด/รหัสไปรษณีย์)
  // ให้ตรงกับรูปแบบเดียวกับหน้าโปรไฟล์ลูกค้า (profile_customer.dart) แทนที่จะกรอก
  // รวมเป็นข้อความบรรทัดเดียวเหมือนเดิม
  String houseNo;
  String moo;
  String tambon;
  String amphoe;
  String changwat;
  String postalCode;
  String phone;
  String photoUrl;

  TechnicianProfile({
    required this.username,
    required this.techName,
    required this.employeeId,
    required this.roleLabel,
    required this.vehicle,
    required this.company,
    required this.address,
    this.houseNo = '',
    this.moo = '',
    this.tambon = '',
    this.amphoe = '',
    this.changwat = '',
    this.postalCode = '',
    required this.phone,
    this.photoUrl = '',
  });

  factory TechnicianProfile.fromMap(Map<String, dynamic> map) {
    return TechnicianProfile(
      username: (map['username']?.toString()) ?? '',
      techName: (map['tech_name']?.toString()) ?? '-',
      employeeId: (map['employee_id']?.toString()) ?? '-',
      roleLabel: (map['role_label']?.toString()) ?? '-',
      vehicle: (map['vehicle']?.toString()) ?? '-',
      company: (map['company']?.toString()) ?? '-',
      address: (map['address']?.toString()) ?? '-',
      houseNo: (map['house_no']?.toString()) ?? '',
      moo: (map['moo']?.toString()) ?? '',
      tambon: (map['tambon']?.toString()) ?? '',
      amphoe: (map['amphoe']?.toString()) ?? '',
      changwat: (map['changwat']?.toString()) ?? '',
      postalCode: (map['postal_code']?.toString()) ?? '',
      phone: (map['phone']?.toString()) ?? '-',
      photoUrl: (map['photo_url']?.toString()) ?? '',
    );
  }

  /// รวมฟิลด์ที่อยู่แยกส่วนเป็นข้อความเดียวสำหรับแสดงผล — ถ้ายังไม่กรอกอะไรเลย
  /// จะ fallback ไปใช้ค่าเดิมในคอลัมน์ 'address' (ข้อมูลเก่าก่อนแยกฟิลด์) แล้วค่อย
  /// โชว์ '-' ถ้าไม่มีอะไรเลยจริง ๆ
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
    return address.isNotEmpty ? address : '-';
  }
}

class ProfileTechnicianPage extends StatefulWidget {
  const ProfileTechnicianPage({super.key});

  @override
  State<ProfileTechnicianPage> createState() => _ProfileTechnicianPageState();
}

class _ProfileTechnicianPageState extends State<ProfileTechnicianPage> {
  bool _loading = true;
  // 🔴 [แก้ไข] เพิ่มโหมด "แก้ไขโปรไฟล์" — เดิมปุ่มนี้กดแล้วไม่ทำอะไรเลย (แค่ขึ้น
  // toast ลอย ๆ) ทั้งที่ดินสอแก้ไขแต่ละแถวโชว์อยู่ตลอดเวลาอยู่แล้วโดยไม่ต้องกด
  // ปุ่มนี้ก่อน ตอนนี้สลับเป็น: ปกติซ่อนดินสอไว้ก่อน กดปุ่มแล้วค่อยโชว์ดินสอ
  // ทุกแถวพร้อมกัน แล้วปุ่มเปลี่ยนเป็น "เสร็จสิ้น" ให้กดปิดโหมดแก้ไขได้
  bool _isEditMode = false;
  TechnicianProfile _profile = TechnicianProfile(
    username: '-',
    techName: '-',
    employeeId: '-',
    roleLabel: '-',
    vehicle: '-',
    company: '-',
    address: '-',
    phone: '-',
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final username = db.Session.currentUsername;
    final row =
        await db.DatabaseHelper.instance.getTechnicianByUsername(username);

    if (!mounted) return;
    setState(() {
      if (row != null) {
        _profile = TechnicianProfile.fromMap(row);
      } else {
        _profile = TechnicianProfile(
          username: username,
          techName: '-',
          employeeId: '-',
          roleLabel: '-',
          vehicle: '-',
          company: '-',
          address: '-',
          phone: '-',
        );
      }
      _loading = false;
    });
  }

  Future<void> _saveField(String column, String value) async {
    await db.DatabaseHelper.instance
        .updateTechnicianProfile(_profile.username, {column: value});
  }

  Future<void> _editField({
    required String label,
    required String currentValue,
    required ValueChanged<String> onSaved,
    required String dbColumn,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('แก้ไข$label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => onSaved(result));
      await _saveField(dbColumn, result);
    }
  }

  /// ✏️ แก้ไขที่อยู่แบบแยกฟิลด์ (บ้านเลขที่/หมู่/ตำบล/อำเภอ/จังหวัด/รหัสไปรษณีย์)
  /// แทนที่จะให้กรอกรวมเป็นบรรทัดเดียว — รูปแบบเดียวกับหน้าโปรไฟล์ลูกค้า
  Future<void> _editAddress() async {
    final houseNoCtrl = TextEditingController(text: _profile.houseNo);
    final mooCtrl = TextEditingController(text: _profile.moo);
    final tambonCtrl = TextEditingController(text: _profile.tambon);
    final amphoeCtrl = TextEditingController(text: _profile.amphoe);
    final changwatCtrl = TextEditingController(text: _profile.changwat);
    final zipCtrl = TextEditingController(text: _profile.postalCode);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Text(
                    'แก้ไขที่อยู่',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: houseNoCtrl,
                          decoration: const InputDecoration(
                            labelText: 'บ้านเลขที่',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: mooCtrl,
                          decoration: const InputDecoration(
                            labelText: 'หมู่',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tambonCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ตำบล',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amphoeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'อำเภอ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: changwatCtrl,
                          decoration: const InputDecoration(
                            labelText: 'จังหวัด',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: zipCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'รหัสไปรษณีย์',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => Navigator.pop(sheetContext, true),
                      child: const Text('บันทึก'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (saved != true) return;

    final houseNo = houseNoCtrl.text.trim();
    final moo = mooCtrl.text.trim();
    final tambon = tambonCtrl.text.trim();
    final amphoe = amphoeCtrl.text.trim();
    final changwat = changwatCtrl.text.trim();
    final postalCode = zipCtrl.text.trim();

    setState(() {
      _profile.houseNo = houseNo;
      _profile.moo = moo;
      _profile.tambon = tambon;
      _profile.amphoe = amphoe;
      _profile.changwat = changwat;
      _profile.postalCode = postalCode;
    });

    await db.DatabaseHelper.instance.updateTechnicianProfile(
      _profile.username,
      {
        'house_no': houseNo,
        'moo': moo,
        'tambon': tambon,
        'amphoe': amphoe,
        'changwat': changwat,
        'postal_code': postalCode,
      },
    );
  }

  final ImagePicker _picker = ImagePicker();

  Future<void> _editProfilePicture() async {
    try {
      // 🔴 [แก้บั๊ก] เดิมย่อขนาด+บีบอัดตั้งแต่ตอน "เลือกรูป" ตรงนี้เลย (maxWidth/
      // maxHeight/imageQuality) ทำให้รูปทั้งใบถูกย่อเหลือ 640×640 ก่อนที่ผู้ใช้จะ
      // ได้ครอป พอครอปเอาแค่บางส่วนของรูปที่ย่อไปแล้ว เลยเหลือพิกเซลน้อยมาก พอถูก
      // ขยายแสดงในวงกลมโปรไฟล์เลยแตก/เบลอ ตอนนี้เปลี่ยนให้เลือกรูปที่ความละเอียด
      // เต็มไปก่อน แล้วไปย่อ/บีบอัด "หลังครอปเสร็จแล้ว" แทน (ดู cropProfileImage()
      // ใน widgets.dart ที่ตั้ง maxWidth/maxHeight: 640 ไว้ตรงนั้นแล้ว)
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      // 🔴 [ใหม่] ให้ผู้ใช้ครอปรูปเป็นวงกลมเองก่อนอัปโหลด กันรูปเบี้ยว/โดนตัด
      // หัวตัดขาตอนไปแสดงในวงกลมโปรไฟล์ (ดู cropProfileImage() ใน widgets.dart)
      final cropped = await cropProfileImage(picked);
      if (cropped == null) return;
      if (!mounted) return;
      // 🔴 อัปโหลดขึ้น Cloudinary แทนการเก็บแค่ path ไฟล์ในเครื่อง เพื่อให้คนอื่นที่
      // ล็อกอินจากเครื่อง/บัญชีอื่นเห็นรูปนี้ได้จริงผ่าน Firebase (ดูรายละเอียดเหตุผลที่
      // uploadPickedImage() ใน widgets.dart)
      final photoUrl = await uploadPickedImage(cropped);
      if (!mounted) return;
      setState(() => _profile.photoUrl = photoUrl);
      await _saveField('photo_url', photoUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🔒 หัวเรื่องล็อกอยู่นิ่ง ไม่เลื่อนตามเนื้อหา
            const AppHeader(
              title: 'โปรไฟล์',
              trailing: ProfileSettingsButton(),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    _AvatarSection(
                      photoUrl: _profile.photoUrl,
                      onEdit: _editProfilePicture,
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.06),
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SectionHeader(
                              isEditMode: _isEditMode,
                              onEditAll: () {
                                setState(() => _isEditMode = !_isEditMode);
                              },
                            ),
                            _ProfileRow(
                              label: 'ชื่อผู้ใช้',
                              value: _profile.username,
                              editable: false,
                            ),
                            _ProfileRow(
                              label: 'ชื่อ-นามสกุล',
                              value: _profile.techName,
                              isEditMode: _isEditMode,
                              onEdit: () => _editField(
                                label: 'ชื่อ-นามสกุล',
                                currentValue: _profile.techName,
                                dbColumn: 'tech_name',
                                onSaved: (v) => _profile.techName = v,
                              ),
                            ),
                            _ProfileRow(
                              label: 'รหัสพนักงาน',
                              value: _profile.employeeId,
                              editable: false,
                            ),
                            _ProfileRow(
                              label: 'ตำแหน่ง',
                              value: _profile.roleLabel,
                              isEditMode: _isEditMode,
                              onEdit: () => _editField(
                                label: 'ตำแหน่ง',
                                currentValue: _profile.roleLabel,
                                dbColumn: 'role_label',
                                onSaved: (v) => _profile.roleLabel = v,
                              ),
                            ),
                            _ProfileRow(
                              label: 'บริษัท',
                              value: _profile.company,
                              isEditMode: _isEditMode,
                              onEdit: () => _editField(
                                label: 'บริษัท',
                                currentValue: _profile.company,
                                dbColumn: 'company',
                                onSaved: (v) => _profile.company = v,
                              ),
                            ),
                            _ProfileRow(
                              label: 'ยานพาหนะ',
                              value: _profile.vehicle,
                              isEditMode: _isEditMode,
                              onEdit: () => _editField(
                                label: 'ยานพาหนะ',
                                currentValue: _profile.vehicle,
                                dbColumn: 'vehicle',
                                onSaved: (v) => _profile.vehicle = v,
                              ),
                            ),
                            _ProfileRow(
                              label: 'ที่อยู่',
                              value: _profile.formattedAddress,
                              isEditMode: _isEditMode,
                              onEdit: _editAddress,
                            ),
                            _ProfileRow(
                              label: 'หมายเลขโทรศัพท์',
                              value: _profile.phone,
                              isLast: true,
                              isEditMode: _isEditMode,
                              onEdit: () => _editField(
                                label: 'หมายเลขโทรศัพท์',
                                currentValue: _profile.phone,
                                dbColumn: 'phone',
                                onSaved: (v) => _profile.phone = v,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary, width: 0.8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const IdentityCardPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.badge_outlined, size: 20),
                          label: const Text(
                            'ดูบัตรประจำตัว',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  final String photoUrl;
  final VoidCallback onEdit;
  const _AvatarSection({required this.photoUrl, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Stack(
          children: [
            ClipOval(
              child: photoUrl.isEmpty
                  ? Container(
                      width: 140,
                      height: 140,
                      color: Colors.grey.shade200,
                      child: Icon(
                        Icons.person,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                    )
                  : LocalOrNetworkImage(
                      path: photoUrl,
                      width: 140,
                      height: 140,
                      fit: BoxFit.cover,
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
                    padding: EdgeInsets.all(8),
                    child: Icon(
                      Icons.camera_alt,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final VoidCallback onEditAll;
  // 🔴 [แก้ไข] สลับข้อความ/ไอคอนปุ่มตามโหมดปัจจุบัน — โหมดแก้ไข: โชว์ปุ่ม
  // "เสร็จสิ้น" ให้กดออกจากโหมดแก้ไขได้ (ตามที่ขอเพิ่ม)
  final bool isEditMode;
  const _SectionHeader({required this.onEditAll, required this.isEditMode});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('ข้อมูลช่าง', style: TextStyle(fontSize: 14)),
          TextButton.icon(
            onPressed: onEditAll,
            icon: Icon(
              isEditMode ? Icons.check_circle : Icons.edit,
              size: 14,
              color: isEditMode ? AppColors.greenText : AppColors.primary,
            ),
            label: Text(
              isEditMode ? 'เสร็จสิ้น' : 'แก้ไขโปรไฟล์',
              style: TextStyle(
                color: isEditMode ? AppColors.greenText : AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 0),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool editable;
  final bool isLast;
  // 🔴 [แก้ไข] ดินสอแก้ไขจะโชว์ก็ต่อเมื่อ editable=true (ฟิลด์นี้แก้ไขได้จริง)
  // และ isEditMode=true (กดปุ่ม "แก้ไขโปรไฟล์" แล้ว) พร้อมกันทั้งสองเงื่อนไข
  final bool isEditMode;

  const _ProfileRow({
    required this.label,
    required this.value,
    this.onEdit,
    this.editable = true,
    this.isLast = false,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
                  ),
                ),
              ],
            ),
          ),
          if (editable && onEdit != null && isEditMode)
            IconButton(
              onPressed: onEdit,
              icon: const Icon(
                Icons.edit_outlined,
                size: 18,
                color: Colors.grey,
              ),
              splashRadius: 20,
            ),
        ],
      ),
    );
  }
}