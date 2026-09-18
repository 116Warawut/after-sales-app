import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show
        rootBundle,
        FilteringTextInputFormatter,
        LengthLimitingTextInputFormatter,
        TextInputFormatter;
import 'package:after_sales/app_styles.dart'; 
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/services.dart'; 

/// ขั้นตอนของหน้าลงทะเบียน: กรอกฟอร์ม -> ยืนยัน OTP อีเมล
enum _RegisterStep { form, verifyOtp }

/// โครงสร้างข้อมูลจังหวัด/อำเภอ/ตำบล/รหัสไปรษณีย์ (โหลดจาก assets/data/thai_address.json)
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

/// ตัดคำนำหน้าจังหวัด/อำเภอ/ตำบล ที่อาจติดมากับข้อมูลดิบใน thai_address.json
/// ออกก่อน (เช่น "เขตพระนคร") ป้องกันขึ้นซ้ำตอนเลือกคำนำหน้าเอง (ดู
/// _buildFullAddress() ด้านล่าง)
String _cleanAddressPrefix(String? text) {
  if (text == null) return '';
  var s = text.trim();
  if (s == '-' || s.isEmpty) return '';
  const prefixes = ['อำเภอ', 'อ.', 'อ ', 'เขต', 'ตำบล', 'ต.', 'ต ', 'แขวง'];
  for (final p in prefixes) {
    if (s.startsWith(p)) {
      s = s.substring(p.length).trim();
    }
  }
  return s;
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false; // State สำหรับโหลดตอนกดลงทะเบียน / ส่ง OTP

  _RegisterStep _step = _RegisterStep.form;
  final TextEditingController _otpController = TextEditingController();
  String _generatedOtp = '';
  DateTime? _otpExpiresAt;
  int _failedOtpAttempts = 0;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _companyController = TextEditingController();
  // 🟢 แยกที่อยู่เป็นช่องย่อย เพื่อให้ประกอบเป็นที่อยู่เต็มสำหรับใช้กับ Geoapify ได้แม่นยำขึ้น
  final TextEditingController _houseNoController = TextEditingController();
  final TextEditingController _mooController = TextEditingController();
  final TextEditingController _tambonController = TextEditingController();
  final TextEditingController _amphoeController = TextEditingController();
  final TextEditingController _changwatController = TextEditingController();
  final TextEditingController _postalCodeController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // ข้อมูลจังหวัด/อำเภอ/ตำบล/รหัสไปรษณีย์ทั้งประเทศ (โหลดครั้งเดียวตอนเปิดหน้า)
  List<_ThaiProvince> _thaiProvinces = [];
  // ignore: unused_field
  bool _thaiAddressLoaded = false;

  @override
  void initState() {
    super.initState();
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
        _thaiAddressLoaded = true;
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

  /// เติมรหัสไปรษณีย์อัตโนมัติเมื่อจังหวัด/อำเภอ/ตำบล ตรงกับข้อมูลพอดี
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

    _postalCodeController.text = tambonMatch.first.zip;
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _otpController.dispose();
    _nameController.dispose();
    _companyController.dispose();
    _houseNoController.dispose();
    _mooController.dispose();
    _tambonController.dispose();
    _amphoeController.dispose();
    _changwatController.dispose();
    _postalCodeController.dispose();
    _phoneController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// รวมช่องที่อยู่ย่อยทั้งหมดเป็นข้อความที่อยู่เต็ม (ใช้แสดงผล/ค้นหาพิกัดผ่าน Geoapify)
  /// 🐛 [แก้บัค] เดิมใช้ 'ต.'/'อ.' นำหน้าตายตัวทุกจังหวัด แต่กรุงเทพมหานคร
  /// ใช้ "แขวง"/"เขต" (ดูรายละเอียดปัญหาเดียวกันใน repair_form.dart)
  String _buildFullAddress() {
    final houseNo = _houseNoController.text.trim();
    final moo = _mooController.text.trim();
    final tambon = _cleanAddressPrefix(_tambonController.text);
    final amphoe = _cleanAddressPrefix(_amphoeController.text);
    final changwat = _cleanAddressPrefix(_changwatController.text);
    final postalCode = _postalCodeController.text.trim();
    final isBangkok = changwat == 'กรุงเทพมหานคร';

    final parts = <String>[
      if (houseNo.isNotEmpty) houseNo,
      if (moo.isNotEmpty) 'หมู่ $moo',
      if (tambon.isNotEmpty) '${isBangkok ? 'แขวง' : 'ต.'}$tambon',
      if (amphoe.isNotEmpty) '${isBangkok ? 'เขต' : 'อ.'}$amphoe',
      if (changwat.isNotEmpty) 'จ.$changwat',
      if (postalCode.isNotEmpty) postalCode,
    ];
    return parts.join(' ').trim();
  }

  void _startCountdown(int seconds) {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft > 0) {
        setState(() => _secondsLeft--);
      } else {
        timer.cancel();
      }
    });
  }

  // ==========================================
  // ขั้นตอนที่ 1: ตรวจสอบข้อมูลฟอร์ม แล้วส่ง OTP ไปยังอีเมล (ช่องชื่อผู้ใช้)
  // ==========================================
  Future<void> _validateAndSendOtp() async {
    final name = _nameController.text.trim();
    final houseNo = _houseNoController.text.trim();
    final tambon = _tambonController.text.trim();
    final amphoe = _amphoeController.text.trim();
    final changwat = _changwatController.text.trim();
    final postalCode = _postalCodeController.text.trim();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 1. ตรวจสอบว่ากรอกข้อมูลครบหรือไม่
    if (name.isEmpty ||
        houseNo.isEmpty ||
        tambon.isEmpty ||
        amphoe.isEmpty ||
        changwat.isEmpty ||
        postalCode.isEmpty ||
        phone.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลที่จำเป็นให้ครบถ้วน');
      return;
    }

    if (postalCode.length != 5) {
      _showSnackBar('รหัสไปรษณีย์ต้องมี 5 หลัก');
      return;
    }

    if (phone.length != 10) {
      _showSnackBar('เบอร์โทรศัพท์ต้องมี 10 หลัก');
      return;
    }

    // ตรวจสอบความยาวรหัสผ่าน
    if (password.length < 8) {
      _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
      return;
    }

    // 🟢 ตรวจสอบว่ารหัสผ่านมีทั้งตัวอักษรและตัวเลข
    final passwordRegExp = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)');
    if (!passwordRegExp.hasMatch(password)) {
      _showSnackBar('รหัสผ่านต้องประกอบด้วยตัวอักษรและตัวเลข');
      return;
    }

    // ช่อง "อีเมล" ต้องเป็นอีเมลจริง เพราะใช้ส่ง OTP ยืนยันตัวตน
    if (!email.contains('@') || !email.contains('.')) {
      _showSnackBar('กรุณากรอกอีเมลให้ถูกต้อง เช่น user@gmail.com');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // ตรวจสอบล่วงหน้าว่าชื่อผู้ใช้หรืออีเมลนี้ถูกใช้ไปแล้วหรือยัง ก่อนเสียเวลาส่ง OTP
      if (await DatabaseHelper.instance.checkUsernameExists(username)) {
        _showSnackBar('ชื่อผู้ใช้นี้มีในระบบแล้ว กรุณาใช้ชื่ออื่น');
        setState(() => _isLoading = false);
        return;
      }
      if (await DatabaseHelper.instance.checkUsernameExists(email)) {
        _showSnackBar('อีเมลนี้ถูกใช้งานในระบบแล้ว กรุณาใช้อีเมลอื่น');
        setState(() => _isLoading = false);
        return;
      }

      // สร้างรหัส OTP 6 หลัก และตั้งเวลาหมดอายุ 3 นาที
      final rng = Random();
      _generatedOtp = (100000 + rng.nextInt(900000)).toString();
      _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));
      _failedOtpAttempts = 0;
      _otpController.clear();

      final sent = await PushNotificationService.sendEmailOtp(
        email: email,
        otp: _generatedOtp,
        purpose: 'REGISTER',
      );

      if (!mounted) return;

      if (sent) {
        _startCountdown(180);
        _showSnackBar('ส่งรหัส OTP ไปยัง $email เรียบร้อยแล้ว');
        setState(() {
          _step = _RegisterStep.verifyOtp;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnackBar('ส่งอีเมลไม่สำเร็จ กรุณาตรวจสอบอีเมลหรือการเชื่อมต่ออินเทอร์เน็ต');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnackBar('เกิดข้อผิดพลาด: $e');
    }
  }

  // ==========================================
  // ขั้นตอนที่ 2: ตรวจสอบรหัส OTP ที่กรอก
  // ==========================================
  Future<void> _verifyOtpAndRegister() async {
    final inputOtp = _otpController.text.trim();

    if (_otpExpiresAt == null || DateTime.now().isAfter(_otpExpiresAt!)) {
      _showSnackBar('รหัส OTP หมดอายุแล้ว กรุณากดขอรหัสใหม่');
      return;
    }

    if (inputOtp.isEmpty || inputOtp.length != 6) {
      _showSnackBar('กรุณากรอกรหัส OTP 6 หลักให้ครบถ้วน');
      return;
    }

    if (inputOtp != _generatedOtp) {
      _failedOtpAttempts++;
      if (_failedOtpAttempts >= 3) {
        _countdownTimer?.cancel();
        _generatedOtp = '';
        _showSnackBar('กรอก OTP ผิดเกิน 3 ครั้ง กรุณากดขอรหัสใหม่');
        setState(() => _step = _RegisterStep.form);
      } else {
        _showSnackBar('รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${3 - _failedOtpAttempts} ครั้ง)');
      }
      return;
    }

    // OTP ถูกต้อง -> ดำเนินการบันทึกบัญชีจริง
    _countdownTimer?.cancel();
    await _register();
  }

  // ==========================================
  // ฟังก์ชันลงทะเบียนบันทึกลง Firebase (เฉพาะลูกค้า) — เรียกหลังยืนยัน OTP สำเร็จแล้วเท่านั้น
  // ==========================================
  Future<void> _register() async {
    final name = _nameController.text.trim();
    final company = _companyController.text.trim();
    final houseNo = _houseNoController.text.trim();
    final moo = _mooController.text.trim();
    final tambon = _tambonController.text.trim();
    final amphoe = _amphoeController.text.trim();
    final changwat = _changwatController.text.trim();
    final postalCode = _postalCodeController.text.trim();
    final phone = _phoneController.text.trim();
    final username = _usernameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    // 1. ตรวจสอบว่ากรอกข้อมูลครบหรือไม่
    if (name.isEmpty ||
        houseNo.isEmpty ||
        tambon.isEmpty ||
        amphoe.isEmpty ||
        changwat.isEmpty ||
        postalCode.isEmpty ||
        phone.isEmpty ||
        username.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showSnackBar('กรุณากรอกข้อมูลที่จำเป็นให้ครบถ้วน');
      return;
    }

    if (postalCode.length != 5) {
      _showSnackBar('รหัสไปรษณีย์ต้องมี 5 หลัก');
      return;
    }

    if (phone.length != 10) {
      _showSnackBar('เบอร์โทรศัพท์ต้องมี 10 หลัก');
      return;
    }

    final address = _buildFullAddress();

    // ตรวจสอบความยาวรหัสผ่าน
    if (password.length < 8) {
      _showSnackBar('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
      return;
    }

    // 🟢 ตรวจสอบว่ารหัสผ่านมีทั้งตัวอักษรและตัวเลข
    final passwordRegExp = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)');
    if (!passwordRegExp.hasMatch(password)) {
      _showSnackBar('รหัสผ่านต้องประกอบด้วยตัวอักษรและตัวเลข');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. เตรียมข้อมูลสำหรับบันทึกลงตาราง Customers
      final nameParts = name.split(' ');
      final firstName = nameParts.first;
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final customerData = {
        'name': firstName,
        'surname': lastName,
        'company': company.isEmpty ? null : company,
        'address': address,
        'house_no': houseNo,
        'moo': moo.isEmpty ? '-' : moo,
        'tambon': tambon,
        'amphoe': amphoe,
        'changwat': changwat,
        'postal_code': postalCode,
        'phone': phone,
        'username': username,
        'email': email,
        'password': password,
      };
      
      // บันทึกลงตาราง Customers
      final id = await DatabaseHelper.instance.registerCustomer(customerData);

      // 3. ตรวจสอบผลการบันทึก
      if (id > 0) {
        _showSnackBar('ลงทะเบียนสำเร็จ! กรุณาเข้าสู่ระบบ');
        if (mounted) Navigator.pop(context); // กลับไปหน้า Login
      } else {
        _showSnackBar('ชื่อผู้ใช้นี้ถูกใช้งานแล้ว หรือเกิดข้อผิดพลาด');
      }
    } catch (e) {
      // ดักจับ Error เช่น กรณี Username ซ้ำ ( UNIQUE constraint )
      if (e.toString().contains('UNIQUE constraint failed')) {
        _showSnackBar('ชื่อผู้ใช้นี้มีในระบบแล้ว กรุณาใช้ชื่ออื่น');
      } else {
        _showSnackBar('เกิดข้อผิดพลาด: ${e.toString()}');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ==========================================
  // ==========================================
  // Widget ตัวช่วยสำหรับสร้าง TextField
  // ==========================================
  Widget _buildTextField({
    required String hintText,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool isPassword = false,
    bool readOnly = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      inputFormatters: inputFormatters,
      obscureText: isPassword ? _obscurePassword : false,
      decoration: AppStyles.inputDecoration(
        hintText: hintText,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: AppColors.textHint,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              )
            : null,
      ),
    );
  }

  /// ช่องกรอกแบบเลือกจาก dropdown ได้ หรือพิมพ์ค้นหาได้ (ใช้กับ จังหวัด/อำเภอ/ตำบล)
  Widget _buildAutocompleteField({
    Key? fieldKey,
    required String hintText,
    required TextEditingController controller,
    required List<String> Function() optionsBuilder,
    void Function(String selected)? onSelected,
    bool enabled = true,
  }) {
    return Autocomplete<String>(
      key: fieldKey,
      initialValue: TextEditingValue(text: controller.text),
      optionsBuilder: (TextEditingValue value) {
        if (!enabled) return const Iterable<String>.empty();
        final options = optionsBuilder();
        final query = value.text.trim();
        if (query.isEmpty) return options;
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
          decoration: AppStyles.inputDecoration(
            hintText: enabled ? hintText : '$hintText (เลือกข้อมูลก่อนหน้าก่อน)',
            suffixIcon: Icon(Icons.arrow_drop_down, color: AppColors.textHint),
          ),
          onChanged: (value) {
            controller.text = value;
            // ถ้าพิมพ์เอง (ไม่ได้กดเลือกจากลิสต์) ก็ยังอัปเดตค่าที่ใช้จริงให้ตรงกันไว้ก่อน
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
              constraints: const BoxConstraints(maxHeight: 220),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Register',
                textAlign: TextAlign.center,
                style: AppStyles.title,
              ),
              const SizedBox(height: 8),
              const Text(
                'ลงทะเบียนเพื่อเข้าสู่ระบบ',
                textAlign: TextAlign.center,
                style: AppStyles.subtitle,
              ),
              const SizedBox(height: 15),
              FractionallySizedBox(
                widthFactor: 0.4,
                child: Container(
                  height: 3, 
                  decoration: AppStyles.gradientLine,
                ),
              ),
              const SizedBox(height: 24),

              if (_step == _RegisterStep.form) ...[
                _buildRegisterForm(),
              ] else ...[
                _buildOtpStep(),
              ],
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // ขั้นตอนที่ 1: ฟอร์มกรอกข้อมูล
  // ==========================================
  Widget _buildRegisterForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
              _buildTextField(
                hintText: 'กรอกชื่อ - นามสกุล',
                controller: _nameController,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'บริษัท (ถ้ามี)',
                controller: _companyController,
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 4),
                child: Text('ที่อยู่', style: AppStyles.inputLabel),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _buildTextField(
                      hintText: 'บ้านเลขที่',
                      controller: _houseNoController,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: _buildTextField(
                      hintText: 'หมู่ (ถ้ามี)',
                      controller: _mooController,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildAutocompleteField(
                hintText: 'จังหวัด',
                controller: _changwatController,
                optionsBuilder: () => _provinceOptions,
                onSelected: (value) {
                  setState(() {
                    _changwatController.text = value;
                    _amphoeController.clear();
                    _tambonController.clear();
                    _postalCodeController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildAutocompleteField(
                hintText: 'อำเภอ / เขต',
                controller: _amphoeController,
                fieldKey: ValueKey('amphoe_${_changwatController.text}'),
                enabled: _changwatController.text.trim().isNotEmpty,
                optionsBuilder: () => _amphoeOptions,
                onSelected: (value) {
                  setState(() {
                    _amphoeController.text = value;
                    _tambonController.clear();
                    _postalCodeController.clear();
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildAutocompleteField(
                hintText: 'ตำบล / แขวง',
                controller: _tambonController,
                fieldKey: ValueKey('tambon_${_changwatController.text}_${_amphoeController.text}'),
                enabled: _changwatController.text.trim().isNotEmpty &&
                    _amphoeController.text.trim().isNotEmpty,
                optionsBuilder: () => _tambonOptions,
                onSelected: (value) {
                  setState(() {
                    _tambonController.text = value;
                    _tryAutoFillPostalCode();
                  });
                },
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'รหัสไปรษณีย์ (กรอกอัตโนมัติ)',
                controller: _postalCodeController,
                keyboardType: TextInputType.number,
                readOnly: true,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'เบอร์โทรศัพท์',
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'ชื่อผู้ใช้ (สำหรับเข้าสู่ระบบ)',
                controller: _usernameController,
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'อีเมล',
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  'EX. user@gmail.com (ใช้รับรหัส OTP ยืนยันตัวตน)',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildTextField(
                hintText: 'รหัสผ่าน',
                controller: _passwordController,
                isPassword: true,
              ),
              const Padding(
                padding: EdgeInsets.only(top: 8, left: 12),
                child: Text(
                  'รหัสผ่าน 8 หลักขึ้นไปประกอบด้วยตัวอักษรและตัวเลข',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // ==========================================
              // ปุ่มถัดไป: ส่งรหัส OTP ไปยังอีเมลก่อนลงทะเบียนจริง
              // ==========================================
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _validateAndSendOtp,
                  style: AppStyles.primaryButton,
                  child: _isLoading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 3,
                          ),
                        )
                      : const Text(
                          'ถัดไป: ยืนยันอีเมล',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),

              // ปุ่มกลับไปหน้าเข้าสู่ระบบ
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'มีบัญชีอยู่แล้ว ? เข้าสู่ระบบ',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
      ],
    );
  }

  // ==========================================
  // ขั้นตอนที่ 2: ยืนยันรหัส OTP ที่ส่งไปยังอีเมล
  // ==========================================
  Widget _buildOtpStep() {
    final email = _emailController.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined,
            size: 56, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(
          'กรอกรหัส OTP 6 หลักที่ส่งไปยัง $email',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
        ),
        const SizedBox(height: 8),
        Text(
          _secondsLeft > 0
              ? 'รหัสหมดอายุใน $_secondsLeft วินาที'
              : 'รหัส OTP หมดอายุแล้ว',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontSize: 13,
            color: _secondsLeft > 0 ? Colors.orange.shade800 : AppColors.requiredMark,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _otpController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.bold),
          decoration: AppStyles.inputDecoration(hintText: '000000'),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            style: AppStyles.primaryButton,
            onPressed: (_isLoading || _secondsLeft <= 0) ? null : _verifyOtpAndRegister,
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('ยืนยันและลงทะเบียน', style: AppStyles.buttonText),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _isLoading
              ? null
              : () {
                  _countdownTimer?.cancel();
                  setState(() => _step = _RegisterStep.form);
                },
          child: const Text(
            'ขอรับรหัส OTP ใหม่ / แก้ไขข้อมูล',
            style: TextStyle(color: AppColors.primary),
          ),
        ),
      ],
    );
  }
}