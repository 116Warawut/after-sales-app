import React, { useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown, X } from "lucide-react";
import useThaiAddress from "../hooks/useThaiAddress";

// 🆕 [ใหม่] แทนที่ช่องกรอกข้อความอิสระ "ตำบล/แขวง", "อำเภอ/เขต", "จังหวัด" เดิม
// ด้วยดรอปดาวน์ 3 ชั้นแบบเลือกต่อกัน — เลือกจังหวัดก่อน ตัวเลือกอำเภอ/เขตจะขึ้น
// เฉพาะของจังหวัดนั้น พอเลือกอำเภอ/เขตแล้ว ตัวเลือกตำบล/แขวงจะขึ้นเฉพาะของ
// อำเภอ/เขตนั้นอีกที ตามที่ขอ พอเลือกตำบล/แขวงเสร็จจะเติมรหัสไปรษณีย์ให้อัตโนมัติ
// (ยังแก้ไขเองได้ถ้าจำเป็น) ค่าที่เก็บยังเป็นชื่อล้วนไม่มีคำนำหน้า (ตำบล/อำเภอ/
// จังหวัด) เหมือนโครงสร้างข้อมูลเดิมทุกประการ — formatAddress() ที่มีอยู่แล้ว
// เป็นตัวเติมคำนำหน้า (ตำบล/แขวง, อำเภอ/เขต, จังหวัด) ตอนแสดงผลเหมือนเดิม
//
// 🔴 [แก้ไข] เดิมทั้ง 3 ช่องเป็น native <select> ธรรมดา — จังหวัดมี 77 ตัวเลือก
// อำเภอ/ตำบลบางจังหวัดมีเป็นร้อย ต้องไล่เลื่อนหาเอาทีละบรรทัด ไม่มีช่องพิมพ์ค้นหา
// เลย (ต่างจากฝั่งแอปมือถือที่มี ThaiAddressAutocompleteField ให้พิมพ์กรองได้อยู่
// แล้ว ดู utils/thai_address.dart) — เปลี่ยนมาใช้ SearchableAddressSelect ด้านล่าง
// แทน: พิมพ์คำอะไรก็ได้ที่ปรากฏอยู่ตรงไหนของชื่อก็กรองเจอ (ใช้ .includes() ไม่ใช่
// แค่คำขึ้นต้น เช่น พิมพ์ "สม" เจอทั้ง "สมุทรปราการ"/"สมุทรสาคร"/"สมุทรสงคราม") ยัง
// คงหน้าตา/เลย์เอาต์ (label, กริด 3 คอลัมน์, disabled ตามลำดับจังหวัด->อำเภอ->
// ตำบล) และค่าที่เก็บ/ไล่ระดับข้อมูลเดิมทุกอย่าง เปลี่ยนแค่ตัว UI ช่องเลือกเอง
function stripDistrictPrefix(nameTh) {
  // ชื่ออำเภอของกรุงเทพฯ ในชุดข้อมูลต้นทางมีคำว่า "เขต" ติดมาด้วย (เช่น
  // "เขตพระนคร") ส่วนจังหวัดอื่นไม่มีคำนำหน้าแบบนี้ติดมาอยู่แล้ว (เช่น
  // "พระประแดง") ตัด "เขต" ออกให้เหลือชื่อล้วน จะได้เก็บ/แสดงผลสม่ำเสมอกัน
  // ทุกจังหวัด (formatAddress จะเติม "เขต" กลับให้เองตอนแสดงผล)
  return nameTh.startsWith("เขต") ? nameTh.slice(3) : nameTh;
}

// ช่องเลือกแบบพิมพ์ค้นหาได้ (ยืดหยุ่น — จับคู่ได้ทุกตำแหน่งในชื่อ ไม่ใช่แค่
// ขึ้นต้น) ใช้ร่วมกันทั้งจังหวัด/อำเภอ-เขต/ตำบล-แขวง ให้หน้าตาสม่ำเสมอกัน
function SearchableAddressSelect({ label, value, options, onSelect, disabled, placeholder }) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const boxRef = useRef(null);

  // ปิดดรอปดาวน์เมื่อคลิกนอกกล่อง
  useEffect(() => {
    function handleClickOutside(e) {
      if (boxRef.current && !boxRef.current.contains(e.target)) {
        setOpen(false);
        setQuery("");
      }
    }
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  const filtered = useMemo(() => {
    const q = query.trim();
    if (!q) return options;
    return options.filter((o) => o.label.includes(q));
  }, [options, query]);

  function handleSelect(opt) {
    onSelect(opt.value);
    setQuery("");
    setOpen(false);
  }

  function handleClear(e) {
    e.stopPropagation();
    onSelect("");
    setQuery("");
  }

  return (
    <div>
      <label className="text-sm text-slate-600 mb-2 block font-medium">{label}</label>
      <div ref={boxRef} className="relative">
        <div
          onClick={() => !disabled && setOpen(true)}
          className={`w-full px-3 py-2.5 rounded-xl bg-slate-50 border text-sm flex items-center gap-2 ${
            disabled ? "opacity-60 cursor-not-allowed border-slate-200" : "cursor-text border-slate-200 focus-within:ring-2 focus-within:ring-blue-100"
          }`}
        >
          <input
            type="text"
            disabled={disabled}
            value={open ? query : value || ""}
            onFocus={() => setOpen(true)}
            onChange={(e) => {
              setQuery(e.target.value);
              setOpen(true);
            }}
            placeholder={disabled ? placeholder : open ? value || "พิมพ์เพื่อค้นหา..." : placeholder}
            className="w-full bg-transparent outline-none text-slate-700 placeholder:text-slate-400 disabled:cursor-not-allowed"
          />
          {value && !disabled ? (
            <button type="button" onClick={handleClear} className="text-slate-400 hover:text-slate-600 shrink-0">
              <X size={15} />
            </button>
          ) : (
            <ChevronDown size={16} className="text-slate-400 shrink-0" />
          )}
        </div>
        {open && !disabled ? (
          <div className="absolute z-20 mt-1 w-full max-h-56 overflow-y-auto rounded-xl border border-slate-200 bg-white shadow-lg">
            {filtered.length === 0 ? (
              <p className="px-3 py-2.5 text-sm text-slate-400">ไม่พบรายการที่ตรงกัน</p>
            ) : (
              filtered.map((opt) => (
                <button
                  type="button"
                  key={opt.key}
                  onClick={() => handleSelect(opt)}
                  className={`w-full text-left px-3 py-2 text-sm hover:bg-blue-50 ${
                    opt.value === value ? "bg-blue-50 text-blue-600 font-medium" : "text-slate-700"
                  }`}
                >
                  {opt.label}
                </button>
              ))
            )}
          </div>
        ) : null}
      </div>
    </div>
  );
}

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

  const provinceOptions = useMemo(
    () => provinces.map((p) => ({ key: p.id, value: p.name_th, label: p.name_th })),
    [provinces]
  );
  const districtOptions = useMemo(
    () => districts.map((d) => ({ key: d.id, value: stripDistrictPrefix(d.name_th), label: stripDistrictPrefix(d.name_th) })),
    [districts]
  );
  const subDistrictOptions = useMemo(
    () => subDistricts.map((s) => ({ key: s.id, value: s.name_th, label: s.name_th })),
    [subDistricts]
  );

  function handleProvinceChange(value) {
    // 🆕 เปลี่ยนจังหวัดใหม่ = ล้างอำเภอ/ตำบล/รหัสไปรษณีย์เดิมทิ้งทั้งหมด เพราะ
    // ไม่ได้อยู่ในจังหวัดใหม่นี้แล้วแน่ๆ กันข้อมูลไม่ตรงกันค้างอยู่
    onChange({ changwat: value, amphoe: "", tambon: "", postalCode: "" });
  }

  function handleDistrictChange(value) {
    onChange({ changwat, amphoe: value, tambon: "", postalCode: "" });
  }

  function handleSubDistrictChange(value) {
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
      <SearchableAddressSelect
        label="จังหวัด"
        value={changwat || ""}
        options={provinceOptions}
        onSelect={handleProvinceChange}
        disabled={loading}
        placeholder={loading ? "กำลังโหลดข้อมูล..." : "เลือกจังหวัด"}
      />
      <SearchableAddressSelect
        label="อำเภอ/เขต"
        value={amphoe || ""}
        options={districtOptions}
        onSelect={handleDistrictChange}
        disabled={!selectedProvince}
        placeholder={selectedProvince ? "เลือกอำเภอ/เขต" : "เลือกจังหวัดก่อน"}
      />
      <SearchableAddressSelect
        label="ตำบล/แขวง"
        value={tambon || ""}
        options={subDistrictOptions}
        onSelect={handleSubDistrictChange}
        disabled={!selectedDistrict}
        placeholder={selectedDistrict ? "เลือกตำบล/แขวง" : "เลือกอำเภอ/เขตก่อน"}
      />
      {error ? (
        <p className="text-xs text-red-500 sm:col-span-3">
          โหลดข้อมูลจังหวัด/อำเภอ/ตำบลไม่สำเร็จ (ต้องใช้อินเทอร์เน็ต) ลองปิดแล้วเปิดฟอร์มนี้ใหม่
        </p>
      ) : null}
    </div>
  );
}
