-- HongCha HRM V84.30 - repair automatic shift-registration finalization.
-- Fixes the scalar UUID return from employee_schedule_conflict() being read
-- incorrectly as a table with an "id" column.
-- This migration changes only the finalizer function definition. It does not
-- execute the finalizer; the existing Cron schedule will process due windows.

BEGIN;

DO $preflight$
DECLARE
  v_conflict_function oid;
  v_return_type oid;
BEGIN
  IF to_regclass('public.shift_registration_windows') IS NULL
     OR to_regclass('public.shift_registration_recurring_rules') IS NULL
     OR to_regclass('public.shift_registrations') IS NULL
     OR to_regclass('public.work_schedules') IS NULL
     OR to_regclass('public.audit_logs') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_TABLE_MISSING: shift registration finalizer dependencies';
  END IF;

  IF to_regprocedure('public.auto_finalize_due_shift_registrations()') IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING: public.auto_finalize_due_shift_registrations()';
  END IF;

  v_conflict_function := to_regprocedure(
    'public.employee_schedule_conflict(uuid,timestamp with time zone,timestamp with time zone,uuid)'
  );
  IF v_conflict_function IS NULL THEN
    RAISE EXCEPTION 'REQUIRED_FUNCTION_MISSING: public.employee_schedule_conflict(uuid,timestamptz,timestamptz,uuid)';
  END IF;

  SELECT p.prorettype INTO v_return_type
  FROM pg_proc p
  WHERE p.oid = v_conflict_function;

  IF v_return_type <> 'uuid'::regtype THEN
    RAISE EXCEPTION 'UNEXPECTED_CONFLICT_FUNCTION_RETURN_TYPE: expected uuid';
  END IF;
END;
$preflight$;

CREATE OR REPLACE FUNCTION public.auto_finalize_due_shift_registrations()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $auto_finalize$
DECLARE
  w record;
  r record;
  s public.work_schedules%rowtype;
  conflict_id uuid;
  rule_auto_approve boolean;
  approved integer := 0;
  rejected integer := 0;
  windows_done integer := 0;
  total_approved integer := 0;
  total_rejected integer := 0;
BEGIN
  FOR w IN
    SELECT *
    FROM public.shift_registration_windows
    WHERE status = 'open'
      AND close_at <= now()
    ORDER BY close_at
    FOR UPDATE
  LOOP
    SELECT COALESCE(rr.auto_approve, true)
      INTO rule_auto_approve
    FROM public.shift_registration_recurring_rules rr
    WHERE rr.store_id = w.store_id
      AND rr.is_active = true
    LIMIT 1;

    IF COALESCE(rule_auto_approve, true) THEN
      approved := 0;
      rejected := 0;

      FOR r IN
        SELECT sr.id AS registration_id, sr.employee_id, sr.schedule_id
        FROM public.shift_registrations sr
        JOIN public.work_schedules ws ON ws.id = sr.schedule_id
        WHERE sr.status = 'pending'
          AND ws.store_id = w.store_id
          AND ws.work_date >= w.week_start
          AND ws.work_date < w.week_start + 7
        ORDER BY sr.requested_at, sr.id
        FOR UPDATE OF sr
      LOOP
        SELECT * INTO s
        FROM public.work_schedules
        WHERE id = r.schedule_id
        FOR UPDATE;

        IF NOT FOUND OR s.status <> 'open' OR s.employee_id IS NOT NULL THEN
          UPDATE public.shift_registrations
          SET status = 'rejected',
              reviewed_at = now(),
              rejection_reason = 'Ca không còn chỗ tại thời điểm tự chốt',
              updated_at = now()
          WHERE id = r.registration_id;
          rejected := rejected + 1;
          CONTINUE;
        END IF;

        -- employee_schedule_conflict() returns a scalar UUID, not a row/table.
        conflict_id := public.employee_schedule_conflict(
          r.employee_id, s.start_at, s.end_at, s.id
        );

        IF conflict_id IS NOT NULL THEN
          UPDATE public.shift_registrations
          SET status = 'rejected',
              reviewed_at = now(),
              rejection_reason = 'Nhân viên bị trùng ca tại thời điểm tự chốt',
              updated_at = now()
          WHERE id = r.registration_id;
          rejected := rejected + 1;
          CONTINUE;
        END IF;

        UPDATE public.shift_registrations
        SET status = 'approved',
            reviewed_at = now(),
            rejection_reason = NULL,
            updated_at = now()
        WHERE id = r.registration_id;

        UPDATE public.work_schedules
        SET employee_id = r.employee_id,
            status = 'assigned',
            assigned_at = now(),
            updated_at = now()
        WHERE id = s.id;

        approved := approved + 1;
      END LOOP;

      total_approved := total_approved + approved;
      total_rejected := total_rejected + rejected;
    END IF;

    UPDATE public.shift_registration_windows
    SET status = 'finalized',
        finalized_at = now(),
        updated_at = now()
    WHERE id = w.id;

    INSERT INTO public.audit_logs(actor_id, action, entity_type, entity_id, new_data)
    VALUES (
      NULL,
      'auto_finalize_shift_registrations',
      'shift_registration_window',
      w.id,
      jsonb_build_object(
        'week_start', w.week_start,
        'auto_approve', COALESCE(rule_auto_approve, true),
        'approved', approved,
        'rejected', rejected
      )
    );

    windows_done := windows_done + 1;
  END LOOP;

  RETURN jsonb_build_object(
    'windows', windows_done,
    'approved', total_approved,
    'rejected', total_rejected
  );
END;
$auto_finalize$;

COMMIT;

