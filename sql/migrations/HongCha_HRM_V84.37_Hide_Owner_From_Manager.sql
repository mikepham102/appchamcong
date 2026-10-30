-- HongCha HRM V84.37 — Manager KHÔNG được thấy tài khoản Owner
--
-- Vấn đề: policy `profiles_staff_read_branch` cho phép mọi Manager có quyền
-- `employee_basic` đọc MỌI hồ sơ trong chi nhánh, gồm cả tài khoản Owner.
--
-- Sửa: thêm điều kiện — chỉ Owner mới đọc được hồ sơ role = 'owner'.
--       Manager chỉ đọc được hồ sơ nhân viên / manager khác (không phải owner).
--
-- Không đụng dữ liệu. Chỉ thay 1 policy SELECT trên public.profiles.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.profiles') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING: public.profiles';
  END IF;
  IF to_regprocedure('public.is_manager_or_owner()') IS NULL
     OR to_regprocedure('public.is_store_member(uuid)') IS NULL
     OR to_regprocedure('public.current_user_has_manager_permission(text)') IS NULL
     OR to_regprocedure('public.my_role()') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'profiles_staff_read_branch'
  ) THEN
    RAISE EXCEPTION 'POLICY_MISSING: profiles_staff_read_branch';
  END IF;
END;
$preflight$;

DROP POLICY IF EXISTS profiles_staff_read_branch ON public.profiles;

CREATE POLICY profiles_staff_read_branch ON public.profiles
  FOR SELECT
  TO authenticated
  USING (
    public.is_manager_or_owner()
    AND store_id IS NOT NULL
    AND public.is_store_member(store_id)
    AND public.current_user_has_manager_permission('employee_basic'::text)
    AND (public.my_role() = 'owner'::public.user_role OR role <> 'owner'::public.user_role)
  );

COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY
-- ---------------------------------------------------------------------------
select policyname, cmd, qual
from pg_policies
where schemaname = 'public' and tablename = 'profiles'
order by policyname;
