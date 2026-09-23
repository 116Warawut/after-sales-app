import { getGoogleAccessToken } from "./googleAuth.js";

/** อ่านทั้งโหนด เช่น rtdbGet(env, 'admins') -> { k1: {...}, k2: {...} } | null */
export async function rtdbGet(env, path) {
  const token = await getGoogleAccessToken(env);
  const url = `${env.FIREBASE_DB_URL}/${path}.json`;
  const resp = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!resp.ok) {
    throw new Error(`RTDB GET ${path} failed: ${resp.status}`);
  }
  return resp.json();
}

/**
 * อัปเดตบางฟิลด์ของโหนด (เหมือน .update() ฝั่ง client) โดยใช้สิทธิ์ Admin
 *
 * รองรับ "multi-location update" ของ Firebase RTDB ด้วย: ถ้า path เป็น '' หรือ
 * '/' (root) และ key ใน data เป็น path ย่อยคั่นด้วย '/' เช่น
 * { 'repairs/k58/hidden': true, 'chat_messages/k99': null } จะอัปเดต/ลบ
 * หลายจุดพร้อมกันในคำขอ (request) เดียว แบบ atomic — ใช้กับ runChatCleanup()
 * ด้านล่างเพื่อซ่อนงาน + ลบข้อความแชทของงานนั้นทั้งหมดในทีเดียว
 */
export async function rtdbPatch(env, path, data) {
  const token = await getGoogleAccessToken(env);
  const url = `${env.FIREBASE_DB_URL}/${path}.json`;
  const resp = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(data),
  });
  if (!resp.ok) {
    throw new Error(`RTDB PATCH ${path} failed: ${resp.status}`);
  }
  return resp.json();
}
