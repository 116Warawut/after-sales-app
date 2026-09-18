import React, { useEffect, useRef, useState } from "react";
import { Bell, X, ChevronRight } from "lucide-react";

// ป้ายชื่อประเภทแจ้งเตือนแบบย่อ ใช้ตัวเดียวกับที่ NotificationsPage.jsx ใช้อยู่
// (คัดลอกมาเฉพาะที่จำเป็นสำหรับโชว์ในการ์ด toast เล็กๆ — ไม่ได้ import ข้ามหน้า
// เพราะไฟล์นั้นไม่ได้ export ออกมา และรายการนี้ไม่ได้เปลี่ยนบ่อย)
const TYPE_LABEL = {
  REPAIR_CREATED: "งานซ่อมใหม่",
  REPAIR_ASSIGNED: "มอบหมายช่าง",
  REPAIR_IN_PROGRESS: "เริ่มดำเนินการซ่อม",
  REPAIR_DONE: "รายงานการซ่อม",
  REPAIR_CANCELLED: "ยกเลิกงานซ่อม",
  PART_REQUEST: "คำขอเบิกอะไหล่",
  PAYMENT_RECEIVED: "ได้รับการชำระเงิน",
  INVOICE_CREATED: "ใบแจ้งหนี้",
  INCOMING_CALL: "สายเรียกเข้า",
  OVERDUE: "งานเกินกำหนด",
  JOB: "งานซ่อม",
  CHAT: "ข้อความใหม่",
  LOW_STOCK: "อะไหล่ใกล้หมด",
  PAYMENT_OVERDUE: "ใบแจ้งหนี้ค้างชำระ",
  WARRANTY_EXPIRING: "ประกันใกล้หมดอายุ",
  STALE_JOB: "งานค้างสถานะนาน",
  DAILY_DIGEST: "สรุปกิจกรรมประจำวัน",
};

// หน้าปลายทางเวลากดที่ toast — คัดลอกแนวคิดเดียวกับ targetLinkFor() ใน
// NotificationsPage.jsx (แต่ละประเภทอ้างอิง id ของคนละอย่างกัน งานซ่อม/อะไหล่/
// เครื่องจักร ไม่ใช่ id แบบเดียวกันหมด)
function linkFor(n) {
  if (n.type === "CHAT") return { page: "chat", query: n.target_id != null ? String(n.target_id) : undefined };
  if (!n.target_id) return { page: "notifications" };
  if (n.type === "LOW_STOCK") return { page: "parts", query: String(n.target_id) };
  if (n.type === "PAYMENT_OVERDUE") return { page: "finance" };
  if (n.type === "WARRANTY_EXPIRING") return { page: "customers" };
  return { page: "jobs", query: String(n.target_id) };
}

const AUTO_DISMISS_MS = 6000;
const MAX_VISIBLE = 4;

function ToastCard({ toast, onClose, onNavigate }) {
  useEffect(() => {
    const t = setTimeout(onClose, AUTO_DISMISS_MS);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const link = linkFor(toast);

  return (
    <div className="w-80 bg-white rounded-2xl border border-slate-100 shadow-xl p-4 pointer-events-auto animate-[toast-in_0.2s_ease-out]">
      <div className="flex items-start gap-3">
        <div className="w-9 h-9 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center shrink-0">
          <Bell size={16} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center justify-between gap-2">
            <span className="text-[11px] font-medium text-blue-600">{TYPE_LABEL[toast.type] || "แจ้งเตือน"}</span>
            <button onClick={onClose} className="text-slate-300 hover:text-slate-500 shrink-0">
              <X size={14} />
            </button>
          </div>
          <p className="text-sm font-semibold text-slate-800 mt-0.5 truncate">{toast.title || "แจ้งเตือนใหม่"}</p>
          {toast.message ? <p className="text-xs text-slate-500 mt-0.5 line-clamp-2">{toast.message}</p> : null}
          <button
            onClick={() => {
              onNavigate?.(link.page, link.query ? { query: link.query } : undefined);
              onClose();
            }}
            className="flex items-center gap-1 text-xs text-blue-600 font-medium mt-2 hover:text-blue-700"
          >
            ดูรายละเอียด
            <ChevronRight size={12} />
          </button>
        </div>
      </div>
    </div>
  );
}

// 🆕 แจ้งเตือนแบบ popup มุมขวาล่าง (toast) โผล่ขึ้นมาเองทุกครั้งที่มีแจ้งเตือน
// ใหม่เข้ามาสำหรับแอดมินที่ล็อกอินอยู่ ไม่ว่าจะอยู่หน้าไหนของเว็บก็เห็น (mount
// ไว้ที่ AuthenticatedShell ระดับบนสุดใน App.jsx ไม่ใช่ในหน้าใดหน้าหนึ่ง) —
// หายไปเองใน 6 วินาที กดปิดเองได้ หรือกด "ดูรายละเอียด" เพื่อไปหน้าที่เกี่ยวข้อง
//
// วิธีตรวจจับ "แจ้งเตือนใหม่": เก็บ id ที่เคยเห็นแล้วไว้ใน ref พอโหลดครั้งแรก
// (ตอน component mount) จะขึ้นทะเบียน id ที่มีอยู่ทั้งหมดไว้เฉยๆ ไม่ toast
// ย้อนหลัง (ไม่งั้นพอเปิดเว็บมาแจ้งเตือนเก่าที่ยังไม่อ่านค้างอยู่ 20 อันจะเด้ง
// รัวๆ ทันที) — พอ useDbList อัปเดตข้อมูลใหม่มา (realtime) ค่อยเทียบหา id ที่ยัง
// ไม่เคยเห็น แล้ว toast เฉพาะอันนั้น
export default function NotificationToasts({ notifications, currentUsername, onNavigate, showToastPopup = true, showDesktopPopup = true }) {
  const seenIds = useRef(null);
  const [toasts, setToasts] = useState([]);

  // 🆕 ขอสิทธิ์แจ้งเตือนระดับ OS (Web Notification API) ครั้งเดียวตอน mount —
  // ต้องขอสิทธิ์ก่อนถึงจะยิงป๊อปอัประดับเครื่องได้ (เบราว์เซอร์จะเด้งถามผู้ใช้
  // เอง ถ้าเคยกดอนุญาต/ปฏิเสธไปแล้วจะไม่ถามซ้ำ) — ขอไว้ก่อนเผื่อผู้ใช้เปิด
  // สวิตช์ "แจ้งเตือนนอกเว็บ" ทีหลัง จะได้ไม่ต้องรอขอสิทธิ์ใหม่ตอนนั้น
  useEffect(() => {
    if (typeof Notification !== "undefined" && Notification.permission === "default") {
      Notification.requestPermission();
    }
  }, []);

  useEffect(() => {
    const mine = notifications.filter((n) => n.user_username === currentUsername);

    if (seenIds.current === null) {
      // รอบแรก (mount) แค่จดจำ id ที่มีอยู่แล้วทั้งหมด ไม่ toast ย้อนหลัง
      seenIds.current = new Set(mine.map((n) => String(n.id)));
      return;
    }

    const fresh = mine.filter((n) => !seenIds.current.has(String(n.id)) && !n.is_read);
    if (fresh.length === 0) return;

    fresh.forEach((n) => seenIds.current.add(String(n.id)));

    // 🆕 2 สวิตช์แยกจากหน้าตั้งค่า > การแจ้งเตือน > ช่องทางการแจ้งเตือน:
    // showToastPopup คุม toast การ์ดในหน้าเว็บ, showDesktopPopup คุมป๊อปอัป
    // ระดับ OS แยกกันอิสระ เปิด/ปิดได้คนละอันไม่ผูกกัน
    if (showToastPopup) {
      setToasts((prev) => [...prev, ...fresh].slice(-MAX_VISIBLE));
    }

    // นอกจาก toast ในหน้าเว็บแล้ว ยิงป๊อปอัประดับ OS ด้วย (มุมขวาล่างของจอ
    // เครื่อง ไม่ใช่แค่ในเว็บ) เห็นได้แม้กำลังใช้เว็บ/แอปอื่นอยู่ ขอแค่เบราว์เซอร์
    // ยังเปิดอยู่เบื้องหลัง (ย่อหน้าต่างไว้ หรือสลับไปแท็บ/โปรแกรมอื่นก็เห็น) —
    // ข้อจำกัด: ถ้าปิดเบราว์เซอร์ไปเลยจะไม่เห็น ต้องทำ Push แบบเต็มรูปแบบ
    // (Service Worker + ลงทะเบียนกับ OneSignal ฝั่งเว็บ) ถึงจะได้แบบนั้น
    if (showDesktopPopup && typeof Notification !== "undefined" && Notification.permission === "granted") {
      fresh.forEach((n) => {
        const osNotif = new Notification(n.title || "แจ้งเตือนใหม่", {
          body: n.message || "",
          tag: String(n.id),
        });
        osNotif.onclick = () => {
          window.focus();
          const link = linkFor(n);
          onNavigate?.(link.page, link.query ? { query: link.query } : undefined);
          osNotif.close();
        };
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [notifications, currentUsername, showToastPopup, showDesktopPopup]);

  const dismiss = (id) => setToasts((prev) => prev.filter((t) => t.id !== id));

  if (toasts.length === 0) return null;

  return (
    <div className="fixed bottom-5 right-5 z-50 flex flex-col gap-3 pointer-events-none">
      {toasts.map((t) => (
        <ToastCard key={t.id} toast={t} onClose={() => dismiss(t.id)} onNavigate={onNavigate} />
      ))}
    </div>
  );
}
