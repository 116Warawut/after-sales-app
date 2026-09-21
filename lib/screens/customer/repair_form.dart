import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart';
import 'package:after_sales/widgets.dart';
import 'package:after_sales/screens/customer/machine_models.dart';
import 'package:after_sales/screens/shared/qr_scanner_page.dart';
import 'package:after_sales/screens/shared/location_picker_page.dart';
import 'package:after_sales/utils/serial_number.dart';
import 'package:after_sales/utils/thai_address.dart';

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

class RepairFormScreen extends StatefulWidget {
  final Machine? preselectedMachine;

  const RepairFormScreen({super.key, this.preselectedMachine});

  @override
  State<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends State<RepairFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _mooController = TextEditingController();
  final TextEditingController _changwatController = TextEditingController();
  final TextEditingController _amphoeController = TextEditingController();
  final TextEditingController _tambonController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  String _severity = 'ปกติ';
  final List<XFile> _selectedImages = [];
  bool _isLoadingProfile = true;
  bool _isSubmitting = false;

  Machine? _selectedMachine;
  bool _isLookingUpMachine = false;

  double? _destLat;
  double? _destLng;
  bool _isLocationConfirmed = false;
  final bool _isLocating = false;

  final ImagePicker _picker = ImagePicker();
  final List<String> _severityOptions = ['ต่ำ', 'ปกติ', 'สูง', 'เร่งด่วน'];

  List<_ThaiProvince> _thaiProvinces = [];

  @override
  void initState() {
    super.initState();
    _selectedMachine = widget.preselectedMachine;
    for (final c in [
      _houseNoController,
      _mooController,
      _changwatController,
      _amphoeController,
      _tambonController,
      _zipCodeController,
    ]) {
      c.addListener(_onAddressFieldChanged);
    }
    _loadThaiAddressData().then((_) => _loadUserProfile());
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

  List<String> get _provinceOptions =>
      _thaiProvinces.map((p) => p.name).toList();

  List<String> get _amphoeOptions {
    final province = _changwatController.text.trim();
    final match = _thaiProvinces.where((p) => p.name == province);
    if (match.isEmpty) return [];
    return match.first.amphures.map((a) => a.name).toList();
  }

  List<String> get _tambonOptions {
    final province = _changwatController.text.trim();
    final amphoe = _amphoeController.text.trim();
    final provinceMatch = _thaiProvinces.where((p) => p.name == province);
    if (provinceMatch.isEmpty) return [];
    final amphoeMatch =
        provinceMatch.first.amphures.where((a) => a.name == amphoe);
    if (amphoeMatch.isEmpty) return [];
    return amphoeMatch.first.tambons.map((t) => t.name).toList();
  }

  void _tryAutoFillPostalCode() {
    final province = _changwatController.text.trim();
    final amphoe = _amphoeController.text.trim();
    final tambon = _tambonController.text.trim();

    final provinceMatch = _thaiProvinces.where((p) => p.name == province);
    if (provinceMatch.isEmpty) return;
    final amphoeMatch =
        provinceMatch.first.amphures.where((a) => a.name == amphoe);
    if (amphoeMatch.isEmpty) return;
    final tambonMatch =
        amphoeMatch.first.tambons.where((t) => t.name == tambon);
    if (tambonMatch.isEmpty) return;

    _zipCodeController.text = tambonMatch.first.zip;
  }

  void _onAddressFieldChanged() {
    if (_isLocationConfirmed) {
      setState(() => _isLocationConfirmed = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _houseNoController.dispose();
    _mooController.dispose();
    _changwatController.dispose();
    _amphoeController.dispose();
    _tambonController.dispose();
    _zipCodeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String _buildFullAddress() {
    final houseNo = _houseNoController.text.trim();
    final moo = _mooController.text.trim();
    // 🐛 [แก้บัค] เดิมใช้คำว่า 'ตำบล'/'อำเภอ' นำหน้าตายตัวทุกจังหวัด แต่ใน
    // กรุงเทพมหานคร หน่วยการปกครองย่อยเรียกว่า "แขวง"/"เขต" ไม่ใช่ "ตำบล"/
    // "อำเภอ" (ตามที่ผู้ใช้แจ้ง: ที่อยู่ที่บันทึกออกมาผิดเป็น "ตำบลวัดอรุณ
    // อำเภอบางกอกใหญ่" ทั้งที่ควรเป็น "แขวงวัดอรุณ เขตบางกอกใหญ่") นอกจากนี้
    // ข้อมูลดิบใน thai_address.json บางรายการก็มีคำว่า "เขต" ติดมาในชื่ออยู่
    // แล้ว (เช่น "เขตพระนคร") ทำให้ขึ้นซ้ำเป็น "อำเภอเขตพระนคร" — ใช้
    // _cleanAddressPrefix() ตัดคำนำหน้าที่อาจติดมาออกก่อน แล้วค่อยเลือกคำ
    // นำหน้าที่ถูกต้องเองตามจังหวัดอีกที
    final tambon = _cleanAddressPrefix(_tambonController.text);
    final amphoe = _cleanAddressPrefix(_amphoeController.text);
    final changwat = _cleanAddressPrefix(_changwatController.text);
    final postalCode = _zipCodeController.text.trim();
    final isBangkok = changwat == 'กรุงเทพมหานคร';

    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (moo.isNotEmpty) 'หมู่ $moo',
      if (tambon.isNotEmpty) '${isBangkok ? 'แขวง' : 'ตำบล'}$tambon',
      if (amphoe.isNotEmpty) '${isBangkok ? 'เขต' : 'อำเภอ'}$amphoe',
      if (changwat.isNotEmpty) 'จังหวัด$changwat',
      if (postalCode.isNotEmpty) postalCode,
      'ประเทศไทย',
    ];
    return parts.join(' ').trim();
  }

  bool _hasRealAddress(Address addr) {
    bool isReal(String v) => v.trim().isNotEmpty && v.trim() != '-';
    return isReal(addr.houseNo) ||
        isReal(addr.tambon) ||
        isReal(addr.amphoe) ||
        isReal(addr.changwat);
  }

  Future<void> _loadUserProfile() async {
    try {
      final username = Session.currentUsername;
      if (username.isNotEmpty) {
        final profile =
            await DatabaseHelper.instance.getCustomerProfile(username);

        if (profile != null && mounted) {
          final name = profile['name'] ?? '';
          final surname = profile['surname'] ?? '';
          final fullName = '$name $surname'.trim();
          final phone = profile['phone'] ?? '';
          final houseNo = profile['house_no'] ?? '';
          final moo = profile['moo'] ?? '';
          final changwat = _cleanAddressPrefix(profile['changwat']?.toString());
          final amphoe = _cleanAddressPrefix(profile['amphoe']?.toString());
          final tambon = _cleanAddressPrefix(profile['tambon']?.toString());
          final postalCode = profile['postal_code'] ?? '';

          setState(() {
            _nameController.text = fullName;
            _phoneController.text = phone;
            _houseNoController.text = houseNo;
            _mooController.text = (moo == '-') ? '' : moo;
            _changwatController.text = changwat;
            _amphoeController.text = amphoe;
            _tambonController.text = tambon;
            _zipCodeController.text = postalCode;
          });

          final preselected = widget.preselectedMachine;
          if (preselected != null && _hasRealAddress(preselected.address)) {
            final addr = preselected.address;
            setState(() {
              _houseNoController.text = (addr.houseNo == '-') ? '' : addr.houseNo;
              _mooController.text = (addr.moo == '-') ? '' : addr.moo;
              _changwatController.text = _cleanAddressPrefix(addr.changwat);
              _amphoeController.text = _cleanAddressPrefix(addr.amphoe);
              _tambonController.text = _cleanAddressPrefix(addr.tambon);
              _zipCodeController.text = (addr.zipCode == '-') ? '' : addr.zipCode;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('เกิดข้อผิดพลาดในการดึงข้อมูลโปรไฟล์: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfile = false);
      }
    }
  }

  Future<void> _scanMachineQr() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrScannerPage(
          title: 'สแกน QR Code เครื่องจักร',
          hintText:
              'นำกล้องส่องไปที่ QR Code บนตัวเครื่องจักรที่ต้องการแจ้งซ่อม',
          valueExtractor: extractSerialNumberFromQr,
          invalidValueMessage:
              'QR Code นี้ไม่ใช่หมายเลข Serial Number ($kSerialNumberLength หลัก) ลองสแกนใหม่อีกครั้ง',
        ),
      ),
    );

    if (scannedValue == null || scannedValue.trim().isEmpty || !mounted) {
      return;
    }

    setState(() => _isLookingUpMachine = true);
    try {
      final username = Session.currentUsername;
      final row = await DatabaseHelper.instance.getMachineBySerialNumber(
        scannedValue,
        customerUsername: username.isNotEmpty ? username : null,
      );

      if (!mounted) return;

      if (row == null) {
        _showSnackBar(
          'ไม่พบเครื่องจักรที่มีหมายเลข Serial "$scannedValue" ในระบบ',
          isError: true,
        );
        return;
      }

      final machine = Machine.fromMap(row);
      setState(() => _selectedMachine = machine);
      _showSnackBar('เลือกเครื่องจักร: ${machine.modelName}');
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เกิดข้อผิดพลาดในการค้นหาเครื่องจักร: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLookingUpMachine = false);
    }
  }

  void _clearSelectedMachine() {
    setState(() => _selectedMachine = null);
  }

  Future<void> _openLocationPicker() async {
    final initLat = _destLat;
    final initLng = _destLng;

    final result = await Navigator.of(context).push<Map<String, double>>(
      MaterialPageRoute(
        builder: (context) => LocationPickerPage(
          initialLat: initLat,
          initialLng: initLng,
          title: 'ปักหมุดตำแหน่งที่ต้องการให้ช่างมาซ่อม',
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _destLat = result['lat'];
        _destLng = result['lng'];
        _isLocationConfirmed = true;
      });
      _showSnackBar('ยืนยันตำแหน่งที่ปักหมุดเรียบร้อยแล้ว');
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      if (_selectedImages.length >= 6) {
        _showSnackBar('สามารถแนบรูปภาพได้สูงสุด 6 รูปเท่านั้น');
        return;
      }

      final List<XFile> pickedFiles =
          await _picker.pickMultiImage(imageQuality: 80);

      if (!mounted) return;

      if (pickedFiles.isNotEmpty) {
        setState(() {
          final remainingCapacity = 6 - _selectedImages.length;
          _selectedImages.addAll(pickedFiles.take(remainingCapacity));
        });
      }
    } catch (e) {
      _handleImageError(e);
    }
  }

  Future<void> _pickImageFromCamera() async {
    try {
      if (_selectedImages.length >= 6) {
        _showSnackBar('สามารถแนบรูปภาพได้สูงสุด 6 รูปเท่านั้น');
        return;
      }

      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (!mounted) return;

      if (pickedFile != null) {
        setState(() {
          _selectedImages.add(pickedFile);
        });
      }
    } catch (e) {
      _handleImageError(e);
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _handleImageError(dynamic error) {
    if (!mounted) return;
    _showSnackBar('เกิดข้อผิดพลาดในการดึงรูปภาพ: $error', isError: true);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: AppStyles.fontFamily),
        ),
        backgroundColor: isError ? Colors.red.shade700 : AppColors.primary,
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedImages.length < 2) {
      _showSnackBar('กรุณาแนบรูปภาพประกอบอย่างน้อย 2 รูป', isError: true);
      return;
    }

    if (!_isLocationConfirmed || _destLat == null || _destLng == null) {
      _showSnackBar('กรุณาปักหมุดยืนยันตำแหน่งที่ต้องการให้ช่างมาซ่อมก่อนส่งฟอร์ม',
          isError: true);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final ticketNo =
          '#AS-${now.millisecondsSinceEpoch.toString().substring(7)}';

      final fullAddress = _buildFullAddress();

      final imageUrls = await CloudinaryService.uploadImages(_selectedImages);
      final imagePathsString = imageUrls.join(',');

      final currentUsername = Session.currentUsername.isNotEmpty
          ? Session.currentUsername
          : 'somchai_j';

      final newRepairData = {
        'ticketNo': ticketNo,
        'customer_username': currentUsername,
        'machine_id': _selectedMachine?.id,
        'machine': _selectedMachine?.modelName ?? 'อุปกรณ์บริการทั่วไป',
        'serial_number': _selectedMachine?.serialNumber,
        'date': '${now.day}/${now.month}/${now.year + 543}',
        'location': fullAddress,
        'status': 'รอจัดสรรช่าง',
        'detail':
            '[ความรุนแรง: $_severity] ${_descriptionController.text.trim()}',
        'images': imagePathsString,
        'progress': 0.0,
        'total_price': 0.0,
        'is_paid': 0,
        'created_at': now.toIso8601String(),
        'dest_lat': _destLat,
        'dest_lng': _destLng,
      };

      final newRepairId =
          await DatabaseHelper.instance.createRepair(newRepairData);

      final admins = await DatabaseHelper.instance.getAllAdmins();
      for (final admin in admins) {
        final adminUsername = admin['username']?.toString();
        if (adminUsername == null) continue;
        await DatabaseHelper.instance.createNotification({
          'user_username': adminUsername,
          'role': 'ADMIN',
          'title': 'มีงานแจ้งซ่อมใหม่',
          'message': 'ลูกค้าแจ้งซ่อมใหม่ $ticketNo กรุณามอบหมายช่าง',
          'type': 'REPAIR_CREATED',
          'target_id': newRepairId,
          'is_read': 0,
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ส่งข้อมูลแจ้งซ่อมเรียบร้อยแล้ว',
            style: TextStyle(fontFamily: AppStyles.fontFamily),
          ),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เกิดข้อผิดพลาดในการส่งข้อมูล: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // 🐛 [แก้บัค] เดิมช่องจังหวัด/อำเภอ/ตำบลใช้ Autocomplete ของตัวเอง โดยผูก
  // ValueKey กับข้อความในช่อง + เรียก onSelected (ซึ่ง setState และล้างอำเภอ/
  // ตำบล) ทุกครั้งที่พิมพ์/ลบตัวอักษร ทำให้ key เปลี่ยนทุกตัวอักษร → widget ถูก
  // สร้างใหม่ → เสียโฟกัส/คีย์บอร์ดเด้ง ลบได้ทีละตัวแล้วหลุด และอำเภอ/ตำบลถูก
  // ล้างทิ้ง จึงเปลี่ยนมาใช้ ThaiAddressAutocompleteField (utils/thai_address.dart)
  // ตัวเดียวกับหน้าอื่น ๆ ที่แก้ปัญหานี้ไปแล้ว: onSelected จะถูกเรียกเฉพาะตอน
  // "เลือกรายการ" หรือกดปุ่ม ✕ เท่านั้น ไม่ถูกเรียกระหว่างพิมพ์/ลบ
  Widget _buildAutocompleteField({
    required String labelText,
    required String hintText,
    required TextEditingController controller,
    required List<String> Function() optionsBuilder,
    void Function(String selected)? onSelected,
    String? Function(String?)? validator,
    bool enabled = true,
    bool moveToNextField = true,
  }) {
    return ThaiAddressAutocompleteField(
      labelText: hintText,
      controller: controller,
      optionsBuilder: optionsBuilder,
      onSelected: onSelected,
      enabled: enabled,
      validator: validator,
      moveToNextField: moveToNextField,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(
              title: 'แบบฟอร์มแจ้งซ่อม',
              showBack: true,
            ),
            Expanded(
              child: _isLoadingProfile
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'ข้อมูลผู้แจ้ง',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.textMain,
                              ),
                            ),
                            const SizedBox(height: 12),

                            TextFormField(
                              controller: _nameController,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'ชื่อ-นามสกุล *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person,
                                    color: AppColors.primary),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'กรุณากรอกชื่อ-นามสกุล'
                                      : null,
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _phoneController,
                              keyboardType: TextInputType.phone,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              decoration: const InputDecoration(
                                labelText: 'เบอร์โทรศัพท์ *',
                                border: OutlineInputBorder(),
                                prefixIcon:
                                    Icon(Icons.phone, color: AppColors.primary),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'กรุณากรอกเบอร์โทรศัพท์';
                                }
                                if (value.length < 9 || value.length > 10) {
                                  return 'กรุณากรอกเบอร์โทรศัพท์ 9-10 หลัก';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            // ที่อยู่ (เรียงแบบมีตรรกะ: บ้านเลขที่ -> จังหวัด -> อำเภอ -> ตำบล -> รหัสไปรษณีย์)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _houseNoController,
                                    style: const TextStyle(
                                        fontFamily: AppStyles.fontFamily),
                                    decoration: const InputDecoration(
                                      labelText: 'บ้านเลขที่ *',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.home,
                                          color: AppColors.primary),
                                    ),
                                    validator: (value) =>
                                        (value == null || value.trim().isEmpty)
                                            ? 'กรุณากรอกบ้านเลขที่'
                                            : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    controller: _mooController,
                                    style: const TextStyle(
                                        fontFamily: AppStyles.fontFamily),
                                    decoration: const InputDecoration(
                                      labelText: 'หมู่ (ถ้ามี)',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            _buildAutocompleteField(
                              labelText: 'จังหวัด *',
                              hintText: 'เลือกจังหวัด',
                              controller: _changwatController,
                              optionsBuilder: () => _provinceOptions,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาเลือกจังหวัด' : null,
                              onSelected: (value) {
                                setState(() {
                                  _changwatController.text = value;
                                  _amphoeController.clear();
                                  _tambonController.clear();
                                  _zipCodeController.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            _buildAutocompleteField(
                              labelText: 'อำเภอ / เขต *',
                              hintText: 'เลือกอำเภอ / เขต',
                              controller: _amphoeController,
                              enabled: _changwatController.text.trim().isNotEmpty,
                              optionsBuilder: () => _amphoeOptions,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาเลือกอำเภอ / เขต' : null,
                              onSelected: (value) {
                                setState(() {
                                  _amphoeController.text = value;
                                  _tambonController.clear();
                                  _zipCodeController.clear();
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            _buildAutocompleteField(
                              labelText: 'ตำบล / แขวง *',
                              hintText: 'เลือกตำบล / แขวง',
                              moveToNextField: false,
                              controller: _tambonController,
                              enabled: _changwatController.text.trim().isNotEmpty &&
                                  _amphoeController.text.trim().isNotEmpty,
                              optionsBuilder: () => _tambonOptions,
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณาเลือกตำบล / แขวง' : null,
                              onSelected: (value) {
                                setState(() {
                                  _tambonController.text = value;
                                  _tryAutoFillPostalCode();
                                });
                              },
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _zipCodeController,
                              readOnly: true,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'รหัสไปรษณีย์ (กรอกอัตโนมัติ) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.markunread_mailbox,
                                    color: AppColors.primary),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'กรุณาระบุรหัสไปรษณีย์';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 8),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline,
                                    size: 15, color: Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'ที่อยู่ด้านบนใช้เป็นข้อมูลอ้างอิงเท่านั้น '
                                    'ตำแหน่งจริงที่ช่างจะไปซ่อมให้ยึดตามหมุดที่ปัก'
                                    'ในแผนที่ด้านล่างเป็นหลัก',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontFamily: AppStyles.fontFamily,
                                      color: Colors.grey.shade600,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),

                            const Text(
                              'ตำแหน่งที่ตั้งสำหรับช่าง',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.textMain,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildLocationSection(),
                            const SizedBox(height: 24),

                            const Text(
                              'เครื่องจักรที่ต้องการแจ้งซ่อม',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.textMain,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildMachineSection(),
                            const SizedBox(height: 24),

                            const Text(
                              'รายละเอียดการแจ้งซ่อม',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.textMain,
                              ),
                            ),
                            const SizedBox(height: 12),

                            DropdownButtonFormField<String>(
                              initialValue: _severity,
                              style: const TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.textMain,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'ระดับความรุนแรง *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.warning_amber_rounded,
                                    color: AppColors.primary),
                              ),
                              items: _severityOptions.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                if (newValue != null) {
                                  setState(() => _severity = newValue);
                                }
                              },
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _descriptionController,
                              maxLines: 4,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'รายละเอียดปัญหา/อาการ *',
                                hintText:
                                    'อธิบายอาการเสีย หรือจุดที่ต้องการให้ซ่อมแซม...',
                                border: OutlineInputBorder(),
                                alignLabelWithHint: true,
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'กรุณาระบุรายละเอียดปัญหา'
                                      : null,
                            ),
                            const SizedBox(height: 24),

                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'แนบรูปภาพประกอบ (${_selectedImages.length}/6) *',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: AppStyles.fontFamily,
                                  ),
                                ),
                                const Text(
                                  'ต้องแนบ 2-6 รูป',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontFamily: AppStyles.fontFamily,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            _buildImagePickerSection(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _handleSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'ส่งข้อมูลแจ้งซ่อม',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLocationSection() {
    if (_isLocationConfirmed && _destLat != null && _destLng != null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green.shade300),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.green.shade600,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ยืนยันตำแหน่งที่ปักหมุดแล้ว',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppStyles.fontFamily,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_destLat!.toStringAsFixed(6)}, ${_destLng!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: AppStyles.fontFamily,
                      color: AppColors.textLabel,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: _isLocating ? null : _openLocationPicker,
              child: const Text(
                'แก้ไข',
                style: TextStyle(fontFamily: AppStyles.fontFamily),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _isLocating ? null : _openLocationPicker,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            side: const BorderSide(color: AppColors.primary),
          ),
          icon: _isLocating
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.pin_drop_outlined, color: AppColors.primary),
          label: Text(
            _isLocating ? 'กำลังค้นหาตำแหน่งเริ่มต้น...' : 'ปักหมุดตำแหน่งของคุณ',
            style: const TextStyle(fontFamily: AppStyles.fontFamily),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'ที่อยู่ด้านบนใช้เป็นข้อมูลอ้างอิงเท่านั้น กรุณาเปิดแผนที่แล้วเลื่อนไปปักหมุด'
          ' ณ ตำแหน่งจริงที่ต้องการให้ช่างมาซ่อมด้วยตัวเอง',
          style: TextStyle(
            fontSize: 12,
            fontFamily: AppStyles.fontFamily,
            color: AppColors.textLabel,
          ),
        ),
      ],
    );
  }

  Widget _buildMachineSection() {
    if (_selectedMachine != null) {
      final machine = _selectedMachine!;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LocalOrNetworkImage(
                path: machine.photoUrl,
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
                    machine.label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFamily: AppStyles.fontFamily,
                      color: AppColors.textMain,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'รุ่น: ${machine.modelName}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppStyles.fontFamily,
                      color: AppColors.textLabel,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'S/N: ${machine.serialNumber}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: AppStyles.fontFamily,
                      color: AppColors.textLabel,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: _isLookingUpMachine ? null : _clearSelectedMachine,
              icon: const Icon(Icons.close, color: AppColors.textHint),
              tooltip: 'ยกเลิกการเลือกเครื่องจักร',
            ),
          ],
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _isLookingUpMachine ? null : _scanMachineQr,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        side: const BorderSide(color: AppColors.primary),
      ),
      icon: _isLookingUpMachine
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.qr_code_scanner, color: AppColors.primary),
      label: Text(
        _isLookingUpMachine
            ? 'กำลังค้นหาเครื่องจักร...'
            : 'สแกน QR Code เพื่อเลือกเครื่องจักร',
        style: const TextStyle(fontFamily: AppStyles.fontFamily),
      ),
    );
  }

  Widget _buildImagePickerSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _selectedImages.length >= 6 ? null : _pickImageFromGallery,
                icon: const Icon(Icons.photo_library, color: AppColors.primary),
                label: const Text(
                  'เลือกจากคลังภาพ',
                  style: TextStyle(fontFamily: AppStyles.fontFamily),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    _selectedImages.length >= 6 ? null : _pickImageFromCamera,
                icon: const Icon(Icons.camera_alt, color: AppColors.primary),
                label: const Text(
                  'ถ่ายภาพ',
                  style: TextStyle(fontFamily: AppStyles.fontFamily),
                ),
              ),
            ),
          ],
        ),
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _selectedImages.length,
            itemBuilder: (context, index) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      File(_selectedImages[index].path),
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removeImage(index),
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}