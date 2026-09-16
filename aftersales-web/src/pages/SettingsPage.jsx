import React, { useState, useEffect, useRef } from "react";
import {
  Plus,
  Pencil,
  Trash2,
  ShieldCheck,
  Check,
  Bell,
  User,
  Settings2,
  Lock,
  Users,
  UserCog,
  Wrench,
  Database,
  Camera,
  Phone,
  Mail,
  Loader2,
} from "lucide-react";
import { Card, PrimaryButton, Modal, ConfirmDialog, FormField, EmptyState } from "../components/ui";
import useDbList from "../hooks/useDbList";
import { addRow, updateRow, deleteRow, getWebSettings, saveWebSettings, getPersonalSettings, savePersonalSettings } from "../services/firebaseDb";
import { uploadImage } from "../services/cloudinary";
import { getSessionAdmin, isMainAdmin } from "../services/session";
import { applyTheme } from "../theme";

function Toggle({ checked, onChange, disabled }) {
  return (
    <button
      onClick={() => !disabled && onChange(!checked)}
      disabled={disabled}
      className={`w-11 h-6 rounded-full transition-colors relative shrink-0 ${
        checked ? "bg-blue-500" : "bg-slate-200"
      } ${disabled ? "opacity-40 cursor-not-allowed" : ""}`}
    >
      <span
        className={`absolute left-0.5 top-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform ${
          checked ? "translate-x-5" : "translate-x-0"
        }`}
      />
    </button>
  );
}

function SelectField({ label, value, onChange, options }) {
  return (
    <div>
      <label className="text-xs text-slate-500 mb-1.5 block">{label}</label>
      <select
        value={value ?? ""}
        onChange={(e) => onChange(e.target.value)}
        className="w-full px-3 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
      >
        {options.map((opt) => (
          <option key={opt.value} value={opt.value}>
            {opt.label}
          </option>
        ))}
      </select>
    </div>
  );
}

const EMPTY_FORM = {
  admin_name: "",
  username: "",
  phone: "",
  email: "",
  password: "",
  photo_url: "",
  admin_type: "general",
};

function AdminAccountsSection() {
  const { data: admins, loading } = useDbList("admins");
  const currentAdmin = getSessionAdmin();
  const currentUsername = currentAdmin?.username || "";
  const isSuperAdmin = isMainAdmin(currentAdmin);

  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);
  const [formError, setFormError] = useState("");

  function openAdd() {
    setFormError("");
    setForm(EMPTY_FORM);
    setEditing({});
  }

  function openEdit(admin) {
    setForm({
      admin_name: admin.admin_name || "",
      username: admin.username || "",
      phone: admin.phone || "",
      email: admin.email || "",
      password: "",
      photo_url: admin.photo_url || "",
      admin_type: admin.admin_type || "main",
    });
    setFormError("");
    setEditing(admin);
  }

  async function handlePickPhoto(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const url = await uploadImage(file);
      setForm((f) => ({ ...f, photo_url: url }));
    } catch (err) {
      console.error("[SettingsPage] upload admin photo failed:", err);
    } finally {
      setUploading(false);
    }
  }

  async function handleSave() {
    const email = form.email.trim();
    if (email && (!email.includes("@") || !email.includes("."))) {
      setFormError("รูปแบบอีเมลไม่ถูกต้อง");
      return;
    }
    setFormError("");
    setSaving(true);
    try {
      const payload = {
        admin_name: form.admin_name.trim(),
        username: form.username.trim(),
        phone: form.phone.trim(),
        email,
        photo_url: form.photo_url || "",
        admin_type: form.admin_type || "general",
      };
      if (form.password.trim()) payload.password = form.password.trim();

      if (editing?.id) {
        await updateRow("admins", editing.id, payload);
      } else {
        await addRow("admins", { ...payload, password: form.password.trim() });
      }
      setEditing(null);
    } catch (err) {
      console.error("[SettingsPage] save admin failed:", err);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRow("admins", deleteTarget.id);
      setDeleteTarget(null);
    } catch (err) {
      console.error("[SettingsPage] delete admin failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <>
      {(() => {
        const me = admins.find((a) => a.username === currentUsername);
        if (!me) return null;
        const myType = me.admin_type || "main";
        return (
          <Card className="mb-4">
            <div className="flex items-center justify-between gap-3">
              <div className="flex items-center gap-3 min-w-0">
                <div className="w-12 h-12 rounded-full bg-blue-500 text-white flex items-center justify-center text-lg font-semibold shrink-0 overflow-hidden">
                  {me.photo_url ? (
                    <img src={me.photo_url} alt={me.admin_name || me.username} className="w-full h-full object-cover" />
                  ) : (
                    (me.admin_name || me.username || "?")[0]
                  )}
                </div>
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="text-sm font-semibold text-slate-800 truncate">{me.admin_name || "ไม่ระบุชื่อ"}</p>
                    <span
                      className={`text-[10px] font-medium px-2 py-0.5 rounded-full ${
                        myType === "main" ? "bg-blue-50 text-blue-600" : "bg-slate-100 text-slate-500"
                      }`}
                    >
                      {myType === "main" ? "แอดมินหลัก" : "แอดมินทั่วไป"}
                    </span>
                  </div>
                  <p className="text-xs text-slate-400 truncate">
                    @{me.username} {me.phone ? `· ${me.phone}` : ""}
                  </p>
                </div>
              </div>
              <button
                onClick={() => openEdit(me)}
                className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-50 text-blue-600 text-xs font-medium hover:bg-blue-100 shrink-0"
              >
                <Pencil size={13} /> แก้ไขโปรไฟล์
              </button>
            </div>
          </Card>
        );
      })()}

      <Card>
        <div className="flex items-center justify-between mb-4">
          <h3 className="text-sm font-semibold text-slate-800">บัญชีผู้ดูแลระบบ</h3>
          {isSuperAdmin && (
            <button
              onClick={openAdd}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-50 text-blue-600 text-xs font-medium hover:bg-blue-100"
            >
              <Plus size={13} /> เพิ่มแอดมิน
            </button>
          )}
        </div>

        {loading ? (
          <p className="text-xs text-slate-400 text-center py-6">กำลังโหลดข้อมูล...</p>
        ) : admins.length === 0 ? (
          <EmptyState icon={ShieldCheck} message="ยังไม่มีบัญชีผู้ดูแลระบบในระบบ" />
        ) : (
          // 🔴 [แก้ไข] เปลี่ยนจากลิสต์แถวเรียงต่อกัน (divide-y) เป็นการ์ดกริดแบบ
          // เดียวกับหน้าลูกค้า/ช่าง — ไอคอนดินสอมุมขวาบนเอาออก เหลือแค่ปุ่มลบ
          // (ตามสิทธิ์ isSuperAdmin เดิม) ส่วนปุ่มแก้ไขย้ายไปเป็นปุ่ม "แก้ไขข้อมูล"
          // ที่แถบท้ายการ์ด (ยังเช็คสิทธิ์ isSuperAdmin || เป็นบัญชีตัวเองเหมือนเดิม)
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            {admins.map((a) => {
              const aType = a.admin_type || "main";
              const canEdit = isSuperAdmin || a.username === currentUsername;
              const canDelete = isSuperAdmin && a.username !== currentUsername;
              return (
                <Card key={a.id}>
                  <div className="flex items-start justify-between mb-3">
                    <div className="flex items-center gap-3 min-w-0">
                      {a.photo_url ? (
                        <img
                          src={a.photo_url}
                          alt={a.admin_name || a.username}
                          className="w-12 h-12 rounded-full object-cover shrink-0 border border-slate-100"
                        />
                      ) : (
                        <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 font-semibold shrink-0 text-base">
                          {(a.admin_name || a.username || "?")[0]}
                        </div>
                      )}
                      <div className="min-w-0">
                        <p className="text-[11px] text-slate-400 font-medium truncate">@{a.username}</p>
                        <p className="text-sm font-semibold text-slate-800 truncate">
                          {a.admin_name || "ไม่ระบุชื่อ"}
                        </p>
                        <div className="flex items-center gap-1.5 mt-0.5">
                          <span
                            className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${
                              aType === "main" ? "bg-blue-50 text-blue-600" : "bg-slate-100 text-slate-500"
                            }`}
                          >
                            {aType === "main" ? "แอดมินหลัก" : "แอดมินทั่วไป"}
                          </span>
                          {a.username === currentUsername ? (
                            <span className="text-[11px] font-medium px-2 py-0.5 rounded-full bg-emerald-50 text-emerald-600 inline-block">
                              คุณ
                            </span>
                          ) : null}
                        </div>
                      </div>
                    </div>
                    {canDelete ? (
                      <div className="flex items-center gap-1 shrink-0">
                        <button onClick={() => setDeleteTarget(a)} title="ลบ" className="w-7 h-7 rounded-lg flex items-center justify-center text-red-500 hover:bg-red-50">
                          <Trash2 size={14} />
                        </button>
                      </div>
                    ) : null}
                  </div>
                  <div className="space-y-2 text-xs text-slate-500 mb-3">
                    <p className="flex items-center gap-1.5">
                      <Phone size={12} className="shrink-0 text-slate-400" />
                      <span>{a.phone || "-"}</span>
                    </p>
                    <p className="flex items-center gap-1.5">
                      <Mail size={12} className="shrink-0 text-slate-400" />
                      <span className="truncate">{a.email || "ยังไม่ได้ตั้งอีเมล"}</span>
                    </p>
                    <p className="flex items-center gap-1.5">
                      <ShieldCheck size={12} className="shrink-0 text-slate-400" />
                      <span>{aType === "main" ? "สิทธิ์การเข้าถึงระบบเต็มรูปแบบ" : "สิทธิ์ดูแลงานซ่อมทั่วไป"}</span>
                    </p>
                  </div>
                  {canEdit ? (
                    <div className="pt-2 border-t border-slate-100 flex justify-end">
                      <button
                        onClick={() => openEdit(a)}
                        className="flex items-center gap-1.5 text-xs font-medium text-blue-600 hover:text-blue-700 bg-blue-50 hover:bg-blue-100 px-3 py-1.5 rounded-lg transition-colors"
                      >
                        <Pencil size={13} />
                        แก้ไขข้อมูล
                      </button>
                    </div>
                  ) : null}
                </Card>
              );
            })}
          </div>
        )}

        {editing !== null && (
          <Modal
            title={editing?.id ? "แก้ไขบัญชีแอดมิน" : "เพิ่มแอดมินใหม่"}
            onClose={() => setEditing(null)}
            wide
            footer={
              <>
                <button
                  onClick={() => setEditing(null)}
                  className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50"
                >
                  ยกเลิก
                </button>
                <PrimaryButton onClick={handleSave} disabled={saving || uploading}>
                  {saving ? "กำลังบันทึก..." : "บันทึก"}
                </PrimaryButton>
              </>
            }
          >
            {/* 🔴 [แก้ไข] บล็อกรูปโปรไฟล์ — ปรับให้เหมือนกับของลูกค้า/ช่างเป๊ะ ๆ:
                รูปวงกลม 16x16 มีเส้นขอบ border-2, มีเส้นคั่น border-b ด้านล่าง,
                ปุ่มอัปโหลดเป็น pill สีฟ้า (Camera icon) พร้อมข้อความบอกชนิด/ขนาดไฟล์ */}
            <div className="flex items-center gap-4 mb-5 pb-4 border-b border-slate-100">
              <div className="relative">
                {form.photo_url ? (
                  <img
                    src={form.photo_url}
                    alt="Profile Preview"
                    className="w-16 h-16 rounded-full object-cover border-2 border-slate-200"
                  />
                ) : (
                  <div className="w-16 h-16 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center text-xl font-semibold border-2 border-slate-200">
                    {form.admin_name?.[0] || "?"}
                  </div>
                )}
                {uploading && (
                  <div className="absolute inset-0 rounded-full bg-black/40 flex items-center justify-center text-white text-xs">
                    อัปโหลด...
                  </div>
                )}
              </div>
              <div>
                <label className="cursor-pointer inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-blue-600 bg-blue-50 hover:bg-blue-100 transition-colors">
                  <Camera size={14} />
                  <span>{form.photo_url ? "เปลี่ยนรูปโปรไฟล์" : "อัปโหลดรูปโปรไฟล์"}</span>
                  <input
                    type="file"
                    accept="image/*"
                    onChange={handlePickPhoto}
                    disabled={uploading}
                    className="hidden"
                  />
                </label>
                <p className="text-[11px] text-slate-400 mt-1">ไฟล์รูปภาพ PNG, JPG ขนาดไม่เกิน 5MB</p>
              </div>
            </div>

            {isSuperAdmin && (
              <div className="mb-4">
                <label className="text-xs text-slate-500 mb-1.5 block">
                  ระดับผู้ดูแลระบบ <span className="text-red-500">*</span>
                </label>
                <select
                  value={form.admin_type}
                  onChange={(e) => setForm((f) => ({ ...f, admin_type: e.target.value }))}
                  className="w-full px-3 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
                >
                  <option value="general">แอดมินทั่วไป (ดูแลงานซ่อมทั่วไป)</option>
                  <option value="main">แอดมินหลัก (จัดการสิทธิ์, มอบหมายงาน, ลบบัญชี)</option>
                </select>
              </div>
            )}

            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                label="ชื่อ-นามสกุล"
                value={form.admin_name}
                onChange={(v) => setForm((f) => ({ ...f, admin_name: v }))}
                placeholder="ชื่อที่แสดงในระบบ"
                required
              />
              <FormField
                label="เบอร์โทร"
                value={form.phone}
                onChange={(v) => setForm((f) => ({ ...f, phone: v }))}
                placeholder="0X-XXX-XXXX"
              />
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <FormField
                label="ชื่อผู้ใช้ (username)"
                value={form.username}
                onChange={(v) => setForm((f) => ({ ...f, username: v }))}
                placeholder="สำหรับล็อกอิน"
                required
              />
              <FormField
                label={editing?.id ? "รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)" : "รหัสผ่าน"}
                type="password"
                value={form.password}
                onChange={(v) => setForm((f) => ({ ...f, password: v }))}
                placeholder="••••••••"
                required={!editing?.id}
              />
            </div>
            <div className="grid grid-cols-1 gap-4 mt-4">
              <FormField
                label="อีเมล"
                type="email"
                value={form.email}
                onChange={(v) => setForm((f) => ({ ...f, email: v }))}
                placeholder="สำหรับรับรหัส OTP ยืนยันตัวตน (2FA)"
              />
              <p className="text-[11px] text-slate-400 -mt-3">
                จำเป็นถ้าต้องการเปิดใช้ "การยืนยันตัวตนสองขั้นตอน (2FA)" ที่หน้าตั้งค่า — ระบบจะส่งรหัส
                OTP มาที่อีเมลนี้ทุกครั้งที่เข้าสู่ระบบ
              </p>
            </div>
            {formError ? <p className="text-xs text-red-500 mt-3">{formError}</p> : null}
          </Modal>
        )}

        {deleteTarget ? (
          <ConfirmDialog
            message={`ต้องการลบบัญชีแอดมิน "${deleteTarget.admin_name}" ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
            onConfirm={handleDelete}
            onCancel={() => setDeleteTarget(null)}
            busy={deleting}
          />
        ) : null}
      </Card>
    </>
  );
}

const DEFAULT_SETTINGS = {
  notifyChat: true,
  notifyJob: true,
  notifyOverdue: true,
  notifyLowStock: true,
  notifyPaymentOverdue: true,
  notifyWarranty: true,
  notifyStaleJob: true,
  notifyDailyDigest: true,
  language: "th",
  itemsPerPageDashboard: "10",
  itemsPerPageJobs: "20",
  itemsPerPageParts: "20",
  itemsPerPageFinance: "20",
  itemsPerPageNotifications: "20",
  openTime: "08:00",
  closeTime: "17:00",
  weeklyOffDays: ["sun"],
  allowMultiDeviceLogin: true,
  notifyEmailChannel: false,
  notifySmsChannel: false,
  notifyToastPopup: true,
  notifyDesktopPopup: true,
  currency: "thb",
  theme: "light",
  lunchBreakStart: "12:00",
  lunchBreakEnd: "13:00",
  specialHolidays: [],
  enable2FA: false,
  notifyNewLogin: true,
};

// 🆕 [ใหม่] คีย์ที่นับเป็น "การตั้งค่าส่วนตัว" ของแต่ละแอดมิน (แยกกันคนละคน
// ไม่ปนกัน) ตามที่ผู้ใช้แจ้งว่าเดิมแอดมินคนหนึ่งเปลี่ยนธีมมืดแล้วกระทบกับทุกคน
// เพราะอ่านค่าเดียวกันหมด — คีย์ที่เหลือทั้งหมดใน DEFAULT_SETTINGS (ประเภท
// แจ้งเตือนที่ระบบจะสร้าง ฯลฯ) ยังคงเป็นค่ารวมของทั้งบริษัทเหมือนเดิม เพราะไม่มี
// ความหมายที่จะแยกเป็นรายคน
const PERSONAL_SETTING_KEYS = [
  "language",
  "itemsPerPageDashboard",
  "itemsPerPageJobs",
  "itemsPerPageParts",
  "itemsPerPageFinance",
  "itemsPerPageNotifications",
  "currency",
  "theme",
  "notifyToastPopup",
  "notifyDesktopPopup",
  // 🔴 [แก้ไข] ตามที่ผู้ใช้แจ้ง — เดิม enable2FA อยู่ใน web_settings (ค่ารวม
  // ทั้งบริษัท) มีผลบังคับทุกบัญชีแอดมินพร้อมกัน ทั้งที่ควรเป็นค่าที่แอดมิน
  // แต่ละคนเปิด/ปิดของตัวเองได้อิสระ (เหมือนธีมสี/จำนวนรายการต่อหน้า) จึงย้าย
  // มาเก็บที่ web_settings_personal/{username} แทน — ฝั่ง Worker (index.js)
  // ก็ต้องอ่านจาก path ส่วนตัวของบัญชีที่ล็อกอินตอนนั้นด้วยเช่นกัน (ดูคอมเมนต์
  // ที่ handleLogin() ฝั่ง Worker)
  "enable2FA",
  // 🆕 [ใหม่] ย้าย "อนุญาตล็อกอินพร้อมกันหลายอุปกรณ์" และ "แจ้งเตือนเมื่อมีการ
  // เข้าสู่ระบบใหม่" มาเป็นค่าส่วนตัวเช่นเดียวกับ 2FA (คนละคนคนละค่า ไม่กระทบ
  // กัน) และทำให้ทำงานจริงแล้ว — ฝั่ง firebaseDb.js/session.js เช็คคีย์นี้จาก
  // web_settings_personal/{username} ของบัญชีที่ล็อกอินอยู่โดยตรง (ดู
  // recordAdminLoginDevice + useSessionGuard)
  "allowMultiDeviceLogin",
  "notifyNewLogin",
];

function SystemInfoCard({ settings }) {
  const { data: admins } = useDbList("admins");
  const { data: customers } = useDbList("customers");
  const { data: technicians } = useDbList("technicians");
  const { data: repairs } = useDbList("repairs");

  const stats = [
    { icon: User, label: "แอดมิน", value: admins.length, color: "text-blue-500 bg-blue-50" },
    { icon: Users, label: "ลูกค้า", value: customers.length, color: "text-emerald-500 bg-emerald-50" },
    { icon: UserCog, label: "ช่างเทคนิค", value: technicians.length, color: "text-orange-500 bg-orange-50" },
    { icon: Wrench, label: "งานซ่อมทั้งหมด", value: repairs.length, color: "text-violet-500 bg-violet-50" },
  ];

  const updatedLabel = settings?.updatedAt
    ? new Date(settings.updatedAt).toLocaleString("th-TH", {
        day: "numeric",
        month: "short",
        year: "numeric",
        hour: "2-digit",
        minute: "2-digit",
      })
    : "ยังไม่เคยบันทึก";

  return (
    <Card className="mt-4">
      <div className="flex items-center gap-2 mb-4">
        <Database size={16} className="text-slate-400" />
        <h3 className="text-sm font-semibold text-slate-800">ข้อมูลระบบ</h3>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-4">
        {stats.map((s) => (
          <div key={s.label} className="rounded-xl bg-slate-50 px-3 py-3">
            <div className={`w-7 h-7 rounded-lg flex items-center justify-center mb-2 ${s.color}`}>
              <s.icon size={14} />
            </div>
            <p className="text-lg font-semibold text-slate-800">{s.value}</p>
            <p className="text-[11px] text-slate-400">{s.label}</p>
          </div>
        ))}
      </div>
      <p className="text-xs text-slate-400 pt-3 border-t border-slate-100">
        อัปเดตการตั้งค่าล่าสุด: {updatedLabel}
      </p>
    </Card>
  );
}

export default function SettingsPage() {
  const [settings, setSettings] = useState(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);
  // 🔴 [แก้ไข] ตามที่ขอ — เปลี่ยนจาก "แก้แล้วต้องกดปุ่มบันทึกเอง" มาเป็น
  // "บันทึกให้อัตโนมัติ" แทน ไม่มีปุ่มบันทึกอีกต่อไป เปลี่ยนค่าอะไรก็จะเซฟให้
  // เองหลังหยุดแก้ไปสักครู่ (debounce กันไม่ให้ยิงเขียน Firebase รัวๆ ตอนพิมพ์
  // ข้อความยาวๆ อย่างชื่อบริษัท) — saveStatus ใช้โชว์สถานะแทนปุ่มเดิม
  const [saveStatus, setSaveStatus] = useState("idle"); // idle | saving | saved | error
  const [saveError, setSaveError] = useState("");
  // ตอนโหลดค่าครั้งแรกเสร็จ setSettings จะทำให้ effect ด้านล่างเห็นว่า settings
  // เปลี่ยน (เปลี่ยนจากค่าเริ่มต้นเป็นค่าที่โหลดมา) ทั้งที่ไม่ใช่การแก้ไขของ
  // ผู้ใช้จริงๆ เลย ใช้ ref นี้กันไม่ให้รอบแรกหลังโหลดเสร็จไปเข้าเงื่อนไข
  // auto-save โดยไม่ตั้งใจ
  const skipNextAutoSaveRef = useRef(true);
  const [lastSavedAt, setLastSavedAt] = useState(null);
  // 🆕 [ใหม่] ใช้เช็คว่าแอดมินที่ล็อกอินอยู่ตอนนี้มีอีเมลบันทึกไว้แล้วหรือยัง —
  // ถ้ายังไม่มี ต้องกันไม่ให้เปิด 2FA ของตัวเอง เพราะไม่มีที่ให้ส่ง OTP ไปหา
  const { data: adminsForEmailCheck } = useDbList("admins");
  const currentAdminEmail = adminsForEmailCheck.find(
    (a) => a.username === getSessionAdmin()?.username
  )?.email;

  useEffect(() => {
    let mounted = true;
    // 🔴 [แก้ไข] โหลดค่าตั้งค่าส่วนตัว (ธีม/จำนวนรายการ/รูปแบบวันที่ ฯลฯ) จาก
    // path เฉพาะของแอดมินคนที่ล็อกอินอยู่ (getPersonalSettings) แยกจากค่ารวม
    // ของบริษัท (getWebSettings) แล้วเอามารวมเป็น state ก้อนเดียวเหมือนเดิม
    // เพื่อไม่ต้องแก้ onChange ของทุกช่องใน UI ด้านล่าง — ตอนบันทึกค่อยแยกกลับ
    // ไปคนละ path ตาม PERSONAL_SETTING_KEYS อีกที (ดู useEffect auto-save)
    const username = getSessionAdmin()?.username;
    Promise.all([getWebSettings(), getPersonalSettings(username)]).then(([shared, personal]) => {
      if (!mounted) return;
      // 🐛 [แก้ไข] บั๊กสำคัญ: ถ้าคีย์ไหนเคยถูกบันทึกไว้ที่ "web_settings" (ค่า
      // รวมเก่า) มาก่อนที่จะย้ายมาเป็นค่าส่วนตัว (เช่น enable2FA) ค่าเก่าที่
      // ค้างอยู่จะโดน merge ทับ DEFAULT_SETTINGS ก่อนอยู่ดี ทำให้ UI โชว์ว่า
      // "เปิดอยู่" ทั้งที่ยังไม่เคยมีการบันทึกค่าไปยัง path ส่วนตัวจริงๆ เลยสัก
      // ครั้ง (auto-save ด้านล่างจะไม่ยิงเพราะ state ตอนโหลดไม่ถือว่าเป็นการ
      // แก้ไขของผู้ใช้) ผลคือ Worker ที่อ่านจาก web_settings_personal ตอน
      // login จะเห็นว่ายังไม่ได้เปิดจริง — ต้องกรองคีย์ที่เป็น "ส่วนตัว" ออก
      // จากก้อน shared ก่อนเสมอ ไม่ให้ค่าเก่าที่ตกค้างมามีผลอีกต่อไป
      const cleanedShared = { ...shared };
      PERSONAL_SETTING_KEYS.forEach((key) => delete cleanedShared[key]);
      setSettings({ ...DEFAULT_SETTINGS, ...cleanedShared, ...personal });
      setLastSavedAt(shared?.updatedAt || null);
      setLoading(false);
    });
    return () => {
      mounted = false;
    };
  }, []);

  // 🆕 บันทึกอัตโนมัติ — ทำงานทุกครั้งที่ settings เปลี่ยน (ยกเว้นรอบแรกหลัง
  // โหลดข้อมูลเสร็จ ดู skipNextAutoSaveRef ด้านบน) หน่วงไว้ 700ms หลังหยุดแก้
  // ก่อนค่อยยิงเขียนจริง กันไม่ให้เขียน Firebase รัวๆ ระหว่างพิมพ์
  useEffect(() => {
    if (loading) return;
    if (skipNextAutoSaveRef.current) {
      skipNextAutoSaveRef.current = false;
      return;
    }
    setSaveStatus("saving");
    setSaveError("");
    const timer = setTimeout(async () => {
      try {
        const username = getSessionAdmin()?.username;
        const updatedAt = new Date().toISOString();
        const updatedSettings = { ...settings, updatedAt };
        // 🔴 [แก้ไข] แยกค่าที่กำลังจะบันทึกเป็น 2 ก้อนตาม PERSONAL_SETTING_KEYS
        // — ก้อนส่วนตัวเซฟลง web_settings_personal/{username} (มีผลแค่คนที่
        // ล็อกอินอยู่ตอนนี้) ก้อนที่เหลือ (ข้อมูลบริษัท/ประเภทแจ้งเตือน/ความ
        // ปลอดภัย) ยังเซฟรวมที่ web_settings เหมือนเดิม (มีผลกับทุกคน)
        const personalPart = {};
        const sharedPart = {};
        Object.entries(updatedSettings).forEach(([key, value]) => {
          if (PERSONAL_SETTING_KEYS.includes(key)) personalPart[key] = value;
          else sharedPart[key] = value;
        });
        await Promise.all([saveWebSettings(sharedPart), savePersonalSettings(username, personalPart)]);
        // เก็บเวลาที่เซฟล่าสุดไว้แสดงผลแยกต่างหาก ไม่ยุ่งกับ settings ที่ผูกอยู่
        // กับ auto-save effect นี้เอง กันไม่ให้เกิด loop เขียนซ้ำไม่จบ
        setLastSavedAt(updatedAt);
        setSaveStatus("saved");
        setTimeout(() => setSaveStatus((s) => (s === "saved" ? "idle" : s)), 2000);
      } catch (err) {
        console.error("[SettingsPage] auto-save failed:", err);
        // 🐛 [ใหม่] โชว์ error ให้ผู้ใช้เห็นจริง แทนที่จะเงียบแค่ log console —
        // เคสที่พบบ่อยสุดคือ permission denied เวลาเขียน Firebase (เช่น rules
        // ยังไม่เปิดให้เขียน path ใหม่ web_settings_personal/{username})
        setSaveError(
          err?.code === "PERMISSION_DENIED" || /permission_denied/i.test(err?.message || "")
            ? "บันทึกไม่สำเร็จ: ไม่มีสิทธิ์เขียนข้อมูล (permission denied) — ลองล็อกอินใหม่ หรือแจ้งผู้ดูแลระบบ"
            : "บันทึกไม่สำเร็จ กรุณาลองใหม่อีกครั้ง"
        );
        setSaveStatus("error");
      }
    }, 700);
    return () => clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [settings, loading]);

  // ธีมสีสลับให้เห็นผลทันทีตอนเลือกเลย ไม่ต้องรอ auto-save ยิงจริงก่อน (เหมือน
  // ที่แก้ไว้ก่อนหน้านี้ — auto-save ด้านบนจะตามไปบันทึกค่าที่เลือกไว้ทีหลัง)
  function updateSetting(key, value) {
    setSettings((s) => ({ ...s, [key]: value }));
    if (key === "theme") applyTheme(value);
  }

  const SaveStatusIndicator = (
    <div className="text-xs shrink-0">
      {saveStatus === "saving" ? (
        <span className="text-slate-400 flex items-center gap-1.5">
          <Loader2 size={13} className="animate-spin" /> กำลังบันทึก...
        </span>
      ) : saveStatus === "saved" ? (
        <span className="text-emerald-500 flex items-center gap-1.5">
          <Check size={13} /> บันทึกแล้ว
        </span>
      ) : saveStatus === "error" ? (
        <span className="text-red-500 max-w-[240px] text-right block">{saveError}</span>
      ) : null}
    </div>
  );

  if (loading) {
    return <p className="text-sm text-slate-400 py-10 text-center">กำลังโหลดข้อมูล...</p>;
  }

  const PAGE_SIZE_5_50 = [20, 25, 30, 35, 40, 45, 50].map((n) => ({ value: String(n), label: `${n} รายการ` }));

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <div>
          <h1 className="text-lg font-semibold text-slate-900">ตั้งค่าระบบ</h1>
          <p className="text-xs text-slate-400 mt-0.5">แก้ไขค่าไหนก็บันทึกให้อัตโนมัติ ไม่ต้องกดปุ่มบันทึกเอง</p>
        </div>
        {SaveStatusIndicator}
      </div>

      {/* คู่ซ้าย-ขวา จับคู่กันตามที่ขอ ไม่ให้เรียงยาวลงมาคอลัมน์เดียว —
          ซ้าย: จำนวนรายการต่อหน้า → ความปลอดภัย → ระบบทั่วไป
          ขวา: การแจ้งเตือน (ยาวสุด อยู่คนเดียวฝั่งขวา) */}
      <div className="flex flex-col lg:flex-row gap-5 items-start">
        <div className="flex-1 w-full space-y-5">
        {/* 🔴 [แก้ไข] ตามที่ขอ — เอาการ์ด "ข้อมูลบริษัท" ออกทั้งหมด (ชื่อบริษัท/
            เบอร์ติดต่อ/อีเมล/เขตเวลา/เว็บไซต์/เลขผู้เสียภาษี/ที่อยู่) ไม่มีช่อง
            แก้ไขข้อมูลบริษัทในหน้าตั้งค่าอีกต่อไป (ค่าที่เคยบันทึกไว้ใน
            web_settings ยังไม่ถูกลบออกจากฐานข้อมูล แค่ไม่มี UI ให้แก้แล้ว —
            หัวใบแจ้งหนี้/รายงานที่เคยอ่านค่าพวกนี้จะกลับไปใช้ชื่อ default แทน)
            🆕 แยกจำนวนรายการต่อหน้าออกเป็นรายหน้า — แต่ละหน้ามีปริมาณข้อมูลต่างกัน
            มาก การ์ด "งานล่าสุด" ในหน้า Dashboard เป็นแค่ตัวอย่างย่อ (5/10/15 พอ)
            ส่วนตารางเต็มของหน้าอื่นๆ ให้เลือกได้ 20-50 */}
        <Card>
          <p className="text-sm font-semibold text-slate-800 mb-1">จำนวนรายการต่อหน้า</p>
          <p className="text-xs text-slate-400 mb-4">กำหนดแยกทีละหน้า เพราะแต่ละหน้ามีปริมาณข้อมูลไม่เท่ากัน</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <SelectField
              label="งานซ่อมล่าสุด (หน้า Dashboard)"
              value={settings.itemsPerPageDashboard}
              onChange={(v) => updateSetting("itemsPerPageDashboard", v)}
              options={[5, 10, 15].map((n) => ({ value: String(n), label: `${n} รายการ` }))}
            />
            <SelectField
              label="งานซ่อม (หน้า งานซ่อม)"
              value={settings.itemsPerPageJobs}
              onChange={(v) => updateSetting("itemsPerPageJobs", v)}
              options={PAGE_SIZE_5_50}
            />
            <SelectField
              label="อะไหล่ (หน้า อะไหล่)"
              value={settings.itemsPerPageParts}
              onChange={(v) => updateSetting("itemsPerPageParts", v)}
              options={PAGE_SIZE_5_50}
            />
            <SelectField
              label="ใบแจ้งหนี้ (หน้า การเงิน)"
              value={settings.itemsPerPageFinance}
              onChange={(v) => updateSetting("itemsPerPageFinance", v)}
              options={PAGE_SIZE_5_50}
            />
            <SelectField
              label="การแจ้งเตือน (หน้า การแจ้งเตือน)"
              value={settings.itemsPerPageNotifications}
              onChange={(v) => updateSetting("itemsPerPageNotifications", v)}
              options={PAGE_SIZE_5_50}
            />
          </div>
        </Card>
        {/* ความปลอดภัย */}
        <Card>
          <div className="flex items-center gap-2 mb-4">
            <Lock size={16} className="text-slate-400" />
            <h2 className="text-sm font-semibold text-slate-800">ความปลอดภัย</h2>
          </div>

          {/* 🔴 [แก้ไข] ตามที่ขอ — ตัด "ระยะเวลา Session ก่อนล็อกเอาต์อัตโนมัติ"
              และ "บังคับเปลี่ยนรหัสผ่านทุก" ออกทั้งคู่ (พร้อมคำเตือน "ยังเป็น
              แค่ UI" ที่เคยคลุมกลุ่มนี้ไว้) — ส่วนที่เหลือทั้งหมดในการ์ดนี้
              (2FA, หลายอุปกรณ์, แจ้งเตือนล็อกอินใหม่) ทำงานจริงแล้ว และเป็นค่า
              "ส่วนตัว" ของแอดมินแต่ละคน (เหมือนธีมสี/จำนวนรายการต่อหน้า) เปิด/
              ปิดของตัวเองได้อิสระ ไม่กระทบแอดมินคนอื่น */}
          <div className="flex items-center justify-between mb-1 pb-4 border-b border-slate-100">
            <div className="pr-4">
              <p className="text-sm text-slate-700">การยืนยันตัวตนสองขั้นตอน (2FA)</p>
              <p className="text-xs text-slate-400 mt-0.5">
                เปิดแล้ว ทุกครั้งที่<strong>บัญชีของคุณ</strong>ล็อกอินเข้าเว็บนี้ จะต้องกรอกรหัส OTP ที่
                ส่งไปยังอีเมลของคุณก่อนถึงจะเข้าระบบได้ — เป็นการตั้งค่าส่วนตัว ไม่มีผลกับแอดมินคนอื่น
                (แต่ละคนเปิด/ปิดของตัวเองได้อิสระ)
              </p>
              {!currentAdminEmail && (
                <p className="text-[11px] text-amber-600 mt-1.5">
                  ยังไม่มีอีเมลผูกกับบัญชีของคุณ — ต้องไปเพิ่มอีเมลที่การ์ด "แอดมินทั้งหมด" ด้านล่าง
                  (กด "แก้ไขโปรไฟล์") ก่อนถึงจะเปิดใช้งาน 2FA ได้
                </p>
              )}
            </div>
            <Toggle
              checked={settings.enable2FA}
              onChange={(v) => updateSetting("enable2FA", v)}
              disabled={!currentAdminEmail}
            />
          </div>

          <div className="flex items-center justify-between pt-4">
            <div>
              <p className="text-sm text-slate-700">อนุญาตให้ล็อกอินพร้อมกันหลายอุปกรณ์</p>
              <p className="text-xs text-slate-400">
                ปิดไว้เพื่อบังคับให้<strong>บัญชีของคุณ</strong>ล็อกอินได้ทีละอุปกรณ์เท่านั้น — เป็นการตั้งค่า
                ส่วนตัว ไม่มีผลกับแอดมินคนอื่น (ล็อกอินจากอุปกรณ์ใหม่ อุปกรณ์เดิมจะถูกออกจากระบบอัตโนมัติ)
              </p>
            </div>
            <Toggle
              checked={settings.allowMultiDeviceLogin}
              onChange={(v) => updateSetting("allowMultiDeviceLogin", v)}
            />
          </div>
          <div className="flex items-center justify-between mt-4">
            <div>
              <p className="text-sm text-slate-700">แจ้งเตือนเมื่อมีการเข้าสู่ระบบใหม่</p>
              <p className="text-xs text-slate-400">
                แจ้งเตือน<strong>บัญชีของคุณ</strong>ทุกครั้งที่ถูกใช้ล็อกอินจากอุปกรณ์ที่ไม่เคยล็อกอินมาก่อน —
                เป็นการตั้งค่าส่วนตัว ไม่มีผลกับแอดมินคนอื่น
              </p>
            </div>
            <Toggle checked={settings.notifyNewLogin} onChange={(v) => updateSetting("notifyNewLogin", v)} />
          </div>
        </Card>
        {/* ระบบทั่วไป */}
        <Card>
          <div className="flex items-center gap-2 mb-4">
            <Settings2 size={16} className="text-slate-400" />
            <h2 className="text-sm font-semibold text-slate-800">ระบบทั่วไป</h2>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <SelectField
              label="ธีมสี"
              value={settings.theme}
              onChange={(v) => updateSetting("theme", v)}
              options={[
                { value: "light", label: "โหมดสว่าง" },
                { value: "dark", label: "โหมดมืด" },
              ]}
            />
          </div>
        </Card>
        </div>
        <div className="flex-1 w-full space-y-5">
        {/* การแจ้งเตือน */}
        <Card>
          <div className="flex items-center gap-2 mb-4">
            <Bell size={16} className="text-slate-400" />
            <h2 className="text-sm font-semibold text-slate-800">การแจ้งเตือน</h2>
          </div>
          <div className="space-y-4">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนข้อความแชทใหม่</p>
                <p className="text-xs text-slate-400">แจ้งเตือนทันทีเมื่อมีข้อความใหม่จากลูกค้าหรือช่าง</p>
              </div>
              <Toggle checked={settings.notifyChat} onChange={(v) => updateSetting("notifyChat", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนงานซ่อมใหม่</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่อมีการแจ้งซ่อมเข้ามาใหม่</p>
              </div>
              <Toggle checked={settings.notifyJob} onChange={(v) => updateSetting("notifyJob", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนงานเกินกำหนด</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่องานซ่อมเลยกำหนดเวลาที่ตั้งไว้</p>
              </div>
              <Toggle checked={settings.notifyOverdue} onChange={(v) => updateSetting("notifyOverdue", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนอะไหล่ใกล้หมดสต็อก</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่ออะไหล่ในคลังเหลือน้อยกว่าเกณฑ์ที่ตั้งไว้</p>
              </div>
              <Toggle checked={settings.notifyLowStock} onChange={(v) => updateSetting("notifyLowStock", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนใบแจ้งหนี้ค้างชำระ</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่อใบแจ้งหนี้ยังไม่ได้ชำระนานเกิน 7 วัน</p>
              </div>
              <Toggle checked={settings.notifyPaymentOverdue} onChange={(v) => updateSetting("notifyPaymentOverdue", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนเครื่องจักรใกล้หมดประกัน</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่อเครื่องจักรของลูกค้าใกล้หมดประกันภายใน 30 วัน</p>
              </div>
              <Toggle checked={settings.notifyWarranty} onChange={(v) => updateSetting("notifyWarranty", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">แจ้งเตือนงานค้างสถานะนาน</p>
                <p className="text-xs text-slate-400">แจ้งเตือนเมื่องานอยู่ในสถานะกำลังซ่อมนานเกิน 5 วันโดยไม่มีความเคลื่อนไหว</p>
              </div>
              <Toggle checked={settings.notifyStaleJob} onChange={(v) => updateSetting("notifyStaleJob", v)} />
            </div>
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-slate-700">สรุปกิจกรรมประจำวัน</p>
                <p className="text-xs text-slate-400">แจ้งเตือนสรุปงานใหม่/เสร็จสิ้นของวันนี้ ตั้งแต่ 17:30 น. เป็นต้นไป (เช็คตอนเปิดหน้า Dashboard)</p>
              </div>
              <Toggle checked={settings.notifyDailyDigest} onChange={(v) => updateSetting("notifyDailyDigest", v)} />
            </div>
          </div>

          <div className="mt-6 pt-5 border-t border-slate-100">
            <p className="text-sm font-semibold text-slate-800 mb-3">ช่องทางการแจ้งเตือน</p>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-slate-700">แจ้งเตือนในเว็บ</p>
                  <p className="text-xs text-slate-400">แสดงในกระดิ่งแจ้งเตือนและหน้า "แจ้งเตือน" (ทำงานอยู่เสมอ)</p>
                </div>
                <span className="text-[11px] font-medium px-2.5 py-1 rounded-full bg-emerald-50 text-emerald-600">
                  เปิดใช้งานอยู่เสมอ
                </span>
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-slate-700">แจ้งเตือน Popup ในเว็บ</p>
                  <p className="text-xs text-slate-400">เด้งการ์ดแจ้งเตือนมุมขวาล่างของหน้าเว็บ ตอนมีแจ้งเตือนใหม่เข้ามา</p>
                </div>
                <Toggle checked={settings.notifyToastPopup} onChange={(v) => updateSetting("notifyToastPopup", v)} />
              </div>
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-slate-700">แจ้งเตือนนอกเว็บ (ระดับเครื่อง)</p>
                  <p className="text-xs text-slate-400">
                    เด้งป๊อปอัประดับเครื่อง (OS) แม้กำลังใช้เว็บ/โปรแกรมอื่นอยู่ ต้องกดอนุญาตแจ้งเตือนจากเบราว์เซอร์ก่อน และต้องเปิดเบราว์เซอร์ค้างไว้เบื้องหลัง
                  </p>
                </div>
                <Toggle checked={settings.notifyDesktopPopup} onChange={(v) => updateSetting("notifyDesktopPopup", v)} />
              </div>
            </div>
          </div>
        </Card>

        </div>
      </div>

      {/* แอดมินทั้งหมด — ใช้ระบบบันทึกทันทีของตัวเองอยู่แล้ว (เพิ่ม/แก้/ลบ
          แต่ละคนแยกจาก settings object นี้ทั้งหมด) ไม่เกี่ยวกับ auto-save
          ด้านบนเลย */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <User size={16} className="text-slate-400" />
          <h2 className="text-sm font-semibold text-slate-800">แอดมินทั้งหมด</h2>
        </div>
        <AdminAccountsSection />
      </div>

      <SystemInfoCard settings={{ ...settings, updatedAt: lastSavedAt }} />
    </div>
  );
}