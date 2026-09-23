import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:after_sales/services.dart' as db;
import 'package:after_sales/utils/firebase_number.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef CallStatusCallback = void Function(String status);

class WebRtcService {
  final DatabaseReference _db = FirebaseDatabase.instance.ref();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  String? currentCallId;
  StreamSubscription<DatabaseEvent>? _answerSub;
  StreamSubscription<DatabaseEvent>? _candidateSub;
  StreamSubscription<DatabaseEvent>? _statusSub;

  StreamStateCallback? onRemoteStreamAdded;
  CallStatusCallback? onStatusChanged;
  void Function(RTCPeerConnectionState state)? onPeerConnectionStateChanged;

  // คิวพัก ICE Candidate เพื่อป้องกันการ drop ทิ้งระหว่างรอเซ็ต RemoteDescription
  final List<RTCIceCandidate> _candidateQueue = [];

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  // บังคับให้ SDP แลกเปลี่ยนท่อเสียง 100%
  final Map<String, dynamic> _sdpConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  /// 1. เริ่มต้นโทรออก (Caller)
  Future<String?> startCall({
    required String callerUsername,
    required String callerName,
    required String calleeUsername,
    required String calleeName,
    String? callerPhotoUrl,
    String? calleeRole,
  }) async {
    _candidateQueue.clear();
    final callRef = _db.child('calls').push();
    currentCallId = callRef.key;

    // ขอเปิดไมโครโฟนพร้อมระบบตัดเสียงสะท้อน
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
    }

    _peerConnection = await createPeerConnection(_iceServers);
    _registerPeerEvents();

    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    // ส่ง ICE Candidates ของผู้โทรขึ้น Firebase
    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (currentCallId != null && candidate.candidate != null) {
        callRef.child('callerCandidates').push().set({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // สร้าง SDP Offer พร้อม Constraints
    final offer = await _peerConnection!.createOffer(_sdpConstraints);
    await _peerConnection!.setLocalDescription(offer);

    await callRef.set({
      'callId': currentCallId,
      'callerUsername': callerUsername,
      'callerName': callerName,
      'callerPhotoUrl': callerPhotoUrl ?? '',
      'calleeUsername': calleeUsername,
      'calleeName': calleeName,
      'status': 'calling',
      'offer': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
      'createdAt': DateTime.now().toIso8601String(),
    });

    // ส่ง Push Notification แจ้งเตือนสายเรียกเข้า
    // ส่ง Push Notification แจ้งเตือนสายเรียกเข้า
    try {
      await db.DatabaseHelper.instance.createNotification({
        'user_username': calleeUsername,
        'role': calleeRole ?? '',
        'title': 'สายเรียกเข้า',
        'message': '$callerName กำลังโทรหาคุณ',
        'type': 'INCOMING_CALL',
        'target_id': null,
        'is_read': 0,
        // 🔴 [แก้ไข] แนบข้อมูลสายเรียกเข้าไปกับ push ด้วย เพื่อให้
        // PushNotificationService (ฟัง addForegroundWillDisplayListener /
        // addClickListener) รู้ว่านี่คือแจ้งเตือนสายเรียกเข้าโดยเฉพาะ ไม่ใช่
        // แจ้งเตือนทั่วไป — ใช้พาผู้ใช้เข้าหน้า CallScreen ตรง ๆ ตอนแตะแจ้งเตือน
        'push_data': {
          'type': 'INCOMING_CALL',
          'callId': currentCallId,
          'callerUsername': callerUsername,
          'callerName': callerName,
          'callerPhotoUrl': callerPhotoUrl ?? '',
        },
      });
    } catch (_) {}

    // ดักฟัง Answer จากผู้รับ
    _answerSub = callRef.child('answer').onValue.listen((event) async {
      final data = event.snapshot.value as Map?;
      if (data != null && _peerConnection != null) {
        final currentRemote = await _peerConnection!.getRemoteDescription();
        if (currentRemote == null) {
          final answer = RTCSessionDescription(
            data['sdp']?.toString(),
            data['type']?.toString(),
          );
          await _peerConnection!.setRemoteDescription(answer);
          await _drainCandidateQueue(); // ปล่อย Candidates ที่ต่อคิวอยู่
        }
      }
    });

    // ดักฟัง ICE Candidates จากผู้รับ
    _candidateSub =
        callRef.child('calleeCandidates').onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final candidate = RTCIceCandidate(
          data['candidate']?.toString(),
          data['sdpMid']?.toString(),
          toIntOrNull(data['sdpMLineIndex']),
        );
        _addCandidateSafely(candidate);
      }
    });

    // ดักฟังสเตตัส
    _statusSub = callRef.child('status').onValue.listen((event) {
      final st = event.snapshot.value?.toString();
      if (st != null) {
        onStatusChanged?.call(st);
      }
    });

    // เปิดลำโพงหลัก
    Helper.setSpeakerphoneOn(true);

    return currentCallId;
  }

  /// 2. ตอบรับสายเรียกเข้า (Callee)
  Future<void> answerCall(String callId) async {
    _candidateQueue.clear();
    currentCallId = callId;
    final callRef = _db.child('calls/$callId');

    final snap = await callRef.get();
    if (!snap.exists || snap.value == null) {
      throw Exception('สายนี้ถูกยกเลิกแล้ว');
    }

    // 🍎 [กันบั๊ก iOS] firebase_database ฝั่ง iOS บางครั้งคืน snapshot ของ node
    // แม่ ('calls') กลับมาแทน node ลูกที่ขอ ('calls/$callId') ถ้าเจอกรณีนั้นให้
    // เจาะลงไปที่ callId เองอีกชั้น (ดูคำอธิบายเต็มใน services.dart _byId)
    if (snap.value is! Map) {
      throw Exception('สายนี้ถูกยกเลิกแล้ว');
    }
    var callData = Map<String, dynamic>.from(snap.value as Map);
    if (!callData.containsKey('offer') && callData[callId] is Map) {
      callData = Map<String, dynamic>.from(callData[callId] as Map);
    }
    // 🍎 [กัน crash iOS] ถ้า offer ยังไม่ถูกเขียน (ผู้โทรเขียนไม่เสร็จ/สายถูกยกเลิก
    // กลางคัน) callData['offer'] จะเป็น null — เดิม cast `as Map` ตรง ๆ ทำให้ crash
    // ทันที เปลี่ยนมาเช็กชนิดก่อนแล้วโยน error ที่ caller จัดการได้แทน
    final rawOffer = callData['offer'];
    if (rawOffer is! Map) {
      throw Exception('สายนี้ยังไม่พร้อมหรือถูกยกเลิกแล้ว');
    }
    final offerData = Map<String, dynamic>.from(rawOffer);

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = true;
    }

    _peerConnection = await createPeerConnection(_iceServers);
    _registerPeerEvents();

    for (final track in _localStream!.getAudioTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        callRef.child('calleeCandidates').push().set({
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    // เซ็ต Offer แล้วปล่อยคิว Candidates
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], offerData['type']),
    );
    await _drainCandidateQueue();

    // สร้าง Answer พร้อม Constraints
    final answer = await _peerConnection!.createAnswer(_sdpConstraints);
    await _peerConnection!.setLocalDescription(answer);

    await callRef.update({
      'answer': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
      'status': 'connected',
    });

    // ดักฟัง ICE Candidates จากผู้โทร
    _candidateSub =
        callRef.child('callerCandidates').onChildAdded.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data != null) {
        final candidate = RTCIceCandidate(
          data['candidate']?.toString(),
          data['sdpMid']?.toString(),
          toIntOrNull(data['sdpMLineIndex']),
        );
        _addCandidateSafely(candidate);
      }
    });

    _statusSub = callRef.child('status').onValue.listen((event) {
      final st = event.snapshot.value?.toString();
      if (st != null) {
        onStatusChanged?.call(st);
      }
    });

    // เปิดลำโพงหลัก
    Helper.setSpeakerphoneOn(true);
  }

  void _addCandidateSafely(RTCIceCandidate candidate) async {
    if (_peerConnection == null) return;
    final remoteDesc = await _peerConnection!.getRemoteDescription();
    if (remoteDesc != null) {
      await _peerConnection!.addCandidate(candidate);
    } else {
      _candidateQueue.add(candidate);
    }
  }

  Future<void> _drainCandidateQueue() async {
    for (final c in _candidateQueue) {
      await _peerConnection?.addCandidate(c);
    }
    _candidateQueue.clear();
  }

  /// 3. ปฏิเสธสายเรียกเข้า
  Future<void> rejectCall(String callId) async {
    await _db.child('calls/$callId').update({'status': 'rejected'});
    await endCall();
  }

  /// 4. วางสายและคืนทรัพยากร
  Future<void> endCall() async {
    try {
      if (currentCallId != null) {
        await _db.child('calls/$currentCallId').update({'status': 'ended'});
        final idToDelete = currentCallId;
        Future.delayed(const Duration(seconds: 3), () {
          _db.child('calls/$idToDelete').remove();
        });
      }
    } catch (_) {}

    await _answerSub?.cancel();
    await _candidateSub?.cancel();
    await _statusSub?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    await _localStream?.dispose();
    await _remoteStream?.dispose();
    await _peerConnection?.close();

    _candidateQueue.clear();
    _localStream = null;
    _remoteStream = null;
    _peerConnection = null;
    currentCallId = null;
  }

  /// เปิด/ปิดไมค์
  void toggleMute(bool isMuted) {
    if (_localStream != null && _localStream!.getAudioTracks().isNotEmpty) {
      _localStream!.getAudioTracks()[0].enabled = !isMuted;
    }
  }

  /// สลับลำโพงนอก / ลำโพงแนบหู
  void setSpeakerphone(bool enable) {
    Helper.setSpeakerphoneOn(enable);
  }

  void _registerPeerEvents() {
    _peerConnection?.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        for (final track in _remoteStream!.getAudioTracks()) {
          track.enabled = true;
        }
        onRemoteStreamAdded?.call(event.streams[0]);
      }
    };

    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint('📞 [onConnectionState] $state');
      onPeerConnectionStateChanged?.call(state);
    };

    _peerConnection?.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint('📞 [onIceConnectionState] $state');
    };
  }

  /// ดักฟังสายเรียกเข้าแบบสแตนด์บาย
  static StreamSubscription<DatabaseEvent> listenIncomingCall({
    required String myUsername,
    required Function(Map<String, dynamic> callData) onIncomingCall,
  }) {
    return FirebaseDatabase.instance
        .ref('calls')
        .orderByChild('calleeUsername')
        .equalTo(myUsername)
        .onChildAdded
        .listen((event) {
      final map = event.snapshot.value;
      if (map is Map) {
        // 🍎 [แก้บัค iOS] ใช้ normalizeRow() แทน Map<String,dynamic>.from() ตรง ๆ
        // ให้สอดคล้องกับจุดอื่นในไฟล์นี้ (ดูคำอธิบายเต็มใน services.dart _byId)
        final data = db.DatabaseHelper.normalizeRow(map);
        if (data['status'] == 'calling') {
          onIncomingCall(data);
        }
      }
    });
  }
}