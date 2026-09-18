import React, { useState, useEffect } from "react";
import {
  ClipboardList,
  CheckCircle2,
  Wrench,
  AlertTriangle,
  Flame,
  Package,
  ChevronDown,
  Share2,
  Check,
  Download,
  Printer,
} from "lucide-react";
import { PieChart, Pie, Cell, ResponsiveContainer } from "recharts";
import { Card, Modal } from "../components/ui";
import useDbList from "../hooks/useDbList";
import { getWebSettings } from "../services/firebaseDb";
import { extractSeverity } from "../shared/constants";

// ---------------------------------------------------------------------------
// 🔴 [แก้ไข] ปรับหน้า "รายงาน" 3 จุดตามที่ขอรอบนี้ (ส่วนการ์ดที่ผสมมาจากแอป
// มือถือรอบก่อน — งานซ่อมเดือนนี้+% เติบโต, จำนวนผู้ใช้งาน, กราฟการเงิน 6 เดือน,
// รายงานประจำเดือน+ทางลัด — ยังอยู่เหมือนเดิมไม่ได้แตะ):
// 1) การ์ดสถิติแถวบน (เดิม: งานทั้งหมด/รอจัดสรรช่าง/กำลังดำเนินการ/เสร็จสิ้น/
//    เร่งด่วน) เปลี่ยนเป็นนับตาม "ระดับความรุนแรง" 4 ระดับที่มีอยู่จริงในระบบ
//    (ต่ำ/ปกติ/สูง/เร่งด่วน — ลูกค้าเลือกตอนแจ้งซ่อมในแอปมือถือ เก็บเป็นข้อความ
//    นำหน้าใน field "detail" แบบ "[ความรุนแรง: สูง] ...", ไม่ได้เป็นคอลัมน์แยก
//    ต่างหาก — ดู extractSeverity() ด้านล่าง) แทนการนับตาม "urgency" ซึ่งเป็น
//    field ที่ทางเว็บสมมติขึ้นเองและไม่มีอยู่จริงในฐานข้อมูลจากแอปมือถือ
// 2) โดนัท "สถิติสถานะงานซ่อม" (เดิมนับตาม status) เปลี่ยนมานับตามระดับความ
//    รุนแรงแทน คู่กับการ์ด "สัดส่วน (%)" ใหม่ (แทนที่การ์ด "ต้องดำเนินการ" กับ
//    การ์ด "สัดส่วนสถานะงานซ่อม" แบบแถบเดิมทั้งคู่ — รวมเป็นการ์ดเดียว) ทั้ง 2
//    วิดเจ็ตนี้แชร์ตัวเลือกช่วงเวลาเดียวกัน (วันนี้/สัปดาห์นี้/เดือนนี้/ปีนี้/
//    ทั้งหมด) กรองจาก created_at
// 3) การ์ด "คำขอเบิกอะไหล่ที่รออนุมัติ" (เดิมโชว์แค่จำนวนคำขอที่ค้าง) เปลี่ยน
//    เป็น "สถิติการเบิกอะไหล่" ที่ออกแบบใหม่ทั้งหมด — โชว์ยอดที่เบิกไปแล้วจริง
//    (จำนวนชิ้น/มูลค่า) และอะไหล่ที่ถูกเบิกบ่อยที่สุด แทนที่จะโชว์แค่คำขอค้าง
// ---------------------------------------------------------------------------

const THAI_MONTHS = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
const BRAND = "#B22121";

// 🔴 ระดับความรุนแรง 4 ระดับ ตรงกับ _severityOptions ในฟอร์มแจ้งซ่อมของแอปมือถือ
// (lib/screens/customer/repair_form.dart) — ค่าเริ่มต้นถ้าไม่เจอ/parse ไม่ได้
// คือ "ปกติ" เหมือนค่าเริ่มต้นของฟอร์มฝั่งแอป — ตัวฟังก์ชัน extractSeverity()
// ย้ายไปอยู่ shared/constants.js แล้ว (ใช้ร่วมกับหน้าอื่นที่ต้องเช็กความรุนแรง
// ของงาน เช่น Dashboard, งานซ่อม, JobDetailModal) เหลือแค่ metadata สี/ไอคอน
// ที่หน้านี้ใช้เฉพาะไว้ที่นี่
const SEVERITY_LEVELS = [
  { key: "ต่ำ", color: "#10B981", icon: CheckCircle2 },
  { key: "ปกติ", color: "#3B82F6", icon: Wrench },
  { key: "สูง", color: "#F97316", icon: AlertTriangle },
  { key: "เร่งด่วน", color: "#EF4444", icon: Flame },
];

function parseIsoDate(raw) {
  if (typeof raw !== "string" || !raw) return null;
  const d = new Date(raw);
  return isNaN(d.getTime()) ? null : d;
}

function isSameMonth(date, y, m) {
  return date && date.getFullYear() === y && date.getMonth() === m;
}

// 🔴 ตัวเลือกช่วงเวลา — ใช้ร่วมกันระหว่างโดนัทความรุนแรงกับการ์ดสัดส่วน %
const RANGE_OPTIONS = [
  { key: "today", label: "วันนี้" },
  { key: "week", label: "สัปดาห์นี้" },
  { key: "month", label: "เดือนนี้" },
  { key: "year", label: "ปีนี้" },
  { key: "all", label: "ทั้งหมด" },
];

function filterByCreatedRange(repairs, rangeKey) {
  if (rangeKey === "all") return repairs;
  const now = new Date();
  return repairs.filter((r) => {
    const d = parseIsoDate(r.created_at);
    if (!d) return false;
    if (rangeKey === "today") {
      return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
    }
    if (rangeKey === "week") {
      const startOfWeek = new Date(now);
      startOfWeek.setHours(0, 0, 0, 0);
      startOfWeek.setDate(now.getDate() - now.getDay());
      const endOfWeek = new Date(startOfWeek);
      endOfWeek.setDate(startOfWeek.getDate() + 7);
      return d >= startOfWeek && d < endOfWeek;
    }
    if (rangeKey === "month") {
      return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
    }
    if (rangeKey === "year") {
      return d.getFullYear() === now.getFullYear();
    }
    return true;
  });
}

// -----------------------------------------------------------------------------
// [แก้ไข] การ์ดสถิติแถวบน — งานทั้งหมด + 4 ระดับความรุนแรง (แทนที่ชุดเดิม)
// -----------------------------------------------------------------------------
function SeverityStatCard({ icon: Icon, label, value, color }) {
  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[170px]">
      <div className="flex items-center gap-2 mb-3">
        <div
          className="w-9 h-9 rounded-xl flex items-center justify-center shrink-0"
          style={{ background: `${color}18`, color }}
        >
          <Icon size={18} />
        </div>
        <span className="text-sm text-slate-500">{label}</span>
      </div>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-semibold text-slate-900">{value}</span>
        <span className="text-sm text-slate-400">งาน</span>
      </div>
    </div>
  );
}

// ตัวเลือกช่วงเวลาแบบ dropdown เล็ก ๆ ใช้ร่วมกันระหว่างโดนัทกับการ์ดสัดส่วน %
function RangePicker({ range, onChange }) {
  const [open, setOpen] = useState(false);
  const label = RANGE_OPTIONS.find((r) => r.key === range)?.label;
  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1 text-xs text-slate-500 bg-slate-50 rounded-lg px-2 py-1 hover:bg-slate-100"
      >
        {label} <ChevronDown size={12} />
      </button>
      {open ? (
        <div className="absolute right-0 mt-1 bg-white border border-slate-100 rounded-xl shadow-lg py-1 z-10 w-32">
          {RANGE_OPTIONS.map((opt) => (
            <button
              key={opt.key}
              onClick={() => {
                onChange(opt.key);
                setOpen(false);
              }}
              className={
                "w-full text-left px-3 py-1.5 text-xs hover:bg-slate-50 " +
                (range === opt.key ? "text-blue-600 font-medium" : "text-slate-600")
              }
            >
              {opt.label}
            </button>
          ))}
        </div>
      ) : null}
    </div>
  );
}

// -----------------------------------------------------------------------------
// [แก้ไข] โดนัทความรุนแรง + การ์ดสัดส่วน % — แชร์ range เดียวกัน (แทนที่โดนัท
// สถานะ + การ์ด "ต้องดำเนินการ" + แถบ "สัดส่วนสถานะงานซ่อม" เดิมทั้ง 3 อย่าง)
// -----------------------------------------------------------------------------
function SeverityBreakdownSection({ repairs }) {
  const [range, setRange] = useState("all");
  const filtered = filterByCreatedRange(repairs, range);

  const counts = { ต่ำ: 0, ปกติ: 0, สูง: 0, เร่งด่วน: 0 };
  filtered.forEach((r) => {
    counts[extractSeverity(r.detail)]++;
  });
  const total = filtered.length;

  const donutData = SEVERITY_LEVELS.map((s) => ({ label: s.key, value: counts[s.key], color: s.color })).filter(
    (s) => s.value > 0
  );

  // 🔴 [แก้ไข] รวมโดนัทความรุนแรง + สัดส่วนร้อยละ เข้าเป็นการ์ดเดียวกัน (เดิม
  // เป็น 2 การ์ดแยกกันวางคู่กัน) ตามที่ขอ — แชร์หัวข้อ + ตัวเลือกช่วงเวลาเดียวกัน
  // ด้านบน แล้วแบ่งเนื้อหาเป็น 2 ครึ่งซ้าย-ขวาภายในกรอบเดียว (โดนัทซ้าย, แถบ
  // ร้อยละขวา) — ใช้ flex-[1.2] ให้มีสัดส่วนใกล้เคียงกับ JobsCard ที่วางคู่กัน
  // ในแถวเดียวกัน (JobsCard ก็ใช้ flex-[1.2] เหมือนกัน)
  return (
    <Card className="flex-[1.8] min-w-[420px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">สถิติงานซ่อมตามระดับความรุนแรง</h3>
        <RangePicker range={range} onChange={setRange} />
      </div>
      <div className="flex flex-wrap gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-[220px]">
          <div className="relative w-28 h-28 shrink-0">
            {donutData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={donutData} dataKey="value" innerRadius={35} outerRadius={50} paddingAngle={2} stroke="none">
                    {donutData.map((s, i) => <Cell key={i} fill={s.color} />)}
                  </Pie>
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="w-full h-full rounded-full border-[12px] border-slate-100" />
            )}
            <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
              <span className="text-base font-semibold text-slate-900">{total}</span>
              <span className="text-[9px] text-slate-400 text-center leading-tight">งานทั้งหมด</span>
            </div>
          </div>
          <div className="space-y-2 flex-1">
            {SEVERITY_LEVELS.map((s) => (
              <div key={s.key} className="flex items-center justify-between text-xs">
                <span className="flex items-center gap-2 text-slate-600">
                  <span className="w-2 h-2 rounded-full shrink-0" style={{ background: s.color }} />
                  {s.key}
                </span>
                <span className="text-slate-400">{counts[s.key]} งาน</span>
              </div>
            ))}
          </div>
        </div>

        <div className="w-px bg-slate-100 shrink-0 hidden sm:block" />

        <div className="flex-1 min-w-[220px]">
          <p className="text-xs font-semibold text-slate-500 mb-3">สัดส่วนความรุนแรง (ร้อยละ)</p>
          {total === 0 ? (
            <p className="text-xs text-slate-400 text-center py-6">ไม่มีงานซ่อมในช่วงเวลานี้</p>
          ) : (
            <div className="space-y-3">
              {SEVERITY_LEVELS.map((s) => {
                const pct = total > 0 ? (counts[s.key] / total) * 100 : 0;
                return (
                  <div key={s.key}>
                    <div className="flex items-center justify-between text-xs mb-1">
                      <span className="flex items-center gap-1.5 font-medium text-slate-600">
                        <s.icon size={12} style={{ color: s.color }} />
                        {s.key}
                      </span>
                      <span className="font-semibold text-slate-700">{pct.toFixed(0)}% ({counts[s.key]} งาน)</span>
                    </div>
                    <div className="h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div className="h-full rounded-full transition-all" style={{ width: `${pct}%`, background: s.color }} />
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </Card>
  );
}

// -----------------------------------------------------------------------------
// [ผสมจากแอปมือถือ — เหมือนเดิม] การ์ดงานซ่อมเดือนนี้ — ตรงกับ _JobsCard
// -----------------------------------------------------------------------------
function JobsCard({ jobsThisMonth, completedThisMonth, growthPercent }) {
  const isUp = (growthPercent ?? 0) >= 0;
  return (
    <Card className="flex-[1.2] min-w-[260px]">
      <div className="flex items-center gap-2 mb-3">
        <div className="w-7 h-7 rounded-lg flex items-center justify-center shrink-0" style={{ background: BRAND }}>
          <Wrench size={14} className="text-white" />
        </div>
        <span className="text-sm font-semibold text-slate-800">งานซ่อมเดือนนี้</span>
      </div>
      <p className="text-4xl font-bold leading-none" style={{ color: BRAND }}>{jobsThisMonth}</p>
      <p className="text-xs text-slate-500 mt-1">งาน</p>
      <div className="mt-3">
        {growthPercent !== null ? (
          <span
            className={`inline-block text-[11px] font-semibold px-2.5 py-1 rounded-full ${
              isUp ? "bg-emerald-50 text-emerald-600" : "bg-red-50 text-red-600"
            }`}
          >
            {isUp ? "+" : ""}
            {growthPercent.toFixed(0)}% จากเดือนก่อน
          </span>
        ) : (
          <span className="text-[11px] text-slate-400">ยังไม่มีข้อมูลเดือนก่อนสำหรับเปรียบเทียบ</span>
        )}
      </div>
      <p className="text-xs text-slate-500 mt-3">
        เสร็จสิ้นแล้ว {completedThisMonth} จาก {jobsThisMonth} งาน
      </p>
    </Card>
  );
}

// [ผสมจากแอปมือถือ — เหมือนเดิม] การ์ดจำนวนผู้ใช้งาน — ตรงกับ _UserCard
function UserCard({ customerCount, technicianCount, adminCount }) {
  const total = customerCount + technicianCount + adminCount;
  const rows = [
    { label: "ช่าง", value: technicianCount, color: BRAND },
    { label: "แอดมิน", value: adminCount, color: "#7A1616" },
    { label: "ลูกค้า", value: customerCount, color: "#94A3B8" },
  ];
  // 🔴 [แก้ไข] เดิมการ์ดนี้สูงตามเนื้อหาเฉย ๆ (ไม่มี h-full) พอมาอยู่แถวเดียวกับ
  // "รายงานประจำเดือน" ที่เนื้อหายาวกว่า แถวนอก (flex) ยืดพื้นที่ให้เท่ากันก็จริง
  // แต่กล่องสีขาวข้างในของการ์ดนี้ไม่ได้ยืดตาม เลยเห็นเป็นกล่องเตี้ยลอยอยู่ใน
  // พื้นที่ว่างเปล่าด้านล่าง ดูไม่สมดุลกับกล่องข้าง ๆ — เพิ่ม h-full ให้เต็มพื้นที่
  // ที่ถูกยืดไว้ แล้วจัดเนื้อหาให้กระจายเต็มความสูงพอดี (flex flex-col +
  // justify-between) แทนที่จะกองไว้บนสุดแล้วเหลือช่องว่างล่างสุด
  return (
    <Card className="flex-1 min-w-[220px] h-full flex flex-col">
      <p className="text-sm font-semibold text-slate-800 mb-1">จำนวนผู้ใช้งาน</p>
      <div className="flex-1 flex flex-col justify-center">
        <div className="text-center py-1">
          <p className="text-2xl font-bold" style={{ color: BRAND }}>{total}</p>
          <p className="text-[11px] text-slate-400">ผู้ใช้งานทั้งหมด</p>
        </div>
        <div className="space-y-2 mt-3">
          {rows.map((r) => (
            <div key={r.label} className="flex items-center justify-between text-xs">
              <span className="flex items-center gap-1.5 text-slate-600">
                <span className="w-2 h-2 rounded-full shrink-0" style={{ background: r.color }} />
                {r.label}
              </span>
              <span className="font-semibold" style={{ color: BRAND }}>{r.value}</span>
            </div>
          ))}
        </div>
      </div>
    </Card>
  );
}

// [ผสมจากแอปมือถือ — เหมือนเดิม] กราฟการเงินย้อนหลัง 6 เดือน — ตรงกับ _FinanceCard
function FinanceCard({ monthlyRevenue, totalPaid, totalPending }) {
  const maxVal = Math.max(1, ...monthlyRevenue.flatMap((m) => [m.paid, m.pending]));
  return (
    <Card>
      <div className="flex items-center justify-between mb-4">
        <p className="text-sm font-semibold text-slate-800">สถิติการเงินย้อนหลัง 6 เดือน</p>
        <div className="flex items-center gap-3 text-[11px] text-slate-500">
          <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full" style={{ background: BRAND }} />ชำระแล้ว</span>
          <span className="flex items-center gap-1"><span className="w-2 h-2 rounded-full bg-amber-400" />รอชำระ</span>
        </div>
      </div>
      <div className="flex items-end gap-2 h-32">
        {monthlyRevenue.map((m) => (
          <div key={m.label} className="flex-1 flex flex-col items-center justify-end h-full">
            <div className="flex items-end gap-1 flex-1">
              <div
                className="w-2.5 rounded-sm"
                style={{ height: `${Math.max(2, (m.paid / maxVal) * 100)}%`, background: BRAND }}
              />
              <div
                className="w-2.5 rounded-sm bg-amber-400"
                style={{ height: `${Math.max(2, (m.pending / maxVal) * 100)}%` }}
              />
            </div>
            <span className="text-[10px] text-slate-400 mt-1.5">{m.label}</span>
          </div>
        ))}
      </div>
      <div className="flex gap-3 mt-4">
        <div className="flex-1 rounded-xl bg-red-50 px-3 py-2">
          <p className="text-[10px] text-slate-500">รายรับที่ชำระแล้ว</p>
          <p className="text-sm font-bold" style={{ color: BRAND }}>฿{totalPaid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</p>
        </div>
        <div className="flex-1 rounded-xl bg-amber-50 px-3 py-2">
          <p className="text-[10px] text-slate-500">รอการชำระ</p>
          <p className="text-sm font-bold text-amber-600">฿{totalPending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</p>
        </div>
      </div>
    </Card>
  );
}

// [ผสมจากแอปมือถือ — เหมือนเดิม] การ์ดรายงานประจำเดือน + ทางลัด — ตรงกับ
// _ReportsCard — 2 แถวสุดท้ายกดไม่ได้เหมือนในแอป (ยังไม่มีระบบเก็บข้อมูลจริง)
function ReportRow({ title, subtitle, status, statusColor, onClick }) {
  const clickable = Boolean(onClick);
  return (
    <button
      onClick={onClick}
      disabled={!clickable}
      className={`w-full flex items-center justify-between gap-3 rounded-xl px-3 py-2.5 text-left ${
        clickable ? "hover:bg-slate-50 cursor-pointer" : "cursor-default"
      }`}
    >
      <div className="min-w-0">
        <p className="text-sm font-medium text-slate-800 truncate">{title}</p>
        <p className="text-xs text-slate-400 mt-0.5 truncate">{subtitle}</p>
      </div>
      <span
        className="text-[11px] font-semibold px-2.5 py-1 rounded-full shrink-0"
        style={{ background: `${statusColor}18`, color: statusColor }}
      >
        {status}
      </span>
    </button>
  );
}

function ReportsCard({ data, onNavigate }) {
  const jobsDone = data.completedThisMonth === data.jobsThisMonth && data.jobsThisMonth > 0;
  const items = [
    {
      title: "สรุปงานซ่อมประจำเดือน",
      subtitle: `เสร็จแล้ว ${data.completedThisMonth}/${data.jobsThisMonth} งาน`,
      status: jobsDone ? "เสร็จสิ้น" : "กำลังซ่อม",
      color: jobsDone ? "#10B981" : "#3B82F6",
      onClick: () => onNavigate?.("jobs"),
    },
    {
      title: "รายรับ-รายจ่ายประจำเดือน",
      subtitle: `ชำระแล้ว ฿${data.totalPaid.toLocaleString("th-TH", { maximumFractionDigits: 0 })} • รอชำระ ฿${data.totalPending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}`,
      status: "เสร็จสิ้น",
      color: "#10B981",
      onClick: () => onNavigate?.("finance"),
    },
    {
      title: "รายงานสต็อกอะไหล่",
      subtitle: data.lowStockCount > 0 ? `มีอะไหล่ใกล้หมด ${data.lowStockCount} รายการ` : "สต็อกอะไหล่อยู่ในเกณฑ์ปกติ",
      status: data.lowStockCount > 0 ? "รอตรวจสอบ" : "เสร็จสิ้น",
      color: data.lowStockCount > 0 ? "#D97706" : "#10B981",
      onClick: () => onNavigate?.("parts"),
    },
    {
      title: "ประเมินผลช่างซ่อม",
      subtitle: "ยังไม่มีระบบเก็บคะแนนช่างในฐานข้อมูล",
      status: "ยังไม่รองรับ",
      color: "#94A3B8",
    },
    {
      title: "รายงานความพึงพอใจลูกค้า",
      subtitle: "ยังไม่มีระบบเก็บแบบสอบถามในฐานข้อมูล",
      status: "ยังไม่รองรับ",
      color: "#94A3B8",
    },
  ];

  return (
    <Card className="flex-[2] min-w-[320px]">
      <p className="text-sm font-semibold text-slate-800 mb-2">รายงานประจำเดือน</p>
      <div className="space-y-1">
        {items.map((item) => (
          <ReportRow
            key={item.title}
            title={item.title}
            subtitle={item.subtitle}
            status={item.status}
            statusColor={item.color}
            onClick={item.onClick}
          />
        ))}
      </div>
    </Card>
  );
}

// -----------------------------------------------------------------------------
// [แก้ไข] "สถิติการเบิกอะไหล่" — ออกแบบใหม่ทั้งหมดแทนที่การ์ด "คำขอเบิกอะไหล่
// ที่รออนุมัติ" เดิม โชว์ยอดที่เบิกไปแล้วจริง (จำนวนชิ้น/มูลค่า) + อะไหล่ที่ถูก
// เบิกบ่อยที่สุด แทนที่จะโชว์แค่จำนวนคำขอที่ค้างอนุมัติเฉย ๆ
// 🔴 [แก้ไข] top 5 -> top 10 + ปุ่ม "ดูทั้งหมด" เปิด modal ดูอะไหล่ที่เบิกทุก
// รายการ (ไม่จำกัดแค่ 10) + เปลี่ยนกล่อง "รออนุมัติ" เป็น "คำขอที่ถูกอนุมัติ
// ทั้งหมด" (นับจำนวนคำขอที่อนุมัติแล้ว ไม่ใช่จำนวนที่ค้างอนุมัติ) ส่วนกล่อง
// "ถูกปฏิเสธ" ไม่แก้ไขตามที่ขอ
// -----------------------------------------------------------------------------
function computePartsUsage(partRequests, spareParts) {
  const approved = partRequests.filter((p) => p.status === "อนุมัติแล้ว");
  const rejectedCount = partRequests.filter((p) => p.status === "ปฏิเสธ").length;

  // 🐛 [แก้บัค] เดิมจับคู่ด้วย record_id (ฟิลด์ id ภายในของอะไหล่ ซึ่งฝั่งแอป
  // เปลี่ยนมาส่ง part_id เป็น Firebase key จริงแล้ว ไม่ใช่ id ภายในนี้อีกต่อไป)
  // เปลี่ยนมาจับคู่ด้วย .id (Firebase key จริง) แทน ให้ตรงกับทุกจุดที่แก้ไปแล้ว
  const priceOf = (partId) => Number(spareParts.find((p) => String(p.id) === String(partId))?.price) || 0;

  const totalApprovedQty = approved.reduce((sum, p) => sum + (Number(p.quantity) || 0), 0);
  const totalApprovedValue = approved.reduce((sum, p) => sum + (Number(p.quantity) || 0) * priceOf(p.part_id), 0);

  // รวมยอดเบิกต่อรายการอะไหล่ (จับคู่ด้วยชื่อ กันกรณี part_id ไม่ตรงกับ part_name)
  const byPart = {};
  approved.forEach((p) => {
    const key = p.part_name || `#${p.part_id}`;
    const qty = Number(p.quantity) || 0;
    if (!byPart[key]) byPart[key] = { name: key, qty: 0, value: 0 };
    byPart[key].qty += qty;
    byPart[key].value += qty * priceOf(p.part_id);
  });
  const allParts = Object.values(byPart).sort((a, b) => b.qty - a.qty);

  return {
    approvedCount: approved.length,
    rejectedCount,
    totalApprovedQty,
    totalApprovedValue,
    allParts,
  };
}

// modal "ดูทั้งหมด" — รายการอะไหล่ที่ถูกเบิกทุกรายการ ไม่จำกัดแค่ 10 อันดับแรก
function AllPartsUsageModal({ allParts, onClose }) {
  const maxQty = Math.max(1, ...allParts.map((p) => p.qty));
  return (
    <Modal title="อะไหล่ที่ถูกเบิกทั้งหมด" onClose={onClose}>
      {allParts.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีการเบิกอะไหล่ที่อนุมัติแล้วในระบบ</p>
      ) : (
        <div className="space-y-2.5 max-h-[60vh] overflow-y-auto pr-1">
          {allParts.map((p, i) => (
            <div key={p.name} className="flex items-center gap-3">
              <span className="text-[11px] text-slate-400 w-5 shrink-0">{i + 1}.</span>
              <span className="text-xs text-slate-600 w-36 truncate shrink-0">{p.name}</span>
              <div className="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                <div className="h-full rounded-full" style={{ width: `${(p.qty / maxQty) * 100}%`, background: BRAND }} />
              </div>
              <span className="text-xs font-semibold text-slate-700 w-14 text-right shrink-0">{p.qty} ชิ้น</span>
              <span className="text-xs text-slate-400 w-20 text-right shrink-0">฿{p.value.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</span>
            </div>
          ))}
        </div>
      )}
    </Modal>
  );
}

function PartsUsageStatsCard({ partRequests, spareParts }) {
  const [showAll, setShowAll] = useState(false);
  const usage = computePartsUsage(partRequests, spareParts);
  const topParts = usage.allParts.slice(0, 10);
  const maxQty = Math.max(1, ...topParts.map((p) => p.qty));

  return (
    <Card>
      <h3 className="text-sm font-semibold text-slate-800 mb-4">สถิติการเบิกอะไหล่</h3>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <div className="rounded-xl bg-red-50 px-3 py-3">
          <p className="text-[10px] text-slate-500">เบิกไปแล้ว (ชิ้น)</p>
          <p className="text-lg font-bold" style={{ color: BRAND }}>{usage.totalApprovedQty.toLocaleString("th-TH")}</p>
        </div>
        <div className="rounded-xl bg-red-50 px-3 py-3">
          <p className="text-[10px] text-slate-500">มูลค่ารวม</p>
          <p className="text-lg font-bold" style={{ color: BRAND }}>฿{usage.totalApprovedValue.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</p>
        </div>
        {/* 🔴 [แก้ไข] เปลี่ยนจาก "รออนุมัติ" (จำนวนคำขอค้าง) เป็น "คำขอที่ถูก
            อนุมัติทั้งหมด" (จำนวนคำขอที่อนุมัติแล้วทั้งหมด) ตามที่ขอ */}
        <div className="rounded-xl bg-emerald-50 px-3 py-3">
          <p className="text-[10px] text-slate-500">คำขอที่ถูกอนุมัติทั้งหมด</p>
          <p className="text-lg font-bold text-emerald-600">{usage.approvedCount} คำขอ</p>
        </div>
        <div className="rounded-xl bg-slate-50 px-3 py-3">
          <p className="text-[10px] text-slate-500">ถูกปฏิเสธ</p>
          <p className="text-lg font-bold text-slate-500">{usage.rejectedCount} คำขอ</p>
        </div>
      </div>

      <div className="flex items-center justify-between mb-2">
        <p className="text-xs font-semibold text-slate-500">อะไหล่ที่ถูกเบิกบ่อยที่สุด (10 อันดับแรก)</p>
        {usage.allParts.length > 10 ? (
          <button onClick={() => setShowAll(true)} className="text-[11px] text-blue-500 font-medium hover:text-blue-600">
            ดูทั้งหมด ({usage.allParts.length})
          </button>
        ) : null}
      </div>
      {topParts.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีการเบิกอะไหล่ที่อนุมัติแล้วในระบบ</p>
      ) : (
        <div className="space-y-2.5">
          {topParts.map((p) => (
            <div key={p.name} className="flex items-center gap-3">
              <Package size={14} className="text-slate-400 shrink-0" />
              <span className="text-xs text-slate-600 w-32 truncate shrink-0">{p.name}</span>
              <div className="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                <div
                  className="h-full rounded-full"
                  style={{ width: `${(p.qty / maxQty) * 100}%`, background: BRAND }}
                />
              </div>
              <span className="text-xs font-semibold text-slate-700 w-14 text-right shrink-0">{p.qty} ชิ้น</span>
            </div>
          ))}
        </div>
      )}

      {showAll ? <AllPartsUsageModal allParts={usage.allParts} onClose={() => setShowAll(false)} /> : null}
    </Card>
  );
}


// -----------------------------------------------------------------------------
// 🔴 [แก้ไข] "ดาวน์โหลดรายงาน" — ออกแบบหน้ารายงานสวย ๆ ให้ดูก่อนโหลดจริง แล้ว
// กด "พิมพ์ / บันทึกเป็น PDF" ซึ่งเรียก window.print() ของเบราว์เซอร์ (เลือก
// "บันทึกเป็น PDF" ในหน้าต่างพิมพ์ได้เลย) — ใช้ CSS @media print ซ่อนทุกอย่าง
// นอก #print-report-area ตอนพิมพ์ เพื่อให้ได้เฉพาะเนื้อหารายงาน ไม่ติดเมนู/
// ปุ่มต่าง ๆ ของเว็บมาด้วย ไม่ต้องเพิ่มไลบรารี PDF ใหม่เข้าโปรเจกต์
// -----------------------------------------------------------------------------
function ReportPreviewModal({ companyName, severityCounts, totalRepairs, mobileData, growthPercent, monthlyRevenue, totalPaid, totalPending, partsUsage, onClose }) {
  const now = new Date();
  const dateLabel = `${now.getDate()}/${now.getMonth() + 1}/${now.getFullYear() + 543}`;

  return (
    <Modal
      title="ตัวอย่างรายงานก่อนดาวน์โหลด"
      onClose={onClose}
      wide
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ปิด
          </button>
          <button
            onClick={() => window.print()}
            className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white"
            style={{ background: BRAND }}
          >
            <Printer size={15} />
            พิมพ์ / บันทึกเป็น PDF
          </button>
        </>
      }
    >
      {/* 🔴 เฉพาะส่วนนี้เท่านั้นที่จะโชว์ตอนสั่งพิมพ์ (ดู <style> ด้านล่าง) */}
      <style>{`
        @media print {
          /* 🐛 [แก้ไข] BUG เดียวกับหน้า Dashboard/การเงิน — Modal ที่ห่ออยู่มี
             overflow-y-auto + max-h-[88vh] เป็น position: relative อยู่แล้ว
             ใช้ position: absolute ให้พื้นที่พิมพ์เลยโดนตัดตามกรอบ Modal แทน
             เปลี่ยนเป็น fixed ให้ยึดวิวพอร์ตทั้งหน้าแทน */
          body * { visibility: hidden; }
          #print-report-area, #print-report-area * { visibility: visible; }
          #print-report-area {
            position: fixed;
            inset: 0;
            width: 100%;
            height: auto;
            overflow: visible;
            padding: 24px;
            margin: 0;
          }
        }
      `}</style>

      <div id="print-report-area" className="text-slate-800">
        <div className="text-center mb-6 pb-4 border-b border-slate-200">
          <h1 className="text-lg font-bold" style={{ color: BRAND }}>{companyName || "ระบบแจ้งซ่อม After Sales"}</h1>
          <p className="text-sm font-semibold text-slate-700 mt-1">รายงานสรุประบบแจ้งซ่อม</p>
          <p className="text-xs text-slate-400 mt-0.5">ข้อมูล ณ วันที่ {dateLabel}</p>
        </div>

        <section className="mb-5">
          <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">งานซ่อมตามระดับความรุนแรง (ทั้งหมด)</h3>
          <table className="w-full text-xs">
            <tbody>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">งานทั้งหมด</td>
                <td className="py-1.5 text-right font-semibold">{totalRepairs} งาน</td>
              </tr>
              {SEVERITY_LEVELS.map((s) => (
                <tr key={s.key} className="border-b border-slate-50">
                  <td className="py-1.5 text-slate-500">ระดับ{s.key}</td>
                  <td className="py-1.5 text-right font-semibold">{severityCounts[s.key]} งาน</td>
                </tr>
              ))}
            </tbody>
          </table>
        </section>

        <section className="mb-5">
          <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">งานซ่อมเดือนนี้</h3>
          <table className="w-full text-xs">
            <tbody>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">งานทั้งหมด</td>
                <td className="py-1.5 text-right font-semibold">{mobileData.jobsThisMonth} งาน</td>
              </tr>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">เสร็จสิ้นแล้ว</td>
                <td className="py-1.5 text-right font-semibold">{mobileData.completedThisMonth} งาน</td>
              </tr>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">การเติบโตจากเดือนก่อน</td>
                <td className="py-1.5 text-right font-semibold">{growthPercent === null ? "-" : `${growthPercent.toFixed(1)}%`}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section className="mb-5">
          <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">การเงินย้อนหลัง 6 เดือน</h3>
          <table className="w-full text-xs">
            <thead>
              <tr className="text-slate-400 border-b border-slate-100">
                <th className="text-left font-medium py-1">เดือน</th>
                <th className="text-right font-medium py-1">ชำระแล้ว</th>
                <th className="text-right font-medium py-1">รอชำระ</th>
              </tr>
            </thead>
            <tbody>
              {monthlyRevenue.map((m) => (
                <tr key={m.label} className="border-b border-slate-50">
                  <td className="py-1.5 text-slate-500">{m.label}</td>
                  <td className="py-1.5 text-right">฿{m.paid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
                  <td className="py-1.5 text-right">฿{m.pending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
                </tr>
              ))}
              <tr className="font-semibold">
                <td className="py-1.5">รวม</td>
                <td className="py-1.5 text-right">฿{totalPaid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
                <td className="py-1.5 text-right">฿{totalPending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section>
          <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">สถิติการเบิกอะไหล่</h3>
          <table className="w-full text-xs mb-3">
            <tbody>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">เบิกไปแล้ว (ชิ้น)</td>
                <td className="py-1.5 text-right font-semibold">{partsUsage.totalApprovedQty.toLocaleString("th-TH")}</td>
              </tr>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">มูลค่ารวม</td>
                <td className="py-1.5 text-right font-semibold">฿{partsUsage.totalApprovedValue.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
              </tr>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">คำขอที่ถูกอนุมัติทั้งหมด</td>
                <td className="py-1.5 text-right font-semibold">{partsUsage.approvedCount} คำขอ</td>
              </tr>
              <tr className="border-b border-slate-50">
                <td className="py-1.5 text-slate-500">ถูกปฏิเสธ</td>
                <td className="py-1.5 text-right font-semibold">{partsUsage.rejectedCount} คำขอ</td>
              </tr>
            </tbody>
          </table>
          {partsUsage.allParts.length > 0 ? (
            <>
              <p className="text-xs font-semibold text-slate-500 mb-1">อะไหล่ที่ถูกเบิกบ่อยที่สุด (10 อันดับแรก)</p>
              <table className="w-full text-xs">
                <thead>
                  <tr className="text-slate-400 border-b border-slate-100">
                    <th className="text-left font-medium py-1">อะไหล่</th>
                    <th className="text-right font-medium py-1">จำนวน</th>
                    <th className="text-right font-medium py-1">มูลค่า</th>
                  </tr>
                </thead>
                <tbody>
                  {partsUsage.allParts.slice(0, 10).map((p) => (
                    <tr key={p.name} className="border-b border-slate-50">
                      <td className="py-1.5 text-slate-600">{p.name}</td>
                      <td className="py-1.5 text-right">{p.qty} ชิ้น</td>
                      <td className="py-1.5 text-right">฿{p.value.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </>
          ) : null}
        </section>
      </div>
    </Modal>
  );
}

export default function ReportsPage({ onNavigate }) {
  const { data: repairs, loading: loadingRepairs } = useDbList("repairs");
  const { data: partRequests, loading: loadingRequests } = useDbList("part_requests");
  const { data: customers, loading: loadingCustomers } = useDbList("customers");
  const { data: technicians, loading: loadingTechnicians } = useDbList("technicians");
  const { data: admins, loading: loadingAdmins } = useDbList("admins");
  const { data: spareParts, loading: loadingParts } = useDbList("spare_parts");
  const [copied, setCopied] = useState(false);
  // 🔴 [แก้ไข] state เปิด/ปิด modal ตัวอย่างรายงานก่อนดาวน์โหลด + ชื่อบริษัท
  // (ดึงจากหน้าตั้งค่า ใช้โชว์เป็นหัวรายงาน)
  const [showReportPreview, setShowReportPreview] = useState(false);
  const [companyName, setCompanyName] = useState("");

  useEffect(() => {
    getWebSettings()
      .then((s) => setCompanyName(s?.companyName || ""))
      .catch((err) => console.error("[ReportsPage] load settings failed:", err));
  }, []);

  const loading =
    loadingRepairs || loadingRequests || loadingCustomers || loadingTechnicians || loadingAdmins || loadingParts;

  if (loading) {
    return <div className="text-sm text-slate-400 py-10 text-center">กำลังโหลดข้อมูล...</div>;
  }

  // [แก้ไข] การ์ดสถิติแถวบน — งานทั้งหมด (ทุกช่วงเวลา) + จำนวนงานแยกตามระดับ
  // ความรุนแรง (แทนที่ชุดเดิมที่นับตามสถานะ/urgency ปลอม)
  const severityCounts = { ต่ำ: 0, ปกติ: 0, สูง: 0, เร่งด่วน: 0 };
  repairs.forEach((r) => {
    severityCounts[extractSeverity(r.detail)]++;
  });
  const TOP_STAT_CARDS = [
    { icon: ClipboardList, label: "งานทั้งหมด", value: repairs.length, color: "#3B82F6" },
    ...SEVERITY_LEVELS.map((s) => ({ icon: s.icon, label: `ระดับ${s.key}`, value: severityCounts[s.key], color: s.color })),
  ];

  // ===== [ผสมจากแอปมือถือ — เหมือนเดิม] เดือนนี้เทียบเดือนก่อน + การเงิน 6 เดือน =====
  const now = new Date();

  // 🐛 [แก้บัค] เหมือนฝั่งแอปมือถือ/DashboardPage: สถานะ "เสร็จแล้ว" ที่ระบบเขียนลง DB
  // จริงมี 3 ค่า (เดิมเช็คแค่ 2 ค่า ขาด "เสร็จสิ้นแล้ว")
  const isCompletedStatus = (status) =>
    status === "เสร็จแล้ว" || status === "เสร็จสิ้น" || status === "เสร็จสิ้นแล้ว";

  // 🐛 [แก้บัค] วันที่ "เสร็จงาน" จริงต้องดูจาก report_submitted_at (วันที่ส่งรายงาน
  // ปิดงาน) ไม่ใช่ created_at (วันที่สร้างงาน) — เดิมกรองงานเดือนนี้จาก created_at
  // ก่อนแล้วค่อยเช็คสถานะ ทำให้งานที่ "สร้างเดือนก่อน แต่เพิ่งมาเสร็จเดือนนี้" ไม่ถูกนับ
  // เลยทั้งตัวเศษ (เสร็จแล้ว) และตัวส่วน (งานทั้งหมด) การ์ดเลยโชว์ 0/0 ทั้งที่มีงานเสร็จจริง
  const completionDate = (r) => parseIsoDate(r.report_submitted_at) || parseIsoDate(r.created_at);

  // งานซ่อมที่ "เกี่ยวข้อง" กับเดือนที่ระบุ = สร้างเดือนนั้น หรือ เสร็จเดือนนั้น
  const isRelevantToMonth = (r, y, m) => {
    const createdInMonth = isSameMonth(parseIsoDate(r.created_at), y, m);
    const completedInMonth = isCompletedStatus(r.status) && isSameMonth(completionDate(r), y, m);
    return createdInMonth || completedInMonth;
  };

  const thisMonthRepairs = repairs.filter((r) => isRelevantToMonth(r, now.getFullYear(), now.getMonth()));
  const lastMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const lastMonthCount = repairs.filter((r) =>
    isRelevantToMonth(r, lastMonthDate.getFullYear(), lastMonthDate.getMonth())
  ).length;
  const completedThisMonth = thisMonthRepairs.filter((r) => isCompletedStatus(r.status)).length;

  let growthPercent = null;
  if (lastMonthCount > 0) {
    const raw = ((thisMonthRepairs.length - lastMonthCount) / lastMonthCount) * 100;
    growthPercent = Math.abs(raw) < 0.01 ? 0 : raw;
  }

  const monthlyRevenue = Array.from({ length: 6 }, (_, index) => {
    const target = new Date(now.getFullYear(), now.getMonth() - (5 - index), 1);
    let paid = 0;
    let pending = 0;
    repairs.forEach((r) => {
      if (isSameMonth(parseIsoDate(r.created_at), target.getFullYear(), target.getMonth())) {
        const price = Number(r.total_price) || 0;
        if (r.is_paid === 1 || r.is_paid === true) paid += price;
        else pending += price;
      }
    });
    return { label: THAI_MONTHS[target.getMonth()], paid, pending };
  });
  const totalPaid = monthlyRevenue.reduce((sum, m) => sum + m.paid, 0);
  const totalPending = monthlyRevenue.reduce((sum, m) => sum + m.pending, 0);
  const lowStockCount = spareParts.filter((p) => (Number(p.stock) || 0) <= 5).length;

  const mobileData = {
    jobsThisMonth: thisMonthRepairs.length,
    completedThisMonth,
    totalPaid,
    totalPending,
    lowStockCount,
  };

  // 🔴 [แก้ไข] คำนวณสถิติการเบิกอะไหล่ไว้ที่นี่ (ใช้ทั้งใน PartsUsageStatsCard
  // และในตัวอย่างรายงานก่อนดาวน์โหลด ผ่านฟังก์ชันกลาง computePartsUsage())
  const partsUsage = computePartsUsage(partRequests, spareParts);

  function handleCopySummary() {
    const lines = [
      "สรุปผลระบบแจ้งซ่อม",
      `ข้อมูล ณ วันที่ ${now.getDate()}/${now.getMonth() + 1}/${now.getFullYear() + 543}`,
      "----------------------------------------",
      "งานซ่อมทั้งหมดแยกตามระดับความรุนแรง",
      `  งานทั้งหมด : ${repairs.length} งาน`,
      ...SEVERITY_LEVELS.map((s) => `  ระดับ${s.key}   : ${severityCounts[s.key]} งาน`),
      "----------------------------------------",
      "จำนวนผู้ใช้งาน",
      `  ลูกค้า        : ${customers.length} คน`,
      `  ช่างเทคนิค    : ${technicians.length} คน`,
      `  แอดมิน        : ${admins.length} คน`,
      "----------------------------------------",
      "งานซ่อมเดือนนี้",
      `  งานทั้งหมด    : ${mobileData.jobsThisMonth} งาน`,
      `  เสร็จสิ้นแล้ว  : ${mobileData.completedThisMonth} งาน`,
      `  การเติบโต     : ${growthPercent === null ? "-" : `${growthPercent.toFixed(1)}%`}`,
      "----------------------------------------",
      "สรุปการเงิน (ย้อนหลัง 6 เดือน)",
      `  ยอดชำระแล้ว    : ${totalPaid.toFixed(2)} บาท`,
      `  ยอดค้างชำระ    : ${totalPending.toFixed(2)} บาท`,
      `  อะไหล่ใกล้หมด  : ${lowStockCount} รายการ`,
    ];
    navigator.clipboard
      ?.writeText(lines.join("\n"))
      .then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      })
      .catch((err) => console.error("[ReportsPage] copy summary failed:", err));
  }

  return (
    <div>
      <div className="flex justify-end gap-2 mb-5">
        <button
          onClick={handleCopySummary}
          className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white border border-slate-200 text-sm font-medium text-slate-600 hover:bg-slate-50"
        >
          {copied ? <Check size={16} className="text-emerald-500" /> : <Share2 size={16} />}
          {copied ? "คัดลอกแล้ว" : "คัดลอกสรุปผล"}
        </button>
        {/* 🔴 [แก้ไข] เพิ่มปุ่ม "ดาวน์โหลดรายงาน" — เปิดตัวอย่างรายงานให้ดูก่อน
            แล้วค่อยสั่งพิมพ์/บันทึกเป็น PDF จากในนั้น */}
        <button
          onClick={() => setShowReportPreview(true)}
          className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white"
          style={{ background: BRAND }}
        >
          <Download size={16} />
          ดาวน์โหลดรายงาน
        </button>
      </div>

      {/* [แก้ไข] การ์ดสถิติแถวบน — งานทั้งหมด + 4 ระดับความรุนแรง แทนที่ชุดเดิม */}
      <div className="flex flex-wrap gap-4 mb-5">
        {TOP_STAT_CARDS.map((s) => <SeverityStatCard key={s.label} {...s} />)}
      </div>

      {/* 🔴 [แก้ไข] สลับตำแหน่ง "จำนวนผู้ใช้งาน" กับ "สถิติงานซ่อมตามระดับความ
          รุนแรง" ตามที่ขอ — งานซ่อมเดือนนี้ยังคงอยู่ข้างเดิม (คู่กับช่องที่สลับ
          มาใหม่) ส่วนจำนวนผู้ใช้งานย้ายไปอยู่แถวถัดไปแทน (ไม่รวมกับงานซ่อม
          เดือนนี้ ตามที่ขอให้แยกช่องกันไว้เหมือนเดิม) */}
      <div className="flex flex-wrap gap-4 mb-5">
        <JobsCard jobsThisMonth={mobileData.jobsThisMonth} completedThisMonth={mobileData.completedThisMonth} growthPercent={growthPercent} />
        <SeverityBreakdownSection repairs={repairs} />
      </div>

      {/* 🔴 [แก้ไข] จำนวนผู้ใช้งาน — ย้ายมาอยู่แถวเดียวกับ "รายงานประจำเดือน"
          แทน (เดิมอยู่แถวเดี่ยว ๆ) แบ่งสัดส่วนพื้นที่ 1:2 ให้จำนวนผู้ใช้งาน
          (เนื้อหาน้อยกว่า) แคบกว่า รายงานประจำเดือน (มีลิสต์ 5 แถว ต้องการพื้นที่
          มากกว่า) แทนที่จะปล่อยให้จำนวนผู้ใช้งานยืดเต็มแถวคนเดียวดูโหวง ๆ */}
      <div className="flex flex-wrap gap-4 mb-5">
        <div className="flex-1 min-w-[220px]">
          <UserCard customerCount={customers.length} technicianCount={technicians.length} adminCount={admins.length} />
        </div>
        <ReportsCard data={mobileData} onNavigate={onNavigate} />
      </div>

      {/* [ผสมจากแอปมือถือ — เหมือนเดิม] กราฟการเงินย้อนหลัง 6 เดือน */}
      <div className="mb-5">
        <FinanceCard monthlyRevenue={monthlyRevenue} totalPaid={totalPaid} totalPending={totalPending} />
      </div>

      {/* [แก้ไข] สถิติการเบิกอะไหล่ แทนที่การ์ดคำขอเบิกอะไหล่ที่รออนุมัติเดิม */}
      <PartsUsageStatsCard partRequests={partRequests} spareParts={spareParts} />

      {showReportPreview ? (
        <ReportPreviewModal
          companyName={companyName}
          severityCounts={severityCounts}
          totalRepairs={repairs.length}
          mobileData={mobileData}
          growthPercent={growthPercent}
          monthlyRevenue={monthlyRevenue}
          totalPaid={totalPaid}
          totalPending={totalPending}
          partsUsage={partsUsage}
          onClose={() => setShowReportPreview(false)}
        />
      ) : null}
    </div>
  );
}