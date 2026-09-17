import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/widgets.dart';
import 'package:after_sales/screens/admin/admin_financial.dart';
import 'package:after_sales/screens/admin/repair_list_admin.dart';
import 'package:after_sales/screens/admin/admin_spare_part.dart';

/// รายชื่อเดือนภาษาไทยสั้น สำหรับแสดงผลในกราฟและรายงานการเงิน
const _thaiMonths = [
  'ม.ค.',
  'ก.พ.',
  'มี.ค.',
  'เม.ย.',
  'พ.ค.',
  'มิ.ย.',
  'ก.ค.',
  'ส.ค.',
  'ก.ย.',
  'ต.ค.',
  'พ.ย.',
  'ธ.ค.'
];

// 🆕 [ใหม่] ระดับความรุนแรง 4 ระดับ — ตรงกับ _severityOptions ในฟอร์มแจ้งซ่อม
// ของลูกค้า (screens/customer/repair_form.dart) และตรงกับสีที่หน้าเว็บใช้
// (SEVERITY_LEVELS ใน ReportsPage.jsx) เพื่อให้สีตรงกันทั้งสองแพลตฟอร์ม
const List<String> _severityLevels = ['ต่ำ', 'ปกติ', 'สูง', 'เร่งด่วน'];
const Map<String, Color> _severityColors = {
  'ต่ำ': Color(0xFF10B981),
  'ปกติ': Color(0xFF3B82F6),
  'สูง': Color(0xFFF97316),
  'เร่งด่วน': Color(0xFFEF4444),
};

// 🆕 [ใหม่] ดึงระดับความรุนแรงจากข้อความ detail ของงานซ่อม (รูปแบบ
// "[ความรุนแรง: xxx] ...") เหมือนกับ extractSeverity() ฝั่งเว็บ
// (src/shared/constants.js) ถ้าไม่เจอ/parse ไม่ได้ default เป็น "ปกติ"
// เหมือนค่าเริ่มต้นของฟอร์มฝั่งลูกค้า
String _extractSeverity(String? detail) {
  if (detail == null) return 'ปกติ';
  for (final level in _severityLevels) {
    if (detail.contains('[ความรุนแรง: $level]')) return level;
  }
  return 'ปกติ';
}

// =============================================================================
// 1. MAIN PAGE & STATE MANAGEMENT (หน้าหลักและการจัดการสถานะ)
// =============================================================================

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  // ตัวแปรดึงข้อมูลแบบ Asynchronous ที่จะส่งไปแสดงผลใน UI
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadDashboardData();
  }

  /// ฟังก์ชันสำหรับดึงข้อมูลใหม่เมื่อกด Refresh หรือเลื่อนหน้าจอลง (Pull-to-Refresh)
  Future<void> _refresh() async {
    final data = _loadDashboardData();
    if (mounted) setState(() => _future = data);
    await data;
  }

  /// 📤 ดาวน์โหลด/ปริ้นสรุปผล — เปิดชีตแสดงสรุปผลเป็นข้อความอ่านง่าย
  /// พร้อมปุ่มคัดลอก เพื่อให้นำไปวางต่อในแอปอื่น (Note, LINE, อีเมล) แล้วปริ้น/บันทึกได้เอง
  Future<void> _exportSummary() async {
    final data = await _future;
    if (!mounted) return;

    final now = DateTime.now();
    final buffer = StringBuffer()
      ..writeln('สรุปผลระบบแจ้งซ่อม')
      ..writeln('ข้อมูล ณ วันที่ ${now.day}/${now.month}/${now.year + 543}')
      ..writeln('----------------------------------------')
      ..writeln('จำนวนผู้ใช้งาน')
      ..writeln('  ลูกค้า        : ${data.customerCount} คน')
      ..writeln('  ช่างเทคนิค    : ${data.technicianCount} คน')
      ..writeln('  แอดมิน        : ${data.adminCount} คน')
      ..writeln('----------------------------------------')
      ..writeln('งานซ่อมเดือนนี้')
      ..writeln('  งานทั้งหมด    : ${data.jobsThisMonth} งาน')
      ..writeln('  เสร็จสิ้นแล้ว  : ${data.completedThisMonth} งาน')
      ..writeln(
        '  การเติบโต     : ${data.growthPercent == null ? '-' : '${data.growthPercent!.toStringAsFixed(1)}%'}',
      )
      ..writeln('----------------------------------------')
      ..writeln('สรุปการเงิน')
      ..writeln(
          '  ยอดชำระแล้ว    : ${data.totalPaid.toStringAsFixed(2)} บาท')
      ..writeln(
          '  ยอดค้างชำระ    : ${data.totalPending.toStringAsFixed(2)} บาท')
      ..writeln('  อะไหล่ใกล้หมด  : ${data.lowStockCount} รายการ');

    if (data.monthlyRevenue.isNotEmpty) {
      buffer.writeln('----------------------------------------');
      buffer.writeln('รายได้รายเดือน');
      for (final m in data.monthlyRevenue) {
        buffer.writeln(
          '  ${m.label.padRight(6)}: ชำระแล้ว ${m.paid.toStringAsFixed(0)} / '
          'ค้างชำระ ${m.pending.toStringAsFixed(0)} บาท',
        );
      }
    }

    final summaryText = buffer.toString();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'ดาวน์โหลด / ปริ้นสรุปผล',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textMain,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      'สรุปผลด้านล่างนี้ คัดลอกไปวางในแอปโน้ต อีเมล หรือ LINE '
                      'เพื่อบันทึกหรือสั่งปริ้นต่อได้เลย',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSubtitle,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: SelectableText(
                          summaryText,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                            height: 1.6,
                            color: AppColors.textMain,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: AppStyles.primaryButton,
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: summaryText));
                          if (!sheetContext.mounted) return;
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'คัดลอกสรุปผลแล้ว นำไปวางในแอปอื่นเพื่อบันทึก/ปริ้นได้เลย',
                                style: TextStyle(
                                    fontFamily: AppStyles.fontFamily),
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_all_outlined, size: 18),
                        label: const Text(
                          'คัดลอกสรุปผล',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // [LOGIC ZONE] ฟังก์ชันดึงข้อมูลจาก Database และคำนวณสถิติต่างๆ
  // หากต้องการแก้เงื่อนไขการคำนวณตัวเลข ให้แก้ไขในฟังก์ชันนี้
  // ---------------------------------------------------------------------------
  Future<_DashboardData> _loadDashboardData() async {
    final dbHelper = db.DatabaseHelper.instance;

    // 1. ดึงข้อมูลดิบจากตารางต่างๆ ในฐานข้อมูล
    final customers = await dbHelper.getAllCustomers();
    final technicians = await dbHelper.getAllTechnicians();
    final admins = await dbHelper.getAllAdmins();
    final repairs = await dbHelper.getAllRepairs();
    final spareParts = await dbHelper.getSpareParts();

    // Helper functions สำหรับแปลงวันที่และเปรียบเทียบเดือน/ปี
    final now = DateTime.now();
    DateTime? parse(dynamic raw) =>
        (raw is String && raw.isNotEmpty) ? DateTime.tryParse(raw) : null;
    bool isSameMonth(DateTime? d, int y, int m) =>
        d != null && d.year == y && d.month == m;

    // 🐛 [แก้บัค] สถานะ "เสร็จแล้ว" ที่ระบบเคยเขียนลง DB มี 3 ค่า (เดิมเช็คแค่ 2 ค่า
    // ขาด 'เสร็จสิ้นแล้ว' ที่ label ของ RepairStatus.completed ใช้อยู่จริง)
    bool isCompletedStatus(dynamic status) =>
        status == 'เสร็จแล้ว' ||
        status == 'เสร็จสิ้น' ||
        status == 'เสร็จสิ้นแล้ว';

    // 🐛 [แก้บัค] วันที่ "เสร็จงาน" จริง ต้องดูจาก report_submitted_at (วันที่ส่ง
    // รายงานปิดงาน) ไม่ใช่ created_at (วันที่สร้างงาน) — เดิมโค้ดกรองงานของเดือนนี้
    // จาก created_at ก่อนแล้วค่อยเช็คสถานะ ทำให้งานที่ "สร้างเดือนก่อน แต่เพิ่งมา
    // เสร็จเดือนนี้" ไม่ถูกนับเลยทั้งตัวเศษ (เสร็จแล้ว) และตัวส่วน (งานทั้งหมด)
    // การ์ดเลยโชว์ 0/0 ทั้งที่มีงานเสร็จจริงในเดือนนี้ (ตามที่แจ้งบั๊กมา)
    DateTime? completionDate(Map<String, dynamic> r) =>
        parse(r['report_submitted_at']) ?? parse(r['created_at']);

    // งานซ่อมที่ "เกี่ยวข้อง" กับเดือนที่ระบุ = สร้างเดือนนั้น หรือ เสร็จเดือนนั้น
    bool isRelevantToMonth(Map<String, dynamic> r, int y, int m) {
      final createdInMonth = isSameMonth(parse(r['created_at']), y, m);
      final completedInMonth =
          isCompletedStatus(r['status']) && isSameMonth(completionDate(r), y, m);
      return createdInMonth || completedInMonth;
    }

    // 2. คำนวณงานซ่อมในเดือนปัจจุบัน และ เดือนก่อนหน้า
    final thisMonthRepairs = repairs
        .where((r) => isRelevantToMonth(r, now.year, now.month))
        .toList();
    final lastMonthDate = DateTime(now.year, now.month - 1, 1);
    final lastMonthCount = repairs
        .where((r) =>
            isRelevantToMonth(r, lastMonthDate.year, lastMonthDate.month))
        .length;

    // คำนวณจำนวนงานที่ 'เสร็จแล้ว' ในเดือนนี้ (อิงวันที่เสร็จงานจริง ไม่ใช่วันที่สร้างงาน)
    final completedThisMonth =
        thisMonthRepairs.where((r) => isCompletedStatus(r['status'])).length;

    // 3. คำนวณเปอร์เซ็นต์การเติบโตเมื่อเทียบกับเดือนก่อน (% Growth)
    double? growthPercent;
    if (lastMonthCount > 0) {
      final raw =
          ((thisMonthRepairs.length - lastMonthCount) / lastMonthCount) * 100;
      growthPercent = raw.abs() < 0.01 ? 0.0 : raw;
    }

    // 4. คำนวณรายรับย้อนหลัง 6 เดือน (แยกยอด ชำระแล้ว / รอชำระ)
    final monthly = List.generate(6, (index) {
      final target = DateTime(now.year, now.month - (5 - index), 1);
      double paid = 0, pending = 0;
      for (final r in repairs) {
        if (isSameMonth(parse(r['created_at']), target.year, target.month)) {
          final price = toDoubleOrNull(r['total_price']) ?? 0;
          r['is_paid'] == 1 ? paid += price : pending += price;
        }
      }
      return _MonthRevenue(_thaiMonths[target.month - 1], paid, pending);
    });

    // 5.1 🆕 [ใหม่] นับจำนวนงานซ่อมตามระดับความรุนแรง (ทั้งหมด ไม่จำกัดเดือน)
    // สำหรับการ์ดโดนัทในแดชบอร์ด — แทนที่การ์ด "จำนวนผู้ใช้งาน" เดิม
    final severityCounts = <String, int>{for (final l in _severityLevels) l: 0};
    for (final r in repairs) {
      final level = _extractSeverity(r['detail']?.toString());
      severityCounts[level] = (severityCounts[level] ?? 0) + 1;
    }

    // 6. ส่งคืน Model รวมข้อมูลเพื่อใช้วาดหน้าจอ
    return _DashboardData(
      customerCount: customers.length,
      technicianCount: technicians.length,
      adminCount: admins.length,
      jobsThisMonth: thisMonthRepairs.length,
      completedThisMonth: completedThisMonth,
      growthPercent: growthPercent,
      monthlyRevenue: monthly,
      totalPaid: monthly.fold(0.0, (sum, m) => sum + m.paid),
      totalPending: monthly.fold(0.0, (sum, m) => sum + m.pending),
      lowStockCount: spareParts
          .where((p) => (toIntOrNull(p['stock']) ?? 0) <= 5)
          .length, // อะไหล่ต่ำกว่าหรือเท่ากับ 5 ชิ้น
      severityCounts: severityCounts,
      ratingStats: await _loadRatingStats(dbHelper, technicians),
    );
  }

  // 🆕 [ใหม่] สรุปคะแนนประเมินช่างซ่อม สำหรับการ์ด "ประเมินผลช่างซ่อม"
  // ในหน้า Dashboard — ใช้ getTechnicianRatingStats() จาก services.dart
  // แล้ว map username -> ชื่อจริงของช่าง เพื่อแสดงผลให้อ่านง่าย
  Future<_RatingStats> _loadRatingStats(
    db.DatabaseHelper dbHelper,
    List<Map<String, dynamic>> technicians,
  ) async {
    final stats = await dbHelper.getTechnicianRatingStats();
    final nameOf = <String, String>{
      for (final t in technicians)
        (t['username']?.toString() ?? ''):
            (t['tech_name']?.toString()) ?? (t['username']?.toString() ?? '-'),
    };

    final byTechnician = (stats['by_technician'] as List)
        .map((e) => _TechnicianRating(
              name: nameOf[e['technician_username']] ??
                  e['technician_username'].toString(),
              average: e['average'] as double,
              count: e['count'] as int,
            ))
        .toList();

    final distributionRaw = stats['distribution'] as Map<int, int>;

    return _RatingStats(
      average: stats['average'] as double,
      totalRated: stats['total_rated'] as int,
      distribution: distributionRaw,
      byTechnician: byTechnician,
    );
  }

  // ---------------------------------------------------------------------------
  // [UI BUILDER] โครงสร้างหน้าจอหลัก
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // ส่วนหัว Dashboard (AppBar)
            AppHeader(
              title: 'สรุปผล',
              showBack: true,
              trailing: IconButton(
                onPressed: _exportSummary,
                icon: const Icon(Icons.ios_share, color: Colors.white),
                tooltip: 'ดาวน์โหลด / ปริ้นสรุปผล',
              ),
            ),
            // ส่วนเนื้อหาหลักที่เลื่อนจอได้
            Expanded(
              child: FutureBuilder<_DashboardData>(
                future: _future,
                builder: (context, snapshot) {
                  // แสดง Loading ระหว่างรอข้อมูล
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  // แสดง Error กรณีเกิดปัญหา
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('เกิดข้อผิดพลาด: ${snapshot.error}',
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                color: AppColors.requiredMark)),
                      ),
                    );
                  }

                  final data = snapshot.data!;
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      children: [
                        // การ์ดสรุปงานซ่อม + สรุปจำนวนผู้ใช้งาน (แสดงผลแบบ Responsive ตามขนาดจอ)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth < 360) {
                              return Column(children: [
                                _JobsCard(data),
                                const SizedBox(height: 12),
                                _SeverityCard(data)
                              ]);
                            }
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(flex: 6, child: _JobsCard(data)),
                                  const SizedBox(width: 12),
                                  Expanded(flex: 5, child: _SeverityCard(data)),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        // การ์ดแสดงกราฟและยอดสรุปการเงิน
                        _FinanceCard(data),
                        const SizedBox(height: 16),
                        // การ์ดรายการรายงานประจำเดือนและปุ่มลัดไปยังเมนูต่างๆ
                        _ReportsCard(data),
                        const SizedBox(height: 16),
                        // 🆕 [ใหม่] การ์ดสรุปการประเมินผลช่างซ่อม (คะแนนดาว)
                        _RatingCard(data.ratingStats),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 2. DATA MODELS (โมเดลสำหรับจัดเก็บข้อมูลเพื่อส่งเข้า UI)
// =============================================================================

/// เก็บสถิติตัวเลขรายรับประจำแต่ละเดือน
class _MonthRevenue {
  final String label;
  final double paid, pending;
  const _MonthRevenue(this.label, this.paid, this.pending);
}

// 🆕 [ใหม่] สถิติคะแนนประเมินช่างซ่อมรายคน (เฉลี่ย/จำนวนครั้งที่ถูกประเมิน)
class _TechnicianRating {
  final String name;
  final double average;
  final int count;
  const _TechnicianRating(
      {required this.name, required this.average, required this.count});
}

// 🆕 [ใหม่] สรุปสถิติการประเมินผลช่างซ่อมทั้งระบบ สำหรับการ์ด Dashboard
class _RatingStats {
  final double average;
  final int totalRated;
  final Map<int, int> distribution; // {1: n, 2: n, ..., 5: n}
  final List<_TechnicianRating> byTechnician;
  const _RatingStats({
    required this.average,
    required this.totalRated,
    required this.distribution,
    required this.byTechnician,
  });
}

/// รวมชุดข้อมูลสถิติทั้งหมดของ Dashboard
class _DashboardData {
  final int customerCount,
      technicianCount,
      adminCount,
      jobsThisMonth,
      completedThisMonth,
      lowStockCount;
  final double? growthPercent;
  final double totalPaid, totalPending;
  final List<_MonthRevenue> monthlyRevenue;
  // 🆕 [ใหม่] จำนวนงานซ่อมแยกตามระดับความรุนแรง (ต่ำ/ปกติ/สูง/เร่งด่วน)
  final Map<String, int> severityCounts;
  // 🆕 [ใหม่] สถิติการประเมินผลช่างซ่อม (ให้คะแนนดาว 1-5 โดยลูกค้า)
  final _RatingStats ratingStats;

  const _DashboardData({
    required this.customerCount,
    required this.technicianCount,
    required this.adminCount,
    required this.jobsThisMonth,
    required this.completedThisMonth,
    required this.growthPercent,
    required this.monthlyRevenue,
    required this.totalPaid,
    required this.totalPending,
    required this.lowStockCount,
    required this.severityCounts,
    required this.ratingStats,
  });
}

// =============================================================================
// 3. UI COMPONENTS (ชิ้นส่วนหน้าจอแยกย่อย)
// =============================================================================

// -----------------------------------------------------------------------------
// [_Header] แถบด้านบน แสดงชื่อ Dashboard
// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------
// [_RatingCard] การ์ดสรุปการประเมินผลช่างซ่อม (คะแนนดาว 1-5 โดยลูกค้า)
// -----------------------------------------------------------------------------
class _RatingCard extends StatelessWidget {
  final _RatingStats stats;
  const _RatingCard(this.stats);

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: Colors.amber,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.star_rounded,
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text('ประเมินผลช่างซ่อม',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),
          if (stats.totalRated == 0)
            const Text('ยังไม่มีลูกค้าให้คะแนนช่างซ่อม',
                style: TextStyle(
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                    color: AppColors.textHint))
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(stats.average.toStringAsFixed(2),
                    style: const TextStyle(
                        color: AppColors.primaryDark,
                        fontSize: 32,
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.w700,
                        height: 1)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('/5 จาก ${stats.totalRated} รีวิว',
                      style: const TextStyle(
                          fontSize: 12, fontFamily: AppStyles.fontFamily)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // สัดส่วนดาว 5 -> 1
            for (var star = 5; star >= 1; star--)
              _RatingBar(
                star: star,
                count: stats.distribution[star] ?? 0,
                total: stats.totalRated,
              ),
            if (stats.byTechnician.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              const Text('อันดับช่างซ่อม (เฉลี่ยสูงสุด)',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final t in stats.byTechnician.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(t.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13,
                                fontFamily: AppStyles.fontFamily)),
                      ),
                      const Icon(Icons.star_rounded,
                          size: 14, color: Colors.amber),
                      const SizedBox(width: 2),
                      Text(t.average.toStringAsFixed(2),
                          style: const TextStyle(
                              fontSize: 13,
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Text('(${t.count})',
                          style: const TextStyle(
                              fontSize: 12,
                              fontFamily: AppStyles.fontFamily,
                              color: AppColors.textHint)),
                    ],
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }
}

class _RatingBar extends StatelessWidget {
  final int star;
  final int count;
  final int total;
  const _RatingBar(
      {required this.star, required this.count, required this.total});

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('$star',
              style: const TextStyle(
                  fontSize: 11, fontFamily: AppStyles.fontFamily)),
          const SizedBox(width: 2),
          const Icon(Icons.star_rounded, size: 12, color: Colors.amber),
          const SizedBox(width: 6),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: AppColors.background,
                valueColor:
                    const AlwaysStoppedAnimation<Color>(Colors.amber),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 20,
            child: Text('$count',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 11, fontFamily: AppStyles.fontFamily)),
          ),
        ],
      ),
    );
  }
}


class _JobsCard extends StatelessWidget {
  final _DashboardData data;
  const _JobsCard(this.data);

  @override
  Widget build(BuildContext context) {
    final growth = data.growthPercent;
    final isUp = (growth ?? 0) >= 0;

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.build_outlined,
                    size: 16, color: AppColors.background),
              ),
              const SizedBox(width: 8),
              const Text('งานซ่อมเดือนนี้',
                  style: TextStyle(
                      fontSize: 12,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text('${data.jobsThisMonth}',
              style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 36,
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w700,
                  height: 1)),
          const Text('งาน',
              style: TextStyle(fontSize: 11, fontFamily: AppStyles.fontFamily)),
          const SizedBox(height: 8),
          // Badge แสดง % การเติบโตเปรียบเทียบเดือนก่อน
          if (growth != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: isUp ? AppColors.greenBg : AppColors.redBg,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(
                '${isUp ? '+' : ''}${growth.toStringAsFixed(0)}% จากเดือนก่อน',
                style: TextStyle(
                    color: isUp ? AppColors.greenText : AppColors.redText,
                    fontSize: 11,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w600),
              ),
            )
          else
            const Text('ยังไม่มีข้อมูลเดือนก่อนสำหรับเปรียบเทียบ',
                style: TextStyle(
                    color: AppColors.textSubtitle,
                    fontSize: 10,
                    fontFamily: AppStyles.fontFamily)),
          const SizedBox(height: 8),
          Text(
              'เสร็จสิ้นแล้ว ${data.completedThisMonth} จาก ${data.jobsThisMonth} งาน',
              style: const TextStyle(
                  color: AppColors.textLabel,
                  fontSize: 11,
                  fontFamily: AppStyles.fontFamily)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// [_SeverityCard] การ์ดสถิติงานซ่อมตามระดับความรุนแรง (โดนัท) — แทนที่การ์ด
// "จำนวนผู้ใช้งาน" เดิม ดีไซน์ตามหน้าเว็บ (ReportsPage.jsx ส่วน
// SeverityBreakdownSection) แต่ตัดส่วน "สัดส่วนร้อยละ" ออก เอาเฉพาะกราฟโดนัท
// + legend รายการจำนวน ให้พอดีกับพื้นที่การ์ดเล็กๆ บนมือถือ
// -----------------------------------------------------------------------------
class _SeverityCard extends StatelessWidget {
  final _DashboardData data;
  const _SeverityCard(this.data);

  @override
  Widget build(BuildContext context) {
    final counts = data.severityCounts;
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    final segments = [
      for (final level in _severityLevels)
        if ((counts[level] ?? 0) > 0)
          MapEntry(_severityColors[level]!, counts[level]!),
    ];

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('สถิติความรุนแรงงานซ่อม',
              style: TextStyle(
                  fontSize: 12,
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(84, 84),
                    painter: _DonutPainter(segments: segments, total: total),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$total',
                          style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontSize: 20,
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.w700,
                              height: 1)),
                      const Text('งานทั้งหมด',
                          style: TextStyle(
                              fontSize: 9,
                              fontFamily: AppStyles.fontFamily,
                              color: AppColors.textSubtitle)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          for (final level in _severityLevels)
            _row(level, counts[level] ?? 0, _severityColors[level]!),
        ],
      ),
    );
  }

  Widget _row(String label, int val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11, fontFamily: AppStyles.fontFamily)),
            ],
          ),
          Text('$val',
              style: const TextStyle(
                  color: AppColors.primaryDark,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppStyles.fontFamily)),
        ],
      ),
    );
  }
}

// 🆕 [ใหม่] วาดกราฟโดนัท (ring chart) ด้วย CustomPainter ตรงๆ เพราะโปรเจกต์นี้
// ไม่มี dependency กราฟ (เช่น fl_chart) อยู่แล้ว ไม่อยากเพิ่ม dependency ใหม่
// แค่สำหรับกราฟวงกลมวงเดียว — เริ่มวาดจาก 12 นาฬิกา (มุม -90°) ไล่ตามเข็ม
// นาฬิกาเหมือนกับ Pie chart ฝั่งเว็บ (recharts) มีช่องว่างเล็กๆ คั่นระหว่าง
// segment ให้คล้าย paddingAngle ของเว็บ
class _DonutPainter extends CustomPainter {
  final List<MapEntry<Color, int>> segments;
  final int total;
  const _DonutPainter({required this.segments, required this.total});

  static const double _strokeWidth = 12;
  static const double _gapRadians = 0.045;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      _strokeWidth / 2,
      _strokeWidth / 2,
      size.width - _strokeWidth,
      size.height - _strokeWidth,
    );

    if (total <= 0 || segments.isEmpty) {
      final emptyPaint = Paint()
        ..color = AppColors.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth;
      canvas.drawArc(rect, 0, 2 * math.pi, false, emptyPaint);
      return;
    }

    double startAngle = -math.pi / 2;
    for (final segment in segments) {
      final sweep = (segment.value / total) * 2 * math.pi;
      final paint = Paint()
        ..color = segment.key
        ..style = PaintingStyle.stroke
        ..strokeWidth = _strokeWidth
        ..strokeCap = StrokeCap.butt;
      // เว้นช่องว่างเล็กน้อยระหว่าง segment (ยกเว้นตอน segment เดียวเต็มวง
      // จะไม่มีช่องว่างให้เห็น เพราะไม่มี segment อื่นมาคั่น)
      final drawSweep =
          segments.length > 1 ? (sweep - _gapRadians).clamp(0.0, sweep) : sweep;
      canvas.drawArc(rect, startAngle, drawSweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.segments != segments || oldDelegate.total != total;
}

// -----------------------------------------------------------------------------
// [_FinanceCard] การ์ดแสดงสถิติรายรับย้อนหลัง 6 เดือน (แท่งกราฟเปรียบเทียบ)
// -----------------------------------------------------------------------------
class _FinanceCard extends StatelessWidget {
  final _DashboardData data;
  const _FinanceCard(this.data);

  @override
  Widget build(BuildContext context) {
    // คำนวณขอบเขตความสูงสูงสุดของกราฟ (Max Value)
    final maxVal = data.monthlyRevenue
        .expand((m) => [m.paid, m.pending])
        .fold<double>(1, (m, v) => v > m ? v : m);

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('สถิติการเงินย้อนหลัง 6 เดือน',
                  style: TextStyle(
                      fontSize: 13,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.w700)),
              Row(
                children: [
                  _dot('ชำระแล้ว', AppColors.primary),
                  const SizedBox(width: 10),
                  _dot('รอชำระ', AppColors.yellowText),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ส่วนแสดงผลกราฟแท่ง (Custom Bar Chart)
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.monthlyRevenue.map((m) {
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // แท่งยอดชำระแล้ว (สีฟ้า/น้ำเงิน)
                          Container(
                              width: 8,
                              height: ((m.paid / maxVal) * 90).clamp(2, 90),
                              decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(3))),
                          const SizedBox(width: 3),
                          // แท่งยอดรอชำระ (สีเหลือง)
                          Container(
                              width: 8,
                              height: ((m.pending / maxVal) * 90).clamp(2, 90),
                              decoration: BoxDecoration(
                                  color: AppColors.yellowText,
                                  borderRadius: BorderRadius.circular(3))),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(m.label,
                          style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.textSubtitle,
                              fontFamily: AppStyles.fontFamily)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          // สรุปยอดรวม ชำระแล้ว / รอชำระ ด้านล่างกราฟ
          Row(
            children: [
              Expanded(
                  child: _totalBox('รายรับที่ชำระแล้ว', data.totalPaid,
                      AppColors.redBg, AppColors.primaryDark)),
              const SizedBox(width: 8),
              Expanded(
                  child: _totalBox('รอการชำระ', data.totalPending,
                      AppColors.yellowBg, AppColors.yellowText)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dot(String label, Color c) => Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontFamily: AppStyles.fontFamily)),
        ],
      );

  Widget _totalBox(String title, double val, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 10, fontFamily: AppStyles.fontFamily)),
          Text('฿${val.toStringAsFixed(0)}',
              style: TextStyle(
                  color: fg,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppStyles.fontFamily)),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// [_ReportsCard] การ์ดรายการรายงานประจำเดือน และทางลัดเปิดไปหน้าอื่น (Navigation)
// -----------------------------------------------------------------------------
class _ReportsCard extends StatelessWidget {
  final _DashboardData data;
  const _ReportsCard(this.data);

  @override
  Widget build(BuildContext context) {
    final jobsDone =
        data.completedThisMonth == data.jobsThisMonth && data.jobsThisMonth > 0;

    // หากต้องการแก้ Route หรือคำอธิบายเมนูย่อย สามารถปรับที่ List ด้านล่างนี้ได้เลย
    final items = [
      _ReportItem(
        'สรุปงานซ่อมประจำเดือน',
        'เสร็จแล้ว ${data.completedThisMonth}/${data.jobsThisMonth} งาน',
        jobsDone ? 'เสร็จสิ้น' : 'กำลังดำเนินการ',
        jobsDone ? AppColors.greenText : AppColors.blueText,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RepairListAdminPage()),
        ),
      ),
      _ReportItem(
        'รายรับ-รายจ่ายประจำเดือน',
        'ชำระแล้ว ฿${data.totalPaid.toStringAsFixed(0)} • รอชำระ ฿${data.totalPending.toStringAsFixed(0)}',
        'เสร็จสิ้น',
        AppColors.greenText,
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const FinancialScreen()),
        ),
      ),
      _ReportItem(
        'รายงานสต็อกอะไหล่',
        data.lowStockCount > 0
            ? 'มีอะไหล่ใกล้หมด ${data.lowStockCount} รายการ'
            : 'สต็อกอะไหล่อยู่ในเกณฑ์ปกติ',
        data.lowStockCount > 0 ? 'รอตรวจสอบ' : 'เสร็จสิ้น',
        data.lowStockCount > 0 ? AppColors.yellowText : AppColors.greenText,
        // 🐛 [แก้บัค] เดิมกดแล้วไม่ทำอะไรเลย (() {}) — เพิ่มให้กดแล้วไปหน้า
        // จัดการอะไหล่ (AdminSparePartPage) เหมือนการ์ดรายการอื่น ๆ ในรายการนี้
        () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const AdminSparePartPage()),
        ),
      ),
      _ReportItem(
        'รายงานความพึงพอใจลูกค้า',
        'ยังไม่มีระบบเก็บแบบสอบถามในฐานข้อมูล',
        'ยังไม่รองรับ',
        AppColors.textHint,
        () => ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ฟีเจอร์นี้ยังไม่เปิดใช้งาน'))),
      ),
    ];

    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('รายงานประจำเดือน',
              style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ReportRow(item: item),
              )),
        ],
      ),
    );
  }
}

/// โมเดลเก็บข้อมูลแถบรายการรายงาน
class _ReportItem {
  final String title, subtitle, status;
  final Color statusColor;
  final VoidCallback onTap;
  _ReportItem(
      this.title, this.subtitle, this.status, this.statusColor, this.onTap);
}

/// แถบรายการรายงานแบบกดได้
class _ReportRow extends StatelessWidget {
  final _ReportItem item;
  const _ReportRow({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 1))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(
                            fontSize: 12,
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(item.subtitle,
                        style: const TextStyle(
                            fontSize: 10,
                            fontFamily: AppStyles.fontFamily,
                            color: AppColors.textSubtitle)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: item.statusColor.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(item.status,
                    style: TextStyle(
                        color: item.statusColor,
                        fontSize: 10,
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// [_CardShell] กรอบพื้นหลังการ์ดส่วนกลาง (Reusable Container)
// -----------------------------------------------------------------------------
class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14)),
      child: child,
    );
  }
}