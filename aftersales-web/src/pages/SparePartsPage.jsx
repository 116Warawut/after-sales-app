import React, { useState, useEffect } from "react";
import { Plus, Search, Package, Check, X, Pencil, Trash2, UploadCloud, Loader2 } from "lucide-react";
import { Card, EmptyState, PrimaryButton, Modal, ConfirmDialog, FormField, Pagination } from "../components/ui";
import useDbList from "../hooks/useDbList";
import useWebSettings from "../hooks/useWebSettings";
import { updatePartRequestStatus, updateRow, addRow, deleteRow, logActivity } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";
import { uploadImage } from "../services/cloudinary";

// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: การ์ดคำขอเบิกอนุมัติ (ปุ่มเขียว = อนุมัติ, ปุ่มแดง =
// ปฏิเสธ) + ตารางคลังอะไหล่ที่มีแถบสีเตือนสต๊อก (ส้ม = ใกล้หมด ≤5 ชิ้น,
// แดง = หมดสต๊อก) — ดูเงื่อนไขสีสต๊อกได้ในฟังก์ชัน map ของตาราง (lowStock/outOfStock)
// ---------------------------------------------------------------------------

// 🆕 [แก้ไข] เดิม PendingRequestRow แสดงคำขอเบิกอะไหล่ทีละใบเรียงเป็น list
// ยาว ๆ ไม่บอกว่าใบไหนเป็นของงานซ่อมไหนบ้าง เปลี่ยนมา "จัดกลุ่มตามเลขแจ้งซ่อม"
// แทน (1 งานซ่อมอาจมีหลายอะไหล่ที่ช่างขอเบิกพร้อมกัน) — ฟังก์ชันนี้ทำหน้าที่
// อนุมัติ/ปฏิเสธคำขอ 1 ใบจริง ๆ (ตัดสต๊อก + เปลี่ยนสถานะ + log activity) ถูก
// แยกออกมาให้ใช้ร่วมกันได้ทั้งปุ่มอนุมัติ/ปฏิเสธรายชิ้น และปุ่ม
// "อนุมัติทั้งหมด"/"ยกเลิกทั้งหมด" ใน JobApprovalModal ด้านล่าง (เดิมโค้ดนี้
// อยู่ใน handle() ของ PendingRequestRow เฉย ๆ ใช้ซ้ำไม่ได้)
async function applyPartRequestDecision(request, status, parts) {
  if (status === "อนุมัติแล้ว") {
    const matchedPart = parts.find((p) => p.record_id === request.part_id);
    if (matchedPart) {
      const currentStock = Number(matchedPart.stock) || 0;
      const requestedQty = Number(request.quantity) || 0;
      const newStock = Math.max(0, currentStock - requestedQty);
      await updateRow("spare_parts", matchedPart.id, { stock: newStock });
    }
  }
  await updatePartRequestStatus(request.id, status);
  // 📝 [ใหม่] บันทึก activity log — ใครอนุมัติ/ปฏิเสธคำขอเบิกอะไหล่ของช่าง
  // คนไหนไปบ้าง
  const admin = getSessionAdmin();
  await logActivity({
    adminUsername: admin?.username,
    adminName: admin?.admin_name,
    action: status === "อนุมัติแล้ว" ? "อนุมัติคำขอเบิกอะไหล่" : "ปฏิเสธคำขอเบิกอะไหล่",
    target: `${request.part_name || "-"} x${request.quantity ?? 0} (ช่าง ${request.technician_username || "-"})`,
  }).catch((err) => console.error("[SparePartsPage] log activity failed:", err));
}

// 🆕 [ใหม่] แถวสรุป 1 งานซ่อมในการ์ด "รายการเบิกอะไหล่ที่รออนุมัติ" — กดแล้ว
// เปิด JobApprovalModal ไปดู/อนุมัติรายการอะไหล่ของงานซ่อมนี้ทั้งหมด
function PendingJobGroupRow({ repairId, items, repairInfo, onOpen }) {
  const jobLabel = repairInfo?.ticketNo || `#${repairId}`;
  const technicianNames = [...new Set(items.map((r) => r.technician_username).filter(Boolean))];
  return (
    <button
      onClick={onOpen}
      className="w-full flex items-center justify-between gap-3 py-3 border-b border-slate-50 last:border-0 text-left hover:bg-slate-50 rounded-lg px-2 -mx-2 transition-colors"
    >
      <div className="min-w-0">
        <p className="text-sm font-medium text-slate-800">
          รายการเบิกอะไหล่ของ {jobLabel}
          {repairInfo?.customer_username ? ` · ${repairInfo.customer_username}` : ""}
        </p>
        <p className="text-xs text-slate-500 mt-0.5">
          {items.length} รายการรออนุมัติ
          {technicianNames.length ? ` · ช่าง ${technicianNames.join(", ")}` : ""}
        </p>
      </div>
      <span className="text-[11px] font-medium px-2.5 py-1 rounded-full bg-orange-50 text-orange-600 shrink-0">
        รออนุมัติ
      </span>
    </button>
  );
}

// 🆕 [ใหม่] Modal แสดงรายการอะไหล่ที่ช่างขอเบิกทั้งหมดของงานซ่อม 1 งาน —
// อนุมัติ/ปฏิเสธได้ทั้งทีละชิ้น (ปุ่มกำกับแต่ละแถว) และทั้งหมดในทีเดียว (ปุ่ม
// "อนุมัติทั้งหมด"/"ยกเลิกทั้งหมด" แยกต่างหากด้านล่าง) — items มาจาก
// pendingRequests ที่กรองด้วย repair_id นี้แล้ว ณ ตอน render ล่าสุด (อัปเดต
// สดตาม realtime listener ของหน้าหลัก) ปิด modal ให้อัตโนมัติเมื่อทำครบทุก
// รายการแล้ว (items กลายเป็น [] เพราะทุกใบเปลี่ยนสถานะพ้นจาก "รอดำเนินการ")
function JobApprovalModal({ repairId, items, repairInfo, parts, onClose }) {
  const [busyId, setBusyId] = useState(null);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (items.length === 0) onClose();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items.length]);

  async function handleOne(request, status) {
    setBusyId(request.id);
    setError("");
    try {
      await applyPartRequestDecision(request, status, parts);
    } catch (err) {
      console.error("[SparePartsPage] update part request failed:", err);
      setError("ดำเนินการไม่สำเร็จ กรุณาลองใหม่");
    } finally {
      setBusyId(null);
    }
  }

  async function handleAll(status) {
    setBulkBusy(true);
    setError("");
    try {
      // 🔴 ทำทีละใบตามลำดับ (ไม่ใช่ Promise.all พร้อมกัน) เพราะการอนุมัติต้อง
      // อ่าน-แล้ว-เขียนสต๊อกของอะไหล่ทับซ้อนกันได้ (อะไหล่ชิ้นเดียวกันถูกขอ
      // เบิกหลายใบในงานเดียวกัน) ถ้ายิงพร้อมกันจะเจอ race condition ตัดสต๊อก
      // ผิดจำนวนได้
      for (const request of items) {
        await applyPartRequestDecision(request, status, parts);
      }
    } catch (err) {
      console.error("[SparePartsPage] bulk update part requests failed:", err);
      setError("ดำเนินการไม่สำเร็จบางรายการ กรุณาตรวจสอบแล้วลองใหม่");
    } finally {
      setBulkBusy(false);
    }
  }

  const jobLabel = repairInfo?.ticketNo || `#${repairId}`;
  const anyBusy = busyId !== null || bulkBusy;

  return (
    <Modal
      title={`รายการเบิกอะไหล่ของ ${jobLabel}`}
      onClose={onClose}
      wide
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ปิด
          </button>
          <button
            onClick={() => handleAll("ปฏิเสธ")}
            disabled={anyBusy}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-red-50 text-red-600 text-sm font-medium hover:bg-red-100 disabled:opacity-50"
          >
            <X size={14} /> ยกเลิกทั้งหมด
          </button>
          <button
            onClick={() => handleAll("อนุมัติแล้ว")}
            disabled={anyBusy}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl bg-emerald-500 text-white text-sm font-medium hover:bg-emerald-600 disabled:opacity-50"
          >
            <Check size={14} /> อนุมัติทั้งหมด
          </button>
        </>
      }
    >
      {repairInfo?.customer_username || repairInfo?.machine ? (
        <p className="text-xs text-slate-400 -mt-2">
          ลูกค้า {repairInfo?.customer_username || "-"} · เครื่อง {repairInfo?.machine || "-"}
        </p>
      ) : null}
      {error ? <p className="text-xs text-red-500">{error}</p> : null}
      <div className="space-y-1">
        {items.map((r) => (
          <div key={r.id} className="flex items-center justify-between gap-3 py-3 border-b border-slate-50 last:border-0">
            <div className="min-w-0">
              <p className="text-sm font-medium text-slate-800">
                {r.part_name || "-"} {r.part_code ? `(${r.part_code})` : ""}
              </p>
              <p className="text-xs text-slate-500 mt-0.5">
                ช่าง {r.technician_username || "-"} ขอเบิก {r.quantity ?? 0} ชิ้น
              </p>
              {r.note ? <p className="text-xs text-slate-400 mt-0.5">หมายเหตุ: {r.note}</p> : null}
            </div>
            <div className="flex items-center gap-2 shrink-0">
              <button
                onClick={() => handleOne(r, "อนุมัติแล้ว")}
                disabled={anyBusy}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-600 text-xs font-medium hover:bg-emerald-100 disabled:opacity-50"
              >
                <Check size={13} /> อนุมัติ
              </button>
              <button
                onClick={() => handleOne(r, "ปฏิเสธ")}
                disabled={anyBusy}
                className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-red-50 text-red-600 text-xs font-medium hover:bg-red-100 disabled:opacity-50"
              >
                <X size={13} /> ปฏิเสธ
              </button>
            </div>
          </div>
        ))}
      </div>
    </Modal>
  );
}

const EMPTY_FORM = { part_code: "", part_name: "", price: "", stock: "", photo_url: "" };

// 🆕 [ใหม่] ป้ายสถานะคำขอเบิกอะไหล่ ใช้ในประวัติการเบิกของ PartDetailModal —
// สีเดียวกับปุ่มอนุมัติ/ปฏิเสธใน PendingRequestRow ด้านบน (เขียว=อนุมัติ,
// แดง=ปฏิเสธ, ส้ม=รอดำเนินการ) ให้ดูสอดคล้องกันทั้งหน้า
const REQUEST_STATUS_BADGE = {
  "อนุมัติแล้ว": "bg-emerald-50 text-emerald-600",
  "ปฏิเสธ": "bg-red-50 text-red-600",
  "รอดำเนินการ": "bg-orange-50 text-orange-600",
};

// 🆕 [ใหม่] Modal แสดงรายละเอียดอะไหล่ 1 ชิ้น — เปิดจากการกดที่แถวในตาราง
// (ไม่ใช่แค่ปุ่มแก้ไข/ลบ) โชว์รูปใหญ่ขึ้น + ข้อมูลครบ + ประวัติการเบิกล่าสุด
// ของอะไหล่ชิ้นนี้ (ดึงจาก part_requests ที่ part_id ตรงกับ record_id ของ
// อะไหล่ — เทียบวิธีเดียวกับที่ PendingRequestRow ใช้จับคู่ตอนอนุมัติ) เพราะ
// ตารางหลักมีคอลัมน์จำกัด ไม่อยากอัดข้อมูลเพิ่มลงไปในแถวจนแน่น จึงแยกมาไว้ที่นี่แทน
function PartDetailModal({ part, requests, onClose, onEdit, onDelete }) {
  const stock = Number(part.stock) || 0;
  const lowStock = stock > 0 && stock <= 5;
  const outOfStock = stock <= 0;

  const history = requests
    .filter((r) => r.part_id === part.record_id)
    .sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""))
    .slice(0, 10);

  return (
    <Modal
      title="รายละเอียดอะไหล่"
      onClose={onClose}
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ปิด
          </button>
          <button
            onClick={onDelete}
            className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-red-500 text-sm font-medium hover:bg-red-50"
          >
            <Trash2 size={14} /> ลบ
          </button>
          <PrimaryButton icon={Pencil} onClick={onEdit}>
            แก้ไข
          </PrimaryButton>
        </>
      }
    >
      <div className="flex items-center gap-4 pb-4 border-b border-slate-100">
        <div className="w-20 h-20 rounded-xl bg-slate-50 border border-slate-200 flex items-center justify-center overflow-hidden shrink-0">
          {part.photo_url ? (
            <img src={part.photo_url} alt={part.part_name} className="w-full h-full object-cover" />
          ) : (
            <Package size={24} className="text-slate-300" />
          )}
        </div>
        <div className="min-w-0">
          <p className="text-sm font-semibold text-slate-800 truncate">{part.part_name || "-"}</p>
          <p className="text-xs text-slate-400 mt-0.5">รหัส {part.part_code || "-"}</p>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 py-4 border-b border-slate-100">
        <div>
          <p className="text-[11px] text-slate-400 mb-1">ราคา</p>
          <p className="text-sm font-medium text-slate-700">{Number(part.price || 0).toLocaleString("th-TH")} บาท</p>
        </div>
        <div>
          <p className="text-[11px] text-slate-400 mb-1">คงเหลือในคลัง</p>
          <p className={"text-sm font-medium " + (outOfStock ? "text-red-500" : lowStock ? "text-orange-500" : "text-slate-700")}>
            {stock} ชิ้น
            {outOfStock ? (
              <span className="ml-2 text-[11px] font-medium px-2 py-0.5 rounded-full bg-red-50 text-red-600">หมด</span>
            ) : lowStock ? (
              <span className="ml-2 text-[11px] font-medium px-2 py-0.5 rounded-full bg-orange-50 text-orange-600">ใกล้หมด</span>
            ) : null}
          </p>
        </div>
      </div>

      <div className="py-4">
        <p className="text-sm font-semibold text-slate-800 mb-3">ประวัติการเบิกล่าสุด</p>
        {history.length === 0 ? (
          <p className="text-xs text-slate-400">ยังไม่มีประวัติการเบิกอะไหล่ชิ้นนี้</p>
        ) : (
          <div className="space-y-3 max-h-56 overflow-y-auto pr-1">
            {history.map((r) => (
              <div key={r.id} className="flex items-center justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs text-slate-700 truncate">
                    ช่าง {r.technician_username || "-"} ขอเบิก {r.quantity ?? 0} ชิ้น
                    {r.repair_id ? ` · งาน #${r.repair_id}` : ""}
                  </p>
                  <p className="text-[11px] text-slate-400 mt-0.5">
                    {r.created_at ? new Date(r.created_at).toLocaleString("th-TH") : "-"}
                  </p>
                </div>
                <span
                  className={
                    "text-[11px] font-medium px-2 py-0.5 rounded-full shrink-0 " +
                    (REQUEST_STATUS_BADGE[r.status] || "bg-slate-100 text-slate-500")
                  }
                >
                  {r.status || "-"}
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </Modal>
  );
}

export default function SparePartsPage({ initialQuery }) {
  const [query, setQuery] = useState(initialQuery || "");
  const { data: parts, loading: loadingParts } = useDbList("spare_parts");
  const { data: partRequests, loading: loadingRequests } = useDbList("part_requests");
  // 🆕 [ใหม่] ใช้หา ticketNo/ลูกค้า/เครื่องจักร ของงานซ่อม มาโชว์เป็นหัวข้อกลุ่ม
  // ในการ์ด "รายการเบิกอะไหล่ที่รออนุมัติ" (จัดกลุ่มตามเลขแจ้งซ่อม)
  const { data: repairs } = useDbList("repairs");

  const [editing, setEditing] = useState(null); // null = ปิด, {} = เพิ่มใหม่, {id,...} = แก้ไข
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  // 🆕 [ใหม่] อะไหล่ที่กำลังเปิดดูรายละเอียด (กดที่แถวในตาราง) — แยกจาก
  // "editing" เพราะเป็นคนละโหมดกัน (ดูอย่างเดียว vs แก้ไขฟอร์ม) แต่ในหน้าดู
  // รายละเอียดมีปุ่ม "แก้ไข"/"ลบ" ลิงก์ไปเปิด editing/deleteTarget ต่อได้เลย
  const [viewing, setViewing] = useState(null);
  // 🆕 [ใหม่] เลข repair_id ของกลุ่มที่กำลังเปิดดู/อนุมัติอยู่ใน
  // JobApprovalModal (null = ปิดอยู่)
  const [viewingGroupId, setViewingGroupId] = useState(null);
  // 🆕 จำนวนรายการต่อหน้า อ่านมาจากหน้าตั้งค่า > ระบบทั่วไป (ของหน้า "อะไหล่")
  const { settings: webSettings } = useWebSettings();
  const pageSize = Number(webSettings.itemsPerPageParts) || 20;
  const [page, setPage] = useState(1);

  // 🔴 [ใหม่] รองรับ initialQuery ที่ส่งมาจากลิงก์ "ไปที่คลังอะไหล่" ใน popup
  // แจ้งเตือนอะไหล่ใกล้หมด (ส่งเลข id ของอะไหล่มาโดยตรง)
  useEffect(() => {
    if (initialQuery) setQuery(initialQuery);
  }, [initialQuery]);

  // 🔴 [แก้ไข] เพิ่มให้ค้นด้วย id ของอะไหล่ตรง ๆ ได้ด้วย (ไม่ใช่แค่ชื่อ) ใช้ตอน
  // กดลิงก์จาก popup แจ้งเตือนที่ส่ง id มาค้นหา
  const filtered = parts.filter(
    (p) =>
      (p.part_name || "").toLowerCase().includes(query.toLowerCase()) ||
      String(p.id ?? "").toLowerCase() === query.toLowerCase()
  );

  // 🆕 กลับไปหน้า 1 ทุกครั้งที่ค้นหาใหม่ กันค้างอยู่หน้าท้ายๆ ที่ไม่มีข้อมูล
  useEffect(() => {
    setPage(1);
  }, [query]);
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const paged = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  const pendingRequests = [...partRequests]
    .filter((r) => r.status === "รอดำเนินการ")
    .sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));

  // 🔴 [แก้ไข] ตามที่ขอ — จัดกลุ่มคำขอที่รออนุมัติตาม repair_id (เลขแจ้งซ่อม)
  // แทนที่จะเรียงเป็น list แบนราบทีละใบเหมือนเดิม ใช้ Map เก็บลำดับการเจอกลุ่ม
  // ครั้งแรกไว้ (ซึ่งเรียงตาม created_at ล่าสุดอยู่แล้วจาก pendingRequests
  // ด้านบน) แล้วค่อยแปลงเป็น array ตอนท้าย
  const pendingGroups = (() => {
    const map = new Map();
    pendingRequests.forEach((r) => {
      const key = r.repair_id ?? "-";
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(r);
    });
    return Array.from(map.entries()).map(([repairId, items]) => ({ repairId, items }));
  })();
  const viewingGroup = pendingGroups.find((g) => String(g.repairId) === String(viewingGroupId));

  function openAdd() {
    setForm(EMPTY_FORM);
    setEditing({});
  }

  function openEdit(part) {
    setForm({
      part_code: part.part_code || "",
      part_name: part.part_name || "",
      price: part.price ?? "",
      stock: part.stock ?? "",
      photo_url: part.photo_url || "",
    });
    setEditing(part);
  }

  // 📷 อัปโหลดรูปอะไหล่ขึ้น Cloudinary ทันทีตอนเลือกไฟล์ (บัญชีเดียวกับที่แอปมือถือ
  // Flutter ใช้อยู่แล้ว) เก็บ URL ที่ได้ไว้ในฟอร์ม รอกดบันทึกอีกทีถึงจะเขียนลง Firebase
  async function handlePickPhoto(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const url = await uploadImage(file);
      setForm((f) => ({ ...f, photo_url: url }));
    } catch (err) {
      console.error("[SparePartsPage] upload photo failed:", err);
    } finally {
      setUploading(false);
    }
  }

  async function handleSave() {
    setSaving(true);
    try {
      const payload = {
        part_code: form.part_code.trim(),
        part_name: form.part_name.trim(),
        price: Number(form.price) || 0,
        stock: Number(form.stock) || 0,
        photo_url: form.photo_url || "",
      };
      if (editing?.id) {
        await updateRow("spare_parts", editing.id, payload);
      } else {
        await addRow("spare_parts", payload);
      }
      setEditing(null);
    } catch (err) {
      console.error("[SparePartsPage] save failed:", err);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRow("spare_parts", deleteTarget.id);
      setDeleteTarget(null);
    } catch (err) {
      console.error("[SparePartsPage] delete failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div>
      {/* 🔴 [แก้ไข] เอาหัวข้อ "อะไหล่" ออก เพราะซ้ำกับ Header บนสุด — ปุ่มเพิ่ม
          อะไหล่ใหม่ย้ายไปอยู่คู่กับช่องค้นหาแทน (ในการ์ดตารางด้านล่าง) */}
      <Card className="mb-5">
        <h3 className="text-sm font-semibold text-slate-800 mb-4">รายการเบิกอะไหล่ที่รออนุมัติ</h3>
        {loadingRequests ? (
          <p className="text-xs text-slate-400 text-center py-6">กำลังโหลดข้อมูล...</p>
        ) : pendingGroups.length === 0 ? (
          <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีคำขอเบิกอะไหล่ที่รออนุมัติ</p>
        ) : (
          <div>
            {pendingGroups.map((g) => (
              <PendingJobGroupRow
                key={g.repairId}
                repairId={g.repairId}
                items={g.items}
                repairInfo={repairs.find((r) => String(r.record_id) === String(g.repairId))}
                onOpen={() => setViewingGroupId(g.repairId)}
              />
            ))}
          </div>
        )}
      </Card>

      <Card className="p-0 overflow-hidden">
        <div className="p-5 pb-0 flex items-center justify-between gap-3">
          <div className="relative max-w-sm flex-1">
            <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="ค้นหาอะไหล่..."
              className="w-full pl-9 pr-8 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-red-100"
            />
            {/* 🔴 [ใหม่] ปุ่มล้างการค้นหา — กดครั้งเดียวเคลียร์ query ทันที ไม่ต้อง
                ลบเองทีละตัวอักษร โชว์เฉพาะตอนมีข้อความในช่องค้นหาเท่านั้น */}
            {query ? (
              <button
                onClick={() => setQuery("")}
                className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500"
              >
                <X size={14} />
              </button>
            ) : null}
          </div>
          <PrimaryButton icon={Plus} onClick={openAdd}>เพิ่มอะไหล่ใหม่</PrimaryButton>
        </div>

        <div className="p-5">
          {loadingParts ? (
            <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
          ) : filtered.length === 0 ? (
            <EmptyState icon={Package} message="ยังไม่มีอะไหล่ในคลัง" />
          ) : (
            <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs text-slate-400 border-b border-slate-100">
                  <th className="py-2 font-medium w-14"></th>
                  <th className="py-2 font-medium">รหัสอะไหล่</th>
                  <th className="py-2 font-medium">ชื่ออะไหล่</th>
                  <th className="py-2 font-medium">ราคา</th>
                  <th className="py-2 font-medium">คงเหลือในคลัง</th>
                  <th className="py-2 font-medium w-20"></th>
                </tr>
              </thead>
              <tbody>
                {paged.map((p) => {
                  const stock = Number(p.stock) || 0;
                  const lowStock = stock > 0 && stock <= 5;
                  const outOfStock = stock <= 0;
                  return (
                    <tr
                      key={p.id}
                      onClick={() => setViewing(p)}
                      className="border-b border-slate-50 last:border-0 cursor-pointer hover:bg-slate-50"
                    >
                      <td className="py-2.5">
                        {p.photo_url ? (
                          <img src={p.photo_url} alt={p.part_name} className="w-9 h-9 rounded-lg object-cover border border-slate-100" />
                        ) : (
                          <div className="w-9 h-9 rounded-lg bg-slate-100 flex items-center justify-center text-slate-300">
                            <Package size={16} />
                          </div>
                        )}
                      </td>
                      <td className="py-2.5 text-slate-500">{p.part_code || "-"}</td>
                      <td className="py-2.5 text-slate-700">{p.part_name || "-"}</td>
                      <td className="py-2.5 text-slate-700">
                        {Number(p.price || 0).toLocaleString("th-TH")} บาท
                      </td>
                      <td className="py-2.5">
                        <span
                          className={
                            "text-sm font-medium " +
                            (outOfStock ? "text-red-500" : lowStock ? "text-orange-500" : "text-slate-700")
                          }
                        >
                          {stock} ชิ้น
                        </span>
                        {outOfStock ? (
                          <span className="ml-2 text-[11px] font-medium px-2 py-0.5 rounded-full bg-red-50 text-red-600">หมด</span>
                        ) : lowStock ? (
                          <span className="ml-2 text-[11px] font-medium px-2 py-0.5 rounded-full bg-orange-50 text-orange-600">ใกล้หมด</span>
                        ) : null}
                      </td>
                      <td className="py-2.5" onClick={(e) => e.stopPropagation()}>
                        <div className="flex items-center gap-1 justify-end">
                          <button
                            onClick={() => openEdit(p)}
                            title="แก้ไข"
                            className="w-7 h-7 rounded-lg flex items-center justify-center text-blue-500 hover:bg-blue-50"
                          >
                            <Pencil size={14} />
                          </button>
                          <button
                            onClick={() => setDeleteTarget(p)}
                            title="ลบ"
                            className="w-7 h-7 rounded-lg flex items-center justify-center text-red-500 hover:bg-red-50"
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

      {viewingGroupId !== null ? (
        <JobApprovalModal
          repairId={viewingGroupId}
          items={viewingGroup?.items || []}
          repairInfo={repairs.find((r) => String(r.record_id) === String(viewingGroupId))}
          parts={parts}
          onClose={() => setViewingGroupId(null)}
        />
      ) : null}

      {viewing ? (
        <PartDetailModal
          part={viewing}
          requests={partRequests}
          onClose={() => setViewing(null)}
          onEdit={() => {
            openEdit(viewing);
            setViewing(null);
          }}
          onDelete={() => {
            setDeleteTarget(viewing);
            setViewing(null);
          }}
        />
      ) : null}

      {editing !== null && (
        <Modal
          title={editing?.id ? "แก้ไขอะไหล่" : "เพิ่มอะไหล่ใหม่"}
          onClose={() => setEditing(null)}
          footer={
            <>
              <button onClick={() => setEditing(null)} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
                ยกเลิก
              </button>
              <PrimaryButton onClick={handleSave} disabled={saving}>
                {saving ? "กำลังบันทึก..." : "บันทึก"}
              </PrimaryButton>
            </>
          }
        >
          <div>
            <label className="text-sm text-slate-600 mb-2 block font-medium">รูปภาพอะไหล่</label>
            <div className="flex items-center gap-4">
              <div className="w-20 h-20 rounded-xl bg-slate-50 border border-slate-200 flex items-center justify-center overflow-hidden shrink-0">
                {form.photo_url ? (
                  <img src={form.photo_url} alt="พรีวิวรูปอะไหล่" className="w-full h-full object-cover" />
                ) : (
                  <Package size={24} className="text-slate-300" />
                )}
              </div>
              <label className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-600 cursor-pointer hover:bg-slate-100">
                {uploading ? <Loader2 size={16} className="animate-spin" /> : <UploadCloud size={16} />}
                {uploading ? "กำลังอัปโหลด..." : "เลือกรูปภาพ"}
                <input type="file" accept="image/*" className="hidden" onChange={handlePickPhoto} disabled={uploading} />
              </label>
            </div>
          </div>
          <FormField label="รหัสอะไหล่" value={form.part_code} onChange={(v) => setForm((f) => ({ ...f, part_code: v }))} placeholder="เช่น SP-001" />
          <FormField label="ชื่ออะไหล่" value={form.part_name} onChange={(v) => setForm((f) => ({ ...f, part_name: v }))} placeholder="เช่น ตลับหมึก HP 12A" required />
          <FormField label="ราคา (บาท)" type="number" value={form.price} onChange={(v) => setForm((f) => ({ ...f, price: v }))} placeholder="0" />
          <FormField label="จำนวนคงเหลือในคลัง" type="number" value={form.stock} onChange={(v) => setForm((f) => ({ ...f, stock: v }))} placeholder="0" />
        </Modal>
      )}

      {deleteTarget ? (
        <ConfirmDialog
          message={`ต้องการลบอะไหล่ "${deleteTarget.part_name}" ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          busy={deleting}
        />
      ) : null}
    </div>
  );
}