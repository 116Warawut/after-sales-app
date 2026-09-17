// =============================================================================
// 💬 หน้ารายการแชท (Chat List)
// =============================================================================
import 'package:flutter/material.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';
import 'package:after_sales/widgets.dart';

class ChatListPage extends StatefulWidget {
  final UserRole role;
  final VoidCallback? onUnreadCountsChanged;

  const ChatListPage({super.key, required this.role, this.onUnreadCountsChanged});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatRoomPreview {
  // 🍎 รองรับทั้ง int (เช่น 18) และ String Push Key (เช่น "-Oxxxx..." หรือ "k18") จากฝั่งเว็บ
  final dynamic repairId;
  final String ticketId;
  final String subtitle;
  final String status;
  final String? lastMessage;
  final bool lastMessageIsImage;
  final bool lastMessageDeleted;
  final String? lastMessageAt;
  final int unreadCount;

  const _ChatRoomPreview({
    required this.repairId,
    required this.ticketId,
    required this.subtitle,
    required this.status,
    required this.lastMessage,
    required this.lastMessageIsImage,
    required this.lastMessageDeleted,
    required this.lastMessageAt,
    required this.unreadCount,
  });
}

class _ChatListPageState extends State<ChatListPage> {
  bool _loading = true;
  List<_ChatRoomPreview> _rooms = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    SwipeToRevealDelete.closeOpened();
    setState(() => _loading = true);
    try {
      final username = db.Session.currentUsername;
      final dbHelper = db.DatabaseHelper.instance;

      List<Map<String, dynamic>> repairs;
      switch (widget.role) {
        case UserRole.customer:
          repairs = await dbHelper.getRepairsByCustomer(username);
          break;
        case UserRole.technician:
          repairs = await dbHelper.getRepairsByTechnician(username);
          break;
        case UserRole.admin:
          // 🔒 แอดมินหลักเห็นทั้งหมด / แอดมินทั่วไปเห็นงานของตนเอง + งานที่ยังไม่มีผู้รับผิดชอบ
          final allRepairs = await dbHelper.getAllRepairs();
          if (db.Session.isMainAdmin) {
            repairs = allRepairs;
          } else {
            repairs = allRepairs.where((r) {
              final adminUser = r['admin_username']?.toString().trim();
              return adminUser == null ||
                  adminUser.isEmpty ||
                  adminUser == username;
            }).toList();
          }
          break;
      }

      final rooms = <_ChatRoomPreview>[];
      for (final repair in repairs) {
        // 🍎 ดึง ID ที่ยืดหยุ่น: อ่านได้ทั้งคีย์ Firebase และฟิลด์ ID ในเอกสาร
        final rawId = resolveRecordId(repair) ?? repair['id'] ?? repair['_fbKey'];
        if (rawId == null) continue;

        // ดึงข้อความล่าสุด (ลองทั้ง ID ดิบ และ ID ตัด prefix 'k')
        Map<String, dynamic>? last = await dbHelper.getLastChatMessage(rawId);
        final rawIdStr = rawId.toString().trim();
        final cleanIdStr = rawIdStr.replaceFirst(RegExp(r'^[kK]'), '');

        if (last == null && cleanIdStr != rawIdStr) {
          last = await dbHelper.getLastChatMessage(cleanIdStr);
        }
        if (last == null) {
          final asInt = int.tryParse(cleanIdStr);
          if (asInt != null) {
            last = await dbHelper.getLastChatMessage(asInt);
          }
        }

        final status = repair['status']?.toString() ?? '';
        final isActiveJob =
            !status.contains('เสร็จ') && !status.contains('ยกเลิก');
        if (last == null && !isActiveJob) continue;

        // ดึงจำนวนที่ยังไม่อ่าน
        int unread = await dbHelper.getUnreadChatCount(rawId, username);
        if (unread == 0 && cleanIdStr != rawIdStr) {
          unread = await dbHelper.getUnreadChatCount(cleanIdStr, username);
        }

        String subtitle;
        switch (widget.role) {
          case UserRole.customer:
            subtitle = repair['machine']?.toString() ?? '-';
            break;
          case UserRole.technician:
          case UserRole.admin:
            final custUsername = repair['customer_username']?.toString();
            subtitle = (custUsername != null && custUsername.isNotEmpty)
                ? custUsername
                : '-';
            break;
        }

        rooms.add(_ChatRoomPreview(
          repairId: rawId,
          ticketId: repair['ticketNo']?.toString() ?? '#AS-$cleanIdStr',
          subtitle: subtitle,
          status: status.isEmpty ? '-' : status,
          lastMessage: last?['message']?.toString(),
          lastMessageIsImage: last?['message_type']?.toString() == 'image',
          lastMessageDeleted:
              last?['is_deleted'] == 1 || last?['is_deleted'] == true,
          lastMessageAt: last?['created_at']?.toString(),
          unreadCount: unread,
        ));
      }

      // 🔃 เรียงห้องที่มีข้อความล่าสุดขึ้นก่อน
      rooms.sort((a, b) {
        if (a.lastMessageAt == null && b.lastMessageAt == null) {
          return b.repairId.toString().compareTo(a.repairId.toString());
        }
        if (a.lastMessageAt == null) return 1;
        if (b.lastMessageAt == null) return -1;
        return b.lastMessageAt!.compareTo(a.lastMessageAt!);
      });

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading chat list: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  List<_ChatRoomPreview> get _filteredRooms {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _rooms;
    return _rooms.where((r) {
      return r.ticketId.toLowerCase().contains(q) ||
          r.subtitle.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openRoom(_ChatRoomPreview room) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          role: widget.role,
          repairId: room.repairId.toString(),
        ),
      ),
    );
    _loadRooms();
    widget.onUnreadCountsChanged?.call();
  }

  Future<void> _deleteRoom(_ChatRoomPreview room) async {
    final backup = List<_ChatRoomPreview>.from(_rooms);
    setState(() => _rooms.removeWhere((r) => r.repairId == room.repairId));

    try {
      final deletedCount =
          await db.DatabaseHelper.instance.deleteChatMessages(room.repairId);
      debugPrint(
          'ลบห้องแชท repairId=${room.repairId} — ลบไป $deletedCount ข้อความ');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบห้องแชทแล้ว')),
      );
    } catch (e) {
      debugPrint('Error deleting chat room: $e');
      if (!mounted) return;
      setState(() => _rooms = backup);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบห้องแชทไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = _filteredRooms;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            const AppHeader(title: 'แชท'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(
                  fontFamily: AppStyles.fontFamily,
                  fontSize: 14,
                ),
                decoration: AppStyles.inputDecoration(
                  hintText: 'ค้นหาเลขแจ้งซ่อม หรือชื่อลูกค้า',
                ).copyWith(
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.primary))
                  : rooms.isEmpty
                      ? const _EmptyChatList()
                      : Listener(
                          onPointerDown: (_) =>
                              SwipeToRevealDelete.closeOpened(),
                          behavior: HitTestBehavior.translucent,
                          child: RefreshIndicator(
                            color: AppColors.primary,
                            onRefresh: _loadRooms,
                            child: ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 4, 16, 20),
                              itemCount: rooms.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final room = rooms[index];
                                return SwipeToRevealDelete(
                                  key: ValueKey(room.repairId),
                                  onDelete: () => _deleteRoom(room),
                                  borderRadius: const BorderRadius.only(
                                    topRight: Radius.circular(14),
                                    bottomRight: Radius.circular(14),
                                  ),
                                  child: _ChatRoomTile(
                                    room: room,
                                    onTap: () => _openRoom(room),
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

class _EmptyChatList extends StatelessWidget {
  const _EmptyChatList();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'ยังไม่มีห้องแชท',
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textSubtitle,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'ห้องแชทจะขึ้นที่นี่เมื่อมีงานซ่อมที่เกี่ยวข้อง',
            style: TextStyle(
              fontFamily: AppStyles.fontFamily,
              fontSize: 13,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatRoomTile extends StatelessWidget {
  final _ChatRoomPreview room;
  final VoidCallback onTap;

  const _ChatRoomTile({required this.room, required this.onTap});

  String _shortTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';

    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);

    if (diff.inDays == 0 && now.day == local.day) {
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    } else if (diff.inDays < 7) {
      const days = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
      return days[local.weekday - 1];
    } else {
      return '${local.day}/${local.month}/${(local.year + 543) % 100}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = room.unreadCount > 0;
    final preview = room.lastMessageDeleted
        ? 'ข้อความถูกลบแล้ว'
        : room.lastMessageIsImage
            ? '📷 รูปภาพ'
            : (room.lastMessage?.trim().isNotEmpty == true
                ? room.lastMessage!.trim()
                : 'เริ่มการสนทนา');

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.chat_bubble_outline,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            room.ticketId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 14,
                              fontWeight:
                                  hasUnread ? FontWeight.w800 : FontWeight.w700,
                              color: AppColors.textMain,
                            ),
                          ),
                        ),
                        if (room.lastMessageAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            _shortTime(room.lastMessageAt),
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 11,
                              color: hasUnread
                                  ? AppColors.primary
                                  : AppColors.textHint,
                              fontWeight: hasUnread
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      room.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppStyles.fontFamily,
                        fontSize: 12,
                        color: AppColors.textSubtitle,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontSize: 13,
                              color: hasUnread
                                  ? AppColors.textMain
                                  : AppColors.textSubtitle,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          CountBadge(count: room.unreadCount),
                        ],
                      ],
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