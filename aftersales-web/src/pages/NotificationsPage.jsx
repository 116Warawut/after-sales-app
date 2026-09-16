import React, { useState, useEffect, useRef } from "react";
import { CheckCheck, Bell, Trash2, MessageSquare, ChevronRight } from "lucide-react";
import { Card, EmptyState, ConfirmDialog, Modal, Pagination } from "../components/ui";
import useDbList from "../hooks/useDbList";
import useWebSettings from "../hooks/useWebSettings";
import {
  markAllNotificationsAsRead,
  updateRow,
  deleteRow,
  deleteAllNotifications,
  markNotificationsRead,
  deleteNotifications,
} from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";

// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: จุดกลมเล็ก ๆ หน้าแต่ละแจ้งเตือน — น้ำเงิน (bg-blue-500)
// = ยังไม่อ่าน, เทา (bg-slate-200) = อ่านแล้ว
// 🔴 [แก้ไข] ทำใหม่ทั้งหมด 2 จุดตามที่ขอ:
// 1) แจ้งเตือนที่ "สำคัญ" (ทุกประเภทยกเว้นข้อความแชท — งานซ่อมใหม่, มอบหมายช่าง,
//    ช่างส่งรายงานซ่อม, งานเกินกำหนด ฯลฯ) เปลี่ยนจาก expand แบบเดิม (คลิกแล้ว
//    กางออกในหน้าเดียวกัน) เป็น popup modal เต็มรูปแบบ พร้อมปุ่มลิงก์ "ไปที่งาน
//    นี้" ถ้าแจ้งเตือนนั้นผูกกับงานซ่อม (มี target_id)
// 2) แจ้งเตือน "ข้อความใหม่" (type: CHAT) ไม่ทำ popup ตามที่ขอ — รวบเป็นแถว
//    เดียวต่อ "งาน" ที่มีข้อความเข้ามา (ไม่แยกทีละข้อความ) กันไม่ให้รายการยาว
//    เป็นหางว่าว โชว่ตัวอย่างข้อความล่าสุด + จำนวนข้อความที่ยังไม่อ่านในกลุ่มนั้น
//    กดแล้วมาร์กอ่านทั้งกลุ่มพร้อมพาไปที่ห้องแชทของงานนั้นเลย
// ---------------------------------------------------------------------------

// ป้ายภาษาไทยของแต่ละประเภทแจ้งเตือน (type ตรงกับที่ทั้งเว็บและแอปมือถือใช้
// จริงในตาราง notifications — เช็กกับ lib/services.dart แล้ว)
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
  // 🔔 [ใหม่] 2 ประเภทใหม่ — อะไหล่ใกล้หมดสต็อก และใบแจ้งหนี้ค้างชำระ
  LOW_STOCK: "อะไหล่ใกล้หมด",
  PAYMENT_OVERDUE: "ใบแจ้งหนี้ค้างชำระ",
  // 🔔 [ใหม่] อีก 3 ประเภท — ประกันใกล้หมด, งานค้างสถานะนาน, สรุปกิจกรรมประจำวัน
  WARRANTY_EXPIRING: "ประกันใกล้หมด",
  STALE_JOB: "งานค้างสถานะนาน",
  DAILY_DIGEST: "สรุปกิจกรรมประจำวัน",
};

function formatDateTime(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "";
  // 🔴 [แก้ไข] ตัดตัวเลือกปี ค.ศ. ออกทั้งระบบตามที่ขอ — locale "th-TH" ให้ปี
  // พ.ศ. เป็นค่าเริ่มต้นอยู่แล้ว
  const opts = { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" };
  return d.toLocaleString("th-TH", opts);
}

// popup รายละเอียดแจ้งเตือนที่ "สำคัญ" (ทุกประเภทยกเว้น CHAT)
// ป้ายชื่อของสิ่งที่ target_id อ้างอิงถึง — ต่างกันไปตามประเภทแจ้งเตือน (งานซ่อม/
// อะไหล่/เครื่องจักร ไม่ใช่ id ชนิดเดียวกันหมด)
const TARGET_ID_LABEL = {
  LOW_STOCK: "รหัสอะไหล่ที่เกี่ยวข้อง",
  WARRANTY_EXPIRING: "รหัสเครื่องจักรที่เกี่ยวข้อง",
};

function targetIdLabelFor(n) {
  return TARGET_ID_LABEL[n.type] || "รหัสงานที่เกี่ยวข้อง";
}

// 🔴 [แก้ไข] เดิมปุ่ม "ไปที่งานนี้" พาไปหน้างานซ่อมเสมอ ไม่ว่า target_id จะ
// หมายถึงอะไร — พอเพิ่มแจ้งเตือน LOW_STOCK เข้ามา (target_id = id ของอะไหล่
// ไม่ใช่ id ของงานซ่อม) กดแล้วจะพาไปค้นงานซ่อมด้วย id อะไหล่ผิดที่ทันที ต้อง
// เลือกหน้าปลายทาง + ข้อความปุ่มให้ตรงกับประเภทของแจ้งเตือนแทน — เพิ่ม
// WARRANTY_EXPIRING (target_id = id เครื่องจักร ไม่ใช่ id งานซ่อม และหน้า
// ลูกค้ายังไม่รองรับค้นหาด้วย id เครื่องจักรโดยตรง) ใช้ noQuery บอกว่าหน้านี้
// ให้พาไปเฉย ๆ ไม่ต้องส่งคำค้นไปด้วย (เหมือนกับ PAYMENT_OVERDUE ที่หน้าการเงิน
// ยังไม่มีช่องค้นหาให้กรองเหมือนกัน)
function targetLinkFor(n) {
  if (!n.target_id) return null;
  if (n.type === "LOW_STOCK") return { page: "parts", label: "ไปที่คลังอะไหล่" };
  if (n.type === "PAYMENT_OVERDUE") return { page: "finance", label: "ไปที่หน้าการเงิน", noQuery: true };
  if (n.type === "WARRANTY_EXPIRING") return { page: "customers", label: "ไปที่หน้าลูกค้า", noQuery: true };
  return { page: "jobs", label: "ไปที่งานนี้" };
}

function NotificationDetailModal({ notification, onClose, onNavigate, onDelete, deleting }) {
  const n = notification;
  const link = targetLinkFor(n);
  return (
    <Modal
      title={n.title || "แจ้งเตือน"}
      onClose={onClose}
      footer={
        <>
          <button
            onClick={onDelete}
            disabled={deleting}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-medium text-red-500 hover:bg-red-50 disabled:opacity-50"
          >
            <Trash2 size={14} />
            ลบแจ้งเตือนนี้
          </button>
          {link ? (
            <button
              onClick={() => {
                // การเงินยังไม่มีช่องค้นหาให้กรอง ส่งแค่หน้าไปเฉย ๆ ส่วนงานซ่อม/
                // อะไหล่ ส่ง id ไปกรองให้เจอแถวนั้นเลย
                onNavigate?.(link.page, link.noQuery ? undefined : { query: String(n.target_id) });
                onClose();
              }}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600"
            >
              {link.label}
              <ChevronRight size={14} />
            </button>
          ) : null}
        </>
      }
    >
      <div className="space-y-3">
        <span className="inline-block text-[11px] font-medium px-2.5 py-1 rounded-full bg-slate-100 text-slate-500">
          {TYPE_LABEL[n.type] || "ทั่วไป"}
        </span>
        <p className="text-[15px] text-slate-700 leading-relaxed">{n.message}</p>
        {n.target_id ? (
          <p className="text-xs text-slate-400">
            {targetIdLabelFor(n)}: #{n.target_id}
          </p>
        ) : null}
        {n.created_at ? <p className="text-xs text-slate-400">{formatDateTime(n.created_at)}</p> : null}
      </div>
    </Modal>
  );
}

export default function NotificationsPage({ onNavigate, initialQuery }) {
  const { data: notifications, loading } = useDbList("notifications");
  const currentUsername = getSessionAdmin()?.username || "";
  const [viewingNotification, setViewingNotification] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  // 🆕 จำนวนรายการต่อหน้า อ่านมาจากหน้าตั้งค่า > ระบบทั่วไป (ของหน้า "การแจ้งเตือน")
  // + รูปแบบวันที่ (พ.ศ./ค.ศ.) ใช้กับ formatDateTime ด้านล่าง
  const { settings: webSettings } = useWebSettings();
  const pageSize = Number(webSettings.itemsPerPageNotifications) || 20;
  const [page, setPage] = useState(1);
  // 🔴 [แก้ไข] state แยกสำหรับยืนยัน "ลบทั้งหมด" (คนละสถานะกับลบทีละอัน)
  const [confirmDeleteAll, setConfirmDeleteAll] = useState(false);
  const [deletingAll, setDeletingAll] = useState(false);
  // 🔴 [ใหม่] ยืนยันลบทั้งกลุ่มข้อความของงานหนึ่ง (คนละสถานะกับลบทีละแจ้งเตือน)
  const [deleteGroupTarget, setDeleteGroupTarget] = useState(null);
  const [deletingGroup, setDeletingGroup] = useState(false);

  const adminNotifications = [...notifications].filter((n) => n.user_username === currentUsername);

  // 🔴 [ใหม่] รองรับ initialQuery ที่ส่งมาจากการ์ด "การแจ้งเตือนล่าสุด" ในหน้า
  // Dashboard (ส่ง id ของแจ้งเตือนที่กดมาโดยตรง) — เปิด popup รายละเอียดของ
  // แจ้งเตือนนั้นให้อัตโนมัติทันทีที่เข้าหน้านี้ (เฉพาะแจ้งเตือนที่ไม่ใช่ CHAT
  // เพราะข้อความแชทไม่มี popup อยู่แล้วตามที่ตกลงกันไว้) — ใช้ ref กันไม่ให้
  // เปิดซ้ำทุกครั้งที่ notifications รีเฟรช (เช่นตอน mark read) ซึ่งจะทำให้
  // popup เด้งกลับมาเองทั้งที่ผู้ใช้เพิ่งกดปิดไป
  const autoOpenedRef = useRef(null);
  useEffect(() => {
    if (!initialQuery || autoOpenedRef.current === initialQuery) return;
    const match = adminNotifications.find((n) => String(n.id) === String(initialQuery) && n.type !== "CHAT");
    if (match) {
      autoOpenedRef.current = initialQuery;
      openNotification(match);
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [initialQuery, notifications]);

  // 🔴 [ใหม่] แยกแจ้งเตือนข้อความแชท (CHAT) ออกมา group ตาม target_id (งาน)
  // ให้เหลือแถวเดียวต่องาน — ส่วนที่เหลือ (ไม่ใช่ CHAT) โชว่แยกทีละรายการปกติ
  // 🔴 [แก้ไข] อันที่เป็น CHAT แต่ไม่มี target_id เลย (ไม่รู้ว่าเป็นของงานไหน)
  // ไม่ต้องเอาไปรวมกลุ่มกัน — เดิมเอาไปกองไว้ในกลุ่มเดียวกันหมดโดยใช้ key
  // "unknown" ปัญหาคือถ้ากดลบกลุ่มนั้นกลุ่มเดียว จะลบแจ้งเตือนที่ไม่มี target_id
  // ทุกอันทิ้งพร้อมกันหมดทั้งที่อาจเป็นคนละงานกันเลย — แยกเป็นรายการเดี่ยวแทน
  // (แต่ยังไม่เปิด popup อยู่ดี เพราะเป็นข้อความแชทเหมือนกัน ตามที่ขอไว้)
  const chatByJob = {};
  const chatWithoutJob = [];
  const importantNotifications = [];
  adminNotifications.forEach((n) => {
    if (n.type === "CHAT") {
      if (n.target_id != null) {
        const key = n.target_id;
        if (!chatByJob[key]) chatByJob[key] = [];
        chatByJob[key].push(n);
      } else {
        chatWithoutJob.push(n);
      }
    } else {
      importantNotifications.push(n);
    }
  });

  const chatGroups = Object.entries(chatByJob).map(([jobId, items]) => {
    const sorted = [...items].sort((a, b) => (new Date(b.created_at).getTime() || 0) - (new Date(a.created_at).getTime() || 0));
    const latest = sorted[0];
    const unreadCount = items.filter((n) => !n.is_read).length;
    return { jobId, ids: items.map((n) => n.id), latest, unreadCount, sortKey: new Date(latest.created_at).getTime() || 0 };
  });

  // รวมแจ้งเตือนสำคัญ + กลุ่มข้อความแชท + ข้อความแชทที่ไม่รู้ว่าเป็นของงานไหน
  // แล้วเรียงตามเวลาล่าสุดปนกัน
  const feed = [
    ...importantNotifications.map((n) => ({ kind: "single", n, sortKey: new Date(n.created_at).getTime() || 0 })),
    ...chatGroups.map((g) => ({ kind: "chat-group", group: g, sortKey: g.sortKey })),
    ...chatWithoutJob.map((n) => ({ kind: "chat-single", n, sortKey: new Date(n.created_at).getTime() || 0 })),
  ].sort((a, b) => b.sortKey - a.sortKey);

  // 🆕 แบ่งหน้ารายการแจ้งเตือนตามจำนวนที่ตั้งไว้ — กลับไปหน้า 1 เองถ้าจำนวน
  // ทั้งหมดเปลี่ยน (เช่น ลบทิ้งจนหน้าปัจจุบันไม่มีข้อมูลเหลือแล้ว)
  useEffect(() => {
    setPage(1);
  }, [feed.length]);
  const totalPages = Math.max(1, Math.ceil(feed.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const pagedFeed = feed.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  async function openNotification(n) {
    setViewingNotification(n);
    if (!n.is_read) {
      try {
        await updateRow("notifications", n.id, { is_read: true });
      } catch (err) {
        console.error("[NotificationsPage] mark read failed:", err);
      }
    }
  }

  async function openChatGroup(group) {
    try {
      await markNotificationsRead(group.ids);
    } catch (err) {
      console.error("[NotificationsPage] mark group read failed:", err);
    }
    onNavigate?.("chat", { query: String(group.jobId) });
  }

  // 🔴 [ใหม่] ข้อความแชทที่ไม่รู้ว่าเป็นของงานไหน (ไม่มี target_id) — มาร์ก
  // อ่านแล้วได้ แต่พาไปห้องแชทเจาะจงไม่ได้ (ไม่รู้ว่างานไหน) เลยแค่พาไปหน้าแชท
  // เฉย ๆ ให้แอดมินเลือกห้องเอง
  async function openChatSingle(n) {
    if (!n.is_read) {
      try {
        await updateRow("notifications", n.id, { is_read: true });
      } catch (err) {
        console.error("[NotificationsPage] mark read failed:", err);
      }
    }
    onNavigate?.("chat");
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRow("notifications", deleteTarget.id);
      setDeleteTarget(null);
      if (viewingNotification?.id === deleteTarget.id) setViewingNotification(null);
    } catch (err) {
      console.error("[NotificationsPage] delete failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  async function handleDeleteGroup() {
    if (!deleteGroupTarget) return;
    setDeletingGroup(true);
    try {
      await deleteNotifications(deleteGroupTarget.ids);
      setDeleteGroupTarget(null);
    } catch (err) {
      console.error("[NotificationsPage] delete group failed:", err);
    } finally {
      setDeletingGroup(false);
    }
  }

  async function handleDeleteAll() {
    setDeletingAll(true);
    try {
      await deleteAllNotifications(notifications, currentUsername);
      setConfirmDeleteAll(false);
      setViewingNotification(null);
    } catch (err) {
      console.error("[NotificationsPage] delete all failed:", err);
    } finally {
      setDeletingAll(false);
    }
  }

  return (
    <div>
      {/* 🔴 [แก้ไข] เอาหัวข้อ "การแจ้งเตือน" ออก เพราะซ้ำกับ Header บนสุด
          เหลือแค่ปุ่ม 2 ปุ่มเดิมชิดขวา */}
      <div className="flex items-center justify-end gap-2 mb-5">
        <button
          onClick={() => markAllNotificationsAsRead(notifications, currentUsername)}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white border border-slate-200 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          <CheckCheck size={16} />
          ทำเครื่องหมายว่าอ่านแล้วทั้งหมด
        </button>
        <button
          onClick={() => setConfirmDeleteAll(true)}
          disabled={adminNotifications.length === 0}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-red-50 border border-red-100 text-sm font-medium text-red-500 hover:bg-red-100 disabled:opacity-50 disabled:hover:bg-red-50"
        >
          <Trash2 size={16} />
          ลบทั้งหมด
        </button>
      </div>

      <Card>
        {loading ? (
          <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
        ) : feed.length === 0 ? (
          <EmptyState icon={Bell} message="ยังไม่มีการแจ้งเตือน" />
        ) : (
          <div className="divide-y divide-slate-50">
            {pagedFeed.map((item) => {
              if (item.kind === "chat-group") {
                const g = item.group;
                const n = g.latest;
                return (
                  <div key={`chat-${g.jobId}`} className="flex items-start gap-3 py-3">
                    <button
                      onClick={() => openChatGroup(g)}
                      className="flex-1 flex items-start gap-3 text-left hover:bg-slate-50 -mx-2 px-2 py-1 rounded-lg min-w-0"
                    >
                      <MessageSquare size={16} className="text-blue-400 mt-0.5 shrink-0" />
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium text-slate-800">
                          ข้อความใหม่ — {n.title?.replace("ข้อความใหม่: ", "") || `งาน #${g.jobId}`}
                        </p>
                        <p className="text-xs text-slate-500 mt-0.5 truncate">{n.message}</p>
                        {n.created_at ? <p className="text-[11px] text-slate-400 mt-1">{formatDateTime(n.created_at)}</p> : null}
                      </div>
                      {g.unreadCount > 0 ? (
                        <span className="text-[11px] font-semibold bg-blue-500 text-white rounded-full w-5 h-5 flex items-center justify-center shrink-0">
                          {g.unreadCount}
                        </span>
                      ) : null}
                    </button>
                    <button
                      onClick={() => setDeleteGroupTarget(g)}
                      title="ลบข้อความกลุ่มนี้"
                      className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 hover:bg-red-50 hover:text-red-500 shrink-0 mt-1"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                );
              }

              if (item.kind === "chat-single") {
                const n = item.n;
                return (
                  <div key={n.id} className="flex items-start gap-3 py-3">
                    <button
                      onClick={() => openChatSingle(n)}
                      className="flex-1 flex items-start gap-3 text-left hover:bg-slate-50 -mx-2 px-2 py-1 rounded-lg min-w-0"
                    >
                      <MessageSquare size={16} className="text-blue-400 mt-0.5 shrink-0" />
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-medium text-slate-800">{n.title || "ข้อความใหม่"}</p>
                        <p className="text-xs text-slate-500 mt-0.5 truncate">{n.message}</p>
                        {n.created_at ? <p className="text-[11px] text-slate-400 mt-1">{formatDateTime(n.created_at)}</p> : null}
                      </div>
                      {!n.is_read ? <span className="w-2 h-2 rounded-full bg-blue-500 mt-1.5 shrink-0" /> : null}
                    </button>
                    <button
                      onClick={() => setDeleteTarget(n)}
                      title="ลบแจ้งเตือน"
                      className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 hover:bg-red-50 hover:text-red-500 shrink-0 mt-1"
                    >
                      <Trash2 size={14} />
                    </button>
                  </div>
                );
              }

              const n = item.n;
              return (
                <div key={n.id} className="flex items-start gap-3 py-3">
                  <button
                    onClick={() => openNotification(n)}
                    className="flex-1 flex items-start gap-3 text-left hover:bg-slate-50 -mx-2 px-2 py-1 rounded-lg min-w-0"
                  >
                    <span className={`w-2 h-2 rounded-full mt-1.5 shrink-0 ${n.is_read ? "bg-slate-200" : "bg-blue-500"}`} />
                    <div className="min-w-0 flex-1">
                      <p className="text-sm font-medium text-slate-800">{n.title || "แจ้งเตือน"}</p>
                      <p className="text-xs text-slate-500 mt-0.5 truncate">{n.message}</p>
                      {n.created_at ? <p className="text-[11px] text-slate-400 mt-1">{formatDateTime(n.created_at)}</p> : null}
                    </div>
                  </button>
                  <button
                    onClick={() => setDeleteTarget(n)}
                    title="ลบแจ้งเตือน"
                    className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 hover:bg-red-50 hover:text-red-500 shrink-0 mt-1"
                  >
                    <Trash2 size={14} />
                  </button>
                </div>
              );
            })}
          </div>
        )}
        <Pagination
          page={currentPage}
          totalPages={totalPages}
          onChange={setPage}
          totalItems={feed.length}
          pageSize={pageSize}
        />
      </Card>

      {viewingNotification ? (
        <NotificationDetailModal
          notification={viewingNotification}
          onClose={() => setViewingNotification(null)}
          onNavigate={onNavigate}
          onDelete={() => setDeleteTarget(viewingNotification)}
          deleting={deleting}
        />
      ) : null}

      {deleteTarget ? (
        <ConfirmDialog
          message="ต้องการลบการแจ้งเตือนนี้ใช่หรือไม่?"
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          busy={deleting}
        />
      ) : null}

      {deleteGroupTarget ? (
        <ConfirmDialog
          title="ลบข้อความกลุ่มนี้"
          message={`ต้องการลบแจ้งเตือนข้อความทั้งหมด (${deleteGroupTarget.ids.length} รายการ) ของงานนี้ใช่หรือไม่?`}
          onConfirm={handleDeleteGroup}
          onCancel={() => setDeleteGroupTarget(null)}
          busy={deletingGroup}
        />
      ) : null}

      {confirmDeleteAll ? (
        <ConfirmDialog
          title="ลบการแจ้งเตือนทั้งหมด"
          message={`ต้องการลบการแจ้งเตือนทั้งหมด (${adminNotifications.length} รายการ) ใช่หรือไม่? การลบนี้กู้คืนไม่ได้`}
          onConfirm={handleDeleteAll}
          onCancel={() => setConfirmDeleteAll(false)}
          busy={deletingAll}
        />
      ) : null}
    </div>
  );
}
