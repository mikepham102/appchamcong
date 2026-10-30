# Mô hình phân quyền — HongCha HRM

Chốt ngày 30/10/2026. Mục tiêu: **mỗi chi nhánh có 1 Manager toàn quyền vận hành nhân sự tại chi nhánh đó**; các cài đặt sâu của hệ thống chỉ Owner.

## 1. Ba tầng quyền

| Tầng | Ai | Phạm vi |
|---|---|---|
| Hệ thống | **Owner** | Tạo/xóa chi nhánh, gán chi nhánh cho Manager, bật/tắt quyền, đổi vai trò, chuyển nhân viên giữa chi nhánh |
| Vận hành | **Manager** | Toàn bộ nhân sự & vận hành **trong chi nhánh mình** (bật/tắt theo chi nhánh) |
| Tự phục vụ | **Employee** | Chỉ dữ liệu của chính mình |

Nguyên tắc: **mọi quyền phải chặn ở database** (RLS hoặc RPC), không chỉ ẩn nút trên giao diện.

## 2. Bảng quyền (12 khoá, 6 nhóm)

| # | Nhóm | Mã quyền | Manager | Nội dung |
|---|---|---|---|---|
| 1 | Nhân sự | `employee_basic` | ✅ | Xem danh sách NV, hồ sơ cơ bản, lịch sử công |
| 2 | Nhân sự | `employee_create` | ✅ | Tạo tài khoản NV + gửi email mời (**đã sửa V84.33**) |
| 3 | Nhân sự | `employee_edit` | ✅ | Sửa họ tên, SĐT, địa chỉ, trạng thái làm việc của NV — **chưa có, cần thêm** |
| 4 | Lịch & ca | `schedule_manage` | ✅ | Mẫu ca, xếp ca, mở/đóng đăng ký ca |
| 5 | Lịch & ca | `shift_registration` | ✅ | Duyệt/hủy đăng ký ca |
| 6 | Chấm công | `attendance_process` | ✅ | Bổ sung công, xử lý quên check-out |
| 7 | Chấm công | `device_manage` | ✅ | Duyệt/thu hồi thiết bị chấm công — **chưa có, cần thêm** |
| 8 | Nghỉ phép | `leave_manage` | ✅ | Duyệt nghỉ phép, duyệt tạm ứng lương |
| 9 | Lương | `payroll_view` | ✅ | Xem bảng lương, xem STK để chi trả |
| 10 | Lương | `payroll_adjust` | ✅ | Phiếu phạt / cộng / tạm ứng — **chưa có, cần thêm** (hiện gắn nhầm vào `leave_manage`) |
| 11 | Chi nhánh | `branch_gps` | ✅ | Sửa **địa chỉ + GPS + bán kính chấm công** của chi nhánh mình — **chưa có, cần thêm** |
| 12 | Kiểm toán | `audit_view` | ✅ | Xem nhật ký thao tác trong chi nhánh |

## 3. Chỉ Owner (không cấp cho Manager)

| Việc | Lý do |
|---|---|
| Tạo / xóa chi nhánh | Thay đổi phạm vi hệ thống |
| Gán Manager vào chi nhánh; bật/tắt quyền Manager | Phân quyền phải do chủ quyết |
| **Đặt mức lương/giờ và ngày áp dụng** (`employee_salary`) | Quyết định chi phí — giữ ở Owner |
| **Sửa số tài khoản ngân hàng của NV** (`employee_bank_edit`) | Chống gian lận tiền lương; NV tự nhập, Owner duyệt |
| Tạo kỳ lương / tính lương / chốt kỳ (`payroll_manage`) | Chốt tiền |
| Chuyển nhân viên sang chi nhánh khác | Ảnh hưởng dữ liệu 2 chi nhánh |
| Đổi vai trò, khóa/xóa tài khoản | Không thể hoàn tác |
| Giờ chấm công (đi trễ/ về sớm/ cutoff), WiFi, múi giờ | Cấu hình sâu (có thể mở sau nếu bạn muốn) |

> Quyết định đã chốt: Manager **được xem lương** và **xem STK** để chi trả, nhưng **không được sửa STK**.

## 4. Quyền gắn với chi nhánh, không gắn với người

`manager_permissions` lưu **theo chi nhánh** (`store_id` + `permission_key`).
Hệ quả: 1 chi nhánh có 2 Manager thì 2 người dùng chung bộ quyền. Đúng với mô hình hiện tại (1 Manager/chi nhánh).

## 5. Preset cấu hình nhanh

| Mức | Bật | Dùng khi |
|---|---|---|
| Cơ bản | `employee_basic`, `schedule_manage`, `shift_registration`, `attendance_process`, `leave_manage`, `audit_view` | Manager mới, thử việc |
| **Vận hành đầy đủ** ⭐ | Cả 12 quyền ở mục 2 | Manager chi nhánh (khuyến nghị) |

## 6. Trạng thái triển khai

| Giai đoạn | Nội dung | Trạng thái |
|---|---|---|
| P1 | Sửa `create-employee` cho Manager có `employee_create` | ✅ Code xong, chờ deploy |
| P2 | Thêm 4 khoá: `employee_edit`, `device_manage`, `payroll_adjust`, `branch_gps` (DB + UI + RPC) | ⏳ Chưa làm |
| P3 | Tách `employee_salary` / `employee_bank_edit` khỏi luồng hiện tại; bổ sung audit log | ⏳ Chưa làm |
| P4 | Nút preset 2 mức + màn hình quyền gọn hơn | ⏳ Chưa làm |

### Điểm cần sửa khi làm P2

- `owner_save_manager_permissions_v2` có **danh sách khoá cứng** 8 giá trị → phải thêm 4 khoá mới, nếu không sẽ báo `QUYEN_KHONG_HOP_LE`.
- `review_attendance_device()` đang chặn `v_role <> 'owner'` → cần bản cho Manager có `device_manage`.
- `manager_permissions` dùng `leave_manage` cho phiếu phạt/cộng → chuyển sang `payroll_adjust` (giữ tương thích 1 thời gian).
- `stores_owner_update` (RLS) đang chỉ cho Owner → cần policy/RPC riêng cho `branch_gps` (chỉ 4 cột: address, latitude, longitude, gps_radius_m).
- `managerPermissionForTab` trong `index.html` đang ẩn toàn bộ tab "Chi nhánh" với Manager → cần màn hình riêng chỉ hiện phần GPS.
