const SESSION_KEY = "aftersales_admin_session";

/** บันทึกข้อมูลแอดมินลงใน localStorage */
export function setSessionAdmin(admin) {
  try {
    if (!admin) {
      localStorage.removeItem(SESSION_KEY);
    } else {
      localStorage.setItem(SESSION_KEY, JSON.stringify(admin));
    }
  } catch (err) {
    console.error("[session] setSessionAdmin failed:", err);
  }
}

/** อ่านข้อมูลแอดมินที่ล็อกอินอยู่ตอนนี้จาก localStorage (username, admin_name, admin_type ฯลฯ) */
export function getSessionAdmin() {
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

/** ตรวจสอบว่าเป็นแอดมินหลัก (Main Admin) หรือไม่ */
export function isMainAdmin(admin = getSessionAdmin()) {
  if (!admin) return false;
  // ค่าเริ่มต้นเป็น 'main' เพื่อรองรับบัญชีเก่าก่อนมี field admin_type
  return (admin.admin_type || "main") === "main";
}

/** ดึงประเภทแอดมิน ('main' | 'general') */
export function getAdminType(admin = getSessionAdmin()) {
  if (!admin) return "general";
  return admin.admin_type || "main";
}

// 🆕 [ใหม่] "รหัสอุปกรณ์" ถาวรของเบราว์เซอร์นี้ — สุ่มครั้งเดียวแล้วเก็บไว้ใน
// localStorage ตลอดไป (ไม่เปลี่ยนแม้ล็อกเอาต์/ล็อกอินใหม่/รีเฟรชหน้า) ใช้แยก
// แยะว่า "อุปกรณ์นี้" กับ "อุปกรณ์อื่น" เป็นคนละเครื่องกันหรือไม่ — ใช้ทั้งกับ
// ฟีเจอร์บังคับล็อกอินได้ทีละอุปกรณ์ (allowMultiDeviceLogin) และแจ้งเตือนเมื่อ
// มีการเข้าสู่ระบบจากอุปกรณ์ใหม่ (notifyNewLogin) ในหน้าตั้งค่า
const DEVICE_ID_KEY = "aftersales_device_id";

export function getOrCreateDeviceId() {
  try {
    let id = localStorage.getItem(DEVICE_ID_KEY);
    if (!id) {
      id = window.crypto?.randomUUID
        ? window.crypto.randomUUID()
        : `dev-${Date.now()}-${Math.random().toString(36).slice(2)}`;
      localStorage.setItem(DEVICE_ID_KEY, id);
    }
    return id;
  } catch (err) {
    console.error("[session] getOrCreateDeviceId failed:", err);
    return `dev-${Date.now()}-${Math.random().toString(36).slice(2)}`;
  }
}

export { SESSION_KEY };