import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

/// {@template payment_qr_sheet}
/// Bottom sheet ที่เด้งขึ้นมาตอนลูกค้ากด "ชำระเงิน" ในหน้ารายละเอียดงาน
/// แสดงรูป QR Code พร้อมเพย์ของร้าน (รูปจริง ไม่ได้ generate เอง) พร้อมช่องให้
/// แนบสลิปโอนเงิน — เมื่อยืนยันแล้วจะอัปโหลดสลิปขึ้น Cloudinary แล้วบันทึกเข้า
/// งานซ่อมนี้ทันที (ผ่าน submitPaymentSlip) ซึ่งจะไปโผล่ที่ฟอร์ม "ส่งรายงานผล"
/// ของช่างแบบอัตโนมัติ ช่างไม่ต้องขอสลิปจากลูกค้าซ้ำอีกรอบ
///
/// ⭐ [แก้ไข] การแนบสลิปที่นี่ยังไม่ถือว่า "ชำระเงินแล้ว" — แค่บันทึกว่าลูกค้า
/// ส่งหลักฐานมาแล้วเท่านั้น สถานะจะขึ้นเป็น "รอตรวจสอบการชำระเงิน" จนกว่าแอดมิน
/// จะตรวจสลิปแล้วกดยืนยันในหน้าจัดการบิล ถึงจะเปลี่ยนเป็น "ชำระเงินเรียบร้อยแล้ว" จริง
///
/// วิธีเปิดใช้งาน: เรียก `showPaymentQrSheet(context, repairId: ..., totalPrice: ...)`
/// จะคืนค่า `true` กลับมาถ้าอัปโหลดสลิปสำเร็จ (ใช้ไป reload หน้าเดิมได้เลย)
/// {@endtemplate}
Future<bool?> showPaymentQrSheet(
  BuildContext context, {
  required int repairId,
  required double totalPrice,
  required String ticketId,
  String adminUsername = '',
  String technicianUsername = '',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentQrSheet(
      repairId: repairId,
      totalPrice: totalPrice,
      ticketId: ticketId,
      adminUsername: adminUsername,
      technicianUsername: technicianUsername,
    ),
  );
}

class _PaymentQrSheet extends StatefulWidget {
  final int repairId;
  final double totalPrice;
  final String ticketId;
  final String adminUsername;
  final String technicianUsername;

  const _PaymentQrSheet({
    required this.repairId,
    required this.totalPrice,
    required this.ticketId,
    required this.adminUsername,
    required this.technicianUsername,
  });

  @override
  State<_PaymentQrSheet> createState() => _PaymentQrSheetState();
}

class _PaymentQrSheetState extends State<_PaymentQrSheet> {
  final ImagePicker _picker = ImagePicker();
  XFile? _slipPhoto;
  bool _isSubmitting = false;

  String _formatPrice(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final integerPart = parts[0].replaceAllMapped(reg, (m) => '${m[1]},');
    return '$integerPart.${parts[1]}';
  }

  Future<void> _pickSlip() async {
    // ให้เลือกได้ทั้งถ่ายภาพหน้าจอสลิป หรือเลือกรูปที่มีอยู่แล้วจากคลังภาพ
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('แนบสลิปโอนเงิน',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('ถ่ายภาพสลิป'),
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
      final picked = await _picker.pickImage(source: source, imageQuality: 85);
      if (picked == null) return;
      setState(() => _slipPhoto = picked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกรูปสลิปไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _confirmPayment() async {
    if (_slipPhoto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาแนบสลิปโอนเงินก่อนยืนยัน')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      // 📤 อัปโหลดสลิปขึ้น Cloudinary ก่อน เพื่อให้ทุกฝ่าย (แอดมิน/ช่าง) เห็นรูปจริง
      final slipUrl = await CloudinaryService.uploadImage(_slipPhoto!);

      await db.DatabaseHelper.instance.submitPaymentSlip(
        widget.repairId,
        slipUrl,
      );

      // 🔔 แจ้งเตือนแอดมินและช่างที่ดูแลงานนี้ว่าลูกค้าอัปโหลดสลิปแล้ว
      if (widget.adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': widget.adminUsername,
          'role': 'ADMIN',
          'title': 'ลูกค้าชำระเงินแล้ว',
          'message':
              'งานซ่อม ${widget.ticketId} แนบสลิปโอนเงินแล้ว ฿${_formatPrice(widget.totalPrice)}',
          'type': 'PAYMENT_RECEIVED',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }
      if (widget.technicianUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': widget.technicianUsername,
          'role': 'TECHNICIAN',
          'title': 'ลูกค้าชำระเงินแล้ว',
          'message':
              'งานซ่อม ${widget.ticketId} ลูกค้าแนบสลิปโอนเงินแล้ว ระบบดึงสลิปไปใส่ในฟอร์มส่งรายงานให้อัตโนมัติ',
          'type': 'PAYMENT_RECEIVED',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปโหลดสลิปไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'สแกน QR เพื่อชำระเงิน',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'งานซ่อม ${widget.ticketId} · ยอดชำระ ${_formatPrice(widget.totalPrice)} บาท',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 16),

            // 🖼️ รูป QR Code พร้อมเพย์ของร้าน — เป็นรูปจริง วางไว้ที่
            // assets/images/payment_qr.png (ดูวิธีตั้งค่าใน README/คอมเมนต์ท้ายไฟล์)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(16),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/payment_qr.png',
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 260,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(16),
                    child: const Text(
                      'ยังไม่พบรูป QR\nวางไฟล์ไว้ที่ assets/images/payment_qr.png\nแล้วเพิ่ม path นี้ใน pubspec.yaml',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSubtitle),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            const _FieldLabel('แนบสลิปโอนเงิน'),
            const SizedBox(height: 8),
            Material(
              color: _slipPhoto != null ? AppColors.greenBg : Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _isSubmitting ? null : _pickSlip,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _slipPhoto != null
                          ? AppColors.greenText
                          : AppColors.textHint,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (_slipPhoto != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LocalOrNetworkImage(
                            path: _slipPhoto!.path,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                          ),
                        )
                      else
                        const Icon(Icons.upload_file,
                            color: AppColors.textHint, size: 22),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _slipPhoto != null
                              ? 'แนบสลิปแล้ว (แตะเพื่อเปลี่ยนรูป)'
                              : 'แตะเพื่อถ่ายภาพ/เลือกรูปสลิป',
                          style: TextStyle(
                            color: _slipPhoto != null
                                ? AppColors.greenText
                                : AppColors.textHint,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_slipPhoto != null)
                        const Icon(Icons.check_circle,
                            color: AppColors.greenText, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSubmitting ? null : _confirmPayment,
              style: AppStyles.primaryButton.copyWith(
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text('ยืนยันการชำระเงิน',
                      style: AppStyles.buttonText),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _isSubmitting ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
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
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textLabel,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: AppStyles.fontFamily,
      ),
    );
  }
}
