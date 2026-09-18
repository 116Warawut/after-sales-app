// 📷 อัปโหลดรูปภาพผ่าน Cloudinary — ใช้ credential เดียวกับที่แอปมือถือ Flutter
// ใช้อยู่แล้ว (cloudinary_service.dart) เพื่อให้รูปที่อัปโหลดจากเว็บกับแอปอยู่ใน
// บัญชี Cloudinary เดียวกัน เปิดดูข้ามแพลตฟอร์มได้ปกติ — เป็น unsigned upload preset
// จึงอัปโหลดตรงจากเบราว์เซอร์ได้เลยโดยไม่ต้องมี backend คั่นกลาง

const CLOUD_NAME = "tlc7uqvz";
const UPLOAD_PRESET = "after-sales";

/** อัปโหลดไฟล์รูป 1 ไฟล์ คืนค่าเป็น URL รูปที่อัปโหลดสำเร็จ (secure_url) */
export async function uploadImage(file) {
  if (!file) return null;
  const formData = new FormData();
  formData.append("file", file);
  formData.append("upload_preset", UPLOAD_PRESET);

  const res = await fetch(
    `https://api.cloudinary.com/v1_1/${CLOUD_NAME}/image/upload`,
    { method: "POST", body: formData }
  );
  if (!res.ok) {
    const text = await res.text().catch(() => "");
    throw new Error(`อัปโหลดรูปไม่สำเร็จ: ${res.status} ${text}`);
  }
  const data = await res.json();
  return data.secure_url;
}
