-- HongCha HRM — ẢNH CHỤP CẤU TRÚC DATABASE (CHỈ ĐỌC)
-- Mục đích: lấy đúng cấu trúc DB hiện tại (bảng, cột, khóa, index, policy, hàm, trigger, quyền).
-- An toàn: KHÔNG đọc dữ liệu nghiệp vụ, KHÔNG tạo/sửa/xóa bất kỳ đối tượng nào.
--
-- CÁCH DÙNG
--   1. Supabase Dashboard -> SQL Editor -> dán toàn bộ file này -> Run.
--   2. Kết quả là 1 bảng 3 cột (section, object_name, detail).
--   3. Bấm "Download" -> chọn CSV -> lưu vào thư mục dự án với tên:
--        sql/snapshots/schema_<ngày>.csv     ví dụ: sql/snapshots/schema_2026-10-30.csv
--
-- Ghi chú: chạy trên project production chỉ ĐỌC catalog PostgreSQL.

WITH rows AS (

  -- 01. Bảng / view / materialized view + trạng thái RLS
  SELECT '01_table'::text AS section,
         n.nspname || '.' || c.relname AS object_name,
         'kind=' || c.relkind::text ||
         '; rls=' || c.relrowsecurity::text ||
         '; force_rls=' || c.relforcerowsecurity::text AS detail
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname IN ('public', 'private')
    AND c.relkind IN ('r', 'p', 'v', 'm')

  UNION ALL

  -- 02. Cột: kiểu dữ liệu, null, default
  SELECT '02_column',
         c.table_schema || '.' || c.table_name,
         c.column_name || ' ' || c.data_type ||
         CASE WHEN c.data_type = 'USER-DEFINED' THEN ' (' || c.udt_name || ')' ELSE '' END ||
         '; null=' || c.is_nullable ||
         '; default=' || coalesce(c.column_default, '-')
  FROM information_schema.columns c
  WHERE c.table_schema IN ('public', 'private')

  UNION ALL

  -- 03. Khóa chính / khóa ngoại / check / unique
  SELECT '03_constraint',
         con.conrelid::regclass::text || '.' || con.conname,
         pg_get_constraintdef(con.oid)
  FROM pg_constraint con
  JOIN pg_class cl ON cl.oid = con.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname IN ('public', 'private')

  UNION ALL

  -- 04. Index
  SELECT '04_index',
         schemaname || '.' || tablename || '.' || indexname,
         indexdef
  FROM pg_indexes
  WHERE schemaname IN ('public', 'private')

  UNION ALL

  -- 05. Row Level Security policy
  SELECT '05_policy',
         schemaname || '.' || tablename || '.' || policyname,
         'cmd=' || cmd ||
         '; roles=' || array_to_string(roles, ',') ||
         '; using=' || coalesce(qual, '-') ||
         '; check=' || coalesce(with_check, '-')
  FROM pg_policies
  WHERE schemaname IN ('public', 'private')

  UNION ALL

  -- 06. Danh sách hàm (chữ ký + thuộc tính bảo mật)
  SELECT '06_function',
         n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         'returns=' || pg_get_function_result(p.oid) ||
         '; security_definer=' || p.prosecdef::text ||
         '; volatility=' || p.provolatile::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname IN ('public', 'private')

  UNION ALL

  -- 07. Trigger
  SELECT '07_trigger',
         n.nspname || '.' || c.relname || '.' || t.tgname,
         pg_get_triggerdef(t.oid)
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE NOT t.tgisinternal
    AND n.nspname IN ('public', 'private')

  UNION ALL

  -- 08. Enum
  SELECT '08_enum',
         t.typname,
         e.enumlabel
  FROM pg_type t
  JOIN pg_enum e ON e.enumtypid = t.oid
  JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public'

  UNION ALL

  -- 09. Quyền trên bảng (ai được SELECT/INSERT/UPDATE/DELETE)
  SELECT '09_table_grant',
         table_schema || '.' || table_name,
         grantee || ':' || privilege_type
  FROM information_schema.role_table_grants
  WHERE table_schema IN ('public', 'private')

  UNION ALL

  -- 10. Quyền thực thi hàm
  SELECT '10_function_grant',
         routine_schema || '.' || routine_name,
         grantee || ':' || privilege_type
  FROM information_schema.role_routine_grants
  WHERE routine_schema IN ('public', 'private')

  UNION ALL

  -- 11. Extension đang bật
  SELECT '11_extension',
         extname,
         extversion
  FROM pg_extension

  UNION ALL

  -- 12. Bảng đang bật Realtime
  SELECT '12_realtime_table',
         schemaname || '.' || tablename,
         'published'
  FROM pg_publication_tables
  WHERE pubname = 'supabase_realtime'
)
SELECT section, object_name, detail
FROM rows
ORDER BY section, object_name;
