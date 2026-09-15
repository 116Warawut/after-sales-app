import { useEffect, useState } from "react";
import { listenTable } from "../services/firebaseDb";

/**
 * Hook สำหรับ subscribe ข้อมูลตารางใน Firebase Realtime Database แบบเรียลไทม์
 * ใช้แทนของเดิมที่เป็น mock array ว่าง ๆ (const REPAIRS = []) ในแต่ละหน้า
 *
 * @param {string} table ชื่อตาราง เช่น 'repairs'
 * @returns {{ data: object[], loading: boolean }}
 */
export default function useDbList(table) {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    const unsubscribe = listenTable(table, (rows) => {
      setData(rows);
      setLoading(false);
    });
    return () => unsubscribe();
  }, [table]);

  return { data, loading };
}
