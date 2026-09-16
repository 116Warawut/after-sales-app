import React, { useState, useEffect } from "react";
import {
  ChevronDown,
  ChevronRight,
  ClipboardList,
  UserPlus,
  Wrench,
  CheckCircle2,
  AlertTriangle,
  Ban,
  HelpCircle,
  CalendarClock,
  Flame,
  X,
  UserCog,
  Package,
  Share2,
  Check,
  Download,
  Printer,
  Clock,
} from "lucide-react";
import { PieChart, Pie, Cell, ResponsiveContainer } from "recharts";
import {
  COLORS,
  STATUS_BADGE,
  SEVERITY_BADGE,
  extractSeverity,
  extractRating,
  displayStatus,
  isPendingStatus,
  isInProgressStatus,
  getEffectiveRepairStatus,
  formatDateBySetting,
  displayStoredDate,
} from "../shared/constants";
import { Card, Modal, StarRating, DateField } from "../components/ui";
import useDbList from "../hooks/useDbList";
import useWebSettings from "../hooks/useWebSettings";
import {
  computeDashboardSummary,
  getWebSettings,
  saveWebSettings,
  createNotification,
  updateRow,
} from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";
import JobDetailModal from "../components/JobDetailModal";

function findActiveJobForTech(techUsername, repairs) {
  if (!techUsername) return null;
  const assigned = repairs.filter(
    (r) =>
      r.technician_username === techUsername &&
      r.status !== "เสร็จแล้ว" &&
      r.status !== "เสร็จสิ้น" &&
      !(r.status || "").includes("ยกเลิก")
  );
  if (assigned.length === 0) return null;
  const inProgress = assigned.find((r) => isInProgressStatus(r.status, r));
  if (inProgress) return inProgress;
  const sorted = [...assigned].sort((a, b) => {
    const da = parseThaiDate(a.date);
    const db = parseThaiDate(b.date);
    if (!da || !db) return 0;
    return da - db;
  });
  return sorted[0];
}

function parseThaiDate(dateStr) {
  if (!dateStr) return null;
  const parts = String(dateStr).split("/");
  if (parts.length !== 3) return null;
  const day = Number(parts[0]);
  const month = Number(parts[1]);
  const yearBE = Number(parts[2]);
  if (!day || !month || !yearBE) return null;
  return new Date(yearBE - 543, month - 1, day);
}

function parseIsoDate(raw) {
  if (typeof raw !== "string" || !raw) return null;
  const d = new Date(raw);
  return isNaN(d.getTime()) ? null : d;
}

const STAT_RANGE_OPTIONS = [
  { key: "all", label: "ทั้งหมด" },
  { key: "year", label: "1 ปี" },
  { key: "nineMonths", label: "9 เดือน" },
  { key: "sixMonths", label: "6 เดือน" },
  { key: "threeMonths", label: "3 เดือน" },
  { key: "thisMonth", label: "เดือนนี้" },
  { key: "thisWeek", label: "สัปดาห์นี้" },
  { key: "today", label: "วันนี้" },
];

function filterByRollingRange(repairs, rangeKey) {
  if (rangeKey === "all") return repairs;
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

  if (rangeKey === "today") {
    return repairs.filter((r) => {
      const d = parseThaiDate(r.date);
      return (
        d &&
        d.getFullYear() === todayStart.getFullYear() &&
        d.getMonth() === todayStart.getMonth() &&
        d.getDate() === todayStart.getDate()
      );
    });
  }

  if (rangeKey === "thisWeek") {
    const startOfWeek = new Date(todayStart);
    startOfWeek.setDate(startOfWeek.getDate() - startOfWeek.getDay());
    const endOfWeek = new Date(startOfWeek);
    endOfWeek.setDate(startOfWeek.getDate() + 7);
    return repairs.filter((r) => {
      const d = parseThaiDate(r.date);
      return d && d >= startOfWeek && d < endOfWeek;
    });
  }

  if (rangeKey === "thisMonth") {
    return repairs.filter((r) => {
      const d = parseThaiDate(r.date);
      return d && d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
    });
  }

  const monthsByKey = { year: 12, nineMonths: 9, sixMonths: 6, threeMonths: 3 };
  const months = monthsByKey[rangeKey];
  if (!months) return repairs;
  const cutoff = new Date(todayStart);
  cutoff.setMonth(cutoff.getMonth() - months);
  return repairs.filter((r) => {
    const d = parseThaiDate(r.date);
    return d && d >= cutoff && d <= now;
  });
}

function StatCard({ icon: Icon, label, value, unit, color, statusValue, onNavigate, disableClickThrough }) {
  const c = COLORS[color];
  const clickable = !disableClickThrough;
  return (
    <div
      onClick={clickable ? () => onNavigate?.("jobs", statusValue ? { tab: statusValue } : undefined) : undefined}
      className={
        "bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[180px] transition-shadow " +
        (clickable ? "cursor-pointer hover:border-slate-200 hover:shadow-sm" : "")
      }
    >
      <div className="flex items-center gap-2 mb-3">
        <div className={`w-9 h-9 rounded-xl ${c.bg} ${c.text} flex items-center justify-center`}>
          <Icon size={18} />
        </div>
        <span className="text-sm text-slate-500">{label}</span>
      </div>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-semibold text-slate-900">{value}</span>
        <span className="text-sm text-slate-400">{unit}</span>
      </div>
    </div>
  );
}

function FeaturedStatCard({ icon: Icon, label, value, unit, iconBg, iconColor, statusValue, onNavigate }) {
  return (
    <button
      onClick={() => onNavigate?.("jobs", statusValue ? { tab: statusValue } : undefined)}
      className="bg-white rounded-2xl border border-slate-100 p-5 w-full h-full flex flex-col items-start justify-between text-left cursor-pointer hover:border-slate-200 hover:shadow-sm transition-shadow"
    >
      <div className={`w-11 h-11 rounded-xl ${iconBg} ${iconColor} flex items-center justify-center mb-4`}>
        <Icon size={22} />
      </div>
      <div>
        <p className="text-sm text-slate-500 mb-1">{label}</p>
        <div className="flex items-baseline gap-1">
          <span className="text-3xl font-semibold text-slate-900">{value}</span>
          <span className="text-sm text-slate-400">{unit}</span>
        </div>
      </div>
    </button>
  );
}

function StatRangePicker({ range, onChange }) {
  const [open, setOpen] = useState(false);
  const label = STAT_RANGE_OPTIONS.find((r) => r.key === range)?.label;
  return (
    <div className="relative">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1 text-xs text-slate-600 bg-white border border-slate-200 rounded-lg px-2.5 py-1.5 hover:bg-slate-50"
      >
        {label} <ChevronDown size={12} />
      </button>
      {open ? (
        <div className="absolute left-0 mt-1 bg-white border border-slate-100 rounded-xl shadow-lg py-1 z-10 w-36">
          {STAT_RANGE_OPTIONS.map((opt) => (
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

function NotificationsCard({ notifications, currentUsername, onNavigate }) {
  const adminNotifications = notifications.filter((n) => n.user_username === currentUsername);

  const chatByJob = {};
  const importantNotifications = [];
  adminNotifications.forEach((n) => {
    if (n.type === "CHAT" && n.target_id != null) {
      const key = n.target_id;
      if (!chatByJob[key]) chatByJob[key] = [];
      chatByJob[key].push(n);
    } else {
      importantNotifications.push(n);
    }
  });
  const chatGroups = Object.entries(chatByJob).map(([jobId, items]) => {
    const sorted = [...items].sort(
      (a, b) => (new Date(b.created_at).getTime() || 0) - (new Date(a.created_at).getTime() || 0)
    );
    const latest = sorted[0];
    const unreadCount = items.filter((n) => !n.is_read).length;
    return {
      kind: "chat-group",
      jobId,
      latest,
      unreadCount,
      isRead: unreadCount === 0,
      sortKey: new Date(latest.created_at).getTime() || 0,
    };
  });

  const recent = [
    ...importantNotifications.map((n) => ({
      kind: "single",
      n,
      isRead: !!n.is_read,
      sortKey: new Date(n.created_at).getTime() || 0,
    })),
    ...chatGroups,
  ]
    .sort((a, b) => b.sortKey - a.sortKey)
    .slice(0, 5);

  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-1 min-w-[280px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">การแจ้งเตือนล่าสุด</h3>
        <button
          onClick={() => onNavigate?.("notifications")}
          className="text-xs text-blue-500 font-medium hover:text-blue-600"
        >
          ดูทั้งหมด
        </button>
      </div>
      {recent.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-8">ยังไม่มีการแจ้งเตือน</p>
      ) : (
        <div className="space-y-3">
          {recent.map((item) => {
            const n = item.kind === "chat-group" ? item.latest : item.n;
            const title =
              item.kind === "chat-group"
                ? `ข้อความใหม่ — ${n.title?.replace("ข้อความใหม่: ", "") || `งาน #${item.jobId}`}`
                : n.title || "แจ้งเตือน";
            return (
              <button
                key={item.kind === "chat-group" ? `chat-${item.jobId}` : n.id}
                onClick={() =>
                  item.kind === "chat-group"
                    ? onNavigate?.("chat", { query: String(item.jobId) })
                    : onNavigate?.("notifications", { query: String(n.id) })
                }
                className="flex items-start gap-2 w-full text-left hover:bg-slate-50 rounded-lg -mx-1 px-1 py-0.5"
              >
                <span
                  className={`w-1.5 h-1.5 rounded-full mt-1.5 shrink-0 ${
                    item.isRead ? "bg-slate-200" : "bg-blue-500"
                  }`}
                />
                <div className="min-w-0">
                  <p className="text-xs font-medium text-slate-800 truncate">{title}</p>
                  <p className="text-[11px] text-slate-400 truncate">{n.message}</p>
                </div>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

function RecentJobsTable({ repairs, onNavigate, onSelectJob, pageSize = 5 }) {
  const sorted = [...repairs].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));
  const recent = sorted.slice(0, pageSize);
  const remaining = sorted.length - recent.length;

  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-[1.6] min-w-[420px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">งานล่าสุด</h3>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="text-xs text-slate-400 border-b border-slate-100">
              <th className="py-2 font-medium">Job ID</th>
              <th className="py-2 font-medium">ลูกค้า</th>
              <th className="py-2 font-medium">อุปกรณ์</th>
              <th className="py-2 font-medium">ช่าง</th>
              <th className="py-2 font-medium">วันที่สร้าง</th>
              <th className="py-2 font-medium">สถานะ</th>
              <th className="py-2 font-medium">ระดับความรุนแรง</th>
            </tr>
          </thead>
          <tbody>
            {recent.length === 0 ? (
              <tr>
                <td colSpan={7} className="py-8 text-center text-xs text-slate-400">
                  ยังไม่มีรายการงานซ่อม
                </td>
              </tr>
            ) : (
              recent.map((r) => {
                const effStatus = getEffectiveRepairStatus(r);
                return (
                  <tr
                    key={r.id}
                    onClick={() => onSelectJob(r)}
                    className="border-b border-slate-50 last:border-0 cursor-pointer hover:bg-slate-50"
                  >
                    <td className="py-2.5 text-slate-700">{r.ticketNo || r.id}</td>
                    <td className="py-2.5 text-slate-700">{r.customer_username || "-"}</td>
                    <td className="py-2.5 text-slate-700">{r.machine || "-"}</td>
                    <td className="py-2.5 text-slate-700">{r.technician_username || "ยังไม่มอบหมาย"}</td>
                    <td className="py-2.5 text-slate-500">{displayStoredDate(r.date)}</td>
                    <td className="py-2.5">
                      <span
                        className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${
                          STATUS_BADGE[effStatus] ?? "bg-gray-100 text-gray-500"
                        }`}
                      >
                        {displayStatus(effStatus)}
                      </span>
                    </td>
                    <td className="py-2.5">
                      <span
                        className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${
                          SEVERITY_BADGE[extractSeverity(r.detail)] ?? "bg-gray-100 text-gray-500"
                        }`}
                      >
                        {extractSeverity(r.detail)}
                      </span>
                    </td>
                  </tr>
                );
              })
            )}
          </tbody>
        </table>
      </div>

      {remaining > 0 ? (
        <div className="flex items-center justify-between mt-3 pt-3 border-t border-slate-50">
          <span className="text-xs text-slate-400">+ อีก {remaining} งาน</span>
          <button
            onClick={() => onNavigate?.("jobs")}
            className="text-xs text-blue-500 font-medium hover:text-blue-600"
          >
            ดูงานทั้งหมด
          </button>
        </div>
      ) : null}
    </div>
  );
}

function TechCategoryModal({ categoryLabel, color, techs, repairs, onSelectJob, onClose }) {
  const isClickableCategory = categoryLabel === "กำลังเดินทาง" || categoryLabel === "กำลังปฏิบัติงาน";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-900/40" onClick={onClose} />
      <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-md max-h-[80vh] overflow-y-auto">
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100">
          <h3 className="text-base font-semibold text-slate-800 flex items-center gap-2">
            <span className={`w-2.5 h-2.5 rounded-full ${COLORS[color].dot}`} />
            {categoryLabel} ({techs.length} คน)
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">
            <X size={20} />
          </button>
        </div>
        <div className="p-4">
          {techs.length === 0 ? (
            <div className="text-sm text-slate-400 text-center py-8">ไม่มีช่างในหมวดนี้</div>
          ) : (
            <div className="space-y-1">
              {techs.map((t) => {
                const job = isClickableCategory ? findActiveJobForTech(t.username, repairs) : null;
                const canClick = Boolean(job);
                return (
                  <div
                    key={t.id || t.username}
                    onClick={() => {
                      if (canClick) {
                        onSelectJob(job);
                        onClose();
                      }
                    }}
                    className={`flex items-center justify-between gap-3 px-3 py-2.5 rounded-xl ${
                      canClick ? "cursor-pointer hover:bg-slate-50" : ""
                    }`}
                  >
                    <div className="flex items-center gap-3 min-w-0">
                      <div className={`w-9 h-9 rounded-full flex items-center justify-center flex-shrink-0 ${COLORS[color].bg}`}>
                        <UserCog size={16} className={COLORS[color].text} />
                      </div>
                      <div className="min-w-0">
                        <p className="text-sm font-medium text-slate-700 truncate">{t.tech_name || t.username}</p>
                        <p className="text-xs text-slate-400 truncate">
                          {job ? `งาน ${job.ticketNo || `#${job.id}`} · ${job.machine || "-"}` : t.phone || "-"}
                        </p>
                      </div>
                    </div>
                    {canClick ? <ChevronRight size={16} className="text-slate-300 flex-shrink-0" /> : null}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function TechOnlineCard({ technicians, repairs, onSelectJob }) {
  const [openCategory, setOpenCategory] = useState(null);

  const legend = [
    { label: "กำลังเดินทาง", key: "กำลังเดินทาง", color: "violet" },
    { label: "กำลังปฏิบัติงาน", key: "กำลังปฏิบัติงาน", color: "orange" },
    { label: "ว่าง", key: "ว่าง", color: "green" },
  ].map((item) => ({
    ...item,
    techs: technicians.filter((t) => (t.status || (t.is_busy ? "กำลังปฏิบัติงาน" : "ว่าง")) === item.key),
  }));
  const total = technicians.length;
  const openLegend = legend.find((l) => l.key === openCategory);

  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-1 min-w-[280px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">ช่างออนไลน์</h3>
        <span className="text-sm font-semibold text-slate-700">{total} คน</span>
      </div>
      <div className="space-y-3">
        {legend.map((t) => (
          <div key={t.label} className="flex items-center justify-between text-sm">
            <span className="flex items-center gap-2 text-slate-600">
              <span className={`w-2.5 h-2.5 rounded-full ${COLORS[t.color].dot}`} />
              {t.label}
            </span>
            <div className="flex items-center gap-3">
              <span className="text-slate-700 font-medium">{t.techs.length} คน</span>
              <button
                onClick={() => setOpenCategory(t.key)}
                className="text-xs text-blue-600 hover:text-blue-700 font-medium px-2 py-0.5 rounded-md hover:bg-blue-50"
              >
                ดูช่าง
              </button>
            </div>
          </div>
        ))}
      </div>

      {openLegend ? (
        <TechCategoryModal
          categoryLabel={openLegend.label}
          color={openLegend.color}
          techs={openLegend.techs}
          repairs={repairs}
          onSelectJob={onSelectJob}
          onClose={() => setOpenCategory(null)}
        />
      ) : null}
    </div>
  );
}

function WarrantyAlertCard({ machines, customers, onNavigate }) {
  const now = Date.now();

  const items = machines
    .map((m) => {
      if (!m.warranty_start_date || !m.warranty_months) return null;
      const start = new Date(m.warranty_start_date);
      if (isNaN(start.getTime())) return null;
      const end = new Date(start);
      end.setMonth(end.getMonth() + Number(m.warranty_months));
      const daysLeft = Math.ceil((end.getTime() - now) / (1000 * 60 * 60 * 24));
      if (daysLeft > 30) return null;
      const customer = customers.find((c) => c.username === m.customer_username);
      const customerName = customer
        ? [customer.name, customer.surname].filter(Boolean).join(" ") || customer.username
        : m.customer_username || "ไม่ทราบลูกค้า";
      return {
        id: m.id,
        title: m.model_name || (m.label ? `เครื่องจักร ${m.label}` : `เครื่องจักร #${m.id}`),
        customerName,
        daysLeft,
      };
    })
    .filter(Boolean)
    .sort((a, b) => {
      const aExpired = a.daysLeft < 0;
      const bExpired = b.daysLeft < 0;
      if (aExpired !== bExpired) return aExpired ? -1 : 1;
      return Math.abs(a.daysLeft) - Math.abs(b.daysLeft);
    });

  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-1 min-w-[320px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">เครื่องจักรใกล้หมดประกัน / หมดประกันแล้ว</h3>
        <button
          onClick={() => onNavigate?.("customers")}
          className="text-xs text-blue-500 font-medium hover:text-blue-600"
        >
          ดูลูกค้าทั้งหมด
        </button>
      </div>
      {items.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-6">ไม่มีเครื่องจักรที่ใกล้หมดประกันตอนนี้</p>
      ) : (
        <div className="space-y-2.5">
          {items.slice(0, 8).map((it) => {
            const expired = it.daysLeft < 0;
            return (
              <div key={it.id} className="flex items-center justify-between gap-2 text-sm">
                <div className="min-w-0">
                  <p className="font-medium text-slate-700 truncate">{it.title}</p>
                  <p className="text-xs text-slate-400 truncate">{it.customerName}</p>
                </div>
                <span
                  className={`text-[11px] font-medium px-2 py-0.5 rounded-full shrink-0 ${
                    expired ? "bg-red-50 text-red-500" : "bg-amber-50 text-amber-600"
                  }`}
                >
                  {expired ? `หมดประกันแล้ว ${Math.abs(it.daysLeft)} วัน` : `เหลือ ${it.daysLeft} วัน`}
                </span>
              </div>
            );
          })}
          {items.length > 8 ? (
            <p className="text-[11px] text-slate-400 text-center pt-1">และอีก {items.length - 8} รายการ</p>
          ) : null}
        </div>
      )}
    </div>
  );
}

const THAI_MONTHS = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
const REPORT_BRAND = "#B22121";

const SEVERITY_LEVELS = [
  { key: "ต่ำ", color: "#10B981", icon: CheckCircle2 },
  { key: "ปกติ", color: "#3B82F6", icon: Wrench },
  { key: "สูง", color: "#F97316", icon: AlertTriangle },
  { key: "เร่งด่วน", color: "#EF4444", icon: Flame },
];

function isSameMonth(date, y, m) {
  return date && date.getFullYear() === y && date.getMonth() === m;
}

const REPORT_RANGE_OPTIONS = [
  { key: "today", label: "วันนี้" },
  { key: "week", label: "สัปดาห์นี้" },
  { key: "month", label: "เดือนนี้" },
  { key: "year", label: "ปีนี้" },
  { key: "custom", label: "กำหนดเอง" },
];

// 🔴 [แก้ไข] เพิ่มโหมด "custom" (กำหนดเอง) — กรองด้วยช่วงวันที่ customStart/
// customEnd ตรงๆ แทนที่จะเทียบกับ "วันนี้" แบบ today/week/month/year เดิม
// 🔴 [แก้ไข] ตัดตัวเลือก "ทั้งหมด" ออกทั้งระบบตามที่ขอ — เหลือ 5 ตัวเลือก
// (วันนี้/สัปดาห์นี้/เดือนนี้/ปีนี้/กำหนดเอง) เท่านั้น
function filterByCreatedRange(repairs, rangeKey, customStart, customEnd) {
  const now = new Date();
  if (rangeKey === "custom") {
    const start = customStart ? new Date(`${customStart}T00:00:00`) : null;
    const end = customEnd ? new Date(`${customEnd}T23:59:59`) : null;
    return repairs.filter((r) => {
      const d = parseIsoDate(r.created_at);
      if (!d) return false;
      if (start && d < start) return false;
      if (end && d > end) return false;
      return true;
    });
  }
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

// 🆕 หาช่วงเวลา "ก่อนหน้า" ที่เทียบเท่ากันของแต่ละตัวเลือก ไว้คำนวณ % การเติบโต
// (เช่น เลือก "วันนี้" ก็เทียบกับเมื่อวาน, "สัปดาห์นี้" เทียบกับสัปดาห์ก่อน)
// "ทั้งหมด" กับ "กำหนดเอง" ไม่มีช่วงก่อนหน้าที่ชัดเจนตามธรรมชาติ คืน [] ไปเลย
// (ไม่โชว์ % การเติบโตในสองกรณีนี้)
function filterByPreviousPeriod(repairs, rangeKey) {
  const now = new Date();
  if (rangeKey === "today") {
    const y = new Date(now);
    y.setDate(y.getDate() - 1);
    return repairs.filter((r) => {
      const d = parseIsoDate(r.created_at);
      return d && d.getFullYear() === y.getFullYear() && d.getMonth() === y.getMonth() && d.getDate() === y.getDate();
    });
  }
  if (rangeKey === "week") {
    const startOfThisWeek = new Date(now);
    startOfThisWeek.setHours(0, 0, 0, 0);
    startOfThisWeek.setDate(now.getDate() - now.getDay());
    const startOfLastWeek = new Date(startOfThisWeek);
    startOfLastWeek.setDate(startOfThisWeek.getDate() - 7);
    return repairs.filter((r) => {
      const d = parseIsoDate(r.created_at);
      return d && d >= startOfLastWeek && d < startOfThisWeek;
    });
  }
  if (rangeKey === "month") {
    const lastMonthDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
    return repairs.filter((r) => isSameMonth(parseIsoDate(r.created_at), lastMonthDate.getFullYear(), lastMonthDate.getMonth()));
  }
  if (rangeKey === "year") {
    return repairs.filter((r) => {
      const d = parseIsoDate(r.created_at);
      return d && d.getFullYear() === now.getFullYear() - 1;
    });
  }
  return [];
}

// 🆕 ป้ายต่อท้าย "รายงานประจำ.../รายงานสรุปผลประจำ..." ตามตัวเลือกช่วงเวลาที่
// เลือกไว้ — "ทั้งหมด" ไม่เข้าแพทเทิร์นคำนี้ (ไม่มีใครพูดว่า "รายงานประจำ
// ทั้งหมด") คืน null ไว้ให้ผู้เรียกไปต่อคำเป็นกรณีพิเศษแทน
function reportPeriodSuffix(rangeKey) {
  switch (rangeKey) {
    case "today":
      return "วันนี้";
    case "week":
      return "สัปดาห์นี้";
    case "month":
      return "เดือนนี้";
    case "year":
      return "ปีนี้";
    case "custom":
      return "ช่วงที่กำหนด";
    default:
      return null;
  }
}

// 🆕 ป้ายชื่อ "ช่วงก่อนหน้า" ไว้ใช้กับข้อความ "การเติบโตจาก...ก่อน" — ทั้งหมด/
// กำหนดเอง ไม่มีช่วงก่อนหน้า คืน null (ผู้เรียกจะซ่อนแถวนี้ไปเลย)
function growthPeriodLabel(rangeKey) {
  switch (rangeKey) {
    case "today":
      return "เมื่อวานนี้";
    case "week":
      return "สัปดาห์ก่อน";
    case "month":
      return "เดือนก่อน";
    case "year":
      return "ปีก่อน";
    default:
      return null;
  }
}

// 🔴 [แก้ไข] เดิมเป็นตัวเลือกช่วงเวลาแยกของการ์ด "สถิติงานซ่อมตามระดับความ
// รุนแรง" ใบเดียว — ตามที่ขอ ยกระดับมาเป็นตัวเลือกกลางตัวเดียวของทั้งโซน
// "รายงานสรุป" ใช้ร่วมกันทุกการ์ด (ยกเว้น "สถิติการเงิน" ที่เป็นกราฟแนวโน้ม
// รายเดือนอยู่แล้ว มีตัวเลือกช่วงเวลาเป็นของตัวเองอยู่แล้วโดยธรรมชาติคนละแบบ
// กัน) ลดขั้นตอนที่ต้องไปกดเลือกทีละการ์ดตามที่ขอ — เพิ่มตัวเลือก "กำหนดเอง"
// พร้อมช่องเลือกวันที่เข้า-ออกด้วย
function ReportRangePicker({ range, onChange, customStart, customEnd, onCustomStartChange, onCustomEndChange }) {
  const [open, setOpen] = useState(false);
  const label = REPORT_RANGE_OPTIONS.find((r) => r.key === range)?.label;
  // 🔴 [แก้ไข] ช่องเลือกวันที่ "กำหนดเอง" ต้องเลือกล่วงหน้าไม่ได้เด็ดขาดตามที่
  // ขอ — จำกัด max ของทั้งวันเริ่มและวันจบไม่ให้เกินวันนี้ (วันเริ่มยังจำกัดไม่
  // ให้เกินวันจบที่เลือกไว้ด้วยเหมือนเดิม)
  const todayIso = toDateInputValue(new Date());
  const startMax = customEnd && customEnd < todayIso ? customEnd : todayIso;
  return (
    <div className="flex items-center gap-2 flex-wrap">
      <div className="relative">
        <button
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-1 text-xs text-slate-500 bg-slate-50 rounded-lg px-2.5 py-1.5 hover:bg-slate-100"
        >
          {label} <ChevronDown size={12} />
        </button>
        {open ? (
          <div className="absolute right-0 mt-1 bg-white border border-slate-100 rounded-xl shadow-lg py-1 z-10 w-36">
            {REPORT_RANGE_OPTIONS.map((opt) => (
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
      {/* 🔴 [แก้ไข] ใช้ DateField (ปฏิทินที่วาดเอง) แทน <input type="date">
          ของเบราว์เซอร์ เพื่อคุมหน้าตาการแสดงผลวันที่ให้เป็น พ.ศ. เสมอ ค่าที่
          เก็บ/ใช้กรองข้อมูลยังเป็น ISO string "YYYY-MM-DD" เหมือนเดิมทุกประการ
          🔴 [แก้ไข] เพิ่ม max={todayIso}/{startMax} กันไม่ให้เลือกวันในอนาคตได้
          ทั้งช่องเริ่มและช่องจบ ตามที่ขอ */}
      {range === "custom" ? (
        <div className="flex items-center gap-1.5 text-xs text-slate-500">
          <div className="w-36">
            <DateField
              value={customStart}
              max={startMax}
              onChange={onCustomStartChange}
            />
          </div>
          <span>ถึง</span>
          <div className="w-36">
            <DateField
              value={customEnd}
              min={customStart}
              max={todayIso}
              onChange={onCustomEndChange}
            />
          </div>
        </div>
      ) : null}
    </div>
  );
}

function SeverityBreakdownSection({ repairs }) {
  const counts = { ต่ำ: 0, ปกติ: 0, สูง: 0, เร่งด่วน: 0 };
  repairs.forEach((r) => {
    counts[extractSeverity(r.detail)]++;
  });
  const total = repairs.length;

  const donutData = SEVERITY_LEVELS.map((s) => ({ label: s.key, value: counts[s.key], color: s.color })).filter(
    (s) => s.value > 0
  );

  return (
    <Card className="flex-[1.8] min-w-[420px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">สถิติงานซ่อมตามระดับความรุนแรง</h3>
      </div>
      <div className="flex flex-wrap gap-6">
        <div className="flex items-center gap-4 flex-1 min-w-[220px]">
          <div className="relative w-32 h-32 shrink-0">
            {donutData.length > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie data={donutData} dataKey="value" innerRadius={40} outerRadius={56} paddingAngle={2} stroke="none">
                    {donutData.map((s, i) => <Cell key={i} fill={s.color} />)}
                  </Pie>
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="w-full h-full rounded-full border-[14px] border-slate-100" />
            )}
            <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
              <span className="text-lg font-semibold text-slate-900">{total}</span>
              <span className="text-[10px] text-slate-400 text-center leading-tight">งานทั้งหมด</span>
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

// 🔴 [แก้บั๊ก] เหตุผลเดียวกับที่แก้ใน TechniciansPage.jsx — จับกลุ่มด้วย
// rating_technician_username (ช่างที่ถูกให้คะแนนจริงตอนนั้น) ก่อนเสมอ ให้ตรง
// กับ getTechnicianRatingStats() ฝั่งมือถือ ไม่ใช้ technician_username ปัจจุบัน
// ของงานเป็นหลัก เพราะงานอาจถูกโอนให้ช่างคนอื่นทีหลังได้
function computeAvgRatingByUsername(repairs) {
  const sums = {};
  repairs.forEach((r) => {
    const ratedUsername = r.rating_technician_username || r.technician_username;
    if (!ratedUsername) return;
    const { value } = extractRating(r);
    if (value === null) return;
    if (!sums[ratedUsername]) sums[ratedUsername] = { total: 0, count: 0 };
    sums[ratedUsername].total += value;
    sums[ratedUsername].count += 1;
  });
  const avgs = {};
  Object.entries(sums).forEach(([username, { total, count }]) => {
    avgs[username] = { value: total / count, count };
  });
  return avgs;
}

function computeActiveJobCountByUsername(repairs) {
  const counts = {};
  repairs.forEach((r) => {
    if (!r.technician_username) return;
    const status = r.status || "";
    if (status.includes("ยกเลิก") || status === "เสร็จสิ้น" || status === "เสร็จแล้ว") return;
    counts[r.technician_username] = (counts[r.technician_username] || 0) + 1;
  });
  return counts;
}

function TechPerformanceModal({ technicians, ratings, jobCounts, onClose }) {
  const rows = [...technicians].sort((a, b) => {
    const ra = ratings[a.username]?.value ?? -1;
    const rb = ratings[b.username]?.value ?? -1;
    if (rb !== ra) return rb - ra;
    return (jobCounts[b.username] || 0) - (jobCounts[a.username] || 0);
  });

  return (
    <Modal title="ประเมินผลช่างซ่อม" onClose={onClose}>
      {rows.length === 0 ? (
        <p className="text-sm text-slate-400 text-center py-6">ยังไม่มีข้อมูลช่างเทคนิคในระบบ</p>
      ) : (
        <div className="space-y-1">
          {rows.map((t) => {
            const name = t.tech_name || t.name || t.username;
            const rating = ratings[t.username] || null;
            return (
              <div key={t.id || t.username} className="flex items-center justify-between gap-3 px-2 py-2.5 rounded-xl hover:bg-slate-50">
                <div className="flex items-center gap-3 min-w-0">
                  <div className="w-9 h-9 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 font-semibold shrink-0 text-sm">
                    {name?.[0] ?? "?"}
                  </div>
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-slate-800 truncate">{name}</p>
                    <p className="text-xs text-slate-400">รับผิดชอบ {jobCounts[t.username] || 0} งาน</p>
                  </div>
                </div>
                <div className="shrink-0 flex items-center gap-1.5">
                  <StarRating value={rating?.value ?? null} size={13} />
                  {rating?.count ? <span className="text-[11px] text-slate-400">({rating.count} รีวิว)</span> : null}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </Modal>
  );
}

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

function MonthlyReportCard({ data, technicians, repairs, cardTitle, periodSuffix, onNavigate }) {
  const [showTechModal, setShowTechModal] = useState(false);
  const jobsDone = data.completedThisMonth === data.jobsThisMonth && data.jobsThisMonth > 0;
  // 🆕 ชื่อ 2 แถวแรกผูกกับช่วงเวลาที่เลือกไว้ตัวเดียวกับหัวข้อการ์ด (periodSuffix
  // เป็น null เมื่อเลือก "ทั้งหมด" เพราะไม่เข้าแพทเทิร์นคำว่า "ประจำ...")
  const jobSummaryTitle = periodSuffix ? `สรุปงานซ่อมประจำ${periodSuffix}` : "สรุปงานซ่อมทั้งหมด";
  const financeSummaryTitle = periodSuffix ? `รายรับ-รายจ่ายประจำ${periodSuffix}` : "รายรับ-รายจ่ายทั้งหมด";

  const ratingsByUsername = computeAvgRatingByUsername(repairs);
  const jobCountsByUsername = computeActiveJobCountByUsername(repairs);
  const ratingEntries = Object.values(ratingsByUsername);
  const totalReviews = ratingEntries.reduce((sum, r) => sum + r.count, 0);
  const overallAvg =
    totalReviews > 0 ? ratingEntries.reduce((sum, r) => sum + r.value * r.count, 0) / totalReviews : null;
  const ratedTechCount = Object.keys(ratingsByUsername).length;

  const items = [
    {
      title: jobSummaryTitle,
      subtitle: `เสร็จแล้ว ${data.completedThisMonth}/${data.jobsThisMonth} งาน`,
      status: jobsDone ? "เสร็จสิ้น" : "กำลังซ่อม",
      color: jobsDone ? "#10B981" : "#3B82F6",
      onClick: () => onNavigate?.("jobs"),
    },
    {
      title: financeSummaryTitle,
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
      subtitle:
        overallAvg !== null
          ? `เฉลี่ย ${overallAvg.toFixed(1)} ดาว จาก ${totalReviews} รีวิว (${ratedTechCount}/${technicians.length} คน)`
          : `ยังไม่มีรีวิวจากลูกค้า (${technicians.length} คน)`,
      status: "ดูรายละเอียด",
      color: overallAvg !== null ? "#3B82F6" : "#94A3B8",
      onClick: () => setShowTechModal(true),
    },
    // 🔴 [แก้ไข] เอาแถว "รายงานความพึงพอใจลูกค้า" ออกตามที่ขอ
  ];

  return (
    <Card className="flex-[2] min-w-[320px]">
      <p className="text-sm font-semibold text-slate-800 mb-2">{cardTitle}</p>
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

      {showTechModal ? (
        <TechPerformanceModal
          technicians={technicians}
          ratings={ratingsByUsername}
          jobCounts={jobCountsByUsername}
          onClose={() => setShowTechModal(false)}
        />
      ) : null}
    </Card>
  );
}

function fmtDayLabel(d) {
  const yearBE2 = ((d.getFullYear() + 543) % 100).toString().padStart(2, "0");
  return `${d.getDate()} ${THAI_MONTHS[d.getMonth()]} ${yearBE2}`;
}

// 🆕 [ใหม่] จัดข้อความช่วงวันที่ของ "แท่งรายสัปดาห์" (เช่น "1-5 ก.ย. 69") — รับ
// วันเริ่ม (รวม) กับวันจบแบบ exclusive (ไม่รวม) แล้วคำนวณ "วันสุดท้ายจริง" (จบ
// exclusive - 1 วัน) มาทำป้ายกำกับ ถ้าอยู่เดือน/ปีเดียวกันจะย่อเหลือ
// "D1-D2 เดือนย่อ ปี" (หรือ "D เดือนย่อ ปี" เดี่ยว ๆ ถ้าเป็นวันเดียว) ถ้าคาบ
// เกี่ยวข้ามเดือน/ปี (เผื่อกรณี "กำหนดเอง" ที่ช่วงวันที่ไม่ได้เริ่ม/จบพอดีเดือน)
// จะโชว่เดือนของทั้งสองฝั่งแยกกันให้ชัดเจน
function fmtWeekRangeLabel(startDate, endExclusive) {
  const lastDay = new Date(endExclusive);
  lastDay.setDate(lastDay.getDate() - 1);
  const yearBE2 = (d) => ((d.getFullYear() + 543) % 100).toString().padStart(2, "0");
  const sameMonth = startDate.getFullYear() === lastDay.getFullYear() && startDate.getMonth() === lastDay.getMonth();
  if (sameMonth) {
    if (startDate.getDate() === lastDay.getDate()) {
      return `${startDate.getDate()} ${THAI_MONTHS[startDate.getMonth()]} ${yearBE2(startDate)}`;
    }
    return `${startDate.getDate()}-${lastDay.getDate()} ${THAI_MONTHS[startDate.getMonth()]} ${yearBE2(startDate)}`;
  }
  return `${startDate.getDate()} ${THAI_MONTHS[startDate.getMonth()]} - ${lastDay.getDate()} ${THAI_MONTHS[lastDay.getMonth()]} ${yearBE2(lastDay)}`;
}

function sumRevenueInRange(repairs, start, end) {
  let paid = 0;
  let pending = 0;
  repairs.forEach((r) => {
    const d = parseIsoDate(r.created_at);
    if (!d || d < start || d >= end) return;
    const price = Number(r.total_price) || 0;
    if (r.is_paid === 1 || r.is_paid === true) paid += price;
    else pending += price;
  });
  return { paid, pending };
}

// 🔴 [แก้ไข] เดิมใช้ระบบ key ของตัวเอง (week/month1/month3/month6/year1/
// custom) แยกจากตัวเลือกกลางของโซน "รายงานสรุป" — ตามที่ขอให้เชื่อมการ์ดนี้
// เข้ากับตัวเลือกกลางด้วย เปลี่ยนมารับ key ชุดเดียวกับ REPORT_RANGE_OPTIONS
// (today/week/month/year/all/custom) แทน แล้วเลือกความละเอียดของแท่งกราฟ
// (รายวัน/รายสัปดาห์/รายเดือน) อัตโนมัติจากความยาวของช่วงที่ได้ ไม่ผูกกับชื่อ
// key เหมือนเดิมแล้ว (ยืดหยุ่นกว่า เผื่อ "กำหนดเอง" ช่วงสั้น/ยาวไม่เท่ากัน)
function buildRevenueBuckets(repairs, rangeKey, customStart, customEnd) {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const tomorrow = new Date(today);
  tomorrow.setDate(tomorrow.getDate() + 1);

  let start;
  let end = tomorrow;
  if (rangeKey === "today") {
    start = new Date(today);
  } else if (rangeKey === "week") {
    start = new Date(today);
    start.setDate(start.getDate() - start.getDay());
  } else if (rangeKey === "month") {
    start = new Date(today.getFullYear(), today.getMonth(), 1);
  } else if (rangeKey === "year") {
    start = new Date(today.getFullYear(), 0, 1);
  } else if (rangeKey === "custom") {
    if (!customStart || !customEnd) return [];
    start = new Date(customStart);
    const endDate = new Date(customEnd);
    endDate.setDate(endDate.getDate() + 1);
    end = endDate;
  } else {
    // 🔴 [แก้ไข] เดิมมี branch "ทั้งหมด" ย้อนไปหางานซ่อมเก่าที่สุดตรงนี้ — ตัด
    // ตัวเลือก "ทั้งหมด" ออกทั้งระบบตามที่ขอแล้ว เหลือ branch นี้ไว้แค่กันเหนียว
    // เผื่อได้ key แปลกที่ไม่รู้จัก (ไม่ควรเกิดขึ้นจริง) — fallback ไปต้นเดือนนี้
    start = new Date(today.getFullYear(), today.getMonth(), 1);
  }

  const spanDays = Math.max(1, Math.round((end - start) / 86400000));
  const useMonthlyBuckets = spanDays > 62;
  const useWeeklyBuckets = !useMonthlyBuckets && spanDays > 14;

  if (useMonthlyBuckets) {
    const months = [];
    const cursor = new Date(start.getFullYear(), start.getMonth(), 1);
    const endCursor = new Date(end.getFullYear(), end.getMonth(), 1);
    while (cursor <= endCursor) {
      months.push(new Date(cursor));
      cursor.setMonth(cursor.getMonth() + 1);
    }
    return months.map((m) => {
      const monthEnd = new Date(m.getFullYear(), m.getMonth() + 1, 1);
      const { paid, pending } = sumRevenueInRange(repairs, m, monthEnd);
      const label =
        months.length > 6
          ? `${THAI_MONTHS[m.getMonth()]} ${(m.getFullYear() + 543).toString().slice(-2)}`
          : THAI_MONTHS[m.getMonth()];
      return { label, paid, pending };
    });
  }

  // 🔴 [แก้ไข] เดิมนับสัปดาห์แบบ "ทีละ 7 วันจากวันเริ่มช่วง" ตรงๆ (เช่น 1-7,
  // 8-14, 15-...) ทำให้ตัวเลขดูไม่เป็นธรรมชาติ — เปลี่ยนมาแบ่งตามสัปดาห์ปฏิทิน
  // จริง (อาทิตย์-เสาร์) แทน สัปดาห์แรกของช่วงอาจสั้นกว่า 7 วันถ้าวันเริ่มไม่ตรง
  // วันอาทิตย์พอดี (เช่น "1-5 ก.ย." ถ้า 1 ก.ย. เป็นวันอังคาร) และสัปดาห์สุดท้าย
  // จะถูกตัดไม่ให้เกิน `end` (ซึ่งไม่มีทางเกินวันนี้อยู่แล้ว — ห้ามโชว์วันในอนาคต)
  if (useWeeklyBuckets) {
    const weeks = [];
    let cursor = new Date(start);
    while (cursor < end) {
      const daysUntilSaturday = 6 - cursor.getDay();
      const calendarWeekEnd = new Date(cursor);
      calendarWeekEnd.setDate(calendarWeekEnd.getDate() + daysUntilSaturday + 1); // exclusive (วันอาทิตย์ถัดไป)
      const chunkEnd = calendarWeekEnd < end ? calendarWeekEnd : end;
      weeks.push({ start: new Date(cursor), end: chunkEnd });
      cursor = new Date(chunkEnd);
    }
    return weeks.map((w) => {
      const { paid, pending } = sumRevenueInRange(repairs, w.start, w.end);
      return { label: fmtWeekRangeLabel(w.start, w.end), paid, pending };
    });
  }

  const days = [];
  const cursor = new Date(start);
  while (cursor < end) {
    days.push(new Date(cursor));
    cursor.setDate(cursor.getDate() + 1);
  }
  return days.map((d) => {
    const dayEnd = new Date(d);
    dayEnd.setDate(dayEnd.getDate() + 1);
    const { paid, pending } = sumRevenueInRange(repairs, d, dayEnd);
    return { label: fmtDayLabel(d), paid, pending };
  });
}

function toDateInputValue(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

// 🔴 [แก้ไข] เอาตัวเลือกช่วงเวลาของตัวเองออกแล้ว ตามที่ขอให้เชื่อมกับตัวเลือก
// กลางของโซน "รายงานสรุป" ด้วย — รับ range/customStart/customEnd มาจาก
// ReportZone แทน (ตัวเดียวกับที่ "สถิติงานซ่อมตามระดับความรุนแรง" และ
// "รายงานประจำ..." ใช้อยู่แล้ว)
function FinanceHistoryCard({ repairs, range, customStart, customEnd }) {
  const buckets = buildRevenueBuckets(repairs, range, customStart, customEnd);
  const totalPaid = buckets.reduce((sum, m) => sum + m.paid, 0);
  const totalPending = buckets.reduce((sum, m) => sum + m.pending, 0);
  const maxVal = Math.max(1, ...buckets.flatMap((m) => [m.paid, m.pending]));

  return (
    <Card className="flex-1 min-w-[420px]">
      <div className="flex items-center justify-between mb-4 flex-wrap gap-2">
        <p className="text-sm font-semibold text-slate-800">สถิติการเงิน</p>
        <div className="flex items-center gap-3 text-[11px] text-slate-500">
          <span className="flex items-center gap-1">
            <span className="w-2 h-2 rounded-full" style={{ background: REPORT_BRAND }} />
            ชำระแล้ว
          </span>
          <span className="flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-amber-400" />
            รอชำระ
          </span>
        </div>
      </div>

      {buckets.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-10">ไม่มีข้อมูลในช่วงเวลานี้</p>
      ) : (
        <div className="flex items-end gap-2 h-32 overflow-x-auto">
          {buckets.map((m, i) => (
            <div key={`${m.label}-${i}`} className="flex-1 min-w-[18px] flex flex-col items-center justify-end h-full">
              <div className="flex items-end gap-1 flex-1">
                <div
                  className="w-2.5 rounded-sm"
                  style={{ height: `${Math.max(2, (m.paid / maxVal) * 100)}%`, background: REPORT_BRAND }}
                />
                <div
                  className="w-2.5 rounded-sm bg-amber-400"
                  style={{ height: `${Math.max(2, (m.pending / maxVal) * 100)}%` }}
                />
              </div>
              <span className="text-[10px] text-slate-400 mt-1.5 whitespace-nowrap">{m.label}</span>
            </div>
          ))}
        </div>
      )}

      <div className="flex gap-3 mt-4">
        <div className="flex-1 rounded-xl bg-red-50 px-3 py-2">
          <p className="text-[10px]" style={{ color: "#000000" }}>
            รายรับที่ชำระแล้ว
          </p>
          <p className="text-sm font-bold" style={{ color: REPORT_BRAND }}>
            ฿{totalPaid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
          </p>
        </div>
        <div className="flex-1 rounded-xl bg-amber-50 px-3 py-2">
          <p className="text-[10px]" style={{ color: "#000000" }}>
            รอการชำระ
          </p>
          <p className="text-sm font-bold text-amber-600">
            ฿{totalPending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
          </p>
        </div>
      </div>
    </Card>
  );
}

function computePartsUsage(partRequests, spareParts) {
  const approved = partRequests.filter((p) => p.status === "อนุมัติแล้ว");
  const rejectedCount = partRequests.filter((p) => p.status === "ปฏิเสธ").length;

  const priceOf = (partId) => Number(spareParts.find((p) => p.record_id === partId)?.price) || 0;

  const totalApprovedQty = approved.reduce((sum, p) => sum + (Number(p.quantity) || 0), 0);
  const totalApprovedValue = approved.reduce((sum, p) => sum + (Number(p.quantity) || 0) * priceOf(p.part_id), 0);

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
                <div
                  className="h-full rounded-full"
                  style={{ width: `${(p.qty / maxQty) * 100}%`, background: REPORT_BRAND }}
                />
              </div>
              <span className="text-xs font-semibold text-slate-700 w-14 text-right shrink-0">{p.qty} ชิ้น</span>
              <span className="text-xs text-slate-400 w-20 text-right shrink-0">
                ฿{p.value.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
              </span>
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
    <Card className="flex-1 min-w-[420px]">
      <h3 className="text-sm font-semibold text-slate-800 mb-4">สถิติการเบิกอะไหล่</h3>

      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-5">
        <div className="rounded-xl bg-red-50 px-3 py-3">
          <p className="text-[10px]" style={{ color: "#000000" }}>เบิกไปแล้ว (ชิ้น)</p>
          <p className="text-lg font-bold" style={{ color: REPORT_BRAND }}>
            {usage.totalApprovedQty.toLocaleString("th-TH")}
          </p>
        </div>
        <div className="rounded-xl bg-red-50 px-3 py-3">
          <p className="text-[10px]" style={{ color: "#000000" }}>มูลค่ารวม</p>
          <p className="text-lg font-bold" style={{ color: REPORT_BRAND }}>
            ฿{usage.totalApprovedValue.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
          </p>
        </div>
        <div className="rounded-xl bg-emerald-50 px-3 py-3">
          <p className="text-[10px]" style={{ color: "#000000" }}>คำขอที่ถูกอนุมัติทั้งหมด</p>
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
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-2.5">
          {[topParts.slice(0, 5), topParts.slice(5, 10)]
            .filter((column) => column.length > 0)
            .map((column, colIndex) => (
              <div key={colIndex} className="space-y-2.5">
                {column.map((p) => (
                  <div key={p.name} className="flex items-center gap-3">
                    <Package size={14} className="text-slate-400 shrink-0" />
                    <span className="text-xs text-slate-600 w-24 truncate shrink-0">{p.name}</span>
                    <div className="flex-1 h-2 rounded-full bg-slate-100 overflow-hidden">
                      <div
                        className="h-full rounded-full"
                        style={{ width: `${(p.qty / maxQty) * 100}%`, background: REPORT_BRAND }}
                      />
                    </div>
                    <span className="text-xs font-semibold text-slate-700 w-14 text-right shrink-0">{p.qty} ชิ้น</span>
                  </div>
                ))}
              </div>
            ))}
        </div>
      )}

      {showAll ? <AllPartsUsageModal allParts={usage.allParts} onClose={() => setShowAll(false)} /> : null}
    </Card>
  );
}

function ReportPreviewModal({
  companyName,
  title,
  periodSuffix,
  severityCounts,
  totalRepairs,
  mobileData,
  growthPercent,
  growthLabel,
  monthlyRevenue,
  totalPaid,
  totalPending,
  partsUsage,
  onClose,
}) {
  const now = new Date();
  const dateLabel = formatDateBySetting(now);
  const [copied, setCopied] = useState(false);
  const jobSectionLabel = periodSuffix ? `งานซ่อม${periodSuffix}` : "งานซ่อมทั้งหมด";
  const severitySectionLabel = `งานซ่อมตามระดับความรุนแรง (${periodSuffix || "ทั้งหมด"})`;

  // 🔴 [แก้ไข] ย้ายปุ่ม "คัดลอกรายงาน" มาไว้ในนี้แทน (เดิมอยู่ที่หัวโซน
  // "รายงานสรุป" นอก popup — ตามที่ขอให้เอาออกจากตรงนั้นไปไว้ตรงนี้แทน)
  function handleCopyReport() {
    const lines = [
      title,
      `ข้อมูล ณ วันที่ ${dateLabel}`,
      "----------------------------------------",
      severitySectionLabel,
      `  งานทั้งหมด : ${totalRepairs} งาน`,
      ...SEVERITY_LEVELS.map((s) => `  ระดับ${s.key}   : ${severityCounts[s.key]} งาน`),
      "----------------------------------------",
      jobSectionLabel,
      `  งานทั้งหมด    : ${mobileData.jobsThisMonth} งาน`,
      `  เสร็จสิ้นแล้ว  : ${mobileData.completedThisMonth} งาน`,
      ...(growthLabel ? [`  การเติบโตจาก${growthLabel} : ${growthPercent === null ? "-" : `${growthPercent.toFixed(1)}%`}`] : []),
      "----------------------------------------",
      "สรุปการเงิน (ย้อนหลัง 6 เดือน)",
      `  ยอดชำระแล้ว    : ${totalPaid.toFixed(2)} บาท`,
      `  ยอดค้างชำระ    : ${totalPending.toFixed(2)} บาท`,
      "----------------------------------------",
      "สถิติการเบิกอะไหล่",
      `  เบิกไปแล้ว     : ${partsUsage.totalApprovedQty} ชิ้น`,
      `  มูลค่ารวม      : ${partsUsage.totalApprovedValue.toFixed(2)} บาท`,
    ];
    navigator.clipboard
      ?.writeText(lines.join("\n"))
      .then(() => {
        setCopied(true);
        setTimeout(() => setCopied(false), 2000);
      })
      .catch((err) => console.error("[DashboardPage] copy report failed:", err));
  }

  return (
    <Modal
      title="ตัวอย่างรายงานก่อนดาวน์โหลด"
      onClose={onClose}
      maxWidth="max-w-6xl"
      footer={
        // 🔴 [แก้ไข] w-full + justify-between ทำให้ปุ่ม "คัดลอกรายงาน" อยู่ชิด
        // ซ้ายสุด ส่วน "ปิด"/"พิมพ์ฯ" ยังอยู่ชิดขวาเหมือนเดิม ตามที่ขอ (ปกติ
        // footer ของ Modal จะจัดทุกปุ่มชิดขวาหมด — ใส่ div ห่อเองแบบนี้ทับ
        // พฤติกรรมเดิมเฉพาะจุดนี้)
        <div className="flex items-center justify-between w-full">
          <button
            onClick={handleCopyReport}
            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-white border border-slate-200 text-sm font-medium text-slate-600 hover:bg-slate-50"
          >
            {copied ? <Check size={15} className="text-emerald-500" /> : <Share2 size={15} />}
            {copied ? "คัดลอกแล้ว" : "คัดลอกรายงาน"}
          </button>
          <div className="flex items-center gap-3">
            <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
              ปิด
            </button>
            <button
              onClick={() => window.print()}
              className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white"
              style={{ background: REPORT_BRAND }}
            >
              <Printer size={15} />
              พิมพ์ / บันทึกเป็น PDF
            </button>
          </div>
        </div>
      }
    >
      <style>{`
        @media print {
          body * { visibility: hidden; }
          #print-report-area, #print-report-area * { visibility: visible; }
          #print-report-area { position: absolute; left: 0; top: 0; width: 100%; padding: 24px; }
        }
      `}</style>

      <div id="print-report-area" className="text-slate-800">
        <div className="text-center mb-6 pb-4 border-b border-slate-200">
          <h1 className="text-lg font-bold" style={{ color: REPORT_BRAND }}>
            {companyName || "ระบบแจ้งซ่อม After Sales"}
          </h1>
          <p className="text-sm font-semibold text-slate-700 mt-1">{title}</p>
          <p className="text-xs text-slate-400 mt-0.5">ข้อมูล ณ วันที่ {dateLabel}</p>
        </div>

        {/* 🔴 [แก้ไข] เดิมทุก section เรียงต่อกันแนวตั้งอันเดียว ยาวมากต้องเลื่อน
            ขึ้นลงอย่างเดียว — ตามที่ขอให้ขยายออกทางซ้าย-ขวาได้ด้วย เปลี่ยนเป็น
            grid 2 คอลัมน์ (จอกว้างพอ) จับคู่ตามความสัมพันธ์ของเนื้อหา ยังเป็น
            การจัดวางแบบแรก รายละเอียดค่อยปรับกันต่อได้ */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-x-8 gap-y-5">
          <section>
            <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">
              {severitySectionLabel}
            </h3>
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

          <section>
            <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">{jobSectionLabel}</h3>
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
                {growthLabel ? (
                  <tr className="border-b border-slate-50">
                    <td className="py-1.5 text-slate-500">การเติบโตจาก{growthLabel}</td>
                    <td className="py-1.5 text-right font-semibold">
                      {growthPercent === null ? "-" : `${growthPercent.toFixed(1)}%`}
                    </td>
                  </tr>
                ) : null}
              </tbody>
            </table>
          </section>

          <section>
            <h3 className="text-sm font-bold text-slate-700 mb-2 pb-1 border-b border-slate-100">
              การเงินย้อนหลัง 6 เดือน
            </h3>
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
                    <td className="py-1.5 text-right">
                      ฿{m.paid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                    </td>
                    <td className="py-1.5 text-right">
                      ฿{m.pending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                    </td>
                  </tr>
                ))}
                <tr className="font-semibold">
                  <td className="py-1.5">รวม</td>
                  <td className="py-1.5 text-right">
                    ฿{totalPaid.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                  </td>
                  <td className="py-1.5 text-right">
                    ฿{totalPending.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                  </td>
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
                  <td className="py-1.5 text-right font-semibold">
                    {partsUsage.totalApprovedQty.toLocaleString("th-TH")}
                  </td>
                </tr>
                <tr className="border-b border-slate-50">
                  <td className="py-1.5 text-slate-500">มูลค่ารวม</td>
                  <td className="py-1.5 text-right font-semibold">
                    ฿{partsUsage.totalApprovedValue.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                  </td>
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
                        <td className="py-1.5 text-right">
                          ฿{p.value.toLocaleString("th-TH", { maximumFractionDigits: 0 })}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </>
            ) : null}
          </section>
        </div>
      </div>
    </Modal>
  );
}

function ReportZone({ repairs, partRequests, spareParts, technicians, onNavigate }) {
  const [showReportPreview, setShowReportPreview] = useState(false);
  const [companyName, setCompanyName] = useState("");
  // 🆕 ตัวเลือกช่วงเวลากลางของทั้งโซน "รายงานสรุป" ตามที่ขอ — ใช้ร่วมกันทุก
  // การ์ดในโซนนี้แล้ว (สถิติงานซ่อมตามความรุนแรง, รายงานประจำ..., สถิติการเงิน,
  // สถิติการเบิกอะไหล่) ไม่ต้องไปกดเลือกทีละการ์ดอีกต่อไป
  // 🔴 [แก้ไข] ตัดตัวเลือก "ทั้งหมด" ออกทั้งระบบตามที่ขอ — เปลี่ยนค่าเริ่มต้น
  // มาเป็น "เดือนนี้" แทน (ตัวเลือกเดิม "all" ไม่มีอยู่แล้ว)
  const [masterRange, setMasterRange] = useState("month");
  const today = new Date();
  const [customStart, setCustomStart] = useState(toDateInputValue(new Date(today.getFullYear(), today.getMonth() - 1, today.getDate())));
  const [customEnd, setCustomEnd] = useState(toDateInputValue(today));

  useEffect(() => {
    getWebSettings()
      .then((s) => setCompanyName(s?.companyName || ""))
      .catch((err) => console.error("[DashboardPage] load settings failed:", err));
  }, []);

  const periodSuffix = reportPeriodSuffix(masterRange);
  const cardTitle = periodSuffix ? `รายงานประจำ${periodSuffix}` : "รายงานทั้งหมด";
  const previewTitle = periodSuffix ? `รายงานสรุปผลประจำ${periodSuffix}` : "รายงานสรุปผลทั้งหมด";

  // งานซ่อม/คำขอเบิกอะไหล่ ที่กรองตามช่วงเวลากลางแล้ว ใช้ต่อกับทุกการ์ดในโซนนี้
  const rangedRepairs = filterByCreatedRange(repairs, masterRange, customStart, customEnd);
  const rangedPartRequests = filterByCreatedRange(partRequests, masterRange, customStart, customEnd);

  const severityCounts = { ต่ำ: 0, ปกติ: 0, สูง: 0, เร่งด่วน: 0 };
  rangedRepairs.forEach((r) => {
    severityCounts[extractSeverity(r.detail)]++;
  });

  const completedInRange = rangedRepairs.filter((r) => getEffectiveRepairStatus(r) === "เสร็จสิ้น").length;

  // 🆕 % การเติบโตเทียบกับ "ช่วงก่อนหน้า" ที่เทียบเท่ากับตัวเลือกที่เลือกไว้
  // (ทั้งหมด/กำหนดเอง ไม่มีช่วงก่อนหน้าที่ชัดเจน เลยไม่โชว์ค่านี้)
  const previousPeriodRepairs = filterByPreviousPeriod(repairs, masterRange);
  let growthPercent = null;
  if (previousPeriodRepairs.length > 0) {
    const raw = ((rangedRepairs.length - previousPeriodRepairs.length) / previousPeriodRepairs.length) * 100;
    growthPercent = Math.abs(raw) < 0.01 ? 0 : raw;
  }
  const growthLabel = growthPeriodLabel(masterRange);

  // 🔴 [แก้ไข] ยอดชำระแล้ว/รอชำระ ในการ์ด "รายงานประจำ..." ตอนนี้อิงช่วงเวลา
  // กลางที่เลือกไว้ (rangedRepairs) แทนที่จะบวกรวม 6 เดือนย้อนหลังตายตัวเหมือน
  // เดิม — ส่วนตาราง "การเงินย้อนหลัง 6 เดือน" ใน popup ตัวอย่างก่อนดาวน์โหลด
  // ยังคงใช้ monthlyRevenue/totalPaid/totalPending ชุดเดิม (6 เดือนย้อนหลัง
  // ตายตัวเสมอ ไม่ขึ้นกับตัวเลือกช่วงเวลากลาง) เพราะเป็นตารางสรุปแนวโน้มระยะยาว
  // ไว้เทียบเคียงเป็นบริบทเสริม ไม่ใช่ตัวเลขหลักของรายงานตามช่วงที่เลือก
  let rangedTotalPaid = 0;
  let rangedTotalPending = 0;
  rangedRepairs.forEach((r) => {
    const price = Number(r.total_price) || 0;
    if (r.is_paid === 1 || r.is_paid === true) rangedTotalPaid += price;
    else rangedTotalPending += price;
  });

  const monthlyRevenue = Array.from({ length: 6 }, (_, index) => {
    const target = new Date(today.getFullYear(), today.getMonth() - (5 - index), 1);
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
    jobsThisMonth: rangedRepairs.length,
    completedThisMonth: completedInRange,
    totalPaid: rangedTotalPaid,
    totalPending: rangedTotalPending,
    lowStockCount,
  };

  const partsUsage = computePartsUsage(rangedPartRequests, spareParts);

  return (
    <div className="pt-2 border-t border-slate-100">
      <div className="flex items-center justify-between gap-3 mb-4 pt-3 flex-wrap">
        <h2 className="text-base font-semibold text-slate-800">รายงานสรุป</h2>
        <div className="flex items-center gap-3 flex-wrap">
          <ReportRangePicker
            range={masterRange}
            onChange={setMasterRange}
            customStart={customStart}
            customEnd={customEnd}
            onCustomStartChange={setCustomStart}
            onCustomEndChange={setCustomEnd}
          />
          <button
            onClick={() => setShowReportPreview(true)}
            className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white"
            style={{ background: REPORT_BRAND }}
          >
            <Download size={16} />
            ดาวน์โหลดรายงาน
          </button>
        </div>
      </div>

      <div className="space-y-5">
        <div className="flex flex-wrap gap-5">
          <SeverityBreakdownSection repairs={rangedRepairs} />
          <MonthlyReportCard
            data={mobileData}
            technicians={technicians}
            repairs={rangedRepairs}
            cardTitle={cardTitle}
            periodSuffix={periodSuffix}
            onNavigate={onNavigate}
          />
        </div>
        <div className="flex flex-wrap gap-5">
          <FinanceHistoryCard repairs={repairs} range={masterRange} customStart={customStart} customEnd={customEnd} />
          <PartsUsageStatsCard partRequests={rangedPartRequests} spareParts={spareParts} />
        </div>
      </div>

      {showReportPreview ? (
        <ReportPreviewModal
          companyName={companyName}
          title={previewTitle}
          periodSuffix={periodSuffix}
          severityCounts={severityCounts}
          totalRepairs={rangedRepairs.length}
          mobileData={mobileData}
          growthPercent={growthPercent}
          growthLabel={growthLabel}
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

export default function DashboardPage({ onNavigate }) {
  const { data: repairs, loading: loadingRepairs } = useDbList("repairs");
  const { data: technicians } = useDbList("technicians");
  const { data: notifications } = useDbList("notifications");
  const { data: machines } = useDbList("machines");
  const { data: customers } = useDbList("customers");
  const { data: spareParts } = useDbList("spare_parts");
  const { data: partRequests } = useDbList("part_requests");
  const currentUsername = getSessionAdmin()?.username || "";
  const [selectedJob, setSelectedJob] = useState(null);
  const [statsRange, setStatsRange] = useState("all");
  const { settings: webSettings } = useWebSettings();
  const dashboardPageSize = Number(webSettings.itemsPerPageDashboard) || 5;

  useEffect(() => {
    if (!currentUsername || repairs.length === 0) return;
    getWebSettings().then((settings) => {
      if (settings?.notifyOverdue === false) return;
      const today = new Date();
      const todayDateOnly = new Date(today.getFullYear(), today.getMonth(), today.getDate());
      const overdueJobs = repairs.filter((r) => {
        const eff = getEffectiveRepairStatus(r);
        if (eff === "เสร็จสิ้น" || eff === "ยกเลิก") return false;
        if (r.overdue_notified) return false;
        const jobDate = parseThaiDate(r.date);
        return jobDate && jobDate < todayDateOnly;
      });
      overdueJobs.forEach((r) => {
        createNotification({
          user_username: currentUsername,
          role: "ADMIN",
          title: `งานเกินกำหนด: ${r.ticketNo || `#${r.id}`}`,
          message: `งานซ่อม ${r.machine || ""} เลยวันนัดหมายแล้ว (${r.date || "-"})`,
          type: "OVERDUE",
          target_id: r.id,
        }).catch((err) => console.error("[DashboardPage] notify overdue failed:", err));
        updateRow("repairs", r.id, { overdue_notified: 1 }).catch((err) =>
          console.error("[DashboardPage] mark overdue_notified failed:", err)
        );
      });
    });
  }, [repairs.length, currentUsername]);

  useEffect(() => {
    if (!currentUsername || spareParts.length === 0) return;
    getWebSettings().then((settings) => {
      if (settings?.notifyLowStock === false) return;
      spareParts.forEach((p) => {
        const stock = Number(p.stock) || 0;
        const isLow = stock <= 5;
        if (isLow && !p.low_stock_notified) {
          createNotification({
            user_username: currentUsername,
            role: "ADMIN",
            title: `อะไหล่ใกล้หมด: ${p.part_name || "-"}`,
            message: `เหลือในสต็อก ${stock} ชิ้น ควรสั่งเพิ่ม`,
            type: "LOW_STOCK",
            target_id: p.id,
          }).catch((err) => console.error("[DashboardPage] notify low stock failed:", err));
          updateRow("spare_parts", p.id, { low_stock_notified: 1 }).catch((err) =>
            console.error("[DashboardPage] mark low_stock_notified failed:", err)
          );
        } else if (!isLow && p.low_stock_notified) {
          updateRow("spare_parts", p.id, { low_stock_notified: 0 }).catch((err) =>
            console.error("[DashboardPage] clear low_stock_notified failed:", err)
          );
        }
      });
    });
  }, [spareParts.length, currentUsername]);

  useEffect(() => {
    if (!currentUsername || repairs.length === 0) return;
    getWebSettings().then((settings) => {
      if (settings?.notifyPaymentOverdue === false) return;
      const now = Date.now();
      const sevenDaysMs = 7 * 24 * 60 * 60 * 1000;
      const overdueInvoices = repairs.filter((r) => {
        if (!(Number(r.total_price) > 0)) return false;
        if (r.is_paid === 1 || r.is_paid === true) return false;
        if (r.payment_overdue_notified) return false;
        if (!r.invoiced_at) return false;
        const invoicedDate = new Date(r.invoiced_at);
        return !isNaN(invoicedDate.getTime()) && now - invoicedDate.getTime() > sevenDaysMs;
      });
      overdueInvoices.forEach((r) => {
        createNotification({
          user_username: currentUsername,
          role: "ADMIN",
          title: `ใบแจ้งหนี้ค้างชำระ: ${r.invoice_no || r.ticketNo || `#${r.id}`}`,
          message: `ยอด ${(Number(r.total_price) || 0).toLocaleString("th-TH")} บาท ยังไม่ได้ชำระเกิน 7 วันแล้ว`,
          type: "PAYMENT_OVERDUE",
          target_id: r.id,
        }).catch((err) => console.error("[DashboardPage] notify payment overdue failed:", err));
        updateRow("repairs", r.id, { payment_overdue_notified: 1 }).catch((err) =>
          console.error("[DashboardPage] mark payment_overdue_notified failed:", err)
        );
      });
    });
  }, [repairs.length, currentUsername]);

  // 🔔 ปรับแก้ส่วน Warranty Expiring Notification
useEffect(() => {
  if (!currentUsername || machines.length === 0) return;
  getWebSettings().then((settings) => {
    if (settings?.notifyWarranty === false) return;
    const now = Date.now();

    machines.forEach((m) => {
      if (!m.warranty_start_date || !m.warranty_months) return;
      const start = new Date(m.warranty_start_date);
      if (isNaN(start.getTime())) return;
      const end = new Date(start);
      end.setMonth(end.getMonth() + Number(m.warranty_months));
      const daysLeft = Math.ceil((end.getTime() - now) / (1000 * 60 * 60 * 24));
      const isNearExpiry = daysLeft <= 30;

      // 1. ถ้าใกล้หมดหรือหมดแล้ว และยังไม่เคยแจ้งเตือน (หรือ warranty_notified != 1)
      if (isNearExpiry && !m.warranty_notified && m.warranty_notified !== 1) {
        const customer = customers.find((c) => c.username === m.customer_username);
        const customerName = customer
          ? [customer.name, customer.surname].filter(Boolean).join(" ") || customer.username
          : m.customer_username || "ไม่ทราบลูกค้า";
        const title = m.model_name || (m.label ? `เครื่องจักร ${m.label}` : `เครื่องจักร #${m.id}`);

        // ส่งแจ้งเตือน
        createNotification({
          user_username: currentUsername,
          role: "ADMIN",
          title: `ประกันใกล้หมด: ${title}`,
          message:
            daysLeft < 0
              ? `หมดประกันแล้ว (ลูกค้า ${customerName})`
              : `เหลือประกันอีก ${daysLeft} วัน (ลูกค้า ${customerName})`,
          type: "WARRANTY_EXPIRING",
          target_id: m.id,
        }).catch((err) => console.error("[DashboardPage] notify warranty failed:", err));

        // ✅ บันทึก flag ลง Firebase ทันทีเพื่อไม่ให้วนส่งซ้ำอีกเวลารีเฟรช
        updateRow("machines", m.id, { warranty_notified: 1 }).catch((err) =>
          console.error("[DashboardPage] mark warranty_notified failed:", err)
        );
      } 
      // 2. กรณีเครื่องจักรได้รับการต่อประกันใหม่แล้ว ค่อยล้าง flag ออก
      else if (!isNearExpiry && (m.warranty_notified === 1 || m.warranty_notified === true)) {
        updateRow("machines", m.id, { warranty_notified: 0 }).catch((err) =>
          console.error("[DashboardPage] clear warranty_notified failed:", err)
        );
      }
    });
  });
}, [machines, currentUsername, customers]);

  useEffect(() => {
    if (!currentUsername || repairs.length === 0) return;
    getWebSettings().then((settings) => {
      if (settings?.notifyStaleJob === false) return;
      const now = Date.now();
      const staleDaysMs = 5 * 24 * 60 * 60 * 1000;
      const staleJobs = repairs.filter((r) => {
        if (!isInProgressStatus(r.status, r)) return false;
        if (r.stale_notified) return false;
        const approvedDate = parseIsoDate(r.approved_at);
        return approvedDate && now - approvedDate.getTime() > staleDaysMs;
      });
      staleJobs.forEach((r) => {
        createNotification({
          user_username: currentUsername,
          role: "ADMIN",
          title: `งานค้างสถานะนาน: ${r.ticketNo || `#${r.id}`}`,
          message: `งานซ่อม ${r.machine || ""} อยู่ในสถานะกำลังซ่อมมาหลายวันแล้วโดยไม่มีความเคลื่อนไหว ลองติดตามกับช่างดู`,
          type: "STALE_JOB",
          target_id: r.id,
        }).catch((err) => console.error("[DashboardPage] notify stale job failed:", err));
        updateRow("repairs", r.id, { stale_notified: 1 }).catch((err) =>
          console.error("[DashboardPage] mark stale_notified failed:", err)
        );
      });
    });
  }, [repairs.length, currentUsername]);

  useEffect(() => {
    if (!currentUsername || repairs.length === 0) return;
    // 🔴 [แก้ไข] ตัดตัวเลือกรูปแบบวันที่ (ที่เคยเป็นค่าส่วนตัวรายแอดมิน) ออก
    // ทั้งระบบตามที่ขอ — formatDateBySetting ไม่ต้องรับค่าตั้งค่าอีกต่อไป เลย
    // ไม่จำเป็นต้องดึง getPersonalSettings(currentUsername) มาแค่เพื่อเรื่องนี้
    getWebSettings().then((settings) => {
      if (settings?.notifyDailyDigest === false) return;
      const today = new Date();
      const todayStr = today.toISOString().slice(0, 10);
      if (settings?.lastDigestDate === todayStr) return;
      const isAfterDigestTime =
        today.getHours() > 17 || (today.getHours() === 17 && today.getMinutes() >= 30);
      if (!isAfterDigestTime) return;
      const todayJobs = repairs.filter((r) => {
        const d = parseIsoDate(r.created_at);
        return (
          d &&
          d.getFullYear() === today.getFullYear() &&
          d.getMonth() === today.getMonth() &&
          d.getDate() === today.getDate()
        );
      });
      //dpoint no dpoint
      const completedToday = todayJobs.filter((r) => getEffectiveRepairStatus(r) === "เสร็จสิ้น").length;
      createNotification({
        user_username: currentUsername,
        role: "ADMIN",
        title: `สรุปกิจกรรมวันนี้ (${formatDateBySetting(today)})`,
        message: `งานใหม่เข้ามา ${todayJobs.length} งาน · เสร็จสิ้นแล้ว ${completedToday} งาน`,
        type: "DAILY_DIGEST",
      }).catch((err) => console.error("[DashboardPage] notify daily digest failed:", err));
      saveWebSettings({ ...settings, lastDigestDate: todayStr }).catch((err) =>
        console.error("[DashboardPage] save lastDigestDate failed:", err)
      );
    });
  }, [repairs.length, currentUsername]);

  const statsRepairs = filterByRollingRange(repairs, statsRange);
  const summary = computeDashboardSummary(statsRepairs);
  const problemCount = statsRepairs.filter((r) => getEffectiveRepairStatus(r) === "มีปัญหา").length;

  const statCards = [
    { icon: CheckCircle2, label: "งานที่เสร็จสิ้น", value: summary.completedToday, unit: "งาน", color: "green", statusValue: "เสร็จสิ้น" },
    { icon: UserPlus, label: "รอจัดสรรช่าง", value: summary.pending, unit: "งาน", color: "yellow", statusValue: "รอจัดสรรช่าง" },
    { icon: Clock, label: "รอดำเนินการ", value: summary.scheduledPending, unit: "งาน", color: "yellow", statusValue: "รอดำเนินการ" },
    { icon: Wrench, label: "กำลังซ่อม", value: summary.inProgress, unit: "งาน", color: "yellow", statusValue: "กำลังซ่อม" },
    { icon: CalendarClock, label: "เกินกำหนดเวลา", value: summary.overdue, unit: "งาน", color: "red", statusValue: "เกินกำหนดเวลา" },
    { icon: HelpCircle, label: "มีปัญหา / ต้องตรวจสอบ", value: problemCount, unit: "งาน", color: "red", statusValue: "มีปัญหา" },
    { icon: AlertTriangle, label: "เร่งด่วน", value: summary.urgent, unit: "งาน", color: "red", statusValue: "เร่งด่วน" },
    { icon: Ban, label: "งานที่ยกเลิก", value: summary.cancelled, unit: "งาน", color: "gray", statusValue: "ยกเลิก", disableClickThrough: true },
  ];

  if (loadingRepairs) {
    return <div className="text-sm text-slate-400 py-10 text-center">กำลังโหลดข้อมูล...</div>;
  }

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <StatRangePicker range={statsRange} onChange={setStatsRange} />
        <button
          onClick={() => onNavigate?.("jobs")}
          className="text-xs text-blue-600 dark:text-white font-medium border border-slate-200 rounded-lg px-3 py-1.5 bg-white hover:bg-slate-50"
        >
          ดูงานทั้งหมด →
        </button>
      </div>

      <div className="flex flex-col sm:flex-row gap-4">
        <div className="sm:w-64 shrink-0">
          <FeaturedStatCard
            icon={ClipboardList}
            label="งานทั้งหมด"
            value={summary.total}
            unit="งาน"
            iconBg="bg-blue-50"
            iconColor="text-blue-600"
            statusValue={null}
            onNavigate={onNavigate}
          />
        </div>
        <div className="flex-1 grid grid-cols-2 sm:grid-cols-4 gap-4">
          {statCards.map((s) => (
            <StatCard key={s.label} {...s} onNavigate={onNavigate} />
          ))}
        </div>
      </div>

      <div className="flex flex-wrap gap-5">
        <RecentJobsTable repairs={repairs} onNavigate={onNavigate} onSelectJob={setSelectedJob} pageSize={dashboardPageSize} />
        <NotificationsCard notifications={notifications} currentUsername={currentUsername} onNavigate={onNavigate} />
      </div>
      <div className="flex flex-wrap gap-5">
        <WarrantyAlertCard machines={machines} customers={customers} onNavigate={onNavigate} />
        <TechOnlineCard technicians={technicians} repairs={repairs} onSelectJob={setSelectedJob} />
      </div>

      <ReportZone
        repairs={repairs}
        partRequests={partRequests}
        spareParts={spareParts}
        technicians={technicians}
        onNavigate={onNavigate}
      />

      {selectedJob ? (
        <JobDetailModal
          job={selectedJob}
          technicians={technicians}
          onClose={() => setSelectedJob(null)}
        />
      ) : null}
    </div>
  );
}