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

/** อัปเดตบางฟิลด์ของโหนด (เหมือน .update() ฝั่ง client) โดยใช้สิทธิ์ Admin */
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
