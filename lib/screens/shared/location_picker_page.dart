import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/geoapify_service.dart';
import 'package:after_sales/location_service.dart';

/// ==========================================
/// 📍 หน้าปักหมุดตำแหน่งด้วยตัวเอง (ใช้ร่วมกันทั้งระบบ)
/// ==========================================
/// ให้ผู้ใช้เลื่อนแผนที่เพื่อขยับหมุด (ตรึงกลางจอ) ไปยังตำแหน่งที่ต้องการ
/// แล้วกดยืนยัน — วิธีนี้ไม่ต้องพึ่งผลลัพธ์จากการ Geocode ข้อความที่อยู่
/// (ซึ่งอาจหาพิกัดไม่เจอหรือคลาดเคลื่อนได้) เพราะผู้ใช้เป็นคนยืนยันตำแหน่งจริงเอง
class LocationPickerPage extends StatefulWidget {
  /// พิกัดเริ่มต้น (เช่น จากการ Geocode ที่อยู่ที่กรอกไว้ในฟอร์ม)
  /// ถ้าไม่ระบุ จะใช้จุดกึ่งกลางกรุงเทพฯ เป็นค่าเริ่มต้น
  final double? initialLat;
  final double? initialLng;
  final String title;

  const LocationPickerPage({
    super.key,
    this.initialLat,
    this.initialLng,
    this.title = 'ปักหมุดตำแหน่งของคุณ',
  });

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  // 🏙️ ค่าเริ่มต้นถ้าไม่มีพิกัดใดๆ เลย: กึ่งกลางกรุงเทพมหานคร
  static const LatLng _fallbackCenter = LatLng(13.7563, 100.5018);

  final MapController _mapController = MapController();
  late LatLng _center;
  bool _hadInitialCoordinate = false;
  bool _locatingMe = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _center = LatLng(widget.initialLat!, widget.initialLng!);
      _hadInitialCoordinate = true;
    } else {
      _center = _fallbackCenter;
    }
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
  }

  // 📡 ใช้ตำแหน่ง GPS จริงของเครื่องเป็นจุดปักหมุด — แม่นกว่าการเดาจากข้อความที่อยู่
  // เสมอ (ไม่ต้องพึ่งข้อมูลแผนที่ที่อาจไม่ครอบคลุมบางตำบล/พื้นที่เล็ก ๆ) เหมาะเวลา
  // ลูกค้ากรอกฟอร์มขณะอยู่ที่หน้างานจริงพอดี
  Future<void> _useCurrentLocation() async {
    setState(() => _locatingMe = true);
    final result = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() => _locatingMe = false);

    if (!result.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.errorMessage ?? 'ไม่สามารถดึงตำแหน่งปัจจุบันได้',
            style: const TextStyle(fontFamily: AppStyles.fontFamily),
          ),
        ),
      );
      return;
    }

    final newCenter = LatLng(result.lat!, result.lng!);
    setState(() {
      _center = newCenter;
      _hadInitialCoordinate = true;
    });
    _mapController.move(newCenter, 17);
  }

  void _confirm() {
    Navigator.of(context).pop({
      'lat': _center.latitude,
      'lng': _center.longitude,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: AppStyles.fontFamily,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: _hadInitialCoordinate ? 16 : 12,
              onPositionChanged: _onPositionChanged,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=${GeoapifyService.apiKey}',
                userAgentPackageName: 'com.aftersales.app',
                maxZoom: 20,
              ),
            ],
          ),

          // 📍 หมุดตรึงอยู่กลางจอเสมอ (ผู้ใช้เลื่อนแผนที่แทนการลากหมุด)
          IgnorePointer(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 42),
                child: Icon(
                  Icons.location_pin,
                  size: 48,
                  color: AppColors.primary,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 📡 ปุ่มลอย "ใช้ตำแหน่งปัจจุบันของฉัน" มุมขวาบน (เว้นที่ให้แถบเตือนด้านบน
          // ถ้ามี ไม่ให้ซ้อนทับกัน)
          Positioned(
            right: 16,
            top: 70,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: InkWell(
                onTap: _locatingMe ? null : _useCurrentLocation,
                customBorder: const CircleBorder(),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: _locatingMe
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        )
                      : const Icon(
                          Icons.my_location,
                          color: AppColors.primary,
                          size: 22,
                        ),
                ),
              ),
            ),
          ),

          if (!_hadInitialCoordinate)
            Positioned(
              left: 16,
              right: 16,
              top: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: const Text(
                  'ไม่พบพิกัดจากที่อยู่ที่กรอกไว้ กรุณาเลื่อนแผนที่ไปยังตำแหน่งของคุณเอง',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: AppStyles.fontFamily,
                    color: Colors.black87,
                  ),
                ),
              ),
            ),

          // ปุ่มยืนยันด้านล่าง
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Text(
                    'เลื่อนแผนที่เพื่อขยับหมุดไปยังตำแหน่งที่ต้องการให้ช่างมาซ่อม',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: AppStyles.fontFamily,
                      color: Colors.black87,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text(
                      'ยืนยันตำแหน่งนี้',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        fontFamily: AppStyles.fontFamily,
                      ),
                    ),
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
