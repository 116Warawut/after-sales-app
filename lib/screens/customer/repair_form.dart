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

class RepairFormScreen extends StatefulWidget {
  /// เครื่องจักรที่เลือกไว้ล่วงหน้า (เช่น มาจากปุ่ม "แจ้งซ่อม" ในหน้ารายละเอียดเครื่องจักร
  /// หรือจากการสแกน QR Code) — ถ้าระบุมา ฟอร์มจะเติมข้อมูลเครื่องจักรให้อัตโนมัติ
  final Machine? preselectedMachine;

  const RepairFormScreen({super.key, this.preselectedMachine});

  @override
  State<RepairFormScreen> createState() => _RepairFormScreenState();
}

class _RepairFormScreenState extends State<RepairFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  // 🟢 แยกที่อยู่เป็นช่องย่อย เพื่อให้ระบบ Geoapify แปลงพิกัดได้แม่นยำขึ้น
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _mooController = TextEditingController();
  final TextEditingController _tambonController = TextEditingController();
  final TextEditingController _amphoeController = TextEditingController();
  final TextEditingController _changwatController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // State Variables
  String _severity = 'ปกติ';
  final List<XFile> _selectedImages = [];
  bool _isLoadingProfile = true;
  bool _isSubmitting = false;

  // 🟢 เครื่องจักรที่เลือกจากการสแกน QR Code (ไม่บังคับ)
  Machine? _selectedMachine;
  bool _isLookingUpMachine = false;

  // พิกัดสำหรับ Geoapify Tracking
  double? _destLat;
  double? _destLng;
  // 🟢 ต้องให้ลูกค้ายืนยันตำแหน่งบนแผนที่เองก่อนส่งฟอร์ม (ไม่พึ่งผล Geocode อัตโนมัติล้วนๆ)
  bool _isLocationConfirmed = false;
  final bool _isLocating = false;

  final ImagePicker _picker = ImagePicker();
  final List<String> _severityOptions = ['ต่ำ', 'ปกติ', 'สูง', 'เร่งด่วน'];

  @override
  void initState() {
    super.initState();
    _selectedMachine = widget.preselectedMachine;
    for (final c in [
      _houseNoController,
      _mooController,
      _tambonController,
      _amphoeController,
      _changwatController,
      _zipCodeController,
    ]) {
      c.addListener(_onAddressFieldChanged);
    }
    _loadUserProfile();
  }

  // ถ้าลูกค้าแก้ไขที่อยู่หลังจากปักหมุดยืนยันไปแล้ว ให้ถือว่าหมุดเดิมอาจไม่ตรงกับที่อยู่ใหม่
  // จึงต้องให้ลูกค้าเปิดแผนที่ยืนยันตำแหน่งอีกครั้งก่อนส่งฟอร์ม
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
    _tambonController.dispose();
    _amphoeController.dispose();
    _changwatController.dispose();
    _zipCodeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// รวมช่องที่อยู่ย่อยทั้งหมดเป็นข้อความที่อยู่เต็ม (ใช้บันทึกงานซ่อม/ค้นหาพิกัดผ่าน Geoapify)
  String _buildFullAddress() {
    final houseNo = _houseNoController.text.trim();
    final moo = _mooController.text.trim();
    final tambon = _tambonController.text.trim();
    final amphoe = _amphoeController.text.trim();
    final changwat = _changwatController.text.trim();
    final postalCode = _zipCodeController.text.trim();

    // 🔴 [แก้ไข] เขียนคำนำหน้าเต็ม ๆ ("ตำบล"/"อำเภอ"/"จังหวัด") แทนตัวย่อ
    // ("ต."/"อ."/"จ.") และเติม "ประเทศไทย" ต่อท้าย — ตัวย่อแบบเดิมทำให้
    // เครื่องมือค้นหาที่อยู่ของ Geoapify จับคู่ชื่อสถานที่ในฐานข้อมูลผิดพลาด
    // บ่อย เพราะไม่รู้จักตัวย่อเหล่านี้ดีเท่าคำเต็ม ยิ่งไม่มีคำว่า "ประเทศไทย"
    // กำกับไว้ ยิ่งเสี่ยงจับคู่ไปเจอสถานที่ชื่อคล้ายกันในประเทศอื่นแทน
    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (moo.isNotEmpty) 'หมู่ $moo',
      if (tambon.isNotEmpty) 'ตำบล$tambon',
      if (amphoe.isNotEmpty) 'อำเภอ$amphoe',
      if (changwat.isNotEmpty) 'จังหวัด$changwat',
      if (postalCode.isNotEmpty) postalCode,
      'ประเทศไทย',
    ];
    return parts.join(' ').trim();
  }

  /// ตรวจสอบว่า Address มีข้อมูลที่พอจะ geocode ได้จริงหรือไม่
  /// (ไม่ใช่ค่าว่างเปล่าหรือค่า placeholder '-' ล้วนๆ)
  bool _hasRealAddress(Address addr) {
    bool isReal(String v) => v.trim().isNotEmpty && v.trim() != '-';
    return isReal(addr.houseNo) ||
        isReal(addr.tambon) ||
        isReal(addr.amphoe) ||
        isReal(addr.changwat);
  }

  // 1. ดึงข้อมูลที่อยู่และโปรไฟล์จากฐานข้อมูลตาราง customers มาใส่ช่องกรอกให้อัตโนมัติ
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
          final tambon = profile['tambon'] ?? '';
          final amphoe = profile['amphoe'] ?? '';
          final changwat = profile['changwat'] ?? '';
          final postalCode = profile['postal_code'] ?? '';

          setState(() {
            _nameController.text = fullName;
            _phoneController.text = phone;
            _houseNoController.text = houseNo;
            _mooController.text = (moo == '-') ? '' : moo;
            _tambonController.text = tambon;
            _amphoeController.text = amphoe;
            _changwatController.text = changwat;
            _zipCodeController.text = postalCode;
          });

          // 🏭 ถ้ามีเครื่องจักรที่เลือกไว้ล่วงหน้าและมีที่อยู่ติดตั้งจริง
          // ให้ใช้ที่อยู่ของเครื่องจักรแทนที่อยู่โปรไฟล์ลูกค้า เพราะเป็นจุดที่ช่างต้องไปซ่อมจริง
          final preselected = widget.preselectedMachine;
          if (preselected != null && _hasRealAddress(preselected.address)) {
            final addr = preselected.address;
            setState(() {
              _houseNoController.text = (addr.houseNo == '-') ? '' : addr.houseNo;
              _mooController.text = (addr.moo == '-') ? '' : addr.moo;
              _tambonController.text = (addr.tambon == '-') ? '' : addr.tambon;
              _amphoeController.text = (addr.amphoe == '-') ? '' : addr.amphoe;
              _changwatController.text =
                  (addr.changwat == '-') ? '' : addr.changwat;
              _zipCodeController.text = (addr.zipCode == '-') ? '' : addr.zipCode;
            });
          }

          // 📍 [แก้ไข] ไม่ลอง geocode ที่อยู่เพื่อเดาพิกัดอัตโนมัติแล้ว — ที่อยู่ที่กรอก
          // ไว้ตรงนี้ใช้เป็นแค่ "ข้อมูลอ้างอิง" (แสดงให้ช่าง/แอดมินเห็นว่าอยู่แถวไหน)
          // ส่วนตำแหน่งจริงที่ช่างจะไปซ่อม ให้ลูกค้าปักหมุดเองในแผนที่เท่านั้น แม่นกว่า
          // การเดาจากข้อความที่อยู่เสมอ (บางตำบลไม่มีข้อมูลพิกัดในระบบแผนที่เลย)
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

  // 1.5 สแกน QR Code บนตัวเครื่องจักร เพื่อดึงหมายเลข Serial Number
  //     แล้วค้นหาข้อมูลเครื่องจักร (ชื่อเครื่อง / รุ่น) จากฐานข้อมูล
  Future<void> _scanMachineQr() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrScannerPage(
          title: 'สแกน QR Code เครื่องจักร',
          hintText:
              'นำกล้องส่องไปที่ QR Code บนตัวเครื่องจักรที่ต้องการแจ้งซ่อม',
          // ✅ ยอมรับเฉพาะ QR Code ที่มีหมายเลข Serial Number (รูปแบบ 2-2-4)
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

  // 📍 เปิดหน้าปักหมุดตำแหน่งให้ลูกค้ายืนยันตำแหน่งที่ต้องการให้ช่างมาซ่อมด้วยตัวเอง
  // [แก้ไข] ไม่ลอง geocode ที่อยู่เพื่อเดาจุดเริ่มต้นอัตโนมัติอีกแล้ว — ให้ลูกค้าปักหมุด
  // เองทั้งหมด (แม่นกว่าเสมอ) ถ้าเคยปักหมุดไว้แล้วก่อนหน้านี้ในฟอร์มเดียวกัน จะใช้จุดนั้น
  // เป็นจุดเริ่มต้นต่อ ไม่งั้นเริ่มจากจุดกลางแผนที่เปล่า ๆ ให้เลื่อนหาเอง
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

  // 2. เลือกรูปภาพจากคลัง (2 - 6 รูป)
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

  // 3. ถ่ายภาพด้วยกล้อง (2 - 6 รูป)
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

  // 4. บันทึกข้อมูลลงฐานข้อมูล SQLite ตาราง repairs
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

    setState(() => _isSubmitting = true);

    try {
      final now = DateTime.now();
      final ticketNo =
          '#AS-${now.millisecondsSinceEpoch.toString().substring(7)}';

      final fullAddress = _buildFullAddress();

      // 📸 อัปโหลดรูปภาพทั้งหมดขึ้น Cloudinary ก่อน แล้วค่อยรวม URL ที่ได้เป็น String
      // คั่นด้วยเครื่องหมายจุลภาค (,) — เดิมเก็บแค่ path ไฟล์ในเครื่อง ซึ่งเครื่องอื่น
      // (เช่นแอดมิน/ช่างที่เปิดดูงานนี้จากอุปกรณ์คนละเครื่อง) เปิดดูไม่ได้เลย
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

      // 💾 บันทึกลง SQLite ตาราง repairs
      final newRepairId =
          await DatabaseHelper.instance.createRepair(newRepairData);

      // 🔔 แจ้งเตือนแอดมินทุกคนว่ามีงานแจ้งซ่อมใหม่เข้ามา
      final admins = await DatabaseHelper.instance.getAllAdmins();
      for (final admin in admins) {
        final adminUsername = admin['username'] as String?;
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

      // 🟢 ส่งค่า true กลับ เพื่อให้หน้าหลัก Reload ดึงข้อมูลใหม่
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เกิดข้อผิดพลาดในการส่งข้อมูล: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
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
            // 📌 AppHeader รูปแบบเดียวกับทั้งระบบ
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

                            // ชื่อ-นามสกุล
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

                            // เบอร์โทรศัพท์
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

                            // ที่อยู่ (แยกช่อง เพื่อให้ระบบแผนที่/ติดตามตำแหน่งทำงานได้แม่นยำ)
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
                                      labelText: 'หมู่',
                                      border: OutlineInputBorder(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // ตำบล
                            TextFormField(
                              controller: _tambonController,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'ตำบล *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_city,
                                    color: AppColors.primary),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'กรุณากรอกตำบล'
                                      : null,
                            ),
                            const SizedBox(height: 16),

                            // อำเภอ
                            TextFormField(
                              controller: _amphoeController,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'อำเภอ *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.location_city,
                                    color: AppColors.primary),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'กรุณากรอกอำเภอ'
                                      : null,
                            ),
                            const SizedBox(height: 16),

                            // จังหวัด
                            TextFormField(
                              controller: _changwatController,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              decoration: const InputDecoration(
                                labelText: 'จังหวัด *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.map,
                                    color: AppColors.primary),
                              ),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'กรุณากรอกจังหวัด'
                                      : null,
                            ),
                            const SizedBox(height: 16),

                            // รหัสไปรษณีย์
                            TextFormField(
                              controller: _zipCodeController,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(5),
                              ],
                              decoration: const InputDecoration(
                                labelText: 'รหัสไปรษณีย์ *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.markunread_mailbox,
                                    color: AppColors.primary),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'กรุณากรอกรหัสไปรษณีย์';
                                }
                                if (value.length != 5) {
                                  return 'รหัสไปรษณีย์ต้องมี 5 หลัก';
                                }
                                return null;
                              },
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

                            // ระดับความรุนแรง
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

                            // รายละเอียดปัญหา
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

                            // ส่วนแนบรูปภาพ
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

  /// การ์ดแสดง/เลือกเครื่องจักร ด้วยการสแกน QR Code
  /// การ์ดปักหมุด/ยืนยันตำแหน่งที่ตั้งของลูกค้า ที่จะส่งให้ช่างและแอดมินดู
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
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.precision_manufacturing,
                  color: Colors.white, size: 24),
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
