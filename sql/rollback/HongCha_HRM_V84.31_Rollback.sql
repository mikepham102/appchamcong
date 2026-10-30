-- HongCha HRM — ROLLBACK V84.31 (quay về trạng thái trước migration đa chi nhánh)
-- CHỈ chạy khi V84.31 gây lỗi và cần quay lui ngay.
-- Khôi phục 4 hàm về đúng định nghĩa đang chạy trước 30/10/2026.
-- Không xóa dữ liệu nghiệp vụ. Bảng private.platform_admins để nguyên.

BEGIN;

CREATE OR REPLACE FUNCTION public.current_user_has_manager_permission(p_permission_key text) RETURNS boolean
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_enabled boolean;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role='owner' then return true; end if;
  if v_role<>'manager' or v_store is null then return false; end if;
  select enabled into v_enabled
  from public.manager_permissions
  where store_id=v_store and permission_key=p_permission_key;
  return coalesce(v_enabled,false);
end;
$$;

CREATE OR REPLACE FUNCTION public.get_my_manager_permissions() RETURNS TABLE(permission_key text, enabled boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_role text; v_store uuid;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'manager' then raise exception 'FORBIDDEN'; end if;
  return query
  select mp.permission_key,mp.enabled
  from public.manager_permissions mp
  where mp.store_id=v_store
  order by mp.permission_key;
end;
$$;

CREATE OR REPLACE FUNCTION public.switch_active_store(p_store_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_store public.stores%rowtype;
  v_role text;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
  select role::text into v_role from public.profiles where id=v_uid and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;

  select s.* into v_store
  from public.stores s
  where s.id=p_store_id
    and public.is_store_owner(s.id);
  if not found then raise exception 'FORBIDDEN'; end if;

  update public.profiles
  set store_id=v_store.id,updated_at=now()
  where id=v_uid;

  return jsonb_build_object('id',v_store.id,'name',v_store.name,'address',v_store.address);
end;
$$;

CREATE OR REPLACE FUNCTION public.enforce_manager_business_permission() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
    if (to_jsonb(new)-array['full_name','phone','address','updated_at'])
       is distinct from
       (to_jsonb(old)-array['full_name','phone','address','updated_at']) then
      raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
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
$$;
-- Gỡ hàm mới (chỉ tồn tại từ V84.31)
DROP FUNCTION IF EXISTS public.owner_set_manager_branches(uuid, uuid[]);

COMMIT;
