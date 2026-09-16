import React, { useState, useMemo, useEffect } from "react";
import { Wallet, CheckCircle2, Clock, Check, Plus, FileText, Printer, Receipt } from "lucide-react";
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
  const isPaid = r.is_paid === 1 || r.is_paid === true;
  if (isPaid) return "paid";
  if (r.customer_payment_slip) return "awaiting";
  return "unpaid";
}

function CreateInvoiceModal({ repairs, partRequests, spareParts, onClose }) {
  const invoiceableJobs = repairs.filter(isInvoiceable);
  const [repairId, setRepairId] = useState("");
  const [laborCost, setLaborCost] = useState("");
  const [saving, setSaving] = useState(false);

  const selectedJob = invoiceableJobs.find((r) => String(r.id) === String(repairId));

  // อะไหล่ที่อนุมัติแล้วของงานนี้ — จับคู่ราคาจาก spare_parts ด้วย part_id
  // เดียวกับที่หน้าอะไหล่ใช้ตอนอนุมัติคำขอ
  const approvedParts = useMemo(() => {
    if (!selectedJob) return [];
    return partRequests
      .filter((pr) => String(pr.repair_id) === String(selectedJob.record_id) && pr.status === "อนุมัติแล้ว")
      .map((pr) => {
        const part = spareParts.find((p) => p.record_id === pr.part_id);
        const qty = Number(pr.quantity) || 0;
        const price = Number(part?.price) || 0;
        return { id: pr.id, name: pr.part_name || part?.part_name || "-", qty, price, subtotal: qty * price };
      });
  }, [selectedJob, partRequests, spareParts]);

  const partsSubtotal = approvedParts.reduce((sum, p) => sum + p.subtotal, 0);
  const total = partsSubtotal + (Number(laborCost) || 0);

  async function handleSave() {
    if (!selectedJob) return;
    setSaving(true);
    try {
      // 🧾 [ใหม่] สร้างเลขที่ใบแจ้งหนี้จริง + เก็บ snapshot รายการอะไหล่ ณ ตอนออก
      // บิล (invoice_items) แยกจาก part_requests สด ๆ เพราะถ้าอะไหล่/คำขอถูก
      // แก้ไข/ลบทีหลัง ใบแจ้งหนี้ที่ออกไปแล้วต้องยังพิมพ์ซ้ำได้ตรงกับตอนออกจริง
      const invoiceNo = await nextInvoiceNumber();
      await updateRow("repairs", selectedJob.id, {
        total_price: total,
        labor_cost: Number(laborCost) || 0,
        is_paid: 0,
        invoiced_at: new Date().toISOString(),
        invoice_no: invoiceNo,
        invoice_items: approvedParts.map((p) => ({ name: p.name, qty: p.qty, price: p.price, subtotal: p.subtotal })),
      });
      // 📝 [ใหม่] บันทึก activity log — ใครออกใบแจ้งหนี้ให้งานไหนเมื่อไหร่
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
          <PrimaryButton onClick={handleSave} disabled={!selectedJob || saving}>
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
          <div className="rounded-xl border border-slate-100 p-4">
            <p className="text-xs font-semibold text-slate-500 mb-2">อะไหล่ที่อนุมัติแล้วสำหรับงานนี้</p>
            {approvedParts.length === 0 ? (
              <p className="text-xs text-slate-400">ไม่มีการเบิกอะไหล่สำหรับงานนี้</p>
            ) : (
              <div className="space-y-1.5">
                {approvedParts.map((p) => (
                  <div key={p.id} className="flex items-center justify-between text-sm">
                    <span className="text-slate-600">{p.name} × {p.qty}</span>
                    <span className="text-slate-700 font-medium">{p.subtotal.toLocaleString("th-TH")} บาท</span>
                  </div>
                ))}
                <div className="flex items-center justify-between text-sm pt-1.5 border-t border-slate-100 mt-1.5">
                  <span className="text-slate-500">รวมค่าอะไหล่</span>
                  <span className="text-slate-700 font-semibold">{partsSubtotal.toLocaleString("th-TH")} บาท</span>
                </div>
              </div>
            )}
          </div>

          <div>
            <label className="text-sm text-slate-600 mb-2 block font-medium">ค่าแรง (บาท)</label>
            <input
              type="number"
              value={laborCost}
              onChange={(e) => setLaborCost(e.target.value)}
              placeholder="0"
              className="w-full px-4 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-[15px] text-slate-700 placeholder:text-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <div className="flex items-center justify-between rounded-xl bg-blue-50 px-4 py-3">
            <span className="text-sm font-medium text-blue-700">ยอดรวมทั้งหมด</span>
            <span className="text-lg font-semibold text-blue-700">{total.toLocaleString("th-TH")} บาท</span>
          </div>
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
  const isPaid = repair.is_paid === 1 || repair.is_paid === true;
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
          body * { visibility: hidden; }
          #print-invoice-area, #print-invoice-area * { visibility: visible; }
          #print-invoice-area { position: absolute; left: 0; top: 0; width: 100%; padding: 24px; }
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
          <div className="w-56">
            <div className="flex items-center justify-between py-2 border-t border-slate-200">
              <span className="text-sm font-semibold text-slate-700">ยอดรวมทั้งหมด</span>
              <span className="text-base font-bold" style={{ color: "#B22121" }}>฿{total.toLocaleString("th-TH", { maximumFractionDigits: 0 })}</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-slate-500">สถานะการชำระ</span>
              <span className={`text-xs font-semibold ${isPaid ? "text-emerald-600" : "text-orange-500"}`}>
                {isPaid ? "ชำระแล้ว" : "ยังไม่ชำระ"}
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

  const paid = invoiced.filter((r) => r.is_paid === 1 || r.is_paid === true);
  const unpaid = invoiced.filter((r) => !(r.is_paid === 1 || r.is_paid === true));

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
                    state === "paid" ? "ชำระแล้ว" : state === "awaiting" ? "รอตรวจสอบสลิป" : "ยังไม่ชำระ";
                  const badgeClass =
                    state === "paid"
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
                        {/* 🎨 ชำระแล้ว = badge เขียว / รอตรวจสอบสลิป = badge ฟ้า /
                            ยังไม่ชำระ = badge ส้ม */}
                        <span className={`text-[11px] font-medium px-2 py-0.5 rounded-full ${badgeClass}`}>
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
                          {!isPaid ? (
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