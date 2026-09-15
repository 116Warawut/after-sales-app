import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';


/// Admin profile model - โหลด/บันทึกจริงกับตาราง `admins` ผ่าน DatabaseHelper
/// (ตาราง admins มีแค่ admin_name / admin_code / username เท่านั้น)
class AdminProfile {
  String username;
  String adminName;
  String adminCode;
  String photoUrl;

  AdminProfile({
    required this.username,
    required this.adminName,
    required this.adminCode,
    this.photoUrl = '',
  });

  factory AdminProfile.fromMap(Map<String, dynamic> map) {
    return AdminProfile(
      username: (map['username'] as String?) ?? '',
      adminName: (map['admin_name'] as String?) ?? '-',
      adminCode: (map['admin_code'] as String?) ?? '-',
      photoUrl: (map['photo_url'] as String?) ?? '',
    );
  }
}

class ProfileAdminPage extends StatefulWidget {
  const ProfileAdminPage({super.key});

  @override
  State<ProfileAdminPage> createState() => _ProfileAdminPageState();
}

class _ProfileAdminPageState extends State<ProfileAdminPage> {
  bool _loading = true;
  AdminProfile _profile = AdminProfile(
    username: '-',
    adminName: '-',
    adminCode: '-',
  );

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final username = db.Session.currentUsername;
    final row = await db.DatabaseHelper.instance.getAdminProfile(username);

    if (!mounted) return;
    setState(() {
      if (row != null) {
        _profile = AdminProfile.fromMap(row);
      } else {
        _profile = AdminProfile(username: username, adminName: '-', adminCode: '-');
      }
      _loading = false;
    });
  }

  Future<void> _saveField(String column, String value) async {
    await db.DatabaseHelper.instance
        .updateAdminProfile(_profile.username, {column: value});
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
                            const _SectionHeaderText(),
                            _ProfileRow(
                              label: 'ชื่อผู้ใช้',
                              value: _profile.username,
                              editable: false,
                            ),
                            _ProfileRow(
                              label: 'ชื่อผู้ดูแลระบบ',
                              value: _profile.adminName,
                              onEdit: () => _editField(
                                label: 'ชื่อผู้ดูแลระบบ',
                                currentValue: _profile.adminName,
                                dbColumn: 'admin_name',
                                onSaved: (v) => _profile.adminName = v,
                              ),
                            ),
                            _ProfileRow(
                              label: 'รหัสแอดมิน',
                              value: _profile.adminCode,
                              onEdit: () => _editField(
                                label: 'รหัสแอดมิน',
                                currentValue: _profile.adminCode,
                                dbColumn: 'admin_code',
                                onSaved: (v) => _profile.adminCode = v,
                              ),
                            ),
                          ],
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

class _SectionHeaderText extends StatelessWidget {
  const _SectionHeaderText();

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
      child: const Text('ข้อมูลผู้ดูแลระบบ', style: TextStyle(fontSize: 14)),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.grey.shade200,
                      ),
                      child: Icon(
                        Icons.admin_panel_settings,
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

class _ProfileRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onEdit;
  final bool editable;

  const _ProfileRow({
    required this.label,
    required this.value,
    this.onEdit,
    this.editable = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x0F000000)),
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
          if (editable && onEdit != null)
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
