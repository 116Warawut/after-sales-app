import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/customer/customer_job_detail.dart';
import 'package:after_sales/screens/customer/machine_qr_sheet.dart';
import 'package:after_sales/screens/customer/repair_form.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'machine_models.dart';

class MachineDetailPage extends StatefulWidget {
  final Machine machine;

  const MachineDetailPage({super.key, required this.machine});

  @override
  State<MachineDetailPage> createState() => _MachineDetailPageState();
}

class _MachineDetailPageState extends State<MachineDetailPage> {
  Machine get machine => widget.machine;

  bool _loadingHistory = true;
  List<Map<String, dynamic>> _repairHistory = [];
  bool _showAllHistory = false;
  static const int _historyPreviewCount = 10;

  @override
  void initState() {
    super.initState();
    _loadRepairHistory();
  }

  /// 🔄 ดึงประวัติการซ่อมทั้งหมดของเครื่องนี้ (ทุกสถานะ)
  Future<void> _loadRepairHistory() async {
    // 🔧 [แก้ mismatch] เครื่องที่แอดมินเพิ่มผ่านเว็บมี id เป็น push-key (string) ฝั่ง
    // แอปแปลงเป็น int ไม่ได้ (machine.id = null) จึง fallback ไปจับคู่ด้วย serial_number
    final serial = machine.serialNumber.trim();
    final hasSerial = serial.isNotEmpty && serial != '-';
    if (machine.id == null && !hasSerial) {
      setState(() => _loadingHistory = false);
      return;
    }
    setState(() => _loadingHistory = true);
    try {
      final rows = await db.DatabaseHelper.instance.getRepairsForMachine(
        machineId: machine.id,
        serialNumber: machine.serialNumber,
      );
      if (!mounted) return;
      setState(() {
        _repairHistory = rows;
        _loadingHistory = false;
      });
    } catch (e) {
      debugPrint('Error loading machine repair history: $e');
      if (!mounted) return;
      setState(() => _loadingHistory = false);
    }
  }

  /// เปิดหน้าแบบฟอร์มแจ้งซ่อมหลัก (RepairFormScreen) พร้อมเติมข้อมูลเครื่องจักรนี้ไว้ล่วงหน้า
  /// ใช้ฟอร์มเดียวกับทางเข้าอื่นๆ ทั้งหมด เพื่อให้ทุกงานซ่อมผ่านการตรวจสอบข้อมูล/แนบรูป/
  /// geocode ที่อยู่ตามมาตรฐานเดียวกัน
  Future<void> _goToRepairForm() async {
    final submitted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => RepairFormScreen(preselectedMachine: machine),
      ),
    );

    if (submitted == true && mounted) {
      _loadRepairHistory();
    }
  }

  /// 🆕 [ใหม่] เปิด bottom sheet แสดง QR Code ที่เข้ารหัสหมายเลข Serial Number
  /// ของเครื่องจักรนี้ (ใช้คู่กับหน้าสแกน QR ที่มีอยู่แล้ว) — พิมพ์แปะเครื่องได้
  void _showQrSheet() {
    showMachineQrSheet(
      context,
      serialNumber: machine.serialNumber,
      modelName: machine.modelName,
      label: machine.label,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'รายละเอียดเครื่องจักร', showBack: true),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header: รูปภาพประกอบ + ชื่อรุ่น + Serial Number
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: ShapeDecoration(
                              shape: RoundedRectangleBorder(
                                side: BorderSide(
                                  width: 2,
                                  color: Colors.black.withValues(alpha: 0.10),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: machine.photoUrl.isEmpty
                                ? Container(
                                    color: AppColors.textHint,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.precision_manufacturing,
                                      color: Colors.white,
                                      size: 36,
                                    ),
                                  )
                                : LocalOrNetworkImage(
                                    path: machine.photoUrl,
                                    width: 90,
                                    height: 90,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  machine.modelName,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.tag,
                                      size: 13,
                                      color: Colors.black54,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      machine.serialNumber,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w300,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body: การ์ดแสดงข้อมูลรายละเอียดบนพื้นหลังสีเทา
                    Container(
                      width: double.infinity,
                      color: AppColors.surface,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _InfoCard(
                            title: 'ข้อมูลเครื่องจักร',
                            trailing: InkWell(
                              onTap: _showQrSheet,
                              borderRadius: BorderRadius.circular(20),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.qr_code_2,
                                        size: 16, color: AppColors.primary),
                                    SizedBox(width: 4),
                                    Text(
                                      'แสดง QR',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                _FieldRow(
                                  icon: Icons.confirmation_number_outlined,
                                  label: 'เลขซีเรียล (Serial Number)',
                                  value: machine.serialNumber,
                                ),
                                const Divider(height: 1),
                                _FieldRow(
                                  icon: Icons.precision_manufacturing_outlined,
                                  label: 'ชื่อรุ่น',
                                  value: machine.modelName,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          _InfoCard(
                            title: 'ตำแหน่งที่ตั้งเครื่องจักร',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'ที่อยู่',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _AddressField(
                                          label: 'บ้านเลขที่',
                                          value: machine.address.houseNo,
                                        ),
                                        _AddressField(
                                          label: 'หมู่',
                                          value: machine.address.moo,
                                        ),
                                        _AddressField(
                                          label: 'ตำบล',
                                          value: machine.address.tambon,
                                        ),
                                        _AddressField(
                                          label: 'อำเภอ',
                                          value: machine.address.amphoe,
                                        ),
                                        _AddressField(
                                          label: 'จังหวัด',
                                          value: machine.address.changwat,
                                        ),
                                        _AddressField(
                                          label: 'รหัสไปรษณีย์',
                                          value: machine.address.zipCode,
                                        ),
                                        const SizedBox(height: 12),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border.all(
                                              color: Colors.black.withValues(
                                                alpha: 0.10,
                                              ),
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'ที่อยู่เต็ม',
                                                style: TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                machine.address.fullAddress,
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w300,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          _InfoCard(
                            title: 'สถานะประกัน',
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: ShapeDecoration(
                                  shape: RoundedRectangleBorder(
                                    side: BorderSide(
                                      color: machine.warrantyActive
                                          ? AppColors.greenText
                                          : AppColors.redText,
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      machine.warrantyActive
                                          ? Icons.verified
                                          : Icons.error_outline,
                                      size: 28,
                                      color: machine.warrantyActive
                                          ? AppColors.greenText
                                          : AppColors.redText,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            machine.warrantyActive
                                                ? 'อยู่ในระยะประกัน'
                                                : 'ประกันหมดอายุแล้ว',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            machine.warrantyExpiryText,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w300,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          _InfoCard(
                            title: _repairHistory.isEmpty || _loadingHistory
                                ? 'ประวัติการซ่อม'
                                : 'ประวัติการซ่อม (${_repairHistory.length} ครั้ง)',
                            child: _loadingHistory
                                ? const Padding(
                                    padding: EdgeInsets.symmetric(vertical: 24),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                          color: AppColors.primary),
                                    ),
                                  )
                                : _repairHistory.isEmpty
                                    ? const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'ยังไม่มีประวัติการซ่อม',
                                          style: TextStyle(
                                              color: AppColors.textSubtitle),
                                        ),
                                      )
                                    : Column(
                                        children: [
                                          for (final row in (_showAllHistory
                                              ? _repairHistory
                                              : _repairHistory
                                                  .take(_historyPreviewCount)
                                                  .toList()))
                                            _RepairHistoryTile(
                                              row: row,
                                              onTap: () async {
                                                await Navigator.of(context)
                                                    .push(
                                                  MaterialPageRoute(
                                                    builder: (context) =>
                                                        CustomerJobDetailPage(
                                                      repairId:
                                                          toIntOrNull(
                                                              row['id']),
                                                    ),
                                                  ),
                                                );
                                                if (!mounted) return;
                                                _loadRepairHistory();
                                              },
                                            ),
                                          if (!_showAllHistory &&
                                              _repairHistory.length >
                                                  _historyPreviewCount)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.all(12),
                                              child: TextButton(
                                                onPressed: () => setState(
                                                    () =>
                                                        _showAllHistory = true),
                                                child: Text(
                                                  'ดูทั้งหมด (${_repairHistory.length} รายการ)',
                                                  style: const TextStyle(
                                                      color:
                                                          AppColors.primary),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                          ),
                          const SizedBox(height: 16),

                          // ปุ่มกดส่งแจ้งซ่อม (เปิดฟอร์มแจ้งซ่อมหลัก พร้อมเติมข้อมูลเครื่องจักรนี้)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _goToRepairForm,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  side: const BorderSide(
                                    color: AppColors.primary,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              icon: const Icon(Icons.build_outlined),
                              label: const Text(
                                'แจ้งซ่อม',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
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

// ---------------------------------------------------------------------------
// Reusable Sub-Widgets
// ---------------------------------------------------------------------------

class _RepairHistoryTile extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onTap;

  const _RepairHistoryTile({required this.row, required this.onTap});

  _StatusStyle get _status {
    final raw = ((row['status']?.toString()) ?? '').trim();
    if (raw.contains('เสร็จ')) {
      return const _StatusStyle('เสร็จสิ้น', AppColors.greenText);
    }
    if (raw.contains('มีปัญหา')) {
      return const _StatusStyle('มีปัญหา', AppColors.redText);
    }
    // 🆕 [ใหม่] แยก "กำลังเดินทาง" ออกจาก "กำลังซ่อม" ให้ตรงกับสถานะจริง — เดิม
    // ไม่มีเคสนี้เลย ตกไปเป็น "รอจัดสรรช่าง" (default) ผิด ๆ
    if (raw.contains('กำลังเดินทาง')) {
      return const _StatusStyle('กำลังเดินทาง', Color(0xFF1D4ED8));
    }
    if (raw.contains('กำลังดำเนินการ') || raw.contains('กำลังซ่อม')) {
      return const _StatusStyle('กำลังซ่อม', AppColors.blueText);
    }
    return const _StatusStyle('รอจัดสรรช่าง', AppColors.yellowText);
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final ticketNo = (row['ticketNo']?.toString()) ?? '-';
    final date = (row['date']?.toString()) ?? '-';

    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0x0F000000))),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ticketNo,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSubtitle),
                  ),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: status.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                status.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: status.color,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color color;
  const _StatusStyle(this.label, this.color);
}

class _InfoCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _InfoCard({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            width: 1,
            color: Colors.black.withValues(alpha: 0.10),
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 3,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.65,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FieldRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 16, color: Colors.black54),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w300,
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

class _AddressField extends StatelessWidget {
  final String label;
  final String value;

  const _AddressField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w300),
            ),
          ),
        ],
      ),
    );
  }
}
