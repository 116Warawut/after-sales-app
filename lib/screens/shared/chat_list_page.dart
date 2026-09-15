// =============================================================================
// 💬 หน้ารายการแชท (Chat List)
// ใช้แทนแท็บ "แชท" เดิมที่เคยเปิด ChatScreen ตรง ๆ โดยไม่มี repairId
// (ซึ่งพอ ChatScreen ถูกปรับให้เป็นห้องแชทต่อ 1 ใบแจ้งซ่อมแล้ว เปิดแบบไม่มี
// repairId จะเจอแค่หน้า "ไม่พบรายการสนทนา" ตันอยู่แค่นั้น)
//
// หน้านี้ดึงใบแจ้งซ่อมที่เกี่ยวข้องกับผู้ใช้ปัจจุบันตามบทบาท มาเรียงเป็นรายการ
// ห้องแชท พร้อมพรีวิวข้อความล่าสุดและตัวเลขที่ยังไม่อ่าน กดแล้วค่อยเข้า
// ChatScreen(repairId: ...) ห้องจริงต่อไป
// =============================================================================
import 'package:flutter/material.dart';

import 'package:after_sales/app_styles.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/screens/chat_screen.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';

class ChatListPage extends StatefulWidget {
  final UserRole role;

  /// 🔔 เรียกทุกครั้งที่กลับมาจากห้องแชท (ซึ่งอาจมีข้อความถูกมาร์กว่าอ่านแล้ว)
  /// เพื่อให้ Shell ด้านนอกรีเฟรชตัวเลขบน BottomNavigationBar ทันที — เดิมตัวเลข
  /// บนแท็บแชท/กระดิ่งจะค้าง ไม่ลดลงจนกว่าผู้ใช้จะสลับแท็บเองอีกครั้ง เพราะ
  /// Shell รีเฟรชค่าพวกนี้เฉพาะตอน onTap ของแถบด้านล่างเท่านั้น ไม่รู้เรื่องการ
  /// push/pop ที่เกิดขึ้นภายใน Navigator ซ้อนของแท็บนี้เลย
  final VoidCallback? onUnreadCountsChanged;

  const ChatListPage({super.key, required this.role, this.onUnreadCountsChanged});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatRoomPreview {
  final int repairId;
  final String ticketId;
  final String subtitle; // ชื่อลูกค้า (แอดมิน/ช่าง) หรือรุ่นเครื่อง (ลูกค้า)
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
    // ปิดรายการที่สไลด์ค้างไว้ก่อนโหลดใหม่ ไม่ให้ค้างคาตอนลิสต์เปลี่ยน
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
          // 🔴 [แก้ไข] เจอบั๊ก: เดิมดึงงานซ่อม "ทั้งหมดในระบบ" มาโชว์เป็นห้องแชท
          // ให้แอดมินทุกคนเห็นเหมือนกันหมด ทำให้แอดมินที่ไม่ได้เป็นคนมอบหมายช่าง
          // ให้งานนี้ (ไม่ใช่เจ้าของงาน) เปิดเข้าไปดู/พิมพ์แชทของงานคนอื่นได้ตามใจ
          // เลย — ทั้งที่ต้องการให้ "1 ห้องแชท มีแอดมินรับผิดชอบได้แค่ 1 คน"
          // กรองให้เหลือเฉพาะงานที่ admin_username ตรงกับแอดมินที่ล็อกอินอยู่เท่านั้น
          repairs = (await dbHelper.getAllRepairs())
              .where((r) => (r['admin_username'] as String?) == username)
              .toList();
          break;
      }

      final rooms = <_ChatRoomPreview>[];
      for (final repair in repairs) {
        final id = repair['id'] as int?;
        if (id == null) continue;

        final last = await dbHelper.getLastChatMessage(id);

        // 🔴 [แก้ไข] เดิมข้ามงานที่ยังไม่มีข้อความเลยทุกกรณี ทำให้พองานเพิ่งถูก
        // แอดมินมอบหมายช่างเสร็จ (อนุมัติงาน) ห้องแชทจะยังไม่โผล่ที่แท็บแชทด้านล่าง
        // จนกว่าจะมีใครส่งข้อความก่อน 1 ครั้ง — ต้องไปเปิดจากหน้ารายละเอียดงานเท่านั้น
        // ใช้งานลำบาก ตอนนี้เปลี่ยนเงื่อนไขเป็น "โชว์ถ้ามีข้อความ หรือ งานนี้ยังทำงาน
        // อยู่จริง (มีช่างรับผิดชอบแล้ว และยังไม่เสร็จ/ไม่ถูกยกเลิก)" แทน — ห้องของงาน
        // ที่เสร็จ/ยกเลิกไปแล้ว พอถูกลบข้อความ (สไลด์ลบ) จะยังหายไปจริงเหมือนเดิม
        // เพราะไม่เข้าเงื่อนไข "ยังทำงานอยู่" อีกต่อไป
        final status = (repair['status'] as String?) ?? '';
        final hasTechnician =
            (repair['technician_username'] as String?)?.isNotEmpty == true;
        final isActiveJob = hasTechnician &&
            !status.contains('เสร็จ') &&
            !status.contains('ยกเลิก');
        if (last == null && !isActiveJob) continue;

        final unread = await dbHelper.getUnreadChatCount(id, username);

        String subtitle;
        switch (widget.role) {
          case UserRole.customer:
            subtitle = (repair['machine'] as String?) ?? '-';
            break;
          case UserRole.technician:
          case UserRole.admin:
            final custUsername = repair['customer_username'] as String?;
            subtitle = (custUsername != null && custUsername.isNotEmpty)
                ? custUsername
                : '-';
            break;
        }

        rooms.add(_ChatRoomPreview(
          repairId: id,
          ticketId: (repair['ticketNo'] as String?) ?? '#AS-$id',
          subtitle: subtitle,
          status: (repair['status'] as String?) ?? '-',
          lastMessage: last?['message'] as String?,
          lastMessageIsImage: (last?['message_type'] as String?) == 'image',
          lastMessageDeleted: last?['is_deleted'] == 1,
          lastMessageAt: last?['created_at'] as String?,
          unreadCount: unread,
        ));
      }

      // 🔃 เรียงห้องที่มีข้อความล่าสุดขึ้นก่อน (คุยล่าสุดอยู่บนสุดเหมือนแชทแอปทั่วไป)
      rooms.sort((a, b) {
        if (a.lastMessageAt == null && b.lastMessageAt == null) {
          return b.repairId.compareTo(a.repairId);
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
    // 🔄 กลับมาแล้วรีเฟรช เผื่อมีข้อความใหม่หรือเพิ่งอ่านไป ตัวเลขจะได้อัปเดต
    _loadRooms();
    // 🔴 [แก้ไข] แจ้ง Shell ให้รีเฟรชตัวเลขบน BottomNavigationBar ด้วย — ไม่งั้น
    // ตัวเลขจะค้างจนกว่าจะสลับแท็บเอง (ดูรายละเอียดที่คอมเมนต์ของ onUnreadCountsChanged)
    widget.onUnreadCountsChanged?.call();
  }

  // 🗑️ ลบห้องแชท — ลบข้อความทั้งหมดของงานนี้ทิ้งจริง (เหมือนการลบแจ้งเตือน ไม่มี pop up ถาม)
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
                          // 👆 แตะที่ไหนก็ได้ในพื้นที่ว่าง (นอกการ์ด) ให้ปิดใบที่เลื่อนค้างไว้
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
                                  // ปัดมุมแค่ฝั่งขวาสุดของกล่องไอคอน (ฝั่งซ้ายที่ชน
                                  // กับการ์ดปล่อยเหลี่ยมไว้ ให้แนบชิดกันตรงรอยต่อ)
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

/// แถวห้องแชท 1 ห้อง — เลขงาน/ชื่อคู่สนทนา + ข้อความล่าสุด + เวลา + ตัวเลขไม่อ่าน
class _ChatRoomTile extends StatelessWidget {
  final _ChatRoomPreview room;
  final VoidCallback onTap;

  const _ChatRoomTile({required this.room, required this.onTap});

  /// เวลาแบบย่อ (ใช้เฉพาะในรายการแชท ต่างจากแบบเต็มที่ใช้ในหน้าแจ้งเตือน)
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