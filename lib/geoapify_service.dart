import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// ผลลัพธ์การโหลดรูปแผนที่ Static Map จาก Geoapify
/// - ถ้าโหลดสำเร็จ: [bytes] จะมีข้อมูลรูปภาพ, [errorMessage] เป็น null
/// - ถ้าล้มเหลว: [bytes] เป็น null, [errorMessage] จะบอกสาเหตุที่แท้จริง (ไม่ใช่ข้อความทั่วไป)
class GeoapifyMapResult {
  final Uint8List? bytes;
  final String? errorMessage;
  const GeoapifyMapResult({this.bytes, this.errorMessage});
  bool get isSuccess => bytes != null;
}

class GeoapifyService {
  // 🔑 Geoapify API Key ของโปรเจกต์นี้
  static const String apiKey = 'a59572fd4e7b414b9a477031873bb341';

  // ใช้ตรวจสอบว่ายังไม่ได้ตั้งค่า API Key จริง (ค่าว่างหรือยังเป็นข้อความ placeholder)
  static bool get _isKeyMissing =>
      apiKey.isEmpty || apiKey == 'YOUR_GEOAPIFY_API_KEY';

  /// 1. Geocoding API: แปลงข้อความที่อยู่เป็นพิกัด (Lat, Lng)
  static Future<Map<String, double>?> geocodeAddress(String address) async {
    if (_isKeyMissing || address.trim().isEmpty) {
      return null;
    }

    // 🔴 [แก้ไข] เพิ่ม filter=countrycode:th และ lang=th — เดิมค้นหาแบบ
    // free-text ล้วน ๆ ไม่มีการจำกัดประเทศเลย พอที่อยู่เป็นภาษาไทยแบบย่อ
    // (ต./อ./จ.) เจอปัญหาว่าชื่อตำบล/อำเภอไทยหลายชื่อซ้ำกันได้ในคนละจังหวัด
    // (เช่น "บ้านนา" มีทั้งในนครนายก, ปราจีนบุรี ฯลฯ) หรือบางครั้ง Geoapify
    // จับคู่ไปเจอสถานที่ชื่อคล้ายกันในต่างประเทศแทน ทำให้ปักหมุดผิดที่แบบ
    // ที่เจอ — การจำกัด countrycode:th บังคับให้ผลลัพธ์ต้องอยู่ในไทยเท่านั้น
    final url = Uri.parse(
      'https://api.geoapify.com/v1/geocode/search'
      '?text=${Uri.encodeComponent(address)}'
      '&filter=countrycode:th'
      '&lang=th'
      '&limit=1&apiKey=$apiKey',
    );

    return _requestGeocode(url);
  }

  /// 1.1 Structured Geocoding: ส่งที่อยู่แยกเป็นฟิลด์ (ตำบล/อำเภอ/จังหวัด/รหัสไปรษณีย์)
  /// แทนการยัดรวมเป็นข้อความก้อนเดียว — แม่นกว่าการค้นหาแบบ text ธรรมดา เพราะ
  /// Geoapify รู้ตั้งแต่แรกว่าแต่ละคำคือ "ระดับการปกครอง" ไหน ไม่ต้องเดาเอาจากประโยค
  ///
  /// ⚠️ ข้อจำกัดที่ควรรู้: ถ้าตำบลนั้นไม่มีข้อมูลอยู่ใน OpenStreetMap เลย (Geoapify
  /// ใช้ฐานข้อมูล OSM เป็นหลัก) ต่อให้ค้นหาแบบไหนก็ตาม ผลลัพธ์อาจยังคลาดเคลื่อนได้
  /// เพราะไม่มีข้อมูลระดับนั้นให้จับคู่จริง ๆ — ตำบลเล็ก ๆ/ชานเมืองหลายแห่งในไทย
  /// ยังไม่มีข้อมูลแม่นในระบบแผนที่สาธารณะ กรณีแบบนี้การปักหมุดเองบนแผนที่
  /// (ที่มีอยู่แล้วในหน้าแจ้งซ่อม) จะแม่นกว่าการเดาจากที่อยู่เสมอ
  static Future<Map<String, double>?> geocodeStructuredAddress({
    String? houseNo,
    String? tambon,
    String? amphoe,
    String? changwat,
    String? postcode,
  }) async {
    if (_isKeyMissing) return null;

    final params = <String, String>{
      'apiKey': apiKey,
      'filter': 'countrycode:th',
      'lang': 'th',
      'limit': '1',
      'country': 'Thailand',
    };
    if (houseNo != null && houseNo.trim().isNotEmpty) {
      params['housenumber'] = houseNo.trim();
    }
    if (tambon != null && tambon.trim().isNotEmpty) {
      params['city'] = tambon.trim();
    }
    if (amphoe != null && amphoe.trim().isNotEmpty) {
      params['county'] = amphoe.trim();
    }
    if (changwat != null && changwat.trim().isNotEmpty) {
      params['state'] = changwat.trim();
    }
    if (postcode != null && postcode.trim().isNotEmpty) {
      params['postcode'] = postcode.trim();
    }

    // ต้องมีอย่างน้อยตำบล/อำเภอ/จังหวัดสักอันหนึ่ง ไม่งั้นค้นหาไปก็ไม่มีความหมาย
    if (!params.containsKey('city') &&
        !params.containsKey('county') &&
        !params.containsKey('state')) {
      return null;
    }

    final url = Uri.https(
      'api.geoapify.com',
      '/v1/geocode/search',
      params,
    );

    return _requestGeocode(url);
  }

  /// ยิงคำขอ geocoding ตาม URL ที่เตรียมไว้ (ใช้ร่วมกันทั้งแบบ text และ structured)
  static Future<Map<String, double>?> _requestGeocode(Uri url) async {
    try {
      // ⏱️ [แก้ไข] เดิมไม่มี timeout — ถ้าเน็ตเวิร์กค้าง (ไม่ error แต่ก็ไม่ตอบ)
      // await ตรงนี้จะค้างไปตลอด ทำให้หน้าที่เรียกใช้ (เช่น Admin Tracking)
      // ติดสถานะ "กำลังโหลด" ค้างอยู่ตลอดไป เพราะ setState(loading=false)
      // ที่อยู่หลังจากนี้ไม่มีวันถูกเรียก
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List;
        if (features.isNotEmpty) {
          final coords = features[0]['geometry']['coordinates'];
          return {
            'lng': (coords[0] as num).toDouble(),
            'lat': (coords[1] as num).toDouble(),
          };
        }
      } else {
        debugPrint(
            'Geocoding error [${response.statusCode}]: ${response.body}');
      }
    } catch (e) {
      debugPrint('Geocoding error: $e');
    }
    return null;
  }

  /// 2. Routing API: คำนวณระยะทาง (กิโลเมตร), เวลาเดินทางจริง (นาที)
  /// และเส้นทางจริงบนถนน (route geometry) สำหรับวาดเป็นเส้นบนแผนที่
  static Future<Map<String, dynamic>?> getRouteInfo({
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
  }) async {
    if (_isKeyMissing) return null;

    final url = Uri.parse(
      'https://api.geoapify.com/v1/routing?waypoints=$startLat,$startLng%7C$destLat,$destLng&mode=drive&apiKey=$apiKey',
    );

    try {
      // ⏱️ [แก้ไข] เพิ่ม timeout เหตุผลเดียวกับ geocodeAddress ด้านบน
      final response = await http.get(url).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = data['features'] as List;
        if (features.isNotEmpty) {
          final feature = features[0];
          final props = feature['properties'];
          final double distanceMeters = (props['distance'] as num).toDouble();
          final double timeSeconds = (props['time'] as num).toDouble();

          // 📍 geometry เป็น MultiLineString: array ของเส้นย่อยแต่ละเส้น
          // เป็น array ของจุดพิกัด [lon, lat] เรียงตามเส้นทางถนนจริง
          // รวมทุกเส้นย่อยต่อกันเป็นเส้นทางเดียว (ต่อเนื่องกันสำหรับ mode=drive)
          final List<Map<String, double>> routePoints = [];
          try {
            final geometry = feature['geometry'];
            if (geometry != null && geometry['type'] == 'MultiLineString') {
              final lines = geometry['coordinates'] as List;
              for (final line in lines) {
                for (final point in (line as List)) {
                  routePoints.add({
                    'lat': (point[1] as num).toDouble(),
                    'lng': (point[0] as num).toDouble(),
                  });
                }
              }
            } else if (geometry != null && geometry['type'] == 'LineString') {
              final points = geometry['coordinates'] as List;
              for (final point in points) {
                routePoints.add({
                  'lat': (point[1] as num).toDouble(),
                  'lng': (point[0] as num).toDouble(),
                });
              }
            }
          } catch (e) {
            debugPrint('Routing geometry parse error: $e');
          }

          return {
            'distance_km':
                double.parse((distanceMeters / 1000.0).toStringAsFixed(1)),
            'time_minutes': (timeSeconds / 60.0).round(),
            'route_points': routePoints,
          };
        }
      } else {
        debugPrint('Routing error [${response.statusCode}]: ${response.body}');
      }
    } catch (e) {
      debugPrint('Routing error: $e');
    }
    return null;
  }

  /// 3. Static Map API: สร้าง URL รูปภาพแผนที่ (หมุดช่าง=รถสีฟ้า, หมุดลูกค้า=ปักสีแดง)
  static String getStaticMapUrl({
    required double startLat,
    required double startLng,
    required double destLat,
    required double destLng,
    int width = 600,
    int height = 400,
  }) {
    if (_isKeyMissing) return '';

    // 🔴 [แก้ไข] Geoapify ต้องการ hex color เป็นตัวพิมพ์เล็กเท่านั้น (ดูตัวอย่างในเอกสาร
    // ทางการทุกตัวอย่างใช้ตัวพิมพ์เล็ก เช่น %231db510, %23ff0000) — ของเดิมใช้ตัวพิมพ์ใหญ่
    // (2563EB, D8232A) ทำให้ Geoapify validate ไม่ผ่านและตอบ 400 กลับมาเป็น
    // "marker[0][2]" does not match any of the allowed types
    const String techColor = '%232563eb'; // สีฟ้า = ตำแหน่งช่าง
    const String appRed = '%23d8232a'; // สีแดงประจำแอป = ตำแหน่งลูกค้า

    // 📍 ต้องใช้รูปแบบ lonlat:lng,lat (Marker Icon API v2)
    // ⚠️ ห้ามใส่ icontype ตอนที่ type:awesome อยู่แล้ว (icontype ใช้คู่กับ type:material
    // เท่านั้น เพื่อระบุว่าไอคอนดึงจาก material หรือ awesome icon set) — ทดสอบยืนยันแล้วว่า
    // ถ้าใส่ icontype ซ้ำตอน type:awesome จะโดน 400 Bad Request จาก Geoapify
    final String techMarker =
        'lonlat:$startLng,$startLat;type:awesome;color:$techColor;size:44'
        ';icon:car';
    final String customerMarker =
        'lonlat:$destLng,$destLat;type:awesome;color:$appRed;size:44';

    return 'https://maps.geoapify.com/v1/staticmap?style=osm-carto'
        '&width=$width&height=$height'
        '&marker=$techMarker'
        // 🔧 ต้อง encode ตัวคั่นระหว่างหมุด "|" เป็น %7C เสมอ เพราะ "|" ไม่ใช่
        // อักขระที่ถูกต้องตามมาตรฐาน URI (RFC 3986) — ถ้าส่งแบบดิบๆ บาง HTTP client
        // (รวมถึง dart:io ที่ http package ใช้อยู่) อาจตัด/ตีความ URL ผิดจุดนี้
        '%7C$customerMarker'
        '&apiKey=$apiKey';
  }

  /// 4. Static Map API แบบหมุดเดียว: ใช้แสดงตัวอย่างตำแหน่งที่ลูกค้าปักหมุดไว้เอง
  /// (ในหน้าแบบฟอร์มแจ้งซ่อม ก่อนส่งข้อมูล)
  static String getSingleMarkerStaticMapUrl({
    required double lat,
    required double lng,
    int width = 600,
    int height = 260,
    double zoom = 15,
  }) {
    if (_isKeyMissing) return '';

    const String appRed = '%23d8232a';
    final String marker = 'lonlat:$lng,$lat;type:awesome;color:$appRed;size:56';

    return 'https://maps.geoapify.com/v1/staticmap?style=osm-carto'
        '&width=$width&height=$height'
        '&center=lonlat:$lng,$lat&zoom=$zoom'
        '&marker=$marker'
        '&apiKey=$apiKey';
  }

  /// 5. โหลดรูปแผนที่จริงพร้อมวินิจฉัยสาเหตุที่แท้จริงเมื่อโหลดไม่สำเร็จ
  /// ใช้แทน Image.network ตรงๆ เพราะ Image.network จะรู้แค่ "โหลดรูปไม่ได้"
  /// แต่ไม่บอกว่าทำไม (API key ผิด, หมดโควต้า, พิกัดไม่ถูกต้อง, หรือเน็ตเวิร์กมีปัญหา)
  /// ฟังก์ชันนี้ยิง HTTP request ไปที่ Static Map URL เอง แล้วอ่าน status code/response
  /// body ของ Geoapify มาแปลเป็นข้อความที่เข้าใจง่าย
  static Future<GeoapifyMapResult> fetchStaticMap(String mapUrl) async {
    if (mapUrl.isEmpty) {
      return const GeoapifyMapResult(
        errorMessage: 'ยังไม่ได้ตั้งค่า Geoapify API Key',
      );
    }

    try {
      final response = await http
          .get(Uri.parse(mapUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        return GeoapifyMapResult(bytes: response.bodyBytes);
      }

      // Geoapify มักส่ง error กลับมาเป็น JSON เช่น {"statusCode":400,"error":"Bad Request","message":"..."}
      String detail = 'รหัสข้อผิดพลาด ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          detail = '${body['message']}';
        }
      } catch (_) {
        // response ไม่ใช่ JSON (เช่นหลุด HTML error page) ก็ใช้ detail แบบ status code แทน
      }

      debugPrint(
          'Geoapify static map error [${response.statusCode}]: $detail\nURL: $mapUrl');

      String friendly;
      switch (response.statusCode) {
        case 401:
        case 403:
          friendly = 'Geoapify API Key ไม่ถูกต้องหรือถูกระงับการใช้งาน';
          break;
        case 429:
          friendly = 'ใช้งาน Geoapify เกินโควต้าที่กำหนดในวันนี้แล้ว';
          break;
        case 400:
          // 🔍 แสดงข้อความ error ดิบจาก Geoapify ต่อท้ายด้วย เพื่อให้รู้ parameter
          // ที่ผิดจริงๆ (เช่น icon ไม่ถูกต้อง, สี/พิกัดผิดรูปแบบ ฯลฯ) โดยไม่ต้องเดา
          friendly = 'สร้างแผนที่ไม่สำเร็จ: $detail';
          break;
        default:
          friendly = 'เชื่อมต่อระบบแผนที่ไม่สำเร็จ ($detail)';
      }
      return GeoapifyMapResult(errorMessage: friendly);
    } catch (e) {
      debugPrint('Geoapify static map network exception: $e\nURL: $mapUrl');
      return const GeoapifyMapResult(
        errorMessage:
            'ไม่สามารถเชื่อมต่ออินเทอร์เน็ตได้ กรุณาตรวจสอบสัญญาณอินเทอร์เน็ต',
      );
    }
  }
}
