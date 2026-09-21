import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';

/// หน้าชำระเงินสำหรับใบแจ้งซ่อมหนึ่งใบ (repairId)
class PaymentPage extends StatefulWidget {
  final int repairId;

  const PaymentPage({super.key, required this.repairId});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  bool _loading = true;
  bool _isPaying = false;
  bool _paid = false;
  // 🆕 [ใหม่] true = เครื่องจักรอยู่ในประกัน บิลนี้ไม่มีค่าใช้จ่ายจริง — ซ่อน
  // การ์ดสลิปโอนเงิน/ปุ่มยืนยันชำระเงิน และเปลี่ยนป้ายสถานะ/ใบเสร็จให้ตรงความจริง
  bool _isWarrantyCovered = false;

  String _ticketNo = '-';
  String _billId = '-';
  double _totalPrice = 0;
  DateTime? _paymentDate;
  String _adminUsername = '';
  // 🖼️ [แก้ไข] สลิปโอนเงินจริงที่ลูกค้าแนบมาตอนกดชำระ (ผ่าน payment_qr_sheet.dart)
  // — เอาไว้แสดงแทน QR Code ปลอมที่ generate เอง เพื่อให้แอดมินเห็นหลักฐานการโอน
  // จริงตอนเปิดดูจากหน้า "ประวัติการออกบิล"
  String? _paymentSlipUrl;

  @override
  void initState() {
    super.initState();
    _loadBill();
  }

  /// ดึงข้อมูลบิลและสถานะการชำระเงินจาก Database
  Future<void> _loadBill() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);

      if (!mounted) return;
      setState(() {
        if (repair != null) {
          _ticketNo = (repair['ticketNo']?.toString()) ?? '-';
          _billId = resolveBillId(repair) ?? '-'; // 🐛 fallback invoice_no (บิลจากเว็บ)
          _totalPrice = toDoubleOrNull(repair['total_price']) ?? 0;
          _paid = (toIntOrNull(repair['is_paid']) ?? 0) == 1 || repair['is_paid'] == true;
          _isWarrantyCovered = repair['is_warranty_covered'] == true ||
              repair['is_warranty_covered'] == 1;
          _adminUsername = (repair['admin_username']?.toString()) ?? '';
          final slip = repair['customer_payment_slip']?.toString();
          _paymentSlipUrl = (slip != null && slip.trim().isNotEmpty) ? slip : null;
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar('เกิดข้อผิดพลาดในการโหลดข้อมูลบิล: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  /// ฟังก์ชันดำเนินการชำระเงิน (หน้านี้ใช้โดยแอดมิน — เปิดจากหน้า "การเงิน"
  /// เพื่อตรวจสลิปแล้วกดยืนยันว่าลูกค้าชำระเงินแล้วจริง)
  Future<void> _pay() async {
    if (_isPaying || _paid) return;

    if (_totalPrice <= 0) {
      _showSnackBar('ยังไม่มีบิลหรือยอดชำระในขณะนี้', isError: true);
      return;
    }

    // 🐛 [แก้ไข] เดิมกดยืนยันได้เลยแม้ลูกค้าจะยังไม่เคยแนบสลิปโอนเงินมาเลย
    // (_paymentSlipUrl == null) ทั้งที่ตามที่ payment_qr_sheet.dart ตั้งใจไว้
    // แอดมินควรตรวจสลิปก่อนค่อยกดยืนยันที่นี่ — เพิ่ม dialog เตือนกันพลาด
    // (ไม่บล็อกทีเดียวเลย เผื่อกรณีลูกค้าจ่ายเงินสดจริงนอกแอป ไม่มีสลิปให้แนบ
    // แอดมินยังต้องยืนยันได้อยู่ แค่ต้องกดยืนยันซ้ำอีกทีให้แน่ใจว่าตรวจสอบแล้ว)
    if (_paymentSlipUrl == null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยังไม่มีสลิปโอนเงินแนบมา'),
          content: const Text(
            'ลูกค้ายังไม่ได้แนบสลิปโอนเงินในระบบ ยืนยันว่าตรวจสอบการชำระเงิน '
            'ด้วยวิธีอื่นแล้ว (เช่น รับเงินสด/เช็คยอดโอนเองแล้ว) ใช่หรือไม่?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ยืนยัน ชำระเงินแล้วจริง'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!mounted) return;
    }

    setState(() => _isPaying = true);

    try {
      final now = DateTime.now();
      await db.DatabaseHelper.instance.createPayment({
        'repair_id': widget.repairId,
        'amount': _totalPrice,
        'status': 'สำเร็จ',
        'payment_date': now.toIso8601String(),
      });

      await db.DatabaseHelper.instance.markRepairPaid(widget.repairId);

      if (_adminUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': _adminUsername,
          'role': 'ADMIN',
          'title': 'ลูกค้าชำระเงินแล้ว',
          'message':
              'งานซ่อม $_ticketNo ชำระเงินแล้ว ฿${_totalPrice.toStringAsFixed(2)}',
          'type': 'PAYMENT_RECEIVED',
          'target_id': widget.repairId,
          'is_read': 0,
        });
      }

      if (!mounted) return;
      setState(() {
        _isPaying = false;
        _paid = true;
        _paymentDate = now;
      });

      _showSnackBar('ชำระเงินสำเร็จ ขอบคุณที่ใช้บริการ');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPaying = false);
      _showSnackBar('ชำระเงินไม่สำเร็จ: $e', isError: true);
    }
  }

  String _formatPrice(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final integerPart = parts[0].replaceAllMapped(reg, (m) => '${m[1]},');
    return '$integerPart.${parts[1]}';
  }

  /// เปิดดูรูปสลิปแบบเต็มจอ
  void _showSlipPreview(String url) {
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
              child: Image.network(
                url,
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

  /// เปิดหน้า Popup ใบเสร็จรับเงิน
  void _showReceiptDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(
              _isWarrantyCovered ? Icons.shield_outlined : Icons.check_circle,
              color: Colors.green,
              size: 60,
            ),
            const SizedBox(height: 8),
            const Text('ใบเสร็จรับเงิน',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text(
              _isWarrantyCovered ? 'ไม่มีค่าใช้จ่าย เนื่องจากอยู่ในประกัน' : 'รายการชำระเงินสมบูรณ์',
              style: const TextStyle(color: Colors.grey),
            ),
            const Divider(height: 32),
            _BillDetailRow(label: 'เลขแจ้งซ่อม', value: _ticketNo),
            const SizedBox(height: 8),
            _BillDetailRow(label: 'รหัสบิล', value: _billId),
            const SizedBox(height: 8),
            _BillDetailRow(
              label: 'ช่องทางชำระ',
              value:
                  _isWarrantyCovered ? 'ไม่มีค่าใช้จ่าย (อยู่ในประกัน)' : 'พร้อมเพย์ (PromptPay)',
            ),
            const SizedBox(height: 8),
            _BillDetailRow(
              label: 'วันที่ชำระ',
              value: _paymentDate != null
                  ? '${_paymentDate!.day}/${_paymentDate!.month}/${_paymentDate!.year} ${_paymentDate!.hour.toString().padLeft(2, '0')}:${_paymentDate!.minute.toString().padLeft(2, '0')} น.'
                  : '-',
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('ยอดชำระทั้งสิ้น',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                Text('${_formatPrice(_totalPrice)} บาท',
                    style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary)),
              ],
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('ปิดหน้าต่าง',
                    style: TextStyle(color: Colors.white, fontSize: 16)),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _paid);
      },
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  AppHeader(
                    title: 'ชำระเงิน',
                    showBack: true,
                    onBack: () => Navigator.pop(context, _paid),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // แสดงสถานะชำระเงินเรียบร้อย / ไม่มีค่าใช้จ่ายเพราะประกัน
                    if (_isWarrantyCovered) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.greenBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greenText),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.shield_outlined, color: AppColors.greenText),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'บิลนี้ไม่มีค่าใช้จ่าย เนื่องจากเครื่องจักรอยู่ในประกัน',
                                style: TextStyle(
                                  color: AppColors.greenText,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else if (_paid) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.greenBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.greenText),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle, color: AppColors.greenText),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'รายการนี้ชำระเงินเรียบร้อยแล้ว',
                                style: TextStyle(
                                  color: AppColors.greenText,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // 🖼️ [แก้ไข] การ์ดแสดงสลิปโอนเงินจริงที่ลูกค้าแนบมา — เดิมหน้านี้
                    // generate QR Code พร้อมเพย์ปลอมขึ้นมาเอง ซึ่งไม่มีประโยชน์ตอน
                    // แอดมินเปิดดูจาก "ประวัติการออกบิล" (ไม่ใช่หน้าจ่ายเงินจริง)
                    // เปลี่ยนมาโชว์สลิปที่ลูกค้าอัปโหลดไว้แทน เพื่อให้เห็นหลักฐานจริง
                    // 🆕 [ใหม่] ไม่ต้องโชว์การ์ดสลิปโอนเงินเลยถ้าเป็นบิลประกัน —
                    // ไม่มีการโอนเงินจริงให้ตรวจสอบ
                    if (_totalPrice > 0 && !_isWarrantyCovered) ...[
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'สลิปโอนเงินจากลูกค้า',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            if (_paymentSlipUrl != null)
                              GestureDetector(
                                onTap: () =>
                                    _showSlipPreview(_paymentSlipUrl!),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: LocalOrNetworkImage(
                                    path: _paymentSlipUrl!,
                                    width: 220,
                                    height: 260,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 220,
                                height: 140,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Text(
                                    'ลูกค้ายังไม่ได้แนบสลิปโอนเงิน',
                                    textAlign: TextAlign.center,
                                    style:
                                        TextStyle(color: AppColors.textSubtitle),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 8),
                            Text(
                              'ยอดเงิน: ${_formatPrice(_totalPrice)} บาท',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // การ์ดแสดงรายละเอียดบิล
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'รายละเอียดค่าบริการ',
                                style: TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _isWarrantyCovered
                                      ? AppColors.greenBg
                                      : (_paid
                                          ? AppColors.greenBg
                                          : AppColors.yellowBg),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  _isWarrantyCovered
                                      ? 'ไม่มีค่าใช้จ่าย (ประกัน)'
                                      : (_paid ? 'ชำระเงินแล้ว' : 'รอชำระเงิน'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: (_isWarrantyCovered || _paid)
                                        ? AppColors.greenText
                                        : AppColors.yellowText,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 24),
                          _BillDetailRow(
                              label: 'เลขแจ้งซ่อม', value: _ticketNo),
                          const SizedBox(height: 8),
                          _BillDetailRow(label: 'รหัสบิล', value: _billId),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ยอดที่ต้องชำระ',
                                  style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                '${_formatPrice(_totalPrice)} บาท',
                                style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ปุ่มดำเนินการ
                    if (!_paid)
                      ElevatedButton(
                        onPressed:
                            (_isPaying || _totalPrice <= 0) ? null : _pay,
                        style: AppStyles.primaryButton.copyWith(
                          padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(vertical: 14)),
                        ),
                        child: _isPaying
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5),
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.payment, size: 20),
                                  SizedBox(width: 8),
                                  Text('ยืนยันชำระเงิน',
                                      style: AppStyles.buttonText),
                                ],
                              ),
                      )
                    else ...[
                      ElevatedButton.icon(
                        onPressed: _showReceiptDialog,
                        icon: const Icon(Icons.receipt_long,
                            color: Colors.white),
                        label: const Text('ดูใบเสร็จรับเงิน',
                            style:
                                TextStyle(color: Colors.white, fontSize: 16)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green.shade700,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('เสร็จสิ้น / กลับหน้าหลัก',
                            style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ],
                ),
              ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _BillDetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _BillDetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 15, color: Colors.black54)),
        Text(value,
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: Colors.black87)),
      ],
    );
  }
}