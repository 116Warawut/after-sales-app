// ---------------------------------------------------------------------------
// 🔔 ยิง Push Notification ออกจากเว็บแอดมิน
//
// ⚠️ [แก้ไข] เดิมเก็บ OneSignal REST API Key ไว้ในไฟล์นี้ตรงๆ (เข้ารหัส/ป้องกัน
// อะไรไม่ได้เลย เพราะโค้ดฝั่ง React ทั้งหมด "ถูกส่งไปที่เบราว์เซอร์ของทุกคน" ที่
// เปิดเว็บนี้ — เปิด DevTools > Sources ก็เห็นคีย์ตรงๆ) เปลี่ยนมายิงผ่าน
// Cloudflare Worker ตัวเดียวกับที่แอปมือถือใช้อยู่แล้วแทน คีย์จริงอยู่บนเซิร์ฟเวอร์
// เท่านั้น ไม่เคยส่งมาที่เบราว์เซอร์เลย
// ---------------------------------------------------------------------------

const ONESIGNAL_APP_ID = "86c13e32-650f-4a2b-9188-6f764ba8994b";
const WORKER_URL = "https://aftersales-push-proxy.omenkungzaza121.workers.dev";
const APP_SHARED_SECRET = "kATyjLNoUIs7ebkEHzX9NY24HWSH3dCf";

/**
 * ส่ง Push Notification ไปยัง user คนเดียว (ระบุด้วย username ซึ่งผูกไว้เป็น
 * OneSignal external_id ตอนล็อกอินฝั่งแอปมือถือ) — ล้มเหลวแล้วแค่ log เฉย ๆ
 * ไม่ throw เพื่อไม่ให้การส่งข้อความ/สร้างแจ้งเตือนในแอปพัง แค่เพราะ push พลาด
 */
export async function sendPushToUser({ username, title, message, additionalData }) {
  if (!username) return;

  try {
    const response = await fetch(WORKER_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        Authorization: `Bearer ${APP_SHARED_SECRET}`,
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        include_aliases: { external_id: [username] },
        target_channel: "push",
        headings: { en: title, th: title },
        contents: { en: message, th: message },
        priority: 10,
        android_visibility: 1,
        android_accent_color: "FF1E88E5",
        ...(additionalData ? { data: additionalData } : {}),
      }),
    });

    if (!response.ok) {
      console.error("[oneSignal] push failed:", response.status, await response.text());
    }
  } catch (err) {
    console.error("[oneSignal] push error:", err);
  }
}