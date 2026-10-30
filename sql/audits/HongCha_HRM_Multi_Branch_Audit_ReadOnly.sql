-- HongCha HRM: READ-ONLY schema/access inventory before multi-branch role changes.
-- Returns one result grid from PostgreSQL catalogs only; no employee data is read or changed.

WITH audit_rows AS (
  SELECT 'columns'::text AS section,
         table_schema || '.' || table_name AS object_name,
         column_name || ' ' || data_type ||
         CASE WHEN data_type = 'USER-DEFINED' THEN ' (' || udt_name || ')' ELSE '' END AS detail
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name IN (
      'profiles','stores','manager_permissions','attendance','work_schedules',
      'schedule_requests','shift_registration_windows','weekly_schedule_plans',
      'payroll_periods','payroll_adjustments','audit_logs','devices'
    )

  UNION ALL

  SELECT 'role_enum', t.typname, e.enumlabel
  FROM pg_type t
  JOIN pg_enum e ON e.enumtypid = t.oid
  JOIN pg_namespace n ON n.oid = t.typnamespace
  WHERE n.nspname = 'public' AND t.typname IN ('user_role','payroll_status')

  UNION ALL

  SELECT 'rls', n.nspname || '.' || c.relname,
         'enabled=' || c.relrowsecurity::text || '; forced=' || c.relforcerowsecurity::text
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r','p')
    AND c.relname IN (
      'profiles','stores','manager_permissions','attendance','work_schedules',
      'schedule_requests','shift_registration_windows','weekly_schedule_plans',
      'payroll_periods','payroll_adjustments','audit_logs','devices'
    )

  UNION ALL

  SELECT 'policy', schemaname || '.' || tablename || '.' || policyname,
         'roles=' || array_to_string(roles, ',') || '; command=' || cmd ||
         '; using=' || coalesce(qual, '<none>') || '; check=' || coalesce(with_check, '<none>')
  FROM pg_policies
  WHERE schemaname = 'public'
    AND tablename IN (
      'profiles','stores','manager_permissions','attendance','work_schedules',
      'schedule_requests','shift_registration_windows','weekly_schedule_plans',
      'payroll_periods','payroll_adjustments','audit_logs','devices'
    )

  UNION ALL

  SELECT 'function_signature',
         n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
         'security_definer=' || p.prosecdef::text || '; volatility=' || p.provolatile::text
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (
      p.proname IN (
        'is_store_owner','current_user_has_manager_permission','switch_active_store',
        'owner_create_store','owner_create_branch','create_branch'
      )
      OR p.proname ILIKE '%branch%'
      OR p.proname ILIKE '%store%'
      OR p.proname ILIKE '%manager%permission%'
    )

  UNION ALL

  SELECT 'store_profile_constraints',
         conrelid::regclass::text || '.' || conname,
         pg_get_constraintdef(oid)
  FROM pg_constraint
  WHERE connamespace = 'public'::regnamespace
    AND conrelid IN ('public.profiles'::regclass, 'public.stores'::regclass)
)
SELECT section, object_name, detail
FROM audit_rows
ORDER BY section, object_name, detail;
