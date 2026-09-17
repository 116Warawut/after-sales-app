// ==========================================
// SECTION 1: IMPORTS
// ==========================================
import 'package:flutter/material.dart';
import 'package:after_sales/models/technician.dart';
import 'package:after_sales/services.dart';
import 'package:after_sales/widgets.dart';

// ==========================================
// SECTION 2: MAIN SCREEN WIDGET
// ==========================================

class AssignTacticianScreen extends StatefulWidget {
  const AssignTacticianScreen({super.key});

  @override
  State<AssignTacticianScreen> createState() => _AssignTacticianScreenState();
}

// ==========================================
// SECTION 3: STATE MANAGEMENT & LOGIC
// ==========================================

class _AssignTacticianScreenState extends State<AssignTacticianScreen> {
  List<Technician> _technicians = [];
  bool _isLoading = true;
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadTechniciansFromDatabase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// 🔄 ดึงข้อมูลช่างจาก Database จริง
  /// สถานะ "ไม่ว่าง" คำนวณจากตาราง repairs: ถ้าช่างคนไหนมีงานสถานะ
  /// "กำลังดำเนินการ" ค้างอยู่ ให้ถือว่าไม่ว่าง (เพราะตาราง technicians
  /// ไม่มีคอลัมน์เก็บสถานะนี้โดยตรง)
  Future<void> _loadTechniciansFromDatabase() async {
    setState(() => _isLoading = true);

    try {
      final dbHelper = DatabaseHelper.instance;

      final List<Map<String, dynamic>> result =
          await dbHelper.getAllTechnicians();

      if (result.isNotEmpty) {
        // หาว่าช่างคนไหน "ไม่ว่าง" อยู่ตอนนี้ (มีงานกำลังดำเนินการค้างอยู่)
        final allRepairs = await dbHelper.getAllRepairs();
        final busyUsernames = allRepairs
            .where((r) =>
                r['status'] == 'กำลังดำเนินการ' &&
                r['technician_username'] != null)
            .map((r) => r['technician_username'].toString())
            .toSet();

        _technicians = result.asMap().entries.map((entry) {
          final map = entry.value;
          final username = map['username']?.toString() ?? '';
          return Technician.fromMap(
            map,
            entry.key,
            isBusyOverride: busyUsernames.contains(username),
          );
        }).toList();
      } else {
        // 🧹 [ลบ mockup] เดิมถ้าฐานข้อมูลว่างจะโชว์ช่างปลอม 3 คน
        // (tech_tamdee/tech_somchai/tech_winai) ที่ไม่มี record จริงใน Firebase
        // ปัญหาคือแอดมินสามารถกดเลือกคนพวกนี้แล้ว "มอบหมายงาน" ให้จริง ๆ ได้
        // ทำให้ repair ถูกผูกกับ technician_username ที่ไม่มีตัวตน ช่างคนนั้นก็จะ
        // ไม่เห็นงานในแอปตัวเองเลย (เพราะ query หา username ไม่เจอ) ตอนนี้เปลี่ยน
        // เป็นปล่อยลิสต์ว่าง ให้ไปเข้า _EmptyTechniciansView ที่มีอยู่แล้วแทน
        _technicians = [];
      }
    } catch (e) {
      debugPrint('Error loading technicians: $e');
      _technicians = [];
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 🧹 ล้างคำค้นหา
  void _clearSearch() {
    _searchController.clear();
    setState(() => _searchQuery = '');
  }

// ==========================================
// SECTION 4: BUILD METHOD
// ==========================================

  @override
  Widget build(BuildContext context) {
    // ดึงค่าการค้นหาออกมาภายนอก Loop เพื่อเพิ่มประสิทธิภาพ
    final query = _searchQuery.trim().toLowerCase();

    // กรองข้อมูลตามคำค้นหา (ชื่อ หรือ บทบาท)
    final filteredTechnicians = _technicians.where((tech) {
      if (query.isEmpty) return true;
      final nameMatches = tech.name.toLowerCase().contains(query);
      final roleMatches = tech.role.toLowerCase().contains(query);
      return nameMatches || roleMatches;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Column(
        children: [
          const AppHeader(title: 'มอบหมายงานให้ช่าง', showBack: true),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _SearchBar(
                        controller: _searchController,
                        searchQuery: _searchQuery,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        onClear: _clearSearch,
                      ),
                      Expanded(
                        child: filteredTechnicians.isEmpty
                            ? const _EmptyTechniciansView()
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12.0),
                                itemCount: filteredTechnicians.length,
                                itemBuilder: (context, index) {
                                  final tech = filteredTechnicians[index];
                                  return _TechnicianTile(
                                    tech: tech,
                                    onSelect: () =>
                                        Navigator.pop(context, tech),
                                  );
                                },
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

// ==========================================
// SECTION 5: SUB-WIDGETS (Modular Components)
// ==========================================

/// 🔍 ช่องค้นหา
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.searchQuery,
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
          hintText: 'ค้นหาชื่อ หรือ ตำแหน่ง...',
          prefixIcon: const Icon(Icons.search, color: Colors.grey),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: Colors.grey),
                  onPressed: onClear,
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: EdgeInsets.zero,
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
            borderSide: BorderSide(color: Theme.of(context).primaryColor),
          ),
        ),
      ),
    );
  }
}

/// 🚫 แสดงเมื่อไม่พบข้อมูลการค้นหา
class _EmptyTechniciansView extends StatelessWidget {
  const _EmptyTechniciansView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'ไม่พบข้อมูลช่างที่ค้นหา',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

/// 👨‍🔧 การ์ดแสดงข้อมูลช่างแต่ละคน
class _TechnicianTile extends StatelessWidget {
  final Technician tech;
  final VoidCallback onSelect;

  const _TechnicianTile({
    required this.tech,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final isBusy = tech.isBusy == 1;

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        leading: CircleAvatar(
          radius: 24,
          backgroundColor: tech.avatarColor,
          child: Text(
            tech.initials,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        title: Text(
          tech.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${tech.role} | ${tech.code}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ),
        trailing: isBusy
            ? Chip(
                label: const Text(
                  'ไม่ว่าง',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                backgroundColor: Colors.grey.shade400,
                side: BorderSide.none,
                padding: EdgeInsets.zero,
              )
            : ElevatedButton(
                onPressed: onSelect,
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('เลือก'),
              ),
      ),
    );
  }
}
