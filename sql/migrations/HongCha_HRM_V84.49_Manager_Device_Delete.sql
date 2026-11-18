-- HongCha HRM V84.49 — Manager được xóa thiết bị chấm công đã thu hồi/từ chối
--
-- Hiện trạng: owner_delete_inactive_attendance_device() yêu cầu role='owner'
--   => Manager dù có quyền device_manage vẫn bị FORBIDDEN và nút Xóa bị ẩn.
--
-- Sửa: cho phép Manager có device_manage, cùng chi nhánh với nhân viên.
-- Giữ NGUYÊN toàn bộ quy tắc an toàn:
--   * chỉ xóa thiết bị status = revoked / rejected
--   * TỪ CHỐI xóa nếu thiết bị đã có lịch sử attendance / attendance_events
--   * ghi audit_logs (kèm actor_role)
-- Không đổi dữ liệu.

BEGIN;

DO $preflight$
DECLARE
  v_src text;
BEGIN
  IF to_regprocedure('public.owner_delete_inactive_attendance_device(uuid)') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING';
  END IF;
  IF to_regclass('public.devices') IS NULL
     OR to_regclass('public.attendance') IS NULL
     OR to_regclass('public.attendance_events') IS NULL
     OR to_regclass('public.audit_logs') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING';
  END IF;
  SELECT p.prosrc INTO v_src
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'owner_delete_inactive_attendance_device';
  IF v_src IS NULL
     OR position('DEVICE_ATTENDANCE_HISTORY' in v_src) = 0
     OR position('DEVICE_NOT_INACTIVE' in v_src) = 0 THEN
    RAISE EXCEPTION 'UNEXPECTED_FUNCTION_BODY: ham da thay doi, dung lai';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.owner_delete_inactive_attendance_device(p_device_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
SET row_security TO 'off'
AS $function$
DECLARE
  v_role text;
  v_device public.devices%rowtype;
  v_device_store uuid;
BEGIN
  SELECT p.role::text
    INTO v_role
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.employment_status = 'active';

  IF v_role = 'owner' THEN
    NULL;
  ELSIF v_role = 'manager' THEN
    IF NOT public.current_user_has_manager_permission('device_manage') THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
  ELSE
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT d.*
    INTO v_device
  FROM public.devices d
  WHERE d.id = p_device_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DEVICE_NOT_FOUND';
  END IF;

  SELECT p.store_id
    INTO v_device_store
  FROM public.profiles p
  WHERE p.id = v_device.employee_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'DEVICE_NOT_FOUND';
  END IF;

  IF v_role = 'owner' THEN
    IF NOT public.is_store_owner(v_device_store) THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
  ELSE
    IF NOT public.is_store_member(v_device_store) THEN
      RAISE EXCEPTION 'FORBIDDEN';
    END IF;
  END IF;

  IF v_device.status NOT IN ('revoked'::public.device_status, 'rejected'::public.device_status) THEN
    RAISE EXCEPTION 'DEVICE_NOT_INACTIVE';
  END IF;

  -- Giữ thiết bị đã có lịch sử chấm công (không phá bằng chứng).
  IF EXISTS (SELECT 1 FROM public.attendance a WHERE a.device_id = p_device_id)
     OR EXISTS (SELECT 1 FROM public.attendance_events e WHERE e.device_id = p_device_id) THEN
    RAISE EXCEPTION 'DEVICE_ATTENDANCE_HISTORY';
  END IF;

  INSERT INTO public.audit_logs(actor_id, store_id, action, entity_type, entity_id, old_data, new_data)
  VALUES (
    auth.uid(),
    v_device_store,
    'owner_delete_inactive_attendance_device',
    'device',
    v_device.id,
    jsonb_build_object(
      'employee_id', v_device.employee_id,
      'device_key', v_device.device_key,
      'device_name', v_device.device_name,
      'status', v_device.status,
      'requested_at', v_device.requested_at,
      'revoked_at', v_device.revoked_at
    ),
    jsonb_build_object('deleted', true, 'reason', 'owner_cleanup_inactive_device', 'actor_role', v_role)
  );

  DELETE FROM public.devices WHERE id = p_device_id;
  RETURN jsonb_build_object('deleted', true, 'device_id', p_device_id);
END;
$function$;

COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY: da_ap_dung phải = true
-- ---------------------------------------------------------------------------
select p.proname,
       position('device_manage' in coalesce(p.prosrc,'')) > 0 as da_ap_dung
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_delete_inactive_attendance_device';
