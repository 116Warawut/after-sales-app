import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart';
//import 'package:after_sales/widgets.dart';

import 'package:after_sales/screens/admin/assign_repair_formdetail.dart';
import 'package:after_sales/screens/shared/job_detail_ui.dart';
import 'package:after_sales/utils/firebase_number.dart';

// --- MAIN PAGE & STATE ---

class RepairListAdminPage extends StatefulWidget {
  final VoidCallback? onBack;
  const RepairListAdminPage({super.key, this.onBack});

  @override
  State<RepairListAdminPage> createState() => _RepairListAdminPageState();
}

class _RepairListAdminPageState extends State<RepairListAdminPage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<RepairListItem> _allItems = [];
  bool _isLoading = true;
  String _searchQuery = '';
  AdminFilterTab _selectedTab = AdminFilterTab.all;
  bool _showAll = false;
  static const int _previewCount = 10;

  // 🐛 [แก้บัค] เดิมหน้านี้โหลดข้อมูลแบบ .get() ครั้งเดียวตอนเปิดหน้า (ผ่าน
  // _loadRepairsFromDB) ทำให้ป้ายสถานะบนการ์ดค้างเป็นค่าเก่าถ้าข้อมูลจริงใน
  // Firebase เปลี่ยนไปแล้วระหว่างที่แอดมินค้างอยู่ในหน้านี้ (เช่นช่างเพิ่งกด
  // "แจ้งปัญหา" หรือวันนัดเลยกำหนดพอดี) ทั้งที่หน้ารายละเอียดงานดึงข้อมูลสดทุก
  // ครั้งที่เปิด เลยเห็นสถานะไม่ตรงกัน — เพิ่ม subscription ฟัง watchAllRepairs()
  // แบบ real-time ควบคู่ไปด้วย เพื่อให้การ์ดอัปเดตสถานะทันทีโดยไม่ต้อง
  // pull-to-refresh เอง (ยังคง _loadRepairsFromDB ไว้ให้ RefreshIndicator เรียก
  // ได้ตามเดิม)
  StreamSubscription<List<Map<String, dynamic>>>? _repairsSubscription;

  // หมายเหตุ: เดิมมี _filterUnassigned/_filterUrgent เป็น checkbox ตัวกรองเสริม
  // แยกจากแท็บเลื่อนด้านบน แต่ตอนนี้ทั้ง "เร่งด่วน" และ "รอจัดสรรช่าง" ใช้แท็บ
  // เลื่อนด้านบนอย่างเดียวแล้ว (ไม่มี checkbox ซ้ำซ้อนด้านล่างอีกต่อไป)

  @override
  void initState() {
    super.initState();
    _loadRepairsFromDB();
    _repairsSubscription =
        DatabaseHelper.instance.watchAllRepairs().listen((data) {
      if (!mounted) return;
      setState(() {
        _allItems = data.map((item) => RepairListItem.fromMap(item)).toList();
        _isLoading = false;
      });
    }, onError: (_) {
      // เงียบไว้ — ถ้า stream ล้มเหลว หน้ายังใช้ข้อมูลจาก _loadRepairsFromDB /
      // pull-to-refresh ได้ตามปกติ ไม่ต้องขึ้น error ซ้ำซ้อนกับตัว snackbar เดิม
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    _repairsSubscription?.cancel();
    super.dispose();
  }

  // หน่วงเวลาค้นหา 300ms เพื่อเพิ่มประสิทธิภาพ
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = query);
    });
  }

  // ดึงรายการงานซ่อมจาก DB
  Future<void> _loadRepairsFromDB() async {
    setState(() => _isLoading = true);
    try {
      final data = await DatabaseHelper.instance.getAllRepairs();
      if (!mounted) return;

      setState(() {
        _allItems = data.map((item) => RepairListItem.fromMap(item)).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);

      // แสดงข้อความสั้นป้องกัน Error Context
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('เกิดข้อผิดพลาด: $e',
              style: const TextStyle(fontFamily: AppStyles.fontFamily)),
          backgroundColor: AppColors.requiredMark,
        ),
      );
    }
  }

  // 🔴 [แก้บั๊ก] เจอบั๊กเดียวกับฝั่งเว็บ (RepairJobsPage.jsx) และหน้าแชท
  // (chat_list_page.dart / ChatPage.jsx): หน้านี้เดิมโชว์งานซ่อม "ทั้งหมดใน
  // ระบบ" ให้แอดมินทุกคนเห็นเหมือนกันหมด ทั้งที่งานที่ถูกมอบหมายให้แอดมินคนใด
  // คนหนึ่งดูแลแล้ว (มี adminUsername แล้ว) ควรเห็นได้แค่แอดมินเจ้าของงานคนเดียว
  // — แอดมินหลัก (Session.isMainAdmin) ยังคงเห็นทุกงานเหมือนเดิม เพราะต้องใช้
  // ดูภาพรวม/มอบหมายงานใหม่ให้แอดมินคนอื่นได้ (ฟังก์ชัน _reassignAdmin ด้านบน
  // ก็จำกัดไว้เฉพาะแอดมินหลักอยู่แล้วเช่นกัน) ส่วนงานที่ยังไม่มีแอดมินรับผิดชอบ
  // เลย (adminUsername ว่าง — เช่นงานที่เพิ่งแจ้งเข้ามาใหม่ ยัง "รอจัดสรรช่าง")
  // ให้ทุกแอดมินยังเห็นได้เหมือนเดิม จะได้มีคนหยิบไปมอบหมายช่างต่อได้
  List<RepairListItem> get _visibleItems {
    if (Session.isMainAdmin) return _allItems;
    final me = Session.currentUsername;
    return _allItems
        .where((item) =>
            (item.adminUsername ?? '').trim().isEmpty ||
            item.adminUsername == me)
        .toList();
  }

  // จับคู่แท็บตัวกรองกับรายการงานซ่อมของแอดมิน
  // 🆕 [ใหม่] ใช้ AdminFilterTab ของหน้านี้เอง (แยกจาก customer_history.FilterTab
  // ที่ลูกค้า/ช่างใช้ร่วมกัน) เพิ่ม 2 แท็บใหม่: "มีปัญหา/ต้องตรวจสอบ" กับ
  // "เกินกำหนดเวลา" ซึ่งไม่มีความหมายสำหรับลูกค้า/ช่างจึงไม่ใส่ในแท็บที่ใช้ร่วมกัน
  bool _tabMatches(AdminFilterTab tab, RepairListItem item) {
    switch (tab) {
      case AdminFilterTab.all:
        return true;
      case AdminFilterTab.done:
        return item.status == RepairStatus.done;
      case AdminFilterTab.inProgress:
        return item.status == RepairStatus.inProgress;
      case AdminFilterTab.pending:
        return item.status == RepairStatus.waiting;
      // 🐛 [แก้บัค] เดิมไม่มีแท็บนี้ทำให้งาน "รอดำเนินการ" (มีช่างแล้วแต่ยังไม่ถึง
      // วันนัด) ไปปนอยู่ในแท็บ "รอจัดสรรช่าง" — เพิ่มให้ตรงกับเว็บแอดมิน
      case AdminFilterTab.scheduledPending:
        return item.status == RepairStatus.scheduledPending;
      case AdminFilterTab.traveling:
        return item.status == RepairStatus.traveling;
      case AdminFilterTab.cancelled:
        return item.status == RepairStatus.cancelled;
      case AdminFilterTab.urgent:
        return item.isUrgent;
      case AdminFilterTab.issue:
        return item.status == RepairStatus.issue;
      case AdminFilterTab.overdue:
        return item.isOverdue;
    }
  }

  // กรองข้อมูลตามแท็บและคำค้นหา
  List<RepairListItem> get _filteredItems {
    final query = _searchQuery.trim().toLowerCase();
    return _visibleItems.where((item) {
      final matchesTab = _tabMatches(_selectedTab, item);
      final matchesSearch = query.isEmpty ||
          item.ticketId.toLowerCase().contains(query) ||
          item.customerName.toLowerCase().contains(query) ||
          item.modelName.toLowerCase().contains(query) ||
          (item.technicianUsername?.toLowerCase().contains(query) ?? false);
      return matchesTab && matchesSearch;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _searchQuery.trim().isNotEmpty || _selectedTab != AdminFilterTab.all;

  void _clearAllFilters() {
    _debounce?.cancel();
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedTab = AdminFilterTab.all;
    });
  }

  // ไปหน้ามอบหมายงาน & รีโหลดข้อมูลเมื่อย้อนกลับ
  Future<void> _openDetail(RepairListItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssignRepairFormDetailPage(repairId: item.id),
      ),
    );
    if (mounted) _loadRepairsFromDB();
  }

  // 🗑️ ลบใบแจ้งซ่อม (ถามยืนยันก่อนเสมอ)
  Future<void> _confirmDelete(RepairListItem item) async {
    final confirmed = await showJobConfirmDialog(
      context,
      title: 'ยืนยันการลบ',
      message:
          'ต้องการลบใบแจ้งซ่อม ${item.ticketId} ของ ${item.customerName} ใช่หรือไม่?\nข้อมูลที่ลบแล้วไม่สามารถกู้คืนได้',
      confirmLabel: 'ลบรายการ',
      cancelLabel: 'ไม่ใช่ตอนนี้',
      icon: Icons.delete_outline,
      danger: true,
    );

    if (!confirmed || !mounted) return;

    try {
      if (item.id > 0) {
        await DatabaseHelper.instance.deleteRepair(item.id);
      } else if (item.fbKey != null && item.fbKey!.trim().isNotEmpty) {
        // 🛠️ [แก้ไข] รายการที่ข้อมูลเสีย/ไม่สมบูรณ์ (ไม่มีฟิลด์ id จริงในฐานข้อมูล
        // — เช่นการ์ดที่ขึ้น "# AS-0000" / "ไม่ระบุชื่อ") ลบผ่าน id ปกติไม่ได้
        // เพราะไม่รู้ id ที่แท้จริง จึงลบโดยอ้างอิงคีย์จริงใน Firebase แทน
        await DatabaseHelper.instance.deleteRepairByKey(item.fbKey!);
      } else {
        throw Exception('ไม่พบข้อมูลอ้างอิงของรายการนี้ในฐานข้อมูล ไม่สามารถลบได้');
      }
      if (!mounted) return;
      _snack('ลบใบแจ้งซ่อม ${item.ticketId} แล้ว');
      await _loadRepairsFromDB();
    } catch (e) {
      if (!mounted) return;
      _snack('ลบไม่สำเร็จ: $e', isError: true);
    }
  }

  // 🔴 [ใหม่] "จัดสรรงานไปให้แอดมินคนอื่น" — เฉพาะแอดมินหลัก (เช็คซ้ำในนี้ด้วย
  // แม้ว่าปุ่มจะถูกซ่อนสำหรับแอดมินทั่วไปไปแล้วจาก UI ก็ตาม กันไว้อีกชั้น)
  Future<void> _reassignAdmin(RepairListItem item) async {
    if (!Session.isMainAdmin) return;

    List<Map<String, dynamic>> admins;
    try {
      admins = await DatabaseHelper.instance.getAllAdmins();
    } catch (e) {
      if (!mounted) return;
      _snack('โหลดรายชื่อแอดมินไม่สำเร็จ', isError: true);
      return;
    }
    if (!mounted) return;

    final selectedUsername = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'มอบหมายให้แอดมิน — ${item.ticketId}',
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: admins.length,
                itemBuilder: (context, index) {
                  final admin = admins[index];
                  final username = (admin['username']?.toString()) ?? '';
                  final name = (admin['admin_name']?.toString()) ?? username;
                  final isCurrent = username == item.adminUsername;
                  return ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined,
                        color: AppColors.primary),
                    title: Text(name,
                        style:
                            const TextStyle(fontFamily: AppStyles.fontFamily)),
                    subtitle: Text(username,
                        style:
                            const TextStyle(fontFamily: AppStyles.fontFamily)),
                    trailing: isCurrent
                        ? const Icon(Icons.check_circle,
                            color: AppColors.primary)
                        : null,
                    onTap: () => Navigator.pop(context, username),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (selectedUsername == null ||
        selectedUsername.isEmpty ||
        selectedUsername == item.adminUsername ||
        !mounted) {
      return;
    }

    try {
      await DatabaseHelper.instance
          .reassignRepairAdmin(item.id, selectedUsername);
      if (!mounted) return;
      _snack('มอบหมาย ${item.ticketId} ให้ $selectedUsername แล้ว');
      await _loadRepairsFromDB();
    } catch (e) {
      if (!mounted) return;
      _snack('มอบหมายงานไม่สำเร็จ: $e', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontFamily: AppStyles.fontFamily)),
        backgroundColor: isError ? AppColors.requiredMark : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final displayedItems =
        (hasSearch || _showAll) ? items : items.take(_previewCount).toList();
    final showExpandButton =
        !hasSearch && !_showAll && items.length > _previewCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _AdminFilterHeader(
              totalTickets: _visibleItems.length,
              selectedTab: _selectedTab,
              onBack: widget.onBack,
              onTabChanged: (tab) {
                setState(() {
                  _selectedTab = tab;
                  _showAll = false;
                });
              },
            ),

            // ช่องค้นหา (Search Bar) - ปรับปรุงให้ปุ่มล้างคำตอบสนองทันที
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 4,
                        offset: Offset(0, 2)),
                  ],
                ),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, child) {
                    return TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(
                          fontFamily: AppStyles.fontFamily, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'ค้นหา Ticket ID, ลูกค้า, หรือรุ่นเครื่อง...',
                        hintStyle: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textHint,
                            fontFamily: AppStyles.fontFamily),
                        prefixIcon: const Icon(Icons.search,
                            color: AppColors.primary, size: 20),
                        suffixIcon: value.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _debounce?.cancel();
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 🛠️ [แก้ไข] เอาปุ่ม/checkbox กรอง "รอจัดสรรช่าง" ออกตามที่ขอ — ตอนนี้
            // ป้าย RepairStatus.waiting ก็ใช้ข้อความ "รอจัดสรรช่าง" อยู่แล้วบนแท็บ
            // เลื่อนด้านบน (ดูตัวกรองสถานะเดียวกันได้จากแท็บด้านบนแทน) เอาไว้ทั้ง
            // สองที่ซ้ำซ้อนและทำให้ดูรกเกินไป

            // รายการงานซ่อม
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _loadRepairsFromDB,
                      child: items.isEmpty
                          ? _EmptyState(
                              hasSearch: _hasActiveFilters,
                              onClearSearch: _clearAllFilters,
                            )
                          : ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior
                                      .onDrag, // ซ่อนคีย์บอร์ดเมื่อเลื่อนจอ
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
                              itemCount: displayedItems.length +
                                  (showExpandButton ? 1 : 0),
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 14),
                              itemBuilder: (context, index) {
                                if (index == displayedItems.length) {
                                  return Center(
                                    child: TextButton(
                                      onPressed: () =>
                                          setState(() => _showAll = true),
                                      child: Text(
                                        'ดูทั้งหมด (${items.length} รายการ)',
                                        style: const TextStyle(
                                            color: AppColors.primary),
                                      ),
                                    ),
                                  );
                                }
                                return _RepairCard(
                                  item: displayedItems[index],
                                  onDetailTap: () =>
                                      _openDetail(displayedItems[index]),
                                  onDeleteTap: () =>
                                      _confirmDelete(displayedItems[index]),
                                  onReassignAdmin: Session.isMainAdmin
                                      ? () =>
                                          _reassignAdmin(displayedItems[index])
                                      : null,
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

// --- DATA MODELS & ENUMS ---

// 🆕 [ใหม่] แท็บตัวกรองของหน้า "รายการซ่อมทั้งหมด" ฝั่งแอดมินโดยเฉพาะ — แยกออกจาก
// customer_history.FilterTab ที่ลูกค้า/ช่างใช้ร่วมกัน เพื่อไม่ให้กระทบหน้าจอบทบาท
// อื่น เพิ่ม 2 แท็บที่มีความหมายเฉพาะฝั่งแอดมิน: "มีปัญหา/ต้องตรวจสอบ" (ช่างแจ้ง
// ปัญหาไว้ผ่าน markRepairProblem) และ "เกินกำหนดเวลา" (วันนัดผ่านไปแล้วแต่ยังไม่เสร็จ)
enum AdminFilterTab {
  all,
  done,
  pending,
  // 🐛 [แก้บัค] เพิ่มแท็บ "รอดำเนินการ" ให้ตรงกับหน้าเว็บแอดมิน (JOB_STATUS_TABS)
  // — เดิมสถานะนี้ถูกคำนวณจาก getEffectiveRepairStatus() อยู่แล้วในฝั่ง service
  // แต่หน้านี้ไม่มีเคสรองรับเลยจึงตกไปปนกับ "รอจัดสรรช่าง" ทั้งที่เป็นคนละสถานะ
  scheduledPending,
  // 🆕 [ใหม่] แท็บ "กำลังเดินทาง" แยกออกจาก "กำลังซ่อม" — ให้ตรงกับ
  // RepairStatus.traveling ที่มีอยู่แล้วในไฟล์นี้ และ JOB_STATUS_TABS ฝั่งเว็บ
  traveling,
  inProgress,
  urgent,
  issue,
  overdue,
  cancelled,
}

extension AdminFilterTabX on AdminFilterTab {
  String get label {
    switch (this) {
      case AdminFilterTab.all:
        return 'ทั้งหมด';
      case AdminFilterTab.done:
        return 'เสร็จสิ้น';
      case AdminFilterTab.pending:
        return 'รอจัดสรรช่าง';
      case AdminFilterTab.scheduledPending:
        return 'รอดำเนินการ';
      case AdminFilterTab.traveling:
        return 'กำลังเดินทาง';
      case AdminFilterTab.inProgress:
        return 'กำลังซ่อม';
      case AdminFilterTab.urgent:
        return 'เร่งด่วน';
      case AdminFilterTab.issue:
        return 'มีปัญหา / ต้องตรวจสอบ';
      case AdminFilterTab.overdue:
        return 'เกินกำหนดเวลา';
      case AdminFilterTab.cancelled:
        return 'ยกเลิก';
    }
  }
}

enum RepairStatus {
  waiting,
  // 🐛 [แก้บัค] เพิ่มสถานะ "รอดำเนินการ" (มีช่างแล้วแต่ยังไม่ถึงวันนัด) และ
  // "เกินกำหนดเวลา" (ถึงวันนัดแล้วแต่ยังไม่เสร็จ) ให้ตรงกับค่าที่
  // getEffectiveRepairStatus() ใน services.dart คำนวณจริง — เดิม fromString()
  // ด้านล่างไม่มีเคสรองรับทั้งคู่ (รวมถึง 'กำลังซ่อม' ของ inProgress) เลยตกไปที่
  // default กลายเป็น waiting ทำให้ป้ายสถานะ/แท็บของแอดมินบนมือถือผิดไปจากเว็บ
  scheduledPending,
  // 🆕 [ใหม่] สถานะ "กำลังเดินทาง" (ถึงคิวงานแล้ว ช่างกำลังมุ่งหน้าไปหาลูกค้า
  // ยังไม่ได้ลงมือซ่อมจริง) — ตั้งโดย markTechnicianTraveling() ใน
  // services.dart ตอนช่างผ่านเงื่อนไขวันนัด+คิวงานในหน้าติดตามตำแหน่งลูกค้า
  traveling,
  inProgress,
  overdue,
  done,
  cancelled,
  issue,
}

extension RepairStatusX on RepairStatus {
  // 🛠️ [แก้ไข] เปลี่ยน label จาก "รอดำเนินการ" เป็น "รอจัดสรรช่าง" ให้ตรงกับ
  // หน้ารายละเอียดงาน (assign_repair_formdetail.dart) ที่แก้ไปแล้วก่อนหน้านี้
  // — เดิมสองหน้านี้ใช้ enum คนละตัวกันแต่ค่า label ไม่ตรงกัน ทำให้ลูกค้า/แอดมิน
  // เห็นข้อความสถานะไม่เหมือนกันระหว่างหน้ารายการซ่อมกับหน้ารายละเอียดงาน
  String get label => switch (this) {
        RepairStatus.waiting => 'รอจัดสรรช่าง',
        RepairStatus.scheduledPending => 'รอดำเนินการ',
        RepairStatus.traveling => 'กำลังเดินทาง',
        RepairStatus.inProgress => 'กำลังซ่อม',
        RepairStatus.overdue => 'เกินกำหนดเวลา',
        RepairStatus.done => 'เสร็จสิ้นแล้ว',
        RepairStatus.cancelled => 'ยกเลิกแล้ว',
        // 🆕 [ใหม่] สถานะที่ช่างแจ้งว่า "มีปัญหา/ต้องตรวจสอบ" (markRepairProblem)
        // — เดิมไม่มีเคสนี้เลย ตกไปที่ default ของ fromString กลายเป็น waiting
        // ทำให้การ์ดโชว์ป้าย "รอจัดสรรช่าง" ผิด ๆ ทั้งที่จริงช่างแจ้งปัญหาไว้แล้ว
        RepairStatus.issue => 'มีปัญหา / ต้องตรวจสอบ',
      };

  Color get bg => switch (this) {
        RepairStatus.waiting => AppColors.yellowBg,
        // สีเดียวกับที่ StatusStyle.getStyle() ใน widgets.dart ใช้กับ
        // 'รอดำเนินการ' และ 'เกินกำหนดเวลา' อยู่แล้ว — เอามาใช้ซ้ำเพื่อให้
        // สีตรงกันทั้งแอป
        RepairStatus.scheduledPending => const Color(0xFFFFF7ED),
        // 🆕 [ใหม่] สีฟ้าเดียวกับที่ StatusStyle.getStyle() ใน widgets.dart
        // ใช้กับ 'กำลังเดินทาง' — แยกจาก "กำลังซ่อม" (น้ำเงินเข้ม) ให้เห็นชัดว่า
        // เป็นคนละขั้นตอนกัน
        RepairStatus.traveling => const Color(0xFFDCEEFF),
        RepairStatus.inProgress => AppColors.blueBg,
        RepairStatus.overdue => const Color(0xFFFFECEC),
        RepairStatus.done => AppColors.greenBg,
        RepairStatus.cancelled => AppColors.surfaceAlt,
        // สีแดงเหมือน "ยกเลิก" — ใช้ธีมเดียวกับ getStatusStyle() ใน widgets.dart
        RepairStatus.issue => AppColors.redBg,
      };

  Color get fg => switch (this) {
        RepairStatus.waiting => AppColors.yellowText,
        RepairStatus.scheduledPending => const Color(0xFFEA580C),
        RepairStatus.traveling => const Color(0xFF1D4ED8),
        RepairStatus.inProgress => AppColors.blueText,
        RepairStatus.overdue => const Color(0xFFB91C1C),
        RepairStatus.done => AppColors.greenText,
        RepairStatus.cancelled => AppColors.textSubtitle,
        RepairStatus.issue => AppColors.redText,
      };

  // 🔴 [แก้ไข] เดิม "ยกเลิก" ไม่มีเคสของตัวเองเลย ตกไปที่ default ซึ่งคืนค่า
  // waiting (รอดำเนินการ) ทำให้งานที่ถูกยกเลิกไปแล้วโชว์ปนอยู่ในแท็บ "รอดำเนินการ"
  // ของแอดมิน (และเผลอถูกนับรวมในสถิติ "รอรับ" ที่หน้าแรกแอดมินไปด้วยถ้าไม่กรองออก)
  static RepairStatus fromString(String? status) {
    if (status == null) return RepairStatus.waiting;
    switch (status.trim().toLowerCase()) {
      // 🆕 [ใหม่] ค่าใหม่ที่ markTechnicianTraveling() ใน services.dart ตั้งให้
      // ตอนช่างถึงคิวงานและเปิดดูแผนที่แล้ว (ก่อนหน้า "กำลังซ่อม" จริง)
      case 'กำลังเดินทาง':
        return RepairStatus.traveling;
      case 'กำลังดำเนินการ':
      // 🐛 [แก้บัค] getEffectiveRepairStatus() คืนค่า 'กำลังซ่อม' (ไม่ใช่
      // 'กำลังดำเนินการ') เมื่อถึงวันนัดแล้ว — เดิมไม่มีเคสนี้เลยจึงตกไปเป็น
      // waiting ทำให้งานที่กำลังซ่อมอยู่โชว์ป้าย "รอจัดสรรช่าง" ผิด ๆ
      case 'กำลังซ่อม':
      case 'inprogress':
      case 'in_progress':
        return RepairStatus.inProgress;
      // 🐛 [แก้บัค] เดิมไม่มีเคสนี้ ทำให้งานที่มีช่างแล้วแต่ยังไม่ถึงวันนัด
      // (สถานะ 'รอดำเนินการ' จาก getEffectiveRepairStatus()) ตกไปเป็น waiting
      // ปนกับงานที่ยังไม่มีช่างเลย ("รอจัดสรรช่าง") ทั้งที่เป็นคนละขั้นตอนกัน
      case 'รอดำเนินการ':
        return RepairStatus.scheduledPending;
      // 🐛 [แก้บัค] เดิมไม่มีเคสนี้ ทำให้งานที่เลยวันนัดไปแล้ว (สถานะ
      // 'เกินกำหนดเวลา') โชว์ป้าย "รอจัดสรรช่าง" ผิด ๆ ทั้งที่ตัวกรอง
      // แท็บ "เกินกำหนดเวลา" (ใช้ item.isOverdue) นับรวมงานนี้ไว้แล้ว
      case 'เกินกำหนดเวลา':
      case 'overdue':
        return RepairStatus.overdue;
      case 'เสร็จแล้ว':
      case 'เสร็จสิ้น':
      case 'เสร็จสิ้นแล้ว':
      case 'done':
      case 'completed':
        return RepairStatus.done;
      case 'ยกเลิก':
      case 'cancelled':
      case 'canceled':
        return RepairStatus.cancelled;
      // 🆕 [ใหม่] ค่าเดียวกับที่ markRepairProblem() ใน services.dart ใช้ตั้ง
      // สถานะตอนช่างกด "แจ้งว่ามีปัญหา / ต้องตรวจสอบ"
      case 'มีปัญหา':
        return RepairStatus.issue;
      default:
        return RepairStatus.waiting;
    }
  }
}

class RepairListItem {
  final int id;
  // 🆕 คีย์จริงใน Firebase ของ record นี้ (เช่น "k12") — ใช้เป็นทางสำรองตอนลบ
  // เมื่อ id ด้านบนเป็น 0 (ข้อมูลเสีย/ไม่มีฟิลด์ id) ดู _confirmDelete
  final String? fbKey;
  final String ticketId;
  final String customerName;
  final String modelName;
  final String? technicianUsername;
  // 🔴 [ใหม่] แอดมินผู้รับผิดชอบงานนี้ — ใช้กับฟีเจอร์ "จัดสรรงานไปให้แอดมินคนอื่น"
  final String? adminUsername;
  final RepairStatus status;
  final String date;
  final String location;
  // 🔴 งานเร่งด่วน = ความเสียหายระดับ "เร่งด่วน" ที่ลูกค้าเลือกไว้ตอนแจ้งซ่อม
  // (เก็บนำหน้าใน 'detail') หรือแอดมินตั้งค่าเองเป็น 'is_urgent' — ใช้ตรรกะเดียวกับ
  // หน้าแรกแอดมิน (home_admin.dart) เพื่อให้ตัวเลข/ตัวกรองตรงกัน
  final bool isUrgent;
  // 🆕 [ใหม่] เกินกำหนดเวลาหรือไม่ = วันนัดผ่านไปแล้วแต่งานยังไม่เสร็จ/ไม่ถูก
  // ยกเลิก — ก็อปตรรกะมาจากหน้าแรกแอดมิน (home_admin.dart _loadSummary) ตรง ๆ
  // ห้ามแก้ไขให้ต่างกัน ไม่งั้นตัวเลข "เกินกำหนด" หน้าแรกกับตัวกรองหน้านี้จะไม่ตรงกัน
  final bool isOverdue;

  const RepairListItem({
    required this.id,
    this.fbKey,
    required this.ticketId,
    required this.customerName,
    required this.modelName,
    this.technicianUsername,
    this.adminUsername,
    required this.status,
    required this.date,
    required this.location,
    this.isUrgent = false,
    this.isOverdue = false,
  });

  factory RepairListItem.fromMap(Map<String, dynamic> map) {
    final detail = (map['detail']?.toString()) ?? '';
    final isSevere = detail.contains('[ความรุนแรง: เร่งด่วน]');
    final isAdminUrgent = map['is_urgent'] == true || map['is_urgent'] == 1;
    final status = RepairStatusX.fromString(map['status']?.toString());

    final jobDate =
        _parseThaiDate((map['date'] ?? map['created_at'])?.toString());
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final isOverdue = jobDate != null &&
        jobDate.isBefore(todayDateOnly) &&
        status != RepairStatus.done &&
        status != RepairStatus.cancelled;

    return RepairListItem(
      // 🐛 [แก้บัค] เดิมอ่าน map['id'] ตรง ๆ ซึ่งอาจไม่ตรงกับคีย์จริงใน Firebase
      // ของ record นี้ (เช่น record ที่ถูกแก้ไขข้อมูลย้อนหลัง) ทำให้กดเข้าไปดู
      // รายละเอียดแล้วเปิดไปเจอ record คนละใบที่บังเอิญมีคีย์ตรงกับ field 'id'
      // (ข้อมูลว่างเปล่า/ไม่ตรงกับที่เห็นในรายการ) — ใช้ resolveRecordId() ที่ยึด
      // คีย์จริงเป็นหลักแทน ให้ตรงกับ record ที่แสดงในรายการเป๊ะ ๆ
      id: resolveRecordId(map) ?? 0,
      fbKey: (map['_fbKey']?.toString()),
      ticketId: map['ticketNo'] ?? map['ticket_no'] ?? '# AS-0000',
      customerName:
          map['customer_username'] ?? map['customer_name'] ?? 'ไม่ระบุชื่อ',
      modelName: map['machine'] ?? map['model_name'] ?? 'ไม่ระบุรุ่น',
      technicianUsername: map['technician_username'],
      adminUsername: map['admin_username'],
      status: status,
      date: (map['date'] ?? map['created_at'] ?? '-').toString(),
      location: (map['location']?.toString()) ?? '-',
      isUrgent: isSevere || isAdminUrgent,
      isOverdue: isOverdue,
    );
  }
}

// 🗓️ แปลงวันที่รูปแบบ 'd/M/พ.ศ.' (เช่น "19/8/2569") ที่เก็บไว้ตอนสร้างงาน กลับเป็น
// DateTime จริง — ก็อปมาจาก home_admin.dart (_parseThaiDate) ตรง ๆ เพื่อให้ตรรกะ
// "เกินกำหนด" ตรงกันทั้งสองหน้า
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

// --- UI COMPONENTS ---

class _RepairCard extends StatelessWidget {
  final RepairListItem item;
  final VoidCallback onDetailTap;
  final VoidCallback onDeleteTap;
  // 🔴 [ใหม่] เรียกตอนกด "มอบหมายให้แอดมิน" — เป็น null ได้ถ้าไม่ต้องการแสดงปุ่มนี้
  // (ใช้เป็น null implicitly เพื่อซ่อนปุ่มสำหรับแอดมินทั่วไป ดู build() ด้านล่าง)
  final VoidCallback? onReassignAdmin;

  const _RepairCard({
    required this.item,
    required this.onDetailTap,
    required this.onDeleteTap,
    this.onReassignAdmin,
  });

  @override
  Widget build(BuildContext context) {
    final techAssigned = item.technicianUsername != null &&
        item.technicianUsername!.trim().isNotEmpty;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onDetailTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                        Text(item.ticketId, style: AppStyles.historyCardTitle),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: ShapeDecoration(
                      color: item.status.fg.withValues(alpha: 0.12),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: item.status.fg, width: 1),
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
                            color: item.status.fg,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.status.label,
                          style: TextStyle(
                            color: item.status.fg,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  // ปุ่มลบใบแจ้งซ่อม (มีป๊อปอัพยืนยันก่อนลบ)
                  Tooltip(
                    message: 'ลบใบแจ้งซ่อม',
                    child: InkWell(
                      onTap: onDeleteTap,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.redBg,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.redText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _InfoRow(label: 'ลูกค้า', value: item.customerName),
              const SizedBox(height: 4),
              _InfoRow(label: 'เครื่อง', value: item.modelName),
              const SizedBox(height: 4),
              _InfoRow(
                label: 'ช่าง',
                value:
                    techAssigned ? item.technicianUsername! : 'ยังไม่ระบุช่าง',
                warn: !techAssigned,
              ),
              const SizedBox(height: 4),
              // 🔴 [ใหม่] แถวแอดมินผู้รับผิดชอบ + ปุ่ม "มอบหมายให้แอดมินคนอื่น"
              // — onReassignAdmin เป็น null สำหรับแอดมินทั่วไป (ซ่อนปุ่มไปเลย ไม่ใช่
              // แค่ปิดใช้งาน ป้องกันการเข้าใจผิดว่าเป็นปุ่มที่กดได้)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _InfoRow(
                      label: 'แอดมิน',
                      value: (item.adminUsername ?? '').trim().isEmpty
                          ? 'ยังไม่ระบุแอดมิน'
                          : item.adminUsername!,
                      warn: (item.adminUsername ?? '').trim().isEmpty,
                    ),
                  ),
                  if (onReassignAdmin != null)
                    InkWell(
                      onTap: onReassignAdmin,
                      borderRadius: BorderRadius.circular(6),
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text(
                          'มอบหมาย',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
                          item.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                        Text(item.date, style: AppStyles.historyCardSubtitle),
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
        ),
      ),
    );
  }
}

// 🆕 [ใหม่] แถบหัวข้อ + แท็บตัวกรองเลื่อนแนวนอนสำหรับหน้า "รายการซ่อมทั้งหมด"
// ของแอดมินโดยเฉพาะ — หน้าตาก็อปมาจาก HistoryHeaderContent (widgets.dart) ที่
// ลูกค้า/ช่างใช้ร่วมกัน แต่ผูกกับ AdminFilterTab แทน FilterTab เพื่อรองรับ 2 แท็บ
// ใหม่ ("มีปัญหา/ต้องตรวจสอบ", "เกินกำหนดเวลา") โดยไม่กระทบหน้าจอบทบาทอื่น
class _AdminFilterHeader extends StatelessWidget {
  final int totalTickets;
  final AdminFilterTab selectedTab;
  final ValueChanged<AdminFilterTab> onTabChanged;
  final VoidCallback? onBack;

  const _AdminFilterHeader({
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
                // ต่อแท็บใน home_admin.dart) ซึ่งเป็น route แรกสุดของ Navigator ของ
                // แท็บนั้นเสมอ ทำให้ maybePop() คืนค่า false เฉย ๆ กดแล้วไม่มีอะไร
                // เกิดขึ้นทุกครั้ง — เปลี่ยนให้รับ onBack callback จาก home_admin.dart
                // มาสลับกลับไปแท็บหน้าแรกแทน และเปลี่ยนหน้าตาปุ่มให้เหมือนปุ่มย้อนกลับ
                // ใน AppHeader (widgets.dart) ที่ใช้ในหน้าโปรไฟล์ — ใช้แพทเทิร์นเดียว
                // กับ _CustomerFilterHeader ใน history_customer.dart
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
              itemCount: AdminFilterTab.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final tab = AdminFilterTab.values[index];
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final bool warn;

  const _InfoRow({required this.label, required this.value, this.warn = false});

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
            style: warn
                ? AppStyles.historyCardSubtitle.copyWith(
                    color: AppColors.yellowText, fontWeight: FontWeight.w600)
                : AppStyles.historyCardSubtitle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final VoidCallback onClearSearch;

  const _EmptyState({required this.hasSearch, required this.onClearSearch});

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 100),
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.inbox_outlined,
                  size: 56, color: AppColors.textHint),
              const SizedBox(height: 12),
              Text(
                hasSearch
                    ? 'ไม่พบงานซ่อมตามเงื่อนไขที่เลือก'
                    : 'ยังไม่มีรายการแจ้งซ่อม',
                style: const TextStyle(
                    color: AppColors.textSubtitle,
                    fontSize: 14,
                    fontFamily: AppStyles.fontFamily),
              ),
              if (hasSearch) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: onClearSearch,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('ล้างคำค้นหา / ตัวกรอง',
                      style: TextStyle(fontFamily: AppStyles.fontFamily)),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.primary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}