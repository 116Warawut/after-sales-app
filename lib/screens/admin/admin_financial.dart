import 'package:flutter/material.dart';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/screens/admin/admin_create_invoice.dart';
import 'package:after_sales/screens/customer/payment.dart';
import 'package:after_sales/widgets.dart';
import 'package:after_sales/utils/firebase_number.dart';

/// ใบแจ้งหนี้ — แปลงจาก row จริงของตาราง `repairs` ที่มีการออกบิลแล้ว
/// (มี bill_id ไม่ว่าง)
class Invoice {
  final int repairId;
  final String id;
  final String date;
  final double amount;
  // 🆕 [ใหม่] true = บิลนี้ยกเว้นค่าใช้จ่ายเพราะเครื่องจักรอยู่ในประกัน — ใช้โชว์
  // ป้ายแยกในรายการบิล กันแอดมินสับสนว่าเป็นยอดชำระจริง (ดู updateRepairBill()
  // ใน services.dart และการ์ด "การรับประกัน" ใน admin_create_invoice.dart)
  final bool isWarrantyCovered;

  Invoice({
    required this.repairId,
    required this.id,
    required this.date,
    required this.amount,
    this.isWarrantyCovered = false,
  });

  factory Invoice.fromMap(Map<String, dynamic> map) {
    return Invoice(
      // 🐛 [แก้บัค] เดิมอ่าน map['id'] ตรง ๆ ซึ่งอาจไม่ตรงกับคีย์จริงใน Firebase
      // ของ record นี้ ทำให้กดเข้าไปหน้าชำระเงินแล้วเปิดไปเจอใบงานคนละใบ —
      // ใช้ resolveRecordId() ที่ยึดคีย์จริงเป็นหลักแทน (ดูเหตุผลใน
      // utils/firebase_number.dart)
      repairId: resolveRecordId(map) ?? 0,
      id: (map['bill_id']?.toString()) ?? '-',
      date: (map['invoice_date']?.toString()) ??
          (map['date']?.toString()) ??
          '-',
      amount: toDoubleOrNull(map['total_price']) ?? 0,
      isWarrantyCovered:
          map['is_warranty_covered'] == true || map['is_warranty_covered'] == 1,
    );
  }
}

class FinancialScreen extends StatefulWidget {
  const FinancialScreen({super.key});

  @override
  State<FinancialScreen> createState() => _FinancialScreenState();
}

class _FinancialScreenState extends State<FinancialScreen> {
  bool _loading = true;
  List<Invoice> _invoices = [];

  @override
  void initState() {
    super.initState();
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    setState(() => _loading = true);
    try {
      final rows = await db.DatabaseHelper.instance.getAllRepairs();
      final invoices = rows
          .where((r) =>
              r['bill_id'] != null &&
              r['bill_id'].toString().trim().isNotEmpty)
          .map((r) => Invoice.fromMap(r))
          .toList();
      if (!mounted) return;
      setState(() {
        _invoices = invoices;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showTodo('โหลดรายการบิลไม่สำเร็จ: $e');
    }
  }

  void _showTodo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message), backgroundColor: AppColors.primary),
    );
  }

  Future<void> _openCreateInvoice() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminCreateInvoicePage()),
    );
    _loadInvoices();
  }

  void _openInvoiceHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _InvoiceHistoryPage(
          invoices: _invoices,
          onOpenInvoice: _openInvoiceDetail,
        ),
      ),
    );
  }

  Future<void> _openInvoiceDetail(Invoice invoice) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentPage(repairId: invoice.repairId),
      ),
    );
    _loadInvoices();
  }

  @override
  Widget build(BuildContext context) {
    final recent = _invoices.take(5).toList();
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'ค่าใช้จ่าย', showBack: true),
            Expanded(
              child: RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadInvoices,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
                  children: [
                    _ActionCard(
                      icon: Icons.receipt_long,
                      title: 'ออกบิล',
                      subtitle: 'สร้างใบแจ้งหนี้ใหม่',
                      onTap: _openCreateInvoice,
                    ),
                    const SizedBox(height: 16),
                    _ActionCard(
                      icon: Icons.history,
                      title: 'ดูประวัติการออกบิล',
                      subtitle: 'ตรวจสอบรายการที่ผ่านมา',
                      onTap: _openInvoiceHistory,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.receipt, size: 16, color: Colors.black87),
                            SizedBox(width: 8),
                            Text(
                              'รายการออกบิลล่าสุด',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        GestureDetector(
                          onTap: _openInvoiceHistory,
                          child: const Text(
                            'ดูทั้งหมด',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(color: AppColors.primary),
                        ),
                      )
                    else if (recent.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'ยังไม่มีรายการออกบิล',
                            style: TextStyle(color: AppColors.textSubtitle),
                          ),
                        ),
                      )
                    else
                      Container(
                        decoration: ShapeDecoration(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          shadows: const [
                            BoxShadow(
                              color: Color(0x19000000),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                              spreadRadius: -2,
                            ),
                            BoxShadow(
                              color: Color(0x19000000),
                              blurRadius: 6,
                              offset: Offset(0, 4),
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            for (int i = 0; i < recent.length; i++)
                              _InvoiceTile(
                                invoice: recent[i],
                                showDivider: i != recent.length - 1,
                                onTap: () => _openInvoiceDetail(recent[i]),
                              ),
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

/// หน้าแสดงประวัติการออกบิลทั้งหมด
class _InvoiceHistoryPage extends StatelessWidget {
  final List<Invoice> invoices;
  final ValueChanged<Invoice> onOpenInvoice;

  const _InvoiceHistoryPage({
    required this.invoices,
    required this.onOpenInvoice,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'ประวัติการออกบิล', showBack: true),
            Expanded(
              child: invoices.isEmpty
                  ? const Center(
                      child: Text(
                        'ยังไม่มีรายการออกบิล',
                        style: TextStyle(color: AppColors.textSubtitle),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          decoration: ShapeDecoration(
                            color: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            shadows: const [
                              BoxShadow(
                                color: Color(0x19000000),
                                blurRadius: 4,
                                offset: Offset(0, 2),
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              for (int i = 0; i < invoices.length; i++)
                                _InvoiceTile(
                                  invoice: invoices[i],
                                  showDivider: i != invoices.length - 1,
                                  onTap: () => onOpenInvoice(invoices[i]),
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
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            shadows: const [
              BoxShadow(
                color: Color(0x19000000),
                blurRadius: 4,
                offset: Offset(0, 2),
                spreadRadius: -2,
              ),
              BoxShadow(
                color: Color(0x19000000),
                blurRadius: 6,
                offset: Offset(0, 4),
                spreadRadius: -1,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment(0.0, 0.0),
                    end: Alignment(1.0, 1.0),
                    colors: [AppColors.primary, AppColors.primary],
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: const ShapeDecoration(
                  color: AppColors.surface,
                  shape: CircleBorder(),
                ),
                child: const Icon(Icons.chevron_right,
                    size: 16, color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InvoiceTile extends StatelessWidget {
  final Invoice invoice;
  final bool showDivider;
  final VoidCallback onTap;

  const _InvoiceTile({
    required this.invoice,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: showDivider
                ? const Border(
                    bottom: BorderSide(width: 1, color: AppColors.surfaceAlt))
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: const ShapeDecoration(
                  color: AppColors.surface,
                  shape: CircleBorder(),
                ),
                child: const Icon(Icons.description_outlined,
                    size: 16, color: Colors.black54),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'บิลหมายเลข ${invoice.id}',
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // 🆕 [ใหม่] ป้าย "ประกัน" แยกให้เห็นชัดว่าบิลนี้ไม่มี
                        // ค่าใช้จ่ายจริง กันแอดมินเข้าใจผิดว่าเป็นยอดขาย
                        if (invoice.isWarrantyCovered) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.greenBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ประกัน',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.greenText,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoice.date,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '฿${_formatAmount(invoice.amount)}',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    final RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final integerPart = parts[0].replaceAllMapped(reg, (m) => '${m[1]},');
    return '$integerPart.${parts[1]}';
  }
}