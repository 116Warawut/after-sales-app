import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'add_machine_page.dart';
import 'machine_detail_page.dart';
import 'machine_models.dart';

class MachineListPage extends StatefulWidget {
  const MachineListPage({super.key});

  @override
  State<MachineListPage> createState() => _MachineListPageState();
}

class _MachineListPageState extends State<MachineListPage> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  bool _loading = true;
  List<Machine> _machines = [];
  bool _showAll = false;
  static const int _previewCount = 10;

  @override
  void initState() {
    super.initState();
    _loadMachines();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// ดึงรายการเครื่องจักรของลูกค้าจาก Database (พร้อม Error Handling)
  Future<void> _loadMachines() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final rows = await db.DatabaseHelper.instance.getMachinesForCustomer(
        db.Session.currentUsername,
      );

      if (!mounted) return;

      setState(() {
        _machines = rows.map((row) => Machine.fromMap(row)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  /// กรองรายการเครื่องจักรตาม S/N, ชื่อรุ่น หรือ Label
  List<Machine> get _filteredMachines {
    if (_query.trim().isEmpty) return _machines;
    final q = _query.trim().toLowerCase();
    return _machines.where((m) {
      final sn = m.serialNumber.toLowerCase();
      final model = m.modelName.toLowerCase();
      final label = m.label.toLowerCase();
      return sn.contains(q) || model.contains(q) || label.contains(q);
    }).toList();
  }

  /// เปิดหน้ารายละเอียด และรีเฟรชข้อมูลเมื่อย้อนกลับมา
  Future<void> _openDetail(Machine machine) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MachineDetailPage(machine: machine),
      ),
    );

    if (!mounted) return;
    _loadMachines();
  }

  /// เปิดหน้าเพิ่มเครื่องจักรใหม่ และรีเฟรชรายการเมื่อบันทึกสำเร็จ
  Future<void> _openAddMachine() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => const AddMachinePage(),
      ),
    );

    if (saved == true && mounted) {
      _loadMachines();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allFiltered = _filteredMachines;
    final hasSearch = _query.trim().isNotEmpty;
    final machines = (hasSearch || _showAll)
        ? allFiltered
        : allFiltered.take(_previewCount).toList();
    final showExpandButton =
        !hasSearch && !_showAll && allFiltered.length > _previewCount;

    return GestureDetector(
      // แตะพื้นที่ว่างเพื่อซ่อนคีย์บอร์ด
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              // ---------------------------------------------------------
              // Header + Search Field
              // ---------------------------------------------------------
              AppHeader(
                title: 'รายการเครื่องจักร',
                showBack: true,
                trailing: Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.hardEdge,
                  child: IconButton(
                    onPressed: _openAddMachine,
                    tooltip: 'เพิ่มเครื่องจักร',
                    icon: const Icon(Icons.add_circle_outline,
                        color: Colors.white),
                  ),
                ),
              ),
              Container(
                width: double.infinity,
                color: AppColors.primary,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x19000000),
                        blurRadius: 3,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.search,
                        size: 20,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) =>
                              FocusScope.of(context).unfocus(),
                          onChanged: (value) =>
                              setState(() => _query = value),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            hintText: 'ค้นหา S/N หรือชื่อรุ่น...',
                            hintStyle: TextStyle(
                              color: Colors.black45,
                              fontSize: 14,
                            ),
                          ),
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          child: const Icon(
                            Icons.close,
                            size: 18,
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // Result Count
              // ---------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'พบ ${machines.length} เครื่อง',
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),

              // ---------------------------------------------------------
              // Machine List View
              // ---------------------------------------------------------
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadMachines,
                        child: machines.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 100),
                                  Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.search_off,
                                          size: 48,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'ไม่พบรายการเครื่องจักรที่ค้นหา',
                                          style: TextStyle(
                                            color: Colors.black54,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  16,
                                ),
                                itemCount:
                                    machines.length + (showExpandButton ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index == machines.length) {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: TextButton(
                                        onPressed: () =>
                                            setState(() => _showAll = true),
                                        child: Text(
                                          'ดูทั้งหมด (${allFiltered.length} รายการ)',
                                          style: const TextStyle(
                                              color: AppColors.primary),
                                        ),
                                      ),
                                    );
                                  }
                                  final machine = machines[index];
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: _MachineCard(
                                      machine: machine,
                                      onTap: () => _openDetail(machine),
                                    ),
                                  );
                                },
                              ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card แสดงข้อมูลเครื่องจักร
class _MachineCard extends StatelessWidget {
  final Machine machine;
  final VoidCallback onTap;

  const _MachineCard({required this.machine, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isWarrantyActive = machine.warrantyActive;
    final statusColor =
        isWarrantyActive ? AppColors.greenText : AppColors.redText;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 92,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Machine Photo Thumbnail (แสดงรูปจริงถ้ามี ไม่งั้น fallback เป็นไอคอน)
                machine.photoUrl.isEmpty
                    ? Container(
                        width: 90,
                        height: double.infinity,
                        color: AppColors.textHint,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.precision_manufacturing,
                          color: Colors.white,
                          size: 32,
                        ),
                      )
                    : LocalOrNetworkImage(
                        path: machine.photoUrl,
                        width: 90,
                        height: double.infinity,
                        fit: BoxFit.cover,
                      ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'S/N: ${machine.serialNumber}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          machine.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              isWarrantyActive
                                  ? Icons.verified
                                  : Icons.error_outline,
                              size: 14,
                              color: statusColor,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                machine.warrantyStatusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}