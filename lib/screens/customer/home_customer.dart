import 'package:after_sales/common_bottom_navbar.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:after_sales/models/repair.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

// Screens ฝั่ง Customer
import 'package:after_sales/screens/shared/chat_list_page.dart';
import 'package:after_sales/screens/customer/customer_job_detail.dart';
import 'package:after_sales/screens/customer/customer_notification.dart';
import 'package:after_sales/screens/customer/history_customer.dart';
import 'package:after_sales/screens/customer/profile_customer.dart';
import 'package:after_sales/screens/customer/repair_form.dart';
import 'package:after_sales/screens/shared/home_ui.dart';

class HomeCustomer extends StatelessWidget {
  const HomeCustomer({super.key});

  @override
  Widget build(BuildContext context) {
    return const RootShell();
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _navIndex = 0;

  // 📌 GlobalKey สำหรับควบคุม Navigator แยกกันในแต่ละแท็บ
  final List<GlobalKey<NavigatorState>> _navigatorKeys = [
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
    GlobalKey<NavigatorState>(),
  ];

  bool _loading = true;
  Repair? _ongoingTicket;
  List<Repair> _historyTickets = [];
  int _total = 0;
  int _completed = 0;
  int _unreadNotifications = 0;
  int _unreadChatRooms = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadUnreadCount();
  }

  /// 🔔 นับจำนวนแจ้งเตือนที่ยังไม่อ่าน — โชว์เป็นวงกลมแดงบนแท็บกระดิ่ง
  /// และนับจำนวนห้องแชทที่มีข้อความยังไม่อ่าน — โชว์บนแท็บแชท
  Future<void> _loadUnreadCount() async {
    try {
      final username = db.Session.currentUsername.isNotEmpty
          ? db.Session.currentUsername
          : 'somchai_j';
      final count =
          await db.DatabaseHelper.instance.getUnreadNotificationCount(
        username,
      );
      final chatRooms = await db.DatabaseHelper.instance
          .getUnreadChatRoomCount(username, 'CUSTOMER');
      if (!mounted) return;
      setState(() {
        _unreadNotifications = count;
        _unreadChatRooms = chatRooms;
      });
    } catch (e) {
      debugPrint('Error loading unread notification count: $e');
    }
  }

  /// 🔄 ดึงข้อมูลตั๋วแจ้งซ่อมทั้งหมดของลูกค้าคนปัจจุบันจาก SQLite DB
  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      // ตรวจสอบ Session Username หากไม่มีให้ใช้ Default 'somchai_j'
      final username = db.Session.currentUsername.isNotEmpty
          ? db.Session.currentUsername
          : 'somchai_j';

      final rows = await db.DatabaseHelper.instance.getRepairsByCustomer(
        username,
      );
      final repairs = rows.map((row) => Repair.fromJson(row)).toList();

      Repair? ongoing;
      final unfinished = repairs
          .where((r) => r.status != 'เสร็จแล้ว' && r.status != 'เสร็จสิ้น')
          .toList();

      if (unfinished.isNotEmpty) {
        ongoing = unfinished.first;
      }

      final history = repairs.where((r) => r != ongoing).toList();
      final completed = repairs
          .where((r) => r.status == 'เสร็จแล้ว' || r.status == 'เสร็จสิ้น')
          .length;

      if (!mounted) return;
      setState(() {
        _ongoingTicket = ongoing;
        _historyTickets = history;
        _total = repairs.length;
        _completed = completed;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading customer repairs: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// ➕ เปิดหน้าสร้างตั๋วแจ้งซ่อมใหม่ และโหลดข้อมูลใหม่เมื่อกดย้อนกลับมา
  void _openNewTicketForm(BuildContext tabContext) async {
    await Navigator.of(
      tabContext,
    ).push(MaterialPageRoute(builder: (context) => const RepairFormScreen()));
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        // เช็กว่า Navigator ของแท็บปัจจุบันสามารถ Pop หน้าได้หรือไม่
        final currentNavigator = _navigatorKeys[_navIndex].currentState;
        if (currentNavigator != null && currentNavigator.canPop()) {
          currentNavigator.pop();
        } else if (_navIndex != 0) {
          // หากอยู่ที่หน้าแรกของแท็บอื่น ให้สลับกลับมาที่แท็บ Home (0)
          setState(() => _navIndex = 0);
        } else {
          // หากอยู่ที่หน้าแรกของแท็บ Home ให้ปิดแอป
          SystemNavigator.pop();
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: Colors.transparent,
        ),
        child: Scaffold(
          body: IndexedStack(
            index: _navIndex,
            children: [
              // 📌 แท็บ 0: Home Page
              Navigator(
                key: _navigatorKeys[0],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (tabContext) => HomePage(
                    isLoading: _loading,
                    ongoingTicket: _ongoingTicket,
                    historyTickets: _historyTickets,
                    total: _total,
                    completed: _completed,
                    onNewTicket: () => _openNewTicketForm(tabContext),
                    onRefreshData: _loadData,
                    onSeeAllHistory: () {
                      setState(() => _navIndex = 1);
                    },
                  ),
                ),
              ),

              // 📌 แท็บ 1: History Page
              Navigator(
                key: _navigatorKeys[1],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (tabContext) => const HistoryCustomer(),
                ),
              ),

              // 📌 แท็บ 2: รายการแชท (เลือกงานที่จะคุยได้ทุกใบ ไม่ใช่แค่งานที่กำลังซ่อม)
              Navigator(
                key: _navigatorKeys[2],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (tabContext) =>
                      ChatListPage(
                        role: UserRole.customer,
                        // 🔴 [แก้ไข] เดิมตัวเลขบนแท็บแชท/กระดิ่งค้างหลังอ่านแล้วออกจาก
                        // ห้องแชท จนกว่าจะสลับแท็บเอง — ให้รีเฟรชทันทีที่กลับมาจากห้องแชท
                        onUnreadCountsChanged: _loadUnreadCount,
                      ),
                ),
              ),

              // 📌 แท็บ 3: Notification Page
              Navigator(
                key: _navigatorKeys[3],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (tabContext) => CustomerNotificationPage(
                    onUnreadCountsChanged: _loadUnreadCount,
                  ),
                ),
              ),

              // 📌 แท็บ 4: Profile Page
              Navigator(
                key: _navigatorKeys[4],
                onGenerateRoute: (settings) => MaterialPageRoute(
                  builder: (tabContext) => const UserProfilePage(),
                ),
              ),
            ],
          ),
          bottomNavigationBar: CommonBottomNavBar(
            currentIndex: _navIndex,
            role: UserRole.customer,
            notificationCount: _unreadNotifications,
            chatCount: _unreadChatRooms,
            onTap: (index) {
              setState(() => _navIndex = index);
              // 🔄 อัปเดตตัวเลขแจ้งเตือนใหม่ทุกครั้งที่สลับแท็บ
              // (เผื่อเพิ่งอ่านแจ้งเตือนในแท็บที่ออกมา)
              _loadUnreadCount();
            },
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 🏠 หน้าหลักฝั่งลูกค้า — ใช้ Home UI Kit ชุดเดียวกับช่างและแอดมิน
// -----------------------------------------------------------------------------
class HomePage extends StatelessWidget {
  final bool isLoading;
  final Repair? ongoingTicket;
  final List<Repair> historyTickets;
  final int total;
  final int completed;
  final VoidCallback onNewTicket;
  final Future<void> Function() onRefreshData;
  final VoidCallback onSeeAllHistory;

  const HomePage({
    super.key,
    this.isLoading = false,
    required this.ongoingTicket,
    required this.historyTickets,
    required this.total,
    required this.completed,
    required this.onNewTicket,
    required this.onRefreshData,
    required this.onSeeAllHistory,
  });

  String _ticketOf(Repair r) =>
      r.ticketNo ?? (r.id != null ? '# AS-${r.id}' : '-');

  Future<void> _openDetail(BuildContext context, Repair repair) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerJobDetailPage(repairId: repair.id),
      ),
    );
    onRefreshData();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = total - completed;
    final preview = historyTickets.take(5).toList();

    return HomeScaffold(
      isLoading: isLoading,
      onRefresh: onRefreshData,
      children: [
        const HomeGreeting('ยินดีต้อนรับกลับ, ลูกค้า'),
        const SizedBox(height: 16),

        // 🔘 ปุ่มแจ้งซ่อม
        HomePrimaryButton(
          label: 'แจ้งซ่อม',
          icon: Icons.add,
          onTap: onNewTicket,
        ),
        const SizedBox(height: 16),

        // 📊 การ์ดสรุปภาพรวม
        TodaySummaryCard(
          total: total,
          completed: completed,
          remaining: remaining < 0 ? 0 : remaining,
        ),
        const SizedBox(height: 20),

        // 🚚 งานที่กำลังดำเนินการ
        const HomeSectionHeader('งานที่กำลังดำเนินการ'),
        const SizedBox(height: 12),
        if (ongoingTicket == null)
          const HomeEmptyState(
            icon: Icons.check_circle_outline,
            message: 'ไม่มีงานที่กำลังดำเนินการอยู่ในขณะนี้',
          )
        else
          HomeHighlightCard(
            title: 'งานที่กำลังดำเนินการ',
            statusLabel: ongoingTicket!.status ?? 'รอจัดสรรช่าง',
            statusBg: HomeStatusStyle.bgOf(ongoingTicket!.status),
            statusFg: HomeStatusStyle.fgOf(ongoingTicket!.status),
            rows: [
              HomeInfoRow('เลขแจ้งซ่อม', _ticketOf(ongoingTicket!)),
              HomeInfoRow('เครื่อง', ongoingTicket!.machine ?? '-'),
              HomeInfoRow('วันนัดซ่อม', ongoingTicket!.date ?? '-'),
              HomeInfoRow('ที่อยู่', ongoingTicket!.location ?? '-'),
            ],
            actionLabel: 'ดูรายละเอียดงาน',
            onAction: () => _openDetail(context, ongoingTicket!),
          ),
        const SizedBox(height: 20),

        // 📜 ประวัติการแจ้งซ่อม
        HomeSectionHeader('ประวัติการแจ้งซ่อม', onAction: onSeeAllHistory),
        const SizedBox(height: 12),
        if (preview.isEmpty)
          const HomeEmptyState(message: 'ยังไม่มีประวัติการแจ้งซ่อม')
        else
          for (var i = 0; i < preview.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: HomeJobTile(
                ticket: _ticketOf(preview[i]),
                subtitle:
                    '${preview[i].machine ?? '-'} • ${preview[i].date ?? '-'}',
                statusLabel: preview[i].status ?? '-',
                statusBg: HomeStatusStyle.bgOf(preview[i].status),
                statusFg: HomeStatusStyle.fgOf(preview[i].status),
                onTap: () => _openDetail(context, preview[i]),
              ),
            ),
      ],
    );
  }
}