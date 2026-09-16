// ==========================================
// SECTION 1: IMPORTS & ENUMS / HELPER
// ==========================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/admin/admin_create_invoice.dart';
import 'package:after_sales/services.dart';
import 'package:after_sales/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:after_sales/screens/admin/admin_tracking.dart';
import 'package:after_sales/utils/firebase_number.dart';

/// 📌 Enum สำหรับจัดการสถานะงานซ่อม (ตรงตามมาตรฐานระบบ)
enum RepairStatus {
  waiting('รอจัดสรรช่าง'),
  // 🐛 [แก้บัค] เพิ่ม "รอดำเนินการ" (มีช่างแล้วแต่ยังไม่ถึงวันนัด) และ
  // "เกินกำหนดเวลา" (ถึงวันนัดแล้วแต่ยังไม่เสร็จ) ให้ตรงกับค่าที่
  // getEffectiveRepairStatus() ใน services.dart คำนวณจริง — เดิม enum นี้ไม่มี
  // 2 เคสนี้เลย (และไม่รองรับ 'กำลังซ่อม' ที่ใช้ตอนถึงวันนัดพอดี) ทำให้ตกไปที่
  // default กลายเป็น waiting เสมอ หน้ารายละเอียดงานเลยโชว์ "รอจัดสรรช่าง" ผิด ๆ
  // ทั้งที่มีช่างรับงานแล้วและหน้ารายการซ่อม (repair_list_admin.dart) โชว์ถูกต้อง
  scheduledPending('รอดำเนินการ'),
  // 🆕 [ใหม่] สถานะ "กำลังเดินทาง" (ถึงคิวงานแล้ว ช่างกำลังมุ่งหน้าไปหาลูกค้า
  // ยังไม่ได้ลงมือซ่อมจริง) — ตั้งโดย markTechnicianTraveling() ใน
  // services.dart ตอนช่างผ่านเงื่อนไขวันนัด+คิวงานในหน้าติดตามตำแหน่งลูกค้า
  traveling('กำลังเดินทาง'),
  inProgress('กำลังดำเนินการ'),
  overdue('เกินกำหนดเวลา'),
  completed('เสร็จสิ้นแล้ว'),
  issue('มีปัญหา / ต้องตรวจสอบ'),
  cancelled('ยกเลิกแล้ว');

  final String label;
  const RepairStatus(this.label);

  /// แปลง String จาก Database เป็น Enum
  static RepairStatus fromString(String? status) {
    if (status == null) return RepairStatus.waiting;
    switch (status.trim().toLowerCase()) {
      // 🆕 [ใหม่] ค่าใหม่ที่ markTechnicianTraveling() ใน services.dart ตั้งให้
      // ตอนช่างถึงคิวงานและเปิดดูแผนที่แล้ว (ก่อนหน้า "กำลังซ่อม" จริง)
      case 'กำลังเดินทาง':
        return RepairStatus.traveling;
      // 🐛 [แก้บัค] getEffectiveRepairStatus() คืนค่า 'กำลังซ่อม' (ไม่ใช่
      // 'กำลังดำเนินการ') เมื่อถึงวันนัดพอดี — เดิมไม่มีเคสนี้เลยจึงตกไปเป็น
      // waiting ทำให้งานที่กำลังซ่อมอยู่โชว์ป้าย "รอจัดสรรช่าง" ผิด ๆ
      case 'กำลังดำเนินการ':
      case 'กำลังซ่อม':
      case 'inprogress':
      case 'in_progress':
        return RepairStatus.inProgress;
      case 'รอดำเนินการ':
        return RepairStatus.scheduledPending;
      case 'เกินกำหนดเวลา':
      case 'overdue':
        return RepairStatus.overdue;
      case 'เสร็จแล้ว':
      case 'เสร็จสิ้น':
      case 'เสร็จสิ้นแล้ว':
      case 'done':
      case 'completed':
        return RepairStatus.completed;
      case 'มีปัญหา':
        return RepairStatus.issue;
      case 'ยกเลิก':
      case 'cancelled':
      case 'canceled':
        return RepairStatus.cancelled;
      default:
        return RepairStatus.waiting;
    }
  }
}

/// 📌 Helper สำหรับจัดการสีตามสถานะงาน
class RepairStatusHelper {
  static Color getBgColor(RepairStatus status) {
    switch (status) {
      case RepairStatus.inProgress:
        return AppColors.blueBg;
      // 🆕 [ใหม่] สีฟ้าเดียวกับที่ widgets.dart/repair_list_admin.dart ใช้กับ
      // 'กำลังเดินทาง' — แยกจาก "กำลังดำเนินการ" (น้ำเงินเข้ม) ให้ชัดเจนว่า
      // เป็นคนละขั้นตอนกัน
      case RepairStatus.traveling:
        return const Color(0xFFDCEEFF);
      case RepairStatus.scheduledPending:
        return const Color(0xFFFFF7ED);
      case RepairStatus.overdue:
        return const Color(0xFFFFECEC);
      case RepairStatus.completed:
        return AppColors.greenBg;
      case RepairStatus.waiting:
        return AppColors.yellowBg;
      case RepairStatus.issue:
        return AppColors.redBg;
      case RepairStatus.cancelled:
        return AppColors.surfaceAlt;
    }
  }

  static Color getTextColor(RepairStatus status) {
    switch (status) {
      case RepairStatus.inProgress:
        return AppColors.blueText;
      case RepairStatus.traveling:
        return const Color(0xFF1D4ED8);
      case RepairStatus.scheduledPending:
        return const Color(0xFFEA580C);
      case RepairStatus.overdue:
        return const Color(0xFFB91C1C);
      case RepairStatus.completed:
        return AppColors.greenText;
      case RepairStatus.waiting:
        return AppColors.yellowText;
      case RepairStatus.issue:
        return AppColors.redText;
      case RepairStatus.cancelled:
        return AppColors.textSubtitle;
    }
  }
}

// ==========================================
// SECTION 2: DATA MODELS
// ==========================================

/// 📌 โมเดลข้อมูลช่าง
class TechnicianItem {
  final String username;
  final String name;
  final int jobsOnSelectedDate;

  const TechnicianItem({
    required this.username,
    required this.name,
    this.jobsOnSelectedDate = 0,
  });

  bool get isFull =>
      jobsOnSelectedDate >= DatabaseHelper.maxJobsPerTechnicianPerDay;

  TechnicianItem copyWith({int? jobsOnSelectedDate}) => TechnicianItem(
        username: username,
        name: name,
        jobsOnSelectedDate: jobsOnSelectedDate ?? this.jobsOnSelectedDate,
      );
}

/// ตัวช่วยแปลงวันที่ให้อยู่ในรูปแบบเดียวกับที่ระบบเก็บในคอลัมน์ date (พ.ศ.)
class AppointmentDate {
  AppointmentDate._();

  static const List<String> _monthsTh = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  static String toDbText(DateTime d) => '${d.day}/${d.month}/${d.year + 543}';

  static String toDisplay(DateTime d) =>
      '${d.day} ${_monthsTh[d.month - 1]} ${d.year + 543}';

  static DateTime? parse(String? text) {
    if (text == null || text.trim().isEmpty || text.trim() == '-') return null;
    final parts = text.trim().split('/');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    var year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    if (year > 2400) year -= 543;
    if (month < 1 || month > 12) return null;
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }
}

/// 📌 โมเดลข้อมูลงานซ่อม
class AdminJobInfo {
  final String ticketId;
  final String machineCode;
  final String modelName;
  final String description;
  final RepairStatus status;
  final String customerName;
  final String customerPhone;
  final String address;
  final double? destLat;
  final double? destLng;
  final String appointmentDate;
  final String appointmentTime;
  final List<String> images;
  final String reportFormCode;
  final String reportProblemDetail;
  final String reportBeforePhoto;
  final String reportAfterPhoto;
  final String reportSlipPhoto;
  final String? reportSubmittedAt;

  const AdminJobInfo({
    required this.ticketId,
    required this.machineCode,
    required this.modelName,
    required this.description,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    this.destLat,
    this.destLng,
    required this.appointmentDate,
    this.appointmentTime = '',
    this.images = const [],
    this.reportFormCode = '',
    this.reportProblemDetail = '',
    this.reportBeforePhoto = '',
    this.reportAfterPhoto = '',
    this.reportSlipPhoto = '',
    this.reportSubmittedAt,
  });

  bool get hasReport =>
      reportSubmittedAt != null && reportSubmittedAt!.isNotEmpty;
}

// ==========================================
// SECTION 3: MAIN WIDGET
// ==========================================

class AssignRepairFormDetailPage extends StatefulWidget {
  final int repairId;

  const AssignRepairFormDetailPage({super.key, required this.repairId});

  @override
  State<AssignRepairFormDetailPage> createState() =>
      _AssignRepairFormDetailPageState();
}

// ==========================================
// SECTION 4: STATE MANAGEMENT & LOGIC
// ==========================================

class _AssignRepairFormDetailPageState
    extends State<AssignRepairFormDetailPage> {
  AdminJobInfo? _job;
  List<TechnicianItem> _technicians = [];

  String? _selectedTechnicianUsername;
  String? _assignedTechnicianUsername;
  String? _assignedTechnicianName;

  /// วันและเวลานัดซ่อม
  DateTime? _appointmentDate;
  TimeOfDay? _appointmentTime;

  bool _isLoading = true;
  bool _isAssigning = false;
  bool _isCheckingQuota = false;

  @override
  void initState() {
    super.initState();
    _loadDataFromDatabase();
  }

  String _formatTimeOfDay(TimeOfDay? time) {
    if (time == null) return 'แตะเพื่อเลือกเวลา';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute น.';
  }

  /// 🔄 ดึงข้อมูลใบแจ้งซ่อม + รายชื่อช่างจาก Database
  Future<void> _loadDataFromDatabase() async {
    setState(() => _isLoading = true);

    try {
      final dbHelper = DatabaseHelper.instance;

      final repairRow = await dbHelper.getRepairById(widget.repairId);
      final techList = await dbHelper.getAllTechnicians();
      _technicians = techList
          .map((item) {
            return TechnicianItem(
              username: item['username']?.toString() ?? '',
              name: item['tech_name']?.toString() ??
                  item['name']?.toString() ??
                  'ไม่ระบุชื่อ',
            );
          })
          .where((t) => t.username.isNotEmpty)
          .toList();

      if (repairRow != null) {
        final rawImages = repairRow['images']?.toString() ?? '';
        final imageList = rawImages.isNotEmpty
            ? rawImages
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : <String>[];

        String cusName = '-';
        String cusPhone = '-';
        final cusUsername = repairRow['customer_username']?.toString();

        if (cusUsername != null && cusUsername.isNotEmpty) {
          final customer = await dbHelper.getCustomerProfile(cusUsername);
          if (customer != null) {
            cusName =
                '${customer['name'] ?? ''} ${customer['surname'] ?? ''}'.trim();
            if (cusName.isEmpty) cusName = cusUsername;
            cusPhone = customer['phone']?.toString() ?? '-';
          }
        }

        final statusStr = repairRow['status']?.toString();
        final timeStr = repairRow['appointment_time']?.toString() ??
            repairRow['time']?.toString() ??
            '';

        if (timeStr.contains(':')) {
          final parts = timeStr.replaceAll(RegExp(r'[^0-9:]'), '').split(':');
          if (parts.length >= 2) {
            final h = int.tryParse(parts[0]);
            final m = int.tryParse(parts[1]);
            if (h != null && m != null) {
              _appointmentTime = TimeOfDay(hour: h, minute: m);
            }
          }
        }
        _appointmentTime ??= const TimeOfDay(hour: 9, minute: 0);

        _job = AdminJobInfo(
          ticketId: repairRow['ticketNo']?.toString() ??
              repairRow['ticket_no']?.toString() ??
              '#AS-${repairRow['id']}',
          machineCode: repairRow['machine']?.toString() ??
              repairRow['machine_code']?.toString() ??
              '-',
          modelName: repairRow['model_name']?.toString() ?? '-',
          description: repairRow['detail']?.toString() ?? '-',
          status: RepairStatus.fromString(statusStr),
          customerName: cusName,
          customerPhone: cusPhone,
          address: repairRow['location']?.toString() ??
              repairRow['address']?.toString() ??
              '-',
          destLat: toDoubleOrNull(repairRow['dest_lat']),
          destLng: toDoubleOrNull(repairRow['dest_lng']),
          appointmentDate: repairRow['date']?.toString() ?? '-',
          appointmentTime: timeStr,
          images: imageList,
          reportFormCode: repairRow['report_form_code']?.toString() ?? '',
          reportProblemDetail:
              repairRow['report_problem_detail']?.toString() ?? '',
          reportBeforePhoto:
              repairRow['report_before_photo']?.toString() ?? '',
          reportAfterPhoto: repairRow['report_after_photo']?.toString() ?? '',
          reportSlipPhoto: repairRow['report_slip_photo']?.toString() ?? '',
          reportSubmittedAt: repairRow['report_submitted_at']?.toString(),
        );

        _assignedTechnicianUsername =
            repairRow['technician_username']?.toString();

        if (_assignedTechnicianUsername != null) {
          final match = _technicians
              .where((t) => t.username == _assignedTechnicianUsername);
          if (match.isNotEmpty) {
            _assignedTechnicianName = match.first.name;
          }
        }

        _selectedTechnicianUsername = _assignedTechnicianUsername;
        _appointmentDate =
            AppointmentDate.parse(_job?.appointmentDate) ?? DateTime.now();
      }

      await _refreshTechnicianWorkload();
    } catch (e) {
      debugPrint('Error loading data: $e');
      _showSnackBar('เกิดข้อผิดพลาดในการโหลดข้อมูล');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 🔄 นับงานของช่างแต่ละคนในวันนัดซ่อมที่เลือก
  Future<void> _refreshTechnicianWorkload() async {
    final date = _appointmentDate;
    if (date == null || _technicians.isEmpty) return;

    try {
      final counts = await DatabaseHelper.instance
          .getTechnicianJobCountsForDate(
        AppointmentDate.toDbText(date),
        excludeRepairId: widget.repairId,
      );

      _technicians = _technicians
          .map((t) => t.copyWith(jobsOnSelectedDate: counts[t.username] ?? 0))
          .toList();

      final selected = _selectedTechnicianUsername;
      if (selected != null) {
        final match = _technicians.where((t) => t.username == selected);
        if (match.isNotEmpty && match.first.isFull) {
          _selectedTechnicianUsername = null;
        }
      }
    } catch (e) {
      debugPrint('Error loading technician workload: $e');
    }
  }

  /// 📅 เปิดปฏิทินให้เลือกวันนัดซ่อม
  Future<bool> _pickAppointmentDate() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year, now.month, now.day);
    final initial = _appointmentDate ?? firstDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(firstDate) ? firstDate : initial,
      firstDate: firstDate,
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: 'เลือกวันนัดซ่อม',
      cancelText: 'ยกเลิก',
      confirmText: 'เลือกวันนี้',
      fieldLabelText: 'วันนัดซ่อม',
    );

    if (picked == null || !mounted) return false;

    setState(() {
      _appointmentDate = picked;
      _isCheckingQuota = true;
    });

    await _refreshTechnicianWorkload();

    if (!mounted) return false;
    setState(() => _isCheckingQuota = false);
    return true;
  }

  /// ⏰ เปิดนาฬิกาให้เลือกเวลานัดหมาย
  Future<void> _pickAppointmentTime() async {
    final initial = _appointmentTime ?? const TimeOfDay(hour: 9, minute: 0);

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'เลือกเวลานัดหมาย',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );

    if (picked != null && mounted) {
      setState(() => _appointmentTime = picked);
    }
  }

  /// 👆 แตะที่ชื่อช่าง — เลือกช่างได้ทันที ไม่บังคับเด้งปฏิทิน
  void _onTechnicianTap(TechnicianItem tech) {
    if (tech.isFull) {
      _showSnackBar(
        'วันที่เลือก ${tech.name} มีงานครบ '
        '${DatabaseHelper.maxJobsPerTechnicianPerDay} งานแล้ว '
        'กรุณาเลือกช่างคนอื่นหรือเปลี่ยนวันนัดซ่อม',
      );
      return;
    }
    setState(() => _selectedTechnicianUsername = tech.username);
  }

  /// 💾 บันทึกการมอบหมายช่าง
  Future<void> _handleAssign() async {
    if (_selectedTechnicianUsername == null) {
      _showSnackBar('กรุณาเลือกช่างก่อนกดมอบหมาย');
      return;
    }

    final currentAdmin = Session.currentUsername;
    if (currentAdmin.isEmpty) {
      _showSnackBar('เซสชันหมดอายุ กรุณาล็อกอินใหม่อีกครั้ง');
      return;
    }

    if (_appointmentDate == null) {
      _showSnackBar('กรุณาเลือกวันนัดซ่อมก่อนมอบหมายงาน');
      return;
    }

    final latestCounts = await DatabaseHelper.instance
        .getTechnicianJobCountsForDate(
      AppointmentDate.toDbText(_appointmentDate!),
      excludeRepairId: widget.repairId,
    );
    final currentLoad = latestCounts[_selectedTechnicianUsername!] ?? 0;
    if (currentLoad >= DatabaseHelper.maxJobsPerTechnicianPerDay) {
      _showSnackBar(
        'ช่างคนนี้มีงานครบ ${DatabaseHelper.maxJobsPerTechnicianPerDay} '
        'งานในวันที่เลือกแล้ว กรุณาเลือกใหม่',
      );
      await _refreshTechnicianWorkload();
      if (mounted) setState(() {});
      return;
    }

    setState(() => _isAssigning = true);

    try {
      final dbHelper = DatabaseHelper.instance;
      final formattedTime = _appointmentTime != null
          ? '${_appointmentTime!.hour.toString().padLeft(2, '0')}:${_appointmentTime!.minute.toString().padLeft(2, '0')}'
          : '09:00';

      // 1. มอบหมายช่าง
      await dbHelper.assignTechnicianToRepair(
        repairId: widget.repairId,
        techUsername: _selectedTechnicianUsername!,
        adminUsername: currentAdmin,
        appointmentDate: AppointmentDate.toDbText(_appointmentDate!),
      );

      // 2. อัปเดตข้อมูลแอดมิน + เวลานัดหมาย
      final adminProfile = await dbHelper.getAdminProfile(currentAdmin);
      await dbHelper.updateRepair(widget.repairId, {
        if (adminProfile != null) ...{
          'admin_name': adminProfile['admin_name'],
          'admin_code': adminProfile['admin_code'],
        },
        'appointment_time': formattedTime,
      });

      // 3. แจ้งเตือนช่าง (ระบุทั้งวันและเวลา)
      if (_job != null) {
        await dbHelper.createNotification({
          'user_username': _selectedTechnicianUsername!,
          'role': 'TECHNICIAN',
          'title': 'ได้รับมอบหมายงานใหม่',
          'message':
              'คุณได้รับมอบหมายงานซ่อม ${_job!.ticketId} (${_job!.machineCode}) '
              'นัดซ่อมวันที่ ${AppointmentDate.toDisplay(_appointmentDate!)} เวลา $formattedTime น.',
          'type': 'REPAIR_ASSIGNED',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error assigning technician: $e');
      if (mounted) {
        setState(() => _isAssigning = false);
        _showSnackBar('เกิดข้อผิดพลาดในการบันทึกข้อมูล');
      }
    }
  }

// ==========================================
// SECTION 5: ACTIONS & UTILITIES
// ==========================================

  void _openTrackingMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminTrackingPage(repairId: widget.repairId),
      ),
    );
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    if (phoneNumber.isEmpty || phoneNumber == '-') {
      _showSnackBar('ไม่พบเบอร์โทรศัพท์ลูกค้า');
      return;
    }

    final Uri phoneUri =
        Uri(scheme: 'tel', path: phoneNumber.replaceAll(RegExp(r'\s+'), ''));

    try {
      if (await canLaunchUrl(phoneUri)) {
        await launchUrl(phoneUri);
      } else {
        _showSnackBar('ไม่สามารถเปิดแอปโทรศัพท์ได้');
      }
    } catch (e) {
      _showSnackBar('เกิดข้อผิดพลาดในการกดโทรออก');
    }
  }

  void _showImagePreview(BuildContext context, String path) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: path.startsWith('http')
                  ? Image.network(
                      path,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 80),
                    )
                  : Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 80),
                    ),
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(fontFamily: AppStyles.fontFamily)),
      ),
    );
  }

// ==========================================
// SECTION 6: BUILD METHOD
// ==========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: 'ใบแจ้งซ่อม #${widget.repairId}',
              showBack: true,
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _job == null
                      ? const Center(
                          child: Text('ไม่พบข้อมูลใบแจ้งซ่อม',
                              style:
                                  TextStyle(fontFamily: AppStyles.fontFamily)))
                      : ListView(
                          padding: const EdgeInsets.all(20),
                          children: [
                            _JobInfoCard(
                              job: _job!,
                              onMap: _openTrackingMap,
                              onCall: () =>
                                  _makePhoneCall(_job!.customerPhone),
                              onImageTap: (path) =>
                                  _showImagePreview(context, path),
                            ),
                            if (_job!.hasReport) ...[
                              const SizedBox(height: 20),
                              _RepairReportCard(
                                job: _job!,
                                onImageTap: (path) =>
                                    _showImagePreview(context, path),
                              ),
                            ],
                            if (_job!.status != RepairStatus.completed) ...[
                              const SizedBox(height: 20),
                              _AssignCard(
                                technicians: _technicians,
                                selectedTechnicianUsername:
                                    _selectedTechnicianUsername,
                                assignedTechnicianName:
                                    _assignedTechnicianName,
                                appointmentDate: _appointmentDate,
                                appointmentTime: _appointmentTime,
                                formattedTime: _formatTimeOfDay(_appointmentTime),
                                isAssigning: _isAssigning,
                                isCheckingQuota: _isCheckingQuota,
                                onTechnicianTap: _onTechnicianTap,
                                onPickDate: _pickAppointmentDate,
                                onPickTime: _pickAppointmentTime,
                                onAssign: _handleAssign,
                              ),
                            ],
                            const SizedBox(height: 20),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                style: AppStyles.primaryButton,
                                onPressed: () async {
                                  final saved = await Navigator.push<bool>(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdminCreateInvoicePage(
                                        initialRepairId:
                                            widget.repairId.toString(),
                                        initialTicketId: _job!.ticketId,
                                        initialCustomerName:
                                            _job!.customerName,
                                        initialCustomerPhone:
                                            _job!.customerPhone,
                                        initialAddress: _job!.address,
                                      ),
                                    ),
                                  );
                                  if (saved == true) _loadDataFromDatabase();
                                },
                                icon: const Icon(Icons.receipt_long),
                                label: const Text('ออกบิล'),
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

// ==========================================
// SECTION 7: SUB-WIDGETS
// ==========================================

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
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
          )
        ],
      ),
      child: child,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: AppColors.textMain,
            fontSize: 14,
            fontFamily: AppStyles.fontFamily,
          ),
          children: [
            TextSpan(
              text: '$label : ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobInfoCard extends StatelessWidget {
  final AdminJobInfo job;
  final VoidCallback onMap;
  final VoidCallback onCall;
  final ValueChanged<String> onImageTap;

  const _JobInfoCard({
    required this.job,
    required this.onMap,
    required this.onCall,
    required this.onImageTap,
  });

  @override
  Widget build(BuildContext context) {
    final displayDate = job.appointmentTime.isNotEmpty
        ? '${job.appointmentDate} (${job.appointmentTime} น.)'
        : job.appointmentDate;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'รายละเอียดงาน',
            textAlign: TextAlign.center,
            style: AppStyles.title.copyWith(
              color: AppColors.primary,
              fontSize: 20,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 16),
          _InfoRow(label: 'เลขแจ้งซ่อม', value: job.ticketId),
          _InfoRow(label: 'เครื่อง / รหัส', value: job.machineCode),
          _InfoRow(label: 'อาการ / รายละเอียด', value: job.description),
          const SizedBox(height: 6),

          Row(
            children: [
              const Text(
                'สถานะ : ',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: RepairStatusHelper.getBgColor(job.status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.circle,
                      size: 7,
                      color: RepairStatusHelper.getTextColor(job.status),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      job.status.label,
                      style: TextStyle(
                        color: RepairStatusHelper.getTextColor(job.status),
                        fontSize: 12,
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoRow(label: 'ชื่อลูกค้า', value: job.customerName),

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 14,
                        fontFamily: AppStyles.fontFamily,
                      ),
                      children: [
                        const TextSpan(
                          text: 'เบอร์ : ',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: job.customerPhone,
                          style: const TextStyle(fontWeight: FontWeight.w400),
                        ),
                      ],
                    ),
                  ),
                ),
                if (job.customerPhone != '-')
                  InkWell(
                    onTap: onCall,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone,
                        color: Colors.green,
                        size: 18,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          _InfoRow(label: 'ที่อยู่', value: job.address),
          _InfoRow(label: 'วัน-เวลานัดซ่อม', value: displayDate),
          const SizedBox(height: 14),
          const Text(
            'รูปภาพประกอบ (แตะเพื่อขยาย)',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 8),

          job.images.isEmpty
              ? Container(
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'ไม่มีรูปภาพแนบมา',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                )
              : SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: job.images.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 10),
                    itemBuilder: (context, index) => GestureDetector(
                      onTap: () => onImageTap(job.images[index]),
                      child: _photo(job.images[index]),
                    ),
                  ),
                ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onMap,
              style: AppStyles.primaryButton.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              icon: const Icon(Icons.near_me_outlined, size: 18),
              label: const Text('ดูตำแหน่ง/เส้นทางในแอป',
                  style: TextStyle(fontFamily: AppStyles.fontFamily)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _photo(String path) {
    Widget imageWidget;

    if (path.startsWith('http')) {
      imageWidget = Image.network(
        path,
        width: 80,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
      );
    } else {
      imageWidget = Image.file(
        File(path),
        width: 80,
        height: 100,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _imagePlaceholder(),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: imageWidget,
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: 80,
      height: 100,
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}

class _RepairReportCard extends StatelessWidget {
  final AdminJobInfo job;
  final ValueChanged<String> onImageTap;

  const _RepairReportCard({required this.job, required this.onImageTap});

  @override
  Widget build(BuildContext context) {
    final photos = <MapEntry<String, String>>[
      if (job.reportBeforePhoto.isNotEmpty)
        MapEntry('ก่อนซ่อม', job.reportBeforePhoto),
      if (job.reportAfterPhoto.isNotEmpty)
        MapEntry('หลังซ่อม', job.reportAfterPhoto),
      if (job.reportSlipPhoto.isNotEmpty)
        MapEntry('สลิปโอนเงิน', job.reportSlipPhoto),
    ];

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppColors.greenBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.fact_check_outlined,
                    size: 18, color: AppColors.greenText),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'รายงานการซ่อมจากช่าง',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),
            ],
          ),
          if (job.reportSubmittedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'ส่งรายงานเมื่อ ${formatNotificationDateTime(job.reportSubmittedAt)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (job.reportFormCode.isNotEmpty) ...[
            _InfoRow(label: 'รหัสฟอร์มซ่อม', value: job.reportFormCode),
            const SizedBox(height: 4),
          ],
          if (job.reportProblemDetail.isNotEmpty) ...[
            const Text(
              'รายละเอียดปัญหา/การซ่อม',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              job.reportProblemDetail,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: AppStyles.fontFamily,
                color: AppColors.textMain,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (photos.isNotEmpty) ...[
            const Text(
              'รูปภาพประกอบการปิดงาน (แตะเพื่อขยาย)',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 110,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final entry = photos[index];
                  return GestureDetector(
                    onTap: () => onImageTap(entry.value),
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            entry.value,
                            width: 80,
                            height: 100,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              width: 80,
                              height: 100,
                              color: Colors.grey.shade200,
                              child: const Icon(Icons.broken_image,
                                  color: Colors.grey),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSubtitle,
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 📌 การ์ดมอบหมายช่าง — แยกกล่องเลือกวัน และกล่องเลือกเวลาออกจากกันชัดเจน
class _AssignCard extends StatelessWidget {
  final List<TechnicianItem> technicians;
  final String? selectedTechnicianUsername;
  final String? assignedTechnicianName;
  final DateTime? appointmentDate;
  final TimeOfDay? appointmentTime;
  final String formattedTime;
  final bool isAssigning;
  final bool isCheckingQuota;
  final ValueChanged<TechnicianItem> onTechnicianTap;
  final Future<bool> Function() onPickDate;
  final Future<void> Function() onPickTime;
  final VoidCallback onAssign;

  const _AssignCard({
    required this.technicians,
    required this.selectedTechnicianUsername,
    required this.assignedTechnicianName,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.formattedTime,
    required this.isAssigning,
    required this.isCheckingQuota,
    required this.onTechnicianTap,
    required this.onPickDate,
    required this.onPickTime,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    final hasTechnicians = technicians.isNotEmpty;
    final availableCount = technicians.where((t) => !t.isFull).length;
    final canAssign = selectedTechnicianUsername != null &&
        appointmentDate != null &&
        !isAssigning;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'มอบหมายช่าง',
            textAlign: TextAlign.center,
            style: AppStyles.title.copyWith(
              color: AppColors.textHeading,
              fontSize: 20,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 16),

          if (assignedTechnicianName != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.greenBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: AppColors.greenText, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'มอบหมายให้ $assignedTechnicianName แล้ว',
                      style: const TextStyle(
                        color: AppColors.greenText,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // 📅 วันและเวลานัดหมาย (วางคู่กัน 2 ช่อง)
          Row(
            children: [
              // ช่องเลือกวัน
              Expanded(
                flex: 6,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'วันนัดซ่อม',
                      style: AppStyles.inputLabel.copyWith(
                        fontSize: 13,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onPickDate(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_month_outlined,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  appointmentDate == null
                                      ? 'เลือกวัน'
                                      : AppointmentDate.toDisplay(
                                          appointmentDate!),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: AppStyles.fontFamily,
                                    fontWeight: FontWeight.w600,
                                    color: appointmentDate == null
                                        ? AppColors.textHint
                                        : AppColors.textMain,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // ช่องเลือกเวลา
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เวลานัดหมาย',
                      style: AppStyles.inputLabel.copyWith(
                        fontSize: 13,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => onPickTime(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.access_time_outlined,
                                  size: 18, color: AppColors.primary),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  formattedTime,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontFamily: AppStyles.fontFamily,
                                    fontWeight: FontWeight.w600,
                                    color: appointmentTime == null
                                        ? AppColors.textHint
                                        : AppColors.textMain,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // 👷 รายชื่อช่าง
          Row(
            children: [
              Expanded(
                child: Text(
                  'เลือกช่างที่จะรับผิดชอบงานนี้',
                  style: AppStyles.inputLabel.copyWith(
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),
              if (hasTechnicians)
                Text(
                  'ว่าง $availableCount/${technicians.length} คน',
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: AppStyles.fontFamily,
                    color: AppColors.textSubtitle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'ช่าง 1 คนรับได้ไม่เกิน '
            '${DatabaseHelper.maxJobsPerTechnicianPerDay} งานต่อวัน',
            style: TextStyle(
              fontSize: 12,
              fontFamily: AppStyles.fontFamily,
              color: AppColors.textHint,
            ),
          ),
          const SizedBox(height: 10),

          if (isCheckingQuota)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (!hasTechnicians)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'ไม่พบรายชื่อช่างในระบบ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppStyles.fontFamily,
                  color: AppColors.textSubtitle,
                ),
              ),
            )
          else
            for (var i = 0; i < technicians.length; i++)
              Padding(
                padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
                child: _TechnicianTile(
                  tech: technicians[i],
                  selected:
                      technicians[i].username == selectedTechnicianUsername,
                  onTap: () => onTechnicianTap(technicians[i]),
                ),
              ),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: canAssign ? onAssign : null,
              style: AppStyles.primaryButton.copyWith(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              child: isAssigning
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : Text(
                      assignedTechnicianName == null
                          ? 'มอบหมาย'
                          : 'มอบหมายใหม่',
                      style: AppStyles.buttonText.copyWith(
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TechnicianTile extends StatelessWidget {
  final TechnicianItem tech;
  final bool selected;
  final VoidCallback onTap;

  const _TechnicianTile({
    required this.tech,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final full = tech.isFull;
    const max = DatabaseHelper.maxJobsPerTechnicianPerDay;

    final borderColor = full
        ? AppColors.border
        : selected
            ? AppColors.primary
            : AppColors.border;

    final bgColor = full
        ? AppColors.surfaceAlt
        : selected
            ? AppColors.primary.withValues(alpha: 0.05)
            : AppColors.background;

    final nameColor = full ? AppColors.textHint : AppColors.textMain;

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: full ? null : onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor,
              width: selected && !full ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                full
                    ? Icons.block
                    : selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                size: 20,
                color: full
                    ? AppColors.textHint
                    : selected
                        ? AppColors.primary
                        : AppColors.textSubtitle,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      full ? '${tech.name} (งานเต็ม)' : tech.name,
                      style: TextStyle(
                        fontSize: 14,
                        fontFamily: AppStyles.fontFamily,
                        fontWeight: FontWeight.w600,
                        color: nameColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'งานในวันที่เลือก ${tech.jobsOnSelectedDate}/$max',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: AppStyles.fontFamily,
                        color:
                            full ? AppColors.textHint : AppColors.textSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: full ? AppColors.redBg : AppColors.greenBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  full ? 'งานเต็ม' : 'ว่าง',
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: AppStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                    color: full ? AppColors.redText : AppColors.greenText,
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