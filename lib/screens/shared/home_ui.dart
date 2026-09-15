// =============================================================================
// 🏠 HOME UI KIT
// ชุด Widget กลางสำหรับ "หน้าแรก" ของทุก Role (ลูกค้า / ช่าง / แอดมิน)
// เพื่อให้ทั้ง 3 หน้าใช้โครง สี ระยะห่าง และตัวอักษรชุดเดียวกัน
//
// ⚠️ ไฟล์นี้มีแต่ "หน้าตา" เท่านั้น ไม่มี logic ธุรกิจใด ๆ
// =============================================================================
import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/widgets.dart';

// =============================================================================
// SECTION 1: โครงหน้า
// =============================================================================

/// โครงหน้าแรกมาตรฐาน — Header ค้างบน + เนื้อหาดึงรีเฟรชได้
/// ระยะขอบ 16 รอบด้าน และการ์ดแต่ละก้อนเว้นห่างกันเอง
class HomeScaffold extends StatelessWidget {
  final String title;
  final bool isLoading;
  final Future<void> Function() onRefresh;
  final List<Widget> children;

  const HomeScaffold({
    super.key,
    this.title = 'หน้าแรก',
    required this.isLoading,
    required this.onRefresh,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppHeader(title: title),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: onRefresh,
                child: isLoading
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: ClampingScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                        children: children,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ข้อความทักทายบนสุดของหน้า
class HomeGreeting extends StatelessWidget {
  final String text;
  const HomeGreeting(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: AppStyles.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: AppColors.textMain,
        ),
      ),
    );
  }
}

/// หัวข้อหมวด พร้อมลิงก์ "ดูทั้งหมด" ทางขวา (ถ้ามี)
class HomeSectionHeader extends StatelessWidget {
  final String title;
  final String actionLabel;
  final VoidCallback? onAction;

  const HomeSectionHeader(
    this.title, {
    super.key,
    this.actionLabel = 'ดูทั้งหมด',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textMain,
          ),
        ),
        if (onAction != null)
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                children: [
                  Text(
                    actionLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// SECTION 2: การ์ด
// =============================================================================

/// การ์ดพื้นฐานของหน้าแรก (ขาว มุมมน 16 มีขอบบาง ๆ และเงาอ่อน)
class HomeCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HomeCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// คู่ "หัวข้อ : ค่า" ใช้ภายในการ์ดเด่น
class HomeInfoRow {
  final String label;
  final String value;
  const HomeInfoRow(this.label, this.value);
}

/// การ์ดเด่นประจำหน้าแรก — ใช้กับ "งานที่กำลังดำเนินการ" (ลูกค้า)
/// และ "งานต่อไป" (ช่าง) ให้หน้าตาเหมือนกัน
class HomeHighlightCard extends StatelessWidget {
  final String title;
  final String? statusLabel;
  final Color? statusBg;
  final Color? statusFg;
  final List<HomeInfoRow> rows;
  final String actionLabel;
  final VoidCallback? onAction;

  const HomeHighlightCard({
    super.key,
    required this.title,
    required this.rows,
    this.statusLabel,
    this.statusBg,
    this.statusFg,
    this.actionLabel = 'ดูรายละเอียด',
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return HomeCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (statusLabel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusBg ?? AppColors.yellowBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 7,
                          color: statusFg ?? AppColors.yellowText,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          statusLabel!,
                          style: TextStyle(
                            color: statusFg ?? AppColors.yellowText,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final row in rows) _InfoLine(row: row),
              ],
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(height: 14),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onAction,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(width: 1, color: AppColors.border),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        actionLabel,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final HomeInfoRow row;
  const _InfoLine({required this.row});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '${row.label} :',
              style: const TextStyle(
                fontFamily: AppStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.value,
              style: const TextStyle(
                fontFamily: AppStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: AppColors.textMain,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// แถวรายการงานแบบย่อ — ใช้กับ "ประวัติการแจ้งซ่อม" (ลูกค้า) และ "งานล่าสุด" (แอดมิน)
class HomeJobTile extends StatelessWidget {
  final String ticket;
  final String subtitle;
  final String statusLabel;
  final Color statusBg;
  final Color statusFg;
  final VoidCallback? onTap;

  const HomeJobTile({
    super.key,
    required this.ticket,
    required this.subtitle,
    required this.statusLabel,
    required this.statusBg,
    required this.statusFg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: statusFg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SECTION 3: ปุ่มและสถานะว่าง
// =============================================================================

/// ปุ่มหลักเต็มความกว้าง (เช่น "+ แจ้งซ่อม")
class HomePrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;

  const HomePrimaryButton({
    super.key,
    required this.label,
    this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppStyles.primaryButton.copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 14),
      ),
    );

    final text = Text(
      label,
      style: AppStyles.buttonText.copyWith(
        fontSize: 16,
        fontFamily: AppStyles.fontFamily,
      ),
    );

    return SizedBox(
      width: double.infinity,
      child: icon == null
          ? ElevatedButton(onPressed: onTap, style: style, child: text)
          : ElevatedButton.icon(
              onPressed: onTap,
              style: style,
              icon: Icon(icon, size: 20),
              label: text,
            ),
    );
  }
}

/// ปุ่มทางลัดแบบไอคอน + ป้ายกำกับ (ใช้ทั้งแอดมินและช่าง)
class HomeShortcutTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// จำนวนที่จะโชว์เป็นวงกลมแดงมุมขวาบนไอคอน (เช่น คำขอเบิกที่รอดำเนินการ)
  /// ใส่ 0 หรือปล่อยว่างไว้ = ไม่แสดง
  final int badgeCount;

  const HomeShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(icon, color: AppColors.primary, size: 24),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: CountBadge(count: badgeCount),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// จัดปุ่มทางลัดเป็นตาราง 2 คอลัมน์ (แถวสุดท้ายที่เหลือใบเดียวจะกินเต็มความกว้าง)
class HomeShortcutGrid extends StatelessWidget {
  final List<HomeShortcutTile> tiles;
  const HomeShortcutGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    for (var i = 0; i < tiles.length; i += 2) {
      final hasSecond = i + 1 < tiles.length;
      rows.add(
        Padding(
          padding: EdgeInsets.only(top: i == 0 ? 0 : 12),
          child: Row(
            children: [
              Expanded(child: tiles[i]),
              if (hasSecond) ...[
                const SizedBox(width: 12),
                Expanded(child: tiles[i + 1]),
              ],
            ],
          ),
        ),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// 📊 กล่องสรุปตัวเลข 1 ช่อง (ไอคอน + ตัวเลขใหญ่ + label) ใช้ในกริดสรุปภาพรวม
/// ของหน้าแรกแต่ละ role (เช่น สรุปงานวันนี้ของช่าง, ภาพรวมงานซ่อมของแอดมิน)
class StatBox extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  const StatBox({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.bg,
    required this.fg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: fg, size: 20),
              Text(
                '$value',
                style: TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textLabel,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// จัดวาง [StatBox] 4 กล่องเป็นตาราง 2x2 — ใช้ซ้ำได้ทุกหน้าแรกที่ต้องการสรุป
/// ตัวเลขแบบนี้ ส่ง [boxes] มาตามลำดับ บน-ซ้าย, บน-ขวา, ล่าง-ซ้าย, ล่าง-ขวา
class StatsGrid2x2 extends StatelessWidget {
  final List<StatBox> boxes;

  const StatsGrid2x2({super.key, required this.boxes}) : assert(boxes.length == 4);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: boxes[0]),
            const SizedBox(width: 12),
            Expanded(child: boxes[1]),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: boxes[2]),
            const SizedBox(width: 12),
            Expanded(child: boxes[3]),
          ],
        ),
      ],
    );
  }
}

/// กล่องข้อความตอนไม่มีข้อมูล
class HomeEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const HomeEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.textHint),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 13,
              color: AppColors.textSubtitle,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SECTION 4: สีสถานะ (ใช้ตัวเดียวกันทุก Role)
// =============================================================================

class HomeStatusStyle {
  HomeStatusStyle._();

  static bool _isCancelled(String s) =>
      s.contains('ยกเลิก') || s.toLowerCase().contains('cancel');

  static bool _isDone(String s) =>
      s.contains('เสร็จ') ||
      s.toLowerCase().contains('done') ||
      s.toLowerCase().contains('complete');

  static bool _isInProgress(String s) =>
      s.contains('กำลังดำเนินการ') ||
      s.contains('กำลังซ่อม') ||
      s.toLowerCase().contains('progress');

  // 🐛 [แก้บัค] เดิม helper นี้ไม่มีเคสของ "มีปัญหา" กับ "เกินกำหนดเวลา" เลย —
  // สองสถานะนี้เลยตกไปที่ default (เหลือง) ทั้งที่ตัว helper สีสถานะอื่นในแอป
  // (StatusStyle ใน widgets.dart, RepairStatusX/RepairStatus ฝั่งแอดมิน,
  // TicketStatusX ฝั่งลูกค้า/ช่าง) ให้สีแดงกับสองสถานะนี้ตรงกันหมดแล้ว ทำให้
  // การ์ด "งานที่กำลังดำเนินการ" หน้าแรกโชว์ป้าย "มีปัญหา" เป็นสีเหลืองผิด ๆ
  // ทั้งที่ทุกหน้าจออื่นในแอปใช้สีแดง — เพิ่มเคสให้ตรงกัน (สีเดียวกับ
  // StatusStyle.getStyle() เป๊ะ)
  static bool _isProblem(String s) => s.contains('ปัญหา');

  static bool _isOverdue(String s) =>
      s.contains('เกินกำหนดเวลา') || s.toLowerCase().contains('overdue');

  static Color bgOf(String? status) {
    final s = status ?? '';
    if (_isProblem(s)) return AppColors.redBg;
    if (_isOverdue(s)) return const Color(0xFFFFECEC);
    if (_isCancelled(s)) return AppColors.redBg;
    if (_isDone(s)) return AppColors.greenBg;
    if (_isInProgress(s)) return AppColors.blueBg;
    return AppColors.yellowBg;
  }

  static Color fgOf(String? status) {
    final s = status ?? '';
    if (_isProblem(s)) return AppColors.redText;
    if (_isOverdue(s)) return const Color(0xFFB91C1C);
    if (_isCancelled(s)) return AppColors.redText;
    if (_isDone(s)) return AppColors.greenText;
    if (_isInProgress(s)) return AppColors.blueText;
    return AppColors.yellowText;
  }
}