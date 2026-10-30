-- HongCha HRM V84.34 — P2: 4 quyền vận hành mới cho Manager
--
-- Thêm 4 khoá quyền (mặc định BẬT cho mọi chi nhánh hiện có):
--   employee_edit   : Manager sửa họ tên / SĐT / địa chỉ / trạng thái nhân viên
--   device_manage   : Manager duyệt / từ chối / thu hồi thiết bị chấm công
--   payroll_adjust  : Manager tạo & duyệt phiếu phạt / cộng / tạm ứng
--   branch_gps      : Manager sửa địa chỉ + GPS + bán kính của chi nhánh mình
--
-- KHÔNG thay đổi: đặt mức lương, sửa STK ngân hàng, tính/chốt kỳ lương,
-- tạo/xóa chi nhánh, phân quyền, chuyển nhân viên giữa chi nhánh — vẫn chỉ Owner.
--
-- An toàn: chỉ CREATE OR REPLACE FUNCTION (code), thêm dòng cấu hình quyền,
-- thêm trigger mới. Không UPDATE/DELETE dữ liệu nghiệp vụ.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.manager_permissions') IS NULL
     OR to_regclass('public.profiles') IS NULL
     OR to_regclass('public.store_memberships') IS NULL
     OR to_regclass('public.stores') IS NULL
     OR to_regclass('public.devices') IS NULL
     OR to_regclass('public.payroll_adjustments') IS NULL
     OR to_regclass('public.audit_logs') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING: manager_permissions/profiles/store_memberships/stores/devices/payroll_adjustments/audit_logs';
  END IF;

  IF to_regprocedure('public.owner_save_manager_permissions_v2(jsonb)') IS NULL
     OR to_regprocedure('public.owner_get_manager_permissions()') IS NULL
     OR to_regprocedure('public.enforce_manager_business_permission()') IS NULL
     OR to_regprocedure('public.review_attendance_device(uuid,text,text)') IS NULL
     OR to_regprocedure('public.current_user_has_manager_permission(text)') IS NULL
     OR to_regprocedure('public.my_role()') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING';
  END IF;
END;
$preflight$;

-- 1) Bật 4 quyền mới cho mọi chi nhánh đang có (không ghi đè cấu hình cũ)
INSERT INTO public.manager_permissions (store_id, permission_key, enabled)
SELECT s.id, d.permission_key, d.enabled
FROM public.stores s
CROSS JOIN (
  VALUES
    ('employee_edit',  true),
    ('device_manage',  true),
    ('payroll_adjust', true),
    ('branch_gps',     true)
) AS d(permission_key, enabled)
ON CONFLICT (store_id, permission_key) DO NOTHING;

-- 2) owner_save_manager_permissions_v2 — chấp nhận 12 khoá quyền
CREATE OR REPLACE FUNCTION public.owner_save_manager_permissions_v2(p_permissions jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
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
         'employee_edit',
         'device_manage',
         'payroll_adjust',
         'branch_gps',
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
$function$;

-- 3) owner_get_manager_permissions — bổ sung 4 quyền mới vào bộ mặc định
CREATE OR REPLACE FUNCTION public.owner_get_manager_permissions()
RETURNS TABLE(permission_key text, enabled boolean)
LANGUAGE plpgsql SECURITY DEFINER
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
      ('employee_edit', true),
      ('device_manage', true),
      ('payroll_adjust', true),
      ('branch_gps', true),
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
$function$;

-- 4) enforce_manager_business_permission — thêm nhánh "Manager sửa hồ sơ nhân viên"
CREATE OR REPLACE FUNCTION public.enforce_manager_business_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_permission text;
  v_my_store uuid;
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

  select p.store_id into v_my_store
  from public.profiles p
  where p.id = auth.uid();

  if tg_table_name='profiles' then
    if tg_op <> 'UPDATE' then
      raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
    end if;

    -- (a) Manager tự sửa hồ sơ của chính mình
    if old.id = auth.uid() then
      if (to_jsonb(new)-array['full_name','phone','address','updated_at','store_id'])
         is distinct from
         (to_jsonb(old)-array['full_name','phone','address','updated_at','store_id']) then
        raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
      end if;
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

    -- (b) Manager sửa hồ sơ NHÂN VIÊN cùng chi nhánh đang làm (cần quyền employee_edit).
    --     Chỉ được đổi: họ tên, SĐT, địa chỉ, trạng thái làm việc.
    if old.role = 'employee'::public.user_role
       and new.role = 'employee'::public.user_role
       and old.store_id is not null
       and old.store_id = v_my_store
       and new.store_id is not distinct from old.store_id
       and public.current_user_has_manager_permission('employee_edit')
       and (to_jsonb(new)-array['full_name','phone','address','employment_status','updated_at'])
           is not distinct from
           (to_jsonb(old)-array['full_name','phone','address','employment_status','updated_at']) then
      return new;
    end if;

    raise exception 'MANAGER_PROFILE_FIELD_FORBIDDEN';
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
$function$;

-- 5) Manager sửa hồ sơ nhân viên (họ tên, SĐT, địa chỉ, trạng thái làm việc)
CREATE OR REPLACE FUNCTION public.manager_update_employee_profile(
  p_employee_id uuid,
  p_full_name text,
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_employment_status text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_store uuid;
  v_target_store uuid;
  v_target_role public.user_role;
  v_new_status public.employment_status;
begin
  if public.my_role() <> 'manager' then raise exception 'FORBIDDEN'; end if;
  if not public.current_user_has_manager_permission('employee_edit') then
    raise exception 'MANAGER_PERMISSION_DENIED';
  end if;

  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid() and p.employment_status = 'active';
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;

  select p.store_id, p.role, p.employment_status
    into v_target_store, v_target_role, v_new_status
  from public.profiles p
  where p.id = p_employee_id
  for update;

  if not found or v_target_store is distinct from v_store or v_target_role <> 'employee' then
    raise exception 'FORBIDDEN';
  end if;

  if length(trim(coalesce(p_full_name, ''))) = 0 then raise exception 'THIEU_HO_TEN'; end if;

  if p_employment_status is not null then
    if p_employment_status not in ('active', 'inactive', 'terminated') then
      raise exception 'TRANG_THAI_KHONG_HOP_LE';
    end if;
    v_new_status := p_employment_status::public.employment_status;
  end if;

  update public.profiles
  set full_name = trim(p_full_name),
      phone = nullif(trim(coalesce(p_phone, '')), ''),
      address = nullif(trim(coalesce(p_address, '')), ''),
      employment_status = v_new_status
  where id = p_employee_id;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(), v_store, 'manager_update_employee_profile', 'profile', p_employee_id,
    jsonb_build_object(
      'full_name', trim(p_full_name),
      'phone', nullif(trim(coalesce(p_phone, '')), ''),
      'address', nullif(trim(coalesce(p_address, '')), ''),
      'employment_status', v_new_status
    )
  );
  return true;
end;
$function$;

-- 6) Manager sửa địa chỉ + GPS + bán kính của chi nhánh mình
CREATE OR REPLACE FUNCTION public.manager_update_branch_gps(
  p_address text DEFAULT NULL,
  p_latitude double precision DEFAULT NULL,
  p_longitude double precision DEFAULT NULL,
  p_gps_radius_m integer DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
declare
  v_store uuid;
begin
  if public.my_role() <> 'manager' then raise exception 'FORBIDDEN'; end if;
  if not public.current_user_has_manager_permission('branch_gps') then
    raise exception 'MANAGER_PERMISSION_DENIED';
  end if;

  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid() and p.employment_status = 'active';
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;

  if p_latitude is not null and (p_latitude < -90 or p_latitude > 90) then
    raise exception 'TOA_DO_KHONG_HOP_LE';
  end if;
  if p_longitude is not null and (p_longitude < -180 or p_longitude > 180) then
    raise exception 'TOA_DO_KHONG_HOP_LE';
  end if;
  if p_gps_radius_m is not null and (p_gps_radius_m < 20 or p_gps_radius_m > 1000) then
    raise exception 'BAN_KINH_KHONG_HOP_LE';
  end if;

  update public.stores
  set address = coalesce(nullif(trim(coalesce(p_address, '')), ''), address),
      latitude = coalesce(p_latitude, latitude),
      longitude = coalesce(p_longitude, longitude),
      gps_radius_m = coalesce(p_gps_radius_m, gps_radius_m),
      updated_at = now()
  where id = v_store;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(), v_store, 'manager_update_branch_gps', 'store', v_store,
    jsonb_build_object('address', p_address, 'latitude', p_latitude,
                       'longitude', p_longitude, 'gps_radius_m', p_gps_radius_m)
  );
  return true;
end;
$function$;

-- 7) review_attendance_device — cho Manager có quyền device_manage duyệt thiết bị
CREATE OR REPLACE FUNCTION public.review_attendance_device(
  p_device_id uuid,
  p_action text,
  p_reason text DEFAULT NULL::text
) RETURNS boolean
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
  select role::text, store_id into v_role, v_store
  from public.profiles
  where id = auth.uid() and employment_status = 'active';

  if v_role is null then raise exception 'FORBIDDEN'; end if;

  if v_role = 'manager' then
    if not public.current_user_has_manager_permission('device_manage') then
      raise exception 'MANAGER_PERMISSION_DENIED';
    end if;
  elsif v_role <> 'owner' then
    raise exception 'OWNER_REQUIRED';
  end if;

  select d.employee_id, p.store_id, d.status into v_employee, v_device_store, v_status
  from public.devices d
  join public.profiles p on p.id = d.employee_id
  where d.id = p_device_id
  for update;

  if not found then raise exception 'THIET_BI_NOT_FOUND'; end if;
  if v_device_store is distinct from v_store then raise exception 'FORBIDDEN'; end if;

  if lower(p_action) = 'approve' then
    if v_status <> 'pending' then raise exception 'THIET_BI_DA_XU_LY'; end if;
    if exists(select 1 from public.devices where employee_id = v_employee and status = 'approved' and id <> p_device_id) then
      raise exception 'NHAN_VIEN_DA_CO_THIET_BI_DUOC_DUYET';
    end if;
    update public.devices
    set status = 'approved', approved_by = auth.uid(), approved_at = now(),
        rejected_reason = null, revoked_at = null, updated_at = now()
    where id = p_device_id;
  elsif lower(p_action) = 'reject' then
    if v_status <> 'pending' then raise exception 'THIET_BI_DA_XU_LY'; end if;
    update public.devices
    set status = 'rejected',
        rejected_reason = nullif(trim(coalesce(p_reason, 'Từ chối')), ''),
        updated_at = now()
    where id = p_device_id;
  elsif lower(p_action) = 'revoke' then
    if v_status <> 'approved' then raise exception 'THIET_BI_CHUA_DUOC_DUYET'; end if;
    update public.devices
    set status = 'revoked', revoked_at = now(), updated_at = now()
    where id = p_device_id;
  else
    raise exception 'ACTION_KHONG_HOP_LE';
  end if;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(), v_store, 'review_attendance_device', 'device', p_device_id,
    jsonb_build_object('action', lower(p_action), 'actor_role', v_role,
                       'reason', nullif(trim(coalesce(p_reason, '')), ''))
  );
  return true;
end;
$function$;

-- 8) Chặn Manager thêm/sửa/xóa phiếu phạt – cộng – tạm ứng nếu thiếu quyền payroll_adjust
CREATE OR REPLACE FUNCTION public.guard_manager_payroll_adjust()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
begin
  -- Cron / service role / Owner: không có JWT hoặc không phải manager => cho qua.
  if auth.uid() is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if public.my_role() = 'manager'
     and not public.current_user_has_manager_permission('payroll_adjust') then
    raise exception 'MANAGER_PERMISSION_DENIED';
  end if;

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS trg_guard_manager_payroll_adjust ON public.payroll_adjustments;
CREATE TRIGGER trg_guard_manager_payroll_adjust
BEFORE INSERT OR UPDATE OR DELETE ON public.payroll_adjustments
FOR EACH ROW EXECUTE FUNCTION public.guard_manager_payroll_adjust();

-- 9) Quyền thực thi
REVOKE ALL ON FUNCTION public.manager_update_employee_profile(uuid, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.manager_update_employee_profile(uuid, text, text, text, text) TO authenticated;

REVOKE ALL ON FUNCTION public.manager_update_branch_gps(text, double precision, double precision, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.manager_update_branch_gps(text, double precision, double precision, integer) TO authenticated;

REVOKE ALL ON FUNCTION public.guard_manager_payroll_adjust() FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.review_attendance_device(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_attendance_device(uuid, text, text) TO authenticated;

COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY (chỉ đọc cấu hình quyền, không có dữ liệu cá nhân)
-- ---------------------------------------------------------------------------
select s.name as chi_nhanh, mp.permission_key, mp.enabled
from public.manager_permissions mp
join public.stores s on s.id = mp.store_id
order by s.name, mp.permission_key;

