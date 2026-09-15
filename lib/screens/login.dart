import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/register.dart';
import 'package:after_sales/screens/forgot_password.dart';
import 'package:after_sales/screens/technician/home_technician.dart';
import 'package:flutter/material.dart';
import 'package:after_sales/screens/customer/home_customer.dart';
import 'package:after_sales/screens/admin/home_admin.dart' hide AppColors;
import 'package:after_sales/services.dart';
import 'package:after_sales/auth_api_service.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/session_storage.dart';
import 'package:after_sales/main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _obscurePassword = true;
  bool _isLoading = false;

  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ==========================================
  // ฟังก์ชันหลักสำหรับกดปุ่ม Login
  // ==========================================
  Future<void> login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showSnackBar("กรุณากรอกชื่อผู้ใช้และรหัสผ่าน");
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 🔐 [แก้ไข] เดิมตรวจ bcrypt เองในแอป (ต้องอ่าน password hash ของทุกคน
      // ออกมาเทียบในเครื่อง) เปลี่ยนมาให้ Cloudflare Worker เป็นคนตรวจแทน แล้ว
      // ออก Firebase Custom Token ที่มี role ฝังมาด้วย ปลอมจากในแอปไม่ได้อีกต่อไป
      // (รับได้ทั้ง username และ email เหมือนของเดิม)
      final result = await AuthApiService.login(username, password);

      // เช็กว่า Widget ยังอยู่อย่างปลอดภัยก่อนใช้ Context
      if (!mounted) return;

      if (result != null) {
        final role = result.role;
        final userData = result.userData;
        // ผู้ใช้อาจพิมพ์ email ตอน login แต่ระบบอื่น ๆ (chat/push/session) ผูก
        // กับ "username" จริงเสมอ ต้องเอาค่านี้จากบัญชีที่ยืนยันแล้ว ไม่ใช่จาก
        // ช่องกรอกดิบ ๆ
        final realUsername = userData['username']?.toString() ?? username;

        // 🟢 เพิ่มการอัปเดต Session เมื่อเข้าสู่ระบบสำเร็จ
        Session.signIn(realUsername, role, userData: userData);

        // 💾 จำผู้ใช้นี้ไว้ในเครื่อง เปิดแอปครั้งหน้าจะเข้าหน้าแรกได้เลยไม่ต้อง
        // ล็อกอินซ้ำ (ไม่ await เพราะไม่อยากให้หน้าจอค้างรอ)
        SessionStorage.save(realUsername, role);

        // 📲 ผูกเครื่องนี้เข้ากับผู้ใช้คนนี้ เพื่อให้ยิง push notification
        // มาหาได้ตรง ๆ ในภายหลัง (ไม่ await เพราะไม่อยากให้หน้าจอค้างรอ)
        PushNotificationService.linkUser(realUsername);

        // 🔴 [แก้ไข] เดิมไม่เคยเรียกตอนล็อกอินสด ทำให้เครื่องนี้ไม่เริ่มฟังสายเรียกเข้า
        // ผ่าน Firebase เลย — ผู้โทรจึงโทรออกได้ปกติ แต่ฝั่งผู้รับไม่มีอะไรขึ้นเลย
        setupIncomingCallListener(realUsername);

        _navigateToHome(role);
      } else {
        _showSnackBar("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง");
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar("เกิดข้อผิดพลาด: ${e.toString()}");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==========================================
  // ฟังก์ชันจัดการการนำทางไปหน้า Home. Now! Attack THE D POINT! -NERVER!
  // ==========================================
  void _navigateToHome(String role) {
    if (!mounted) return;

    Widget nextScreen;
    switch (role) {
      case "ADMIN":
        nextScreen = const HomeAdmin();
        break;
      case "TECHNICIAN":
        nextScreen = const HomeTechnician();
        break;
      case "CUSTOMER":
      default:
        nextScreen = const HomeCustomer();
        break;
    }

    Navigator.of(context, rootNavigator: true).pushReplacement(
      MaterialPageRoute(builder: (_) => nextScreen),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 46.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 100),
              const Text(
                'Sign in',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 32,
                  fontFamily: 'Sarabun',
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.28,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'เข้าสู่ระบบเพื่อดำเนินการต่อ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSubtitle,
                  fontSize: 16,
                  fontFamily: 'Sarabun',
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.64,
                ),
              ),
              const SizedBox(height: 12),
              FractionallySizedBox(
                widthFactor: 0.4,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange.shade300,
                        Colors.orange.shade700,
                        Colors.orange.shade300,
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 48),
              const Text(
                'ชื่อผู้ใช้',
                style: TextStyle(
                  color: AppColors.textLabel,
                  fontSize: 16,
                  fontFamily: 'Sarabun',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(
                  hintText: 'กรอกชื่อผู้ใช้',
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 15,
                    fontFamily: 'Sarabun',
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'รหัสผ่าน',
                style: TextStyle(
                  color: AppColors.textLabel,
                  fontSize: 16,
                  fontFamily: 'Sarabun',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: 'กรอกรหัสผ่าน',
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 15,
                    fontFamily: 'Sarabun',
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: AppColors.textHint,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ForgotPasswordScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    'ลืมรหัสผ่าน ?',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontFamily: 'Sarabun',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
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
                          'เข้าสู่ระบบ',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Sarabun',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'ยังไม่มีบัญชี ?',
                    style: TextStyle(
                      color: AppColors.textLabel,
                      fontSize: 14,
                      fontFamily: 'Sarabun',
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'สมัครสมาชิก',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontFamily: 'Sarabun',
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}