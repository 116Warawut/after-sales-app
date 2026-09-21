import React, { useEffect, useState } from "react";
import { Phone, PhoneOff, Mic, MicOff, User } from "lucide-react";

function formatDuration(sec) {
  const m = Math.floor(sec / 60)
    .toString()
    .padStart(2, "0");
  const s = (sec % 60).toString().padStart(2, "0");
  return `${m}:${s}`;
}

function Avatar({ name, photoUrl }) {
  if (photoUrl) {
    return <img src={photoUrl} alt={name} className="w-16 h-16 rounded-full object-cover border border-white/20" />;
  }
  return (
    <div className="w-16 h-16 rounded-full bg-white/10 flex items-center justify-center text-white">
      <User size={28} />
    </div>
  );
}

/** แจ้งเตือนสั้น ๆ ตอนโทรไม่สำเร็จ/อีกฝ่ายปฏิเสธสาย — หายเองใน 4 วิ */
function ErrorToast({ message }) {
  const [visible, setVisible] = useState(!!message);
  useEffect(() => {
    if (!message) return undefined;
    setVisible(true);
    const t = setTimeout(() => setVisible(false), 4000);
    return () => clearTimeout(t);
  }, [message]);

  if (!message || !visible) return null;
  return (
    <div className="fixed bottom-6 right-6 z-[70] bg-slate-800 text-white text-sm px-4 py-2.5 rounded-xl shadow-lg">
      {message}
    </div>
  );
}

export default function CallOverlay({ call }) {
  const { phase, peerName, peerPhotoUrl, muted, durationSec, errorMessage, acceptIncomingCall, declineIncomingCall, hangUp, toggleMute } = call;

  if (phase === "idle") {
    return <ErrorToast message={errorMessage} />;
  }

  // 📞 สายเรียกเข้า — การ์ดกลางจอ กดปิดข้างนอกไม่ได้ (ต้องรับ/ปฏิเสธเท่านั้น)
  if (phase === "incoming") {
    return (
      <div className="fixed inset-0 z-[70] flex items-center justify-center p-4">
        <div className="absolute inset-0 bg-slate-900/50" />
        <div className="relative bg-slate-800 text-white rounded-2xl shadow-2xl w-full max-w-xs p-6 flex flex-col items-center gap-4">
          <p className="text-xs text-slate-300">สายเรียกเข้า</p>
          <Avatar name={peerName} photoUrl={peerPhotoUrl} />
          <p className="text-base font-semibold">{peerName}</p>
          <div className="flex items-center gap-6 mt-2">
            <button
              onClick={declineIncomingCall}
              title="ปฏิเสธ"
              className="w-14 h-14 rounded-full bg-red-500 hover:bg-red-600 flex items-center justify-center transition-colors"
            >
              <PhoneOff size={22} />
            </button>
            <button
              onClick={acceptIncomingCall}
              title="รับสาย"
              className="w-14 h-14 rounded-full bg-green-500 hover:bg-green-600 flex items-center justify-center transition-colors"
            >
              <Phone size={22} />
            </button>
          </div>
        </div>
      </div>
    );
  }

  // 📤 กำลังโทรออก / 🔗 เชื่อมต่อแล้ว — แถบลอยมุมล่างขวา ไม่บังการทำงานหน้าอื่น
  const isConnected = phase === "connected";
  return (
    <div className="fixed bottom-6 right-6 z-[70] bg-slate-800 text-white rounded-2xl shadow-2xl w-72 p-4 flex items-center gap-3">
      <Avatar name={peerName} photoUrl={peerPhotoUrl} />
      <div className="min-w-0 flex-1">
        <p className="text-sm font-semibold truncate">{peerName}</p>
        <p className="text-xs text-slate-300">{isConnected ? formatDuration(durationSec) : "กำลังโทรออก..."}</p>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        {isConnected ? (
          <button
            onClick={toggleMute}
            title={muted ? "เปิดไมค์" : "ปิดไมค์"}
            className={`w-9 h-9 rounded-full flex items-center justify-center transition-colors ${
              muted ? "bg-white/20 text-white" : "bg-white/10 text-slate-200 hover:bg-white/20"
            }`}
          >
            {muted ? <MicOff size={16} /> : <Mic size={16} />}
          </button>
        ) : null}
        <button
          onClick={hangUp}
          title="วางสาย"
          className="w-9 h-9 rounded-full bg-red-500 hover:bg-red-600 flex items-center justify-center transition-colors"
        >
          <PhoneOff size={16} />
        </button>
      </div>
    </div>
  );
}
