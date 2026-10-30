# SQL — HongCha HRM

Database đang chạy thật. Đọc `docs/DEPLOY.md` mục 5 trước khi chạy bất kỳ file nào.

## migrations/ — thứ tự áp dụng (đã chạy trên production)

| # | File | Nội dung |
|---|---|---|
| 1 | `HongCha_HRM_V84.29_Device_Cleanup_Migration.sql` | Hàm Owner xóa thiết bị chấm công đã thu hồi (chặn nếu có lịch sử chấm công) |
| 2 | `HongCha_HRM_V84.29_Employee_Profile_Approval_Migration.sql` | Bảng + trigger + RPC duyệt yêu cầu sửa hồ sơ nhân viên |
| 3 | `HongCha_HRM_Multi_Branch_Manager_Access_Migration.sql` | Manager đa chi nhánh, `switch_active_store`, `owner_set_manager_branches`, schema `private` |
| 4 | `HongCha_HRM_V84.30_Shift_Registration_Auto_Finalize_Fix.sql` | Sửa hàm tự chốt đăng ký ca (đọc UUID scalar) |

Thứ tự 1→2→3→4 là thứ tự đã áp dụng theo thời gian (15/10 → 18/10). Cả 4 file đều **additive** và có `BEGIN/COMMIT` + block `preflight`.

## audits/ — chỉ đọc, an toàn để chạy bất cứ lúc nào

- `HongCha_HRM_Schema_Snapshot_ReadOnly.sql` — **chụp cấu trúc DB hiện tại** (bảng, cột, khóa, index, policy, hàm, trigger, quyền, enum, realtime). Chạy 1 lần trong SQL Editor → Download CSV → lưu `sql/snapshots/schema_<ngày>.csv`.
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
