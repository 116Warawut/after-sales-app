import 'package:flutter/material.dart';

/// =============================================================================
/// 🎨 1. APP COLORS (รวมค่าสีทั้งหมดในระบบ)
/// =============================================================================
class AppColors {
  AppColors._(); // ป้องกันการสร้าง instance ของคลาสนี้

  // ---------------------------------------------------------------------------
  // 🔴 Brand / Primary Colors (สีประจำแอป)
  // ---------------------------------------------------------------------------
  static const Color primary = Color(0xFFD8232A);
  static const Color primaryDark = Color(0xFFB22121);

  // ---------------------------------------------------------------------------
  // 🖤 Text Colors (สีข้อความ)
  // ---------------------------------------------------------------------------
  static const Color textMain = Colors.black;
  static const Color textLabel = Color(0xFF555555);
  static const Color textSubtitle = Color(0xFF8A8580);
  static const Color textHint = Color(0xFFA3A3A3);

  /// สีหัวข้อการ์ดที่ไม่ใช่หัวข้อหลัก (เทาเข้ม)
  static const Color textHeading = Color(0xFF2A2A2A);
  static const Color requiredMark = Color(0xFFD42B2B);

  // ---------------------------------------------------------------------------
  // ⚪ Surface / Border Colors (สีพื้นหลังและขอบ)
  // ---------------------------------------------------------------------------
  static const Color background = Colors.white;
  static const Color border = Color(0xFFE8E8E8);

  /// พื้นหลังรองสำหรับหน้าที่ต้องการแยกชั้นจากการ์ดสีขาว
  static const Color surface = Color(0xFFF5F5F7);

  /// พื้นเทาอ่อนสำหรับกล่องว่าง รูป placeholder หรือแถบ progress
  static const Color surfaceAlt = Color(0xFFF0F0F0);

  // ---------------------------------------------------------------------------
  // 🟢🟡🔵🔴 Status & Analytics Colors (สีสถานะและสรุปผล)
  // ---------------------------------------------------------------------------
  // Blue: กำลังดำเนินการ (In Progress)
  static const Color blueBg = Color(0xFFEEF5FF);
  static const Color blueText = Color(0xFF3B82F6);

  // Green: เสร็จสิ้น (Success)
  static const Color greenBg = Color(0xFFEFFFF1);
  static const Color greenText = Color(0xFF22C55E);

  // Yellow: รอจัดสรรช่าง (Pending)
  static const Color yellowBg = Color(0xFFFFFBEB);
  static const Color yellowText = Color(0xFFF59E0B);

  // Red: ยกเลิก / มีปัญหา (Cancelled / Failed)
  static const Color redBg = Color(0xFFFFEBEE);
  static const Color redText = Color(0xFFD32F2F);

  // ---------------------------------------------------------------------------
  // 📊 Chart Accents (สีเสริมสำหรับกราฟ/ป้ายหมวดหมู่ที่ต้องแยกจากกัน)
  // ---------------------------------------------------------------------------
  static const Color accentTeal = Color(0xFF0891B2);
  static const Color accentPurple = Color(0xFF7C3AED);
  static const Color accentIndigo = Color(0xFF7A83BC);
}

/// =============================================================================
/// 📐 2. APP STYLES (สไตล์ข้อความ ปุ่มกด และฟอร์ม)
/// =============================================================================
class AppStyles {
  AppStyles._();

  // ---------------------------------------------------------------------------
  // 🔤 Base Font Definition
  // ---------------------------------------------------------------------------
  static const String fontFamily = 'Sarabun';

  // ---------------------------------------------------------------------------
  // 💬 Typography: General & Auth (หน้าหลัก / เข้าสู่ระบบ / ลงทะเบียน)
  // ---------------------------------------------------------------------------
  static const TextStyle title = TextStyle(
    color: AppColors.textMain,
    fontSize: 32,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w600,
    letterSpacing: 1.28,
  );

  static const TextStyle subtitle = TextStyle(
    color: AppColors.textSubtitle,
    fontSize: 16,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.64,
  );

  static const TextStyle inputLabel = TextStyle(
    color: AppColors.textLabel,
    fontSize: 16,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: 16,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w600,
  );

  // ---------------------------------------------------------------------------
  // 📜 Typography: History Page & Cards (หน้าประวัติและการ์ด)
  // ---------------------------------------------------------------------------
  static const TextStyle historyPageTitle = TextStyle(
    color: Colors.white,
    fontSize: 24,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.28,
  );

  static const TextStyle historySectionTitle = TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle historyMeta = TextStyle(
    color: Colors.white70,
    fontSize: 13,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
  );

  static const TextStyle historyFilterChipSelected = TextStyle(
    color: AppColors.primary,
    fontSize: 13,
    fontFamily: fontFamily,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle historyFilterChipUnselected = TextStyle(
    color: Colors.white,
    fontSize: 13,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w500,
  );

  static const TextStyle historyCardTitle = TextStyle(
    fontSize: 16,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w700,
  );

  static const TextStyle historyCardSubtitle = TextStyle(
    fontSize: 12,
    fontFamily: fontFamily,
    fontWeight: FontWeight.w400,
    color: AppColors.textSubtitle,
  );

  // ---------------------------------------------------------------------------
  // 🔘 Button Styles (สไตล์ปุ่มกด)
  // ---------------------------------------------------------------------------
  /// ปุ่มหลัก สีแดงทึบ
  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
    elevation: 0,
  );

  /// ปุ่มรอง ขอบสีแดง พื้นใส
  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: AppColors.primary,
    side: const BorderSide(color: AppColors.primary, width: 1.5),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  );

  /// Getter เรียกใช้ Gradient Line เพื่อความสะดวก
  static Decoration get gradientLine => AppDecorations.gradientLine;

  // ---------------------------------------------------------------------------
  // 📝 Form Field Helpers (ตัวช่วยสร้างกล่องกรอกข้อความและ Label)
  // ---------------------------------------------------------------------------
  /// กำหนดสไตล์ Input Box (TextField / TextFormField)
  static InputDecoration inputDecoration({
    required String hintText,
    Widget? suffixIcon,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppColors.textHint,
        fontSize: 15,
        fontFamily: fontFamily,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.requiredMark),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.requiredMark, width: 1.5),
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
    );
  }

  /// สร้าง Label หน้าช่องกรอก (พร้อมเครื่องหมาย * สีแดง)
  static Widget fieldLabel(String text, {bool required = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: text,
              style: const TextStyle(
                color: AppColors.textSubtitle,
                fontSize: 14,
                fontFamily: fontFamily,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (required)
              const TextSpan(
                text: ' *',
                style: TextStyle(
                  color: AppColors.requiredMark,
                  fontSize: 14,
                  fontFamily: fontFamily,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// =============================================================================
/// 🖼️ 3. APP DECORATIONS (รวมการตกแต่งกล่อง การ์ด และเส้นประดับ)
/// =============================================================================
class AppDecorations {
  AppDecorations._();

  // ---------------------------------------------------------------------------
  // 🔲 Card & Line Decorations (ตกแต่งแบบคงที่)
  // ---------------------------------------------------------------------------
  /// การ์ดหลักพร้อมเงา (OngoingJobCard, TodaySummaryCard)
  static BoxDecoration card = BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: AppColors.border),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.02),
        blurRadius: 8,
        offset: const Offset(0, 2),
      ),
    ],
  );

  /// การ์ดประวัติย่อย (HistoryCard)
  static BoxDecoration historyCard = BoxDecoration(
    color: AppColors.background,
    borderRadius: BorderRadius.circular(12),
    border: Border.all(color: AppColors.border),
  );

  /// เส้น Gradient สีส้มประดับใต้หัวข้อ Sign in / Register
  static final BoxDecoration gradientLine = BoxDecoration(
    borderRadius: BorderRadius.circular(50),
    gradient: LinearGradient(
      colors: [
        Colors.orange.shade300,
        Colors.orange.shade700,
        Colors.orange.shade300,
      ],
    ),
  );

  // ---------------------------------------------------------------------------
  // 🏷️ Dynamic Helper Decorations (ตกแต่งแบบรับค่าสีตามสถานะ)
  // ---------------------------------------------------------------------------
  /// กล่องแสดงตัวเลขสถิติย่อย
  static BoxDecoration statBox(Color bg) => BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      );

  /// แบดจ์แสดงสถานะ
  static BoxDecoration statusBadge(Color bg) => BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      );
}

/// =============================================================================
/// 🎨 4. APP THEME (ธีมกลางของทั้งแอป)
/// ผูกไว้ที่ MaterialApp เพียงจุดเดียว ทำให้ทุกหน้าที่ไม่ได้ระบุสไตล์เอง
/// ได้ฟอนต์ Sarabun สีแดงประจำแบรนด์ และหน้าตาปุ่ม/ช่องกรอก/ป๊อปอัพชุดเดียวกัน
/// =============================================================================
class AppTheme {
  AppTheme._();

  static ThemeData get light {
    const base = AppStyles.fontFamily;

    return ThemeData(
      useMaterial3: true,
      fontFamily: base,
      scaffoldBackgroundColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,

      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        onPrimary: Colors.white,
        surface: AppColors.background,
        onSurface: AppColors.textMain,
        error: AppColors.requiredMark,
        brightness: Brightness.light,
      ),

      // ---------------------------------------------------------------------
      // ตัวอักษร — ทุกขนาดใช้ Sarabun และสีข้อความชุดเดียวกัน
      // ---------------------------------------------------------------------
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontFamily: base, color: AppColors.textMain),
        displayMedium: TextStyle(fontFamily: base, color: AppColors.textMain),
        displaySmall: TextStyle(fontFamily: base, color: AppColors.textMain),
        headlineLarge: TextStyle(fontFamily: base, color: AppColors.textMain),
        headlineMedium: TextStyle(fontFamily: base, color: AppColors.textMain),
        headlineSmall: TextStyle(fontFamily: base, color: AppColors.textMain),
        titleLarge: TextStyle(
          fontFamily: base,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
        titleMedium: TextStyle(
          fontFamily: base,
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
        titleSmall: TextStyle(
          fontFamily: base,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
        bodyLarge: TextStyle(
          fontFamily: base,
          fontSize: 15,
          color: AppColors.textMain,
        ),
        bodyMedium: TextStyle(
          fontFamily: base,
          fontSize: 14,
          color: AppColors.textMain,
        ),
        bodySmall: TextStyle(
          fontFamily: base,
          fontSize: 12,
          color: AppColors.textSubtitle,
        ),
        labelLarge: TextStyle(
          fontFamily: base,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        labelMedium: TextStyle(fontFamily: base, fontSize: 12),
        labelSmall: TextStyle(fontFamily: base, fontSize: 11),
      ),

      // ---------------------------------------------------------------------
      // แถบหัวเรื่อง (เผื่อหน้าไหนยังใช้ AppBar อยู่ ให้หน้าตาตรงกับ AppHeader)
      // ---------------------------------------------------------------------
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: base,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),

      // ---------------------------------------------------------------------
      // ปุ่ม
      // ---------------------------------------------------------------------
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textHint,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: base,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: base,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(
            fontFamily: base,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),

      iconTheme: const IconThemeData(color: AppColors.primary),

      // ---------------------------------------------------------------------
      // ช่องกรอกข้อมูล — ให้ตรงกับ AppStyles.inputDecoration
      // ---------------------------------------------------------------------
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        hintStyle: const TextStyle(
          color: AppColors.textHint,
          fontSize: 15,
          fontFamily: base,
        ),
        labelStyle: const TextStyle(
          color: AppColors.textLabel,
          fontFamily: base,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.requiredMark),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.requiredMark, width: 1.5),
        ),
      ),

      // ---------------------------------------------------------------------
      // การ์ด เส้นคั่น ป๊อปอัพ และแถบแจ้งเตือน
      // ---------------------------------------------------------------------
      cardTheme: CardThemeData(
        color: AppColors.background,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.background,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: base,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textMain,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: base,
          fontSize: 14,
          height: 1.5,
          color: AppColors.textMain,
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.textHeading,
        contentTextStyle: const TextStyle(
          fontFamily: base,
          fontSize: 14,
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        labelStyle: const TextStyle(fontFamily: base, fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
      ),

      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.border,
        circularTrackColor: Colors.transparent,
      ),

      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.primary,
        titleTextStyle: TextStyle(
          fontFamily: base,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.textMain,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: base,
          fontSize: 13,
          color: AppColors.textSubtitle,
        ),
      ),

      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.white,
        ),
      ),

      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSubtitle,
        indicatorColor: AppColors.primary,
        labelStyle: TextStyle(
          fontFamily: base,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: TextStyle(fontFamily: base, fontSize: 14),
      ),
    );
  }
}
