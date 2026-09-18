import { useEffect, useState } from "react";

// 🆕 [ใหม่] ข้อมูล จังหวัด/อำเภอ/ตำบล (พร้อมรหัสไปรษณีย์) ของทั้งประเทศไทย
// (77 จังหวัด, 928 อำเภอ/เขต, 7,400+ ตำบล/แขวง) มีขนาดใหญ่เกินกว่าจะฝังไว้ใน
// ซอร์สโค้ดของเว็บตรงๆ (จะทำให้ไฟล์โปรเจกต์บวมหลายร้อย KB โดยไม่จำเป็น) —
// เว็บนี้จึงดึงข้อมูลชุดนี้จาก GitHub Raw ตรงๆ ตอนเปิดฟอร์มที่อยู่ครั้งแรก
// (เบราว์เซอร์ของผู้ใช้มีอินเทอร์เน็ตอยู่แล้ว ไม่เหมือนเครื่องมือของเรา) แล้ว
// เก็บแคชไว้ในหน่วยความจำของหน้าเว็บ (module-level cache) ไม่ต้องโหลดซ้ำทุก
// ครั้งที่เปิดฟอร์ม เปิดครั้งเดียวต่อการรีเฟรชหน้าเว็บ 1 ครั้งพอ
//
// แหล่งข้อมูล: kongvut/thai-province-data (MIT License) — เป็นชุดข้อมูลจังหวัด/
// อำเภอ/ตำบลของไทยที่เปิดเผยสาธารณะ อัปเดตตามกรมการปกครอง
const THAI_ADDRESS_URL =
  "https://raw.githubusercontent.com/kongvut/thai-province-data/refs/heads/master/api/latest/province_with_district_and_sub_district.json";

let cachedProvinces = null;
let cachedError = null;
let inFlightPromise = null;

function loadThaiAddressData() {
  if (cachedProvinces) return Promise.resolve(cachedProvinces);
  if (!inFlightPromise) {
    inFlightPromise = fetch(THAI_ADDRESS_URL)
      .then((res) => {
        if (!res.ok) throw new Error(`โหลดข้อมูลที่อยู่ไม่สำเร็จ (${res.status})`);
        return res.json();
      })
      .then((data) => {
        cachedProvinces = Array.isArray(data) ? data : [];
        return cachedProvinces;
      })
      .catch((err) => {
        cachedError = err;
        inFlightPromise = null; // เปิดทางให้ลองใหม่ได้ถ้าเปิดฟอร์มอีกครั้ง
        throw err;
      });
  }
  return inFlightPromise;
}

// คืนค่า { provinces, loading, error }
// provinces: [{ id, name_th, name_en, districts: [{ id, name_th, name_en,
//   sub_districts: [{ id, name_th, name_en, zip_code }] }] }]
export default function useThaiAddress() {
  const [provinces, setProvinces] = useState(cachedProvinces || []);
  const [loading, setLoading] = useState(!cachedProvinces);
  const [error, setError] = useState(cachedError);

  useEffect(() => {
    if (cachedProvinces) return;
    let alive = true;
    setLoading(true);
    loadThaiAddressData()
      .then((data) => {
        if (alive) {
          setProvinces(data);
          setLoading(false);
        }
      })
      .catch((err) => {
        if (alive) {
          setError(err);
          setLoading(false);
        }
      });
    return () => {
      alive = false;
    };
  }, []);

  return { provinces, loading, error };
}
