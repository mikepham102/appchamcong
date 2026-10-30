# Bản đồ dự án — HongCha HRM

Cập nhật: 30/10/2026. Nguồn: `index.html` (bản đang chạy, blob `718c2cba…`) + `sql/snapshots/hongcha_schema.sql` (ảnh chụp DB **13/10**, cũ hơn 5 migration).

## 1. Tổng quan

Ứng dụng quản lý nhân sự / chấm công / lương cho chuỗi quán trà sữa HongCha, dùng tiếng Việt.

| Lớp | Công nghệ |
|---|---|
| Frontend | **1 file `index.html`** (7.235 dòng, vanilla JS, không framework, không bundler) |
| Hosting | GitHub Pages (nhánh `main`, thư mục gốc) |
| Backend | Supabase: Postgres 17 + Auth + RLS + RPC (PostgREST) + Realtime + pg_cron |
| Thư viện ngoài | `@supabase/supabase-js@2` nạp từ jsDelivr lúc chạy (có timeout 5s + thông báo lỗi riêng) |

Đăng nhập: email + mật khẩu, hoặc magic link qua email. Không có backend riêng — **toàn bộ bảo mật dựa trên RLS + hàm RPC `SECURITY DEFINER`**.

## 2. Cấu trúc thư mục

```
index.html                 Ứng dụng (bản duy nhất đang chạy)
manifest.webmanifest       Khai báo PWA
icons/                     4 icon (192, 512, 512-maskable, apple-touch)
sql/migrations/            5 migration đã áp dụng — lịch sử thay đổi DB
sql/audits/                2 script kiểm toán CHỈ ĐỌC (chẩn đoán, không sửa dữ liệu)
sql/snapshots/             Ảnh chụp cấu trúc DB ngày 13/10 (tham chiếu, KHÔNG phải bản chuẩn)
docs/                      CHANGELOG, DEPLOY, PROJECT (file này)
_archive/                  Bản sao lưu cục bộ (không đưa lên GitHub)
```

## 3. Bảy màn hình

| View | Vai trò dùng | Nội dung chính |
|---|---|---|
| `dashboard` | Cả 3 | Trang chủ nhân viên (ca hôm nay, nút chấm công) hoặc tổng quan Owner (nhân sự, việc cần xử lý) |
| `schedule` | Cả 3 | Lịch tuần: xem ca, đăng ký ca, thêm/sửa ca, duyệt yêu cầu |
| `attendance` | Cả 3 | Chấm công (GPS + thiết bị) và bảng chấm công theo ngày cho quản lý |
| `salary` | Cả 3 | Lương: báo cáo kỳ, chi tiết ngày, tạm ứng, phiếu cộng/phạt |
| `admin` | Owner, Manager | Quản trị: nhân viên, yêu cầu hồ sơ, thiết bị, chi nhánh, quyền Manager |
| `profile` | Cả 3 | Hồ sơ cá nhân, ngân hàng, đổi mật khẩu |
| `deviceGate` | Employee | Chặn khi thiết bị chưa được duyệt |

## 4. Vai trò & phân quyền

- `owner` (Chủ quán): toàn quyền trong các chi nhánh mình sở hữu.
- `manager` (Quản lý): quyền theo **từng chi nhánh** qua bảng `manager_permissions` (khóa: `schedule_manage`, `leave_manage`, `payroll_view`, `audit_view`, …). Có thể được gán nhiều chi nhánh và chuyển chi nhánh bằng `switch_active_store`.
- `employee` (Nhân viên): chỉ thấy ca của mình + ca trống của chi nhánh; chấm công phải qua thiết bị đã duyệt + GPS.

**Cơ chế 2 lớp (quan trọng):**
- `store_memberships` = quyền thật (user thuộc chi nhánh nào, vai trò gì).
- `profiles.store_id` = **con trỏ "chi nhánh đang làm việc"**. Nhiều policy và hàm đọc theo cột này → khi Manager chuyển chi nhánh, phạm vi dữ liệu đổi theo.

Theo snapshot 13/10: **25/25 bảng bật RLS**, 59 policy, 96 hàm, 21 trigger, 10 enum.

## 5. Bảng dữ liệu (25)

| Nhóm | Bảng |
|---|---|
| Tổ chức | `stores`, `profiles`, `store_memberships`, `manager_permissions` |
| Lịch & ca | `shift_templates`, `shift_template_versions`, `work_schedules`, `weekly_shift_plan_items`, `schedule_requests`, `shift_registrations`, `shift_registration_windows`, `shift_registration_recurring_rules` |
| Chấm công | `attendance`, `attendance_events`, `devices` |
| Lương | `payroll_periods`, `payroll_runs`, `payroll_run_items`, `payroll_adjustments`, `payroll_penalty_rules`, `employee_salary_versions` |
| Nghỉ phép | `leave_requests` |
| Ngân hàng | `employee_bank_accounts` (**chuẩn**), `employee_bank_details` (**cũ**) |
| Hệ thống | `audit_logs` |

Bảng mới từ V84.29 (chưa có trong snapshot): `employee_profile_change_requests`, `private.platform_admins`.


## 6. Quyết định đã chốt: bảng ngân hàng

**Nguồn chuẩn là `employee_bank_accounts`.** App hiện tại đọc/ghi bảng này ở 7 chỗ (hồ sơ nhân viên, Owner sửa nhân viên, danh sách nhân viên, báo cáo lương để chuyển khoản, luồng duyệt hồ sơ).

`employee_bank_details` là bảng **cũ còn tồn tại**: 4 hàm liên quan (`get_my_bank_details`, `save_my_bank_details`, `owner_get_employee_bank_details`, `owner_save_employee_bank_details`) **không được app gọi lần nào**. Không xóa bảng này cho tới khi xác nhận dữ liệu cũ không cần.

## 7. Luồng nghiệp vụ cốt lõi

1. **Chấm công**: `attendance_punch(action, device_key, lat, lng, accuracy, schedule_id)` — kiểm tra thiết bị đã duyệt → GPS trong bán kính quán → ca thuộc nhân viên → khung giờ check-in/check-out → nghỉ phép đã duyệt → xử lý "bàn giao ca liền kề" → ghi `attendance`. Có advisory lock theo nhân viên (chặn bấm 2 lần).
2. **Đăng ký ca**: Owner mở cửa sổ đăng ký theo tuần (rule lặp lại) → nhân viên đăng ký → Owner duyệt hoặc **pg_cron tự chốt** khi hết hạn (`auto_finalize_due_shift_registrations`), kiểm tra còn chỗ + trùng ca.
3. **Lương**: mức lương theo ngày hiệu lực → chấm công → phiếu phạt/cộng/tạm ứng → `owner_calculate_payroll` → Owner chốt trạng thái kỳ lương.
4. **Thiết bị**: nhân viên xin → Owner duyệt → nhân viên chấm công. Đổi máy/xóa cache trình duyệt = phải xin duyệt lại (khóa thiết bị lưu ở `localStorage`).
5. **Hồ sơ**: hồ sơ đã đầy đủ thì nhân viên không tự sửa được họ tên/SĐT/địa chỉ/ngân hàng — phải tạo yêu cầu, Owner duyệt.

## 8. Vấn đề đã biết (chưa sửa — cần bạn quyết định)

| # | Vấn đề | Mức độ | Ghi chú |
|---|---|---|---|
| 1 | Snapshot DB (`sql/snapshots/`) cũ hơn 5 migration | Cao | Cần ảnh chụp mới trước khi sửa DB |
| 2 | Job `pg_cron` không nằm trong snapshot | Cao | Nếu job không tồn tại, tự chốt đăng ký ca sẽ không chạy. Cần kiểm tra `cron.job` (chỉ đọc) |
| 3 | Không có môi trường staging | Cao | Mọi thử nghiệm đang chạm dữ liệu thật |
| 4 | Vài policy cũ so sánh trực tiếp `store_id = profiles.store_id` trong khi mô hình mới dùng `store_memberships` | Trung bình | Xem `schedules_employee_select_v21`, `manager_permissions_manager_read`, `weekly_shift_plan_insert` |
| 5 | Frontend ghi trực tiếp bảng (`profiles`, `stores`, `payroll_penalty_rules`, `employee_bank_accounts`) thay vì RPC | Trung bình | Không có `audit_logs` cho các thay đổi này |
| 6 | CSS lỗi cú pháp: thừa 1 dấu `}` cuối rule `.app-brand-center .brand-mark` (dòng 977) | Thấp | Trình duyệt bỏ qua; chỉ là lỗi cú pháp |
| 7 | Realtime subscribe 7 bảng không lọc theo `store_id` | Thấp | Tăng tải khi nhiều chi nhánh online |
| 8 | Không có log tập trung | Trung bình | Chỉ có `console.error` trên máy người dùng |

## 9. Bảo mật

- Frontend chứa Supabase URL + `sb_publishable_…` (khóa công khai, ai cũng thấy được) → **an toàn phụ thuộc 100% vào RLS**.
- Kiểm tra ngày 30/10: 25/25 bảng bật RLS; bảng mới `employee_profile_change_requests` đã bật RLS + thu hồi quyền ghi + chỉ cho đọc của mình hoặc Owner. Tốt.
- `private.platform_admins` không cấp quyền nào cho `anon`/`authenticated`.

## 10. Việc nên làm tiếp (theo thứ tự)

1. Ảnh chụp DB mới + kiểm tra `cron.job` (chỉ đọc) — không đổi gì.
2. Bộ test tay theo 3 vai trò + các luồng ở mục 7.
3. Dựng bản sao Supabase (staging) để thử migration an toàn.
4. Rà policy theo mô hình đa chi nhánh (mục 8.4).
5. Sửa lỗi CSS (mục 8.6) — gộp vào lần phát hành frontend tiếp theo.
