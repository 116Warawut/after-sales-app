import React, { useState } from "react";
import { Camera, Eye, EyeOff } from "lucide-react";
import { FormField } from "./ui";
import ThaiAddressFields from "./ThaiAddressFields";

// 🔴 [แก้ไข] ปรับฟอร์มกลาง (ลูกค้า+ช่างใช้ร่วมกัน) ตามลำดับฟิลด์ที่ขอใหม่ล่าสุด:
// รูปโปรไฟล์ → รหัสลูกค้า/ช่าง → ชื่อ-นามสกุล (รวมเป็นช่องเดียว ไม่แยกชื่อ/
// นามสกุลอีกต่อไป) → บริษัท (เฉพาะลูกค้า) → username → รหัสผ่าน → เบอร์โทร →
// ที่อยู่ (บ้านเลขที่/ถนน/ซอย) + หมู่ → จังหวัด/อำเภอ/ตำบล (ดรอปดาวน์เลือกต่อกัน
// แบบเดิมที่เคยทำไว้ ไม่เปลี่ยนกลไก) → รหัสไปรษณีย์ (เติมอัตโนมัติ อยู่ล่างสุด
// ของกลุ่มที่อยู่ตามลำดับที่ขอ) → ยานพาหนะ (เฉพาะช่าง)
export default function PersonFormFields({
  photoUrl,
  initials,
  uploadingImage,
  onImageChange,
  codeLabel,
  codePlaceholder,
  code,
  onCodeChange,
  name,
  onNameChange,
  namePlaceholder,
  username,
  onUsernameChange,
  currentPassword,
  password,
  onPasswordChange,
  passwordLabel,
  passwordRequired,
  phone,
  onPhoneChange,
  showCompany,
  company,
  onCompanyChange,
  houseNo,
  onHouseNoChange,
  moo,
  onMooChange,
  postalCode,
  onPostalCodeChange,
  tambon,
  amphoe,
  changwat,
  onAddressChange,
  showVehicle,
  vehicle,
  onVehicleChange,
}) {
  // 🆕 [ใหม่] ปุ่มตาเปิด/ปิดดูรหัสผ่านจริงตามที่ขอ — ใช้ input ของตัวเองแทน
  // FormField (ซึ่งใช้ร่วมกับที่อื่นในเว็บอีกหลายจุด ไม่อยากไปแก้ผลกับจุดอื่น)
  // สลับ type ระหว่าง "password" (ซ่อน ●●●) กับ "text" (โชว่ตัวอักษรจริง)
  const [showPassword, setShowPassword] = useState(false);
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);

  return (
    <>
      <div className="flex items-center gap-4 mb-5 pb-4 border-b border-slate-100">
        <div className="relative">
          {photoUrl ? (
            <img
              src={photoUrl}
              alt="Profile Preview"
              className="w-16 h-16 rounded-full object-cover border-2 border-slate-200"
            />
          ) : (
            <div className="w-16 h-16 rounded-full bg-slate-100 text-slate-400 flex items-center justify-center text-xl font-semibold border-2 border-slate-200">
              {initials || "?"}
            </div>
          )}
          {uploadingImage && (
            <div className="absolute inset-0 rounded-full bg-black/40 flex items-center justify-center text-white text-xs">
              อัปโหลด...
            </div>
          )}
        </div>
        <div>
          <label className="cursor-pointer inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-blue-600 bg-blue-50 hover:bg-blue-100 transition-colors">
            <Camera size={14} />
            <span>{photoUrl ? "เปลี่ยนรูปโปรไฟล์" : "อัปโหลดรูปโปรไฟล์"}</span>
            <input type="file" accept="image/*" onChange={onImageChange} disabled={uploadingImage} className="hidden" />
          </label>
          <p className="text-[11px] text-slate-400 mt-1">ไฟล์รูปภาพ PNG, JPG ขนาดไม่เกิน 5MB</p>
        </div>
      </div>

      <FormField label={codeLabel} value={code} onChange={onCodeChange} placeholder={codePlaceholder} />
      <FormField label="ชื่อ-นามสกุล" value={name} onChange={onNameChange} placeholder={namePlaceholder} required />
      {showCompany ? (
        <FormField label="บริษัท" value={company} onChange={onCompanyChange} placeholder="ชื่อบริษัท (ถ้ามี)" />
      ) : null}
      <FormField
        label="ชื่อผู้ใช้ (username)"
        value={username}
        onChange={onUsernameChange}
        placeholder="สำหรับล็อกอินในแอปมือถือ"
        required
      />
      {/* 🐛 [แก้ไข] BUG: ค่า "รหัสผ่านปัจจุบัน" ที่ดึงมาโชว่ กลายเป็น bcrypt
          hash (เช่น "$2a$10$...") แทนที่จะเป็นรหัสผ่านตัวจริง — ไม่ใช่บั๊กของ
          ช่องนี้ แต่เป็นเพราะระบบเข้ารหัสรหัสผ่านแบบ hash (bcrypt) ไว้ที่ฝั่ง
          เซิร์ฟเวอร์ก่อนบันทึกจริง (คนละจุดกับเว็บนี้) ซึ่ง hash เป็นการเข้ารหัส
          "ทางเดียว" ถอดกลับเป็นข้อความจริงไม่ได้อีกเลยไม่ว่าจะวิธีไหน (เป็น
          หลักการความปลอดภัยที่ถูกต้องแล้ว) เลยไม่มีทางโชว่รหัสผ่านจริงของ
          เรคคอร์ดที่บันทึกไปแล้วได้เลย — ตรวจจับรูปแบบ hash แล้วโชว่ข้อความ
          อธิบายแทนค่า hash ที่อ่านไม่รู้เรื่อง ไม่ให้ปุ่มตาเปิด/ปิดด้วยเพราะ
          ไม่มีอะไรจะ "เปิดดู" จริง ๆ */}
      {currentPassword !== undefined && currentPassword !== null ? (
        <div>
          <label className="text-sm text-slate-600 mb-2 block font-medium">รหัสผ่านปัจจุบัน</label>
          {/^\$2[aby]\$/.test(currentPassword) ? (
            <div className="w-full px-4 py-2.5 rounded-xl bg-slate-100 border border-slate-200 text-sm text-slate-400 italic">
              รหัสผ่านถูกเข้ารหัสไว้ (hash) ไม่สามารถแสดงค่าจริงได้ เพื่อความปลอดภัย
            </div>
          ) : (
            <div className="relative">
              <input
                type={showCurrentPassword ? "text" : "password"}
                value={currentPassword}
                readOnly
                className="w-full px-4 py-2.5 pr-11 rounded-xl bg-slate-100 border border-slate-200 text-[15px] text-slate-500 cursor-default focus:outline-none"
              />
              <button
                type="button"
                onClick={() => setShowCurrentPassword((v) => !v)}
                tabIndex={-1}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                aria-label={showCurrentPassword ? "ซ่อนรหัสผ่าน" : "แสดงรหัสผ่าน"}
              >
                {showCurrentPassword ? <EyeOff size={17} /> : <Eye size={17} />}
              </button>
            </div>
          )}        </div>
      ) : null}
      <div>
        <label className="text-sm text-slate-600 mb-2 block font-medium">
          {passwordLabel} {passwordRequired ? <span className="text-red-400">*</span> : null}
        </label>
        <div className="relative">
          <input
            type={showPassword ? "text" : "password"}
            value={password ?? ""}
            onChange={(e) => onPasswordChange(e.target.value)}
            placeholder="••••••••"
            className="w-full px-4 py-2.5 pr-11 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
          <button
            type="button"
            onClick={() => setShowPassword((v) => !v)}
            tabIndex={-1}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
            aria-label={showPassword ? "ซ่อนรหัสผ่าน" : "แสดงรหัสผ่าน"}
          >
            {showPassword ? <EyeOff size={17} /> : <Eye size={17} />}
          </button>
        </div>
      </div>
      <FormField label="เบอร์โทร" value={phone} onChange={onPhoneChange} placeholder="0X-XXX-XXXX" />

      <div className="pt-2 border-t border-slate-100">
        <p className="text-sm font-semibold text-slate-700 mb-3 mt-3">ที่อยู่</p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          <div className="sm:col-span-2">
            <FormField
              label="ที่อยู่"
              value={houseNo}
              onChange={onHouseNoChange}
              placeholder="บ้านเลขที่ ถนน ซอย"
            />
          </div>
          <FormField label="หมู่" value={moo} onChange={onMooChange} placeholder="5" />
        </div>

        <div className="mt-4">
          <ThaiAddressFields
            changwat={changwat}
            amphoe={amphoe}
            tambon={tambon}
            postalCode={postalCode}
            onChange={onAddressChange}
          />
        </div>

        <div className="mt-4">
          <FormField
            label="รหัสไปรษณีย์"
            value={postalCode}
            onChange={onPostalCodeChange}
            placeholder="เลือกตำบล/แขวงเพื่อเติมอัตโนมัติ"
          />
        </div>
      </div>

      {showVehicle ? (
        <div className="mt-4">
          <FormField
            label="ยานพาหนะ"
            value={vehicle}
            onChange={onVehicleChange}
            placeholder="เช่น กระบะ ทะเบียน กข-1234"
          />
        </div>
      ) : null}
    </>
  );
}
