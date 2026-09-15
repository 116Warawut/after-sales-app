import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';

import 'package:after_sales/screens/admin/assign_repair_formdetail.dart';

class AdminNotificationPage extends StatefulWidget {
  /// 🔔 เรียกทุกครั้งที่จำนวน "ยังไม่อ่าน" อาจเปลี่ยน (อ่าน/ลบ) เพื่อให้ Shell
  /// ด้านนอก (AdminRootShell) รีเฟรชตัวเลขบน BottomNavigationBar ทันที ไม่ต้อง
  /// รอสลับแท็บก่อนถึงจะอัปเดต
  final VoidCallback? onUnreadCountsChanged;

  const AdminNotificationPage({super.key, this.onUnreadCountsChanged});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// 🔄 ดึงรายการแจ้งเตือนของแอดมินที่ล็อกอินอยู่จาก SQLite
  Future<void> _loadNotifications({bool showLoading = true}) async {
    // ปิดรายการที่สไลด์ค้างไว้ก่อนโหลดใหม่ ไม่ให้ค้างคาตอนลิสต์เปลี่ยน
    SwipeToRevealDelete.closeOpened();
    if (showLoading) {
      setState(() => _loading = true);
    }

    try {
      final username = db.Session.currentUsername;
      await db.DatabaseHelper.instance.deleteExpiredNotifications(username);
      final data = await db.DatabaseHelper.instance.getNotificationsForUser(
        username,
      );

      if (!mounted) return;
      setState(() {
        // ⚠️ sqflite คืนค่าเป็น QueryResultSet ซึ่งเป็น list แบบอ่านอย่างเดียว
        // ถ้าเอามาใช้ตรง ๆ การ removeWhere / [index] = ... จะโยน UnsupportedError
        // จึงต้องคัดลอกเป็น List และ Map ที่แก้ไขได้ก่อนเสมอ
        _notifications = data
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: true);
      });
    } catch (e) {
      debugPrint('Error loading notifications: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// ⏱️ ฟังก์ชันคำนวณเวลาเปรียบเทียบ (เช่น "เมื่อ 5 นาทีที่แล้ว")
  String _formatTimeAgo(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'เมื่อสักครู่';
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inSeconds < 60) {
        return 'เมื่อสักครู่';
      } else if (difference.inMinutes < 60) {
        return 'เมื่อ ${difference.inMinutes} นาทีที่แล้ว';
      } else if (difference.inHours < 24) {
        return 'เมื่อ ${difference.inHours} ชั่วโมงที่แล้ว';
      } else if (difference.inDays < 7) {
        return 'เมื่อ ${difference.inDays} วันที่แล้ว';
      } else {
        return '${dateTime.day}/${dateTime.month}/${dateTime.year + 543}';
      }
    } catch (_) {
      return 'เมื่อสักครู่';
    }
  }

  // ---------------------------------------------------------------------------
  // 🛡️ ตัวช่วยแปลงชนิดข้อมูลจาก Firebase อย่างปลอดภัย
  // ---------------------------------------------------------------------------
  // ⭐ [แก้ไข] BEFORE: เดิม cast ตรง ๆ เช่น `item['is_read'] as int?` ซึ่งจะ
  // throw TypeError ทันทีถ้าค่าที่เก็บใน Firebase ไม่ใช่ int พอดี (เช่นถูกบันทึก
  // เป็น bool true/false หรือ String มาจากการทดสอบ/แก้ข้อมูลตรงใน Firebase
  // Console) ทำให้ทั้งหน้าพัง กลายเป็นจอเทาว่างเปล่า (Flutter แสดง ErrorWidget
  // สีเทาแทนที่จะ crash แบบมี error message ตอน build แบบ release)
  //
  // ⭐ [แก้ไข] AFTER: แปลงค่าแบบยอมรับได้หลายชนิด (int/double/bool/String/null)
  // ไม่ throw ไม่ว่าข้อมูลจริงจะเป็นชนิดไหน
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return int.tryParse(v.toString());
  }

  String? _asString(dynamic v) => v?.toString();

  int get _unreadCount =>
      _notifications.where((n) => (_asInt(n['is_read']) ?? 0) == 0).length;

  // 🔔 [ใหม่] รวมแจ้งเตือน "ข้อความใหม่" (type: CHAT) ที่เป็นงานเดียวกันให้เหลือ
  // แถวเดียว เหมือนที่ทำไว้ฝั่งเว็บ (NotificationsPage.jsx)
  List<_FeedItem> get _feed {
    final Map<int, List<Map<String, dynamic>>> chatByJob = {};
    final List<Map<String, dynamic>> others = [];

    for (final n in _notifications) {
      final targetId = _asInt(n['target_id']);
      if (n['type'] == 'CHAT' && targetId != null) {
        chatByJob.putIfAbsent(targetId, () => []).add(n);
      } else {
        others.add(n);
      }
    }

    final feed = <_FeedItem>[
      for (final n in others) _FeedItem.single(n),
      for (final entry in chatByJob.entries)
        _FeedItem.chatGroup(_ChatGroup.from(entry.key, entry.value, _asInt)),
    ];

    feed.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return feed;
  }

  /// 💬 เปิดห้องแชทของงานนี้โดยตรง + มาร์กแจ้งเตือนทั้งกลุ่มว่าอ่านแล้ว
  Future<void> _openChatGroup(_ChatGroup group) async {
    final unreadIds = group.items
        .where((n) => (_asInt(n['is_read']) ?? 0) == 0)
        .map((n) => _asInt(n['id']))
        .whereType<int>()
        .toList();

    if (unreadIds.isNotEmpty) {
      setState(() {
        _notifications = _notifications.map((n) {
          if (unreadIds.contains(_asInt(n['id']))) return {...n, 'is_read': 1};
          return n;
        }).toList();
      });
      for (final id in unreadIds) {
        db.DatabaseHelper.instance.markNotificationAsRead(id);
      }
      // 🔴 [แก้ไข] แจ้ง Shell ให้รีเฟรชตัวเลขบน BottomNavigationBar ทันที แทนที่
      // จะรอให้ผู้ใช้สลับแท็บก่อนถึงจะอัปเดต
      widget.onUnreadCountsChanged?.call();
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          role: UserRole.admin,
          repairId: group.jobId.toString(),
        ),
      ),
    );
    if (!mounted) return;
    _loadNotifications(showLoading: false);
    widget.onUnreadCountsChanged?.call();
  }

  /// 🗑️ ลบแจ้งเตือนแชททั้งกลุ่มพร้อมกัน (สไลด์ซ้ายที่แถวกลุ่ม)
  Future<void> _deleteChatGroup(_ChatGroup group) async {
    final backup = List<Map<String, dynamic>>.from(_notifications);
    final ids = group.items.map((n) => _asInt(n['id'])).toSet();
    setState(
        () => _notifications.removeWhere((n) => ids.contains(_asInt(n['id']))));
    widget.onUnreadCountsChanged?.call();

    try {
      for (final n in group.items) {
        final id = _asInt(n['id']);
        if (id != null) {
          await db.DatabaseHelper.instance.deleteNotification(id);
        }
      }
    } catch (e) {
      debugPrint('Error deleting chat group: $e');
      if (!mounted) return;
      setState(() => _notifications = backup);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบการแจ้งเตือนไม่สำเร็จ: $e',
              style: const TextStyle(fontFamily: AppStyles.fontFamily)),
          backgroundColor: AppColors.requiredMark,
        ),
      );
    }
  }

  /// ✅ ทำเครื่องหมายว่าอ่านแล้วทั้งหมด
  Future<void> _markAllAsRead() async {
    if (_unreadCount == 0) return;

    final username = db.Session.currentUsername;

    // อัปเดต UI ทันที (Optimistic Update)
    setState(() {
      _notifications = _notifications
          .map((n) => {...n, 'is_read': 1})
          .toList();
    });
    widget.onUnreadCountsChanged?.call();

    await db.DatabaseHelper.instance.markAllNotificationsAsRead(username);
  }

  /// 🗑️ ลบการแจ้งเตือนทั้งหมด — ถามยืนยันก่อนเสมอ เพราะกู้คืนไม่ได้
  Future<void> _deleteAllNotifications() async {
    if (_notifications.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'ยืนยันการลบทั้งหมด',
          style: TextStyle(fontFamily: AppStyles.fontFamily),
        ),
        content: Text(
          'ต้องการลบการแจ้งเตือนทั้งหมด ${_notifications.length} รายการใช่หรือไม่?\n'
          'เมื่อลบแล้วจะไม่สามารถกู้คืนได้',
          style: const TextStyle(fontFamily: AppStyles.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก',
                style: TextStyle(fontFamily: AppStyles.fontFamily)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ลบทั้งหมด',
              style: TextStyle(
                  color: Colors.red, fontFamily: AppStyles.fontFamily),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final backup = List<Map<String, dynamic>>.from(_notifications);
    setState(() => _notifications = []);
    widget.onUnreadCountsChanged?.call();

    try {
      await db.DatabaseHelper.instance
          .deleteAllNotifications(db.Session.currentUsername);
    } catch (e) {
      debugPrint('Error deleting all notifications: $e');
      if (!mounted) return;
      setState(() => _notifications = backup);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบการแจ้งเตือนทั้งหมดไม่สำเร็จ: $e',
              style: const TextStyle(fontFamily: AppStyles.fontFamily)),
          backgroundColor: AppColors.requiredMark,
        ),
      );
    }
  }

  /// 👆 เมื่อกดเลือกรายการแจ้งเตือน — เด้ง pop-up รายละเอียดย่อ
  Future<void> _onTapNotification(Map<String, dynamic> item) async {
    final notificationId = _asInt(item['id']);
    final targetId = _asInt(item['target_id']); // repair_id
    final isRead = (_asInt(item['is_read']) ?? 0) == 1;

    // 1. อัปเดต UI ทันที (Optimistic Update)
    if (notificationId != null && !isRead) {
      setState(() {
        final index =
            _notifications.indexWhere((e) => e['id'] == notificationId);
        if (index != -1) {
          final updatedItem = Map<String, dynamic>.from(_notifications[index]);
          updatedItem['is_read'] = 1;
          _notifications[index] = updatedItem;
        }
      });

      // อัปเดตในฐานข้อมูลเบื้องหลัง
      await db.DatabaseHelper.instance.markNotificationAsRead(notificationId);
      // 🔴 [แก้ไข] ต้องแจ้ง Shell ตรงนี้เลย เพราะบางรายการ (ไม่มี targetId) จะไม่มี
      // การ push หน้าใหม่เลย — ถ้ารอ _loadNotifications ตอน pop กลับมา จะไม่มีทาง
      // ถูกเรียกเลยสำหรับรายการแบบนี้ ตัวเลขบน BottomNavigationBar เลยค้าง
      widget.onUnreadCountsChanged?.call();
    }

    if (!mounted) return;

    final title = _asString(item['title']) ?? 'แจ้งเตือน';
    final message = _asString(item['message']) ?? '-';
    final timeAgo = _formatTimeAgo(_asString(item['created_at']));
    final typeLabel = notificationTypeLabel(_asString(item['type']));
    final createdAtText =
        formatNotificationDateTime(_asString(item['created_at']));

    // 🔗 ไปหน้าใบแจ้งซ่อม — เฉพาะการแจ้งเตือนที่ผูกกับงานซ่อมเท่านั้น
    Future<void> openJobDetail() async {
      if (targetId == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => AssignRepairFormDetailPage(repairId: targetId),
        ),
      );
      if (!mounted) return;
      _loadNotifications(showLoading: false);
      widget.onUnreadCountsChanged?.call();
    }

    // 📄 ดูรายละเอียดแบบเต็ม — ใช้ได้กับการแจ้งเตือนทุกรายการ
    Future<void> openFullDetail() async {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => NotificationFullDetailPage(
            title: title,
            message: message,
            typeLabel: typeLabel,
            createdAtText: createdAtText,
            timeAgo: timeAgo,
            isRead: true,
            onViewDetail: targetId == null ? null : openJobDetail,
          ),
        ),
      );
      if (!mounted) return;
      _loadNotifications(showLoading: false);
      widget.onUnreadCountsChanged?.call();
    }

    // 2. เด้ง pop-up รายละเอียดย่อ พร้อมทางเลือกดูแบบเต็ม
    await showNotificationDetailDialog(
      context,
      title: title,
      message: message,
      timeAgo: timeAgo,
      typeLabel: typeLabel,
      onViewFull: openFullDetail,
      onViewDetail: targetId == null ? null : openJobDetail,
    );
  }

  /// 🗑️ ลบการแจ้งเตือนออกจากรายการ (สไลด์ซ้าย)
  Future<void> _deleteNotification(Map<String, dynamic> item) async {
    final id = _asInt(item['id']);
    if (id == null) return;

    // เก็บสำเนาไว้ก่อน เผื่อลบใน DB ไม่สำเร็จจะได้คืนรายการกลับมา
    final backup = List<Map<String, dynamic>>.from(_notifications);

    setState(() => _notifications.removeWhere((e) => _asInt(e['id']) == id));
    widget.onUnreadCountsChanged?.call();

    try {
      final affected =
          await db.DatabaseHelper.instance.deleteNotification(id);
      if (affected == 0) throw Exception('ไม่พบรายการแจ้งเตือน id=$id');
    } catch (e) {
      debugPrint('Error deleting notification: $e');
      if (!mounted) return;
      setState(() => _notifications = backup);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ลบการแจ้งเตือนไม่สำเร็จ: $e',
              style: const TextStyle(fontFamily: AppStyles.fontFamily)),
          backgroundColor: AppColors.requiredMark,
        ),
      );
    }
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
            AppHeader(
              title: 'การแจ้งเตือน',
              showBack: false,
              leading: IconButton(
                onPressed: _unreadCount > 0 ? _markAllAsRead : null,
                icon: Icon(
                  Icons.done_all,
                  color: _unreadCount > 0 ? Colors.white : Colors.white38,
                  size: 22,
                ),
                tooltip: 'อ่านทั้งหมด',
              ),
              trailing: IconButton(
                onPressed:
                    _notifications.isNotEmpty ? _deleteAllNotifications : null,
                icon: Icon(
                  Icons.delete_sweep_outlined,
                  color: _notifications.isNotEmpty
                      ? Colors.white
                      : Colors.white38,
                  size: 22,
                ),
                tooltip: 'ลบการแจ้งเตือนทั้งหมด',
              ),
            ),

            // 📌 แถบบอกจำนวนที่ยังไม่อ่าน (ปุ่ม "อ่านทั้งหมด" ย้ายขึ้นไปที่มุมซ้ายบน
            // ของ Header แล้ว เหลือแค่ตัวเลขสรุปไว้ตรงนี้)
            if (!_loading && _unreadCount > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'ยังไม่อ่าน $_unreadCount รายการ',
                    style: const TextStyle(
                      color: AppColors.textSubtitle,
                      fontSize: 13,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                ),
              ),

            // 📋 รายการการแจ้งเตือน / สถานะไม่มีข้อมูล
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : Listener(
                      // 👆 แตะที่ไหนก็ได้ในพื้นที่ว่าง (นอกการ์ด) ให้ปิดใบที่เลื่อนค้างไว้
                      onPointerDown: (_) => SwipeToRevealDelete.closeOpened(),
                      behavior: HitTestBehavior.translucent,
                      child: RefreshIndicator(
                        color: AppColors.primary,
                        onRefresh: () =>
                            _loadNotifications(showLoading: false),
                        child: _notifications.isEmpty
                          ? LayoutBuilder(
                              builder: (context, constraints) {
                                return SingleChildScrollView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: constraints.maxHeight,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.notifications_none_outlined,
                                            size: 64,
                                            color: Colors.grey.shade400,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'ไม่มีการแจ้งเตือน',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: AppColors.textSubtitle,
                                              fontFamily: AppStyles.fontFamily,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            'คุณยังไม่มีรายการแจ้งเตือนในขณะนี้',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSubtitle,
                                              fontFamily: AppStyles.fontFamily,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            )
                          : ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                24,
                              ),
                              itemCount: _feed.length,
                              separatorBuilder: (_, __) => const Divider(
                                height: 1,
                                color: AppColors.border,
                              ),
                              itemBuilder: (context, index) {
                                final feedItem = _feed[index];

                                if (feedItem.isChatGroup) {
                                  final group = feedItem.chatGroup!;
                                  return SwipeToRevealDelete(
                                    key: ValueKey('chat-${group.jobId}'),
                                    onDelete: () => _deleteChatGroup(group),
                                    child: _NotificationCard(
                                      title: 'ข้อความใหม่ — ${group.chatTitle}',
                                      message: group.latestMessage,
                                      timeAgo:
                                          _formatTimeAgo(group.latestCreatedAt),
                                      isRead: group.unreadCount == 0,
                                      unreadCount: group.unreadCount,
                                      onTap: () => _openChatGroup(group),
                                    ),
                                  );
                                }

                                final item = feedItem.single!;
                                final isRead =
                                    (_asInt(item['is_read']) ?? 0) == 1;

                                return SwipeToRevealDelete(
                                  key: ValueKey(item['id'] ?? index),
                                  onDelete: () => _deleteNotification(item),
                                  child: _NotificationCard(
                                    title: _asString(item['title']) ??
                                        'แจ้งเตือน',
                                    message:
                                        _asString(item['message']) ?? '-',
                                    timeAgo: _formatTimeAgo(
                                        _asString(item['created_at'])),
                                    isRead: isRead,
                                    onTap: () => _onTapNotification(item),
                                  ),
                                );
                              },
                            ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 📦 การ์ดแสดงผลแต่ละรายการแจ้งเตือน (เหมือนฝั่งลูกค้า เพื่อความสอดคล้องของ UI)
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// 🔔 [ใหม่] โครงข้อมูลสำหรับ "รวมแจ้งเตือนแชท" ต่องานเดียวกันให้เหลือแถวเดียว
// ---------------------------------------------------------------------------
class _ChatGroup {
  final int jobId;
  final List<Map<String, dynamic>> items;
  final String chatTitle;
  final String latestMessage;
  final String? latestCreatedAt;
  final int unreadCount;
  final int sortKey;

  _ChatGroup({
    required this.jobId,
    required this.items,
    required this.chatTitle,
    required this.latestMessage,
    required this.latestCreatedAt,
    required this.unreadCount,
    required this.sortKey,
  });

  // 🔴 [แก้ไข] รับ toInt เข้ามาแยกต่างหาก เพราะไฟล์นี้ (แอดมิน) ต้องแปลง id/
  // is_read ด้วย _asInt() เสมอ (ค่าจาก Firebase อาจไม่ใช่ int ตรง ๆ) ต่างจาก
  // อีก 2 หน้า (ลูกค้า/ช่าง) ที่ cast แบบ `as int?` ตรง ๆ ได้เลย
  factory _ChatGroup.from(
    int jobId,
    List<Map<String, dynamic>> items,
    int? Function(dynamic) toInt,
  ) {
    final sorted = [...items]
      ..sort((a, b) => (toInt(b['id']) ?? 0).compareTo(toInt(a['id']) ?? 0));
    final latest = sorted.first;
    final title = (latest['title'] as String?) ?? 'ข้อความใหม่';
    final chatTitle = title.replaceFirst('ข้อความใหม่: ', '');
    final unreadCount = items.where((n) => (toInt(n['is_read']) ?? 0) == 0).length;
    return _ChatGroup(
      jobId: jobId,
      items: items,
      chatTitle: chatTitle,
      latestMessage: (latest['message'] as String?) ?? '-',
      latestCreatedAt: latest['created_at'] as String?,
      unreadCount: unreadCount,
      sortKey: toInt(latest['id']) ?? 0,
    );
  }
}

class _FeedItem {
  final Map<String, dynamic>? single;
  final _ChatGroup? chatGroup;

  _FeedItem.single(this.single) : chatGroup = null;
  _FeedItem.chatGroup(this.chatGroup) : single = null;

  bool get isChatGroup => chatGroup != null;

  // 🔴 [แก้ไข] parse แบบยอมรับได้หลายชนิดเหมือน _asInt() ของ State — ไม่ cast
  // ตรง ๆ ด้วย `as int?` เพราะค่า id จาก Firebase อาจไม่ใช่ int ตรง ๆ เสมอไป
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  int get sortKey => chatGroup?.sortKey ?? (_toInt(single?['id']) ?? 0);
}

class _NotificationCard extends StatelessWidget {
  final String title;
  final String message;
  final String timeAgo;
  final bool isRead;
  final VoidCallback onTap;
  final int unreadCount;

  const _NotificationCard({
    //super.key,
    required this.title,
    required this.message,
    required this.timeAgo,
    required this.isRead,
    required this.onTap,
    this.unreadCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isRead
          ? AppColors.background
          : AppColors.primary.withValues(alpha: 0.05),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // วงกลมไอคอนฝั่งซ้าย
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: isRead
                      ? AppColors.surfaceAlt
                      : AppColors.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_outlined,
                  color: isRead ? Colors.grey : AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // ข้อความหัวข้อ + รายละเอียด
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: AppColors.textMain,
                              fontSize: 16,
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.w700,
                              fontFamily: AppStyles.fontFamily,
                              letterSpacing: 0.16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // จุดแดงเล็กๆ ถ้ายังไม่อ่าน (หรือเลขจำนวนถ้าเป็นกลุ่มแชท
                        // ที่มีมากกว่า 1 ข้อความยังไม่อ่าน)
                        if (unreadCount > 1)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            width: 20,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                fontFamily: AppStyles.fontFamily,
                              ),
                            ),
                          )
                        else if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 8),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: const TextStyle(
                        color: AppColors.textMain,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        fontFamily: AppStyles.fontFamily,
                        letterSpacing: 0.16,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeAgo,
                      style: const TextStyle(
                        color: AppColors.textSubtitle,
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        fontFamily: AppStyles.fontFamily,
                        letterSpacing: 0.12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}