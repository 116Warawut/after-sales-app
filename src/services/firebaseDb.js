import { ref, onValue, set, get, push, update, remove } from "firebase/database";
import { signInWithCustomToken, signOut } from "firebase/auth";
import { db, auth } from "../firebase";
import { getOrCreateDeviceId, getSessionAdmin } from "./session";
import {
  isDoneStatus,
  extractSeverity,
  getEffectiveRepairStatus,
  compareAppointmentDate,
} from "../shared/constants";

const AUTH_RACE_RETRY_DELAYS_MS = [300, 600, 1200, 2000, 3000];

function isPermissionDeniedError(error) {
  const code = (error?.code || "").toString().toUpperCase();
  return code === "PERMISSION_DENIED" || /permission_denied/i.test(error?.message || "");
}

function parseTableSnapshot(snapshot) {
  if (!snapshot.exists()) return [];
  const val = snapshot.val();
  if (Array.isArray(val)) {
    return val.filter(Boolean).map((item, idx) => ({
      ...(typeof item === "object" ? item : { value: item }),
      record_id: item?.id,
      id: item?.id ?? String(idx),
    }));
  } else if (typeof val === "object" && val !== null) {
    return Object.entries(val).map(([key, item]) => ({
      ...(typeof item === "object" && item !== null ? item : { value: item }),
      record_id: item?.id,
      id: key,
    }));
  }
  return [];
}

async function getWithAuthRetry(refInstance) {
  let lastError;
  for (let i = 0; i <= AUTH_RACE_RETRY_DELAYS_MS.length; i++) {
    try {
      return await get(refInstance);
    } catch (error) {
      lastError = error;
      if (!isPermissionDeniedError(error) || i === AUTH_RACE_RETRY_DELAYS_MS.length) {
        throw error;
      }
      await new Promise((resolve) => setTimeout(resolve, AUTH_RACE_RETRY_DELAYS_MS[i]));
    }
  }
  throw lastError;
}

/** Realtime Listener สำหรับดึงข้อมูลจาก Firebase Realtime Database */
export function listenTable(table, callback) {
  const tableRef = ref(db, table);
  let cancelled = false;
  let detachCurrent = null;
  let retryTimer = null;
  let retryAttempt = 0;

  function attach() {
    detachCurrent = onValue(
      tableRef,
      (snapshot) => {
        retryAttempt = 0;
        callback(parseTableSnapshot(snapshot));
      },
      (error) => {
        console.error(`[firebaseDb] listenTable error on '${table}':`, error);
        if (isPermissionDeniedError(error) && retryAttempt < AUTH_RACE_RETRY_DELAYS_MS.length) {
          const delay = AUTH_RACE_RETRY_DELAYS_MS[retryAttempt];
          retryAttempt += 1;
          retryTimer = setTimeout(() => {
            if (!cancelled) attach();
          }, delay);
          return;
        }
        callback([]);
      }
    );
  }

  attach();

  return () => {
    cancelled = true;
    if (retryTimer) clearTimeout(retryTimer);
    if (detachCurrent) detachCurrent();
  };
}

export async function addRow(table, data) {
  const tableRef = ref(db, table);
  const newRef = push(tableRef);
  const now = new Date().toISOString();
  await set(newRef, {
    ...data,
    id: newRef.key,
    created_at: data.created_at || now,
  });
  return newRef.key;
}

export async function updateRow(table, id, data) {
  const itemRef = ref(db, `${table}/${id}`);
  await update(itemRef, { ...data, updated_at: new Date().toISOString() });
}

export async function deleteRow(table, id) {
  const itemRef = ref(db, `${table}/${id}`);
  await remove(itemRef);
}

export async function createDbItem(path, data) {
  return addRow(path, data);
}

export async function updateDbItem(path, id, data) {
  return updateRow(path, id, data);
}

export async function deleteDbItem(path, id) {
  return deleteRow(path, id);
}

export async function deleteRepair(id) {
  return deleteRow("repairs", id);
}

export async function clearActivityLog() {
  const logRef = ref(db, "activity_log");
  await remove(logRef);
}

export async function updatePartRequestStatus(requestId, status, extraData = {}) {
  const reqRef = ref(db, `part_requests/${requestId}`);
  await update(reqRef, {
    status,
    updated_at: new Date().toISOString(),
    ...extraData,
  });
}

const WORKER_URL = "https://aftersales-push-proxy.omenkungzaza121.workers.dev";
const APP_SHARED_SECRET = "kATyjLNoUIs7ebkEHzX9NY24HWSH3dCf";

export async function loginAdmin(username, password) {
  const response = await fetch(WORKER_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      Authorization: `Bearer ${APP_SHARED_SECRET}`,
    },
    body: JSON.stringify({
      type: "LOGIN",
      identifier: username,
      password,
    }),
  });

  if (response.status === 401) return null;
  if (!response.ok) {
    throw new Error(`เข้าสู่ระบบไม่สำเร็จ (status ${response.status})`);
  }

  const data = await response.json();
  if (!data.customToken || !data.user) return null;

  if (data.role !== "ADMIN") return null;

  if (data.requires2FA) {
    return { requires2FA: true, pendingToken: data.customToken, user: data.user };
  }

  await signInWithCustomToken(auth, data.customToken);
  await recordAdminLoginDevice(data.user.username);
  return { requires2FA: false, user: data.user };
}

export async function completeAdminLogin(pendingToken, username) {
  await signInWithCustomToken(auth, pendingToken);
  await recordAdminLoginDevice(username);
}

export async function recordAdminLoginDevice(username) {
  if (!username) return;
  try {
    const deviceId = getOrCreateDeviceId();
    const now = new Date().toISOString();
    await set(ref(db, `admin_active_sessions/${username}`), { deviceId, loggedInAt: now });

    const knownRef = ref(db, `admin_known_devices/${username}/${deviceId}`);
    const snapshot = await get(knownRef);
    if (!snapshot.exists()) {
      await set(knownRef, { firstLoginAt: now });
      const personal = await getPersonalSettings(username);
      if (personal.notifyNewLogin !== false) {
        await createNotification({
          user_username: username,
          role: "ADMIN",
          title: "เข้าสู่ระบบจากอุปกรณ์ใหม่",
          message: `บัญชีของคุณถูกใช้เข้าสู่ระบบจากอุปกรณ์ใหม่เมื่อ ${new Date(now).toLocaleString("th-TH")}`,
          type: "SECURITY",
        });
      }
    }
  } catch (err) {
    console.error("[firebaseDb] recordAdminLoginDevice failed:", err);
  }
}

export async function sendAdminLoginOtp(email, otp) {
  const response = await fetch(WORKER_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      Authorization: `Bearer ${APP_SHARED_SECRET}`,
    },
    body: JSON.stringify({
      type: "EMAIL_OTP",
      email,
      otp,
      purpose: "ADMIN_LOGIN_2FA",
    }),
  });
  return response.ok;
}

export async function logoutAdmin() {
  await signOut(auth);
}

export async function assignTechnicianToRepair(repairId, technicianUsername, adminUsername, appointmentDate = null, extraData = {}) {
  const repairRef = ref(db, `repairs/${repairId}`);
  const now = new Date().toISOString();
  
  let initialStatus = "รอดำเนินการ";
  let progress = 0.05;
  if (appointmentDate) {
    const comp = compareAppointmentDate(appointmentDate);
    if (comp === "future") {
      initialStatus = "รอดำเนินการ";
      progress = 0.05;
    } else if (comp === "past") {
      initialStatus = "เกินกำหนดเวลา";
      progress = 0.1;
    }
  }

  const currentAdmin = getSessionAdmin();
  const effectiveAdminUsername = (adminUsername && String(adminUsername).trim())
    ? String(adminUsername).trim()
    : (currentAdmin?.username || "admin");
  const effectiveAdminName = extraData?.admin_name
    || currentAdmin?.admin_name
    || effectiveAdminUsername;

  const payload = {
    technician_username: technicianUsername,
    admin_username: effectiveAdminUsername,
    admin_name: effectiveAdminName,
    status: initialStatus,
    assignment_status: "จัดสรรช่างแล้ว",
    progress,
    assigned_at: now,
    approved_at: now,
    assigned_by: effectiveAdminUsername,
    ...extraData,
  };

  if (appointmentDate) {
    payload.date = appointmentDate;
  }

  await update(repairRef, payload);
}

export async function reassignRepairAdmin(repairId, adminUsername) {
  const repairRef = ref(db, `repairs/${repairId}`);
  await update(repairRef, { admin_username: adminUsername });
}

export async function submitRepairReview(repairId, { rating, comment, techUsername, customerUsername }) {
  const repairRef = ref(db, `repairs/${repairId}`);
  const now = new Date().toISOString();
  const reviewData = {
    rating: Number(rating),
    rating_stars: Number(rating),
    rating_comment: comment || "",
    rated_at: now,
  };
  await update(repairRef, reviewData);
  if (techUsername) {
    try {
      const repairsRef = ref(db, "repairs");
      const snapshot = await getWithAuthRetry(repairsRef);
      if (snapshot.exists()) {
        const allRepairs = Object.values(snapshot.val());
        const techRepairs = allRepairs.filter(
          (r) => r.technician_username === techUsername && (r.rating_stars || r.rating)
        );
        const totalScore = techRepairs.reduce(
          (sum, r) => sum + Number(r.rating_stars || r.rating || 0),
          0
        );
        const avgRating = techRepairs.length > 0 ? totalScore / techRepairs.length : Number(rating);
        const techsRef = ref(db, "technicians");
        const techSnap = await getWithAuthRetry(techsRef);
        if (techSnap.exists()) {
          const techsData = techSnap.val();
          const techEntry = Object.entries(techsData).find(
            ([, t]) => t.username === techUsername
          );
          if (techEntry) {
            await update(ref(db, `technicians/${techEntry[0]}`), {
              rating: Number(avgRating.toFixed(1)),
              rating_count: techRepairs.length,
            });
          }
        }
      }
    } catch (err) {
      console.error("[firebaseDb] update technician avg rating error:", err);
    }
  }

  logActivity({
    adminUsername: customerUsername || "customer",
    adminName: customerUsername || "ลูกค้า",
    action: "ประเมินผลงาน",
    target: `งาน #${repairId} ได้รับ ${rating} ดาว ${comment ? `("${comment}")` : ""}`,
  }).catch(console.error);
}

export async function logActivity({ adminUsername, adminName, action, target }) {
  const logsRef = ref(db, "activity_log");
  const newRef = push(logsRef);
  await set(newRef, {
    id: newRef.key,
    admin_username: adminUsername || "admin",
    admin_name: adminName || adminUsername || "แอดมิน",
    action,
    target: target || "",
    created_at: new Date().toISOString(),
  });
}

export async function createNotification({ user_username, role, title, message, type = "GENERAL", target_id = null }) {
  const notiRef = ref(db, "notifications");
  const newRef = push(notiRef);
  await set(newRef, {
    id: newRef.key,
    user_username,
    role,
    title,
    message,
    type,
    target_id: target_id !== null ? String(target_id) : null,
    is_read: 0,
    created_at: new Date().toISOString(),
  });
}

export async function markAllNotificationsAsRead(notifications, currentUsername) {
  const unread = notifications.filter((n) => n.user_username === currentUsername && !n.is_read);
  await Promise.all(unread.map((n) => updateRow("notifications", n.id, { is_read: 1 })));
}

export async function markNotificationsRead(ids = []) {
  await Promise.all(ids.map((id) => updateRow("notifications", id, { is_read: 1 })));
}

export async function deleteNotifications(ids = []) {
  await Promise.all(ids.map((id) => deleteRow("notifications", id)));
}

export async function deleteAllNotifications(notifications, currentUsername) {
  const targets = notifications.filter((n) => n.user_username === currentUsername);
  await Promise.all(targets.map((n) => deleteRow("notifications", n.id)));
}

export async function nextInvoiceNumber() {
  const yearBE = new Date().getFullYear() + 543;
  const rand = Math.floor(1000 + Math.random() * 9000);
  return `INV-${yearBE}-${rand}`;
}

const DEFAULT_WEB_SETTINGS_FALLBACK = {
  notifyChat: true,
  notifyJob: true,
  notifyOverdue: true,
  notifyLowStock: true,
  notifyPaymentOverdue: true,
  notifyWarranty: true,
  notifyStaleJob: true,
  notifyDailyDigest: true,
  companyName: "AfterSales Service",
};

export async function getWebSettings() {
  const settingsRef = ref(db, "web_settings");
  try {
    const snapshot = await getWithAuthRetry(settingsRef);
    if (snapshot.exists()) return snapshot.val();
    return DEFAULT_WEB_SETTINGS_FALLBACK;
  } catch (error) {
    console.error("[firebaseDb] getWebSettings failed after retries:", error);
    return DEFAULT_WEB_SETTINGS_FALLBACK;
  }
}

export async function saveWebSettings(settings) {
  const settingsRef = ref(db, "web_settings");
  await set(settingsRef, settings);
}

export async function getPersonalSettings(username) {
  if (!username) return {};
  const settingsRef = ref(db, `web_settings_personal/${username}`);
  try {
    const snapshot = await getWithAuthRetry(settingsRef);
    return snapshot.exists() ? snapshot.val() : {};
  } catch (error) {
    console.error("[firebaseDb] getPersonalSettings failed after retries:", error);
    return {};
  }
}

export async function savePersonalSettings(username, settings) {
  if (!username) return;
  const settingsRef = ref(db, `web_settings_personal/${username}`);
  await set(settingsRef, settings);
}

export function computeDashboardSummary(repairs = []) {
  const total = repairs.length;
  let pending = 0;
  let scheduledPending = 0;
  let inProgress = 0;
  let overdue = 0;
  let urgent = 0;
  repairs.forEach((r) => {
    const eff = getEffectiveRepairStatus(r);
    if (eff === "เสร็จสิ้น" || eff === "ยกเลิก" || eff === "มีปัญหา") return;
    const isUrgentJob = extractSeverity(r.detail) === "เร่งด่วน";
    if (eff === "เกินกำหนดเวลา") overdue++;
    else if (isUrgentJob) urgent++;
    else if (eff === "รอจัดสรรช่าง") pending++;
    else if (eff === "รอดำเนินการ") scheduledPending++;
    else if (eff === "กำลังซ่อม" || eff === "กำลังเดินทาง") inProgress++;
  });
  const completedToday = repairs.filter((r) => isDoneStatus(getEffectiveRepairStatus(r))).length;
  const cancelled = repairs.filter((r) => (r.status || "").includes("ยกเลิก")).length;
  return { total, pending, scheduledPending, inProgress, overdue, completedToday, urgent, cancelled };
}