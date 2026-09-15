import React, { useState, useRef, useEffect } from "react";
import { Search, Bell, MessageSquare, Wrench, Users, UserCog, X, Menu } from "lucide-react";
import useDbList from "../hooks/useDbList";

// ---------------------------------------------------------------------------
// 🔴 [แก้ไข] ช่องค้นหากลางที่เคยเป็นแค่ของตกแต่ง (พิมพ์แล้วไม่มีอะไรเกิดขึ้น) —
// ตอนนี้ค้นได้จริงข้าม 3 หมวด (งานซ่อม/ลูกค้า/ช่าง) พร้อมกัน โชว์ผลลัพธ์แบบ
// dropdown สูงสุดหมวดละ 5 รายการ กดแล้วพาไปหน้านั้นพร้อมส่งคำค้นเข้าไปเป็น
// initialQuery ให้หน้าปลายทางกรองต่อให้เลย (แต่ละหน้ามีช่องค้นหาของตัวเองอยู่
// แล้ว แค่ยังไม่เคยเชื่อมกับช่องค้นหากลางนี้)
// ---------------------------------------------------------------------------
function GlobalSearch({ onNavigate }) {
  const [term, setTerm] = useState("");
  const [open, setOpen] = useState(false);
  const boxRef = useRef(null);
  const { data: repairs } = useDbList("repairs");
  const { data: customers } = useDbList("customers");
  const { data: technicians } = useDbList("technicians");

  useEffect(() => {
    function handleClickOutside(e) {
      if (boxRef.current && !boxRef.current.contains(e.target)) setOpen(false);
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const q = term.trim().toLowerCase();
  const hasQuery = q.length > 0;

  const jobResults = hasQuery
    ? repairs
        .filter(
          (r) =>
            String(r.ticketNo || r.id || "").toLowerCase().includes(q) ||
            (r.customer_username || "").toLowerCase().includes(q) ||
            (r.machine || "").toLowerCase().includes(q)
        )
        .slice(0, 5)
    : [];
  const customerResults = hasQuery
    ? customers
        .filter(
          (c) =>
            (c.name || "").toLowerCase().includes(q) ||
            (c.surname || "").toLowerCase().includes(q) ||
            (c.company || "").toLowerCase().includes(q) ||
            (c.username || "").toLowerCase().includes(q)
        )
        .slice(0, 5)
    : [];
  const techResults = hasQuery
    ? technicians
        .filter(
          (t) =>
            (t.tech_name || t.name || "").toLowerCase().includes(q) ||
            (t.username || "").toLowerCase().includes(q) ||
            (t.employee_id || "").toLowerCase().includes(q)
        )
        .slice(0, 5)
    : [];

  const noResults = hasQuery && jobResults.length === 0 && customerResults.length === 0 && techResults.length === 0;

  function goTo(page, query) {
    onNavigate?.(page, { query });
    setOpen(false);
    setTerm("");
  }

  return (
    <div className="relative" ref={boxRef}>
      <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
      <input
        value={term}
        onChange={(e) => {
          setTerm(e.target.value);
          setOpen(true);
        }}
        onFocus={() => setOpen(true)}
        placeholder="ค้นหางาน, ลูกค้า, ช่าง, Job ID..."
        className="w-40 sm:w-56 md:w-72 pl-9 pr-8 py-2 rounded-xl bg-white border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
      />
      {term ? (
        <button
          onClick={() => {
            setTerm("");
            setOpen(false);
          }}
          className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500"
        >
          <X size={14} />
        </button>
      ) : null}

      {open && hasQuery ? (
        <div className="absolute left-0 mt-2 w-[88vw] max-w-96 bg-white border border-slate-100 rounded-xl shadow-lg py-2 z-20 max-h-[70vh] overflow-y-auto">
          {noResults ? (
            <p className="text-xs text-slate-400 text-center py-6">ไม่พบผลลัพธ์ที่ตรงกับ "{term}"</p>
          ) : (
            <>
              {jobResults.length > 0 ? (
                <div className="mb-1">
                  <p className="px-3 py-1 text-[11px] font-semibold text-slate-400">งานซ่อม</p>
                  {jobResults.map((r) => (
                    <button
                      key={r.id}
                      onClick={() => goTo("jobs", String(r.ticketNo || r.id))}
                      className="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-slate-50 text-left"
                    >
                      <Wrench size={14} className="text-blue-400 shrink-0" />
                      <div className="min-w-0">
                        <p className="text-sm text-slate-700 truncate">{r.ticketNo || `#${r.id}`} · {r.customer_username || "-"}</p>
                        <p className="text-xs text-slate-400 truncate">{r.machine || "-"}</p>
                      </div>
                    </button>
                  ))}
                </div>
              ) : null}

              {customerResults.length > 0 ? (
                <div className="mb-1">
                  <p className="px-3 py-1 text-[11px] font-semibold text-slate-400">ลูกค้า</p>
                  {customerResults.map((c) => (
                    <button
                      key={c.id}
                      onClick={() => goTo("customers", c.name || c.username)}
                      className="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-slate-50 text-left"
                    >
                      <Users size={14} className="text-emerald-400 shrink-0" />
                      <div className="min-w-0">
                        <p className="text-sm text-slate-700 truncate">{[c.name, c.surname].filter(Boolean).join(" ") || c.username}</p>
                        <p className="text-xs text-slate-400 truncate">{c.company || c.username}</p>
                      </div>
                    </button>
                  ))}
                </div>
              ) : null}

              {techResults.length > 0 ? (
                <div>
                  <p className="px-3 py-1 text-[11px] font-semibold text-slate-400">ช่างเทคนิค</p>
                  {techResults.map((t) => (
                    <button
                      key={t.id}
                      onClick={() => goTo("technicians", t.tech_name || t.name || t.username)}
                      className="w-full flex items-center gap-2.5 px-3 py-2 hover:bg-slate-50 text-left"
                    >
                      <UserCog size={14} className="text-orange-400 shrink-0" />
                      <div className="min-w-0">
                        <p className="text-sm text-slate-700 truncate">{t.tech_name || t.name || t.username}</p>
                        <p className="text-xs text-slate-400 truncate">{t.employee_id ? `รหัส ${t.employee_id}` : t.username}</p>
                      </div>
                    </button>
                  ))}
                </div>
              ) : null}
            </>
          )}
        </div>
      ) : null}
    </div>
  );
}

export default function Header({ greeting, subtitle, admin, onNavigate, unreadNotifications = 0, unreadChats = 0, onMenuClick }) {
  const displayName = admin?.admin_name || admin?.username || "Admin";
  const initial = displayName?.[0] ?? "A";
  return (
    <header className="flex items-center justify-between px-4 sm:px-8 py-4 sm:py-6 gap-3">
      <div className="flex items-center gap-3 min-w-0">
        {/* 🔴 [แก้ไข] ปุ่มเปิดเมนู (hamburger) — โชว์เฉพาะจอเล็กกว่า lg (<1024px) ที่
            แถบเมนูซ้ายถูกซ่อนเป็น overlay แทนการตรึงไว้ตลอด */}
        <button
          onClick={onMenuClick}
          className="lg:hidden w-9 h-9 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-500 hover:bg-slate-50 shrink-0"
        >
          <Menu size={18} />
        </button>
        <div className="min-w-0">
          {/* 🔤 text-2xl font-semibold = คำทักทาย/ชื่อหน้า (ใหญ่สุดบนหน้าจอ)
              text-slate-900 = สีตัวอักษรเกือบดำ — ย่อขนาดลงบนจอเล็กด้วย text-lg */}
          <h1 className="text-lg sm:text-2xl font-semibold text-slate-900 truncate">{greeting}</h1>
          {/* 🔤 text-sm text-slate-500 = คำอธิบายย่อยใต้หัวข้อ (เล็ก สีเทา) —
              ซ่อนบนจอเล็กมากเพื่อประหยัดพื้นที่แนวตั้ง */}
          <p className="hidden sm:block text-sm text-slate-500 mt-0.5">{subtitle}</p>
        </div>
      </div>

      <div className="flex items-center gap-2 sm:gap-4 shrink-0">
        <GlobalSearch onNavigate={onNavigate} />

        {/* 🔴 [แก้ไข] เดิม 2 ปุ่มนี้กดไม่ได้เลย (แค่ตกแต่ง) — เชื่อมให้ไปหน้า
            แจ้งเตือน/แชทจริงแล้ว 🎨 ปุ่มไอคอนกลม พื้นขาวขอบเทา (ทั้งกระดิ่ง
            แจ้งเตือนและไอคอนแชท ใช้สไตล์เดียวกัน) — w-9 h-9 = ขนาดปุ่ม (36x36px) */}
        <button
          onClick={() => onNavigate?.("notifications")}
          className="relative w-9 h-9 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-500 hover:bg-slate-50"
        >
          <Bell size={17} />
          {unreadNotifications > 0 ? (
            // 🎨 badge ตัวเลขแจ้งเตือนที่ยังไม่อ่าน สีแดง มุมขวาบนของกระดิ่ง
            <span className="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-red-500 text-white text-[10px] font-semibold flex items-center justify-center">
              {unreadNotifications > 9 ? "9+" : unreadNotifications}
            </span>
          ) : null}
        </button>

        <button
          onClick={() => onNavigate?.("chat")}
          className="relative w-9 h-9 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-500 hover:bg-slate-50"
        >
          <MessageSquare size={17} />
          {unreadChats > 0 ? (
            // 🔴 [แก้ไข] เพิ่ม badge ตัวเลขข้อความแชทที่ยังไม่อ่าน แบบเดียวกับ
            // ไอคอนกระดิ่งด้านบน — เดิมไม่มีเลย
            <span className="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-red-500 text-white text-[10px] font-semibold flex items-center justify-center">
              {unreadChats > 9 ? "9+" : unreadChats}
            </span>
          ) : null}
        </button>

        <div className="flex items-center gap-2 pl-2">
          {/* 🎨 bg-blue-500 = สีวงกลม avatar ตัวอักษรแรกของชื่อแอดมิน (สีน้ำเงิน
              มาตรฐานของเว็บ — คนละสีกับแถบเมนูซ้ายที่เป็นสีแดงแบรนด์ตั้งใจ
              แยกกันเพื่อไม่ให้ปนกับสีแบรนด์หลัก)
              📷 [ใหม่] โชว่รูปโปรไฟล์จริงถ้ามี (admin.photo_url — เพิ่งเปิดให้
              แก้ไขได้จากหน้าตั้งค่า → บัญชีของฉัน) ไม่มีก็ fallback เป็นตัวอักษร
              แรกของชื่อเหมือนเดิม */}
          <div className="w-9 h-9 rounded-full bg-blue-500 text-white flex items-center justify-center text-sm font-semibold shrink-0 overflow-hidden">
            {admin?.photo_url ? (
              <img src={admin.photo_url} alt={displayName} className="w-full h-full object-cover" />
            ) : (
              initial
            )}
          </div>
          {/* 🔴 [แก้ไข] ซ่อนชื่อ/ตำแหน่งบนจอเล็ก (เหลือแค่ avatar) ประหยัดพื้นที่
              แนวนอน — จอ sm ขึ้นไปแสดงเหมือนเดิมทุกประการ */}
          <div className="hidden sm:block leading-tight">
            <p className="text-sm font-medium text-slate-800">{displayName}</p>
            <p className="text-xs text-slate-400">ผู้ดูแลระบบ</p>
          </div>
        </div>
      </div>
    </header>
  );
}

