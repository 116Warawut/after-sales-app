import 'package:after_sales/app_styles.dart';
import 'package:flutter/material.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';

// ==========================================
// 1. Data Model — รับข้อมูลจริงจากตาราง spare_parts
// ==========================================
class PartItem {
  final int id;
  final String partName;
  final String partCode;
  final int stock; // จำนวนคงเหลือจริง — โชว์เฉพาะตอนเปิดดูรายละเอียด
  final bool isAvailable; // true = มี (stock > 0), false = หมด
  // 📷 [แก้ไข] เพิ่ม photoUrl — เดิมโมเดลนี้ไม่ได้อ่านฟิลด์นี้จาก Firebase เลย
  // ทำให้ต่อให้แอดมินอัปโหลดรูปไว้แล้ว หน้าเบิกของช่างก็ยังโชว์แต่ไอคอนเดิม
  final String photoUrl;

  PartItem({
    required this.id,
    required this.partName,
    required this.partCode,
    required this.stock,
    required this.isAvailable,
    this.photoUrl = '',
  });

  factory PartItem.fromMap(Map<String, dynamic> map) {
    final stock = toIntOr(map['stock'], 0);
    return PartItem(
      id: toIntOr(map['id'], 0),
      partName: (map['part_name'] as String?) ?? '-',
      partCode: (map['part_code'] as String?) ?? '-',
      stock: stock,
      isAvailable: stock > 0,
      // ⭐ ใช้ key เดียวกับที่แอดมินบันทึกไว้ ('photo_url')
      photoUrl: (map['photo_url'] as String?) ?? '',
    );
  }
}

/// รายการอะไหล่ 1 ชิ้นที่อยู่ในตะกร้าเบิก (ยังไม่ได้ยืนยัน)
class _CartLine {
  final PartItem part;
  int quantity;
  _CartLine({required this.part, this.quantity = 1});
}

// ==========================================
// 2. หน้าจอหลัก (UI)
// ==========================================
class RequestPartScreen extends StatefulWidget {
  /// ถ้าเปิดมาจากหน้ารายละเอียดงานซ่อม จะส่ง id งานนั้นมาด้วย เพื่อผูกอะไหล่ที่เบิก
  /// เข้ากับงานนี้โดยเฉพาะ (ใช้ดึงมาออกบิลได้ทีหลัง) ถ้าเปิดจากเมนูทั่วไปจะเป็น null
  final int? repairId;

  const RequestPartScreen({super.key, this.repairId});

  @override
  State<RequestPartScreen> createState() => _RequestPartScreenState();
}

class _RequestPartScreenState extends State<RequestPartScreen> {
  bool _loading = true;
  List<PartItem> _allParts = [];
  String _query = '';

  // 🛒 ตะกร้าเบิกอะไหล่ — key เป็น part.id กันเผลอเพิ่มชิ้นเดียวกันซ้ำเป็นแถวใหม่
  final Map<int, _CartLine> _cart = {};

  @override
  void initState() {
    super.initState();
    _loadParts();
  }

  Future<void> _loadParts() async {
    setState(() => _loading = true);
    try {
      final rows = await db.DatabaseHelper.instance.getSpareParts();
      if (!mounted) return;
      setState(() {
        _allParts = rows.map((row) => PartItem.fromMap(row)).toList();
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading spare parts: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<PartItem> get _filteredParts {
    if (_query.trim().isEmpty) return _allParts;
    final q = _query.trim().toLowerCase();
    return _allParts.where((p) {
      return p.partName.toLowerCase().contains(q) ||
          p.partCode.toLowerCase().contains(q);
    }).toList();
  }

  int get _cartCount =>
      _cart.values.fold(0, (sum, line) => sum + line.quantity);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: AppStyles.fontFamily),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 🧾 เปิด popup รายละเอียดอะไหล่ + เลือกจำนวนที่จะเบิก
  // ---------------------------------------------------------------------
  void _openPartDetail(PartItem part) {
    int quantity = _cart[part.id]?.quantity ?? 1;
    if (quantity > part.stock && part.stock > 0) quantity = part.stock;
    bool showStockWarning = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // 🖼️ [แก้ไข] รูปจริงจาก photo_url + ชื่อ/รหัส/สถานะ
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: LocalOrNetworkImage(
                            path: part.photoUrl,
                            width: 64,
                            height: 64,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                part.partName,
                                style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textMain,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'รหัส : ${part.partCode}',
                                style: const TextStyle(
                                  fontFamily: AppStyles.fontFamily,
                                  fontSize: 13,
                                  color: AppColors.textSubtitle,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: part.isAvailable
                                          ? AppColors.greenBg
                                          : AppColors.redBg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      part.isAvailable ? 'มีสต๊อก' : 'หมดสต๊อก',
                                      style: TextStyle(
                                        fontFamily: AppStyles.fontFamily,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: part.isAvailable
                                            ? AppColors.greenText
                                            : AppColors.redText,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'คงเหลือ ${part.stock} ชิ้น',
                                    style: const TextStyle(
                                      fontFamily: AppStyles.fontFamily,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textSubtitle,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),
                    const Divider(height: 1, color: AppColors.border),
                    const SizedBox(height: 16),

                    // 🔢 ตัวเลือกจำนวน — กดได้เฉพาะตอนมีสต๊อก
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'จำนวนที่จะเบิก',
                          style: TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: part.isAvailable
                                ? AppColors.textMain
                                : AppColors.textHint,
                          ),
                        ),
                        Row(
                          children: [
                            _StepperButton(
                              icon: Icons.remove,
                              enabled: part.isAvailable && quantity > 1,
                              onTap: () => setSheetState(() {
                                quantity--;
                                showStockWarning = false;
                              }),
                            ),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '$quantity',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: AppStyles.fontFamily,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: part.isAvailable
                                      ? AppColors.textMain
                                      : AppColors.textHint,
                                ),
                              ),
                            ),
                            _StepperButton(
                              icon: Icons.add,
                              enabled: part.isAvailable,
                              onTap: () => setSheetState(() {
                                // 🚫 กดเกินจำนวนคงเหลือในคลัง — เตือนแทนที่จะเพิ่มให้เงียบ ๆ
                                if (quantity >= part.stock) {
                                  showStockWarning = true;
                                } else {
                                  quantity++;
                                  showStockWarning = false;
                                }
                              }),
                            ),
                          ],
                        ),
                      ],
                    ),
                    if (showStockWarning) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: AppColors.redText),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'จำนวนอะไหล่ไม่เพียงพอต่อการเบิก (คงเหลือ ${part.stock} ชิ้น)',
                              style: const TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                fontSize: 12,
                                color: AppColors.redText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),

                    // ➕ ปุ่มเพิ่มลงตะกร้า — เทาและกดไม่ได้ถ้าอะไหล่หมด
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: part.isAvailable
                              ? AppColors.primary
                              : AppColors.border,
                          foregroundColor: part.isAvailable
                              ? Colors.white
                              : AppColors.textHint,
                          elevation: 0,
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: part.isAvailable
                            ? () {
                                Navigator.pop(sheetContext);
                                _addToCart(part, quantity);
                              }
                            : null,
                        icon: Icon(
                          part.isAvailable
                              ? Icons.add_shopping_cart
                              : Icons.block,
                          size: 18,
                        ),
                        label: Text(
                          part.isAvailable
                              ? 'เพิ่มลงตะกร้าเบิก'
                              : 'อะไหล่หมด ไม่สามารถเบิกได้',
                          style: const TextStyle(
                            fontFamily: AppStyles.fontFamily,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _addToCart(PartItem part, int quantity) {
    if (quantity > part.stock) {
      _snack('จำนวนอะไหล่ไม่เพียงพอต่อการเบิก (คงเหลือ ${part.stock} ชิ้น)');
      return;
    }
    setState(() {
      final existing = _cart[part.id];
      if (existing != null) {
        existing.quantity = quantity;
      } else {
        _cart[part.id] = _CartLine(part: part, quantity: quantity);
      }
    });
    _snack('เพิ่ม "${part.partName}" (จำนวน $quantity) ลงตะกร้าเบิกแล้ว');
  }

  // ---------------------------------------------------------------------
  // 🛒 เปิดตะกร้าเบิกอะไหล่ — ดูรายการที่เลือกไว้ทั้งหมด ก่อนยืนยัน
  // ---------------------------------------------------------------------
  Future<void> _openCart() async {
    if (_cart.isEmpty) {
      _snack('ยังไม่มีอะไหล่ในตะกร้าเบิก');
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final lines = _cart.values.toList();
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'ตะกร้าเบิกอะไหล่',
                              style: TextStyle(
                                fontFamily: AppStyles.fontFamily,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textMain,
                              ),
                            ),
                          ),
                          Text(
                            '${lines.length} รายการ',
                            style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 13,
                              color: AppColors.textSubtitle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.border),
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        itemCount: lines.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final line = lines[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        line.part.partName,
                                        style: const TextStyle(
                                          fontFamily: AppStyles.fontFamily,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textMain,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'รหัส ${line.part.partCode} • จำนวน ${line.quantity}',
                                        style: const TextStyle(
                                          fontFamily: AppStyles.fontFamily,
                                          fontSize: 12,
                                          color: AppColors.textSubtitle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppColors.redText, size: 20),
                                  tooltip: 'นำออกจากตะกร้า',
                                  onPressed: () {
                                    setState(() => _cart.remove(line.part.id));
                                    setSheetState(() {});
                                    if (_cart.isEmpty && sheetContext.mounted) {
                                      Navigator.pop(sheetContext);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: AppStyles.primaryButton.copyWith(
                            padding: const WidgetStatePropertyAll(
                              EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _submitCart();
                          },
                          icon: const Icon(Icons.check_circle_outline,
                              size: 18),
                          label: const Text(
                            'ยืนยันการเบิกอะไหล่ทั้งหมด',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------
  // ✅ ยืนยันคำขอเบิกทั้งหมดในตะกร้า — บันทึกลง DB ทีละรายการ + แจ้งเตือนแอดมิน
  // ---------------------------------------------------------------------
  Future<void> _submitCart() async {
    if (_cart.isEmpty) return;

    final lines = _cart.values.toList();
    final technician = db.Session.currentUsername;

    try {
      for (final line in lines) {
        await db.DatabaseHelper.instance.createPartRequest(
          technicianUsername: technician,
          partId: line.part.id,
          partName: line.part.partName,
          partCode: line.part.partCode,
          quantity: line.quantity,
          repairId: widget.repairId,
        );
      }

      // 🔔 แจ้งเตือนแอดมินทุกคนว่ามีคำขอเบิกอะไหล่ใหม่
      final summary = lines
          .map((l) => '${l.part.partName} x${l.quantity}')
          .join(', ');
      final admins = await db.DatabaseHelper.instance.getAllAdmins();
      for (final admin in admins) {
        final adminUsername = admin['username'] as String?;
        if (adminUsername == null || adminUsername.isEmpty) continue;
        await db.DatabaseHelper.instance.createNotification({
          'user_username': adminUsername,
          'role': 'ADMIN',
          'title': 'มีคำขอเบิกอะไหล่ใหม่',
          'message': 'ช่าง $technician ขอเบิกอะไหล่: $summary',
          'type': 'PART_REQUEST',
          'is_read': 0,
        });
      }

      if (!mounted) return;
      setState(() => _cart.clear());
      _snack('ส่งคำขอเบิกอะไหล่เรียบร้อยแล้ว รอแอดมินดำเนินการ');
    } catch (e) {
      debugPrint('Error submitting part requests: $e');
      _snack('ส่งคำขอเบิกอะไหล่ไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final parts = _filteredParts;

    return Scaffold(
      //backgroundColor: AppColors.redBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppHeader(
            title: widget.repairId != null ? 'เบิกอะไหล่สำหรับงานนี้' : 'เบิกอะไหล่',
            showBack: true,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: _loadParts,
                ),
                // 🛒 ปุ่มตะกร้า พร้อมป้ายจำนวนชิ้นที่เลือกไว้
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shopping_cart_outlined,
                          color: Colors.white),
                      onPressed: _openCart,
                    ),
                    if (_cartCount > 0)
                      Positioned(
                        right: 4,
                        top: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$_cartCount',
                            style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ส่วนค้นหา
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ค้นหาชื่อ / รหัสอะไหล่',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'เช่น Roller หรือ SP-001',
                    hintStyle: const TextStyle(color: AppColors.textHint),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.grey),
                    ),
                    suffixIcon: const Icon(Icons.search),
                  ),
                ),
              ],
            ),
          ),

          // รายการอะไหล่
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : parts.isEmpty
                    ? const Center(
                        child: Text(
                          'ไม่พบรายการอะไหล่',
                          style: TextStyle(color: Colors.black54),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadParts,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 90),
                          itemCount: parts.length,
                          itemBuilder: (context, index) {
                            return _buildPartCard(parts[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),

      // ✅ แถบล่างค้างจอ ให้กดยืนยันเบิกทั้งหมดได้ทันทีโดยไม่ต้องเปิดตะกร้าก่อน
      bottomNavigationBar: _cartCount == 0
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'เลือกไว้ $_cartCount ชิ้น (${_cart.length} รายการ)',
                        style: const TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textMain,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _openCart,
                      child: const Text(
                        'ดูตะกร้า',
                        style: TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      style: AppStyles.primaryButton,
                      onPressed: _submitCart,
                      child: const Text(
                        'ยืนยันเบิก',
                        style: TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  // ==========================================
  // 3. การ์ดแสดงแต่ละรายการ — แสดงแค่ มี / หมด, แตะเพื่อดูรายละเอียด
  // ==========================================
  Widget _buildPartCard(PartItem part) {
    final inCart = _cart.containsKey(part.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openPartDetail(part),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: inCart
                ? Border.all(color: AppColors.primary, width: 1.5)
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 🖼️ [แก้ไข] แสดงรูปจริงจาก photo_url ถ้ามี ไม่งั้นค่อย fallback เป็นไอคอน
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LocalOrNetworkImage(
                  path: part.photoUrl,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 16),

              // ข้อมูลอะไหล่
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      part.partName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'รหัส : ${part.partCode}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black54,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (inCart) ...[
                      const SizedBox(height: 4),
                      Text(
                        'อยู่ในตะกร้า x${_cart[part.id]!.quantity}',
                        style: const TextStyle(
                          fontFamily: AppStyles.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 🟢🔴 สถานะ มี/หมด แบบ badge (ไม่โชว์จำนวนจริง)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: part.isAvailable
                      ? AppColors.greenBg
                      : AppColors.redBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: part.isAvailable ? Colors.green : Colors.red,
                  ),
                ),
                child: Text(
                  part.isAvailable ? 'มี' : 'หมด',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: part.isAvailable
                        ? AppColors.greenText
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right,
                  color: AppColors.textHint, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// ปุ่มบวก/ลบ ของตัวเลือกจำนวนใน popup รายละเอียดอะไหล่
class _StepperButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StepperButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled ? AppColors.surfaceAlt : AppColors.surfaceAlt.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            icon,
            size: 16,
            color: enabled ? AppColors.textMain : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}