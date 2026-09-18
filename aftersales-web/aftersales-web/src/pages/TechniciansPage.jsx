import React, { useState, useEffect } from "react";
import {
  Plus,
  Search,
  UserCog,
  Pencil,
  Trash2,
  MapPin,
  Phone,
  Briefcase,
  Truck,
  X,
} from "lucide-react";
import { Card, EmptyState, PrimaryButton, Modal, ConfirmDialog, StarRating } from "../components/ui";
import PersonFormFields from "../components/PersonFormFields";
import { COLORS, TECH_STATUS_BADGE, extractRating } from "../shared/constants";
import useDbList from "../hooks/useDbList";
import { addRow, updateRow, deleteRow, logActivity } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";
import { uploadImage } from "../services/cloudinary";

const EMPTY_FORM = {
  employee_id: "",
  tech_name: "",
  username: "",
  phone: "",
  password: "",
  photo_url: "",
  house_no: "",
  moo: "",
  tambon: "",
  amphoe: "",
  changwat: "",
  postal_code: "",
  vehicle: "",
};

function techStatus(tech) {
  if (tech.status) return tech.status;
  return tech.is_busy ? "กำลังปฏิบัติงาน" : "ว่าง";
}

function getTechPhoto(t) {
  if (!t) return "";
  const url = t.photo_url || t.photo || t.avatar || t.profile_photo || t.profile_url || t.image || "";
  return typeof url === "string" ? url.trim() : "";
}

function formatAddress(t) {
  if (!t) return "-";

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

  const changwatRaw = (t.changwat || "").trim();
  const isBKK =
    changwatRaw.includes("กรุงเทพ") ||
    changwatRaw.toLowerCase().includes("bangkok") ||
    changwatRaw === "กทม" ||
    changwatRaw === "กทม.";

  const tambon = clean(t.tambon, ["ตำบล", "ต.", "ต ", "แขวง"]);
  const amphoe = clean(t.amphoe, ["อำเภอ", "อ.", "อ ", "เขต"]);
  const changwat = clean(t.changwat, ["จังหวัด", "จ.", "จ "]);
  const moo = clean(t.moo, ["หมู่ที่", "หมู่", "ม.", "ม "]);

  const parts = [
    t.house_no ? t.house_no.trim() : "",
    moo ? `หมู่ ${moo}` : "",
    tambon ? (isBKK ? `แขวง${tambon}` : `ตำบล${tambon}`) : "",
    amphoe ? (isBKK ? `เขต${amphoe}` : `อำเภอ${amphoe}`) : "",
    changwat ? (isBKK ? changwat : `จังหวัด${changwat}`) : "",
    t.postal_code ? t.postal_code.trim() : "",
  ].filter(Boolean);

  return parts.length > 0 ? parts.join(" ") : (t.address || "-");
}

// 🔴 [ใหม่] คำนวณคะแนนเฉลี่ยของช่างแต่ละคน จากทุกงานที่ลูกค้าให้คะแนนแล้ว
// (extractRating คืนค่า null ถ้างานนั้นยังไม่มีคะแนน — ไม่นับรวมในค่าเฉลี่ย)
// 🔴 [แก้บั๊ก] เดิมจับกลุ่มคะแนนด้วย r.technician_username (ช่างที่รับผิดชอบ
// งานนี้ ณ "ปัจจุบัน") — แต่เช็กกับ getTechnicianRatingStats() ในมือถือ
// (services.dart) จริงแล้ว มือถือจับกลุ่มด้วย r.rating_technician_username
// ก่อนเสมอ (ช่างที่ถูกให้คะแนน "ตอนนั้น" ที่ submitTechnicianRating() บันทึกไว้)
// แล้วค่อย fallback เป็น technician_username ถ้าไม่มีค่านี้ — สองอันนี้ต่างกัน
// ตอนงานถูกโอนให้ช่างคนอื่นทีหลัง (เปลี่ยน technician_username แต่ rating เดิม
// ยังผูกกับช่างคนแรกที่ทำงานจริง) เดิมเว็บเอาคะแนนเก่าไปติดกับช่างคนใหม่ผิดคน
// แก้ให้จับกลุ่มด้วยลำดับความสำคัญเดียวกับมือถือ
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

function TechCard({ tech, jobCount, rating, onEdit, onDelete }) {
  const status = techStatus(tech);
  const name = tech.tech_name || tech.name || "ไม่ระบุชื่อ";
  const address = formatAddress(tech);
  const photo = getTechPhoto(tech);

  return (
    <Card>
      <div className="flex items-start justify-between mb-3">
        <div className="flex items-center gap-3 min-w-0">
          {photo ? (
            <img
              src={photo}
              alt={name}
              className="w-12 h-12 rounded-full object-cover shrink-0 border border-slate-100"
            />
          ) : (
            <div className="w-12 h-12 rounded-full bg-slate-100 flex items-center justify-center text-slate-500 font-semibold shrink-0 text-base">
              {name?.[0] ?? "?"}
            </div>
          )}

          <div className="min-w-0">
            {tech.employee_id ? (
              <p className="text-[11px] text-slate-400 font-medium truncate">#{tech.employee_id}</p>
            ) : (
              <p className="text-[11px] text-slate-400 font-medium truncate">@{tech.username}</p>
            )}
            <p className="text-sm font-semibold text-slate-800 truncate">{name}</p>
            <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${TECH_STATUS_BADGE[status] ?? "bg-gray-100 text-gray-500"}`}>
              {status}
            </span>
          </div>
        </div>

        {/* 🔴 [แก้ไข] เอาไอคอนดินสอ (แก้ไข) มุมขวาบนออก — ย้ายการแก้ไขไปเป็น
            ปุ่ม "แก้ไขข้อมูล" ท้ายการ์ดแทน (ให้เหมือนรูปแบบของแอดมิน) เหลือแค่
            ปุ่มลบไว้ตรงนี้ */}
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
          <span>{tech.phone || "-"}</span>
        </p>
        {address !== "-" ? (
          <p className="flex items-start gap-1.5 line-clamp-2">
            <MapPin size={12} className="shrink-0 text-slate-400 mt-0.5" />
            <span>{address}</span>
          </p>
        ) : null}
        {tech.vehicle ? (
          <p className="flex items-center gap-1.5">
            <Truck size={12} className="shrink-0 text-slate-400" />
            <span>{tech.vehicle}</span>
          </p>
        ) : null}
        <p className="flex items-center gap-1.5 pt-1 text-slate-600">
          <Briefcase size={12} className="shrink-0 text-slate-400" />
          <span>รับผิดชอบ {jobCount} งาน</span>
        </p>
      </div>

      {/* 🔴 [ใหม่] คะแนนรีวิวเฉลี่ยจากลูกค้า — ยังไม่มีหน้าให้คะแนนจริงฝั่ง
          Flutter (ลูกค้ายังให้คะแนนไม่ได้) ตอนนี้จะขึ้น "ยังไม่มีคะแนน" เสมอ
          จนกว่าจะมีข้อมูลจริงในฟิลด์ที่เดาไว้ (ดู extractRating ใน
          shared/constants.js) — วางไว้พร้อมแล้ว รอแค่ข้อมูลจริงเข้ามา */}
      <div className="pb-2 flex items-center gap-1.5">
        <StarRating value={rating?.value ?? null} size={13} />
        {rating?.count ? (
          <span className="text-[11px] text-slate-400">({rating.count} รีวิว)</span>
        ) : null}
      </div>

      {/* 🔴 [ใหม่] แถบท้ายการ์ด (เส้นคั่น border-t) + ปุ่ม "แก้ไขข้อมูล" —
          ให้เหมือนรูปแบบเดียวกับการ์ดแอดมินที่ทำไว้ก่อนหน้านี้ */}
      <div className="pt-2 border-t border-slate-100 flex justify-end">
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

export default function TechniciansPage({ initialQuery }) {
  const { data: technicians, loading } = useDbList("technicians");
  const { data: repairs } = useDbList("repairs");
  const [query, setQuery] = useState(initialQuery || "");

  useEffect(() => {
    if (initialQuery) setQuery(initialQuery);
  }, [initialQuery]);

  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);
  const [uploadingImage, setUploadingImage] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [deleting, setDeleting] = useState(false);

  const filteredTechnicians = technicians.filter((t) => {
    const q = query.trim().toLowerCase();
    if (!q) return true;
    const searchTarget = `${t.tech_name || ""} ${t.name || ""} ${t.username || ""} ${t.employee_id || ""} ${t.phone || ""}`.toLowerCase();
    return searchTarget.includes(q);
  });

  const summary = [
    { label: "ช่างทั้งหมด", value: technicians.length, color: "blue" },
    { label: "กำลังปฏิบัติงาน", value: technicians.filter((t) => techStatus(t) === "กำลังปฏิบัติงาน").length, color: "orange" },
    { label: "ว่าง", value: technicians.filter((t) => techStatus(t) === "ว่าง").length, color: "green" },
  ];

  const jobCountByUsername = {};
  repairs.forEach((r) => {
    if (!r.technician_username) return;
    const status = r.status || "";
    if (status.includes("ยกเลิก") || status === "เสร็จสิ้น" || status === "เสร็จแล้ว") return;
    jobCountByUsername[r.technician_username] = (jobCountByUsername[r.technician_username] || 0) + 1;
  });

  // 🔴 [ใหม่] คะแนนเฉลี่ยต่อช่าง — ดูคอมเมนต์ที่ computeAvgRatingByUsername ด้านบน
  const avgRatingByUsername = computeAvgRatingByUsername(repairs);

  function openAdd() {
    setForm(EMPTY_FORM);
    setEditing({});
  }

  function openEdit(tech) {
    setForm({
      employee_id: tech.employee_id || "",
      tech_name: tech.tech_name || tech.name || "",
      username: tech.username || "",
      phone: tech.phone || "",
      password: "",
      photo_url: getTechPhoto(tech),
      house_no: tech.house_no || "",
      moo: tech.moo || "",
      tambon: tech.tambon || "",
      amphoe: tech.amphoe || "",
      changwat: tech.changwat || "",
      postal_code: tech.postal_code || "",
      vehicle: tech.vehicle || "",
    });
    setEditing(tech);
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
    if (!editing?.id && !form.password.trim()) {
      alert("กรุณากรอกรหัสผ่านสำหรับช่างใหม่ ไม่งั้นจะล็อกอินในแอปมือถือไม่ได้");
      return;
    }
    setSaving(true);
    try {
      const payload = {
        employee_id: form.employee_id.trim(),
        tech_name: form.tech_name.trim(),
        username: form.username.trim(),
        phone: form.phone.trim(),
        photo_url: form.photo_url.trim(),
        house_no: form.house_no.trim(),
        moo: form.moo.trim(),
        tambon: form.tambon.trim(),
        amphoe: form.amphoe.trim(),
        changwat: form.changwat.trim(),
        postal_code: form.postal_code.trim(),
        vehicle: form.vehicle.trim(),
      };
      if (form.password.trim()) payload.password = form.password.trim();

      if (editing?.id) {
        await updateRow("technicians", editing.id, payload);
      } else {
        await addRow("technicians", { ...payload, password: form.password.trim() });
      }
      setEditing(null);
    } catch (err) {
      console.error("[TechniciansPage] save failed:", err);
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete() {
    if (!deleteTarget) return;
    setDeleting(true);
    try {
      await deleteRow("technicians", deleteTarget.id);
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ลบช่างเทคนิค",
        target: deleteTarget.tech_name || deleteTarget.name || deleteTarget.username,
      }).catch((err) => console.error("[TechniciansPage] log activity failed:", err));
      setDeleteTarget(null);
    } catch (err) {
      console.error("[TechniciansPage] delete failed:", err);
    } finally {
      setDeleting(false);
    }
  }

  return (
    <div>
      {/* 🔴 [แก้ไข] รวมปุ่ม "เพิ่มช่างใหม่" กับช่องค้นหาไว้บรรทัดเดียวกัน */}
      <div className="flex items-center justify-between gap-3 mb-5">
        <div className="relative max-w-sm flex-1">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="ค้นหาช่าง / รหัสช่าง / เบอร์โทร..."
            className="w-full pl-9 pr-8 py-2 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
          {/* 🔴 [ใหม่] ปุ่มล้างการค้นหา — เคลียร์ query ในคลิกเดียว */}
          {query ? (
            <button
              onClick={() => setQuery("")}
              className="absolute right-2.5 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500"
            >
              <X size={14} />
            </button>
          ) : null}
        </div>
        <PrimaryButton icon={Plus} onClick={openAdd}>เพิ่มช่างใหม่</PrimaryButton>
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
              <span className="text-xl font-semibold text-slate-900">{s.value} คน</span>
            </div>
          );
        })}
      </div>

      {loading ? (
        <Card>
          <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
        </Card>
      ) : filteredTechnicians.length === 0 ? (
        <Card>
          <EmptyState icon={UserCog} message={query ? "ไม่พบช่างที่ค้นหา" : "ยังไม่มีช่างในระบบ"} />
        </Card>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredTechnicians.map((t) => (
            <TechCard
              key={t.id}
              tech={t}
              jobCount={jobCountByUsername[t.username] || 0}
              rating={avgRatingByUsername[t.username] || null}
              onEdit={() => openEdit(t)}
              onDelete={() => setDeleteTarget(t)}
            />
          ))}
        </div>
      )}

      {editing !== null && (
        <Modal
          title={editing?.id ? "แก้ไขข้อมูลช่าง" : "เพิ่มช่างใหม่"}
          onClose={() => setEditing(null)}
          wide
          footer={
            <div className="w-full flex items-center justify-end gap-3">
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
          }
        >
          <PersonFormFields
            photoUrl={form.photo_url}
            initials={form.tech_name?.[0] || "?"}
            uploadingImage={uploadingImage}
            onImageChange={handleImageChange}
            codeLabel="รหัสช่าง"
            codePlaceholder="เช่น T-001"
            code={form.employee_id}
            onCodeChange={(v) => setForm((f) => ({ ...f, employee_id: v }))}
            name={form.tech_name}
            onNameChange={(v) => setForm((f) => ({ ...f, tech_name: v }))}
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
            showVehicle
            vehicle={form.vehicle}
            onVehicleChange={(v) => setForm((f) => ({ ...f, vehicle: v }))}
          />
        </Modal>
      )}

      {deleteTarget ? (
        <ConfirmDialog
          message={`ต้องการลบช่าง "${deleteTarget.tech_name || deleteTarget.name}" ใช่หรือไม่? การลบนี้ไม่สามารถกู้คืนได้`}
          onConfirm={handleDelete}
          onCancel={() => setDeleteTarget(null)}
          busy={deleting}
        />
      ) : null}
    </div>
  );
}