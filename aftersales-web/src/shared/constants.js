// 🔴 [ใหม่] Geoapify API Key เดียวกับที่ฝั่ง Flutter ใช้ (lib/geoapify_service.dart)
// ใช้สำหรับดึงไทล์แผนที่ + คำนวณเส้นทาง/ระยะทาง/เวลาให้แผนที่ตำแหน่งช่างฝั่งเว็บ
// (JobLocationMap ใน components/JobDetailModal.jsx) แสดงผลแบบเดียวกับหน้าจอ
// ติดตามงานซ่อมของแอดมินบนมือถือ (admin_tracking.dart)
export const GEOAPIFY_API_KEY = "a59572fd4e7b414b9a477031873bb341";

export const COLORS = {
  blue: { bg: "bg-blue-50", text: "text-blue-600", dot: "bg-blue-500", border: "border-blue-200" },
  orange: { bg: "bg-orange-50", text: "text-orange-600", dot: "bg-orange-500", border: "border-orange-200" },
  yellow: { bg: "bg-amber-50", text: "text-amber-600", dot: "bg-amber-500", border: "border-amber-200" },
  violet: { bg: "bg-violet-50", text: "text-violet-600", dot: "bg-violet-500", border: "border-violet-200" },
  green: { bg: "bg-emerald-50", text: "text-emerald-600", dot: "bg-emerald-500", border: "border-emerald-200" },
  red: { bg: "bg-red-50", text: "text-red-600", dot: "bg-red-500", border: "border-red-200" },
  gray: { bg: "bg-slate-100", text: "text-slate-500", dot: "bg-slate-400", border: "border-slate-200" },
  black: { bg: "bg-slate-900", text: "text-white", dot: "bg-slate-800", border: "border-slate-700" },
};

export const STATUS_BADGE = {
  "รอจัดสรรช่าง": "bg-amber-50 text-amber-600 border border-amber-200",
  "รอดำเนินการ": "bg-orange-50 text-orange-600 border border-orange-200",
  "กำลังซ่อม": "bg-blue-50 text-blue-600 border border-amber-200",
  "กำลังดำเนินการ": "bg-blue-50 text-blue-600 border border-blue-200",
  "มีปัญหา": "bg-red-50 text-red-600 border border-red-200",
  "เกินกำหนดเวลา": "bg-rose-50 text-rose-700 border border-rose-200",
  "เสร็จสิ้น": "bg-emerald-50 text-emerald-600 border border-emerald-200",
  "เสร็จแล้ว": "bg-emerald-50 text-emerald-600 border border-emerald-200",
  "ยกเลิก": "bg-slate-100 text-slate-500 border border-slate-200",
};

export const TECH_STATUS_BADGE = {
  "พร้อมปฏิบัติงาน": "bg-emerald-50 text-emerald-600 border border-emerald-200",
  "กำลังเดินทาง": "bg-orange-50 text-orange-600 border border-orange-200",
  "กำลังซ่อม": "bg-violet-50 text-violet-600 border border-violet-200",
  "ออฟไลน์": "bg-slate-100 text-slate-500 border border-slate-200",
};

// 🐛 [แก้ไข] คีย์เดิมของ SEVERITY_BADGE (ปกติ/ปานกลาง/รุนแรง/เร่งด่วน) ไม่ตรง
// กับ 4 ระดับจริงที่ extractSeverity() คืนค่า (ต่ำ/ปกติ/สูง/เร่งด่วน) เลยทำให้
// badge ของ "ต่ำ" กับ "สูง" หา key ไม่เจอ ตกไปใช้สีเทา default เสมอ — แก้คีย์ให้
// ตรงกัน และให้โทนสีตรงกับ SEVERITY_LEVELS ที่ใช้ในหน้า Dashboard/รายงาน
// (ต่ำ=เขียว, ปกติ=ฟ้า, สูง=ส้ม, เร่งด่วน=แดง)
export const SEVERITY_BADGE = {
  "ต่ำ": "bg-emerald-50 text-emerald-600",
  "ปกติ": "bg-blue-50 text-blue-600",
  "สูง": "bg-orange-50 text-orange-600",
  "เร่งด่วน": "bg-red-50 text-red-600 font-semibold",
};

export const JOB_STATUS_TABS = [
  "ทั้งหมด",
  "รอจัดสรรช่าง",
  "รอดำเนินการ",
  "กำลังซ่อม",
  "เร่งด่วน",
  "มีปัญหา",
  "เกินกำหนดเวลา",
  "เสร็จสิ้น",
];

export const TAB_COLOR = {
  "ทั้งหมด": { active: "bg-slate-900 text-white", text: "text-slate-600" },
  "รอจัดสรรช่าง": { active: "bg-amber-50 text-amber-600", text: "text-amber-600" },
  "รอดำเนินการ": { active: "bg-orange-50 text-orange-600", text: "text-orange-600" },
  "กำลังซ่อม": { active: "bg-blue-50 text-blue-600", text: "text-yellow-600" },
  "เร่งด่วน": { active: "bg-red-50 text-red-600", text: "text-red-600" },
  "มีปัญหา": { active: "bg-red-50 text-red-700", text: "text-red-700" },
  "เกินกำหนดเวลา": { active: "bg-rose-50 text-rose-700", text: "text-rose-700" },
  "เสร็จสิ้น": { active: "bg-emerald-50 text-emerald-600", text: "text-emerald-600" },
};

/** แปลงสตริงวันที่ทั้งรูปแบบ "ว/ด/ป.พ.ศ." (เช่น 20/8/2569) และ ISO Date */
export function parseThaiDate(dateStr) {
  if (!dateStr) return null;
  const str = String(dateStr).trim();
  const parts = str.split("/");
  if (parts.length === 3) {
    const day = Number(parts[0]);
    const month = Number(parts[1]);
    const beYear = Number(parts[2]);
    if (!day || !month || !beYear) return null;
    const ceYear = beYear > 2400 ? beYear - 543 : beYear;
    return new Date(ceYear, month - 1, day);
  }
  const iso = new Date(str);
  return isNaN(iso.getTime()) ? null : iso;
}

/** เปรียบเทียบวันนัดหมายกับวันปัจจุบัน: 'future' | 'today' | 'past' */
export function compareAppointmentDate(dateStr) {
  const appDate = parseThaiDate(dateStr);
  if (!appDate) return "today";
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const target = new Date(appDate.getFullYear(), appDate.getMonth(), appDate.getDate());

  if (target > today) return "future";
  if (target < today) return "past";
  return "today";
}

/**
 * คำนวณสถานะที่แท้จริงของงานซ่อม
 * - ยังไม่มีช่าง -> รอจัดสรรช่าง
 * - มีช่างแล้ว & ยังไม่ถึงวันนัด -> รอดำเนินการ
 * - มีช่างแล้ว & ถึงวันนัดแล้ว -> กำลังซ่อม
 * - มีช่างแล้ว & เลยวันนัดแล้ว -> เกินกำหนดเวลา
 */
export function getEffectiveRepairStatus(job = {}) {
  const rawStatus = (job.status || "").trim() || "รอจัดสรรช่าง";

  // 🐛 [แก้ไข] BUG: เดิม return rawStatus ตรงๆ (ค่าดิบที่เก็บจริง) สำหรับงานที่
  // จบแล้ว/ยกเลิก/มีปัญหา — แต่ข้อมูลจริงมีทั้ง "เสร็จแล้ว" และ "เสร็จสิ้น" ปนกัน
  // (isDoneStatus() ด้านล่างถึงต้องเช็คทั้ง 2 คำ) พอฟังก์ชันนี้ไม่ normalize ให้
  // เป็นคำเดียว จุดไหนที่เทียบตรงๆ แบบ `getEffectiveRepairStatus(j) === "เสร็จสิ้น"`
  // (เช่น แท็บ "เสร็จสิ้น" ในหน้างานซ่อม, การนับ "เสร็จสิ้นแล้ว" ในโดนัทหน้า
  // Dashboard) เลยพลาดงานที่เก็บมาเป็น "เสร็จแล้ว" ไปเงียบๆ (นับได้ 0 ทั้งที่มี
  // งานเสร็จจริง) — แก้ให้ normalize เป็นคำเดียวเสมอ ("เสร็จสิ้น" / "ยกเลิก")
  // ก่อน return เพื่อให้ทุกจุดที่เทียบค่าตรงๆ ได้ผลลัพธ์ตรงกันหมด
  if (rawStatus === "เสร็จแล้ว" || rawStatus === "เสร็จสิ้น") {
    return "เสร็จสิ้น";
  }
  if (rawStatus.includes("ยกเลิก")) {
    return "ยกเลิก";
  }
  if (rawStatus === "มีปัญหา") {
    return rawStatus;
  }

  const tech = (job.technician_username || "").trim();
  if (!tech || rawStatus === "รอจัดสรรช่าง") {
    return "รอจัดสรรช่าง";
  }

  const dateComp = compareAppointmentDate(job.date);
  switch (dateComp) {
    case "future":
      return "รอดำเนินการ";
    case "today":
      return "กำลังซ่อม";
    case "past":
      return "เกินกำหนดเวลา";
    default:
      return rawStatus;
  }
}

export function displayStatus(statusOrJob, date = null, technicianUsername = null) {
  if (typeof statusOrJob === "object" && statusOrJob !== null) {
    return getEffectiveRepairStatus(statusOrJob);
  }
  if (date !== null || technicianUsername !== null) {
    return getEffectiveRepairStatus({
      status: statusOrJob,
      date,
      technician_username: technicianUsername,
    });
  }
  if (!statusOrJob) return "รอจัดสรรช่าง";
  if (statusOrJob === "กำลังดำเนินการ") return "กำลังซ่อม";
  return statusOrJob;
}

export function isPendingStatus(status) {
  return !status || status === "รอจัดสรรช่าง";
}

export function isScheduledPendingStatus(status) {
  return status === "รอดำเนินการ";
}

export function isInProgressStatus(status) {
  return status === "กำลังซ่อม" || status === "กำลังดำเนินการ";
}

export function isDoneStatus(status) {
  return status === "เสร็จสิ้น" || status === "เสร็จแล้ว";
}

// 🐛 [แก้ไข] BUG สำคัญที่ผู้ใช้แจ้ง: ระดับความรุนแรงจริงมีแค่ 4 ระดับคือ
// ต่ำ/ปกติ/สูง/เร่งด่วน เก็บเป็นข้อความนำหน้าใน field "detail" รูปแบบ
// "[ความรุนแรง: X] ..." (X คือหนึ่งใน 4 ระดับ) แต่ฟังก์ชันเดิมเช็กด้วย
// String.includes("รุนแรง") ตรงๆ ซึ่งดันไปตรงกับคำว่า "รุนแรง" ที่ซ้อนอยู่ใน
// คำว่า "ความรุนแรง" (ป้ายชื่อ field เอง) อยู่แล้ว ทำให้ทุกงานที่ไม่ใช่
// "เร่งด่วน" ถูกจัดเป็น "รุนแรง" ไปหมด (ซึ่งไม่ใช่ระดับที่มีอยู่จริงในระบบด้วย
// ซ้ำ) ทั้งที่ตัวจริงอาจเป็น "ต่ำ", "ปกติ" หรือ "สูง" — เปลี่ยนมาแกะค่าจาก
// เนื้อหาในวงเล็บ [ความรุนแรง: X] ตรงๆ ด้วย regex แทนการเช็ก substring แบบเดิม
export function extractSeverity(detail = "") {
  if (typeof detail !== "string") return "ปกติ";
  const match = detail.match(/\[ความรุนแรง:\s*([^\]]+)\]/);
  const level = match ? match[1].trim() : "";
  if (level === "ต่ำ" || level === "ปกติ" || level === "สูง" || level === "เร่งด่วน") {
    return level;
  }
  // เผื่อข้อมูลเก่าที่ไม่มี bracket tag แต่มีคำว่า "เร่งด่วน" ระบุตรงๆ
  if (detail.includes("เร่งด่วน")) return "เร่งด่วน";
  return "ปกติ";
}

export function extractRating(job = {}) {
  const rawRating =
    job.rating_stars ??
    job.rating ??
    job.score ??
    job.stars ??
    job.customer_rating ??
    job.tech_rating;
  const rating = Number(rawRating);
  const comment =
    job.rating_comment ||
    job.review ||
    job.customer_comment ||
    job.feedback ||
    job.comment ||
    "";
  const ratedAt = job.rated_at || job.reviewed_at || "";
  return {
    value: Number.isFinite(rating) && rating > 0 ? rating : null,
    comment: typeof comment === "string" ? comment.trim() : "",
    ratedAt: typeof ratedAt === "string" ? ratedAt : "",
  };
}

// 🆕 ชื่อเดือนย่อแบบไทย (index 0 = ม.ค.)
const THAI_MONTHS_ABBR = [
  "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.",
  "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค.",
];

// 🔴 [แก้ไข] ตัดตัวเลือก "รูปแบบวันที่" (พ.ศ./ค.ศ.) ในหน้าตั้งค่าออกทั้งระบบ
// ตามที่ขอ — เหลือแสดงผลแบบ พ.ศ. เดียวเท่านั้นทุกที่ในเว็บ ฟังก์ชันนี้จึงไม่
// รับพารามิเตอร์ dateFormat อีกต่อไป รับ Date object แล้วคืนสตริง
// "D ชื่อเดือนย่อ ปี พ.ศ." เสมอ (เช่น 12 ก.ย. 2569)
export function formatDateBySetting(date) {
  if (!date || isNaN(date.getTime?.())) return "-";
  const day = date.getDate();
  const month = date.getMonth() + 1;
  const yearBE = date.getFullYear() + 543;
  return `${day} ${THAI_MONTHS_ABBR[month - 1]} ${yearBE}`;
}

// 🆕 ฟิลด์ "date" (วันนัดหมาย/วันที่ของงานซ่อม) เป็นข้อความที่เก็บลง Database
// ตรงๆ ในรูปแบบ "D/M/ปี พ.ศ." ตายตัวเสมอ (ทั้งจากแอปมือถือและจากปฏิทินฝั่งเว็บ
// ตอนนัดหมาย) เพราะทั้งระบบ (ตัวกรองช่วงเวลา, การเรียงลำดับ ฯลฯ) ยังอ่านฟิลด์
// นี้โดยคาดหวังรูปแบบ พ.ศ. เป๊ะๆ อยู่ — ฟังก์ชันนี้ "ไม่ได้แก้ข้อมูลที่เก็บไว้
// เลย" แค่แปลงเฉพาะตอนจะแสดงผลบนจอเท่านั้น (จากตัวเลขล้วน "D/M/ปีพ.ศ." เป็น
// "D ชื่อเดือนย่อ ปีพ.ศ." เช่น 1/12/2569 → 1 ธ.ค. 2569)
// 🔴 [แก้ไข] ตัดพารามิเตอร์/ตัวเลือก ค.ศ. ออกทั้งระบบตามที่ขอ — เหลือ พ.ศ.
// อย่างเดียวเสมอ
export function displayStoredDate(dateStr) {
  if (!dateStr) return "-";
  const parts = String(dateStr).split("/");
  if (parts.length !== 3) return dateStr; // รูปแบบไม่ตรงที่คาด แสดงค่าดิบไว้ก่อน ดีกว่าทำพัง
  const day = Number(parts[0]);
  const month = Number(parts[1]);
  const yearBE = Number(parts[2]);
  if (!day || !month || !yearBE) return dateStr;
  const monthLabel = THAI_MONTHS_ABBR[month - 1] || month;
  return `${day} ${monthLabel} ${yearBE}`;
}

// ---------------------------------------------------------------------------
// 🔢 [ใหม่] หมายเลข Serial Number ของเครื่องจักร — ต้องตรงกับกฎเดียวกับฝั่ง
// มือถือเป๊ะๆ (lib/utils/serial_number.dart): โครงสร้าง 2-2-4 รวม 8 ตัวอักษร
// [รหัสรุ่น 2 ตัวอักษร][ปี ค.ศ. 2 หลัก][ลำดับ 4 หลัก] เช่น "PM260145"
//
// 🐛 [แก้บัค] เดิมฟอร์มเพิ่ม/แก้ไขเครื่องจักรของแอดมินบนเว็บ
// (CustomersPage.jsx) เช็กแค่ "ไม่ว่าง" กับ "ไม่ซ้ำ" เท่านั้น ไม่เคยตรวจ
// รูปแบบเลย ทำให้แอดมินกรอกเลขที่ไม่ตรง format ผ่านเว็บได้ (เช่น "1234"
// หรือ "ABC-99") ผลคือเครื่องจักรตัวนั้นสแกน QR จากแอปมือถือไม่เจอ (ฝั่ง
// มือถือ extractSerialNumberFromQr คาดหวัง pattern 2-2-4 เท่านั้น) — เพิ่ม
// ตัวตรวจชุดนี้ให้ตรงกับกฎเดียวกับมือถือ
// ---------------------------------------------------------------------------
const SERIAL_NUMBER_PATTERN = /^[A-Z]{2}\d{2}\d{4}$/;

export const SERIAL_NUMBER_FORMAT_ERROR =
  "หมายเลข Serial Number ต้องมี 8 ตัวอักษร รูปแบบ [ตัวอักษร 2 ตัว][ปี ค.ศ. 2 หลัก][ลำดับ 4 หลัก] เช่น PM260145";

/** แปลงค่าให้เป็นรูปแบบมาตรฐานก่อนตรวจ/บันทึก/เทียบซ้ำ (ตัดช่องว่าง + ตัวพิมพ์ใหญ่ทั้งหมด) */
export function normalizeSerialNumber(value) {
  return (value || "").trim().toUpperCase();
}

/** ตรวจว่าค่าที่ได้เป็นหมายเลข Serial Number ที่ถูกต้องตามโครงสร้าง 2-2-4 หรือไม่ */
export function isValidSerialNumber(value) {
  return SERIAL_NUMBER_PATTERN.test(normalizeSerialNumber(value));
}