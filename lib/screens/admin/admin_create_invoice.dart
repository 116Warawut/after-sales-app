import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';
import 'package:after_sales/app_styles.dart';
// 🆕 [ใหม่] ใช้ Machine.warrantyActive/warrantyStatusText เพื่อตรวจสอบประกัน
// ของเครื่องจักรที่ผูกกับงานซ่อมนี้ ตอนเปิดหน้าออกบิล (ดู _loadWarrantyInfo())
import 'package:after_sales/screens/customer/machine_models.dart';

// =============================================================================
// [SECTION 1] DATA MODELS (โครงสร้างข้อมูล)
// =============================================================================

/// โมเดลข้อมูลสำหรับรายการสินค้า อะไหล่ หรือค่าบริการในใบแจ้งหนี้
class InvoiceItem {
  final String id;
  final String name;
  final int quantity;
  final double unitPrice;

  InvoiceItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unitPrice,
  });

  /// คำนวณราคารวมของรายการนี้ (จำนวน x ราคาต่อหน่วย)
  double get totalPrice => quantity * unitPrice;

  /// แปลงข้อมูลเป็น Map เพื่อเตรียมส่งไปยัง Database / REST API
  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'totalPrice': totalPrice,
      };
}

// =============================================================================
// [SECTION 2] MAIN WIDGET & STATE
// =============================================================================

/// หน้าจอสร้างและแก้ไขใบแจ้งหนี้ (Invoice Creation Screen)
/// รองรับการรับข้อมูลเริ่มต้น (Initial Data) ส่งมาจากหน้ารายละเอียดงานซ่อม
class AdminCreateInvoicePage extends StatefulWidget {
  /// รหัสงานซ่อม (ถ้ามาจากหน้า assign_repair_formdetail.dart)
  final String? initialRepairId;
  // 🧾 เลขที่ใบแจ้งซ่อม (ticketNo) ส่งมาจากหน้ารายละเอียดงาน เพื่อกรอกให้อัตโนมัติ
  final String? initialTicketId;
  final String? initialCustomerName;
  final String? initialCustomerPhone;
  final String? initialAddress;
  final List<InvoiceItem>? initialItems;

  const AdminCreateInvoicePage({
    super.key,
    this.initialRepairId,
    this.initialTicketId,
    this.initialCustomerName,
    this.initialCustomerPhone,
    this.initialAddress,
    this.initialItems,
  });

  @override
  State<AdminCreateInvoicePage> createState() => _AdminCreateInvoicePageState();
}

class _AdminCreateInvoicePageState extends State<AdminCreateInvoicePage> {
  /// GlobalKey สำหรับตรวจสอบความถูกต้องของฟอร์มหลัก (Form Validation)
  final _formKey = GlobalKey<FormState>();

  // ---------------------------------------------------------------------------
  // [SECTION 3] CONTROLLERS & FORM STATES
  // ---------------------------------------------------------------------------

  // Controllers สำหรับจัดการข้อความใน Input Field
  late TextEditingController _invoiceNumberController;
  // 🧾 เลขที่ใบแจ้งซ่อม (ticketNo ของงานซ่อม) — แยกจากเลขที่ใบแจ้งหนี้
  late TextEditingController _ticketNumberController;
  late TextEditingController _customerNameController;
  late TextEditingController _customerPhoneController;
  late TextEditingController _taxIdController;
  late TextEditingController _addressController;
  late TextEditingController _branchController;
  late TextEditingController _discountController;

  // สถานะวันที่ออกเอกสาร และวันครบกำหนดชำระ
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 30));

  // รายการสินค้า/บริการที่ถูกเพิ่มเข้ามาในใบแจ้งหนี้
  List<InvoiceItem> _items = [];

  // 🔧 อะไหล่จากคำขอเบิกที่อนุมัติแล้วของงานซ่อมนี้ (ยังไม่ถูกออกบิล) — โชว์ให้แอดมิน
  // กดเพิ่มเป็นรายการในบิลได้เลย ไม่ต้องพิมพ์ชื่อ/ราคาซ้ำเอง
  bool _loadingPartRequests = false;
  List<Map<String, dynamic>> _availablePartRequests = [];
  // เก็บราคาต่อหน่วยของแต่ละคำขอ (ดึงจากตารางอะไหล่ ณ ตอนโหลด) แยกจาก request เอง
  // เพราะ part_requests ไม่ได้เก็บราคาไว้ (เก็บแค่ชื่อ/รหัส/จำนวนที่เบิก)
  final Map<int, double> _partRequestUnitPrice = {};

  // ตัวแปรควบคุมภาษี
  bool _includeVat = true; // เปิด/ปิด การคิด VAT 7%
  bool _enableWithholdingTax = false; // เปิด/ปิด การคิดภาษีหัก ณ ที่จ่าย
  double _withholdingTaxRate =
      3.0; // อัตราหัก ณ ที่จ่าย (ค่าเริ่มต้น 3% สำหรับค่าบริการ)

  // 🆕 [ใหม่] สถานะประกันของเครื่องจักรที่ผูกกับงานซ่อมนี้ — ถ้าเปิดใช้งาน
  // (auto-detect จาก Machine.warrantyActive หรือแอดมินเปิดเอง) รายการ/ราคาในบิล
  // ยังกรอกได้ตามปกติ แต่ลูกค้าจะไม่เห็นปุ่มชำระเงิน/QR code (ดู _saveInvoice()
  // และหน้า customer_job_detail.dart ฝั่งลูกค้า)
  bool _isWarrantyCovered = false;
  bool _loadingWarrantyInfo = false;
  // ข้อความสถานะประกันที่ตรวจพบจากข้อมูลเครื่องจักรจริง (ถ้ามี) โชว์เป็นคำอธิบาย
  // ใต้สวิตช์ — null ถ้าไม่พบเครื่องจักรผูกกับงานนี้เลย (เช่น "อุปกรณ์บริการทั่วไป")
  String? _machineWarrantyStatusText;

  @override
  void initState() {
    super.initState();
    // กำหนดค่าเริ่มต้นให้กับ Controller โดยดึงจาก Widget Properties (ถ้ามี)
    _invoiceNumberController = TextEditingController(
      text:
          'INV-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}',
    );
    // ถ้ามาจากหน้ารายละเอียดงาน จะได้เลขใบแจ้งซ่อม (ticketNo) มากรอกให้อัตโนมัติ
    _ticketNumberController =
        TextEditingController(text: widget.initialTicketId ?? '');
    _customerNameController =
        TextEditingController(text: widget.initialCustomerName ?? '');
    _customerPhoneController =
        TextEditingController(text: widget.initialCustomerPhone ?? '');
    _taxIdController = TextEditingController();
    _addressController =
        TextEditingController(text: widget.initialAddress ?? '');
    _branchController = TextEditingController(text: 'สำนักงานใหญ่');
    _discountController = TextEditingController(text: '0');

    // ถ้ามีรายการสินค้าส่งมาจากหน้ารายละเอียดการซ่อม ให้โหลดเข้า List
    if (widget.initialItems != null) {
      _items = List.from(widget.initialItems!);
    }

    // ถ้ามาจากงานซ่อมงานใดงานหนึ่ง ดึงอะไหล่ที่เบิกไปสำหรับงานนี้ (อนุมัติแล้ว)
    // มาเสนอให้เพิ่มเข้าบิลด้วย
    if (widget.initialRepairId != null) {
      _loadAvailablePartRequests();
      // 🔴 [ใหม่] ดึงราคาประเมินที่ช่างกรอกไว้ มาเติมเป็นรายการค่าแรงเริ่มต้น
      // ในบิลให้อัตโนมัติ แอดมินไม่ต้องถามช่างเองว่าตีราคาไว้เท่าไหร่
      _prefillEstimatedLaborItem();
      // 🆕 [ใหม่] ตรวจสอบประกันของเครื่องจักรที่ผูกกับงานซ่อมนี้ ถ้ายังอยู่ใน
      // ประกัน เปิดสวิตช์ "ไม่มีค่าใช้จ่าย (อยู่ในประกัน)" ให้อัตโนมัติ
      _loadWarrantyInfo();
    }
  }

  /// 🛡️ [ใหม่] ดึง machine_id จากงานซ่อมนี้ แล้วเช็คสถานะประกันของเครื่องจักร
  /// (Machine.warrantyActive) — ถ้ายังอยู่ในประกัน เปิดสวิตช์ยกเว้นค่าใช้จ่าย
  /// ให้อัตโนมัติ (แอดมินยังปิด/เปิดสวิตช์เองทีหลังได้ตามดุลยพินิจ เช่น ความเสียหาย
  /// ไม่เข้าเงื่อนไขประกัน)
  Future<void> _loadWarrantyInfo() async {
    final repairId = int.tryParse(widget.initialRepairId ?? '');
    if (repairId == null) return;

    setState(() => _loadingWarrantyInfo = true);
    try {
      final repair = await db.DatabaseHelper.instance.getRepairById(repairId);
      final machineId = repair?['machine_id'];
      if (machineId == null) {
        if (!mounted) return;
        setState(() => _loadingWarrantyInfo = false);
        return;
      }

      final machineMap =
          await db.DatabaseHelper.instance.getMachineById(machineId);
      if (machineMap == null || !mounted) {
        if (mounted) setState(() => _loadingWarrantyInfo = false);
        return;
      }

      final machine = Machine.fromMap(machineMap);
      setState(() {
        _isWarrantyCovered = machine.warrantyActive;
        _machineWarrantyStatusText = machine.warrantyStatusText;
        _loadingWarrantyInfo = false;
      });
    } catch (e) {
      debugPrint('Error loading warranty info for invoice: $e');
      if (!mounted) return;
      setState(() => _loadingWarrantyInfo = false);
    }
  }

  /// 💰 [ใหม่] ดึง "ราคาประเมิน" (estimated_price) ที่ช่างกรอกไว้ตอนลงพื้นที่
  /// ซ่อม มาเติมเป็นรายการค่าแรงเริ่มต้นให้อัตโนมัติในบิลนี้ — ยังคงแก้ไขหรือ
  /// ลบรายการนี้ได้ตามปกติก่อนกดบันทึกบิลจริง (ไม่ได้บังคับใช้ตามราคาประเมิน)
  Future<void> _prefillEstimatedLaborItem() async {
    final repairId = int.tryParse(widget.initialRepairId ?? '');
    if (repairId == null) return;
    try {
      final repair = await db.DatabaseHelper.instance.getRepairById(repairId);
      final estimatedPrice =
          toDoubleOrNull(repair?['estimated_price']) ?? 0;
      if (estimatedPrice <= 0 || !mounted) return;
      // กันไม่ให้เพิ่มซ้ำเผื่อมีรายการนี้อยู่แล้ว (เช่นส่งมาจาก initialItems)
      final alreadyHasEstimate =
          _items.any((item) => item.id == 'estimated_labor');
      if (alreadyHasEstimate) return;
      setState(() {
        _items.add(InvoiceItem(
          id: 'estimated_labor',
          name: 'ค่าแรง (ราคาประเมินจากช่าง)',
          quantity: 1,
          unitPrice: estimatedPrice,
        ));
      });
    } catch (e) {
      debugPrint('Error loading estimated price for invoice: $e');
    }
  }

  /// 🔧 โหลดอะไหล่ที่ช่างเบิกไปสำหรับงานนี้ (สถานะอนุมัติแล้ว + ยังไม่ถูกออกบิล)
  /// พร้อมราคาต่อหน่วยล่าสุดจากตารางอะไหล่ เตรียมให้กดเพิ่มเข้าบิลได้ทันที
  Future<void> _loadAvailablePartRequests() async {
    final repairId = int.tryParse(widget.initialRepairId ?? '');
    if (repairId == null) return;

    setState(() => _loadingPartRequests = true);
    try {
      final requests = await db.DatabaseHelper.instance
          .getApprovedPartRequestsForRepair(repairId);

      final prices = <int, double>{};
      for (final r in requests) {
        final partId = toIntOrNull(r['part_id']);
        if (partId == null || prices.containsKey(partId)) continue;
        final part = await db.DatabaseHelper.instance.getSparePartById(partId);
        prices[partId] = toDoubleOrNull(part?['price']) ?? 0;
      }

      if (!mounted) return;
      setState(() {
        _availablePartRequests = requests;
        _partRequestUnitPrice
          ..clear()
          ..addAll(prices);
        _loadingPartRequests = false;
      });
    } catch (e) {
      debugPrint('Error loading part requests for invoice: $e');
      if (!mounted) return;
      setState(() => _loadingPartRequests = false);
    }
  }

  /// ➕ เพิ่มอะไหล่จากคำขอเบิก 1 รายการเข้าไปในบิล แล้วมาร์กว่า "ออกบิลแล้ว"
  /// กันไม่ให้ถูกดึงมาเสนอซ้ำในบิลใบอื่นทีหลัง
  Future<void> _addPartRequestToInvoice(Map<String, dynamic> request) async {
    final requestId = toIntOr(request['id'], 0);
    final partId = toIntOrNull(request['part_id']);
    final quantity = toIntOrNull(request['quantity']) ?? 1;
    final unitPrice =
        partId != null ? (_partRequestUnitPrice[partId] ?? 0) : 0.0;

    setState(() {
      _items.add(InvoiceItem(
        id: 'part_req_$requestId',
        name: (request['part_name']?.toString()) ?? 'อะไหล่',
        quantity: quantity,
        unitPrice: unitPrice,
      ));
      _availablePartRequests.removeWhere((r) => r['id'] == request['id']);
    });

    try {
      await db.DatabaseHelper.instance
          .updatePartRequestStatus(requestId, 'ออกบิลแล้ว');
    } catch (e) {
      debugPrint('Error marking part request as billed: $e');
    }
  }

  @override
  void dispose() {
    // คืน Memory ให้ระบบเมื่อผู้ใช้ปิดหน้านี้
    _invoiceNumberController.dispose();
    _ticketNumberController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _taxIdController.dispose();
    _addressController.dispose();
    _branchController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // [SECTION 4] FINANCIAL CALCULATIONS (สูตรการคำนวณทางการเงิน)
  // ---------------------------------------------------------------------------

  /// ราคารวมของรายการสินค้าทั้งหมดก่อนหักส่วนลด (Subtotal)
  double get _subtotal => _items.fold(0, (sum, item) => sum + item.totalPrice);

  /// จำนวนเงินส่วนลดสุทธิ (ดักจับไม่ให้ส่วนลดมากกว่าราคารวม)
  double get _discountAmount {
    final discount = double.tryParse(_discountController.text) ?? 0.0;
    return discount > _subtotal ? _subtotal : discount;
  }

  /// ยอดเงินหลังหักส่วนลด (Before Tax Subtotal)
  double get _subtotalAfterDiscount => _subtotal - _discountAmount;

  /// จำนวนเงินภาษีมูลค่าเพิ่ม (VAT 7%)
  double get _vatAmount => _includeVat ? (_subtotalAfterDiscount * 0.07) : 0.0;

  /// จำนวนเงินภาษีหัก ณ ที่จ่าย (คำนวณจากยอดก่อน VAT)
  double get _withholdingTaxAmount => _enableWithholdingTax
      ? (_subtotalAfterDiscount * (_withholdingTaxRate / 100))
      : 0.0;

  /// ยอดเงินสุทธิที่ลูกค้าต้องจ่ายจริง (Grand Total)
  double get _grandTotal =>
      _subtotalAfterDiscount + _vatAmount - _withholdingTaxAmount;

  // ---------------------------------------------------------------------------
  // [SECTION 5] DIALOGS & BOTTOM SHEETS (ป๊อบอัพเพิ่ม/แก้ไขสินค้า)
  // ---------------------------------------------------------------------------

  /// แสดง Bottom Sheet สำหรับเพิ่มหรือแก้ไขรายการสินค้า
  /// ใช้ [StatefulBuilder] เพื่อ Re-render UI และคำนวณราคารวมแบบ Real-time เฉพาะใน Bottom Sheet
  void _showItemDialog({InvoiceItem? itemToEdit, int? indexToEdit}) {
    final nameCtrl = TextEditingController(text: itemToEdit?.name ?? '');
    final qtyCtrl =
        TextEditingController(text: itemToEdit?.quantity.toString() ?? '1');
    final priceCtrl =
        TextEditingController(text: itemToEdit?.unitPrice.toString() ?? '');
    final dialogKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // รองรับดัน UI ขึ้นเมื่อคีย์บอร์ดเปิด
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setBottomSheetState) {
            // คำนวณราคารวมในตัว Bottom Sheet แบบทันที
            final qty = int.tryParse(qtyCtrl.text) ?? 0;
            final price = double.tryParse(priceCtrl.text) ?? 0.0;
            final itemTotal = qty * price;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 20,
                left: 20,
                right: 20,
              ),
              child: Form(
                key: dialogKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    Text(
                      itemToEdit == null
                          ? 'เพิ่มรายการสินค้า / บริการ'
                          : 'แก้ไขรายการ',
                      style: AppStyles.title.copyWith(
                        color: AppColors.textHeading,
                        fontSize: 18,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ช่องกรอกชื่อสินค้า/รายการ
                    TextFormField(
                      controller: nameCtrl,
                      style: const TextStyle(
                          fontFamily: AppStyles.fontFamily, fontSize: 14),
                      decoration: AppStyles.inputDecoration(
                        hintText: 'ชื่อสินค้า / บริการ / อะไหล่',
                      ),
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'กรุณากรอกชื่อรายการ'
                          : null,
                    ),
                    const SizedBox(height: 12),

                    // ช่องกรอกจำนวน และ ราคาต่อหน่วย
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: qtyCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily, fontSize: 14),
                            decoration:
                                AppStyles.inputDecoration(hintText: 'จำนวน'),
                            onChanged: (_) => setBottomSheetState(
                                () {}), // Refresh เพื่ออัปเดตราคารวม
                            validator: (v) =>
                                v == null || (int.tryParse(v) ?? 0) <= 0
                                    ? 'จำนวนต้อง > 0'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily, fontSize: 14),
                            decoration: AppStyles.inputDecoration(
                                hintText: 'ราคาต่อหน่วย (฿)'),
                            onChanged: (_) => setBottomSheetState(
                                () {}), // Refresh เพื่ออัปเดตราคารวม
                            validator: (v) =>
                                v == null || (double.tryParse(v) ?? -1) < 0
                                    ? 'ราคาไม่ถูกต้อง'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),

                    // กล่องแสดงผลราคารวมรายการแบบ Real-time Preview
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'รวมรายการนี้',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textMain,
                            ),
                          ),
                          Text(
                            '฿${itemTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ปุ่มกดบันทึกรายการสินค้า
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: AppStyles.primaryButton,
                        onPressed: () {
                          if (dialogKey.currentState!.validate()) {
                            final newItem = InvoiceItem(
                              id: itemToEdit?.id ??
                                  DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString(),
                              name: nameCtrl.text.trim(),
                              quantity: int.parse(qtyCtrl.text),
                              unitPrice: double.parse(priceCtrl.text),
                            );

                            setState(() {
                              if (indexToEdit != null) {
                                _items[indexToEdit] =
                                    newItem; // แก้ไขรายการเดิม
                              } else {
                                _items.add(newItem); // เพิ่มรายการใหม่
                              }
                            });
                            Navigator.pop(context);
                          }
                        },
                        child: Text(
                          itemToEdit == null ? 'เพิ่มรายการ' : 'บันทึกการแก้ไข',
                          style: AppStyles.buttonText.copyWith(
                            fontFamily: AppStyles.fontFamily,
                          ),
                        ),
                      ),
                    )
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // [SECTION 6] SAVE & EXPORT LOGIC
  // ---------------------------------------------------------------------------

  /// ตรวจสอบความถูกต้องและบันทึกข้อมูลใบแจ้งหนี้
  /// รวบรวมข้อมูลทั้งหมดให้อยู่ในรูปแบบ Map (JSON Ready) สำหรับส่งต่อ Backend หรือไปออก PDF
  bool _isSaving = false;

  Future<void> _saveInvoice() async {
    // 1. ตรวจสอบการกรอกข้อมูลในฟอร์มหลัก
    if (!_formKey.currentState!.validate()) return;

    // 2. ตรวจสอบว่ามีรายการสินค้าอย่างน้อย 1 รายการ
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเพิ่มรายการสินค้าอย่างน้อย 1 รายการ'),
          backgroundColor: AppColors.requiredMark,
        ),
      );
      return;
    }

    final repairId = int.tryParse(widget.initialRepairId ?? '');
    if (repairId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'ไม่พบงานซ่อมที่จะออกบิล กรุณาเปิดหน้านี้จากหน้ารายละเอียดงานซ่อม'),
          backgroundColor: AppColors.requiredMark,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // 3. บันทึกบิลจริงลงตาราง repairs (bill_id / invoice_no / total_price)
      // 🆕 [ใหม่] ส่ง isWarrantyCovered ไปด้วย — ถ้าอยู่ในประกัน
      // updateRepairBill() จะมาร์กบิลนี้เป็น "ชำระแล้ว" ให้อัตโนมัติ (ไม่ต้องรอ
      // ลูกค้าจ่ายเงินจริง) แต่ไม่นับเป็นรายได้ตอนสรุปยอด
      await db.DatabaseHelper.instance.updateRepairBill(
        repairId,
        billId: _invoiceNumberController.text.trim(),
        totalPrice: _grandTotal,
        isWarrantyCovered: _isWarrantyCovered,
      );

      // 4. แจ้งเตือนลูกค้าว่ามีใบแจ้งหนี้ใหม่ — ข้อความต่างกันถ้าอยู่ในประกัน
      // (ไม่ต้องบอกให้ลูกค้าไปชำระเงิน เพราะไม่มีค่าใช้จ่ายจริง)
      final repair = await db.DatabaseHelper.instance.getRepairById(repairId);
      final customerUsername = repair?['customer_username']?.toString();
      final ticketNo = repair?['ticketNo']?.toString() ?? '';
      if (customerUsername != null && customerUsername.isNotEmpty) {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': customerUsername,
          'role': 'CUSTOMER',
          'title':
              _isWarrantyCovered ? 'มีใบแจ้งค่าบริการ (อยู่ในประกัน)' : 'มีใบแจ้งหนี้ใหม่',
          'message': _isWarrantyCovered
              ? 'งานซ่อม $ticketNo มีค่าบริการ ฿${_grandTotal.toStringAsFixed(2)} แต่ไม่มีค่าใช้จ่าย เนื่องจากเครื่องจักรอยู่ในประกัน'
              : 'งานซ่อม $ticketNo มีใบแจ้งหนี้ยอด ฿${_grandTotal.toStringAsFixed(2)} กรุณาชำระเงิน',
          'type': 'INVOICE_CREATED',
          'target_id': repairId,
          'is_read': 0,
        });
      }

      if (!mounted) return;

      // 5. แสดงการแจ้งเตือนสำเร็จ และส่งข้อมูลกลับไปยังหน้าก่อนหน้า
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('บันทึกใบแจ้งหนี้เรียบร้อยแล้ว'),
          backgroundColor: AppColors.greenText,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('บันทึกใบแจ้งหนี้ไม่สำเร็จ: $e')),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // [SECTION 7] UI BUILD METHODS
  // ---------------------------------------------------------------------------

  /// ป๊อปอัพเลือกวันที่ ใช้ร่วมกันทั้งวันออกเอกสารและวันครบกำหนด
  Future<void> _pickDate({required bool isIssueDate}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isIssueDate ? _issueDate : _dueDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: isIssueDate ? 'เลือกวันที่ออกเอกสาร' : 'เลือกวันครบกำหนดชำระ',
      cancelText: 'ยกเลิก',
      confirmText: 'ตกลง',
    );
    if (picked == null) return;
    setState(() {
      if (isIssueDate) {
        _issueDate = picked;
      } else {
        _dueDate = picked;
      }
    });
  }

  String _formatDate(DateTime d) {
    const months = [
      'ม.ค.',
      'ก.พ.',
      'มี.ค.',
      'เม.ย.',
      'พ.ค.',
      'มิ.ย.',
      'ก.ค.',
      'ส.ค.',
      'ก.ย.',
      'ต.ค.',
      'พ.ย.',
      'ธ.ค.',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year + 543}';
  }

  String _money(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'สร้างใบแจ้งหนี้', showBack: true),
            Expanded(
              // ซ่อนคีย์บอร์ดเมื่อแตะพื้นที่ว่างภายนอก Input
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 20),
                      _buildCustomerCard(),
                      const SizedBox(height: 20),
                      // 🆕 [ใหม่] การ์ดยกเว้นค่าใช้จ่ายเพราะประกัน — โชว์เฉพาะตอน
                      // ออกบิลผูกกับงานซ่อมจริง (มี initialRepairId) เพราะต้องมี
                      // เครื่องจักร/งานซ่อมให้อ้างอิงสถานะประกัน
                      if (widget.initialRepairId != null) ...[
                        _buildWarrantyCard(),
                        const SizedBox(height: 20),
                      ],
                      if (widget.initialRepairId != null &&
                          (_loadingPartRequests ||
                              _availablePartRequests.isNotEmpty)) ...[
                        _buildSuggestedPartsCard(),
                        const SizedBox(height: 20),
                      ],
                      _buildItemsCard(),
                      const SizedBox(height: 20),
                      _buildFinancialSummaryCard(),
                    ],
                  ),
                ),
              ),
            ),

            // 💰 แถบยอดสุทธิ + ปุ่มบันทึก ยึดติดด้านล่างตลอด ไม่ต้องเลื่อนหา
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ชิ้นส่วน UI ที่ใช้ซ้ำ
  // ---------------------------------------------------------------------------

  /// การ์ดมาตรฐานของหน้านี้ (หัวข้อ + ไอคอน + เนื้อหา)
  Widget _card({
    required IconData icon,
    required String title,
    Widget? action,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textHeading,
                    ),
                  ),
                ),
                if (action != null) action,
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.border),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  /// ป้ายกำกับเหนือช่องกรอก — แทนการใช้ labelText ที่ทำให้แถวดูรก
  Widget _field({
    required String label,
    required Widget child,
    bool required = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStyles.fieldLabel(label, required: required),
        child,
      ],
    );
  }

  InputDecoration _inputStyle({String? hint, String? suffix}) {
    return AppStyles.inputDecoration(hintText: hint ?? '').copyWith(
      isDense: true,
      suffixText: suffix,
      suffixStyle: const TextStyle(
        fontFamily: AppStyles.fontFamily,
        fontSize: 13,
        color: AppColors.textSubtitle,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // การ์ดที่ 1: ข้อมูลเอกสาร
  // ---------------------------------------------------------------------------
  Widget _buildHeaderCard() {
    return _card(
      icon: Icons.description_outlined,
      title: 'ข้อมูลเอกสาร',
      children: [
        _field(
          label: 'เลขที่ใบแจ้งหนี้',
          required: true,
          child: TextFormField(
            controller: _invoiceNumberController,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
            ),
            decoration: _inputStyle(hint: 'INV-000000'),
            validator: (v) =>
                v == null || v.isEmpty ? 'กรุณากรอกเลขที่เอกสาร' : null,
          ),
        ),
        const SizedBox(height: 14),
        // 🧾 เลขที่ใบแจ้งซ่อม (ticketNo) — ถ้าเปิดมาจากหน้ารายละเอียดงาน
        // จะถูกกรอกให้อัตโนมัติ และล็อกไว้ไม่ให้แก้ไข เพื่อให้ตรงกับงานซ่อมที่ผูกไว้
        _field(
          label: 'เลขใบแจ้งซ่อม',
          required: false,
          child: TextFormField(
            controller: _ticketNumberController,
            readOnly: widget.initialTicketId != null,
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
              color: widget.initialTicketId != null
                  ? AppColors.textSubtitle
                  : AppColors.textMain,
            ),
            decoration: _inputStyle(hint: 'เช่น AS-000001').copyWith(
              fillColor:
                  widget.initialTicketId != null ? AppColors.surfaceAlt : null,
              filled: widget.initialTicketId != null,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _DateField(
                label: 'วันที่ออกเอกสาร',
                value: _formatDate(_issueDate),
                onTap: () => _pickDate(isIssueDate: true),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DateField(
                label: 'ครบกำหนดชำระ',
                value: _formatDate(_dueDate),
                onTap: () => _pickDate(isIssueDate: false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // การ์ดที่ 2: ข้อมูลลูกค้า
  // ---------------------------------------------------------------------------
  Widget _buildCustomerCard() {
    return _card(
      icon: Icons.person_outline,
      title: 'ข้อมูลลูกค้า',
      children: [
        _field(
          label: 'ชื่อลูกค้า / ชื่อบริษัท',
          required: true,
          child: TextFormField(
            controller: _customerNameController,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
            ),
            decoration: _inputStyle(hint: 'เช่น บริษัท ตัวอย่าง จำกัด'),
            validator: (v) =>
                v == null || v.trim().isEmpty ? 'กรุณากรอกชื่อลูกค้า' : null,
          ),
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _field(
                label: 'เบอร์โทรศัพท์',
                required: false,
                child: TextFormField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                  ),
                  decoration: _inputStyle(hint: '08x-xxx-xxxx'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _field(
                label: 'สาขา',
                required: false,
                child: TextFormField(
                  controller: _branchController,
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                  ),
                  decoration: _inputStyle(hint: 'สำนักงานใหญ่'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _field(
          label: 'เลขประจำตัวผู้เสียภาษี (13 หลัก)',
          required: false,
          child: TextFormField(
            controller: _taxIdController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(13),
            ],
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
            ),
            decoration: _inputStyle(hint: '0000000000000'),
          ),
        ),
        const SizedBox(height: 14),
        _field(
          label: 'ที่อยู่สำหรับออกใบเสร็จ',
          required: false,
          child: TextFormField(
            controller: _addressController,
            maxLines: 2,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
            ),
            decoration: _inputStyle(hint: 'บ้านเลขที่ ถนน แขวง เขต จังหวัด'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // การ์ดยกเว้นค่าใช้จ่ายเพราะประกัน (🆕 [ใหม่])
  // ---------------------------------------------------------------------------
  Widget _buildWarrantyCard() {
    return _card(
      icon: Icons.shield_outlined,
      title: 'การรับประกัน',
      action: _loadingWarrantyInfo
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      children: [
        _TaxSwitch(
          label: 'อยู่ในประกัน (ลูกค้าไม่ต้องชำระเงิน)',
          value: _isWarrantyCovered,
          onChanged: (val) => setState(() => _isWarrantyCovered = val),
        ),
        const SizedBox(height: 6),
        Text(
          _machineWarrantyStatusText != null
              ? 'ตรวจสอบจากข้อมูลเครื่องจักร: $_machineWarrantyStatusText'
              : 'ไม่พบข้อมูลประกันของเครื่องจักรนี้ในระบบ — เปิดสวิตช์เองได้ถ้า'
                  'ทราบว่ายังอยู่ในประกัน',
          style: const TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontSize: 12,
            color: AppColors.textSubtitle,
          ),
        ),
        if (_isWarrantyCovered) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.greenBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.greenText, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ช่างยังกรอกรายการ/ราคาค่าใช้จ่ายด้านล่างได้ตามปกติเพื่อ'
                    'บันทึกไว้เป็นหลักฐาน แต่ลูกค้าจะไม่เห็นปุ่มชำระเงินหรือ '
                    'QR code สำหรับบิลนี้',
                    style: TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 12,
                      color: AppColors.greenText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // การ์ดที่ 3: รายการสินค้า/บริการ
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // การ์ด: อะไหล่จากคำขอเบิกที่อนุมัติแล้วของงานนี้ (ยังไม่ถูกออกบิล)
  // ---------------------------------------------------------------------------
  Widget _buildSuggestedPartsCard() {
    return _card(
      icon: Icons.sync_alt,
      title: 'อะไหล่จากคำขอเบิกของงานนี้',
      children: [
        if (_loadingPartRequests)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else ...[
          const Text(
            'ช่างเบิกอะไหล่พวกนี้ไปสำหรับงานนี้ และแอดมินอนุมัติแล้ว '
            'กด "เพิ่มเข้าบิล" เพื่อดึงมาเป็นรายการในใบแจ้งหนี้ได้เลย',
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 12,
              color: AppColors.textSubtitle,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _availablePartRequests.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: _SuggestedPartTile(
                request: _availablePartRequests[i],
                unitPrice: _partRequestUnitPrice[
                        toIntOrNull(_availablePartRequests[i]['part_id'])] ??
                    0,
                money: _money,
                onAdd: () =>
                    _addPartRequestToInvoice(_availablePartRequests[i]),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildItemsCard() {
    return _card(
      icon: Icons.inventory_2_outlined,
      title: 'รายการสินค้า / บริการ',
      action: TextButton.icon(
        onPressed: () => _showItemDialog(),
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          'เพิ่ม',
          style: TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      children: [
        if (_items.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.format_list_bulleted,
                    size: 32, color: AppColors.textHint),
                SizedBox(height: 8),
                Text(
                  'ยังไม่มีรายการ กด "เพิ่ม" ด้านบนเพื่อเริ่มต้น',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 13,
                    color: AppColors.textSubtitle,
                  ),
                ),
              ],
            ),
          )
        else
          for (var i = 0; i < _items.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: _InvoiceItemTile(
                index: i + 1,
                item: _items[i],
                money: _money,
                onEdit: () =>
                    _showItemDialog(itemToEdit: _items[i], indexToEdit: i),
                onDelete: () => setState(() => _items.removeAt(i)),
              ),
            ),
        if (_items.isNotEmpty) ...[
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'รวม ${_items.length} รายการ',
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 13,
                  color: AppColors.textSubtitle,
                ),
              ),
              Text(
                '฿${_money(_subtotal)}',
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // การ์ดที่ 4: สรุปยอดเงิน
  // ---------------------------------------------------------------------------
  Widget _buildFinancialSummaryCard() {
    return _card(
      icon: Icons.calculate_outlined,
      title: 'สรุปยอดเงิน',
      children: [
        _buildSummaryRow('รวมเป็นเงิน', '฿${_money(_subtotal)}'),
        const SizedBox(height: 10),

        // ช่องป้อนเงินส่วนลด
        Row(
          children: [
            const Expanded(
              child: Text(
                'ส่วนลด',
                style: TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 14,
                  color: AppColors.textMain,
                ),
              ),
            ),
            SizedBox(
              width: 130,
              child: TextFormField(
                controller: _discountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                decoration: _inputStyle(hint: '0', suffix: '฿'),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        if (_discountAmount > 0) ...[
          const SizedBox(height: 10),
          _buildSummaryRow(
            'ยอดหลังหักส่วนลด',
            '฿${_money(_subtotalAfterDiscount)}',
            key: const ValueKey('discount_after_row'),
          ),
        ],
        const SizedBox(height: 14),
        const Divider(height: 1, color: AppColors.border),
        const SizedBox(height: 6),

        // สวิตช์คำนวณ VAT 7%
        _TaxSwitch(
          key: const ValueKey('vat_switch'),
          label: 'ภาษีมูลค่าเพิ่ม (VAT 7%)',
          value: _includeVat,
          onChanged: (val) => setState(() => _includeVat = val),
        ),
        if (_includeVat)
          _buildSummaryRow(
            'VAT 7%',
            '+฿${_money(_vatAmount)}',
            key: const ValueKey('vat_amount_row'),
          ),

        // สวิตช์คำนวณภาษีหัก ณ ที่จ่าย
        _TaxSwitch(
          key: const ValueKey('wht_switch'),
          label: 'หักภาษี ณ ที่จ่าย',
          value: _enableWithholdingTax,
          onChanged: (val) => setState(() => _enableWithholdingTax = val),
        ),
        if (_enableWithholdingTax) ...[
          Padding(
            key: const ValueKey('wht_rate_picker'),
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'อัตราหัก ณ ที่จ่าย',
                    style: TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 14,
                      color: AppColors.textMain,
                    ),
                  ),
                ),
                DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: _withholdingTaxRate,
                    isDense: true,
                    borderRadius: BorderRadius.circular(10),
                    style: const TextStyle(
                      fontFamily: AppStyles.fontFamily,
                      fontSize: 14,
                      color: AppColors.textMain,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1.0, child: Text('1% (ขนส่ง)')),
                      DropdownMenuItem(value: 2.0, child: Text('2% (โฆษณา)')),
                      DropdownMenuItem(value: 3.0, child: Text('3% (บริการ)')),
                      DropdownMenuItem(value: 5.0, child: Text('5% (ค่าเช่า)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _withholdingTaxRate = val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          _buildSummaryRow(
            'หัก ณ ที่จ่าย ${_withholdingTaxRate.toStringAsFixed(0)}%',
            '-฿${_money(_withholdingTaxAmount)}',
            color: AppColors.redText,
            key: const ValueKey('wht_amount_row'),
          ),
        ],
      ],
    );
  }

  /// Helper Widget สำหรับสร้างแถวแสดงรายการยอดเงิน
  Widget _buildSummaryRow(String label, String value,
      {Color? color, Key? key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
              color: AppColors.textSubtitle,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color ?? AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }

  /// แถบล่างค้างจอ — เห็นยอดสุทธิและกดบันทึกได้ตลอดโดยไม่ต้องเลื่อนลง
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'ยอดสุทธิ',
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const Spacer(),
                Text(
                  '฿${_money(_grandTotal)}',
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            // 🆕 [ใหม่] เตือนย้ำอีกครั้งตรงปุ่มบันทึกว่าบิลนี้ลูกค้าไม่ต้องจ่าย
            if (_isWarrantyCovered) ...[
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'ลูกค้าไม่ต้องชำระเงิน (อยู่ในประกัน)',
                  style: TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.greenText,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: AppStyles.primaryButton.copyWith(
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                onPressed: _isSaving ? null : _saveInvoice,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _isSaving ? 'กำลังบันทึก...' : 'บันทึกใบแจ้งหนี้',
                  style: AppStyles.buttonText.copyWith(
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// [SECTION 8] SUB-WIDGETS
// =============================================================================

/// ช่องเลือกวันที่ — แตะแล้วเปิดปฏิทิน
class _DateField extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStyles.fieldLabel(label, required: false),
        Material(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// แถวสวิตช์ภาษี — กะทัดรัดกว่า SwitchListTile ที่กินพื้นที่แนวตั้งเยอะ
class _TaxSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _TaxSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
              color: AppColors.textMain,
            ),
          ),
        ),
        Transform.scale(
          scale: 0.85,
          child: Switch(
            key: key,
            value: value,
            onChanged: onChanged,
            // -----------------------------------------------------------------
            // แก้ไขปัญหาปุ่มหายด้วยการแยกสีของ Track และ Thumb ให้ชัดเจน
            // -----------------------------------------------------------------
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.primary,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }
}

/// แถวรายการสินค้า 1 รายการในใบแจ้งหนี้
/// แถวอะไหล่ 1 รายการจากคำขอเบิกที่อนุมัติแล้ว พร้อมปุ่ม "เพิ่มเข้าบิล"
class _SuggestedPartTile extends StatelessWidget {
  final Map<String, dynamic> request;
  final double unitPrice;
  final String Function(double) money;
  final VoidCallback onAdd;

  const _SuggestedPartTile({
    required this.request,
    required this.unitPrice,
    required this.money,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final quantity = toIntOrNull(request['quantity']) ?? 1;
    final total = unitPrice * quantity;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (request['part_name']?.toString()) ?? 'อะไหล่',
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'จำนวน $quantity x ฿${money(unitPrice)}'
                  '${unitPrice == 0 ? ' (ยังไม่ตั้งราคาอะไหล่นี้)' : ''}',
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
          Text(
            '฿${money(total)}',
            style: const TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textMain,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onAdd,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Text(
              'เพิ่มเข้าบิล',
              style: TextStyle(
                fontFamily: AppStyles.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceItemTile extends StatelessWidget {
  final int index;
  final InvoiceItem item;
  final String Function(double) money;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _InvoiceItemTile({
    required this.index,
    required this.item,
    required this.money,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$index',
              style: const TextStyle(
                fontFamily: AppStyles.fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    fontFamily: AppStyles.fontFamily,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item.quantity} x ฿${money(item.unitPrice)}',
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '฿${money(item.totalPrice)}',
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textMain,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    color: AppColors.textSubtitle,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'แก้ไขรายการ',
                    onPressed: onEdit,
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    color: AppColors.redText,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'ลบรายการ',
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
