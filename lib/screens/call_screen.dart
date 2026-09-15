import 'dart:async';
import 'package:after_sales/app_styles.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/webrtc_service.dart';
import 'package:after_sales/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class CallScreen extends StatefulWidget {
  final bool isCaller;
  final String? callId;
  final String targetUsername;
  final String targetName;
  final String? targetPhotoUrl;
  final String? targetRole;

  const CallScreen({
    super.key,
    required this.isCaller,
    this.callId,
    required this.targetUsername,
    required this.targetName,
    this.targetPhotoUrl,
    this.targetRole,
  });

  /// สร้างสายโทรออก
  static Widget makeCall({
    required String calleeUsername,
    required String calleeName,
    String? calleePhotoUrl,
    String? calleeRole,
  }) {
    return CallScreen(
      isCaller: true,
      targetUsername: calleeUsername,
      targetName: calleeName,
      targetPhotoUrl: calleePhotoUrl,
      targetRole: calleeRole,
    );
  }

  /// รับสายเรียกเข้า
  static Widget receiveCall({
    required String callId,
    required String callerUsername,
    required String callerName,
    String? callerPhotoUrl,
  }) {
    return CallScreen(
      isCaller: false,
      callId: callId,
      targetUsername: callerUsername,
      targetName: callerName,
      targetPhotoUrl: callerPhotoUrl,
    );
  }

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final WebRtcService _webrtc = WebRtcService();

  String _statusText = 'กำลังเชื่อมต่อ...';
  bool _isConnected = false;
  bool _isMuted = false;
  bool _isSpeaker = false;

  Timer? _timer;
  int _secondsElapsed = 0;

  @override
  void initState() {
    super.initState();
    _initCall();
  }

  Future<void> _initCall() async {
    _webrtc.onStatusChanged = (status) {
      if (!mounted) return;
      if (status == 'connected') {
        setState(() {
          _isConnected = true;
          _statusText = 'กำลังสนทนา';
        });
        _startTimer();
        // 🔴 [แก้ไข] เดิมค่าเริ่มต้นคือลำโพงแนบหู (earpiece) ซึ่งเสียงเบามาก
        // ถ้าไม่ได้แนบเครื่องกับหูจริง ๆ จะแทบไม่ได้ยินเลย เผลอเข้าใจผิดว่า
        // "ไม่มีเสียง" ทั้งที่จริง ๆ เสียงออกอยู่แค่เบามาก — เปิดลำโพงเป็นค่า
        // เริ่มต้นให้เลยตอนสายเชื่อมต่อสำเร็จ ยังกดปิดกลับเป็นแนบหูได้ตามปกติ
        _webrtc.setSpeakerphone(true);
        setState(() => _isSpeaker = true);
      } else if (status == 'ended' || status == 'rejected') {
        _endCall();
      }
    };

    // 🔴 [แก้ไข] เดิมไม่มีการดักสถานะการเชื่อมต่อจริงของ WebRTC เลย ทำให้ต่อให้
    // เสียงเชื่อมต่อไม่สำเร็จจริง (เช่น ICE ล้มเหลวเพราะเครือข่ายเข้มงวด — ระบบนี้
    // มีแค่ STUN server ยังไม่มี TURN server สำรอง) หน้าจอก็ยังโชว์ "กำลังสนทนา"
    // อยู่ดีเพราะอ่านจากสถานะ signaling เท่านั้น ตอนนี้ถ้า WebRTC รายงานว่า
    // เชื่อมต่อไม่สำเร็จ/หลุด จะแจ้งให้เห็นตรง ๆ แทนที่จะเงียบไปเฉย ๆ
    _webrtc.onPeerConnectionStateChanged = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _statusText = 'เชื่อมต่อเสียงไม่สำเร็จ (เครือข่ายไม่เอื้ออำนวย)');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'เชื่อมต่อเสียงไม่สำเร็จ อาจเป็นเพราะเครือข่ายทั้งสองฝั่งเข้มงวดเกินไป',
            ),
          ),
        );
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _statusText = 'สัญญาณหลุด กำลังพยายามเชื่อมต่อใหม่...');
      }
    };

    try {
      if (widget.isCaller) {
        setState(() => _statusText = 'กำลังโทรออก...');
        await _webrtc.startCall(
          callerUsername: db.Session.currentUsername,
          callerName: db.Session.currentUserData?['name'] ??
              db.Session.currentUsername,
          callerPhotoUrl:
              db.Session.currentUserData?['photo_url']?.toString(),
          calleeUsername: widget.targetUsername,
          calleeName: widget.targetName,
          calleeRole: widget.targetRole,
        );
      } else {
        setState(() => _statusText = 'สายเรียกเข้า...');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ข้อผิดพลาด: $e')),
        );
        Navigator.pop(context);
      }
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _secondsElapsed++);
      }
    });
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _acceptCall() async {
    try {
      setState(() => _statusText = 'กำลังเชื่อมต่อสาย...');
      await _webrtc.answerCall(widget.callId!);
      setState(() {
        _isConnected = true;
        _statusText = 'กำลังสนทนา';
      });
      _startTimer();
    } catch (e) {
      _endCall();
    }
  }

  Future<void> _rejectCall() async {
    if (widget.callId != null) {
      await _webrtc.rejectCall(widget.callId!);
    }
    _endCall();
  }

  Future<void> _endCall() async {
    _timer?.cancel();
    await _webrtc.endCall();
    if (mounted) {
      Navigator.maybePop(context);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _webrtc.endCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // หัวข้อด้านบน
              Column(
                children: [
                  const SizedBox(height: 20),
                  Text(
                    _isConnected
                        ? _formatDuration(_secondsElapsed)
                        : _statusText,
                    style: TextStyle(
                      color: _isConnected ? Colors.greenAccent : Colors.white70,
                      fontSize: 16,
                      fontFamily: AppStyles.fontFamily,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              // ข้อมูลคู่สนทนาตรงกลาง
              Column(
                children: [
                  Container(
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _isConnected
                            ? Colors.greenAccent
                            : AppColors.primary,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (_isConnected
                                  ? Colors.greenAccent
                                  : AppColors.primary)
                              .withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: widget.targetPhotoUrl != null &&
                              widget.targetPhotoUrl!.isNotEmpty
                          ? LocalOrNetworkImage(
                              path: widget.targetPhotoUrl!,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              color: Colors.white12,
                              child: const Icon(
                                Icons.person,
                                size: 70,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    widget.targetName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      fontFamily: AppStyles.fontFamily,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '@${widget.targetUsername}',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 14,
                      fontFamily: AppStyles.fontFamily,
                    ),
                  ),
                ],
              ),

              // ปุ่มควบคุมด้านล่าง
              if (!widget.isCaller && !_isConnected)
                // สายเรียกเข้า (ยังไม่ได้รับสาย): มีปุ่มปฏิเสธ + ปุ่มรับสาย
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'ปฏิเสธ',
                      onTap: _rejectCall,
                    ),
                    _CallActionButton(
                      icon: Icons.call,
                      color: Colors.green,
                      label: 'รับสาย',
                      onTap: _acceptCall,
                    ),
                  ],
                )
              else
                // กำลังโทรออก หรือ สนทนาอยู่: ปุ่ม Mute, Speaker, วางสาย
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: _isMuted ? Icons.mic_off : Icons.mic,
                      color: _isMuted ? Colors.amber : Colors.white24,
                      iconColor: _isMuted ? Colors.black : Colors.white,
                      label: _isMuted ? 'เปิดไมค์' : 'ปิดไมค์',
                      onTap: () {
                        setState(() => _isMuted = !_isMuted);
                        _webrtc.toggleMute(_isMuted);
                      },
                    ),
                    _CallActionButton(
                      icon: Icons.call_end,
                      color: Colors.red,
                      label: 'วางสาย',
                      size: 68,
                      onTap: _endCall,
                    ),
                    _CallActionButton(
                      icon: _isSpeaker
                          ? Icons.volume_up
                          : Icons.volume_down_outlined,
                      color: _isSpeaker ? Colors.amber : Colors.white24,
                      iconColor: _isSpeaker ? Colors.black : Colors.white,
                      label: 'ลำโพง',
                      onTap: () {
                        setState(() => _isSpeaker = !_isSpeaker);
                        _webrtc.setSpeakerphone(_isSpeaker);
                      },
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color iconColor;
  final String label;
  final double size;
  final VoidCallback onTap;

  const _CallActionButton({
    required this.icon,
    required this.color,
    this.iconColor = Colors.white,
    required this.label,
    this.size = 56,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontFamily: AppStyles.fontFamily,
          ),
        ),
      ],
    );
  }
}