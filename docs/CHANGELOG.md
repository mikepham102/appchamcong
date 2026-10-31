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

---

## V84.34 — P2: 4 quyền vận hành mới cho Manager (30/10/2026)

**Database** — `sql/migrations/HongCha_HRM_V84.34_Manager_P2_Permissions.sql`
- Thêm 4 khoá quyền, **bật sẵn cho mọi chi nhánh hiện có** (không ghi đè cấu hình cũ):
  `employee_edit`, `device_manage`, `payroll_adjust`, `branch_gps`.
- `owner_save_manager_permissions_v2`: whitelist 8 → 12 khoá (nếu không sẽ báo `QUYEN_KHONG_HOP_LE`).
- `owner_get_manager_permissions`: bộ mặc định 12 khoá.
- `review_attendance_device`: thêm nhánh Manager (cần `device_manage`, cùng chi nhánh).
- `enforce_manager_business_permission`: thêm nhánh "Manager sửa hồ sơ nhân viên cùng chi nhánh" — chỉ cho đổi `full_name`, `phone`, `address`, `employment_status`; chặn đổi `role`, `hourly_rate`, `store_id`, `email`.
- Trigger mới `trg_guard_manager_payroll_adjust` trên `payroll_adjustments` — chặn Manager thao tác phiếu phạt/cộng/tạm ứng khi thiếu `payroll_adjust`.
- RPC mới `manager_update_employee_profile(...)` và `manager_update_branch_gps(...)`, đều ghi `audit_logs`.

**Frontend** — `index.html`
- Màn cấu hình quyền Manager hiển thị 4 quyền mới.
- Tab **Thiết bị** mở cho Manager có `device_manage`; tab **Cửa hàng** mở cho Manager có `branch_gps`.
- Form cửa hàng: Manager chỉ sửa địa chỉ/GPS/bán kính; các ô tên quán, giờ đi trễ, giờ mở check-in, lương mặc định bị khoá.
- Sửa nhân viên (Manager) gọi RPC mới, cho đổi **địa chỉ + trạng thái làm việc**; ô vai trò/lương/ngân hàng vẫn khoá.
- Phiếu phạt / cộng / tạm ứng chuyển từ `leave_manage` sang `payroll_adjust`.
- **Chuyển nhân viên sang chi nhánh khác: chỉ Owner**.

**Không thay đổi:** đặt mức lương, sửa STK ngân hàng, tính/chốt kỳ lương, tạo/xóa chi nhánh, phân quyền, đổi vai trò.

---

## V84.35 — Công tắc bật/tắt dùng chung (30/10/2026)

Chỉ giao diện. Không đổi nghiệp vụ, không đổi dữ liệu, không cần deploy SQL.

- Thêm thành phần công tắc `.hc-switch` (thuần CSS, dùng `appearance:none`), tôn trọng `role="switch"` và trạng thái `disabled`.
- Áp dụng cho:
  - 12 quyền Manager (màn Quản trị → Quyền Manager)
  - Gán chi nhánh cho từng Manager
  - Cài đặt đăng ký ca: tự mở, tự duyệt
  - Quy tắc thưởng đủ giờ (`bonusDailyActive`)
  - Trạng thái mẫu ca (`tplActive`) — đổi từ dropdown 2 lựa chọn sang công tắc
- `tplActive` chuyển sang boolean: cập nhật 4 chỗ đọc/ghi (`openCreateTemplate`, `openEditTemplate`, `saveTemplate`, `toggleTemplateActive`).
- `.settings-toggle-card` đổi cột đầu 18px → 52px để chứa công tắc.
- Kiểm tra: JS `node --check` PASS; block CSS cân bằng ngoặc (605/605).

---

## V84.36 — Đặt mật khẩu lần đầu + gọn màn hình đăng nhập (30/10/2026)

### 1. Nhân viên nhận email mời phải đặt mật khẩu lần đầu
- Trước: bấm link mời → tài khoản được kích hoạt nhưng **không có mật khẩu** → lần sau phải dùng "Quên mật khẩu" hoặc nhờ Owner đặt lại.
- Nay: sau khi bấm link, app hiện màn hình **"Đặt mật khẩu lần đầu"** (2 ô: mật khẩu + nhập lại, tối thiểu 8 ký tự), chỉ vào app sau khi lưu thành công.
- Nhận biết link mời theo 2 lớp:
  1. Đọc `type=invite` trên URL **trước khi** supabase-js xoá hash.
  2. Dự phòng: nếu hồ sơ còn `employment_status = 'invited'` thì vẫn buộc đặt mật khẩu (áp dụng cả khi đăng nhập bằng link email).
- Cờ chờ đặt mật khẩu lưu theo `user_id` trong `localStorage` → **refresh giữa chừng vẫn không vào được app**.
- Cờ tự xoá khi: đặt mật khẩu thành công, đổi mật khẩu trong app, hoặc đặt lại qua email khôi phục.
- Nút "Đăng xuất" ngay trên màn hình đó để đổi tài khoản.

### 2. Màn hình đăng nhập gọn hơn
- Bỏ ô Email trùng lặp: trước đây tab "Mật khẩu" và tab "Email" mỗi bên có một ô email riêng.
- Nay **một ô Email duy nhất** dùng cho cả hai cách đăng nhập (mật khẩu / link email).
- Xoá toàn bộ tham chiếu tới `loginEmailOtp` (input, `initLoginPreference`, `setLoginMode`, `sendMagicLink`).

**Không đổi:** cơ chế xác thực, quyền, dữ liệu. Chỉ giao diện + luồng đặt mật khẩu lần đầu.

---

## V84.37 — Chi nhánh, phân quyền hiển thị, danh sách nhân viên, Excel (30/10/2026)

### 1. Đổi "Tên quán" → "Chi nhánh" + tiêu đề tab theo chi nhánh
- Nhãn cài đặt: `Tên quán` → **`Tên chi nhánh`**; tiêu đề khung: `Cửa hàng & chấm công` → **`Chi nhánh & chấm công`**.
- Nhóm menu Quản trị: `Cửa hàng & hệ thống` → **`Chi nhánh & hệ thống`**, mục `Cửa hàng` → **`Chi nhánh`**.
- **Tiêu đề tab trình duyệt** tự đổi theo chi nhánh đang chọn: `HongCha HRM - CN <tên chi nhánh>`; không có chi nhánh thì `HongCha HRM`.
  - Owner/Manager: cập nhật trong `syncBranchUI()` (đổi chi nhánh là đổi tiêu đề ngay).
  - Nhân viên: lấy tên chi nhánh 1 lần khi đăng nhập (có cache, không gọi lại).
  - Đồng bộ cả `apple-mobile-web-app-title` (tên khi thêm vào màn hình chính).

### 2. Manager không thấy tài khoản Owner
- **DB (V84.37 migration):** policy `profiles_staff_read_branch` thêm điều kiện
  `my_role()='owner' OR role <> 'owner'` → Manager không đọc được hồ sơ Owner kể cả khi gọi API trực tiếp.
- **Giao diện:** danh sách nhân viên lọc bỏ dòng `role='owner'` khi người xem không phải Owner.

### 3. Danh sách nhân viên trong Quản trị (giao diện mới)
- Bỏ bảng 5 cột cũ → **danh sách thẻ** dễ đọc:
  - Avatar chữ cái đầu · Tên · nhãn Vai trò · nhãn Trạng thái.
  - Dòng phụ 1: email · số điện thoại.
  - Dòng phụ 2 (chỉ Owner): lương/giờ · ngân hàng + số tài khoản.
  - Nút **Sửa** tách riêng bên phải.
- Mobile (≤560px): tự xuống 2 dòng, nút Sửa nằm dưới — không bị bóp cột.

### 4. Excel báo cáo lương tháng có cột ngân hàng
- `exportOwnerMonthlyPayroll` (báo cáo tháng, truy vấn trực tiếp) thêm 3 cột đầu: **Ngân hàng · Số tài khoản · Chủ tài khoản**.
- Nguồn: `employee_bank_accounts`, lấy 1 lượt cho các nhân viên trong báo cáo; số tài khoản giữ dạng text (không mất số 0 đầu).
- Báo cáo kỳ lương (`exportPayrollReportExcel`) vốn đã có 3 cột này — không đổi.

---

## V84.38 — Bỏ hẳn 2 tab đăng nhập (30/10/2026)

- Xoá khối chuyển chế độ **"Mật khẩu / Email"** ở màn hình đăng nhập → chỉ còn **một form duy nhất**: Email → Mật khẩu → Đăng nhập → Quên mật khẩu.
- Xoá khối **"Gửi link đăng nhập"** (magic link) khỏi giao diện.
- Xoá code liên quan: biến `loginMode`, hàm `setLoginMode()`, hàm `sendMagicLink()` và mọi tham chiếu tới `loginModePassword`, `loginModeOtp`, `otpLoginFields`.
- Vẫn giữ: "Lưu đăng nhập", "Quên mật khẩu" (gửi email đặt lại), và màn hình "Đặt mật khẩu lần đầu" sau link mời.
- Kiểm tra: `grep` xác nhận 0 tham chiếu còn lại; `node --check` PASS.

---

## V84.39 — Tăng tốc Phiếu phạt / Phiếu cộng / Ứng lương (30/10/2026)

**Nguyên nhân:** mỗi lần mở 3 màn này app gọi lại **toàn bộ RPC** (kể cả phần "bối cảnh" nặng: danh sách kỳ lương + nhân viên + quy tắc), không có cache, và mở lại tab là chờ lại từ đầu.

**Sửa (frontend):**
- Thêm `hcRpc(key, ttl, loader)` — cache phản hồi **thành công** + **gộp các lời gọi trùng** đang bay (chỉ 1 request).
- Áp dụng cho 6 truy vấn: bối cảnh phiếu phạt (5 phút), danh sách phiếu phạt (60 giây, theo trạng thái + offset), quy tắc phạt (5 phút), bối cảnh phiếu cộng (5 phút), danh sách phiếu cộng (60 giây), danh sách tạm ứng (45 giây).
- **Tải trước khi mở Quản trị:** `prefetchAdminFinancePanels()` chạy sau 900 ms, tải sẵn 3 bối cảnh/ danh sách tạm ứng — nên bấm vào tab là có dữ liệu ngay. Chỉ 1 lần/chi nhánh/5 phút.
- Sau mỗi thao tác tạo/duyệt/lưu quy tắc: buộc tải lại (`force`) để dữ liệu không bị cũ.
- Không đổi dữ liệu, không đổi RPC, không cần chạy SQL.

**Kết quả kỳ vọng:** lần đầu mở có thể vẫn chờ theo tốc độ mạng; mở lại tab và chuyển qua lại giữa 3 màn gần như tức thì.

---

## V84.40 — Làm tròn phút khi chấm công (30/10/2026)

**Lỗi:** nhân viên vào `07:30:0x`, ca kết thúc `12:00` → app hiện **7h30 – 12h** nhưng ghi nhận **4h29p**. Nguyên nhân: hàm `attendance_punch` tính `floor((12:00 − 07:30:0x)/60)` → 269 phút, phần giây bị cắt.

**Cách sửa (đúng quy tắc chủ dự án chốt):**
| Thời điểm chấm | Ghi nhận | Trễ |
|---|---|---|
| `07:30:00` hoặc sớm hơn | `07:30` | 0 |
| `07:30:02` | `07:31` | 1 phút |
| Check-out `12:05:47` | `12:05` | — |

- Check-in **làm tròn LÊN** phút (`v_in_at`), check-out **làm tròn XUỐNG** phút (`v_out_at`).
- `late_minutes`, `worked_minutes`, `early_leave_minutes` tính từ giờ đã làm tròn → **hiển thị và tính lương luôn khớp**.
- Giữ nguyên toàn bộ: kiểm tra thiết bị / GPS / khung giờ / handoff ca liền kề / mức chốt tối đa đến giờ kết thúc ca (V70).
- **Bằng chứng thật vẫn còn:** `public.attendance_events.event_at` lưu giờ chấm **chính xác đến giây**.
- **Không sửa dữ liệu chấm công đã có** — bản ghi 4h29 cũ giữ nguyên.
- Migration tạo từ **đúng bản hàm đang chạy** (`sql/snapshots/attendance_punch_live.csv`), không dùng bản dump cũ.
- File: `sql/migrations/HongCha_HRM_V84.40_Attendance_Rounding.sql` · rollback: `sql/rollback/HongCha_HRM_V84.40_Rollback.sql`

---

## V84.41 — Tăng tốc Phiếu phạt / Phiếu cộng / Ứng lương (30/10/2026)

**Nguyên nhân gốc (tìm ra sau khi đọc 5 hàm production):**

```sql
-- manager_owner_list_penalties_v85
AND coalesce(a.origin_store_id, pp.store_id) = v_store
-- manager_owner_list_bonus_vouchers_v1
AND COALESCE(a.origin_store_id, pp.store_id, e.store_id) = v_store
```

Bọc cột trong `coalesce()` khiến PostgreSQL **không dùng được index** trên `origin_store_id` → phải **quét toàn bộ `payroll_adjustments` của mọi chi nhánh**, join rồi mới sắp xếp + `LIMIT 100`.

**Đã sửa:**
- Viết lại điều kiện lọc thành so sánh trực tiếp, **giữ nguyên kết quả trả về** (đã kiểm chứng từng nhánh `origin_store_id` có/không có, `payroll_period` có/không có).
- Thêm 4 index:
  - `payroll_adjustments_penalty_store_created_idx` — phiếu phạt **đã xếp kỳ** (index cũ chỉ phủ phiếu chưa xếp kỳ).
  - `payroll_adjustments_penalty_null_origin_idx` — phiếu phạt thiếu `origin_store_id`.
  - `payroll_adjustments_bonus_null_origin_idx` — phiếu cộng thiếu `origin_store_id`.
  - `payroll_adjustments_advance_emp_created_idx` — phiếu tạm ứng.
- Quyền Manager cho 4 hàm: chấp nhận `payroll_adjust` **hoặc** `leave_manage` (giao diện đã chuyển sang `payroll_adjust` từ V84.34; giữ `leave_manage` để tương thích cấu hình cũ).
- Không đổi cột trả về, không đổi dữ liệu.

**Files:** `sql/migrations/HongCha_HRM_V84.41_Finance_RPC_Index.sql` · `sql/rollback/HongCha_HRM_V84.41_Rollback.sql`

---

## V84.42 — Sửa thanh tải bị kẹt ở Phiếu phạt / Ứng lương (30/10/2026)

**Hiện tượng:** mở **Quản lý phạt** hoặc **Ứng lương** thấy vệt sáng chạy lặp mãi (thanh tải), dù nội dung bên dưới đã hiển thị và thao tác được. Mở sang **Phiếu cộng** rồi quay lại thì hết.

**Nguyên nhân:** `adminTab()` bật class `is-loading` cho khung Quản trị, nhưng chỉ gắn lệnh tắt (`done`) cho các tab nằm trong danh sách nạp dữ liệu chung. `penalties` và `advances` **nạp dữ liệu riêng** (gọi thẳng, không `await`) nên **không bao giờ tắt** class → vệt sáng chạy vô hạn. Khi mở tab khác, `done()` của tab đó mới xoá class → nên quay lại thì "bình thường".

**Sửa:**
- Thêm `adminPaneLoading(task)` — bật thanh tải, **luôn tắt** trong `finally` (kể cả khi lỗi).
- `penalties` / `advances` dùng wrapper này.
- Khối nạp chung **không** bật thanh tải cho 2 tab đó nữa (tránh 2 nơi cùng quản lý).

**Lưu ý:** đây là **lỗi hiển thị**, không phải tốc độ. Việc tăng tốc thật nằm ở V84.41 (bỏ `coalesce` + thêm index).

---

## V84.43 — 4 lỗi ở tài khoản Quản lý (30/10/2026)

### 1. Manager không thấy mức lương hiện tại của nhân viên
- `loadEmployees()` chỉ lấy cột `hourly_rate` khi người xem là Owner → Manager thấy ô lương trống/0.
- Nay: Manager có quyền `payroll_view` **thấy** mức lương (chỉ đọc; ô nhập vẫn bị khoá như trước).

### 2. Manager không có cấu hình phạt tự động
- `payroll_penalty_rules` chỉ có policy **owner-only** → Manager bị chặn cả đọc lẫn ghi; panel quy tắc bị ẩn.
- **DB (V84.43):** thêm policy `payroll_penalty_rules_manager_manage` — Manager cùng chi nhánh, có `payroll_adjust` **hoặc** `leave_manage`.
- **Frontend:** cho Manager xem/lưu/bật-tắt quy tắc phạt; **ẩn nút "Tạo phiếu phạt tự động"** (việc đó gắn với kỳ lương do Owner tính).

### 3. Manager thấy "Đăng ký ca: Chưa cài" dù Owner đã cấu hình và đang mở
- `loadRegistrationWindow()` mở đầu bằng `if(profile?.role!=='owner')return;` → Manager thoát ngay, giao diện giữ nguyên chữ mặc định "Chưa cài".
- Nay: Manager có `schedule_manage` **xem được** cấu hình + trạng thái tuần; các nút thao tác (Lưu / Mở đăng ký) **ẩn** với Manager.

### 4. Thưởng +20k đủ 8h/ngày không hiện ở màn lương nhân viên
- Màn "Lương của tôi" chỉ tính `giờ công × đơn giá` từ bảng chấm công, **không hề đọc** `payroll_adjustments` → mọi khoản thưởng/phạt/tạm ứng đều không hiện.
- Nay bổ sung:
  - Truy vấn khoản thưởng/phạt/tạm ứng **của chính nhân viên** trong tháng (RLS `payroll_adjustments_employee_read_own` cho phép).
  - Khối "Thưởng đã duyệt / Phạt đã duyệt / Tạm ứng đã duyệt" + **Thực nhận tạm tính**.
  - Danh sách chi tiết từng khoản (lý do, ngày áp dụng, trạng thái).
- Lưu ý: khoản thưởng đủ giờ **chỉ được tạo thành phiếu khi Owner tính kỳ lương** (`owner_prepare_payroll_bonuses_v1`). Trước thời điểm đó chưa có dòng nào để hiển thị.

---

## V84.44 — Thưởng/phạt hiển thị theo từng ngày (30/10/2026)

**Mục tiêu:** mọi phiếu thưởng (đủ giờ, ngày lễ, thủ công…) và phiếu phạt đều nhìn thấy được **ngay trong lương từng ngày**, cho cả NV — Manager — Owner.

### Nhân viên (`loadEmployeeSalaryMonth`)
- Truy vấn thêm `payroll_adjustments` của chính mình (RLS `payroll_adjustments_employee_read_own`).
- Mỗi ngày hiện chip: `+ Thưởng`, `− Phạt`, `Chờ duyệt`.
- Cột phải = **Thực nhận ngày** = lương công + thưởng − phạt (thay vì chỉ lương công).
- Ngày **chỉ có thưởng/phạt** (không có ca) vẫn hiện trong danh sách.
- Khối tổng: Thưởng/Phạt/Tạm ứng đã duyệt + Thực nhận tạm tính (V84.43).

### Owner / Manager (báo cáo tháng)
- Mỗi ngày hiện thêm dòng thưởng/phạt và **số thực nhận của ngày**; vẫn hiện "công …" để đối chiếu.
- Excel sheet **"Theo ngày"** thêm 3 cột: Thưởng · Phạt · Thực nhận ngày.

### Quy tắc xác định "ngày" của phiếu
`effective_date` → nếu trống thì dùng **ngày tạo phiếu** (`created_at`).
Truy vấn dùng `effective_date` trong khoảng HOẶC (`effective_date` trống VÀ `created_at` trong khoảng) — để phiếu cũ không có ngày áp dụng **không bị rơi khỏi báo cáo**.

### Tài liệu
- Thêm `docs/PAYROLL_WORKFLOW.md`: quy trình lương chuẩn HRM 7 bước, đối chiếu hiện trạng, 5 khoảng trống (P1 phiếu lương NV · P2 chốt công · P3 làm rõ 2 màn báo cáo · P4 Manager xem kỳ · P5 audit lần tính lương).

---

## V84.45 — Hiện người "đã đăng ký, chờ chốt" trong Lịch Quản trị (30/10/2026)

**Hiện tượng:** ca tối Chủ nhật 8/11 có người đăng ký nhưng Lịch trong Quản trị hiện "Trống".

**Nguyên nhân:** `loadAdminSchedule()` chỉ đọc `work_schedules` (+ chấm công), **không đọc `shift_registrations`**. Người đăng ký nhưng chưa được chốt (`pending`) không có `employee_id` trong ca ⇒ ca hiện trống. (Màn Lịch chính của nhân viên/quản lý thì đã hiện — riêng Lịch trong Quản trị thì thiếu.)

**Đã sửa:**
- Tải thêm `shift_registrations` trạng thái `pending` của các ca trong ngày.
- Mỗi ca hiện thêm các dòng người **"Đã đăng ký · chờ chốt"** (kèm giờ đăng ký), phân biệt với người đã được xếp.
- Tiêu đề ca ghi thêm `· N chờ chốt`.
- Thêm ô thống kê **"ĐĂNG KÝ CHỜ CHỐT"** ở đầu lịch ngày.
- Không đổi dữ liệu, không đổi nghiệp vụ.

**Lưu ý nghiệp vụ:** đăng ký ≠ được xếp ca. Ca chỉ có người khi đăng ký được **duyệt** — tự động khi cửa sổ đóng (nếu bật `auto_approve`) hoặc Owner/Manager duyệt tay.

---

## V84.46 — Sửa lỗi "trùng ca" chặn xếp người đã đăng ký (30/10/2026)

**Hiện tượng:** NV đăng ký ca thành công (chờ duyệt) nhưng ca vẫn trống; Owner bấm "Điều chỉnh" thêm chính NV đó vào ca thì báo **"Nhân viên đã có ca trùng giờ"**.

**Nguyên nhân (đọc hàm production `employee_schedule_conflict`):** một ca có nhiều *vị trí* = nhiều dòng `work_schedules` cùng `shift_group_id`. Hàm coi **mọi đăng ký `pending` trùng giờ** là xung đột, chỉ loại trừ đúng 1 `schedule_id`. NV đăng ký vị trí A → Owner xếp vào vị trí B của **cùng ca** → đăng ký chờ ở A bị tính là trùng ⇒ chặn.

**Đã sửa (SQL — V84.46):**
1. `employee_schedule_conflict`: bỏ qua đăng ký chờ nằm **trong cùng `shift_group_id`** với ca đích (đó chính là ca đang xếp người). Các ca khác trùng giờ vẫn bị chặn như cũ.
2. Trigger `trg_confirm_registration_on_assignment`: khi một ca được gán nhân viên, tự chuyển đăng ký chờ của NV đó **trong cùng ca** sang `approved` (có `reviewed_at`, `reviewed_by`) — không còn đăng ký treo.
3. Preflight chốt an toàn: nếu thân hàm trên production đã khác cấu trúc đã biết → **dừng, không thay gì**.

Không đổi dữ liệu; không đổi UI.






