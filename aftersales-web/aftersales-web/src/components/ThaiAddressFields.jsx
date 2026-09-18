import React, { useMemo } from "react";
import useThaiAddress from "../hooks/useThaiAddress";

// 🆕 [ใหม่] แทนที่ช่องกรอกข้อความอิสระ "ตำบล/แขวง", "อำเภอ/เขต", "จังหวัด" เดิม
// ด้วยดรอปดาวน์ 3 ชั้นแบบเลือกต่อกัน — เลือกจังหวัดก่อน ตัวเลือกอำเภอ/เขตจะขึ้น
// เฉพาะของจังหวัดนั้น พอเลือกอำเภอ/เขตแล้ว ตัวเลือกตำบล/แขวงจะขึ้นเฉพาะของ
// อำเภอ/เขตนั้นอีกที ตามที่ขอ พอเลือกตำบล/แขวงเสร็จจะเติมรหัสไปรษณีย์ให้อัตโนมัติ
// (ยังแก้ไขเองได้ถ้าจำเป็น) ค่าที่เก็บยังเป็นชื่อล้วนไม่มีคำนำหน้า (ตำบล/อำเภอ/
// จังหวัด) เหมือนโครงสร้างข้อมูลเดิมทุกประการ — formatAddress() ที่มีอยู่แล้ว
// เป็นตัวเติมคำนำหน้า (ตำบล/แขวง, อำเภอ/เขต, จังหวัด) ตอนแสดงผลเหมือนเดิม
function stripDistrictPrefix(nameTh) {
  // ชื่ออำเภอของกรุงเทพฯ ในชุดข้อมูลต้นทางมีคำว่า "เขต" ติดมาด้วย (เช่น
  // "เขตพระนคร") ส่วนจังหวัดอื่นไม่มีคำนำหน้าแบบนี้ติดมาอยู่แล้ว (เช่น
  // "พระประแดง") ตัด "เขต" ออกให้เหลือชื่อล้วน จะได้เก็บ/แสดงผลสม่ำเสมอกัน
  // ทุกจังหวัด (formatAddress จะเติม "เขต" กลับให้เองตอนแสดงผล)
  return nameTh.startsWith("เขต") ? nameTh.slice(3) : nameTh;
}

const SELECT_CLASS =
  "w-full px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100 disabled:opacity-60 disabled:cursor-not-allowed";

export default function ThaiAddressFields({ changwat, amphoe, tambon, postalCode, onChange }) {
  const { provinces, loading, error } = useThaiAddress();

  const selectedProvince = useMemo(
    () => provinces.find((p) => p.name_th === changwat) || null,
    [provinces, changwat]
  );
  const districts = selectedProvince?.districts || [];
  const selectedDistrict = useMemo(
    () => districts.find((d) => stripDistrictPrefix(d.name_th) === amphoe) || null,
    [districts, amphoe]
  );
  const subDistricts = selectedDistrict?.sub_districts || [];

  function handleProvinceChange(e) {
    const value = e.target.value;
    // 🆕 เปลี่ยนจังหวัดใหม่ = ล้างอำเภอ/ตำบล/รหัสไปรษณีย์เดิมทิ้งทั้งหมด เพราะ
    // ไม่ได้อยู่ในจังหวัดใหม่นี้แล้วแน่ๆ กันข้อมูลไม่ตรงกันค้างอยู่
    onChange({ changwat: value, amphoe: "", tambon: "", postalCode: "" });
  }

  function handleDistrictChange(e) {
    const value = e.target.value;
    onChange({ changwat, amphoe: value, tambon: "", postalCode: "" });
  }

  function handleSubDistrictChange(e) {
    const value = e.target.value;
    const match = subDistricts.find((s) => s.name_th === value);
    onChange({
      changwat,
      amphoe,
      tambon: value,
      postalCode: match ? String(match.zip_code) : "",
    });
  }

  return (
    <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div>
        <label className="text-sm text-slate-600 mb-2 block font-medium">จังหวัด</label>
        <select className={SELECT_CLASS} value={changwat || ""} onChange={handleProvinceChange} disabled={loading}>
          <option value="">{loading ? "กำลังโหลดข้อมูล..." : "เลือกจังหวัด"}</option>
          {provinces.map((p) => (
            <option key={p.id} value={p.name_th}>
              {p.name_th}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="text-sm text-slate-600 mb-2 block font-medium">อำเภอ/เขต</label>
        <select
          className={SELECT_CLASS}
          value={amphoe || ""}
          onChange={handleDistrictChange}
          disabled={!selectedProvince}
        >
          <option value="">เลือกอำเภอ/เขต</option>
          {districts.map((d) => (
            <option key={d.id} value={stripDistrictPrefix(d.name_th)}>
              {stripDistrictPrefix(d.name_th)}
            </option>
          ))}
        </select>
      </div>
      <div>
        <label className="text-sm text-slate-600 mb-2 block font-medium">ตำบล/แขวง</label>
        <select
          className={SELECT_CLASS}
          value={tambon || ""}
          onChange={handleSubDistrictChange}
          disabled={!selectedDistrict}
        >
          <option value="">เลือกตำบล/แขวง</option>
          {subDistricts.map((s) => (
            <option key={s.id} value={s.name_th}>
              {s.name_th}
            </option>
          ))}
        </select>
      </div>
      {error ? (
        <p className="text-xs text-red-500 sm:col-span-3">
          โหลดข้อมูลจังหวัด/อำเภอ/ตำบลไม่สำเร็จ (ต้องใช้อินเทอร์เน็ต) ลองปิดแล้วเปิดฟอร์มนี้ใหม่
        </p>
      ) : null}
    </div>
  );
}
