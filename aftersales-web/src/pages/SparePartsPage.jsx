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

function PendingRequestRow({ request, parts }) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  // 🔴 [แก้ไข] เดิมกด "อนุมัติ" แล้วแค่เปลี่ยนสถานะคำขอ ไม่ได้ตัดสต๊อกจริงเลย —
  // ตอนนี้ถ้าอนุมัติ จะหาอะไหล่ที่ตรงกับคำขอ (จับคู่ด้วย part_id) แล้วลดจำนวน
  // คงเหลือในคลังลงตามจำนวนที่ขอเบิกให้อัตโนมัติ (ไม่ต่ำกว่า 0)
  async function handle(status) {
    setBusy(true);
    setError("");
    try {
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
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: status === "อนุมัติแล้ว" ? "อนุมัติคำขอเบิกอะไหล่" : "ปฏิเสธคำขอเบิกอะไหล่",
        target: `${request.part_name || "-"} x${request.quantity ?? 0} (ช่าง ${request.technician_username || "-"})`,
      }).catch((err) => console.error("[SparePartsPage] log activity failed:", err));
    } catch (err) {
      console.error("[SparePartsPage] update part request failed:", err);
      setError("ดำเนินการไม่สำเร็จ กรุณาลองใหม่");
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex items-center justify-between py-3 border-b border-slate-50 last:border-0">
      <div className="min-w-0">
        <p className="text-sm font-medium text-slate-800">
          {request.part_name || "-"} {request.part_code ? `(${request.part_code})` : ""}
        </p>
        <p className="text-xs text-slate-500 mt-0.5">
          ช่าง {request.technician_username || "-"} ขอเบิก {request.quantity ?? 0} ชิ้น
          {request.repair_id ? ` · งาน #${request.repair_id}` : ""}
        </p>
        {request.note ? <p className="text-xs text-slate-400 mt-0.5">หมายเหตุ: {request.note}</p> : null}
        {error ? <p className="text-xs text-red-500 mt-0.5">{error}</p> : null}
      </div>
      {/* 🎨 ปุ่มอนุมัติ = เขียว (emerald) / ปุ่มปฏิเสธ = แดง (red) — ใช้สีตรงข้ามกัน
          ชัดเจนเพื่อลดโอกาสกดผิดฝั่ง */}
      <div className="flex items-center gap-2 shrink-0">
        <button
          onClick={() => handle("อนุมัติแล้ว")}
          disabled={busy}
          className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-600 text-xs font-medium hover:bg-emerald-100 disabled:opacity-50"
        >
          <Check size={13} /> อนุมัติ
        </button>
        <button
          onClick={() => handle("ปฏิเสธ")}
          disabled={busy}
          className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-red-50 text-red-600 text-xs font-medium hover:bg-red-100 disabled:opacity-50"
        >
          <X size={13} /> ปฏิเสธ
        </button>
      </div>
    </div>
  );
}

const EMPTY_FORM = { part_code: "", part_name: "", price: "", stock: "", photo_url: "" };

export default function SparePartsPage({ initialQuery }) {
  const [query, setQuery] = useState(initialQuery || "");
  const { data: parts, loading: loadingParts } = useDbList("spare_parts");
  const { data: partRequests, loading: loadingRequests } = useDbList("part_requests");

  const [editing, setEditing] = useState(null); // null = ปิด, {} = เพิ่มใหม่, {id,...} = แก้ไข
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
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
        <h3 className="text-sm font-semibold text-slate-800 mb-4">คำขอเบิกอะไหล่ที่รออนุมัติ</h3>
        {loadingRequests ? (
          <p className="text-xs text-slate-400 text-center py-6">กำลังโหลดข้อมูล...</p>
        ) : pendingRequests.length === 0 ? (
          <p className="text-xs text-slate-400 text-center py-6">ยังไม่มีคำขอเบิกอะไหล่ที่รออนุมัติ</p>
        ) : (
          <div>
            {pendingRequests.map((r) => (
              <PendingRequestRow key={r.id} request={r} parts={parts} />
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
                    <tr key={p.id} className="border-b border-slate-50 last:border-0">
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
                      <td className="py-2.5">
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
