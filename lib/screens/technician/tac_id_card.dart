import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';


/// ข้อมูลบัตรประจำตัวช่าง — แปลงจาก row ของตาราง `technicians`
class EmployeeIdentity {
  final String nameTh;
  final String phone;
  final String employeeId;
  final String? photoUrl;

  const EmployeeIdentity({
    required this.nameTh,
    required this.phone,
    required this.employeeId,
    required this.photoUrl,
  });

  factory EmployeeIdentity.fromMap(Map<String, dynamic> map) {
    return EmployeeIdentity(
      nameTh: (map['tech_name'] as String?) ?? '-',
      phone: (map['phone'] as String?) ?? '-',
      employeeId: (map['employee_id'] as String?) ?? '-',
      photoUrl: map['photo_url'] as String?,
    );
  }
}

class IdentityCardPage extends StatefulWidget {
  const IdentityCardPage({super.key});

  @override
  State<IdentityCardPage> createState() => _IdentityCardPageState();
}

class _IdentityCardPageState extends State<IdentityCardPage> {
  bool _loading = true;
  EmployeeIdentity? _employee;

  @override
  void initState() {
    super.initState();
    _loadEmployee();
  }

  /// ดึงข้อมูลช่างที่ล็อกอินอยู่ตอนนี้จาก SQLite (ตาราง technicians)
  Future<void> _loadEmployee() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final username = db.Session.currentUsername;
      final row =
          await db.DatabaseHelper.instance.getTechnicianByUsername(username);

      if (!mounted) return;
      setState(() {
        _employee = row != null ? EmployeeIdentity.fromMap(row) : null;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading technician identity: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🔒 หัวเรื่องล็อกอยู่นิ่ง ไม่เลื่อนตามเนื้อหา (เหมือนกันทุกสถานะ)
            const AppHeader(title: 'บัตรประจำตัว', showBack: true),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _employee == null
                      ? _buildNotFound()
                      : ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 24, 20, 0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _IdCard(employee: _employee!),
                                  const SizedBox(height: 24),
                                  _BackButton(
                                      onTap: () =>
                                          Navigator.maybePop(context)),
                                ],
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

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'ไม่พบข้อมูลช่าง กรุณาเข้าสู่ระบบใหม่อีกครั้ง',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 16),
            _BackButton(onTap: () => Navigator.maybePop(context)),
          ],
        ),
      ),
    );
  }
}

class _IdCard extends StatelessWidget {
  final EmployeeIdentity employee;
  const _IdCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final hasPhoto = employee.photoUrl != null && employee.photoUrl!.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: hasPhoto
                ? LocalOrNetworkImage(
                    path: employee.photoUrl!,
                    height: 214,
                    fit: BoxFit.cover,
                  )
                : Container(
                    height: 214,
                    color: AppColors.accentIndigo,
                    alignment: Alignment.center,
                    child: const Icon(Icons.person,
                        size: 64, color: Colors.white70),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            employee.nameTh,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.black, fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          _InfoTile(
            icon: Icons.badge,
            label: 'รหัสประจำตัว / EMPLOYEE ID',
            value: employee.employeeId,
          ),
          const SizedBox(height: 12),
          _InfoTile(
            icon: Icons.phone,
            label: 'เบอร์โทรศัพท์ / TEL',
            value: employee.phone,
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoTile(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.redBg,
        border: Border.all(color: AppColors.redBg),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.requiredMark,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w300,
                      letterSpacing: 0.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 60,
          alignment: Alignment.center,
          child: const Text(
            'ย้อนกลับ',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5),
          ),
        ),
      ),
    );
  }
}
