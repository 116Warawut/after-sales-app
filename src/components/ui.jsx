import React, { useEffect, useRef, useState } from "react";
import { X, Loader2, Star, ChevronLeft, ChevronRight, Calendar } from "lucide-react";

// การ์ดพื้นฐาน — ใช้ห่อทุกบล็อกเนื้อหาให้หน้าตาสม่ำเสมอกันทั้งเว็บ
export function Card({ children, className = "" }) {
  return (
    <div
      // 🎨 bg-white = สีพื้นหลังการ์ด (ขาว) | border-slate-100 = สีเส้นขอบการ์ด
      // (เทาอ่อนมาก) | rounded-2xl = ความโค้งมุม | p-5 = ระยะห่างขอบใน
      className={`bg-white rounded-2xl border border-slate-100 p-5 ${className}`}
    >
      {children}
    </div>
  );
}

// หัวข้อบนสุดของแต่ละหน้า (ชื่อหน้า + คำอธิบายสั้น ๆ + ปุ่ม action ฝั่งขวา ถ้ามี)
export function PageHeader({ title, subtitle, action }) {
  return (
    <div className="flex items-start justify-between mb-6">
      <div>
        {/* 🔤 text-xl = ขนาดตัวอักษรหัวข้อหน้า | font-semibold = น้ำหนักตัวหนา
            ปานกลาง | text-slate-900 = สีตัวอักษร (เกือบดำ) */}
        <h2 className="text-xl font-semibold text-slate-900">{title}</h2>
        {subtitle ? (
          // 🔤 text-sm = ขนาดเล็กกว่าหัวข้อ | text-slate-500 = สีเทาอ่อนกว่า (รอง)
          <p className="text-sm text-slate-500 mt-1">{subtitle}</p>
        ) : null}
      </div>
      {action}
    </div>
  );
}

// ข้อความ "ยังไม่มีข้อมูล" มาตรฐาน — ใช้แทนตำแหน่งที่รอข้อมูลจริงจาก Firebase
export function EmptyState({ icon: Icon, message = "ยังไม่มีข้อมูล" }) {
  return (
    // 🎨 text-slate-300 = สีไอคอนจาง ๆ (เทาอ่อนมาก บอกว่ายังไม่มีข้อมูลจริง)
    <div className="flex flex-col items-center justify-center py-12 text-slate-300">
      {Icon ? <Icon size={32} className="mb-2" /> : null}
      {/* 🎨 text-slate-400 = สีตัวอักษรข้อความว่างเปล่า */}
      <p className="text-sm text-slate-400">{message}</p>
    </div>
  );
}

// 🔴 [ใหม่] แสดงคะแนนดาว (อ่านอย่างเดียว ไม่กดแก้ได้จากฝั่งแอดมิน — ลูกค้าเป็น
// คนให้คะแนนจากแอปมือถือ เว็บแค่แสดงผล) ใช้ทั้งในการ์ดช่าง (ค่าเฉลี่ย, รองรับ
// ทศนิยมเช่น 4.5 โดยปัดเป็นดาวเต็ม/ดาวเปล่า) และใน JobDetailModal (คะแนนของ
// งานเดียว ไม่มีทศนิยม) — value เป็น null แปลว่ายังไม่มีใครให้คะแนนเลย
// 🎨 amber-400 = สีดาวที่ได้คะแนน (เหลืองทอง มาตรฐานของรีวิว) | slate-200 = สีดาว
// ที่ยังไม่ได้คะแนน (เทาอ่อนมาก ให้เห็นเป็นเงาดาว 5 ดวงเสมอ)
export function StarRating({ value, size = 14, showValue = true, emptyLabel = "ยังไม่มีคะแนน" }) {
  if (value === null || value === undefined) {
    return <span className="text-xs text-slate-400">{emptyLabel}</span>;
  }
  const rounded = Math.round(value);
  return (
    <div className="flex items-center gap-1">
      <div className="flex items-center gap-0.5">
        {[1, 2, 3, 4, 5].map((n) => (
          <Star
            key={n}
            size={size}
            className={n <= rounded ? "fill-amber-400 text-amber-400" : "fill-slate-200 text-slate-200"}
          />
        ))}
      </div>
      {showValue ? (
        <span className="text-xs font-medium text-slate-600">{value.toFixed(1)}</span>
      ) : null}
    </div>
  );
}

// ปุ่มหลักสีน้ำเงิน มาตรฐานของทั้งเว็บ (เช่น "เพิ่มลูกค้าใหม่", "บันทึกการตั้งค่า")
export function PrimaryButton({ children, icon: Icon, onClick, disabled, className = "" }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      // 🎨 bg-blue-500 = สีพื้นหลังปุ่มหลัก (น้ำเงิน) | hover:bg-blue-600 = สีตอน
      // เอาเมาส์ชี้ (เข้มขึ้น) | rounded-xl = ความโค้งมุมปุ่ม | disabled:opacity-50
      // = ความจางตอนกดไม่ได้ (เช่นระหว่างบันทึก)
      className={`flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50 transition-colors ${className}`}
    >
      {Icon ? <Icon size={16} /> : null}
      {children}
    </button>
  );
}

// ปุ่มรอง (ขอบเทา พื้นขาว) — ใช้กับ "ยกเลิก", "แก้ไข" ในตาราง/การ์ด
export function SecondaryButton({ children, icon: Icon, onClick, className = "" }) {
  return (
    <button
      onClick={onClick}
      // 🎨 bg-white + border-slate-200 = ปุ่มพื้นขาวขอบเทาอ่อน (ตรงข้ามปุ่มหลัก)
      // hover:bg-slate-50 = สีตอนชี้เมาส์ (เทาจางมาก)
      className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-white border border-slate-200 text-xs font-medium text-slate-600 hover:bg-slate-50 transition-colors ${className}`}
    >
      {Icon ? <Icon size={13} /> : null}
      {children}
    </button>
  );
}

// ปุ่มไอคอนกลม เล็ก ๆ — ใช้กับ "แก้ไข"/"ลบ" ท้ายแถวตาราง
export function IconButton({ icon: Icon, onClick, tone = "slate", title }) {
  // 🎨 กำหนดสีตาม tone ที่ส่งเข้ามา — "red" ใช้กับปุ่มลบ, "blue" ใช้กับปุ่มแก้ไข,
  // ค่าเริ่มต้น (slate) ใช้กับปุ่มทั่วไปที่ไม่มีความหมายเชิงอันตราย/แก้ไข
  const toneClass =
    tone === "red"
      ? "text-red-500 hover:bg-red-50"
      : tone === "blue"
      ? "text-blue-500 hover:bg-blue-50"
      : "text-slate-400 hover:bg-slate-100";
  return (
    <button
      onClick={onClick}
      title={title}
      // 🎨 w-7 h-7 = ขนาดปุ่มวงกลม (28x28px) | rounded-lg = ความโค้งมุม
      className={`w-7 h-7 rounded-lg flex items-center justify-center transition-colors ${toneClass}`}
    >
      <Icon size={14} />
    </button>
  );
}

// ช่องกรอกข้อมูลมาตรฐานสำหรับฟอร์มเพิ่ม/แก้ไข
// 🔴 [แก้ไข] ขยายขนาดตัวหนังสือ/ช่องกรอกให้ใหญ่อ่านง่ายขึ้น (เดิมเล็กไป)
export function FormField({ label, value, onChange, type = "text", placeholder, required }) {
  return (
    <div>
      {/* 🔤 text-sm + font-medium = label ของช่องกรอก | text-red-400 = สี * แดง
          บอกว่าฟิลด์นี้บังคับกรอก */}
      <label className="text-sm text-slate-600 mb-2 block font-medium">
        {label} {required ? <span className="text-red-400">*</span> : null}
      </label>
      <input
        type={type}
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        // 🎨 bg-slate-50 = สีพื้นหลังช่องกรอก (เทาอ่อนมาก ต่างจากพื้นขาวรอบ ๆ
        // เล็กน้อยให้เห็นขอบเขตชัด) | border-slate-200 = สีเส้นขอบปกติ
        // focus:ring-2 focus:ring-blue-100 = วงแหวนสีฟ้าอ่อนตอนคลิกเข้าไปกรอก
        // 🔤 text-[15px] = ขนาดตัวอักษรในช่องกรอก (ใหญ่กว่ามาตรฐาน text-sm เดิม)
        className="w-full px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
      />
    </div>
  );
}

// ช่องข้อความหลายบรรทัด (เช่น หมายเหตุ, รายละเอียด)
export function TextAreaField({ label, value, onChange, placeholder, rows = 3, required }) {
  return (
    <div>
      <label className="text-sm text-slate-600 mb-2 block font-medium">
        {label} {required ? <span className="text-red-400">*</span> : null}
      </label>
      {/* สไตล์เดียวกับ FormField ด้านบนทุกอย่าง ต่างแค่เป็น textarea หลายบรรทัด
          resize-none = ห้ามผู้ใช้ลากขยาย/ย่อกล่องเอง (คุมขนาดด้วย rows แทน) */}
      <textarea
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        rows={rows}
        className="w-full px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100 resize-none"
      />
    </div>
  );
}

// หน้าต่าง Modal กลาง — ใช้กับฟอร์มเพิ่ม/แก้ไขข้อมูลทุกหน้า (อะไหล่/ช่าง/ลูกค้า/แอดมิน)
// 🔴 [แก้ไข] ขยายจาก max-w-md เป็น max-w-xl + เพิ่ม padding/ขนาดตัวหนังสือหัวข้อ
// เดิมรู้สึกเล็กไปเวลาใช้งานจริง โดยเฉพาะฟอร์มที่มีหลายช่อง
// 🔴 [แก้ไข] เพิ่ม prop "maxWidth" (ส่ง class Tailwind เช่น "max-w-5xl" ตรงๆ)
// ไว้ override ความกว้างแบบละเอียดกว่า wide=true เดิม (ซึ่งให้แค่ max-w-2xl
// ตายตัว) — ใช้เฉพาะจุดที่ต้องการกว้างเป็นพิเศษ เช่น ReportPreviewModal ใน
// DashboardPage.jsx โดยไม่กระทบ modal อื่นที่ใช้ wide=true อยู่แล้วทั่วเว็บ
// (CustomersPage, FinancePage, SettingsPage, TechniciansPage ฯลฯ ยังกว้าง
// max-w-2xl เท่าเดิมทุกที่ ไม่ได้รับผลกระทบจาก prop ใหม่นี้เลย)
export function Modal({ title, onClose, children, footer, wide, maxWidth }) {
  const widthClass = maxWidth || (wide ? "max-w-2xl" : "max-w-xl");
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      {/* 🎨 bg-slate-900/40 = สีฉากหลังทึบแสงด้านหลัง modal (ดำโปร่งแสง 40%) */}
      <div className="absolute inset-0 bg-slate-900/40" onClick={onClose} />
      {/* 📏 max-w-xl (ปกติ) / max-w-2xl (ถ้าส่ง wide=true) / กำหนดเองผ่าน
          maxWidth = ความกว้างสูงสุดของกล่อง modal — ปรับตรงนี้ถ้าอยากให้ modal
          กว้าง/แคบกว่านี้ */}
      <div className={`relative bg-white rounded-2xl shadow-xl w-full ${widthClass} max-h-[88vh] overflow-y-auto`}>
        {/* 🎨 border-b border-slate-100 = เส้นคั่นใต้หัวข้อ modal (เทาอ่อนมาก) */}
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100">
          <h3 className="text-base font-semibold text-slate-800">{title}</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">
            <X size={20} />
          </button>
        </div>
        <div className="p-6 space-y-5">{children}</div>
        {footer ? (
          // 🎨 border-t border-slate-100 = เส้นคั่นเหนือแถบปุ่มด้านล่าง modal
          <div className="flex items-center justify-end gap-3 px-6 py-5 border-t border-slate-100">{footer}</div>
        ) : null}
      </div>
    </div>
  );
}

// กล่องยืนยันก่อนลบ — ใช้ทุกจุดที่มีปุ่ม "ลบ" ในเว็บนี้ กันกดพลาด
export function ConfirmDialog({ title = "ยืนยันการลบ", message, onConfirm, onCancel, busy }) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-900/40" onClick={onCancel} />
      <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-md p-6">
        <h3 className="text-base font-semibold text-slate-800 mb-2">{title}</h3>
        <p className="text-[15px] text-slate-500 mb-6">{message}</p>
        <div className="flex items-center justify-end gap-3">
          <SecondaryButton onClick={onCancel}>ยกเลิก</SecondaryButton>
          <button
            onClick={onConfirm}
            disabled={busy}
            // 🎨 bg-red-500/hover:bg-red-600 = ปุ่ม "ลบ" สีแดงเสมอ (ตัดกับปุ่มหลัก
            // สีน้ำเงินปกติ เพื่อเตือนว่าเป็นการกระทำที่กู้คืนไม่ได้)
            className="flex items-center gap-1.5 px-5 py-2.5 rounded-xl bg-red-500 text-white text-[15px] font-medium hover:bg-red-600 disabled:opacity-50"
          >
            {busy ? <Loader2 size={14} className="animate-spin" /> : null}
            ลบ
          </button>
        </div>
      </div>
    </div>
  );
}

// 🆕 ตัวควบคุมแบ่งหน้า (ก่อนหน้า/ถัดไป + "หน้า X จาก Y") — ใช้ร่วมกันในหน้าที่
// อ่านค่า "จำนวนรายการต่อหน้า" จากหน้าตั้งค่า (ดู useWebSettings.js) ไม่แสดงผล
// อะไรเลยถ้ามีแค่หน้าเดียว (totalPages <= 1) กันไม่ให้รกจอตอนรายการน้อย
export function Pagination({ page, totalPages, onChange, totalItems, pageSize }) {
  if (totalPages <= 1) return null;
  const from = totalItems === 0 ? 0 : (page - 1) * pageSize + 1;
  const to = Math.min(page * pageSize, totalItems);
  return (
    <div className="flex items-center justify-between gap-3 pt-4 mt-1 border-t border-slate-100 flex-wrap">
      <p className="text-xs text-slate-400">
        {totalItems != null ? `แสดง ${from}-${to} จาก ${totalItems} รายการ • ` : ""}หน้า {page}/{totalPages}
      </p>
      <div className="flex items-center gap-2">
        <button
          onClick={() => onChange(Math.max(1, page - 1))}
          disabled={page <= 1}
          className="w-8 h-8 rounded-lg flex items-center justify-center border border-slate-200 text-slate-600 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50"
        >
          <ChevronLeft size={15} />
        </button>
        <button
          onClick={() => onChange(Math.min(totalPages, page + 1))}
          disabled={page >= totalPages}
          className="w-8 h-8 rounded-lg flex items-center justify-center border border-slate-200 text-slate-600 disabled:opacity-40 disabled:cursor-not-allowed hover:bg-slate-50"
        >
          <ChevronRight size={15} />
        </button>
      </div>
    </div>
  );
}

// ---------------------------------------------------------------------------
// 🆕 [ใหม่] ปฏิทินเลือกวันที่แบบสร้างเอง — แทนที่ <input type="date"> เดิม
// (ตอนใช้ input ของเบราว์เซอร์ตรงๆ รูปแบบวันที่ที่โชว์ในช่อง — วว/ดด/ปปปป หรือ
// ดด/วว/ปปปป — ถูกกำหนดโดยภาษา/OS ของผู้ใช้เอง ไม่ใช่โดยเว็บนี้) ปฏิทินนี้วาด
// เองทั้งหมดด้วย React ธรรมดา จึงคุมข้อความที่โชว์ได้เต็มที่
// 🔴 [แก้ไข] ตัดตัวเลือกปี ค.ศ. ออกทั้งระบบตามที่ขอ — ช่องปุ่มและหัวปฏิทินโชว่
// ปี พ.ศ. เสมอ (เดือนเป็นชื่อเต็มภาษาไทยเสมอเช่นเดิม)
//
// รับ/คืนค่าเป็น ISO string "YYYY-MM-DD" เหมือน <input type="date"> เดิมทุก
// ประการ (ไม่กระทบโค้ดส่วนอื่นที่อ่าน/บันทึกค่านี้ต่อ) — เปลี่ยนแค่หน้าตาช่อง
// กรอกกับปฏิทินป๊อปอัปเท่านั้น
// ---------------------------------------------------------------------------
const THAI_MONTHS_FULL = [
  "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
  "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม",
];
const THAI_MONTHS_ABBR = [
  "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
  "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
];
const THAI_WEEKDAYS = ["อา", "จ", "อ", "พ", "พฤ", "ศ", "ส"];

function isoToYMD(iso) {
  if (!iso) return null;
  const [y, m, d] = iso.split("-").map(Number);
  if (!y || !m || !d) return null;
  return { y, m, d };
}
function ymdToIso(y, m, d) {
  return `${String(y).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}
function displayYear(gregorianYear) {
  return gregorianYear + 543;
}

export function DateField({ value, onChange, min, max, disabled, placeholder = "เลือกวันที่" }) {
  const [open, setOpen] = useState(false);
  const selected = isoToYMD(value);
  const minYMD = isoToYMD(min);
  const maxYMD = isoToYMD(max);
  const today = new Date();
  // เดือนที่กำลังเปิดดูอยู่ในปฏิทิน (เริ่มจากวันที่เลือกไว้ ถ้ายังไม่เลือกก็เริ่มจากเดือนปัจจุบัน)
  const [viewY, setViewY] = useState(selected ? selected.y : today.getFullYear());
  const [viewM, setViewM] = useState(selected ? selected.m : today.getMonth() + 1);
  const wrapRef = useRef(null);

  useEffect(() => {
    if (!open) return;
    const s = isoToYMD(value);
    setViewY(s ? s.y : today.getFullYear());
    setViewM(s ? s.m : today.getMonth() + 1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open]);

  useEffect(() => {
    if (!open) return;
    function onDocClick(e) {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(false);
    }
    function onEsc(e) {
      if (e.key === "Escape") setOpen(false);
    }
    document.addEventListener("mousedown", onDocClick);
    document.addEventListener("keydown", onEsc);
    return () => {
      document.removeEventListener("mousedown", onDocClick);
      document.removeEventListener("keydown", onEsc);
    };
  }, [open]);

  const label = selected
    ? `${selected.d} ${THAI_MONTHS_ABBR[selected.m - 1]} ${displayYear(selected.y)}`
    : placeholder;

  function ymdKey(y, m, d) {
    return y * 10000 + m * 100 + d;
  }
  const minKey = minYMD ? ymdKey(minYMD.y, minYMD.m, minYMD.d) : null;
  const maxKey = maxYMD ? ymdKey(maxYMD.y, maxYMD.m, maxYMD.d) : null;
  function isDisabled(y, m, d) {
    const k = ymdKey(y, m, d);
    if (minKey != null && k < minKey) return true;
    if (maxKey != null && k > maxKey) return true;
    return false;
  }

  const firstOfMonth = new Date(viewY, viewM - 1, 1);
  const daysInMonth = new Date(viewY, viewM, 0).getDate();
  const startWeekday = firstOfMonth.getDay(); // 0 = อาทิตย์
  const cells = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(d);

  function goPrevMonth() {
    if (viewM === 1) { setViewM(12); setViewY(viewY - 1); } else setViewM(viewM - 1);
  }
  function goNextMonth() {
    if (viewM === 12) { setViewM(1); setViewY(viewY + 1); } else setViewM(viewM + 1);
  }
  function pickDay(d) {
    if (isDisabled(viewY, viewM, d)) return;
    onChange(ymdToIso(viewY, viewM, d));
    setOpen(false);
  }

  return (
    <div className="relative" ref={wrapRef}>
      <button
        type="button"
        disabled={disabled}
        onClick={() => setOpen((v) => !v)}
        className={`w-full flex items-center gap-2 px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-left focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:opacity-60 disabled:cursor-not-allowed ${selected ? "text-slate-700" : "text-slate-400"}`}
      >
        <Calendar size={15} className="text-slate-400 shrink-0" />
        <span className="truncate">{label}</span>
      </button>

      {open ? (
        // 🎨 ป๊อปอัปปฏิทิน — การ์ดขาวลอยใต้ปุ่ม เงาเบา ๆ กันขอบจอบัง
        <div className="absolute z-[9999] mt-1.5 w-72 bg-white rounded-xl border border-slate-200 shadow-lg p-3">
          <div className="flex items-center justify-between mb-2">
            <button type="button" onClick={goPrevMonth} className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-500 hover:bg-slate-50">
              <ChevronLeft size={15} />
            </button>
            <p className="text-sm font-semibold text-slate-700">
              {THAI_MONTHS_FULL[viewM - 1]} {displayYear(viewY)}
            </p>
            <button type="button" onClick={goNextMonth} className="w-7 h-7 rounded-lg flex items-center justify-center text-slate-500 hover:bg-slate-50">
              <ChevronRight size={15} />
            </button>
          </div>
          <div className="grid grid-cols-7 mb-1">
            {THAI_WEEKDAYS.map((w) => (
              <div key={w} className="text-center text-[11px] text-slate-400 py-1">{w}</div>
            ))}
          </div>
          <div className="grid grid-cols-7 gap-y-1">
            {cells.map((d, i) => {
              if (d == null) return <div key={`blank-${i}`} />;
              const isSelected = selected && selected.y === viewY && selected.m === viewM && selected.d === d;
              const isToday = today.getFullYear() === viewY && today.getMonth() + 1 === viewM && today.getDate() === d;
              const dis = isDisabled(viewY, viewM, d);
              return (
                <button
                  type="button"
                  key={d}
                  disabled={dis}
                  onClick={() => pickDay(d)}
                  className={`w-9 h-9 mx-auto rounded-lg text-sm flex items-center justify-center
                    ${isSelected ? "bg-blue-500 text-white font-semibold" : dis ? "text-slate-300 cursor-not-allowed" : "text-slate-700 hover:bg-slate-100"}
                    ${isToday && !isSelected ? "border border-blue-200" : ""}`}
                >
                  {d}
                </button>
              );
            })}
          </div>
        </div>
      ) : null}
    </div>
  );
}

// ---------------------------------------------------------------------------
// 🆕 [ใหม่] ตัวเลือกเวลา (ชั่วโมง:นาที) แบบง่าย — ใช้คู่กับ DateField ตอน
// เลือกวันเวลานัดหมายช่าง รับ/คืนค่าเป็นสตริง "HH:MM" แบบ 24 ชั่วโมง (เช่น
// "09:05", "23:59") เลือกได้ตั้งแต่ 00:00 ถึง 23:59 ไม่มีข้อจำกัดอื่น (ข้อจำกัด
// เรื่อง "ห้ามเลือกวันในอดีต" อยู่ที่ DateField คู่กันอยู่แล้ว)
// ---------------------------------------------------------------------------
const HOURS_24 = Array.from({ length: 24 }, (_, i) => String(i).padStart(2, "0"));
const MINUTES_60 = Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0"));

export function TimeField({ value, onChange, disabled }) {
  const [h, m] = (value || "").split(":");
  const hour = HOURS_24.includes(h) ? h : "";
  const minute = MINUTES_60.includes(m) ? m : "";

  function setHour(newH) {
    onChange(`${newH}:${minute || "00"}`);
  }
  function setMinute(newM) {
    onChange(`${hour || "00"}:${newM}`);
  }

  return (
    <div className="flex items-center gap-2">
      <select
        value={hour}
        onChange={(e) => setHour(e.target.value)}
        disabled={disabled}
        className="px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:opacity-60"
      >
        <option value="" disabled>ชม.</option>
        {HOURS_24.map((v) => (
          <option key={v} value={v}>{v}</option>
        ))}
      </select>
      <span className="text-slate-400 font-medium">:</span>
      <select
        value={minute}
        onChange={(e) => setMinute(e.target.value)}
        disabled={disabled}
        className="px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:opacity-60"
      >
        <option value="" disabled>นาที</option>
        {MINUTES_60.map((v) => (
          <option key={v} value={v}>{v}</option>
        ))}
      </select>
    </div>
  );
}
