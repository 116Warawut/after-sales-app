import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:after_sales/screens/admin/customer_models.dart';
import 'package:after_sales/screens/customer/machine_models.dart';
import 'package:after_sales/screens/shared/qr_scanner_page.dart';
import 'package:after_sales/utils/serial_number.dart';
import 'package:after_sales/utils/thai_address.dart';

/// ==========================================
/// 📋 หน้าแก้ไขข้อมูลลูกค้า (แบบ B: แท็บแยก)
/// ==========================================
/// แท็บที่ 1: ข้อมูลลูกค้าทั่วไป (ชื่อ, บริษัท, เบอร์, อีเมล, ที่อยู่)
/// แท็บที่ 2: เครื่องจักรของลูกค้า — ดู/เพิ่ม/แก้ไข พร้อมสถานะประกันที่คำนวณสด
///           (badge สี: เขียว=ปกติ, เหลือง=ใกล้หมด, แดง=หมดแล้ว, เทา=ไม่มีข้อมูล)
class CustomerEditPage extends StatefulWidget {
  final CustomerItem customer;

  const CustomerEditPage({super.key, required this.customer});

  @override
  State<CustomerEditPage> createState() => _CustomerEditPageState();
}

class _CustomerEditPageState extends State<CustomerEditPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _loadingMachines = true;
  List<Machine> _machines = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMachines();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadMachines() async {
    setState(() => _loadingMachines = true);
    try {
      final rows = await db.DatabaseHelper.instance
          .getMachinesForCustomer(widget.customer.username);
      if (!mounted) return;
      setState(() {
        _machines = rows.map((m) => Machine.fromMap(m)).toList();
        _loadingMachines = false;
      });
    } catch (e) {
      debugPrint('Error loading machines: $e');
      if (!mounted) return;
      setState(() => _loadingMachines = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openMachineDialog({Machine? existing}) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => _MachineFormPage(
          customerUsername: widget.customer.username,
          existing: existing,
        ),
      ),
    );
    if (result == true) {
      await _loadMachines();
      _showSnack(existing == null ? 'เพิ่มเครื่องจักรเรียบร้อย' : 'บันทึกเครื่องจักรเรียบร้อย');
    }
  }

  Future<void> _confirmDeleteMachine(Machine machine) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบเครื่องจักร'),
        content: Text('ต้องการลบ "${machine.modelName}" (SN: ${machine.serialNumber}) ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && machine.id != null) {
      try {
        await db.DatabaseHelper.instance.deleteMachine(machine.id!);
        await _loadMachines();
        _showSnack('ลบเครื่องจักรเรียบร้อยแล้ว');
      } catch (e) {
        debugPrint('Error deleting machine: $e');
        _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _tabController.index == 1
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () => _openMachineDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppHeader(title: widget.customer.fullName, showBack: true),
            Container(
              color: AppColors.primary,
              child: TabBar(
                controller: _tabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
                onTap: (_) => setState(() {}), // รีเฟรช FAB ตามแท็บที่เลือก
                tabs: [
                  const Tab(text: 'ข้อมูลลูกค้า'),
                  Tab(text: 'เครื่องจักร (${_machines.length})'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _CustomerInfoTab(customer: widget.customer),
                  _MachinesTab(
                    loading: _loadingMachines,
                    machines: _machines,
                    onEdit: (m) => _openMachineDialog(existing: m),
                    onDelete: _confirmDeleteMachine,
                    onRefresh: _loadMachines,
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

// ==========================================
// แท็บ 1: ข้อมูลลูกค้า
// ==========================================
class _CustomerInfoTab extends StatefulWidget {
  final CustomerItem customer;
  const _CustomerInfoTab({required this.customer});

  @override
  State<_CustomerInfoTab> createState() => _CustomerInfoTabState();
}

class _CustomerInfoTabState extends State<_CustomerInfoTab> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _companyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  // 🔴 [แก้ไข] เปลี่ยนที่อยู่จากช่องเดียวเป็นแยกฟิลด์ (บ้านเลขที่/หมู่/ตำบล/
  // อำเภอ/จังหวัด/รหัสไปรษณีย์) ให้ตรงกับคอลัมน์จริงที่ใช้ทั้งระบบ (เหมือนหน้า
  // เพิ่มลูกค้าใหม่ใน manage_customer.dart และหน้าโปรไฟล์ลูกค้า)
  late final TextEditingController _houseNoController;
  late final TextEditingController _mooController;
  late final TextEditingController _tambonController;
  late final TextEditingController _amphoeController;
  late final TextEditingController _changwatController;
  late final TextEditingController _zipController;

  bool _isSaving = false;
  // 🆕 [ใหม่] รายชื่อจังหวัด/อำเภอ/ตำบล — ใช้กับช่องค้นหาแบบ Autocomplete
  List<ThaiProvince> _thaiProvinces = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.customer.fullName);
    _companyController = TextEditingController(text: widget.customer.company);
    _phoneController = TextEditingController(text: widget.customer.phone);
    _emailController = TextEditingController(text: widget.customer.email);
    _houseNoController =
        TextEditingController(text: widget.customer.houseNo);
    _mooController = TextEditingController(text: widget.customer.moo);
    _tambonController = TextEditingController(
        text: cleanThaiAddressPrefix(widget.customer.tambon));
    _amphoeController = TextEditingController(
        text: cleanThaiAddressPrefix(widget.customer.amphoe));
    _changwatController = TextEditingController(
        text: cleanThaiAddressPrefix(widget.customer.changwat));
    _zipController = TextEditingController(text: widget.customer.postalCode);
    loadThaiProvinces().then((provinces) {
      if (!mounted) return;
      setState(() => _thaiProvinces = provinces);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _companyController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _houseNoController.dispose();
    _mooController.dispose();
    _tambonController.dispose();
    _amphoeController.dispose();
    _changwatController.dispose();
    _zipController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final fullNameParts = _nameController.text.trim().split(' ');
    final name = fullNameParts.first;
    final surname =
        fullNameParts.length > 1 ? fullNameParts.sublist(1).join(' ') : '';

    try {
      await db.DatabaseHelper.instance.updateCustomerProfile(
        widget.customer.username,
        {
          'name': name,
          'surname': surname,
          'company': _companyController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          'house_no': _houseNoController.text.trim(),
          'moo': _mooController.text.trim(),
          'tambon': _tambonController.text.trim(),
          'amphoe': _amphoeController.text.trim(),
          'changwat': _changwatController.text.trim(),
          'postal_code': _zipController.text.trim(),
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกข้อมูลลูกค้าเรียบร้อยแล้ว')),
      );
    } catch (e) {
      debugPrint('Error saving customer: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'ชื่อ-นามสกุล',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _companyController,
              decoration: const InputDecoration(
                labelText: 'บริษัท',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทรศัพท์',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'อีเมล',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 20),
            const Text(
              'ที่อยู่',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _houseNoController,
                    decoration: const InputDecoration(
                      labelText: 'บ้านเลขที่',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _mooController,
                    decoration: const InputDecoration(
                      labelText: 'หมู่',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 🐛 [แก้บัค] เดิมเป็นช่องพิมพ์เปล่า ๆ เรียงตำบล->อำเภอ->จังหวัด
            // (เล็กไปใหญ่ ไม่มีค้นหา/ไล่ระดับ) — เปลี่ยนเป็นช่องค้นหาแบบเดียว
            // กับหน้าลงทะเบียน/แจ้งซ่อม เรียงจังหวัด -> อำเภอ/เขต -> ตำบล/แขวง
            ThaiAddressAutocompleteField(
              key: ValueKey('changwat_${_changwatController.text}'),
              labelText: 'จังหวัด',
              controller: _changwatController,
              optionsBuilder: () =>
                  _thaiProvinces.map((p) => p.name).toList(),
              onSelected: (value) {
                setState(() {
                  _changwatController.text = value;
                  _amphoeController.clear();
                  _tambonController.clear();
                  _zipController.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            ThaiAddressAutocompleteField(
              key: ValueKey(
                  'amphoe_${_changwatController.text}_${_amphoeController.text}'),
              labelText: 'อำเภอ / เขต',
              controller: _amphoeController,
              enabled: _changwatController.text.trim().isNotEmpty,
              optionsBuilder: () =>
                  thaiAmphoeOptions(_thaiProvinces, _changwatController.text),
              onSelected: (value) {
                setState(() {
                  _amphoeController.text = value;
                  _tambonController.clear();
                  _zipController.clear();
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ThaiAddressAutocompleteField(
                    key: ValueKey(
                        'tambon_${_changwatController.text}_${_amphoeController.text}_${_tambonController.text}'),
                    labelText: 'ตำบล / แขวง',
                    controller: _tambonController,
                    enabled: _changwatController.text.trim().isNotEmpty &&
                        _amphoeController.text.trim().isNotEmpty,
                    optionsBuilder: () => thaiTambonOptions(_thaiProvinces,
                        _changwatController.text, _amphoeController.text),
                    onSelected: (value) {
                      setState(() {
                        _tambonController.text = value;
                        final zip = thaiZipFor(
                            _thaiProvinces,
                            _changwatController.text,
                            _amphoeController.text,
                            value);
                        if (zip != null) _zipController.text = zip;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _zipController,
                    readOnly: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'รหัสไปรษณีย์',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('บันทึกข้อมูลลูกค้า'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// แท็บ 2: เครื่องจักร + ประกัน
// ==========================================
class _MachinesTab extends StatelessWidget {
  final bool loading;
  final List<Machine> machines;
  final ValueChanged<Machine> onEdit;
  final ValueChanged<Machine> onDelete;
  final Future<void> Function() onRefresh;

  const _MachinesTab({
    required this.loading,
    required this.machines,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (machines.isEmpty) {
      return RefreshIndicator(
        color: AppColors.primary,
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Text(
                  'ลูกค้ายังไม่มีเครื่องจักร\nกดปุ่ม + เพื่อเพิ่มเครื่องจักรให้ลูกค้า',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
        itemCount: machines.length,
        itemBuilder: (context, index) {
          final m = machines[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _MachineCard(
              machine: m,
              onTap: () => onEdit(m),
              onDelete: () => onDelete(m),
            ),
          );
        },
      ),
    );
  }
}

class _MachineCard extends StatelessWidget {
  final Machine machine;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MachineCard({
    required this.machine,
    required this.onTap,
    required this.onDelete,
  });

  _WarrantyBadgeStyle get _badge {
    switch (machine.warrantyState) {
      case WarrantyState.active:
        return const _WarrantyBadgeStyle('ปกติ', AppColors.greenText);
      case WarrantyState.expiringSoon:
        return const _WarrantyBadgeStyle('ใกล้หมด', AppColors.yellowText);
      case WarrantyState.expired:
        return const _WarrantyBadgeStyle('หมดประกัน', AppColors.redText);
      case WarrantyState.none:
        return _WarrantyBadgeStyle('ไม่มีข้อมูล', Colors.grey.shade600);
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              // รูปเครื่องจักร
              machine.photoUrl.isEmpty
                  ? Container(
                      width: 72,
                      color: AppColors.textHint,
                      alignment: Alignment.center,
                      child: const Icon(Icons.precision_manufacturing,
                          color: Colors.white, size: 26),
                    )
                  : LocalOrNetworkImage(
                      path: machine.photoUrl,
                      width: 72,
                      fit: BoxFit.cover,
                    ),
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        machine.modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SN: ${machine.serialNumber}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: badge.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${badge.label} • ${machine.warrantyStatusText}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: badge.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: onDelete,
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WarrantyBadgeStyle {
  final String label;
  final Color color;
  const _WarrantyBadgeStyle(this.label, this.color);
}

// ==========================================
// หน้าเพิ่ม/แก้ไขเครื่องจักร + ประกัน (แบบเต็มหน้าจอ)
// ==========================================
// 🔴 [แก้ไข] BEFORE: เดิมเป็น AlertDialog เล็ก ๆ ไม่มีรูปเครื่องจักร ไม่มีปุ่ม
// สแกน QR Code — หน้าตา/การใช้งานไม่ตรงกับฝั่งลูกค้า (AddMachinePage) ทำให้
// แอดมินกรอกข้อมูลเครื่องจักรได้ไม่ครบเท่าที่ลูกค้าทำได้เอง
//
// AFTER: เปลี่ยนเป็นหน้าเต็มจอ ทำหน้าตา/ลำดับการกรอกให้เหมือนฝั่งลูกค้า —
// มีรูปเครื่องจักร (ถ่าย/เลือกรูป อัปโหลดขึ้น Cloudinary), ปุ่มสแกน QR Code
// เพื่อดึง Serial Number, ฟอร์มไอคอนนำหน้าแบบเดียวกัน — ต่างจากฝั่งลูกค้าแค่มี
// ส่วน "ข้อมูลประกัน" เพิ่มมาให้แอดมินกรอกได้ในหน้าเดียวกัน
class _MachineFormPage extends StatefulWidget {
  final String customerUsername;
  final Machine? existing;

  const _MachineFormPage({required this.customerUsername, this.existing});

  @override
  State<_MachineFormPage> createState() => _MachineFormPageState();
}

class _MachineFormPageState extends State<_MachineFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _modelController;
  late final TextEditingController _serialController;

  DateTime? _warrantyStart;
  int? _warrantyMonths; // null = ไม่ระบุ/ไม่มีประกัน

  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  static const List<int?> _monthOptions = [null, 6, 12, 24, 36];

  String _monthLabel(int? m) {
    if (m == null) return 'ไม่ระบุประกัน';
    return '$m เดือน';
  }

  // 📷 รูปภาพเครื่องจักร (เลือกจากแกลเลอรีหรือถ่ายรูปใหม่) — เหมือนฝั่งลูกค้า
  final ImagePicker _picker = ImagePicker();
  String _photoPath = '';
  XFile? _pickedPhotoFile;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _labelController = TextEditingController(text: existing?.label ?? '');
    _modelController = TextEditingController(text: existing?.modelName ?? '');
    _serialController =
        TextEditingController(text: existing?.serialNumber ?? '');
    _warrantyStart = existing?.warrantyStartDate;
    _warrantyMonths = existing?.warrantyMonths;
    _photoPath = existing?.photoUrl ?? '';
  }

  @override
  void dispose() {
    _labelController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// เลือกรูปภาพเครื่องจักรจากแกลเลอรีหรือถ่ายรูปใหม่ด้วยกล้อง
  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera, color: AppColors.primary),
              title: const Text('ถ่ายรูปใหม่',
                  style: TextStyle(fontFamily: AppStyles.fontFamily)),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('เลือกจากคลังภาพ',
                  style: TextStyle(fontFamily: AppStyles.fontFamily)),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      final picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null || !mounted) return;
      setState(() {
        _photoPath = picked.path;
        _pickedPhotoFile = picked;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack('เลือกรูปไม่สำเร็จ: $e');
    }
  }

  /// สแกน QR Code บนตัวเครื่องจักรเพื่อดึงหมายเลข Serial Number มาใส่ในฟอร์ม
  Future<void> _scanSerialNumber() async {
    final scannedValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const QrScannerPage(
          title: 'สแกน QR Code เครื่องจักร',
          hintText: 'นำกล้องส่องไปที่ QR Code บนตัวเครื่องจักรเพื่อดึงหมายเลข Serial',
          // ✅ ยอมรับเฉพาะ QR Code ที่มีหมายเลข Serial Number (รูปแบบ 2-2-4)
          valueExtractor: extractSerialNumberFromQr,
          invalidValueMessage:
              'QR Code นี้ไม่ใช่หมายเลข Serial Number ($kSerialNumberLength หลัก) ลองสแกนใหม่อีกครั้ง',
        ),
      ),
    );
    if (scannedValue == null || scannedValue.trim().isEmpty || !mounted) {
      return;
    }
    setState(() => _serialController.text = scannedValue.trim());
    _showSnack('ดึงหมายเลข Serial จาก QR Code เรียบร้อยแล้ว');
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _warrantyStart ?? now,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      helpText: 'วันที่เริ่มประกัน (วันซื้อ/วันติดตั้ง)',
    );
    if (picked != null) {
      setState(() => _warrantyStart = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    // ถ้าเลือกระยะเวลาประกันไว้ ต้องมีวันที่เริ่มด้วย
    if (_warrantyMonths != null && _warrantyStart == null) {
      _showSnack('กรุณาเลือกวันที่เริ่มประกัน');
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 📤 อัปโหลดรูปเครื่องจักรขึ้น Cloudinary ตอนกดบันทึกจริง ๆ (ถ้ามีเลือกรูปไว้)
      String photoUrl = _photoPath;
      if (_pickedPhotoFile != null) {
        photoUrl = await CloudinaryService.uploadImage(_pickedPhotoFile!);
      }

      final data = {
        'label': _labelController.text.trim(),
        'model_name': _modelController.text.trim(),
        'serial_number': normalizeSerialNumber(_serialController.text),
        'photo_url': photoUrl,
        'warranty_start_date': _warrantyMonths == null
            ? null
            : _warrantyStart?.toIso8601String(),
        'warranty_months': _warrantyMonths,
      };

      if (_isEditing) {
        await db.DatabaseHelper.instance
            .updateMachine(widget.existing!.id!, data);
      } else {
        await db.DatabaseHelper.instance.createMachine({
          ...data,
          'customer_username': widget.customerUsername,
          'status': 'พร้อมใช้งาน',
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving machine: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showSnack('บันทึกไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              AppHeader(
                title: _isEditing ? 'แก้ไขเครื่องจักร' : 'เพิ่มเครื่องจักร',
                showBack: true,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 📷 รูปภาพเครื่องจักร
                        Center(
                          child: GestureDetector(
                            onTap: _pickPhoto,
                            child: Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: _photoPath.isEmpty
                                      ? Container(
                                          width: 140,
                                          height: 140,
                                          color: Colors.grey.shade200,
                                          alignment: Alignment.center,
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.add_a_photo_outlined,
                                                  size: 32,
                                                  color: Colors.grey.shade500),
                                              const SizedBox(height: 6),
                                              Text(
                                                'เพิ่มรูปเครื่องจักร',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontFamily:
                                                      AppStyles.fontFamily,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      : LocalOrNetworkImage(
                                          path: _photoPath,
                                          width: 140,
                                          height: 140,
                                          fit: BoxFit.cover,
                                        ),
                                ),
                                Positioned(
                                  right: 0,
                                  bottom: 0,
                                  child: Material(
                                    color: AppColors.primary,
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _pickPhoto,
                                      child: const Padding(
                                        padding: EdgeInsets.all(7),
                                        child: Icon(
                                          Icons.camera_alt,
                                          size: 16,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        const Text(
                          'ข้อมูลเครื่องจักร',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppStyles.fontFamily,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // หมายเลข Serial Number + ปุ่มสแกน QR Code
                        TextFormField(
                          controller: _serialController,
                          style:
                              const TextStyle(fontFamily: AppStyles.fontFamily),
                          keyboardType: TextInputType.text,
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            // รูปแบบ 2-2-4: ตัวอักษร 2 ตัว + ตัวเลข 6 หลัก
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[A-Za-z0-9]')),
                            LengthLimitingTextInputFormatter(
                                kSerialNumberLength),
                            _AdminUpperCaseTextFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: 'หมายเลข Serial Number *',
                            hintText: 'เช่น PM260145',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.confirmation_number,
                                color: AppColors.primary),
                            suffixIcon: IconButton(
                              onPressed: _scanSerialNumber,
                              icon: const Icon(Icons.qr_code_scanner,
                                  color: AppColors.primary),
                              tooltip: 'สแกน QR Code',
                            ),
                          ),
                          validator: (value) {
                            final trimmed = value?.trim() ?? '';
                            if (trimmed.isEmpty) {
                              return 'กรุณากรอกหรือสแกนหมายเลข Serial Number';
                            }
                            if (!isValidSerialNumber(trimmed)) {
                              return serialNumberFormatError;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),

                        // รุ่น
                        TextFormField(
                          controller: _modelController,
                          style:
                              const TextStyle(fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'รุ่น (Model) *',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.precision_manufacturing,
                                color: AppColors.primary),
                          ),
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                                  ? 'กรุณากรอกรุ่นของเครื่องจักร'
                                  : null,
                        ),
                        const SizedBox(height: 16),

                        // ชื่อเครื่อง/ป้ายชื่อ
                        TextFormField(
                          controller: _labelController,
                          style:
                              const TextStyle(fontFamily: AppStyles.fontFamily),
                          decoration: const InputDecoration(
                            labelText: 'ชื่อเครื่องจักร (ป้ายชื่อ)',
                            hintText: 'เช่น เครื่องพิมพ์ A, ปั๊มน้ำโซน 2',
                            border: OutlineInputBorder(),
                            prefixIcon:
                                Icon(Icons.label, color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(height: 24),

                        const Text(
                          'ข้อมูลประกัน',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: AppStyles.fontFamily,
                            color: AppColors.textMain,
                          ),
                        ),
                        const SizedBox(height: 12),

                        DropdownButtonFormField<int?>(
                          initialValue: _warrantyMonths,
                          style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: AppColors.textMain),
                          decoration: const InputDecoration(
                            labelText: 'ระยะเวลาประกัน',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.verified_user,
                                color: AppColors.primary),
                          ),
                          items: _monthOptions
                              .map((m) => DropdownMenuItem<int?>(
                                    value: m,
                                    child: Text(_monthLabel(m)),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(() => _warrantyMonths = v),
                        ),
                        const SizedBox(height: 16),
                        if (_warrantyMonths != null)
                          InkWell(
                            onTap: _pickStartDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'วันที่เริ่มประกัน',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.calendar_today,
                                    color: AppColors.primary, size: 20),
                              ),
                              child: Text(
                                _warrantyStart == null
                                    ? 'แตะเพื่อเลือกวันที่'
                                    : '${_warrantyStart!.day}/${_warrantyStart!.month}/${_warrantyStart!.year + 543}',
                                style: const TextStyle(
                                    fontFamily: AppStyles.fontFamily),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        _isEditing ? 'บันทึกการแก้ไข' : 'บันทึกเครื่องจักร',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// แปลงตัวอักษรที่พิมพ์ในช่อง Serial Number ให้เป็นตัวพิมพ์ใหญ่ทันทีที่พิมพ์
/// (ใช้คู่กับ normalizeSerialNumber ตอนบันทึก/ตรวจซ้ำ ให้ค่าที่เก็บสม่ำเสมอกัน)
class _AdminUpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
