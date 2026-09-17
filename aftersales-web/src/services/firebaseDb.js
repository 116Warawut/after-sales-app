import { ref, onValue, set, get, push, update, remove } from "firebase/database";
import { signInWithCustomToken, signOut } from "firebase/auth";
import { db, auth } from "../firebase";
import { getOrCreateDeviceId } from "./session";
import {
  isDoneStatus,
  extractSeverity,
  getEffectiveRepairStatus,
  compareAppointmentDate,
} from "../shared/constants";

// ---------------------------------------------------------------------------
// 🔐 [แก้ไข] Race condition หลัง login ใหม่ ๆ: signInWithCustomToken() resolve
// ทันทีที่ Firebase Auth มี currentUser แล้ว แต่ "connection websocket ของ
// Realtime Database" ต้องส่ง token ไป auth กับ server แยกอีกรอบหนึ่ง (คนละ
// ขั้นตอนกัน) ซึ่งช้ากว่าเล็กน้อย — ถ้า onValue()/get() ถูกเรียกในช่วงรอยต่อนี้
// (เช่นตอน mount หน้าแรกทันทีหลัง login) rules จะเห็น auth เป็น null ก่อน แล้ว
// เจอ permission_denied และที่ร้ายคือ Firebase จะ "cancel listener ทิ้งทันที"
// เมื่อเจอ permission_denied — ต่อให้ token ไปถึง server จริงในเสี้ยววินาที
// ถัดมาก็ไม่ช่วย เพราะ listener ตายไปแล้ว ไม่ retry ให้เอง จึงต้อง retry เอง
// แบบ backoff เมื่อเจอ permission_denied เท่านั้น (error อื่นไม่ retry)
// ---------------------------------------------------------------------------
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
      // 🛠️ [แก้ไข] เดิม id: item.id || String(idx) มาก่อน ...item ทับทีหลัง
      // ทำให้ถ้า item มีฟิลด์ id ของตัวเอง (เช่นเลข id จากฝั่ง Flutter)
      // มันจะทับ index ที่เป็นตำแหน่งจริงใน array — ทำให้ id ที่ React ใช้
      // เขียน/ลบข้อมูล ไม่ตรงกับตำแหน่งจริงใน Firebase อีกต่อไป จึงย้าย
      // id: มาไว้หลังสุดเพื่อให้ "ตำแหน่ง/คีย์จริง" ชนะเสมอ (เก็บ id เดิม
      // ไว้ในชื่อ record_id เผื่อที่อื่นต้องใช้เลขนี้แสดงผล)
      record_id: item?.id,
      id: item?.id ?? String(idx),
    }));
  } else if (typeof val === "object" && val !== null) {
    return Object.entries(val).map(([key, item]) => ({
      ...(typeof item === "object" && item !== null ? item : { value: item }),
      // 🛠️ [แก้ไข] บั๊กสำคัญ: เดิม id: key ถูกตั้งก่อน ...item แล้วโดน
      // ...item ทับด้วยฟิลด์ id ภายในของมันเอง (เช่นเลข id ธรรมดาที่ฝั่ง
      // Flutter เขียนลงไปตอนสร้าง record) ผลคือ id ที่ฝั่งเว็บใช้อ้างอิงเวลา
      // update()/remove() กลายเป็น "เลข id" แทนที่จะเป็น "คีย์จริงใน Firebase"
      // (เช่น "k18") — พอเรียก updateRow("repairs", r.id, ...) หรือ
      // deleteRepair(deleteTarget.id) ด้วยเลขนี้ จะไปเขียน/ลบผิด path
      // (เช่น "repairs/18" ที่ไม่มีอยู่จริง) ซึ่ง Firebase update() จะสร้าง
      // node เปล่า ๆ ขึ้นมาใหม่ให้ทันทีแทนที่จะ error — นี่คือต้นตอของ
      // record ผีแบบ "# AS-0000" ที่ลบแล้วโผล่กลับมาเรื่อย ๆ ทุกครั้งที่
      // หน้า Dashboard รัน stale-check ซ้ำ แก้โดยย้าย id: key มาไว้หลังสุด
      // ให้คีย์จริงชนะเสมอ (เก็บเลข id เดิมไว้ในชื่อ record_id เผื่อที่อื่น
      // ต้องใช้เลขนี้แสดงผล เช่น fallback ticket number)
      record_id: item?.id,
      id: key,
    }));
  }
  return [];
}

// 🔐 [แก้ไข] wrapper สำหรับ one-time get() ที่ใช้ retry แบบเดียวกับ listenTable
// ด้านล่าง — ป้องกัน permission_denied ที่เกิดจาก race เดียวกันตอน login ใหม่ ๆ
// (ดูคอมเมนต์ยาวด้านบน AUTH_RACE_RETRY_DELAYS_MS)
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
        retryAttempt = 0; // อ่านสำเร็จแล้ว รีเซ็ต counter ไว้เผื่อ error รอบถัดไป
        callback(parseTableSnapshot(snapshot));
      },
      (error) => {
        console.error(`[firebaseDb] listenTable error on '${table}':`, error);
        // 🔐 [แก้ไข] permission_denied ตอนนี้อาจเป็นแค่ race ตอน auth ยังไม่
        // ทันไปถึง RTDB connection (ดูคอมเมนต์ด้านบน) — ลอง re-subscribe ใหม่
        // แบบ backoff ก่อนที่จะยอมแพ้จริง ๆ แล้วส่ง callback([]) ให้หน้าจอ
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

// ---------------------------------------------------------------------------
// 🔐 [แก้ไข] เดิมฟังก์ชันนี้ดึงทั้งตาราง "admins" (รวม password hash ของทุกคน)
// ออกมาเทียบ bcrypt "ในเบราว์เซอร์" เอง — ใครก็เปิด DevTools ดูได้ว่าเทียบ
// ยังไง แถมยังมี backdoor admin/12345678 ที่ทำงานถ้าตาราง admins ว่างอีกด้วย
// เปลี่ยนมายิงไปที่ Cloudflare Worker แทน ให้ Worker เป็นคนตรวจรหัสผ่านจริงด้วย
// สิทธิ์ Admin ของ Service Account (bypass Firebase Rules ได้) แล้วออก Firebase
// Custom Token ที่มี role ฝังมาด้วย — เว็บเอา token นี้ไป signInWithCustomToken()
// ทำให้ auth.token.role ที่ใช้เช็คสิทธิ์ใน Firebase Rules เชื่อถือได้จริง ปลอม
// จากฝั่งเบราว์เซอร์ไม่ได้อีกต่อไป (ใช้ Worker endpoint เดียวกับที่ oneSignal.js
// ใช้อยู่แล้ว)
// ---------------------------------------------------------------------------
const WORKER_URL = "https://aftersales-push-proxy.omenkungzaza121.workers.dev";
const APP_SHARED_SECRET = "kATyjLNoUIs7ebkEHzX9NY24HWSH3dCf";

// 🔐 [ใหม่] เดิมฟังก์ชันนี้ signInWithCustomToken() ทันทีที่รหัสผ่านถูกต้อง
// แต่ตอนนี้ต้องรองรับ 2FA ด้วย — ถ้า Worker บอกว่าบัญชีนี้ต้องยืนยัน OTP
// (requires2FA: true จาก web_settings.enable2FA + บัญชีมีอีเมลแล้ว) จะ "ยังไม่"
// signInWithCustomToken() ทันที แต่คืน token ไว้ให้ LoginPage ถือรอไว้ก่อน
// รอกรอก OTP ถูกต้องแล้วค่อยเรียก completeAdminLogin() เพื่อ sign in จริง
// (ถ้าไม่ต้อง 2FA ก็ sign in ทันทีเหมือนเดิม)
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

  // เว็บแอดมินรับเฉพาะบทบาท ADMIN เท่านั้น (ช่าง/ลูกค้า login ผ่านแอปมือถือ)
  if (data.role !== "ADMIN") return null;

  if (data.requires2FA) {
    return { requires2FA: true, pendingToken: data.customToken, user: data.user };
  }

  await signInWithCustomToken(auth, data.customToken);
  await recordAdminLoginDevice(data.user.username);
  return { requires2FA: false, user: data.user };
}

/** ยืนยัน 2FA ผ่านแล้ว — เอา customToken ที่ค้างไว้จาก loginAdmin() ไป sign in จริง */
export async function completeAdminLogin(pendingToken, username) {
  await signInWithCustomToken(auth, pendingToken);
  await recordAdminLoginDevice(username);
}

// 🆕 [ใหม่] ทำให้ "อนุญาตล็อกอินพร้อมกันหลายอุปกรณ์" และ "แจ้งเตือนเมื่อมีการ
// เข้าสู่ระบบใหม่" (หน้าตั้งค่า > ความปลอดภัย) ทำงานจริง — เรียกทุกครั้งที่
// แอดมิน sign in สำเร็จ (ทั้งเส้นทางไม่มี 2FA และเส้นทางผ่าน OTP แล้ว):
// 1) บันทึกว่า "อุปกรณ์นี้" (deviceId ถาวรจาก getOrCreateDeviceId) เป็น
//    อุปกรณ์ล่าสุดที่ล็อกอินเข้าบัญชีนี้ไว้ที่ admin_active_sessions/{username}
//    — useSessionGuard ฝั่ง React จะ subscribe path นี้แบบ realtime เพื่อเช็ค
//    ว่าอุปกรณ์อื่นเพิ่งล็อกอินทับเข้ามาหรือไม่ (ถ้า allowMultiDeviceLogin
//    ของบัญชีนี้ปิดอยู่ จะบังคับออกจากระบบอุปกรณ์เก่าโดยอัตโนมัติ)
// 2) ถ้า deviceId นี้ไม่เคยล็อกอินเข้าบัญชีนี้มาก่อน (ไม่มีใน
//    admin_known_devices/{username}/{deviceId}) ถือเป็น "อุปกรณ์ใหม่" — สร้าง
//    แจ้งเตือนให้บัญชีนี้เห็น ถ้าเปิด notifyNewLogin ไว้ (ค่าเริ่มต้นเปิด) แล้ว
//    บันทึก deviceId นี้ไว้เป็นอุปกรณ์ที่รู้จักแล้ว กันไม่ให้แจ้งเตือนซ้ำทุกครั้ง
// ทำงานแบบ best-effort เงียบ ๆ — พังแล้วไม่ควรบล็อกการล็อกอินจริง จึง catch
// error ทุกจุดเอง ไม่ throw ต่อ
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

/** ส่งรหัส OTP ไปยังอีเมลแอดมิน สำหรับขั้นตอนยืนยันตัวตนตอนล็อกอิน (2FA) */
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
  
  // คำนวณสถานะเริ่มต้นตามวันนัดหมาย
  // 🐛 [แก้ไข] BUG: เดิม default เป็น "กำลังซ่อม" ทันทีเมื่อวันนัดเป็นวันนี้
  // (หรือไม่ระบุวันนัด) ทั้งที่ช่างยังไม่ได้เริ่มเดินทาง/ลงมือทำจริงเลย — ตรงกับ
  // บั๊กเดียวกันที่แก้ไปแล้วฝั่ง Flutter (assignTechnicianToRepair() ใน
  // services.dart) เปลี่ยนเป็น "รอดำเนินการ" ก่อน แล้วให้ระบบคิวงานฝั่งแอปมือถือ
  // (markTechnicianTraveling()/รับงานจริง) ขยับสถานะเป็น "กำลังเดินทาง" แล้ว
  // "กำลังดำเนินการ" ตามลำดับจริงแทน — เว็บเองไม่มีการติดตาม GPS ของช่าง เลย
  // ไม่ต้องขยับสถานะเองที่นี่ แค่ตั้งค่าเริ่มต้นให้ถูกพอ
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

  await update(repairRef, {
    technician_username: technicianUsername,
    status: initialStatus,
    assignment_status: "จัดสรรช่างแล้ว",
    progress,
    assigned_at: now,
    assigned_by: adminUsername || "admin",
    ...extraData,
  });
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
    // 🔐 [แก้ไข] มีหลายหน้าเรียก getWebSettings().then(...) โดยไม่มี .catch —
    // ถ้า retry ครบแล้วยังไม่ได้ (เช่น auth หลุดจริง ๆ ไม่ใช่แค่ race) ปล่อยให้
    // throw จะกลายเป็น unhandled promise rejection กระจายไปหลายหน้าจอ จึง
    // "กันชน" ที่นี่จุดเดียว: log ไว้ดูแล้ว fallback เป็นค่า default แทน ผลคือ
    // แย่ที่สุดคือ badge/การตั้งค่าใช้ค่า default ชั่วคราว ไม่ใช่หน้าจอพัง
    console.error("[firebaseDb] getWebSettings failed after retries:", error);
    return DEFAULT_WEB_SETTINGS_FALLBACK;
  }
}

export async function saveWebSettings(settings) {
  const settingsRef = ref(db, "web_settings");
  await set(settingsRef, settings);
}

// 🆕 [ใหม่] การตั้งค่าส่วนตัวของแต่ละแอดมิน (ธีมสี, จำนวนรายการต่อหน้า,
// รูปแบบวันที่, ภาษา, สกุลเงิน, Popup แจ้งเตือน) เก็บแยกคนละ path ต่อ username
// ("web_settings_personal/{username}") ไม่ปนกับ "web_settings" (ข้อมูลบริษัท/
// นโยบายความปลอดภัย/ประเภทแจ้งเตือนที่ระบบจะสร้าง ซึ่งยังควรเป็นค่ารวมทั้งบริษัท
// เหมือนเดิม) ตามที่ผู้ใช้แจ้งว่าอยากให้แอดมินแต่ละคนตั้งธีม/ค่าส่วนตัวแยกกัน
// ไม่กระทบกัน (เดิมแอด1เปลี่ยนธีมมืด แอด2ก็เห็นมืดไปด้วย เพราะอ่านค่าเดียวกัน)
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
  // 🐛 [แก้ไข] BUG ที่ผู้ใช้ทัก (จุดเดียวกับที่แก้ในการ์ด "สถิติสถานะงานซ่อม"
  // กับรายการ "งานที่ต้องติดตาม" ของ DashboardPage.jsx ไปแล้ว — จุดนี้เป็น
  // การ์ดสถิติ 8 ใบบนสุดหน้า Dashboard ซึ่งดึงเลขจากฟังก์ชันนี้ มีปัญหาเดียวกัน
  // ที่ยังไม่ได้แก้): เดิม pending/scheduledPending/inProgress/overdue/urgent
  // นับซ้อนทับกันได้ (เร่งด่วนเป็นคนละมิติกับสถานะ งานเดียวเข้าได้ทั้ง 2 การ์ด)
  // เปลี่ยนมาจัดแต่ละงานเข้าหมวดเดียวตามลำดับความสำคัญแทน ให้ตัวเลขบนการ์ด
  // ด้านบนตรงกับโดนัท/รายการด้านล่างเป๊ะ ไม่ขัดกันเองอีก ลำดับ (สูง→ต่ำ):
  // เกินกำหนดเวลา > เร่งด่วน > รอจัดสรรช่าง > รอดำเนินการ > กำลังซ่อม
  // (เสร็จสิ้น/ยกเลิก/มีปัญหา ไม่ถูกนับในกลุ่มนี้อยู่แล้ว เพราะ
  // getEffectiveRepairStatus() คืนค่าพวกนี้แยกจากสถานะที่ใช้กรองด้านล่างไปตั้ง
  // แต่แรก ไม่ได้ทับซ้อนอะไร)
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
    // 🆕 [ใหม่] รวม "กำลังเดินทาง" (สถานะใหม่ฝั่งแอปมือถือ — ช่างถึงคิวงานแล้ว
    // กำลังมุ่งหน้าไปหาลูกค้า) เข้าการ์ด "กำลังซ่อม" เดิมไปด้วย — เดิมเทียบ
    // "กำลังซ่อม" ตรงๆ เท่านั้น พอ getEffectiveRepairStatus() คืนค่า
    // "กำลังเดินทาง" แยกออกมาแล้ว งานกลุ่มนี้จะตกไปไม่ถูกนับในการ์ดไหนเลย
    // ทั้งที่ยังนับรวมอยู่ใน "งานทั้งหมด" (total) ทำให้ตัวเลขไม่ตรงกัน
    else if (eff === "กำลังซ่อม" || eff === "กำลังเดินทาง") inProgress++;
  });
  const completedToday = repairs.filter((r) => isDoneStatus(getEffectiveRepairStatus(r))).length;
  const cancelled = repairs.filter((r) => (r.status || "").includes("ยกเลิก")).length;
  return { total, pending, scheduledPending, inProgress, overdue, completedToday, urgent, cancelled };
}