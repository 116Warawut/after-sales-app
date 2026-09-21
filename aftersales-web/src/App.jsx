import React, { useState, useEffect, useMemo } from "react";
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
import { getSessionAdmin, SESSION_KEY, isMainAdmin } from "./services/session";
import { getEffectiveRepairStatus } from "./shared/constants";
import { logoutAdmin } from "./services/firebaseDb";
import { onAuthStateChanged } from "firebase/auth";
import { auth } from "./firebase";
import useDbList from "./hooks/useDbList";
import useWebSettings from "./hooks/useWebSettings";
import useSessionGuard from "./hooks/useSessionGuard";
import { applyTheme } from "./theme";
import { CallProvider } from "./contexts/CallContext";

function saveSession(admin) {
  const { password, ...safeAdmin } = admin || {};
  localStorage.setItem(SESSION_KEY, JSON.stringify(safeAdmin));
}

function clearSession() {
  localStorage.removeItem(SESSION_KEY);
}

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
  const [jobsInitialTab, setJobsInitialTab] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [pageInitialQuery, setPageInitialQuery] = useState({});

  function handleNavigate(page, options) {
    if (page === "jobs" && options?.tab) {
      setJobsInitialTab(options.tab);
    } else if (page === "jobs") {
      setJobsInitialTab(null);
    }
    setPageInitialQuery((prev) => ({ ...prev, [page]: options?.query }));
    setActivePage(page);
  }

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
  const { data: notifications = [] } = useDbList("notifications");
  const { data: chatMessages = [] } = useDbList("chat_messages");
  const { data: repairs = [] } = useDbList("repairs");
  const { data: partRequests = [] } = useDbList("part_requests");

  const { settings: webSettings } = useWebSettings();
  useEffect(() => {
    applyTheme(webSettings.theme);
    return () => {
      applyTheme("light");
    };
  }, [webSettings.theme]);

  useSessionGuard(admin?.username, () => {
    window.alert("บัญชีนี้ถูกใช้ล็อกอินจากอุปกรณ์อื่น จึงออกจากระบบอุปกรณ์นี้โดยอัตโนมัติ");
    onLogout();
  });

  const unreadNotifications = notifications.filter(
    (n) => n.user_username === admin?.username && !(n.is_read === 1 || n.is_read === "1" || n.is_read === true)
  ).length;

  useEffect(() => {
    document.title = unreadNotifications > 0 ? `(${unreadNotifications}) AfterSales` : "AfterSales";
    return () => {
      document.title = "AfterSales";
    };
  }, [unreadNotifications]);

  const isMain = isMainAdmin(admin);

  const visibleRepairs = useMemo(() => {
    if (!repairs || !Array.isArray(repairs)) return [];
    if (isMain) return repairs;
    return repairs.filter(
      (r) =>
        r.admin_username === admin?.username ||
        !r.admin_username ||
        r.admin_username === ""
    );
  }, [repairs, isMain, admin?.username]);

  const allowedRepairIds = useMemo(() => {
    return new Set(visibleRepairs.map((r) => String(r.id ?? r.record_id ?? "")));
  }, [visibleRepairs]);

  const visiblePartRequests = useMemo(() => {
    if (!partRequests || !Array.isArray(partRequests)) return [];
    if (isMain) return partRequests;
    return partRequests.filter(
      (p) => !p.repair_id || allowedRepairIds.has(String(p.repair_id))
    );
  }, [partRequests, isMain, allowedRepairIds]);

  // 🔒 ดึงรหัสงานซ่อมที่แอดมินคนนี้รับผิดชอบในห้องแชท (ตามกฎ 1 งาน มีแอดมินรับผิดชอบ 1 คน)
  const myChatRepairIds = useMemo(() => {
    if (!admin?.username || !Array.isArray(repairs)) return new Set();
    const myRepairs = repairs.filter((r) => r.admin_username === admin.username);
    const idSet = new Set();
    myRepairs.forEach((r) => {
      if (r.id != null) {
        const idStr = String(r.id).trim();
        idSet.add(idStr);
        idSet.add(idStr.replace(/^[kK]/, ""));
      }
      if (r.record_id != null) {
        const recStr = String(r.record_id).trim();
        idSet.add(recStr);
        idSet.add(recStr.replace(/^[kK]/, ""));
      }
    });
    return idSet;
  }, [repairs, admin?.username]);

  // 💬 นับเฉพาะข้อความแชทที่ยังไม่อ่าน ในงานซ่อมที่แอดมินคนนี้รับผิดชอบเท่านั้น
  // (ไม่นับงานของแอดมินคนอื่น ป้องกันตัวเลขค้างหรือตามไปโผล่บัญชีอื่น)
  const unreadChats = useMemo(() => {
    if (!admin?.username || myChatRepairIds.size === 0) return 0;
    return chatMessages.filter((m) => {
      if (m.sender_username === admin.username) return false;
      const isRead = m.is_read === 1 || m.is_read === "1" || m.is_read === true;
      if (isRead) return false;
      const repairIdStr = String(m.repair_id ?? "").trim();
      const cleanRepairId = repairIdStr.replace(/^[kK]/, "");
      return myChatRepairIds.has(repairIdStr) || myChatRepairIds.has(cleanRepairId);
    }).length;
  }, [chatMessages, admin?.username, myChatRepairIds]);

  const unreadJobs = visibleRepairs.filter(
    (r) => getEffectiveRepairStatus(r) === "รอจัดสรรช่าง"
  ).length;

  const unreadParts = visiblePartRequests.filter((p) => p.status === "รอดำเนินการ").length;

  const unreadFinance = visibleRepairs.filter(
    (r) => Number(r.total_price) > 0 && !(r.is_paid === 1 || r.is_paid === true)
  ).length;

  const ActivePageComponent = PAGES[activePage];
  const meta = PAGE_META[activePage];

  return (
    <CallProvider admin={admin}>
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
          <NotificationToasts
            notifications={notifications}
            currentUsername={admin?.username}
            onNavigate={onNavigate}
            showToastPopup={webSettings.notifyToastPopup}
            showDesktopPopup={webSettings.notifyDesktopPopup}
          />
        </main>
      </div>
    </CallProvider>
  );
}