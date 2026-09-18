import React, { useEffect, useRef, useState, useMemo } from "react";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import {
  X,
  MapPin,
  User,
  Wrench,
  FileText,
  Navigation,
  MessageSquare,
  ShieldAlert,
  Loader2,
  CalendarClock,
  Check,
} from "lucide-react";
import {
  GEOAPIFY_API_KEY,
  STATUS_BADGE,
  SEVERITY_BADGE,
  displayStatus,
  extractSeverity,
  displayStoredDate,
  extractRating,
  parseThaiDate,
  compareAppointmentDate,
  isDoneStatus,
} from "../shared/constants";
import { StarRating, DateField, TimeField } from "./ui";
import useDbList from "../hooks/useDbList";
import {
  assignTechnicianToRepair,
  updateRow,
  logActivity,
  createNotification,
} from "../services/firebaseDb";
import { getSessionAdmin } from "../services/session";

export function findMachineForJob(job, machines = []) {
  if (!job || !Array.isArray(machines) || machines.length === 0) return null;

  const directSn =
    job.serial_number ||
    job.serialNumber ||
    job.serial_no ||
    job.machine_serial ||
    job.machine_serial_number;
  if (directSn && String(directSn).trim() !== "" && directSn !== "-") {
    const found = machines.find(
      (m) => (m.serial_number || "").trim().toUpperCase() === String(directSn).trim().toUpperCase()
    );
    if (found) return found;
    return { serial_number: String(directSn).trim().toUpperCase() };
  }

  const targetId = job.machine_id ?? job.machineId;
  if (targetId != null && String(targetId).trim() !== "") {
    const targetStr = String(targetId).trim();
    const targetClean = targetStr.replace(/^[kK]/, "");

    const found = machines.find((m) => {
      const mId = m.id != null ? String(m.id).trim() : "";
      const mRecordId = m.record_id != null ? String(m.record_id).trim() : "";
      const mIdClean = mId.replace(/^[kK]/, "");
      const mRecordIdClean = mRecordId.replace(/^[kK]/, "");

      return (
        mId === targetStr ||
        mRecordId === targetStr ||
        (targetClean && (mIdClean === targetClean || mRecordIdClean === targetClean))
      );
    });
    if (found) return found;
  }

  if (job.customer_username) {
    const custUsername = String(job.customer_username).trim().toLowerCase();
    const custMachines = machines.filter(
      (m) => (m.customer_username || "").trim().toLowerCase() === custUsername
    );

    if (custMachines.length > 0) {
      if (job.machine) {
        const jobMachine = String(job.machine).trim().toLowerCase();
        const matched = custMachines.find((m) => {
          const model = (m.model_name || "").trim().toLowerCase();
          const label = (m.label || "").trim().toLowerCase();
          return (
            (model && (model === jobMachine || jobMachine.includes(model) || model.includes(jobMachine))) ||
            (label && (label === jobMachine || jobMachine.includes(label) || label.includes(jobMachine)))
          );
        });
        if (matched) return matched;
      }
      if (custMachines.length === 1) {
        return custMachines[0];
      }
    }
  }

  if (job.detail) {
    const match = String(job.detail).match(/[A-Za-z]{2}\d{2}\d{4}/);
    if (match) {
      const sn = match[0].toUpperCase();
      const found = machines.find(
        (m) => (m.serial_number || "").trim().toUpperCase() === sn
      );
      if (found) return found;
      return { serial_number: sn };
    }
  }

  return null;
}

const createCustomerPinIcon = () =>
  L.divIcon({
    className: "custom-map-pin",
    html: `
      <div style="
        position: relative;
        width: 38px;
        height: 48px;
        display: flex;
        align-items: center;
        justify-content: center;
        filter: drop-shadow(0 4px 6px rgba(0,0,0,0.35));
        cursor: pointer;
      ">
        <svg width="38" height="48" viewBox="0 0 38 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          <path d="M19 0C8.50659 0 0 8.50659 0 19C0 32.5 19 48 19 48C19 48 38 32.5 38 19C38 8.50659 29.4934 0 19 0Z" fill="#D8232A"/>
          <circle cx="19" cy="18" r="8" fill="#FFFFFF"/>
        </svg>
      </div>
    `,
    iconSize: [38, 48],
    iconAnchor: [19, 48],
    popupAnchor: [0, -48],
  });

const createTechnicianPinIcon = () =>
  L.divIcon({
    className: "custom-tech-pin",
    html: `
      <div style="
        position: relative;
        width: 40px;
        height: 40px;
        background: #2563EB;
        border: 3px solid #FFFFFF;
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        box-shadow: 0 4px 10px rgba(37, 99, 235, 0.45);
        color: white;
      ">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
          <path d="M19 17h2c.6 0 1-.4 1-1v-3c0-.9-.7-1.7-1.5-1.9C18.7 10.6 16 10 16 10s-1.3-1.4-2.2-2.3c-.5-.4-1.1-.7-1.8-.7H5c-.6 0-1.1.4-1.4.9l-1.4 2.9A3.7 3.7 0 0 0 2 12v4c0 .6.4 1 1 1h2"/>
          <circle cx="7" cy="17" r="2"/>
          <path d="M9 17h6"/>
          <circle cx="17" cy="17" r="2"/>
        </svg>
      </div>
    `,
    iconSize: [40, 40],
    iconAnchor: [20, 20],
    popupAnchor: [0, -20],
  });

function JobLocationMap({ techLocation, customerLocation, customerAddress }) {
  const mapContainerRef = useRef(null);
  const mapInstanceRef = useRef(null);
  const [routeInfo, setRouteInfo] = useState(null);
  const [resolvedCustLoc, setResolvedCustLoc] = useState(customerLocation);

  useEffect(() => {
    if (customerLocation?.lat && customerLocation?.lng) {
      setResolvedCustLoc(customerLocation);
      return;
    }
    if (customerAddress && customerAddress !== "-") {
      const geoUrl = `https://api.geoapify.com/v1/geocode/search?text=${encodeURIComponent(
        customerAddress
      )}&filter=countrycode:th&lang=th&limit=1&apiKey=${GEOAPIFY_API_KEY}`;

      fetch(geoUrl)
        .then((res) => res.json())
        .then((data) => {
          const coords = data?.features?.[0]?.geometry?.coordinates;
          if (coords) {
            setResolvedCustLoc({ lat: coords[1], lng: coords[0] });
          }
        })
        .catch((err) => console.error("Geocoding error:", err));
    }
  }, [customerLocation, customerAddress]);

  useEffect(() => {
    if (!mapContainerRef.current) return;

    const defaultLat = resolvedCustLoc?.lat || 13.7563;
    const defaultLng = resolvedCustLoc?.lng || 100.5018;

    if (!mapInstanceRef.current) {
      const map = L.map(mapContainerRef.current, {
        zoomControl: true,
      }).setView([defaultLat, defaultLng], 13);

      L.tileLayer(
        `https://maps.geoapify.com/v1/tile/osm-carto/{z}/{x}/{y}.png?apiKey=${GEOAPIFY_API_KEY}`,
        {
          attribution: 'Powered by <a href="https://www.geoapify.com/" target="_blank">Geoapify</a>',
          maxZoom: 20,
        }
      ).addTo(map);

      mapInstanceRef.current = map;
    }

    const map = mapInstanceRef.current;

    map.eachLayer((layer) => {
      if (layer instanceof L.Marker || layer instanceof L.Polyline) {
        map.removeLayer(layer);
      }
    });

    const bounds = [];

    if (resolvedCustLoc?.lat && resolvedCustLoc?.lng) {
      const custLatLng = [resolvedCustLoc.lat, resolvedCustLoc.lng];
      L.marker(custLatLng, { icon: createCustomerPinIcon() })
        .addTo(map)
        .bindPopup("<b>สถานที่ซ่อม (ลูกค้า)</b>");
      bounds.push(custLatLng);
    }

    if (techLocation?.lat && techLocation?.lng) {
      const techLatLng = [techLocation.lat, techLocation.lng];
      L.marker(techLatLng, { icon: createTechnicianPinIcon() })
        .addTo(map)
        .bindPopup("<b>ตำแหน่งช่างเทคนิค</b>");
      bounds.push(techLatLng);
    }

    if (
      techLocation?.lat &&
      techLocation?.lng &&
      resolvedCustLoc?.lat &&
      resolvedCustLoc?.lng
    ) {
      const routingUrl = `https://api.geoapify.com/v1/routing?waypoints=${techLocation.lat},${techLocation.lng}|${resolvedCustLoc.lat},${resolvedCustLoc.lng}&mode=drive&apiKey=${GEOAPIFY_API_KEY}`;

      fetch(routingUrl)
        .then((res) => res.json())
        .then((data) => {
          const feature = data?.features?.[0];
          if (!feature) return;

          const routeCoords = [];
          const geom = feature.geometry;

          if (geom.type === "MultiLineString") {
            geom.coordinates.forEach((line) => {
              line.forEach(([lng, lat]) => routeCoords.push([lat, lng]));
            });
          } else if (geom.type === "LineString") {
            geom.coordinates.forEach(([lng, lat]) => routeCoords.push([lat, lng]));
          }

          if (routeCoords.length > 0) {
            L.polyline(routeCoords, {
              color: "#B22121",
              weight: 8,
              opacity: 0.35,
              lineCap: "round",
              lineJoin: "round",
            }).addTo(map);

            const mainLine = L.polyline(routeCoords, {
              color: "#D8232A",
              weight: 6,
              opacity: 0.95,
              lineCap: "round",
              lineJoin: "round",
            }).addTo(map);

            map.fitBounds(mainLine.getBounds(), { padding: [45, 45] });

            setRouteInfo({
              distanceKm: (feature.properties.distance / 1000).toFixed(1),
              timeMin: Math.round(feature.properties.time / 60),
            });
          }
        })
        .catch((err) => console.error("Routing error:", err));
    } else if (bounds.length > 0) {
      map.fitBounds(bounds, { padding: [50, 50], maxZoom: 15 });
    }

    setTimeout(() => map.invalidateSize(), 250);
  }, [techLocation?.lat, techLocation?.lng, resolvedCustLoc?.lat, resolvedCustLoc?.lng]);

  return (
    <div className="relative w-full h-[320px] rounded-2xl overflow-hidden border border-slate-200">
      <div ref={mapContainerRef} className="w-full h-full" />

      {routeInfo && (
        <div
          className="absolute top-3 right-3 backdrop-blur-sm px-3.5 py-2 rounded-xl shadow-md z-[1000] text-xs space-y-0.5"
          style={{ background: "rgba(255,255,255,0.95)", border: "1px solid #f1f5f9" }}
        >
          <p style={{ color: "#64748b", margin: 0 }}>
            ระยะทาง: <span style={{ fontWeight: 600, color: "#1e293b" }}>{routeInfo.distanceKm} กม.</span>
          </p>
          <p style={{ color: "#64748b", margin: 0 }}>
            เวลาเดินทางโดยประมาณ: <span style={{ fontWeight: 600, color: "#dc2626" }}>{routeInfo.timeMin} นาที</span>
          </p>
        </div>
      )}
    </div>
  );
}

function toDateInputValue(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, "0");
  const day = String(d.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function isoToThaiDate(iso) {
  const parts = String(iso).split("-").map(Number);
  const [y, m, d] = parts;
  if (!y || !m || !d) return "";
  return `${d}/${m}/${y + 543}`;
}

function formatBangkokAddress(address) {
  if (!address || typeof address !== "string" || address === "-") return address;
  if (!address.includes("กรุงเทพ")) return address;
  return address
    .replace(/ตำบล/g, "แขวง")
    .replace(/อำเภอ/g, "เขต")
    .replace(/จังหวัดกรุงเทพ/g, "กรุงเทพ");
}

function getProblemPhotos(job) {
  if (typeof job.images === "string" && job.images.trim()) {
    const urls = job.images.split(",").map((u) => u.trim()).filter(Boolean);
    if (urls.length) return urls.slice(0, 6);
  }
  const arrayCandidates = [job.photos, job.problem_photos, job.images, job.photo_urls];
  for (const arr of arrayCandidates) {
    if (Array.isArray(arr) && arr.length) return arr.filter(Boolean).slice(0, 6);
  }
  const singles = [];
  for (let i = 1; i <= 6; i++) {
    const url = job[`photo_url_${i}`] || job[`photo_${i}`] || job[`image_${i}`];
    if (url) singles.push(url);
  }
  return singles;
}

function getRepairReport(job) {
  const text = typeof job.report_problem_detail === "string" ? job.report_problem_detail.trim() : "";
  return {
    text,
    beforePhoto: job.report_before_photo || "",
    afterPhoto: job.report_after_photo || "",
    slipPhoto: job.report_slip_photo || "",
    formCode: job.report_form_code || "",
    reportedAt: job.report_submitted_at || "",
  };
}

function getIssueReport(job) {
  const detail = job.problem_note || "";
  let photos = [];
  if (typeof job.problem_photos === "string" && job.problem_photos.trim()) {
    photos = job.problem_photos.split(",").map((u) => u.trim()).filter(Boolean);
  }
  return { detail, photos: photos.slice(0, 4) };
}

function TechnicianAssignBox({ job, technicians, currentTech }) {
  const [techUsername, setTechUsername] = useState("");
  const [dateIso, setDateIso] = useState("");
  const [time, setTime] = useState("");
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");

  const [isEditingSchedule, setIsEditingSchedule] = useState(false);
  const [editDateIso, setEditDateIso] = useState("");
  const [editTime, setEditTime] = useState("");
  const [savingSchedule, setSavingSchedule] = useState(false);
  const [editError, setEditError] = useState("");

  const todayIso = toDateInputValue(new Date());

  async function handleAssign() {
    if (!techUsername || !dateIso || !time) return;
    setSaving(true);
    setError("");
    try {
      const admin = getSessionAdmin();
      const thaiDate = isoToThaiDate(dateIso);
      const adminUsername = admin?.username || "admin";
      const adminName = admin?.admin_name || adminUsername;

      await assignTechnicianToRepair(job.id, techUsername, adminUsername, thaiDate, {
        time,
        appointment_time: time,
        admin_name: adminName,
      });

      logActivity({
        adminUsername,
        adminName,
        action: "มอบหมายช่าง",
        target: `งาน #${job.ticketNo || job.id} ให้ช่าง ${techUsername} วันที่ ${thaiDate} เวลา ${time} น.`,
      }).catch(console.error);

      const ticketLabel = job.ticketNo || `#${job.id}`;
      createNotification({
        user_username: techUsername,
        role: "TECHNICIAN",
        title: `งานซ่อมใหม่: ${ticketLabel}`,
        message: `เครื่อง ${job.machine || ""} (${thaiDate}) เวลา ${time} น.`,
        type: "JOB",
        target_id: job.id,
      }).catch(console.error);

      if (job.customer_username) {
        createNotification({
          user_username: job.customer_username,
          role: "CUSTOMER",
          title: `จัดสรรช่างแล้ว: ${ticketLabel}`,
          message: `แอดมิน ${adminName} ได้มอบหมายช่าง ${techUsername} ดูแลงานซ่อมของคุณแล้ว วันที่ ${thaiDate} เวลา ${time} น.`,
          type: "JOB",
          target_id: job.id,
        }).catch(console.error);
      }
    } catch (err) {
      console.error("[JobDetailModal] assign failed:", err);
      setError("มอบหมายไม่สำเร็จ ลองอีกครั้ง");
    } finally {
      setSaving(false);
    }
  }

  async function handleSaveSchedule() {
    if (!editDateIso || !editTime) {
      setEditError("กรุณาระบุวันและเวลานัดหมายให้ครบถ้วน");
      return;
    }
    setSavingSchedule(true);
    setEditError("");
    try {
      const thaiDate = isoToThaiDate(editDateIso);
      const cleanTime = editTime.trim();
      const comp = compareAppointmentDate(thaiDate);
      let newStatus = job.status;
      // 🐛 [แก้บัค] เดิมเช็คแค่ "ยังไม่เสร็จ/ยกเลิก/มีปัญหา" แล้วเขียนทับสถานะ
      // เป็น "รอดำเนินการ"/"เกินกำหนดเวลา" ตามวันที่ใหม่เสมอ — ถ้างานนั้นกำลัง
      // ทำอยู่จริง (กำลังเดินทาง/กำลังซ่อม) แล้วแอดมินมาเลื่อนนัดหมาย จะโดนเขียน
      // ทับสถานะจริงทิ้งไปเฉยๆ ทั้งที่ช่างลงมือทำไปแล้ว — กันไว้เหมือนกับที่แก้
      // getEffectiveRepairStatus() ใน constants.js
      const alreadyInProgress =
        job.status === "กำลังเดินทาง" ||
        job.status === "กำลังดำเนินการ" ||
        job.status === "กำลังซ่อม";
      if (
        !alreadyInProgress &&
        !isDoneStatus(job.status) &&
        !job.status?.includes("ยกเลิก") &&
        job.status !== "มีปัญหา"
      ) {
        if (comp === "future" || comp === "today") {
          newStatus = "รอดำเนินการ";
        } else if (comp === "past") {
          newStatus = "เกินกำหนดเวลา";
        }
      }

      await updateRow("repairs", job.id, {
        date: thaiDate,
        time: cleanTime,
        appointment_time: cleanTime,
        status: newStatus,
        rescheduled_at: new Date().toISOString(),
      });

      const admin = getSessionAdmin();
      logActivity({
        adminUsername: admin?.username,
        adminName: admin?.admin_name,
        action: "แก้ไขวันเวลานัดซ่อม",
        target: `งาน #${job.ticketNo || job.id} เลื่อนเป็น ${thaiDate} เวลา ${cleanTime} น.`,
      }).catch(console.error);

      const ticketLabel = job.ticketNo || `#${job.id}`;
      if (job.technician_username) {
        createNotification({
          user_username: job.technician_username,
          role: "TECHNICIAN",
          title: `แก้ไขวันเวลานัดซ่อม: ${ticketLabel}`,
          message: `งานซ่อม ${job.machine || ""} เปลี่ยนวันนัดหมายใหม่เป็นวันที่ ${thaiDate} เวลา ${cleanTime} น.`,
          type: "JOB",
          target_id: job.id,
        }).catch(console.error);
      }
      if (job.customer_username) {
        createNotification({
          user_username: job.customer_username,
          role: "CUSTOMER",
          title: `อัปเดตวันเวลานัดซ่อม: ${ticketLabel}`,
          message: `งานซ่อมของคุณได้รับการเปลี่ยนวันนัดหมายใหม่เป็นวันที่ ${thaiDate} เวลา ${cleanTime} น.`,
          type: "JOB",
          target_id: job.id,
        }).catch(console.error);
      }

      setIsEditingSchedule(false);
    } catch (err) {
      console.error("[JobDetailModal] update schedule failed:", err);
      setEditError("บันทึกวันเวลานัดใหม่ไม่สำเร็จ กรุณาลองใหม่อีกครั้ง");
    } finally {
      setSavingSchedule(false);
    }
  }

  const assignedTime = (job.appointment_time || job.time || "")
    .toString()
    .trim()
    .replace(/\s*น\.?$/, "");

  return (
    <div className="border border-slate-100 rounded-2xl p-4 space-y-3">
      <div className="flex items-center gap-2 text-slate-800 font-semibold text-sm">
        <Wrench size={16} className="text-orange-500" />
        <span>ช่างผู้รับผิดชอบ</span>
      </div>

      {job.technician_username ? (
        <div className="space-y-3">
          <div className="text-xs text-slate-600 space-y-1">
            <p><span className="text-slate-400">ช่าง:</span> {job.technician_username}</p>
            <p><span className="text-slate-400">แอดมินผู้ดูแล:</span> {job.admin_username ? `@${job.admin_username}` : (job.assigned_by ? `@${job.assigned_by}` : "-")}</p>
            <p><span className="text-slate-400">เบอร์โทร:</span> {currentTech?.phone || "-"}</p>
            <p><span className="text-slate-400">สถานะช่าง:</span> {currentTech?.status || "ว่าง"}</p>
            {(job.date || assignedTime) ? (
              <p>
                <span className="text-slate-400">วันนัดหมาย:</span> {displayStoredDate(job.date)}
                {assignedTime ? ` เวลา ${assignedTime} น.` : ""}
              </p>
            ) : null}
            <p><span className="text-slate-400">ยานพาหนะ:</span> {currentTech?.vehicle || "-"}</p>
          </div>

          {!isDoneStatus(job.status) && !job.status?.includes("ยกเลิก") && (
            <div className="pt-2 border-t border-slate-100">
              {!isEditingSchedule ? (
                <button
                  type="button"
                  onClick={() => {
                    const parsedD = parseThaiDate(job.date);
                    setEditDateIso(parsedD ? toDateInputValue(parsedD) : todayIso);
                    setEditTime(assignedTime || "09:00");
                    setIsEditingSchedule(true);
                    setEditError("");
                  }}
                  className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-medium text-blue-600 hover:text-blue-700 bg-blue-50 hover:bg-blue-100 transition-colors"
                >
                  <CalendarClock size={14} />
                  แก้ไขวันเวลานัดซ่อม
                </button>
              ) : (
                <div className="space-y-3 bg-slate-50 p-3 rounded-xl border border-slate-200 animate-in fade-in duration-150">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-semibold text-slate-700 flex items-center gap-1.5">
                      <CalendarClock size={14} className="text-blue-600" />
                      ระบุวันเวลานัดหมายใหม่
                    </p>
                    <button
                      type="button"
                      onClick={() => setIsEditingSchedule(false)}
                      className="text-slate-400 hover:text-slate-600"
                    >
                      <X size={14} />
                    </button>
                  </div>
                  <div>
                    <p className="text-[11px] font-medium text-slate-500 mb-1">วันนัดซ่อมใหม่</p>
                    <DateField
                      value={editDateIso}
                      min={todayIso}
                      onChange={setEditDateIso}
                      disabled={savingSchedule}
                    />
                  </div>
                  <div>
                    <p className="text-[11px] font-medium text-slate-500 mb-1">เวลานัดหมายใหม่</p>
                    <TimeField
                      value={editTime}
                      onChange={setEditTime}
                      disabled={savingSchedule}
                    />
                  </div>
                  {editError && <p className="text-[11px] text-red-500">{editError}</p>}
                  <div className="flex items-center justify-end gap-2 pt-1">
                    <button
                      type="button"
                      onClick={() => setIsEditingSchedule(false)}
                      disabled={savingSchedule}
                      className="px-3 py-1.5 rounded-lg text-xs text-slate-500 hover:bg-slate-200 transition-colors"
                    >
                      ยกเลิก
                    </button>
                    <button
                      type="button"
                      onClick={handleSaveSchedule}
                      disabled={savingSchedule || !editDateIso || !editTime}
                      className="inline-flex items-center gap-1.5 px-3.5 py-1.5 rounded-lg bg-blue-600 text-white text-xs font-medium hover:bg-blue-700 disabled:opacity-50 transition-colors"
                    >
                      {savingSchedule ? <Loader2 size={13} className="animate-spin" /> : <Check size={13} />}
                      บันทึกวันเวลาใหม่
                    </button>
                  </div>
                </div>
              )}
            </div>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          <p className="text-xs text-slate-500">ช่าง: ยังไม่ได้มอบหมาย</p>
          <select
            value={techUsername}
            onChange={(e) => setTechUsername(e.target.value)}
            disabled={saving}
            className="w-full px-3 py-2.5 rounded-xl bg-slate-50 border border-slate-200 text-xs text-slate-700 focus:outline-none focus:ring-2 focus:ring-blue-100"
          >
            <option value="">เลือกช่างเทคนิค...</option>
            {technicians.map((t) => (
              <option key={t.id || t.username} value={t.username}>
                {t.tech_name || t.name || t.username}
              </option>
            ))}
          </select>

          {techUsername ? (
            <div>
              <p className="text-[11px] font-medium text-slate-500 mb-1.5">วันนัดหมาย</p>
              <DateField value={dateIso} min={todayIso} onChange={setDateIso} disabled={saving} />
            </div>
          ) : null}

          {techUsername && dateIso ? (
            <div>
              <p className="text-[11px] font-medium text-slate-500 mb-1.5">เวลานัดหมาย</p>
              <TimeField value={time} onChange={setTime} disabled={saving} />
            </div>
          ) : null}

          {error ? <p className="text-[11px] text-red-500">{error}</p> : null}

          {techUsername && dateIso && time ? (
            <button
              onClick={handleAssign}
              disabled={saving}
              className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-blue-500 text-white text-xs font-medium hover:bg-blue-600 disabled:opacity-50"
            >
              {saving ? <Loader2 size={13} className="animate-spin" /> : null}
              มอบหมายช่าง
            </button>
          ) : null}
        </div>
      )}
    </div>
  );
}

function JobLeftColumn({ job, currentCust, currentTech, technicians, customerAddress, techLoc, custLoc }) {
  return (
    <div className="space-y-4">
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div className="border border-slate-100 rounded-2xl p-4 space-y-2">
          <div className="flex items-center gap-2 text-slate-800 font-semibold text-sm">
            <User size={16} className="text-blue-500" />
            <span>ข้อมูลลูกค้า</span>
          </div>
          <div className="text-xs text-slate-600 space-y-1">
            <p><span className="text-slate-400">ชื่อ:</span> {job.customer_username || "-"}</p>
            <p><span className="text-slate-400">เบอร์โทร:</span> {currentCust?.phone || "-"}</p>
            <p className="flex items-start gap-1">
              <MapPin size={13} className="text-slate-400 shrink-0 mt-0.5" />
              <span className="line-clamp-2">{customerAddress}</span>
            </p>
          </div>
        </div>

        <TechnicianAssignBox job={job} technicians={technicians} currentTech={currentTech} />
      </div>

      <div className="space-y-2">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-slate-800 flex items-center gap-2">
            <Navigation size={16} className="text-[#B22121]" />
            ตำแหน่งงานซ่อม และช่าง (เรียลไทม์)
          </h3>
        </div>
        <JobLocationMap techLocation={techLoc} customerLocation={custLoc} customerAddress={customerAddress} />
      </div>
    </div>
  );
}

export default function JobDetailModal({ job: jobProp, machines: machinesProp, onClose, onNavigate }) {
  const { data: technicians = [] } = useDbList("technicians");
  const { data: customers = [] } = useDbList("customers");
  const { data: repairs = [] } = useDbList("repairs");
  const { data: dbMachines = [] } = useDbList("machines");

  if (!jobProp) return null;

  const machines = machinesProp && machinesProp.length > 0 ? machinesProp : dbMachines;
  const rawJob =
    repairs.find(
      (r) =>
        String(r.id) === String(jobProp.id) ||
        (jobProp.record_id && String(r.record_id) === String(jobProp.record_id))
    ) || jobProp;

  const matchedMachine = findMachineForJob(rawJob, machines) || findMachineForJob(jobProp, machines);
  const resolvedSerialNumber =
    rawJob.serial_number ||
    jobProp.serial_number ||
    rawJob.serialNumber ||
    jobProp.serialNumber ||
    matchedMachine?.serial_number ||
    "-";

  const job = {
    ...jobProp,
    ...rawJob,
    serial_number: resolvedSerialNumber,
  };

  const currentTech = technicians.find((t) => t.username === job.technician_username);
  const currentCust = customers.find((c) => c.username === job.customer_username);

  const effStatus = displayStatus(job);
  const severity = extractSeverity(job.detail);
  const ratingInfo = extractRating(job);
  const problemPhotos = getProblemPhotos(job);
  const report = getRepairReport(job);
  const hasReport = !!(report.text || report.beforePhoto || report.afterPhoto || report.slipPhoto);
  const issue = getIssueReport(job);
  const hasIssue = effStatus === "มีปัญหา" || !!(issue.detail || issue.photos.length);

  const techLoc = currentTech?.current_lat && currentTech?.current_lng
    ? { lat: Number(currentTech.current_lat), lng: Number(currentTech.current_lng) }
    : null;

  const custLoc = job.dest_lat && job.dest_lng
    ? { lat: Number(job.dest_lat), lng: Number(job.dest_lng) }
    : null;

  const customerAddress = formatBangkokAddress(job.location || currentCust?.address || "-");

  const headerTime = (job.appointment_time || job.time || "")
    .toString()
    .trim()
    .replace(/\s*น\.?$/, "");

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-slate-900/50 backdrop-blur-xs overflow-y-auto"
      onClick={onClose}
    >
      <div
        className={`relative bg-white rounded-3xl shadow-2xl w-full ${
          hasReport || hasIssue ? "max-w-5xl" : "max-w-3xl"
        } my-8 overflow-hidden border border-slate-100 animate-in fade-in duration-200`}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-6 py-5 border-b border-slate-100">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 rounded-xl bg-red-50 text-[#B22121] flex items-center justify-center font-bold text-sm">
              <Wrench size={20} />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h2 className="text-lg font-bold text-slate-800">
                  {job.ticketNo || `#${job.id}`}
                </h2>
                <span className={`text-xs font-semibold px-2.5 py-0.5 rounded-full ${STATUS_BADGE[effStatus] || "bg-slate-100 text-slate-600"}`}>
                  {effStatus}
                </span>
                <span className={`text-xs font-semibold px-2.5 py-0.5 rounded-full ${SEVERITY_BADGE[severity] || "bg-slate-100 text-slate-600"}`}>
                  {severity}
                </span>
              </div>
              <p className="text-xs text-slate-400 mt-0.5">
                วันนัดหมาย: {displayStoredDate(job.date)}
                {headerTime ? ` เวลา ${headerTime} น.` : ""}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="w-9 h-9 rounded-xl flex items-center justify-center text-slate-400 hover:text-slate-600 hover:bg-slate-100 transition-colors"
          >
            <X size={18} />
          </button>
        </div>

        <div className="p-6 space-y-6 max-h-[calc(85vh-120px)] overflow-y-auto">
          <div className="bg-slate-50 rounded-2xl p-4 border border-slate-100 space-y-3">
            <h3 className="text-xs font-bold text-slate-500 uppercase tracking-wider">ข้อมูลอุปกรณ์และปัญหา</h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 text-sm">
              <div>
                <span className="text-slate-400 text-xs block">อุปกรณ์/เครื่องจักร:</span>
                <span className="font-medium text-slate-800">{job.machine || matchedMachine?.model_name || "-"}</span>
              </div>
              <div>
                <span className="text-slate-400 text-xs block">Serial Number:</span>
                <span className="font-medium text-slate-800 font-mono text-blue-600">{job.serial_number || "-"}</span>
              </div>
              <div className="sm:col-span-2">
                <span className="text-slate-400 text-xs block">รายละเอียดปัญหา:</span>
                <span className="text-slate-700 whitespace-pre-wrap">{job.detail || "-"}</span>
              </div>
            </div>
            {problemPhotos.length > 0 ? (
              <div>
                <span className="text-slate-400 text-xs block mb-1.5">
                  ภาพปัญหาที่ลูกค้าแนบมา ({problemPhotos.length} รูป):
                </span>
                <div className="flex flex-wrap gap-2">
                  {problemPhotos.map((url, i) => (
                    <a
                      key={i}
                      href={url}
                      target="_blank"
                      rel="noreferrer"
                      className="block w-20 h-20 rounded-lg overflow-hidden border border-slate-200 hover:opacity-80 transition-opacity"
                    >
                      <img src={url} alt={`ภาพปัญหา ${i + 1}`} className="w-full h-full object-cover" />
                    </a>
                  ))}
                </div>
              </div>
            ) : null}
          </div>

          {hasReport || hasIssue ? (
            <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
              <div className="lg:col-span-3 space-y-4">
                <JobLeftColumn
                  job={job}
                  currentCust={currentCust}
                  currentTech={currentTech}
                  technicians={technicians}
                  customerAddress={customerAddress}
                  techLoc={techLoc}
                  custLoc={custLoc}
                />
              </div>

              <div className="lg:col-span-2 space-y-4">
                {hasReport ? (
                  <div className="border border-slate-100 rounded-2xl p-4 space-y-3">
                    <div className="flex items-center gap-2 text-slate-800 font-semibold text-sm">
                      <FileText size={16} className="text-emerald-600" />
                      <span>รายงานการซ่อม</span>
                    </div>
                    <div className="text-xs text-slate-600 space-y-2">
                      {report.formCode ? (
                        <p><span className="text-slate-400">รหัสงานซ่อม:</span> {report.formCode}</p>
                      ) : null}
                      {report.text ? (
                        <div>
                          <span className="text-slate-400 block mb-1">รายละเอียดปัญหาที่พบ:</span>
                          <span className="text-slate-700 whitespace-pre-wrap">{report.text}</span>
                        </div>
                      ) : null}
                      {(report.beforePhoto || report.afterPhoto) ? (
                        <div className="grid grid-cols-2 gap-2">
                          {report.beforePhoto ? (
                            <div>
                              <span className="text-slate-400 block mb-1">ภาพก่อนซ่อม</span>
                              <a href={report.beforePhoto} target="_blank" rel="noreferrer" className="block aspect-square rounded-lg overflow-hidden border border-slate-200">
                                <img src={report.beforePhoto} alt="ภาพก่อนซ่อม" className="w-full h-full object-cover" />
                              </a>
                            </div>
                          ) : null}
                          {report.afterPhoto ? (
                            <div>
                              <span className="text-slate-400 block mb-1">ภาพหลังซ่อม</span>
                              <a href={report.afterPhoto} target="_blank" rel="noreferrer" className="block aspect-square rounded-lg overflow-hidden border border-slate-200">
                                <img src={report.afterPhoto} alt="ภาพหลังซ่อม" className="w-full h-full object-cover" />
                              </a>
                            </div>
                          ) : null}
                        </div>
                      ) : null}
                      {report.slipPhoto ? (
                        <div>
                          <span className="text-slate-400 block mb-1">สลิปโอนเงินของลูกค้า</span>
                          <a href={report.slipPhoto} target="_blank" rel="noreferrer" className="block w-28 aspect-square rounded-lg overflow-hidden border border-slate-200">
                            <img src={report.slipPhoto} alt="สลิปโอนเงิน" className="w-full h-full object-cover" />
                          </a>
                        </div>
                      ) : null}
                    </div>
                  </div>
                ) : null}

                {hasIssue ? (
                  <div className="border border-amber-100 bg-amber-50/40 rounded-2xl p-4 space-y-3">
                    <div className="flex items-center gap-2 text-amber-800 font-semibold text-sm">
                      <ShieldAlert size={16} className="text-amber-600" />
                      <span>ปัญหาที่พบ</span>
                    </div>
                    <div className="text-xs text-slate-700 space-y-2">
                      <p className="whitespace-pre-wrap">{issue.detail || "ช่างแจ้งว่ามีปัญหา แต่ยังไม่มีรายละเอียดเพิ่มเติม"}</p>
                      {issue.photos.length > 0 ? (
                        <div className="flex flex-wrap gap-2">
                          {issue.photos.map((url, i) => (
                            <a key={i} href={url} target="_blank" rel="noreferrer" className="block w-20 h-20 rounded-lg overflow-hidden border border-amber-200">
                              <img src={url} alt={`ภาพปัญหา ${i + 1}`} className="w-full h-full object-cover" />
                            </a>
                          ))}
                        </div>
                      ) : null}
                    </div>
                  </div>
                ) : null}
              </div>
            </div>
          ) : (
            <JobLeftColumn
              job={job}
              currentCust={currentCust}
              currentTech={currentTech}
              technicians={technicians}
              customerAddress={customerAddress}
              techLoc={techLoc}
              custLoc={custLoc}
            />
          )}

          {ratingInfo.value !== null && (
            <div className="border border-slate-100 bg-amber-50/50 rounded-2xl p-4">
              <h4 className="text-xs font-bold text-amber-800 mb-2">ผลการประเมินจากลูกค้า</h4>
              <div className="flex items-center gap-2 mb-1">
                <StarRating value={ratingInfo.value} size={16} />
                <span className="text-sm font-bold text-slate-800">{ratingInfo.value} / 5</span>
              </div>
              {ratingInfo.comment && (
                <p className="text-xs text-slate-600 italic">"{ratingInfo.comment}"</p>
              )}
            </div>
          )}
        </div>

        <div className="flex items-center justify-end gap-3 px-6 py-4 bg-slate-50 border-t border-slate-100">
          {onNavigate && (
            <button
              onClick={() => {
                onClose();
                onNavigate("chat", { query: String(job.record_id ?? job.id) });
              }}
              className="flex items-center gap-1.5 px-4 py-2 rounded-xl text-sm font-medium bg-white border border-slate-200 text-slate-700 hover:bg-slate-100"
            >
              <MessageSquare size={16} />
              เปิดห้องแชท
            </button>
          )}
          <button
            onClick={onClose}
            className="px-5 py-2 rounded-xl text-sm font-medium bg-[#B22121] text-white hover:bg-[#8B1A1A] transition-colors"
          >
            ปิด
          </button>
        </div>
      </div>
    </div>
  );
}