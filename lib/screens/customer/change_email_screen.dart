import 'dart:async';
import 'dart:math';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';

/// หน้าจอเปลี่ยนอีเมลของบัญชี (ใช้ใน "โปรไฟล์ลูกค้า")
///
/// เหตุผลที่ต้องยืนยันอีเมลเดิมก่อน แทนที่จะให้กรอกอีเมลใหม่แล้วเปลี่ยนได้ทันที:
/// ถ้าไม่ยืนยันอีเมลเดิมก่อน คนที่แอบใช้เครื่อง/เซสชันที่ล็อกอินค้างอยู่จะ
/// เปลี่ยนอีเมลเป็นของตัวเองได้ทันที แล้วไปกด "ลืมรหัสผ่าน" ต่อด้วยอีเมลใหม่
/// ที่ตัวเองคุมอยู่ ยึดบัญชีไปทั้งบัญชีได้เลย จึงต้องพิสูจน์ก่อนว่าเป็นเจ้าของ
/// บัญชีจริง (เข้าถึงอีเมลเดิมได้) ก่อนจะยอมให้เปลี่ยนไปอีเมลใหม่
///
/// flow: ยืนยันอีเมลเดิมด้วย OTP -> กรอกอีเมลใหม่ -> ยืนยันอีเมลใหม่ด้วย OTP
/// -> บันทึก -> ส่งอีเมลแจ้งเตือนไปอีเมลเดิมว่าเปลี่ยนอีเมลไปแล้ว
class ChangeEmailScreen extends StatefulWidget {
  final String username;
  final String currentEmail;

  const ChangeEmailScreen({
    super.key,
    required this.username,
    required this.currentEmail,
  });

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

enum _Step {
  confirmOldEmail,
  verifyOldOtp,
  inputNewEmail,
  verifyNewOtp,
  done,
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  _Step _step = _Step.confirmOldEmail;
  bool _isLoading = false;

  final _oldOtpController = TextEditingController();
  final _newEmailController = TextEditingController();
  final _newOtpController = TextEditingController();

  String _generatedOtp = '';
  DateTime? _otpExpiresAt;
  int _failedOtpAttempts = 0;
  Timer? _countdownTimer;
  int _secondsLeft = 0;

  late String _newEmail;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _oldOtpController.dispose();
    _newEmailController.dispose();
    _newOtpController.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.requiredMark : Colors.green.shade700,
      ),
    );
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

  // ---------------------------------------------------------------------
  // 1. ส่ง OTP ไปยืนยัน "อีเมลเดิม" ก่อน (พิสูจน์ว่าเป็นเจ้าของบัญชีจริง)
  // ---------------------------------------------------------------------
  Future<void> _sendOtpToOldEmail() async {
    setState(() => _isLoading = true);
    try {
      final rng = Random();
      _generatedOtp = (100000 + rng.nextInt(900000)).toString();
      _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));
      _failedOtpAttempts = 0;

      final success = await PushNotificationService.sendEmailOtp(
        email: widget.currentEmail,
        otp: _generatedOtp,
        purpose: 'CHANGE_EMAIL_OLD',
      );

      if (!mounted) return;

      if (success) {
        _oldOtpController.clear();
        _startCountdown(180);
        _showSnack('ส่งรหัส OTP ไปยัง ${widget.currentEmail} เรียบร้อยแล้ว', isError: false);
        setState(() {
          _step = _Step.verifyOldOtp;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnack('ส่งอีเมลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('เกิดข้อผิดพลาด: $e');
    }
  }

  void _verifyOldOtp() {
    final inputOtp = _oldOtpController.text.trim();

    if (_otpExpiresAt == null || DateTime.now().isAfter(_otpExpiresAt!)) {
      _showSnack('รหัส OTP หมดอายุแล้ว กรุณาขอรับรหัสใหม่');
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
        _showSnack('กรอก OTP ผิดเกิน 3 ครั้ง กรุณาเริ่มใหม่อีกครั้งเพื่อความปลอดภัย');
        setState(() => _step = _Step.confirmOldEmail);
      } else {
        _showSnack('รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${3 - _failedOtpAttempts} ครั้ง)');
      }
      return;
    }

    _countdownTimer?.cancel();
    setState(() => _step = _Step.inputNewEmail);
  }

  // ---------------------------------------------------------------------
  // 2. กรอกอีเมลใหม่ -> ตรวจสอบความถูกต้อง/ซ้ำ -> ส่ง OTP ไปยืนยัน
  // ---------------------------------------------------------------------
  Future<void> _submitNewEmail() async {
    final newEmail = _newEmailController.text.trim();

    if (newEmail.isEmpty || !newEmail.contains('@') || !newEmail.contains('.')) {
      _showSnack('กรุณากรอกอีเมลให้ถูกต้อง');
      return;
    }
    if (newEmail.toLowerCase() == widget.currentEmail.trim().toLowerCase()) {
      _showSnack('อีเมลใหม่ต้องไม่ซ้ำกับอีเมลเดิม');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final exists = await db.DatabaseHelper.instance.checkUsernameExists(newEmail);
      if (!mounted) return;
      if (exists) {
        setState(() => _isLoading = false);
        _showSnack('อีเมลนี้ถูกใช้งานโดยบัญชีอื่นในระบบแล้ว');
        return;
      }

      _newEmail = newEmail;
      final rng = Random();
      _generatedOtp = (100000 + rng.nextInt(900000)).toString();
      _otpExpiresAt = DateTime.now().add(const Duration(minutes: 3));
      _failedOtpAttempts = 0;

      final success = await PushNotificationService.sendEmailOtp(
        email: _newEmail,
        otp: _generatedOtp,
        purpose: 'CHANGE_EMAIL_NEW',
      );

      if (!mounted) return;

      if (success) {
        _newOtpController.clear();
        _startCountdown(180);
        _showSnack('ส่งรหัส OTP ไปยัง $_newEmail เรียบร้อยแล้ว', isError: false);
        setState(() {
          _step = _Step.verifyNewOtp;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
        _showSnack('ส่งอีเมลไม่สำเร็จ กรุณาตรวจสอบอีเมลแล้วลองใหม่');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('เกิดข้อผิดพลาด: $e');
    }
  }

  // ---------------------------------------------------------------------
  // 3. ยืนยัน OTP อีเมลใหม่ -> บันทึกอีเมลใหม่ -> แจ้งเตือนอีเมลเดิม
  // ---------------------------------------------------------------------
  Future<void> _verifyNewOtpAndSave() async {
    final inputOtp = _newOtpController.text.trim();

    if (_otpExpiresAt == null || DateTime.now().isAfter(_otpExpiresAt!)) {
      _showSnack('รหัส OTP หมดอายุแล้ว กรุณาขอรับรหัสใหม่');
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
        _showSnack('กรอก OTP ผิดเกิน 3 ครั้ง กรุณากรอกอีเมลใหม่อีกครั้ง');
        setState(() => _step = _Step.inputNewEmail);
      } else {
        _showSnack('รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${3 - _failedOtpAttempts} ครั้ง)');
      }
      return;
    }

    _countdownTimer?.cancel();
    setState(() => _isLoading = true);
    try {
      await db.DatabaseHelper.instance.updateCustomerProfile(
        widget.username,
        {'email': _newEmail},
      );

      // แจ้งเตือนอีเมลเดิมแบบ fire-and-forget — ส่งไม่สำเร็จก็ไม่ควร block
      // ผลลัพธ์หลัก เพราะการเปลี่ยนอีเมลได้บันทึกสำเร็จไปแล้ว
      unawaited(PushNotificationService.sendEmailChangeNotice(
        oldEmail: widget.currentEmail,
        newEmail: _newEmail,
      ));

      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _step = _Step.done;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('บันทึกอีเมลใหม่ไม่สำเร็จ: $e');
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
            const AppHeader(title: 'เปลี่ยนอีเมล', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ขั้นตอนที่ 1: ยืนยันว่าเป็นเจ้าของอีเมลเดิม
                    if (_step == _Step.confirmOldEmail) ...[
                      const Icon(Icons.shield_outlined, color: AppColors.primary, size: 56),
                      const SizedBox(height: 16),
                      Text(
                        'เพื่อความปลอดภัย กรุณายืนยันว่าคุณเข้าถึงอีเมลเดิมได้ก่อน '
                        'โดยระบบจะส่งรหัส OTP ไปที่ ${widget.currentEmail}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: _isLoading ? null : _sendOtpToOldEmail,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ส่งรหัส OTP ไปยังอีเมลเดิม', style: AppStyles.buttonText),
                        ),
                      ),
                    ]
                    // ขั้นตอนที่ 2: กรอก OTP ที่ส่งไปอีเมลเดิม
                    else if (_step == _Step.verifyOldOtp) ...[
                      Text(
                        'กรอกรหัส OTP 6 หลักที่ส่งไปยัง ${widget.currentEmail}',
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
                        controller: _oldOtpController,
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
                          onPressed: _secondsLeft > 0 ? _verifyOldOtp : null,
                          child: const Text('ยืนยันรหัส OTP', style: AppStyles.buttonText),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _step = _Step.confirmOldEmail),
                        child: const Text('ขอรับรหัส OTP ใหม่', style: TextStyle(color: AppColors.primary)),
                      ),
                    ]
                    // ขั้นตอนที่ 3: กรอกอีเมลใหม่
                    else if (_step == _Step.inputNewEmail) ...[
                      const Text(
                        'กรอกอีเมลใหม่ที่ต้องการใช้แทนอีเมลเดิม',
                        style: TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 15),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _newEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: AppStyles.inputDecoration(
                          hintText: 'กรอกอีเมลใหม่',
                          prefixIcon: const Icon(Icons.email_outlined, color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: _isLoading ? null : _submitNewEmail,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ส่งรหัส OTP ไปยังอีเมลใหม่', style: AppStyles.buttonText),
                        ),
                      ),
                    ]
                    // ขั้นตอนที่ 4: กรอก OTP ที่ส่งไปอีเมลใหม่
                    else if (_step == _Step.verifyNewOtp) ...[
                      Text(
                        'กรอกรหัส OTP 6 หลักที่ส่งไปยัง $_newEmail',
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
                        controller: _newOtpController,
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
                          onPressed: (_secondsLeft > 0 && !_isLoading) ? _verifyNewOtpAndSave : null,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text('ยืนยันและบันทึกอีเมลใหม่', style: AppStyles.buttonText),
                        ),
                      ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => setState(() => _step = _Step.inputNewEmail),
                        child: const Text('แก้ไขอีเมล / ขอรับรหัสใหม่', style: TextStyle(color: AppColors.primary)),
                      ),
                    ]
                    // ขั้นตอนที่ 5: เสร็จสมบูรณ์
                    else ...[
                      const Icon(Icons.check_circle_rounded, color: AppColors.greenText, size: 72),
                      const SizedBox(height: 16),
                      const Text(
                        'เปลี่ยนอีเมลเรียบร้อยแล้ว',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'อีเมลของบัญชีนี้ถูกเปลี่ยนเป็น $_newEmail แล้ว',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontFamily: AppStyles.fontFamily, fontSize: 14, color: Colors.black54),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          style: AppStyles.primaryButton,
                          onPressed: () => Navigator.pop(context, _newEmail),
                          child: const Text('เสร็จสิ้น', style: AppStyles.buttonText),
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
