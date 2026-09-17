//หมายเหตุ ตัวอย่างการติดตามช่าง (Technician Tracking) สำหรับลูกค้า ตัวเทสนั่นแหละ
import 'dart:async';
import 'dart:math' as math;
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/geoapify_service.dart';
import 'package:after_sales/screens/shared/route_map_view.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

class Technician {
  final String name;
  final String role;
  final String employeeId;
  final String vehicle;
  final String? photoUrl;

  const Technician({
    required this.name,
    required this.role,
    required this.employeeId,
    required this.vehicle,
    this.photoUrl,
  });

  // 🔴 [แก้บัค] เดิมค่า default ของทุกช่องเป็นข้อมูล mockup สมัยเทส UI
  // ('นายประสิทธิ์ โชคชัยฟาร์ม' / เลขบัตร 1265864102548 / Honda Wave กง 999)
  // พองานยังไม่มีช่าง หรือ record ช่างไม่มีฟิลด์ tech_name ลูกค้าจะเห็นชื่อช่าง
  // ปลอมคนนี้บนแผนที่ทันที ทั้งที่ยังไม่มีใครรับงาน — เปลี่ยนเป็น '-' ให้หมด
  factory Technician.fromMap(Map<String, dynamic> map) {
    return Technician(
      name: map['tech_name']?.toString() ?? '-',
      role: map['role_label']?.toString() ?? 'ช่างเทคนิค',
      employeeId: map['employee_id']?.toString() ?? '-',
      vehicle: map['vehicle']?.toString() ?? '-',
      photoUrl: map['photo_url']?.toString(),
    );
  }
}

class TechnicianTrackingPage extends StatefulWidget {
  final int? repairId;
  const TechnicianTrackingPage({super.key, this.repairId});

  @override
  State<TechnicianTrackingPage> createState() => _TechnicianTrackingPageState();
}

class _TechnicianTrackingPageState extends State<TechnicianTrackingPage> {
  bool _loading = true;
  String? _errorMessage;

  Technician? _technician;
  double _arrivalProgress = 0.4; // Mockup progress 40%
  int _minutesRemaining = 15; // Mockup 15 นาที
  double _distanceKm = 4.2; // Mockup 4.2 กม.
  LatLng? _techPosition;
  LatLng? _destPosition;
  List<LatLng> _routePoints = [];

  // 🔴 ตำแหน่งช่างแบบ Live: ฟังการเปลี่ยนแปลง current_lat/current_lng ของช่างคนนี้
  // จาก Firebase โดยตรง แทนที่จะต้องกดรีเฟรชหน้าเองถึงจะเห็นตำแหน่งล่าสุด
  StreamSubscription<Map<String, dynamic>?>? _techLocationSub;
  LatLng?
      _lastRoutedTechPosition; // ตำแหน่งล่าสุดที่เคยขอเส้นทางจาก Geoapify ไปแล้ว

  @override
  void initState() {
    super.initState();
    _loadRealTrackingData();
  }

  @override
  void dispose() {
    _techLocationSub?.cancel();
    super.dispose();
  }

  // 🔴 เริ่ม/สลับการฟังตำแหน่งของช่างคนนี้แบบเรียลไทม์ — เรียกครั้งเดียวหลังรู้ username
  // ของช่างที่รับงานนี้ (จาก _loadRealTrackingData) จากนั้นทุกครั้งที่ช่างขยับ (เปิดหน้า
  // "ตำแหน่งลูกค้า" ฝั่งช่างแล้วส่ง GPS ขึ้นมาใหม่) จุดหมุดบนแผนที่ฝั่งลูกค้าจะขยับตามทันที
  void _subscribeToTechnicianLocation(String? techUsername) {
    _techLocationSub?.cancel();
    _techLocationSub = null;
    if (techUsername == null || techUsername.isEmpty) return;

    _techLocationSub = db.DatabaseHelper.instance
        .watchTechnicianLocation(techUsername)
        .listen((row) async {
      if (!mounted) return;
      final lat = toDoubleOrNull(row?['current_lat']);
      final lng = toDoubleOrNull(row?['current_lng']);
      if (lat == null || lng == null) return;

      final newPos = LatLng(lat, lng);
      setState(() => _techPosition = newPos);

      // 🧭 ขอเส้นทางใหม่จาก Geoapify เฉพาะตอนช่างขยับไปพอสมควรแล้ว (>~50 ม.) กันยิง
      // API รัวเกินไปทุกครั้งที่พิกัด GPS สั่นนิดหน่อย
      final moved = _lastRoutedTechPosition == null ||
          _distanceRoughlyMeters(_lastRoutedTechPosition!, newPos) > 50;
      if (!moved || _destPosition == null) return;
      _lastRoutedTechPosition = newPos;

      final routeInfo = await GeoapifyService.getRouteInfo(
        startLat: newPos.latitude,
        startLng: newPos.longitude,
        destLat: _destPosition!.latitude,
        destLng: _destPosition!.longitude,
      );
      if (!mounted || routeInfo == null) return;

      final pts = routeInfo['route_points'] as List<Map<String, double>>?;
      setState(() {
        _minutesRemaining = routeInfo['time_minutes'] ?? _minutesRemaining;
        _distanceKm =
            toDoubleOrNull(routeInfo['distance_km']) ?? _distanceKm;
        if (pts != null && pts.isNotEmpty) {
          _routePoints = pts.map((p) => LatLng(p['lat']!, p['lng']!)).toList();
        }
      });
    }, onError: (e) {
      debugPrint('TechnicianTrackingPage.watchTechnicianLocation error: $e');
    });
  }

  // ระยะทางแบบคร่าว ๆ (ไม่ต้องแม่นยำระดับภูมิศาสตร์ ใช้แค่เทียบว่า "ขยับพอจะขอเส้นทาง
  // ใหม่หรือยัง") แปลงองศา lat/lng เป็นเมตรแบบประมาณการที่เส้นศูนย์สูตร
  double _distanceRoughlyMeters(LatLng a, LatLng b) {
    const metersPerDegree = 111320.0;
    final dLat = (a.latitude - b.latitude) * metersPerDegree;
    final dLng = (a.longitude - b.longitude) * metersPerDegree;
    return math.sqrt(dLat * dLat + dLng * dLng);
  }

  /// 🗓️ ฟังก์ชันแปลงข้อความวันที่ไทย

  /// 🗓️ ฟังก์ชันแปลงข้อความวันที่ไทย (เช่น 31 กรกฎาคม 2569) เพื่อเทียบกับวันที่ปัจจุบัน
  /// (ใช้เป็นเงื่อนไข "ถึงวันนัด" ด้านล่าง — เดิมไฟล์นี้อ้างถึงฟังก์ชันนี้ในคอมเมนต์
  /// แต่ไม่เคยประกาศไว้จริง ถ้าปลดคอมเมนต์เฉยๆ จะ compile ไม่ผ่าน จึงเพิ่มเข้ามาให้ครบ)
  /// 🗓️ เช็คว่าถึงวันนัดซ่อมแล้วหรือยัง (วันนี้ หรือเลยมาแล้ว)
  /// 🛠️ [แก้บั๊ก] เดิมฟังก์ชันนี้แกะรูปแบบ "31 กรกฎาคม 2569" (ชื่อเดือนเต็ม เว้น
  /// วรรคคั่น) แต่ repair['date'] ที่เก็บจริงในฐานข้อมูลเป็นรูปแบบตัวเลขคั่น "/"
  /// เช่น "1/9/2569" (แบบเดียวกับที่ใช้ทั่วทั้งแอป — ดู _parseThaiDate ใน
  /// repair_list_admin.dart / home_admin.dart) ทำให้ split(' ') ได้ length แค่ 1
  /// เงื่อนไข parts.length < 3 เป็นจริงเสมอ ฟังก์ชันเลย return false ตลอด ไม่ว่า
  /// จะถึงวันนัดจริงหรือยัง ลูกค้าเลยเห็นข้อความ "ยังไม่ถึงวันนัด" ทั้งที่นัดวันนี้
  /// พอดี ตอนนี้แก้ให้แกะรูปแบบตัวเลขคั่น / ให้ตรงกับของจริงแล้ว
  bool _isTodayOrPast(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) return false;
    try {
      final parts = dateStr.trim().split('/');
      if (parts.length != 3) return false;

      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final buddhistYear = int.parse(parts[2]);
      final year = buddhistYear - 543;

      final appointmentDate = DateTime(year, month, day);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      return !appointmentDate.isAfter(today);
    } catch (_) {
      return true;
    }
  }

  Future<void> _loadRealTrackingData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    // ---------------------------------------------------------------------
    // 🧪 1. พยายามอ่านข้อมูลจริงจาก SQLite (ถ้าไม่มีข้อมูลให้ใช้ Mockup Fallback)
    // ---------------------------------------------------------------------
    Map<String, dynamic>? repair;
    if (widget.repairId != null) {
      repair = await db.DatabaseHelper.instance.getRepairById(widget.repairId!);
    }

    // ✅ [แก้ไข] เดิมเงื่อนไขทั้งหมดด้านล่างนี้ถูก comment ไว้เพื่อทดสอบ UI ทำให้
    // ลูกค้าเห็นตำแหน่งช่างได้ตลอดเวลา ทั้งที่แอดมินสั่งนัดซ่อมไว้เป็นวันอื่น
    // ปลดคอมเมนต์และเปิดใช้งานจริงแล้ว

    if (widget.repairId == null || repair == null) {
      setState(() {
        _errorMessage = 'ไม่พบรหัสงานซ่อม';
        _loading = false;
      });
      return;
    }

    // เงื่อนไขที่ 1: ต้องถึงวันนัดซ่อมก่อนเท่านั้น ลูกค้าถึงจะติดตามตำแหน่งช่างได้
    final appointmentDate = repair['date']?.toString();
    if (!_isTodayOrPast(appointmentDate)) {
      setState(() {
        _errorMessage =
            'สามารถติดตามตำแหน่งช่างได้ในวันนัดซ่อมเท่านั้น\n(วันนัดซ่อม: $appointmentDate)';
        _loading = false;
      });
      return;
    }

    // เงื่อนไขที่ 2: ต้องถึงคิวงานนี้แล้วเท่านั้น (ใช้ระบบคิวจริงตาม approved_at
    // ถ้าช่างมีงานนัดวันเดียวกันหลายงาน ลูกค้าจะติดตามตำแหน่งช่างได้เฉพาะตอนที่
    // งานของตัวเองเป็นคิวที่ 1 (อนุมัติก่อนสุดในบรรดางานที่ยังไม่เสร็จวันนั้น) เท่านั้น
    // 🐛 [แก้บัค] เดิมอ่าน map['id'] ตรง ๆ อาจไม่ตรงกับคีย์จริงใน Firebase ของ
    // record นี้ ทำให้เช็คคิวงาน (getQueueInfo) ผิดใบ — ใช้ resolveRecordId()
    // ที่ยึดคีย์จริงเป็นหลักแทน
    final repairId = resolveRecordId(repair);
    if (repairId != null) {
      final queueInfo = await db.DatabaseHelper.instance.getQueueInfo(repairId);
      final isMyTurn = queueInfo.position == 1;
      // 🐛 [แก้บัค] เดิมมีเงื่อนไขข้อยกเว้น "isPhysicallyStarted" (status ==
      // 'กำลังซ่อม'/'กำลังเดินทาง') ที่ปล่อยผ่านได้แม้ยังไม่ถึงคิว — แต่เพราะ
      // getEffectiveRepairStatus() ใน services.dart (ตอนนั้น) บังคับคืนค่า
      // 'กำลังซ่อม' ให้ทุกงานของช่างที่ตรงกับวันนัดวันนี้เสมอ (ไม่ว่าจะถึงคิวจริง
      // หรือยัง) เงื่อนไขนี้เลยเป็นจริงตลอดเวลาโดยไม่ได้ตั้งใจ ทำให้ลูกค้าเห็น
      // ตำแหน่งช่างได้ก่อนถึงคิวของตัวเอง (ทั้งที่ช่างยังอยู่ระหว่างทำงานคิวก่อน
      // หน้าอยู่) — ตัดเงื่อนไขนี้ทิ้ง ยึด isMyTurn (คิวที่ 1 เท่านั้น) เป็นเกณฑ์
      // เดียวแทน (ฝั่ง services.dart ก็แก้ไม่ให้บังคับสถานะแบบนั้นแล้วเช่นกัน)
      if (!isMyTurn) {
        setState(() {
          _errorMessage =
              'ยังไม่ถึงคิวงานของคุณ\nขณะนี้อยู่คิวที่ ${queueInfo.position} จาก ${queueInfo.total} งานของวันนี้';
          _loading = false;
        });
        return;
      }
    }

    // ---------------------------------------------------------------------
    // 🧪 2. โหลดข้อมูลช่าง (หากไม่พบข้อมูลใน DB จะใช้ข้อมูล Mockup ทันที)
    // ---------------------------------------------------------------------
    // 🔴 [แก้บัค] เดิมตั้งค่าเริ่มต้นเป็นช่าง mockup ('นายประสิทธิ์ โชคชัยฟาร์ม')
    // แล้วค่อยทับด้วยช่างจริงถ้ามี ผลคืองานที่ยังไม่ได้จัดสรรช่าง (หรือหา record
    // ช่างไม่เจอ) ลูกค้าจะเห็นแผนที่พร้อมชื่อช่างปลอมคนนี้ — ตอนนี้ถ้ายังไม่มีช่าง
    // ให้แจ้งตามจริงแล้วจบ ไม่ต้องเปิดแผนที่
    final techUsername = repair['technician_username']?.toString();
    if (techUsername == null || techUsername.isEmpty) {
      setState(() {
        _errorMessage =
            'งานนี้ยังไม่มีการมอบหมายช่าง\nติดตามตำแหน่งได้หลังแอดมินจัดสรรช่างแล้ว';
        _loading = false;
      });
      return;
    }

    final techRow =
        await db.DatabaseHelper.instance.getTechnicianByUsername(techUsername);
    if (techRow == null) {
      setState(() {
        _errorMessage = 'ไม่พบข้อมูลช่างที่รับผิดชอบงานนี้ ($techUsername)';
        _loading = false;
      });
      return;
    }
    final Technician tech = Technician.fromMap(techRow);

    // ---------------------------------------------------------------------
    // 🧪 3. กำหนดพิกัด
    // 🔴 [แก้ไข] เดิมอ่านจาก repair['start_lat']/['start_lng'] ซึ่งเป็นคอลัมน์ที่ไม่มีอยู่จริง
    // ในตาราง repairs เลย (ไม่เคยถูกเซ็ตค่า) ทำให้ตำแหน่งช่างเป็น Mockup ตายตัว (สยาม)
    // ตลอดเวลา ไม่ว่าช่างจะอยู่ที่ไหนจริงๆ ก็ตาม
    // ที่ถูกต้องคือตำแหน่งช่างต้องอ่านจาก technicians.current_lat/current_lng ซึ่งจะถูก
    // อัปเดตเป็นพิกัด GPS จริงล่าสุดทุกครั้งที่ช่างเปิดหน้า "ตำแหน่งลูกค้า" ของฝั่งช่างเอง
    // (ดู LocationService + updateTechnicianLocation ใน customer_tracking.dart ฝั่งช่าง)
    // ---------------------------------------------------------------------
    double? startLat = toDoubleOrNull(techRow['current_lat']);
    double? startLng = toDoubleOrNull(techRow['current_lng']);
    // ถ้ายังไม่เคยมีการอัปเดตตำแหน่งช่างเลย (ช่างยังไม่เคยเปิดหน้าติดตามตำแหน่งลูกค้า
    // เพื่อส่ง GPS ขึ้นมา) ค่อย fallback เป็น Mockup เพื่อให้ยังเห็นตัวอย่างแผนที่ได้
    startLat ??= 13.7460; // Mockup: สยาม
    startLng ??= 100.5340;

    double destLat = toDoubleOrNull(repair['dest_lat']) ??
        13.7412; // Mockup: เขตสัมพันธวงศ์
    double destLng = toDoubleOrNull(repair['dest_lng']) ?? 100.5042;

    // ---------------------------------------------------------------------
    // 🧪 4. คำนวณเส้นทางจริงบนถนนจาก Geoapify Routing API
    // ---------------------------------------------------------------------
    final routeInfo = await GeoapifyService.getRouteInfo(
      startLat: startLat,
      startLng: startLng,
      destLat: destLat,
      destLng: destLng,
    );

    int etaMinutes = routeInfo != null ? routeInfo['time_minutes'] : 15;
    double distKm = routeInfo != null ? routeInfo['distance_km'] : 4.2;
    List<LatLng> routePoints = [];
    if (routeInfo != null) {
      final pts = routeInfo['route_points'] as List<Map<String, double>>?;
      if (pts != null && pts.isNotEmpty) {
        routePoints = pts.map((p) => LatLng(p['lat']!, p['lng']!)).toList();
      }
    }

    double progress =
        (toDoubleOrNull(repair['progress']) ?? 0.0).clamp(0.0, 1.0);

    if (!mounted) return;
    setState(() {
      _technician = tech;
      _arrivalProgress = progress;
      _minutesRemaining = etaMinutes;
      _distanceKm = distKm;
      _techPosition = LatLng(startLat!, startLng!);
      _destPosition = LatLng(destLat, destLng);
      _routePoints = routePoints;
      _errorMessage = null;
      _loading = false;
    });

    // 🔴 เริ่มฟังตำแหน่งช่างแบบเรียลไทม์ต่อจากนี้ (ครั้งแรกให้ถือว่าพิกัดเริ่มต้นด้านบน
    // คือจุดที่ "ขอเส้นทางไปแล้ว" กันยิง Geoapify ซ้ำทันทีที่ Stream ยิงค่าปัจจุบันกลับมา)
    _lastRoutedTechPosition = LatLng(startLat, startLng);
    _subscribeToTechnicianLocation(techUsername);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  const AppHeader(title: 'ติดตามสถานะช่าง', showBack: true),

                  // 🗺️ แผนที่แบบโต้ตอบได้ (ซูมได้ + เส้นทางจริงบนถนน)
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      color: AppColors.border,
                      child: (_destPosition != null)
                          ? RouteMapView(
                              startPoint: _techPosition,
                              endPoint: _destPosition,
                              routePoints: _routePoints,
                            )
                          : Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  _errorMessage ?? 'ไม่มีข้อมูลตำแหน่ง',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Colors.black87,
                                    fontFamily: AppStyles.fontFamily,
                                    height: 1.5,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                    ),
                  ),

                  // 👤 แสดงการ์ดข้อมูลช่างและ Progress
                  if (_technician != null) ...[
                    _TechnicianInfoCard(technician: _technician!),
                    _ArrivalProgressCard(
                      progress: _arrivalProgress,
                      minutesRemaining: _minutesRemaining,
                      distanceKm: _distanceKm,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _TechnicianInfoCard extends StatelessWidget {
  final Technician technician;
  const _TechnicianInfoCard({required this.technician});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      color: Colors.white,
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.border,
            backgroundImage: localOrNetworkImageProvider(technician.photoUrl),
            child: technician.photoUrl == null
                ? const Icon(Icons.person, size: 30, color: Colors.grey)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  technician.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
                Text(
                  (technician.vehicle.isNotEmpty && technician.vehicle != '-')
                      ? '${technician.role} • ${technician.vehicle}'
                      : technician.role,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black54,
                    fontFamily: AppStyles.fontFamily,
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

class _ArrivalProgressCard extends StatelessWidget {
  final double progress;
  final int minutesRemaining;
  final double distanceKm;

  const _ArrivalProgressCard({
    required this.progress,
    required this.minutesRemaining,
    required this.distanceKm,
  });

  @override
  Widget build(BuildContext context) {
    final arrived = progress >= 1.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                arrived ? 'ช่างถึงจุดหมายแล้ว!' : 'ช่างกำลังเดินทางมา',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
              if (!arrived)
                Text(
                  'ระยะทาง $distanceKm กม.',
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            arrived
                ? 'ช่างเดินทางถึงสถานที่เรียบร้อยแล้ว'
                : 'คาดว่าจะถึงในอีก $minutesRemaining นาที',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: AppColors.border,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}