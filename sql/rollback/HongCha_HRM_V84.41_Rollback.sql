-- HongCha HRM — ROLLBACK V84.41
-- Khôi phục nguyên bản 4 hàm (lấy từ production trước V84.41) và bỏ index mới.
-- Không xóa dữ liệu.

BEGIN;

DROP INDEX IF EXISTS public.payroll_adjustments_penalty_store_created_idx;
DROP INDEX IF EXISTS public.payroll_adjustments_penalty_null_origin_idx;
DROP INDEX IF EXISTS public.payroll_adjustments_bonus_null_origin_idx;
DROP INDEX IF EXISTS public.payroll_adjustments_advance_emp_created_idx;

CREATE OR REPLACE FUNCTION public.manager_owner_penalty_context_v85()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET row_security TO 'off'
AS $function$
DECLARE
  v_role text;
  v_store uuid;
  v_periods jsonb;
  v_employees jsonb;
BEGIN
  SELECT p.role::text, p.store_id INTO v_role, v_store
  FROM public.profiles p
  WHERE p.id = auth.uid() AND p.employment_status = 'active';
  IF v_role = 'owner' THEN
    IF v_store IS NULL OR NOT public.is_store_owner(v_store) THEN RAISE EXCEPTION 'FORBIDDEN_BRANCH'; END IF;
  ELSIF v_role = 'manager' THEN
    IF v_store IS NULL OR NOT public.current_user_has_manager_permission('leave_manage') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.start_date DESC), '[]'::jsonb) INTO v_periods
  FROM (
    SELECT pp.id, pp.period_name, pp.start_date, pp.end_date, pp.status
    FROM public.payroll_periods pp
    WHERE pp.store_id = v_store
      AND pp.status IN ('draft'::public.payroll_status, 'review'::public.payroll_status)
    ORDER BY pp.start_date DESC LIMIT 36
  ) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'full_name', e.full_name) ORDER BY e.full_name), '[]'::jsonb)
    INTO v_employees
  FROM public.profiles e
  WHERE e.store_id = v_store AND e.role = 'employee'::public.user_role
    AND e.employment_status IN ('active'::public.employment_status, 'invited'::public.employment_status);
  RETURN jsonb_build_object('store_id', v_store, 'periods', v_periods, 'employees', v_employees);
END;
$function$;

CREATE OR REPLACE FUNCTION public.manager_owner_list_penalties_v85(p_status text DEFAULT 'pending'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(adjustment_id uuid, employee_id uuid, employee_name text, payroll_period_id uuid, period_name text, start_date date, end_date date, amount numeric, reason text, status adjustment_status, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET row_security TO 'off'
AS $function$
DECLARE
  v_role text;
  v_store uuid;
BEGIN
  SELECT p.role::text, p.store_id INTO v_role, v_store
  FROM public.profiles p
  WHERE p.id = auth.uid() AND p.employment_status = 'active';
  IF v_role = 'owner' THEN
    IF v_store IS NULL OR NOT public.is_store_owner(v_store) THEN RAISE EXCEPTION 'FORBIDDEN_BRANCH'; END IF;
  ELSIF v_role = 'manager' THEN
    IF v_store IS NULL OR NOT public.current_user_has_manager_permission('leave_manage') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF lower(coalesce(p_status, '')) NOT IN ('pending', 'approved', 'rejected', 'all') THEN RAISE EXCEPTION 'PENALTY_STATUS_INVALID'; END IF;

  RETURN QUERY
  SELECT a.id, a.employee_id, coalesce(e.full_name, 'Nhân viên')::text,
         a.payroll_period_id, pp.period_name, pp.start_date, pp.end_date,
         a.amount, a.reason, a.status, a.created_at
  FROM public.payroll_adjustments a
  LEFT JOIN public.payroll_periods pp ON pp.id = a.payroll_period_id
  LEFT JOIN public.profiles e ON e.id = a.employee_id
  WHERE a.adjustment_type = 'penalty'::public.adjustment_type
    AND coalesce(a.origin_store_id, pp.store_id) = v_store
    AND (lower(p_status) = 'all' OR a.status::text = lower(p_status))
  ORDER BY a.created_at DESC, a.id DESC
  LIMIT greatest(1, least(coalesce(p_limit, 100), 100))
  OFFSET greatest(coalesce(p_offset, 0), 0);
END;
$function$;

CREATE OR REPLACE FUNCTION public.manager_owner_bonus_context_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET row_security TO 'off'
AS $function$
DECLARE v_role text; v_store uuid; v_employees jsonb; v_day_rule jsonb; v_holidays jsonb;
BEGIN
  SELECT p.role::text,p.store_id INTO v_role,v_store
  FROM public.profiles p WHERE p.id=auth.uid() AND p.employment_status='active';
  IF v_role='owner' THEN
    IF v_store IS NULL OR NOT public.is_store_owner(v_store) THEN RAISE EXCEPTION 'FORBIDDEN_BRANCH'; END IF;
  ELSIF v_role='manager' THEN
    IF v_store IS NULL OR NOT public.current_user_has_manager_permission('leave_manage') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  ELSE RAISE EXCEPTION 'FORBIDDEN'; END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id',e.id,'full_name',e.full_name) ORDER BY e.full_name),'[]'::jsonb)
  INTO v_employees FROM public.profiles e
  WHERE e.store_id=v_store AND e.role='employee'::public.user_role
    AND e.employment_status IN ('active'::public.employment_status,'invited'::public.employment_status);
  SELECT to_jsonb(r) INTO v_day_rule FROM public.payroll_full_day_bonus_rules r WHERE r.store_id=v_store;
  SELECT COALESCE(jsonb_agg(to_jsonb(h) ORDER BY h.start_date DESC,h.label),'[]'::jsonb)
  INTO v_holidays FROM public.payroll_holiday_pay_rules h WHERE h.store_id=v_store;
  RETURN jsonb_build_object('store_id',v_store,'employees',v_employees,
    'full_day_rule',COALESCE(v_day_rule,'null'::jsonb),'holiday_rules',v_holidays);
END;
$function$;

CREATE OR REPLACE FUNCTION public.manager_owner_list_bonus_vouchers_v1(p_status text DEFAULT 'all'::text, p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS TABLE(adjustment_id uuid, employee_id uuid, employee_name text, effective_date date, amount numeric, reason text, status adjustment_status, payroll_period_id uuid, period_name text, source_key text, created_at timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET row_security TO 'off'
AS $function$
DECLARE v_role text; v_store uuid;
BEGIN
  SELECT p.role::text,p.store_id INTO v_role,v_store
  FROM public.profiles p WHERE p.id=auth.uid() AND p.employment_status='active';
  IF v_role='owner' THEN
    IF v_store IS NULL OR NOT public.is_store_owner(v_store) THEN RAISE EXCEPTION 'FORBIDDEN_BRANCH'; END IF;
  ELSIF v_role='manager' THEN
    IF v_store IS NULL OR NOT public.current_user_has_manager_permission('leave_manage') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  ELSE RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF lower(coalesce(p_status,'all')) NOT IN ('all','pending','approved','rejected') THEN RAISE EXCEPTION 'BONUS_STATUS_INVALID'; END IF;
  RETURN QUERY
  SELECT a.id,a.employee_id,COALESCE(e.full_name,'Nhân viên')::text,a.effective_date,
    a.amount,a.reason,a.status,a.payroll_period_id,pp.period_name,a.source_key,a.created_at
  FROM public.payroll_adjustments a
  JOIN public.profiles e ON e.id=a.employee_id
  LEFT JOIN public.payroll_periods pp ON pp.id=a.payroll_period_id
  WHERE a.adjustment_type='bonus'::public.adjustment_type
    AND COALESCE(a.origin_store_id,pp.store_id,e.store_id)=v_store
    AND (lower(coalesce(p_status,'all'))='all' OR a.status::text=lower(p_status))
  ORDER BY a.effective_date DESC,a.created_at DESC,a.id DESC
  LIMIT greatest(1,least(coalesce(p_limit,100),200)) OFFSET greatest(coalesce(p_offset,0),0);
END;
$function$;

COMMIT;
