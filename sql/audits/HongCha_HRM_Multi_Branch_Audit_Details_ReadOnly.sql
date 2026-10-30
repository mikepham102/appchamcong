-- HongCha HRM: READ-ONLY follow-up inventory for the multi-branch authorization design.
-- One result grid. Reads PostgreSQL catalogs only; does not read business rows or modify data.

WITH audit_rows AS (
  SELECT 'function_definition'::text AS section,
         n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS object_name,
         pg_get_functiondef(p.oid) AS detail
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND p.proname IN (
      'is_owner','is_manager_or_owner','my_role','is_store_owner','is_store_member',
      'get_my_active_store_id','switch_active_store','create_branch',
      'current_user_has_manager_permission','get_my_manager_permissions',
      'owner_get_manager_permissions','owner_save_manager_permissions',
      'owner_save_manager_permissions_v2','sync_profile_store_membership',
      'transfer_employee_branch'
    )

  UNION ALL

  SELECT 'related_table_columns',
         c.table_schema || '.' || c.table_name,
         string_agg(c.column_name || ' ' || c.data_type ||
           CASE WHEN c.data_type = 'USER-DEFINED' THEN ' (' || c.udt_name || ')' ELSE '' END,
           ', ' ORDER BY c.ordinal_position)
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND (
      c.table_name IN ('manager_permissions','profiles','stores')
      OR c.column_name IN ('store_id','branch_id','owner_id','user_id','manager_id')
      OR c.table_name ILIKE '%membership%'
      OR c.table_name ILIKE '%branch%'
      OR c.table_name ILIKE '%store%'
    )
  GROUP BY c.table_schema, c.table_name

  UNION ALL

  SELECT 'related_table_constraint',
         conrelid::regclass::text || '.' || conname,
         pg_get_constraintdef(oid)
  FROM pg_constraint
  WHERE connamespace = 'public'::regnamespace
    AND conrelid IN (
      SELECT c.oid
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public'
        AND (c.relname IN ('manager_permissions','profiles','stores')
          OR c.relname ILIKE '%membership%'
          OR c.relname ILIKE '%branch%'
          OR c.relname ILIKE '%store%')
    )

  UNION ALL

  SELECT 'policy', schemaname || '.' || tablename || '.' || policyname,
         'command=' || cmd || '; roles=' || array_to_string(roles, ',') ||
         '; using=' || coalesce(qual, '<none>') || '; check=' || coalesce(with_check, '<none>')
  FROM pg_policies
  WHERE schemaname = 'public'
)
SELECT section, object_name, detail
FROM audit_rows
ORDER BY section, object_name;
