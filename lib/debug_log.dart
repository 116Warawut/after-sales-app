// 🔴 [ชั่วคราว-Debug] ที่เก็บ log แบบง่ายๆ ไว้ดูบนหน้าจอเครื่องจริงโดยไม่ต้องต่อ
// Xcode/Mac — เรียก DebugLog.add('ข้อความ') จากตรงไหนก็ได้ในแอป แล้วกดปุ่ม 🐛
// (มุมขวาล่างของทุกหน้าจอ ใส่ไว้ผ่าน main.dart) เพื่อดูรายการทั้งหมด (ล่าสุดอยู่บนสุด)
//
// ---- ลบไฟล์นี้ทิ้งทั้งไฟล์ได้เมื่อ debug เสร็จแล้ว พร้อมกับจุดที่เรียกใช้
//      (services.dart และ main.dart) ----
import 'package:flutter/material.dart';

class DebugLog {
  static final List<String> _entries = [];

  static void add(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    _entries.insert(0, '[$time] $message');
    // กันไม่ให้ลิสต์ยาวจนกินหน่วยความจำ เก็บล่าสุดไว้ 300 รายการพอ
    if (_entries.length > 300) {
      _entries.removeLast();
    }
  }

  static List<String> get entries => List.unmodifiable(_entries);

  static void clear() => _entries.clear();
}

/// ปุ่มลอย 🐛 มุมขวาล่าง กดเพื่อดู log ทั้งหมดที่บันทึกไว้ระหว่างใช้งานแอป
/// ใส่ไว้ใน builder ของ MaterialApp (main.dart) เพื่อให้กดได้จากทุกหน้าจอ
class DebugLogButton extends StatelessWidget {
  const DebugLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 12,
      bottom: 24,
      child: SafeArea(
        child: FloatingActionButton.small(
          heroTag: 'debug_log_btn',
          backgroundColor: Colors.red.shade700,
          onPressed: () => _showLog(context),
          child: const Icon(Icons.bug_report, color: Colors.white),
        ),
      ),
    );
  }

  void _showLog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.3,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Debug Log',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              DebugLog.clear();
                              setSheetState(() {});
                            },
                            child: const Text('ล้าง'),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: DebugLog.entries.isEmpty
                          ? const Center(child: Text('ยังไม่มี log บันทึกไว้'))
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(12),
                              itemCount: DebugLog.entries.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 16),
                              itemBuilder: (ctx, i) => SelectableText(
                                DebugLog.entries[i],
                                style: const TextStyle(
                                    fontSize: 12, fontFamily: 'monospace'),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}
