-- HongCha HRM V84.43 — Manager được cấu hình quy tắc phạt tự động
--
-- Hiện trạng: policy duy nhất trên payroll_penalty_rules là owner-only
--   payroll_penalty_rules_owner_manage_branch USING (is_owner() AND is_store_owner(store_id))
-- => Manager đọc/ghi đều bị chặn, màn "Quản lý phạt" không hiện phần cấu hình.
--
-- Sửa: thêm policy cho Manager CÙNG CHI NHÁNH khi có quyền payroll_adjust
--       (hoặc leave_manage để tương thích cấu hình cũ).
-- Không sửa policy của Owner. Không đổi dữ liệu.
-- Lưu ý: chỉ cấu hình quy tắc. Việc TẠO phiếu phạt tự động vẫn gắn với kỳ lương
--        do Owner tính (RPC owner_generate_payroll_penalties giữ nguyên owner-only).

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.payroll_penalty_rules') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING: public.payroll_penalty_rules';
  END IF;
  IF to_regprocedure('public.is_manager_or_owner()') IS NULL
     OR to_regprocedure('public.is_store_member(uuid)') IS NULL
     OR to_regprocedure('public.current_user_has_manager_permission(text)') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING';
  END IF;
END;
$preflight$;

DROP POLICY IF EXISTS payroll_penalty_rules_manager_manage ON public.payroll_penalty_rules;

CREATE POLICY payroll_penalty_rules_manager_manage ON public.payroll_penalty_rules
  FOR ALL
  TO authenticated
  USING (
    public.is_manager_or_owner()
    AND public.is_store_member(store_id)
    AND (
      public.current_user_has_manager_permission('payroll_adjust'::text)
      OR public.current_user_has_manager_permission('leave_manage'::text)
    )
  )
  WITH CHECK (
    public.is_manager_or_owner()
    AND public.is_store_member(store_id)
    AND (
      public.current_user_has_manager_permission('payroll_adjust'::text)
      OR public.current_user_has_manager_permission('leave_manage'::text)
    )
  );

COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY
-- ---------------------------------------------------------------------------
select policyname, cmd, roles
from pg_policies
where schemaname = 'public' and tablename = 'payroll_penalty_rules'
order by policyname;
