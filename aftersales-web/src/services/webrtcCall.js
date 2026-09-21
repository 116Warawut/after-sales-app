// =============================================================================
// 📞 WebRtcCallService — ระบบโทรของฝั่งเว็บแอดมิน (เสียงอย่างเดียว)
// =============================================================================
// ทำงานคู่กับ webrtc_service.dart ฝั่ง Flutter — ใช้ Firebase Realtime Database
// node 'calls' เดียวกัน โครงสร้างข้อมูลเดียวกันทุกฟิลด์ (callerUsername,
// calleeUsername, offer/answer เป็น {sdp, type}, callerCandidates/
// calleeCandidates, status) เพื่อให้เว็บกับแอปคุยกันได้โดยไม่ต้องแก้ฝั่งแอปเลย
//
// ต่างจากฝั่งแอปแค่ 2 จุด:
//   1. ใช้ RTCPeerConnection ของเบราว์เซอร์ตรง ๆ (ไม่ผ่าน flutter_webrtc)
//   2. ไม่มีลำโพง/เปิดหน้าจอปลุก (setSpeakerphoneOn ฯลฯ) เพราะเป็นเว็บ
// =============================================================================
import { ref, push, set, update, get, remove, onValue, onChildAdded, query, orderByChild, equalTo } from "firebase/database";
import { db } from "../firebase";

// สาย STUN เดียวกับที่ฝั่งแอปใช้ (ไม่มี TURN — โทรตรงแบบ P2P เท่านั้น)
const ICE_SERVERS = {
  iceServers: [
    { urls: "stun:stun.l.google.com:19302" },
    { urls: "stun:stun1.l.google.com:19302" },
    { urls: "stun:stun2.l.google.com:19302" },
    { urls: "stun:stun3.l.google.com:19302" },
    { urls: "stun:stun4.l.google.com:19302" },
  ],
};

export class WebRtcCallService {
  constructor() {
    this.peerConnection = null;
    this.localStream = null;
    this.currentCallId = null;

    this._candidateQueue = [];
    this._answerUnsub = null;
    this._candidateUnsub = null;
    this._statusUnsub = null;

    // ผูก callback จากภายนอก (useCallManager) เข้ามาตรงนี้
    this.onRemoteStream = null; // (MediaStream) => void
    this.onStatusChange = null; // (status: string) => void
  }

  _registerPeerEvents() {
    this.peerConnection.ontrack = (event) => {
      const stream = event.streams?.[0];
      if (stream) this.onRemoteStream?.(stream);
    };
  }

  async _openMic() {
    this.localStream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true },
      video: false,
    });
    return this.localStream;
  }

  async _addCandidateSafely(candidate) {
    if (!this.peerConnection) return;
    const remoteDesc = this.peerConnection.remoteDescription;
    if (remoteDesc) {
      await this.peerConnection.addIceCandidate(candidate);
    } else {
      this._candidateQueue.push(candidate);
    }
  }

  async _drainCandidateQueue() {
    for (const c of this._candidateQueue) {
      await this.peerConnection.addIceCandidate(c);
    }
    this._candidateQueue = [];
  }

  /** 1. เริ่มโทรออก (แอดมินเป็นผู้โทร) */
  async startCall({ callerUsername, callerName, calleeUsername, calleeName, callerPhotoUrl }) {
    this._candidateQueue = [];
    const callRef = push(ref(db, "calls"));
    this.currentCallId = callRef.key;

    await this._openMic();

    this.peerConnection = new RTCPeerConnection(ICE_SERVERS);
    this._registerPeerEvents();
    this.localStream.getAudioTracks().forEach((track) => this.peerConnection.addTrack(track, this.localStream));

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        push(ref(db, `calls/${this.currentCallId}/callerCandidates`), event.candidate.toJSON());
      }
    };

    const offer = await this.peerConnection.createOffer({ offerToReceiveAudio: true, offerToReceiveVideo: false });
    await this.peerConnection.setLocalDescription(offer);

    await set(callRef, {
      callId: this.currentCallId,
      callerUsername,
      callerName,
      callerPhotoUrl: callerPhotoUrl || "",
      calleeUsername,
      calleeName,
      status: "calling",
      offer: { sdp: offer.sdp, type: offer.type },
      createdAt: new Date().toISOString(),
    });

    // 🔔 เขียนแจ้งเตือนสายเรียกเข้า — รูปแบบเดียวกับที่ createNotification ของ
    // Flutter startCall() เขียนไว้ (type: INCOMING_CALL + push_data) เผื่อฝั่ง
    // backend push (OneSignal ผ่าน Cloudflare Worker) เอาไปยิง push ปลุกเครื่อง
    // ที่ปิดแอปอยู่ได้เหมือนกับตอนแอปโทรหากันเอง
    try {
      await push(ref(db, "notifications"), {
        user_username: calleeUsername,
        role: "",
        title: "สายเรียกเข้า",
        message: `${callerName} กำลังโทรหาคุณ`,
        type: "INCOMING_CALL",
        target_id: null,
        is_read: 0,
        created_at: new Date().toISOString(),
        push_data: {
          type: "INCOMING_CALL",
          callId: this.currentCallId,
          callerUsername,
          callerName,
          callerPhotoUrl: callerPhotoUrl || "",
        },
      });
    } catch (_) {
      // เงียบไว้ — พลาดแค่ push แจ้งเตือน ไม่ใช่ตัวสายจริง ไม่ต้องบล็อกการโทร
    }

    this._answerUnsub = onValue(ref(db, `calls/${this.currentCallId}/answer`), async (snap) => {
      const data = snap.val();
      if (data && this.peerConnection && !this.peerConnection.remoteDescription) {
        await this.peerConnection.setRemoteDescription(new RTCSessionDescription(data));
        await this._drainCandidateQueue();
      }
    });

    this._candidateUnsub = onChildAdded(ref(db, `calls/${this.currentCallId}/calleeCandidates`), (snap) => {
      const data = snap.val();
      if (data) this._addCandidateSafely(new RTCIceCandidate(data));
    });

    this._statusUnsub = onValue(ref(db, `calls/${this.currentCallId}/status`), (snap) => {
      const status = snap.val();
      if (status) this.onStatusChange?.(status);
    });

    return this.currentCallId;
  }

  /** 2. รับสายเรียกเข้า (มีคนโทรมาหาแอดมิน) */
  async answerCall(callId) {
    this._candidateQueue = [];
    this.currentCallId = callId;
    const callRef = ref(db, `calls/${callId}`);

    const snap = await get(callRef);
    if (!snap.exists() || !snap.val()) {
      throw new Error("สายนี้ถูกยกเลิกแล้ว");
    }
    const callData = snap.val();
    const offerData = callData.offer;

    await this._openMic();

    this.peerConnection = new RTCPeerConnection(ICE_SERVERS);
    this._registerPeerEvents();
    this.localStream.getAudioTracks().forEach((track) => this.peerConnection.addTrack(track, this.localStream));

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        push(ref(db, `calls/${callId}/calleeCandidates`), event.candidate.toJSON());
      }
    };

    await this.peerConnection.setRemoteDescription(new RTCSessionDescription(offerData));
    await this._drainCandidateQueue();

    const answer = await this.peerConnection.createAnswer({ offerToReceiveAudio: true, offerToReceiveVideo: false });
    await this.peerConnection.setLocalDescription(answer);

    await update(callRef, {
      answer: { sdp: answer.sdp, type: answer.type },
      status: "connected",
    });

    this._candidateUnsub = onChildAdded(ref(db, `calls/${callId}/callerCandidates`), (snap2) => {
      const data = snap2.val();
      if (data) this._addCandidateSafely(new RTCIceCandidate(data));
    });

    this._statusUnsub = onValue(ref(db, `calls/${callId}/status`), (snap2) => {
      const status = snap2.val();
      if (status) this.onStatusChange?.(status);
    });
  }

  /** 3. ปฏิเสธสายเรียกเข้า */
  async rejectCall(callId) {
    await update(ref(db, `calls/${callId}`), { status: "rejected" });
    await this.endCall();
  }

  /** 4. วางสาย + คืนทรัพยากรทั้งหมด */
  async endCall() {
    try {
      if (this.currentCallId) {
        await update(ref(db, `calls/${this.currentCallId}`), { status: "ended" });
        const idToDelete = this.currentCallId;
        setTimeout(() => {
          remove(ref(db, `calls/${idToDelete}`)).catch(() => {});
        }, 3000);
      }
    } catch (_) {
      // เงียบไว้ — วางสายให้สำเร็จก่อน ไม่ต้องบล็อกจากปัญหาลบข้อมูลปลาย
    }

    // onValue/onChildAdded ของ modular SDK คืน "ฟังก์ชันยกเลิกฟัง" มาตรง ๆ —
    // เรียกมันตรง ๆ เพื่อเลิกฟัง แทนการใช้ off() แบบ namespaced API เดิม
    this._answerUnsub?.();
    this._candidateUnsub?.();
    this._statusUnsub?.();
    this._answerUnsub = null;
    this._candidateUnsub = null;
    this._statusUnsub = null;

    this.localStream?.getTracks().forEach((t) => t.stop());
    this.peerConnection?.close();

    this._candidateQueue = [];
    this.localStream = null;
    this.peerConnection = null;
    this.currentCallId = null;
  }

  /** เปิด/ปิดไมค์ */
  toggleMute(isMuted) {
    if (this.localStream) {
      this.localStream.getAudioTracks().forEach((track) => {
        track.enabled = !isMuted;
      });
    }
  }

  /** ดักฟังสายเรียกเข้าแบบสแตนด์บาย — คืนฟังก์ชันไว้ยกเลิกการฟัง */
  static listenIncomingCall({ myUsername, onIncomingCall }) {
    const callsQuery = query(ref(db, "calls"), orderByChild("calleeUsername"), equalTo(myUsername));
    return onChildAdded(callsQuery, (snap) => {
      const data = snap.val();
      if (data && data.status === "calling") {
        onIncomingCall({ ...data, callId: data.callId || snap.key });
      }
    });
  }
}
