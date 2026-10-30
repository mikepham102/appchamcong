-- HongCha HRM V84.31 — Multi-branch Manager access (BẢN ÁP DỤNG CHÍNH THỨC)
--
-- Vì sao có file này: file gốc `HongCha_HRM_Multi_Branch_Manager_Access_Migration.sql`
-- KHÔNG đủ để Manager chuyển chi nhánh, vì trigger `trg_enforce_manager_business_permission`
-- chặn mọi thay đổi trên bảng profiles của Manager ngoại trừ full_name/phone/address.
-- File này = nội dung file gốc + vá trigger đó + thêm chốt an toàn không khóa quyền Manager.
--
-- An toàn dữ liệu:
--   * Chỉ THÊM schema/bảng/hàm; không xóa, không sửa dữ liệu nghiệp vụ.
--   * Có preflight: nếu có Manager đang hoạt động mà thiếu membership chi nhánh hiện tại
--     thì RAISE EXCEPTION và KHÔNG áp dụng gì (tránh Manager mất quyền).
--   * Toàn bộ chạy trong 1 transaction: lỗi ở bất kỳ đâu => rollback toàn bộ.
--
-- Thứ tự chạy: file này SAU 3 migration V84.29 (device cleanup, profile approval) và
-- TRƯỚC migration V84.30 không bắt buộc — V84.30 chỉ sửa 1 hàm độc lập.

BEGIN;

DO $preflight$
BEGIN
  IF to_regclass('public.profiles') IS NULL
     OR to_regclass('public.stores') IS NULL
     OR to_regclass('public.store_memberships') IS NULL
     OR to_regclass('public.manager_permissions') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING: profiles, stores, store_memberships or manager_permissions';
  END IF;
  IF to_regprocedure('public.is_store_owner(uuid)') IS NULL
     OR to_regprocedure('public.is_store_member(uuid)') IS NULL
     OR to_regprocedure('public.my_role()') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING: existing branch authorization helpers';
  END IF;

  IF to_regprocedure('public.enforce_manager_business_permission()') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING: public.enforce_manager_business_permission()';
  END IF;

  -- CHỐT AN TOÀN (V84.31): không bao giờ áp dụng nếu có Manager đang hoạt động
  -- mà thiếu dòng membership manager active tại chi nhánh họ đang làm việc.
  -- Lý do: bản mới của current_user_has_manager_permission() đọc membership;
  -- nếu thiếu, Manager sẽ MẤT toàn bộ quyền sau khi chạy file này.
  IF EXISTS (
    SELECT 1
    FROM public.profiles p
    WHERE p.role = 'manager'
      AND p.employment_status = 'active'
      AND (
        p.store_id IS NULL
        OR NOT EXISTS (
          SELECT 1 FROM public.store_memberships m
          WHERE m.user_id = p.id
            AND m.store_id = p.store_id
            AND m.role = 'manager'::public.user_role
            AND m.is_active = true
        )
      )
  ) THEN
    RAISE EXCEPTION 'PRECHECK_MANAGER_MEMBERSHIP_MISSING: co Manager thieu membership active tai chi nhanh hien tai. Hay chay sql/audits/HongCha_HRM_MultiBranch_Safety_Preflight_ReadOnly.sql truoc.';
  END IF;
END;
$preflight$;

-- Platform administration is intentionally separate from profiles.role and branch data access.
-- No account is added here. This table grants no client access and does not grant operational data access.
CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;
CREATE TABLE IF NOT EXISTS private.platform_admins (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  note text
);
ALTER TABLE private.platform_admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE private.platform_admins FORCE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE private.platform_admins FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE private.platform_admins IS
  'Platform administration identities only. Membership grants no access to store operational data.';

CREATE OR REPLACE FUNCTION public.current_user_has_manager_permission(p_permission_key text)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
  v_store uuid;
  v_enabled boolean;
BEGIN
  SELECT p.role::text, p.store_id
    INTO v_role, v_store
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.employment_status = 'active';

  IF v_role = 'owner' THEN
    RETURN true;
  END IF;
  IF v_role <> 'manager' OR v_store IS NULL OR p_permission_key IS NULL THEN
    RETURN false;
  END IF;

  -- A manager's active branch pointer is accepted only while that manager
  -- has an active manager membership in the same branch.
  IF NOT EXISTS (
    SELECT 1
    FROM public.store_memberships sm
    WHERE sm.user_id = auth.uid()
      AND sm.store_id = v_store
      AND sm.role = 'manager'::public.user_role
      AND sm.is_active = true
  ) THEN
    RETURN false;
  END IF;

  SELECT mp.enabled INTO v_enabled
  FROM public.manager_permissions mp
  WHERE mp.store_id = v_store
    AND mp.permission_key = p_permission_key;
  RETURN coalesce(v_enabled, false);
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_manager_permissions()
RETURNS TABLE(permission_key text, enabled boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
  v_store uuid;
BEGIN
  SELECT p.role::text, p.store_id INTO v_role, v_store
  FROM public.profiles p
  WHERE p.id = auth.uid() AND p.employment_status = 'active';

  IF v_role <> 'manager' OR v_store IS NULL
     OR NOT EXISTS (
       SELECT 1 FROM public.store_memberships sm
       WHERE sm.user_id = auth.uid()
         AND sm.store_id = v_store
         AND sm.role = 'manager'::public.user_role
         AND sm.is_active = true
     ) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  RETURN QUERY
  SELECT mp.permission_key, mp.enabled
  FROM public.manager_permissions mp
  WHERE mp.store_id = v_store
  ORDER BY mp.permission_key;
END;
$function$;

CREATE OR REPLACE FUNCTION public.switch_active_store(p_store_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_store public.stores%rowtype;
  v_role text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;
  SELECT p.role::text INTO v_role
  FROM public.profiles p
  WHERE p.id = v_uid AND p.employment_status = 'active';

  IF v_role = 'owner' THEN
    SELECT s.* INTO v_store
    FROM public.stores s
    WHERE s.id = p_store_id AND public.is_store_owner(s.id);
  ELSIF v_role = 'manager' THEN
    SELECT s.* INTO v_store
    FROM public.stores s
    JOIN public.store_memberships sm ON sm.store_id = s.id
    WHERE s.id = p_store_id
      AND sm.user_id = v_uid
      AND sm.role = 'manager'::public.user_role
      AND sm.is_active = true;
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF NOT FOUND THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  UPDATE public.profiles SET store_id = v_store.id, updated_at = now() WHERE id = v_uid;
  RETURN jsonb_build_object('id', v_store.id, 'name', v_store.name, 'address', v_store.address);
END;
$function$;

-- Owner may grant or revoke one Manager's memberships only in branches the caller owns.
-- Existing memberships with other Owners are left untouched.
CREATE OR REPLACE FUNCTION public.owner_set_manager_branches(
  p_manager_id uuid,
  p_store_ids uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_role text;
  v_status text;
  v_previous_store uuid;
  v_next_store uuid;
  v_target_ids uuid[] := coalesce(p_store_ids, ARRAY[]::uuid[]);
  v_changed integer := 0;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'UNAUTHENTICATED'; END IF;
  IF public.my_role() <> 'owner' THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF p_manager_id IS NULL THEN RAISE EXCEPTION 'MANAGER_REQUIRED'; END IF;

  SELECT p.role::text, p.employment_status::text, p.store_id
    INTO v_role, v_status, v_previous_store
  FROM public.profiles p
  WHERE p.id = p_manager_id
  FOR UPDATE;

  IF NOT FOUND OR v_role <> 'manager' OR v_status <> 'active' THEN
    RAISE EXCEPTION 'ACTIVE_MANAGER_REQUIRED';
  END IF;
  IF array_position(v_target_ids, NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'BRANCH_ID_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM unnest(v_target_ids) AS requested(store_id)
    WHERE NOT public.is_store_owner(requested.store_id)
  ) THEN
    RAISE EXCEPTION 'FORBIDDEN_BRANCH_SCOPE';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.store_memberships sm
    WHERE sm.user_id = p_manager_id
      AND sm.role = 'owner'::public.user_role
      AND sm.is_active = true
      AND public.is_store_owner(sm.store_id)
  ) THEN
    RAISE EXCEPTION 'TARGET_IS_OWNER';
  END IF;

  -- Deactivate only this caller's Manager assignments omitted from the submitted list.
  UPDATE public.store_memberships sm
  SET is_active = false,
      left_at = coalesce(sm.left_at, now()),
      updated_at = now()
  WHERE sm.user_id = p_manager_id
    AND sm.role = 'manager'::public.user_role
    AND sm.is_active = true
    AND public.is_store_owner(sm.store_id)
    AND NOT (sm.store_id = ANY(v_target_ids));
  GET DIAGNOSTICS v_changed = ROW_COUNT;

  -- Activate or create exactly the Manager memberships requested by this Owner.
  INSERT INTO public.store_memberships AS current_membership
    (user_id, store_id, role, is_active, joined_at, left_at)
  SELECT p_manager_id, requested.store_id, 'manager'::public.user_role, true, now(), NULL
  FROM (SELECT DISTINCT unnest(v_target_ids) AS store_id) requested
  ON CONFLICT (user_id, store_id) DO UPDATE
  SET role = 'manager'::public.user_role,
      is_active = true,
      joined_at = CASE WHEN current_membership.is_active
                       THEN current_membership.joined_at ELSE now() END,
      left_at = NULL,
      updated_at = now();

  -- Keep the Manager's active branch context valid if this Owner removed it.
  IF v_previous_store IS NULL AND cardinality(v_target_ids) > 0 THEN
    SELECT requested.store_id INTO v_next_store
    FROM (SELECT DISTINCT unnest(v_target_ids) AS store_id) requested
    ORDER BY requested.store_id
    LIMIT 1;
    UPDATE public.profiles SET store_id = v_next_store, updated_at = now()
    WHERE id = p_manager_id;
  ELSIF v_previous_store IS NOT NULL
     AND public.is_store_owner(v_previous_store)
     AND NOT (v_previous_store = ANY(v_target_ids)) THEN
    SELECT requested.store_id INTO v_next_store
    FROM (SELECT DISTINCT unnest(v_target_ids) AS store_id) requested
    ORDER BY requested.store_id
    LIMIT 1;
    IF v_next_store IS NULL THEN
      SELECT sm.store_id INTO v_next_store
      FROM public.store_memberships sm
      WHERE sm.user_id = p_manager_id
        AND sm.role = 'manager'::public.user_role
        AND sm.is_active = true
      ORDER BY sm.store_id
      LIMIT 1;
    END IF;
    UPDATE public.profiles SET store_id = v_next_store, updated_at = now()
    WHERE id = p_manager_id;
  END IF;

  INSERT INTO public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  VALUES (
    auth.uid(),
    (SELECT p.store_id FROM public.profiles p WHERE p.id = auth.uid()),
    'owner_set_manager_branches',
    'manager_branch_memberships',
    p_manager_id,
    jsonb_build_object('manager_id', p_manager_id, 'store_ids', v_target_ids,
                       'deactivated_count', v_changed)
  );

  RETURN jsonb_build_object('manager_id', p_manager_id, 'store_ids', v_target_ids,
                            'deactivated_count', v_changed);
END;
$function$;

REVOKE ALL ON FUNCTION public.current_user_has_manager_permission(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.current_user_has_manager_permission(text) TO authenticated;
REVOKE ALL ON FUNCTION public.get_my_manager_permissions() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_manager_permissions() TO authenticated;
REVOKE ALL ON FUNCTION public.switch_active_store(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.switch_active_store(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.owner_set_manager_branches(uuid, uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.owner_set_manager_branches(uuid, uuid[]) TO authenticated;

-- ---------------------------------------------------------------------------
-- V84.31 FIX — cho phép Manager đổi "chi nhánh đang làm việc".
--
-- Trigger cũ chặn MỌI thay đổi trên profiles của Manager ngoại trừ
-- full_name / phone / address / updated_at. Vì vậy switch_active_store()
-- (do chính Manager gọi) sẽ bị chặn với lỗi MANAGER_PROFILE_FIELD_FORBIDDEN.
--
-- Bản mới CHỈ mở thêm cột store_id, và CHỈ khi Manager đã có membership
-- manager đang hoạt động tại chi nhánh đích (do chủ quán gán trước).
-- Mọi cột khác vẫn bị chặn như cũ. Manager không thể tự cấp quyền cho mình
-- vì không có quyền ghi vào store_memberships (policy chỉ cho Owner).
-- ---------------------------------------------------------------------------
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
$function$;

COMMIT;

