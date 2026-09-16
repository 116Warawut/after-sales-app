import React, { useState, useEffect, useRef } from "react";
import { Wrench, Trash2, Search, UserCog, Loader2, X, UserCheck } from "lucide-react";
import { Card, EmptyState, ConfirmDialog, Pagination } from "../components/ui";
import {
  JOB_STATUS_TABS,
  STATUS_BADGE,
  SEVERITY_BADGE,
  extractSeverity,
  displayStatus,
  getEffectiveRepairStatus,
  isDoneStatus,
  displayStoredDate,
} from "../shared/constants";
import useDbList from "../hooks/useDbList";
import useWebSettings from "../hooks/useWebSettings";
import {
  deleteRepair,
  logActivity,
  assignTechnicianToRepair,
  createNotification,
  getWebSettings,
  reassignRepairAdmin,
} from "../services/firebaseDb";
import { getSessionAdmin, isMainAdmin } from "../services/session";
import JobDetailModal from "../components/JobDetailModal";

function isAssignable(j) {
  const effective = getEffectiveRepairStatus(j);
  const isCancelled = effective.includes("ยกเลิก");
  return !j.technician_username && !isCancelled && !isDoneStatus(effective);
}

// นับจำนวนงานของแต่ละแท็บสถานะ ไว้โชว์ตัวเลขชิดขวาบนปุ่มแท็บ — ถ้างานหนึ่ง
// เข้าเงื่อนไขได้หลายหัวข้อพร้อมกัน (เช่น เร่งด่วนแต่ก็เสร็จสิ้นไปแล้วด้วย) ให้
// นับที่หัวข้อสำคัญที่สุดหัวข้อเดียวตามลำดับนี้ (สูง→ต่ำ): เสร็จสิ้น > มีปัญหา >
// เกินกำหนดเวลา > เร่งด่วน > รอจัดสรรช่าง > รอดำเนินการ > กำลังซ่อม (แนวทาง
// เดียวกับที่การ์ดสถิติในหน้า Dashboard ใช้ กันไม่ให้งานเดียวโผล่นับซ้ำ 2 ที่)
// หมายเหตุ: ตัวเลขนี้มีไว้ "โชว์" เท่านั้น ไม่ได้เปลี่ยนพฤติกรรมการกรอง byTab
// เวลากดแท็บจริง (ของเดิมยังทำงานเหมือนเดิมทุกอย่าง)
function computeTabCounts(jobs) {
  const counts = {
    "รอจัดสรรช่าง": 0,
    "รอดำเนินการ": 0,
    "กำลังซ่อม": 0,
    "เร่งด่วน": 0,
    "มีปัญหา": 0,
    "เกินกำหนดเวลา": 0,
    "เสร็จสิ้น": 0,
  };
  jobs.forEach((j) => {
    const eff = getEffectiveRepairStatus(j);
    const isUrgent = extractSeverity(j.detail) === "เร่งด่วน";
    if (isDoneStatus(eff)) counts["เสร็จสิ้น"]++;
    else if (eff === "มีปัญหา") counts["มีปัญหา"]++;
    else if (eff === "เกินกำหนดเวลา") counts["เกินกำหนดเวลา"]++;
    else if (isUrgent) counts["เร่งด่วน"]++;
    else if (eff === "รอจัดสรรช่าง") counts["รอจัดสรรช่าง"]++;
    else if (eff === "รอดำเนินการ") counts["รอดำเนินการ"]++;
    else if (eff === "กำลังซ่อม") counts["กำลังซ่อม"]++;
  });
  counts["ทั้งหมด"] = jobs.length;
  return counts;
}

function BulkAssignModal({ count, technicians, onAssign, onClose }) {
  const [selectedTech, setSelectedTech] = useState("");
  const [assigning, setAssigning] = useState(false);
  const [error, setError] = useState("");

  async function handleConfirm() {
    if (!selectedTech) {
      setError("กรุณาเลือกช่างเทคนิค");
      return;
    }
    setError("");
    setAssigning(true);
    try {
      await onAssign(selectedTech);
    } finally {
      setAssigning(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-900/40" onClick={onClose} />
      <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-sm p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-base font-semibold text-slate-800">มอบหมายงาน {count} รายการ</h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">
            <X size={18} />
          </button>
        </div>
        <select
          value={selectedTech}
          onChange={(e) => setSelectedTech(e.target.value)}
          disabled={assigning}
          className="w-full px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100 mb-3"
        >
          <option value="">เลือกช่างเทคนิค...</option>
          {technicians.map((t) => (
            <option key={t.id || t.username} value={t.username}>
              {t.tech_name || t.name || t.username}
            </option>
          ))}
        </select>
        {error ? <p className="text-xs text-red-500 mb-3">{error}</p> : null}
        <div className="flex items-center justify-end gap-2">
          <button onClick={onClose} disabled={assigning} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ยกเลิก
          </button>
          <button
            onClick={handleConfirm}
            disabled={assigning}
            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50"
          >
            {assigning ? <Loader2 size={16} className="animate-spin" /> : null}
            บันทึก
          </button>
        </div>
      </div>
    </div>
  );
}

function ReassignAdminModal({ job, admins, onClose }) {
  const [selectedAdmin, setSelectedAdmin] = useState(job.admin_username || "");
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState("");

  async function handleReassign() {
    if (!selectedAdmin) {
      setError("กรุณาเลือกแอดมิน");
      return;
    }
    setSubmitting(true);
    setError("");
    try {
      await reassignRepairAdmin(job.id, selectedAdmin);
      onClose();
    } catch (err) {
      setError(err.message || "เกิดข้อผิดพลาด");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-slate-900/40" onClick={onClose} />
      <div className="relative bg-white rounded-2xl shadow-xl w-full max-w-sm p-6">
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-base font-semibold text-slate-800">
            เปลี่ยนแอดมินผู้ดูแล #{job.ticketNo || job.id}
          </h3>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">
            <X size={18} />
          </button>
        </div>
        <p className="text-xs text-slate-500 mb-3">
          เลือกแอดมินคนใหม่ที่จะรับผิดชอบงานแจ้งซ่อมนี้
        </p>
        <select
          value={selectedAdmin}
          onChange={(e) => setSelectedAdmin(e.target.value)}
          disabled={submitting}
          className="w-full px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100 mb-3"
        >
          <option value="">เลือกแอดมิน...</option>
          {admins.map((a) => (
            <option key={a.id || a.username} value={a.username}>
              {a.admin_name || a.username} ({a.admin_type === "general" ? "แอดมินทั่วไป" : "แอดมินหลัก"})
            </option>
          ))}
        </select>
        {error ? <p className="text-xs text-red-500 mb-3">{error}</p> : null}
        <div className="flex items-center justify-end gap-2">
          <button
            onClick={onClose}
            disabled={submitting}
            className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50"
          >
            ยกเลิก
          </button>
          <button
            onClick={handleReassign}
            disabled={submitting}
            className="flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50"
          >
            {submitting ? <Loader2 size={16} className="animate-spin" /> : null}
            ยืนยัน
          </button>
        </div>
      </div>
    </div>
  );
}

export default function RepairJobsPage({ initialTab, initialQuery }) {
  const [tab, setTab] = useState(initialTab || "ทั้งหมด");
  const [query, setQuery] = useState(initialQuery || "");
  const { data: jobs, loading } = useDbList("repairs");
  const { data: technicians } = useDbList("technicians");
  const { data: admins } = useDbList("admins");
  const [selectedJob, setSelectedJob] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [showBulkAssign, setShowBulkAssign] = useState(false);
  const [reassignTarget, setReassignTarget] = useState(null);
  // 🆕 จำนวนรายการต่อหน้า อ่านมาจากหน้าตั้งค่า > ระบบทั่วไป (เฉพาะของหน้า
  // "งานซ่อม" — แยกจากจำนวนรายการของหน้า Dashboard/อะไหล่/การเงิน/แจ้งเตือน)
  const { settings: webSettings } = useWebSettings();
  const pageSize = Number(webSettings.itemsPerPageJobs) || 20;
  const [page, setPage] = useState(1);

  const currentAdmin = getSessionAdmin();
  const isSuperAdmin = isMainAdmin(currentAdmin);
  const autoOpenedRef = useRef(null);

  useEffect(() => {
    if (!initialQuery || autoOpenedRef.current === initialQuery) return;
    if (jobs.length === 0) return;
    const match = jobs.find(
      (j) => String(j.id) === String(initialQuery) || String(j.record_id) === String(initialQuery)
    );
    autoOpenedRef.current = initialQuery;
    if (match) {
      setSelectedJob(match);
    } else {
      setQuery(initialQuery);
    }
  }, [initialQuery, jobs]);

  const sorted = [...jobs].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));
  const tabCounts = computeTabCounts(jobs);

  const byTab =
    tab === "ทั้งหมด"
      ? sorted
      : tab === "เร่งด่วน"
      ? sorted.filter((j) => extractSeverity(j.detail) === "เร่งด่วน")
      : tab === "เสร็จสิ้น"
      ? sorted.filter((j) => isDoneStatus(getEffectiveRepairStatus(j)))
      : sorted.filter((j) => getEffectiveRepairStatus(j) === tab);

  const filtered = byTab.filter((j) => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    return (
      String(j.ticketNo || "").toLowerCase().includes(q) ||
      String(j.id ?? "").toLowerCase().includes(q) ||
      (j.customer_username || "").toLowerCase().includes(q) ||
      (j.machine || "").toLowerCase().includes(q)
    );
  });

  // 🆕 แบ่งหน้ารายการงานซ่อมตามจำนวนรายการต่อหน้าที่ตั้งไว้ — สลับแท็บหรือ
  // ค้นหาใหม่ต้องกลับไปหน้า 1 เสมอ กันเผลอค้างอยู่หน้าท้ายๆ ที่ไม่มีข้อมูลแล้ว
  useEffect(() => {
    setPage(1);
  }, [tab, query]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const paged = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRepair(deleteTarget.id);
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ลบใบแจ้งซ่อม",
        target: deleteTarget.ticketNo || `#${deleteTarget.id}`,
      }).catch((err) => console.error("[RepairJobsPage] log activity failed:", err));
      setDeleteTarget(null);
    } catch (err) {
      console.error("[RepairJobsPage] delete failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  // 🆕 "เลือกทั้งหมด" ตอนนี้อิงจากรายการที่เห็นอยู่ในหน้าปัจจุบันเท่านั้น
  // (หลังจากมีการแบ่งหน้าแล้ว เลือกข้ามหน้าจะงงว่าเลือกอะไรไปบ้าง)
  const assignableFiltered = paged.filter(isAssignable);
  const allAssignableSelected =
    assignableFiltered.length > 0 && assignableFiltered.every((j) => selectedIds.has(j.id));

  function toggleSelect(id) {
    setSelectedIds((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleSelectAll() {
    setSelectedIds((prev) => {
      if (allAssignableSelected) return new Set();
      return new Set(assignableFiltered.map((j) => j.id));
    });
  }

  async function handleBulkAssign(techUsername) {
    const admin = getSessionAdmin();
    const adminUsername = admin?.username || "";
    const jobsToAssign = jobs.filter((j) => selectedIds.has(j.id));

    try {
      await Promise.all(jobsToAssign.map((j) => assignTechnicianToRepair(j.id, techUsername, adminUsername, j.date)));
      logActivity({
        adminUsername,
        adminName: admin?.admin_name,
        action: "มอบหมายงานหลายรายการ",
        target: `${jobsToAssign.length} รายการให้ช่าง ${techUsername}`,
      }).catch((err) => console.error("[RepairJobsPage] log activity failed:", err));

      getWebSettings()
        .then((settings) => {
          if (settings?.notifyJob === false) return;
          jobsToAssign.forEach((j) => {
            const ticketLabel = j.ticketNo || `#${j.id}`;
            createNotification({
              user_username: techUsername,
              role: "TECHNICIAN",
              title: `งานซ่อมใหม่: ${ticketLabel}`,
              message: `เครื่อง ${j.machine || ""} (${j.date || "ไม่ระบุวัน"})`,
              type: "JOB",
              target_id: j.id,
            }).catch((err) => console.error("[RepairJobsPage] notify technician failed:", err));

            if (j.customer_username) {
              createNotification({
                user_username: j.customer_username,
                role: "CUSTOMER",
                title: `จัดสรรช่างแล้ว: ${ticketLabel}`,
                message: `ช่าง ${techUsername} ได้รับมอบหมายงานซ่อมของคุณแล้ว`,
                type: "JOB",
                target_id: j.id,
              }).catch((err) => console.error("[RepairJobsPage] notify customer failed:", err));
            }
          });
        })
        .catch((err) => console.error("[RepairJobsPage] load settings failed:", err));

      setSelectedIds(new Set());
      setShowBulkAssign(false);
    } catch (err) {
      console.error("[RepairJobsPage] bulk assign failed:", err);
    }
  }

  return (
    <div>
      <Card className="p-0 overflow-hidden">
        <div className="px-5 pt-5">
          <div className="relative max-w-sm">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="ค้นหา Job ID / ลูกค้า / เครื่อง..."
              className="w-full pl-9 pr-8 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
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

        <div className="px-5 pt-4 overflow-x-auto">
          {/* ตัดสีต่างๆ ของแต่ละแท็บออกทั้งหมดตามที่ขอ (ดูตาลาย) เหลือแค่
              ตัวอักษรสีดำเสมอ ทุกปุ่มมีกรอบและขนาดเท่ากันหมด (grid-cols-8
              เพราะ JOB_STATUS_TABS มีคงที่ 8 รายการพอดี) ปุ่มที่กำลังเลือกอยู่
              จะเปลี่ยนกรอบเป็นสีน้ำเงินจางๆ (border-blue-200 + bg-blue-50)
              แบบเดียวกับโทนสีของการ์ด "งานทั้งหมด" ในหน้า Dashboard — ชื่อแท็บ
              ชิดซ้าย ตัวเลขจำนวนงาน (จาก computeTabCounts) ชิดขวา */}
          <div className="grid grid-cols-8 gap-2 min-w-[720px]">
            {JOB_STATUS_TABS.map((t) => {
              const active = tab === t;
              return (
                <button
                  key={t}
                  onClick={() => setTab(t)}
                  className={
                    "flex items-center justify-between gap-2 px-3 py-2 rounded-xl text-sm font-medium whitespace-nowrap border transition-colors " +
                    (active
                      ? "border-blue-200 bg-blue-50 text-blue-900"
                      : "border-slate-200 bg-white text-slate-800 hover:bg-slate-50")
                  }
                >
                  <span className="truncate">{t}</span>
                  {/* 🔴 [แก้ไข] แท็บที่กำลังเลือกอยู่ใช้พื้นฟ้าอ่อน (bg-blue-50)
                      ที่ตั้งใจให้อยู่เฉยๆ ไม่เปลี่ยนตามธีมมืด เหมือน badge สถานะ
                      ทั่วไป (ผู้ใช้แจ้งว่าอยากให้กลุ่มนี้ชัดเจนเหมือนเดิม
                      ไม่ต้องเปลี่ยนสี) เลยใช้ text-blue-900 แทน text-slate-800/
                      text-slate-400 เฉพาะตอน active เพราะสี text-slate-* โดน
                      กฎโหมดมืดด้านบนแปลงเป็นสีอ่อนเสมอ ซึ่งจะกลายเป็นอ่านไม่ออก
                      บนพื้นฟ้าอ่อนที่ไม่ได้เปลี่ยนสีตาม (ตอนไม่ active พื้นเป็น
                      bg-white ซึ่งกฎโหมดมืดแปลงให้เข้มขึ้นอยู่แล้ว เลยยังใช้
                      text-slate-* แบบเดิมได้ปกติ) */}
                  <span className={"text-xs shrink-0 " + (active ? "text-blue-900/70" : "text-slate-400")}>
                    {tabCounts[t] ?? 0}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="p-5">
          {selectedIds.size > 0 ? (
            <div className="flex items-center justify-between mb-4 px-4 py-2.5 rounded-xl bg-blue-50">
              <p className="text-sm text-blue-700 font-medium">เลือกอยู่ {selectedIds.size} รายการ</p>
              <div className="flex items-center gap-2">
                <button
                  onClick={() => setSelectedIds(new Set())}
                  className="text-xs text-blue-600 hover:text-blue-700 px-2"
                >
                  ยกเลิกการเลือก
                </button>
                <button
                  onClick={() => setShowBulkAssign(true)}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-500 text-white text-xs font-medium hover:bg-blue-600"
                >
                  <UserCog size={14} />
                  มอบหมายช่าง
                </button>
              </div>
            </div>
          ) : null}

          {loading ? (
            <p className="text-xs text-slate-400 text-center py-8">กำลังโหลด...</p>
          ) : filtered.length === 0 ? (
            <EmptyState icon={Wrench} message={query ? "ไม่พบงานซ่อมที่ค้นหา" : "ไม่มีรายการงานซ่อม"} />
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead>
                  <tr className="text-xs text-slate-400 border-b border-slate-100">
                    <th className="py-2 font-medium w-8">
                      {assignableFiltered.length > 0 ? (
                        <input
                          type="checkbox"
                          checked={allAssignableSelected}
                          onChange={toggleSelectAll}
                          onClick={(e) => e.stopPropagation()}
                          className="rounded border-slate-300"
                        />
                      ) : null}
                    </th>
                    <th className="py-2 font-medium">Job ID</th>
                    <th className="py-2 font-medium">ลูกค้า</th>
                    <th className="py-2 font-medium">เครื่องจักร</th>
                    <th className="py-2 font-medium">ช่างผู้ดูแล</th>
                    <th className="py-2 font-medium">แอดมินผู้ดูแล</th>
                    <th className="py-2 font-medium">วันนัดซ่อม</th>
                    <th className="py-2 font-medium">เวลานัด</th>
                    <th className="py-2 font-medium">สถานะ</th>
                    <th className="py-2 font-medium">ระดับความรุนแรง</th>
                    <th className="py-2 font-medium w-16"></th>
                  </tr>
                </thead>
                <tbody>
                  {paged.map((j) => {
                    const effStatus = getEffectiveRepairStatus(j);
                    return (
                      <tr
                        key={j.id}
                        onClick={() => setSelectedJob(j)}
                        className="border-b border-slate-50 last:border-0 cursor-pointer hover:bg-slate-50"
                      >
                        <td className="py-2.5" onClick={(e) => e.stopPropagation()}>
                          {isAssignable(j) ? (
                            <input
                              type="checkbox"
                              checked={selectedIds.has(j.id)}
                              onChange={() => toggleSelect(j.id)}
                              className="rounded border-slate-300"
                            />
                          ) : null}
                        </td>
                        <td className="py-2.5 text-slate-700">{j.ticketNo || j.id}</td>
                        <td className="py-2.5 text-slate-700">{j.customer_username || "-"}</td>
                        <td className="py-2.5 text-slate-700">{j.machine || "-"}</td>
                        <td className="py-2.5">
                          {j.technician_username ? (
                            <span className="text-slate-700">{j.technician_username}</span>
                          ) : (
                            <span className="text-amber-500 font-medium">รอจัดสรร</span>
                          )}
                        </td>
                        <td className="py-2.5 text-slate-600">
                          {j.admin_username ? (
                            <span className="text-xs bg-slate-100 text-slate-700 px-2 py-0.5 rounded-md">
                              @{j.admin_username}
                            </span>
                          ) : (
                            <span className="text-xs text-slate-400">-</span>
                          )}
                        </td>
                        <td className="py-2.5 text-slate-500">{displayStoredDate(j.date)}</td>
                        <td className="py-2.5 text-slate-500">{j.appointment_time ? `${j.appointment_time} น.` : "-"}</td>
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
                              SEVERITY_BADGE[extractSeverity(j.detail)] ?? "bg-gray-100 text-gray-500"
                            }`}
                          >
                            {extractSeverity(j.detail)}
                          </span>
                        </td>
                        <td className="py-2.5" onClick={(e) => e.stopPropagation()}>
                          <div className="flex items-center justify-end gap-1">
                            {isSuperAdmin && !isDoneStatus(effStatus) && (
                              <button
                                onClick={() => setReassignTarget(j)}
                                title="เปลี่ยนแอดมินผู้ดูแล"
                                className="w-7 h-7 rounded-lg flex items-center justify-center text-blue-500 hover:bg-blue-50"
                              >
                                <UserCheck size={14} />
                              </button>
                            )}
                            <button
                              onClick={() => setDeleteTarget(j)}
                              title="ลบงานซ่อม"
                              className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 hover:bg-red-50 hover:text-red-500"
                            >
                              <Trash2 size={14} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <Pagination
            page={currentPage}
            totalPages={totalPages}
            onChange={setPage}
            totalItems={filtered.length}
            pageSize={pageSize}
          />
        </div>
      </Card>

      {selectedJob ? (
        <JobDetailModal job={selectedJob} technicians={technicians} onClose={() => setSelectedJob(null)} />
      ) : null}
      {showBulkAssign ? (
        <BulkAssignModal
          count={selectedIds.size}
          technicians={technicians}
          onAssign={handleBulkAssign}
          onClose={() => setShowBulkAssign(false)}
        />
      ) : null}
      {reassignTarget ? (
        <ReassignAdminModal
          job={reassignTarget}
          admins={admins}
          onClose={() => setReassignTarget(null)}
        />
      ) : null}
      {deleteTarget ? (
        <ConfirmDialog
          title="ยืนยันการลบใบแจ้งซ่อม"
          message={`ต้องการลบใบแจ้งซ่อม "${deleteTarget.ticketNo || `#${deleteTarget.id}`}" ใช่หรือไม่?`}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          busy={deleting}
        />
      ) : null}
    </div>
  );
}