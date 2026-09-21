import React, { createContext, useContext } from "react";
import useCallManager from "../hooks/useCallManager";
import CallOverlay from "../components/CallOverlay";

const CallContext = createContext(null);

/** ครอบไว้ใน AuthenticatedShell เดียว ให้ทุกหน้าเรียก useCall() แล้วสั่งโทรได้เลย */
export function CallProvider({ admin, children }) {
  const call = useCallManager(admin?.username, admin?.admin_name);

  return (
    <CallContext.Provider value={call}>
      {children}
      {/* <audio> ที่ซ่อนไว้สำหรับเล่นเสียงปลายสาย ต้องอยู่ใน DOM ตลอดไม่ว่าจะ
          อยู่หน้าไหน ไม่งั้นเสียงจะหายตอนสลับหน้าระหว่างคุยสายอยู่ */}
      <audio ref={call.audioRef} autoPlay style={{ display: "none" }} />
      <CallOverlay call={call} />
    </CallContext.Provider>
  );
}

/** ใช้ในหน้าไหนก็ได้: const { callPerson } = useCall(); callPerson({ username, name, photoUrl }) */
export function useCall() {
  const ctx = useContext(CallContext);
  if (!ctx) {
    throw new Error("useCall ต้องถูกเรียกภายใน <CallProvider> เท่านั้น");
  }
  return ctx;
}
