import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/screens/technician/job_detail.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';

class TechnicianNotificationPage extends StatefulWidget {
  /// 🔔 เรียกทุกครั้งที่จำนวน "ยังไม่อ่าน" อาจเปลี่ยน (อ่าน/ลบ) เพื่อให้ Shell
  /// ด้านนอก (TechnicianRootShell) รีเฟรชตัวเลขบน BottomNavigationBar ทันที
  /// ไม่ต้องรอสลับแท็บก่อนถึงจะอัปเดต
  final VoidCallback? onUnreadCountsChanged;

  const TechnicianNotificationPage({super.key, this.onUnreadCountsChanged});

  @override
  State<TechnicianNotificationPage> createState() =>
      _TechnicianNotificationPageState();
}

class _TechnicianNotificationPageState
    extends State<TechnicianNotificationPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  /// 🔄 ดึงรายการแจ้งเตือนของช่างที่ล็อกอินอยู่จาก SQLite / Firebase
  Future<void> _loadNotifications({bool showLoading = true}) async {
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
  int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is bool) return v ? 1 : 0;
    return int.tryParse(v.toString().replaceFirst(RegExp(r'^[kK]'), ''));
  }

  String? _asString(dynamic v) => v?.toString();

  int get _unreadCount =>
      _notifications.where((n) => (_asInt(n['is_read']) ?? 0) == 0).length;

  // 🔔 รวมแจ้งเตือน "ข้อความใหม่" (type: CHAT) ที่เป็นงานเดียวกันให้เหลือแถวเดียว
  List<_FeedItem> get _feed {
    final Map<int, List<Map<String, dynamic>>> chatByJob = {};
    final List<Map<String, dynamic>> others = [];

    for (final n in _notifications) {
      final targetId = _asInt(n['target_id']);
      final type = _asString(n['type'])?.trim().toUpperCase() ?? '';
      if (type == 'CHAT' && targetId != null) {
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
    // 1. อัปเดต UI ทันที
    setState(() {
      _notifications = _notifications.map((n) {
        if (_asInt(n['target_id']) == group.jobId &&
            _asString(n['type'])?.trim().toUpperCase() == 'CHAT') {
          return {...n, 'is_read': 1};
        }
        return n;
      }).toList();
    });

    // 2. เคลียร์ในฐานข้อมูล Firebase ทั้งแจ้งเตือนและข้อความแชท
    for (final n in group.items) {
      final rawId = n['_fbKey'] ?? n['id'];
      if (rawId != null) {
        await db.DatabaseHelper.instance.markNotificationAsRead(rawId);
      }
    }
    await db.DatabaseHelper.instance
        .markChatAsRead(group.jobId, db.Session.currentUsername);
    widget.onUnreadCountsChanged?.call();

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          role: UserRole.technician,
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
        final id = n['_fbKey'] ?? n['id'];
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

    setState(() {
      _notifications =
          _notifications.map((n) => {...n, 'is_read': 1}).toList();
    });
    widget.onUnreadCountsChanged?.call();

    await db.DatabaseHelper.instance.markAllNotificationsAsRead(username);
  }

  /// 🗑️ ลบการแจ้งเตือนทั้งหมด
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

  /// 👆 เมื่อกดเลือกรายการแจ้งเตือน
  Future<void> _onTapNotification(Map<String, dynamic> item) async {
    final notificationId = _asInt(item['id']);
    final rawId = item['_fbKey'] ?? item['id'];
    final targetId = _asInt(item['target_id']);
    final isRead = (_asInt(item['is_read']) ?? 0) == 1;
    final rawType = _asString(item['type'])?.trim().toUpperCase() ?? '';
    final isChat = rawType == 'CHAT';

    // 1. อัปเดต UI ทันทีและบันทึกลง Firebase
    if (!isRead) {
      setState(() {
        _notifications = _notifications.map((e) {
          final sameId = _asInt(e['id']) == notificationId ||
              (e['_fbKey'] != null && e['_fbKey'] == item['_fbKey']);
          final sameChat = isChat &&
              targetId != null &&
              _asInt(e['target_id']) == targetId &&
              _asString(e['type'])?.trim().toUpperCase() == 'CHAT';
          if (sameId || sameChat) {
            return {...e, 'is_read': 1};
          }
          return e;
        }).toList();
      });

      if (rawId != null) {
        await db.DatabaseHelper.instance.markNotificationAsRead(rawId);
      }
      if (isChat && targetId != null) {
        await db.DatabaseHelper.instance
            .markChatAsRead(targetId, db.Session.currentUsername);
      }
      widget.onUnreadCountsChanged?.call();
    }

    if (!mounted) return;

    final title = _asString(item['title']) ?? 'แจ้งเตือน';
    final message = _asString(item['message']) ?? '-';
    final timeAgo = _formatTimeAgo(_asString(item['created_at']));
    final typeLabel = notificationTypeLabel(_asString(item['type']));
    final createdAtText =
        formatNotificationDateTime(_asString(item['created_at']));

    // 🔗 ไปหน้าห้องแชท หรือ หน้าใบแจ้งซ่อม ตามประเภทการแจ้งเตือน
    Future<void> openDetailDestination() async {
      if (targetId == null) return;
      if (isChat) {
        await db.DatabaseHelper.instance
            .markChatAsRead(targetId, db.Session.currentUsername);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              role: UserRole.technician,
              repairId: targetId.toString(),
            ),
          ),
        );
      } else {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobsDetail(repairId: targetId),
          ),
        );
      }
      if (!mounted) return;
      _loadNotifications(showLoading: false);
      widget.onUnreadCountsChanged?.call();
    }

    // 📄 ดูรายละเอียดแบบเต็ม
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
            viewDetailLabel: isChat ? 'ไปที่ห้องแชท' : 'ไปที่ใบแจ้งซ่อม',
            onViewDetail: targetId == null ? null : openDetailDestination,
          ),
        ),
      );
      if (!mounted) return;
      _loadNotifications(showLoading: false);
      widget.onUnreadCountsChanged?.call();
    }

    // 2. เด้ง pop-up รายละเอียดย่อ
    await showNotificationDetailDialog(
      context,
      title: title,
      message: message,
      timeAgo: timeAgo,
      typeLabel: typeLabel,
      viewDetailLabel: isChat ? 'ไปที่ห้องแชท' : 'ไปที่ใบแจ้งซ่อม',
      onViewFull: openFullDetail,
      onViewDetail: targetId == null ? null : openDetailDestination,
    );
  }

  /// 🗑️ ลบการแจ้งเตือนออกจากรายการ (สไลด์ซ้าย)
  Future<void> _deleteNotification(Map<String, dynamic> item) async {
    final id = item['_fbKey'] ?? item['id'];
    if (id == null) return;

    final backup = List<Map<String, dynamic>>.from(_notifications);

    setState(() => _notifications
        .removeWhere((e) => (e['_fbKey'] ?? e['id']) == id));
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
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    )
                  : Listener(
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
                                        title:
                                            'ข้อความใหม่ — ${group.chatTitle}',
                                        message: group.latestMessage,
                                        timeAgo: _formatTimeAgo(
                                            group.latestCreatedAt),
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
                                      title: item['title'] ?? 'แจ้งเตือน',
                                      message: item['message'] ?? '-',
                                      timeAgo:
                                          _formatTimeAgo(item['created_at']),
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
    final unreadCount =
        items.where((n) => (toInt(n['is_read']) ?? 0) == 0).length;
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

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().replaceFirst(RegExp(r'^[kK]'), ''));
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