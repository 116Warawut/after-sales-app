// ==========================================
// SECTION 1: IMPORTS
// ==========================================
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/services.dart';
import 'package:after_sales/widgets.dart';

// ==========================================
// SECTION 2: DATA MODEL — ผูกกับตาราง spare_parts จริง
// ==========================================

/// โมเดลข้อมูลอะไหล่หนึ่งรายการ ([SparePartItem])
///
/// ต่างจากฝั่งช่าง (RequestPartScreen) ตรงที่แอดมินต้องเห็น "จำนวนคงเหลือจริง"
/// (stock) และราคา เพื่อใช้บริหารสต็อก ไม่ใช่แค่สถานะ มี/หมด
class SparePartItem {
  final int id;
  final String partName;
  final String partCode;
  final double price;
  final int stock;
  // 📷 รูปภาพอะไหล่ (URL จาก Cloudinary) — เหมือนกับที่หน้าเว็บแอดมินใช้ (photo_url)
  final String photoUrl;

  const SparePartItem({
    required this.id,
    required this.partName,
    required this.partCode,
    required this.price,
    required this.stock,
    this.photoUrl = '',
  });

  factory SparePartItem.fromMap(Map<String, dynamic> map) {
    return SparePartItem(
      // 🐛 [แก้บัค] เดิม `as int` แบบ hard cast — ถ้า id ที่มาจาก Firebase เป็น
      // ชนิดอื่น (เช่น num ที่ไม่ใช่ int ตรง ๆ) จะ throw TypeError ทำให้ทั้งหน้า
      // รายการอะไหล่พังตั้งแต่ตอน build รายการ (เหมือนบั๊กที่เคยแก้ในหน้าแจ้งเตือน)
      id: (map['id'] as num?)?.toInt() ?? 0,
      partName: (map['part_name'] as String?) ?? '-',
      partCode: (map['part_code'] as String?) ?? '-',
      price: (map['price'] as num?)?.toDouble() ?? 0,
      stock: (map['stock'] as num?)?.toInt() ?? 0,
      photoUrl: (map['photo_url'] as String?) ?? '',
    );
  }

  /// เกณฑ์ "อะไหล่ใกล้หมด" — ใช้ค่าเดียวกับที่แดชบอร์ดแอดมินใช้ (stock <= 5)
  bool get isLowStock => stock > 0 && stock <= 5;
  bool get isOutOfStock => stock <= 0;
}

// ==========================================
// SECTION 3: MAIN SCREEN WIDGET
// ==========================================

/// {@template admin_spare_part}
/// หน้าจัดการอะไหล่สำหรับแอดมิน ([AdminSparePartPage])
///
/// รองรับ: ค้นหา, ดูจำนวนคงเหลือจริง, เพิ่ม/แก้ไข/ลบรายการอะไหล่
/// เชื่อมกับตาราง `spare_parts` ผ่าน [DatabaseHelper] โดยตรง
/// {@endtemplate}
class AdminSparePartPage extends StatefulWidget {
  const AdminSparePartPage({super.key});

  @override
  State<AdminSparePartPage> createState() => _AdminSparePartPageState();
}

class _AdminSparePartPageState extends State<AdminSparePartPage>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;
  List<SparePartItem> _allParts = [];
  String _query = '';

  final TextEditingController _searchController = TextEditingController();

  late final TabController _tabController;

  // 📋 คำขอเบิกอะไหล่จากช่างทุกคน
  bool _isLoadingRequests = true;
  List<Map<String, dynamic>> _allRequests = [];

  // 🐛 [แก้บัค] _approveRequest/_rejectRequest เดิมใช้ request['id']/['part_id']
  // as int แบบ hard cast — ถ้า Firebase ส่งค่ามาเป็นชนิดอื่น (เช่น num ที่ไม่ใช่
  // int ตรง ๆ) จะ throw TypeError ทำให้หน้าเบิกอะไหล่ทั้งหน้าพัง เอาแพตช์เดียวกับ
  // ที่ใช้แก้หน้าแจ้งเตือน (_asInt ใน technician_notification.dart /
  // admin_notification.dart) มาใช้ตรงนี้ด้วย
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return int.tryParse(v.toString());
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadParts();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ------------------------------------------
  // 🔄 โหลดรายการอะไหล่จากฐานข้อมูล
  // ------------------------------------------
  Future<void> _loadParts() async {
    setState(() => _isLoading = true);
    try {
      final rows = await DatabaseHelper.instance.getSpareParts();
      if (!mounted) return;
      setState(() {
        _allParts = rows.map((row) => SparePartItem.fromMap(row)).toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading spare parts: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showSnack('โหลดข้อมูลอะไหล่ไม่สำเร็จ');
    }
  }

  // ------------------------------------------
  // 🔄 โหลดคำขอเบิกอะไหล่ทั้งหมด (ทุกช่าง ทุกสถานะ)
  // ------------------------------------------
  Future<void> _loadRequests() async {
    setState(() => _isLoadingRequests = true);
    try {
      final rows = await DatabaseHelper.instance.getAllPartRequests();
      if (!mounted) return;
      setState(() {
        _allRequests = rows;
        _isLoadingRequests = false;
      });
    } catch (e) {
      debugPrint('Error loading part requests: $e');
      if (!mounted) return;
      setState(() => _isLoadingRequests = false);
      _showSnack('โหลดคำขอเบิกอะไหล่ไม่สำเร็จ');
    }
  }

  List<SparePartItem> get _filteredParts {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _allParts;
    return _allParts.where((p) {
      return p.partName.toLowerCase().contains(q) ||
          p.partCode.toLowerCase().contains(q);
    }).toList();
  }

  int get _pendingRequestCount =>
      _allRequests.where((r) => r['status'] == 'รอดำเนินการ').length;

  /// จัดกลุ่มคำขอเบิกตามช่าง — เพื่อรวมเป็นการ์ดเดียวต่อช่าง 1 คน
  /// (แทนที่จะแยกการ์ดทีละรายการ ซึ่งยาวเกินไปถ้าช่างคนเดียวเบิกหลายชิ้น)
  /// _allRequests เรียงจากล่าสุดก่อนอยู่แล้ว (id DESC) ดังนั้นลำดับกลุ่มที่ได้
  /// จาก Map (คงลำดับการแทรก) จะเรียงตามคำขอล่าสุดของแต่ละช่างโดยอัตโนมัติ
  Map<String, List<Map<String, dynamic>>> get _requestsByTechnician {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in _allRequests) {
      final tech = (r['technician_username'] as String?) ?? '-';
      grouped.putIfAbsent(tech, () => []).add(r);
    }
    return grouped;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ------------------------------------------
  // ➕ / ✏️ เปิดฟอร์มเพิ่ม/แก้ไขอะไหล่
  // ------------------------------------------
  Future<void> _openAddEditDialog({SparePartItem? existing}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => _PartFormDialog(existing: existing),
    );
    if (result == true) {
      await _loadParts();
      _showSnack(existing == null
          ? 'เพิ่มอะไหล่เรียบร้อย'
          : 'บันทึกการแก้ไขเรียบร้อย');
    }
  }

  // ------------------------------------------
  // 🗑️ ยืนยันและลบอะไหล่
  // ------------------------------------------
  Future<void> _confirmDelete(SparePartItem part) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบ "${part.partName}" ใช่หรือไม่?'),
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
        await DatabaseHelper.instance.deleteSparePart(part.id);
        await _loadParts();
        _showSnack('ลบ "${part.partName}" เรียบร้อยแล้ว');
      } catch (e) {
        debugPrint('Error deleting spare part: $e');
        _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
      }
    }
  }

  // ------------------------------------------
  // ✅ อนุมัติคำขอเบิก — ตัดสต๊อกจริง แล้วแจ้งเตือนช่าง
  // ------------------------------------------
  Future<void> _approveRequest(Map<String, dynamic> request) async {
    final id = _asInt(request['id']);
    final partId = _asInt(request['part_id']);
    final partName = request['part_name'] as String? ?? '-';
    final quantity = _asInt(request['quantity']) ?? 1;
    final technician = request['technician_username'] as String? ?? '';

    if (id == null || partId == null) {
      _showSnack('ข้อมูลคำขอเบิกไม่ถูกต้อง กรุณาโหลดหน้าใหม่');
      return;
    }

    // เช็กสต๊อกจริง ณ ตอนนี้ก่อนตัด กันกรณีสต๊อกเปลี่ยนไปหลังช่างส่งคำขอ
    final part = await DatabaseHelper.instance.getSparePartById(partId);
    final currentStock = (part?['stock'] as int?) ?? 0;
    if (currentStock < quantity) {
      _showSnack(
        'สต๊อก "$partName" เหลือไม่พอ (มี $currentStock, ขอเบิก $quantity)',
      );
      return;
    }

    try {
      await DatabaseHelper.instance.updateSparePartStock(partId, quantity);
      await DatabaseHelper.instance.updatePartRequestStatus(id, 'อนุมัติแล้ว');

      if (technician.isNotEmpty) {
        await DatabaseHelper.instance.createNotification({
          'user_username': technician,
          'role': 'TECHNICIAN',
          'title': 'คำขอเบิกอะไหล่ได้รับการอนุมัติ',
          'message': 'อนุมัติเบิก "$partName" จำนวน $quantity ชิ้นแล้ว',
          'type': 'PART_REQUEST',
          'is_read': 0,
        });
      }

      await Future.wait([_loadParts(), _loadRequests()]);
      _showSnack('อนุมัติคำขอเบิก "$partName" เรียบร้อยแล้ว');
    } catch (e) {
      debugPrint('Error approving part request: $e');
      _showSnack('อนุมัติไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  // ------------------------------------------
  // ❌ ปฏิเสธคำขอเบิก — ไม่ตัดสต๊อก แต่แจ้งเตือนช่างว่าถูกปฏิเสธ
  // ------------------------------------------
  Future<void> _rejectRequest(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการปฏิเสธคำขอ'),
        content: Text(
          'ต้องการปฏิเสธคำขอเบิก "${request['part_name']}" '
          'ของช่าง ${request['technician_username']} ใช่หรือไม่?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ปฏิเสธ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final id = _asInt(request['id']);
    final partName = request['part_name'] as String? ?? '-';
    final technician = request['technician_username'] as String? ?? '';

    if (id == null) {
      _showSnack('ข้อมูลคำขอเบิกไม่ถูกต้อง กรุณาโหลดหน้าใหม่');
      return;
    }

    try {
      await DatabaseHelper.instance.updatePartRequestStatus(id, 'ปฏิเสธ');

      if (technician.isNotEmpty) {
        await DatabaseHelper.instance.createNotification({
          'user_username': technician,
          'role': 'TECHNICIAN',
          'title': 'คำขอเบิกอะไหล่ถูกปฏิเสธ',
          'message': 'คำขอเบิก "$partName" ถูกปฏิเสธ กรุณาติดต่อแอดมิน',
          'type': 'PART_REQUEST',
          'is_read': 0,
        });
      }

      await _loadRequests();
      _showSnack('ปฏิเสธคำขอเบิก "$partName" แล้ว');
    } catch (e) {
      debugPrint('Error rejecting part request: $e');
      _showSnack('ทำรายการไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  // ------------------------------------------
  // 🗑️ ยืนยันและลบคำขอเบิกอะไหล่ออกจากประวัติ
  // ------------------------------------------
  Future<void> _deleteRequest(Map<String, dynamic> request) async {
    final partName = request['part_name'] as String? ?? '-';
    final technician = request['technician_username'] as String? ?? '-';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบคำขอเบิก'),
        content: Text(
          'ต้องการลบคำขอเบิก "$partName" ของช่าง $technician ใช่หรือไม่?\n'
          'รายการนี้จะหายไปจากประวัติทั้งหมด',
        ),
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
    if (confirmed != true) return;

    final id = _asInt(request['id']);
    if (id == null) {
      _showSnack('ข้อมูลคำขอเบิกไม่ถูกต้อง กรุณาโหลดหน้าใหม่');
      return;
    }
    try {
      await DatabaseHelper.instance.deletePartRequest(id);
      await _loadRequests();
      _showSnack('ลบคำขอเบิก "$partName" แล้ว');
    } catch (e) {
      debugPrint('Error deleting part request: $e');
      _showSnack('ลบไม่สำเร็จ กรุณาลองใหม่');
    }
  }

  // ==========================================
  // SECTION 4: BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final parts = _filteredParts;
    final lowStockCount = _allParts.where((p) => p.isLowStock).length;
    final outOfStockCount = _allParts.where((p) => p.isOutOfStock).length;

    return Scaffold(
      backgroundColor: AppColors.background,
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              backgroundColor: AppColors.primary,
              onPressed: () => _openAddEditDialog(),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            // 🔒 หัวเรื่องล็อกอยู่นิ่ง แสดงตลอดแม้กำลังโหลดข้อมูล
            AppHeader(
              title: 'จัดการอะไหล่',
              showBack: true,
              trailing: IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  _loadParts();
                  _loadRequests();
                },
              ),
            ),
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
                tabs: [
                  const Tab(text: 'รายการอะไหล่'),
                  Tab(
                    text: _pendingRequestCount > 0
                        ? 'คำขอเบิก ($_pendingRequestCount)'
                        : 'คำขอเบิก',
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // ------------------------------------------------------
                  // แท็บ 1: รายการอะไหล่ (ของเดิม)
                  // ------------------------------------------------------
                  _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                      : Column(
                          children: [
                            _SearchBar(
                              controller: _searchController,
                              query: _query,
                              onChanged: (v) => setState(() => _query = v),
                              onClear: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                            if (lowStockCount > 0 || outOfStockCount > 0)
                              _StockWarningBanner(
                                lowStockCount: lowStockCount,
                                outOfStockCount: outOfStockCount,
                              ),
                            Expanded(
                              child: parts.isEmpty
                                  ? const _EmptyPartsView()
                                  : RefreshIndicator(
                                      color: AppColors.primary,
                                      onRefresh: _loadParts,
                                      child: ListView.builder(
                                        padding: const EdgeInsets.fromLTRB(
                                            16, 8, 16, 88),
                                        itemCount: parts.length,
                                        itemBuilder: (context, index) {
                                          final part = parts[index];
                                          return _PartCard(
                                            part: part,
                                            onEdit: () => _openAddEditDialog(
                                                existing: part),
                                            onDelete: () =>
                                                _confirmDelete(part),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),

                  // ------------------------------------------------------
                  // แท็บ 2: คำขอเบิกอะไหล่จากช่างทุกคน
                  // ------------------------------------------------------
                  _isLoadingRequests
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary))
                      : _allRequests.isEmpty
                          ? const _EmptyRequestsView()
                          : RefreshIndicator(
                              color: AppColors.primary,
                              onRefresh: _loadRequests,
                              child: Builder(builder: (context) {
                                final groups =
                                    _requestsByTechnician.entries.toList();
                                return ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 12, 16, 24),
                                  itemCount: groups.length,
                                  itemBuilder: (context, index) {
                                    final entry = groups[index];
                                    return _TechnicianRequestGroupCard(
                                      technicianUsername: entry.key,
                                      requests: entry.value,
                                      onApprove: _approveRequest,
                                      onReject: _rejectRequest,
                                      onDelete: _deleteRequest,
                                    );
                                  },
                                );
                              }),
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
// SECTION 5: SUB-WIDGETS (Modular Components)
// ==========================================

/// 🔍 ช่องค้นหาอะไหล่ (ชื่อ / รหัส)
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'ค้นหาชื่อ หรือ รหัสอะไหล่...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

/// ⚠️ แถบเตือนสรุปจำนวนอะไหล่ใกล้หมด / หมดสต็อก
class _StockWarningBanner extends StatelessWidget {
  final int lowStockCount;
  final int outOfStockCount;

  const _StockWarningBanner({
    required this.lowStockCount,
    required this.outOfStockCount,
  });

  @override
  Widget build(BuildContext context) {
    final parts = <String>[
      if (outOfStockCount > 0) 'หมด $outOfStockCount รายการ',
      if (lowStockCount > 0) 'ใกล้หมด $lowStockCount รายการ',
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.yellowBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppColors.yellowText, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'อะไหล่ต้องเติมสต็อก: ${parts.join(' • ')}',
              style: const TextStyle(
                fontFamily: AppStyles.fontFamily,
                color: AppColors.yellowText,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 🚫 แสดงเมื่อไม่พบข้อมูลการค้นหา / ยังไม่มีอะไหล่ในระบบ
class _EmptyPartsView extends StatelessWidget {
  const _EmptyPartsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'ไม่พบรายการอะไหล่',
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// 📭 สถานะไม่มีคำขอเบิกอะไหล่
class _EmptyRequestsView extends StatelessWidget {
  const _EmptyRequestsView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.move_to_inbox_outlined,
              size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'ยังไม่มีคำขอเบิกอะไหล่',
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

/// 🧾 การ์ดคำขอเบิกอะไหล่ 1 รายการ — โชว์สถานะและปุ่มอนุมัติ/ปฏิเสธ (เฉพาะที่รอดำเนินการ)
/// 🧾 การ์ดคำขอเบิกอะไหล่ของช่าง 1 คน — รวมทุกรายการที่ช่างคนนี้เบิกไว้เป็นการ์ดเดียว
/// (แทนที่จะแยกการ์ดทีละรายการ ซึ่งยาวเกินไปถ้าช่างคนเดียวเบิกหลายชิ้น)
class _TechnicianRequestGroupCard extends StatelessWidget {
  final String technicianUsername;
  final List<Map<String, dynamic>> requests;
  final ValueChanged<Map<String, dynamic>> onApprove;
  final ValueChanged<Map<String, dynamic>> onReject;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _TechnicianRequestGroupCard({
    required this.technicianUsername,
    required this.requests,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final pendingCount =
        requests.where((r) => r['status'] == 'รอดำเนินการ').length;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 👷 หัวการ์ด — ชื่อช่าง + จำนวนรายการทั้งหมด/ที่รอดำเนินการ
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.engineering_outlined,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        technicianUsername,
                        style: const TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                      Text(
                        '${requests.length} รายการ',
                        style: const TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 12,
                          color: AppColors.textSubtitle,
                        ),
                      ),
                    ],
                  ),
                ),
                if (pendingCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.yellowBg,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'รอ $pendingCount',
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.yellowText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),

          // 📋 รายการอะไหล่ที่ช่างคนนี้เบิก — แถวย่อยในการ์ดเดียวกัน
          for (var i = 0; i < requests.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AppColors.border),
            _RequestRow(
              request: requests[i],
              onApprove: () => onApprove(requests[i]),
              onReject: () => onReject(requests[i]),
              onDelete: () => onDelete(requests[i]),
            ),
          ],
        ],
      ),
    );
  }
}

/// 🧾 แถวคำขอเบิก 1 รายการ ภายในการ์ดกลุ่มของช่าง
class _RequestRow extends StatelessWidget {
  final Map<String, dynamic> request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onDelete;

  const _RequestRow({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final status = (request['status'] as String?) ?? 'รอดำเนินการ';
    final isPending = status == 'รอดำเนินการ';
    final isApproved = status == 'อนุมัติแล้ว';

    final Color statusBg;
    final Color statusFg;
    if (isApproved) {
      statusBg = AppColors.greenBg;
      statusFg = AppColors.greenText;
    } else if (isPending) {
      statusBg = AppColors.yellowBg;
      statusFg = AppColors.yellowText;
    } else {
      statusBg = AppColors.redBg;
      statusFg = AppColors.redText;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request['part_name'] ?? '-'}',
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'รหัส ${request['part_code'] ?? '-'} • จำนวน ${request['quantity'] ?? 1} • '
                      '${formatNotificationDateTime(request['created_at'] as String?)}',
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSubtitle,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: statusFg,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // 🗑️ ลบคำขอนี้ออกจากประวัติ (มี pop up ยืนยันก่อนลบเสมอ)
              InkWell(
                onTap: onDelete,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline,
                      size: 18, color: AppColors.redText),
                ),
              ),
            ],
          ),
          if (isPending) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.redText,
                      side: const BorderSide(color: AppColors.redText),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 15),
                    label: const Text(
                      'ปฏิเสธ',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 15),
                    label: const Text(
                      'อนุมัติ',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}


/// 🧾 การ์ดแสดงข้อมูลอะไหล่แต่ละรายการ พร้อมปุ่มแก้ไข/ลบ
class _PartCard extends StatelessWidget {
  final SparePartItem part;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PartCard({
    required this.part,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeBg;
    final Color badgeFg;
    final String badgeLabel;

    if (part.isOutOfStock) {
      badgeBg = AppColors.redBg;
      badgeFg = AppColors.redText;
      badgeLabel = 'หมด';
    } else if (part.isLowStock) {
      badgeBg = AppColors.yellowBg;
      badgeFg = AppColors.yellowText;
      badgeLabel = 'ใกล้หมด (${part.stock})';
    } else {
      badgeBg = AppColors.greenBg;
      badgeFg = AppColors.greenText;
      badgeLabel = 'คงเหลือ ${part.stock}';
    }

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: part.photoUrl.isEmpty
                    ? Container(
                        width: 48,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.build_circle_outlined,
                            color: Colors.grey, size: 24),
                      )
                    : LocalOrNetworkImage(
                        path: part.photoUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      part.partName,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'รหัส: ${part.partCode}',
                      style: TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '฿${part.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  badgeLabel,
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: badgeFg,
                  ),
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
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  textStyle: const TextStyle(fontFamily: AppStyles.fontFamily),
                ),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('ลบ'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  textStyle: const TextStyle(fontFamily: AppStyles.fontFamily),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ==========================================
// SECTION 6: เพิ่ม/แก้ไขอะไหล่ (Dialog Form)
// ==========================================

/// ฟอร์มสำหรับเพิ่มอะไหล่ใหม่ หรือแก้ไขอะไหล่เดิม (ใช้ dialog เดียวกันทั้งสองกรณี)
class _PartFormDialog extends StatefulWidget {
  final SparePartItem? existing;

  const _PartFormDialog({this.existing});

  @override
  State<_PartFormDialog> createState() => _PartFormDialogState();
}

class _PartFormDialogState extends State<_PartFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;

  bool _isSaving = false;

  // 📷 รูปภาพอะไหล่ — เก็บ URL เดิม (ถ้าแก้ไข) ไว้แสดงพรีวิว และไฟล์ที่เพิ่งเลือกใหม่
  // (ยังไม่อัปโหลด) ไว้อัปโหลดขึ้น Cloudinary ตอนกด "บันทึก" เท่านั้น เหมือนหน้า
  // เพิ่มเครื่องจักรของลูกค้า (add_machine_page.dart)
  final ImagePicker _picker = ImagePicker();
  String _photoUrl = '';
  XFile? _pickedPhotoFile;
  bool _isUploadingPhoto = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.partName ?? '');
    _codeController = TextEditingController(text: existing?.partCode ?? '');
    _priceController = TextEditingController(
        text: existing != null ? existing.price.toStringAsFixed(0) : '');
    _stockController = TextEditingController(
        text: existing != null ? existing.stock.toString() : '');
    _photoUrl = existing?.photoUrl ?? '';
  }

  /// เลือกรูปภาพอะไหล่จากแกลเลอรีหรือถ่ายรูปใหม่ด้วยกล้อง
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
              title: const Text('ถ่ายรูปใหม่'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading:
                  const Icon(Icons.photo_library, color: AppColors.primary),
              title: const Text('เลือกจากคลังภาพ'),
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
        _photoUrl = picked.path;
        _pickedPhotoFile = picked;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เลือกรูปไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // 📤 อัปโหลดรูปขึ้น Cloudinary ตอนกดบันทึกจริง ๆ (ถ้ามีเลือกรูปใหม่ไว้)
    String photoUrl = _photoUrl;
    if (_pickedPhotoFile != null) {
      setState(() => _isUploadingPhoto = true);
      try {
        photoUrl = await CloudinaryService.uploadImage(_pickedPhotoFile!);
      } catch (e) {
        debugPrint('Error uploading spare part photo: $e');
        if (!mounted) return;
        setState(() {
          _isSaving = false;
          _isUploadingPhoto = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')),
        );
        return;
      }
      if (mounted) setState(() => _isUploadingPhoto = false);
    }

    final data = {
      'part_name': _nameController.text.trim(),
      'part_code': _codeController.text.trim(),
      'price': double.tryParse(_priceController.text.trim()) ?? 0,
      'stock': int.tryParse(_stockController.text.trim()) ?? 0,
      'photo_url': photoUrl,
    };

    try {
      if (_isEditing) {
        await DatabaseHelper.instance
            .updateSparePart(widget.existing!.id, data);
      } else {
        await DatabaseHelper.instance.createSparePart(data);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      debugPrint('Error saving spare part: $e');
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
      title: Text(_isEditing ? 'แก้ไขอะไหล่' : 'เพิ่มอะไหล่ใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 📷 รูปภาพอะไหล่
              Center(
                child: GestureDetector(
                  onTap: _isSaving ? null : _pickPhoto,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _photoUrl.isEmpty
                            ? Container(
                                width: 96,
                                height: 96,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined,
                                        size: 26, color: Colors.grey.shade500),
                                    const SizedBox(height: 4),
                                    Text(
                                      'เพิ่มรูป',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              )
                            : LocalOrNetworkImage(
                                path: _photoUrl,
                                width: 96,
                                height: 96,
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
                            onTap: _isSaving ? null : _pickPhoto,
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.camera_alt,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'ชื่ออะไหล่'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'กรุณากรอกชื่ออะไหล่'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'รหัสอะไหล่'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'กรุณากรอกรหัสอะไหล่'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(labelText: 'ราคา (บาท)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'กรุณากรอกราคา';
                  if (double.tryParse(v.trim()) == null) {
                    return 'ราคาต้องเป็นตัวเลข';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                decoration:
                    const InputDecoration(labelText: 'จำนวนคงเหลือ (ชิ้น)'),
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'กรุณากรอกจำนวน';
                  if (int.tryParse(v.trim()) == null) {
                    return 'จำนวนต้องเป็นตัวเลข';
                  }
                  return null;
                },
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
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  _isUploadingPhoto ? 'กำลังอัปโหลดรูป...' : 'บันทึก',
                  style: const TextStyle(color: Colors.white),
                ),
        ),
      ],
    );
  }
}