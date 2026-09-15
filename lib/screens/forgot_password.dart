import 'dart:async';
import 'dart:math';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { inputEmail, verifyOtp, resetPassword, resetDone }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.inputEmail;
  bool _isLoading = false;
  bool _obscurePassword1 = true;
  bool _obscurePassword2 = true;

  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  Map<String, dynamic>? _account;
  String _targetEmail = '';
  String _generatedOtp = '';
  DateTime? _otpExpiresAt;
  int _failedOtpAttempts = 0;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String get _role => (_account?['role'] as String?) ?? '';

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.requiredMark : Colors.green.shade700,
      ),
    );
  }

  // 1. ค้นหาบัญชีและส่ง OTP เข้าอีเมล
  Future<void> _sendOtpToEmail() async {
    final emailInput = _emailController.text.trim();
    if (emailInput.isEmpty) {
      _showSnack('กรุณากรอกอีเมล');
      return;
    }
    if (!emailInput.contains('@')) {
      _showSnack('กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final account =
          await db.DatabaseHelper.instance.findAccountByUsername(emailInput);
      if (!mounted) return;

      if (account == null) {
        _showSnack('ไม่พบบัญชีผู้ใช้นี้ในระบบ');
        setState(() => _isLoading = false);
        return;
      }

      _account = account;

      // ดึงอีเมลจากฟิลด์ email ก่อน ถ้าไม่มีค่อย fallback ไป username
      final foundEmail = (account['email'] as String?)?.trim();
      final foundUsername = (account['username'] as String?)?.trim();

      if (foundEmail != null && foundEmail.isNotEmpty) {
        _targetEmail = foundEmail;
      } else if (foundUsername != null && foundUsername.contains('@')) {
        _targetEmail = foundUsername;
      } else {
        _targetEmail = emailInput;
      }

      // สร้างรหัส OTP 6 หลัก และตั้งเวลาหมดอายุ 3 นาที
      final rng = Random();
      _generatedOtp = (100000 + rng.nextInt(900000)).toString();
      _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));
      _failedOtpAttempts = 0;

      // ส่ง OTP ผ่าน Worker -> SendGrid
      final success = await PushNotificationService.sendEmailOtp(
        email: _targetEmail,
        otp: _generatedOtp,
      );

      if (!mounted) return;

      if (success) {
        _startCountdown(180);
        _showSnack('ส่งรหัส OTP ไปยังอีเมล $_targetEmail เรียบร้อยแล้ว', isError: false);
        setState(() {
          _step = _Step.verifyOtp;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnack('ส่งอีเมลไม่สำเร็จ กรุณาตรวจสอบการตั้งค่าอีเมลผู้ส่งหรือการเชื่อมต่ออินเทอร์เน็ต');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('เกิดข้อผิดพลาด: $e');
    }
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

  // 2. ยืนยัน OTP
  void _verifyOtp() {
    final inputOtp = _otpController.text.trim();

    if (_otpExpiresAt == null || DateTime.now().isAfter(_otpExpiresAt!)) {
      _showSnack('รหัส OTP หมดอายุแล้ว กรุณากดย้อนกลับเพื่อขอรับรหัสใหม่');
      return;
    }

    if (inputOtp.isEmpty || inputOtp.length != 6) {
      _showSnack('กรุณากรอกรหัส OTP 6 หลักให้ครบถ้วน');
      return;
    }

    if (inputOtp != _generatedOtp) {
      _failedOtpAttempts++;
      if (_failedOtpAttempts >= 3) {
        _countdownTimer?.cancel();
        _generatedOtp = '';
        _showSnack('กรอก OTP ผิดเกิน 3 ครั้ง รหัสถูกยกเลิกเพื่อความปลอดภัย');
        setState(() => _step = _Step.inputEmail);
      } else {
        _showSnack('รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${3 - _failedOtpAttempts} ครั้ง)');
      }
      return;
    }

    _countdownTimer?.cancel();
    setState(() => _step = _Step.resetPassword);
  }

  // 3. ตั้งรหัสผ่านใหม่
  Future<void> _submitNewPassword() async {
    final newPw = _newPasswordController.text.trim();
    final confirmPw = _confirmPasswordController.text.trim();

    if (newPw.length < 8) {
      _showSnack('รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร');
      return;
    }

    final passwordRegExp = RegExp(r'^(?=.*[A-Za-z])(?=.*\d)');
    if (!passwordRegExp.hasMatch(newPw)) {
      _showSnack('รหัสผ่านต้องประกอบด้วยตัวอักษรและตัวเลข');
      return;
    }

    if (newPw != confirmPw) {
      _showSnack('รหัสผ่านใหม่ทั้ง 2 ช่องไม่ตรงกัน');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final targetIdentifier = (_account!['username'] as String?) ?? _targetEmail;
      await db.DatabaseHelper.instance.updatePasswordForRole(
        targetIdentifier,
        _role,
        newPw,
      );
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _Step.resetDone;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('เปลี่ยนรหัสผ่านไม่สำเร็จ: $e');
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
            const AppHeader(title: 'ลืมรหัสผ่าน', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ขั้นตอนที่ 1: กรอกอีเมล
                    if (_step == _Step.inputEmail) ...[
                      const Text(
                        'กรอกอีเมลบัญชีของคุณเพื่อรับรหัสยืนยัน OTP',
                        style: TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: AppStyles.inputDecoration(
                          hintText: 'กรอกอีเมล',
                          prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: _isLoading ? null : _sendOtpToEmail,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ส่งรหัส OTP เข้าอีเมล', style: AppStyles.buttonText),
                        ),
                      ),
                    ]
                    // ขั้นตอนที่ 2: กรอกรหัส OTP
                    else if (_step == _Step.verifyOtp) ...[
                      Text(
                        'กรอกรหัส OTP 6 หลักที่ส่งไปยัง $_targetEmail',
                        style: const TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _secondsLeft > 0
                            ? 'รหัสหมดอายุใน $_secondsLeft วินาที'
                            : 'รหัส OTP หมดอายุแล้ว',
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
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: _secondsLeft > 0 ? _verifyOtp : null,
                          child: const Text('ยืนยันรหัส OTP', style: AppStyles.buttonText),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _step = _Step.inputEmail),
                        child: const Text('ขอรับรหัส OTP ใหม่ / เปลี่ยนอีเมล', style: TextStyle(color: AppColors.primary)),
                      ),
                    ]
                    // ขั้นตอนที่ 3: ตั้งรหัสผ่านใหม่
                    else if (_step == _Step.resetPassword) ...[
                      const Text(
                        'กำหนดรหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร มีตัวอักษรและตัวเลข)',
                        style: TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _newPasswordController,
                        obscureText: _obscurePassword1,
                        decoration: AppStyles.inputDecoration(
                          hintText: 'รหัสผ่านใหม่',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword1 ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword1 = !_obscurePassword1),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscurePassword2,
                        decoration: AppStyles.inputDecoration(
                          hintText: 'ยืนยันรหัสผ่านใหม่',
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword2 ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword2 = !_obscurePassword2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: _isLoading ? null : _submitNewPassword,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('บันทึกรหัสผ่านใหม่', style: AppStyles.buttonText),
                        ),
                      ),
                    ]
                    // ขั้นตอนที่ 4: เสร็จสมบูรณ์
                    else ...[
                      const Icon(Icons.check_circle_rounded, color: AppColors.greenText, size: 72),
                      const SizedBox(height: 16),
                      const Text(
                        'ตั้งรหัสผ่านใหม่เรียบร้อยแล้ว',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: () => Navigator.pop(context),
                          child: const Text('กลับไปหน้าเข้าสู่ระบบ', style: AppStyles.buttonText),
                        ),
                      ),
                    ],
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