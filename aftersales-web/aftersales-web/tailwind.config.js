/** @type {import('tailwindcss').Config} */
export default {
  content: ["./index.html", "./src/**/*.{js,jsx}"],
  // 🆕 เปิดโหมดมืดแบบอิง class (".dark" บน <html>) แทนการอิง prefers-color-scheme
  // ของเครื่อง เพราะต้องสลับตามค่าที่ผู้ใช้เลือกไว้ในหน้าตั้งค่า ไม่ใช่ตาม OS
  darkMode: "class",
  theme: {
    extend: {},
  },
  plugins: [],
};
