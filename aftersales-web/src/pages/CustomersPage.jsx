import React, { useState, useEffect } from "react";
import {
  Plus,
  Search,
  Users,
  Pencil,
  Trash2,
  MapPin,
  Cog,
  Phone,
  Wrench,
  Camera,
  X,
} from "lucide-react";
import { Card, EmptyState, PrimaryButton, Modal, ConfirmDialog, FormField, DateField } from "../components/ui";
import PersonFormFields from "../components/PersonFormFields";
import {
  COLORS,
  formatDateBySetting,
  normalizeSerialNumber,
  isValidSerialNumber,
  SERIAL_NUMBER_FORMAT_ERROR,
} from "../shared/constants";
import { addMonthsClamped } from "../shared/constants";
import useDbList from "../hooks/useDbList";
import { addRow, updateRow, deleteRow, logActivity } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";
import { uploadImage } from "../services/cloudinary";

const EMPTY_FORM = {
  employee_id: "",
  name: "",
  company: "",
  username: "",
  password: "",
  phone: "",
  photo_url: "",
  house_no: "",
  moo: "",
  tambon: "",
  amphoe: "",
  changwat: "",
  postal_code: "",
};

function formatAddress(c) {
  if (!c) return "-";

  const clean = (val, prefixes = []) => {
    if (!val || typeof val !== "string") return "";
    let str = val.trim();
    for (const p of prefixes) {
      if (str.startsWith(p)) {
        str = str.replace(p, "").trim();
      }
    }
    return str;
  };

  const changwatRaw = (c.changwat || "").trim();
  const isBKK =
    changwatRaw.includes("กรุงเทพ") ||
    changwatRaw.toLowerCase().includes("bangkok") ||
    changwatRaw === "กทม" ||
    changwatRaw === "กทม.";

  const tambon = clean(c.tambon, ["ตำบล", "ต.", "ต ", "แขวง"]);
  const amphoe = clean(c.amphoe, ["อำเภอ", "อ.", "อ ", "เขต"]);
  const changwat = clean(c.changwat, ["จังหวัด", "จ.", "จ "]);
  const moo = clean(c.moo, ["หมู่ที่", "หมู่", "ม.", "ม "]);

  const parts = [
    c.house_no ? c.house_no.trim() : "",
    moo ? `หมู่ ${moo}` : "",
    tambon ? (isBKK ? `แขวง${tambon}` : `ตำบล${tambon}`) : "",
    amphoe ? (isBKK ? `เขต${amphoe}` : `อำเภอ${amphoe}`) : "",
    changwat ? (isBKK ? changwat : `จังหวัด${changwat}`) : "",
    c.postal_code ? c.postal_code.trim() : "",
  ].filter(Boolean);

  return parts.length > 0 ? parts.join(" ") : "-";
}

function warrantyStatus(m) {
  if (!m.warranty_start_date || !m.warranty_months) {
    return { label: "ไม่มีข้อมูลประกัน", color: "text-slate-400" };
  }
  const start = new Date(m.warranty_start_date);
  if (isNaN(start.getTime())) {
    return { label: "ไม่มีข้อมูลประกัน", color: "text-slate-400" };
  }
  const end = addMonthsClamped(start, Number(m.warranty_months));
  const daysLeft = Math.ceil((end.getTime() - Date.now()) / (1000 * 60 * 60 * 24));
  if (daysLeft < 0) {
    return { label: `หมดประกันแล้ว (${formatDateBySetting(end)})`, color: "text-red-500" };
  }
  if (daysLeft <= 30) {
    return { label: `ใกล้หมดประกัน (เหลือ ${daysLeft} วัน)`, color: "text-amber-500" };
  }
  return { label: `อยู่ในประกัน (ถึง ${formatDateBySetting(end)})`, color: "text-emerald-500" };
}

function CustomerCard({ customer, machineCount, jobCount, onEdit, onDelete, onViewMachines }) {
  const fullName = `${customer.name || ""} ${customer.surname || ""}`.trim() || customer.username || "ไม่ระบุชื่อ";
  const address = formatAddress(customer);

  return (
    <Card>
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3 min-w-0">
          {customer.photo_url ? (
            <img
              src={customer.photo_url}
              alt={fullName}
              className="w-12 h-12 rounded-full object-cover shrink-0 border border-slate-100"
            />
          ) : (
            <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 font-semibold shrink-0 text-base">
              {fullName?.[0] ?? "?"}
            </div>
          )}
          <div className="min-w-0">
            <p className="text-[11px] text-slate-400 font-medium truncate">@{customer.username}</p>
            <p className="text-sm font-semibold text-slate-800 truncate">{fullName}</p>
            {customer.company ? (
              <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-blue-50 text-blue-600 inline-block truncate max-w-full">
                {customer.company}
              </span>
            ) : null}
          </div>
        </div>

        <div className="flex items-center gap-1 shrink-0">
          <button
            onClick={onDelete}
            title="ลบ"
            className="w-7 h-7 rounded-lg flex items-center justify-center text-red-500 hover:bg-red-50"
          >
            <Trash2 size={14} />
          </button>
        </div>
      </div>

      <div className="space-y-1.5 text-xs text-slate-500 mb-3">
        <p className="flex items-center gap-1.5">
          <Phone size={12} className="shrink-0 text-slate-400" />
          <span>{customer.phone || "-"}</span>
        </p>
        {address !== "-" ? (
          <p className="flex items-start gap-1.5 line-clamp-2">
            <MapPin size={12} className="shrink-0 text-slate-400 mt-0.5" />
            <span>{address}</span>
          </p>
        ) : null}
        <div className="flex items-center gap-4 pt-1 text-slate-600">
          <span className="flex items-center gap-1">
            <Cog size={12} className="text-slate-400" /> {machineCount} เครื่องจักร
          </span>
          <span className="flex items-center gap-1">
            <Wrench size={12} className="text-slate-400" /> {jobCount} งานซ่อม
          </span>
        </div>
      </div>

      <div className="pt-2 border-t border-slate-100 flex items-center justify-between">
        <button
          onClick={onViewMachines}
          className="flex items-center gap-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors"
        >
          <Cog size={13} />
          ดูเครื่องจักร ({machineCount})
        </button>
        <button
          onClick={onEdit}
          className="flex items-center gap-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors"
        >
          <Pencil size={13} />
          แก้ไขข้อมูล
        </button>
      </div>
    </Card>
  );
}

const EMPTY_MACHINE_FORM = {
  label: "",
  model_name: "",
  serial_number: "",
  photo_url: "",
  warranty_start_date: "",
  warranty_months: "",
};

const WARRANTY_MONTH_OPTIONS = [
  { value: "", label: "ไม่ระบุประกัน" },
  { value: "6", label: "6 เดือน" },
  { value: "12", label: "12 เดือน" },
  { value: "24", label: "24 เดือน" },
  { value: "36", label: "36 เดือน" },
];

function MachineListModal({ customer, machines, onClose }) {
  const list = machines.filter((m) => m.customer_username === customer.username);

  const [editingMachine, setEditingMachine] = useState(null);
  const [form, setForm] = useState(EMPTY_MACHINE_FORM);
  const [savingMachine, setSavingMachine] = useState(false);
  const [uploadingPhoto, setUploadingPhoto] = useState(false);
  const [deleteMachineTarget, setDeleteMachineTarget] = useState(null);
  const [deletingMachine, setDeletingMachine] = useState(false);

  function openAddMachine() {
    setForm(EMPTY_MACHINE_FORM);
    setEditingMachine({});
  }

  function openEditMachine(m) {
    setForm({
      label: m.label || "",
      model_name: m.model_name || "",
      serial_number: m.serial_number || "",
      photo_url: m.photo_url || "",
      warranty_start_date: m.warranty_start_date ? String(m.warranty_start_date).slice(0, 10) : "",
      warranty_months: m.warranty_months != null ? String(m.warranty_months) : "",
    });
    setEditingMachine(m);
  }

  async function handlePhotoChange(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingPhoto(true);
    try {
      const url = await uploadImage(file);
      setForm((f) => ({ ...f, photo_url: url }));
    } catch (err) {
      alert("อัปโหลดรูปภาพไม่สำเร็จ: " + (err.message || err));
    } finally {
      setUploadingPhoto(false);
    }
  }

  async function handleSaveMachine() {
    const serial = normalizeSerialNumber(form.serial_number);
    if (!serial) {
      alert("กรุณากรอก Serial Number");
      return;
    }
    // 🐛 [แก้บัค] จุดที่ไม่ตรงกับมือถือ: เดิมที่นี่เช็กแค่ "ไม่ว่าง" ไม่เคย
    // ตรวจรูปแบบ 2-2-4 เลย (ดูคอมเมนต์เต็มที่ isValidSerialNumber ใน
    // shared/constants.js) ทำให้เพิ่มเครื่องจักรผ่านเว็บด้วยเลขที่ไม่ตรง
    // format ได้ แล้วสแกน QR จากแอปมือถือไม่เจอ
    if (!isValidSerialNumber(serial)) {
      alert(SERIAL_NUMBER_FORMAT_ERROR);
      return;
    }
    if (!form.model_name.trim()) {
      alert("กรุณากรอกรุ่นเครื่องจักร");
      return;
    }
    const warrantyMonths = form.warranty_months ? Number(form.warranty_months) : null;
    if (warrantyMonths && !form.warranty_start_date) {
      alert("กรุณาเลือกวันที่เริ่มประกัน");
      return;
    }

    const duplicate = machines.find(
      (m) => (m.serial_number || "").trim().toUpperCase() === serial && m.id !== editingMachine?.id
    );
    if (duplicate) {
      alert("Serial Number นี้ถูกใช้งานแล้วกับเครื่องจักรอื่น");
      return;
    }

    setSavingMachine(true);
    try {
      const startDateIso =
        warrantyMonths && form.warranty_start_date && !isNaN(new Date(form.warranty_start_date).getTime())
          ? new Date(form.warranty_start_date).toISOString()
          : null;

      const payload = {
        label: form.label.trim(),
        model_name: form.model_name.trim(),
        serial_number: serial,
        photo_url: form.photo_url.trim(),
        warranty_start_date: startDateIso,
        warranty_months: warrantyMonths,
      };

      if (editingMachine?.id) {
        await updateRow("machines", editingMachine.id, payload);
      } else {
        await addRow("machines", { ...payload, customer_username: customer.username, status: "พร้อมใช้งาน" });
      }
      setEditingMachine(null);
    } catch (err) {
      console.error("[MachineListModal] save failed:", err);
      alert("บันทึกไม่สำเร็จ: " + (err.message || err));
    } finally {
      setSavingMachine(false);
    }
  }

  async function handleDeleteMachine() {
    if (!deleteMachineTarget) return;
    setDeletingMachine(true);
    try {
      await deleteRow("machines", deleteMachineTarget.id);
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ลบเครื่องจักร",
        target: deleteMachineTarget.model_name || deleteMachineTarget.label || "เครื่องจักร",
      }).catch((err) => console.error("[MachineListModal] log activity failed:", err));
      setDeleteMachineTarget(null);
    } catch (err) {
      console.error("[MachineListModal] delete failed:", err);
    } finally {
      setDeletingMachine(false);
    }
  }

  return (
    <>
      <Modal
        title={`เครื่องจักรของ ${customer.name || customer.username}`}
        onClose={onClose}
        footer={
          <PrimaryButton icon={Plus} onClick={openAddMachine}>
            เพิ่มเครื่องจักร
          </PrimaryButton>
        }
      >
        {list.length === 0 ? (
          <EmptyState icon={Cog} message="ลูกค้ารายนี้ยังไม่มีเครื่องจักรในระบบ" />
        ) : (
          <div className="space-y-3">
            {list.map((m, i) => {
              const title = m.model_name || (m.label ? `เครื่องจักร ${m.label}` : `เครื่องจักร #${m.id ?? i + 1}`);
              const ws = warrantyStatus(m);
              const details = [
                m.label ? `ป้ายชื่อย่อ: ${m.label}` : null,
                m.serial_number ? `S/N: ${m.serial_number}` : null,
              ].filter(Boolean);
              return (
                <div key={m.id ?? i} className="rounded-xl border border-slate-100 p-3">
                  <div className="flex items-center justify-between gap-2">
                    <div className="flex items-center gap-2 min-w-0">
                      {m.photo_url ? (
                        <img src={m.photo_url} alt={title} className="w-8 h-8 rounded-lg object-cover shrink-0" />
                      ) : (
                        <div className="w-8 h-8 rounded-lg bg-slate-100 text-slate-500 flex items-center justify-center shrink-0">
                          <Cog size={14} />
                        </div>
                      )}
                      <p className="text-sm font-medium text-slate-800 truncate">{title}</p>
                    </div>
                    <div className="flex items-center gap-1 shrink-0">
                      <button
                        onClick={() => openEditMachine(m)}
                        className="p-1.5 rounded-lg text-slate-400 hover:text-blue-500 hover:bg-blue-50"
                        title="แก้ไขเครื่องจักร"
                      >
                        <Pencil size={14} />
                      </button>
                      <button
                        onClick={() => setDeleteMachineTarget(m)}
                        className="p-1.5 rounded-lg text-slate-400 hover:text-red-500 hover:bg-red-50"
                        title="ลบเครื่องจักร"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  </div>
                  {details.length > 0 ? (
                    <p className="text-xs text-slate-500 mt-2 pl-10">{details.join(" · ")}</p>
                  ) : null}
                  <p className={`text-xs mt-1 pl-10 ${ws.color}`}>{ws.label}</p>
                </div>
              );
            })}
          </div>
        )}
      </Modal>

      {editingMachine !== null ? (
        <Modal
          title={editingMachine?.id ? "แก้ไขเครื่องจักร" : "เพิ่มเครื่องจักรใหม่"}
          onClose={() => setEditingMachine(null)}
          footer={
            <div className="flex items-center gap-3">
              <button
                onClick={() => setEditingMachine(null)}
                className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50"
              >
                ยกเลิก
              </button>
              <PrimaryButton onClick={handleSaveMachine} disabled={savingMachine || uploadingPhoto}>
                {savingMachine ? "กำลังบันทึก..." : "บันทึก"}
              </PrimaryButton>
            </div>
          }
        >
          <div className="flex items-center gap-4 mb-5 pb-4 border-b border-slate-100">
            <div className="relative">
              {form.photo_url ? (
                <img
                  src={form.photo_url}
                  alt="Machine Preview"
                  className="w-16 h-16 rounded-xl object-cover border-2 border-slate-200"
                />
              ) : (
                <div className="w-16 h-16 rounded-xl bg-slate-100 text-slate-400 flex items-center justify-center border-2 border-slate-200">
                  <Cog size={22} />
                </div>
              )}
              {uploadingPhoto && (
                <div className="absolute inset-0 rounded-xl bg-black/40 flex items-center justify-center text-white text-xs">
                  อัปโหลด...
                </div>
              )}
            </div>
            <div>
              <label className="cursor-pointer inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-blue-600 bg-blue-50 hover:bg-blue-100 transition-colors">
                <Camera size={14} />
                <span>{form.photo_url ? "เปลี่ยนรูปเครื่องจักร" : "อัปโหลดรูปเครื่องจักร"}</span>
                <input
                  type="file"
                  accept="image/*"
                  onChange={handlePhotoChange}
                  disabled={uploadingPhoto}
                  className="hidden"
                />
              </label>
              <p className="text-[11px] text-slate-400 mt-1">ไฟล์รูปภาพ PNG, JPG ขนาดไม่เกิน 5MB</p>
            </div>
          </div>

          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <FormField
              label="รุ่นเครื่องจักร"
              value={form.model_name}
              onChange={(v) => setForm((f) => ({ ...f, model_name: v }))}
              placeholder="เช่น Excavator PC200"
              required
            />
            <FormField
              label="ป้ายชื่อย่อ"
              value={form.label}
              onChange={(v) => setForm((f) => ({ ...f, label: v }))}
              placeholder="เช่น รถแบคโฮ 1"
            />
          </div>
          <FormField
            label="Serial Number"
            value={form.serial_number}
            onChange={(v) => setForm((f) => ({ ...f, serial_number: v }))}
            placeholder="PM260145"
            required
          />

          <div className="pt-2 border-t border-slate-100">
            <p className="text-sm font-semibold text-slate-700 mb-3 mt-3">ข้อมูลประกัน</p>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {/* 🔴 [แก้ไข] ใช้ DateField (ปฏิทินที่วาดเอง) แทน <input type="date">
                  ของเบราว์เซอร์ เพื่อคุมหน้าตาการแสดงผลวันที่ให้เป็น พ.ศ. เสมอ
                  ค่าที่เก็บยังเป็น ISO string เหมือนเดิมทุกประการ */}
              <div>
                <label className="text-sm text-slate-600 mb-2 block font-medium">วันที่เริ่มประกัน</label>
                <DateField
                  value={form.warranty_start_date}
                  onChange={(v) => setForm((f) => ({ ...f, warranty_start_date: v }))}
                />
              </div>
              <div>
                <label className="text-sm text-slate-600 mb-2 block font-medium">ระยะเวลาประกัน</label>
                <select
                  value={form.warranty_months}
                  onChange={(e) => setForm((f) => ({ ...f, warranty_months: e.target.value }))}
                  className="w-full px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                >
                  {WARRANTY_MONTH_OPTIONS.map((opt) => (
                    <option key={opt.value} value={opt.value}>
                      {opt.label}
                    </option>
                  ))}
                </select>
              </div>
            </div>
          </div>
        </Modal>
      ) : null}

      {deleteMachineTarget ? (
        <ConfirmDialog
          message={`ต้องการลบเครื่องจักร "${
            deleteMachineTarget.model_name || deleteMachineTarget.label || "เครื่องจักรนี้"
          }" ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
          onConfirm={handleDeleteMachine}
          onCancel={() => setDeleteMachineTarget(null)}
          busy={deletingMachine}
        />
      ) : null}
    </>
  );
}

export default function CustomersPage({ initialQuery }) {
  const [query, setQuery] = useState(initialQuery || "");
  const { data: customers, loading } = useDbList("customers");
  const { data: machines } = useDbList("machines");
  const { data: repairs } = useDbList("repairs");

  useEffect(() => {
    if (initialQuery) setQuery(initialQuery);
  }, [initialQuery]);

  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [viewingMachinesFor, setViewingMachinesFor] = useState(null);

  const filtered = customers.filter((c) => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    const searchTarget = `${c.name || ""} ${c.surname || ""} ${c.company || ""} ${c.username || ""} ${c.phone || ""}`.toLowerCase();
    return searchTarget.includes(q);
  });

  const summary = [
    { label: "ลูกค้าทั้งหมด", value: customers.length, color: "blue" },
    { label: "เครื่องจักรในระบบ", value: machines.length, color: "orange" },
    { label: "งานแจ้งซ่อมทั้งหมด", value: repairs.length, color: "green" },
  ];

  function openAdd() {
    setForm(EMPTY_FORM);
    setEditing({});
  }

  function openEdit(customer) {
    setForm({
      employee_id: customer.employee_id || "",
      // 🔴 [แก้ไข] เดิมแยกช่อง "ชื่อ" กับ "นามสกุล" — รวมเป็นช่องเดียว
      // "ชื่อ-นามสกุล" ตามที่ขอ ตอนแก้ไขลูกค้าเก่าที่ยังมีข้อมูลแยกอยู่ ก็เอามา
      // ต่อกันให้เป็นค่าเริ่มต้นในช่องเดียว
      name: [customer.name, customer.surname].filter(Boolean).join(" "),
      company: customer.company || "",
      username: customer.username || "",
      password: "",
      phone: customer.phone || "",
      photo_url: customer.photo_url || "",
      house_no: customer.house_no || "",
      moo: customer.moo || "",
      tambon: customer.tambon || "",
      amphoe: customer.amphoe || "",
      changwat: customer.changwat || "",
      postal_code: customer.postal_code || "",
    });
    setEditing(customer);
  }

  async function handleImageChange(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploadingImage(true);
    try {
      const url = await uploadImage(file);
      setForm((f) => ({ ...f, photo_url: url }));
    } catch (err) {
      alert("อัปโหลดรูปภาพไม่สำเร็จ: " + (err.message || err));
    } finally {
      setUploadingImage(false);
    }
  }

  async function handleSave() {
    // 🆕 [ใหม่] เพิ่มช่องรหัสผ่านให้ลูกค้าด้วยตามที่ขอ (เดิมมีแค่ username ไม่มี
    // password) — บังคับกรอกตอนเพิ่มลูกค้าใหม่เหมือนกับฝั่งช่างทุกประการ
    if (!editing?.id && !form.password.trim()) {
      alert("กรุณากรอกรหัสผ่านสำหรับลูกค้าใหม่ ไม่งั้นจะล็อกอินในแอปมือถือไม่ได้");
      return;
    }
    setSaving(true);
    try {
      const payload = {
        employee_id: form.employee_id.trim(),
        // 🔴 [แก้ไข] ช่อง "ชื่อ-นามสกุล" รวมเป็นช่องเดียวแล้ว — เก็บทั้งหมดลง
        // "name" ตามที่กรอก ส่วน "surname" เคลียร์ทิ้ง (ของเก่าที่เคยแยกไว้จะถูก
        // รวมมาแสดงในช่องเดียวนี้ตั้งแต่ openEdit แล้ว)
        name: form.name.trim(),
        surname: "",
        company: form.company.trim(),
        username: form.username.trim(),
        phone: form.phone.trim(),
        photo_url: form.photo_url.trim(),
        house_no: form.house_no.trim(),
        moo: form.moo.trim(),
        tambon: form.tambon.trim(),
        amphoe: form.amphoe.trim(),
        changwat: form.changwat.trim(),
        postal_code: form.postal_code.trim(),
      };
      if (form.password.trim()) payload.password = form.password.trim();

      if (editing?.id) {
        await updateRow("customers", editing.id, payload);
      } else {
        await addRow("customers", { ...payload, password: form.password.trim() });
      }
      setEditing(null);
    } catch (err) {
      console.error("[CustomersPage] save failed:", err);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRow("customers", deleteTarget.id);
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ลบลูกค้า",
        target: [deleteTarget.name, deleteTarget.surname].filter(Boolean).join(" ") || deleteTarget.username,
      }).catch((err) => console.error("[CustomersPage] log activity failed:", err));
      setDeleteTarget(null);
    } catch (err) {
      console.error("[CustomersPage] delete failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-5">
        <div className="relative max-w-sm flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="ค้นหาชื่อ / บริษัท / เบอร์โทร..."
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
        <PrimaryButton icon={Plus} onClick={openAdd}>เพิ่มลูกค้าใหม่</PrimaryButton>
      </div>

      <div className="flex flex-wrap gap-4 mb-5">
        {summary.map((s) => {
          const c = COLORS[s.color];
          return (
            <div key={s.label} className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[160px]">
              <div className="flex items-center gap-2 mb-2">
                <span className={`w-2.5 h-2.5 rounded-full ${c.dot}`} />
                <span className="text-xs text-slate-500">{s.label}</span>
              </div>
              <span className="text-xl font-semibold text-slate-900">{s.value}</span>
            </div>
          );
        })}
      </div>

      {loading ? (
        <Card>
          <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
        </Card>
      ) : filtered.length === 0 ? (
        <Card>
          <EmptyState icon={Users} message={query ? "ไม่พบลูกค้าที่ค้นหา" : "ยังไม่มีลูกค้าในระบบ"} />
        </Card>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((c) => {
            const machineCount = machines.filter((m) => m.customer_username === c.username).length;
            const jobCount = repairs.filter((r) => r.customer_username === c.username).length;
            return (
              <CustomerCard
                key={c.id}
                customer={c}
                machineCount={machineCount}
                jobCount={jobCount}
                onEdit={() => openEdit(c)}
                onDelete={() => setDeleteTarget(c)}
                onViewMachines={() => setViewingMachinesFor(c)}
              />
            );
          })}
        </div>
      )}

      {editing !== null && (
        <Modal
          title={editing?.id ? "แก้ไขข้อมูลลูกค้า" : "เพิ่มลูกค้าใหม่"}
          onClose={() => setEditing(null)}
          wide
          footer={
            <div className="w-full flex items-center justify-between">
              {editing?.id ? (
                <button
                  onClick={() => setViewingMachinesFor(editing)}
                  className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-medium text-slate-600 bg-slate-50 hover:bg-slate-100"
                >
                  <Cog size={14} />
                  ดูเครื่องจักร
                </button>
              ) : (
                <span />
              )}
              <div className="flex items-center gap-3">
                <button
                  onClick={() => setEditing(null)}
                  className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50"
                >
                  ยกเลิก
                </button>
                <PrimaryButton onClick={handleSave} disabled={saving || uploadingImage}>
                  {saving ? "กำลังบันทึก..." : "บันทึก"}
                </PrimaryButton>
              </div>
            </div>
          }
        >
          <PersonFormFields
            photoUrl={form.photo_url}
            initials={form.name?.[0] || "?"}
            uploadingImage={uploadingImage}
            onImageChange={handleImageChange}
            codeLabel="รหัสลูกค้า"
            codePlaceholder="เช่น C-001"
            code={form.employee_id}
            onCodeChange={(v) => setForm((f) => ({ ...f, employee_id: v }))}
            name={form.name}
            onNameChange={(v) => setForm((f) => ({ ...f, name: v }))}
            namePlaceholder="เช่น สมชาย ใจดี"
            username={form.username}
            onUsernameChange={(v) => setForm((f) => ({ ...f, username: v }))}
            currentPassword={editing?.id ? editing.password || "" : undefined}
            password={form.password}
            onPasswordChange={(v) => setForm((f) => ({ ...f, password: v }))}
            passwordLabel={editing?.id ? "รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)" : "รหัสผ่าน"}
            passwordRequired={!editing?.id}
            phone={form.phone}
            onPhoneChange={(v) => setForm((f) => ({ ...f, phone: v }))}
            showCompany
            company={form.company}
            onCompanyChange={(v) => setForm((f) => ({ ...f, company: v }))}
            houseNo={form.house_no}
            onHouseNoChange={(v) => setForm((f) => ({ ...f, house_no: v }))}
            moo={form.moo}
            onMooChange={(v) => setForm((f) => ({ ...f, moo: v }))}
            postalCode={form.postal_code}
            onPostalCodeChange={(v) => setForm((f) => ({ ...f, postal_code: v }))}
            tambon={form.tambon}
            amphoe={form.amphoe}
            changwat={form.changwat}
            onAddressChange={({ changwat, amphoe, tambon, postalCode }) =>
              setForm((f) => ({ ...f, changwat, amphoe, tambon, postal_code: postalCode }))
            }
          />
        </Modal>
      )}

      {viewingMachinesFor ? (
        <MachineListModal
          customer={viewingMachinesFor}
          machines={machines}
          onClose={() => setViewingMachinesFor(null)}
        />
      ) : null}

      {deleteTarget ? (
        <ConfirmDialog
          message={`ต้องการลบลูกค้า "${deleteTarget.name} ${deleteTarget.surname || ""}" ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          busy={deleting}
        />
      ) : null}
    </div>
  );
}