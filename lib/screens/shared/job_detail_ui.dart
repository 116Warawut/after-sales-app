// =============================================================================
// 🎨 JOB DETAIL UI KIT
// ชุด Widget กลางสำหรับหน้า "รายละเอียดงานซ่อม" ของทุก Role
// อ้างอิงสไตล์จากหน้าแอดมิน (assign_repair_formdetail.dart)
//
// ⚠️ ไฟล์นี้มีแต่ "หน้าตา" เท่านั้น ไม่มี logic ธุรกิจใด ๆ
// =============================================================================
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';

// =============================================================================
// SECTION 1: STATUS HELPER (แปลง String สถานะ -> สี)
// =============================================================================

class JobStatusStyle {
  JobStatusStyle._();

  static bool _isDone(String s) =>
      s.contains('เสร็จ') || s.toLowerCase().contains('done') ||
      s.toLowerCase().contains('complete');

  static bool _isInProgress(String s) =>
      s.contains('กำลังดำเนินการ') ||
      s.contains('กำลังซ่อม') ||
      s.toLowerCase().contains('progress');

  static bool _isCancelled(String s) =>
      s.contains('ยกเลิก') || s.toLowerCase().contains('cancel');

  // 🆕 [ใหม่] สถานะ "มีปัญหา / ต้องตรวจสอบ" ที่ช่างแจ้งได้จากหน้ารายละเอียดงาน
  static bool _isProblem(String s) => s.contains('มีปัญหา');

  static Color bgOf(String status) {
    if (_isCancelled(status)) return AppColors.redBg;
    if (_isProblem(status)) return AppColors.redBg;
    if (_isDone(status)) return AppColors.greenBg;
    if (_isInProgress(status)) return AppColors.blueBg;
    return AppColors.yellowBg;
  }

  static Color fgOf(String status) {
    if (_isCancelled(status)) return AppColors.redText;
    if (_isProblem(status)) return AppColors.redText;
    if (_isDone(status)) return AppColors.greenText;
    if (_isInProgress(status)) return AppColors.blueText;
    return AppColors.yellowText;
  }
}

// =============================================================================
// SECTION 1.1: ป๊อปอัพยืนยัน (ใช้ร่วมกันทุกหน้า)
// =============================================================================

/// ป๊อปอัพยืนยันการทำรายการ — คืนค่า true เมื่อผู้ใช้กดยืนยัน
///
/// [danger] = true จะทำให้ปุ่มยืนยันเป็นสีแดงเตือน (ใช้กับยกเลิก / ลบ)
Future<bool> showJobConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'ยืนยัน',
  String cancelLabel = 'ไม่ใช่ตอนนี้',
  IconData icon = Icons.help_outline,
  bool danger = false,
}) async {
  final accent = danger ? AppColors.redText : AppColors.primary;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
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
              decoration: BoxDecoration(
                color: danger ? AppColors.redBg : AppColors.yellowBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppStyles.title.copyWith(
                color: AppColors.textHeading,
                fontSize: 18,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.textSubtitle,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSubtitle,
                      side: const BorderSide(color: AppColors.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      cancelLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  return result ?? false;
}

// =============================================================================
// SECTION 2: LAYOUT (โครงหน้าเดียวกันทุก Role)
// =============================================================================

/// โครงหน้ามาตรฐาน: Header ค้างด้านบน + เนื้อหาเลื่อนได้ padding 20 การ์ดห่างกัน 20
class JobDetailScaffold extends StatelessWidget {
  final Widget header;
  final bool isLoading;
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  const JobDetailScaffold({
    super.key,
    required this.header,
    required this.isLoading,
    required this.children,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    Widget body = ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: children.length,
      separatorBuilder: (_, __) => const SizedBox(height: 20),
      itemBuilder: (_, i) => children[i],
    );

    if (onRefresh != null) {
      body = RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh!,
        child: body,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            header,
            Expanded(
              child: isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary),
                    )
                  : body,
            ),
          ],
        ),
      ),
    );
  }
}

/// การ์ดพื้นฐาน (เหมือน _SectionCard ของแอดมิน)
class JobSectionCard extends StatelessWidget {
  final Widget child;
  const JobSectionCard({super.key, required this.child});

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
          ),
        ],
      ),
      child: child,
    );
  }
}

/// หัวข้อการ์ด
/// [primary] = true  -> สีแดง (ใช้กับการ์ด "รายละเอียดงาน")
/// [primary] = false -> สีเทาเข้ม (ใช้กับการ์ด action เหมือน "มอบหมายช่าง" ของแอดมิน)
class JobSectionTitle extends StatelessWidget {
  final String text;
  final bool primary;
  const JobSectionTitle(this.text, {super.key, this.primary = true});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: AppStyles.title.copyWith(
        color: primary ? AppColors.primary : AppColors.textHeading,
        fontSize: 20,
        fontFamily: AppStyles.fontFamily,
      ),
    );
  }
}

// =============================================================================
// SECTION 3: ข้อมูลย่อย (แถวข้อความ / แบดจ์สถานะ)
// =============================================================================

/// แถวข้อมูล "หัวข้อ : ค่า"
class JobInfoRow extends StatelessWidget {
  final String label;
  final String value;
  const JobInfoRow({super.key, required this.label, required this.value});

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

/// แถวเบอร์โทร (ถ้าส่ง [onCall] มาจะมีปุ่มโทรสีเขียวท้ายแถว)
class JobPhoneRow extends StatelessWidget {
  final String label;
  final String phone;
  final VoidCallback? onCall;

  const JobPhoneRow({
    super.key,
    this.label = 'เบอร์',
    required this.phone,
    this.onCall,
  });

  @override
  Widget build(BuildContext context) {
    final canCall = onCall != null && phone.isNotEmpty && phone != '-';

    return Padding(
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
                  TextSpan(
                    text: '$label : ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(
                    text: phone,
                    style: const TextStyle(fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
          ),
          if (canCall)
            InkWell(
              onTap: onCall,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.phone, color: Colors.green, size: 18),
              ),
            ),
        ],
      ),
    );
  }
}

/// แถวสถานะ + แบดจ์สี
class JobStatusRow extends StatelessWidget {
  final String status;
  const JobStatusRow({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final bg = JobStatusStyle.bgOf(status);
    final fg = JobStatusStyle.fgOf(status);

    return Row(
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.circle, size: 7, color: fg),
              const SizedBox(width: 5),
              Text(
                status,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// SECTION 4: รูปภาพประกอบ
// =============================================================================

/// แถบรูปภาพแนวนอน + สถานะว่าง + แตะเพื่อขยาย
class JobImageStrip extends StatelessWidget {
  final List<String> images;
  final String heading;

  const JobImageStrip({
    super.key,
    required this.images,
    this.heading = 'รูปภาพประกอบ (แตะเพื่อขยาย)',
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          heading,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: AppStyles.fontFamily,
          ),
        ),
        const SizedBox(height: 8),
        images.isEmpty
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
                  itemCount: images.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => showJobImagePreview(context, images[i]),
                    child: JobThumbnail(path: images[i]),
                  ),
                ),
              ),
      ],
    );
  }
}

/// รูปย่อขนาด 80x100
class JobThumbnail extends StatelessWidget {
  final String path;
  const JobThumbnail({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final isNetwork = path.startsWith('http');

    final image = isNetwork
        ? Image.network(
            path,
            width: 80,
            height: 100,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _ThumbFallback(),
          )
        : Image.file(
            File(path),
            width: 80,
            height: 100,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const _ThumbFallback(),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: image,
    );
  }
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 100,
      color: Colors.grey.shade200,
      child: const Icon(Icons.broken_image, color: Colors.grey),
    );
  }
}

/// ป๊อปอัพดูรูปขนาดใหญ่ (ซูมได้)
void showJobImagePreview(BuildContext context, String path) {
  showDialog(
    context: context,
    builder: (ctx) => Dialog(
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
                    errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 80),
                  )
                : Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
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
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
        ],
      ),
    ),
  );
}

// =============================================================================
// SECTION 5: ปุ่ม
// =============================================================================

/// ปุ่มหลักสีแดงเต็มความกว้าง (รองรับสถานะกำลังโหลด)
class JobPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;
  final double verticalPadding;
  final Color? background;

  const JobPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
    this.verticalPadding = 14,
    this.background,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppStyles.primaryButton.copyWith(
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: verticalPadding),
      ),
      backgroundColor:
          background != null ? WidgetStatePropertyAll(background) : null,
    );

    final child = isLoading
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.5,
            ),
          )
        : Text(
            label,
            style: AppStyles.buttonText.copyWith(
              fontFamily: AppStyles.fontFamily,
            ),
          );

    return SizedBox(
      width: double.infinity,
      child: (icon == null || isLoading)
          ? ElevatedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: child,
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: child,
            ),
    );
  }
}

/// ปุ่มรอง (ขอบแดง พื้นใส)
class JobSecondaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const JobSecondaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = AppStyles.secondaryButton.copyWith(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 12),
      ),
    );

    final child = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primary,
            ),
          )
        : Text(
            label,
            style: AppStyles.buttonText.copyWith(
              fontSize: 15,
              fontFamily: AppStyles.fontFamily,
            ),
          );

    return SizedBox(
      width: double.infinity,
      child: (icon == null || isLoading)
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: child,
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: child,
            ),
    );
  }
}

/// ปุ่มอันตราย (ยกเลิก / ลบ) — ขอบแดง พื้นใส
class JobDangerButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const JobDangerButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = OutlinedButton.styleFrom(
      foregroundColor: AppColors.redText,
      side: const BorderSide(color: AppColors.redText, width: 1.5),
      padding: const EdgeInsets.symmetric(vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );

    final child = isLoading
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.redText,
            ),
          )
        : Text(
            label,
            style: AppStyles.buttonText.copyWith(
              fontSize: 15,
              fontFamily: AppStyles.fontFamily,
            ),
          );

    return SizedBox(
      width: double.infinity,
      child: (icon == null || isLoading)
          ? OutlinedButton(
              onPressed: isLoading ? null : onPressed,
              style: style,
              child: child,
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 18),
              label: child,
            ),
    );
  }
}

/// ปุ่มไอคอนสี่เหลี่ยม (ติดต่อสอบถาม / ส่งข้อความ)
class JobActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const JobActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: AppColors.primary),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// SECTION 6: การ์ดผู้ติดต่อ (ใช้ร่วมกันทั้งช่างและลูกค้า)
// =============================================================================

class JobContactCard extends StatelessWidget {
  final String title;
  final String roleLabel;
  final String name;
  final String? code;
  final String? phone;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;

  const JobContactCard({
    super.key,
    required this.title,
    required this.roleLabel,
    required this.name,
    this.code,
    this.phone,
    this.onCall,
    this.onMessage,
  });

  @override
  Widget build(BuildContext context) {
    return JobSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          JobSectionTitle(title, primary: false),
          const SizedBox(height: 16),
          JobInfoRow(label: roleLabel, value: name),
          if (code != null && code != '-')
            JobInfoRow(label: 'รหัสประจำตัว', value: code!),
          if (phone != null && phone != '-')
            JobInfoRow(label: 'เบอร์โทร', value: phone!),
          const SizedBox(height: 16),
          Row(
            children: [
              if (onCall != null) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onCall,
                    icon: const Icon(Icons.phone_outlined,
                        size: 18, color: AppColors.primary),
                    label: const Text(
                      'ติดต่อสอบถาม',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMain,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (onMessage != null)
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onMessage,
                    icon: const Icon(Icons.chat_bubble_outline,
                        size: 18, color: AppColors.primary),
                    label: const Text(
                      'ส่งข้อความ',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textMain,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}