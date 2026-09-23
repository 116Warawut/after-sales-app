import React, { useState, useEffect, useRef, useMemo } from "react";
import { Wrench, Trash2, Search, UserCog, Loader2, X, UserCheck } from "lucide-react";
import { Card, EmptyState, ConfirmDialog, Pagination, DateField, TimeField } from "../components/ui";
import {
  JOB_STATUS_TABS,
  STATUS_BADGE,
  SEVERITY_BADGE,
  extractSeverity,
  displayStatus,
  getEffectiveRepairStatus,
  isDoneStatus,
  displayStoredDate,
  formatReportDateTime,
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
import JobDetailModal, { findMachineForJob } from "../components/JobDetailModal";

function isAssignable(j) {
  const effective = getEffectiveRepairStatus(j);
  const isCancelled = effective.includes("ยกเลิก");
  return !j.technician_username && !isCancelled && !isDoneStatus(effective);
}

function toDateInputValue(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isoToThaiDate(iso) {
  const parts = String(iso).split("-").map(Number);
  const [y, m, d] = parts;
  if (!y || !m || !d) return "";
  return `${d}/${m}/${y + 543}`;
}

function computeTabCounts(jobs) {
  const counts = {
    "รอจัดสรรช่าง": 0,
    "รอดำเนินการ": 0,
    "กำลังเดินทาง": 0,
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
    else if (eff === "กำลังเดินทาง") counts["กำลังเดินทาง"]++;
    else if (eff === "กำลังซ่อม") counts["กำลังซ่อม"]++;
  });
  counts["ทั้งหมด"] = jobs.length;
  return counts;
}

function BulkAssignModal({ count, technicians, onAssign, onClose }) {
  const [selectedTech, setSelectedTech] = useState("");
  const [dateIso, setDateIso] = useState("");
  const [time, setTime] = useState("");
  const [assigning, setAssigning] = useState(false);
  const [error, setError] = useState("");

  const todayIso = toDateInputValue(new Date());

  async function handleConfirm() {
    if (!selectedTech || !dateIso || !time) {
      setError("กรุณาเลือกช่าง วันนัด และเวลานัดให้ครบ");
      return;
    }
    setError("");
    setAssigning(true);
    try {
      await onAssign(selectedTech, isoToThaiDate(dateIso), time);
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

        {selectedTech ? (
          <div className="mb-3">
            <p className="text-xs font-medium text-slate-500 mb-1.5">วันนัดหมาย</p>
            <DateField value={dateIso} min={todayIso} onChange={setDateIso} disabled={assigning} />
          </div>
        ) : null}

        {selectedTech && dateIso ? (
          <div className="mb-3">
            <p className="text-xs font-medium text-slate-500 mb-1.5">เวลานัดหมาย</p>
            <TimeField value={time} onChange={setTime} disabled={assigning} />
          </div>
        ) : null}

        {error ? <p className="text-xs text-red-500 mb-3">{error}</p> : null}
        <div className="flex items-center justify-end gap-2">
          <button onClick={onClose} disabled={assigning} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ยกเลิก
          </button>
          {selectedTech && dateIso && time ? (
            <button
              onClick={handleConfirm}
              disabled={assigning}
              className="flex items-center gap-2 px-4 py-2 rounded-xl bg-blue-500 text-white text-sm font-medium hover:bg-blue-600 disabled:opacity-50"
            >
              {assigning ? <Loader2 size={16} className="animate-spin" /> : null}
              บันทึก
            </button>
          ) : null}
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

export default function RepairJobsPage({ initialTab, initialQuery, onNavigate }) {
  const [tab, setTab] = useState(initialTab || "ทั้งหมด");
  const [query, setQuery] = useState(initialQuery || "");
  const { data: jobs = [], loading } = useDbList("repairs");
  const { data: technicians = [] } = useDbList("technicians");
  const { data: admins = [] } = useDbList("admins");
  const { data: machines = [] } = useDbList("machines");

  const [selectedJob, setSelectedJob] = useState(null);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [selectedIds, setSelectedIds] = useState(new Set());
  const [showBulkAssign, setShowBulkAssign] = useState(false);
  const [reassignTarget, setReassignTarget] = useState(null);

  const { settings: webSettings } = useWebSettings();
  const pageSize = Number(webSettings.itemsPerPageJobs) || 20;
  const [page, setPage] = useState(1);

  const currentAdmin = getSessionAdmin();
  const isSuperAdmin = isMainAdmin(currentAdmin);
  const autoOpenedRef = useRef(null);

  const visibleJobs = useMemo(() => {
    if (!jobs || !Array.isArray(jobs)) return [];
    const scoped = isSuperAdmin
      ? jobs
      : jobs.filter(
          (j) =>
            j.admin_username === currentAdmin?.username ||
            !j.admin_username ||
            j.admin_username === ""
        );

    return scoped.map((j) => {
      if (j.serial_number) return j;
      const m = findMachineForJob(j, machines);
      return m?.serial_number ? { ...j, serial_number: m.serial_number } : j;
    });
  }, [jobs, isSuperAdmin, currentAdmin?.username, machines]);

  useEffect(() => {
    if (!initialQuery || autoOpenedRef.current === initialQuery) return;
    if (visibleJobs.length === 0) return;
    const match = visibleJobs.find(
      (j) => String(j.id) === String(initialQuery) || String(j.record_id) === String(initialQuery)
    );
    autoOpenedRef.current = initialQuery;
    if (match) {
      setSelectedJob(match);
    } else {
      setQuery(initialQuery);
    }
  }, [initialQuery, visibleJobs]);

  const sorted = useMemo(() => {
    return [...visibleJobs].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));
  }, [visibleJobs]);

  const tabCounts = useMemo(() => computeTabCounts(visibleJobs), [visibleJobs]);

  const byTab = useMemo(() => {
    if (tab === "ทั้งหมด") return sorted;
    if (tab === "เร่งด่วน") return sorted.filter((j) => extractSeverity(j.detail) === "เร่งด่วน");
    if (tab === "เสร็จสิ้น") return sorted.filter((j) => isDoneStatus(getEffectiveRepairStatus(j)));
    return sorted.filter((j) => getEffectiveRepairStatus(j) === tab);
  }, [sorted, tab]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return byTab;
    return byTab.filter((j) => {
      return (
        String(j.ticketNo || "").toLowerCase().includes(q) ||
        String(j.id ?? "").toLowerCase().includes(q) ||
        (j.customer_username || "").toLowerCase().includes(q) ||
        (j.machine || "").toLowerCase().includes(q) ||
        (j.serial_number || "").toLowerCase().includes(q)
      );
    });
  }, [byTab, query]);

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
    setSelectedIds(() => {
      if (allAssignableSelected) return new Set();
      return new Set(assignableFiltered.map((j) => j.id));
    });
  }

  async function handleBulkAssign(techUsername, thaiDate, time) {
    const admin = getSessionAdmin();
    const adminUsername = admin?.username || "";
    const adminName = admin?.admin_name || adminUsername;
    const jobsToAssign = visibleJobs.filter((j) => selectedIds.has(j.id));

    try {
      await Promise.all(
        jobsToAssign.map((j) =>
          assignTechnicianToRepair(j.id, techUsername, adminUsername, thaiDate, {
            time,
            appointment_time: time,
            admin_name: adminName,
          })
        )
      );
      logActivity({
        adminUsername,
        adminName,
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
              message: `เครื่อง ${j.machine || ""} (${thaiDate || "ไม่ระบุวัน"}) เวลา ${time} น.`,
              type: "JOB",
              target_id: j.id,
            }).catch((err) => console.error("[RepairJobsPage] notify technician failed:", err));

            if (j.customer_username) {
              createNotification({
                user_username: j.customer_username,
                role: "CUSTOMER",
                title: `จัดสรรช่างแล้ว: ${ticketLabel}`,
                message: `ช่าง ${techUsername} ได้รับมอบหมายงานซ่อมของคุณแล้ว วันที่ ${thaiDate} เวลา ${time} น.`,
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
              placeholder="ค้นหา Job ID / ลูกค้า / เครื่อง / S/N..."
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

        <div className="px-5 pt-4">
          <div className="flex gap-2 overflow-x-auto pb-1">
            {JOB_STATUS_TABS.map((t) => {
              const active = tab === t;
              return (
                <button
                  key={t}
                  onClick={() => setTab(t)}
                  className={
                    "flex-1 min-w-0 flex items-center justify-between gap-1.5 px-2.5 py-2 rounded-xl text-xs sm:text-sm font-medium whitespace-nowrap border transition-colors " +
                    (active
                      ? "border-blue-200 bg-blue-50 text-blue-900"
                      : "border-slate-200 bg-white text-slate-800 hover:bg-slate-50")
                  }
                >
                  <span className="truncate">{t}</span>
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
                    const rawTime = (j.appointment_time || j.time || "").toString().trim();
                    const cleanTime = rawTime.replace(/\s*น\.?$/, "");

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
                        <td className="py-2.5 text-slate-700">
                          <div>{j.machine || "-"}</div>
                          {j.serial_number ? (
                            <div className="text-[11px] text-blue-600 font-mono">S/N: {j.serial_number}</div>
                          ) : null}
                        </td>
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
                        <td className="py-2.5 text-slate-500">
                          <div>{displayStoredDate(j.date)}</div>
                          {/* 🆕 [ใหม่] โชว์วันที่เสร็จสิ้นจริงต่อท้ายวันนัด
                              เฉพาะงานที่ปิดแล้ว — แพทเทิร์นเดียวกับที่ column
                              "เครื่องจักร" โชว์ S/N ต่อท้ายชื่อเครื่องด้านบน */}
                          {isDoneStatus(effStatus) && j.report_submitted_at ? (
                            <div className="text-[11px] text-emerald-600">
                              เสร็จ {formatReportDateTime(j.report_submitted_at)}
                            </div>
                          ) : null}
                        </td>
                        <td className="py-2.5 text-slate-500">{cleanTime ? `${cleanTime} น.` : "-"}</td>
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
        <JobDetailModal
          job={selectedJob}
          technicians={technicians}
          machines={machines}
          onClose={() => setSelectedJob(null)}
          onNavigate={onNavigate}
        />
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