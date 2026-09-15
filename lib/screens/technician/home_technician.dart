import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/technician/job_detail.dart';
import 'package:after_sales/screens/technician/joblist_technician.dart';
import 'package:after_sales/screens/technician/technician_notification.dart';
import 'package:after_sales/screens/technician/profile_technician.dart';
import 'package:after_sales/screens/technician/spare_part_tec_viewer.dart';
import 'package:after_sales/screens/shared/home_ui.dart';
import 'package:after_sales/common_bottom_navbar.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/shared/chat_list_page.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeTechnician extends StatelessWidget {
  const HomeTechnician({super.key});

  @override
  Widget build(BuildContext context) {
    return const TechnicianRootShell();
  }
}

/// Shell กลางของฝั่งช่าง ใช้ CommonBottomNavBar ตัวเดียวกับ Customer/Admin
class TechnicianRootShell extends StatefulWidget {
  const TechnicianRootShell({super.key});

  @override
  State<TechnicianRootShell> createState() => _TechnicianRootShellState();
}

class _TechnicianRootShellState extends State<TechnicianRootShell> {
  int _navIndex = 0;
  int _unreadNotifications = 0;
  int _unreadChatRooms = 0;

  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  /// 🔔 นับจำนวนแจ้งเตือนที่ยังไม่อ่าน — โชว์เป็นวงกลมแดงบนแท็บกระดิ่ง
  /// และนับจำนวนห้องแชทที่มีข้อความยังไม่อ่าน — โชว์บนแท็บแชท
  Future<void> _loadUnreadCount() async {
    try {
      final count = await db.DatabaseHelper.instance
          .getUnreadNotificationCount(db.Session.currentUsername);
      final chatRooms = await db.DatabaseHelper.instance
          .getUnreadChatRoomCount(db.Session.currentUsername, 'TECHNICIAN');
      if (!mounted) return;
      setState(() {
        _unreadNotifications = count;
        _unreadChatRooms = chatRooms;
      });
    } catch (e) {
      debugPrint('Error loading unread notification count: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final currentNavigator = _navigatorKeys[_navIndex].currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else if (_navIndex != 0) {
          setState(() => _navIndex = 0);
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: _navIndex,
          children: [
            // 📌 แท็บ 0: หน้าหลัก
            Navigator(
              key: _navigatorKeys[0],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => NextJobPage(
                  onViewAllJobs: () => setState(() => _navIndex = 1),
                  onNotificationTap: () => setState(() => _navIndex = 3),
                ),
              ),
            ),

            // 📌 แท็บ 1: งานทั้งหมด
            Navigator(
              key: _navigatorKeys[1],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => RepairListPage(
                  onBack: () => setState(() => _navIndex = 0),
                ),
              ),
            ),

            // 📌 แท็บ 2: รายการแชท (เลือกงานที่จะคุยได้)
            Navigator(
              key: _navigatorKeys[2],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => ChatListPage(
                  role: UserRole.technician,
                  // 🔴 [แก้ไข] เดิมตัวเลขบนแท็บแชท/กระดิ่งค้างหลังอ่านแล้วออกจาก
                  // ห้องแชท จนกว่าจะสลับแท็บเอง — ให้รีเฟรชทันทีที่กลับมาจากห้องแชท
                  onUnreadCountsChanged: _loadUnreadCount,
                ),
              ),
            ),

            // 📌 แท็บ 3: แจ้งเตือน
            Navigator(
              key: _navigatorKeys[3],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => TechnicianNotificationPage(
                  onUnreadCountsChanged: _loadUnreadCount,
                ),
              ),
            ),

            // 📌 แท็บ 4: โปรไฟล์
            Navigator(
              key: _navigatorKeys[4],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => const ProfileTechnicianPage(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: CommonBottomNavBar(
          currentIndex: _navIndex,
          role: UserRole.technician,
          notificationCount: _unreadNotifications,
          chatCount: _unreadChatRooms,
          onTap: (index) {
            setState(() => _navIndex = index);
            // 🔄 อัปเดตตัวเลขแจ้งเตือนใหม่ทุกครั้งที่สลับแท็บ
            _loadUnreadCount();
          },
        ),
      ),
    );
  }
}

/// Job model - swap for real data from your backend / state manager.
class NextJob {
  final int repairId;
  final String ticketId;
  final String company;
  final String machine;
  final String date;
  final String address;
  const NextJob({
    required this.repairId,
    required this.ticketId,
    required this.company,
    required this.machine,
    required this.date,
    required this.address,
  });
}

/// Today's overall job stats - swap for real data from your backend.
class JobSummary {
  final int total;
  final int done;
  final int remaining;
  const JobSummary({
    required this.total,
    required this.done,
    required this.remaining,
  });

  double get progress => total == 0 ? 0 : done / total;
}

/// งาน 1 รายการที่ต้องทำวันนี้ (ใช้กับรายการ "งานที่ต้องทำวันนี้" ใต้งานถัดไป)
class TodayJobItem {
  final int repairId;
  final String? time;
  final String machine;
  final String company;
  const TodayJobItem({
    required this.repairId,
    required this.time,
    required this.machine,
    required this.company,
  });
}

class NextJobPage extends StatefulWidget {
  final VoidCallback? onViewAllJobs;
  final VoidCallback? onNotificationTap;

  const NextJobPage({super.key, this.onViewAllJobs, this.onNotificationTap});

  @override
  State<NextJobPage> createState() => _NextJobPageState();
}

class _NextJobPageState extends State<NextJobPage> {
  bool _loading = true;
  NextJob? _job;
  // 🆕 ชื่อช่างสำหรับคำทักทาย
  String _techName = '-';

  // 🆕 สรุปงาน "วันนี้" เท่านั้น (ต่างจาก _done ด้านบนที่นับรวมทุกวัน)
  int _totalToday = 0;
  int _inProgressToday = 0;
  int _doneToday = 0;
  int _urgentToday = 0;
  String? _firstJobTimeToday;
  List<TodayJobItem> _todayJobs = [];

  /// แจ้งเตือนเรื่องคำขอเบิกอะไหล่ที่ยังไม่อ่าน (เช่น แอดมินเพิ่งอนุมัติ/ปฏิเสธ)
  /// โชว์เป็นวงกลมแดงบนปุ่มลัด "เบิกอะไหล่"
  int _unreadPartRequestUpdates = 0;

  //double get _progress => _total == 0 ? 0 : _done / _total;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  Future<void> _loadSummary() async {
    setState(() => _loading = true);
    try {
      final rows = await db.DatabaseHelper.instance
          .getRepairsByTechnician(db.Session.currentUsername);
      final unreadPartUpdates =
          await db.DatabaseHelper.instance.getUnreadNotificationCountByType(
        db.Session.currentUsername,
        'PART_REQUEST',
      );

      // 🆕 ดึงชื่อจริงของช่างมาใช้ทักทาย (เดิมใช้คำว่า "ช่างผู้ดูแล" ลอย ๆ)
      final techProfile = await db.DatabaseHelper.instance
          .getTechnicianByUsername(db.Session.currentUsername);
      final techName = (techProfile?['tech_name'] as String?)?.trim();

      Map<String, dynamic>? nextRow;
      for (final r in rows) {
        final status = (r['status'] as String?) ?? '';
        if (!status.contains('เสร็จ')) {
          nextRow ??= r;
        }
      }

      NextJob? job;
      if (nextRow != null) {
        String company = '-';
        final customerUsername = nextRow['customer_username'] as String?;
        if (customerUsername != null && customerUsername.isNotEmpty) {
          final customer = await db.DatabaseHelper.instance
              .getCustomerProfile(customerUsername);
          if (customer != null) {
            company =
                '${customer['name'] ?? ''} ${customer['surname'] ?? ''}'.trim();
            if (company.isEmpty) company = customerUsername;
          } else {
            company = customerUsername;
          }
        }
        job = NextJob(
          repairId: toIntOr(nextRow['id'], 0),
          ticketId: (nextRow['ticketNo'] as String?) ?? '-',
          company: company,
          machine: (nextRow['machine'] as String?) ?? '-',
          date: (nextRow['date'] as String?) ?? '-',
          address: (nextRow['location'] as String?) ?? '-',
        );
      }

      // 🆕 [แก้ไข] คัดกรองเฉพาะ "งานวันนี้" — ใช้รูปแบบวันที่เดียวกับตอนสร้างงาน
      // ('d/M/พ.ศ.') เพื่อเทียบสตริงตรง ๆ ได้ ไม่ต้องแปลงวันที่ไปมา
      final now = DateTime.now();
      final todayStr = '${now.day}/${now.month}/${now.year + 543}';
      final todayRows =
          rows.where((r) => (r['date'] as String?) == todayStr).toList();

      int inProgressToday = 0;
      int doneToday = 0;
      int urgentToday = 0;
      final todayJobs = <TodayJobItem>[];
      final todayTimes = <String>[];

      for (final r in todayRows) {
        final status = (r['status'] as String?) ?? '';
        if (status.contains('เสร็จ')) {
          doneToday++;
        } else if (status.contains('กำลังดำเนินการ')) {
          inProgressToday++;
        }

        // 🔴 งานเร่งด่วน = ลูกค้าเลือกระดับความรุนแรง "เร่งด่วน" ตอนแจ้งซ่อม
        // (เก็บเป็นข้อความนำหน้าใน 'detail' เช่น "[ความรุนแรง: เร่งด่วน] ...")
        // หรือแอดมินมอบหมายเป็นงานเร่งด่วนเองโดยเฉพาะ ('is_urgent' — ยังไม่มี UI
        // ให้แอดมินตั้งค่านี้ตอนนี้ เตรียมฟิลด์ไว้รอต่อ)
        final detail = (r['detail'] as String?) ?? '';
        final isSevere = detail.contains('[ความรุนแรง: เร่งด่วน]');
        final isAdminUrgent = r['is_urgent'] == true || r['is_urgent'] == 1;
        if (isSevere || isAdminUrgent) urgentToday++;

        final time = (r['appointment_time'] as String?)?.trim();
        if (time != null && time.isNotEmpty) todayTimes.add(time);

        String companyToday = '-';
        final custUsername = r['customer_username'] as String?;
        if (custUsername != null && custUsername.isNotEmpty) {
          final customer =
              await db.DatabaseHelper.instance.getCustomerProfile(custUsername);
          if (customer != null) {
            companyToday =
                '${customer['name'] ?? ''} ${customer['surname'] ?? ''}'.trim();
            if (companyToday.isEmpty) companyToday = custUsername;
          } else {
            companyToday = custUsername;
          }
        }

        todayJobs.add(TodayJobItem(
          repairId: toIntOr(r['id'], 0),
          time: (time != null && time.isNotEmpty) ? time : null,
          machine: (r['machine'] as String?) ?? '-',
          company: companyToday,
        ));
      }
      todayTimes.sort();

      if (!mounted) return;
      setState(() {
        _job = job;
        _unreadPartRequestUpdates = unreadPartUpdates;
        _techName = (techName != null && techName.isNotEmpty)
            ? techName
            : db.Session.currentUsername;
        _totalToday = todayRows.length;
        _inProgressToday = inProgressToday;
        _doneToday = doneToday;
        _urgentToday = urgentToday;
        _firstJobTimeToday = todayTimes.isNotEmpty ? todayTimes.first : null;
        _todayJobs = todayJobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('โหลดข้อมูลไม่สำเร็จ: $e')));
    }
  }

  void _showJobDetail() {
    final job = _job;
    if (job == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => JobsDetail(repairId: job.repairId),
      ),
    ).then((_) => _loadSummary());
  }

  void _showAllJobs() {
    if (widget.onViewAllJobs != null) {
      widget.onViewAllJobs!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ไปหน้า "งานทั้งหมด" (ยังไม่ได้เชื่อมต่อ)')),
    );
  }

  void _openRequestParts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RequestPartScreen()),
    );
    // 🔄 กลับมาแล้วรีเฟรชตัวเลขแจ้งเตือนบนปุ่มลัด เผื่อมีคำขอใหม่/อัปเดตระหว่างนั้น
    _loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;

    return HomeScaffold(
      isLoading: _loading,
      onRefresh: _loadSummary,
      children: [
        // 👋 คำทักทาย — เดิมใช้คำลอย ๆ "ช่างผู้ดูแล" เปลี่ยนเป็นชื่อจริงของช่างคนนั้น
        // พร้อมบรรทัดเล็กบอกจำนวนงานวันนี้ + เวลานัดงานแรก (ถ้ามีเวลาระบุไว้)
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'สวัสดี $_techName',
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textMain,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _firstJobTimeToday != null
                ? 'วันนี้มี $_totalToday งาน • เริ่มงานแรก $_firstJobTimeToday น.'
                : 'วันนี้มี $_totalToday งาน',
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 13,
              color: AppColors.textSubtitle,
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 📊 สรุปงานวันนี้ — 4 ช่อง (งานทั้งหมด/กำลังดำเนินการ/เสร็จแล้ว/เร่งด่วน)
        // แทนที่การ์ดแถบความคืบหน้าเดิม (TodaySummaryCard ยังใช้กับหน้าแรกของ
        // ลูกค้า/แอดมินอยู่ ไม่ได้แตะของเดิม แค่ไม่ใช้ตัวนั้นในหน้านี้แล้ว)
        const HomeSectionHeader('สรุปงานวันนี้'),
        const SizedBox(height: 12),
        StatsGrid2x2(
          boxes: [
            StatBox(
              label: 'งานทั้งหมด',
              value: _totalToday,
              icon: Icons.assignment_outlined,
              bg: AppColors.blueBg,
              fg: AppColors.blueText,
            ),
            StatBox(
              label: 'กำลังดำเนินการ',
              value: _inProgressToday,
              icon: Icons.autorenew,
              bg: AppColors.yellowBg,
              fg: AppColors.yellowText,
            ),
            StatBox(
              label: 'เสร็จแล้ว',
              value: _doneToday,
              icon: Icons.check_circle_outline,
              bg: AppColors.greenBg,
              fg: AppColors.greenText,
            ),
            StatBox(
              label: 'งานเร่งด่วน',
              value: _urgentToday,
              icon: Icons.priority_high,
              bg: AppColors.redBg,
              fg: AppColors.redText,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // 🔧 งานต่อไป (ของเดิม ไม่เปลี่ยนแปลง)
        const HomeSectionHeader('งานต่อไป'),
        const SizedBox(height: 12),
        if (job == null)
          const HomeEmptyState(
            icon: Icons.check_circle_outline,
            message: 'ไม่มีงานที่ต้องทำตอนนี้',
          )
        else
          HomeHighlightCard(
            title: 'งานต่อไป',
            rows: [
              HomeInfoRow('เลขแจ้งซ่อม', job.ticketId),
              HomeInfoRow('ลูกค้า', job.company),
              HomeInfoRow('เครื่อง', job.machine),
              HomeInfoRow('วันนัดซ่อม', job.date),
              HomeInfoRow('ที่อยู่', job.address),
            ],
            actionLabel: 'ดูรายละเอียดงาน',
            onAction: _showJobDetail,
          ),
        const SizedBox(height: 24),

        // 📋 งานที่ต้องทำวันนี้ — ไล่ทีละงาน (ช่าง 1 คนรับได้ไม่เกิน 3 งาน/วันอยู่แล้ว)
        const HomeSectionHeader('งานที่ต้องทำวันนี้'),
        const SizedBox(height: 12),
        if (_todayJobs.isEmpty)
          const HomeEmptyState(
            icon: Icons.event_available_outlined,
            message: 'วันนี้ไม่มีงานที่ต้องทำ',
          )
        else
          ..._todayJobs.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TodayJobTile(
                item: item,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => JobsDetail(repairId: item.repairId),
                  ),
                ).then((_) => _loadSummary()),
              ),
            ),
          ),
        const SizedBox(height: 24),

        // ⚡ ทางลัด
        const HomeSectionHeader('ทางลัด'),
        const SizedBox(height: 12),
        HomeShortcutGrid(
          tiles: [
            HomeShortcutTile(
              icon: Icons.assignment_outlined,
              label: 'ดูงานทั้งหมด',
              onTap: _showAllJobs,
            ),
            HomeShortcutTile(
              icon: Icons.inventory_2_outlined,
              label: 'เบิกอะไหล่',
              onTap: _openRequestParts,
              badgeCount: _unreadPartRequestUpdates,
            ),
          ],
        ),
      ],
    );
  }
}

/// 📋 การ์ดงาน 1 รายการในลิสต์ "งานที่ต้องทำวันนี้" — เวลา/เครื่องจักร/บริษัท
class _TodayJobTile extends StatelessWidget {
  final TodayJobItem item;
  final VoidCallback onTap;

  const _TodayJobTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule,
                        size: 18, color: AppColors.primary),
                    const SizedBox(height: 2),
                    Text(
                      item.time ?? '-',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 34,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: AppColors.border,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.machine,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.company,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12.5,
                        color: AppColors.textSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}