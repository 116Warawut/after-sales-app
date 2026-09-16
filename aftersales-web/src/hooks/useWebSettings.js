import { useEffect, useState } from "react";
import { getPersonalSettings } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";

// ค่าเริ่มต้น (ต้องตรงกับ DEFAULT_PERSONAL_SETTINGS ใน SettingsPage.jsx) — ใส่
// ไว้ที่นี่ด้วยเผื่อหน้าอื่นเรียก useWebSettings() ก่อนที่แอดมินคนนั้นจะเคยเปิด
// หน้าตั้งค่าเลยสักครั้ง (ยังไม่เคยมีค่าส่วนตัวถูกเซฟไว้มาก่อน)
const DEFAULTS = {
  itemsPerPageDashboard: "10",
  itemsPerPageJobs: "20",
  itemsPerPageParts: "20",
  itemsPerPageFinance: "20",
  itemsPerPageNotifications: "20",
  theme: "light",
  notifyToastPopup: true,
  notifyDesktopPopup: true,
};

/**
 * ดึงค่า "ตั้งค่าส่วนตัว" ของแอดมินที่ล็อกอินอยู่ตอนนี้ (แยกคนละชุดต่อ username
 * ไม่ใช่ค่ารวมของทั้งบริษัทอีกต่อไป) — เช่น จำนวนรายการต่อหน้า, ธีมสี ดึงครั้ง
 * เดียวตอน mount (เหมือนวิธีที่ SettingsPage.jsx
 * ใช้อยู่แล้ว ไม่ใช่ realtime listener — ถ้าอยากได้ค่าล่าสุดหลังไปแก้ที่หน้า
 * ตั้งค่า ต้องรีเฟรชหน้านี้ใหม่) 🔴 [แก้ไข] เดิมอ่านจาก getWebSettings() ซึ่ง
 * เป็นค่ารวมของทุกแอดมิน ทำให้แอดมินคนหนึ่งเปลี่ยนธีม/ค่าอื่นแล้วกระทบกับทุก
 * คนที่ล็อกอินอยู่ไปด้วย — เปลี่ยนมาอ่านจาก getPersonalSettings(username) ตาม
 * username ของแอดมินที่ล็อกอินอยู่ในเครื่องนี้แทน (จาก getSessionAdmin())
 */
export default function useWebSettings() {
  const [settings, setSettings] = useState(DEFAULTS);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    const username = getSessionAdmin()?.username;
    getPersonalSettings(username).then((data) => {
      if (mounted) setSettings({ ...DEFAULTS, ...data });
      if (mounted) setLoading(false);
    });
    return () => {
      mounted = false;
    };
  }, []);

  return { settings, loading };
}
