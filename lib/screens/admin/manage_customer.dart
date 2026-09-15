// ==========================================
// SECTION 1: IMPORTS
// ==========================================
import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:after_sales/screens/admin/customer_edit_page.dart';
import 'package:after_sales/screens/admin/customer_models.dart';

// ==========================================
// SECTION 2: DATA MODEL
// ==========================================
// (ย้าย CustomerItem ไปไว้ที่ customer_models.dart แล้ว เพื่อใช้ร่วมกับ
// customer_edit_page.dart โดยไม่เกิด circular import)

// ==========================================
// SECTION 3: MAIN SCREEN WIDGET
// ==========================================

/// {@template manage_customer}
/// หน้าจัดการรายชื่อลูกค้าสำหรับแอดมิน ([ManageCustomerPage])
///
/// รองรับ: ค้นหา, ดูรายชื่อลูกค้าทั้งหมด, เพิ่มลูกค้าใหม่, แก้ไข/ลบลูกค้า
/// เชื่อมกับตาราง `customers` ผ่าน [DatabaseHelper] โดยตรง
/// {@endtemplate}
class ManageCustomerPage extends StatefulWidget {
  const ManageCustomerPage({super.key});

  @override
  State<ManageCustomerPage> createState() => _ManageCustomerPageState();
}

class _ManageCustomerPageState extends State<ManageCustomerPage> {
  bool _isLoading = true;
  List<CustomerItem> _allCustomers = [];
  String _query = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomers() async {
    setState(() => _isLoading = true);
    try {
      final rows = await db.DatabaseHelper.instance.getAllCustomers();
      if (!mounted) return;
      setState(() {
        _allCustomers = rows.map((row) => CustomerItem.fromMap(row)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading customers: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('โหลดรายชื่อลูกค้าไม่สำเร็จ');
    }
  }

  List<CustomerItem> get _filteredCustomers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allCustomers;
    return _allCustomers.where((c) {
      return c.fullName.toLowerCase().contains(q) ||
          c.username.toLowerCase().contains(q) ||
          c.company.toLowerCase().contains(q);
    }).toList();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openAddDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _CustomerFormDialog(),
    );
    if (result == true) {
      await _loadCustomers();
      _showSnack('เพิ่มลูกค้าเรียบร้อย');
    }
  }

  /// 🔴 [แก้ไข] เปลี่ยนจาก Dialog เดิม เป็นหน้าเต็ม (แบบ B) ที่มี 2 แท็บ:
  /// "ข้อมูลลูกค้า" และ "เครื่องจักร" เพื่อให้แอดมินจัดการข้อมูลเครื่องจักร +
  /// ประกันของลูกค้าคนนั้นได้ในที่เดียว ไม่ต้องสลับหน้าไปมา
  Future<void> _openEditDialog(CustomerItem customer) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CustomerEditPage(customer: customer),
      ),
    );
    // รีเฟรชรายชื่อเสมอหลังกลับมา เผื่อมีการแก้ไขข้อมูลลูกค้าในหน้านั้น
    await _loadCustomers();
  }

  Future<void> _confirmDelete(CustomerItem customer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบลูกค้า "${customer.fullName}" ใช่หรือไม่?'),
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

    if (confirmed == true) {
      try {
        await db.DatabaseHelper.instance.deleteCustomer(customer.username);
        await _loadCustomers();
        _showSnack('ลบ "${customer.fullName}" เรียบร้อยแล้ว');
      } catch (e) {
        debugPrint('Error deleting customer: $e');
        _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
      }
    }
  }

  // ==========================================
  // SECTION 4: BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final customers = _filteredCustomers;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primary,
        onPressed: _openAddDialog,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'จัดการลูกค้า', showBack: true),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาชื่อลูกค้า, บริษัท หรือ Username...',
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.grey),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : customers.isEmpty
                      ? Center(
                          child: Text(
                            'ไม่พบรายชื่อลูกค้า',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: Colors.grey.shade600,
                              fontSize: 16,
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _loadCustomers,
                          child: ListView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 88),
                            itemCount: customers.length,
                            itemBuilder: (context, index) {
                              final customer = customers[index];
                              return _CustomerCard(
                                customer: customer,
                                onEdit: () => _openEditDialog(customer),
                                onDelete: () => _confirmDelete(customer),
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// SECTION 5: SUB-WIDGETS
// ==========================================

class _CustomerCard extends StatelessWidget {
  final CustomerItem customer;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CustomerCard({
    required this.customer,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 🔴 [แก้บั๊ก] เดิมช่องนี้เป็นไอคอนคนเปล่า ๆ ตายตัวเสมอ ไม่เคยเช็ค
              // customer.photoUrl เลย (สาเหตุจริง ๆ คือ CustomerItem ยังไม่มี
              // ฟิลด์ photoUrl มาก่อน — แก้ไปแล้วใน customer_models.dart) ตอนนี้
              // ถ้ามีรูปให้แสดงรูปจริงแทนไอคอน ถ้าไม่มีค่อย fallback เป็นไอคอนเดิม
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: customer.photoUrl.isEmpty
                    ? Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.person_outline,
                            color: AppColors.primary, size: 22),
                      )
                    : LocalOrNetworkImage(
                        path: customer.photoUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.fullName,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${customer.username} • ${customer.company}',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Text(
                customer.phone,
                style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    color: Colors.grey.shade700),
              ),
              const SizedBox(width: 12),
              Icon(Icons.email_outlined, size: 14, color: Colors.grey.shade600),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  customer.email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 12,
                      color: Colors.grey.shade700),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('แก้ไข'),
                style: TextButton.styleFrom(foregroundColor: AppColors.primary),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบ'),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SECTION 6: เพิ่ม/แก้ไขลูกค้า (Dialog Form)
// ==========================================

class _CustomerFormDialog extends StatefulWidget {
  final CustomerItem? existing;

  const _CustomerFormDialog() : existing = null;

  @override
  State<_CustomerFormDialog> createState() => _CustomerFormDialogState();
}

class _CustomerFormDialogState extends State<_CustomerFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _nameController;
  late final TextEditingController _companyController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  // 🔴 [แก้ไข] เปลี่ยนที่อยู่จากช่องเดียวเป็นแยกฟิลด์ (บ้านเลขที่/หมู่/ตำบล/
  // อำเภอ/จังหวัด/รหัสไปรษณีย์) ให้ตรงกับคอลัมน์จริงที่ใช้ทั้งระบบ
  late final TextEditingController _houseNoController;
  late final TextEditingController _mooController;
  late final TextEditingController _tambonController;
  late final TextEditingController _amphoeController;
  late final TextEditingController _changwatController;
  late final TextEditingController _zipController;

  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _usernameController =
        TextEditingController(text: existing?.username ?? '');
    _passwordController = TextEditingController();
    _nameController = TextEditingController(text: existing?.fullName ?? '');
    _companyController = TextEditingController(text: existing?.company ?? '');
    _phoneController = TextEditingController(text: existing?.phone ?? '');
    _emailController = TextEditingController(text: existing?.email ?? '');
    _houseNoController = TextEditingController(text: existing?.houseNo ?? '');
    _mooController = TextEditingController(text: existing?.moo ?? '');
    _tambonController = TextEditingController(text: existing?.tambon ?? '');
    _amphoeController = TextEditingController(text: existing?.amphoe ?? '');
    _changwatController =
        TextEditingController(text: existing?.changwat ?? '');
    _zipController = TextEditingController(text: existing?.postalCode ?? '');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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

    // แยกชื่อ-นามสกุลจากช่องเดียว (คั่นด้วยช่องว่างแรก) ให้ตรงกับ name/surname ในตาราง
    final fullNameParts = _nameController.text.trim().split(' ');
    final name = fullNameParts.first;
    final surname =
        fullNameParts.length > 1 ? fullNameParts.sublist(1).join(' ') : '';
    final addressFields = {
      'house_no': _houseNoController.text.trim(),
      'moo': _mooController.text.trim(),
      'tambon': _tambonController.text.trim(),
      'amphoe': _amphoeController.text.trim(),
      'changwat': _changwatController.text.trim(),
      'postal_code': _zipController.text.trim(),
    };

    try {
      if (_isEditing) {
        await db.DatabaseHelper.instance.updateCustomerProfile(
          widget.existing!.username,
          {
            'name': name,
            'surname': surname,
            'company': _companyController.text.trim(),
            'phone': _phoneController.text.trim(),
            'email': _emailController.text.trim(),
            ...addressFields,
          },
        );
      } else {
        final username = _usernameController.text.trim();
        final exists =
            await db.DatabaseHelper.instance.checkUsernameExists(username);
        if (exists) {
          if (!mounted) return;
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username นี้ถูกใช้งานแล้ว')),
          );
          return;
        }
        await db.DatabaseHelper.instance.registerCustomer({
          'username': username,
          'password': _passwordController.text.trim(),
          'name': name,
          'surname': surname,
          'company': _companyController.text.trim(),
          'phone': _phoneController.text.trim(),
          'email': _emailController.text.trim(),
          ...addressFields,
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving customer: $e');
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'แก้ไขข้อมูลลูกค้า' : 'เพิ่มลูกค้าใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isEditing) ...[
                TextFormField(
                  controller: _usernameController,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'กรุณากรอก Username'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(labelText: 'Password'),
                  obscureText: true,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'กรุณากรอก Password'
                      : null,
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'ชื่อ-นามสกุล'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _companyController,
                decoration: const InputDecoration(labelText: 'บริษัท'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'อีเมล'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'ที่อยู่',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _houseNoController,
                      decoration:
                          const InputDecoration(labelText: 'บ้านเลขที่'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _mooController,
                      decoration: const InputDecoration(labelText: 'หมู่'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _tambonController,
                decoration: const InputDecoration(labelText: 'ตำบล'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amphoeController,
                decoration: const InputDecoration(labelText: 'อำเภอ'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _changwatController,
                      decoration: const InputDecoration(labelText: 'จังหวัด'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _zipController,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'รหัสไปรษณีย์'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('บันทึก', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}