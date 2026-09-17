import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
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
enum _Stage { waiting, traveling, inProgress, problem, done }

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
  // 🆕 [ใหม่] สถานะคิวงานของช่างในวันนัดเดียวกัน (ใช้ล็อกปุ่ม "เริ่มดำเนินการ"
  // ให้กดได้เฉพาะงานที่ถึงคิวแล้วเท่านั้น — ดู getQueueInfo() ใน services.dart)
  int _queuePosition = 1;
  int _queueTotal = 1;
  bool _isArriving = false;

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
    // 🆕 [ใหม่] เช็ค "กำลังเดินทาง" ก่อน — เป็นขั้นตอนใหม่ระหว่าง "รอดำเนินการ"
    // กับ "กำลังซ่อม" (เดินทางไปหาลูกค้าแล้วแต่ยังไม่ได้ลงมือซ่อมจริง)
    if (status.contains('กำลังเดินทาง')) return _Stage.traveling;
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
          id: resolveRecordId(repair),
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

      // 🆕 [ใหม่] โหลดคิวงานแยกต่างหาก (ไม่บล็อก UI หลัก) เพื่อโชว์ว่าตอนนี้
      // งานนี้อยู่คิวที่เท่าไหร่ และล็อกปุ่ม "เริ่มดำเนินการ" ถ้ายังไม่ถึงคิว
      final repairIdForQueue = resolveRecordId(repair);
      if (repairIdForQueue != null) {
        try {
          final queueInfo =
              await db.DatabaseHelper.instance.getQueueInfo(repairIdForQueue);
          if (!mounted) return;
          setState(() {
            _queuePosition = queueInfo.position;
            _queueTotal = queueInfo.total;
          });
        } catch (_) {
          // เงียบไว้ — ถ้าเช็คคิวพลาด ปล่อยให้ปุ่มกดได้ตามค่า default (คิวที่ 1)
          // แล้วให้ markTechnicianTraveling() ฝั่ง services.dart เป็นด่านสุดท้าย
          // ที่บังคับเช็คคิวจริงอีกครั้งตอนกดปุ่ม
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    }
  }

  // ✅ [แก้ไข] เดิมกดปุ่มนี้แล้วเปลี่ยนสถานะตรงไปเป็น "กำลังดำเนินการ" ทันที
  // ข้ามขั้นตอน "กำลังเดินทาง" ไปเลย ตอนนี้เปลี่ยนเป็นเริ่มเดินทางก่อน (ตาม
  // คิวงานเท่านั้น — ดู markTechnicianTraveling() ใน services.dart) แล้วค่อยกด
  // "ถึงที่หมายแล้ว" (_confirmArrived) อีกทีตอนถึงบ้านลูกค้าจริง ๆ ถึงจะเปลี่ยน
  // เป็น "กำลังซ่อม"
  Future<void> _startTravel() async {
    if (_job.id == null) return;
    setState(() => _isAccepting = true);
    try {
      await db.DatabaseHelper.instance.markTechnicianTraveling(_job.id);
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('เริ่มเดินทางไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
  }

  // 🆕 [ใหม่] ช่างกดยืนยันว่าถึงที่หมาย (บ้าน/สถานที่ลูกค้า) แล้ว — เปลี่ยนสถานะ
  // จาก "กำลังเดินทาง" เป็น "กำลังซ่อม" และแจ้งเตือนลูกค้าอัตโนมัติ (ดู
  // markTechnicianArrived() ใน services.dart)
  Future<void> _confirmArrived() async {
    if (_job.id == null) return;
    setState(() => _isArriving = true);
    try {
      await db.DatabaseHelper.instance.markTechnicianArrived(_job.id);
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('ยืนยันถึงที่หมายไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isArriving = false);
    }
  }

  // ⚠️ แจ้งว่างานนี้ "มีปัญหา / ต้องตรวจสอบ"
  // 🆕 [ใหม่] เพิ่มช่องแนบรูปภาพประกอบ (สูงสุด 4 รูป ไม่บังคับ) นอกเหนือจาก
  // ข้อความเดิม — ฝั่งเว็บ (JobDetailModal.jsx -> getIssueReport()) เตรียมช่อง
  // แสดงรูปประกอบปัญหาไว้รอแล้วแต่ฝั่งแอปยังไม่เคยส่งรูปขึ้นไปเลย ใช้ image_picker
  // + CloudinaryService แบบเดียวกับหน้าส่งรายงานซ่อม (report.dart) และฟอร์ม
  // แจ้งซ่อมของลูกค้า (repair_form.dart) เพื่อให้ทุกฝ่ายเปิดดูรูปได้จากทุกเครื่อง
  Future<void> _markProblem() async {
    final noteController = TextEditingController();
    final picker = ImagePicker();
    final List<XFile> selectedPhotos = [];

    Future<void> pickPhoto(StateSetter setDialogState) async {
      if (selectedPhotos.length >= 4) {
        _snack('แนบรูปได้สูงสุด 4 รูป');
        return;
      }
      // 🐛 [แก้บัค] เดิมเปิด showModalBottomSheet นี้จากใน showDialog อีกที
      // (ป๊อปอัพซ้อนป๊อปอัพ) โดยไม่ระบุ useRootNavigator เลย ค่า default ของ
      // showModalBottomSheet คือ false (ใช้ Navigator ที่ใกล้ context ที่สุด)
      // แต่ showDialog ด้านนอกใช้ useRootNavigator: true (ค่า default ของมัน)
      // — ถ้าหน้านี้อยู่ใต้ Navigator ซ้อนกัน (เช่น bottom nav ที่มี Navigator
      // แยกต่อแท็บ) ทั้งสองป๊อปอัพเลยไปเปิดอยู่คนละ Navigator กัน ตัวเลือก
      // "ถ่ายภาพ/เลือกจากคลังภาพ" เลยไปโผล่อยู่ใน Overlay ของ Navigator ชั้นใน
      // (ต่ำกว่า) ทำให้ม่านมืดโปร่งแสงของ Dialog ชั้นนอกทับอยู่ด้านบน กดเลือก
      // อะไรไม่ได้เลยตามที่เจอ — บังคับให้ใช้ root Navigator เดียวกับ Dialog
      // เสมอ กันไม่ให้ไปเปิดคนละชั้นกันอีก
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        useRootNavigator: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (sheetCtx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('แนบรูปภาพประกอบปัญหา',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFamily: AppStyles.fontFamily)),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('ถ่ายภาพ'),
                onTap: () => Navigator.pop(sheetCtx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('เลือกจากคลังภาพ'),
                onTap: () => Navigator.pop(sheetCtx, ImageSource.gallery),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (source == null) return;
      try {
        final picked = await picker.pickImage(source: source, imageQuality: 80);
        if (picked == null) return;
        setDialogState(() => selectedPhotos.add(picked));
      } catch (e) {
        _snack('เลือกรูปไม่สำเร็จ: $e');
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
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
                    'ระบุเหตุผลและแนบรูปประกอบให้แอดมินทราบ (ไม่บังคับ) สถานะงานจะ'
                    'เปลี่ยนเป็น "มีปัญหา" จนกว่าจะกดยกเลิกสถานะนี้',
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
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'รูปภาพประกอบ (ไม่บังคับ, สูงสุด 4 รูป)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSubtitle,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < selectedPhotos.length; i++)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(selectedPhotos[i].path),
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () => setDialogState(
                                    () => selectedPhotos.removeAt(i)),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: const BoxDecoration(
                                    color: AppColors.redText,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close,
                                      color: Colors.white, size: 14),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (selectedPhotos.length < 4)
                        GestureDetector(
                          onTap: () => pickPhoto(setDialogState),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border),
                              color: AppColors.surfaceAlt,
                            ),
                            child: const Icon(Icons.add_a_photo_outlined,
                                color: AppColors.textSubtitle, size: 22),
                          ),
                        ),
                    ],
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
      // 📤 อัปโหลดรูปประกอบ (ถ้ามี) ขึ้น Cloudinary ก่อนเสมอ — เก็บแค่ path ไฟล์
      // ในเครื่องช่างจะทำให้แอดมิน/ลูกค้าที่เปิดดูจากเครื่องอื่นเห็นรูปไม่ได้
      // (บั๊กแบบเดียวกับที่เคยเจอในฟอร์มแจ้งซ่อม/รายงานซ่อม)
      List<String> photoUrls = [];
      if (selectedPhotos.isNotEmpty) {
        photoUrls = await CloudinaryService.uploadImages(selectedPhotos);
      }
      await db.DatabaseHelper.instance.markRepairProblem(
        widget.repairId,
        techUsername: db.Session.currentUsername,
        note: note,
        photoUrls: photoUrls,
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
          isArriving: _isArriving,
          queuePosition: _queuePosition,
          queueTotal: _queueTotal,
          onStartTravel: _startTravel,
          onArrived: _confirmArrived,
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
  // 🆕 [ใหม่] สถานะ/ข้อมูลสำหรับขั้นตอน "เริ่มเดินทาง" → "ถึงที่หมายแล้ว"
  final bool isArriving;
  final int queuePosition;
  final int queueTotal;
  final VoidCallback onStartTravel;
  final VoidCallback onArrived;
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
    required this.isArriving,
    required this.queuePosition,
    required this.queueTotal,
    required this.onStartTravel,
    required this.onArrived,
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
        // 🆕 [ใหม่] ล็อกปุ่มถ้ายังไม่ถึงคิวงานนี้ (ตำแหน่งที่ 1 ของคิววันนัด
        // เดียวกันเท่านั้นถึงจะเริ่มเดินทางได้ — ดู getQueueInfo() ใน
        // services.dart) กันช่างข้ามคิวไปเริ่มงานอื่นก่อนงานที่ควรทำก่อน
        final isMyTurn = queuePosition == 1;
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('เริ่มงานซ่อม', primary: false),
              const SizedBox(height: 16),
              Text(
                isMyTurn
                    ? 'กดเริ่มดำเนินการเมื่อพร้อมออกเดินทางไปหาลูกค้า สถานะจะ'
                        'เปลี่ยนเป็น "กำลังเดินทาง"'
                    : 'ยังไม่ถึงคิวงานนี้ (คิวที่ $queuePosition จาก $queueTotal '
                        'งานของวันนี้) — ต้องทำงานคิวก่อนหน้าให้เสร็จ/ถึงคิวก่อน '
                        'ถึงจะเริ่มงานนี้ได้',
                textAlign: TextAlign.center,
                style: isMyTurn
                    ? _hintStyle
                    : _hintStyle.copyWith(
                        color: AppColors.redText, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              JobPrimaryButton(
                label: 'เริ่มดำเนินการ',
                onPressed: isMyTurn ? onStartTravel : null,
                isLoading: isAccepting,
              ),
            ],
          ),
        );

      // 🆕 [ใหม่] ขั้นตอน "กำลังเดินทาง" — ช่างกำลังไปหาลูกค้า ยังไม่ได้ลงมือซ่อม
      // จริง กดยืนยัน "ถึงที่หมายแล้ว" เมื่อไปถึงบ้าน/สถานที่ลูกค้าแล้วเท่านั้น
      case _Stage.traveling:
        return JobSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const JobSectionTitle('กำลังเดินทางไปหาลูกค้า', primary: false),
              const SizedBox(height: 16),
              const Text(
                'เมื่อถึงบ้าน/สถานที่ของลูกค้าแล้ว กดยืนยันด้านล่าง ระบบจะแจ้ง'
                'เตือนลูกค้าอัตโนมัติ และเปลี่ยนสถานะเป็น "กำลังซ่อม"',
                textAlign: TextAlign.center,
                style: _hintStyle,
              ),
              const SizedBox(height: 20),
              JobPrimaryButton(
                label: 'ถึงที่หมายแล้ว',
                icon: Icons.pin_drop_outlined,
                onPressed: onArrived,
                isLoading: isArriving,
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