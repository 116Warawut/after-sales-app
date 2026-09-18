import React, { useEffect, useRef, useState } from "react";
import { Lock, User, Eye, EyeOff, Loader2, ShieldCheck } from "lucide-react";
import { loginAdmin, completeAdminLogin, sendAdminLoginOtp } from "../services/firebaseDb";

// เชื่อมกับ Firebase แล้ว — เช็ก username/password จริงจากตาราง 'admins'
// (แทนที่ hardcode DEMO_USERNAME/DEMO_PASSWORD เดิม)
// บัญชีแอดมินเริ่มต้นที่ seed มาจาก services.dart ฝั่ง Flutter คือ ad / 12345678
// ยังใช้ล็อกอินได้อยู่ ถ้ามีอยู่จริงในฐานข้อมูล
// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: การ์ดฟอร์มกลางจอ พื้นหลังเทาอ่อน (bg-slate-50)
// ⚠️ หมายเหตุสี: โลโก้/ปุ่ม "เข้าสู่ระบบ" ใช้ #D8232A (สีแดงสดของแบรนด์ ตรงกับ
// AppColors.primary ในแอปมือถือ) — คนละเฉดกับแถบเมนูซ้ายหลังล็อกอินที่ใช้
// #B22121 (เข้มกว่า) ตั้งใจแยกกันเพราะหน้า Login เป็นพื้นหลังสว่าง สีสดกว่า
// จะดูสะดุดตากว่า ถ้าอยากให้เป็นเฉดเดียวกันทั้งหมด แก้ #D8232A ในไฟล์นี้ให้
// เป็น #B22121 แทนได้
//
// 🔐 [ใหม่] ขั้นตอนยืนยัน OTP (2FA) — ถ้าแอดมินคนนี้เปิด "การยืนยันตัวตนสองขั้นตอน"
// ไว้ที่หน้า Settings (และมีอีเมลบันทึกไว้แล้ว) หลังกรอกรหัสผ่านถูกต้อง จะยังไม่
// เข้าระบบทันที แต่จะสลับมาหน้ากรอก OTP 6 หลักที่ส่งไปอีเมลก่อน (รูปแบบเดียวกับ
// ที่ใช้ตอนเปลี่ยนอีเมลในแอปมือถือ — สุ่มรหัสฝั่ง client, หมดอายุ 3 นาที,
// พลาดครบ 3 ครั้งให้เริ่มใหม่) ผ่านแล้วถึงจะ sign in เข้าระบบจริง
// ---------------------------------------------------------------------------
export default function LoginPage({ onLogin }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);

  // ---- ขั้นตอน 2FA ----
  const [step, setStep] = useState("credentials"); // credentials | otp
  const [pendingToken, setPendingToken] = useState(null);
  const [pendingUser, setPendingUser] = useState(null);
  const [otpInput, setOtpInput] = useState("");
  const [secondsLeft, setSecondsLeft] = useState(0);
  const [failedAttempts, setFailedAttempts] = useState(0);
  const generatedOtpRef = useRef("");
  const otpExpiresAtRef = useRef(null);
  const timerRef = useRef(null);

  useEffect(() => {
    return () => clearInterval(timerRef.current);
  }, []);

  function startCountdown(seconds) {
    clearInterval(timerRef.current);
    setSecondsLeft(seconds);
    timerRef.current = setInterval(() => {
      setSecondsLeft((s) => {
        if (s <= 1) {
          clearInterval(timerRef.current);
          return 0;
        }
        return s - 1;
      });
    }, 1000);
  }

  async function sendOtpTo(email) {
    const otp = (100000 + Math.floor(Math.random() * 900000)).toString();
    generatedOtpRef.current = otp;
    otpExpiresAtRef.current = Date.now() + 3 * 60 * 1000;
    setFailedAttempts(0);
    setOtpInput("");
    const ok = await sendAdminLoginOtp(email, otp);
    if (ok) startCountdown(180);
    return ok;
  }

  async function handleSubmit(e) {
    e.preventDefault();
    if (!username || !password) {
      setError("กรุณากรอกชื่อผู้ใช้และรหัสผ่าน");
      return;
    }
    setError("");
    setLoading(true);
    try {
      const result = await loginAdmin(username.trim(), password);
      if (!result) {
        setError("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง");
        return;
      }

      if (result.requires2FA) {
        const ok = await sendOtpTo(result.user.email);
        if (!ok) {
          setError("ส่ง OTP ไปยังอีเมลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
          return;
        }
        setPendingToken(result.pendingToken);
        setPendingUser(result.user);
        setStep("otp");
        return;
      }

      onLogin(result.user);
    } catch (err) {
      console.error("[LoginPage] login error:", err);
      setError("เชื่อมต่อฐานข้อมูลไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    } finally {
      setLoading(false);
    }
  }

  async function handleVerifyOtp(e) {
    e.preventDefault();
    if (!otpExpiresAtRef.current || Date.now() > otpExpiresAtRef.current) {
      setError("รหัส OTP หมดอายุแล้ว กรุณาขอรับรหัสใหม่");
      return;
    }
    if (otpInput.trim().length !== 6) {
      setError("กรุณากรอกรหัส OTP 6 หลักให้ครบถ้วน");
      return;
    }
    if (otpInput.trim() !== generatedOtpRef.current) {
      const attempts = failedAttempts + 1;
      if (attempts >= 3) {
        clearInterval(timerRef.current);
        generatedOtpRef.current = "";
        setError("กรอก OTP ผิดเกิน 3 ครั้ง กรุณาเข้าสู่ระบบใหม่อีกครั้ง");
        resetToCredentials();
      } else {
        setFailedAttempts(attempts);
        setError(`รหัส OTP ไม่ถูกต้อง (เหลือโอกาสอีก ${3 - attempts} ครั้ง)`);
      }
      return;
    }

    setError("");
    setLoading(true);
    try {
      await completeAdminLogin(pendingToken, pendingUser?.username);
      onLogin(pendingUser);
    } catch (err) {
      console.error("[LoginPage] complete login error:", err);
      setError("เข้าสู่ระบบไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    } finally {
      setLoading(false);
    }
  }

  function resetToCredentials() {
    clearInterval(timerRef.current);
    setStep("credentials");
    setPendingToken(null);
    setPendingUser(null);
    setOtpInput("");
    setFailedAttempts(0);
    setPassword("");
  }

  return (
    <div className="min-h-screen bg-slate-50 flex items-center justify-center px-4">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center mb-8">
          <div className="w-14 h-14 rounded-2xl bg-[#D8232A] flex items-center justify-center text-white font-bold text-xl mb-4">
            A
          </div>
          <h1 className="text-xl font-semibold text-slate-900">AfterSales</h1>
          <p className="text-sm text-slate-500 mt-1">
            {step === "credentials" ? "เข้าสู่ระบบสำหรับผู้ดูแลระบบ" : "ยืนยันตัวตนสองขั้นตอน (2FA)"}
          </p>
        </div>

        {step === "credentials" ? (
          <form
            onSubmit={handleSubmit}
            className="bg-white rounded-2xl border border-slate-100 p-6 space-y-4"
          >
            <div>
              <label className="text-xs text-slate-500 mb-1.5 block">ชื่อผู้ใช้</label>
              <div className="relative">
                <User size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  value={username}
                  onChange={(e) => setUsername(e.target.value)}
                  placeholder="ชื่อผู้ใช้"
                  className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-red-100"
                  autoFocus
                  disabled={loading}
                />
              </div>
            </div>

            <div>
              <label className="text-xs text-slate-500 mb-1.5 block">รหัสผ่าน</label>
              <div className="relative">
                <Lock size={16} className="absolute left-3 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type={showPassword ? "text" : "password"}
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  placeholder="รหัสผ่าน"
                  className="w-full pl-9 pr-9 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-sm text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-red-100"
                  disabled={loading}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600"
                >
                  {showPassword ? <EyeOff size={16} /> : <Eye size={16} />}
                </button>
              </div>
            </div>

            {error ? <p className="text-xs text-red-500">{error}</p> : null}

            <button
              type="submit"
              disabled={loading}
              className="w-full py-2.5 rounded-xl bg-[#D8232A] text-white text-sm font-semibold hover:bg-[#B22121] transition-colors disabled:opacity-60 flex items-center justify-center gap-2"
            >
              {loading ? <Loader2 size={16} className="animate-spin" /> : null}
              {loading ? "กำลังตรวจสอบ..." : "เข้าสู่ระบบ"}
            </button>
          </form>
        ) : (
          <form
            onSubmit={handleVerifyOtp}
            className="bg-white rounded-2xl border border-slate-100 p-6 space-y-4"
          >
            <div className="flex flex-col items-center text-center gap-2 pb-1">
              <ShieldCheck size={32} className="text-[#D8232A]" />
              <p className="text-sm text-slate-600">
                ระบบส่งรหัส OTP 6 หลักไปยัง{" "}
                <span className="font-medium text-slate-800">{pendingUser?.email}</span> แล้ว
              </p>
              <p
                className={`text-xs font-medium ${
                  secondsLeft > 0 ? "text-orange-600" : "text-red-500"
                }`}
              >
                {secondsLeft > 0 ? `รหัสหมดอายุใน ${secondsLeft} วินาที` : "รหัส OTP หมดอายุแล้ว"}
              </p>
            </div>

            <input
              value={otpInput}
              onChange={(e) => setOtpInput(e.target.value.replace(/\D/g, "").slice(0, 6))}
              inputMode="numeric"
              maxLength={6}
              placeholder="000000"
              autoFocus
              className="w-full text-center text-2xl tracking-[0.5em] py-3 rounded-xl bg-slate-50 border border-slate-200 text-slate-800 placeholder:text-slate-300 focus:outline-none focus:ring-2 focus:ring-red-100"
              disabled={loading}
            />

            {error ? <p className="text-xs text-red-500 text-center">{error}</p> : null}

            <button
              type="submit"
              disabled={loading || secondsLeft === 0}
              className="w-full py-2.5 rounded-xl bg-[#D8232A] text-white text-sm font-semibold hover:bg-[#B22121] transition-colors disabled:opacity-60 flex items-center justify-center gap-2"
            >
              {loading ? <Loader2 size={16} className="animate-spin" /> : null}
              {loading ? "กำลังยืนยัน..." : "ยืนยัน OTP"}
            </button>

            <div className="flex items-center justify-between text-xs pt-1">
              <button
                type="button"
                onClick={resetToCredentials}
                className="text-slate-400 hover:text-slate-600"
              >
                ยกเลิก / กลับไปกรอกรหัสผ่านใหม่
              </button>
              <button
                type="button"
                disabled={secondsLeft > 0 || loading}
                onClick={() => sendOtpTo(pendingUser.email)}
                className="text-[#D8232A] font-medium disabled:text-slate-300"
              >
                ขอรหัสใหม่
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}
