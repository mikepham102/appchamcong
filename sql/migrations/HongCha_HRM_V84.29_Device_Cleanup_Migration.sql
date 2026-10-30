-- HongCha HRM V84.29
-- Safe cleanup for revoked/rejected attendance devices.
-- Attendance and attendance-event rows are never deleted or modified.

BEGIN;

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

  IF v_role IS DISTINCT FROM 'owner' THEN
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

  IF NOT public.is_store_owner(v_device_store) THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  IF v_device.status NOT IN ('revoked'::public.device_status, 'rejected'::public.device_status) THEN
    RAISE EXCEPTION 'DEVICE_NOT_INACTIVE';
  END IF;

  -- Keep device rows referenced by either attendance table so historical
  -- check-in/check-out evidence and foreign keys remain intact.
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
    jsonb_build_object('deleted', true, 'reason', 'owner_cleanup_inactive_device')
  );

  DELETE FROM public.devices WHERE id = p_device_id;
  RETURN jsonb_build_object('deleted', true, 'device_id', p_device_id);
END;
$function$;

REVOKE ALL ON FUNCTION public.owner_delete_inactive_attendance_device(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.owner_delete_inactive_attendance_device(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.owner_delete_inactive_attendance_device(uuid) TO authenticated;

COMMIT;
