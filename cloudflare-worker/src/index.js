import bcrypt from "bcryptjs";
import { rtdbGet, rtdbPatch } from "./rtdb.js";
import { mintFirebaseCustomToken } from "./googleAuth.js";

// ---------------------------------------------------------------------------
// ⏰ [ใหม่] ทำความสะอาดห้องแชทของงานที่ปิดแล้ว (สถานะมีคำว่า "เสร็จ" — ครอบคลุม
// ทั้ง 'เสร็จแล้ว' และ 'เสร็จสิ้น') เกิน CHAT_AUTO_DELETE_AFTER_DAYS วัน
//
// ตามที่ตกลงกัน: "ลบ" ในที่นี้คือลบเฉพาะห้องแชท (chat_messages +
// chat_read_status) ของงานนั้นทิ้งจริง แต่ "ไม่" ลบ record งานซ่อมทิ้ง —
// เพราะงานที่เสร็จแล้วผูกกับข้อมูลใบแจ้งหนี้/การชำระเงิน (invoice_no,
// invoice_items, bill_id, is_paid ฯลฯ) ถ้าลบทิ้งจริงข้อมูลบัญชีจะหายถาวรไปด้วย
// จึงใช้วิธี "ซ่อน" งานนั้นแทน (ตั้ง field hidden: true) ให้เห็นได้เฉพาะแอดมิน
// เท่านั้น (ฝั่ง Flutter: getRepairsByCustomer/getRepairsByTechnician กรอง
// hidden ออกแล้ว ส่วน getAllRepairs() ของแอดมินไม่กรอง ยังเห็นได้ปกติ)
//
// รันจริงฝั่งเซิร์ฟเวอร์ผ่าน Cron Trigger ของ Cloudflare Worker (ดู
// wrangler.toml [triggers]) ไม่ใช่ฝั่ง client เพราะต้องทำงานแม้ไม่มีใครเปิดแอป
// เลยก็ตาม — ตรงตามที่ขอ (รันตามเวลาจริงฝั่งเซิร์ฟเวอร์)
// ---------------------------------------------------------------------------
const CHAT_AUTO_DELETE_AFTER_DAYS = 3;

function repairIdOf(repairKey, repair) {
  // งาน id จริงที่ chat_messages.repair_id / chat_read_status ใช้อ้างอิง คือ
  // เลขล้วนจากฟิลด์ 'id' ของ record หรือถ้าไม่มีให้ตัด prefix 'k' ออกจากคีย์
  // Firebase เอง (เช่น 'k58' -> '58') ให้ตรงกับ resolveRecordId() ฝั่ง Flutter
  // (utils/firebase_number.dart) เป๊ะ ๆ
  if (repair?.id !== undefined && repair?.id !== null) {
    return repair.id.toString();
  }
  return repairKey.replace(/^[kK]/, "");
}

export async function runChatCleanup(env) {
  const nowMs = Date.now();
  const thresholdMs = CHAT_AUTO_DELETE_AFTER_DAYS * 24 * 60 * 60 * 1000;

  const [repairs, chatMessages, chatReadStatus] = await Promise.all([
    rtdbGet(env, "repairs"),
    rtdbGet(env, "chat_messages"),
    rtdbGet(env, "chat_read_status"),
  ]);

  const result = { checkedRepairs: 0, hiddenRepairs: 0, deletedMessages: 0, deletedReadStatus: 0 };
  if (!repairs) return result;
  result.checkedRepairs = Object.keys(repairs).length;

  const updates = {};

  for (const [repairKey, repair] of Object.entries(repairs)) {
    if (!repair) continue;
    if (repair.hidden === true) continue; // ซ่อนไปแล้วรอบก่อน ข้าม

    const status = (repair.status ?? "").toString();
    if (!status.includes("เสร็จ")) continue;

    // 🕒 เวลาปิดงานจริง — ใช้ report_submitted_at เป็นหลัก (ตั้งตอนช่างส่ง
    // รายงานซ่อมพร้อมเปลี่ยนสถานะเป็น 'เสร็จแล้ว' จุดเดียว — ดู
    // submitRepairReport() ใน services.dart ฝั่ง Flutter) ถ้าไม่มี (ข้อมูลเก่า
    // ก่อนมีฟิลด์นี้) fallback ไปที่ updated_at แทน — เส้นทางเดียวกับที่
    // Ticket.fromMap() ใน history_customer.dart ใช้คำนวณ completedAt
    const closedAtStr = repair.report_submitted_at ?? repair.updated_at;
    if (!closedAtStr) continue;
    const closedAtMs = Date.parse(closedAtStr);
    if (Number.isNaN(closedAtMs)) continue;

    if (nowMs - closedAtMs < thresholdMs) continue;

    // ✅ เข้าเงื่อนไข: ปิดงานมาเกิน 3 วันแล้ว -> ซ่อนงาน + ลบห้องแชท
    updates[`repairs/${repairKey}/hidden`] = true;
    updates[`repairs/${repairKey}/hidden_at`] = new Date(nowMs).toISOString();
    result.hiddenRepairs++;

    const repairId = repairIdOf(repairKey, repair);

    if (chatMessages) {
      for (const [msgKey, msg] of Object.entries(chatMessages)) {
        if (msg?.repair_id?.toString() === repairId) {
          updates[`chat_messages/${msgKey}`] = null;
          result.deletedMessages++;
        }
      }
    }
    if (chatReadStatus) {
      const prefix = `${repairId}_`;
      for (const key of Object.keys(chatReadStatus)) {
        if (key.startsWith(prefix)) {
          updates[`chat_read_status/${key}`] = null;
          result.deletedReadStatus++;
        }
      }
    }
  }

  // multi-location update จุดเดียวจบ (root path ว่าง '') — ปลอดภัยกว่ายิงทีละ
  // path เพราะถ้ามีปัญหาเน็ตหลุดกลางทาง จะไม่มีสถานะครึ่ง ๆ กลาง ๆ (บาง path
  // อัปเดตแล้วบาง path ยังไม่ได้อัปเดต) ของ "งานเดียวกัน"
  if (Object.keys(updates).length > 0) {
    await rtdbPatch(env, "", updates);
  }

  return result;
}

// ลำดับการค้นหาเดียวกับ _findAccountByUsernameWithPassword ฝั่งแอป
// (customers -> technicians -> admins)
const ROLE_TABLES = [
  { table: "customers", role: "CUSTOMER" },
  { table: "technicians", role: "TECHNICIAN" },
  { table: "admins", role: "ADMIN" },
];

function looksHashed(password) {
  return /^\$2[aby]\$/.test(password || "");
}

function matchesIdentifier(row, normalized) {
  const username = row?.username?.toString().trim().toLowerCase() ?? "";
  const email = row?.email?.toString().trim().toLowerCase() ?? "";
  return username === normalized || (email !== "" && email === normalized);
}

/**
 * 🔐 กรณี login: ตรวจ username/email + password จริงฝั่งเซิร์ฟเวอร์ (ด้วยสิทธิ์
 * Admin ที่ bypass Firebase Rules ได้) แล้วออก Firebase Custom Token ที่มี role
 * ฝังอยู่ในนั้น เซ็นด้วยกุญแจ Service Account — ปลอมจากฝั่ง client ไม่ได้อีกต่อไป
 * ทั้งแอปมือถือและเว็บแอดมินเรียก action นี้เหมือนกัน
 */
async function handleLogin(payload, env) {
  const identifier = payload?.identifier?.toString().trim().toLowerCase() ?? "";
  const password = payload?.password?.toString() ?? "";

  if (!identifier || !password) {
    return new Response(
      JSON.stringify({ error: "Missing identifier or password" }),
      { status: 400 }
    );
  }

  for (const { table, role } of ROLE_TABLES) {
    let rows;
    try {
      rows = await rtdbGet(env, table);
    } catch (e) {
      console.error(e);
      continue;
    }
    if (!rows) continue;

    for (const key of Object.keys(rows)) {
      const row = rows[key];
      if (!row || !matchesIdentifier(row, identifier)) continue;

      const stored = row.password?.toString() ?? "";
      const hashed = looksHashed(stored);
      const valid = hashed
        ? bcrypt.compareSync(password, stored)
        : password === stored;

      if (!valid) {
        return new Response(
          JSON.stringify({ error: "Invalid credentials" }),
          { status: 401 }
        );
      }

      // lazy-migrate รหัสผ่าน plaintext เก่าให้เป็น bcrypt (พฤติกรรมเดียวกับแอปเดิม)
      if (!hashed) {
        const newHash = bcrypt.hashSync(password, 10);
        try {
          await rtdbPatch(env, `${table}/${key}`, { password: newHash });
        } catch (e) {
          console.error("password migration failed", e);
        }
      }

      const claims = { role };
      if (role === "ADMIN") {
        claims.admin_type = row.admin_type ?? "main";
      }

      const username = row.username?.toString() ?? identifier;
      const customToken = await mintFirebaseCustomToken(env, username, claims);

      // 🔐 [แก้ไข] ตามที่ผู้ใช้แจ้ง — 2FA ต้องเป็นค่าที่แอดมิน "แต่ละคน" เปิด/ปิด
      // เองได้อิสระ ไม่ใช่สวิตช์รวมที่กระทบทุกบัญชีพร้อมกัน จึงเปลี่ยนจากอ่าน
      // "web_settings" (ค่ารวมทั้งบริษัท) มาอ่าน "web_settings_personal/{username}"
      // (ค่าส่วนตัวของบัญชีที่กำลังจะล็อกอินเข้ามาโดยเฉพาะ) แทน — ถ้าเปิดไว้
      // "และ" บัญชีนี้มีอีเมลบันทึกไว้แล้ว ถึงจะตอบ requires2FA: true กลับไป
      let requires2FA = false;
      if (role === "ADMIN") {
        try {
          const personalSettings = await rtdbGet(env, `web_settings_personal/${username}`);
          if (personalSettings?.enable2FA && row.email) {
            requires2FA = true;
          }
        } catch (e) {
          console.error("2FA settings check failed", e);
        }
      }

      const { password: _pw, ...safeUser } = row;
      return new Response(
        JSON.stringify({ customToken, role, user: safeUser, requires2FA }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  return new Response(JSON.stringify({ error: "Invalid credentials" }), {
    status: 401,
  });
}

// ---------------------------------------------------------------------------
// 🌐 [แก้ไข] เพิ่ม CORS: เว็บแอดมิน (React/Vite) เรียก Worker นี้ตรง ๆ จาก
// browser ข้าม origin (localhost:5173 ตอน dev, โดเมนจริงตอน production) แต่
// Worker ไม่เคยตอบ Access-Control-Allow-Origin เลย browser เลยบล็อกตั้งแต่ขั้น
// preflight (OPTIONS) — ต้นเหตุ error "has been blocked by CORS policy"
// ต้องตอบ preflight (OPTIONS) ก่อนเช็คอย่างอื่นทั้งหมด (preflight ไม่ส่ง
// Authorization header มาด้วย เช็ค auth ก่อนจะพังไปคนละเรื่อง) แล้วก็แปะ
// header เดียวกันนี้ลงไปกับทุก response จริงด้วย ไม่งั้น browser จะอ่าน
// response ไม่ได้อยู่ดีแม้ request จะผ่านไปถึง Worker แล้วก็ตาม
// ---------------------------------------------------------------------------
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

function withCors(response) {
  const headers = new Headers(response.headers);
  for (const [key, value] of Object.entries(CORS_HEADERS)) {
    headers.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

export default {
  async fetch(request, env) {
    // Preflight request — ต้องตอบก่อนเช็คอย่างอื่นทั้งหมด
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (request.method !== 'POST') {
      return withCors(new Response('Method Not Allowed', { status: 405 }));
    }

    const authHeader = request.headers.get('Authorization');
    if (!authHeader || authHeader !== `Bearer ${env.APP_SHARED_SECRET}`) {
      return withCors(new Response('Unauthorized', { status: 401 }));
    }

    try {
      const payload = await request.json();

      // 🔐 0. กรณี login (ใหม่) — ตรวจรหัสผ่านจริง + ออก Firebase Custom Token
      if (payload.type === 'LOGIN') {
        return withCors(await handleLogin(payload, env));
      }

      // ⏰ 0.5 [ใหม่] ทริกเกอร์ runChatCleanup() ด้วยมือผ่าน HTTP (สำหรับทดสอบ
      // เอง โดยไม่ต้องรอ cron รอบถัดไป) — ใช้ Authorization secret เดียวกับ
      // endpoint อื่นทั้งหมด (เช็คผ่านไปแล้วก่อนถึงจุดนี้) รอบจริงยังรันอัตโนมัติ
      // ทุกวันผ่าน Cron Trigger ตามปกติ (ดู scheduled() ด้านล่างของไฟล์นี้)
      if (payload.type === 'RUN_CHAT_CLEANUP') {
        const result = await runChatCleanup(env);
        return withCors(new Response(JSON.stringify(result), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        }));
      }

      // 📧 1. กรณีส่ง Email OTP ผ่าน SendGrid (Single Sender Verification)
      if (payload.type === 'EMAIL_OTP') {
        const { email, otp } = payload;
        // purpose:
        //  'REGISTER'          = ยืนยันการสมัครสมาชิก
        //  'RESET_PASSWORD'    = รีเซ็ตรหัสผ่าน (ค่าเริ่มต้น)
        //  'CHANGE_EMAIL_OLD'  = ยืนยันความเป็นเจ้าของอีเมลเดิม ก่อนจะให้เปลี่ยนอีเมล
        //  'CHANGE_EMAIL_NEW'  = ยืนยันว่าเข้าถึงอีเมลใหม่ได้จริง ก่อนบันทึกเปลี่ยนอีเมล
        const VALID_PURPOSES = [
          'REGISTER',
          'RESET_PASSWORD',
          'CHANGE_EMAIL_OLD',
          'CHANGE_EMAIL_NEW',
          'ADMIN_LOGIN_2FA',
        ];
        const purpose = VALID_PURPOSES.includes(payload.purpose)
          ? payload.purpose
          : 'RESET_PASSWORD';
        if (!email || !otp) {
          return withCors(new Response(JSON.stringify({ error: 'Missing email or otp' }), { status: 400 }));
        }

        const OTP_EMAIL_CONTENT = {
          REGISTER: {
            subject: `[After Sales] รหัส OTP ยืนยันการสมัครสมาชิก: ${otp}`,
            intro: 'คุณกำลังสมัครสมาชิกในระบบบริการหลังการขาย รหัส OTP สำหรับยืนยันอีเมลของคุณคือ:',
            footer: 'หากคุณไม่ได้เป็นผู้ทำการสมัครสมาชิก โปรดละเว้นอีเมลฉบับนี้',
          },
          RESET_PASSWORD: {
            subject: `[After Sales] รหัส OTP ยืนยันตัวตน: ${otp}`,
            intro: 'คุณได้ทำการขอรีเซ็ตรหัสผ่าน รหัส OTP สำหรับยืนยันตัวตนของคุณคือ:',
            footer: 'หากคุณไม่ได้เป็นผู้ทำรายการ โปรดละเว้นอีเมลฉบับนี้',
          },
          CHANGE_EMAIL_OLD: {
            subject: `[After Sales] รหัส OTP ยืนยันอีเมลเดิม: ${otp}`,
            intro: 'คุณกำลังขอเปลี่ยนอีเมลของบัญชี ก่อนดำเนินการต่อ กรุณายืนยันความเป็นเจ้าของอีเมลนี้ด้วยรหัส OTP:',
            footer: 'หากคุณไม่ได้เป็นผู้ทำรายการเปลี่ยนอีเมล โปรดละเว้นอีเมลฉบับนี้ และตรวจสอบความปลอดภัยของบัญชีของคุณ',
          },
          CHANGE_EMAIL_NEW: {
            subject: `[After Sales] รหัส OTP ยืนยันอีเมลใหม่: ${otp}`,
            intro: 'คุณกำลังตั้งค่าอีเมลนี้เป็นอีเมลใหม่ของบัญชี กรุณายืนยันด้วยรหัส OTP เพื่อยืนยันว่าเข้าถึงอีเมลนี้ได้จริง:',
            footer: 'หากคุณไม่ได้เป็นผู้ทำรายการเปลี่ยนอีเมล โปรดละเว้นอีเมลฉบับนี้',
          },
          ADMIN_LOGIN_2FA: {
            subject: `[After Sales] รหัส OTP ยืนยันการเข้าสู่ระบบแอดมิน: ${otp}`,
            intro: 'มีการเข้าสู่ระบบด้วยบัญชีแอดมินของคุณ กรุณายืนยันตัวตนด้วยรหัส OTP ต่อไปนี้:',
            footer: 'หากคุณไม่ได้เป็นผู้เข้าสู่ระบบ กรุณาเปลี่ยนรหัสผ่านทันทีเพื่อความปลอดภัยของบัญชี',
          },
        };

        const emailSubject = OTP_EMAIL_CONTENT[purpose].subject;
        const introText = OTP_EMAIL_CONTENT[purpose].intro;
        const footerText = OTP_EMAIL_CONTENT[purpose].footer;

        const sendGridRes = await fetch('https://api.sendgrid.com/v3/mail/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${env.SENDGRID_API_KEY}`,
          },
          body: JSON.stringify({
            personalizations: [
              {
                to: [{ email: email }],
              },
            ],
            from: {
              email: 'aftersales.auto.otp@gmail.com',
              name: 'After Sales System',
            },
            subject: emailSubject,
            content: [
              {
                type: 'text/html',
                value: `
                  <div style="font-family: sans-serif; max-width: 500px; margin: auto; padding: 24px; border: 1px solid #e8e8e8; border-radius: 12px; background-color: #ffffff;">
                    <h2 style="color: #140909; text-align: center; margin-bottom: 8px;">After Sales Service</h2>
                    <p style="color: #555; text-align: center; font-size: 14px;">ระบบบริการหลังการขาย</p>
                    <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
                    <p style="color: #333; font-size: 15px;">สวัสดีครับ,</p>
                    <p style="color: #555; font-size: 14px; line-height: 1.5;">${introText}</p>
                    <div style="text-align: center; margin: 28px 0;">
                      <span style="font-size: 32px; font-weight: bold; letter-spacing: 8px; background-color: #f5f5f7; padding: 12px 28px; border-radius: 8px; color: #d8232a; display: inline-block;">
                        ${otp}
                      </span>
                    </div>
                    <p style="color: #d8232a; font-size: 13px; text-align: center;">* รหัส OTP นี้มีอายุการใช้งาน 3 นาที</p>
                    <p style="color: #999; font-size: 12px; margin-top: 30px; text-align: center;">${footerText}</p>
                  </div>
                `,
              },
            ],
          }),
        });

        // SendGrid ตอบสำเร็จด้วย 202 Accepted และ body ว่างเปล่า (ไม่ใช่ JSON)
        // ต้องเช็คก่อนว่ามีเนื้อหาไหมค่อย parse ไม่งั้น error ตอนแปลง JSON
        const resText = await sendGridRes.text();
        const resBody = resText.length > 0
          ? resText
          : JSON.stringify({ success: sendGridRes.ok });

        return withCors(new Response(resBody, {
          status: sendGridRes.status,
          headers: { 'Content-Type': 'application/json' },
        }));
      }

      // 📧 1.5 กรณีแจ้งเตือนไปยังอีเมลเดิม หลังเปลี่ยนอีเมลสำเร็จ (ไม่ใช่ OTP)
      // เผื่อเจ้าของบัญชีตัวจริงเห็นแล้วรู้ตัวว่ามีคนสวมสิทธิ์เปลี่ยนอีเมลไป
      if (payload.type === 'EMAIL_CHANGE_NOTICE') {
        const { oldEmail, newEmail } = payload;
        if (!oldEmail || !newEmail) {
          return withCors(new Response(JSON.stringify({ error: 'Missing oldEmail or newEmail' }), { status: 400 }));
        }

        const sendGridRes = await fetch('https://api.sendgrid.com/v3/mail/send', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${env.SENDGRID_API_KEY}`,
          },
          body: JSON.stringify({
            personalizations: [
              {
                to: [{ email: oldEmail }],
              },
            ],
            from: {
              email: 'aftersales.auto.otp@gmail.com',
              name: 'After Sales System',
            },
            subject: '[After Sales] แจ้งเตือน: บัญชีของคุณเพิ่งเปลี่ยนอีเมล',
            content: [
              {
                type: 'text/html',
                value: `
                  <div style="font-family: sans-serif; max-width: 500px; margin: auto; padding: 24px; border: 1px solid #e8e8e8; border-radius: 12px; background-color: #ffffff;">
                    <h2 style="color: #140909; text-align: center; margin-bottom: 8px;">After Sales Service</h2>
                    <p style="color: #555; text-align: center; font-size: 14px;">ระบบบริการหลังการขาย</p>
                    <hr style="border: none; border-top: 1px solid #eee; margin: 20px 0;" />
                    <p style="color: #333; font-size: 15px;">สวัสดีครับ,</p>
                    <p style="color: #555; font-size: 14px; line-height: 1.5;">
                      บัญชีที่ผูกกับอีเมลนี้เพิ่งเปลี่ยนอีเมลติดต่อเป็น <b>${newEmail}</b> เมื่อสักครู่นี้
                    </p>
                    <p style="color: #d8232a; font-size: 13px; text-align: center; margin-top: 24px;">
                      หากคุณไม่ได้เป็นผู้ทำรายการนี้ กรุณาติดต่อผู้ดูแลระบบทันทีเพื่อความปลอดภัยของบัญชี
                    </p>
                  </div>
                `,
              },
            ],
          }),
        });

        const resText = await sendGridRes.text();
        const resBody = resText.length > 0
          ? resText
          : JSON.stringify({ success: sendGridRes.ok });

        return withCors(new Response(resBody, {
          status: sendGridRes.status,
          headers: { 'Content-Type': 'application/json' },
        }));
      }

      // 🔔 2. กรณีส่ง Push Notification OneSignal (เดิม)
      const oneSignalRes = await fetch('https://api.onesignal.com/notifications', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Authorization': `Key ${env.ONESIGNAL_REST_API_KEY}`,
        },
        body: JSON.stringify(payload),
      });

      const resData = await oneSignalRes.text();
      return withCors(new Response(resData, {
        status: oneSignalRes.status,
        headers: { 'Content-Type': 'application/json' },
      }));
    } catch (err) {
      return withCors(new Response(JSON.stringify({ error: err.message }), { status: 500 }));
    }
  },

  // ⏰ [ใหม่] เรียกอัตโนมัติตามตาราง Cron Trigger ใน wrangler.toml ([triggers]
  // crons) — ไม่ต้องมีใครเปิดแอปหรือยิง HTTP request ใด ๆ ก็ทำงานเอง
  // ctx.waitUntil() กันไม่ให้ Worker หยุดทำงานก่อนที่ Promise จะเสร็จ (พฤติกรรม
  // มาตรฐานของ Cloudflare Worker สำหรับงานเบื้องหลังที่ไม่มี response ให้รอ)
  async scheduled(event, env, ctx) {
    ctx.waitUntil(
      runChatCleanup(env).catch((e) => console.error('runChatCleanup failed', e))
    );
  },
};