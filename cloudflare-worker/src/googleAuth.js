import { SignJWT, importPKCS8 } from "jose";

function normalizePrivateKey(rawKey) {
  return rawKey.includes("\\n") ? rawKey.replace(/\\n/g, "\n") : rawKey;
}

async function getSigningKey(env) {
  const pem = normalizePrivateKey(env.FIREBASE_PRIVATE_KEY);
  return importPKCS8(pem, "RS256");
}

/**
 * ขอ Google OAuth2 Access Token แบบ "Admin" ด้วย Service Account
 * ใช้ยิง Firebase Realtime Database REST API ได้ตรงๆ โดยไม่ติด Security Rules
 * (เทียบเท่ากับ Firebase Admin SDK ฝั่งเซิร์ฟเวอร์)
 */
// ในไฟล์ src/googleAuth.js

export async function getGoogleAccessToken(env) {
  const key = await getSigningKey(env);
  const now = Math.floor(Date.now() / 1000);

  const assertion = await new SignJWT({
    // 🔴 แก้ไข: เพิ่ม https://www.googleapis.com/auth/userinfo.email คั่นด้วยช่องว่าง
    scope: "https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(env.FIREBASE_CLIENT_EMAIL)
    .setSubject(env.FIREBASE_CLIENT_EMAIL)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  
  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });

  const data = await resp.json();
  if (!resp.ok) {
    throw new Error(`Failed to get Google access token: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

/**
 * ออก Firebase Custom Token ให้ uid + custom claims (role, admin_type)
 * ทั้งแอปมือถือและเว็บแอดมินเอา token นี้ไป signInWithCustomToken()
 */
export async function mintFirebaseCustomToken(env, uid, claims) {
  const key = await getSigningKey(env);
  const now = Math.floor(Date.now() / 1000);

  return new SignJWT({ uid, claims })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(env.FIREBASE_CLIENT_EMAIL)
    .setSubject(env.FIREBASE_CLIENT_EMAIL)
    .setAudience(
      "https://identitytoolkit.googleapis.com/google.identity.identitytoolkit.v1.IdentityToolkit"
    )
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
}
