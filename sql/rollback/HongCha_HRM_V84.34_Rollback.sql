-- HongCha HRM — ROLLBACK V84.34 (quay về trước khi thêm 4 quyền vận hành)
-- CHỈ chạy khi V84.34 gây lỗi và cần quay lui ngay.
-- Nguồn: sql/snapshots/premig_v84.34_2026-10-30.csv (chụp trực tiếp từ production
-- ngay trước khi chạy migration) => khôi phục CHÍNH XÁC trạng thái cũ.
-- Không xóa dữ liệu nghiệp vụ. Các dòng manager_permissions mới để nguyên
-- (code cũ bỏ qua khoá lạ, không ảnh hưởng vận hành).

BEGIN;

CREATE OR REPLACE FUNCTION public.owner_save_manager_permissions_v2(p_permissions jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
 SET row_security TO 'off'
AS $function$
DECLARE
  v_store uuid;
BEGIN
  IF public.my_role() <> 'owner' THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT p.store_id
  INTO v_store
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.employment_status = 'active';

  IF v_store IS NULL THEN
    RAISE EXCEPTION 'STORE_NOT_FOUND';
  END IF;

  IF p_permissions IS NULL OR jsonb_typeof(p_permissions) <> 'array' THEN
    RAISE EXCEPTION 'QUYEN_KHONG_HOP_LE';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM jsonb_array_elements(p_permissions) AS item(value)
    WHERE jsonb_typeof(item.value->'permission_key') IS DISTINCT FROM 'string'
       OR jsonb_typeof(item.value->'enabled') IS DISTINCT FROM 'boolean'
       OR item.value->>'permission_key' NOT IN (
         'attendance_process',
         'schedule_manage',
         'shift_registration',
         'leave_manage',
         'employee_basic',
         'employee_create',
         'audit_view',
         'payroll_view'
       )
  ) THEN
    RAISE EXCEPTION 'QUYEN_KHONG_HOP_LE';
  END IF;

  IF EXISTS (
    SELECT item.value->>'permission_key'
    FROM jsonb_array_elements(p_permissions) AS item(value)
    GROUP BY item.value->>'permission_key'
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION 'QUYEN_BI_TRUNG';
  END IF;

  INSERT INTO public.manager_permissions AS mp (store_id, permission_key, enabled)
  SELECT
    v_store,
    permissions.permission_key,
    permissions.enabled
  FROM jsonb_to_recordset(p_permissions)
    AS permissions(permission_key text, enabled boolean)
  ON CONFLICT (store_id, permission_key)
  DO UPDATE SET enabled = EXCLUDED.enabled;
END;
$function$


CREATE OR REPLACE FUNCTION public.owner_get_manager_permissions()
 RETURNS TABLE(permission_key text, enabled boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare
  v_store uuid;
begin
  if public.my_role() <> 'owner' then
    raise exception 'FORBIDDEN';
  end if;

  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid()
    and p.employment_status = 'active';

  if v_store is null then
    raise exception 'STORE_NOT_FOUND';
  end if;

  insert into public.manager_permissions(store_id, permission_key, enabled)
  select v_store, defaults.permission_key, defaults.enabled
  from (
    values
      ('attendance_process', true),
      ('schedule_manage', true),
      ('shift_registration', true),
      ('leave_manage', true),
      ('employee_basic', true),
      ('employee_create', false),
      ('audit_view', true),
      ('payroll_view', false)
  ) as defaults(permission_key, enabled)
  on conflict (store_id, permission_key) do nothing;

  return query
  select mp.permission_key, mp.enabled
  from public.manager_permissions mp
  where mp.store_id = v_store
  order by mp.permission_key;
end;
$function$


CREATE OR REPLACE FUNCTION public.enforce_manager_business_permission()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_permission text;
begin
  if auth.uid() is null then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if not exists(
    select 1 from public.profiles
    where id=auth.uid() and role='manager' and employment_status='active'
  ) then
    if tg_op='DELETE' then return old; end if;
    return new;
  end if;

  if tg_table_name='profiles' then
    if tg_op<>'UPDATE' or old.id is distinct from auth.uid() then
      raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
    end if;
    if (to_jsonb(new)-array['full_name','phone','address','updated_at','store_id'])
       is distinct from
       (to_jsonb(old)-array['full_name','phone','address','updated_at','store_id']) then
      raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
    end if;
    -- V84.31: đổi chi nhánh chỉ hợp lệ khi đã được gán quyền quản lý tại chi nhánh đích.
    if new.store_id is distinct from old.store_id then
      if new.store_id is null
         or not exists (
           select 1 from public.store_memberships m
           where m.user_id = auth.uid()
             and m.store_id = new.store_id
             and m.role = 'manager'::public.user_role
             and m.is_active = true
         ) then
        raise exception 'MANAGER_BRANCH_NOT_ASSIGNED';
      end if;
    end if;
    return new;
  end if;

  v_permission:=case tg_table_name
    when 'attendance' then 'attendance_process'
    when 'attendance_events' then 'attendance_process'
    when 'work_schedules' then 'schedule_manage'
    when 'shift_templates' then 'schedule_manage'
    when 'shift_template_versions' then 'schedule_manage'
    when 'weekly_shift_plan_items' then 'schedule_manage'
    when 'shift_registration_windows' then 'schedule_manage'
    when 'shift_registration_recurring_rules' then 'schedule_manage'
    when 'shift_registrations' then 'shift_registration'
    when 'leave_requests' then 'leave_manage'
    when 'schedule_requests' then 'leave_manage'
    else null
  end;

  if v_permission is null or not public.current_user_has_manager_permission(v_permission) then
    raise exception 'MANAGER_PERMISSION_DENIED';
  end if;

  if tg_op='DELETE' then return old; end if;
  return new;
end;
$function$


CREATE OR REPLACE FUNCTION public.review_attendance_device(p_device_id uuid, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_role text;
  v_store uuid;
  v_device_store uuid;
  v_employee uuid;
  v_status public.device_status;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role is null then raise exception 'FORBIDDEN'; end if;
  if v_role<>'owner' then raise exception 'OWNER_REQUIRED'; end if;

  select d.employee_id,p.store_id,d.status into v_employee,v_device_store,v_status
  from public.devices d
  join public.profiles p on p.id=d.employee_id
  where d.id=p_device_id
  for update;
  if not found then raise exception 'THIET_BI_NOT_FOUND'; end if;
  if v_device_store is distinct from v_store then raise exception 'FORBIDDEN'; end if;

  if lower(p_action)='approve' then
    if v_status<>'pending' then raise exception 'THIET_BI_DA_XU_LY'; end if;
    if exists(select 1 from public.devices where employee_id=v_employee and status='approved' and id<>p_device_id) then
      raise exception 'NHAN_VIEN_DA_CO_THIET_BI_DUOC_DUYET';
    end if;
    update public.devices
    set status='approved',approved_by=auth.uid(),approved_at=now(),rejected_reason=null,revoked_at=null,updated_at=now()
    where id=p_device_id;
  elsif lower(p_action)='reject' then
    if v_status<>'pending' then raise exception 'THIET_BI_DA_XU_LY'; end if;
    update public.devices
    set status='rejected',rejected_reason=nullif(trim(coalesce(p_reason,'Từ chối bởi Owner')), ''),updated_at=now()
    where id=p_device_id;
  elsif lower(p_action)='revoke' then
    if v_status<>'approved' then raise exception 'THIET_BI_CHUA_DUOC_DUYET'; end if;
    update public.devices
    set status='revoked',revoked_at=now(),updated_at=now()
    where id=p_device_id;
  else
    raise exception 'ACTION_KHONG_HOP_LE';
  end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'review_attendance_device','device',p_device_id,
         jsonb_build_object('action',lower(p_action),'reason',nullif(trim(coalesce(p_reason,'')),'')));
  return true;
end;
$function$

-- Gỡ các đối tượng chỉ tồn tại từ V84.34
DROP TRIGGER IF EXISTS trg_guard_manager_payroll_adjust ON public.payroll_adjustments;
DROP FUNCTION IF EXISTS public.guard_manager_payroll_adjust();
DROP FUNCTION IF EXISTS public.manager_update_employee_profile(uuid, text, text, text, text);
DROP FUNCTION IF EXISTS public.manager_update_branch_gps(text, double precision, double precision, integer);

COMMIT;
