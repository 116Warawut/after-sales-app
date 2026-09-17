import 'dart:convert';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image_picker/image_picker.dart';

import 'change_email_screen.dart';
import 'machine_list_page.dart';

class ProfileCustomer extends StatelessWidget {
  const ProfileCustomer({super.key});

  @override
  Widget build(BuildContext context) {
    return const UserProfilePage();
  }
}

/// โครงสร้างข้อมูลจังหวัด/อำเภอ/ตำบล/รหัสไปรษณีย์
class _ThaiTambon {
  final String name;
  final String zip;
  _ThaiTambon(this.name, this.zip);
}

class _ThaiAmphure {
  final String name;
  final List<_ThaiTambon> tambons;
  _ThaiAmphure(this.name, this.tambons);
}

class _ThaiProvince {
  final String name;
  final List<_ThaiAmphure> amphures;
  _ThaiProvince(this.name, this.amphures);
}

String _cleanAddressPrefix(String? text) {
  if (text == null) return '';
  var s = text.trim();
  if (s == '-' || s.isEmpty) return '';
  const prefixes = [
    'จังหวัด',
    'จ.',
    'จ ',
    'อำเภอ',
    'อ.',
    'อ ',
    'เขต',
    'ตำบล',
    'ต.',
    'ต ',
    'แขวง',
  ];
  for (final p in prefixes) {
    if (s.startsWith(p)) {
      s = s.substring(p.length).trim();
    }
  }
  return s;
}

/// User profile model
class UserProfile {
  String username;
  String fullName;
  String company;
  String email;
  String address;
  String houseNo;
  String moo;
  String tambon;
  String amphoe;
  String changwat;
  String postalCode;
  String phone;
  int machineCount;
  String photoUrl;

  UserProfile({
    required this.username,
    required this.fullName,
    required this.company,
    required this.email,
    required this.address,
    this.houseNo = '',
    this.moo = '',
    this.tambon = '',
    this.amphoe = '',
    this.changwat = '',
    this.postalCode = '',
    required this.phone,
    required this.machineCount,
    this.photoUrl = '',
  });

  factory UserProfile.fromMap(
    Map<String, dynamic> map, {
    int machineCount = 0,
  }) {
    final name = (map['name']?.toString()) ?? '';
    final surname = (map['surname']?.toString()) ?? '';
    return UserProfile(
      username: (map['username']?.toString()) ?? '',
      fullName: '$name $surname'.trim(),
      company: (map['company']?.toString()) ?? '-',
      email: (map['email']?.toString()) ?? '-',
      address: (map['address']?.toString()) ?? '-',
      houseNo: (map['house_no']?.toString()) ?? '',
      moo: (map['moo']?.toString()) ?? '',
      tambon: (map['tambon']?.toString()) ?? '',
      amphoe: (map['amphoe']?.toString()) ?? '',
      changwat: (map['changwat']?.toString()) ?? '',
      postalCode: (map['postal_code']?.toString()) ?? '',
      phone: (map['phone']?.toString()) ?? '-',
      machineCount: machineCount,
      photoUrl: (map['photo_url']?.toString()) ?? '',
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
    return parts.isEmpty ? '-' : parts.join(' ');
  }
}

class UserProfilePage extends StatefulWidget {
  const UserProfilePage({super.key});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  bool _loading = true;
  bool _isEditMode = false;
  UserProfile _profile = UserProfile(
    username: '-',
    fullName: '-',
    company: '-',
    email: '-',
    address: '-',
    phone: '-',
    machineCount: 0,
  );

  List<_ThaiProvince> _thaiProvinces = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadThaiAddressData();
  }

  Future<void> _loadThaiAddressData() async {
    try {
      final raw = await rootBundle.loadString('assets/data/thai_address.json');
      final List<dynamic> data = jsonDecode(raw);
      final provinces = data.map((p) {
        final amphures = (p['amphures'] as List).map((a) {
          final tambons = (a['tambons'] as List)
              .map((t) => _ThaiTambon(
                    t['name'] as String,
                    t['zip'].toString(),
                  ))
              .toList();
          return _ThaiAmphure(a['name'] as String, tambons);
        }).toList();
        return _ThaiProvince(p['name'] as String, amphures);
      }).toList();

      if (!mounted) return;
      setState(() {
        _thaiProvinces = provinces;
      });
    } catch (e) {
      debugPrint('โหลดข้อมูลจังหวัด/อำเภอ/ตำบลไม่สำเร็จ: $e');
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    final username = db.Session.currentUsername;
    final row = await db.DatabaseHelper.instance.getCustomerProfile(username);
    final machines = await db.DatabaseHelper.instance.getMachinesForCustomer(
      username,
    );

    if (!mounted) return;
    setState(() {
      if (row != null) {
        _profile = UserProfile.fromMap(row, machineCount: machines.length);
      }
      _loading = false;
    });
  }

  Future<void> _saveField(String column, String value) async {
    await db.DatabaseHelper.instance.updateCustomerProfile(_profile.username, {
      column: value,
    });
  }

  Future<void> _editFullName() async {
    final controller = TextEditingController(text: _profile.fullName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขชื่อ-นามสกุล'),
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
      final parts = result.split(' ');
      final name = parts.first;
      final surname = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      setState(() => _profile.fullName = result);
      await db.DatabaseHelper.instance.updateCustomerProfile(
        _profile.username,
        {'name': name, 'surname': surname},
      );
    }
  }

  Future<void> _editField({
    required String label,
    required String currentValue,
    required ValueChanged<String> onSaved,
    required String dbColumn,
    TextInputType? keyboardType,
  }) async {
    final controller = TextEditingController(text: currentValue);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('แก้ไข$label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboardType,
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

  Future<void> _editEmail() async {
    final newEmail = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => ChangeEmailScreen(
          username: _profile.username,
          currentEmail: _profile.email,
        ),
      ),
    );
    if (newEmail != null && newEmail.isNotEmpty && mounted) {
      setState(() => _profile.email = newEmail);
    }
  }

  /// ✏️ แก้ไขที่อยู่แบบ Dropdown เลือก จังหวัด -> อำเภอ -> ตำบล และกรอกรหัสไปรษณีย์อัตโนมัติ
  Future<void> _editAddress() async {
    if (_thaiProvinces.isEmpty) {
      await _loadThaiAddressData();
    }

    final houseNoCtrl = TextEditingController(text: _profile.houseNo);
    final mooCtrl = TextEditingController(text: _profile.moo);
    final changwatCtrl = TextEditingController(text: _cleanAddressPrefix(_profile.changwat));
    final amphoeCtrl = TextEditingController(text: _cleanAddressPrefix(_profile.amphoe));
    final tambonCtrl = TextEditingController(text: _cleanAddressPrefix(_profile.tambon));
    final zipCtrl = TextEditingController(text: _profile.postalCode);

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            List<String> getProvinceOptions() =>
                _thaiProvinces.map((p) => p.name).toList();

            List<String> getAmphoeOptions() {
              final prov = changwatCtrl.text.trim();
              final match = _thaiProvinces.where((p) => p.name == prov);
              if (match.isEmpty) return [];
              return match.first.amphures.map((a) => a.name).toList();
            }

            List<String> getTambonOptions() {
              final prov = changwatCtrl.text.trim();
              final amp = amphoeCtrl.text.trim();
              final provMatch = _thaiProvinces.where((p) => p.name == prov);
              if (provMatch.isEmpty) return [];
              final ampMatch = provMatch.first.amphures.where((a) => a.name == amp);
              if (ampMatch.isEmpty) return [];
              return ampMatch.first.tambons.map((t) => t.name).toList();
            }

            void tryAutoFillZip() {
              final prov = changwatCtrl.text.trim();
              final amp = amphoeCtrl.text.trim();
              final tam = tambonCtrl.text.trim();
              final provMatch = _thaiProvinces.where((p) => p.name == prov);
              if (provMatch.isEmpty) return;
              final ampMatch = provMatch.first.amphures.where((a) => a.name == amp);
              if (ampMatch.isEmpty) return;
              final tamMatch = ampMatch.first.tambons.where((t) => t.name == tam);
              if (tamMatch.isEmpty) return;
              zipCtrl.text = tamMatch.first.zip;
            }

            Widget buildAutocompleteDropdown({
              Key? key,
              required String hintText,
              required TextEditingController controller,
              required List<String> Function() optionsBuilder,
              void Function(String selected)? onSelected,
              bool enabled = true,
            }) {
              return Autocomplete<String>(
                key: key,
                initialValue: TextEditingValue(text: controller.text),
                optionsBuilder: (TextEditingValue value) {
                  if (!enabled) return const Iterable<String>.empty();
                  final options = optionsBuilder();
                  final query = value.text.trim();
                  if (query.isEmpty || query == controller.text.trim()) return options;
                  return options.where((o) => o.contains(query));
                },
                displayStringForOption: (o) => o,
                onSelected: (selection) {
                  controller.text = selection;
                  onSelected?.call(selection);
                },
                fieldViewBuilder: (context, fieldController, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: fieldController,
                    focusNode: focusNode,
                    enabled: enabled,
                    style: const TextStyle(fontFamily: AppStyles.fontFamily),
                    decoration: InputDecoration(
                      labelText: hintText,
                      hintText: enabled ? hintText : '$hintText (เลือกข้อมูลก่อนหน้าก่อน)',
                      border: const OutlineInputBorder(),
                      suffixIcon: fieldController.text.isNotEmpty && enabled
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: AppColors.textHint),
                              onPressed: () {
                                fieldController.clear();
                                controller.clear();
                                onSelected?.call('');
                              },
                            )
                          : const Icon(Icons.arrow_drop_down, color: AppColors.textHint),
                    ),
                    onChanged: (value) {
                      controller.text = value;
                      onSelected?.call(value);
                    },
                  );
                },
                optionsViewBuilder: (context, onSelectedOption, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 320),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              dense: true,
                              title: Text(option, style: const TextStyle(fontFamily: AppStyles.fontFamily)),
                              onTap: () => onSelectedOption(option),
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            }

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
                            color: AppColors.border,
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
                                labelText: 'หมู่ (ถ้ามี)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      buildAutocompleteDropdown(
                        key: ValueKey('changwat_${changwatCtrl.text}'),
                        hintText: 'จังหวัด',
                        controller: changwatCtrl,
                        optionsBuilder: getProvinceOptions,
                        onSelected: (value) {
                          setModalState(() {
                            changwatCtrl.text = value;
                            amphoeCtrl.clear();
                            tambonCtrl.clear();
                            zipCtrl.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      buildAutocompleteDropdown(
                        key: ValueKey('amphoe_${changwatCtrl.text}_${amphoeCtrl.text}'),
                        hintText: 'อำเภอ / เขต',
                        controller: amphoeCtrl,
                        enabled: changwatCtrl.text.trim().isNotEmpty,
                        optionsBuilder: getAmphoeOptions,
                        onSelected: (value) {
                          setModalState(() {
                            amphoeCtrl.text = value;
                            tambonCtrl.clear();
                            zipCtrl.clear();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      buildAutocompleteDropdown(
                        key: ValueKey('tambon_${changwatCtrl.text}_${amphoeCtrl.text}_${tambonCtrl.text}'),
                        hintText: 'ตำบล / แขวง',
                        controller: tambonCtrl,
                        enabled: changwatCtrl.text.trim().isNotEmpty &&
                            amphoeCtrl.text.trim().isNotEmpty,
                        optionsBuilder: getTambonOptions,
                        onSelected: (value) {
                          setModalState(() {
                            tambonCtrl.text = value;
                            tryAutoFillZip();
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: zipCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'รหัสไปรษณีย์ (กรอกอัตโนมัติ)',
                          border: OutlineInputBorder(),
                        ),
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
      },
    );

    if (saved != true) return;

    final houseNo = houseNoCtrl.text.trim();
    final moo = mooCtrl.text.trim();
    final changwat = changwatCtrl.text.trim();
    final amphoe = amphoeCtrl.text.trim();
    final tambon = tambonCtrl.text.trim();
    final postalCode = zipCtrl.text.trim();

    setState(() {
      _profile.houseNo = houseNo;
      _profile.moo = moo;
      _profile.changwat = changwat;
      _profile.amphoe = amphoe;
      _profile.tambon = tambon;
      _profile.postalCode = postalCode;
    });

    await db.DatabaseHelper.instance.updateCustomerProfile(
      _profile.username,
      {
        'address': _profile.formattedAddress,
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
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      final cropped = await cropProfileImage(picked);
      if (cropped == null) return;
      if (!mounted) return;
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
            _Header(),
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
                                    value: _profile.fullName,
                                    isEditMode: _isEditMode,
                                    onEdit: _editFullName,
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
                                    label: 'อีเมล',
                                    value: _profile.email,
                                    isEditMode: _isEditMode,
                                    onEdit: _editEmail,
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
                                    isEditMode: _isEditMode,
                                    onEdit: () => _editField(
                                      label: 'หมายเลขโทรศัพท์',
                                      currentValue: _profile.phone,
                                      dbColumn: 'phone',
                                      onSaved: (v) => _profile.phone = v,
                                      keyboardType: TextInputType.phone,
                                    ),
                                  ),
                                  _ProfileRow(
                                    label: 'จำนวนเครื่องที่มี',
                                    value: '${_profile.machineCount}',
                                    editable: false,
                                    isLast: true,
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const MachineListPage(),
                                        ),
                                      );
                                    },
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

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const AppHeader(
      title: 'โปรไฟล์',
      showBack: false,
      trailing: ProfileSettingsButton(),
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
          const Text('ข้อมูลส่วนตัว', style: TextStyle(fontSize: 14)),
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
  final VoidCallback? onTap;
  final bool editable;
  final bool isLast;
  final bool isEditMode;

  const _ProfileRow({
    required this.label,
    required this.value,
    this.onEdit,
    this.onTap,
    this.editable = true,
    this.isLast = false,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : Border(
                    bottom: BorderSide(
                      color: Colors.black.withValues(alpha: 0.06),
                    ),
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
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 14,
                    color: Colors.grey,
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
        ),
      ),
    );
  }
}