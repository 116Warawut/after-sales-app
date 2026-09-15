import { initializeApp } from "firebase/app";
import { getDatabase } from "firebase/database";
import { getAuth } from "firebase/auth";

// ==========================================================================
// ค่า config นี้ดึงมาจากโปรเจกต์ Firebase เดียวกับแอป Flutter (aftersales-5c4b4)
// อ้างอิงจาก google-services.json ที่ให้มา — apiKey, projectId, databaseURL,
// storageBucket และ messagingSenderId (project_number) เป็นค่าระดับโปรเจกต์
// ใช้ร่วมกันได้ทั้งเว็บและแอปมือถือ จึงนำมาใช้ตรงนี้ได้เลย
//
// ⚠️ มีจุดเดียวที่ไม่แน่นอน: appId ด้านล่างเป็น appId ของแอป "Android"
// (client_info ระบุ android_client_info) ไม่ใช่ appId ของเว็บโดยเฉพาะ ซึ่งใช้งาน
// Realtime Database ได้ปกติ (ไม่กระทบการอ่าน/เขียนข้อมูล) แต่ถ้าจะใช้ฟีเจอร์อื่น
// ที่ผูกกับ appId เช่น Firebase Analytics บนเว็บ แนะนำให้ไปเพิ่ม "เว็บแอป" ใหม่ใน
// โปรเจกต์เดิมที่ Firebase Console -> Project settings -> Your apps -> ไอคอน "</>"
// แล้วจะได้ appId สำหรับเว็บโดยเฉพาะมาแทนค่านี้
const firebaseConfig = {
  apiKey: "AIzaSyC9I_rU665uqlH1_eR9xnSa1frGnlS1Kjs",
  authDomain: "aftersales-5c4b4.firebaseapp.com",
  databaseURL: "https://aftersales-5c4b4-default-rtdb.asia-southeast1.firebasedatabase.app",
  projectId: "aftersales-5c4b4",
  storageBucket: "aftersales-5c4b4.firebasestorage.app",
  messagingSenderId: "2344674067",
  appId: "1:2344674067:android:5a2904e4a064a49a70b0e6",
};

export const app = initializeApp(firebaseConfig);
export const db = getDatabase(app);
export const auth = getAuth(app);