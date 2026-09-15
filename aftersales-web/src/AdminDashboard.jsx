import React from "react";
import {
  LayoutDashboard,
  Wrench,
  Users,
  UserCog,
  Bell,
  BarChart3,
  Settings,
  Search,
  MessageSquare,
  ChevronDown,
  LogOut,
  ClipboardList,
  UserPlus,
  CheckCircle2,
  AlertTriangle,
  Clock,
  MessageCircle,
  HelpCircle,
  CalendarClock,
  MoreVertical,
} from "lucide-react";
import {
  PieChart,
  Pie,
  Cell,
  ResponsiveContainer,
} from "recharts";

// ---------------------------------------------------------------------------
// ข้อมูล — ตอนนี้เป็นค่าว่าง/0 ทั้งหมด (ตัดข้อมูลจำลองออกแล้ว) รอเชื่อมต่อ Firebase
// จริงมาแทนที่ค่าพวกนี้ โครง component ด้านล่างรองรับค่าว่างไว้แล้ว ไม่ต้องแก้โครงสร้าง
// ---------------------------------------------------------------------------

const NAV_ITEMS = [
  { icon: LayoutDashboard, label: "Dashboard", active: true },
  { icon: Wrench, label: "งานซ่อม" },
  { icon: UserCog, label: "ช่างเทคนิค" },
  { icon: Users, label: "ลูกค้า" },
  { icon: Bell, label: "แจ้งเตือน", badge: 0 },
  { icon: BarChart3, label: "รายงาน" },
  { icon: Settings, label: "ตั้งค่า" },
];

const STAT_CARDS = [
  { icon: ClipboardList, label: "งานทั้งหมด", value: 0, unit: "งาน", delta: "", color: "blue" },
  { icon: UserPlus, label: "รอจัดสรรช่าง", value: 0, unit: "งาน", delta: "", color: "orange" },
  { icon: Wrench, label: "กำลังดำเนินการ", value: 0, unit: "งาน", delta: "", color: "violet" },
  { icon: CheckCircle2, label: "เสร็จสิ้นวันนี้", value: 0, unit: "งาน", delta: "", color: "green" },
  { icon: AlertTriangle, label: "เร่งด่วน", value: 0, unit: "งาน", delta: "", color: "red" },
];

const STATUS_STATS = [];

const FOLLOW_UP_ITEMS = [
  { icon: UserPlus, count: 0, label: "รอจัดสรรช่าง", sub: "งานที่รอการมอบหมายช่าง", color: "red" },
  { icon: Clock, count: 0, label: "รอการอัปเดตจากช่าง", sub: "ช่างยังไม่ได้อัปเดตสถานะตามกำหนด", color: "blue" },
  { icon: MessageCircle, count: 0, label: "รอการตอบกลับจากลูกค้า", sub: "รอยืนยันข้อมูล/นัดหมาย/อะไหล่", color: "violet" },
  { icon: HelpCircle, count: 0, label: "มีปัญหา / ต้องตรวจสอบ", sub: "งานที่มีปัญหาหรือแจ้งเหตุขัดข้อง", color: "blue" },
  { icon: CalendarClock, count: 0, label: "เกินกำหนดเวลา", sub: "งานที่เลยกำหนดระยะเวลาที่กำหนด", color: "orange" },
];

const NOTIFICATIONS = [];

const RECENT_JOBS = [];

const TECH_ONLINE_TOTAL = 0;
const TECH_ONLINE_MAX = 0;
const TECH_LEGEND = [
  { label: "กำลังเดินทาง", value: 0, color: "violet" },
  { label: "กำลังปฏิบัติงาน", value: 0, color: "orange" },
  { label: "ว่าง", value: 0, color: "green" },
  { label: "ออฟไลน์", value: 0, color: "gray" },
];

const COLORS = {
  blue: { bg: "bg-blue-50", text: "text-blue-600", dot: "bg-blue-500" },
  orange: { bg: "bg-orange-50", text: "text-orange-600", dot: "bg-orange-500" },
  violet: { bg: "bg-violet-50", text: "text-violet-600", dot: "bg-violet-500" },
  green: { bg: "bg-emerald-50", text: "text-emerald-600", dot: "bg-emerald-500" },
  red: { bg: "bg-red-50", text: "text-red-600", dot: "bg-red-500" },
  gray: { bg: "bg-gray-100", text: "text-gray-500", dot: "bg-gray-400" },
};

const STATUS_BADGE = {
  "กำลังดำเนินการ": "bg-blue-50 text-blue-600",
  "รอจัดสรรช่าง": "bg-orange-50 text-orange-600",
  "รอการตอบกลับลูกค้า": "bg-violet-50 text-violet-600",
  "เสร็จสิ้น": "bg-emerald-50 text-emerald-600",
  "มีปัญหา": "bg-red-50 text-red-600",
};

const URGENCY_BADGE = {
  "ปกติ": "bg-gray-100 text-gray-500",
  "สูง": "bg-red-50 text-red-600",
};

function Sidebar() {
  return (
    <aside className="w-64 shrink-0 bg-slate-950 text-slate-300 flex flex-col h-full">
      <div className="flex items-center gap-2 px-5 py-5">
        <div className="w-9 h-9 rounded-xl bg-blue-500 flex items-center justify-center text-white font-bold text-sm">
          A
        </div>
        <span className="text-white font-semibold text-lg">AfterSales</span>
      </div>

      <nav className="flex-1 px-3 py-2 space-y-1 overflow-y-auto">
        {NAV_ITEMS.map((item) => (
          <button
            key={item.label}
            className={
              "w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm transition-colors " +
              (item.active
                ? "bg-blue-500 text-white font-medium"
                : "text-slate-400 hover:bg-slate-900 hover:text-slate-200")
            }
          >
            <item.icon size={18} className="shrink-0" />
            <span className="flex-1 text-left">{item.label}</span>
            {item.badge ? (
              <span className="text-[11px] font-semibold bg-red-500 text-white rounded-full w-5 h-5 flex items-center justify-center">
                {item.badge}
              </span>
            ) : null}
          </button>
        ))}
      </nav>

      <div className="px-3 pb-4">
        <button className="w-full flex items-center gap-3 px-3 py-2.5 rounded-xl text-sm text-slate-400 hover:bg-slate-900 hover:text-slate-200 transition-colors">
          <LogOut size={18} />
          ออกจากระบบ
        </button>
      </div>
    </aside>
  );
}

function Header() {
  return (
    <header className="flex items-center justify-between px-8 py-6">
      <div>
        <h1 className="text-2xl font-semibold text-slate-900">สวัสดีแอดมิน</h1>
        <p className="text-sm text-slate-500 mt-0.5">ภาพรวมระบบ</p>
      </div>

      <div className="flex items-center gap-4">
        <div className="relative">
          <Search size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
          <input
            placeholder="ค้นหางาน, ลูกค้า, ช่าง, Job ID..."
            className="w-72 pl-9 pr-3 py-2 rounded-xl bg-white border border-slate-200 text-sm text-slate-600 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <button className="relative w-9 h-9 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-500 hover:bg-slate-50">
          <Bell size={17} />
        </button>

        <button className="relative w-9 h-9 rounded-xl bg-white border border-slate-200 flex items-center justify-center text-slate-500 hover:bg-slate-50">
          <MessageSquare size={17} />
        </button>

        <div className="flex items-center gap-2 pl-2">
          <div className="w-9 h-9 rounded-full bg-blue-500 text-white flex items-center justify-center text-sm font-semibold">
            A
          </div>
          <div className="leading-tight">
            <p className="text-sm font-medium text-slate-800">Admin</p>
            <p className="text-xs text-slate-400">ผู้ดูแลระบบ</p>
          </div>
        </div>
      </div>
    </header>
  );
}

function StatCard({ icon: Icon, label, value, unit, delta, color }) {
  const c = COLORS[color];
  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[180px]">
      <div className="flex items-center gap-2 mb-3">
        <div className={`w-9 h-9 rounded-xl ${c.bg} ${c.text} flex items-center justify-center`}>
          <Icon size={18} />
        </div>
        <span className="text-sm text-slate-500">{label}</span>
      </div>
      <div className="flex items-baseline gap-1 mb-1">
        <span className="text-2xl font-semibold text-slate-900">{value}</span>
        <span className="text-sm text-slate-400">{unit}</span>
      </div>
      {delta ? <p className={`text-xs ${c.text}`}>{delta}</p> : <p className="text-xs text-slate-300">—</p>}
    </div>
  );
}

function StatusAndFollowUpCard() {
  const total = STATUS_STATS.reduce((a, s) => a + s.value, 0);

  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-[1.4] min-w-[420px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">สถิติสถานะงานซ่อม</h3>
        <button className="flex items-center gap-1 text-xs text-slate-500 bg-slate-50 rounded-lg px-2 py-1">
          สัปดาห์นี้ <ChevronDown size={12} />
        </button>
      </div>

      <div className="flex gap-6">
        <div className="flex items-center gap-4 shrink-0 w-56">
          <div className="relative w-32 h-32 shrink-0">
            {total > 0 ? (
              <ResponsiveContainer width="100%" height="100%">
                <PieChart>
                  <Pie
                    data={STATUS_STATS}
                    dataKey="value"
                    innerRadius={40}
                    outerRadius={56}
                    paddingAngle={2}
                    stroke="none"
                  >
                    {STATUS_STATS.map((s, i) => (
                      <Cell key={i} fill={s.color} />
                    ))}
                  </Pie>
                </PieChart>
              </ResponsiveContainer>
            ) : (
              <div className="w-full h-full rounded-full border-[14px] border-slate-100" />
            )}
            <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
              <span className="text-lg font-semibold text-slate-900">{total}</span>
              <span className="text-[10px] text-slate-400 text-center leading-tight">งานทั้งหมด</span>
            </div>
          </div>
        </div>

        <div className="w-px bg-slate-100 shrink-0" />

        <div className="flex-1 min-w-0">
          <h4 className="text-xs font-semibold text-slate-500 mb-3">งานที่ต้องติดตาม</h4>
          <div className="space-y-2.5">
            {FOLLOW_UP_ITEMS.map((item) => {
              const c = COLORS[item.color];
              return (
                <div key={item.label} className="flex items-center gap-2.5">
                  <div className={`w-7 h-7 rounded-lg ${c.bg} ${c.text} flex items-center justify-center shrink-0`}>
                    <item.icon size={13} />
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-xs font-medium text-slate-800 truncate">
                      {item.count} งาน — {item.label}
                    </p>
                  </div>
                  <button className="text-[11px] text-blue-500 font-medium shrink-0 hover:text-blue-600">
                    ดูงาน
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}

function NotificationsCard() {
  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-1 min-w-[280px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">การแจ้งเตือนล่าสุด</h3>
        <button className="text-xs text-blue-500 font-medium hover:text-blue-600">ดูทั้งหมด</button>
      </div>
      {NOTIFICATIONS.length === 0 ? (
        <p className="text-xs text-slate-400 text-center py-8">ยังไม่มีการแจ้งเตือน</p>
      ) : (
        <div className="space-y-3">
          {NOTIFICATIONS.map((n, i) => {
            const c = COLORS[n.color];
            return (
              <div key={i} className="flex items-center gap-3">
                <div className={`w-9 h-9 rounded-xl ${c.bg} ${c.text} flex items-center justify-center shrink-0`}>
                  <n.icon size={16} />
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-slate-800 truncate">{n.title}</p>
                  <p className="text-xs text-slate-400 truncate">{n.sub}</p>
                </div>
                <span className="text-[11px] text-slate-400 shrink-0">{n.time}</span>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function RecentJobsTable() {
  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-[1.6] min-w-[420px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">งานล่าสุด</h3>
        <button className="text-xs text-blue-500 font-medium hover:text-blue-600">ดูงานทั้งหมด</button>
      </div>
      <div className="overflow-x-auto">
        <table className="w-full text-left text-sm">
          <thead>
            <tr className="text-xs text-slate-400 border-b border-slate-100">
              <th className="py-2 font-medium">Job ID</th>
              <th className="py-2 font-medium">ลูกค้า</th>
              <th className="py-2 font-medium">อุปกรณ์</th>
              <th className="py-2 font-medium">ช่าง</th>
              <th className="py-2 font-medium">วันที่สร้าง</th>
              <th className="py-2 font-medium">สถานะ</th>
              <th className="py-2 font-medium">ความเร่งด่วน</th>
              <th className="py-2 font-medium"></th>
            </tr>
          </thead>
          <tbody>
            {RECENT_JOBS.length === 0 ? (
              <tr>
                <td colSpan={8} className="py-8 text-center text-xs text-slate-400">
                  ยังไม่มีรายการงานซ่อม
                </td>
              </tr>
            ) : (
              RECENT_JOBS.map((job) => (
                <tr key={job.id} className="border-b border-slate-50 last:border-0">
                  <td className="py-3 font-medium text-slate-700">{job.id}</td>
                  <td className="py-3 text-slate-600">{job.customer}</td>
                  <td className="py-3 text-slate-600">{job.device}</td>
                  <td className="py-3 text-slate-600">{job.tech}</td>
                  <td className="py-3 text-slate-500">
                    <div>{job.date}</div>
                    <div className="text-xs text-slate-400">{job.time}</div>
                  </td>
                  <td className="py-3">
                    <span
                      className={`text-xs font-medium px-2.5 py-1 rounded-full ${
                        STATUS_BADGE[job.status] ?? "bg-gray-100 text-gray-500"
                      }`}
                    >
                      {job.status}
                    </span>
                  </td>
                  <td className="py-3">
                    <span
                      className={`text-xs font-medium px-2.5 py-1 rounded-full ${
                        URGENCY_BADGE[job.urgency] ?? "bg-gray-100 text-gray-500"
                      }`}
                    >
                      {job.urgency}
                    </span>
                  </td>
                  <td className="py-3 text-right">
                    <button className="text-slate-300 hover:text-slate-500">
                      <MoreVertical size={16} />
                    </button>
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function TechOnlineCard() {
  return (
    <div className="bg-white rounded-2xl border border-slate-100 p-5 flex-1 min-w-[280px]">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-semibold text-slate-800">ช่างออนไลน์</h3>
        <span className="text-sm font-semibold text-slate-700">
          {TECH_ONLINE_TOTAL} / {TECH_ONLINE_MAX} คน
        </span>
      </div>
      <div className="space-y-3">
        {TECH_LEGEND.map((t) => (
          <div key={t.label} className="flex items-center justify-between text-sm">
            <span className="flex items-center gap-2 text-slate-600">
              <span className={`w-2.5 h-2.5 rounded-full ${COLORS[t.color].dot}`} />
              {t.label}
            </span>
            <span className="text-slate-700 font-medium">{t.value} คน</span>
          </div>
        ))}
      </div>
    </div>
  );
}

export default function AdminDashboard() {
  return (
    <div className="flex h-screen bg-slate-50 font-sans overflow-hidden">
      <Sidebar />
      <main className="flex-1 overflow-y-auto">
        <Header />
        <div className="px-8 pb-10 space-y-5">
          <div className="flex flex-wrap gap-4">
            {STAT_CARDS.map((s) => (
              <StatCard key={s.label} {...s} />
            ))}
          </div>

          <div className="flex flex-wrap gap-5">
            <StatusAndFollowUpCard />
            <NotificationsCard />
          </div>

          <div className="flex flex-wrap gap-5">
            <RecentJobsTable />
            <TechOnlineCard />
          </div>
        </div>
      </main>
    </div>
  );
}
