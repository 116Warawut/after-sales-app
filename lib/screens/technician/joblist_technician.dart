import 'dart:async';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/technician/job_detail.dart';
import 'package:after_sales/screens/customer/history_customer.dart'
    as customer_history;
import 'package:after_sales/services.dart' as db;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class JoblistTechnician extends StatelessWidget {
  final VoidCallback? onBack;
  const JoblistTechnician({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return RepairListPage(onBack: onBack);
  }
}

// ---------------------------------------------------------------------------
// หมายเหตุ: Ticket / TicketStatus / FilterTab ใช้ตัวเดียวกับฝั่งลูกค้า
// (customer_history.dart) ไม่ประกาศซ้ำ เพราะถ้าประกาศ enum/class ชื่อเดียวกันซ้ำ
// ในไฟล์นี้ จะกลายเป็นคนละ type กัน แล้ว Dart จะ error ตอน build
// 🐛 [แก้บัค] เดิมหน้านี้ยังเรียก HistoryHeaderContent (widgets.dart) ตรง ๆ อยู่ดี
// ทั้งที่ type ของมันผูกกับ FilterTab ของ widgets.dart เอง (คนละตัวกับ
// customer_history.FilterTab ที่ _selectedTab ด้านล่างใช้) ทำให้คอมไพล์ไม่ผ่าน
// จริง ๆ — แก้โดยใช้ _TechnicianFilterHeader ของหน้านี้เองแทน (ดูด้านล่างสุดของ
// ไฟล์) ไม่พึ่ง HistoryHeaderContent อีกต่อไป จึงเอา import widgets.dart ออกด้วย
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class RepairListPage extends StatefulWidget {
  final VoidCallback? onBack;
  const RepairListPage({super.key, this.onBack});

  @override
  State<RepairListPage> createState() => _RepairListPageState();
}

class _RepairListPageState extends State<RepairListPage> {
  customer_history.FilterTab _selectedTab = customer_history.FilterTab.all;

  bool _loading = true;
  List<customer_history.Ticket> _tickets = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showAll = false;
  static const int _previewCount = 10;

  // 🐛 [แก้บัค] หน้านี้เดิมโหลดงานของช่างด้วย .get() ครั้งเดียวตอนเปิดหน้า ทำให้
  // ป้ายสถานะบนการ์ดค้างเป็นค่าเก่าถ้าสถานะจริงใน Firebase เปลี่ยนไปแล้วระหว่างที่
  // ช่างค้างอยู่ในหน้ารายการ (เช่นถึง/เลยวันนัดพอดี) ทั้งที่หน้ารายละเอียดงาน
  // (job_detail.dart) ดึงข้อมูลสดทุกครั้งที่เปิด เลยเห็นสถานะไม่ตรงกันระหว่างสอง
  // หน้า — เพิ่ม subscription ฟัง watchRepairsByTechnician() แบบ real-time ควบคู่
  // ไปกับ _loadTickets() เดิม (ยังคงไว้เผื่อ subscription ล้มเหลว)
  StreamSubscription<List<Map<String, dynamic>>>? _ticketsSubscription;

  @override
  void initState() {
    super.initState();
    _loadTickets();
    _ticketsSubscription = db.DatabaseHelper.instance
        .watchRepairsByTechnician(db.Session.currentUsername)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _tickets =
            rows.map((row) => customer_history.Ticket.fromMap(row)).toList();
        _loading = false;
      });
    }, onError: (_) {
      // เงียบไว้ — ถ้า stream ล้มเหลว หน้ายังใช้ข้อมูลจาก _loadTickets() ตอนเปิด
      // หน้า/กลับจากหน้ารายละเอียดได้ตามปกติ
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _ticketsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadTickets() async {
    if (!mounted) return;
    setState(() => _loading = true);

    // 📌 หน้านี้คือ "งานทั้งหมด" ของช่าง ต้องดึงงานที่ถูกมอบหมายให้ช่างคนนี้
    // (ไม่ใช่ getRepairsByCustomer ซึ่งเป็นของฝั่งลูกค้า)
    final rows = await db.DatabaseHelper.instance.getRepairsByTechnician(
      db.Session.currentUsername,
    );

    if (!mounted) return;
    setState(() {
      _tickets =
          rows.map((row) => customer_history.Ticket.fromMap(row)).toList();
      _loading = false;
    });
  }

  List<customer_history.Ticket> get _filteredTickets {
    final query = _searchQuery.trim().toLowerCase();
    return _tickets.where((t) {
      final matchesTab = _selectedTab.matches(t.status);
      final matchesSearch = query.isEmpty ||
          t.ticketNo.toLowerCase().contains(query) ||
          t.device.toLowerCase().contains(query);
      return matchesTab && matchesSearch;
    }).toList();
  }

  // 🔄 ปรับเปิดหน้า Detail ให้ await แล้วค่อยโหลดข้อมูลใหม่เผื่อมีการเปลี่ยนแปลง
  Future<void> _openTicketDetail(customer_history.Ticket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => JobDetailPage(repairId: ticket.id!),
      ),
    );
    _loadTickets();
  }

  String get _emptyStateMessage => 'ไม่มีรายการในสถานะนี้';

  @override
  Widget build(BuildContext context) {
    final allFiltered = _filteredTickets;
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final tickets = (hasSearch || _showAll)
        ? allFiltered
        : allFiltered.take(_previewCount).toList();
    final showExpandButton =
        !hasSearch && !_showAll && allFiltered.length > _previewCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🐛 [แก้บัค] เดิมหน้านี้เรียก HistoryHeaderContent (widgets.dart) ตรง ๆ
            // ซึ่งรับ selectedTab/onTabChanged เป็น enum FilterTab ของ widgets.dart
            // เอง — คนละ type กับ customer_history.FilterTab ที่ _selectedTab ใช้อยู่
            // (ชื่อซ้ำกันแต่ประกาศคนละไฟล์) ทำให้คอมไพล์ไม่ผ่าน (คอมเมนต์ด้านบนบอกว่า
            // เคยเจอปัญหานี้มาก่อนแต่แก้ไม่ครบ) เปลี่ยนมาใช้ _TechnicianFilterHeader
            // ของหน้านี้เองแทน (แพทเทิร์นเดียวกับ _AdminFilterHeader /
            // _CustomerFilterHeader ในอีก 2 หน้า)
            _TechnicianFilterHeader(
              totalTickets: _tickets.length,
              selectedTab: _selectedTab,
              onBack: widget.onBack,
              onTabChanged: (tab) {
                setState(() {
                  _selectedTab = tab;
                  _showAll = false;
                });
              },
            ),

            // ช่องค้นหา (รหัสงานซ่อม หรือ รุ่นเครื่อง)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหารหัสงานซ่อม หรือรุ่นเครื่อง...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),

            // รายการซ่อม
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTickets,
                      color: AppColors.primary,
                      child: tickets.isEmpty
                          ? ListView(
                              children: [
                                const SizedBox(height: 120),
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 32),
                                    child: Text(
                                      _emptyStateMessage,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: AppColors.textSubtitle,
                                        fontFamily: AppStyles.fontFamily,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                24,
                                16,
                                24,
                              ),
                              itemCount:
                                  tickets.length + (showExpandButton ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == tickets.length) {
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: TextButton(
                                      onPressed: () =>
                                          setState(() => _showAll = true),
                                      child: Text(
                                        'ดูทั้งหมด (${allFiltered.length} รายการ)',
                                        style: const TextStyle(
                                            color: AppColors.primary),
                                      ),
                                    ),
                                  );
                                }
                                final ticket = tickets[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(16),
                                      onTap: () => _openTicketDetail(ticket),
                                      child: _TicketCard(
                                        ticket: ticket,
                                        onDetailTap: () =>
                                            _openTicketDetail(ticket),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket card widget
// ---------------------------------------------------------------------------

class _TicketCard extends StatelessWidget {
  final customer_history.Ticket ticket;
  final VoidCallback onDetailTap;

  const _TicketCard({required this.ticket, required this.onDetailTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        shadows: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x198B0000),
            blurRadius: 24,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'TICKET',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 1.2,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(ticket.ticketNo, style: AppStyles.historyCardTitle),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: ShapeDecoration(
                  color: ticket.status.color.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: ticket.status.color, width: 1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: ticket.status.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      ticket.status.label,
                      style: TextStyle(
                        color: ticket.status.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _InfoRow(label: 'เครื่อง', value: ticket.device),
          const SizedBox(height: 4),
          _InfoRow(label: 'ตำแหน่ง', value: ticket.location),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ticket.subStatusLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    Text(ticket.date, style: AppStyles.historyCardSubtitle),
                  ],
                ),
              ),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'รายละเอียด',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 56,
          child: Text(label, style: AppStyles.historyCardSubtitle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: AppStyles.historyCardSubtitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// 🐛 [แก้บัค] แถบหัวข้อ + แท็บตัวกรองเลื่อนแนวนอนของหน้ารายการงานซ่อมช่าง —
// หน้าตาก็อปมาจาก HistoryHeaderContent (widgets.dart) แต่ผูกกับ
// customer_history.FilterTab (ตัวเดียวกับที่ _selectedTab ในหน้านี้ใช้อยู่แล้ว)
// แทนที่จะเรียก HistoryHeaderContent ตรง ๆ ซึ่งต้องการ FilterTab ของ widgets.dart
// เอง (คนละ type กัน แม้ชื่อจะซ้ำ) — ใช้แพทเทิร์นเดียวกับ _AdminFilterHeader ใน
// repair_list_admin.dart และ _CustomerFilterHeader ใน history_customer.dart
class _TechnicianFilterHeader extends StatelessWidget {
  final int totalTickets;
  final customer_history.FilterTab selectedTab;
  final ValueChanged<customer_history.FilterTab> onTabChanged;
  final VoidCallback? onBack;

  const _TechnicianFilterHeader({
    required this.totalTickets,
    required this.selectedTab,
    required this.onTabChanged,
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
              // 🐛 [แก้บัค] เดิม Row นี้ใช้ crossAxisAlignment.start แล้วดัน
              // Column [หัวข้อ, จำนวนรายการ] ลงด้วย Padding top:12 เพื่อให้ตรงกับ
              // ปุ่มลูกศรแบบเก่า (IconButton เริ่มต้นที่มี padding ~8 รอบไอคอน)
              // แต่พอเปลี่ยนปุ่มมาเป็นวงกลม 40x40 ไม่มี padding แล้ว ค่า offset เดิม
              // ไม่ตรงกันอีกต่อไป ทำให้ลูกศรลอยอยู่เหนือข้อความหัวข้อ — เปลี่ยนมาให้
              // ปุ่มลูกศรกับข้อความหัวข้อ "รายการซ่อมทั้งหมด" อยู่ใน Row เดียวกันแบบ
              // center-align ตรง ๆ (อยู่บรรทัดเดียวกันเป๊ะไม่ว่าปุ่มจะสูงเท่าไหร่)
              // แล้วย้ายบรรทัดจำนวนรายการลงมาอยู่บรรทัดถัดไป เยื้องซ้ายให้ตรงกับ
              // ข้อความหัวข้อ (56 = ความกว้างปุ่ม 40 + ช่องว่าง 4 + padding ซ้ายเดิม
              // ของ Row 12)
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 🐛 [แก้บัค] เดิมปุ่มนี้เรียก Navigator.of(context).maybePop() ตรง ๆ
                // แต่หน้านี้ถูกเปิดเป็นแท็บล่างของแอป (IndexedStack + Navigator แยก
                // ต่อแท็บใน home_technician.dart) ซึ่งเป็น route แรกสุดของ Navigator
                // ของแท็บนั้นเสมอ ทำให้ maybePop() คืนค่า false เฉย ๆ กดแล้วไม่มีอะไร
                // เกิดขึ้นทุกครั้ง — เปลี่ยนให้รับ onBack callback จาก home_technician.dart
                // มาสลับกลับไปแท็บหน้าแรกแทน และเปลี่ยนหน้าตาปุ่มให้เหมือนปุ่มย้อนกลับ
                // ใน AppHeader (widgets.dart) ที่ใช้ในหน้าโปรไฟล์ — ใช้แพทเทิร์นเดียว
                // กับ _CustomerFilterHeader / _AdminFilterHeader ในอีก 2 หน้า
                Material(
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
                        Navigator.of(context).maybePop();
                      }
                    },
                    icon: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'รายการซ่อมทั้งหมด',
                    style: AppStyles.historySectionTitle,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Text(
              '$totalTickets รายการทั้งหมด',
              style: AppStyles.historyMeta,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: customer_history.FilterTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = customer_history.FilterTab.values[index];
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