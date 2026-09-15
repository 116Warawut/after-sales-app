import React, { useState, useMemo, useRef, useEffect } from "react";
import { MessageSquare, Send, ImagePlus, Loader2, Pencil, Trash2, Check, X, CheckCheck, ArrowLeft, Search } from "lucide-react";
import { PageHeader, EmptyState, ConfirmDialog } from "../components/ui";
import useDbList from "../hooks/useDbList";
import { addRow, updateRow, createNotification, getWebSettings } from "../services/firebaseDb";
import { uploadImage } from "../services/cloudinary";
import { getSessionAdmin } from "../services/session";

// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: เลย์เอาต์ 2 คอลัมน์ (รายชื่อห้องซ้าย 320px คงที่ +
// พื้นที่สนทนาขวา) แบบเดียวกับแอปแชททั่วไป — 📏 height ใช้สูตร
// calc(100vh - 150px) เพื่อให้พอดีจอโดยลบพื้นที่ Header ด้านบนออก
// 🔴 [แก้ไข] เดิมเป็นแค่โครงเปล่า (CONVERSATIONS = []) ตอนนี้เชื่อมข้อมูลจริง
// จาก chat_messages แล้ว — ข้อความของแอดมิน (ฝั่งเรา) ใช้ฟองสีน้ำเงินชิดขวา
// ข้อความของอีกฝ่ายใช้ฟองสีเทาชิดซ้าย (สไตล์แชทมาตรฐานทั่วไป)
// ---------------------------------------------------------------------------

export default function ChatPage({ initialQuery }) {
  const admin = getSessionAdmin();
  const { data: repairs, loading: loadingRepairs } = useDbList("repairs");
  const { data: messages, loading: loadingMessages } = useDbList("chat_messages");
  const [selectedRepairId, setSelectedRepairId] = useState(null);
  const [draft, setDraft] = useState("");
  const [sending, setSending] = useState(false);
  const [query, setQuery] = useState("");
  const [uploadingImage, setUploadingImage] = useState(false);
  // 🔴 [แก้ไข] state สำหรับแก้ไข/ลบข้อความของตัวเอง
  const [editingId, setEditingId] = useState(null);
  const [editDraft, setEditDraft] = useState("");
  const [savingEdit, setSavingEdit] = useState(false);
  const [deleteMsgTarget, setDeleteMsgTarget] = useState(null);
  const [deletingMsg, setDeletingMsg] = useState(false);
  const bottomRef = useRef(null);
  const markedReadRef = useRef(new Set());
  // 🔔 [แก้ไข] ดึงสวิตช์ "แจ้งเตือนข้อความแชทใหม่" จากหน้าตั้งค่ามาเช็กจริง —
  // เดิมสวิตช์นี้กดปิด/เปิดได้แต่ไม่มีผลอะไรเลย ยิง push ทุกครั้งไม่ว่าจะปิดสวิตช์
  // ไว้หรือไม่ก็ตาม
  const [notifyChatEnabled, setNotifyChatEnabled] = useState(true);

  useEffect(() => {
    getWebSettings()
      .then((s) => setNotifyChatEnabled(s?.notifyChat !== false))
      .catch((err) => console.error("[ChatPage] load settings failed:", err));
  }, []);

  // ห้องแชท = งานซ่อมที่มีข้อความอยู่แล้ว หรือมีช่างรับผิดชอบแล้วและยังไม่จบ
  // (ตรงกับกฎเดียวกับหน้ารายการแชทในแอปมือถือ) เรียงห้องที่มีข้อความล่าสุดไว้บนสุด
  // 🔴 [แก้บั๊ก] เจอบั๊กเดียวกับที่เคยแก้ไปแล้วฝั่งแอปมือถือ (chat_list_page.dart):
  // เดิมหน้านี้ดึงงานซ่อม "ทั้งหมดในระบบ" มาสร้างห้องแชทให้แอดมินทุกคนเห็นเหมือนกัน
  // หมด ทำให้แอดมินที่ไม่ใช่ผู้อนุมัติ/มอบหมายช่างให้งานนั้น (ไม่ตรงกับ
  // repair.admin_username) ก็ยังเปิดเข้าไปดู/พิมพ์แชทของงานที่ตัวเองไม่ได้
  // รับผิดชอบได้ตามใจ ทั้งที่ต้องการให้ "1 ห้องแชท มีแอดมินรับผิดชอบได้แค่ 1 คน"
  // เหมือนกับที่แอปมือถือกำหนดไว้ — แก้โดยกรอง repairs ให้เหลือเฉพาะงานที่
  // admin_username ตรงกับแอดมินที่ล็อกอินอยู่บนเว็บเท่านั้น ก่อนจะสร้างห้องแชท
  // 🔴 [แก้ไข] เดิมเรียงข้อความด้วย id ของข้อความ โดยเข้าใจว่าเว็บกับแอปมือถือใช้
  // counter เดียวกันจาก Firebase — แต่ตรวจโค้ดจริงแล้วไม่ใช่: ฝั่งเว็บสร้างข้อความ
  // ด้วย push() (คีย์สุ่ม ไม่ใช่ตัวเลขวิ่ง) ส่วนฝั่งมือถือใช้ counter ตัวเลขจริง
  // สองระบบนี้ "ไม่ได้" นับเลขร่วมกันเลย เอา id มาเรียงข้ามแพลตฟอร์มจึงไม่การันตี
  // ลำดับที่ถูกต้อง (ใช้ได้แค่ตอนข้อความมาจากฝั่งเดียวกันทั้งหมดเท่านั้น) — เปลี่ยน
  // มาเรียงด้วย created_at (ISO string เทียบตรง ๆ ได้ถูกต้องเพราะเป็นรูปแบบ
  // ISO 8601 อยู่แล้วทั้งสองฝั่ง) ซึ่งเชื่อถือได้ข้ามแพลตฟอร์มมากกว่า id จริง ๆ
  const rooms = useMemo(() => {
    const sortKey = (m) => (m?.created_at ? new Date(m.created_at).getTime() || 0 : 0);
    const byRepair = {};
    messages.forEach((m) => {
      if (!byRepair[m.repair_id]) byRepair[m.repair_id] = [];
      byRepair[m.repair_id].push(m);
    });

    // 🔴 [แก้บั๊ก] กรองเฉพาะงานที่แอดมินคนนี้เป็นผู้รับผิดชอบ (admin_username
    // ตรงกับแอดมินที่ล็อกอินอยู่) ก่อนเสมอ — ดูเหตุผลเต็ม ๆ ในคอมเมนต์ด้านบน
    const myRepairs = repairs.filter((r) => r.admin_username === admin?.username);

    return myRepairs
      .map((r) => {
        const msgs = (byRepair[r.record_id] || []).sort((a, b) => sortKey(a) - sortKey(b));
        const last = msgs[msgs.length - 1];
        const status = r.status || "";
        const isActive =
          r.technician_username && !status.includes("ยกเลิก") && status !== "เสร็จแล้ว" && status !== "เสร็จสิ้น";
        return { repair: r, messages: msgs, last, hasRoom: msgs.length > 0 || isActive };
      })
      .filter((room) => room.hasRoom)
      .filter((room) => {
        const q = query.trim().toLowerCase();
        if (!q) return true;
        // 🔴 [แก้ไข] เดิมเช็ก id แค่ตอน ticketNo ไม่มีค่า — เพิ่มให้เช็ก id
        // แยกเป็นเงื่อนไขของตัวเองเสมอ (ใช้ตอนกดลิงก์ "ไปที่ห้องแชท" จาก popup
        // แจ้งเตือนข้อความ ซึ่งส่ง id งานมาค้นหาตรง ๆ)
        return (
          (room.repair.ticketNo || "").toLowerCase().includes(q) ||
          String(room.repair.record_id ?? "").toLowerCase().includes(q) ||
          (room.repair.customer_username || "").toLowerCase().includes(q)
        );
      })
      .sort((a, b) => sortKey(b.last) - sortKey(a.last));
  }, [repairs, messages, query, admin?.username]);

  // 🔴 [แก้บั๊ก] เดิมเทียบด้วย r.repair.id (คีย์จริงของ Firebase เช่น "k18")
  // แต่ rooms ด้านบนกรองข้อความด้วย byRepair[r.record_id] (เลข id จริงของงาน
  // ซ่อม เช่น 18) — สองค่านี้คนละความหมายกัน ทำให้ selectedRepairId ที่เก็บ
  // เป็นคีย์ Firebase ไม่มีทาง match กับ record_id ได้เลย ต้องเทียบด้วย
  // record_id ให้ตรงกับตัวกรองข้อความ
  const selectedRoom = rooms.find((r) => r.repair.record_id === selectedRepairId);

  // 🔴 [ใหม่] รองรับ initialQuery ที่ส่งมาจากลิงก์ "ไปที่ห้องแชท" ในหน้าแจ้งเตือน
  // (ส่งเลข id ของงานมาโดยตรง) — เปิดห้องแชทของงานนั้นให้อัตโนมัติทันทีที่เข้า
  // หน้านี้ ไม่ต้องให้แอดมินมาค้นหาเองอีกที
  useEffect(() => {
    if (!initialQuery || selectedRepairId || rooms.length === 0) return;
    const numericId = Number(initialQuery);
    const match = rooms.find((r) => r.repair.record_id === numericId) || rooms.find((r) => r.repair.ticketNo === initialQuery);
    if (match) setSelectedRepairId(match.repair.record_id);
  }, [initialQuery, rooms, selectedRepairId]);

  // 🔴 [แก้ไข] เพิ่มสถานะ "อ่านแล้ว" — เมื่อแอดมินเปิดห้องและเห็นข้อความของอีกฝ่าย
  // ที่ยังไม่อ่าน ให้มาร์ก is_read: true ทันที (ใช้ field is_read เดิมที่มีอยู่
  // แล้ว) markedReadRef กันไม่ให้ยิง updateRow ซ้ำข้อความเดิมซ้ำ ๆ ทุก re-render
  useEffect(() => {
    if (!selectedRoom) return;
    selectedRoom.messages.forEach((m) => {
      const isMe = m.sender_username === admin?.username;
      if (!isMe && !m.is_read && !markedReadRef.current.has(m.id)) {
        markedReadRef.current.add(m.id);
        updateRow("chat_messages", m.id, { is_read: 1 }).catch((err) =>
          console.error("[ChatPage] mark read failed:", err)
        );
      }
    });
  }, [selectedRoom, admin?.username]);

  // 🔴 [แก้ไข] เดิม scroll ลงล่างสุดทำงานตาม "จำนวนข้อความ" อย่างเดียว —
  // ถ้าสลับไปห้องอื่นที่มีจำนวนข้อความเท่ากันพอดี จะไม่เลื่อนลงให้ (ค่า dependency
  // ไม่เปลี่ยน) ทำให้บางครั้งเปิดห้องมาแล้วไม่ได้อยู่ล่างสุดเหมือนไลน์ — เพิ่ม
  // selectedRepairId เข้า dependency ด้วย เพื่อบังคับเลื่อนลงล่างสุดทุกครั้งที่
  // เปลี่ยนห้องหรือมีข้อความใหม่ ข้อความล่าสุดต้องอยู่ล่างสุดเสมอ
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "auto" });
  }, [selectedRepairId, selectedRoom?.messages?.length]);

  // 🔔 [ใหม่] สร้างแจ้งเตือน (+ push) ให้ผู้ร่วมแชทอีกฝ่าย (ลูกค้า/ช่าง) ทุกครั้ง
  // ที่แอดมินส่งข้อความ/รูปจากเว็บ — เทียบเท่า _notifyOtherParticipants()
  // ฝั่งแอปมือถือ (chat_screen.dart) เดิมเว็บไม่เคยเรียกจุดนี้เลย ทำให้คนใช้แอป
  // มือถือไม่รู้เลยว่ามีข้อความใหม่ถ้าปิดแอปอยู่ ยิงแบบ "ยิงทิ้ง" (ไม่ await ผล
  // ทีละคน) เพื่อไม่ให้แจ้งเตือนคนหนึ่งพลาดแล้วดันบล็อกอีกคน
  function notifyOtherParticipants(room, previewText) {
    if (!room) return;
    // 🔔 [แก้ไข] เช็กสวิตช์ "แจ้งเตือนข้อความแชทใหม่" ในหน้าตั้งค่าก่อนยิงจริง
    if (!notifyChatEnabled) return;
    const myUsername = admin?.username || "admin";
    const chatTitle = room.repair.ticketNo || `#${room.repair.id}`;
    const participants = [
      { username: room.repair.customer_username, role: "CUSTOMER" },
      { username: room.repair.technician_username, role: "TECHNICIAN" },
    ].filter((p) => p.username && p.username !== myUsername);

    participants.forEach((p) => {
      createNotification({
        user_username: p.username,
        role: p.role,
        title: `ข้อความใหม่: ${chatTitle}`,
        message: previewText,
        type: "CHAT",
        target_id: room.repair.id,
      }).catch((err) => console.error(`[ChatPage] notify ${p.username} failed:`, err));
    });
  }

  async function handleSend() {
    const text = draft.trim();
    if (!text || !selectedRepairId) return;
    setSending(true);
    try {
      await addRow("chat_messages", {
        repair_id: selectedRepairId,
        sender_username: admin?.username || "admin",
        sender_role: "ADMIN",
        message: text,
        message_type: "text",
        created_at: new Date().toISOString(),
        is_read: 0,
      });
      notifyOtherParticipants(selectedRoom, text);
      setDraft("");
    } catch (err) {
      console.error("[ChatPage] send message failed:", err);
    } finally {
      setSending(false);
    }
  }

  // 🔴 [แก้ไข] ปุ่มเพิ่มรูปภาพในแชท — อัปโหลดขึ้น Cloudinary (บัญชีเดียวกับ
  // แอปมือถือ) แล้วส่งเป็นข้อความ message_type: "image" ทันที ใช้ field
  // image_path ให้ตรงกับที่ฝั่งแสดงผลข้อความ (บรรทัด 166) และห้องแชท (บรรทัด 124)
  // อ่านอยู่แล้ว
  async function handlePickImage(e) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file || !selectedRepairId) return;
    setUploadingImage(true);
    try {
      const url = await uploadImage(file);
      await addRow("chat_messages", {
        repair_id: selectedRepairId,
        sender_username: admin?.username || "admin",
        sender_role: "ADMIN",
        message: "",
        message_type: "image",
        image_path: url,
        created_at: new Date().toISOString(),
        is_read: 0,
      });
      notifyOtherParticipants(selectedRoom, "📷 รูปภาพ");
    } catch (err) {
      console.error("[ChatPage] send image failed:", err);
    } finally {
      setUploadingImage(false);
    }
  }

  // 🕒 แปลง created_at เป็นเวลา HH:mm โชว์ใต้ข้อความ — กันเคส parse ไม่ได้ (บาง
  // ข้อความจากแอปมือถืออาจเขียนรูปแบบต่างกัน) ด้วยการเช็ก isNaN ก่อน
  function formatTime(createdAt) {
    if (!createdAt) return "";
    const d = new Date(createdAt);
    if (isNaN(d.getTime())) return "";
    return d.toLocaleTimeString("th-TH", { hour: "2-digit", minute: "2-digit" });
  }

  // 🔴 [แก้ไข] แก้ไขข้อความของตัวเอง (เฉพาะข้อความตัวหนังสือ) — บันทึกแล้วติดแท็ก
  // is_edited ไว้โชว์ "(แก้ไขแล้ว)" ต่อท้าย เหมือนพฤติกรรมฝั่งแอปมือถือ
  function startEdit(m) {
    setEditingId(m.id);
    setEditDraft(m.message || "");
  }

  function cancelEdit() {
    setEditingId(null);
    setEditDraft("");
  }

  async function saveEdit(m) {
    const text = editDraft.trim();
    if (!text) return;
    setSavingEdit(true);
    try {
      // 🔴 [แก้ไข] เขียนเป็นเลข 1 (ไม่ใช่ boolean true) — เช็กแล้วกับโค้ดแอปมือถือ
      // จริง (chat_screen.dart) ว่าอ่านค่าด้วย msg['is_edited'] == 1 ถ้าเขียน
      // true เข้าไป Dart จะเทียบไม่ตรง (true != 1) ทำให้แอปมือถือไม่รู้ว่าข้อความ
      // ถูกแก้ไข
      await updateRow("chat_messages", m.id, { message: text, is_edited: 1 });
      setEditingId(null);
      setEditDraft("");
    } catch (err) {
      console.error("[ChatPage] edit message failed:", err);
    } finally {
      setSavingEdit(false);
    }
  }

  // 🔴 [แก้ไข] ลบข้อความของตัวเอง — soft-delete (ไม่ลบแถวจริง) ตั้ง is_deleted
  // แล้วฝั่งแสดงผลจะโชว์ "ข้อความถูกลบแล้ว" แทนเนื้อหาเดิม ตรงกับพฤติกรรมฝั่งแอป
  // มือถือ
  async function confirmDeleteMessage() {
    if (!deleteMsgTarget) return;
    setDeletingMsg(true);
    try {
      // 🔴 [แก้ไข] เขียนเป็นเลข 1 เหมือนกัน (ดูเหตุผลเดียวกับ is_edited ด้านบน)
      // — เช็กกับ services.dart จริงแล้วว่าเขียน is_deleted: 1 เช่นกัน
      await updateRow("chat_messages", deleteMsgTarget.id, { is_deleted: 1 });
      setDeleteMsgTarget(null);
    } catch (err) {
      console.error("[ChatPage] delete message failed:", err);
    } finally {
      setDeletingMsg(false);
    }
  }

  // 🔴 [แก้ไข] รอบที่แล้วโชว์ "อ่านแล้ว" แค่ใต้ข้อความล่าสุดที่อ่านแล้วเพียง
  // ข้อความเดียว (เหมือน LINE) แต่พอลองใช้จริงแล้วดูเหมือนข้อความเก่า ๆ ที่อ่าน
  // ไปแล้วจริง ๆ "ไม่ขึ้น" เพราะแต่ละครั้งจะมีแค่ 1 ข้อความที่โชว่ป้ายนี้เท่านั้น
  // (ข้อความอื่นแม้อ่านแล้วก็ไม่ติดป้ายให้เห็น) — เปลี่ยนเป็นโชว่ "อ่านแล้ว" ใต้
  // ทุกข้อความของเราเองที่ is_read เป็นจริง ไม่จำกัดแค่ข้อความล่าสุด ตรงไปตรงมา
  // กับข้อมูลจริงที่สุด ไม่ต้องมีตัวชี้ lastReadOwnMessage อีกแล้ว

  return (
    <div>
      {/* 🔴 [แก้ไข] ลดพื้นที่ที่หักออกจาก 220px เหลือ 150px — ค่าเดิมตั้งไว้ตอน
          Header ยังมี padding ใหญ่กว่านี้ พอลด padding ของ Header ไปตอนทำ
          responsive แล้ว 220px กลายเป็นเผื่อไว้เกินจริง ทำให้กรอบแชทเตี้ยกว่าที่
          ควรและมีพื้นที่ว่างโล่ง ๆ ใต้กรอบเยอะ ปรับให้กรอบแชทสูงเกือบเต็มจอแทน */}
      <div className="bg-white rounded-2xl border border-slate-100 overflow-hidden flex" style={{ height: "calc(100vh - 150px)" }}>
        {/* รายชื่อห้องแชท — 🔴 [แก้ไข] บนจอเล็กกว่า md (<768px) โชว์แค่ทีละแผง
            (รายชื่อห้อง หรือ หน้าต่างสนทนา) แทนที่จะบีบสองแผงชนกันจนใช้งานไม่ได้
            เหมือนแอปแชทมือถือทั่วไป — ซ่อนแผงนี้เมื่อเลือกห้องแล้วบนจอเล็ก */}
        <div className={`${selectedRoom ? "hidden md:flex" : "flex"} w-full md:w-80 border-r border-slate-100 flex-col shrink-0`}>
          <div className="p-4 border-b border-slate-100">
            {/* 🔴 [แก้ไข] ช่องนี้เดิมไม่มีไอคอนแว่นขยายเหมือนหน้าอื่น ๆ — เพิ่มให้
                ตรงกัน พร้อมปุ่มล้างการค้นหา (X) กดครั้งเดียวเคลียร์ query */}
            <div className="relative">
              <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
              <input
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                placeholder="ค้นหาห้องแชท..."
                className="w-full pl-9 pr-8 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-red-100"
              />
              {query ? (
                <button
                  onClick={() => setQuery("")}
                  className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500"
                >
                  <X size={14} />
                </button>
              ) : null}
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">
            {loadingRepairs || loadingMessages ? (
              <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
            ) : rooms.length === 0 ? (
              <EmptyState icon={MessageSquare} message="ยังไม่มีห้องแชท" />
            ) : (
              rooms.map((room) => {
                // 🔴 [แก้บั๊ก] เดิมเทียบ/ตั้งค่าด้วย room.repair.id (คีย์จริงของ
                // Firebase เช่น "k18") ทำให้ setSelectedRepairId เก็บค่าเป็นคีย์
                // Firebase — พอกดส่งข้อความ (handleSend ใช้ repair_id:
                // selectedRepairId ตรง ๆ) ข้อความเลยถูกเขียนด้วย repair_id ผิด
                // รูปแบบ (คีย์ Firebase แทนที่จะเป็นเลข id ของงานซ่อม) ไม่ตรงกับที่
                // แอปมือถือใช้ (เลข id จริง) และไม่ตรงกับตัวกรองข้อความในห้อง
                // (byRepair[r.record_id]) ด้วย — ข้อความที่ส่งจากเว็บเลยถูกบันทึก
                // ลง Firebase สำเร็จ แต่ไม่โผล่ในห้องไหนเลยทั้งสองฝั่ง (เว็บเอง
                // และแอปมือถือของอีกฝ่าย) แก้โดยใช้ record_id (เลข id จริง) แทน
                // id ให้ตรงกับที่ rooms กรองไว้ — คง key={room.repair.id} ไว้
                // เหมือนเดิมได้ เพราะใช้แค่เป็น React key ไม่กระทบ logic
                const active = room.repair.record_id === selectedRepairId;
                return (
                  <button
                    key={room.repair.id}
                    onClick={() => setSelectedRepairId(room.repair.record_id)}
                    // 🎨 ห้องที่เลือกอยู่ = พื้นแดงอ่อน (ตรงกับสีแบรนด์) | ห้องอื่น
                    // = พื้นขาว โชว์เทาอ่อนตอนเอาเมาส์ชี้
                    className={`w-full text-left px-4 py-3 border-b border-slate-50 transition-colors ${
                      active ? "bg-red-50" : "hover:bg-slate-50"
                    }`}
                  >
                    {/* 🔴 [แก้ไข] ห้องแชทที่กำลังเลือกอยู่ใช้พื้นแดงอ่อน (bg-red-50)
                        ที่ตั้งใจให้อยู่เฉยๆ ไม่เปลี่ยนตามธีมมืด (เหมือน badge
                        สถานะทั่วไป) แต่ตัวหนังสือเดิมใช้ text-slate-800/
                        text-slate-400 ซึ่งโดนกฎโหมดมืดแปลงเป็นสีอ่อนเสมอ ทำให้
                        อ่านไม่ออกบนพื้นอ่อนที่ไม่เปลี่ยนสีตาม (ตัวหนังสือจาง
                        เกือบขาวบนพื้นชมพูอ่อน) — เฉพาะตอน active เปลี่ยนมาใช้สี
                        เทาเข้ม/ดำคงที่ผ่าน inline style แทน ไม่โดนกฎโหมดมืดแตะ
                        เลย ห้องที่ไม่ได้เลือกอยู่พื้นเป็น bg-white ซึ่งกฎโหมดมืด
                        แปลงให้เข้มขึ้นอยู่แล้ว เลยยังใช้ text-slate-* แบบเดิมได้
                        ปกติ ไม่ต้องแก้ */}
                    <p
                      className={active ? "text-sm font-medium truncate" : "text-sm font-medium text-slate-800 truncate"}
                      style={active ? { color: "#1e293b" } : undefined}
                    >
                      {room.repair.ticketNo || `#${room.repair.id}`} — {room.repair.customer_username || "-"}
                    </p>
                    <p
                      className={active ? "text-xs truncate mt-0.5" : "text-xs text-slate-400 truncate mt-0.5"}
                      style={active ? { color: "#475569" } : undefined}
                    >
                      {room.last
                        ? room.last.is_deleted
                          ? "ข้อความถูกลบแล้ว"
                          : room.last.message || "📷 รูปภาพ"
                        : "ยังไม่มีข้อความ"}
                    </p>
                  </button>
                );
              })
            )}
          </div>
        </div>

        {/* หน้าต่างสนทนา */}
        {selectedRoom ? (
          <div className="flex-1 flex flex-col min-w-0">
            <div className="px-5 py-3 border-b border-slate-100 shrink-0 flex items-center gap-2">
              {/* 🔴 [แก้ไข] ปุ่มย้อนกลับไปรายชื่อห้อง — โชว์เฉพาะจอเล็กกว่า md
                  ที่ซ่อนแผงรายชื่อห้องไว้ตอนเปิดห้องสนทนาอยู่ */}
              <button
                onClick={() => setSelectedRepairId(null)}
                className="md:hidden w-8 h-8 rounded-lg flex items-center justify-center text-slate-500 hover:bg-slate-50 shrink-0 -ml-1"
              >
                <ArrowLeft size={18} />
              </button>
              <div className="min-w-0">
                <p className="text-sm font-semibold text-slate-800">
                  {selectedRoom.repair.ticketNo || `#${selectedRoom.repair.id}`}
                </p>
                <p className="text-xs text-slate-400">
                  ลูกค้า: {selectedRoom.repair.customer_username || "-"} · ช่าง: {selectedRoom.repair.technician_username || "ยังไม่มอบหมาย"}
                </p>
              </div>
            </div>

            <div className="flex-1 overflow-y-auto p-5 space-y-3">
              {selectedRoom.messages.length === 0 ? (
                <p className="text-xs text-slate-400 text-center py-8">ยังไม่มีข้อความในห้องนี้ ส่งข้อความแรกได้เลย</p>
              ) : (
                selectedRoom.messages.map((m, i) => {
                  const isMe = m.sender_username === admin?.username;
                  const isEditing = editingId === m.id;
                  const isImage = m.message_type === "image" && m.image_path;
                  return (
                    <div key={m.id ?? i} className={`flex ${isMe ? "justify-end" : "justify-start"} group`}>
                      <div className="max-w-[70%]">
                        {!isMe ? (
                          <p className="text-[11px] text-slate-400 mb-1 px-1">
                            {m.sender_username} ({m.sender_role})
                          </p>
                        ) : null}

                        <div className={`flex items-end gap-1.5 ${isMe ? "justify-end" : "justify-start"}`}>
                          {/* 🎨 ข้อความของเรา (แอดมิน) = ฟองสีแดงแบรนด์ ตัวอักษรขาว
                              ข้อความของอีกฝ่าย = ฟองสีเทาอ่อน ตัวอักษรเข้ม
                              🔴 [แก้ไข] ข้อความที่ถูกลบ (is_deleted) = ฟองจางลง
                              ตัวอักษรเอียง โชว์ "ข้อความถูกลบแล้ว" แทนเนื้อหาเดิม */}
                          {isEditing ? (
                            <div className="flex items-center gap-1.5">
                              <input
                                autoFocus
                                value={editDraft}
                                onChange={(e) => setEditDraft(e.target.value)}
                                onKeyDown={(e) => {
                                  if (e.key === "Enter" && !savingEdit) saveEdit(m);
                                  if (e.key === "Escape") cancelEdit();
                                }}
                                className="px-3 py-2 rounded-2xl text-sm bg-white border border-red-200 text-slate-700 focus:outline-none focus:ring-2 focus:ring-red-100 min-w-[180px]"
                              />
                              <button
                                onClick={() => saveEdit(m)}
                                disabled={savingEdit}
                                title="บันทึก"
                                className="w-7 h-7 rounded-lg flex items-center justify-center text-green-600 hover:bg-green-50 shrink-0"
                              >
                                {savingEdit ? <Loader2 size={14} className="animate-spin" /> : <Check size={14} />}
                              </button>
                              <button
                                onClick={cancelEdit}
                                title="ยกเลิก"
                                className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-400 hover:bg-slate-100 shrink-0"
                              >
                                <X size={14} />
                              </button>
                            </div>
                          ) : (
                            <>
                              {/* 🔴 [แก้ไข] ปุ่มแก้ไข/ลบ — โชว์เฉพาะข้อความของตัวเอง ที่ยัง
                                  ไม่ถูกลบ ซ่อนไว้ปกติ โผล่ตอนเอาเมาส์ชี้ที่แถวข้อความ
                                  (group-hover) ไม่ให้รกตาเวลาไม่ได้ใช้ */}
                              {isMe && !m.is_deleted ? (
                                <div className="flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity shrink-0">
                                  {!isImage ? (
                                    <button
                                      onClick={() => startEdit(m)}
                                      title="แก้ไขข้อความ"
                                      className="w-6 h-6 rounded-lg flex items-center justify-center text-slate-400 hover:bg-slate-100 hover:text-slate-600"
                                    >
                                      <Pencil size={12} />
                                    </button>
                                  ) : null}
                                  <button
                                    onClick={() => setDeleteMsgTarget(m)}
                                    title="ลบข้อความ"
                                    className="w-6 h-6 rounded-lg flex items-center justify-center text-slate-400 hover:bg-red-50 hover:text-red-500"
                                  >
                                    <Trash2 size={12} />
                                  </button>
                                </div>
                              ) : null}

                              {/* 🔴 [แก้ไข] เวลา + อ่านแล้ว — ข้อความของเรา (isMe): วางไว้
                                  "หน้า" กล่องข้อความ (ชิดกล่องด้านที่ติดกำแพงขวา) เรียง
                                  แนวตั้ง 2 บรรทัด ชิดขวาให้พอดีกับกล่อง: อ่านแล้วอยู่บน,
                                  เวลาอยู่ล่าง — ข้อความของอีกฝ่าย: ไม่ต้องมีคอลัมน์นี้
                                  (ไปอยู่ฝั่งขวาของกล่องแทน ต่อจากบรรทัดล่างสุด) */}
                              {isMe ? (
                                <div className="flex flex-col items-end justify-end pb-0.5 shrink-0">
                                  {!m.is_deleted && isMe && m.is_read ? (
                                    <span className="flex items-center gap-0.5 text-[10px] text-slate-400 whitespace-nowrap">
                                      <CheckCheck size={11} />
                                      อ่านแล้ว
                                    </span>
                                  ) : null}
                                  {/* 🔴 [แก้ไข] ย้าย "(แก้ไขแล้ว)" มาไว้หน้าเวลาแทน — เดิม
                                      อยู่ต่อท้ายในเนื้อข้อความเอง ตามที่ขอ */}
                                  <span className="text-[10px] text-slate-300 whitespace-nowrap">
                                    {!m.is_deleted && m.is_edited ? "(แก้ไขแล้ว) " : ""}
                                    {formatTime(m.created_at)}
                                  </span>
                                </div>
                              ) : null}

                              <div
                                // 🔴 [แก้ไข] ข้อความรูปภาพ = ไม่มีกรอบสี/พื้นหลัง/padding
                                // เลย (โชว์แค่รูปเปล่า ๆ) ต่างจากข้อความตัวหนังสือที่ยัง
                                // เป็นฟองสีปกติ — ใช้ isImage เช็กแยก className ตรงนี้
                                className={
                                  isImage && !m.is_deleted
                                    ? "rounded-2xl overflow-hidden"
                                    : `px-3.5 py-2 rounded-2xl text-sm ${
                                        m.is_deleted
                                          ? "bg-slate-50 text-slate-400 italic border border-slate-100"
                                          : isMe
                                          ? "bg-[#B22121] text-white"
                                          : "bg-slate-100 text-slate-700"
                                      }`
                                }
                              >
                                {m.is_deleted ? (
                                  "ข้อความถูกลบแล้ว"
                                ) : isImage ? (
                                  <img src={m.image_path} alt="รูปภาพ" className="rounded-2xl max-w-full block" />
                                ) : (
                                  m.message
                                )}
                              </div>

                              {/* 🔴 [แก้ไข] ข้อความของอีกฝ่าย: เวลาต่อจากกล่องข้อความ
                                  ทางฝั่งขวา บรรทัดเดียว ไม่มีสถานะอ่านแล้ว (อ่านแล้ว
                                  โชว์เฉพาะข้อความของเราเองเท่านั้น) — "(แก้ไขแล้ว)"
                                  ก็ย้ายมาไว้หน้าเวลาตรงนี้เหมือนกัน */}
                              {!isMe ? (
                                <span className="text-[10px] text-slate-300 whitespace-nowrap pb-0.5 shrink-0">
                                  {!m.is_deleted && m.is_edited ? "(แก้ไขแล้ว) " : ""}
                                  {formatTime(m.created_at)}
                                </span>
                              ) : null}
                            </>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })
              )}
              <div ref={bottomRef} />
            </div>

            <div className="p-4 border-t border-slate-100 flex items-center gap-2 shrink-0">
              {/* 🎨 ปุ่มเพิ่มรูปภาพ — ทรงกลมเทาอ่อนเหมือนปุ่มรองทั่วไป (ไม่ใช่สีแดง
                  แบรนด์ เพราะยังไม่ใช่การ "ส่ง") ใช้ label ครอบ input type=file
                  ที่ซ่อนไว้ เพื่อให้กดรูปแล้วเปิดตัวเลือกไฟล์ได้เลย */}
              <label
                title="ส่งรูปภาพ"
                className={`w-10 h-10 rounded-xl bg-slate-100 text-slate-500 flex items-center justify-center hover:bg-slate-200 shrink-0 cursor-pointer ${
                  uploadingImage ? "opacity-50 pointer-events-none" : ""
                }`}
              >
                {uploadingImage ? <Loader2 size={16} className="animate-spin" /> : <ImagePlus size={16} />}
                <input type="file" accept="image/*" className="hidden" onChange={handlePickImage} disabled={uploadingImage} />
              </label>
              <input
                value={draft}
                onChange={(e) => setDraft(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && !sending && handleSend()}
                placeholder="พิมพ์ข้อความ..."
                className="flex-1 px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-red-100"
              />
              <button
                onClick={handleSend}
                disabled={sending || !draft.trim()}
                // 🎨 ปุ่มส่งใช้สีแดงแบรนด์ (#B22121) เดียวกับข้อความฝั่งเรา ให้รู้สึก
                // เป็นชุดเดียวกัน
                className="w-10 h-10 rounded-xl bg-[#B22121] text-white flex items-center justify-center hover:bg-[#8B1A1A] disabled:opacity-50 shrink-0"
              >
                <Send size={16} />
              </button>
            </div>
          </div>
        ) : (
          <div className="hidden md:flex flex-1 flex-col items-center justify-center text-slate-300">
            <MessageSquare size={40} className="mb-2" />
            <p className="text-sm text-slate-400">เลือกห้องแชทจากรายการด้านซ้ายเพื่อเริ่มดูข้อความ</p>
          </div>
        )}
      </div>

      {deleteMsgTarget ? (
        <ConfirmDialog
          title="ลบข้อความ"
          message="ต้องการลบข้อความนี้ใช่หรือไม่? อีกฝ่ายจะเห็นว่า 'ข้อความถูกลบแล้ว'"
          onConfirm={confirmDeleteMessage}
          onCancel={() => setDeleteMsgTarget(null)}
          busy={deletingMsg}
        />
      ) : null}
    </div>
  );
}