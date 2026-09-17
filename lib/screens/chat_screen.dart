import 'dart:async';
import 'dart:convert';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/cloudinary_service.dart';
import 'package:after_sales/enums/user_role.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:after_sales/screens/call_screen.dart';

/// ตัวช่วยแปลง ID ให้ปลอดภัย รองรับทั้ง int, num, String ("12", "k12")
int? _parseId(dynamic val) {
  if (val is num) return val.toInt();
  if (val == null) return null;
  final s = val.toString().trim().replaceFirst(RegExp(r'^[kK]'), '');
  return int.tryParse(s);
}

/// 🕒 ฟังก์ชันเรียงลำดับข้อความแชทตามวันเวลาที่ส่งจริง (เก่าสุด -> ใหม่สุด)
List<Map<String, dynamic>> _sortMessagesChronological(List<Map<String, dynamic>> rawMsgs) {
  final list = List<Map<String, dynamic>>.from(rawMsgs);
  list.sort((a, b) {
    final dateStrA = a['created_at']?.toString() ?? '';
    final dateStrB = b['created_at']?.toString() ?? '';
    final timeA = DateTime.tryParse(dateStrA) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final timeB = DateTime.tryParse(dateStrB) ?? DateTime.fromMillisecondsSinceEpoch(0);
    final cmp = timeA.compareTo(timeB);
    if (cmp != 0) return cmp;
    return (a['id']?.toString() ?? '').compareTo(b['id']?.toString() ?? '');
  });
  return list;
}

/// ==========================================
/// 👤 ข้อมูลผู้ร่วมแชท 1 คน (แอดมิน / ช่าง / ลูกค้า)
/// ==========================================
class _ChatContact {
  final String username;
  final String role; // 'ADMIN' | 'TECHNICIAN' | 'CUSTOMER'
  final String name;
  final String phone;
  final String? photoUrl;

  const _ChatContact({
    required this.username,
    required this.role,
    required this.name,
    required this.phone,
    this.photoUrl,
  });

  String get roleLabel {
    switch (role) {
      case 'ADMIN':
        return 'แอดมิน';
      case 'TECHNICIAN':
        return 'ช่างเทคนิค';
      case 'CUSTOMER':
        return 'ลูกค้า';
      default:
        return role;
    }
  }

  IconData get roleIcon {
    switch (role) {
      case 'ADMIN':
        return Icons.admin_panel_settings;
      case 'TECHNICIAN':
        return Icons.engineering;
      default:
        return Icons.person;
    }
  }
}

ImageProvider? _chatContactImageProvider(String path) {
  if (isDataUriImage(path)) {
    try {
      final commaIndex = path.indexOf(',');
      if (commaIndex == -1) return null;
      final bytes = base64Decode(path.substring(commaIndex + 1));
      return MemoryImage(bytes);
    } catch (_) {
      return null;
    }
  }
  return NetworkImage(path);
}

class ChatScreen extends StatefulWidget {
  final UserRole role;
  final String? repairId;

  const ChatScreen({
    super.key,
    required this.role,
    this.repairId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _picker = ImagePicker();

  bool _loading = true;
  bool _sendingImage = false;
  Map<String, dynamic>? _repairData;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription<List<Map<String, dynamic>>>? _chatSub;

  bool _hasTechnician = false;
  bool _isJobCompleted = false;
  String _chatTitle = 'ห้องสนทนา';

  _ChatContact? _adminContact;
  _ChatContact? _technicianContact;
  _ChatContact? _customerContact;

  Map<String, int> _readStatus = {};
  Map<String, dynamic>? _replyingTo;

  final Map<String, GlobalKey> _messageKeys = {};
  int? _highlightedMessageId;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _loadChatData(isInitial: true);

    final parsedRepairId = _parseId(widget.repairId);
    if (parsedRepairId != null) {
      _chatSub = db.DatabaseHelper.instance
          .watchChatMessages(parsedRepairId)
          .listen(_onMessagesUpdate, onError: (e) {
        debugPrint('ChatScreen.watchChatMessages error: $e');
      });
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _chatSub?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _scrollToMessage(int targetId) async {
    final index = _messages.indexWhere((m) => _parseId(m['id']) == targetId);
    if (index == -1) {
      _snack('ไม่พบข้อความต้นฉบับ');
      return;
    }

    final key = _messageKeys['msg_$targetId'];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    } else if (_scrollController.hasClients) {
      final total = _messages.length;
      if (total > 0) {
        final targetOffset = (index / total) * _scrollController.position.maxScrollExtent;
        await _scrollController.animateTo(
          targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          final postKey = _messageKeys['msg_$targetId'];
          if (postKey?.currentContext != null) {
            Scrollable.ensureVisible(
              postKey!.currentContext!,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
          }
        });
      }
    }

    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = targetId);
    _highlightTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) {
        setState(() => _highlightedMessageId = null);
      }
    });
  }

  Future<void> _loadChatData({bool isInitial = false}) async {
    final parsedRepairId = _parseId(widget.repairId);
    if (parsedRepairId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      final repair = await db.DatabaseHelper.instance.getRepairById(parsedRepairId);
      if (repair == null) {
        if (!mounted) return;
        setState(() => _loading = false);
        return;
      }

      final techUsername = repair['technician_username']?.toString();
      final hasTech = techUsername != null && techUsername.isNotEmpty;

      final effStatus = db.getEffectiveRepairStatus(repair);
      final isCompleted = (effStatus == 'เสร็จแล้ว' || effStatus == 'เสร็จสิ้น' || effStatus.contains('ยกเลิก'));

      final adminUsername = repair['admin_username']?.toString();
      final customerUsername = repair['customer_username']?.toString();

      _ChatContact? adminContact;
      if (adminUsername != null && adminUsername.isNotEmpty) {
        final row = await db.DatabaseHelper.instance.getAdminProfile(adminUsername);
        adminContact = _ChatContact(
          username: adminUsername,
          role: 'ADMIN',
          name: (row?['admin_name']?.toString())?.trim().isNotEmpty == true
              ? row!['admin_name'].toString().trim()
              : ((repair['admin_name']?.toString()) ?? 'แอดมิน'),
          phone: (row?['phone']?.toString()) ?? '-',
          photoUrl: row?['photo_url']?.toString(),
        );
      }

      _ChatContact? technicianContact;
      if (hasTech) {
        final row = await db.DatabaseHelper.instance.getTechnicianByUsername(techUsername);
        technicianContact = _ChatContact(
          username: techUsername,
          role: 'TECHNICIAN',
          name: (row?['tech_name']?.toString())?.trim().isNotEmpty == true
              ? row!['tech_name'].toString().trim()
              : 'ช่างเทคนิค',
          phone: (row?['phone']?.toString()) ?? '-',
          photoUrl: row?['photo_url']?.toString(),
        );
      }

      _ChatContact? customerContact;
      if (customerUsername != null && customerUsername.isNotEmpty) {
        final row = await db.DatabaseHelper.instance.getCustomerProfile(customerUsername);
        final name = (row?['name']?.toString()) ?? '';
        final surname = (row?['surname']?.toString()) ?? '';
        final fullName = '$name $surname'.trim();
        customerContact = _ChatContact(
          username: customerUsername,
          role: 'CUSTOMER',
          name: fullName.isNotEmpty ? fullName : customerUsername,
          phone: (row?['phone']?.toString()) ?? '-',
          photoUrl: row?['photo_url']?.toString(),
        );
      }

      final ticketNo = (repair['ticketNo']?.toString()) ?? '#AS-${repair['id']}';
      final chatTitle = ticketNo;

      final rawMsgs = await db.DatabaseHelper.instance.getChatMessages(parsedRepairId);
      final msgs = _sortMessagesChronological(rawMsgs);

      await db.DatabaseHelper.instance.markChatAsRead(parsedRepairId, db.Session.currentUsername);

      if (msgs.isNotEmpty) {
        final latestId = _parseId(msgs.last['id']) ?? 0;
        await db.DatabaseHelper.instance.markChatRead(
          parsedRepairId,
          db.Session.currentUsername,
          latestId,
        );
      }
      final readStatus = await db.DatabaseHelper.instance.getChatReadStatus(parsedRepairId);

      if (!mounted) return;
      setState(() {
        _repairData = repair;
        _hasTechnician = hasTech;
        _isJobCompleted = isCompleted;
        _chatTitle = chatTitle;
        _adminContact = adminContact;
        _technicianContact = technicianContact;
        _customerContact = customerContact;
        _messages = msgs;
        _readStatus = readStatus;
        _loading = false;
      });

      if (isInitial) {
        _scrollToBottom();
      }
    } catch (e, st) {
      debugPrint('ChatScreen._loadChatData error: $e\n$st');
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('เกิดข้อผิดพลาดในการโหลดแชท: $e');
    }
  }

  Future<void> _onMessagesUpdate(List<Map<String, dynamic>> rawMsgs) async {
    final parsedRepairId = _parseId(widget.repairId);
    if (!mounted || parsedRepairId == null) return;
    try {
      final msgs = _sortMessagesChronological(rawMsgs);
      final hasNewMessages = msgs.length != _messages.length;

      if (hasNewMessages) {
        await db.DatabaseHelper.instance.markChatAsRead(
          parsedRepairId,
          db.Session.currentUsername,
        );
      }

      if (msgs.isNotEmpty) {
        final latestId = _parseId(msgs.last['id']) ?? 0;
        await db.DatabaseHelper.instance.markChatRead(
          parsedRepairId,
          db.Session.currentUsername,
          latestId,
        );
      }
      final readStatus = await db.DatabaseHelper.instance.getChatReadStatus(parsedRepairId);

      if (!mounted) return;
      setState(() {
        _messages = msgs;
        _readStatus = readStatus;
      });
      if (hasNewMessages) {
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('ChatScreen._onMessagesUpdate error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _notifyOtherParticipants(String previewText) async {
    final repairId = _parseId(widget.repairId);
    if (repairId == null) return;

    final myUsername = db.Session.currentUsername;
    final others = [_adminContact, _technicianContact, _customerContact]
        .whereType<_ChatContact>()
        .where((c) => c.username != myUsername && c.username.isNotEmpty);

    for (final contact in others) {
      try {
        await db.DatabaseHelper.instance.createNotification({
          'user_username': contact.username,
          'role': contact.role,
          'title': 'ข้อความใหม่: $_chatTitle',
          'message': previewText,
          'type': 'CHAT',
          'target_id': repairId,
          'is_read': 0,
          'push_data': {
            'type': 'CHAT',
            'target_id': repairId.toString(),
            'repair_id': repairId.toString(),
          },
        });
      } catch (e) {
        debugPrint('Error notifying ${contact.username}: $e');
      }
    }
  }

  void _showMessageActions(Map<String, dynamic> msg, bool isImage, bool isMe) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.reply_outlined, color: AppColors.primary),
                title: const Text('ตอบกลับ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _setReplyTo(msg);
                },
              ),
              if (!isImage)
                ListTile(
                  leading: const Icon(Icons.copy_outlined, color: AppColors.primary),
                  title: const Text('คัดลอกข้อความ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _copyMessageText(msg);
                  },
                ),
              if (isImage)
                ListTile(
                  leading: const Icon(Icons.download_outlined, color: AppColors.primary),
                  title: const Text('ดาวน์โหลดรูปภาพ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _downloadImage(msg['image_path']?.toString() ?? '');
                  },
                ),
              if (isMe && !isImage)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: AppColors.primary),
                  title: const Text('แก้ไขข้อความ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _editMessage(msg);
                  },
                ),
              if (isMe)
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: AppColors.redText),
                  title: const Text('ลบข้อความ', style: TextStyle(fontFamily: AppStyles.fontFamily, color: AppColors.redText)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _confirmDeleteMessage(msg);
                  },
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _setReplyTo(Map<String, dynamic> msg) {
    setState(() => _replyingTo = msg);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingTo = null);
  }

  String _replySenderLabel(Map<String, dynamic> msg) {
    if (msg['sender_username'] == db.Session.currentUsername) return 'คุณ';
    switch (msg['sender_role']) {
      case 'ADMIN':
        return 'แอดมิน';
      case 'TECHNICIAN':
        return 'ช่างเทคนิค';
      case 'CUSTOMER':
        return 'ลูกค้า';
      default:
        return (msg['sender_role']?.toString()) ?? '';
    }
  }

  String _replyPreviewText(Map<String, dynamic> msg) {
    if (msg['message_type'] == 'image') return '📷 รูปภาพ';
    if (msg['is_deleted'] == 1 || msg['is_deleted'] == true) return 'ข้อความถูกลบแล้ว';
    return (msg['message']?.toString()) ?? '';
  }

  Future<void> _copyMessageText(Map<String, dynamic> msg) async {
    final text = (msg['message']?.toString())?.trim() ?? '';
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    _snack('คัดลอกข้อความแล้ว');
  }

  Future<void> _downloadImage(String imagePath) async {
    if (imagePath.isEmpty) {
      _snack('ไม่พบรูปภาพสำหรับดาวน์โหลด');
      return;
    }
    try {
      if (isDataUriImage(imagePath)) {
        final commaIndex = imagePath.indexOf(',');
        if (commaIndex == -1) throw const FormatException('รูปภาพไม่ถูกต้อง');
        final bytes = base64Decode(imagePath.substring(commaIndex + 1));
        await Gal.putImageBytes(bytes, album: 'After Sales');
      } else {
        final response = await http.get(Uri.parse(imagePath));
        if (response.statusCode != 200) {
          throw Exception('โหลดรูปภาพไม่สำเร็จ (${response.statusCode})');
        }
        await Gal.putImageBytes(response.bodyBytes, album: 'After Sales');
      }
      if (!mounted) return;
      _snack('บันทึกรูปภาพลงในคลังภาพแล้ว');
    } on GalException catch (e) {
      if (!mounted) return;
      _snack(e.type.message);
    } catch (e) {
      if (!mounted) return;
      _snack('ดาวน์โหลดรูปภาพไม่สำเร็จ: $e');
    }
  }

  Future<void> _editMessage(Map<String, dynamic> msg) async {
    final messageId = _parseId(msg['id']);
    if (messageId == null) return;

    final controller = TextEditingController(text: msg['message']?.toString());
    final newText = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('แก้ไขข้อความ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 4,
          minLines: 1,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (newText == null || newText.isEmpty || !mounted) return;

    try {
      await db.DatabaseHelper.instance.editChatMessage(messageId, newText);
    } catch (e) {
      debugPrint('Error editing message: $e');
      _snack('แก้ไขข้อความไม่สำเร็จ: $e');
    }
  }

  Future<void> _confirmDeleteMessage(Map<String, dynamic> msg) async {
    final messageId = _parseId(msg['id']);
    if (messageId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบข้อความ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
        content: const Text(
          'ต้องการลบข้อความนี้ใช่หรือไม่? เมื่อลบแล้วจะไม่สามารถกู้คืนได้',
          style: TextStyle(fontFamily: AppStyles.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบ', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await db.DatabaseHelper.instance.deleteChatMessage(messageId);
    } catch (e) {
      debugPrint('Error deleting message: $e');
      _snack('ลบข้อความไม่สำเร็จ: $e');
    }
  }

  int _readCountFor(Map<String, dynamic> msg) {
    final msgId = _parseId(msg['id']);
    if (msgId == null) return 0;
    final senderUsername = msg['sender_username']?.toString();

    final others = [_adminContact, _technicianContact, _customerContact]
        .whereType<_ChatContact>()
        .where((c) => c.username != senderUsername);

    var count = 0;
    for (final c in others) {
      final lastRead = _readStatus[c.username] ?? 0;
      if (lastRead >= msgId) count++;
    }
    return count;
  }

  String? _photoUrlFor(String? senderUsername) {
    final contact = [_adminContact, _technicianContact, _customerContact]
        .whereType<_ChatContact>()
        .where((c) => c.username == senderUsername);
    if (contact.isEmpty) return null;
    final url = contact.first.photoUrl;
    return (url == null || url.isEmpty) ? null : url;
  }

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    final parsedRepairId = _parseId(widget.repairId);
    if (text.isEmpty || parsedRepairId == null || _isJobCompleted) return;

    _msgController.clear();

    final replySnapshot = _replyingTo;
    if (replySnapshot != null) setState(() => _replyingTo = null);

    final newMsg = {
      'repair_id': parsedRepairId,
      'sender_username': db.Session.currentUsername,
      'sender_role': widget.role.name.toUpperCase(),
      'message': text,
      'message_type': 'text',
      'created_at': DateTime.now().toIso8601String(),
      'is_read': 0,
      if (replySnapshot != null) ...{
        'reply_to_id': _parseId(replySnapshot['id']),
        'reply_to_sender_role': replySnapshot['sender_role'],
        'reply_to_message': _replyPreviewText(replySnapshot),
        'reply_to_is_image': replySnapshot['message_type'] == 'image',
      },
    };

    try {
      await db.DatabaseHelper.instance.sendChatMessage(newMsg);
      if (!mounted) return;

      _scrollToBottom();
      _focusNode.requestFocus();
      _notifyOtherParticipants(text);
    } catch (e) {
      _snack('ส่งข้อความไม่สำเร็จ: $e');
    }
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    final parsedRepairId = _parseId(widget.repairId);
    if (parsedRepairId == null || _isJobCompleted) return;

    try {
      final XFile? picked = await _picker.pickImage(source: source, imageQuality: 80);
      if (picked == null) return;

      if (!mounted) return;
      setState(() => _sendingImage = true);

      final imageUrl = await CloudinaryService.uploadImage(picked);

      final replySnapshot = _replyingTo;
      if (replySnapshot != null && mounted) {
        setState(() => _replyingTo = null);
      }

      final newMsg = {
        'repair_id': parsedRepairId,
        'sender_username': db.Session.currentUsername,
        'sender_role': widget.role.name.toUpperCase(),
        'message': '📷 รูปภาพ',
        'message_type': 'image',
        'image_path': imageUrl,
        'created_at': DateTime.now().toIso8601String(),
        'is_read': 0,
        if (replySnapshot != null) ...{
          'reply_to_id': _parseId(replySnapshot['id']),
          'reply_to_sender_role': replySnapshot['sender_role'],
          'reply_to_message': _replyPreviewText(replySnapshot),
          'reply_to_is_image': replySnapshot['message_type'] == 'image',
        },
      };

      await db.DatabaseHelper.instance.sendChatMessage(newMsg);
      if (!mounted) return;

      _scrollToBottom();
      _notifyOtherParticipants('📷 ส่งรูปภาพ');
    } catch (e) {
      _snack('ส่งรูปภาพไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  void _showAttachSheet() {
    if (_isJobCompleted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined, color: AppColors.primary),
                title: const Text('ถ่ายภาพ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined, color: AppColors.primary),
                title: const Text('เลือกจากคลังภาพ', style: TextStyle(fontFamily: AppStyles.fontFamily)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<_ChatContact> get _callableContacts {
    final all = [_adminContact, _technicianContact, _customerContact];
    return all
        .whereType<_ChatContact>()
        .where((c) => c.username != db.Session.currentUsername)
        .toList();
  }

  void _showCallSheet() {
    if (_isJobCompleted) {
      _snack('งานนี้เสร็จสิ้นแล้ว ไม่สามารถโทรออกผ่านห้องแชทนี้ได้อีก');
      return;
    }

    final contacts = _callableContacts;
    if (contacts.isEmpty) {
      _snack('ยังไม่มีผู้ร่วมแชทที่โทรออกได้ในตอนนี้');
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'เลือกวิธีโทร',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                ),
              ),
              ...contacts.map((c) => Column(
                    children: [
                      Builder(builder: (_) {
                        final hasPhoto = c.photoUrl != null && c.photoUrl!.isNotEmpty;
                        final provider = hasPhoto ? _chatContactImageProvider(c.photoUrl!) : null;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.redBg,
                            backgroundImage: provider,
                            child: provider == null ? Icon(c.roleIcon, color: AppColors.primary) : null,
                          ),
                          title: Text(
                            '${c.name} (${c.roleLabel})',
                            style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: const Text(
                            'โทรด้วยเสียงผ่านอินเทอร์เน็ต (ฟรี)',
                            style: TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: Colors.green,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.phone_in_talk, color: Colors.white, size: 18),
                          ),
                          onTap: () {
                            Navigator.pop(ctx);
                            _startInAppVoiceCall(c);
                          },
                        );
                      }),
                      if (c.phone != '-' && c.phone.isNotEmpty)
                        ListTile(
                          dense: true,
                          leading: const SizedBox(width: 40),
                          title: Text(
                            'โทรเบอร์มือถือ (${c.phone})',
                            style: const TextStyle(
                              fontFamily: AppStyles.fontFamily,
                              color: AppColors.textSubtitle,
                              fontSize: 13,
                            ),
                          ),
                          trailing: const Icon(Icons.phone_android, size: 16, color: Colors.grey),
                          onTap: () {
                            Navigator.pop(ctx);
                            _callViaSim(c);
                          },
                        ),
                      const Divider(height: 1),
                    ],
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _startInAppVoiceCall(_ChatContact contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen.makeCall(
          calleeUsername: contact.username,
          calleeName: contact.name,
          calleePhotoUrl: contact.photoUrl,
          calleeRole: contact.role,
        ),
      ),
    );
  }

  Future<void> _callViaSim(_ChatContact contact) async {
    if (contact.phone == '-' || contact.phone.isEmpty) {
      _snack('ไม่พบเบอร์โทรศัพท์ของ${contact.roleLabel}');
      return;
    }
    final uri = Uri(scheme: 'tel', path: contact.phone.replaceAll(' ', ''));
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _snack('ไม่สามารถโทรออกได้ในอุปกรณ์นี้');
    }
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute น.';
    } catch (_) {
      return '';
    }
  }

  static const List<String> _thaiShortMonths = [
    'ม.ค.', 'ก.พ.', 'มี.ค.', 'เม.ย.', 'พ.ค.', 'มิ.ย.',
    'ก.ค.', 'ส.ค.', 'ก.ย.', 'ต.ค.', 'พ.ย.', 'ธ.ค.',
  ];

  String _formatDateLabel(String? isoString) {
    if (isoString == null) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final date = DateTime(dt.year, dt.month, dt.day);

      if (date == today) return 'วันนี้';
      if (date == yesterday) return 'เมื่อวาน';

      final day = dt.day;
      final month = _thaiShortMonths[dt.month - 1];
      if (dt.year == now.year) return '$day $month';
      return '$day $month ${dt.year + 543}';
    } catch (_) {
      return '';
    }
  }

  bool _isSameDay(String? isoA, String? isoB) {
    if (isoA == null || isoB == null) return false;
    try {
      final a = DateTime.parse(isoA).toLocal();
      final b = DateTime.parse(isoB).toLocal();
      return a.year == b.year && a.month == b.month && a.day == b.day;
    } catch (_) {
      return false;
    }
  }

  void _openImageViewer(String path) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(
              child: LocalOrNetworkImage(path: path, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (widget.repairId == null || _repairData == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Column(
            children: [
              const AppHeader(
                title: 'แชท',
                showBack: true,
              ),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      const Text(
                        'ไม่พบรายการสนทนา',
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textSubtitle,
                          fontFamily: AppStyles.fontFamily,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'กรุณาเลือกใบแจ้งซ่อมเพื่อเริ่มการพูดคุย',
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
            ],
          ),
        ),
      );
    }

    final canType = _hasTechnician && !_isJobCompleted;

    if (widget.role == UserRole.admin) {
      final ownerAdminUsername = _repairData!['admin_username']?.toString();
      final isOwner = ownerAdminUsername == null ||
          ownerAdminUsername.isEmpty ||
          ownerAdminUsername == db.Session.currentUsername;
      if (!isOwner) {
        final ownerName = _adminContact?.name ?? ownerAdminUsername;
        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Column(
              children: [
                const AppHeader(title: 'แชท', showBack: true),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          const Text(
                            'ไม่มีสิทธิ์เข้าถึงห้องแชทนี้',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.textSubtitle,
                              fontFamily: AppStyles.fontFamily,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'งานนี้อยู่ในความดูแลของแอดมิน "$ownerName" เท่านั้น '
                            'แอดมินท่านอื่นไม่สามารถดูหรือส่งข้อความในห้องนี้ได้',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSubtitle,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                        ],
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            AppHeader(
              title: _chatTitle,
              showBack: true,
              trailing: IconButton(
                onPressed: _isJobCompleted ? null : _showCallSheet,
                icon: Icon(
                  Icons.call,
                  color: _isJobCompleted ? Colors.white38 : Colors.white,
                ),
                tooltip: _isJobCompleted ? 'งานเสร็จแล้ว โทรออกไม่ได้' : 'โทรออก',
              ),
            ),

            if (!_hasTechnician)
              Container(
                width: double.infinity,
                color: Colors.amber.shade100,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'รอดำเนินการมอบหมายช่าง สามารถเริ่มสนทนาได้เมื่อมีช่างรับงานแล้ว',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_isJobCompleted)
              Container(
                width: double.infinity,
                color: Colors.grey.shade200,
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: const Row(
                  children: [
                    Icon(Icons.lock_outline, color: Colors.grey, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'งานนี้เสร็จสิ้นเรียบร้อยแล้ว แชทถูกปิดการแก้ไข (อ่านได้อย่างเดียว)',
                        style: TextStyle(
                          color: Colors.black87,
                          fontSize: 12,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Text(
                        _hasTechnician ? 'เริ่มพิมพ์ข้อความพูดคุยที่นี่' : 'ยังไม่มีประวัติการสนทนา',
                        style: const TextStyle(
                          color: AppColors.textSubtitle,
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final msg = _messages[index];
                        final msgId = _parseId(msg['id']);
                        final keyStr = msgId != null ? 'msg_$msgId' : 'idx_$index';

                        if (!_messageKeys.containsKey(keyStr)) {
                          _messageKeys[keyStr] = GlobalKey();
                        }
                        final msgKey = _messageKeys[keyStr];

                        final isMe = msg['sender_username'] == db.Session.currentUsername;
                        final isImage = msg['message_type'] == 'image';
                        final isDeleted = msg['is_deleted'] == 1 || msg['is_deleted'] == true;
                        final isEdited = msg['is_edited'] == 1 || msg['is_edited'] == true;

                        final targetReplyId = _parseId(msg['reply_to_id']);

                        final bubble = _ChatBubble(
                          key: msgKey,
                          message: msg['message']?.toString() ?? '',
                          time: _formatTime(msg['created_at']),
                          isMe: isMe,
                          senderRole: msg['sender_role']?.toString() ?? '',
                          isImage: isImage && !isDeleted,
                          isDeleted: isDeleted,
                          isEdited: isEdited,
                          imagePath: msg['image_path']?.toString(),
                          readCount: isMe ? _readCountFor(msg) : 0,
                          senderPhotoUrl: isMe ? null : _photoUrlFor(msg['sender_username']?.toString()),
                          onTapImage: (isImage && !isDeleted)
                              ? () => _openImageViewer(msg['image_path']?.toString() ?? '')
                              : null,
                          replyToMessage: msg['reply_to_message']?.toString(),
                          replyToSenderRole: msg['reply_to_sender_role']?.toString(),
                          replyToIsImage: msg['reply_to_is_image'] == true ||
                              msg['reply_to_is_image'] == 1 ||
                              msg['reply_to_is_image'] == 'true' ||
                              msg['reply_to_is_image'] == '1',
                          onTapReplyQuote: targetReplyId != null
                              ? () => _scrollToMessage(targetReplyId)
                              : null,
                          isHighlighted: _highlightedMessageId != null && _highlightedMessageId == msgId,
                          onLongPress: isDeleted || _isJobCompleted
                              ? null
                              : () => _showMessageActions(msg, isImage, isMe),
                        );

                        final showDateDivider = index == 0 ||
                            !_isSameDay(
                              _messages[index - 1]['created_at']?.toString(),
                              msg['created_at']?.toString(),
                            );
                        if (!showDateDivider) return bubble;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _DateDivider(
                              label: _formatDateLabel(msg['created_at']),
                            ),
                            bubble,
                          ],
                        );
                      },
                    ),
            ),

            if (_sendingImage)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),

            // แถบตอบกลับ
            if (_replyingTo != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                color: AppColors.surfaceAlt,
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'ตอบกลับ ${_replySenderLabel(_replyingTo!)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                          Text(
                            _replyPreviewText(_replyingTo!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSubtitle,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    InkResponse(
                      onTap: _cancelReply,
                      radius: 16,
                      child: const Icon(Icons.close, size: 18, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),

            // ✏️ กล่องพิมพ์ส่งข้อความ
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              color: AppColors.primary,
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: 40,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _BarIconButton(
                        icon: Icons.image_outlined,
                        onTap: canType ? _showAttachSheet : null,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 40,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _msgController,
                            focusNode: _focusNode,
                            enabled: canType,
                            maxLines: 1,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: _hasTechnician
                                  ? (_isJobCompleted ? 'แชทจบแล้ว' : 'พิมพ์ข้อความ...')
                                  : 'ยังไม่มีช่างรับงาน',
                              hintStyle: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: 14,
                                fontFamily: AppStyles.fontFamily,
                              ),
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              isCollapsed: true,
                            ),
                            style: const TextStyle(
                              fontSize: 14,
                              fontFamily: AppStyles.fontFamily,
                              color: AppColors.textMain,
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _BarIconButton(
                        icon: Icons.send,
                        onTap: canType ? _sendMessage : null,
                      ),
                    ],
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

class _BarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _BarIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: Icon(
            icon,
            size: 22,
            color: onTap == null ? Colors.white54 : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  final String label;

  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSubtitle,
              fontWeight: FontWeight.w600,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String message;
  final String time;
  final bool isMe;
  final String senderRole;
  final bool isImage;
  final String? imagePath;
  final VoidCallback? onTapImage;
  final int readCount;
  final String? senderPhotoUrl;
  final bool isDeleted;
  final bool isEdited;
  final String? replyToMessage;
  final String? replyToSenderRole;
  final bool replyToIsImage;
  final VoidCallback? onTapReplyQuote;
  final bool isHighlighted;
  final VoidCallback? onLongPress;

  const _ChatBubble({
    super.key,
    required this.message,
    required this.time,
    required this.isMe,
    required this.senderRole,
    this.isImage = false,
    this.imagePath,
    this.onTapImage,
    this.readCount = 0,
    this.senderPhotoUrl,
    this.isDeleted = false,
    this.isEdited = false,
    this.replyToMessage,
    this.replyToSenderRole,
    this.replyToIsImage = false,
    this.onTapReplyQuote,
    this.isHighlighted = false,
    this.onLongPress,
  });

  static String? _labelForRole(String? role) {
    switch (role) {
      case 'ADMIN':
        return 'แอดมิน';
      case 'TECHNICIAN':
        return 'ช่างเทคนิค';
      case 'CUSTOMER':
        return 'ลูกค้า';
      default:
        return role;
    }
  }

  static Color _colorForRole(String? role) {
    switch (role) {
      case 'ADMIN':
        return AppColors.primary;
      case 'TECHNICIAN':
        return Colors.blueGrey;
      default:
        return Colors.teal;
    }
  }

  String? get _roleLabel => _labelForRole(senderRole);
  Color get _roleColor => _colorForRole(senderRole);

  @override
  Widget build(BuildContext context) {
    final bgBubble = isMe ? AppColors.primary : AppColors.surfaceAlt;
    final textBg = isMe ? Colors.white : AppColors.textMain;
    final label = _roleLabel;
    final hasReply = replyToMessage != null && replyToMessage!.isNotEmpty;

    final bubbleColumn = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMe && label != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 2, left: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: _roleColor,
                fontWeight: FontWeight.bold,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (isMe)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  isEdited ? '$time (แก้ไขแล้ว)' : time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSubtitle,
                    fontStyle: FontStyle.italic,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),

            Flexible(
              child: GestureDetector(
                onLongPress: onLongPress,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isDeleted ? AppColors.surfaceAlt : bgBubble,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMe ? 16 : 3),
                      bottomRight: Radius.circular(isMe ? 3 : 16),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasReply) _buildReplyQuote(),
                      if (isImage)
                        _buildImageBubble()
                      else if (isDeleted)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            'ข้อความถูกลบแล้ว',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 14,
                              fontStyle: FontStyle.italic,
                              fontFamily: AppStyles.fontFamily,
                            ),
                          ),
                        )
                      else
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Text(
                            message,
                            style: TextStyle(
                              color: textBg,
                              fontSize: 14,
                              fontFamily: AppStyles.fontFamily,
                              height: 1.3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),

            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  isEdited ? '$time (แก้ไขแล้ว)' : time,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSubtitle,
                    fontStyle: FontStyle.italic,
                    fontFamily: AppStyles.fontFamily,
                  ),
                ),
              ),
          ],
        ),
      ],
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      decoration: BoxDecoration(
        color: isHighlighted ? AppColors.primary.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: isMe
          ? bubbleColumn
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatAvatar(photoUrl: senderPhotoUrl),
                const SizedBox(width: 6),
                Flexible(child: bubbleColumn),
              ],
            ),
    );
  }

  Widget _buildReplyQuote() {
    final targetRoleLabel = _labelForRole(replyToSenderRole) ?? '';
    final roleAccentColor = _colorForRole(replyToSenderRole);

    final quoteBg = isMe ? Colors.white.withOpacity(0.18) : Colors.white;
    final sideBarColor = isMe ? Colors.white : roleAccentColor;
    final labelColor = isMe ? Colors.white : roleAccentColor;
    final contentColor = isMe ? Colors.white.withOpacity(0.9) : AppColors.textSubtitle;

    return InkWell(
      onTap: onTapReplyQuote,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: quoteBg,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: sideBarColor, width: 3.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (targetRoleLabel.isNotEmpty)
              Text(
                'ตอบกลับ $targetRoleLabel',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: labelColor,
                  fontFamily: AppStyles.fontFamily,
                ),
              ),
            const SizedBox(height: 2),
            Text(
              replyToIsImage ? '📷 รูปภาพ' : (replyToMessage ?? ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: contentColor,
                fontFamily: AppStyles.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageBubble() {
    if (imagePath == null || imagePath!.isEmpty) {
      return Container(
        width: 160,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported, color: Colors.grey),
      );
    }
    return GestureDetector(
      onTap: onTapImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: LocalOrNetworkImage(
          path: imagePath!,
          width: 180,
          height: 180,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  final String? photoUrl;
  static const double _size = 28;

  const _ChatAvatar({this.photoUrl});

  @override
  Widget build(BuildContext context) {
    if (photoUrl == null || photoUrl!.isEmpty) {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          color: AppColors.surfaceAlt,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.person, size: 16, color: AppColors.textHint),
      );
    }

    return ClipOval(
      child: LocalOrNetworkImage(
        path: photoUrl!,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
      ),
    );
  }
}