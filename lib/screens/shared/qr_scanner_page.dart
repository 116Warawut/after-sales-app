import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:after_sales/app_styles.dart';

/// ==========================================
/// 📷 หน้าสแกน QR Code (ใช้ร่วมกันทั้งระบบ)
/// ==========================================
/// สแกน QR Code ที่ติดอยู่บนตัวเครื่องจักร แล้วส่งค่าข้อความที่อ่านได้
/// (โดยทั่วไปคือ Serial Number) กลับไปยังหน้าที่เรียกใช้งานผ่าน
/// `Navigator.of(context).pop(value)`
class QrScannerPage extends StatefulWidget {
  /// ข้อความหัวข้อของหน้าสแกน เช่น 'สแกน QR Code เครื่องจักร'
  final String title;

  /// คำแนะนำที่แสดงใต้กรอบสแกน
  final String hintText;

  /// 🔎 ตัวตรวจ/แยกค่าที่ต้องการจากข้อความดิบที่สแกนได้ (raw QR value)
  ///
  /// ใช้เพื่อ "ยืนยันว่านี่คือค่าที่ต้องการจริง ๆ" ก่อนปิดหน้าสแกน เช่น
  /// เวลาสแกนหา Serial Number ให้ส่ง `extractSerialNumberFromQr` เข้ามา —
  /// ถ้า QR Code ที่สแกนได้ไม่ใช่รูปแบบที่ต้องการ (คืนค่า null) หน้าจอจะ
  /// แจ้งเตือนแล้วให้สแกนต่อ แทนที่จะปิดหน้าแล้วส่งค่าผิด ๆ กลับไป
  ///
  /// ถ้าไม่ระบุ จะส่งค่าดิบที่อ่านได้กลับไปตรง ๆ เหมือนเดิม
  final String? Function(String rawValue)? valueExtractor;

  /// ข้อความแจ้งเตือนเมื่อสแกนได้ QR Code ที่ไม่ตรงกับรูปแบบที่ต้องการ
  /// (ใช้เมื่อระบุ [valueExtractor] เท่านั้น)
  final String invalidValueMessage;

  const QrScannerPage({
    super.key,
    this.title = 'สแกน QR Code',
    this.hintText = 'นำกล้องส่องไปที่ QR Code บนตัวเครื่องจักร',
    this.valueExtractor,
    this.invalidValueMessage = 'QR Code นี้ไม่ตรงกับรูปแบบที่ต้องการ ลองสแกนใหม่อีกครั้ง',
  });

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  // 🔴 [แก้ไข] mobile_scanner รุ่น 7.x เปลี่ยนวิธีทำงาน — ต้องปล่อยให้ widget
  // MobileScanner เป็นคนเรียก start() เองตอนมันถูก build/attach เข้าจอจริง ๆ
  // ห้ามเรียก controller.start() เองก่อนสร้าง widget แบบที่เคยทำไว้ (จัดการ
  // lifecycle เองด้วย WidgetsBindingObserver) เพราะ 7.x จะโยน
  // MobileScannerException(controllerNotAttached, ...) ทันทีถ้า start() ถูก
  // เรียกก่อน widget ถูก attach — ปล่อยให้ autoStart (ค่าเริ่มต้น = true) จัดการ
  // ทั้งหมดเอง ปลั๊กอินดูแล pause/resume ตอนแอปสลับพื้นหลัง/กลับมาให้เองอยู่แล้ว
  MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handled = false;
  bool _torchOn = false;
  // กันแจ้งเตือน "QR Code ไม่ตรงรูปแบบ" ซ้อนกันหลายอันตอนกล้องยังจับภาพต่อเนื่อง
  bool _showingInvalidMessage = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue?.trim();
      if (rawValue == null || rawValue.isEmpty) continue;

      final extractor = widget.valueExtractor;
      if (extractor == null) {
        _handled = true;
        Navigator.of(context).pop(rawValue);
        return;
      }

      // 🔍 ตรวจว่า QR Code ที่สแกนได้นี้ "คือ" ค่าที่ต้องการจริงหรือไม่
      // (เช่น เป็นหมายเลข Serial Number ตามรูปแบบที่กำหนด) ก่อนปิดหน้าสแกน
      final extracted = extractor(rawValue);
      if (extracted == null) {
        _flashInvalidValueMessage();
        continue; // ไม่ใช่รูปแบบที่ต้องการ — ปล่อยให้สแกนต่อ ไม่ปิดหน้า
      }

      _handled = true;
      Navigator.of(context).pop(extracted);
      return;
    }
  }

  void _flashInvalidValueMessage() {
    if (_showingInvalidMessage || !mounted) return;
    _showingInvalidMessage = true;
    ScaffoldMessenger.of(context)
        .showSnackBar(
          SnackBar(
            content: Text(
              widget.invalidValueMessage,
              style: const TextStyle(fontFamily: AppStyles.fontFamily),
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
        )
        .closed
        .then((_) => _showingInvalidMessage = false);
  }

  Future<void> _toggleTorch() async {
    await _controller.toggleTorch();
    if (!mounted) return;
    setState(() => _torchOn = !_torchOn);
  }

  // 🔁 สร้างตัวควบคุมกล้องใหม่ทั้งหมด — ใช้ตอนกด "ลองเปิดกล้องอีกครั้ง"
  // (ทิ้งตัวเก่าที่พังไปแล้วสร้างใหม่ สะอาดกว่าพยายามเรียก start() ซ้ำตัวเดิม)
  void _retryCamera() {
    final oldController = _controller;
    setState(() {
      _torchOn = false;
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
      );
    });
    oldController.dispose();
  }

  // ⌨️ ให้พิมพ์รหัสเองแทนการสแกน — ใช้เป็นทางออกสำรองเมื่อกล้องเปิดไม่ได้/ค้าง
  // (เช่นปัญหาจากปลั๊กอินกล้องบนบางรุ่นเครื่อง) จะได้ไม่ตันไปทั้งฟีเจอร์
  Future<void> _enterManually() async {
    final controller = TextEditingController();
    String? errorText;

    final value = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'พิมพ์รหัสเอง',
            style: TextStyle(fontFamily: AppStyles.fontFamily),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'พิมพ์หมายเลข Serial บนตัวเครื่องจักร',
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: (_) {
              if (errorText != null) setDialogState(() => errorText = null);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                final raw = controller.text.trim();
                final extractor = widget.valueExtractor;
                if (extractor == null) {
                  Navigator.pop(context, raw);
                  return;
                }
                // ✅ พิมพ์เองก็ต้องผ่านการตรวจรูปแบบเดียวกับตอนสแกนด้วย
                final extracted = extractor(raw);
                if (extracted == null) {
                  setDialogState(() => errorText = widget.invalidValueMessage);
                  return;
                }
                Navigator.pop(context, extracted);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('ยืนยัน'),
            ),
          ],
        ),
      ),
    );

    if (value != null && value.isNotEmpty && mounted) {
      _handled = true;
      Navigator.of(context).pop(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _enterManually,
            icon: const Icon(Icons.keyboard_outlined),
            tooltip: 'พิมพ์รหัสเอง',
          ),
          IconButton(
            onPressed: _toggleTorch,
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
          ),
          IconButton(
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 🔑 key: ValueKey(_controller) — เวลากด "ลองเปิดกล้องอีกครั้ง" แล้ว
          // สร้าง controller ตัวใหม่ ต้องบังคับให้ Flutter สร้าง MobileScanner
          // element ใหม่ทั้งตัวด้วย (ไม่ใช่แค่ rebuild ของเดิม) ไม่งั้นบาง
          // เวอร์ชันของปลั๊กอินจะยังผูกกับ controller ตัวเก่าที่ dispose ไปแล้วอยู่
          MobileScanner(
            key: ValueKey(_controller),
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.videocam_off_outlined,
                          color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Text(
                        'เปิดกล้องไม่สำเร็จ: '
                        '${error.errorDetails?.message ?? error.errorCode}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _retryCamera,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: const Icon(Icons.refresh),
                        label: const Text(
                          'ลองเปิดกล้องอีกครั้ง',
                          style: TextStyle(fontFamily: AppStyles.fontFamily),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: _enterManually,
                        icon: const Icon(Icons.keyboard_outlined,
                            color: Colors.white70),
                        label: const Text(
                          'พิมพ์รหัสเอง แทนการสแกน',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          // กรอบสแกนตรงกลางจอ
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.hintText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
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
