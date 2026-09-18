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
    // 🐛 [แก้บัค] เดิมจับคู่ด้วย record_id (ฟิลด์ id ภายในของอะไหล่ ซึ่งฝั่งแอป
    // เปลี่ยนมาส่ง part_id เป็น Firebase key จริงแล้ว ไม่ใช่ id ภายในนี้อีกต่อไป
    // — ดู spare_part_tec_viewer.dart) ทำให้จับคู่ไม่เจอ สต๊อกเลยไม่ถูกตัดตอน
    // อนุมัติ เปลี่ยนมาจับคู่ด้วย .id (Firebase key จริง) แทน ให้ตรงกับที่ฝั่ง
    // แอปใช้ getSparePartById()/updateSparePartStock() เช่นกัน
    const matchedPart = parts.find((p) => String(p.id) === String(request.part_id));
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

// 🆕 [ใหม่] ป้ายสถานะคำขอเบิกอะไหล่ ใช้ทั้งในประวัติการเบิกของ PartDetailModal
// และตอนแสดงกลุ่มคำขอที่ไม่ได้กรองเฉพาะ "รอดำเนินการ" อีกต่อไป (การ์ด "รายการ
// เบิกอะไหล่ทั้งหมด" ที่เพิ่มใหม่) — สีเดียวกับปุ่มอนุมัติ/ปฏิเสธ (เขียว=อนุมัติ,
// แดง=ปฏิเสธ, ส้ม=รอดำเนินการ) ให้ดูสอดคล้องกันทั้งหน้า
const REQUEST_STATUS_BADGE = {
  "อนุมัติแล้ว": "bg-emerald-50 text-emerald-600",
  "ปฏิเสธ": "bg-red-50 text-red-600",
  "รอดำเนินการ": "bg-orange-50 text-orange-600",
};

// 🐛 [แก้ไข] BUG: จุดที่ต้องหา repairInfo จาก repairId (ของกลุ่มคำขอเบิก
// อะไหล่) เดิมเทียบแค่ String(r.record_id) === String(repairId) เท่านั้น —
// เจอว่าแทบทุกกลุ่มหา repairInfo ไม่เจอเลยสักรายการ (ตัวหัวข้อเลยตกไปใช้
// fallback "#repairId" เฉยๆ แทน ticketNo จริง, ไม่โชว่ชื่อลูกค้าที่ควรมี, และ
// ปุ่ม "ลบงานซ่อม" ที่เพิ่งเพิ่มก็เลยไม่ขึ้นเลยสักแถวเพราะเช็ค repairInfo?.id
// ไว้) สาเหตุคือ repair_id ที่ฝั่งแอปมือถือบันทึกไว้ใน part_requests บางที
// อ้างอิงด้วยคีย์จริงใน Firebase (r.id) ไม่ใช่เลข record_id เพียงอย่างเดียว —
// เปลี่ยนมาเทียบทั้งสองแบบ (ลองจับคู่กับ record_id ก่อน ถ้าไม่เจอค่อยลองจับคู่
// กับ id) ให้ครอบคลุมทั้งสองกรณี
function findRepairInfo(repairs, repairId) {
  return repairs.find(
    (r) => String(r.record_id) === String(repairId) || String(r.id) === String(repairId)
  );
}

// 🆕 [ใหม่] แถวสรุป 1 งานซ่อม ใช้ร่วมกันทั้งการ์ด "รอเบิก" (ทุกใบในกลุ่มเป็น
// "รอดำเนินการ" เสมออยู่แล้ว) และการ์ด "ทั้งหมด" ที่เพิ่มใหม่ (สถานะในกลุ่ม
// อาจปนกันได้ — อนุมัติไปแล้วบ้าง ปฏิเสธไปแล้วบ้าง ยังรอบ้าง) ป้ายสถานะเลย
// ต้องคำนวณจากรายการจริงในกลุ่มแทนที่จะ hardcode "รออนุมัติ" ไว้ตรงๆ เหมือนเดิม
function groupStatusBadge(items) {
  const statuses = new Set(items.map((r) => r.status));
  if (statuses.size === 1) {
    const s = [...statuses][0];
    return { label: s || "-", className: REQUEST_STATUS_BADGE[s] || "bg-slate-100 text-slate-500" };
  }
  const pendingCount = items.filter((r) => r.status === "รอดำเนินการ").length;
  if (pendingCount > 0) {
    return { label: `รออนุมัติ ${pendingCount} รายการ`, className: "bg-orange-50 text-orange-600" };
  }
  return { label: "หลายสถานะ", className: "bg-slate-100 text-slate-500" };
}

// 🔴 [แก้ไข] รื้อใหม่ตามที่ขอ — เดิมปุ่มลบผูกกับ "ลบงานซ่อม" ซึ่งต้องหา
// repairInfo (ข้อมูลงานซ่อมจริง) มาก่อนถึงจะรู้ว่าจะลบ record ไหนใน collection
// "repairs" แต่การจับคู่ repair_id ↔ repairs ยังมีบั๊กอยู่ (เพื่อนกำลังแก้อีก
// ทาง) ทำให้หา repairInfo ไม่เจอแทบทุกแถว ปุ่มเลยไม่โผล่มาให้กดเลย —
// เปลี่ยนแนวทางใหม่ทั้งหมด: ปุ่มนี้ลบ "รายการคำขอเบิกอะไหล่ทั้งหมดของกลุ่มนี้"
// (part_requests ที่รวมกันอยู่ในแถวนี้) โดยตรงแทน ไม่ต้องพึ่ง repairInfo เลย
// เพราะ items ที่ส่งเข้ามาแต่ละชิ้นมี id ของตัวเองอยู่แล้วจาก part_requests
// ตรงๆ (ไม่ผ่านการจับคู่ใดๆ) รับประกันว่ากดได้ผลจริงทุกแถว รวมถึงแถว "#-" ที่
// หา repairInfo ไม่เจอด้วย (ให้ลบทิ้งเพื่อเคลียร์ข้อมูลเก่าที่ไม่มีเจ้าของแล้ว)
function JobGroupRow({ repairId, items, repairInfo, onOpen, onDelete }) {
  const jobLabel = repairInfo?.ticketNo || `#${repairId}`;
  const technicianNames = [...new Set(items.map((r) => r.technician_username).filter(Boolean))];
  const badge = groupStatusBadge(items);
  return (
    // 🔴 [แก้ไข] เดิมทั้งแถวเป็น <button> เดียวกดได้ทั้งแถว — เพิ่มปุ่ม "ลบ
    // งานซ่อม" เข้ามาตามที่ขอ ปุ่มซ้อนอยู่ในปุ่มไม่ได้ (ผิดกฎ HTML กดแล้วจะงง)
    // เลยเปลี่ยนแถวนอกสุดเป็น <div> ธรรมดา แล้วแยกส่วนข้อความ (กดเพื่อดู
    // รายละเอียด) กับปุ่มลบออกเป็นปุ่มคนละอันวางเคียงกันแทน
    <div className="w-full flex items-center justify-between gap-3 py-3 border-b border-slate-50 last:border-0 hover:bg-slate-50 rounded-lg px-2 -mx-2 transition-colors">
      <button onClick={onOpen} className="min-w-0 flex-1 text-left">
        <p className="text-sm font-medium text-slate-800">
          รายการเบิกอะไหล่ของ {jobLabel}
          {repairInfo?.customer_username ? ` · ${repairInfo.customer_username}` : ""}
        </p>
        <p className="text-xs text-slate-500 mt-0.5">
          {items.length} รายการ
          {technicianNames.length ? ` · ช่าง ${technicianNames.join(", ")}` : ""}
        </p>
      </button>
      <div className="flex items-center gap-2 shrink-0">
        <span className={`text-[11px] font-medium px-2.5 py-1 rounded-full ${badge.className}`}>
          {badge.label}
        </span>
        {onDelete ? (
          <button
            onClick={(e) => {
              e.stopPropagation();
              onDelete({ repairId, items, jobLabel });
            }}
            title="ลบรายการเบิกอะไหล่ของงานนี้ทั้งหมด"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 bg-red-500/10 hover:text-red-300 hover:bg-red-500/20 transition-colors"
          >
            <Trash2 size={14} />
          </button>
        ) : null}
      </div>
    </div>
  );
}

// 🆕 [ใหม่] Modal แสดงรายการอะไหล่ที่ช่างขอเบิกทั้งหมดของงานซ่อม 1 งาน —
// อนุมัติ/ปฏิเสธได้ทั้งทีละชิ้น (ปุ่มกำกับแต่ละแถว) และทั้งหมดในทีเดียว (ปุ่ม
// "อนุมัติทั้งหมด"/"ยกเลิกทั้งหมด" แยกต่างหากด้านล่าง) — items มาจาก
// pendingRequests ที่กรองด้วย repair_id นี้แล้ว ณ ตอน render ล่าสุด (อัปเดต
// สดตาม realtime listener ของหน้าหลัก) ปิด modal ให้อัตโนมัติเมื่อทำครบทุก
// รายการแล้ว (items กลายเป็น [] เพราะทุกใบเปลี่ยนสถานะพ้นจาก "รอดำเนินการ")
// 🔴 [แก้ไข] เดิม modal นี้เปิดได้แค่จากการ์ด "รอเบิก" เท่านั้น (ทุกใบในกลุ่ม
// เป็น "รอดำเนินการ" เสมอ) ตอนนี้เปิดได้จากการ์ด "ทั้งหมด" ด้วย ซึ่งกลุ่มอาจมี
// ใบที่อนุมัติ/ปฏิเสธไปแล้วปนอยู่ — ถ้าปล่อยให้กดปุ่ม "อนุมัติ" ซ้ำกับใบที่
// อนุมัติไปแล้ว จะตัดสต๊อกซ้ำอีกรอบ (บั๊ก) เลยต้องโชว่ปุ่มอนุมัติ/ปฏิเสธเฉพาะ
// ใบที่ยัง "รอดำเนินการ" จริงๆ เท่านั้น ใบที่ตัดสินใจไปแล้วโชว่แค่ป้ายสถานะ
// เฉยๆ (กดอะไรไม่ได้อีก) ปุ่ม "อนุมัติทั้งหมด/ยกเลิกทั้งหมด" ด้านล่างก็เหลือ
// แค่ทำกับใบที่ยังรออยู่เท่านั้นเช่นกัน ถ้าไม่มีใบไหนรออยู่เลยก็ซ่อนปุ่มสองอันนี้
function JobApprovalModal({ repairId, items, repairInfo, parts, onClose }) {
  const [busyId, setBusyId] = useState(null);
  const [bulkBusy, setBulkBusy] = useState(false);
  const [error, setError] = useState("");
  // 🆕 [ใหม่] ลบคำขอเบิกอะไหล่ทีละรายการ (ตามที่ขอ — แยกจากปุ่ม "ลบงานซ่อม"
  // ทั้งใบที่ทำไปก่อนหน้านี้ อันนี้ลบแค่รายการอะไหล่ 1 บรรทัดในงานนี้ ลบได้ทุก
  // สถานะไม่ว่าจะรออยู่/อนุมัติ/ปฏิเสธไปแล้วก็ตาม)
  const [deleteRequestTarget, setDeleteRequestTarget] = useState(null);
  const [deletingRequest, setDeletingRequest] = useState(false);

  const pendingItems = items.filter((r) => r.status === "รอดำเนินการ");

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
      for (const request of pendingItems) {
        await applyPartRequestDecision(request, status, parts);
      }
    } catch (err) {
      console.error("[SparePartsPage] bulk update part requests failed:", err);
      setError("ดำเนินการไม่สำเร็จบางรายการ กรุณาตรวจสอบแล้วลองใหม่");
    } finally {
      setBulkBusy(false);
    }
  }

  async function handleDeleteRequest() {
    if (!deleteRequestTarget) return;
    setDeletingRequest(true);
    try {
      await deleteRow("part_requests", deleteRequestTarget.id);
      setDeleteRequestTarget(null);
    } catch (err) {
      console.error("[SparePartsPage] delete part request failed:", err);
      setError("ลบรายการไม่สำเร็จ กรุณาลองใหม่");
    } finally {
      setDeletingRequest(false);
    }
  }

  const jobLabel = repairInfo?.ticketNo || `#${repairId}`;
  const anyBusy = busyId !== null || bulkBusy;

  return (
    <>
    <Modal
      title={`รายการเบิกอะไหล่ของ ${jobLabel}`}
      onClose={onClose}
      wide
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ปิด
          </button>
          {pendingItems.length > 0 ? (
            <>
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
          ) : null}
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
              {r.status === "รอดำเนินการ" ? (
                <>
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
                </>
              ) : (
                <span className={`text-[11px] font-medium px-2.5 py-1 rounded-full ${REQUEST_STATUS_BADGE[r.status] || "bg-slate-100 text-slate-500"}`}>
                  {r.status || "-"}
                </span>
              )}
              {/* 🆕 [ใหม่] ปุ่มลบรายการนี้ทีละบรรทัด — โชว่ทุกแถวไม่ว่าสถานะไหน
                  (แยกจากปุ่มอนุมัติ/ปฏิเสธ/ป้ายสถานะด้านซ้าย) ตามที่ขอ อยู่ใน
                  กลุ่ม flex เดียวกันกับปุ่ม/ป้ายด้านบน จะได้ติดกัน ไม่ถูก
                  justify-between ของแถวนอกดันให้ห่างออกไปสุดขอบ */}
              <button
                onClick={() => setDeleteRequestTarget(r)}
                disabled={anyBusy}
                title="ลบรายการนี้"
                className="w-7 h-7 rounded-lg flex items-center justify-center text-red-400 bg-red-500/10 hover:text-red-300 hover:bg-red-500/20 transition-colors shrink-0 disabled:opacity-50"
              >
                <Trash2 size={13} />
              </button>
            </div>
          </div>
        ))}
      </div>
    </Modal>

    {deleteRequestTarget ? (
      <ConfirmDialog
        message={`ต้องการลบรายการเบิก "${deleteRequestTarget.part_name || "-"}" (ช่าง ${deleteRequestTarget.technician_username || "-"} ขอเบิก ${deleteRequestTarget.quantity ?? 0} ชิ้น) ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
        onConfirm={handleDeleteRequest}
        onCancel={() => setDeleteRequestTarget(null)}
        busy={deletingRequest}
      />
    ) : null}
    </>
  );
}

// 🆕 [ใหม่] Popup "ดูรายการทั้งหมด" ใช้ร่วมกันทั้งการ์ด "รอเบิก" และ "ทั้งหมด"
// (ตามที่ขอให้หน้าตาเหมือนกัน) — แค่ส่ง groups/title ต่างกันเข้ามา แบ่งหน้าด้วย
// จำนวนรายการต่อหน้าที่ตั้งไว้ในหน้าตั้งค่า (itemsPerPagePartRequests) กดแถว
// ไหนก็เปิด JobApprovalModal ของงานนั้นต่อได้เลยเหมือนในหน้าหลัก
function AllGroupsListModal({ title, groups, pageSize, repairs, onOpenGroup, onDeleteJob, onClose }) {
  const [page, setPage] = useState(1);
  const totalPages = Math.max(1, Math.ceil(groups.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const paged = groups.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  return (
    <Modal title={title} onClose={onClose} wide>
      {groups.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีรายการ</p>
      ) : (
        <div>
          {paged.map((g) => (
            <JobGroupRow
              key={g.repairId}
              repairId={g.repairId}
              items={g.items}
              repairInfo={findRepairInfo(repairs, g.repairId)}
              onOpen={() => onOpenGroup(g.repairId)}
              onDelete={onDeleteJob}
            />
          ))}
        </div>
      )}
      <Pagination page={currentPage} totalPages={totalPages} onChange={setPage} totalItems={groups.length} pageSize={pageSize} />
    </Modal>
  );
}

// 🆕 [ใหม่] Modal แสดงรายละเอียดอะไหล่ 1 ชิ้น — เปิดจากการกดที่แถวในตาราง
// (ไม่ใช่แค่ปุ่มแก้ไข/ลบ) โชว์รูปใหญ่ขึ้น + ข้อมูลครบ + ประวัติการเบิกล่าสุด
// ของอะไหล่ชิ้นนี้ (ดึงจาก part_requests ที่ part_id ตรงกับ .id (Firebase key
// จริง) ของอะไหล่ — แก้ให้ตรงกับ applyPartRequestDecision() ด้านบนที่แก้ไปแล้ว)
// เพราะตารางหลักมีคอลัมน์จำกัด ไม่อยากอัดข้อมูลเพิ่มลงไปในแถวจนแน่น จึงแยกมาไว้ที่นี่แทน
function PartDetailModal({ part, requests, onClose, onEdit, onDelete }) {
  const stock = Number(part.stock) || 0;
  const lowStock = stock > 0 && stock <= 5;
  const outOfStock = stock <= 0;

  const history = requests
    .filter((r) => String(r.part_id) === String(part.id))
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

const EMPTY_FORM = { part_code: "", part_name: "", price: "", stock: "", photo_url: "" };

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
  // 🆕 [ใหม่] popup "ดูรายการทั้งหมด" — "pending" = จากการ์ดรอเบิก, "all" =
  // จากการ์ดทั้งหมด, null = ปิดอยู่ (ใช้ popup เดียวกันสลับข้อมูลตามโหมด)
  const [viewAllMode, setViewAllMode] = useState(null);
  // 🔴 [แก้ไข] เปลี่ยนจาก "ลบงานซ่อม" (ต้องพึ่ง repairInfo ที่จับคู่ไม่ติด) มา
  // เป็น "ลบคำขอเบิกอะไหล่ทั้งกลุ่มของงานนี้" แทน — เก็บ { repairId, items,
  // jobLabel } ของกลุ่มที่จะลบไว้ตรงนี้ (ไม่ต้องมี repairInfo เลย)
  const [deleteGroupTarget, setDeleteGroupTarget] = useState(null);
  const [deletingGroup, setDeletingGroup] = useState(false);
  // 🆕 จำนวนรายการต่อหน้า อ่านมาจากหน้าตั้งค่า > ระบบทั่วไป (ของหน้า "อะไหล่")
  const { settings: webSettings } = useWebSettings();
  const pageSize = Number(webSettings.itemsPerPageParts) || 20;
  // 🆕 [ใหม่] จำนวนรายการต่อหน้าของ popup "ดูรายการทั้งหมด" (คำขอเบิกอะไหล่)
  // แยกต่างหากจากจำนวนรายการต่อหน้าของตารางคลังอะไหล่ด้านบน — ตั้งค่าได้ที่
  // หน้าตั้งค่า > จำนวนรายการต่อหน้า > "รายการเบิกอะไหล่ (Pop-up ดูทั้งหมด)"
  const requestsPageSize = Number(webSettings.itemsPerPagePartRequests) || 20;
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

  // 🆕 [ใหม่] จัดกลุ่มคำขอเบิกอะไหล่ตาม repair_id (เลขแจ้งซ่อม) — ใช้ฟังก์ชัน
  // เดียวกันทั้งสร้างกลุ่ม "รอเบิก" (กรองเฉพาะรอดำเนินการก่อน) และกลุ่ม
  // "ทั้งหมด" (ไม่กรองสถานะเลย) ตามที่ขอให้มีทั้ง 2 กล่องนี้ในหน้าเดียวกัน
  function groupByRepairId(requests) {
    const map = new Map();
    requests.forEach((r) => {
      const key = r.repair_id ?? "-";
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(r);
    });
    return Array.from(map.entries()).map(([repairId, items]) => ({ repairId, items }));
  }

  const pendingRequests = [...partRequests]
    .filter((r) => r.status === "รอดำเนินการ")
    .sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));
  const allRequestsSorted = [...partRequests].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));

  const pendingGroups = groupByRepairId(pendingRequests);
  const allGroups = groupByRepairId(allRequestsSorted);
  // 🔴 [แก้ไข] กลุ่มที่กำลังเปิดดูอาจถูกเปิดมาจากการ์ด "ทั้งหมด" ก็ได้ (มีใบที่
  // ตัดสินใจไปแล้วปนอยู่ ไม่ได้อยู่ใน pendingGroups) เลยต้องหาจาก allGroups
  // (ชุดใหญ่กว่า ครอบคลุมทุกกรณี) แทนที่จะหาจาก pendingGroups อย่างเดียวเหมือนเดิม
  const viewingGroup = allGroups.find((g) => String(g.repairId) === String(viewingGroupId));

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

  // 🔴 [แก้ไข] รื้อใหม่ตามที่ขอ — เดิมลบ "งานซ่อม" ทั้งใบ (ต้องรู้คีย์จริงของ
  // repairs record ซึ่งมาจาก repairInfo ที่จับคู่ไม่ติดแทบทุกครั้ง ปุ่มเลย
  // กดไม่ได้ผลจริง) เปลี่ยนมาลบ "คำขอเบิกอะไหล่ทุกใบของกลุ่มนี้" (part_requests)
  // โดยตรงแทน — ใช้ items ที่มาจาก useDbList("part_requests") ตรงๆ อยู่แล้ว
  // (แต่ละใบมี id ของตัวเองชัดเจน ไม่ต้องพึ่งการจับคู่ใดๆ) รับประกันว่าลบได้
  // จริงทุกแถว รวมถึงแถว "#-" ที่หา repairInfo ไม่เจอด้วย (ลบเพื่อเคลียร์
  // ข้อมูลเก่าที่ไม่มีเจ้าของแล้วออกไปเลย)
  async function handleDeleteGroup() {
    if (!deleteGroupTarget?.items?.length) {
      setDeleteGroupTarget(null);
      return;
    }
    setDeletingGroup(true);
    try {
      // 🔴 ลบทีละใบตามลำดับ (ไม่ใช่ Promise.all พร้อมกัน) ให้สอดคล้องกับแนวทาง
      // เดียวกับตอนอนุมัติ/ปฏิเสธทั้งหมดด้านบน กันปัญหาเขียนพร้อมกันชนกัน
      for (const item of deleteGroupTarget.items) {
        await deleteRow("part_requests", item.id);
      }
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ลบรายการเบิกอะไหล่ทั้งกลุ่ม",
        target: `${deleteGroupTarget.jobLabel} (${deleteGroupTarget.items.length} รายการ)`,
      }).catch((err) => console.error("[SparePartsPage] log activity failed:", err));
      setDeleteGroupTarget(null);
    } catch (err) {
      console.error("[SparePartsPage] delete group failed:", err);
    } finally {
      setDeletingGroup(false);
    }
  }

  return (
    <div>
      {/* 🔴 [แก้ไข] เอาหัวข้อ "อะไหล่" ออก เพราะซ้ำกับ Header บนสุด — ปุ่มเพิ่ม
          อะไหล่ใหม่ย้ายไปอยู่คู่กับช่องค้นหาแทน (ในการ์ดตารางด้านล่าง)
          🆕 [ใหม่] เดิมมีแค่กล่อง "รอเบิก" กล่องเดียวเต็มความกว้าง — เพิ่มกล่อง
          "ทั้งหมด" คู่กันตามที่ขอ วางข้างกัน 2 คอลัมน์ ทั้งคู่โชว่แค่ 5 รายการ
          ล่าสุด (ขนาดกล่องจะได้เท่ากันพอดี) พร้อมปุ่ม "ดูรายการทั้งหมด" มุมขวา
          บนเปิด popup แบ่งหน้าดูครบทุกรายการได้ */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-5 mb-5">
        <Card>
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-semibold text-slate-800">รายการเบิกอะไหล่ที่รออนุมัติ</h3>
            {pendingGroups.length > 0 ? (
              <button
                onClick={() => setViewAllMode("pending")}
                className="text-xs font-medium text-blue-600 hover:underline shrink-0"
              >
                ดูรายการทั้งหมด
              </button>
            ) : null}
          </div>
          {loadingRequests ? (
            <p className="text-xs text-slate-400 text-center py-6">กำลังโหลดข้อมูล...</p>
          ) : pendingGroups.length === 0 ? (
            <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีคำขอเบิกอะไหล่ที่รออนุมัติ</p>
          ) : (
            <div>
              {pendingGroups.slice(0, 5).map((g) => (
                <JobGroupRow
                  key={g.repairId}
                  repairId={g.repairId}
                  items={g.items}
                  repairInfo={findRepairInfo(repairs, g.repairId)}
                  onOpen={() => setViewingGroupId(g.repairId)}
                />
              ))}
            </div>
          )}
        </Card>

        <Card>
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-sm font-semibold text-slate-800">รายการเบิกอะไหล่ทั้งหมด</h3>
            {allGroups.length > 0 ? (
              <button
                onClick={() => setViewAllMode("all")}
                className="text-xs font-medium text-blue-600 hover:underline shrink-0"
              >
                ดูรายการทั้งหมด
              </button>
            ) : null}
          </div>
          {loadingRequests ? (
            <p className="text-xs text-slate-400 text-center py-6">กำลังโหลดข้อมูล...</p>
          ) : allGroups.length === 0 ? (
            <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีการเบิกอะไหล่</p>
          ) : (
            <div>
              {allGroups.slice(0, 5).map((g) => (
                <JobGroupRow
                  key={g.repairId}
                  repairId={g.repairId}
                  items={g.items}
                  repairInfo={findRepairInfo(repairs, g.repairId)}
                  onOpen={() => setViewingGroupId(g.repairId)}
                  onDelete={setDeleteGroupTarget}
                />
              ))}
            </div>
          )}
        </Card>
      </div>

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

      {/* 🔴 [แก้ไข] เดิมกดรายการในป๊อปอัป "ดูรายการทั้งหมด" แล้วป๊อปอัปนั้นจะปิด
          ตัวเองไปเลย (setViewAllMode(null)) พอปิดรายละเอียดที่เพิ่งเปิดก็เลย
          ต้องกดเปิด "ดูรายการทั้งหมด" ใหม่อีกรอบ — ตามที่ขอ เปลี่ยนให้ป๊อปอัป
          "ดูรายการทั้งหมด" ไม่ปิดตัวเองแล้ว ให้ป๊อปอัปรายละเอียดงานเด้งซ้อนขึ้น
          มาอีกชั้นแทน (ทั้งสองเปิดพร้อมกันได้) พอปิดรายละเอียดงาน ป๊อปอัป "ดู
          รายการทั้งหมด" จะยังอยู่ที่เดิม ไม่ต้องเปิดใหม่ — ต้องวาง
          AllGroupsListModal ไว้ "ก่อน" JobApprovalModal ในโค้ดด้วย (ลำดับ DOM
          หลังกว่า = ซ้อนทับอยู่บนกว่า ทั้งคู่ใช้ z-50 เท่ากัน) ไม่งั้นจะซ้อน
          สลับด้านผิดที่ */}
      {viewAllMode ? (
        <AllGroupsListModal
          title={viewAllMode === "pending" ? "รายการเบิกอะไหล่ที่รออนุมัติ (ทั้งหมด)" : "รายการเบิกอะไหล่ทั้งหมด"}
          groups={viewAllMode === "pending" ? pendingGroups : allGroups}
          pageSize={requestsPageSize}
          repairs={repairs}
          onOpenGroup={(repairId) => setViewingGroupId(repairId)}
          onDeleteJob={viewAllMode === "all" ? setDeleteGroupTarget : undefined}
          onClose={() => setViewAllMode(null)}
        />
      ) : null}

      {viewingGroupId !== null ? (
        <JobApprovalModal
          repairId={viewingGroupId}
          items={viewingGroup?.items || []}
          repairInfo={findRepairInfo(repairs, viewingGroupId)}
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

      {deleteGroupTarget ? (
        <ConfirmDialog
          message={`ต้องการลบรายการเบิกอะไหล่ของ "${deleteGroupTarget.jobLabel}" ทั้งหมด (${deleteGroupTarget.items?.length ?? 0} รายการ) ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
          onConfirm={handleDeleteGroup}
          onCancel={() => setDeleteGroupTarget(null)}
          busy={deletingGroup}
        />
      ) : null}
    </div>
  );
}