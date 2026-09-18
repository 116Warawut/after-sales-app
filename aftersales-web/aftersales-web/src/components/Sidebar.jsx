import React from "react";
import {
  LayoutDashboard,
  Wrench,
  Users,
  UserCog,
  Bell,
  Settings,
  LogOut,
  Package,
  MessageSquare,
  Wallet,
  History,
} from "lucide-react";

// 📋 รายการเมนูซ้าย — เรียงตามลำดับที่จะโชว์บนจอ (บนลงล่าง) อยากเพิ่ม/ลบ/สลับ
// ลำดับเมนู แก้ตรงนี้ที่เดียว ไม่ต้องไปแก้ในฟังก์ชัน Sidebar ด้านล่าง
// 🔴 [แก้ไข] เอา badge: 0 ตายตัวออกจาก "แจ้งเตือน" — เดิมเป็นเลขคงที่ 0 ตลอด
// ไม่เคยอัปเดตจริงเลย ตอนนี้คำนวณสดจาก unreadNotifications/unreadChats ที่ส่ง
// เข้ามาแทน (ดูใน Sidebar ด้านล่าง) เก็บไว้แค่ "รู้ว่าเมนูไหนควรมี badge" ผ่าน
// key ตรง ๆ ไม่ต้องมี field badge ในนี้อีกแล้ว
export const NAV_ITEMS = [
  { key: "dashboard", icon: LayoutDashboard, label: "Dashboard" },
  { key: "jobs", icon: Wrench, label: "งานซ่อม" },
  { key: "technicians", icon: UserCog, label: "ช่างเทคนิค" },
  { key: "customers", icon: Users, label: "ลูกค้า" },
  { key: "parts", icon: Package, label: "อะไหล่" },
  // 🔴 [แก้ไข] สลับลำดับ: "การเงิน" ย้ายมาอยู่เหนือ "แชท" ตามที่ขอ
  { key: "finance", icon: Wallet, label: "การเงิน" },
  { key: "chat", icon: MessageSquare, label: "แชท" },
  { key: "notifications", icon: Bell, label: "แจ้งเตือน" },
  // 🔴 [ลบ] เอาเมนู "รายงาน" ออกตามที่ขอ (ReportsPage.jsx ก็ลบทิ้งไปด้วย)
  // 📝 [ใหม่] "ประวัติการใช้งาน" — ดูว่าแอดมินคนไหนทำอะไรไปบ้าง
  { key: "activity", icon: History, label: "ประวัติการใช้งาน" },
  { key: "settings", icon: Settings, label: "ตั้งค่า" },
];

export default function Sidebar({
  activePage,
  onNavigate,
  onLogout,
  open,
  onClose,
  unreadNotifications = 0,
  unreadChats = 0,
  unreadJobs = 0,
  unreadParts = 0,
  unreadFinance = 0,
}) {
  // 🔴 [แก้ไข] เพิ่ม 3 เมนู "งานซ่อม"/"อะไหล่"/"การเงิน" เข้า badge map ด้วย
  // ตามที่ขอ — งานซ่อม = จำนวนงานที่ยังไม่จัดสรรช่าง, อะไหล่ = คำขอเบิกที่รอ
  // อนุมัติ, การเงิน = ใบแจ้งหนี้ที่ยังไม่ชำระ (คำนวณจริงใน App.jsx)
  const badgeByKey = {
    notifications: unreadNotifications,
    chat: unreadChats,
    jobs: unreadJobs,
    parts: unreadParts,
    finance: unreadFinance,
  };

  return (
    <>
      {/* 🔴 [แก้ไข] เพิ่มการรองรับจอเล็ก (มือถือ/แท็บเล็ต) — เดิมแถบเมนูเป็น
          w-64 คงที่เสมอ ไม่ยุบ ทำให้บนจอแคบเนื้อหาถูกบีบจนใช้งานไม่ได้ ตอนนี้
          บนจอเล็กกว่า lg (<1024px) แถบเมนูจะซ่อนไว้เป็น slide-in overlay แทน
          (เลื่อนออกจากซ้าย ปิดด้วยการกดฉากหลังมืดหรือเลือกเมนู) ส่วนจอใหญ่ตั้งแต่
          lg ขึ้นไปแสดงแถบเมนูตรึงไว้เหมือนเดิมทุกประการ ไม่มีอะไรเปลี่ยน */}
      {open ? (
        <div className="fixed inset-0 bg-slate-900/40 z-40 lg:hidden" onClick={onClose} />
      ) : null}
      <aside
        className={
          "w-64 shrink-0 bg-[#B22121] text-white/90 flex flex-col h-full fixed lg:static inset-y-0 left-0 z-50 transition-transform duration-200 " +
          (open ? "translate-x-0" : "-translate-x-full") +
          " lg:translate-x-0"
        }
      >
        <div className="flex items-center gap-2 px-5 py-5">
          {/* 🎨 bg-white + text-[#B22121] = โลโก้วงกลม พื้นขาวตัวอักษรแดง (สลับสีกับ
              พื้นหลังแถบเมนู ให้เด่นออกมา) */}
          <div className="w-9 h-9 rounded-xl bg-white flex items-center justify-center text-[#B22121] font-bold text-sm">
            A
          </div>
          {/* 🔤 text-lg font-semibold = ชื่อแอป "AfterSales" ตัวหนาขนาดใหญ่กว่าเมนู */}
          <span className="text-white font-semibold text-lg">AfterSales</span>
        </div>

        <nav className="flex-1 px-3 py-2 space-y-1 overflow-y-auto">
          {NAV_ITEMS.map((item) => {
            const active = item.key === activePage;
            const badgeCount = badgeByKey[item.key] || 0;
            return (
              <button
                key={item.key}
                onClick={() => {
                  onNavigate(item.key);
                  onClose?.();
                }}
                // 🎨 เมนูที่กำลังเลือกอยู่ (active) = พื้นขาว ตัวอักษรแดง (สลับสีเด่นชัด)
                // เมนูปกติ = ตัวอักษรขาวโปร่งแสงเล็กน้อย (white/90) พื้นหลังใส
                // hover:bg-white/15 = พื้นหลังขาวจาง ๆ ตอนเอาเมาส์ชี้ (ยังไม่กด)
                // 🔤 text-[15px] = ขนาดตัวอักษรเมนู (ปรับใหญ่กว่ามาตรฐานเพื่อให้อ่านง่าย)
                className={
                  "w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[15px] transition-colors " +
                  (active
                    ? "bg-white text-[#B22121] font-semibold"
                    : "text-white/90 font-medium hover:bg-white/15 hover:text-white")
                }
              >
                <item.icon size={19} className="shrink-0" />
                <span className="flex-1 text-left">{item.label}</span>
                {badgeCount > 0 ? (
                  // 🎨 ตัวเลข badge วงกลม (จำนวนแจ้งเตือน/ข้อความแชทที่ยังไม่อ่าน)
                  // พื้นขาว ตัวอักษรแดง ให้เด่นออกมาจากพื้นหลังแถบเมนูสีแดง —
                  // 🔴 [แก้ไข] เกิน 99 ให้ตัดเหลือ "99+" กันเลขยาวจนบีบเมนูจนแตก
                  <span className="text-[11px] font-semibold bg-white text-[#B22121] rounded-full min-w-[20px] h-5 px-1 flex items-center justify-center">
                    {badgeCount > 99 ? "99+" : badgeCount}
                  </span>
                ) : null}
              </button>
            );
          })}
        </nav>

        <div className="px-3 pb-4">
          {/* ปุ่ม "ออกจากระบบ" ล่างสุด — ใช้สไตล์เดียวกับเมนูปกติ (ไม่ active) */}
          <button
            onClick={onLogout}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-[15px] text-white/90 font-medium hover:bg-white/15 hover:text-white transition-colors"
          >
            <LogOut size={19} />
            ออกจากระบบ
          </button>
        </div>
      </aside>
    </>
  );
}
