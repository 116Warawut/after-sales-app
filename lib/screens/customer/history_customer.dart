import 'dart:async';

import 'package:after_sales/app_styles.dart';
//import 'package:after_sales/common_bottom_navbar.dart';
//import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/customer/customer_job_detail.dart';
import 'package:after_sales/screens/customer/history_customer.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HistoryCustomer extends StatelessWidget {
  final VoidCallback? onBack;
  const HistoryCustomer({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return RepairListPage(onBack: onBack);
  }
}

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------

enum TicketStatus {
  done,
  inProgress,
  waitingParts,
  waitingApproval,
  // 🆕 [ใหม่] สถานะ "รอดำเนินการ" (มีช่างแล้วแต่ยังไม่ถึงวันนัด) — ฝั่งแอดมิน
  // (web + mobile) แยกสถานะนี้ออกจาก "รอจัดสรรช่าง" อยู่แล้ว แต่ฝั่งลูกค้าเดิม
  // เอาไปรวมกับ waitingApproval ทำให้ลูกค้าไม่เห็นความแตกต่างว่างานของตัวเอง
  // ได้ช่างแล้วหรือยัง — เพิ่มเคสแยกให้ตรงกับแอดมิน
  scheduledPending,
  cancelled,
  // 🐛 [แก้บัค] เดิม enum นี้ไม่มีเคสสำหรับ "เกินกำหนดเวลา" และ "มีปัญหา" เลย —
  // ค่าทั้งสองนี้ที่ getEffectiveRepairStatus() ใน services.dart คำนวณได้ (ตรง
  // กับ RepairStatus.overdue/issue ที่ฝั่งแอดมันมีอยู่แล้วใน
  // repair_list_admin.dart / assign_repair_formdetail.dart) จะตกไปที่ default
  // ของ fromDbStatus() ด้านล่าง กลายเป็น waitingParts ทำให้หน้ารายการงานของ
  // ลูกค้า "และ" ของช่าง (joblist_technician.dart ใช้ enum นี้ร่วมกัน) โชว์ป้าย
  // "รอจัดสรรช่าง" ผิด ๆ ทั้งที่จริงงานเกินกำหนดหรือช่างแจ้งปัญหาไว้แล้ว —
  // เพิ่ม 2 เคสนี้ให้ตรงกับฝั่งแอดมิน
  overdue,
  issue,
  // 🆕 [ใหม่] สถานะ "กำลังเดินทาง" (ถึงคิวงานแล้ว ช่างกำลังมุ่งหน้าไปหาลูกค้า
  // ยังไม่ได้ลงมือซ่อมจริง) — ตั้งโดย markTechnicianTraveling() ใน
  // services.dart ตอนช่างผ่านเงื่อนไขวันนัด+คิวงานในหน้าติดตามตำแหน่งลูกค้า
  // เพิ่มเคสให้ตรงกับฝั่งแอดมิน (RepairStatus.traveling ใน
  // repair_list_admin.dart / assign_repair_formdetail.dart) กันตกไปที่
  // default กลายเป็น waitingParts เหมือนสถานะใหม่อื่น ๆ ที่เจอมาก่อนหน้านี้
  traveling,
}

extension TicketStatusX on TicketStatus {
  String get label {
    switch (this) {
      case TicketStatus.done:
        return 'เสร็จสิ้น';
      case TicketStatus.inProgress:
        return 'กำลังซ่อม';
      case TicketStatus.waitingParts:
        return 'รอจัดสรรช่าง';
      case TicketStatus.waitingApproval:
        return 'รอจัดสรรช่าง';
      case TicketStatus.scheduledPending:
        return 'รอดำเนินการ';
      case TicketStatus.cancelled:
        return 'ยกเลิกแล้ว';
      // 🆕 [ใหม่] label เดียวกับที่ฝั่งแอดมินใช้ (RepairStatus.overdue/issue)
      case TicketStatus.overdue:
        return 'เกินกำหนดเวลา';
      case TicketStatus.issue:
        return 'มีปัญหา / ต้องตรวจสอบ';
      case TicketStatus.traveling:
        return 'กำลังเดินทาง';
    }
  }

  Color get color {
    switch (this) {
      case TicketStatus.done:
        return AppColors.greenText;
      case TicketStatus.inProgress:
        return AppColors.yellowText;
      case TicketStatus.waitingParts:
        return AppColors.textLabel;
      case TicketStatus.waitingApproval:
        return AppColors.textLabel;
      // สีเดียวกับที่ StatusStyle.getStyle() ใน widgets.dart ใช้กับ
      // 'รอดำเนินการ' อยู่แล้ว — เอามาใช้ซ้ำเพื่อให้สีตรงกันทั้งแอป
      case TicketStatus.scheduledPending:
        return const Color(0xFFEA580C);
      case TicketStatus.cancelled:
        return AppColors.textHint;
      // 🆕 [ใหม่] สีเดียวกับที่ RepairStatusHelper ฝั่งแอดมินใช้กับสองสถานะนี้
      case TicketStatus.overdue:
        return const Color(0xFFB91C1C);
      case TicketStatus.issue:
        return AppColors.redText;
      // 🆕 [ใหม่] สีฟ้าเดียวกับที่ StatusStyle.getStyle() ใน widgets.dart /
      // RepairStatus.traveling ฝั่งแอดมินใช้ — แยกจาก "กำลังซ่อม" (เหลือง)
      case TicketStatus.traveling:
        return const Color(0xFF1D4ED8);
    }
  }

  // 🔴 [แก้ไข] เดิมสถานะ "ยกเลิก" ไม่มีเคสของตัวเองเลย ตกไปที่ default ซึ่งคืนค่า
  // waitingParts (รอจัดสรรช่าง) ทำให้งานที่ลูกค้ายกเลิกไปแล้วโชว์เหมือนยังรอดำเนินการ
  // อยู่ในหน้าประวัติของลูกค้าเอง — เพิ่มเคสให้ตรงจริง
  static TicketStatus fromDbStatus(String? status) {
    switch (status) {
      case 'เสร็จแล้ว':
      case 'เสร็จสิ้น':
        return TicketStatus.done;
      case 'กำลังดำเนินการ':
      case 'กำลังซ่อม':
        return TicketStatus.inProgress;
      case 'รอจัดสรรช่าง':
      case 'รอช่างรับงาน':
        return TicketStatus.waitingApproval;
      // 🆕 [ใหม่] แยกออกจาก 'รอจัดสรรช่าง' ด้านบน — เดิมรวมเป็นเคสเดียวกันทำให้
      // ลูกค้าเห็นป้าย "รอจัดสรรช่าง" ทั้งที่จริงมีช่างรับงานแล้ว แค่ยังไม่ถึง
      // วันนัดหมาย (ตรงกับ getEffectiveRepairStatus() ใน services.dart)
      case 'รอดำเนินการ':
        return TicketStatus.scheduledPending;
      case 'ยกเลิก':
        return TicketStatus.cancelled;
      // 🆕 [ใหม่] เพิ่มเคสที่ขาดไป — ก่อนหน้านี้ทั้งสองค่าตกไปที่ default
      // (waitingParts) ทำให้โชว์ป้าย "รอจัดสรรช่าง" ผิด
      case 'เกินกำหนดเวลา':
        return TicketStatus.overdue;
      case 'มีปัญหา':
        return TicketStatus.issue;
      // 🆕 [ใหม่] เพิ่มเคสให้ตรงกับฝั่งแอดมิน (ดู RepairStatus.traveling)
      case 'กำลังเดินทาง':
        return TicketStatus.traveling;
      default:
        return TicketStatus.waitingParts;
    }
  }
}

class Ticket {
  final int? id;
  final String ticketNo;
  final TicketStatus status;
  final String device;
  final String location;
  final String subStatusLabel;
  final String date;
  // ⭐ [เพิ่มใหม่] เร่งด่วนหรือไม่ — คำนวณจาก 2 ทาง (เหมือนกับ home_admin.dart
  // เป๊ะ ๆ กันสองหน้าคำนวณไม่ตรงกัน): (1) ลูกค้าเลือกความรุนแรง "เร่งด่วน"
  // ตอนแจ้งซ่อม เก็บเป็น tag ใน field 'detail', หรือ (2) แอดมินตั้งเองผ่าน
  // field 'is_urgent'
  final bool isUrgent;
  // ⭐ [เพิ่มใหม่] true = งานเสร็จสิ้นแล้วแต่ลูกค้ายังไม่ได้ให้คะแนนช่าง —
  // เช็คจากสถานะ+rating_stars ตรง ๆ (ไม่พึ่ง rating_eligible ที่ตั้งจาก
  // ฝั่ง backend อย่างเดียว เพราะ trigger อาจไม่ทันเซ็ตค่าให้ทุกเคส) ให้
  // สอดคล้องกับเงื่อนไข isDoneJob ใน customer_job_detail.dart
  final bool needsRating;
  // 🆕 [ใหม่] เวลาที่ปิดงานจริง (จาก report_submitted_at ตอนช่างส่งรายงานซ่อม
  // ซึ่งเป็นจุดเดียวที่ตั้งสถานะ 'เสร็จแล้ว' — ดู submitRepairReport() ใน
  // services.dart) แยกออกจาก [date] ซึ่งเป็น "วันนัดหมาย" เดิมของงาน ไม่ใช่
  // วันที่ปิดงานจริง — จำเป็นสำหรับแยกแยะ "งานเสร็จวันนี้" ให้ถูกต้องตอนที่
  // งานนั้นนัดไว้วันอื่นแต่เพิ่งมาปิดจบวันนี้ (งานเลยกำหนด)
  final DateTime? completedAt;

  const Ticket({
    this.id,
    required this.ticketNo,
    required this.status,
    required this.device,
    required this.location,
    required this.subStatusLabel,
    required this.date,
    this.isUrgent = false, // ⭐ [เพิ่มใหม่]
    this.needsRating = false, // ⭐ [เพิ่มใหม่]
    this.completedAt, // 🆕 [ใหม่]
  });

  factory Ticket.fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status']?.toString();
    // รองรับทั้งคอลัมน์ date และ created_at เผื่อใน DB ใช้ชื่อต่างกัน
    final dateStr = (map['date'] ?? map['created_at'])?.toString();

    // ⭐ [เพิ่มใหม่] logic เดียวกับ home_admin.dart — ห้ามแก้ไขให้ต่างกัน
    // ไม่งั้นหน้าลูกค้ากับหน้าแอดมินจะนับงาน "เร่งด่วน" ไม่ตรงกัน
    final detail = (map['detail']?.toString()) ?? '';
    final isSevere = detail.contains('[ความรุนแรง: เร่งด่วน]');
    final isAdminUrgent = map['is_urgent'] == true || map['is_urgent'] == 1;

    // 🆕 [ใหม่] เวลาปิดงานจริง — ใช้ report_submitted_at เป็นหลัก (เซ็ตตอน
    // ช่างส่งรายงานซ่อมพร้อมเปลี่ยนสถานะเป็น 'เสร็จแล้ว' จุดเดียว) ถ้าไม่มี
    // (ข้อมูลเก่าก่อนมีฟิลด์นี้) fallback ไปที่ updated_at แทน
    final completedAtStr =
        (map['report_submitted_at'] ?? map['updated_at'])?.toString();
    final completedAt =
        completedAtStr != null ? DateTime.tryParse(completedAtStr) : null;

    return Ticket(
      // 🐛 [แก้บัค] เดิมอ่าน map['id'] ตรง ๆ ซึ่งอาจไม่ตรงกับคีย์จริงใน Firebase
      // ของ record นี้ ทำให้กดเข้าไปดูรายละเอียดแล้วเปิดไปเจอ record คนละใบ —
      // ใช้ resolveRecordId() ที่ยึดคีย์จริงเป็นหลักแทน (ดูเหตุผลใน
      // utils/firebase_number.dart)
      id: resolveRecordId(map),
      ticketNo: (map['ticketNo']?.toString()) ?? '#AS-${map['id'] ?? ''}',
      status: TicketStatusX.fromDbStatus(rawStatus),
      device: (map['machine']?.toString()) ?? '-',
      location: (map['location']?.toString()) ?? '-',
      subStatusLabel: rawStatus ?? '-',
      date: dateStr ?? '-',
      isUrgent: isSevere || isAdminUrgent, // ⭐ [เพิ่มใหม่]
      // ⭐ [เพิ่มใหม่] เงื่อนไขเดียวกับ isDoneJob ใน customer_job_detail.dart —
      // เสร็จงานแล้ว + ยังไม่เคยมีคะแนน (rating_stars/rating) ในระเบียนนี้
      needsRating: (rawStatus ?? '').contains('เสร็จ') &&
          map['rating_stars'] == null &&
          map['rating'] == null,
      completedAt: completedAt, // 🆕 [ใหม่]
    );
  }
}

// ⭐ [เพิ่มใหม่] เพิ่มค่า urgent ต่อท้าย cancelled — เดิมมีแค่
// { all, done, inProgress, pending, cancelled }
// 🆕 [ใหม่] เพิ่มแท็บ "รอดำเนินการ" ให้ตรงกับฝั่งแอดมิน (web + mobile) — เดิม
// งานที่มีช่างรับแล้วแต่ยังไม่ถึงวันนัดจะไปโผล่ในแท็บ "รอจัดสรรช่าง" ปนกับงาน
// ที่ยังไม่มีช่างเลย ทำให้ลูกค้าแยกไม่ออกว่างานตัวเองมีช่างรับแล้วหรือยัง
enum FilterTab {
  all,
  done,
  inProgress,
  pending,
  scheduledPending,
  cancelled,
  urgent,
  // 🆕 [ใหม่] เพิ่มแท็บ "มีปัญหา" ให้ครบเหมือนฝั่งแอดมิน (AdminFilterTab.issue
  // ใน repair_list_admin.dart) และหน้าเว็บแอดมิน (JOB_STATUS_TABS ใน
  // constants.js) — เดิม TicketStatus.issue มีอยู่แล้วและคำนวณ/แสดงสีถูกต้อง
  // ในการ์ดรายการงาน แต่ไม่มีแท็บให้กดกรองดูเฉพาะงานที่ช่างแจ้งว่ามีปัญหา ทำให้
  // ลูกค้า/ช่างต้องไล่หาเองในแท็บ "ทั้งหมด"
  issue,
  // 🆕 [ใหม่] เพิ่มแท็บ "กำลังเดินทาง" แยกออกจาก "กำลังซ่อม" — เดิม
  // TicketStatus.traveling ถูกนับรวมอยู่ในสรุปสถานะทั่วไปแต่ไม่มีแท็บกรองแยก
  // ให้ตรงกับที่แอดมิน/เว็บมี (ดู RepairStatus.traveling ใน
  // assign_repair_formdetail.dart และ JOB_STATUS_TABS ฝั่งเว็บ)
  traveling,
}

extension FilterTabX on FilterTab {
  String get label {
    switch (this) {
      case FilterTab.all:
        return 'ทั้งหมด';
      case FilterTab.done:
        return 'เสร็จสิ้น';
      case FilterTab.inProgress:
        return 'กำลังซ่อม';
      case FilterTab.pending:
        return 'รอจัดสรรช่าง';
      case FilterTab.scheduledPending: // 🆕 [ใหม่]
        return 'รอดำเนินการ';
      case FilterTab.cancelled:
        return 'ยกเลิก';
      case FilterTab.urgent: // ⭐ [เพิ่มใหม่]
        return 'เร่งด่วน';
      // 🆕 [ใหม่] ใช้คำว่า "มีปัญหา" สั้น ๆ ให้ตรงกับป้ายแท็บบนหน้าเว็บแอดมิน
      // (JOB_STATUS_TABS ใน constants.js ใช้ "มีปัญหา" ไม่ใช่ "มีปัญหา / ต้อง
      // ตรวจสอบ" แบบที่ TicketStatus.issue.label ใช้ในการ์ดรายละเอียด)
      case FilterTab.issue:
        return 'มีปัญหา';
      case FilterTab.traveling:
        return 'กำลังเดินทาง';
    }
  }

  // ⭐ [เพิ่มใหม่] เพิ่มพารามิเตอร์ isUrgent แบบมีค่า default (false) เพื่อไม่ให้
  // จุดเรียกใช้เดิมที่ยังเรียกแบบ .matches(status) เฉย ๆ (ไม่ส่ง isUrgent มา) พัง
  // — ของเดิมทุกเคส (all/done/inProgress/pending/cancelled) ไม่ถูกแก้ไขเลย
  bool matches(TicketStatus status, {bool isUrgent = false}) {
    switch (this) {
      case FilterTab.all:
        return true;
      case FilterTab.done:
        return status == TicketStatus.done;
      case FilterTab.inProgress:
        return status == TicketStatus.inProgress;
      case FilterTab.pending:
        return status == TicketStatus.waitingParts ||
            status == TicketStatus.waitingApproval;
      // 🆕 [ใหม่] แยกออกจากแท็บ "รอจัดสรรช่าง" ด้านบน
      case FilterTab.scheduledPending:
        return status == TicketStatus.scheduledPending;
      case FilterTab.cancelled:
        return status == TicketStatus.cancelled;
      case FilterTab.urgent: // ⭐ [เพิ่มใหม่]
        return isUrgent;
      // 🆕 [ใหม่] กรองเฉพาะงานที่ TicketStatus เป็น issue (ช่างกดแจ้งว่ามีปัญหา/
      // ต้องตรวจสอบ — mapped จากสถานะ 'มีปัญหา' ใน fromDbStatus() ด้านบนแล้ว)
      case FilterTab.issue:
        return status == TicketStatus.issue;
      case FilterTab.traveling:
        return status == TicketStatus.traveling;
    }
  }
}

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
  FilterTab _selectedTab = FilterTab.all;

  bool _loading = true;
  List<Ticket> _tickets = [];

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showAll = false;
  static const int _previewCount = 10;

  // 🐛 [แก้บัค] เหมือนกับที่แก้ในหน้า "งานทั้งหมด" ของช่าง
  // (joblist_technician.dart) — เดิมหน้านี้โหลดงานของลูกค้าด้วย .get() ครั้งเดียว
  // ตอนเปิดหน้า ทำให้ป้ายสถานะค้างเป็นค่าเก่าถ้าสถานะเปลี่ยนระหว่างที่ลูกค้าค้าง
  // อยู่ในหน้ารายการ — เพิ่ม subscription ฟัง watchRepairsByCustomer() แบบ
  // real-time ควบคู่ไปกับ _loadTickets() เดิม (ยังคงไว้เผื่อ subscription ล้มเหลว)
  StreamSubscription<List<Map<String, dynamic>>>? _ticketsSubscription;

  @override
  void initState() {
    super.initState();
    _loadTickets();
    _ticketsSubscription = db.DatabaseHelper.instance
        .watchRepairsByCustomer(db.Session.currentUsername)
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _tickets = rows.map((row) => Ticket.fromMap(row)).toList();
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

    final rows = await db.DatabaseHelper.instance.getRepairsByCustomer(
      db.Session.currentUsername,
    );

    if (!mounted) return;
    setState(() {
      _tickets = rows.map((row) => Ticket.fromMap(row)).toList();
      _loading = false;
    });
  }

  List<Ticket> get _filteredTickets {
    final query = _searchQuery.trim().toLowerCase();
    return _tickets.where((t) {
      // ⭐ [แก้ไข] เพิ่มการส่ง isUrgent: t.isUrgent เข้าไปด้วย — เดิมเรียกแค่
      // _selectedTab.matches(t.status) เฉย ๆ ไม่กระทบผลลัพธ์เดิมเพราะ isUrgent
      // มีค่า default เป็น false ถ้าไม่ได้เลือกแท็บ "เร่งด่วน"
      final matchesTab = _selectedTab.matches(t.status, isUrgent: t.isUrgent);
      final matchesSearch = query.isEmpty ||
          t.ticketNo.toLowerCase().contains(query) ||
          t.device.toLowerCase().contains(query);
      return matchesTab && matchesSearch;
    }).toList();
  }

  // 🔄 ปรับเปิดหน้า Detail ให้ await แล้วค่อยโหลดข้อมูลใหม่เผื่อมีการเปลี่ยนแปลง
  Future<void> _openTicketDetail(Ticket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerJobDetailPage(repairId: ticket.id),
      ),
    );
    _loadTickets();
  }

  @override
  Widget build(BuildContext context) {
    final allFiltered = _filteredTickets;
    final hasSearch = _searchQuery.trim().isNotEmpty;
    final tickets = (hasSearch || _showAll)
        ? allFiltered
        : allFiltered.take(_previewCount).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🐛 [แก้บัค] เดิมหน้านี้เรียก HistoryHeaderContent (widgets.dart) ซึ่งรับ
            // พารามิเตอร์ selectedTab/onTabChanged เป็น enum FilterTab "คนละตัว"
            // กับ enum FilterTab ที่ไฟล์นี้ประกาศเองด้านบน (ชื่อซ้ำกันแต่เป็นคนละ
            // ชนิดข้อมูลเพราะประกาศคนละไฟล์กัน) ทำให้ส่ง _selectedTab เข้าไปไม่ตรง
            // ชนิดพารามิเตอร์ที่ต้องการ — คอมไพล์ไม่ผ่าน จึงเปลี่ยนมาใช้
            // _CustomerFilterHeader ของหน้านี้เองแทน (แพทเทิร์นเดียวกับที่
            // repair_list_admin.dart ใช้ _AdminFilterHeader ของตัวเองเพื่อเลี่ยงปัญหา
            // เดียวกันนี้)
            _CustomerFilterHeader(
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

            // ช่องค้นหา (รหัสแจ้งซ่อม หรือ รุ่นเครื่อง)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหารหัสแจ้งซ่อม หรือรุ่นเครื่อง...',
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
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text(
                                    'ไม่มีรายการในสถานะนี้',
                                    style: TextStyle(
                                      color: AppColors.textSubtitle,
                                      fontFamily: AppStyles.fontFamily,
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
                                  tickets.length + (hasSearch || _showAll || allFiltered.length <= _previewCount ? 0 : 1),
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

      //Todo: ตรงนี้ error เพราะไม่มีตัวแปร pages และ currentIndex ใน class นี้
      //body: pages[currentIndex],ตรงนี้ error
    );
  }
}

// ---------------------------------------------------------------------------
// Ticket card widget
// ---------------------------------------------------------------------------

class _TicketCard extends StatelessWidget {
  final Ticket ticket;
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
          if (ticket.needsRating) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: ShapeDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  side: const BorderSide(color: Colors.amber, width: 1),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                  SizedBox(width: 4),
                  Text(
                    'รอให้คะแนนช่าง',
                    style: TextStyle(
                      color: Color(0xFF8A6D00),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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

// 🐛 [แก้บัค] แถบหัวข้อ + แท็บตัวกรองเลื่อนแนวนอนของหน้าประวัติงานซ่อมลูกค้า —
// หน้าตาก็อปมาจาก HistoryHeaderContent (widgets.dart) แต่ผูกกับ FilterTab ของ
// ไฟล์นี้เอง (คนละชนิดกับ FilterTab ใน widgets.dart แม้ชื่อจะซ้ำกัน) เพื่อแก้
// ปัญหาชนิดข้อมูลไม่ตรงกันตอนเรียก HistoryHeaderContent ตรง ๆ — ใช้แพทเทิร์น
// เดียวกับ _AdminFilterHeader ใน repair_list_admin.dart
class _CustomerFilterHeader extends StatelessWidget {
  final int totalTickets;
  final FilterTab selectedTab;
  final ValueChanged<FilterTab> onTabChanged;
  final VoidCallback? onBack;

  const _CustomerFilterHeader({
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
                // ต่อแท็บใน home_customer.dart) ซึ่งเป็น route แรกสุดของ Navigator
                // ของแท็บนั้นเสมอ ทำให้ maybePop() คืนค่า false เฉย ๆ กดแล้วไม่มีอะไร
                // เกิดขึ้นทุกครั้ง — เปลี่ยนให้รับ onBack callback จาก home_customer.dart
                // มาสลับกลับไปแท็บหน้าแรกแทน ถ้าไม่มี onBack (เช่นถูก push ตรง ๆ ผ่าน
                // route '/history') จึง fallback ไปที่ maybePop() แบบเดิม และเปลี่ยน
                // หน้าตาปุ่มให้เหมือนปุ่มย้อนกลับใน AppHeader (widgets.dart) ที่ใช้ใน
                // หน้าโปรไฟล์ — วงกลม, arrow_back_ios_new_rounded, มี haptic feedback
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