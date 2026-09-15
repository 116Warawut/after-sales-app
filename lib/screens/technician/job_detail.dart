import 'package:flutter/material.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/screens/customer/customer_job_detail.dart'
    show CustomerJobInfo;
import 'package:after_sales/screens/shared/job_detail_ui.dart';
import 'package:after_sales/screens/technician/customer_tracking.dart';
import 'package:after_sales/screens/technician/report.dart';
import 'package:after_sales/screens/technician/spare_part_tec_viewer.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';

/// {@template jobs_detail}
/// จุดเข้าใช้งานเดิม (ยังคงชื่อไว้เพื่อไม่ต้องแก้จุดเรียกใช้เดิมทั้งหมด)
/// {@endtemplate}
class JobsDetail extends StatelessWidget {
  final int repairId;
  const JobsDetail({super.key, required this.repairId});

  @override
  Widget build(BuildContext context) {
    return JobDetailPage(repairId: repairId);
  }
}

/// {@template job_detail_page}
/// หน้ารายละเอียดงานซ่อมของช่าง ([JobDetailPage]) — ดึงข้อมูลจริงจาก SQLite
/// ผ่าน [repairId] และมี action จริง: รับงาน / บันทึกราคาประเมิน / ส่งรายงานซ่อม
/// (ซึ่งจะตั้งสถานะเป็น "เสร็จแล้ว" ให้อัตโนมัติ) / ติดต่อแอดมิน / ดูแผนที่
/// {@endtemplate}
class JobDetailPage extends StatefulWidget {
  final int repairId;
  const JobDetailPage({super.key, required this.repairId});

  @override
  State<JobDetailPage> createState() => _JobDetailPageState();
}

/// สถานะของงาน แบ่งเป็นช่วงสำหรับตัดสินใจว่าจะโชว์ action ไหน
enum _Stage { waiting, inProgress, problem, done }

class _JobDetailPageState extends State<JobDetailPage> {
  bool _loading = true;
  CustomerJobInfo _job = CustomerJobInfo.placeholder;
  String _customerUsername = '';
  String _adminUsername = '';

  final TextEditingController _priceController = TextEditingController();
  bool _isAccepting = false;
  bool _isSavingPrice = false;
  bool _isMarkingProblem = false;
  bool _isCancellingProblem = false;

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  @override
  void dispose() {
    _priceController.dispose();
    super.dispose();
  }

  _Stage get _stage {
    final status = _job.status;
    if (status.contains('เสร็จ')) return _Stage.done;
    if (status.contains('มีปัญหา')) return _Stage.problem;
    if (status.contains('กำลังดำเนินการ') || status.contains('กำลังซ่อม')) {
      return _Stage.inProgress;
    }
    return _Stage.waiting;
  }

  Future<void> _loadJob() async {
    setState(() => _loading = true);

    try {
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);

      if (repair == null) {
        if (!mounted) return;
        setState(() {
          _job = CustomerJobInfo.placeholder;
          _loading = false;
        });
        return;
      }

      final customer = await db.DatabaseHelper.instance.getCustomerProfile(
        toStringOrNull(repair['customer_username']) ?? '',
      );

      List<String> imageList = [];
      final rawImages = repair['images'] ?? repair['image_path'];
      if (rawImages is String && rawImages.isNotEmpty) {
        imageList = rawImages
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      } else if (rawImages is List) {
        imageList = rawImages.map((e) => e.toString()).toList();
      }

      // 🕒 ดึงวันและเวลานัดหมายมาประกอบกัน
      final dateStr = toStringOrNull(repair['date']) ?? '-';
      final timeStr = toStringOrNull(repair['appointment_time']) ??
          toStringOrNull(repair['time']) ??
          '';
      final appointmentDisplay = (timeStr.isNotEmpty && dateStr != '-')
          ? '$dateStr เวลา $timeStr น.'
          : dateStr;

      if (!mounted) return;
      setState(() {
        _job = CustomerJobInfo(
          id: toIntOrNull(repair['id']),
          ticketId: toStringOrNull(repair['ticketNo']) ?? '-',
          machineCode: toIntOrNull(repair['machine_id'])?.toString() ??
              toStringOrNull(repair['machine_id']) ??
              '-',
          modelName: toStringOrNull(repair['machine']) ?? '-',
          description: toStringOrNull(repair['detail']) ?? '-',
          status: toStringOrNull(repair['status']) ?? 'รอจัดสรรช่าง',
          customerName: customer != null
              ? '${customer['name'] ?? ''} ${customer['surname'] ?? ''}'.trim()
              : '-',
          customerPhone: toStringOrNull(customer?['phone']) ?? '-',
          address: toStringOrNull(repair['location']) ?? '-',
          appointmentDate: appointmentDisplay,
          adminName: toStringOrNull(repair['admin_name']) ?? 'ยังไม่มีแอดมินดูแล',
          adminCode: toStringOrNull(repair['admin_code']) ?? '-',
          adminPhone: toStringOrNull(repair['admin_phone']) ?? '-',
          technicianName: '-',
          technicianCode: '-',
          technicianPhone: '-',
          images: imageList,
          billId: toStringOrNull(repair['bill_id']) ?? '-',
          totalPrice: toDoubleOrNull(repair['total_price']) ?? 0,
          isPaid: toIntOrNull(repair['is_paid']) == 1 ||
              repair['is_paid'] == true,
        );
        _customerUsername = toStringOrNull(repair['customer_username']) ?? '';
        _adminUsername = toStringOrNull(repair['admin_username']) ?? '';
        final estimatedPrice = toDoubleOrNull(repair['estimated_price']) ?? 0;
        _priceController.text =
            estimatedPrice > 0 ? estimatedPrice.toStringAsFixed(0) : '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    }
  }

  // ✅ รับงาน / เริ่มดำเนินการซ่อม
  Future<void> _acceptJob() async {
    setState(() => _isAccepting = true);
    try {
      await db.DatabaseHelper.instance.updateRepairStatus(
        widget.repairId,
        'กำลังดำเนินการ',
        techUsername: db.Session.currentUsername,
      );
      if (_customerUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _customerUsername,
          'role': 'CUSTOMER',
          'title': 'ช่างเริ่มดำเนินการซ่อมแล้ว',
          'message': 'งานซ่อม ${_job.ticketId} กำลังดำเนินการโดยช่าง',
          'type': 'REPAIR_IN_PROGRESS',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('รับงานไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  // ⚠️ แจ้งว่างานนี้ "มีปัญหา / ต้องตรวจสอบ"
  Future<void> _markProblem() async {
    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.redBg,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.report_problem_outlined,
                    color: AppColors.redText, size: 26),
              ),
              const SizedBox(height: 14),
              const Text(
                'แจ้งว่างานนี้มีปัญหา / ต้องตรวจสอบ',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'ระบุเหตุผลสั้น ๆ ให้แอดมินทราบ (ไม่บังคับ) สถานะงานจะเปลี่ยนเป็น '
                '"มีปัญหา" จนกว่าจะกดยกเลิกสถานะนี้',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textSubtitle,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: noteController,
                maxLines: 3,
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: AppStyles.fontFamily,
                ),
                decoration: AppStyles.inputDecoration(
                  hintText: 'เช่น รออะไหล่, ติดต่อลูกค้าไม่ได้',
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ไม่ใช่ตอนนี้'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.redText,
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('แจ้งปัญหา',
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) {
      noteController.dispose();
      return;
    }

    final note = noteController.text.trim();
    noteController.dispose();

    setState(() => _isMarkingProblem = true);
    try {
      await db.DatabaseHelper.instance.markRepairProblem(
        widget.repairId,
        techUsername: db.Session.currentUsername,
        note: note,
      );
      if (_adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _adminUsername,
          'role': 'ADMIN',
          'title': 'ช่างแจ้งปัญหางานซ่อม',
          'message': note.isNotEmpty
              ? 'งานซ่อม ${_job.ticketId} มีปัญหา: $note'
              : 'งานซ่อม ${_job.ticketId} ถูกแจ้งว่ามีปัญหา / ต้องตรวจสอบ',
          'type': 'REPAIR_PROBLEM',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('แจ้งปัญหาไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isMarkingProblem = false);
    }
  }

  // ✅ ยกเลิกสถานะ "มีปัญหา" กลับไปดำเนินการต่อ
  Future<void> _cancelProblem() async {
    final confirmed = await showJobConfirmDialog(
      context,
      title: 'ยกเลิกสถานะปัญหา?',
      message: 'งานจะกลับไปเป็นสถานะก่อนหน้า (ปกติคือ "กำลังดำเนินการ")',
      confirmLabel: 'ยกเลิกสถานะปัญหา',
      icon: Icons.undo_rounded,
    );
    if (!confirmed) return;

    setState(() => _isCancellingProblem = true);
    try {
      await db.DatabaseHelper.instance.resolveRepairProblem(widget.repairId);
      if (_adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _adminUsername,
          'role': 'ADMIN',
          'title': 'ยกเลิกสถานะปัญหาแล้ว',
          'message': 'งานซ่อม ${_job.ticketId} กลับมาดำเนินการต่อตามปกติแล้ว',
          'type': 'REPAIR_PROBLEM_RESOLVED',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('ยกเลิกสถานะไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isCancellingProblem = false);
    }
  }

  Future<void> _savePrice() async {
    final price = double.tryParse(_priceController.text.trim());
    if (price == null || price < 0) {
      _snack('กรุณากรอกราคาที่ถูกต้อง');
      return;
    }
    setState(() => _isSavingPrice = true);
    try {
      await db.DatabaseHelper.instance
          .updateRepair(widget.repairId, {'estimated_price': price});
      if (!mounted) return;
      _snack('บันทึกราคาประเมินแล้ว');
    } catch (e) {
      if (!mounted) return;
      _snack('บันทึกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isSavingPrice = false);
    }
  }

  // 📝 เปิดฟอร์มส่งรายงานซ่อม
  Future<void> _openReportForm() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ReportPage(repairId: widget.repairId),
      ),
    );
    if (result == true) {
      if (_customerUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _customerUsername,
          'role': 'CUSTOMER',
          'title': 'งานซ่อมเสร็จสิ้นแล้ว',
          'message': 'งานซ่อม ${_job.ticketId} เสร็จสิ้นแล้ว รอออกใบแจ้งหนี้',
          'type': 'REPAIR_DONE',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      if (_adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _adminUsername,
          'role': 'ADMIN',
          'title': 'ช่างส่งรายงานซ่อมแล้ว',
          'message': 'งานซ่อม ${_job.ticketId} เสร็จสิ้นแล้ว กรุณาออกใบแจ้งหนี้',
          'type': 'REPAIR_DONE',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      _loadJob();
    }
  }

  // 🗺️ เปิดหน้าติดตามตำแหน่ง/แผนที่จริง
  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomerTrackingPage(repairId: widget.repairId),
      ),
    );
  }

  // 💬 ส่งข้อความหาแอดมิน
  void _messageAdmin() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          role: UserRole.technician,
          repairId: widget.repairId.toString(),
        ),
      ),
    );
  }

  // 🧰 เปิดหน้าเบิกอะไหล่
  void _openRequestParts() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RequestPartScreen(repairId: widget.repairId),
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: AppStyles.fontFamily),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return JobDetailScaffold(
      header: const AppHeader(title: 'รายละเอียดงาน', showBack: true),
      isLoading: _loading,
      onRefresh: _loadJob,
      children: [
        _JobInfoCard(job: _job, onMap: _openMap),
        JobContactCard(
          title: 'แอดมิน',
          roleLabel: 'แอดมินผู้ดูแล',
          name: _job.adminName,
          code: _job.adminCode,
          onMessage: _messageAdmin,
        ),
        _StageActionCard(
          stage: _stage,
          priceController: _priceController,
          isAccepting: _isAccepting,
          isSavingPrice: _isSavingPrice,
          isMarkingProblem: _isMarkingProblem,
          isCancellingProblem: _isCancellingProblem,
          onAccept: _acceptJob,
          onSavePrice: _savePrice,
          onOpenReport: _openReportForm,
          onRequestParts: _openRequestParts,
          onMarkProblem: _markProblem,
          onCancelProblem: _cancelProblem,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _JobInfoCard extends StatelessWidget {
  final CustomerJobInfo job;
  final VoidCallback onMap;
  const _JobInfoCard({required this.job, required this.onMap});

  @override
  Widget build(BuildContext context) {
    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JobSectionTitle('รายละเอียดงาน'),
          const SizedBox(height: 16),
          JobInfoRow(label: 'เลขแจ้งซ่อม', value: job.ticketId),
          JobInfoRow(label: 'เครื่อง / รหัส', value: job.modelName),
          JobInfoRow(label: 'อาการ / รายละเอียด', value: job.description),
          const SizedBox(height: 6),
          JobStatusRow(status: job.status),
          const SizedBox(height: 8),
          JobInfoRow(label: 'ชื่อลูกค้า', value: job.customerName),
          JobPhoneRow(phone: job.customerPhone),
          JobInfoRow(label: 'ที่อยู่', value: job.address),
          // 🕒 แสดงผลเป็น "วัน-เวลานัดซ่อม"
          JobInfoRow(label: 'วัน-เวลานัดซ่อม', value: job.appointmentDate),
          const SizedBox(height: 14),
          JobImageStrip(images: job.images),
          const SizedBox(height: 16),
          JobPrimaryButton(
            label: 'ดูแผนที่',
            icon: Icons.map_outlined,
            onPressed: onMap,
            verticalPadding: 12,
          ),
        ],
      ),
    );
  }
}

/// การ์ด action ที่เปลี่ยนหน้าตาไปตามสถานะงาน
class _StageActionCard extends StatelessWidget {
  final _Stage stage;
  final TextEditingController priceController;
  final bool isAccepting;
  final bool isSavingPrice;
  final bool isMarkingProblem;
  final bool isCancellingProblem;
  final VoidCallback onAccept;
  final VoidCallback onSavePrice;
  final VoidCallback onOpenReport;
  final VoidCallback onRequestParts;
  final VoidCallback onMarkProblem;
  final VoidCallback onCancelProblem;

  const _StageActionCard({
    required this.stage,
    required this.priceController,
    required this.isAccepting,
    required this.isSavingPrice,
    required this.isMarkingProblem,
    required this.isCancellingProblem,
    required this.onAccept,
    required this.onSavePrice,
    required this.onOpenReport,
    required this.onRequestParts,
    required this.onMarkProblem,
    required this.onCancelProblem,
  });

  static const _hintStyle = TextStyle(
    fontSize: 13,
    color: AppColors.textSubtitle,
    fontFamily: AppStyles.fontFamily,
  );

  @override
  Widget build(BuildContext context) {
    switch (stage) {
      case _Stage.waiting:
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('เริ่มงานซ่อม', primary: false),
              const SizedBox(height: 16),
              const Text(
                'กดรับงานเมื่อพร้อมเริ่มดำเนินการซ่อม สถานะจะเปลี่ยนเป็น "กำลังดำเนินการ"',
                textAlign: TextAlign.center,
                style: _hintStyle,
              ),
              const SizedBox(height: 20),
              JobPrimaryButton(
                label: 'รับงาน / เริ่มดำเนินการ',
                onPressed: onAccept,
                isLoading: isAccepting,
              ),
            ],
          ),
        );

      case _Stage.inProgress:
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('ค่าใช้จ่าย & รายงาน', primary: false),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ราคาที่ประเมินได้ (รวม)',
                  style: AppStyles.inputLabel.copyWith(
                    fontSize: 13,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'กรอกราคารวมเพื่อส่งให้แอดมินออกบิล',
                style: _hintStyle,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: priceController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: AppStyles.fontFamily,
                ),
                decoration: AppStyles.inputDecoration(hintText: '0').copyWith(
                  prefixText: '฿ ',
                  suffixText: 'บาท',
                ),
              ),
              const SizedBox(height: 12),
              JobSecondaryButton(
                label: 'บันทึกราคาประเมิน',
                onPressed: onSavePrice,
                isLoading: isSavingPrice,
              ),
              const SizedBox(height: 16),
              JobSecondaryButton(
                label: 'เบิกอะไหล่สำหรับงานนี้',
                icon: Icons.inventory_2_outlined,
                onPressed: onRequestParts,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  onPressed: isMarkingProblem ? null : onMarkProblem,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.redText,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: isMarkingProblem
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.redText),
                        )
                      : const Icon(Icons.report_problem_outlined, size: 18),
                  label: const Text('แจ้งว่ามีปัญหา / ต้องตรวจสอบ'),
                ),
              ),
              const SizedBox(height: 8),
              const SizedBox(height: 20),
              const Divider(color: AppColors.border, height: 1),
              const SizedBox(height: 16),
              const Text(
                'เมื่อซ่อมเสร็จแล้ว กดส่งรายงานเพื่อปิดงาน (สถานะจะเปลี่ยนเป็น "เสร็จแล้ว" ให้อัตโนมัติ)',
                style: _hintStyle,
              ),
              const SizedBox(height: 12),
              JobPrimaryButton(
                label: 'ส่งรายงานซ่อม',
                icon: Icons.assignment_turned_in_outlined,
                onPressed: onOpenReport,
              ),
            ],
          ),
        );

      case _Stage.problem:
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('มีปัญหา / ต้องตรวจสอบ', primary: false),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.redBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.report_problem_outlined,
                        color: AppColors.redText, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'งานนี้ถูกแจ้งว่ามีปัญหา / ต้องตรวจสอบ แอดมินได้รับแจ้งแล้ว',
                        style: TextStyle(
                          color: AppColors.redText,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'เมื่อแก้ปัญหาได้แล้ว กดยกเลิกสถานะนี้เพื่อกลับไปดำเนินการซ่อมต่อ',
                textAlign: TextAlign.center,
                style: _hintStyle,
              ),
              const SizedBox(height: 12),
              JobPrimaryButton(
                label: 'ยกเลิกสถานะปัญหา',
                icon: Icons.undo_rounded,
                onPressed: onCancelProblem,
                isLoading: isCancellingProblem,
              ),
            ],
          ),
        );

      case _Stage.done:
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('สรุปงาน', primary: false),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.greenBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.check_circle,
                        color: AppColors.greenText, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'งานนี้เสร็จสิ้นแล้ว ส่งรายงานเรียบร้อย',
                        style: TextStyle(
                          color: AppColors.greenText,
                          fontWeight: FontWeight.w600,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }
}