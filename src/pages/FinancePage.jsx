import React, { useState, useMemo, useEffect } from "react";
import { Wallet, CheckCircle2, Clock, Check, Plus, FileText, Printer, Receipt, Trash2, ShieldCheck } from "lucide-react";
import { Card, EmptyState, PrimaryButton, Modal, Pagination } from "../components/ui";
import { COLORS, formatDateBySetting, displayStoredDate } from "../shared/constants";
import useDbList from "../hooks/useDbList";
import useWebSettings from "../hooks/useWebSettings";
import { updateRow, logActivity, nextInvoiceNumber, getWebSettings } from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";

// ---------------------------------------------------------------------------
// 🎨 ภาพรวมสไตล์หน้านี้: การ์ดสรุป 3 ใบ (สไตล์เดียวกับการ์ดสถิติหน้าอื่น ๆ ใน
// เว็บนี้) + ตารางใบแจ้งหนี้ — badge "ชำระแล้ว" สีเขียว / "ยังไม่ชำระ" สีส้ม
// 🔴 [แก้ไข] เพิ่มปุ่ม "ออกใบแจ้งหนี้ใหม่" + หน้าออกบิลจริง (เลือกงานที่ยังไม่
// ออกบิล ดึงอะไหล่ที่อนุมัติแล้วของงานนั้นมาคำนวณยอดอะไหล่อัตโนมัติ + กรอกค่าแรง
// เอง แล้วบันทึกยอดรวมกลับไปที่ repairs.total_price) — ก่อนหน้านี้หน้านี้ทำได้
// แค่ดู/มาร์กว่าชำระแล้ว ยังออกบิลใหม่จากเว็บไม่ได้เลย
// ---------------------------------------------------------------------------

// ออกบิลได้เฉพาะงานที่ "เสร็จสิ้น" แล้วและยังไม่เคยตั้งยอดไว้ (total_price = 0)
// เท่านั้น — ป้องกันออกบิลงานที่ยังไม่เสร็จหรือออกบิลซ้ำงานเดิม
function isInvoiceable(r) {
  const status = r.status || "";
  return (status === "เสร็จสิ้น" || status === "เสร็จแล้ว") && !(Number(r.total_price) > 0);
}

// 🔴 [แก้บั๊ก] เดิมเว็บมีสถานะการชำระแค่ 2 แบบ (ชำระแล้ว/ยังไม่ชำระ จาก is_paid
// อย่างเดียว) ทั้งที่ลูกค้าฝั่งแอปมือถืออัปโหลดสลิปโอนเงินไว้ที่ฟิลด์
// customer_payment_slip บน repairs/{id} (เช็กกับ services.dart/payment.dart จริง
// แล้ว) แต่เว็บไม่เคยอ่านฟิลด์นี้เลยแม้แต่นิดเดียว แอดมินเลยมองไม่เห็นหลักฐาน
// การโอนเงินบนเว็บ ต้องไปเปิดแอปมือถือดูแทน — เพิ่มสถานะกลาง "รอตรวจสอบสลิป"
// (มีสลิปแล้วแต่แอดมินยังไม่กดยืนยัน) คั่นระหว่าง "ยังไม่ชำระ" กับ "ชำระแล้ว"
function getPaymentState(r) {
  // 🆕 [ใหม่] ให้ตรงกับฝั่งแอป — บิลที่อยู่ในประกันถูกมาร์ก is_paid ให้อัตโนมัติ
  // (ไม่มีการชำระเงินจริง) ต้องแยกออกจาก "ชำระแล้ว" จริงๆ กันแอดมินสับสน/นับรายได้ผิด
  const isWarranty = r.is_warranty_covered === true || r.is_warranty_covered === 1;
  if (isWarranty) return "warranty";
  const isPaid = r.is_paid === 1 || r.is_paid === true;
  if (isPaid) return "paid";
  if (r.customer_payment_slip) return "awaiting";
  return "unpaid";
}

// 🆕 [ใหม่] พอร์ตลอจิกเช็คประกันจาก Machine.warrantyActive/warrantyStatusText
// ในแอป (screens/customer/machine_models.dart) มาใช้ฝั่งเว็บ เพื่อให้หน้าออกบิล
// เว็บตรวจจับประกันของเครื่องจักรได้แบบเดียวกับหน้าออกบิลในแอป
// (admin_create_invoice.dart)
function getMachineWarrantyInfo(machine) {
  if (!machine?.warranty_start_date || !machine?.warranty_months) {
    return { active: false, statusText: null };
  }
  const start = new Date(machine.warranty_start_date);
  if (isNaN(start.getTime())) return { active: false, statusText: null };
  const end = new Date(start);
  end.setMonth(end.getMonth() + Number(machine.warranty_months));
  const msPerDay = 1000 * 60 * 60 * 24;
  const today = new Date();
  const daysLeft = Math.round(
    (new Date(end.getFullYear(), end.getMonth(), end.getDate()) -
      new Date(today.getFullYear(), today.getMonth(), today.getDate())) /
      msPerDay
  );
  if (daysLeft < 0) {
    return { active: false, statusText: `ประกันหมดอายุแล้ว (${-daysLeft} วันก่อน)` };
  }
  const months = Math.floor(daysLeft / 30);
  return {
    active: true,
    statusText: months > 0 ? `ประกัน: เหลือประมาณ ${months} เดือน` : `ประกัน: เหลือ ${daysLeft} วัน`,
  };
}

// 🔴 [แก้ไข] เดิม CreateInvoiceModal คำนวณยอดอะไหล่อัตโนมัติจากคำขอเบิกที่อนุมัติ
// แล้วเท่านั้น (join ราคาด้วย record_id ซึ่งเป็นฟิลด์ id ภายในของอะไหล่ — ข้อมูล
// อะไหล่บางส่วนมีฟิลด์นี้เป็น 0 ซ้ำกันหลายชิ้น เพราะย้ายมาจาก SQLite แล้วไม่ได้ตั้ง
// id ให้ครบ ทำให้จับคู่ราคาผิดชิ้นหรือหาไม่เจอ ราคาอะไหล่เลยไม่ขึ้น) และไม่มีทาง
// เพิ่มรายการเองได้เลย ต่างจากหน้าออกบิลฝั่งแอป (admin_create_invoice.dart) ที่ให้
// แอดมินเพิ่ม/แก้ไข/ลบรายการได้อิสระ ทำให้สองฝั่งออกบิลคนละแบบ ไม่ sync กัน —
// เปลี่ยนมาใช้กลไกเดียวกับแอป: รายการในบิลแก้ไขได้อิสระ, เสนอคำขอเบิกที่อนุมัติ
// แล้วให้กดเพิ่มเข้าบิลทีละรายการ (จับคู่ราคาด้วย .id ซึ่งเป็น Firebase key จริง
// ของแถวอะไหล่ — ตรงกับที่ getSparePartById() ฝั่งแอปดึงตรงจาก path ของ key จริง
// เช่นกัน ไม่มีทางซ้ำ), auto-prefill ค่าแรงจาก estimated_price, และเช็คประกัน
// เครื่องจักรอัตโนมัติเหมือนกันทุกอย่าง
function CreateInvoiceModal({ repairs, partRequests, spareParts, machines, onClose }) {
  const invoiceableJobs = repairs.filter(isInvoiceable);
  const [repairId, setRepairId] = useState("");
  const [items, setItems] = useState([]);
  const [isWarrantyCovered, setIsWarrantyCovered] = useState(false);
  const [warrantyStatusText, setWarrantyStatusText] = useState(null);
  // 🆕 [ใหม่] ภาษี — พอร์ตสูตรคำนวณเดียวกับหน้าออกบิลฝั่งแอปทุกจุด (ดู
  // _subtotal/_discountAmount/_vatAmount/_withholdingTaxAmount/_grandTotal ใน
  // admin_create_invoice.dart): ส่วนลดเป็นจำนวนเงินบาท (ไม่ใช่ %) หักก่อนคิด
  // VAT/WHT, VAT คงที่ 7% เปิด/ปิดได้, หัก ณ ที่จ่ายเลือกอัตราได้ (1/2/3/5%)
  // คำนวณจากยอดหลังหักส่วนลด (ก่อน VAT)
  const [discount, setDiscount] = useState("");
  const [includeVat, setIncludeVat] = useState(true);
  const [enableWht, setEnableWht] = useState(false);
  const [whtRate, setWhtRate] = useState(3);
  const [saving, setSaving] = useState(false);

  const selectedJob = invoiceableJobs.find((r) => String(r.id) === String(repairId));

  const machineById = useMemo(() => {
    const map = new Map();
    (machines || []).forEach((m) => map.set(String(m.id), m));
    return map;
  }, [machines]);

  // คำขอเบิกอะไหล่ที่อนุมัติแล้วของงานนี้ (ยังไม่ถูกออกบิล) — เสนอให้กดเพิ่ม
  // เข้าบิลได้ทันที เหมือนหน้าออกบิลฝั่งแอป
  // 🐛 [แก้บั๊ก] เดิมจับคู่ด้วย record_id (ฟิลด์ id ภายในของงานซ่อม ซึ่งข้อมูลเก่า
  // บางส่วนมีค่าเป็น 0 ซ้ำกันหลายงาน หรือไม่มีค่าเลยสำหรับงานที่สร้างใหม่บน
  // Firebase) เท่านั้น ทั้งที่ repair_id ที่ฝั่งแอปมือถือบันทึกไว้ใน part_requests
  // (ดู spare_part_tec_viewer.dart) เป็นคีย์จริงใน Firebase (widget.repairId ตรง
  // กับ selectedJob.id) — ผลคือรายการอะไหล่ที่ช่างเบิกและแอดมินอนุมัติแล้วแทบไม่
  // เคยโผล่มาให้กดเพิ่มเข้าบิลเลย เหมือนบั๊กเดียวกับที่แก้ไปแล้วใน
  // SparePartsPage.jsx/DashboardPage.jsx/ReportsPage.jsx — เปลี่ยนมาเทียบทั้งสอง
  // แบบ (record_id ก่อน แล้วค่อยลองด้วย id) ให้ครอบคลุมทั้งงานเก่าและงานใหม่
  const availablePartRequests = useMemo(() => {
    if (!selectedJob) return [];
    return partRequests.filter(
      (pr) =>
        (String(pr.repair_id) === String(selectedJob.record_id) ||
          String(pr.repair_id) === String(selectedJob.id)) &&
        pr.status === "อนุมัติแล้ว"
    );
  }, [selectedJob, partRequests]);

  function priceForPartId(partId) {
    const part = spareParts.find((p) => String(p.id) === String(partId));
    return Number(part?.price) || 0;
  }

  // เปลี่ยนงานที่เลือก → รีเซ็ตรายการ แล้ว prefill ค่าแรงประเมิน (ถ้ามี) + เช็ค
  // ประกันเครื่องจักรอัตโนมัติ ให้เหมือนพฤติกรรมตอนเปิดหน้าออกบิลฝั่งแอป
  useEffect(() => {
    if (!selectedJob) {
      setItems([]);
      setIsWarrantyCovered(false);
      setWarrantyStatusText(null);
      return;
    }
    const initial = [];
    const estimatedPrice = Number(selectedJob.estimated_price) || 0;
    if (estimatedPrice > 0) {
      initial.push({ key: "estimated_labor", name: "ค่าแรง (ราคาประเมินจากช่าง)", qty: 1, price: estimatedPrice });
    }
    setItems(initial);
    // รีเซ็ตส่วนลด/ภาษีกลับเป็นค่าเริ่มต้นทุกครั้งที่เปลี่ยนงาน (เหมือนเปิดหน้า
    // ออกบิลใหม่ทุกครั้งฝั่งแอป)
    setDiscount("");
    setIncludeVat(true);
    setEnableWht(false);
    setWhtRate(3);

    const machine = selectedJob.machine_id != null ? machineById.get(String(selectedJob.machine_id)) : null;
    const info = getMachineWarrantyInfo(machine);
    setIsWarrantyCovered(info.active);
    setWarrantyStatusText(machine ? info.statusText : null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedJob?.id]);

  const subtotal = items.reduce((sum, it) => sum + (Number(it.qty) || 0) * (Number(it.price) || 0), 0);
  const discountAmount = Math.min(Number(discount) || 0, subtotal);
  const subtotalAfterDiscount = subtotal - discountAmount;
  const vatAmount = includeVat ? subtotalAfterDiscount * 0.07 : 0;
  const whtAmount = enableWht ? subtotalAfterDiscount * (whtRate / 100) : 0;
  const grandTotal = subtotalAfterDiscount + vatAmount - whtAmount;
  const addedRequestIds = new Set(items.filter((it) => it.sourceRequestId).map((it) => it.sourceRequestId));

  function addPartRequestItem(pr) {
    setItems((prev) => [
      ...prev,
      {
        key: `part_req_${pr.id}`,
        name: pr.part_name || "อะไหล่",
        qty: Number(pr.quantity) || 1,
        price: priceForPartId(pr.part_id),
        sourceRequestId: pr.id,
      },
    ]);
  }

  function addBlankItem() {
    setItems((prev) => [...prev, { key: `custom_${Date.now()}`, name: "", qty: 1, price: 0 }]);
  }

  function updateItem(key, patch) {
    setItems((prev) => prev.map((it) => (it.key === key ? { ...it, ...patch } : it)));
  }

  function removeItem(key) {
    setItems((prev) => prev.filter((it) => it.key !== key));
  }

  async function handleSave() {
    if (!selectedJob || items.length === 0) return;
    setSaving(true);
    try {
      const invoiceNo = await nextInvoiceNumber();
      const cleanItems = items
        .filter((it) => it.name.trim())
        .map((it) => ({
          name: it.name.trim(),
          qty: Number(it.qty) || 0,
          price: Number(it.price) || 0,
          subtotal: (Number(it.qty) || 0) * (Number(it.price) || 0),
        }));
      // 🆕 [ใหม่] คำนวณจาก cleanItems (ตัดแถวที่ไม่ได้ตั้งชื่อทิ้งแล้ว) ให้ตรงกับ
      // ยอดที่บันทึกจริง แทนที่จะใช้ subtotal/grandTotal ที่คำนวณจาก items ดิบ
      // ด้านบน (ซึ่งอาจมีแถวว่างชื่อปนอยู่)
      const cleanSubtotal = cleanItems.reduce((sum, it) => sum + it.subtotal, 0);
      const cleanDiscount = Math.min(Number(discount) || 0, cleanSubtotal);
      const cleanAfterDiscount = cleanSubtotal - cleanDiscount;
      const cleanVat = includeVat ? cleanAfterDiscount * 0.07 : 0;
      const cleanWht = enableWht ? cleanAfterDiscount * (whtRate / 100) : 0;
      const total = cleanAfterDiscount + cleanVat - cleanWht;

      // 🆕 [ใหม่] ให้ตรงกับ updateRepairBill() ฝั่งแอป — บิลที่อยู่ในประกันมาร์ก
      // ว่าชำระแล้วทันที (ไม่มีค่าใช้จ่ายจริง ไม่ต้องรอลูกค้าจ่าย) และแยกด้วย
      // is_warranty_covered กันไม่ให้ปนกับรายได้จริงตอนสรุปยอด (ดู totalRevenue
      // ด้านล่าง) — ส่วนฟิลด์ invoice_subtotal/discount/vat/wht เก็บไว้เพิ่มเติม
      // (แอปไม่ได้เก็บ breakdown พวกนี้ เก็บแค่ total_price) เพื่อให้ใบแจ้งหนี้ที่
      // พิมพ์จากเว็บ (InvoiceModal) โชว์รายละเอียดส่วนลด/ภาษีได้ครบ
      const updates = {
        total_price: total,
        invoiced_at: new Date().toISOString(),
        invoice_no: invoiceNo,
        invoice_items: cleanItems,
        invoice_subtotal: cleanSubtotal,
        invoice_discount: cleanDiscount,
        invoice_vat_amount: cleanVat,
        invoice_wht_amount: cleanWht,
        is_warranty_covered: isWarrantyCovered,
        is_paid: isWarrantyCovered ? 1 : 0,
      };
      if (isWarrantyCovered) {
        updates.receipt_no = `WARRANTY-${invoiceNo}`;
      }
      await updateRow("repairs", selectedJob.id, updates);

      // มาร์กคำขอเบิกที่ถูกดึงเข้าบิลแล้วว่า "ออกบิลแล้ว" กันถูกเสนอซ้ำในบิลใบอื่น
      // ทีหลัง (พฤติกรรมเดียวกับ _addPartRequestToInvoice() ฝั่งแอป)
      await Promise.all(
        items
          .filter((it) => it.sourceRequestId)
          .map((it) =>
            updateRow("part_requests", it.sourceRequestId, { status: "ออกบิลแล้ว" }).catch((err) =>
              console.error("[FinancePage] mark part request billed failed:", err)
            )
          )
      );

      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "ออกใบแจ้งหนี้",
        target: `${invoiceNo} · ${selectedJob.ticketNo || `#${selectedJob.id}`} · ${total.toLocaleString("th-TH")} บาท`,
      }).catch((err) => console.error("[FinancePage] log activity failed:", err));
      onClose();
    } catch (err) {
      console.error("[FinancePage] create invoice failed:", err);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal
      title="ออกใบแจ้งหนี้ใหม่"
      onClose={onClose}
      wide
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ยกเลิก
          </button>
          <PrimaryButton onClick={handleSave} disabled={!selectedJob || items.length === 0 || saving}>
            {saving ? "กำลังบันทึก..." : "ออกใบแจ้งหนี้"}
          </PrimaryButton>
        </>
      }
    >
      <div>
        <label className="text-sm text-slate-600 mb-2 block font-medium">
          เลือกงานซ่อม <span className="text-red-400">*</span>
        </label>
        <select
          value={repairId}
          onChange={(e) => setRepairId(e.target.value)}
          className="w-full px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
        >
          <option value="">เลือกงานที่เสร็จสิ้นแล้วและยังไม่ออกบิล...</option>
          {invoiceableJobs.map((r) => (
            <option key={r.id} value={r.id}>
              {r.ticketNo || `#${r.id}`} — {r.customer_username || "-"} ({r.machine || "-"})
            </option>
          ))}
        </select>
        {invoiceableJobs.length === 0 ? (
          <p className="text-xs text-slate-400 mt-2">ไม่มีงานที่พร้อมออกบิลตอนนี้ (ต้องเป็นงานที่เสร็จสิ้นแล้วและยังไม่เคยออกบิล)</p>
        ) : null}
      </div>

      {selectedJob ? (
        <>
          {/* 🛡️ [ใหม่] การรับประกัน — เหมือนการ์ด "การรับประกัน" ในหน้าออกบิลฝั่งแอป
              ตรวจจับอัตโนมัติจากข้อมูลเครื่องจักร แอดมินเปิด/ปิดเองทีหลังได้ */}
          <div className="rounded-xl border border-slate-100 p-4">
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={isWarrantyCovered}
                onChange={(e) => setIsWarrantyCovered(e.target.checked)}
                className="rounded border-slate-300"
              />
              <span className="text-sm font-medium text-slate-700">อยู่ในประกัน (ลูกค้าไม่ต้องชำระเงิน)</span>
            </label>
            <p className="text-xs text-slate-400 mt-1.5 ml-6">
              {warrantyStatusText
                ? `ตรวจสอบจากข้อมูลเครื่องจักร: ${warrantyStatusText}`
                : "ไม่พบข้อมูลประกันของเครื่องจักรนี้ในระบบ — เลือกเองได้ถ้าทราบว่ายังอยู่ในประกัน"}
            </p>
          </div>

          {/* รายการในบิล — เพิ่ม/แก้ไข/ลบได้อิสระเหมือนฝั่งแอป */}
          <div className="rounded-xl border border-slate-100 p-4">
            <div className="flex items-center justify-between mb-2">
              <p className="text-xs font-semibold text-slate-500">รายการในบิล</p>
              <button
                onClick={addBlankItem}
                className="flex items-center gap-1 text-xs font-medium text-blue-600 hover:text-blue-700"
              >
                <Plus size={13} /> เพิ่มรายการเอง
              </button>
            </div>
            {items.length === 0 ? (
              <p className="text-xs text-slate-400 py-2">ยังไม่มีรายการในบิล — เพิ่มจากคำขอเบิกด้านล่าง หรือกด "เพิ่มรายการเอง"</p>
            ) : (
              <div className="space-y-2">
                {items.map((it) => (
                  <div key={it.key} className="flex items-center gap-2">
                    <input
                      type="text"
                      value={it.name}
                      onChange={(e) => updateItem(it.key, { name: e.target.value })}
                      placeholder="ชื่อรายการ"
                      className="flex-1 min-w-0 px-3 py-2 rounded-lg bg-slate-50 border border-slate-200 text-sm text-slate-700"
                    />
                    <input
                      type="number"
                      value={it.qty}
                      onChange={(e) => updateItem(it.key, { qty: e.target.value })}
                      className="w-16 px-2 py-2 rounded-lg bg-slate-50 border border-slate-200 text-sm text-slate-700 text-center"
                      title="จำนวน"
                    />
                    <input
                      type="number"
                      value={it.price}
                      onChange={(e) => updateItem(it.key, { price: e.target.value })}
                      className="w-24 px-2 py-2 rounded-lg bg-slate-50 border border-slate-200 text-sm text-slate-700 text-right"
                      title="ราคา/หน่วย"
                    />
                    <span className="w-24 shrink-0 text-right text-sm font-medium text-slate-700">
                      {((Number(it.qty) || 0) * (Number(it.price) || 0)).toLocaleString("th-TH")}
                    </span>
                    <button onClick={() => removeItem(it.key)} className="text-red-400 hover:text-red-600 shrink-0">
                      <Trash2 size={15} />
                    </button>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* คำขอเบิกอะไหล่ที่อนุมัติแล้ว — กดเพิ่มเข้าบิลได้ทันที ไม่ต้องพิมพ์เอง */}
          {availablePartRequests.length > 0 ? (
            <div className="rounded-xl border border-slate-100 p-4">
              <p className="text-xs font-semibold text-slate-500 mb-2">คำขอเบิกอะไหล่ที่อนุมัติแล้ว (ยังไม่ออกบิล)</p>
              <div className="space-y-1.5">
                {availablePartRequests.map((pr) => {
                  const added = addedRequestIds.has(pr.id);
                  return (
                    <div key={pr.id} className="flex items-center justify-between text-sm gap-2">
                      <span className="text-slate-600">
                        {pr.part_name} × {pr.quantity} ({priceForPartId(pr.part_id).toLocaleString("th-TH")} บาท/ชิ้น)
                      </span>
                      <button
                        onClick={() => addPartRequestItem(pr)}
                        disabled={added}
                        className={`shrink-0 text-xs font-medium px-2.5 py-1 rounded-lg ${
                          added ? "bg-slate-50 text-slate-300" : "bg-blue-50 text-blue-600 hover:bg-blue-100"
                        }`}
                      >
                        {added ? "เพิ่มแล้ว" : "+ เพิ่มเข้าบิล"}
                      </button>
                    </div>
                  );
                })}
              </div>
            </div>
          ) : null}

          {/* 💸 [ใหม่] ส่วนลด + ภาษี — เหมือนหน้าออกบิลฝั่งแอปทุกจุด */}
          <div className="rounded-xl border border-slate-100 p-4 space-y-3">
            <div>
              <label className="text-xs font-medium text-slate-500 mb-1 block">ส่วนลด (บาท)</label>
              <input
                type="number"
                value={discount}
                onChange={(e) => setDiscount(e.target.value)}
                placeholder="0"
                className="w-full px-3 py-2 rounded-lg bg-slate-50 border border-slate-200 text-sm text-slate-700 placeholder:text-slate-400"
              />
            </div>
            <label className="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                checked={includeVat}
                onChange={(e) => setIncludeVat(e.target.checked)}
                className="rounded border-slate-300"
              />
              <span className="text-sm text-slate-700">ภาษีมูลค่าเพิ่ม (VAT 7%)</span>
            </label>
            <div>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={enableWht}
                  onChange={(e) => setEnableWht(e.target.checked)}
                  className="rounded border-slate-300"
                />
                <span className="text-sm text-slate-700">หักภาษี ณ ที่จ่าย</span>
              </label>
              {enableWht ? (
                <select
                  value={whtRate}
                  onChange={(e) => setWhtRate(Number(e.target.value))}
                  className="mt-2 ml-6 px-3 py-1.5 rounded-lg bg-slate-50 border border-slate-200 text-sm text-slate-700"
                >
                  <option value={1}>1% (ขนส่ง)</option>
                  <option value={2}>2% (โฆษณา)</option>
                  <option value={3}>3% (บริการ)</option>
                  <option value={5}>5% (ค่าเช่า)</option>
                </select>
              ) : null}
            </div>
          </div>

          <div className="rounded-xl bg-blue-50 px-4 py-3 space-y-1.5">
            <div className="flex items-center justify-between text-sm">
              <span className="text-slate-500">รวมรายการ</span>
              <span className="text-slate-700">{subtotal.toLocaleString("th-TH")} บาท</span>
            </div>
            {discountAmount > 0 ? (
              <div className="flex items-center justify-between text-sm">
                <span className="text-slate-500">ส่วนลด</span>
                <span className="text-red-500">-{discountAmount.toLocaleString("th-TH")} บาท</span>
              </div>
            ) : null}
            {includeVat ? (
              <div className="flex items-center justify-between text-sm">
                <span className="text-slate-500">VAT 7%</span>
                <span className="text-slate-700">+{vatAmount.toLocaleString("th-TH")} บาท</span>
              </div>
            ) : null}
            {enableWht ? (
              <div className="flex items-center justify-between text-sm">
                <span className="text-slate-500">หัก ณ ที่จ่าย {whtRate}%</span>
                <span className="text-red-500">-{whtAmount.toLocaleString("th-TH")} บาท</span>
              </div>
            ) : null}
            <div className="flex items-center justify-between pt-1.5 border-t border-blue-100">
              <span className="text-sm font-medium text-blue-700">ยอดรวมทั้งหมด</span>
              <span className="text-lg font-semibold text-blue-700">{grandTotal.toLocaleString("th-TH")} บาท</span>
            </div>
          </div>
          {isWarrantyCovered ? (
            <p className="text-xs text-emerald-600 -mt-2">ลูกค้าไม่ต้องชำระเงิน (อยู่ในประกัน)</p>
          ) : null}
        </>
      ) : null}
    </Modal>
  );
}

// -----------------------------------------------------------------------------
// 🧾 [ใหม่] ใบแจ้งหนี้จริงต่อ 1 งานซ่อม — แยกจาก "ดาวน์โหลดรายงาน" ในหน้ารายงาน
// ที่เป็นแค่สรุปภาพรวมทั้งระบบ ใบนี้เป็นเอกสารทางการที่พิมพ์ให้ลูกค้าถือกลับได้
// จริง มีเลขที่ใบแจ้งหนี้ + รายการอะไหล่/ค่าแรง + ที่อยู่ลูกค้า ใช้ window.print()
// แบบเดียวกับที่ทำไว้ในหน้ารายงาน (ไม่ต้องเพิ่มไลบรารี PDF ใหม่)
// -----------------------------------------------------------------------------
function formatCustomerAddress(c) {
  if (!c) return "-";
  const parts = [
    c.house_no,
    c.moo ? `หมู่ ${c.moo}` : "",
    c.tambon ? `ตำบล${c.tambon}` : "",
    c.amphoe ? `อำเภอ${c.amphoe}` : "",
    c.changwat ? `จังหวัด${c.changwat}` : "",
    c.postal_code,
  ].filter(Boolean);
  return parts.length > 0 ? parts.join(" ") : "-";
}

function InvoiceModal({ repair, customer, companySettings, onClose }) {
  const items = Array.isArray(repair.invoice_items) ? repair.invoice_items : [];
  const laborCost = Number(repair.labor_cost) || 0;
  const total = Number(repair.total_price) || 0;
  // 🆕 [ใหม่] breakdown ส่วนลด/ภาษี — มีเฉพาะบิลที่ออกจากฟอร์มใหม่ (เว็บ) เท่านั้น
  // บิลเก่า/บิลที่ออกจากแอปจะไม่มีฟิลด์พวกนี้ (แอปเก็บแค่ total_price รวมสุทธิ)
  // จึงต้องเช็คก่อนแสดงเสมอ
  const subtotal = Number(repair.invoice_subtotal) || 0;
  const discount = Number(repair.invoice_discount) || 0;
  const vatAmount = Number(repair.invoice_vat_amount) || 0;
  const whtAmount = Number(repair.invoice_wht_amount) || 0;
  const hasBreakdown = subtotal > 0;
  const isPaid = repair.is_paid === 1 || repair.is_paid === true;
  // 🆕 [ใหม่] แยกโชว์ "ไม่มีค่าใช้จ่าย (ประกัน)" แทน "ชำระแล้ว" เฉยๆ กันลูกค้า/
  // แอดมินเข้าใจผิดว่ามีการโอนเงินจริงเกิดขึ้น (ดู is_warranty_covered ที่
  // CreateInvoiceModal เซ็ตไว้ตอนออกบิล หรือฝั่งแอปที่ updateRepairBill() ตั้งให้)
  const isWarrantyCovered = repair.is_warranty_covered === true || repair.is_warranty_covered === 1;
  const issuedDate = repair.invoiced_at ? new Date(repair.invoiced_at) : null;
  const dateLabel = issuedDate ? formatDateBySetting(issuedDate) : "-";
  const customerName = customer ? [customer.name, customer.surname].filter(Boolean).join(" ") || customer.username : repair.customer_username || "-";

  return (
    <Modal
      title="ใบแจ้งหนี้"
      onClose={onClose}
      wide
      footer={
        <>
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50">
            ปิด
          </button>
          <button
            onClick={() => window.print()}
            className="flex items-center gap-2 px-4 py-2 rounded-xl text-sm font-medium text-white"
            style={{ background: "#B22121" }}
          >
            <Printer size={15} />
            พิมพ์ / บันทึกเป็น PDF
          </button>
        </>
      }
    >
      <style>{`
        @media print {
          /* 🐛 [แก้ไข] BUG เดียวกับหน้า Dashboard — Modal ที่ห่ออยู่มี
             overflow-y-auto + max-h-[88vh] เป็น position: relative อยู่แล้ว
             ใช้ position: absolute ให้พื้นที่พิมพ์เลยโดนตัดตามกรอบ Modal แทน
             เปลี่ยนเป็น fixed ให้ยึดวิวพอร์ตทั้งหน้าแทน */
          body * { visibility: hidden; }
          #print-invoice-area, #print-invoice-area * { visibility: visible; }
          #print-invoice-area {
            position: fixed;
            inset: 0;
            width: 100%;
            height: auto;
            overflow: visible;
            padding: 24px;
            margin: 0;
          }
        }
      `}</style>

      <div id="print-invoice-area" className="text-slate-800">
        <div className="flex items-start justify-between mb-6 pb-4 border-b border-slate-200">
          <div>
            <h1 className="text-lg font-bold" style={{ color: "#B22121" }}>{companySettings?.companyName || "ระบบแจ้งซ่อม After Sales"}</h1>
            {companySettings?.companyPhone ? <p className="text-xs text-slate-400 mt-1">โทร {companySettings.companyPhone}</p> : null}
            {companySettings?.companyEmail ? <p className="text-xs text-slate-400">{companySettings.companyEmail}</p> : null}
          </div>
          <div className="text-right">
            <p className="text-base font-bold text-slate-800">ใบแจ้งหนี้</p>
            <p className="text-sm text-slate-500 mt-0.5">{repair.invoice_no || "-"}</p>
            <p className="text-xs text-slate-400 mt-1">วันที่ {dateLabel}</p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 mb-6">
          <div>
            <p className="text-xs font-semibold text-slate-500 mb-1">ลูกค้า</p>
            <p className="text-sm font-medium text-slate-800">{customerName}</p>
            {customer?.company ? <p className="text-xs text-slate-500">{customer.company}</p> : null}
            <p className="text-xs text-slate-500 mt-1">{formatCustomerAddress(customer)}</p>
            {customer?.phone ? <p className="text-xs text-slate-500 mt-1">โทร {customer.phone}</p> : null}
          </div>
          <div>
            <p className="text-xs font-semibold text-slate-500 mb-1">งานซ่อม</p>
            <p className="text-sm font-medium text-slate-800">{repair.ticketNo || `#${repair.id}`}</p>
            <p className="text-xs text-slate-500 mt-1">{repair.machine || "-"}</p>
            <p className="text-xs text-slate-500 mt-1">วันนัดหมาย: {displayStoredDate(repair.date)}</p>
          </div>
        </div>

        <table className="w-full text-sm mb-4">
          <thead>
            <tr className="text-xs text-slate-400 border-b border-slate-200">
              <th className="text-left font-medium py-2">รายการ</th>
              <th className="text-right font-medium py-2">จำนวน</th>
              <th className="text-right font-medium py-2">ราคา/หน่วย</th>
              <th className="text-right font-medium py-2">รวม</th>
            </tr>
          </thead>
          <tbody>
            {items.map((it, i) => (
              <tr key={i} className="border-b border-slate-50">
                <td className="py-2 text-slate-700">{it.name}</td>
                <td className="py-2 text-right text-slate-600">{it.qty}</td>
                <td className="py-2 text-right text-slate-600">{Number(it.price).toLocaleString("th-TH")}</td>
                <td className="py-2 text-right text-slate-700 font-medium">{Number(it.subtotal).toLocaleString("th-TH")}</td>
              </tr>
            ))}
            {laborCost > 0 ? (
              <tr className="border-b border-slate-50">
                <td className="py-2 text-slate-700">ค่าแรง</td>
                <td className="py-2 text-right text-slate-600">-</td>
                <td className="py-2 text-right text-slate-600">-</td>
                <td className="py-2 text-right text-slate-700 font-medium">{laborCost.toLocaleString("th-TH")}</td>
              </tr>
            ) : null}
            {items.length === 0 && laborCost === 0 ? (
              <tr>
                <td colSpan={4} className="py-4 text-center text-xs text-slate-400">ไม่มีรายการ</td>
              </tr>
            ) : null}
          </tbody>
        </table>

        <div className="flex justify-end">
          <div className="w-64">
            {/* 🆕 [ใหม่] โชว์ breakdown ส่วนลด/VAT/หัก ณ ที่จ่าย ถ้ามี (เฉพาะบิลที่
                ออกจากฟอร์มใหม่บนเว็บ) */}
            {hasBreakdown ? (
              <>
                <div className="flex items-center justify-between py-1 text-sm">
                  <span className="text-slate-500">รวมรายการ</span>
                  <span className="text-slate-700">{subtotal.toLocaleString("th-TH")} บาท</span>
                </div>
                {discount > 0 ? (
                  <div className="flex items-center justify-between py-1 text-sm">
                    <span className="text-slate-500">ส่วนลด</span>
                    <span className="text-red-500">-{discount.toLocaleString("th-TH")} บาท</span>
                  </div>
                ) : null}
                {vatAmount > 0 ? (
                  <div className="flex items-center justify-between py-1 text-sm">
                    <span className="text-slate-500">VAT 7%</span>
                    <span className="text-slate-700">+{vatAmount.toLocaleString("th-TH")} บาท</span>
                  </div>
                ) : null}
                {whtAmount > 0 ? (
                  <div className="flex items-center justify-between py-1 text-sm">
                    <span className="text-slate-500">หัก ณ ที่จ่าย</span>
                    <span className="text-red-500">-{whtAmount.toLocaleString("th-TH")} บาท</span>
                  </div>
                ) : null}
              </>
            ) : null}
            <div className="flex items-center justify-between py-2 border-t border-slate-200">
              <span className="text-sm font-semibold text-slate-700">ยอดรวมทั้งหมด</span>
              <span className="text-base font-bold" style={{ color: "#B22121" }}>฿{total.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-slate-500">สถานะการชำระ</span>
              <span className={`text-xs font-semibold ${isWarrantyCovered || isPaid ? "text-emerald-600" : "text-orange-500"}`}>
                {isWarrantyCovered ? "ไม่มีค่าใช้จ่าย (อยู่ในประกัน)" : isPaid ? "ชำระแล้ว" : "ยังไม่ชำระ"}
              </span>
            </div>
          </div>
        </div>
      </div>
    </Modal>
  );
}

export default function FinancePage() {
  const { data: repairs, loading } = useDbList("repairs");
  const { data: partRequests } = useDbList("part_requests");
  const { data: spareParts } = useDbList("spare_parts");
  const { data: customers } = useDbList("customers");
  // 🆕 [ใหม่] โหลดตาราง machines มาด้วย ให้ CreateInvoiceModal เช็คประกันของ
  // เครื่องจักรที่ผูกกับงานซ่อมได้ (เหมือนหน้าออกบิลฝั่งแอป)
  const { data: machines } = useDbList("machines");
  // 🔴 [แก้ไข] state เปิด/ปิด modal "ออกใบแจ้งหนี้ใหม่"
  const [creatingInvoice, setCreatingInvoice] = useState(false);
  // 🧾 [ใหม่] state เปิด/ปิด modal ดู/พิมพ์ใบแจ้งหนี้ของงานที่เลือก + ข้อมูล
  // บริษัทจากหน้าตั้งค่า (ใช้เป็นหัวใบแจ้งหนี้)
  const [viewingInvoice, setViewingInvoice] = useState(null);
  // 🔴 [ใหม่] state เปิด/ปิด modal ดูสลิปโอนเงินที่ลูกค้าอัปโหลดมาจากแอปมือถือ
  const [viewingSlip, setViewingSlip] = useState(null);
  const [companySettings, setCompanySettings] = useState(null);
  // 🔴 [แก้ไข] itemsPerPageFinance/dateFormat ย้ายไปเป็นค่าตั้งค่าส่วนตัวราย
  // แอดมินแล้ว (ไม่ได้อยู่ใน web_settings รวมของบริษัทอีกต่อไป) เลยต้องดึงจาก
  // useWebSettings() แยกออกมาจาก companySettings ที่เหลือไว้แค่ข้อมูลบริษัท
  // (ชื่อ/เบอร์/อีเมล) สำหรับหัวใบแจ้งหนี้เท่านั้น
  const { settings: webSettings } = useWebSettings();

  useEffect(() => {
    getWebSettings()
      .then(setCompanySettings)
      .catch((err) => console.error("[FinancePage] load settings failed:", err));
  }, []);

  // งานที่ "ออกบิลแล้ว" คือมี total_price ตั้งไว้มากกว่า 0
  const invoiced = repairs.filter((r) => Number(r.total_price) > 0);

  // 🆕 [ใหม่] ไม่นับบิลที่อยู่ในประกัน (is_warranty_covered) เป็นรายได้จริง แม้จะ
  // ถูกมาร์ก is_paid ให้อัตโนมัติตอนออกบิลก็ตาม เพราะลูกค้าไม่ได้จ่ายเงินจริง —
  // ให้ตรงกับ getAdminDashboardSummary() ฝั่งแอปที่กันไว้เหมือนกัน
  const isWarrantyRow = (r) => r.is_warranty_covered === true || r.is_warranty_covered === 1;
  const paid = invoiced.filter((r) => !isWarrantyRow(r) && (r.is_paid === 1 || r.is_paid === true));
  const unpaid = invoiced.filter((r) => !isWarrantyRow(r) && !(r.is_paid === 1 || r.is_paid === true));

  const totalRevenue = paid.reduce((sum, r) => sum + (Number(r.total_price) || 0), 0);
  const totalUnpaid = unpaid.reduce((sum, r) => sum + (Number(r.total_price) || 0), 0);

  async function markAsPaid(repair) {
    try {
      // 🔔 [ใหม่] เคลียร์ธง payment_overdue_notified ไปด้วยตอนมาร์กว่าชำระแล้ว
      // เผื่ออนาคตมีเหตุต้องกลับไปเป็นค้างชำระอีกครั้ง จะได้แจ้งเตือนซ้ำได้
      await updateRow("repairs", repair.id, { is_paid: 1, payment_overdue_notified: 0 });
      // 📝 [ใหม่] บันทึก activity log — เงินเข้าออกควรมีร่องรอยเสมอ
      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "มาร์กว่าชำระแล้ว",
        target: `${repair.ticketNo || `#${repair.id}`} · ${(Number(repair.total_price) || 0).toLocaleString("th-TH")} บาท`,
      }).catch((err) => console.error("[FinancePage] log activity failed:", err));
    } catch (err) {
      console.error("[FinancePage] mark as paid failed:", err);
    }
  }

  const sorted = [...invoiced].sort((a, b) => (b.created_at || "").localeCompare(a.created_at || ""));

  // 🆕 จำนวนรายการต่อหน้า อ่านมาจากหน้าตั้งค่า > ระบบทั่วไป (ของหน้า "การเงิน")
  // — เป็นค่าส่วนตัวของแอดมินคนนี้ (webSettings) ไม่ใช่ companySettings แล้ว
  const pageSize = Number(webSettings.itemsPerPageFinance) || 20;
  const [page, setPage] = useState(1);
  useEffect(() => {
    setPage(1);
  }, [sorted.length]);
  const totalPages = Math.max(1, Math.ceil(sorted.length / pageSize));
  const currentPage = Math.min(page, totalPages);
  const paged = sorted.slice((currentPage - 1) * pageSize, currentPage * pageSize);

  return (
    <div>
      {/* 🔴 [แก้ไข] เอาหัวข้อ "การเงิน" ออก เพราะซ้ำกับ Header บนสุด เหลือแค่
          ปุ่ม "ออกใบแจ้งหนี้ใหม่" ชิดขวา */}
      <div className="flex justify-end mb-5">
        <PrimaryButton icon={Plus} onClick={() => setCreatingInvoice(true)}>
          ออกใบแจ้งหนี้ใหม่
        </PrimaryButton>
      </div>

      <div className="flex flex-wrap gap-4 mb-5">
        <div className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[200px]">
          <div className="flex items-center gap-2 mb-3">
            <div className={`w-9 h-9 rounded-xl ${COLORS.green.bg} ${COLORS.green.text} flex items-center justify-center`}>
              <CheckCircle2 size={18} />
            </div>
            <span className="text-sm text-slate-500">รายได้ที่ชำระแล้ว</span>
          </div>
          <span className="text-2xl font-semibold text-slate-900">{totalRevenue.toLocaleString("th-TH")} บาท</span>
        </div>

        <div className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[200px]">
          <div className="flex items-center gap-2 mb-3">
            <div className={`w-9 h-9 rounded-xl ${COLORS.orange.bg} ${COLORS.orange.text} flex items-center justify-center`}>
              <Clock size={18} />
            </div>
            <span className="text-sm text-slate-500">ยอดค้างชำระ</span>
          </div>
          <span className="text-2xl font-semibold text-slate-900">{totalUnpaid.toLocaleString("th-TH")} บาท</span>
        </div>

        <div className="bg-white rounded-2xl border border-slate-100 p-4 flex-1 min-w-[200px]">
          <div className="flex items-center gap-2 mb-3">
            <div className={`w-9 h-9 rounded-xl ${COLORS.blue.bg} ${COLORS.blue.text} flex items-center justify-center`}>
              <Wallet size={18} />
            </div>
            <span className="text-sm text-slate-500">ใบแจ้งหนี้ทั้งหมด</span>
          </div>
          <span className="text-2xl font-semibold text-slate-900">{invoiced.length} ใบ</span>
        </div>
      </div>

      <Card className="p-0 overflow-hidden">
        <div className="p-5">
          {loading ? (
            <p className="text-xs text-slate-400 text-center py-8">กำลังโหลดข้อมูล...</p>
          ) : sorted.length === 0 ? (
            <EmptyState icon={Wallet} message="ยังไม่มีใบแจ้งหนี้ในระบบ" />
          ) : (
            <div className="overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs text-slate-400 border-b border-slate-100">
                  <th className="py-2 font-medium">เลขที่ใบแจ้งหนี้</th>
                  <th className="py-2 font-medium">Job ID</th>
                  <th className="py-2 font-medium">ลูกค้า</th>
                  <th className="py-2 font-medium">ยอดรวม</th>
                  <th className="py-2 font-medium">สถานะ</th>
                  <th className="py-2 font-medium"></th>
                </tr>
              </thead>
              <tbody>
                {paged.map((r) => {
                  const isPaid = r.is_paid === 1 || r.is_paid === true;
                  // 🔴 [แก้บั๊ก] เดิมมีแค่ isPaid ตัวเดียว ใช้ getPaymentState แทน
                  // เพื่อแยกสถานะ "รอตรวจสอบสลิป" (มีสลิปแล้วแต่ยังไม่กดยืนยัน)
                  // ออกจาก "ยังไม่ชำระ" (ยังไม่มีอะไรเลย)
                  const state = getPaymentState(r);
                  const badgeText =
                    state === "warranty"
                      ? "ไม่มีค่าใช้จ่าย (ประกัน)"
                      : state === "paid"
                      ? "ชำระแล้ว"
                      : state === "awaiting"
                      ? "รอตรวจสอบสลิป"
                      : "ยังไม่ชำระ";
                  const badgeClass =
                    state === "warranty"
                      ? "bg-emerald-50 text-emerald-600"
                      : state === "paid"
                      ? "bg-emerald-50 text-emerald-600"
                      : state === "awaiting"
                      ? "bg-blue-50 text-blue-600"
                      : "bg-orange-50 text-orange-600";
                  return (
                    <tr key={r.id} className="border-b border-slate-50 last:border-0">
                      <td className="py-2.5 text-slate-500">{r.invoice_no || "-"}</td>
                      <td className="py-2.5 text-slate-700">{r.ticketNo || r.id}</td>
                      <td className="py-2.5 text-slate-700">{r.customer_username || "-"}</td>
                      <td className="py-2.5 text-slate-700">{Number(r.total_price || 0).toLocaleString("th-TH")} บาท</td>
                      <td className="py-2.5">
                        {/* 🎨 ชำระแล้ว/ประกัน = badge เขียว / รอตรวจสอบสลิป = badge ฟ้า /
                            ยังไม่ชำระ = badge ส้ม */}
                        <span className={`inline-flex items-center gap-1 text-[11px] font-medium px-2 py-0.5 rounded-full ${badgeClass}`}>
                          {state === "warranty" ? <ShieldCheck size={11} /> : null}
                          {badgeText}
                        </span>
                      </td>
                      <td className="py-2.5 text-right">
                        <div className="flex items-center justify-end gap-2">
                          {/* 🧾 [ใหม่] ปุ่มดู/พิมพ์ใบแจ้งหนี้จริง — โชว์เฉพาะงานที่
                              มีเลขที่ใบแจ้งหนี้แล้ว (ออกผ่านฟอร์มใหม่ที่สร้าง
                              invoice_no ให้) งานเก่าที่ออกบิลไว้ก่อนหน้านี้จะยัง
                              ไม่มีเลขที่ใบแจ้งหนี้ย้อนหลัง */}
                          {r.invoice_no ? (
                            <button
                              onClick={() => setViewingInvoice(r)}
                              className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-slate-50 text-slate-600 text-xs font-medium hover:bg-slate-100"
                            >
                              <FileText size={13} /> ดูใบแจ้งหนี้
                            </button>
                          ) : null}
                          {/* 🔴 [ใหม่] ปุ่มดูสลิปโอนเงิน — โชว์เฉพาะงานที่ลูกค้า
                              อัปโหลดสลิปมาจากแอปมือถือแล้ว (repairs.customer_
                              payment_slip) ให้แอดมินเช็กหลักฐานก่อนกดยืนยัน
                              แทนที่จะต้องเปิดแอปมือถือดูแยกต่างหาก */}
                          {r.customer_payment_slip ? (
                            <button
                              onClick={() => setViewingSlip(r)}
                              className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-blue-50 text-blue-600 text-xs font-medium hover:bg-blue-100"
                            >
                              <Receipt size={13} /> ดูสลิป
                            </button>
                          ) : null}
                          {/* 🆕 [ใหม่] ซ่อนปุ่มนี้ด้วยถ้าอยู่ในประกัน (state ===
                              "warranty") เพราะ is_paid ถูกมาร์กให้แล้วอัตโนมัติ
                              ไม่มีอะไรให้กดยืนยันซ้ำ */}
                          {!isPaid && state !== "warranty" ? (
                            <button
                              onClick={() => markAsPaid(r)}
                              className="flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-50 text-emerald-600 text-xs font-medium hover:bg-emerald-100"
                            >
                              <Check size={13} /> มาร์กว่าชำระแล้ว
                            </button>
                          ) : null}
                        </div>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
            </div>
          )}
          <Pagination
            page={currentPage}
            totalPages={totalPages}
            onChange={setPage}
            totalItems={sorted.length}
            pageSize={pageSize}
          />
        </div>
      </Card>

      {creatingInvoice ? (
        <CreateInvoiceModal
          repairs={repairs}
          partRequests={partRequests}
          spareParts={spareParts}
          machines={machines}
          onClose={() => setCreatingInvoice(false)}
        />
      ) : null}

      {viewingInvoice ? (
        <InvoiceModal
          repair={viewingInvoice}
          customer={customers.find((c) => c.username === viewingInvoice.customer_username)}
          companySettings={companySettings}
          onClose={() => setViewingInvoice(null)}
        />
      ) : null}

      {/* 🔴 [ใหม่] modal ดูสลิปโอนเงินเต็มรูป — ให้แอดมินเช็กหลักฐานแล้วกด
          "มาร์กว่าชำระแล้ว" ต่อได้เลยในหน้าเดียวกัน ไม่ต้องปิดแล้วไปหาปุ่มที่ตาราง */}
      {viewingSlip ? (
        <Modal
          title={`สลิปโอนเงิน — ${viewingSlip.ticketNo || `#${viewingSlip.id}`}`}
          onClose={() => setViewingSlip(null)}
          footer={
            <>
              <button
                onClick={() => setViewingSlip(null)}
                className="px-4 py-2 rounded-xl text-sm text-slate-500 hover:bg-slate-50"
              >
                ปิด
              </button>
              {!(viewingSlip.is_paid === 1 || viewingSlip.is_paid === true) ? (
                <PrimaryButton
                  icon={Check}
                  onClick={() => {
                    markAsPaid(viewingSlip);
                    setViewingSlip(null);
                  }}
                >
                  มาร์กว่าชำระแล้ว
                </PrimaryButton>
              ) : null}
            </>
          }
        >
          <div className="flex flex-col items-center">
            <img
              src={viewingSlip.customer_payment_slip}
              alt="สลิปโอนเงิน"
              className="max-h-[70vh] w-auto rounded-xl border border-slate-100"
            />
            <p className="text-xs text-slate-400 mt-3">
              ยอดที่ต้องชำระ: {Number(viewingSlip.total_price || 0).toLocaleString("th-TH")} บาท
            </p>
          </div>
        </Modal>
      ) : null}
    </div>
  );
}