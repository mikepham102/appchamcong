-- HongCha HRM — ROLLBACK V84.43
-- Bỏ policy cho Manager trên payroll_penalty_rules (trở lại chỉ Owner như trước).
-- Không đổi dữ liệu, không đụng policy của Owner.

BEGIN;

DROP POLICY IF EXISTS payroll_penalty_rules_manager_manage ON public.payroll_penalty_rules;

COMMIT;
