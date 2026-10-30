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
| 2 | Nhân sự | `employee_create` | ✅ | Tạo tài khoản NV + gửi email mời (**V84.33**) |
| 3 | Nhân sự | `employee_edit` | ✅ | Sửa họ tên, SĐT, địa chỉ, trạng thái làm việc (**V84.34**) |
| 4 | Lịch & ca | `schedule_manage` | ✅ | Mẫu ca, xếp ca, mở/đóng đăng ký ca |
| 5 | Lịch & ca | `shift_registration` | ✅ | Duyệt/hủy đăng ký ca |
| 6 | Chấm công | `attendance_process` | ✅ | Bổ sung công, xử lý quên check-out |
| 7 | Chấm công | `device_manage` | ✅ | Duyệt/thu hồi thiết bị chấm công (**V84.34**) |
| 8 | Nghỉ phép | `leave_manage` | ✅ | Duyệt nghỉ phép, yêu cầu đổi ca/đi trễ |
| 9 | Lương | `payroll_view` | ✅ | Xem bảng lương, xem STK để chi trả |
| 10 | Lương | `payroll_adjust` | ✅ | Phiếu phạt / cộng / tạm ứng (**V84.34**, tách khỏi `leave_manage`) |
| 11 | Chi nhánh | `branch_gps` | ✅ | Sửa địa chỉ + GPS + bán kính chi nhánh mình (**V84.34**) |
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
| P1 | Sửa `create-employee` cho Manager có `employee_create` | ✅ Xong (V84.33) |
| P2 | Thêm 4 khoá: `employee_edit`, `device_manage`, `payroll_adjust`, `branch_gps` | ✅ Xong code (V84.34) — chờ chạy SQL + deploy frontend |
| P3 | Tách `employee_salary` / `employee_bank_edit`; bổ sung audit log cho các chỗ ghi trực tiếp | ⏳ Chưa làm |
| P4 | Nút preset 2 mức + màn hình quyền gọn hơn | ⏳ Chưa làm |

### Đã xử lý trong V84.34

- `owner_save_manager_permissions_v2`: whitelist mở rộng 8 → **12 khoá**.
- `owner_get_manager_permissions`: bộ mặc định 12 khoá (4 khoá mới bật sẵn).
- Migration bật sẵn 4 quyền mới cho **mọi chi nhánh đang có** (không ghi đè giá trị cũ).
- `review_attendance_device`: Manager có `device_manage` duyệt/từ chối/thu hồi được.
- `enforce_manager_business_permission`: Manager sửa được hồ sơ nhân viên cùng chi nhánh (chỉ 4 cột: họ tên, SĐT, địa chỉ, trạng thái) khi có `employee_edit`.
- Trigger mới `trg_guard_manager_payroll_adjust`: chặn Manager thêm/sửa/xoá phiếu phạt–cộng–tạm ứng nếu thiếu `payroll_adjust`.
- `manager_update_employee_profile` và `manager_update_branch_gps`: RPC mới, chỉ thao tác trong chi nhánh của chính Manager.
- Frontend: 4 quyền mới trong màn hình cấu hình; tab Thiết bị / Cửa hàng mở cho Manager theo quyền; form cửa hàng khoá các ô ngoài GPS; phiếu phạt/cộng/tạm ứng chuyển sang `payroll_adjust`.
- **Chuyển nhân viên sang chi nhánh khác** nay chỉ Owner (đúng thiết kế mục 3).

