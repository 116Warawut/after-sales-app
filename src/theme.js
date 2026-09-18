// 🆕 สลับโหมดมืด/สว่างของทั้งเว็บ — ใส่/เอา class "dark" ออกจาก <html> ตรงๆ
// (ไม่ผ่าน state ของ React) เพราะ Tailwind's darkMode:"class" อ่าน class นี้จาก
// ancestor element ไหนก็ได้ ทำแบบนี้เรียกใช้ได้จากทุกที่ (ตอนแอปเปิดครั้งแรก,
// ตอนกดบันทึกในหน้าตั้งค่า) โดยไม่ต้องส่ง prop ลอดผ่านทุกชั้นของ component tree
export function applyTheme(theme) {
  const isDark = theme === "dark";
  document.documentElement.classList.toggle("dark", isDark);
}
