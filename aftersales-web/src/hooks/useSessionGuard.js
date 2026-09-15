import { useEffect, useRef } from "react";
import { ref, onValue } from "firebase/database";
import { db } from "../firebase";
import { getOrCreateDeviceId } from "../services/session";

// 🆕 [ใหม่] ทำให้ "อนุญาตล็อกอินพร้อมกันหลายอุปกรณ์" (หน้าตั้งค่า > ความ
// ปลอดภัย) ทำงานจริง — subscribe แบบ realtime 2 path พร้อมกันของแอดมินที่
// ล็อกอินอยู่ในเครื่องนี้:
//   1) web_settings_personal/{username} เพื่ออ่านค่า allowMultiDeviceLogin
//      ล่าสุด (ถ้าไปเปลี่ยนที่หน้าตั้งค่าระหว่างที่ล็อกอินค้างอยู่ ก็มีผลทันที
//      ไม่ต้องรีเฟรชหน้า)
//   2) admin_active_sessions/{username} เพื่อดูว่า "อุปกรณ์ล่าสุด" ที่ล็อกอิน
//      เข้าบัญชีนี้คืออุปกรณ์ไหน (เขียนโดย recordAdminLoginDevice() ใน
//      firebaseDb.js ทุกครั้งที่ล็อกอินสำเร็จ)
// ถ้า allowMultiDeviceLogin ปิดอยู่ "และ" อุปกรณ์ล่าสุดไม่ใช่อุปกรณ์นี้ (มีคน
// ล็อกอินทับจากเครื่องอื่น) จะเรียก onForceLogout ทันที — ใช้ deviceId ถาวร
// จาก getOrCreateDeviceId() เทียบ ไม่ใช่ sessionId ชั่วคราว เพราะต้องรอด
// ผ่านการรีเฟรชหน้า/ปิดเปิดเบราว์เซอร์ของอุปกรณ์เดิมได้โดยไม่ถูกเข้าใจผิดว่า
// เป็นอุปกรณ์ใหม่
export default function useSessionGuard(username, onForceLogout) {
  const onForceLogoutRef = useRef(onForceLogout);
  onForceLogoutRef.current = onForceLogout;

  useEffect(() => {
    if (!username) return undefined;

    const myDeviceId = getOrCreateDeviceId();
    let allowMultiDeviceLogin = true;
    let activeDeviceId = null;
    let settingsLoaded = false;
    let sessionLoaded = false;
    let triggered = false;

    function evaluate() {
      if (triggered) return;
      if (!settingsLoaded || !sessionLoaded) return;
      if (allowMultiDeviceLogin) return;
      if (activeDeviceId && activeDeviceId !== myDeviceId) {
        triggered = true;
        onForceLogoutRef.current?.();
      }
    }

    const unsubSettings = onValue(ref(db, `web_settings_personal/${username}`), (snap) => {
      const val = snap.val();
      allowMultiDeviceLogin = val?.allowMultiDeviceLogin !== false;
      settingsLoaded = true;
      evaluate();
    });
    const unsubSession = onValue(ref(db, `admin_active_sessions/${username}`), (snap) => {
      const val = snap.val();
      activeDeviceId = val?.deviceId || null;
      sessionLoaded = true;
      evaluate();
    });

    return () => {
      unsubSettings();
      unsubSession();
    };
  }, [username]);
}
