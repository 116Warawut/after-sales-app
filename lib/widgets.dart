import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/push_notification_service.dart';
import 'package:after_sales/auth_api_service.dart';
import 'package:after_sales/session_storage.dart';
import 'package:after_sales/models/repair.dart';
import 'package:after_sales/screens/login.dart';
import 'package:after_sales/screens/forgot_password.dart';
import 'package:after_sales/screens/admin/manage_admin.dart';
import 'package:after_sales/services.dart' as db;

/// ==========================================
/// 🏷️ Enum สำหรับแท็บตัวกรองรายการซ่อมทั้งหมด (ใช้ร่วมกันทุกหน้า)
/// ==========================================
enum FilterTab {
  all('ทั้งหมด'),
  pendingAssign('รอจัดสรรช่าง'),
  scheduledPending('รอดำเนินการ'),
  inProgress('กำลังซ่อม'),
  urgent('เร่งด่วน'),
  problem('มีปัญหา / ต้องตรวจสอบ'),
  overdue('เกินกำหนดเวลา'),
  completed('เสร็จสิ้น'),
  cancelled('ยกเลิก');

  final String label;
  const FilterTab(this.label);

  bool matches(String? status, {String? detail}) {
    final s = status?.trim() ?? '';
    switch (this) {
      case FilterTab.all:
        return true;
      case FilterTab.pendingAssign:
        return s == 'รอจัดสรรช่าง' || s == 'Pending';
      case FilterTab.scheduledPending:
        return s == 'รอดำเนินการ';
      case FilterTab.inProgress:
        // 🆕 [ใหม่] รวม 'กำลังเดินทาง' (สถานะใหม่ก่อนหน้า 'กำลังซ่อม' จริง —
        // ตั้งตอนช่างถึงคิวงานและเปิดดูแผนที่แล้ว ดู markTechnicianTraveling()
        // ใน services.dart) เข้าแท็บ "กำลังซ่อม" เดิมไปด้วย กันตกหล่นไปโผล่แท็บ
        // อื่นผิด ๆ เหมือนเคสสถานะใหม่อื่น ๆ ที่เจอมาก่อนหน้านี้ในโปรเจกต์นี้
        return s == 'กำลังซ่อม' ||
            s == 'กำลังดำเนินการ' ||
            s == 'กำลังเดินทาง' ||
            s == 'In Progress';
      case FilterTab.urgent:
        return (detail ?? '').contains('เร่งด่วน') ||
            (detail ?? '').contains('[ความรุนแรง: เร่งด่วน]');
      case FilterTab.problem:
        return s == 'มีปัญหา';
      case FilterTab.overdue:
        return s == 'เกินกำหนดเวลา' || s == 'Overdue';
      case FilterTab.completed:
        return s == 'เสร็จสิ้น' || s == 'เสร็จแล้ว' || s == 'Completed';
      case FilterTab.cancelled:
        return s.contains('ยกเลิก') || s == 'Cancelled';
    }
  }
}

/// ==========================================
/// 🎨 Helper ช่วยจัดการสีและสถานะงานซ่อมให้อัตโนมัติ
/// ==========================================
class StatusStyle {
  final Color bg;
  final Color fg;
  final IconData icon;

  const StatusStyle({required this.bg, required this.fg, required this.icon});

  static StatusStyle getStyle(String? status) {
    switch (status?.trim()) {
      case 'เสร็จแล้ว':
      case 'เสร็จสิ้น':
      case 'Completed':
        return const StatusStyle(
          bg: AppColors.greenBg,
          fg: AppColors.greenText,
          icon: Icons.check_circle_outline,
        );
      case 'กำลังซ่อม':
      case 'กำลังดำเนินการ':
      case 'In Progress':
        return const StatusStyle(
          bg: AppColors.yellowBg,
          fg: AppColors.yellowText,
          icon: Icons.sync,
        );
      // 🆕 [ใหม่] สถานะ "กำลังเดินทาง" (ช่างถึงคิวงานแล้ว กำลังมุ่งหน้าไปหา
      // ลูกค้า ยังไม่ได้ลงมือซ่อมจริง) — ให้สีฟ้าแยกจาก "กำลังซ่อม" (เหลือง)
      // เพื่อให้ลูกค้า/แอดมินแยกออกว่าช่างอยู่ขั้นไหนจริง ๆ
      case 'กำลังเดินทาง':
        return const StatusStyle(
          bg: Color(0xFFDCEEFF),
          fg: Color(0xFF1D4ED8),
          icon: Icons.directions_car_filled_outlined,
        );
      case 'รอดำเนินการ':
        return const StatusStyle(
          bg: Color(0xFFFFF7ED),
          fg: Color(0xFFEA580C),
          icon: Icons.schedule_rounded,
        );
      case 'รอจัดสรรช่าง':
      case 'Pending':
        return const StatusStyle(
          bg: AppColors.yellowBg,
          fg: AppColors.yellowText,
          icon: Icons.access_time_rounded,
        );
      case 'เกินกำหนดเวลา':
      case 'Overdue':
        return const StatusStyle(
          bg: Color(0xFFFFECEC),
          fg: Color(0xFFB91C1C),
          icon: Icons.event_busy_rounded,
        );
      case 'ยกเลิก':
      case 'Cancelled':
        return const StatusStyle(
          bg: AppColors.surfaceAlt,
          fg: AppColors.textSubtitle,
          icon: Icons.cancel_outlined,
        );
      case 'มีปัญหา':
        return const StatusStyle(
          bg: AppColors.redBg,
          fg: AppColors.redText,
          icon: Icons.report_problem_outlined,
        );
      default:
        return const StatusStyle(
          bg: AppColors.yellowBg,
          fg: AppColors.yellowText,
          icon: Icons.info_outline,
        );
    }
  }
}

/// ==========================================
/// แถบ header Chat
/// ==========================================
class ChatHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const ChatHeader({
    super.key,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        bottom: 12,
        left: 16,
        right: 16,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 🔴 วงกลมแดงแสดงตัวเลขแจ้งเตือน
/// ==========================================
class CountBadge extends StatelessWidget {
  final int count;
  final int max;

  const CountBadge({super.key, required this.count, this.max = 99});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > max ? '$max+' : '$count';

    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: AppColors.requiredMark,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          fontFamily: AppStyles.fontFamily,
          height: 1.2,
        ),
      ),
    );
  }
}

/// ==========================================
/// 🔝 แถบ Header ส่วนบนของแอป (AppHeader)
/// ==========================================
class AppHeader extends StatelessWidget {
  final String title;
  final bool showBack;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Widget? leading;

  const AppHeader({
    super.key,
    required this.title,
    this.showBack = false,
    this.onBack,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.only(
        top: topPadding + 10,
        left: 12,
        right: 12,
        bottom: 14,
      ),
      child: SizedBox(
        height: 40,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showBack)
              Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.hardEdge,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (onBack != null) {
                        onBack!();
                      } else {
                        Navigator.maybePop(context);
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              )
            else if (leading != null)
              Align(
                alignment: Alignment.centerLeft,
                child: leading,
              ),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontFamily: AppStyles.fontFamily,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
            if (trailing != null)
              Align(
                alignment: Alignment.centerRight,
                child: trailing,
              ),
          ],
        ),
      ),
    );
  }
}

/// ==========================================
/// 🏷️ ส่วนกรองและหัวข้อประวัติ (HistoryHeaderContent)
/// ==========================================
class HistoryHeaderContent extends StatelessWidget {
  final int totalTickets;
  final FilterTab selectedTab;
  final ValueChanged<FilterTab> onTabChanged;
  final bool showBack;
  final VoidCallback? onBack;

  const HistoryHeaderContent({
    super.key,
    required this.totalTickets,
    required this.selectedTab,
    required this.onTabChanged,
    this.showBack = true,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Container(
      width: double.infinity,
      color: AppColors.primary,
      padding: EdgeInsets.fromLTRB(0, topPadding + 12, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showBack)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  )
                else
                  const SizedBox(width: 8),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: showBack ? 12 : 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'รายการซ่อมทั้งหมด',
                          style: AppStyles.historySectionTitle,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$totalTickets รายการทั้งหมด',
                          style: AppStyles.historyMeta,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: FilterTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = FilterTab.values[index];
                final selected = tab == selectedTab;

                return GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onTabChanged(tab);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Center(
                      child: Text(
                        tab.label,
                        style: selected
                            ? AppStyles.historyFilterChipSelected
                            : AppStyles.historyFilterChipUnselected,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 📊 การ์ดสรุปจำนวนงานทั้งหมด (TodaySummaryCard)
/// ==========================================
class TodaySummaryCard extends StatelessWidget {
  final int total;
  final int completed;
  final int remaining;

  const TodaySummaryCard({
    super.key,
    required this.total,
    required this.completed,
    required this.remaining,
  });

  @override
  Widget build(BuildContext context) {
    final double targetProgress =
        total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ภาพรวมงานซ่อม',
            style: TextStyle(
              fontSize: 16,
              fontFamily: AppStyles.fontFamily,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ความคืบหน้า',
                style: TextStyle(
                  color: AppColors.textSubtitle,
                  fontSize: 13,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              Text(
                '${(targetProgress * 100).toInt()}%',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: targetProgress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: AppColors.border,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.primary,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'เสร็จแล้ว $completed งาน',
                style: const TextStyle(
                  color: AppColors.textSubtitle,
                  fontSize: 12,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              Text(
                'คงเหลือ $remaining งาน',
                style: const TextStyle(
                  color: AppColors.textSubtitle,
                  fontSize: 12,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statBox(
                  '$total',
                  'ทั้งหมด',
                  AppColors.blueBg,
                  AppColors.blueText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  '$completed',
                  'เสร็จแล้ว',
                  AppColors.greenBg,
                  AppColors.greenText,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statBox(
                  '$remaining',
                  'เหลืออีก',
                  AppColors.yellowBg,
                  AppColors.yellowText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statBox(String count, String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 18,
              fontFamily: AppStyles.fontFamily,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppStyles.fontFamily,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 🛠️ การ์ดงานที่กำลังดำเนินการ (OngoingJobCard)
/// ==========================================
class OngoingJobCard extends StatelessWidget {
  final Repair repair;
  final VoidCallback? onTap;

  const OngoingJobCard({super.key, required this.repair, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ticketText =
        repair.ticketNo ?? (repair.id != null ? '# AS-${repair.id}' : '-');
    final rawStatus = repair.status ?? 'กำลังซ่อม';
    final statusText = (rawStatus == 'กำลังดำเนินการ') ? 'กำลังซ่อม' : rawStatus;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.lightImpact();
            onTap!();
          }
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
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
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'งานที่กำลังดำเนินการ',
                    style: TextStyle(
                      fontSize: 15,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppColors.textHint,
                    size: 20,
                  ),
                ],
              ),
              const Divider(height: 20, color: AppColors.border),
              _detailRow(
                label: 'Ticket :',
                widgetValue: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        ticketText,
                        style: const TextStyle(
                          fontSize: 14,
                          fontFamily: AppStyles.fontFamily,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status: statusText),
                  ],
                ),
              ),
              _detailRow(label: 'เครื่อง :', textValue: repair.machine ?? '-'),
              _detailRow(label: 'วันที่ :', textValue: repair.date ?? '-'),
              _detailRow(label: 'ที่อยู่ :', textValue: repair.location ?? '-'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailRow({
    required String label,
    String? textValue,
    Widget? widgetValue,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSubtitle,
                fontSize: 13,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
          ),
          Expanded(
            child: widgetValue ??
                Text(
                  textValue ?? '',
                  style: const TextStyle(
                    color: AppColors.textMain,
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 📜 การ์ดประวัติการแจ้งซ่อมย่อย (HistoryCard)
/// ==========================================
class HistoryCard extends StatelessWidget {
  final Repair repair;
  final VoidCallback? onTap;

  const HistoryCard({super.key, required this.repair, this.onTap});

  @override
  Widget build(BuildContext context) {
    final ticketText =
        repair.ticketNo ?? (repair.id != null ? '# AS-${repair.id}' : '-');
    final rawStatus = repair.status ?? 'เสร็จแล้ว';
    final statusText = (rawStatus == 'กำลังดำเนินการ') ? 'กำลังซ่อม' : rawStatus;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onTap != null) {
            HapticFeedback.lightImpact();
            onTap!();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            ticketText,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusBadge(status: statusText),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      repair.machine ?? '-',
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${repair.date ?? ''}  •  ${repair.location ?? ''}',
                      style: AppStyles.historyCardSubtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textHint,
                  size: 20,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// ==========================================
/// 🏷️ Widget ตัวช่วยสร้าง Badge สถานะ (_StatusBadge)
/// ==========================================
class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final style = StatusStyle.getStyle(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 12, color: style.fg),
          const SizedBox(width: 4),
          Text(
            status,
            style: TextStyle(
              color: style.fg,
              fontSize: 11,
              fontFamily: AppStyles.fontFamily,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 📱 หน้าสลับชั่วคราว (PlaceholderPage)
/// ==========================================
class PlaceholderPage extends StatelessWidget {
  final String title;
  final IconData icon;

  const PlaceholderPage({
    super.key,
    required this.title,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(fontFamily: AppStyles.fontFamily),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 64, color: AppColors.textHint.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontFamily: AppStyles.fontFamily,
                color: AppColors.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ==========================================
/// ⚙️ ปุ่มตั้งค่า สำหรับใส่ใน trailing ของ AppHeader หน้าโปรไฟล์
/// ==========================================
class ProfileSettingsButton extends StatelessWidget {
  const ProfileSettingsButton({super.key});

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยืนยันออกจากระบบ'),
        content: const Text('ต้องการออกจากระบบใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child:
                const Text('ออกจากระบบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    await PushNotificationService.unlinkUser();
    await SessionStorage.clear();
    // 🔐 ต้อง sign out ออกจาก Firebase Auth ด้วย ไม่งั้น auth.token.role เก่า
    // จะยังค้างอยู่ในเครื่อง แม้ Session ในแอปจะถูกล้างไปแล้วก็ตาม
    await AuthApiService.logout();

    db.Session.signOut();
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _changePassword(BuildContext context) async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              final current = currentController.text.trim();
              final newPw = newController.text.trim();
              final confirmPw = confirmController.text.trim();

              if (current.isEmpty || newPw.isEmpty || confirmPw.isEmpty) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('กรุณากรอกข้อมูลให้ครบทุกช่อง')),
                );
                return;
              }
              if (newPw.length < 6) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content: Text('รหัสผ่านใหม่ต้องมีอย่างน้อย 6 ตัวอักษร')),
                );
                return;
              }
              if (newPw != confirmPw) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                      content: Text('รหัสผ่านใหม่ทั้ง 2 ช่องไม่ตรงกัน')),
                );
                return;
              }

              setDialogState(() => isSaving = true);
              final verified = await db.DatabaseHelper.instance.login(
                db.Session.currentUsername,
                current,
                db.Session.currentRole,
              );
              if (verified == null) {
                setDialogState(() => isSaving = false);
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(content: Text('รหัสผ่านปัจจุบันไม่ถูกต้อง')),
                );
                return;
              }

              await db.DatabaseHelper.instance.updatePasswordForRole(
                db.Session.currentUsername,
                db.Session.currentRole,
                newPw,
              );
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('เปลี่ยนรหัสผ่านเรียบร้อยแล้ว')),
              );
            }

            return AlertDialog(
              title: const Text('เปลี่ยนรหัสผ่าน'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: newController,
                      obscureText: true,
                      decoration:
                          const InputDecoration(labelText: 'รหัสผ่านใหม่'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: confirmController,
                      obscureText: true,
                      decoration: const InputDecoration(
                          labelText: 'ยืนยันรหัสผ่านใหม่'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                      isSaving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: isSaving ? null : submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('บันทึก'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMainAdmin = db.Session.isMainAdmin;
    return PopupMenuButton<String>(
      icon: const Icon(Icons.settings_outlined, color: Colors.white),
      onSelected: (value) {
        if (value == 'logout') {
          _logout(context);
        } else if (value == 'change_password') {
          // ลูกค้า: ใช้หน้า "ลืมรหัสผ่าน" (ยืนยันตัวตนผ่าน OTP อีเมล) แทนไดอะล็อกเดิม
          if (db.Session.currentRole == 'CUSTOMER') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ForgotPasswordScreen()),
            );
          } else {
            _changePassword(context);
          }
        } else if (value == 'manage_admin') {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ManageAdminPage()),
          );
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'howto',
          child: Text('วิธีใช้งานแอป'),
        ),
        if (isMainAdmin)
          const PopupMenuItem(
            value: 'manage_admin',
            child: Text('จัดการแอดมิน'),
          ),
        const PopupMenuItem(
          value: 'change_password',
          child: Text('เปลี่ยนรหัสผ่าน'),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: Text('ออกจากระบบ'),
        ),
      ],
    );
  }
}

Future<String> uploadPickedImage(XFile file) =>
    CloudinaryService.uploadImage(file);

Future<XFile?> cropProfileImage(XFile picked) async {
  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 85,
    maxWidth: 640,
    maxHeight: 640,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: 'ครอปรูปโปรไฟล์',
        toolbarColor: AppColors.primary,
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: AppColors.primary,
        initAspectRatio: CropAspectRatioPreset.square,
        lockAspectRatio: true,
        cropStyle: CropStyle.circle,
      ),
      IOSUiSettings(
        title: 'ครอปรูปโปรไฟล์',
        aspectRatioLockEnabled: true,
        aspectRatioPickerButtonHidden: true,
        resetAspectRatioEnabled: false,
        cropStyle: CropStyle.circle,
      ),
    ],
  );
  if (cropped == null) return null;
  return XFile(cropped.path);
}

bool isDataUriImage(String path) => path.startsWith('data:image');

Uint8List? _decodeDataUriImage(String dataUri) {
  try {
    final commaIndex = dataUri.indexOf(',');
    if (commaIndex == -1) return null;
    return base64Decode(dataUri.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

ImageProvider? localOrNetworkImageProvider(String? path) {
  if (path == null || path.isEmpty) return null;
  if (isDataUriImage(path)) {
    final bytes = _decodeDataUriImage(path);
    return bytes != null ? MemoryImage(bytes) : null;
  }
  if (path.startsWith('http://') || path.startsWith('https://')) {
    return NetworkImage(path);
  }
  return FileImage(File(path));
}

class LocalOrNetworkImage extends StatelessWidget {
  final String path;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const LocalOrNetworkImage({
    super.key,
    required this.path,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  Widget _fallback() {
    return Container(
      width: width,
      height: height,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: Icon(Icons.image_not_supported,
          color: Colors.grey.shade400, size: (height ?? 60) * 0.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (path.isEmpty) {
      image = _fallback();
    } else if (isDataUriImage(path)) {
      final bytes = _decodeDataUriImage(path);
      image = bytes == null
          ? _fallback()
          : Image.memory(
              bytes,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (context, error, stackTrace) => _fallback(),
            );
    } else if (path.startsWith('http://') || path.startsWith('https://')) {
      image = Image.network(
        path,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    } else {
      image = Image.file(
        File(path),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}

String notificationTypeLabel(String? type) {
  switch ((type ?? '').trim().toUpperCase()) {
    case 'REPAIR_ASSIGNED':
      return 'มอบหมายงานซ่อม';
    case 'REPAIR_IN_PROGRESS':
      return 'เริ่มดำเนินการซ่อม';
    case 'REPAIR_DONE':
      return 'งานซ่อมเสร็จสิ้น';
    case 'REPAIR_CANCELLED':
      return 'ยกเลิกการแจ้งซ่อม';
    case 'REPAIR_CREATED':
      return 'แจ้งซ่อมใหม่';
    case 'INVOICE':
    case 'INVOICE_CREATED':
      return 'ใบแจ้งหนี้';
    case 'PAYMENT':
    case 'PAYMENT_RECEIVED':
      return 'การชำระเงิน';
    case 'CHAT':
    case 'MESSAGE':
      return 'ข้อความใหม่';
    case 'INCOMING_CALL':
      return 'สายเรียกเข้า';
    case 'PART_REQUEST':
      return 'คำขอเบิกอะไหล่';
    case '':
      return 'ทั่วไป';
    default:
      return type!;
  }
}

String formatNotificationDateTime(String? iso) {
  if (iso == null || iso.trim().isEmpty) return '-';
  final dt = DateTime.tryParse(iso);
  if (dt == null) return iso;

  const months = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  final local = dt.toLocal();
  final day = local.day;
  final month = months[local.month - 1];
  final year = local.year + 543;
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');

  return '$day $month $year เวลา $hh:$mm น.';
}

Future<void> showNotificationDetailDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String timeAgo,
  String? typeLabel,
  VoidCallback? onViewFull,
  VoidCallback? onViewDetail,
  String viewDetailLabel = 'ไปที่ใบแจ้งซ่อม',
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.notifications_active_outlined,
                      color: AppColors.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(dialogContext),
                    color: Colors.grey,
                    splashRadius: 18,
                  ),
                ],
              ),
              if (typeLabel != null) ...[
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      typeLabel,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                    color: AppColors.textMain,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                timeAgo,
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 12,
                  color: AppColors.textSubtitle,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (onViewFull != null)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          onViewFull();
                        },
                        icon: const Icon(Icons.article_outlined, size: 18),
                        label: const Text(
                          'ดูรายละเอียดแบบเต็ม',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (onViewDetail != null) ...[
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          onViewDetail();
                        },
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: Text(
                          viewDetailLabel,
                          style: const TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class NotificationFullDetailPage extends StatelessWidget {
  final String title;
  final String message;
  final String typeLabel;
  final String createdAtText;
  final String timeAgo;
  final bool isRead;
  final VoidCallback? onViewDetail;
  final String viewDetailLabel;

  const NotificationFullDetailPage({
    super.key,
    required this.title,
    required this.message,
    required this.typeLabel,
    required this.createdAtText,
    required this.timeAgo,
    required this.isRead,
    this.onViewDetail,
    this.viewDetailLabel = 'ไปที่ใบแจ้งซ่อม',
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
            const AppHeader(title: 'รายละเอียดการแจ้งเตือน', showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.notifications_active_outlined,
                                color: AppColors.primary,
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: const TextStyle(
                                      fontFamily: AppStyles.fontFamily,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textMain,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    timeAgo,
                                    style: const TextStyle(
                                      fontFamily: AppStyles.fontFamily,
                                      fontSize: 12,
                                      color: AppColors.textSubtitle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(color: AppColors.border, height: 1),
                        const SizedBox(height: 16),
                        const Text(
                          'เนื้อหาการแจ้งเตือน',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          message,
                          style: const TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontSize: 14,
                            height: 1.6,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _DetailRow(label: 'ประเภท', value: typeLabel),
                        _DetailRow(
                            label: 'วันเวลาที่แจ้ง', value: createdAtText),
                        _DetailRow(
                          label: 'สถานะ',
                          value: isRead ? 'อ่านแล้ว' : 'ยังไม่ได้อ่าน',
                        ),
                        if (onViewDetail != null) ...[
                          const SizedBox(height: 20),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: onViewDetail,
                              icon: const Icon(Icons.open_in_new, size: 18),
                              label: Text(
                                viewDetailLabel,
                                style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
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
              value,
              style: const TextStyle(
                fontFamily: AppStyles.fontFamily,
                fontSize: 14,
                color: AppColors.textSubtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ==========================================
/// 🗑️ Widget สำหรับสไลด์เพื่อลบรายการ (SwipeToRevealDelete)
/// ==========================================
class SwipeToRevealDelete extends StatefulWidget {
  final Widget child;
  final VoidCallback onDelete;
  final BorderRadius? borderRadius;

  const SwipeToRevealDelete({
    super.key,
    required this.child,
    required this.onDelete,
    this.borderRadius,
  });

  static void closeOpened() => _SwipeToRevealDeleteState._openItem?._close();

  @override
  State<SwipeToRevealDelete> createState() => _SwipeToRevealDeleteState();
}

class _SwipeToRevealDeleteState extends State<SwipeToRevealDelete> {
  static const double _actionWidth = 84;
  static _SwipeToRevealDeleteState? _openItem;

  double _reveal = 0;
  bool _dragging = false;

  bool get _isOpen => _reveal > 0;

  @override
  void dispose() {
    if (_openItem == this) _openItem = null;
    super.dispose();
  }

  void _closeOthers() {
    final other = _openItem;
    if (other != null && other != this) other._close();
  }

  void _close() {
    if (_openItem == this) _openItem = null;
    if (!mounted) return;
    setState(() {
      _reveal = 0;
      _dragging = false;
    });
  }

  void _open() {
    _closeOthers();
    _openItem = this;
    if (!mounted) return;
    setState(() {
      _reveal = _actionWidth;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _closeOthers(),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: ClipRRect(
                borderRadius: widget.borderRadius ?? BorderRadius.zero,
                child: Material(
                  color: Colors.red,
                  child: InkWell(
                    onTap: widget.onDelete,
                    child: const SizedBox(
                      width: _actionWidth,
                      height: double.infinity,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.delete_outline,
                              color: Colors.white, size: 24),
                          SizedBox(height: 4),
                          Text(
                            'ลบ',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration:
                _dragging ? Duration.zero : const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(-_reveal, 0, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) {
                _closeOthers();
                setState(() => _dragging = true);
              },
              onHorizontalDragUpdate: (details) {
                setState(() {
                  _reveal =
                      (_reveal - details.delta.dx).clamp(0.0, _actionWidth);
                });
              },
              onHorizontalDragEnd: (_) {
                if (_reveal > _actionWidth / 2) {
                  _open();
                } else {
                  _close();
                }
              },
              child: Container(
                color: AppColors.background,
                child: Stack(
                  children: [
                    widget.child,
                    if (_isOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _close,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}