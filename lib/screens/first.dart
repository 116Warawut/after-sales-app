import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/login.dart';
import 'package:after_sales/screens/register.dart';

class FirstPage extends StatelessWidget {
  const FirstPage({super.key});
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 36.0, vertical: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ==========================================
                // 1. โลโก้วงกลมพร้อมขอบและเงา
                // ==========================================
                Container(
                  width: 140,
                  height: 140,
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 16,
                        spreadRadius: 2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      'assets/images/logo.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.build_circle_rounded,
                          size: 80,
                          color: AppColors.primary,
                        );
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ==========================================
                // 2. ชื่อระบบ (After Sale System)
                // ==========================================
                RichText(
                  textAlign: TextAlign.center,
                  text: TextSpan(
                    style: AppStyles.title,
                    children: [
                      const TextSpan(text: 'After Sale '),
                      TextSpan(
                        text: 'System',
                        style:
                            AppStyles.title.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ==========================================
                // 3. เส้น Gradient ใต้หัวข้อ
                // ==========================================
                FractionallySizedBox(
                  widthFactor: 0.35,
                  child: Container(
                    height: 3,
                    decoration: AppStyles.gradientLine,
                  ), 
                ),

                const SizedBox(height: 12),

                // ==========================================
                // 4. สโลแกน / Subtitle
                // ==========================================
                const Text(
                  'ระบบบริการหลังการขาย',
                  textAlign: TextAlign.center,
                  style: AppStyles.subtitle,
                ),

                const SizedBox(height: 48),

                // ==========================================
                // 5. ปุ่มหลัก: เข้าสู่ระบบ (เพิ่ม Icon)
                // ==========================================
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    // เปลี่ยนมาใช้ .icon
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LoginScreen(),
                        ),
                      );
                    },
                    style: AppStyles.primaryButton,
                    icon: const Icon(
                      Icons.login_rounded, // ไอคอนเข้าสู่ระบบ
                      color: Colors.white,
                    ),
                    label:
                        const Text('เข้าสู่ระบบ', style: AppStyles.buttonText),
                  ),
                ),

                const SizedBox(height: 14),

                // ==========================================
                // 6. ปุ่มรอง: ลงทะเบียน (เพิ่ม Icon)
                // ==========================================
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    // เปลี่ยนมาใช้ .icon
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RegisterScreen(),
                        ),
                      );
                    },
                    style: AppStyles.secondaryButton,
                    icon: const Icon(
                      Icons.person_add_alt_1_rounded, // ไอคอนลงทะเบียน
                      color: AppColors.primary,
                    ),
                    label: Text(
                      'ลงทะเบียน',
                      style: AppStyles.buttonText.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
