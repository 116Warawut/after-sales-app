import React, { useState, useEffect } from "react";
import Sidebar from "./components/Sidebar";
import Header from "./components/Header";
import NotificationToasts from "./components/NotificationToasts";
import LoginPage from "./pages/LoginPage";
import DashboardPage from "./pages/DashboardPage";
import RepairJobsPage from "./pages/RepairJobsPage";
import TechniciansPage from "./pages/TechniciansPage";
import CustomersPage from "./pages/CustomersPage";
import SparePartsPage from "./pages/SparePartsPage";
import ChatPage from "./pages/ChatPage";
import FinancePage from "./pages/FinancePage";
import NotificationsPage from "./pages/NotificationsPage";
import ActivityLogPage from "./pages/ActivityLogPage";
import SettingsPage from "./pages/SettingsPage";
import { getSessionAdmin, SESSION_KEY } from "./services/session";
import { logoutAdmin } from "./services/firebaseDb";
import { onAuthStateChanged } from "firebase/auth";
import { auth } from "./firebase";
import useDbList from "./hooks/useDbList";
import useWebSettings from "./hooks/useWebSettings";
import useSessionGuard from "./hooks/useSessionGuard";
import { applyTheme } from "./theme";

// เก็บ session ไว้ใน localStorage เพื่อไม่ให้ต้องล็อกอินใหม่ทุกครั้งที่รีเฟรชหน้า
// (เทียบเท่า SessionStorage ฝั่ง Flutter) — เก็บเฉพาะข้อมูลแอดมินที่ไม่อ่อนไหว
// ไม่เก็บรหัสผ่านไว้ที่นี่
function saveSession(admin) {
  const { password, ...safeAdmin } = admin || {};
  localStorage.setItem(SESSION_KEY, JSON.stringify(safeAdmin));
}

function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

// หัวข้อ/คำอธิบายบนสุดของแต่ละหน้า (โชว์ใน Header) — แยกจาก PageHeader ในตัวเนื้อหา
// เพราะ Header บนสุดใช้เป็น "คำทักทาย" รวม ส่วน PageHeader ในแต่ละหน้าใช้บอกว่า
// หน้านี้คือหน้าอะไรอีกที
const PAGE_META = {
  dashboard: { greeting: "สวัสดี Admin", subtitle: "ภาพรวมระบบ" },
  jobs: { greeting: "งานซ่อม", subtitle: "จัดการงานซ่อมทั้งหมด" },
  technicians: { greeting: "ช่างเทคนิค", subtitle: "จัดการช่างเทคนิคทั้งหมด" },
  customers: { greeting: "ลูกค้า", subtitle: "จัดการข้อมูลลูกค้า" },
  parts: { greeting: "อะไหล่", subtitle: "คลังอะไหล่และคำขอเบิกอะไหล่" },
  chat: { greeting: "แชท", subtitle: "สนทนากับลูกค้าและช่างเทคนิค" },
  finance: { greeting: "การเงิน", subtitle: "ใบแจ้งหนี้และสถานะการชำระเงิน" },
  notifications: { greeting: "แจ้งเตือน", subtitle: "การแจ้งเตือนทั้งหมด" },
  activity: { greeting: "ประวัติการใช้งาน", subtitle: "บันทึกการกระทำของแอดมินในระบบ" },
  settings: { greeting: "ตั้งค่า", subtitle: "ตั้งค่าระบบ" },
};

const PAGES = {
  dashboard: DashboardPage,
  jobs: RepairJobsPage,
  technicians: TechniciansPage,
  customers: CustomersPage,
  parts: SparePartsPage,
  chat: ChatPage,
  finance: FinancePage,
  notifications: NotificationsPage,
  activity: ActivityLogPage,
  settings: SettingsPage,
};

export default function App() {
  const [admin, setAdmin] = useState(null);
  const [checkingSession, setCheckingSession] = useState(true);
  const [activePage, setActivePage] = useState("dashboard");
  // 🔴 [แก้ไข] ตัวกรองแท็บเริ่มต้นของหน้า "งานซ่อม" — ใช้ตอนกดปุ่ม "ดูงาน" จาก
  // การ์ด "งานที่ต้องติดตาม" ในหน้าแรก จะได้เด้งมาหน้างานซ่อมพร้อมกรองแท็บที่
  // ตรงกับหมวดที่กดมาให้เลย ไม่ต้องมากดกรองเองซ้ำ
  const [jobsInitialTab, setJobsInitialTab] = useState(null);
  // 🔴 [แก้ไข] state เปิด/ปิดแถบเมนูซ้ายบนจอเล็ก (มือถือ/แท็บเล็ต) — จอใหญ่ตั้งแต่
  // lg ขึ้นไปไม่ใช้ค่านี้เลย (Sidebar ตรึงไว้เสมอ)
  const [sidebarOpen, setSidebarOpen] = useState(false);
  // 🔴 [แก้ไข] คำค้นเริ่มต้นของแต่ละหน้า — ใช้ตอนกดผลลัพธ์จากช่องค้นหากลางใน
  // Header (ค้นงานซ่อม/ลูกค้า/ช่างข้ามหน้าได้จากที่เดียว) เก็บแยกตามหน้าเพราะ
  // แต่ละหน้ามีช่องค้นหาของตัวเองอยู่แล้ว แค่ต้องการ "ส่งคำค้นเริ่มต้น" เข้าไป
  const [pageInitialQuery, setPageInitialQuery] = useState({});

  function handleNavigate(page, options) {
    if (page === "jobs" && options?.tab) {
      setJobsInitialTab(options.tab);
    } else if (page === "jobs") {
      setJobsInitialTab(null);
    }
    if (options?.query !== undefined) {
      setPageInitialQuery((prev) => ({ ...prev, [page]: options.query }));
    }
    setActivePage(page);
  }

  // 🔐 [แก้ไข] เดิมเช็ค session จาก localStorage แบบทันที (synchronous) แล้ว
  // โชว์หน้าแอดมิน/ดึงข้อมูลเลย — แต่ Firebase Auth (ตัวจริงที่ Rules ใช้เช็ค
  // auth.token.role) ต้อง restore session แบบ asynchronous ตอนโหลดหน้าเว็บ
  // ถ้าหน้าไหนดึงข้อมูลไวกว่า Firebase Auth restore เสร็จ จะโดน permission
  // denied ค้างว่างไปเลย (ไม่ retry เองด้วย) — เปลี่ยนมารอ onAuthStateChanged
  // ยืนยันว่ามี Firebase user จริงก่อน ค่อยโชว์หน้า/ปล่อยให้ดึงข้อมูล
  useEffect(() => {
    const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
      if (firebaseUser) {
        setAdmin(getSessionAdmin());
      } else {
        setAdmin(null);
        clearSession();
      }
      setCheckingSession(false);
    });
    return unsubscribe;
  }, []);

  function handleLogin(adminData) {
    saveSession(adminData);
    setAdmin(adminData);
  }

  function handleLogout() {
    // 🔐 ต้อง sign out ออกจาก Firebase Auth ด้วย ไม่งั้น auth.token.role เก่า
    // จะยังค้างอยู่ในเบราว์เซอร์ แม้ localStorage session จะถูกล้างไปแล้วก็ตาม
    logoutAdmin();
    clearSession();
    setAdmin(null);
    setActivePage("dashboard");
  }

  if (checkingSession) {
    return <div className="min-h-screen bg-slate-50" />;
  }

  if (!admin) {
    return <LoginPage onLogin={handleLogin} />;
  }

  return (
    <AuthenticatedShell
      admin={admin}
      activePage={activePage}
      onNavigate={handleNavigate}
      onLogout={handleLogout}
      jobsInitialTab={jobsInitialTab}
      pageInitialQuery={pageInitialQuery}
      sidebarOpen={sidebarOpen}
      onOpenSidebar={() => setSidebarOpen(true)}
      onCloseSidebar={() => setSidebarOpen(false)}
    />
  );
}

// 🔴 [แก้ไข] แยก shell หลังล็อกอินออกมาเป็นคอมโพเนนต์ของตัวเอง เพื่อให้เรียก
// useDbList (แจ้งเตือน + ข้อความแชท สำหรับ badge ตัวเลขที่ยังไม่อ่าน) ได้เฉพาะ
// ตอนล็อกอินแล้วเท่านั้น — ถ้าดึงไว้ใน App() ตรง ๆ จะยิง listener ทั้งสองตาราง
// ทิ้งไว้ตั้งแต่ก่อนล็อกอินด้วย (ตอนนั้นค่า admin ยังเป็น null) ซึ่งไม่จำเป็นและ
// สิ้นเปลือง ค่าที่ได้ (unreadNotifications, unreadChats) ใช้ร่วมกันทั้ง Sidebar
// (badge ตัวเลขบนเมนู "แจ้งเตือน"/"แชท" ทางซ้าย) และ Header (badge บนไอคอน
// กระดิ่ง/แชทมุมขวาบน) ดึงข้อมูลจุดเดียวพอ ไม่ต้องแยกดึงคนละที่
function AuthenticatedShell({
  admin,
  activePage,
  onNavigate,
  onLogout,
  jobsInitialTab,
  pageInitialQuery,
  sidebarOpen,
  onOpenSidebar,
  onCloseSidebar,
}) {
  const { data: notifications } = useDbList("notifications");
  const { data: chatMessages } = useDbList("chat_messages");
  // 🔴 [ใหม่] ดึงเพิ่มอีก 2 ตาราง สำหรับ badge ตัวเลขของเมนู "งานซ่อม", "อะไหล่",
  // "การเงิน" — repairs ใช้ได้ทั้งงานซ่อม (นับงานที่ยังไม่จัดสรรช่าง) และการเงิน
  // (นับใบแจ้งหนี้ที่ยังไม่ชำระ) ในทีเดียว ไม่ต้องดึงซ้ำ
  const { data: repairs } = useDbList("repairs");
  const { data: partRequests } = useDbList("part_requests");
  // 🆕 อ่านธีมสีที่ตั้งไว้ในหน้าตั้งค่า แล้วใส่/เอา class "dark" ออกจาก <html>
  // ตอนแอปโหลดเสร็จ (การสลับธีมแบบสดหลังกดบันทึกในหน้าตั้งค่า ทำแยกไว้ที่
  // SettingsPage.jsx เอง ไม่ต้องรอโหลดหน้าใหม่)
  // 🔴 [แก้ไข] ธีมมืด/สว่างเป็นค่าที่ตั้งไว้ "หลังล็อกอิน" เท่านั้น (ต่อไปควร
  // จะเป็นการตั้งค่าเฉพาะของแต่ละผู้ใช้ ไม่ใช่ตั้งรวมบังคับทุกคน) หน้า Login
  // ไม่ควรเปลี่ยนสีตามธีมที่เคยตั้งไว้ก่อนหน้าเลย — เดิมโค้ดนี้ใส่ class "dark"
  // แล้วไม่เคยเอาออกตอน component นี้ unmount (ตอน logout) เลย ถ้าเคยเปิดโหมด
  // มืดไว้ พอ logout กลับไปหน้า Login จะยังติดโหมดมืดค้างอยู่ เพิ่ม cleanup
  // ให้เอา class "dark" ออกตอน unmount เสมอ หน้า Login เลยจะเป็นสีเดิมคงที่
  // ไม่ว่าผู้ใช้ก่อนหน้าจะตั้งธีมอะไรไว้ก็ตาม
  const { settings: webSettings } = useWebSettings();
  useEffect(() => {
    applyTheme(webSettings.theme);
    return () => {
      applyTheme("light");
    };
  }, [webSettings.theme]);

  // 🆕 [ใหม่] บังคับ "ล็อกอินได้ทีละอุปกรณ์" ตามค่าตั้งค่าส่วนตัวของบัญชีนี้
  // (allowMultiDeviceLogin) — ถ้าปิดไว้ แล้วมีอุปกรณ์อื่นล็อกอินทับเข้ามา จะ
  // เด้งแจ้งเตือนแล้วออกจากระบบอัตโนมัติทันที (ดูรายละเอียดที่ useSessionGuard.js)
  useSessionGuard(admin?.username, () => {
    window.alert("บัญชีนี้ถูกใช้ล็อกอินจากอุปกรณ์อื่น จึงออกจากระบบอุปกรณ์นี้โดยอัตโนมัติ");
    onLogout();
  });

  const unreadNotifications = notifications.filter(
    (n) => n.user_username === admin?.username && !n.is_read
  ).length;

  // 🆕 โชว์จำนวนแจ้งเตือนที่ยังไม่อ่านไว้หน้าชื่อแท็บเบราว์เซอร์ แบบเดียวกับ
  // IG/Facebook/YouTube — ใช้ตัวเลขเดียวกับ badge กระดิ่งแจ้งเตือนใน Header
  // เป๊ะ (unreadNotifications ตัวเดียวกัน) ถ้าไม่มีเลยก็กลับไปเป็น "AfterSales"
  // เฉยๆ ไม่ต้องมีวงเล็บ (0) ห้อยอยู่
  useEffect(() => {
    document.title = unreadNotifications > 0 ? `(${unreadNotifications}) AfterSales` : "AfterSales";
    // ล้างกลับเป็นชื่อธรรมดาตอนออกจากระบบ (component นี้ unmount) กันไม่ให้
    // ตัวเลขค้างอยู่บนแท็บทั้งที่กลับไปหน้า login แล้ว
    return () => {
      document.title = "AfterSales";
    };
  }, [unreadNotifications]);

  const unreadChats = chatMessages.filter(
    (m) => m.sender_username !== admin?.username && !m.is_read
  ).length;
  // 🔴 [ใหม่] "งานซ่อม" = จำนวนงานที่ยังไม่ได้จัดสรรช่าง (status จริงคือ
  // "รอดำเนินการ" — เช็กกับ lib/services.dart แล้ว ไม่ใช่ "รอจัดสรรช่าง" ซึ่ง
  // เป็นแค่ label ที่โชว์บนจอ) ต้องมีคนมาจัดสรรช่างให้ ถือเป็นงานที่ "รอดำเนินการ
  // จากแอดมิน" เหมือนกับแจ้งเตือน/ข้อความที่ยังไม่อ่าน
  const unreadJobs = repairs.filter((r) => r.status === "รอดำเนินการ").length;
  // 🔴 [ใหม่] "อะไหล่" = จำนวนคำขอเบิกอะไหล่ที่รออนุมัติ
  const unreadParts = partRequests.filter((p) => p.status === "รอดำเนินการ").length;
  // 🔴 [ใหม่] "การเงิน" = จำนวนใบแจ้งหนี้ที่ออกแล้วแต่ยังไม่ได้ชำระ (total_price
  // ตั้งไว้แล้ว แต่ is_paid ยังไม่เป็นจริง)
  const unreadFinance = repairs.filter(
    (r) => Number(r.total_price) > 0 && !(r.is_paid === 1 || r.is_paid === true)
  ).length;

  const ActivePageComponent = PAGES[activePage];
  const meta = PAGE_META[activePage];

  return (
    <div className="flex h-screen bg-slate-50 font-sans overflow-hidden">
      <Sidebar
        activePage={activePage}
        onNavigate={onNavigate}
        onLogout={onLogout}
        open={sidebarOpen}
        onClose={onCloseSidebar}
        unreadNotifications={unreadNotifications}
        unreadChats={unreadChats}
        unreadJobs={unreadJobs}
        unreadParts={unreadParts}
        unreadFinance={unreadFinance}
      />
      <main className="flex-1 overflow-y-auto w-full">
        <Header
          greeting={meta.greeting}
          subtitle={meta.subtitle}
          admin={admin}
          onNavigate={onNavigate}
          onMenuClick={onOpenSidebar}
          unreadNotifications={unreadNotifications}
          unreadChats={unreadChats}
        />
        <div className="px-4 sm:px-8 pb-10">
          <ActivePageComponent
            onNavigate={onNavigate}
            initialTab={activePage === "jobs" ? jobsInitialTab : undefined}
            initialQuery={pageInitialQuery[activePage]}
          />
        </div>
        {/* 🆕 แจ้งเตือน popup มุมขวาล่าง โผล่ขึ้นมาเองทุกครั้งที่มีแจ้งเตือนใหม่
            เข้ามา ไม่ว่าจะอยู่หน้าไหนของเว็บ (mount ไว้ในนี้ ไม่ใช่ในหน้าใด
            หน้าหนึ่ง เพราะงั้นสลับหน้าไปมาจะยังเห็นอยู่เสมอ — ต้องอยู่ใน
            <main> ด้วย ไม่ใช่นอก <main> เพราะกฎสีโหมดมืดของการ์ดพื้นขาว
            (.dark main .bg-white) กันไม่ให้ไปโดน Sidebar สโคปไว้แค่ในนี้) */}
        <NotificationToasts
          notifications={notifications}
          currentUsername={admin?.username}
          onNavigate={onNavigate}
          showToastPopup={webSettings.notifyToastPopup}
          showDesktopPopup={webSettings.notifyDesktopPopup}
        />
      </main>
    </div>
  );
}