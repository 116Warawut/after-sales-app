import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:after_sales/common_bottom_navbar.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/services.dart' as db;

import 'package:after_sales/screens/admin/dashboard.dart';
import 'package:after_sales/screens/admin/repair_list_admin.dart';
import 'package:after_sales/screens/admin/assign_repair_formdetail.dart'
    hide RepairStatus;
import 'package:after_sales/screens/admin/admin_notification.dart';
import 'package:after_sales/screens/admin/admin_financial.dart';
import 'package:after_sales/screens/admin/admin_spare_part.dart';
import 'package:after_sales/screens/admin/manage_technician.dart';
import 'package:after_sales/screens/admin/manage_customer.dart';
import 'package:after_sales/screens/admin/profile_admin.dart';
import 'package:after_sales/screens/shared/chat_list_page.dart';
import 'package:after_sales/screens/shared/home_ui.dart';

abstract final class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E7EB);
  static const textMain = Color(0xFF1F2937);
  static const yellowBg = Color(0xFFFFF7D6);
  static const yellowText = Color(0xFF9A6700);
  static const blueBg = Color(0xFFE0F2FE);
  static const blueText = Color(0xFF0369A1);
  static const accentPurple = Color(0xFF7C3AED);
  static const greenBg = Color(0xFFDCFCE7);
  static const greenText = Color(0xFF15803D);
  static const redBg = Color(0xFFFEE2E2);
  static const redText = Color(0xFFB91C1C);
}

class HomeAdmin extends StatelessWidget {
  const HomeAdmin({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminRootShell();
  }
}

class AdminRootShell extends StatefulWidget {
  const AdminRootShell({super.key});

  @override
  State<AdminRootShell> createState() => _AdminRootShellState();
}

class _AdminRootShellState extends State<AdminRootShell> {
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

  Future<void> _loadUnreadCount() async {
    try {
      final count = await db.DatabaseHelper.instance
          .getUnreadNotificationCount(db.Session.currentUsername);
      final chatRooms = await db.DatabaseHelper.instance
          .getUnreadChatRoomCount(db.Session.currentUsername, 'ADMIN');
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
        body: IndexedStack(
          index: _navIndex,
          children: [
            Navigator(
              key: _navigatorKeys[0],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => AdminHomeContent(
                  onViewAllJobs: () => setState(() => _navIndex = 1),
                  onNotificationTap: () => setState(() => _navIndex = 3),
                ),
              ),
            ),
            Navigator(
              key: _navigatorKeys[1],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => RepairListAdminPage(
                  onBack: () => setState(() => _navIndex = 0),
                ),
              ),
            ),
            Navigator(
              key: _navigatorKeys[2],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => ChatListPage(
                  role: UserRole.admin,
                  onUnreadCountsChanged: _loadUnreadCount,
                ),
              ),
            ),
            Navigator(
              key: _navigatorKeys[3],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => AdminNotificationPage(
                  onUnreadCountsChanged: _loadUnreadCount,
                ),
              ),
            ),
            Navigator(
              key: _navigatorKeys[4],
              onGenerateRoute: (settings) => MaterialPageRoute(
                builder: (_) => const ProfileAdminPage(),
              ),
            ),
          ],
        ),
        bottomNavigationBar: CommonBottomNavBar(
          currentIndex: _navIndex,
          role: UserRole.admin,
          notificationCount: _unreadNotifications,
          chatCount: _unreadChatRooms,
          onTap: (index) {
            setState(() => _navIndex = index);
            _loadUnreadCount();
          },
        ),
      ),
    );
  }
}

class AdminHomeContent extends StatefulWidget {
  final VoidCallback onViewAllJobs;
  final VoidCallback onNotificationTap;

  const AdminHomeContent({
    super.key,
    required this.onViewAllJobs,
    required this.onNotificationTap,
  });

  @override
  State<AdminHomeContent> createState() => _AdminHomeContentState();
}

class _AdminHomeContentState extends State<AdminHomeContent> {
  bool _loading = true;
  int _completed = 0;
  List<RepairListItem> _recentJobs = [];

  int _pendingPartRequests = 0;
  String _adminName = 'Admin';

  int _waitingCount = 0;
  int _inProgressCount = 0;
  int _urgentCount = 0;
  int _overdueCount = 0;
  int _issueCount = 0; // 🔴 ปลดจากค่าคงที่ เป็นตัวแปรที่รับค่าจากการนับจริง

  final int _waitingTechUpdateCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  DateTime? _parseThaiDate(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return null;
    final parts = dateStr.split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final yearBE = int.tryParse(parts[2]);
    if (day == null || month == null || yearBE == null) return null;
    return DateTime(yearBE - 543, month, day);
  }

  Future<void> _loadSummary() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final dbHelper = db.DatabaseHelper.instance;
      final allRawRepairs = await dbHelper.getAllRepairs();
      final allRawPartRequests = await dbHelper.getAllPartRequests();

      final repairs = db.Session.isMainAdmin
          ? allRawRepairs
          : allRawRepairs.where((r) {
              final adminUser = r['admin_username']?.toString().trim();
              return adminUser == null ||
                  adminUser.isEmpty ||
                  adminUser == db.Session.currentUsername;
            }).toList();

      final allowedRepairIds = repairs
          .map((r) => (r['id'] ?? r['_fbKey'])?.toString())
          .whereType<String>()
          .toSet();

      final partRequests = db.Session.isMainAdmin
          ? allRawPartRequests
          : allRawPartRequests.where((pr) {
              final rId = pr['repair_id']?.toString();
              return rId == null || rId.isEmpty || allowedRepairIds.contains(rId);
            }).toList();

      final adminProfile =
          await dbHelper.getAdminProfile(db.Session.currentUsername);
      final adminName = (adminProfile?['admin_name']?.toString())?.trim();

      int completed = 0;
      int waiting = 0;
      int inProgress = 0;
      int urgent = 0;
      int overdue = 0;
      int issue = 0; // 🔴 ตัวนับสถานะมีปัญหา
      final today = DateTime.now();
      final todayDateOnly = DateTime(today.year, today.month, today.day);

      for (final r in repairs) {
        final eff = db.getEffectiveRepairStatus(r);
        final rawStatus = (r['status']?.toString()) ?? '';
        final isCancelled = rawStatus.contains('ยกเลิก');

        if (eff == 'เสร็จสิ้น' || eff == 'เสร็จแล้ว') {
          completed++;
          continue;
        }
        if (isCancelled) continue;

        // 🔴 เช็คสถานะมีปัญหาจริงจากงานซ่อม
        if (eff == 'มีปัญหา' || rawStatus.contains('ปัญหา')) {
          issue++;
        }

        if (eff == 'รอจัดสรรช่าง') waiting++;
        if (eff == 'กำลังซ่อม' || eff == 'กำลังเดินทาง' || eff == 'กำลังดำเนินการ') inProgress++;

        final detail = (r['detail']?.toString()) ?? '';
        final isSevere = detail.contains('[ความรุนแรง: เร่งด่วน]');
        final isAdminUrgent = r['is_urgent'] == true || r['is_urgent'] == 1;
        if (isSevere || isAdminUrgent) urgent++;

        final jobDate = _parseThaiDate(r['date']?.toString());
        if (jobDate != null && jobDate.isBefore(todayDateOnly)) {
          overdue++;
        }
      }

      final pendingParts =
          partRequests.where((r) => r['status'] == 'รอดำเนินการ').length;

      final recent =
          repairs.take(3).map((r) => RepairListItem.fromMap(r)).toList();

      if (!mounted) return;
      setState(() {
        _completed = completed;
        _recentJobs = recent;
        _pendingPartRequests = pendingParts;
        _adminName =
            (adminName != null && adminName.isNotEmpty) ? adminName : 'Admin';
        _waitingCount = waiting;
        _inProgressCount = inProgress;
        _urgentCount = urgent;
        _overdueCount = overdue;
        _issueCount = issue; // 🔴 บันทึกตัวเลขมีปัญหาเข้า State
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading admin home summary: $e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('โหลดข้อมูลสรุปไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _openDashboard() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
    );
    _loadSummary();
  }

  Future<void> _openManageTechnician() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageTechnicianPage()),
    );
    _loadSummary();
  }

  Future<void> _openManageCustomer() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ManageCustomerPage()),
    );
    _loadSummary();
  }

  Future<void> _openFinancial() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const FinancialScreen()),
    );
    _loadSummary();
  }

  Future<void> _openSpareParts() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminSparePartPage()),
    );
    _loadSummary();
  }

  Future<void> _openJobDetail(RepairListItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignRepairFormDetailPage(repairId: item.id),
      ),
    );
    _loadSummary();
  }

  @override
  Widget build(BuildContext context) {
    return HomeScaffold(
      isLoading: _loading,
      onRefresh: _loadSummary,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'สวัสดี $_adminName 👋',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                db.Session.isMainAdmin
                    ? 'แอดมินหลัก (ภาพรวมทั้งระบบ)'
                    : 'แอดมินทั่วไป (งานในความรับผิดชอบ)',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6B7280),
                  fontFamily: 'Sarabun',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        const HomeSectionHeader('ภาพรวมงานซ่อม'),
        const SizedBox(height: 12),
        StatsGrid2x2(
          boxes: [
            StatBox(
              label: 'รอจัดสรรช่าง',
              value: _waitingCount,
              icon: Icons.hourglass_empty,
              bg: AppColors.yellowBg,
              fg: AppColors.yellowText,
            ),
            StatBox(
              label: 'กำลังซ่อม',
              value: _inProgressCount,
              icon: Icons.build_outlined,
              bg: AppColors.blueBg,
              fg: AppColors.blueText,
            ),
            StatBox(
              label: 'เสร็จ',
              value: _completed,
              icon: Icons.check_circle_outline,
              bg: AppColors.greenBg,
              fg: AppColors.greenText,
            ),
            StatBox(
              label: 'เร่งด่วน',
              value: _urgentCount,
              icon: Icons.priority_high,
              bg: AppColors.redBg,
              fg: AppColors.redText,
            ),
          ],
        ),
        const SizedBox(height: 24),

        const HomeSectionHeader('ทางลัด'),
        const SizedBox(height: 12),
        HomeShortcutGrid(
          tiles: [
            HomeShortcutTile(
              icon: Icons.people_outline,
              label: 'จัดการลูกค้า',
              onTap: _openManageCustomer,
            ),
            HomeShortcutTile(
              icon: Icons.engineering_outlined,
              label: 'จัดการช่าง',
              onTap: _openManageTechnician,
            ),
            HomeShortcutTile(
              icon: Icons.inventory_2_outlined,
              label: 'จัดการอะไหล่',
              onTap: _openSpareParts,
              badgeCount: _pendingPartRequests,
            ),
            HomeShortcutTile(
              icon: Icons.payments_outlined,
              label: 'การเงิน',
              onTap: _openFinancial,
            ),
            HomeShortcutTile(
              icon: Icons.bar_chart,
              label: 'สรุปผล (Dashboard)',
              onTap: _openDashboard,
            ),
          ],
        ),
        const SizedBox(height: 24),

        const HomeSectionHeader('ต้องดำเนินการ'),
        const SizedBox(height: 12),
        _ActionNeededCard(
          unassignedCount: _waitingCount,
          waitingTechUpdateCount: _waitingTechUpdateCount,
          issueCount: _issueCount, // 🔴 ส่งค่าตัวเลขมีปัญหาจริง
          overdueCount: _overdueCount,
          onViewAll: widget.onViewAllJobs,
        ),
        const SizedBox(height: 24),

        HomeSectionHeader('งานล่าสุด', onAction: widget.onViewAllJobs),
        const SizedBox(height: 12),
        if (_recentJobs.isEmpty)
          const HomeEmptyState(message: 'ยังไม่มีรายการแจ้งซ่อม')
        else
          for (var i = 0; i < _recentJobs.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: HomeJobTile(
                ticket: _recentJobs[i].ticketId,
                subtitle:
                    '${_recentJobs[i].customerName} • ${_recentJobs[i].modelName}',
                statusLabel: _recentJobs[i].status.label,
                statusBg: _recentJobs[i].status.bg,
                statusFg: _recentJobs[i].status.fg,
                onTap: () => _openJobDetail(_recentJobs[i]),
              ),
            ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _ActionNeededCard extends StatelessWidget {
  final int unassignedCount;
  final int waitingTechUpdateCount;
  final int issueCount;
  final int overdueCount;
  final VoidCallback onViewAll;

  const _ActionNeededCard({
    required this.unassignedCount,
    required this.waitingTechUpdateCount,
    required this.issueCount,
    required this.overdueCount,
    required this.onViewAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ActionNeededRow(
            icon: Icons.person_search_outlined,
            text: '$unassignedCount งาน — รอจัดสรรช่าง',
            color: AppColors.yellowText,
          ),
          const SizedBox(height: 10),
          _ActionNeededRow(
            icon: Icons.engineering_outlined,
            text: '$waitingTechUpdateCount งาน — รอการอัปเดตจากช่าง',
            color: AppColors.blueText,
          ),
          const SizedBox(height: 10),
          _ActionNeededRow(
            icon: Icons.report_gmailerrorred_outlined,
            text: '$issueCount งาน — มีปัญหา', // 🔴 ปรับข้อความเป็น "มีปัญหา" ให้ตรงกับเว็บ
            color: AppColors.redText,
          ),
          const SizedBox(height: 10),
          _ActionNeededRow(
            icon: Icons.warning_amber_outlined,
            text: '$overdueCount งาน — เลยกำหนดเวลา',
            color: AppColors.redText,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onViewAll,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.redText,
                side: const BorderSide(color: AppColors.redText),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text(
                'ดูทั้งหมด',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionNeededRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _ActionNeededRow({
    required this.icon,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textMain,
            ),
          ),
        ),
      ],
    );
  }
}