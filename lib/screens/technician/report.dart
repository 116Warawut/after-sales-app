import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
// 🆕 [ใหม่] ใช้ Machine.warrantyActive เพื่อตรวจสอบว่าเครื่องจักรของงานซ่อมนี้
// อยู่ในประกันหรือไม่ — ถ้าอยู่ในประกันไม่ต้องบังคับแนบสลิปโอนเงิน (ดู
// _loadWarrantyInfo() และ _submit() ด้านล่าง)
import 'package:after_sales/screens/customer/machine_models.dart';

class Report extends StatelessWidget {
  final int repairId;
  const Report({super.key, required this.repairId});

  @override
  Widget build(BuildContext context) {
    return ReportPage(repairId: repairId);
  }
}

/// {@template report_page}
/// แบบฟอร์มส่งรายงานหลังซ่อม ผูกกับใบแจ้งซ่อม [repairId] จริง
/// บันทึกผ่าน `submitRepairReport()` ซึ่งจะตั้งสถานะงานเป็น "เสร็จแล้ว" ให้อัตโนมัติ
/// รูปที่แนบ (ก่อนซ่อม/หลังซ่อม/สลิป) ใช้ image_picker จริง เก็บเป็น path ไฟล์ในเครื่อง
/// {@endtemplate}
class ReportPage extends StatefulWidget {
  final int repairId;
  const ReportPage({super.key, required this.repairId});

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _formCodeController = TextEditingController();
  final TextEditingController _problemController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _beforePhoto;
  XFile? _afterPhoto;
  XFile? _slipPhoto;
  bool _isSubmitting = false;
  bool _loadingTicket = true;

  // 🔗 URL สลิปที่ลูกค้าอัปโหลดเองตอนกดชำระเงินในแอป (จาก payment_qr_sheet.dart)
  // ถ้ามีค่านี้อยู่ = ลูกค้าจ่ายและแนบสลิปมาก่อนแล้ว ช่างไม่ต้องขอสลิปซ้ำ/อัปโหลดเอง
  String? _customerSlipUrl;

  // 🆕 [ใหม่] เครื่องจักรของงานซ่อมนี้อยู่ในประกันหรือไม่ — ถ้าอยู่ในประกัน
  // ไม่มีการชำระเงินจริง จึงไม่บังคับแนบสลิปโอนเงินในหน้านี้ (ดู
  // _loadWarrantyInfo() / _submit())
  bool _isWarrantyCovered = false;
  bool _loadingWarrantyInfo = true;
  String? _machineWarrantyStatusText;

  @override
  void initState() {
    super.initState();
    _loadTicketNumber();
    _loadWarrantyInfo();
  }

  /// 🏷️ ดึงเลขที่ใบแจ้งซ่อม (เช่น AS-291954) มาใส่ในช่อง "รหัสฟอร์มซ่อม" ให้อัตโนมัติ
  /// กันช่างพิมพ์เลขผิด/พิมพ์ไม่ตรงกับใบจริง เพราะเดิมต้องพิมพ์เองล้วน ๆ
  /// พร้อมกันนี้เช็คด้วยว่าลูกค้าอัปโหลดสลิปโอนเงินมาจากหน้าชำระเงินแล้วหรือยัง
  /// ถ้ามีแล้วจะดึง URL มาเติมในช่อง "สลิปโอนเงินลูกค้า" ให้อัตโนมัติเลย
  Future<void> _loadTicketNumber() async {
    try {
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);
      final ticketNo = repair?['ticketNo']?.toString();
      final customerSlip = repair?['customer_payment_slip']?.toString();
      if (!mounted) return;
      setState(() {
        if (ticketNo != null && ticketNo.isNotEmpty) {
          _formCodeController.text = ticketNo;
        }
        if (customerSlip != null && customerSlip.isNotEmpty) {
          _customerSlipUrl = customerSlip;
        }
        _loadingTicket = false;
      });
    } catch (e) {
      debugPrint('Error loading ticket number: $e');
      if (!mounted) return;
      setState(() => _loadingTicket = false);
    }
  }

  /// 🛡️ [ใหม่] ดึง machine_id จากงานซ่อมนี้ แล้วเช็คสถานะประกันของเครื่องจักร
  /// (Machine.warrantyActive) — ถ้าอยู่ในประกัน ไม่บังคับแนบสลิปโอนเงินในหน้านี้
  /// (เหมือนกับตอนออกบิลที่ admin_create_invoice.dart เช็คแบบเดียวกัน)
  Future<void> _loadWarrantyInfo() async {
    try {
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);
      final machineId = repair?['machine_id'];
      if (machineId == null) {
        if (!mounted) return;
        setState(() => _loadingWarrantyInfo = false);
        return;
      }

      final machineMap =
          await db.DatabaseHelper.instance.getMachineById(machineId);
      if (machineMap == null || !mounted) {
        if (mounted) setState(() => _loadingWarrantyInfo = false);
        return;
      }

      final machine = Machine.fromMap(machineMap);
      setState(() {
        _isWarrantyCovered = machine.warrantyActive;
        _machineWarrantyStatusText = machine.warrantyStatusText;
        _loadingWarrantyInfo = false;
      });
    } catch (e) {
      debugPrint('Error loading warranty info for report: $e');
      if (!mounted) return;
      setState(() => _loadingWarrantyInfo = false);
    }
  }

  @override
  void dispose() {
    _formCodeController.dispose();
    _problemController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(String label, ValueChanged<XFile?> onPicked) async {
    // ให้เลือกได้ทั้งถ่ายภาพใหม่ หรือเลือกจากคลังภาพ
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายภาพ'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('เลือกจากคลังภาพ'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;
      setState(() => onPicked(picked));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _submit() async {
    // 🆕 [ใหม่] กันกดส่งเร็วเกินไปก่อนเช็คประกันเสร็จ — ถ้ายังไม่รู้ผลแน่ชัด อาจ
    // บังคับให้แนบสลิปทั้งที่จริงเป็นเครื่องประกัน (ไม่ควรต้องแนบ) ให้รอสักครู่
    if (_loadingWarrantyInfo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กำลังตรวจสอบข้อมูลประกัน กรุณารอสักครู่')),
      );
      return;
    }
    final formOk = _formKey.currentState!.validate();
    // ✅ สลิปถือว่าครบได้ 3 ทาง: เครื่องจักรอยู่ในประกัน (ไม่ต้องมีสลิปเลย),
    // ช่างอัปโหลดเอง (_slipPhoto), หรือลูกค้าอัปโหลดมาจากหน้าชำระเงินในแอปแล้ว
    // (_customerSlipUrl) — ไม่บังคับให้ช่างอัปโหลดซ้ำอีกรอบ
    final hasSlip =
        _isWarrantyCovered || _slipPhoto != null || _customerSlipUrl != null;
    final photosOk = _beforePhoto != null && _afterPhoto != null && hasSlip;

    if (!photosOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_isWarrantyCovered
                ? 'กรุณาอัปโหลดรูปภาพก่อนซ่อมและหลังซ่อมให้ครบ'
                : 'กรุณาอัปโหลดรูปภาพก่อนซ่อม, หลังซ่อม และสลิปโอนเงินให้ครบ')),
      );
      return;
    }
    if (!formOk) return;

    setState(() => _isSubmitting = true);
    try {
      // 📤 อัปโหลดรูปก่อนซ่อม/หลังซ่อม ขึ้น Cloudinary เสมอ
      // เดิมเก็บแค่ path ไฟล์ในเครื่องช่าง ทำให้แอดมิน/ลูกค้าที่เปิดดูจากเครื่องอื่น
      // เห็นแค่ path ที่ไม่มีไฟล์จริงอยู่ด้วย รูปเลยไม่ขึ้น
      final beforeAfterUrls = await CloudinaryService.uploadImages(
        [_beforePhoto!, _afterPhoto!],
      );

      // สลิป: ถ้าช่างเลือกรูปใหม่เอง (เผื่อกรณีลูกค้ายังไม่ได้จ่ายผ่านแอป) ให้อัปโหลด
      // ใหม่ตามปกติ แต่ถ้ามี _customerSlipUrl จากลูกค้าอยู่แล้ว ใช้ URL เดิมได้เลย
      // ไม่ต้องอัปโหลดซ้ำ (ประหยัดโควต้า Cloudinary + เร็วขึ้น) — ถ้าอยู่ในประกัน
      // และไม่มีสลิปเลย ส่งค่าว่างไป ไม่มีอะไรให้อัปโหลด
      final slipUrl = _slipPhoto != null
          ? await CloudinaryService.uploadImage(_slipPhoto!)
          : (_customerSlipUrl ?? '');

      await db.DatabaseHelper.instance.submitRepairReport(
        repairId: widget.repairId,
        formCode: _formCodeController.text.trim(),
        beforePhotoPath: beforeAfterUrls[0],
        afterPhotoPath: beforeAfterUrls[1],
        slipPhotoPath: slipUrl,
        problemDetail: _problemController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('ส่งรายงานสำเร็จ')));
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งรายงานไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🔒 หัวเรื่องล็อกอยู่นิ่ง ไม่เลื่อนตามเนื้อหา
            const AppHeader(title: 'รายงานผล', showBack: true),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _UploadTile(
                            label: 'อัปโหลดรูปภาพก่อนซ่อม',
                            photo: _beforePhoto,
                            onTap: () => _pickImage(
                                'รูปก่อนซ่อม', (v) => _beforePhoto = v),
                          ),
                          const SizedBox(height: 16),
                          _UploadTile(
                            label: 'อัปโหลดรูปภาพหลังซ่อม',
                            photo: _afterPhoto,
                            onTap: () => _pickImage(
                                'รูปหลังซ่อม', (v) => _afterPhoto = v),
                          ),
                          const SizedBox(height: 16),
                          const _FieldLabel('รหัสฟอร์มซ่อม'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _formCodeController,
                            decoration: InputDecoration(
                              hintText: 'กรอกตัวเลขและตัวอักษร',
                              border: const OutlineInputBorder(),
                              suffixIcon: _loadingTicket
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      ),
                                    )
                                  : null,
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'กรุณากรอกรหัสฟอร์มซ่อม'
                                : null,
                          ),
                          const SizedBox(height: 16),
                          // 🆕 [ใหม่] ระหว่างเช็คสถานะประกันอยู่ (เรียก API ยังไม่
                          // เสร็จ) โชว์ตัวโหลดไว้ก่อน กันช่างเห็นช่องแนบสลิปโผล่มา
                          // แวบเดียวแล้วหายไปถ้าเครื่องจักรอยู่ในประกัน (จอกระพริบ)
                          if (_loadingWarrantyInfo)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              ),
                            )
                          // ถ้าเครื่องจักรอยู่ในประกัน ไม่ต้องแนบสลิปโอนเงินเลย
                          // (ไม่มีการชำระเงินจริง) — โชว์กล่องข้อความแทนช่องอัปโหลด
                          else if (_isWarrantyCovered)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.greenBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.shield_outlined,
                                      color: AppColors.greenText, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _machineWarrantyStatusText != null
                                          ? 'ไม่ต้องแนบสลิปโอนเงิน — เครื่องจักรอยู่ในประกัน ($_machineWarrantyStatusText)'
                                          : 'ไม่ต้องแนบสลิปโอนเงิน — เครื่องจักรอยู่ในประกัน',
                                      style: const TextStyle(
                                        color: AppColors.greenText,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            _UploadTile(
                              label: 'สลิปโอนเงินลูกค้า',
                              photo: _slipPhoto,
                              prefilledUrl: _customerSlipUrl,
                              prefilledCaption:
                                  'ลูกค้าอัปโหลดแล้วจากหน้าชำระเงิน (แตะเพื่อเปลี่ยนรูป)',
                              onTap: () => _pickImage(
                                  'สลิปโอนเงิน', (v) => _slipPhoto = v),
                            ),
                          const SizedBox(height: 16),
                          const _FieldLabel('ปัญหาที่พบ'),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _problemController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'อธิบายปัญหาที่พบและวิธีแก้ไข',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'กรุณากรอกปัญหาที่พบ'
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Material(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: _isSubmitting ? null : _submit,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('ส่งรายงาน',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(text,
            style: const TextStyle(
                color: AppColors.textLabel,
                fontSize: 14,
                fontWeight: FontWeight.w500)),
        const SizedBox(width: 4),
        const Text('*',
            style:
                TextStyle(color: AppColors.requiredMark, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _UploadTile extends StatelessWidget {
  final String label;
  final XFile? photo;
  final VoidCallback onTap;
  // 🔗 ถ้ามีค่านี้ (ไม่ใช่จากช่างเลือกเอง) แปลว่ามีรูปที่มาจากที่อื่นอยู่แล้ว
  // (เช่น สลิปที่ลูกค้าอัปโหลดจากหน้าชำระเงิน) ให้โชว์เป็น "อัปโหลดแล้ว" ทันที
  final String? prefilledUrl;
  final String? prefilledCaption;
  const _UploadTile({
    required this.label,
    required this.photo,
    required this.onTap,
    this.prefilledUrl,
    this.prefilledCaption,
  });

  bool get _hasPrefilled =>
      photo == null && prefilledUrl != null && prefilledUrl!.isNotEmpty;
  bool get uploaded => photo != null || _hasPrefilled;

  @override
  Widget build(BuildContext context) {
    final displayPath = photo?.path ?? (_hasPrefilled ? prefilledUrl! : '');
    final caption = photo != null
        ? 'อัปโหลดแล้ว (แตะเพื่อเปลี่ยนรูป)'
        : _hasPrefilled
            ? (prefilledCaption ?? 'อัปโหลดแล้ว (แตะเพื่อเปลี่ยนรูป)')
            : 'อัปโหลดขั้นต่ำ 1 รูป';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 6),
        Material(
          color: uploaded ? AppColors.greenBg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(
                    color: uploaded
                        ? AppColors.greenText
                        : AppColors.textHint),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  if (uploaded)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LocalOrNetworkImage(
                        path: displayPath,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    const Icon(Icons.upload_file,
                        color: AppColors.textHint, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      caption,
                      style: TextStyle(
                        color: uploaded
                            ? AppColors.greenText
                            : AppColors.textHint,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  if (uploaded)
                    const Icon(Icons.check_circle,
                        color: AppColors.greenText, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}