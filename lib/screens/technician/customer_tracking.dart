//หมายเหตุ ตัวอย่างการติดตามตำแหน่งลูกค้า (Customer Tracking) สำหรับช่าง
// เงื่อนไข "ถึงวันนัด" และ "ถึงคิวงาน" ถูก comment ไว้ก่อนเพื่อทดสอบ UI
// เมื่อพร้อมใช้งานจริงให้ปลดคอมเมนต์ตามจุดที่ระบุไว้
//
// หมายเหตุ: หน้านี้ผสาน UI ส่วนที่ไม่ใช่แผนที่จาก MapApp (map_app.dart) เข้ามา
// ได้แก่ การ์ดล่างแบบมุมโค้ง, ปุ่มติดต่อ/ส่งข้อความ (_buildActionMenu)
// และปุ่ม "แสดงบัตร" (นำไปสู่ IdentityCardPage) แต่ยังคงใช้ข้อมูลจริง
// (SQLite + Geoapify) ของ CustomerTrackingPage เดิมทั้งหมด ไม่ได้ mock ข้อมูล
import 'dart:async' show unawaited;
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/geoapify_service.dart';
import 'package:after_sales/location_service.dart';
import 'package:after_sales/screens/shared/route_map_view.dart';
import 'package:after_sales/screens/technician/tac_id_card.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

/// ข้อมูลลูกค้าที่จะแสดงในการ์ดด้านล่างแผนที่
class CustomerInfo {
  final String name;
  final String phone;
  final String address;
  final String machine;
  final String? photoUrl;

  const CustomerInfo({
    required this.name,
    required this.phone,
    required this.address,
    required this.machine,
    this.photoUrl,
  });

  factory CustomerInfo.fromMap(
    Map<String, dynamic> customerRow, {
    required String address,
    required String machine,
  }) {
    final name = (customerRow['name']?.toString()) ?? '';
    final surname = (customerRow['surname']?.toString()) ?? '';
    final fullName = '$name $surname'.trim();
    return CustomerInfo(
      name: fullName.isNotEmpty ? fullName : '-',
      phone: (customerRow['phone']?.toString()) ?? '-',
      address: address.isNotEmpty ? address : '-',
      machine: machine.isNotEmpty ? machine : '-',
      photoUrl: customerRow['photo_url']?.toString(),
    );
  }
}

class CustomerTrackingPage extends StatefulWidget {
  final int repairId;
  const CustomerTrackingPage({super.key, required this.repairId});

  @override
  State<CustomerTrackingPage> createState() => _CustomerTrackingPageState();
}

class _CustomerTrackingPageState extends State<CustomerTrackingPage> {
  bool _loading = true;
  String? _errorMessage;

  CustomerInfo? _customer;
  double _distanceKm = 0.0;
  int _minutesRemaining = 0;
  LatLng? _techPosition;
  LatLng? _customerPosition;
  List<LatLng> _routePoints = [];
  String? _gpsWarning;

  @override
  void initState() {
    super.initState();
    _loadCustomerLocation();
  }

  /// 🗓️ เช็คว่าถึงวันนัดซ่อมแล้วหรือยัง (วันนี้ หรือเลยมาแล้ว)
  /// 🛠️ [แก้บั๊ก] เดิมฟังก์ชันนี้แกะรูปแบบ "31 กรกฎาคม 2569" (ชื่อเดือนเต็ม เว้น
  /// วรรคคั่น) แต่ repair['date'] ที่เก็บจริงในฐานข้อมูลเป็นรูปแบบตัวเลขคั่น "/"
  /// เช่น "1/9/2569" (แบบเดียวกับที่ใช้ทั่วทั้งแอป — ดู _parseThaiDate ใน
  /// repair_list_admin.dart / home_admin.dart) ทำให้ split(' ') ได้ length แค่ 1
  /// เงื่อนไข parts.length < 3 เป็นจริงเสมอ ฟังก์ชันเลย return false ตลอด ไม่ว่า
  /// จะถึงวันนัดจริงหรือยัง ช่างเลยเห็นข้อความ "ยังไม่ถึงวันนัด" ทั้งที่นัดวันนี้
  /// พอดี ตอนนี้แก้ให้แกะรูปแบบตัวเลขคั่น / ให้ตรงกับของจริงแล้ว
  
  Future<void> _loadCustomerLocation() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    // 🛡️ [แก้ไข] เดิมฟังก์ชันนี้ไม่มี try/catch เลย — ถ้าขั้นตอนไหนโยน exception
    // ขึ้นมา (query DB พลาด, updateTechnicianLocation error ฯลฯ) โค้ดจะหยุดทำงาน
    // กลางคันแบบไม่มีใครจับ ทำให้ไม่มีการ setState(loading=false) เกิดขึ้นอีกเลย
    // หน้าจึงค้างที่ "กำลังโหลด" ตลอดไปโดยไม่มี error โผล่ให้เห็น (เหมือนบั๊กเดียวกับ
    // ที่เจอในหน้า AdminTrackingPage)
    try {
      // 1. อ่านข้อมูลใบแจ้งซ่อมจาก SQLite
      final repair =
          await db.DatabaseHelper.instance.getRepairById(widget.repairId);
      if (repair == null) {
        if (!mounted) return;
        setState(() {
          _errorMessage = 'ไม่พบข้อมูลการแจ้งซ่อมในระบบ';
          _loading = false;
        });
        return;
      }
      await _loadFromRepair(repair);
    } catch (e, st) {
      debugPrint('CustomerTrackingPage._loadCustomerLocation error: $e\n$st');
      if (!mounted) return;
      setState(() {
        _errorMessage = 'เกิดข้อผิดพลาดในการโหลดข้อมูลตำแหน่ง: $e';
        _loading = false;
      });
    }
  }

  Future<void> _loadFromRepair(Map<String, dynamic> repair) async {
    // ✅ [แก้ไข] เดิมเงื่อนไข "ถึงวันนัด" และ "ถึงคิวงาน" ถูก comment ไว้เพื่อทดสอบ UI
    // ทำให้ช่างเห็นตำแหน่งลูกค้าได้ตลอดเวลา ทั้งที่แอดมินสั่งนัดซ่อมไว้เป็นวันอื่น
    // ปลดคอมเมนต์และเปิดใช้งานจริงแล้ว

    // เงื่อนไขที่ 1: ต้องถึงวันนัดซ่อมก่อนเท่านั้น ช่างถึงจะเห็นตำแหน่งลูกค้า
    final appointmentDate = repair['date']?.toString();
    if (!db.isAppointmentTodayOrPast(appointmentDate)) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'จะเห็นตำแหน่งลูกค้าได้ในวันนัดซ่อมเท่านั้น\n(วันนัดซ่อม: $appointmentDate)';
        _loading = false;
      });
      return;
    }

    // เงื่อนไขที่ 2: ต้องถึงคิวงานนี้แล้วเท่านั้น (ใช้ระบบคิวจริงตาม approved_at
    // แทนการเช็คแค่ status — ถ้าช่างมีงานนัดวันเดียวกันหลายงาน จะเห็นตำแหน่งลูกค้า
    // ได้เฉพาะงานที่ถูกอนุมัติ/มอบหมายก่อนที่สุด (คิวที่ 1) ก่อนเท่านั้น)
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
      // หรือยัง) เงื่อนไขนี้เลยเป็นจริงตลอดเวลาโดยไม่ได้ตั้งใจ ทำให้ช่างดู
      // ตำแหน่งลูกค้าของ "ทุกงาน" ในวันเดียวกันได้พร้อมกันหมด ทั้งที่ควรดูได้
      // ทีละงานตามคิวเท่านั้น — ตัดเงื่อนไขนี้ทิ้ง ให้ยึด isMyTurn (คิวที่ 1
      // เท่านั้น) เป็นเกณฑ์เดียวแทน (ฝั่ง services.dart ก็แก้ไม่ให้บังคับสถานะ
      // แบบนั้นแล้วเช่นกัน)
      if (!isMyTurn) {
        if (!mounted) return;
        setState(() {
          _errorMessage =
              'ยังไม่ถึงคิวงานนี้\nขณะนี้อยู่คิวที่ ${queueInfo.position} จาก ${queueInfo.total} งานของวันนี้\n(ระบบจะแสดงตำแหน่งลูกค้าเมื่อถึงคิวงาน)';
          _loading = false;
        });
        return;
      }
      // 🆕 [ใหม่] ผ่านทั้งเงื่อนไขวันนัดและคิวงานแล้ว = ช่างกำลังจะออกเดินทางไป
      // หาลูกค้าจริง ๆ — ตั้งสถานะ "กำลังเดินทาง" ให้ลูกค้าเห็นด้วย
      await db.DatabaseHelper.instance.markTechnicianTraveling(repairId);
    }

    // 2. ดึงข้อมูลลูกค้าเจ้าของงาน
    final customerUsername = repair['customer_username']?.toString();
    if (customerUsername == null || customerUsername.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ไม่พบข้อมูลลูกค้าของงานนี้';
        _loading = false;
      });
      return;
    }

    final customerRow =
        await db.DatabaseHelper.instance.getCustomerProfile(customerUsername);
    if (customerRow == null) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'ไม่พบข้อมูลลูกค้าในระบบ';
        _loading = false;
      });
      return;
    }

    final customer = CustomerInfo.fromMap(
      customerRow,
      address: (repair['location']?.toString()) ?? '',
      machine: (repair['machine']?.toString()) ?? '',
    );

    // 3. ดึงพิกัดหมุดลูกค้า (dest_lat/dest_lng) ที่บันทึกไว้ตอนแจ้งซ่อม
    double? destLat = toDoubleOrNull(repair['dest_lat']);
    double? destLng = toDoubleOrNull(repair['dest_lng']);

    // ถ้าไม่มีพิกัดที่บันทึกไว้ ให้ลอง Geocode จากข้อความที่อยู่แทน
    if ((destLat == null || destLng == null) &&
        (repair['location']?.toString())?.isNotEmpty == true) {
      final geocoded = await GeoapifyService.geocodeAddress(repair['location']);
      if (geocoded != null) {
        destLat = geocoded['lat'];
        destLng = geocoded['lng'];
      }
    }

    if (destLat == null || destLng == null) {
      if (!mounted) return;
      setState(() {
        _customer = customer;
        _errorMessage = 'ไม่สามารถระบุพิกัดที่อยู่ลูกค้าได้';
        _loading = false;
      });
      return;
    }

    // 4. ดึงพิกัดปัจจุบันของช่างที่ล็อกอินอยู่ เพื่อคำนวณระยะทาง/เวลาไปหาลูกค้า
    // 🔴 [แก้ไข] ใช้ตำแหน่ง GPS จริงของเครื่องช่างก่อนเสมอ (แทนค่าตายตัวใน DB)
    // ถ้าดึง GPS จริงไม่ได้ (ปิด GPS/ไม่ได้รับสิทธิ์) ค่อย fallback ไปใช้ค่าที่เคยบันทึกไว้ล่าสุด
    final techUsername = db.Session.currentUsername;
    double? startLat;
    double? startLng;
    String? gpsWarning;

    final gpsResult = await LocationService.getCurrentLocation();
    if (gpsResult.isSuccess) {
      startLat = gpsResult.lat;
      startLng = gpsResult.lng;
      // อัปเดตตำแหน่งล่าสุดของช่างลง DB ด้วย เผื่อหน้าอื่น (เช่นฝั่งลูกค้าดูตำแหน่งช่าง)
      // จะได้เห็นตำแหน่งล่าสุดเช่นกัน
      await db.DatabaseHelper.instance
          .updateTechnicianLocation(techUsername, startLat!, startLng!);
    } else {
      gpsWarning = gpsResult.errorMessage;
      final techRow = await db.DatabaseHelper.instance
          .getTechnicianByUsername(techUsername);
      startLat = toDoubleOrNull(techRow?['current_lat']);
      startLng = toDoubleOrNull(techRow?['current_lng']);
    }

    double distKm = 0.0;
    int etaMinutes = 0;
    List<LatLng> routePoints = [];

    if (startLat != null && startLng != null) {
      final routeInfo = await GeoapifyService.getRouteInfo(
        startLat: startLat,
        startLng: startLng,
        destLat: destLat,
        destLng: destLng,
      );
      if (routeInfo != null) {
        distKm = routeInfo['distance_km'];
        etaMinutes = routeInfo['time_minutes'];
        final pts = routeInfo['route_points'] as List<Map<String, double>>?;
        if (pts != null && pts.isNotEmpty) {
          routePoints = pts.map((p) => LatLng(p['lat']!, p['lng']!)).toList();
        }
      }
    }

    // 🆕 [ใหม่] เช็คระยะห่างแบบเส้นตรงจริง (ไม่ใช่ระยะทางถนนจาก Routing API
    // ด้านบน) ถ้าช่างเข้าใกล้หมุดลูกค้าในรัศมี 1 กม. ให้แจ้งเตือนลูกค้าว่า
    // "ช่างใกล้ถึงแล้ว" (ส่งแค่ครั้งเดียวต่องาน — ดู notifyIfTechnicianNearby)
    if (startLat != null && startLng != null && repairId != null) {
      final ticketLabel =
          (repair['ticketNo']?.toString())?.trim().isNotEmpty == true
              ? repair['ticketNo'].toString()
              : '#$repairId';
      unawaited(db.DatabaseHelper.instance.notifyIfTechnicianNearby(
        repairId: repairId,
        techLat: startLat,
        techLng: startLng,
        destLat: destLat,
        destLng: destLng,
        customerUsername: customerUsername,
        ticketLabel: ticketLabel,
      ));
    }

    if (!mounted) return;
    setState(() {
      _customer = customer;
      _distanceKm = distKm;
      _minutesRemaining = etaMinutes;
      _techPosition = (startLat != null && startLng != null)
          ? LatLng(startLat, startLng)
          : null;
      _customerPosition = LatLng(destLat!, destLng!);
      _routePoints = routePoints;
      // แจ้งเตือนเรื่อง GPS แบบไม่บล็อกหน้าจอ (แผนที่ยังแสดงได้จากตำแหน่งล่าสุดที่มี)
      _gpsWarning = gpsWarning;
      _errorMessage = null;
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
            // 🔒 หัวเรื่องล็อกอยู่นิ่ง แสดงตลอดแม้กำลังโหลดข้อมูล
            const AppHeader(title: 'ตำแหน่งลูกค้า', showBack: true),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        // ⚠️ แจ้งเตือนถ้าดึงตำแหน่ง GPS จริงของช่างไม่ได้ (ใช้ตำแหน่งล่าสุดที่บันทึกไว้แทน)
                        if (_gpsWarning != null)
                          Container(
                            width: double.infinity,
                            color: Colors.amber.shade50,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.amber.shade800, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$_gpsWarning (แสดงตำแหน่งล่าสุดที่บันทึกไว้แทน)',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontFamily: AppStyles.fontFamily,
                                      color: Colors.black87,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // 🗺️ แผนที่แบบโต้ตอบได้ (ซูมได้ + เส้นทางจริงบนถนน)
                        Expanded(
                          child: Container(
                            width: double.infinity,
                            color: AppColors.border,
                            child: (_customerPosition != null)
                                ? RouteMapView(
                                    startPoint: _techPosition,
                                    endPoint: _customerPosition,
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

                        // 👤 การ์ดข้อมูลลูกค้าด้านล่าง (ปรับจากส่วนที่ไม่ใช่แผนที่ของ MapApp)
                        if (_customer != null)
                          _CustomerBottomPanel(
                            customer: _customer!,
                            distanceKm: _distanceKm,
                            minutesRemaining: _minutesRemaining,
                            hasError: _errorMessage != null,
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

/// การ์ดข้อมูลลูกค้าด้านล่างแผนที่ — รวมสไตล์มุมโค้ง/เงา + ปุ่มติดต่อ/ส่งข้อความ
/// + ปุ่ม "แสดงบัตร" ที่ยกมาจาก MapApp (map_app.dart) แต่ผูกกับข้อมูลจริงของ
/// CustomerTrackingPage (ชื่อ, เครื่องจักร, ที่อยู่, ระยะทาง/เวลา จาก Geoapify)
class _CustomerBottomPanel extends StatelessWidget {
  final CustomerInfo customer;
  final double distanceKm;
  final int minutesRemaining;
  final bool hasError;

  const _CustomerBottomPanel({
    required this.customer,
    required this.distanceKm,
    required this.minutesRemaining,
    required this.hasError,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // แถวบน: รูป + ชื่อ + เครื่องจักร (จาก CustomerInfoCard เดิม)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.border,
                backgroundImage: localOrNetworkImageProvider(customer.photoUrl),
                child: customer.photoUrl == null
                    ? const Icon(Icons.person, size: 30, color: Colors.grey)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      customer.machine,
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

          const SizedBox(height: 16),

          // หัวข้อ "ที่อยู่ลูกค้า" (สไตล์จาก MapApp)
          const Text(
            'ที่อยู่ลูกค้า',
            style: TextStyle(
              color: AppColors.primary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            customer.address,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
              height: 1.5,
              fontFamily: AppStyles.fontFamily,
            ),
          ),

          // ระยะทาง/เวลาถึงลูกค้า (จาก DistanceCard เดิม ใช้ข้อมูลจริงจาก Geoapify)
          if (!hasError) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.alt_route, color: AppColors.primary, size: 20),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    distanceKm > 0
                        ? 'ระยะทางถึงลูกค้า $distanceKm กม. • คาดว่าใช้เวลา $minutesRemaining นาที'
                        : 'ปักหมุดตำแหน่งลูกค้าไว้แล้ว',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 24),

          // ปุ่มติดต่อ / ส่งข้อความ (ยกมาจาก MapApp: _buildActionMenu)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionMenu(context, Icons.phone, 'ติดต่อสอบถาม', () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('โทร: ${customer.phone}')),
                );
              }),
              _buildActionMenu(
                context,
                Icons.chat_bubble_outline,
                'ส่งข้อความ',
                () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ส่งข้อความถึง: ${customer.phone}')),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ปุ่มแสดงบัตร (ยกมาจาก MapApp) — ช่างกดเพื่อแสดงบัตรประจำตัวให้ลูกค้าดู
          Container(
            width: double.infinity,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.primary],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  // ignore: deprecated_member_use
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(2, 2),
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const IdentityCardPage(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'แสดงบัตร',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Widget ช่วยสร้างปุ่มเมนูเล็กๆ (ติดต่อ, ส่งข้อความ) — ยกมาจาก MapApp
  Widget _buildActionMenu(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.black87, size: 20),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
        ],
      ),
    );
  }
}