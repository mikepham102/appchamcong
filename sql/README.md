# SQL — HongCha HRM

Database đang chạy thật. Đọc `docs/DEPLOY.md` mục 5 trước khi chạy bất kỳ file nào.

## migrations/ — thứ tự áp dụng (đã chạy trên production)

| # | File | Nội dung |
|---|---|---|
| 1 | `HongCha_HRM_V84.29_Device_Cleanup_Migration.sql` | Hàm Owner xóa thiết bị chấm công đã thu hồi (chặn nếu có lịch sử chấm công) |
| 2 | `HongCha_HRM_V84.29_Employee_Profile_Approval_Migration.sql` | Bảng + trigger + RPC duyệt yêu cầu sửa hồ sơ nhân viên |
| 3 | `HongCha_HRM_Multi_Branch_Manager_Access_Migration.sql` | **BẢN GỐC — KHÔNG dùng để chạy**. Chỉ giữ làm lịch sử. Thiếu phần vá trigger nên Manager vẫn không chuyển chi nhánh được |
| 4 | `HongCha_HRM_V84.30_Shift_Registration_Auto_Finalize_Fix.sql` | Sửa hàm tự chốt đăng ký ca (đọc UUID scalar) — **đã áp dụng** trên production |
| 5 | `HongCha_HRM_V84.31_MultiBranch_Manager_Access_Apply.sql` | **BẢN ÁP DỤNG CHÍNH THỨC** cho đa chi nhánh: nội dung file 3 + vá trigger `enforce_manager_business_permission` + chốt an toàn không khóa quyền Manager |
| 6 | `HongCha_HRM_V84.34_Manager_P2_Permissions.sql` | 4 quyền vận hành mới cho Manager (`employee_edit`, `device_manage`, `payroll_adjust`, `branch_gps`) + RPC mới + trigger chặn phiếu phạt/cộng |
| 7 | `HongCha_HRM_V84.37_Hide_Owner_From_Manager.sql` | Manager không đọc được hồ sơ tài khoản Owner (sửa policy `profiles_staff_read_branch`) |
| 8 | `HongCha_HRM_V84.40_Attendance_Rounding.sql` | Làm tròn phút khi chấm công: vào làm tròn LÊN, ra làm tròn XUỐNG; giờ công/trễ/về sớm tính theo giờ đã làm tròn |
| 9 | `HongCha_HRM_V84.41_Finance_RPC_Index.sql` | Tăng tốc Phiếu phạt / Phiếu cộng / Ứng lương: bỏ `coalesce()` trong điều kiện lọc để dùng được index + thêm 4 index; Manager dùng `payroll_adjust` **hoặc** `leave_manage` |
| 10 | `HongCha_HRM_V84.43_Manager_Penalty_Rules.sql` | Manager được cấu hình quy tắc phạt tự động (policy `payroll_penalty_rules_manager_manage`) |
| 10 |  | Manager được cấu hình quy tắc phạt tự động (policy ) |

Thứ tự 1→2→3→4 là thứ tự đã áp dụng theo thời gian (15/10 → 18/10). Cả 4 file đều **additive** và có `BEGIN/COMMIT` + block `preflight`.

## audits/ — chỉ đọc, an toàn để chạy bất cứ lúc nào

- `HongCha_HRM_Schema_Snapshot_ReadOnly.sql` — **chụp cấu trúc DB hiện tại** (bảng, cột, khóa, index, policy, hàm, trigger, quyền, enum, realtime). Chạy 1 lần trong SQL Editor → Download CSV → lưu `sql/snapshots/schema_<ngày>.csv`.
- `HongCha_HRM_PreMigration_Snapshot_ReadOnly.sql` — **trước mỗi lần chạy migration**: số dòng từng bảng + định nghĩa các hàm sắp bị thay (dùng thay cho backup khi dùng gói Free).
- `HongCha_HRM_Runtime_Checks_ReadOnly.sql` — kiểm tra cron job, phiên bản hàm `switch_active_store` / `auto_finalize_due_shift_registrations`.
- `HongCha_HRM_MultiBranch_Safety_Preflight_ReadOnly.sql` — đếm mức độ an toàn trước khi chạy migration đa chi nhánh.
- `HongCha_HRM_Multi_Branch_Audit_ReadOnly.sql` — kiểm kê cột / enum / RLS / policy / hàm.
- `HongCha_HRM_Multi_Branch_Audit_Details_ReadOnly.sql` — bản chi tiết (định nghĩa hàm, constraint, toàn bộ policy).

Chỉ đọc catalog PostgreSQL. Không đọc dữ liệu nghiệp vụ, không sửa gì.

## snapshots/ — ảnh chụp cấu trúc

- `hongcha_schema.sql` — dump ngày 13/10/2026 (PostgreSQL 17.6).
  **Cũ hơn 4 migration ở trên** → dùng để tham chiếu/so sánh, **không** dùng làm bản chuẩn của DB hiện tại.
  Để có ảnh chụp mới: Supabase → Database → Backups/Dump, hoặc `pg_dump --schema-only`.

## Quy ước đặt tên file mới

```
HongCha_HRM_V<major>.<minor>_<Mô_Tả_Ngắn>.sql
```
Ví dụ: `HongCha_HRM_V84.31_Payroll_Export_Fix.sql`
