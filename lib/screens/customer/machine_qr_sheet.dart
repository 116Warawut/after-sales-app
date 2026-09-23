import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:after_sales/app_styles.dart';

/// {@template machine_qr_sheet}
/// Bottom sheet แสดง QR Code ที่เข้ารหัสหมายเลข Serial Number ของเครื่องจักร
/// (generate เองด้วย qr_flutter ไม่ใช่รูปจริงแบบ payment_qr_sheet.dart)
///
/// ใช้คู่กับหน้าสแกน QR ที่มีอยู่แล้ว (`qr_scanner_page.dart` +
/// `extractSerialNumberFromQr`) — พิมพ์ QR นี้ออกมาแปะที่ตัวเครื่องจักร แล้ว
/// ลูกค้า/ช่างใช้กล้องสแกนตอนแจ้งซ่อมหรือค้นหาเครื่องจักรได้เลย โดยไม่ต้อง
/// พิมพ์เลข Serial Number เอง (ลด human error สะกด/พิมพ์ผิด)
///
/// วิธีเปิดใช้งาน: เรียก `showMachineQrSheet(context, serialNumber: ..., modelName: ...)`
/// {@endtemplate}
Future<void> showMachineQrSheet(
  BuildContext context, {
  required String serialNumber,
  String modelName = '',
  String label = '',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _MachineQrSheet(
      serialNumber: serialNumber,
      modelName: modelName,
      label: label,
    ),
  );
}

class _MachineQrSheet extends StatefulWidget {
  final String serialNumber;
  final String modelName;
  final String label;

  const _MachineQrSheet({
    required this.serialNumber,
    required this.modelName,
    required this.label,
  });

  @override
  State<_MachineQrSheet> createState() => _MachineQrSheetState();
}

class _MachineQrSheetState extends State<_MachineQrSheet> {
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _isSaving = false;

  bool get _hasSerial =>
      widget.serialNumber.trim().isNotEmpty && widget.serialNumber.trim() != '-';

  /// 📸 แปลง QR (พร้อมกรอบขาว+เลข serial ด้านล่าง) เป็นรูปภาพ แล้วบันทึกลงคลังภาพ
  /// เครื่อง — ใช้ RepaintBoundary จับภาพ widget ตรง ๆ เพื่อให้ได้ทั้ง QR และ
  /// ข้อความเลข serial ในภาพเดียวกัน พร้อมพิมพ์/ส่งต่อได้ทันที
  Future<void> _saveQrImage() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        throw Exception('ไม่พบ QR Code ที่จะบันทึก');
      }
      // pixelRatio สูงหน่อยให้พิมพ์ออกมาคมชัด ไม่แตกเวลาขยาย
      final ui.Image image = await boundary.toImage(pixelRatio: 4);
      final ByteData? byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('แปลงรูปภาพไม่สำเร็จ');
      }
      final bytes = byteData.buffer.asUint8List();
      await Gal.putImageBytes(bytes, album: 'After Sales');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกรูป QR Code ลงคลังภาพแล้ว')),
      );
    } on GalException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.type.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('บันทึกรูปไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
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
              'QR Code เครื่องจักร',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            if (widget.modelName.isNotEmpty || widget.label.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                [
                  if (widget.label.isNotEmpty) 'เครื่อง ${widget.label}',
                  if (widget.modelName.isNotEmpty) widget.modelName,
                ].join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSubtitle,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            ],
            const SizedBox(height: 20),

            if (!_hasSerial)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'เครื่องจักรนี้ยังไม่มีหมายเลข Serial Number\nจึงยังสร้าง QR Code ไม่ได้',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSubtitle),
                ),
              )
            else ...[
              // 🖼️ RepaintBoundary ครอบทั้งกรอบ QR + ข้อความ เพื่อให้บันทึกภาพ
              // ออกมาเป็นภาพเดียวกัน พร้อมพิมพ์/ส่งต่อได้เลย
              RepaintBoundary(
                key: _qrBoundaryKey,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      QrImageView(
                        data: widget.serialNumber,
                        version: QrVersions.auto,
                        size: 220,
                        backgroundColor: Colors.white,
                        gapless: true,
                        errorStateBuilder: (context, error) => const Center(
                          child: Text(
                            'สร้าง QR Code ไม่สำเร็จ',
                            style: TextStyle(color: AppColors.redText),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.tag,
                              size: 15, color: Colors.black54),
                          const SizedBox(width: 4),
                          Text(
                            widget.serialNumber,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'พิมพ์ QR นี้แปะไว้ที่ตัวเครื่องจักร แล้วใช้กล้องสแกนตอนแจ้งซ่อมได้เลย',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSubtitle),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveQrImage,
                  style: AppStyles.primaryButton.copyWith(
                    padding: const WidgetStatePropertyAll(
                        EdgeInsets.symmetric(vertical: 14)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.download_outlined,
                          color: Colors.white),
                  label: Text(
                    _isSaving ? 'กำลังบันทึก...' : 'บันทึกรูป QR ลงคลังภาพ',
                    style: AppStyles.buttonText,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ปิด'),
            ),
          ],
        ),
      ),
    );
  }
}
