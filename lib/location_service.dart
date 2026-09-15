import 'package:geolocator/geolocator.dart';

/// ผลลัพธ์การดึงตำแหน่ง GPS จริงของเครื่อง
/// - สำเร็จ: [lat]/[lng] จะมีค่า, [errorMessage] เป็น null
/// - ล้มเหลว: [lat]/[lng] เป็น null, [errorMessage] จะบอกสาเหตุที่แท้จริง
/// (GPS ปิดอยู่ / ไม่ได้รับสิทธิ์ / สิทธิ์ถูกปฏิเสธถาวร ฯลฯ)
class LocationResult {
  final double? lat;
  final double? lng;
  final String? errorMessage;
  const LocationResult({this.lat, this.lng, this.errorMessage});
  bool get isSuccess => lat != null && lng != null;
}

class LocationService {
  /// ขอสิทธิ์เข้าถึงตำแหน่ง (ถ้ายังไม่เคยขอ) แล้วดึงพิกัด GPS ปัจจุบันของเครื่อง
  /// ใช้แทนตำแหน่ง mock ที่ seed ไว้ตายตัวในฐานข้อมูล (technicians.current_lat/current_lng)
  static Future<LocationResult> getCurrentLocation() async {
    try {
      // 1. เช็คว่าเปิด GPS/Location Service ของอุปกรณ์อยู่หรือไม่
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const LocationResult(
          errorMessage: 'กรุณาเปิดสัญญาณ GPS/ตำแหน่งบนอุปกรณ์ก่อนใช้งาน',
        );
      }

      // 2. เช็คสิทธิ์การเข้าถึงตำแหน่ง — ถ้ายังไม่เคยขอ ให้ขอตอนนี้เลย
      // ⏱️ [แก้ไข] เพิ่ม timeout ให้ checkPermission/requestPermission — ถ้า popup
      // ขอสิทธิ์ไม่ขึ้นมาเลย (เช่น emulator ตั้งค่า permission ใน AndroidManifest.xml
      // ไม่ครบ) เดิม await ตรงนี้จะค้างรอ user ตอบ popup ที่ไม่มีวันโผล่ ทำให้หน้าที่
      // เรียกใช้ (เช่น CustomerTrackingPage ฝั่งช่าง) ติดสถานะ "กำลังโหลด" ตลอดไป
      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 15));
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 30));
        if (permission == LocationPermission.denied) {
          return const LocationResult(
            errorMessage: 'แอปไม่ได้รับอนุญาตให้เข้าถึงตำแหน่ง GPS',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const LocationResult(
          errorMessage:
              'สิทธิ์การเข้าถึงตำแหน่งถูกปฏิเสธถาวร กรุณาไปเปิดสิทธิ์ในการตั้งค่าแอปด้วยตนเอง',
        );
      }

      // 3. ดึงพิกัดปัจจุบัน
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));

      return LocationResult(lat: position.latitude, lng: position.longitude);
    } catch (e) {
      return LocationResult(
        errorMessage: 'ไม่สามารถดึงตำแหน่ง GPS ได้ ($e)',
      );
    }
  }
}
