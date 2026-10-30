# Lịch sử phát triển — HongCha HRM

Tài liệu này thay thế các file `README_V65.txt` … `README_V74_PERFORMANCE.txt` (đã xóa khỏi repo, nội dung giữ nguyên ở đây).
Toàn bộ lịch sử chi tiết từng dòng code nằm trong `git log` (163 commit tính đến 18/10/2026).

---

## Ghi chú theo phiên bản (V65 → V74)

### V65 — Ngày áp dụng cho ca và lương
- Thay đổi mẫu ca có "ngày áp dụng"; ca trong tương lai thuộc mẫu đó được đồng bộ từ đúng ngày áp dụng.
- Ca đã bắt đầu hoặc đã có check-in **không bao giờ** bị ghi đè.
- Thay đổi mức lương cũng có "ngày áp dụng": bảng lương tính lương/giờ **theo ngày làm việc**, nên mức lương mới không ảnh hưởng công đã làm trước đó.
- DB: `02_V65_Effective_Date.sql` (DB đang có dữ liệu) hoặc `01_HONGCHA_HRM_V65_COMPLETE_ONE_RUN.sql` (DB trống).

### V66 — Giao diện Lịch + tông màu
- Lịch Owner/Manager hiển thị rõ tên ca + giờ, tiêu đề ca có nền đỏ/xanh phân biệt.
- Thêm ca trực tiếp trên giao diện Lịch; tạo ca theo mẫu ca + phiên bản có hiệu lực đúng ngày.
- UI chuyển từ be/xám nhạt sang hệ đỏ + xanh.
- Không thay đổi nghiệp vụ. Dùng RPC `create_schedule_slots` sẵn có.

### V67 — Sửa lỗi chấm công (enum/text)
- Sửa lỗi `attendance_punch` lệch kiểu enum/text cho `check_in_status` / `check_out_status`.
- Sau khi RPC lỗi, UI **kiểm tra lại dữ liệu thật** và nói rõ đã ghi nhận chấm công hay chưa (không để nhân viên đoán).
- Không đổi quyền/nghiệp vụ lương/lịch.

### V68 — (không có ghi chú riêng) Sửa lỗi lưu mẫu ca. Truy vết bằng `git log`.

### V69 — Trạng thái sau check-in sớm
- Check-in sớm vẫn ghi nhận đúng ca được phân.
- Trước giờ ca: "Đã check-in sớm", **khóa checkout**.
- Từ giờ ca trở đi: "Đang làm việc", cho checkout.
- Chặn checkout trước giờ mở ca ở mức database.

### V70 — Quy tắc checkout + lịch nhân viên
- Checkout: không trước giờ mở ca; được checkout trong ca và **tối đa 60 phút** sau giờ kết thúc.
- Checkout trong 60 phút sau giờ kết thúc: ghi nhận giờ thực tế nhưng **giờ công chốt tối đa đến giờ kết thúc ca**.
- Quá 60 phút: khóa tự checkout, giờ công chờ Owner/Manager bổ sung.
- Lịch nhân viên: hiện toàn bộ ca trong ngày + người được xếp + số điện thoại; **không** lộ trạng thái chấm công của người khác.
- DB: `07_V70_Attendance_Schedule.sql`.

### V71 — Tóm tắt ca trên trang chủ nhân viên
- Có ca hôm nay: "Hôm nay bạn có ca" + tên/giờ từng ca.
- Không có ca: "Hôm nay bạn không có ca làm" + ca gần nhất sắp tới (tên, giờ, ngày).
- Chỉ UI, không cần migration.

### V72 — Sửa nguồn dữ liệu lịch nhân viên
- RPC `get_employee_schedule_overview()` là **nguồn chuẩn** cho lịch nhân viên.
- Nhân viên thấy mọi ca chưa hủy của chi nhánh trong khoảng ngày đã chọn, kèm tên + SĐT người được xếp; không trả trạng thái chấm công của người khác.
- Frontend phân biệt "ngày trống thật" với "lỗi tải dữ liệu" (V72 không còn báo sai "Ngày này chưa có lịch").
- Đầu trang lịch nhân viên hiện **tổng số ca** trong ngày, không chỉ ca của bản thân.
- DB: `HongCha_HRM_V72_Employee_Schedule_Fix.sql`. **Không** chạy lại bộ SQL cài đặt một lần trên DB đang có dữ liệu.

### V73 — (không có ghi chú riêng) Truy vết bằng `git log`.

### V74 — Tối ưu hiệu năng & nạp dữ liệu (chỉ hiệu năng)
- **Đăng nhập**: hiện khung app ngay sau khi qua bước hồ sơ/thiết bị; chỉ nạp dữ liệu màn hình đang mở (trước đây nạp tuần tự nhiều màn).
- **Trang chủ nhân viên**: bỏ việc nạp lịch 2 lần do `renderRoleUI → navigate → loadApp`.
- **Mở Lịch**: mỗi lần chỉ 1 lượt nạp; lịch tuần nhân viên dùng cache 20 giây + request song song.
- **Đổi ngày/tuần**: đổi ngày trong tuần đã cache xử lý tại máy; chỉ tuần mới cần mạng.
- **Mở Chấm công**: state/history/device chạy song song; GPS không chặn màn hình.
- **Sau khi lưu**: chấm công, đăng ký/hủy ca, lưu mẫu ca, tạo ca trực tiếp, duyệt đăng ký → phản hồi ngay, refresh chạy nền bằng `Promise.allSettled`.
- Không cần migration. Chỉ thêm mốc thời gian `console.info` để đo hiệu năng.

---

## V75 → V84.28
Không có ghi chú riêng. Truy vết bằng `git log --oneline` (mỗi commit = 1 thay đổi giao diện/nghiệp vụ nhỏ).

## V84.29 — Bảo vệ chuyển chi nhánh + duyệt hồ sơ + dọn thiết bị
Ba migration trong `sql/migrations/`:
1. `HongCha_HRM_Multi_Branch_Manager_Access_Migration.sql` — Manager được gán nhiều chi nhánh (`store_memberships`), tự chuyển chi nhánh bằng `switch_active_store`, quyền chức năng vẫn theo từng chi nhánh qua `manager_permissions`; thêm schema `private` + bảng `private.platform_admins` (không cấp quyền dữ liệu nghiệp vụ).
2. `HongCha_HRM_V84.29_Employee_Profile_Approval_Migration.sql` — nhân viên sửa họ tên/SĐT/địa chỉ/ngân hàng phải qua yêu cầu chờ Owner duyệt (chặn bằng trigger ở DB, không chỉ ở UI); thêm bảng `employee_profile_change_requests` (RLS bật, chỉ đọc của mình hoặc Owner).
3. `HongCha_HRM_V84.29_Device_Cleanup_Migration.sql` — Owner xóa thiết bị chấm công đã thu hồi/từ chối; **từ chối xóa** nếu thiết bị đã có lịch sử `attendance`/`attendance_events`; ghi `audit_logs`.

## V84.30 — Sửa tự chốt đăng ký ca
`HongCha_HRM_V84.30_Shift_Registration_Auto_Finalize_Fix.sql`
- Lỗi: `employee_schedule_conflict()` trả về **UUID scalar** nhưng hàm tự chốt lại đọc như bảng có cột `id` → job luôn lỗi.
- Sửa: gán trực tiếp `conflict_id := public.employee_schedule_conflict(...)`.
- Chỉ thay định nghĩa hàm, không chạy hàm, không đổi dữ liệu. Cron hiện có sẽ xử lý các cửa sổ quá hạn.

---

## Tính năng đã gỡ khỏi repo (vẫn khôi phục được bằng git)
- `HongCha_HRM_V59_Native_App_Icon.html` — bản app V59 (347 KB), không còn được dùng. Khôi phục:
  `git log --oneline -- HongCha_HRM_V59_Native_App_Icon.html` rồi `git show <commit>:<file> > /tmp/v59.html`

---

## Sau V84.30 — Dọn dẹp & ổn định (30/10/2026)

Không thay đổi nghiệp vụ, không thay đổi giao diện.

- Đồng bộ repo về đúng bản đang chạy: `index.html` khớp blob `718c2cba…` của commit `ebbfb76` (tag `v84.30`). Bản HTML cũ trong máy (commit `e39dbd0`) chỉ được lưu ở `_archive/`, không dùng để phát hành.
- Xóa khỏi repo: `mnt/` (thư mục rác sandbox), `HongCha_HRM_V59_Native_App_Icon.html`, `README_V65…V74` (8 file), `DEPLOY_README.txt`. Tổng giảm 2.769 dòng / ~353 KB. Không file nào được app tham chiếu.
- Gộp ghi chú phiên bản vào `docs/CHANGELOG.md`; thêm `README.md`, `docs/PROJECT.md`, `docs/DEPLOY.md`, `sql/README.md`, `.gitignore`.
- Đưa 8 file SQL (migration + audit + snapshot) vào git — trước đây SQL chỉ nằm ngoài repo.
- Sửa lỗi cú pháp CSS: bỏ 1 dấu `}` thừa ở cuối rule `.app-brand-center .brand-mark` (dòng 985). Gradient logo `#e50000 → #216345` **giữ nguyên** theo ý chủ dự án.
- Kiểm tra sau sửa: JS `node --check` PASS; các block CSS cân bằng ngoặc; `index.html` chỉ đổi đúng 1 ký tự.

---

## V84.31 HOTFIX — Đổi mật khẩu nhân viên luôn báo PASSWORD_TOO_SHORT (30/10/2026)

**Hiện tượng:** Owner vào Nhân viên → Sửa nhân viên → đổi mật khẩu, nhập mật khẩu dài bao nhiêu cũng báo `PASSWORD_TOO_SHORT`.

**Nguyên nhân:** Edge Function `change-employee-password` đọc `body["password"]`, nhưng app gửi `{ employee_id, new_password }`. Giá trị nhận được luôn là chuỗi rỗng → `length 0 < 8` → luôn báo lỗi.

**Sửa:**
- Đọc `body.new_password ?? body.password` (tương thích ngược cả 2 tên trường).
- Ghi `audit_logs` thất bại **không còn** làm API trả lỗi sau khi mật khẩu đã đổi thành công.
- Trả thêm `min_length` / `max_length` khi báo lỗi độ dài.

**File nguồn (lần đầu được đưa vào git):** `supabase/functions/change-employee-password/index.ts`
**Không cần sửa `index.html`** — chỉ deploy lại Edge Function.

---

## V84.32 — Đa chi nhánh hoàn chỉnh cho đổi mật khẩu + dọn cron (30/10/2026)

### A. Edge Function `change-employee-password` — phạm vi chi nhánh
- **Trước:** chỉ cho đổi mật khẩu khi `employee.store_id === caller.store_id` (Owner phải đang chọn đúng chi nhánh của nhân viên) → khi mở chi nhánh 2 sẽ bị `FORBIDDEN`.
- **Sau:** kiểm tra quyền bằng `store_memberships` (`role = owner`, `is_active = true`) tại chi nhánh của nhân viên → Owner đổi được mật khẩu cho nhân viên ở **bất kỳ chi nhánh mình sở hữu**.
- `audit_logs.store_id` ghi theo **chi nhánh của nhân viên** (kể cả khi Owner đang ở chi nhánh khác).
- Bỏ yêu cầu `caller.store_id` (Owner có thể chưa chọn chi nhánh).
- Vẫn giữ: chỉ Owner, chỉ tài khoản `role = employee`, chặn nhân viên đã `terminated`, độ dài 8–128.

### B. Cron trùng lặp
- `sql/maintenance/HongCha_HRM_V84.32_Remove_Duplicate_Cron_Job.sql` — bỏ job 10 (trùng job 9), có kiểm tra trước khi xóa.
- Xác nhận an toàn: `shift_registration_windows` có `UNIQUE (store_id, week_start)` nên chạy trùng không thể sinh dữ liệu trùng.

---

## V84.33 — Manager được tạo nhân viên + chốt mô hình phân quyền (30/10/2026)

### Sửa lỗi
- Edge Function `create-employee` chặn cứng `caller.role !== "owner"` → Manager dù có quyền `employee_create` vẫn nhận `FORBIDDEN`.
- Nay: Owner tạo được; **Manager tạo được khi** (a) `profiles.role = manager`, `employment_status = active`, có `store_id`; (b) có `store_memberships` manager active tại chi nhánh đó; (c) `manager_permissions.employee_create = true` tại chi nhánh đó.
- Nhân viên mới luôn thuộc chi nhánh của người tạo (client không gửi `store_id`).
- `audit_logs` ghi kèm `store_id` + `created_by_role`.
- Giữ nguyên: email mời, hoàn tác khi tạo hồ sơ lỗi, hoàn tác khi ghi audit lỗi.

### Tài liệu
- Thêm `docs/PERMISSIONS.md`: mô hình 3 tầng, 12 khoá quyền, danh sách chỉ-Owner, preset, lộ trình P1–P4.

