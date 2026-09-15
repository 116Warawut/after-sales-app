import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/geoapify_service.dart';

/// ==========================================
/// 🗺️ แผนที่แบบโต้ตอบได้ (ซูม/ลาก/ปัด) ที่ใช้ร่วมกันทั้งระบบ
/// ==========================================
/// ใช้แทนของเดิมที่เป็นรูปภาพ Static Map — หน้านี้ทำให้:
/// - ซูมเข้า/ออกได้จริง (pinch + ปุ่ม +/-)
/// - แสดงเส้นทางจริงบนถนน (จาก Geoapify Routing API geometry ไม่ใช่เส้นตรง)
/// - ปักหมุดต้นทาง (ช่าง, สีฟ้า) และปลายทาง (ลูกค้า, สีแดง) พร้อมกัน
class RouteMapView extends StatefulWidget {
  /// ตำแหน่งต้นทาง (เช่น ตำแหน่งช่าง) — ไอคอนรถสีฟ้า
  final LatLng? startPoint;

  /// ตำแหน่งปลายทาง (เช่น ตำแหน่งลูกค้า) — หมุดสีแดง
  final LatLng? endPoint;

  /// จุดเส้นทางจริงบนถนน (จาก GeoapifyService.getRouteInfo -> route_points)
  /// ถ้าว่าง จะวาดเส้นตรงระหว่าง startPoint/endPoint แทนชั่วคราว
  final List<LatLng> routePoints;

  const RouteMapView({
    super.key,
    required this.startPoint,
    required this.endPoint,
    this.routePoints = const [],
  });

  @override
  State<RouteMapView> createState() => _RouteMapViewState();
}

class _RouteMapViewState extends State<RouteMapView> {
  final MapController _mapController = MapController();

  static const LatLng _fallbackCenter = LatLng(13.7563, 100.5018);

  List<LatLng> get _lineToDraw {
    if (widget.routePoints.length >= 2) return widget.routePoints;
    if (widget.startPoint != null && widget.endPoint != null) {
      return [widget.startPoint!, widget.endPoint!];
    }
    return const [];
  }

  CameraFit? get _initialFit {
    final points = <LatLng>[
      if (widget.startPoint != null) widget.startPoint!,
      if (widget.endPoint != null) widget.endPoint!,
      ...widget.routePoints,
    ];
    if (points.length < 2) return null;
    return CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(48, 80, 48, 48),
    );
  }

  LatLng get _initialCenter =>
      widget.endPoint ?? widget.startPoint ?? _fallbackCenter;

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, (camera.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _initialCenter,
            initialZoom: 14,
            initialCameraFit: _initialFit,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=${GeoapifyService.apiKey}',
              userAgentPackageName: 'com.aftersales.app',
              maxZoom: 20,
            ),
            if (_lineToDraw.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _lineToDraw,
                    strokeWidth: 5,
                    color: AppColors.primary,
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (widget.startPoint != null)
                  Marker(
                    point: widget.startPoint!,
                    width: 42,
                    height: 42,
                    child: const _MapPinIcon(
                      icon: Icons.two_wheeler,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                if (widget.endPoint != null)
                  Marker(
                    point: widget.endPoint!,
                    width: 42,
                    height: 42,
                    child: const _MapPinIcon(
                      icon: Icons.location_pin,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ],
        ),

        // 🔎 ปุ่มซูมเข้า/ออก (นอกเหนือจาก pinch-to-zoom ที่ทำได้อยู่แล้วโดยปริยาย)
        Positioned(
          right: 12,
          bottom: 16,
          child: Column(
            children: [
              _ZoomButton(icon: Icons.add, onTap: () => _zoomBy(1)),
              const SizedBox(height: 8),
              _ZoomButton(icon: Icons.remove, onTap: () => _zoomBy(-1)),
            ],
          ),
        ),

        // © ต้องแปะเครดิต Geoapify/OpenStreetMap ตามเงื่อนไขการใช้งาน
        const Positioned(
          left: 6,
          bottom: 4,
          child: _MapAttribution(),
        ),
      ],
    );
  }
}

class _MapPinIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPinIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _ZoomButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: AppColors.textMain, size: 20),
        ),
      ),
    );
  }
}

class _MapAttribution extends StatelessWidget {
  const _MapAttribution();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: Colors.white.withValues(alpha: 0.7),
      child: const Text(
        'Powered by Geoapify | © OpenStreetMap contributors',
        style: TextStyle(fontSize: 8, color: Colors.black87),
      ),
    );
  }
}
