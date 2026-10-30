-- HongCha HRM — ẢNH CHỤP TRƯỚC KHI CHẠY MIGRATION V84.31 (CHỈ ĐỌC)
--
-- Dùng khi KHÔNG có backup (gói Supabase Free không có backup tự động).
-- Script này trả về đúng 2 thứ cần thiết để quay lui / đối chiếu:
--   1. Số dòng của từng bảng (chỉ ĐẾM, không đọc nội dung)
--   2. Định nghĩa hiện tại của 4 hàm sắp bị thay (để khôi phục nếu cần)
--
-- CÁCH DÙNG
--   1. Supabase → SQL Editor → dán toàn bộ → Run
--   2. Bấm Download → CSV → lưu thành:
--        sql/snapshots/premig_v84.31_<ngày>.csv
--   3. Chạy migration V84.31
--   4. Chạy LẠI script này → lưu thành premig_v84.31_<ngày>_after.csv
--   5. So 2 file: số dòng từng bảng phải GIỐNG HỆT.
--
-- An toàn: chỉ SELECT catalog + COUNT(*). Không trả về tên, lương, số tài khoản.

with counts as (
  select '01_rowcount'::text as section,
         n.nspname || '.' || c.relname as object_name,
         (xpath('/row/cnt/text()',
                query_to_xml(format('select count(*) as cnt from %I.%I', n.nspname, c.relname),
                             false, true, '')))[1]::text as detail
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  where n.nspname = 'public'
    and c.relkind = 'r'
),
funcs as (
  select '02_function_def'::text as section,
         n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' as object_name,
         pg_get_functiondef(p.oid) as detail
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname in (
      'current_user_has_manager_permission',
      'get_my_manager_permissions',
      'switch_active_store',
      'enforce_manager_business_permission',
      'owner_set_manager_branches'
    )
)
select section, object_name, detail from counts
union all
select section, object_name, detail from funcs
order by section, object_name;
