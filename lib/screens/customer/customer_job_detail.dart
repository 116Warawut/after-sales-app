import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/screens/shared/job_detail_ui.dart';
import 'package:after_sales/screens/customer/technician_tracking.dart';
import 'package:after_sales/screens/customer/payment_qr_sheet.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

/// หน้า "รายละเอียดงาน" ฝั่งลูกค้า
class CustomerJobDetail extends StatelessWidget {
  final int? repairId;
  const CustomerJobDetail({super.key, this.repairId});

  @override
  Widget build(BuildContext context) {
    return CustomerJobDetailPage(repairId: repairId);
  }
}

/// ข้อมูลงานซ่อมที่ลูกค้าดู
class CustomerJobInfo {
  final int? id;
  final String ticketId;
  final String machineCode;
  final String modelName;
  final String description;
  final String status;
  final String customerName;
  final String customerPhone;
  final String address;
  final String appointmentDate;
  final String adminName;
  final String adminCode;
  final String adminPhone;
  final String technicianName;
  final String technicianCode;
  final String technicianPhone;
  final List<String> images;
  final String billId;
  final double totalPrice;
  final bool isPaid;
  final String? paymentSlipUrl;
  final int? ratingStars;
  final String? ratingComment;

  const CustomerJobInfo({
    this.id,
    required this.ticketId,
    required this.machineCode,
    required this.modelName,
    required this.description,
    required this.status,
    required this.customerName,
    required this.customerPhone,
    required this.address,
    required this.appointmentDate,
    required this.adminName,
    required this.adminCode,
    required this.adminPhone,
    required this.technicianName,
    required this.technicianCode,
    required this.technicianPhone,
    required this.images,
    required this.billId,
    required this.totalPrice,
    required this.isPaid,
    this.paymentSlipUrl,
    this.ratingStars,
    this.ratingComment,
  });

  static const placeholder = CustomerJobInfo(
    ticketId: '-',
    machineCode: '-',
    modelName: '-',
    description: '-',
    status: 'ไม่พบข้อมูล',
    customerName: '-',
    customerPhone: '-',
    address: '-',
    appointmentDate: '-',
    adminName: 'ยังไม่มีแอดมินดูแล',
    adminCode: '-',
    adminPhone: '-',
    technicianName: 'ยังไม่มีการมอบหมายช่าง',
    technicianCode: '-',
    technicianPhone: '-',
    images: [],
    billId: '-',
    totalPrice: 0,
    isPaid: false,
    paymentSlipUrl: null,
    ratingStars: null,
    ratingComment: null,
  );
}

class CustomerJobDetailPage extends StatefulWidget {
  final int? repairId;
  const CustomerJobDetailPage({super.key, this.repairId});

  @override
  State<CustomerJobDetailPage> createState() => _CustomerJobDetailPageState();
}

class _CustomerJobDetailPageState extends State<CustomerJobDetailPage> {
  bool _loading = true;
  CustomerJobInfo _job = CustomerJobInfo.placeholder;

  final bool _isPaying = false;
  bool _paid = false;

  String _adminUsername = '';
  String _technicianUsername = '';
  bool _isCancelling = false;
  bool _isRating = false;

  bool get _canCancel {
    final s = _job.status;
    if (_job.id == null) return false;
    if (_paid) return false;
    if (s.contains('ยกเลิก')) return false;
    if (s.contains('เสร็จ')) return false;
    if (s == 'ไม่พบข้อมูล' || s == '-') return false;
    return true;
  }

  @override
  void initState() {
    super.initState();
    _loadJob();
  }

  Future<void> _loadJob() async {
    setState(() => _loading = true);

    if (widget.repairId == null) {
      if (!mounted) return;
      setState(() {
        _job = CustomerJobInfo.placeholder;
        _loading = false;
      });
      return;
    }

    try {
      final repair = await db.DatabaseHelper.instance.getRepairById(
        widget.repairId!,
      );

      if (repair == null) {
        if (!mounted) return;
        setState(() {
          _job = CustomerJobInfo.placeholder;
          _loading = false;
        });
        return;
      }

      final customer = await db.DatabaseHelper.instance.getCustomerProfile(
        (repair['customer_username'] as String?) ?? '',
      );

      String technicianName = 'ยังไม่มีการมอบหมายช่าง';
      String technicianCode = '-';
      String technicianPhone = '-';
      final techUsername = repair['technician_username'] as String?;
      if (techUsername != null && techUsername.isNotEmpty) {
        final tech = await db.DatabaseHelper.instance.getTechnicianByUsername(
          techUsername,
        );
        if (tech != null) {
          technicianName = (tech['tech_name'] as String?) ?? techUsername;
          technicianCode = (tech['employee_id'] as String?) ?? '-';
          technicianPhone = (tech['phone'] as String?) ?? '-';
        }
      }

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

      final totalPrice = (repair['total_price'] as num?)?.toDouble() ?? 0;
      final billId = (repair['bill_id'] as String?) ?? '-';
      final isPaid = ((repair['is_paid'] as num?)?.toInt() ?? 0) == 1 || repair['is_paid'] == true;
      final paymentSlipUrl = repair['customer_payment_slip'] as String?;

      // อ่านค่าคะแนนและความคิดเห็น
      final ratingStars = (repair['rating_stars'] as num?)?.toInt() ??
          (repair['rating'] as num?)?.toInt();
      final ratingComment = (repair['rating_comment'] as String?) ??
          (repair['review'] as String?) ??
          (repair['customer_comment'] as String?);

      final dateStr = (repair['date'] as String?) ?? '-';
      final timeStr = (repair['appointment_time'] as String?) ??
          (repair['time'] as String?) ??
          '';
      final appointmentDisplay = (timeStr.isNotEmpty && dateStr != '-')
          ? '$dateStr เวลา $timeStr น.'
          : dateStr;

      if (!mounted) return;
      setState(() {
        _job = CustomerJobInfo(
          id: repair['id'] as int?,
          ticketId: (repair['ticketNo'] as String?) ?? '-',
          machineCode: (repair['machine_id'] as int?)?.toString() ?? '-',
          modelName: (repair['machine'] as String?) ?? '-',
          description: (repair['detail'] as String?) ?? '-',
          status: (repair['status'] as String?) ?? '-',
          customerName: customer != null
              ? '${customer['name'] ?? ''} ${customer['surname'] ?? ''}'.trim()
              : '-',
          customerPhone: customer?['phone'] as String? ?? '-',
          address: (repair['location'] as String?) ?? '-',
          appointmentDate: appointmentDisplay,
          adminName: (repair['admin_name'] as String?) ?? 'ยังไม่มีแอดมินดูแล',
          adminCode: (repair['admin_code'] as String?) ?? '-',
          adminPhone: (repair['admin_phone'] as String?) ?? '-',
          technicianName: technicianName,
          technicianCode: technicianCode,
          technicianPhone: technicianPhone,
          images: imageList,
          billId: billId,
          totalPrice: totalPrice,
          isPaid: isPaid,
          paymentSlipUrl: paymentSlipUrl,
          ratingStars: ratingStars,
          ratingComment: ratingComment,
        );
        _paid = isPaid;
        _adminUsername = (repair['admin_username'] as String?) ?? '';
        _technicianUsername = techUsername ?? '';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('เกิดข้อผิดพลาดในการโหลดข้อมูล: $e');
    }
  }

  void _openChat() {
    if (_job.id == null) {
      _snack('ยังไม่พบข้อมูลใบแจ้งซ่อมสำหรับเปิดแชท');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          role: UserRole.customer,
          repairId: _job.id.toString(),
        ),
      ),
    );
  }

  void _openMap() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TechnicianTrackingPage(repairId: _job.id),
      ),
    );
  }

  Future<void> _handlePay() async {
    if (_job.totalPrice <= 0 || _job.id == null) {
      _snack('ยังไม่มีบิลให้ชำระในขณะนี้');
      return;
    }

    final result = await showPaymentQrSheet(
      context,
      repairId: _job.id!,
      totalPrice: _job.totalPrice,
      ticketId: _job.ticketId,
      adminUsername: _adminUsername,
      technicianUsername: _technicianUsername,
    );

    if (result == true) {
      if (!mounted) return;
      _snack(
          'ส่งสลิปสำเร็จ ระบบส่งสลิปไปที่รายงานผลของช่างให้อัตโนมัติแล้ว รอทีมงานตรวจสอบและยืนยันการชำระเงิน');
      await _loadJob();
    }
  }

  // ส่งคะแนนและข้อความรีวิว
  Future<void> _submitRating(int stars, String comment) async {
    if (_job.id == null || _isRating) return;
    setState(() => _isRating = true);
    try {
      await db.DatabaseHelper.instance.updateRepair(
        _job.id!,
        {
          'rating': stars,
          'rating_stars': stars,
          'rating_comment': comment.trim(),
          'rated_at': DateTime.now().toIso8601String(),
          // 🐛 [แก้บัค] เดิมไม่เคยเขียนฟิลด์นี้เลย ทำให้ logic กันคะแนนโดน
          // เหมาโอนไปติดช่างคนใหม่หลังงานถูกเปลี่ยนช่าง (ทั้งฝั่งเว็บ
          // TechniciansPage.jsx และ services.dart:getTechnicianRatingStats
          // ที่ต่างก็ priority อ่านฟิลด์นี้ก่อน technician_username) ไม่เคย
          // ทำงานจริงสักที — บันทึกช่างที่ทำงานนี้ ณ ตอนที่ถูกให้คะแนนไว้ตรงนี้
          if (_technicianUsername.isNotEmpty)
            'rating_technician_username': _technicianUsername,
        },
      );
      if (!mounted) return;
      _snack('ขอบคุณสำหรับการประเมินการบริการ ($stars ดาว)');
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      _snack('ให้คะแนนไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _isRating = false);
    }
  }

  Future<void> _handleCancelRepair() async {
    if (_job.id == null) return;

    final confirmed = await showJobConfirmDialog(
      context,
      title: 'ยืนยันการยกเลิก',
      message:
          'ยืนยันว่าจะยกเลิกการแจ้งซ่อม ${_job.ticketId} ใช่หรือไม่?\nเมื่อยกเลิกแล้วจะไม่สามารถย้อนกลับได้',
      confirmLabel: 'ยกเลิกการแจ้งซ่อม',
      cancelLabel: 'ไม่ใช่ตอนนี้',
      icon: Icons.report_gmailerrorred_outlined,
      danger: true,
    );

    if (!confirmed) return;

    setState(() => _isCancelling = true);

    try {
      await db.DatabaseHelper.instance.updateRepairStatus(
        _job.id!,
        'ยกเลิก',
      );

      if (_adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _adminUsername,
          'role': 'ADMIN',
          'title': 'ลูกค้ายกเลิกการแจ้งซ่อม',
          'message': 'งานซ่อม ${_job.ticketId} ถูกยกเลิกโดยลูกค้า',
          'type': 'REPAIR_CANCELLED',
          'target_id': _job.id,
          'is_read': 0,
        });
      }

      if (_technicianUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _technicianUsername,
          'role': 'TECHNICIAN',
          'title': 'งานซ่อมถูกยกเลิก',
          'message': 'งานซ่อม ${_job.ticketId} ถูกยกเลิกโดยลูกค้า',
          'type': 'REPAIR_CANCELLED',
          'target_id': _job.id,
          'is_read': 0,
        });
      }

      if (!mounted) return;
      setState(() => _isCancelling = false);
      _snack('ยกเลิกการแจ้งซ่อมเรียบร้อยแล้ว');
      await _loadJob();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      _snack('ยกเลิกไม่สำเร็จ: $e');
    }
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
    final bool isDoneJob = _job.status.contains('เสร็จ') ||
        _job.status.toLowerCase().contains('done') ||
        _job.status.toLowerCase().contains('complete');

    return JobDetailScaffold(
      header: const AppHeader(title: 'รายละเอียดงาน', showBack: true),
      isLoading: _loading,
      onRefresh: _loadJob,
      children: [
        _JobInfoCard(job: _job, onMap: _openMap),

        // การ์ดประเมินช่าง (แสดงเมื่องานเสร็จสิ้นและยังไม่เคยประเมิน)
        if (isDoneJob && _job.ratingStars == null)
          _RatingCard(isSubmitting: _isRating, onRate: _submitRating)
        // การ์ดแสดงคะแนนและความคิดเห็นที่บันทึกแล้ว
        else if (_job.ratingStars != null)
          _RatedCard(stars: _job.ratingStars!, comment: _job.ratingComment),

        JobContactCard(
          title: 'แอดมิน',
          roleLabel: 'แอดมินผู้ดูแล',
          name: _job.adminName,
          code: _job.adminCode,
          phone: _job.adminPhone,
          onMessage: _openChat,
        ),
        JobContactCard(
          title: 'ช่าง',
          roleLabel: 'ช่างผู้ดูแล',
          name: _job.technicianName,
          code: _job.technicianCode,
          phone: _job.technicianPhone,
          onMessage: _openChat,
        ),
        _PaymentCard(
          billId: _job.billId,
          totalPrice: _job.totalPrice,
          isPaying: _isPaying,
          paid: _paid,
          awaitingVerification: !_paid &&
              (_job.paymentSlipUrl != null && _job.paymentSlipUrl!.isNotEmpty),
          onPay: _handlePay,
        ),
        _CancelCard(
          canCancel: _canCancel,
          isCancelled: _job.status.contains('ยกเลิก'),
          isCancelling: _isCancelling,
          onCancel: _handleCancelRepair,
        ),
      ],
    );
  }
}

// ---------- การ์ดรายละเอียดงาน ----------
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
          JobInfoRow(label: 'รหัสเครื่อง', value: job.machineCode),
          JobInfoRow(label: 'อาการ / รายละเอียด', value: job.description),
          const SizedBox(height: 6),
          JobStatusRow(status: job.status),
          const SizedBox(height: 8),
          JobInfoRow(label: 'ชื่อลูกค้า', value: job.customerName),
          JobPhoneRow(phone: job.customerPhone),
          JobInfoRow(label: 'ที่อยู่', value: job.address),
          JobInfoRow(label: 'วัน-เวลานัดซ่อม', value: job.appointmentDate),
          const SizedBox(height: 14),
          JobImageStrip(images: job.images),
          const SizedBox(height: 16),
          JobPrimaryButton(
            label: 'ดูตำแหน่งที่อยู่ / แผนที่',
            icon: Icons.map_outlined,
            onPressed: onMap,
            verticalPadding: 12,
          ),
        ],
      ),
    );
  }
}

// ---------- การ์ดให้คะแนนช่างซ่อม (1-5 ดาว + กล่องข้อความ) ----------
class _RatingCard extends StatefulWidget {
  final bool isSubmitting;
  final Function(int stars, String comment) onRate;

  const _RatingCard({
    required this.isSubmitting,
    required this.onRate,
  });

  @override
  State<_RatingCard> createState() => _RatingCardState();
}

class _RatingCardState extends State<_RatingCard> {
  int _selectedStars = 5;
  final TextEditingController _commentController = TextEditingController();

  static const List<String> _ratingLabels = [
    '1 ดาว (1 คะแนน) - ควรปรับปรุง',
    '2 ดาว (2 คะแนน) - พอใช้',
    '3 ดาว (3 คะแนน) - ปานกลาง',
    '4 ดาว (4 คะแนน) - ดี',
    '5 ดาว (5 คะแนน) - ยอดเยี่ยม',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JobSectionTitle('ให้คะแนนช่างซ่อม'),
          const SizedBox(height: 8),
          const Text(
            'งานซ่อมนี้เสร็จสิ้นแล้ว โปรดให้คะแนนความพึงพอใจการบริการของช่าง (1-5 คะแนน)',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.textSubtitle,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final starNumber = index + 1;
              final isFilled = starNumber <= _selectedStars;
              return GestureDetector(
                onTap: widget.isSubmitting
                    ? null
                    : () => setState(() => _selectedStars = starNumber),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    isFilled ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 40,
                    color: isFilled ? Colors.amber : Colors.grey.shade300,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              _ratingLabels[_selectedStars - 1],
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textMain,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _commentController,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'เขียนความคิดเห็นเพิ่มเติมถึงช่าง (ไม่บังคับ)...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 16),
          JobPrimaryButton(
            label: 'ส่งคะแนนประเมิน ($_selectedStars คะแนน)',
            icon: Icons.check_circle_outline,
            isLoading: widget.isSubmitting,
            onPressed: () =>
                widget.onRate(_selectedStars, _commentController.text),
          ),
        ],
      ),
    );
  }
}

// ---------- การ์ดแสดงคะแนนที่ประเมินแล้ว ----------
class _RatedCard extends StatelessWidget {
  final int stars;
  final String? comment;
  const _RatedCard({required this.stars, this.comment});

  @override
  Widget build(BuildContext context) {
    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JobSectionTitle('คะแนนการประเมินช่าง', primary: false),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.greenBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.verified, color: AppColors.greenText, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'คุณได้ให้คะแนนช่างซ่อมเรียบร้อยแล้ว',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.greenText,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Row(
                                children: List.generate(5, (i) {
                                  return Icon(
                                    i < stars
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 18,
                                    color: Colors.amber,
                                  );
                                }),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$stars / 5 คะแนน',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textMain,
                                  fontFamily: AppStyles.fontFamily,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (comment != null && comment!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(
                      '"$comment"',
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------- การ์ดชำระเงิน ----------
class _PaymentCard extends StatelessWidget {
  final String billId;
  final double totalPrice;
  final bool isPaying;
  final bool paid;
  final bool awaitingVerification;
  final VoidCallback onPay;

  const _PaymentCard({
    required this.billId,
    required this.totalPrice,
    required this.isPaying,
    required this.paid,
    this.awaitingVerification = false,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    final hasBill = totalPrice > 0;

    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JobSectionTitle('ชำระเงิน', primary: false),
          const SizedBox(height: 16),
          JobInfoRow(label: 'รหัสบิล', value: billId),
          JobInfoRow(
            label: 'ราคารวม',
            value: '${totalPrice.toStringAsFixed(2)} บาท',
          ),
          const SizedBox(height: 16),
          if (!hasBill)
            const Text(
              'ยังไม่มีบิลให้ชำระในขณะนี้ ทีมงานจะแจ้งราคาหลังตรวจเช็คอาการเสร็จสิ้น',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            )
          else if (paid)
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
                      'ชำระเงินเรียบร้อยแล้ว',
                      style: TextStyle(
                        color: AppColors.greenText,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (awaitingVerification)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.yellowBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      color: AppColors.yellowText, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ส่งสลิปแล้ว รอตรวจสอบการชำระเงิน',
                      style: TextStyle(
                        color: AppColors.yellowText,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            JobPrimaryButton(
              label: 'ชำระเงิน',
              onPressed: onPay,
              isLoading: isPaying,
            ),
        ],
      ),
    );
  }
}

// ---------- การ์ดยกเลิกการแจ้งซ่อม ----------
class _CancelCard extends StatelessWidget {
  final bool canCancel;
  final bool isCancelled;
  final bool isCancelling;
  final VoidCallback onCancel;

  const _CancelCard({
    required this.canCancel,
    required this.isCancelled,
    required this.isCancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const JobSectionTitle('ยกเลิกการแจ้งซ่อม', primary: false),
          const SizedBox(height: 16),
          if (isCancelled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.redBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.cancel, color: AppColors.redText, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'รายการนี้ถูกยกเลิกแล้ว',
                      style: TextStyle(
                        color: AppColors.redText,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (!canCancel)
            const Text(
              'ไม่สามารถยกเลิกได้แล้ว เนื่องจากงานซ่อมเสร็จสิ้นหรือชำระเงินเรียบร้อยแล้ว',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            )
          else ...[
            const Text(
              'หากไม่ต้องการใช้บริการแล้ว สามารถกดยกเลิกได้ ระบบจะแจ้งแอดมินและช่างให้ทราบทันที',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 16),
            JobDangerButton(
              label: 'ยกเลิกการแจ้งซ่อม',
              icon: Icons.cancel_outlined,
              onPressed: onCancel,
              isLoading: isCancelling,
            ),
          ],
        ],
      ),
    );
  }
}