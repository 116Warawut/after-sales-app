// ==========================================
// 🗺️ หน้าติดตามตำแหน่งงานซ่อม สำหรับแอดมิน (Admin Tracking)
// ==========================================
// ใช้ระบบแผนที่แบบเดียวกับฝั่งช่าง/ลูกค้า (RouteMapView + Geoapify) แทนการเปิด
// Google Maps ภายนอก โดย "ไม่มีเงื่อนไข" ใดๆ กั้นการดูตำแหน่ง (แอดมินดูได้ทุกเมื่อ
// ไม่ต้องรอถึงวันนัดซ่อมหรือถึงคิวงานเหมือนฝั่งลูกค้า) — ตำแหน่งช่างที่แสดงจะเป็น
// พิกัดล่าสุดที่ฝั่งช่างอัปเดตไว้ใน DB เอง (จากหน้า "ตำแหน่งลูกค้า" ของช่าง) แอดมิน
// เป็นเพียงผู้ดู ไม่ได้ขอ GPS จากเครื่องแอดมินเอง
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/geoapify_service.dart';
import 'package:after_sales/screens/shared/route_map_view.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

class AdminTrackingPage extends StatefulWidget {
  final int repairId;
  const AdminTrackingPage({super.key, required this.repairId});

  @override
  State<AdminTrackingPage> createState() => _AdminTrackingPageState();
}

class _AdminTrackingPageState extends State<AdminTrackingPage> {
  bool _loading = true;
  String? _errorMessage;

  String _ticketId = '-';
  String _customerName = '-';
  String _customerAddress = '-';
  String _technicianName = '-';
  String _technicianPhone = '-';

  LatLng? _techPosition;
  LatLng? _customerPosition;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0;
  int _etaMinutes = 0;

  /// true เมื่อมีช่างที่รับผิดชอบงานนี้ แต่ยังไม่เคยมีการอัปเดตพิกัดจากฝั่งช่างเลย
  bool _technicianLocationMissing = false;

  @override
  void initState() {
    super.initState();
    _loadTrackingData();
  }

  Future<void> _loadTrackingData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    // 🛡️ [แก้ไข] เดิมฟังก์ชันนี้ไม่มี try/catch เลย — ถ้าขั้นตอนไหนโยน exception
    // ขึ้นมา (เช่น query DB พลาด, แปลงค่า null ผิดชนิด) โค้ดจะหยุดทำงานกลางคัน
    // แบบไม่มีใครจับ ทำให้ไม่มีการ setState(loading=false) เกิดขึ้นอีกเลย
    // หน้าจึงค้างที่ "กำลังโหลด" ตลอดไปโดยไม่มี error โผล่ให้เห็น (แผนที่เลย
    // ไม่มีทางถูกสร้างขึ้นมา เพราะ RouteMapView จะแสดงก็ต่อเมื่อ loading เป็น false)
    try {
      // 1. ดึงข้อมูลใบแจ้งซ่อม — แอดมินดูได้ทุกเมื่อ ไม่มีเงื่อนไขเรื่องวันนัด/คิวงาน
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);
      if (repair == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'ไม่พบข้อมูลใบแจ้งซ่อมในระบบ';
          _loading = false;
        });
        return;
      }
      await _loadFromRepair(repair);
    } catch (e, st) {
      debugPrint('AdminTrackingPage._loadTrackingData error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการโหลดข้อมูลตำแหน่ง: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadFromRepair(Map<String, dynamic> repair) async {
    _ticketId = repair['ticketNo']?.toString() ??
        repair['ticket_no']?.toString() ??
        '#AS-${repair['id']}';

    // 2. ข้อมูลลูกค้า + พิกัดปลายทาง
    final customerUsername = repair['customer_username'] as String?;
    if (customerUsername != null && customerUsername.isNotEmpty) {
      final customerRow =
          await db.DatabaseHelper.instance.getCustomerProfile(customerUsername);
      if (customerRow != null) {
        final name = (customerRow['name'] as String?) ?? '';
        final surname = (customerRow['surname'] as String?) ?? '';
        final fullName = '$name $surname'.trim();
        _customerName = fullName.isNotEmpty ? fullName : '-';
      }
    }
    _customerAddress = (repair['location'] as String?) ??
        (repair['address'] as String?) ??
        '-';

    double? destLat = (repair['dest_lat'] as num?)?.toDouble();
    double? destLng = (repair['dest_lng'] as num?)?.toDouble();

    // ถ้าไม่มีพิกัดปักหมุดไว้ ลอง Geocode จากข้อความที่อยู่แทน
    if ((destLat == null || destLng == null) &&
        _customerAddress.isNotEmpty &&
        _customerAddress != '-') {
      final geocoded = await GeoapifyService.geocodeAddress(_customerAddress);
      if (geocoded != null) {
        destLat = geocoded['lat'];
        destLng = geocoded['lng'];
      }
    }

    // 3. ข้อมูลช่างที่รับผิดชอบงานนี้ + ตำแหน่งล่าสุดที่ช่างอัปเดตไว้เอง
    // (แอดมินไม่ได้ขอ GPS จากเครื่องตัวเอง แค่อ่านค่าล่าสุดจาก DB)
    final techUsername = repair['technician_username'] as String?;
    double? startLat;
    double? startLng;

    if (techUsername != null && techUsername.isNotEmpty) {
      final techRow = await db.DatabaseHelper.instance
          .getTechnicianByUsername(techUsername);
      if (techRow != null) {
        _technicianName =
            (techRow['tech_name'] as String?)?.trim().isNotEmpty == true
                ? (techRow['tech_name'] as String).trim()
                : '-';
        _technicianPhone = (techRow['phone'] as String?) ?? '-';
        startLat = (techRow['current_lat'] as num?)?.toDouble();
        startLng = (techRow['current_lng'] as num?)?.toDouble();
        _technicianLocationMissing = startLat == null || startLng == null;
      }
    }

    // 4. คำนวณเส้นทางจริงบนถนน (ถ้ามีพิกัดครบทั้งสองฝั่ง)
    List<LatLng> routePoints = [];
    double distanceKm = 0;
    int etaMinutes = 0;
    if (startLat != null &&
        startLng != null &&
        destLat != null &&
        destLng != null) {
      final routeInfo = await GeoapifyService.getRouteInfo(
        startLat: startLat,
        startLng: startLng,
        destLat: destLat,
        destLng: destLng,
      );
      if (routeInfo != null) {
        distanceKm = routeInfo['distance_km'] ?? 0;
        etaMinutes = routeInfo['time_minutes'] ?? 0;
        final pts = routeInfo['route_points'] as List<Map<String, double>>?;
        if (pts != null && pts.isNotEmpty) {
          routePoints = pts.map((p) => LatLng(p['lat']!, p['lng']!)).toList();
        }
      }
    }

    if (!mounted) return;

    if (destLat == null || destLng == null) {
      setState(() {
        _errorMessage = 'ไม่สามารถระบุพิกัดที่อยู่ลูกค้าได้';
        _loading = false;
      });
      return;
    }

    setState(() {
      _customerPosition = LatLng(destLat!, destLng!);
      _techPosition = (startLat != null && startLng != null)
          ? LatLng(startLat, startLng)
          : null;
      _routePoints = routePoints;
      _distanceKm = distanceKm;
      _etaMinutes = etaMinutes;
      _loading = false;
    });
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
            AppHeader(title: 'ติดตามงานซ่อม $_ticketId', showBack: true),

            // ⚠️ แจ้งเตือนแบบไม่บล็อกหน้าจอ ถ้าช่างยังไม่เคยอัปเดตตำแหน่งเลย
            if (!_loading && _technicianLocationMissing)
              Container(
                width: double.infinity,
                color: Colors.amber.shade50,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.amber.shade800, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'ยังไม่มีตำแหน่งช่างล่าสุด (ช่างยังไม่เคยเปิดหน้าติดตามตำแหน่งลูกค้า)',
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: AppStyles.fontFamily,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _loading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : (_errorMessage != null || _customerPosition == null)
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _errorMessage ?? 'ไม่มีข้อมูลตำแหน่ง',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 15,
                                fontFamily: AppStyles.fontFamily,
                                height: 1.5,
                              ),
                            ),
                          ),
                        )
                      : RouteMapView(
                          startPoint: _techPosition,
                          endPoint: _customerPosition,
                          routePoints: _routePoints,
                        ),
            ),

            // การ์ดข้อมูลสรุปด้านล่าง
            if (!_loading && _customerPosition != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.engineering,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ช่าง: $_technicianName ${_technicianPhone != '-' ? '($_technicianPhone)' : ''}',
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.location_on,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'ลูกค้า: $_customerName — $_customerAddress',
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (_techPosition != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.route,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            'ระยะทาง ${_distanceKm.toStringAsFixed(1)} กม. • ประมาณ $_etaMinutes นาที',
                            style: const TextStyle(
                                fontFamily: AppStyles.fontFamily, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
