/*import 'package:after_sales/app_styles.dart';
import 'package:after_sales/screens/technician/tac_id_card.dart';
import 'package:flutter/material.dart';
//import 'dart:convert'; // สำหรับแปลง JSON จาก API

class MapApp extends StatelessWidget {
  const MapApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Sarabun', // ใช้ฟอนต์ Sarabun
      ),
      home: const CustomerMapScreen(),
    );
  }
}

// ==========================================
// 1. Data Model เตรียมไว้รับข้อมูล JSON จาก API (SQL)
// ==========================================
class CustomerLocation {
  final String address;
  final double latitude;
  final double longitude;
  final String phone;

  CustomerLocation({
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
  });

  // ฟังก์ชันแปลง JSON เป็น Object
  factory CustomerLocation.fromJson(Map<String, dynamic> json) {
    return CustomerLocation(
      address: json['address'] ?? '',
      latitude: json['latitude'] ?? 0.0,
      longitude: json['longitude'] ?? 0.0,
      phone: json['phone'] ?? '',
    );
  }
}

// ==========================================
// 2. หน้าจอ UI หลัก
// ==========================================
class CustomerMapScreen extends StatefulWidget {
  const CustomerMapScreen({super.key});

  @override
  State<CustomerMapScreen> createState() => _CustomerMapScreenState();
}

class _CustomerMapScreenState extends State<CustomerMapScreen> {
  CustomerLocation? customerData;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchCustomerLocationAPI();
  }

  // ==========================================
  // 3. ฟังก์ชันจำลองการดึง API จาก Backend
  // ==========================================
  Future<void> _fetchCustomerLocationAPI() async {
    // Todo: ของจริงให้ใช้ package:http หรือ dio ยิง API ไปหา Backend
    // ตัวอย่างโค้ดจริง:
    // final response = await http.get(Uri.parse('https://your-api.com/api/getLocation?customerId=123'));
    // if (response.statusCode == 200) { ... }

    // จำลองการโหลดข้อมูล (หน่วงเวลา 1.5 วินาที)
    await Future.delayed(const Duration(milliseconds: 1500));

    // จำลองข้อมูล JSON ที่ได้กลับมาจาก Backend (SQL)
    final mockJsonResponse = {
      "address":
          "264 ถนน จักรวรรดิ แขวงจักรวรรดิ์ เขตสัมพันธวงศ์ กรุงเทพมหานคร 10100",
      "latitude": 13.7423,
      "longitude": 100.5050,
      "phone": "0812345678",
    };

    if (mounted) {
      setState(() {
        customerData = CustomerLocation.fromJson(mockJsonResponse);
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      // แถบด้านบน
      appBar: AppBar(
        backgroundColor: const Color(0xFFBA0000),
        centerTitle: true,
        title: const Text(
          'MAP',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),

      // ส่วนเนื้อหา
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFBA0000)),
            ) // โหลดดิ้งตอนดึง API
          : Column(
              children: [
                // 4. พื้นที่สำหรับใส่ Google Maps Real-time
                Expanded(
                  child: Container(
                    color: Colors.grey.shade300,
                    width: double.infinity,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.map, size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'พื้นที่สำหรับแสดง Google Maps\n(ใช้ package: google_maps_flutter)',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.black54),
                        ),
                      ],
                    ),
                    // Todo: เมื่อลง google_maps_flutter ให้เอาโค้ดด้านล่างนี้ไปแทนที่ Column ด้านบน
                    /*
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(customerData!.latitude, customerData!.longitude),
                        zoom: 15,
                      ),
                      markers: {
                        Marker(
                          markerId: const MarkerId('customer'),
                          position: LatLng(customerData!.latitude, customerData!.longitude),
                        ),
                      },
                    ),
                    */
                  ),
                ),

                // 5. ส่วนข้อมูลลูกค้าด้านล่าง
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        // ignore: deprecated_member_use
                        color: Colors.black.withOpacity(0.1),
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
                      // หัวข้อ
                      const Text(
                        'ที่อยู่ลูกค้า',
                        style: TextStyle(
                          color: Color(0xFFBA0000),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ที่อยู่ (ดึงจาก API)
                      Text(
                        customerData?.address ?? '-',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Colors.black87,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ปุ่มติดต่อ
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildActionMenu(Icons.phone, 'ติดต่อสอบถาม', () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'โทร: ${customerData?.phone ?? '-'}',
                                ),
                              ),
                            );
                          }),
                          _buildActionMenu(
                            Icons.chat_bubble_outline,
                            'ส่งข้อความ',
                            () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'ส่งข้อความถึง: ${customerData?.phone ?? '-'}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // ปุ่มแสดงบัตร
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFBA0000), Color(0xFFE53935)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              // ignore: deprecated_member_use
                              color: Colors.black.withOpacity(0.2),
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
                            backgroundColor:
                                Colors.transparent, // โปร่งใสเพื่อโชว์ Gradient
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'แสดงบัตร',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

      // แถบด้านล่างสุดสีแดง
      bottomNavigationBar: Container(
        height: 60,
        color: const Color(0xFFBA0000),
      ),
    );
  }

  // Widget ช่วยสร้างปุ่มเมนูเล็กๆ (ติดต่อ, ส่งข้อความ)
  Widget _buildActionMenu(IconData icon, String label, VoidCallback onTap) {
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
*/