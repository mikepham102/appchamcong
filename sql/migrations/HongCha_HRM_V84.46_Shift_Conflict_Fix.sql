-- HongCha HRM V84.46 — Sửa lỗi "trùng ca" khi xếp người đã đăng ký vào ca
--
-- NGUYÊN NHÂN:
--   Hàm employee_schedule_conflict() coi ĐĂNG KÝ CHỜ (shift_registrations.status='pending')
--   ở BẤT KỲ slot nào trùng giờ là xung đột. Một ca có nhiều "vị trí" = nhiều dòng
--   work_schedules cùng shift_group_id. Nhân viên đăng ký slot A (chờ duyệt);
--   Owner thêm vào slot B của CÙNG ca => hệ thống thấy đăng ký chờ ở slot A
--   => báo TRUNG_CA. Vì vậy ca hiện trống mà không xếp được người.
--
-- SỬA:
--   1) Khi kiểm tra xung đột, bỏ qua đăng ký chờ nằm TRONG CÙNG shift_group_id
--      với ca đích (đó chính là ca đang xếp người). Các trường hợp khác giữ nguyên.
--   2) Thêm trigger: khi một ca được gán nhân viên, tự chuyển đăng ký chờ của
--      nhân viên đó trong cùng ca sang 'approved' để dữ liệu không còn treo.

BEGIN;

DO $preflight$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.employee_schedule_conflict(uuid,timestamp with time zone,timestamp with time zone,uuid)') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING: employee_schedule_conflict';
  END IF;
  IF to_regclass('public.work_schedules') IS NULL
     OR to_regclass('public.shift_registrations') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING';
  END IF;
  -- Chốt an toàn: chỉ thay khi bản đang chạy đúng cấu trúc đã biết.
  SELECT p.prosrc INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname='public' AND p.proname='employee_schedule_conflict';
  IF v_src IS NULL
     OR position('shift_registrations' in v_src) = 0
     OR position('pending' in v_src) = 0 THEN
    RAISE EXCEPTION 'UNEXPECTED_FUNCTION_BODY: employee_schedule_conflict da thay doi, dung lai';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.employee_schedule_conflict(
  p_employee_id uuid,
  p_start_at timestamp with time zone,
  p_end_at timestamp with time zone,
  p_exclude_schedule_id uuid DEFAULT NULL::uuid
) RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_group uuid;
begin
  -- Nhóm ca của ca đích: mọi slot cùng shift_group_id là CÙNG một ca làm việc.
  if p_exclude_schedule_id is not null then
    select s.shift_group_id into v_group
    from public.work_schedules s
    where s.id = p_exclude_schedule_id;
  end if;

  return (
    -- 1) Đã được xếp vào ca khác trùng giờ
    select s.id
    from public.work_schedules s
    where s.employee_id = p_employee_id
      and s.id is distinct from p_exclude_schedule_id
      and s.status in ('open','assigned')
      and s.start_at < p_end_at
      and s.end_at > p_start_at

    union all

    -- 2) Đang có đăng ký CHỜ ở ca khác trùng giờ (bỏ qua đăng ký trong cùng ca đích)
    select s.id
    from public.work_schedules s
    join public.shift_registrations r on r.schedule_id = s.id
    where r.employee_id = p_employee_id
      and r.status = 'pending'
      and s.status = 'open'
      and s.start_at < p_end_at
      and s.end_at > p_start_at
      and s.id is distinct from p_exclude_schedule_id
      and (v_group is null or s.shift_group_id is distinct from v_group)

    limit 1
  );
end;
$function$;

-- 2) Tự chốt đăng ký chờ khi nhân viên được gán vào ca
CREATE OR REPLACE FUNCTION public.confirm_registration_on_assignment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  if new.employee_id is null or new.shift_group_id is null then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.employee_id is not distinct from new.employee_id then
    return new;
  end if;

  update public.shift_registrations r
  set status = 'approved',
      reviewed_at = now(),
      reviewed_by = auth.uid(),
      rejection_reason = null,
      updated_at = now()
  where r.employee_id = new.employee_id
    and r.status = 'pending'
    and exists (
      select 1 from public.work_schedules s
      where s.id = r.schedule_id
        and s.shift_group_id = new.shift_group_id
    );

  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_confirm_registration_on_assignment ON public.work_schedules;
CREATE TRIGGER trg_confirm_registration_on_assignment
AFTER INSERT OR UPDATE OF employee_id ON public.work_schedules
FOR EACH ROW EXECUTE FUNCTION public.confirm_registration_on_assignment();

COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY
-- ---------------------------------------------------------------------------
select p.proname,
       position('v_group' in coalesce(p.prosrc,'')) > 0 as da_ap_dung
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'employee_schedule_conflict';
