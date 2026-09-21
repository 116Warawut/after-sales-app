import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:after_sales/screens/shared/qr_scanner_page.dart';
import 'package:after_sales/utils/serial_number.dart';
import 'package:after_sales/utils/thai_address.dart';

/// ==========================================
/// ➕ หน้าเพิ่มเครื่องจักรใหม่ (Machine List)
/// ==========================================
/// รองรับการกรอกข้อมูลด้วยตนเอง หรือสแกน QR Code บนตัวเครื่องจักร
/// เพื่อดึงหมายเลข Serial Number มาใส่ในฟอร์มโดยอัตโนมัติ
class AddMachinePage extends StatefulWidget {
  const AddMachinePage({super.key});

  @override
  State<AddMachinePage> createState() => _AddMachinePageState();
}

class _AddMachinePageState extends State<AddMachinePage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _labelController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _serialController = TextEditingController();
  final TextEditingController _typeController = TextEditingController();
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _mooController = TextEditingController();
  final TextEditingController _tambonController = TextEditingController();
  final TextEditingController _amphoeController = TextEditingController();
  final TextEditingController _changwatController = TextEditingController();
  final TextEditingController _zipCodeController = TextEditingController();

  bool _isSaving = false;

  // 🆕 [ใหม่] รายชื่อจังหวัด/อำเภอ/ตำบล — ใช้กับช่องค้นหาแบบ Autocomplete ให้
  // พิมพ์ค้นหาได้และไล่ระดับจังหวัด -> อำเภอ/เขต -> ตำบล/แขวง เหมือนหน้า
  // ลงทะเบียน/แจ้งซ่อม (เดิมหน้านี้เป็นช่องพิมพ์เปล่า ๆ ไม่มีการค้นหา/ไล่ระดับ
  // เลย ทำให้พิมพ์ชื่ออำเภอ/ตำบลผิดหรือไม่ตรงกับข้อมูลจริงได้ง่าย)
  List<ThaiProvince> _thaiProvinces = [];

  // 📷 รูปภาพเครื่องจักร (เลือกจากแกลเลอรีหรือถ่ายรูปใหม่)
  final ImagePicker _picker = ImagePicker();
  String _photoPath = '';
  // ไฟล์รูปที่เพิ่งเลือกไว้ (ยังไม่อัปโหลด) — จะอัปโหลดขึ้น Cloudinary จริง ๆ
  // ตอนกด "บันทึก" เท่านั้น กันอัปโหลดทิ้งเปล่า ๆ ถ้าผู้ใช้เปลี่ยนใจเลือกรูปใหม่ก่อนบันทึก
  XFile? _pickedPhotoFile;

  @override
  void initState() {
    super.initState();
    loadThaiProvinces().then((provinces) {
      if (!mounted) return;
      setState(() => _thaiProvinces = provinces);
    });
  }

  @override
  void dispose() {
    _labelController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _typeController.dispose();
    _houseNoController.dispose();
    _mooController.dispose();
    _tambonController.dispose();
    _amphoeController.dispose();
    _changwatController.dispose();
    _zipCodeController.dispose();
    super.dispose();
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

  /// เลือกรูปภาพเครื่องจักรจากแกลเลอรีหรือถ่ายรูปใหม่ด้วยกล้อง
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.primary),
              title: const Text('ถ่ายรูปใหม่',
                  style: TextStyle(fontFamily: AppStyles.fontFamily)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('เลือกจากคลังภาพ',
                  style: TextStyle(fontFamily: AppStyles.fontFamily)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null || !mounted) return;
      setState(() {
        _photoPath = picked.path;
        _pickedPhotoFile = picked;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เลือกรูปไม่สำเร็จ: $e', isError: true);
    }
  }

  /// สแกน QR Code บนตัวเครื่องจักรเพื่อดึงหมายเลข Serial Number มาใส่ในฟอร์ม
  Future<void> _scanSerialNumber() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrScannerPage(
          title: 'สแกน QR Code เครื่องจักร',
          hintText: 'นำกล้องส่องไปที่ QR Code บนตัวเครื่องจักรเพื่อดึงหมายเลข Serial',
          // ✅ ยอมรับเฉพาะ QR Code ที่มีหมายเลข Serial Number (รูปแบบ 2-2-4)
          // เท่านั้น กัน QR Code อื่น ๆ ที่ไม่เกี่ยวข้องหลุดเข้ามาในฟอร์ม
          valueExtractor: extractSerialNumberFromQr,
          invalidValueMessage:
              'QR Code นี้ไม่ใช่หมายเลข Serial Number ($kSerialNumberLength หลัก) ลองสแกนใหม่อีกครั้ง',
        ),
      ),
    );

    if (scannedValue == null || scannedValue.trim().isEmpty || !mounted) {
      return;
    }

    setState(() => _serialController.text = scannedValue.trim());
    _showSnackBar('ดึงหมายเลข Serial จาก QR Code เรียบร้อยแล้ว');
  }

  Future<void> _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final username = db.Session.currentUsername;
      final serialNumber = normalizeSerialNumber(_serialController.text);

      // กันการเพิ่มเครื่องจักรซ้ำด้วยหมายเลข Serial เดียวกัน
      final existing = await db.DatabaseHelper.instance
          .getMachineBySerialNumber(serialNumber, customerUsername: username);
      if (existing != null) {
        if (!mounted) return;
        _showSnackBar('มีเครื่องจักรที่ใช้หมายเลข Serial นี้อยู่แล้ว', isError: true);
        return;
      }

      // 📤 อัปโหลดรูปเครื่องจักรขึ้น Cloudinary ตอนกดบันทึกจริง ๆ (ถ้ามีเลือกรูปไว้)
      // เดิมเก็บแค่ path ไฟล์ในเครื่อง เครื่องอื่นที่ล็อกอินเปิดดูจะไม่เห็นรูปเลย
      String photoUrl = _photoPath;
      if (_pickedPhotoFile != null) {
        photoUrl = await CloudinaryService.uploadImage(_pickedPhotoFile!);
      }

      await db.DatabaseHelper.instance.createMachine({
        'customer_username': username,
        'label': _labelController.text.trim(),
        'model_name': _modelController.text.trim(),
        'serial_number': serialNumber,
        'type': _typeController.text.trim(),
        'status': 'พร้อมใช้งาน',
        'house_no': _houseNoController.text.trim(),
        'moo': _mooController.text.trim(),
        'tambon': _tambonController.text.trim(),
        'amphoe': _amphoeController.text.trim(),
        'changwat': _changwatController.text.trim(),
        'zip_code': _zipCodeController.text.trim(),
        'photo_url': photoUrl,
      });

      if (!mounted) return;
      _showSnackBar('เพิ่มเครื่องจักรเรียบร้อยแล้ว');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('เกิดข้อผิดพลาดในการบันทึกข้อมูล: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              const AppHeader(title: 'เพิ่มเครื่องจักร', showBack: true),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 📷 รูปภาพเครื่องจักร
                        Center(
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _photoPath.isEmpty
                                      ? Container(
                                          width: 140,
                                          height: 140,
                                          color: Colors.grey.shade200,
                                          alignment: Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.add_a_photo_outlined,
                                                  size: 32,
                                                  color: Colors.grey.shade500),
                                              const SizedBox(height: 6),
                                              Text(
                                                'เพิ่มรูปเครื่องจักร',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontFamily:
                                                      AppStyles.fontFamily,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : LocalOrNetworkImage(
                                          path: _photoPath,
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
                                      onTap: _pickPhoto,
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
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'ข้อมูลเครื่องจักร',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppStyles.fontFamily,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // หมายเลข Serial Number + ปุ่มสแกน QR Code
                        TextFormField(
                          controller: _serialController,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily),
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            // รูปแบบ 2-2-4: ตัวอักษร 2 ตัว + ตัวเลข 6 หลัก
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]')),
                            LengthLimitingTextInputFormatter(
                                kSerialNumberLength),
                            _UpperCaseTextFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: 'หมายเลข Serial Number *',
                            hintText: 'เช่น PM260145',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.confirmation_number,
                                color: AppColors.primary),
                            suffixIcon: IconButton(
                              onPressed: _scanSerialNumber,
                              icon: const Icon(Icons.qr_code_scanner,
                                  color: AppColors.primary),
                              tooltip: 'สแกน QR Code',
                            ),
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'กรุณากรอกหรือสแกนหมายเลข Serial Number';
                            }
                            if (!isValidSerialNumber(trimmed)) {
                              return serialNumberFormatError;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // ชื่อเครื่อง/ป้ายชื่อ
                        TextFormField(
                          controller: _labelController,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'ชื่อเครื่องจักร *',
                            hintText: 'เช่น เครื่องพิมพ์ A, ปั๊มน้ำโซน 2',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.label,
                                color: AppColors.primary),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'กรุณากรอกชื่อเครื่องจักร'
                                  : null,
                        ),
                        const SizedBox(height: 16),

                        // รุ่น
                        TextFormField(
                          controller: _modelController,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'รุ่น (Model) *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.precision_manufacturing,
                                color: AppColors.primary),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'กรุณากรอกรุ่นของเครื่องจักร'
                                  : null,
                        ),
                        const SizedBox(height: 16),

                        // ประเภทเครื่องจักร
                        TextFormField(
                          controller: _typeController,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'ประเภทเครื่องจักร',
                            hintText: 'เช่น Printer, ปั๊มน้ำ, เครื่องอัดลม',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.category,
                                color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'สถานที่ติดตั้ง (ไม่บังคับ)',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppStyles.fontFamily,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),

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
                                  labelText: 'บ้านเลขที่',
                                  border: OutlineInputBorder(),
                                ),
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

                        // 🐛 [แก้บัค] เดิมเป็นช่องพิมพ์เปล่า ๆ เรียงตำบล->อำเภอ->
                        // จังหวัด (เล็กไปใหญ่ และพิมพ์เองไม่มีเช็คถูกต้อง) —
                        // เปลี่ยนเป็นช่องค้นหาแบบเดียวกับหน้าลงทะเบียน/แจ้งซ่อม
                        // เรียงจังหวัด -> อำเภอ/เขต -> ตำบล/แขวง (ใหญ่ไปเล็ก)
                        // พิมพ์ค้นหาได้ และไล่ระดับตามจังหวัด/อำเภอที่เลือกไว้
                        // ก่อนหน้า พร้อมเติมรหัสไปรษณีย์ให้อัตโนมัติ
                        ThaiAddressAutocompleteField(
                          labelText: 'จังหวัด',
                          controller: _changwatController,
                          optionsBuilder: () =>
                              _thaiProvinces.map((p) => p.name).toList(),
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

                        ThaiAddressAutocompleteField(
                          labelText: 'อำเภอ / เขต',
                          controller: _amphoeController,
                          enabled: _changwatController.text.trim().isNotEmpty,
                          optionsBuilder: () => thaiAmphoeOptions(
                              _thaiProvinces, _changwatController.text),
                          onSelected: (value) {
                            setState(() {
                              _amphoeController.text = value;
                              _tambonController.clear();
                              _zipCodeController.clear();
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        ThaiAddressAutocompleteField(
                          labelText: 'ตำบล / แขวง',
                          moveToNextField: false,
                          controller: _tambonController,
                          enabled: _changwatController.text.trim().isNotEmpty &&
                              _amphoeController.text.trim().isNotEmpty,
                          optionsBuilder: () => thaiTambonOptions(
                              _thaiProvinces,
                              _changwatController.text,
                              _amphoeController.text),
                          onSelected: (value) {
                            setState(() {
                              _tambonController.text = value;
                              final zip = thaiZipFor(
                                  _thaiProvinces,
                                  _changwatController.text,
                                  _amphoeController.text,
                                  value);
                              if (zip != null) _zipCodeController.text = zip;
                            });
                          },
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _zipCodeController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'รหัสไปรษณีย์ (กรอกอัตโนมัติ)',
                            border: OutlineInputBorder(),
                          ),
                        ),
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
                onPressed: _isSaving ? null : _handleSave,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text(
                        'บันทึกเครื่องจักร',
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
      ),
    );
  }
}

/// แปลงตัวอักษรที่พิมพ์ในช่อง Serial Number ให้เป็นตัวพิมพ์ใหญ่ทันทีที่พิมพ์
/// (ใช้คู่กับ [normalizeSerialNumber] ตอนบันทึก/ตรวจซ้ำ ให้ค่าที่เก็บสม่ำเสมอกัน)
class _UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
