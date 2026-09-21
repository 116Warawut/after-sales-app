import { useCallback, useEffect, useRef, useState } from "react";
import { WebRtcCallService } from "../services/webrtcCall";

// ==========================================================================
// 📞 useCallManager — จัดการ state ทั้งหมดของการโทร (โทรออก/รับสาย/วางสาย)
// ให้หน้าไหนก็เรียกใช้ได้ผ่าน CallContext (ดู contexts/CallContext.jsx)
// ==========================================================================
const INITIAL_STATE = {
  phase: "idle", // idle | outgoing | incoming | connected
  callId: null,
  peerUsername: null,
  peerName: null,
  peerPhotoUrl: null,
  muted: false,
  durationSec: 0,
  errorMessage: null,
};

export default function useCallManager(myUsername, myName) {
  const [state, setState] = useState(INITIAL_STATE);
  const serviceRef = useRef(null);
  const audioRef = useRef(null); // <audio> element ที่จะเล่นเสียงปลายสาย
  const timerRef = useRef(null);

  if (!serviceRef.current) {
    serviceRef.current = new WebRtcCallService();
  }

  const clearTimer = useCallback(() => {
    if (timerRef.current) {
      clearInterval(timerRef.current);
      timerRef.current = null;
    }
  }, []);

  const resetToIdle = useCallback((errorMessage = null) => {
    clearTimer();
    setState({ ...INITIAL_STATE, errorMessage });
  }, [clearTimer]);

  // 🔊 ผูกกระแสเสียงปลายสายเข้ากับ <audio> element ที่ซ่อนไว้ (audioRef)
  const wireServiceCallbacks = useCallback((service) => {
    service.onRemoteStream = (stream) => {
      if (audioRef.current) {
        audioRef.current.srcObject = stream;
        audioRef.current.play().catch(() => {});
      }
    };
    service.onStatusChange = (status) => {
      if (status === "connected") {
        setState((prev) => (prev.phase === "connected" ? prev : { ...prev, phase: "connected" }));
      } else if (status === "rejected") {
        resetToIdle("อีกฝ่ายปฏิเสธสาย");
      } else if (status === "ended") {
        resetToIdle();
      }
    };
  }, [resetToIdle]);

  // ⏱️ นับเวลาสนทนาตอนสถานะเป็น "เชื่อมต่อแล้ว"
  useEffect(() => {
    if (state.phase === "connected") {
      clearTimer();
      timerRef.current = setInterval(() => {
        setState((prev) => (prev.phase === "connected" ? { ...prev, durationSec: prev.durationSec + 1 } : prev));
      }, 1000);
    } else {
      clearTimer();
    }
    return clearTimer;
  }, [state.phase, clearTimer]);

  // 📥 ดักฟังสายเรียกเข้าตลอดเวลาที่ล็อกอินอยู่
  useEffect(() => {
    if (!myUsername) return undefined;
    const service = serviceRef.current;
    const unsubscribe = WebRtcCallService.listenIncomingCall({
      myUsername,
      onIncomingCall: (callData) => {
        setState((prev) => {
          // ถ้ากำลังโทร/คุยสายอื่นอยู่แล้ว ปฏิเสธสายใหม่ทันที (ยังไม่รองรับสายซ้อน)
          if (prev.phase !== "idle") {
            service.rejectCall(callData.callId).catch(() => {});
            return prev;
          }
          return {
            ...INITIAL_STATE,
            phase: "incoming",
            callId: callData.callId,
            peerUsername: callData.callerUsername,
            peerName: callData.callerName || "สายเรียกเข้า",
            peerPhotoUrl: callData.callerPhotoUrl || null,
          };
        });
      },
    });
    return () => unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [myUsername]);

  const callPerson = useCallback(
    async ({ username, name, photoUrl }) => {
      if (!username || state.phase !== "idle") return;
      const service = serviceRef.current;
      wireServiceCallbacks(service);
      setState({
        ...INITIAL_STATE,
        phase: "outgoing",
        peerUsername: username,
        peerName: name || username,
        peerPhotoUrl: photoUrl || null,
      });
      try {
        const callId = await service.startCall({
          callerUsername: myUsername,
          callerName: myName || myUsername,
          calleeUsername: username,
          calleeName: name || username,
        });
        setState((prev) => (prev.phase === "outgoing" ? { ...prev, callId } : prev));
      } catch (err) {
        console.error("[useCallManager] startCall failed:", err);
        resetToIdle(err?.message?.includes("Permission") ? "กรุณาอนุญาตให้ใช้ไมโครโฟน" : "โทรไม่สำเร็จ ลองใหม่อีกครั้ง");
      }
    },
    [myUsername, myName, state.phase, wireServiceCallbacks, resetToIdle]
  );

  const acceptIncomingCall = useCallback(async () => {
    if (state.phase !== "incoming" || !state.callId) return;
    const service = serviceRef.current;
    wireServiceCallbacks(service);
    try {
      await service.answerCall(state.callId);
      setState((prev) => ({ ...prev, phase: "connected" }));
    } catch (err) {
      console.error("[useCallManager] answerCall failed:", err);
      resetToIdle("รับสายไม่สำเร็จ");
    }
  }, [state.phase, state.callId, wireServiceCallbacks, resetToIdle]);

  const declineIncomingCall = useCallback(async () => {
    if (state.phase !== "incoming" || !state.callId) return;
    try {
      await serviceRef.current.rejectCall(state.callId);
    } catch (_) {
      // เงียบไว้
    }
    resetToIdle();
  }, [state.phase, state.callId, resetToIdle]);

  const hangUp = useCallback(async () => {
    try {
      await serviceRef.current.endCall();
    } catch (_) {
      // เงียบไว้
    }
    resetToIdle();
  }, [resetToIdle]);

  const toggleMute = useCallback(() => {
    setState((prev) => {
      const nextMuted = !prev.muted;
      serviceRef.current.toggleMute(nextMuted);
      return { ...prev, muted: nextMuted };
    });
  }, []);

  return {
    ...state,
    audioRef,
    callPerson,
    acceptIncomingCall,
    declineIncomingCall,
    hangUp,
    toggleMute,
  };
}
