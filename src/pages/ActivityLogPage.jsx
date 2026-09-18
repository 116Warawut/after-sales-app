import React, { useState } from "react";
import { History, UserPlus, Trash2, Check, X, FileText, Wallet, HelpCircle } from "lucide-react";
import { Card, EmptyState, ConfirmDialog } from "../components/ui";
import useDbList from "../hooks/useDbList";
import { clearActivityLog } from "../services/firebaseDb";

// ---------------------------------------------------------------------------
// 📝 [ใหม่] หน้า "ประวัติการใช้งาน" (Activity Log) — เพิ่งเพิ่มระบบบันทึกนี้เข้า
// ไปในหลายจุดของเว็บ (มอบหมายช่าง, ลบงาน, อนุมัติ/ปฏิเสธอะไหล่, ลบลูกค้า/ช่าง,
// ออกใบแจ้งหนี้, มาร์กว่าชำระแล้ว) หน้านี้เอาไว้ดูภาพรวมว่าใครทำอะไรไปบ้างเมื่อไหร่
// ตั้งใจให้เป็น "read-only" ไม่มีปุ่มลบประวัติ เพราะเป็นหลักฐานตรวจสอบย้อนหลัง
// ลบทิ้งได้จะขัดกับจุดประสงค์ของมันเอง — บันทึกเฉพาะ action สำคัญที่กระทบข้อมูล
// จริง ไม่ได้ log ทุกคลิกเล็กน้อย เพื่อไม่ให้ประวัติรกจนอ่านไม่ไหว
// 🔴 [ชั่วคราว] เพิ่มปุ่ม "ลบประวัติทั้งหมด" กลับเข้ามาแล้วตามที่ขอ — สำหรับ
// เคลียร์ log ข้อมูลจำลอง/ทดสอบที่พอกพูนระหว่างพัฒนาเท่านั้น พอจะขึ้นใช้งานจริง
// ต้อง **เอาปุ่มนี้ออก** (ลบตั้งแต่ import ConfirmDialog/clearActivityLog/
// showClearConfirm/handleClear ไปจนถึงปุ่มในส่วน return ด้านล่าง) เพราะขัดกับ
// จุดประสงค์เดิมของหน้านี้ที่ต้องเป็นหลักฐานตรวจสอบย้อนหลังที่ลบไม่ได้
// ---------------------------------------------------------------------------

const ACTION_META = {
  "มอบหมายช่าง": { icon: UserPlus, color: "text-blue-500 bg-blue-50" },
  "ลบงานซ่อม": { icon: Trash2, color: "text-red-500 bg-red-50" },
  "อนุมัติคำขอเบิกอะไหล่": { icon: Check, color: "text-emerald-500 bg-emerald-50" },
  "ปฏิเสธคำขอเบิกอะไหล่": { icon: X, color: "text-red-500 bg-red-50" },
  "ลบลูกค้า": { icon: Trash2, color: "text-red-500 bg-red-50" },
  "ลบช่างเทคนิค": { icon: Trash2, color: "text-red-500 bg-red-50" },
  "ออกใบแจ้งหนี้": { icon: FileText, color: "text-violet-500 bg-violet-50" },
  "มาร์กว่าชำระแล้ว": { icon: Wallet, color: "text-emerald-500 bg-emerald-50" },
};

function formatDateTime(iso) {
  if (!iso) return "-";
  const d = new Date(iso);
  if (isNaN(d.getTime())) return "-";
  // 🔴 [แก้ไข] ตัดตัวเลือกปี ค.ศ. ออกทั้งระบบตามที่ขอ — locale "th-TH" ให้ปี
  // พ.ศ. เป็นค่าเริ่มต้นอยู่แล้ว
  const opts = { day: "numeric", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" };
  return d.toLocaleString("th-TH", opts);
}

export default function ActivityLogPage() {
  const { data: logs, loading } = useDbList("activity_log");
  const [adminFilter, setAdminFilter] = useState("ทั้งหมด");
  // 🔴 [ชั่วคราว] state คู่กับปุ่มลบประวัติทั้งหมด — ลบพร้อมกับปุ่มด้านล่างทีหลัง
  const [showClearConfirm, setShowClearConfirm] = useState(false);
  const [clearing, setClearing] = useState(false);

  const admins = ["ทั้งหมด", ...new Set(logs.map((l) => l.admin_name).filter(Boolean))];
  const sorted = [...logs]
    .filter((l) => adminFilter === "ทั้งหมด" || l.admin_name === adminFilter)
    .sort((a, b) => (new Date(b.created_at).getTime() || 0) - (new Date(a.created_at).getTime() || 0));

  // 🔴 [ชั่วคราว] ลบพร้อมกับปุ่ม/state/import ด้านบนตอนจะขึ้นใช้งานจริง
  async function handleClear() {
    setClearing(true);
    try {
      await clearActivityLog();
      setShowClearConfirm(false);
    } catch (err) {
      console.error("[ActivityLogPage] clear failed:", err);
    } finally {
      setClearing(false);
    }
  }

  if (loading) {
    return <div className="text-sm text-slate-400 py-10 text-center">กำลังโหลดข้อมูล...</div>;
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-5 gap-4">
        <p className="text-xs text-slate-400">
          บันทึกเฉพาะการกระทำสำคัญที่กระทบข้อมูลจริง (มอบหมายช่าง, ลบข้อมูล, อนุมัติ/ปฏิเสธอะไหล่, การเงิน)
        </p>
        <div className="flex items-center gap-2 shrink-0">
          {admins.length > 2 ? (
            <select
              value={adminFilter}
              onChange={(e) => setAdminFilter(e.target.value)}
              className="px-3 py-2 rounded-xl bg-white border border-slate-200 text-sm text-slate-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            >
              {admins.map((a) => (
                <option key={a} value={a}>{a}</option>
              ))}
            </select>
          ) : null}
          {/* 🔴 [ชั่วคราว] ปุ่มลบประวัติทั้งหมด — สำหรับเคลียร์ log ข้อมูลจำลอง/
              ทดสอบระหว่างพัฒนาเท่านั้น เอาออกก่อนขึ้นใช้งานจริง (ดูคอมเมนต์
              บนสุดของไฟล์) */}
          {sorted.length > 0 ? (
            <button
              onClick={() => setShowClearConfirm(true)}
              className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-white border border-red-200 text-sm font-medium text-red-500 hover:bg-red-50"
            >
              <Trash2 size={14} />
              ลบประวัติทั้งหมด
            </button>
          ) : null}
        </div>
      </div>

      <Card className="p-0 overflow-hidden">
        {sorted.length === 0 ? (
          <div className="p-8">
            <EmptyState icon={History} message="ยังไม่มีประวัติการใช้งาน" />
          </div>
        ) : (
          <div className="divide-y divide-slate-50">
            {sorted.map((log, i) => {
              const meta = ACTION_META[log.action] || { icon: HelpCircle, color: "text-slate-500 bg-slate-100" };
              return (
                <div key={log.id ?? i} className="flex items-start gap-3 px-5 py-3.5">
                  <div className={`w-8 h-8 rounded-lg flex items-center justify-center shrink-0 ${meta.color}`}>
                    <meta.icon size={15} />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="text-sm text-slate-700">
                      <span className="font-semibold">{log.admin_name || "ไม่ทราบผู้ใช้"}</span>
                      {" "}
                      <span className="text-slate-500">{log.action}</span>
                    </p>
                    {log.target ? <p className="text-xs text-slate-400 mt-0.5 truncate">{log.target}</p> : null}
                  </div>
                  <span className="text-xs text-slate-400 shrink-0 whitespace-nowrap">{formatDateTime(log.created_at)}</span>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      {/* 🔴 [ชั่วคราว] ลบพร้อมกับปุ่มด้านบนตอนจะขึ้นใช้งานจริง */}
      {showClearConfirm ? (
        <ConfirmDialog
          title="ลบประวัติการใช้งานทั้งหมด?"
          message="ลบแล้วกู้คืนไม่ได้ ปกติหน้านี้ควรเป็นหลักฐานตรวจสอบย้อนหลังที่ลบไม่ได้ — ใช้ปุ่มนี้เฉพาะตอนเคลียร์ข้อมูลจำลอง/ทดสอบเท่านั้น"
          busy={clearing}
          onConfirm={handleClear}
          onCancel={() => setShowClearConfirm(false)}
        />
      ) : null}
    </div>
  );
}
