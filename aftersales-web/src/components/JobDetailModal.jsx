import React, { useState } from "react";
import { X, User, Wrench, UserCog, Calendar, MapPin, AlertTriangle, Loader2, Navigation, ImageOff, ChevronLeft, ChevronRight, FileText } from "lucide-react";
import { STATUS_BADGE, SEVERITY_BADGE, extractSeverity, displayStatus, extractRating, displayStoredDate } from "../shared/constants";
import { assignTechnicianToRepair, logActivity, createNotification, getWebSettings } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";
import { StarRating } from "./ui";

// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: modal popup กลางจอ (ไม่ได้ใช้ Modal จาก components/ui.jsx
// เพราะต้องการโครง header สีเทาแยกต่างหากสำหรับ badge สถานะ/ความเร่งด่วนบนสุด)
// แต่ละแถวข้อมูล (Row ด้านล่าง) มีเส้นคั่นบาง ๆ (border-slate-50) คั่นระหว่างกัน
// 🔴 [แก้ไข] เพิ่มส่วน "มอบหมายช่าง" ด้านล่างสุด — เดิม modal นี้ดูข้อมูลได้
// อย่างเดียว มอบหมายช่างให้งานที่ยังไม่มีคนรับผิดชอบไม่ได้เลยจากหน้าเว็บ
// 🔴 [แก้ไข] เพิ่มแผนที่ตำแหน่งงาน + ตำแหน่งช่าง — เช็กกับซอร์ส Flutter จริงแล้ว
// (lib/screens/customer/technician_tracking.dart) ว่าเก็บพิกัดปลายทางไว้ที่
// repairs.dest_lat/dest_lng (ลูกค้ายืนยันตำแหน่งตอนแจ้งซ่อม บังคับกรอกเสมอ) และ
// พิกัดช่างสดที่ technicians.current_lat/current_lng (ไม่มี field เก็บเวลา
// อัปเดตล่าสุด ใช้ค่าปัจจุบันในฐานข้อมูลตรง ๆ) — ใช้ OpenStreetMap embed แบบ
// iframe (ไม่ต้องมี API key/ไลบรารีใหม่) โชว์ปักหมุดจุดหมาย + คำนวณระยะห่างช่าง
// แบบเส้นตรง (Haversine) พร้อมปุ่มเปิดเส้นทางเต็มใน Google Maps
// 🔴 [แก้ไข] เพิ่มแกลเลอรีรูปภาพที่ลูกค้าแนบมาตอนแจ้งซ่อม — เช็กกับซอร์ส Flutter
// จริงแล้ว (lib/screens/customer/repair_form.dart) ว่าเก็บไว้ที่ repairs.images
// เป็น string คั่นด้วยจุลภาค (ลิงก์ Cloudinary หลายรูปต่อกัน ไม่ใช่ array จริง ๆ
// ใน Firebase) เดิม modal นี้ไม่เคยอ่าน field นี้เลยแม้แต่นิดเดียว จึงไม่เคยมี
// รูปโชว์ให้เห็นสักรูป — เพิ่มการ parse + แกลเลอรีธัมบ์เนล กดดูรูปเต็มได้
// (lightbox เรียบง่าย เลื่อนดูรูปถัดไป/ก่อนหน้าได้ถ้ามีหลายรูป) พร้อมขยาย modal
// ให้กว้างขึ้นเป็น 2 คอลัมน์บนจอใหญ่ (รายละเอียดซ้าย, รูป+แผนที่ขวา) เพื่อให้มี
// ที่พอแสดงรูปโดยไม่บีบเนื้อหาเดิม
// ---------------------------------------------------------------------------

function parseImages(raw) {
  if (typeof raw !== "string" || !raw.trim()) return [];
  return raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

// 🔴 [ใหม่] แปลง Date → ค่าที่ <input type="date"> ต้องการ ("YYYY-MM-DD")
function toDateInputValue(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// 🔴 [ใหม่] แปลงค่าจาก <input type="date"> ("YYYY-MM-DD") กลับเป็นรูปแบบไทย
// "D/M/พ.ศ." ให้ตรงกับ field "date" ที่ใช้กันอยู่แล้วทั้งระบบ (parseThaiDate ที่
// หน้าอื่น ๆ ใช้กรอง/เรียงงาน คาดหวังรูปแบบนี้เป๊ะ)
function formatThaiDate(isoDateStr) {
  const [y, m, d] = isoDateStr.split("-").map(Number);
  return `${d}/${m}/${y + 543}`;
}

function formatReportDate(rawDate, dateFormat) {
  if (!rawDate) return "";
  const d = new Date(rawDate);
  if (isNaN(d.getTime())) return String(rawDate);
  const opts = { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" };
  // 🆕 ค่าเริ่มต้นของ locale "th-TH" คือปี พ.ศ. อยู่แล้ว — ต้องระบุ
  // calendar: "gregory" ตรงๆ ถ้าอยากได้ปี ค.ศ. ตามตั้งค่า
  if (dateFormat === "ce") opts.calendar = "gregory";
  return d.toLocaleString("th-TH", opts);
}

// 🐛 [แก้ไข] BUG: เดิมเดาชื่อ field ไว้หลายแบบ (report_detail/repair_report/
// tech_report ฯลฯ) เพราะยังไม่เคยเช็กกับซอร์ส Flutter จริง เลยไม่เคยขึ้นข้อมูล
// เลยสักครั้งทั้งที่ช่างส่งรายงานมาจริง — เช็กกับ services.dart
// (submitRepairReport()) แล้ว ชื่อ field จริงคือ report_problem_detail /
// report_before_photo / report_after_photo / report_slip_photo /
// report_submitted_at / report_form_code แก้ให้ตรงเป๊ะ ห้ามเดาอีก
function getRepairReport(job, dateFormat) {
  if (!job) {
    return { text: "", beforePhoto: "", afterPhoto: "", slipPhoto: "", formCode: "", reportedAt: "" };
  }
  const text = typeof job.report_problem_detail === "string" ? job.report_problem_detail.trim() : "";
  return {
    text,
    beforePhoto: job.report_before_photo || "",
    afterPhoto: job.report_after_photo || "",
    slipPhoto: job.report_slip_photo || "",
    formCode: job.report_form_code || "",
    reportedAt: formatReportDate(job.report_submitted_at || "", dateFormat),
  };
}

function PhotoGallery({ images }) {
  const [lightboxIndex, setLightboxIndex] = useState(null);

  if (images.length === 0) {
    return (
      <div className="rounded-xl border border-dashed border-slate-200 py-10 flex flex-col items-center justify-center text-slate-300">
        <ImageOff size={28} className="mb-2" />
        <p className="text-xs text-slate-400">ลูกค้าไม่ได้แนบรูปภาพมากับงานนี้</p>
      </div>
    );
  }

  return (
    <>
      <div className="grid grid-cols-3 gap-2">
        {images.map((url, i) => (
          <button
            key={i}
            onClick={() => setLightboxIndex(i)}
            className="aspect-square rounded-lg overflow-hidden border border-slate-100 hover:opacity-80 transition-opacity"
          >
            <img src={url} alt={`รูปที่ ${i + 1}`} className="w-full h-full object-cover" />
          </button>
        ))}
      </div>

      {/* 🔍 Lightbox ดูรูปเต็ม — z-[60] สูงกว่า modal หลัก (z-50) ให้ลอยทับได้ */}
      {lightboxIndex !== null ? (
        <div
          className="fixed inset-0 z-[60] flex items-center justify-center bg-black/80 p-4"
          onClick={() => setLightboxIndex(null)}
        >
          <button
            onClick={() => setLightboxIndex(null)}
            className="absolute top-4 right-4 text-white/80 hover:text-white"
          >
            <X size={24} />
          </button>
          {images.length > 1 ? (
            <>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setLightboxIndex((lightboxIndex - 1 + images.length) % images.length);
                }}
                className="absolute left-4 text-white/80 hover:text-white"
              >
                <ChevronLeft size={28} />
              </button>
              <button
                onClick={(e) => {
                  e.stopPropagation();
                  setLightboxIndex((lightboxIndex + 1) % images.length);
                }}
                className="absolute right-4 text-white/80 hover:text-white"
              >
                <ChevronRight size={28} />
              </button>
            </>
          ) : null}
          <img
            src={images[lightboxIndex]}
            alt={`รูปที่ ${lightboxIndex + 1}`}
            className="max-w-full max-h-full rounded-lg"
            onClick={(e) => e.stopPropagation()}
          />
          {images.length > 1 ? (
            <p className="absolute bottom-4 text-white/70 text-xs">{lightboxIndex + 1} / {images.length}</p>
          ) : null}
        </div>
      ) : null}
    </>
  );
}

function haversineKm(lat1, lng1, lat2, lng2) {
  const R = 6371;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function JobLocationMap({ job, technician }) {
  const destLat = Number(job.dest_lat);
  const destLng = Number(job.dest_lng);
  const hasDest = Number.isFinite(destLat) && Number.isFinite(destLng);
  if (!hasDest) return null;

  const techLat = Number(technician?.current_lat);
  const techLng = Number(technician?.current_lng);
  const hasTech = Number.isFinite(techLat) && Number.isFinite(techLng);

  // bbox ครอบคลุมทั้งจุดหมายและตำแหน่งช่าง (ถ้ามี) เผื่อขอบไว้เล็กน้อยให้ดูง่าย
  const lats = hasTech ? [destLat, techLat] : [destLat];
  const lngs = hasTech ? [destLng, techLng] : [destLng];
  const pad = 0.01;
  const minLat = Math.min(...lats) - pad;
  const maxLat = Math.max(...lats) + pad;
  const minLng = Math.min(...lngs) - pad;
  const maxLng = Math.max(...lngs) + pad;
  const embedUrl = `https://www.openstreetmap.org/export/embed.html?bbox=${minLng}%2C${minLat}%2C${maxLng}%2C${maxLat}&layer=mapnik&marker=${destLat}%2C${destLng}`;

  const distanceKm = hasTech ? haversineKm(destLat, destLng, techLat, techLng) : null;
  const directionsUrl = hasTech
    ? `https://www.google.com/maps/dir/?api=1&origin=${techLat},${techLng}&destination=${destLat},${destLng}`
    : `https://www.google.com/maps/search/?api=1&query=${destLat},${destLng}`;

  return (
    <div className="mt-6">
      <p className="text-sm font-semibold text-slate-700 mb-3">ตำแหน่งงานซ่อม{hasTech ? " และช่าง" : ""}</p>
      <div className="rounded-xl overflow-hidden border border-slate-100">
        <iframe title="job-location-map" src={embedUrl} className="w-full h-48 border-0" loading="lazy" />
      </div>
      <div className="flex items-center justify-between mt-2 gap-2">
        {hasTech ? (
          <p className="text-xs text-slate-500">ช่างอยู่ห่างจากจุดหมาย ~{distanceKm.toFixed(1)} กม. (ระยะเส้นตรง)</p>
        ) : (
          <p className="text-xs text-slate-400">ยังไม่มีตำแหน่ง GPS ล่าสุดของช่าง</p>
        )}
        <a
          href={directionsUrl}
          target="_blank"
          rel="noreferrer"
          className="flex items-center gap-1 text-xs text-blue-500 font-medium hover:text-blue-600 shrink-0"
        >
          <Navigation size={12} />
          เปิดใน Google Maps
        </a>
      </div>
    </div>
  );
}

function Row({ icon: Icon, label, value }) {
  return (
    <div className="flex items-start gap-3 py-2.5 border-b border-slate-50 last:border-0">
      <Icon size={16} className="text-slate-400 mt-0.5 shrink-0" />
      <div className="min-w-0">
        <p className="text-xs text-slate-400">{label}</p>
        <p className="text-[15px] text-slate-800 break-words">{value || "-"}</p>
      </div>
    </div>
  );
}

export default function JobDetailModal({ job, technicians = [], onClose, onAssigned, dateFormat }) {
  const [selectedTech, setSelectedTech] = useState("");
  // 🔴 [ใหม่] วันนัด/เวลานัด — กรอกได้ต่อเมื่อเลือกช่างแล้วเท่านั้น (ตามลำดับ
  // ขั้นตอนที่ขอ: เลือกช่างก่อน ค่อยเลือกวันนัดทีหลัง) ค่า appointmentDate เป็น
  // ISO string ("YYYY-MM-DD") ตรงกับ <input type="date"> โดยตรง ส่วนตอนบันทึก
  // ลงฐานข้อมูลจะแปลงเป็นรูปแบบไทย "D/M/พ.ศ." ให้ตรงกับ field "date" (วันนัด
  // หมาย) ที่ใช้อยู่แล้วทั้งระบบ (parseThaiDate ในหน้าอื่น ๆ คาดหวังรูปแบบนี้)
  const [appointmentDate, setAppointmentDate] = useState("");
  // 🔴 [แก้ไข] เปลี่ยนจาก <input type="time"> (ระบบ 00-23 น. แบบสากล) เป็น
  // dropdown ชั่วโมง/นาทีแยกกันแทน ตามที่ขอให้เป็นเวลาแบบไทย 01-24 น. (24.00
  // หมายถึงเที่ยงคืน แทนที่จะเป็น 00.00) — เก็บแยก 2 ค่านี้แล้วค่อยประกอบเป็น
  // string ตอนจะใช้งานจริง (ดู appointmentTime ด้านล่าง)
  const [appointmentHour, setAppointmentHour] = useState("");
  const [appointmentMinute, setAppointmentMinute] = useState("");
  const appointmentTime = appointmentHour && appointmentMinute ? `${appointmentHour}.${appointmentMinute}` : "";
  const [assigning, setAssigning] = useState(false);
  const [assignError, setAssignError] = useState("");
  if (!job) return null;

  const isCancelled = (job.status || "").includes("ยกเลิก");
  const isDone = job.status === "เสร็จสิ้น" || job.status === "เสร็จแล้ว";
  const reportInfo = getRepairReport(job, dateFormat);
  const ratingInfo = extractRating(job);
  // 🔴 แสดงกล่องมอบหมายช่างเฉพาะงานที่ยังไม่มีช่างและยังไม่จบ (เสร็จ/ยกเลิก) —
  // งานที่จบไปแล้วไม่ควรให้มอบหมายช่างใหม่ทับของเดิม
  const canAssign = !job.technician_username && !isCancelled && !isDone;
  // ใช้หาตำแหน่ง GPS สดของช่างที่รับผิดชอบงานนี้ (technicians.current_lat/lng)
  const assignedTechnician = technicians.find((t) => t.username === job.technician_username);

  // ห้ามเลือกวันย้อนหลัง — วันนี้เป็นค่าต่ำสุดที่เลือกได้ (ตามที่ขอ "ตั้งวันนี้
  // เป็นต้นไป")
  const todayInputValue = toDateInputValue(new Date());

  async function handleAssign() {
    if (!selectedTech) {
      setAssignError("กรุณาเลือกช่างก่อน");
      return;
    }
    if (!appointmentDate || !appointmentTime) {
      setAssignError("กรุณาเลือกวันและเวลานัดหมาย");
      return;
    }
    setAssignError("");
    setAssigning(true);
    try {
      const admin = getSessionAdmin();
      const adminUsername = admin?.username || "";
      const thaiDate = formatThaiDate(appointmentDate);
      // 🐛 [แก้ไข] BUG: เดิมยัดอ็อบเจกต์ {date, appointment_time} เข้าไปเป็น
      // argument ตัวที่ 4 (appointmentDate) ของ assignTechnicianToRepair()
      // ตรงๆ — แต่ signature จริงของฟังก์ชัน (firebaseDb.js) คือ (repairId,
      // technicianUsername, adminUsername, appointmentDate, extraData) ทำให้
      // เกิด 2 บั๊กซ้อนกัน: (1) appointmentDate ที่ควรเป็นสตริงวันที่ กลาย
      // เป็นอ็อบเจกต์ทั้งก้อน ทำให้ compareAppointmentDate() คำนวณสถานะเริ่มต้น
      // ผิด (parseThaiDate แปลงอ็อบเจกต์ไม่ได้ กลายเป็น "today" เสมอ) และ (2)
      // extraData (argument ตัวที่ 5 ตัวจริง) ไม่เคยได้รับค่าเลย เท่ากับ
      // date/appointment_time ที่กรอกไว้ไม่เคยถูกบันทึกลง Firebase จริงๆ สักครั้ง
      // — ย้าย thaiDate ไปเป็น argument ตัวที่ 4 ตามตำแหน่งจริง แล้วส่ง
      // {date, appointment_time} เป็นตัวที่ 5 (extraData) แทน
      await assignTechnicianToRepair(job.id, selectedTech, adminUsername, thaiDate, {
        date: thaiDate,
        appointment_time: appointmentTime,
      });
      // 📝 [ใหม่] บันทึก activity log — ใครมอบหมายช่างให้งานไหนเมื่อไหร่
      logActivity({
        adminUsername,
        adminName: admin?.admin_name,
        action: "มอบหมายช่าง",
        target: `${job.ticketNo || `#${job.id}`} → ${selectedTech} (นัด ${thaiDate} ${appointmentTime})`,
      }).catch((err) => console.error("[JobDetailModal] log activity failed:", err));
      // 🔔 [ใหม่] แจ้งเตือน (+ push) ให้ทั้งช่างที่ถูกมอบหมายและลูกค้ารู้ทันที —
      // เดิมมอบหมายช่างจากเว็บแล้วเงียบสนิท ทั้งคู่ต้องเปิดแอปมาเห็นเองถึงจะรู้
      // เช็กสวิตช์ "แจ้งเตือนอัปเดตงานซ่อม" ในหน้าตั้งค่าก่อนยิงจริง
      getWebSettings()
        .then((settings) => {
          if (settings?.notifyJob === false) return;
          const ticketLabel = job.ticketNo || `#${job.id}`;
          createNotification({
            user_username: selectedTech,
            role: "TECHNICIAN",
            title: `งานใหม่: ${ticketLabel}`,
            message: `คุณได้รับมอบหมายงานซ่อม ${job.machine || ""} นัดหมายวันที่ ${thaiDate} เวลา ${appointmentTime} น.`,
            type: "JOB",
            target_id: job.id,
          }).catch((err) => console.error("[JobDetailModal] notify technician failed:", err));
          if (job.customer_username) {
            createNotification({
              user_username: job.customer_username,
              role: "CUSTOMER",
              title: `งานซ่อมของคุณมีช่างแล้ว: ${ticketLabel}`,
              message: `ช่าง ${selectedTech} รับผิดชอบงานซ่อมของคุณแล้ว นัดหมายวันที่ ${thaiDate} เวลา ${appointmentTime} น.`,
              type: "JOB",
              target_id: job.id,
            }).catch((err) => console.error("[JobDetailModal] notify customer failed:", err));
          }
        })
        .catch((err) => console.error("[JobDetailModal] load settings failed:", err));
      onAssigned?.();
      onClose();
    } catch (err) {
      console.error("[JobDetailModal] assign failed:", err);
      setAssignError("มอบหมายช่างไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    } finally {
      setAssigning(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-900/40" onClick={onClose} />
      {/* 🔴 [แก้ไข] ขยาย modal กว้างขึ้นเป็น max-w-4xl บนจอใหญ่ (lg ขึ้นไป) เพื่อ
          ให้มีที่พอวางคอลัมน์รูปภาพ+แผนที่ข้าง ๆ รายละเอียดงาน — จอเล็กยังคง
          แคบแบบเดิม (max-w-lg) ไม่บีบจนอ่านยาก
          🐛 [แก้ไข] BUG (ย้อนกลับมาอีกครั้งในไฟล์ล่าสุดที่อัปมา — แก้ซ้ำให้):
          เดิมงานที่ "เสร็จสิ้น" ขยับเป็น 3 คอลัมน์ที่ระดับจอ xl (1280px) แต่จอ
          จริงที่ใช้ดูไม่กว้างถึงระดับนั้น เลยไม่เคยเห็น 3 คอลัมน์เลย ตกลงมาเป็น
          แถวเต็มความกว้างด้านล่างตลอด (ยืนยันแล้วว่าเป็นบั๊กจากการทดสอบจริง)
          — เปลี่ยนมาขยับที่ระดับ lg (1024px) แทน ให้ตรงกับจุดที่ 2 คอลัมน์เดิม
          ขึ้นอยู่แล้วพอดี (ขยาย max-w-6xl ที่ lg ไปเลยตอนงานเสร็จ ไม่ใช่ค่อย
          ขยับต่อที่ xl อีกที) */}
      <div className={`relative bg-white rounded-2xl shadow-xl w-full max-w-lg ${isDone ? "lg:max-w-6xl" : "lg:max-w-4xl"} max-h-[90vh] overflow-y-auto`}>
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100">
          <div>
            <h3 className="text-base font-semibold text-slate-800">{job.ticketNo || `#${job.id}`}</h3>
            <p className="text-xs text-slate-400 mt-0.5">รายละเอียดงานซ่อม</p>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">
            <X size={20} />
          </button>
        </div>

        {/* 🔴 [แก้ไข] แบ่ง 2 คอลัมน์บนจอใหญ่ (3 คอลัมน์ถ้างานเสร็จแล้ว — ดู
            คอมเมนต์ที่ isDone ? "lg:grid-cols-3" ด้านล่าง) — ซ้าย: รายละเอียด
            งาน+มอบหมายช่าง (เหมือนเดิมทุกประการ) กลาง: รูปภาพจากลูกค้า+แผนที่
            ขวา (เฉพาะงานเสร็จแล้ว): คะแนนรีวิว+รายงานการซ่อม จอเล็กกว่า lg จะ
            เรียงตกลงมาเป็นคอลัมน์เดียวตามลำดับเสมอ */}
        <div className={`p-6 lg:grid ${isDone ? "lg:grid-cols-3" : "lg:grid-cols-2"} lg:gap-8`}>
          <div>
            <div className="flex items-center gap-2 mb-4">
              <span className={`text-xs font-medium px-2.5 py-1 rounded-full ${STATUS_BADGE[job.status] ?? "bg-gray-100 text-gray-500"}`}>
                {displayStatus(job.status)}
              </span>
              <span className={`text-xs font-medium px-2.5 py-1 rounded-full ${SEVERITY_BADGE[extractSeverity(job.detail)] ?? "bg-gray-100 text-gray-500"}`}>
                {extractSeverity(job.detail)}
              </span>
            </div>

            <Row icon={User} label="ลูกค้า" value={job.customer_username} />
            <Row icon={Wrench} label="อุปกรณ์ / เครื่องจักร" value={job.machine} />
            <Row icon={UserCog} label="ช่างที่รับผิดชอบ" value={job.technician_username || "ยังไม่มอบหมาย"} />
            <Row icon={Calendar} label="วันนัดหมาย" value={displayStoredDate(job.date, dateFormat)} />
            {job.appointment_time ? <Row icon={Calendar} label="เวลานัดหมาย" value={`${job.appointment_time} น.`} /> : null}
            <Row icon={MapPin} label="สถานที่" value={job.location} />
            {job.detail ? <Row icon={AlertTriangle} label="รายละเอียดปัญหา" value={job.detail} /> : null}

            {/* 🔴 กล่องมอบหมายช่าง — โชว์เฉพาะงานที่ยังไม่มีช่างและยังไม่จบ */}
            {canAssign ? (
              <div className="mt-5 pt-5 border-t border-slate-100">
                <p className="text-sm font-semibold text-slate-700 mb-3">มอบหมายช่างให้งานนี้</p>

                {/* ขั้นที่ 1: เลือกช่างก่อน */}
                <select
                  value={selectedTech}
                  onChange={(e) => setSelectedTech(e.target.value)}
                  disabled={assigning}
                  className="w-full px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                >
                  <option value="">เลือกช่าง...</option>
                  {technicians.map((t) => (
                    <option key={t.id} value={t.username}>
                      {t.tech_name || t.name || t.username}
                    </option>
                  ))}
                </select>
                {technicians.length === 0 ? (
                  <p className="text-xs text-slate-400 mt-2">ยังไม่มีช่างในระบบ — เพิ่มช่างได้ที่เมนู "ช่างเทคนิค"</p>
                ) : null}

                {/* 🔴 [ใหม่] ขั้นที่ 2: เลือกวันนัด+เวลา — โชว่ต่อเมื่อเลือกช่าง
                    แล้วเท่านั้น (ตามลำดับขั้นตอนที่ขอ: เลือกช่างก่อน ค่อยเลือก
                    วันนัดทีหลัง) วันที่เลือกได้ต่ำสุดคือวันนี้ ห้ามเลือก
                    ย้อนหลัง (min={todayInputValue}) */}
                {selectedTech ? (
                  <div className="mt-3">
                    <p className="text-xs font-medium text-slate-500 mb-1.5">นัดหมายวันที่และเวลา</p>
                    <div className="flex items-center gap-2">
                      <input
                        type="date"
                        value={appointmentDate}
                        min={todayInputValue}
                        onChange={(e) => setAppointmentDate(e.target.value)}
                        disabled={assigning}
                        className="flex-1 px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                      />
                      {/* 🔴 [แก้ไข] เวลาแบบไทย — ชั่วโมง 01-24 น. (24.00 = เที่ยงคืน
                          แทน 00.00 แบบสากล) นาที 00-59 แยกเป็น 2 dropdown คั่นด้วย
                          จุดแบบที่คนไทยเขียนเวลากัน (เช่น "14.30 น.") */}
                      <select
                        value={appointmentHour}
                        onChange={(e) => setAppointmentHour(e.target.value)}
                        disabled={assigning}
                        className="px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                      >
                        <option value="">ชม.</option>
                        {Array.from({ length: 24 }, (_, i) => String(i + 1).padStart(2, "0")).map((h) => (
                          <option key={h} value={h}>{h}</option>
                        ))}
                      </select>
                      <span className="text-slate-400 shrink-0">.</span>
                      <select
                        value={appointmentMinute}
                        onChange={(e) => setAppointmentMinute(e.target.value)}
                        disabled={assigning}
                        className="px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                      >
                        <option value="">นาที</option>
                        {Array.from({ length: 60 }, (_, i) => String(i).padStart(2, "0")).map((m) => (
                          <option key={m} value={m}>{m}</option>
                        ))}
                      </select>
                      <span className="text-xs text-slate-400 shrink-0">น.</span>
                    </div>
                  </div>
                ) : null}

                <button
                  onClick={handleAssign}
                  disabled={assigning || !selectedTech}
                  // 🎨 ปุ่ม "มอบหมาย" สีน้ำเงินมาตรฐาน (ตรงกับ PrimaryButton ใน
                  // components/ui.jsx) — เขียนแยกในไฟล์นี้เพราะต้องใส่ loading state
                  className="w-full mt-3 flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50"
                >
                  {assigning ? <Loader2 size={16} className="animate-spin" /> : null}
                  มอบหมาย
                </button>
                {assignError ? <p className="text-xs text-red-500 mt-2">{assignError}</p> : null}
              </div>
            ) : null}
          </div>

          {/* 🔴 [แก้ไข] คอลัมน์กลาง — รูปภาพจากลูกค้า + แผนที่ตำแหน่ง เท่านั้น
              (คะแนนรีวิว/รายงานการซ่อมแยกออกไปเป็นคอลัมน์ที่ 3 ต่างหากแล้ว
              ไม่ได้ต่อท้ายอยู่ในคอลัมน์เดียวกันแบบก่อนหน้านี้) */}
          <div className="mt-6 lg:mt-0">
            <p className="text-sm font-semibold text-slate-700 mb-3">รูปภาพจากลูกค้า</p>
            <PhotoGallery images={parseImages(job.images)} />

            <JobLocationMap job={job} technician={assignedTechnician} />
          </div>

          {/* 🔴 [ใหม่] คอลัมน์ที่ 3 — คะแนนรีวิว + รายงานการซ่อม เป็นโซนแยก
              ต่างหากถัดจากคอลัมน์รูปภาพ/แผนที่ (ไม่ใช่ต่อท้ายด้านล่าง) โชว์
              เฉพาะตอนงาน "เสร็จสิ้น" เท่านั้น (isDone) ซึ่งเป็นเงื่อนไขเดียวกับ
              ที่ทำให้ grid ด้านบนเปลี่ยนเป็น lg:grid-cols-3 พอดี จึงไม่ต้องมี
              col-span พิเศษ/breakpoint แยกอีกชั้นแบบที่เคยลองไว้ (mt-6 lg:mt-0
              ให้ตรงกับ pattern เดียวกับคอลัมน์กลาง) */}
          {isDone ? (
            <div className="mt-6 lg:mt-0">
              {/* 🔴 [ใหม่] คะแนนรีวิวจากลูกค้า — ฟีเจอร์ให้คะแนนยังไม่มีอยู่จริง
                  ฝั่ง Flutter (ลูกค้ายังกดให้คะแนนไม่ได้) จึงเดาชื่อ field ไว้
                  ก่อน (ดู extractRating ใน shared/constants.js) — ตอนนี้จะขึ้น
                  "ยังไม่มีคะแนน" เสมอ จนกว่าจะมีฟีเจอร์ให้คะแนนจริงและ field
                  ตรงกัน */}
              <div className="rounded-2xl border border-amber-100 bg-amber-50/40 p-5">
                <p className="text-sm font-semibold text-slate-800 mb-2">คะแนนรีวิวจากลูกค้า</p>
                <StarRating value={ratingInfo.value} size={16} />
                {ratingInfo.comment ? (
                  <p className="text-sm text-slate-600 mt-3">"{ratingInfo.comment}"</p>
                ) : null}
              </div>

              {/* 🔴 [ใหม่] รายงานการซ่อมจากช่าง — โชว์เฉพาะงานที่สถานะ "เสร็จสิ้น"/
                  "เสร็จแล้ว" เท่านั้น
                  🐛 [แก้ไข] ใช้ชื่อ field ที่ถูกต้องแล้ว (เช็กกับ services.dart
                  submitRepairReport() ตรง ๆ) เดิมเดาชื่อผิดเลยไม่เคยขึ้นข้อมูล */}
              <div className="mt-6 rounded-2xl border border-emerald-100 bg-emerald-50/40 p-5">
                <div className="flex items-center justify-between gap-2 mb-4">
                  <div className="flex items-center gap-2">
                    <div className="w-8 h-8 rounded-full bg-emerald-100 flex items-center justify-center flex-shrink-0">
                      <FileText size={16} className="text-emerald-600" />
                    </div>
                    <div>
                      <p className="text-sm font-semibold text-slate-800">
                        รายงานการซ่อมจากช่าง {reportInfo.formCode ? `(${reportInfo.formCode})` : ""}
                      </p>
                      {reportInfo.reportedAt ? (
                        <p className="text-xs text-slate-400">ส่งรายงานเมื่อ {reportInfo.reportedAt}</p>
                      ) : null}
                    </div>
                  </div>
                </div>

                <p className="text-sm text-slate-700 whitespace-pre-line leading-relaxed mb-4">
                  {reportInfo.text || "ช่างไม่ได้ระบุข้อความรายละเอียด"}
                </p>

                {(reportInfo.beforePhoto || reportInfo.afterPhoto || reportInfo.slipPhoto) ? (
                  <div>
                    <p className="text-xs font-medium text-slate-500 mb-2">รูปภาพประกอบการปิดงาน (ก่อนซ่อม / หลังซ่อม / สลิป)</p>
                    <PhotoGallery
                      images={[reportInfo.beforePhoto, reportInfo.afterPhoto, reportInfo.slipPhoto].filter(Boolean)}
                    />
                  </div>
                ) : null}
              </div>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
