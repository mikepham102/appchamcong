-- HongCha HRM — ROLLBACK V84.46
-- Khôi phục employee_schedule_conflict như trước và bỏ trigger tự chốt đăng ký.
-- Không đổi dữ liệu.

BEGIN;

DROP TRIGGER IF EXISTS trg_confirm_registration_on_assignment ON public.work_schedules;
DROP FUNCTION IF EXISTS public.confirm_registration_on_assignment();

CREATE OR REPLACE FUNCTION public.employee_schedule_conflict(
  p_employee_id uuid,
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone,
  p_exclude_schedule_id uuid DEFAULT NULL::uuid
) RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  select s.id
  from public.work_schedules s
  where s.employee_id = p_employee_id
    and s.id is distinct from p_exclude_schedule_id
    and s.status in ('open','assigned')
    and s.start_at < p_end_at
    and s.end_at > p_start_at
  union all
  select s.id
  from public.work_schedules s
  join public.shift_registrations r on r.schedule_id = s.id
  where r.employee_id = p_employee_id
    and r.status = 'pending'
    and s.id is distinct from p_exclude_schedule_id
    and s.status = 'open'
    and s.start_at < p_end_at
    and s.end_at > p_start_at
  limit 1;
$function$;

COMMIT;
