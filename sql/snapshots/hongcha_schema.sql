--
-- PostgreSQL database dump
--

\restrict V2qfbHKDNYYXBi3uuew3XjhfSd3ta4dkN3dEU5Lfov5rDVKpV51f91T0KsgyT2P

-- Dumped from database version 17.6
-- Dumped by pg_dump version 18.6

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: graphql; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql;


--
-- Name: graphql_public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA graphql_public;


--
-- Name: pgbouncer; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pgbouncer;


--
-- Name: vault; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA vault;


--
-- Name: pg_stat_statements; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_stat_statements WITH SCHEMA extensions;


--
-- Name: EXTENSION pg_stat_statements; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_stat_statements IS 'track planning and execution statistics of all SQL statements executed';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: supabase_vault; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS supabase_vault WITH SCHEMA vault;


--
-- Name: EXTENSION supabase_vault; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION supabase_vault IS 'Supabase Vault Extension';


--
-- Name: uuid-ossp; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;


--
-- Name: EXTENSION "uuid-ossp"; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION "uuid-ossp" IS 'generate universally unique identifiers (UUIDs)';


--
-- Name: adjustment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.adjustment_status AS ENUM (
    'pending',
    'approved',
    'rejected'
);


--
-- Name: adjustment_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.adjustment_type AS ENUM (
    'bonus',
    'penalty',
    'advance'
);


--
-- Name: attendance_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.attendance_status AS ENUM (
    'valid',
    'late',
    'invalid',
    'manual',
    'missing_checkout'
);


--
-- Name: device_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.device_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'revoked'
);


--
-- Name: employment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.employment_status AS ENUM (
    'active',
    'inactive',
    'invited',
    'terminated'
);


--
-- Name: leave_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.leave_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'cancelled'
);


--
-- Name: payroll_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payroll_status AS ENUM (
    'draft',
    'review',
    'locked',
    'paid'
);


--
-- Name: registration_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.registration_status AS ENUM (
    'pending',
    'approved',
    'rejected',
    'cancelled'
);


--
-- Name: schedule_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.schedule_status AS ENUM (
    'open',
    'assigned',
    'cancelled',
    'completed'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'owner',
    'manager',
    'employee'
);


--
-- Name: graphql(text, text, jsonb, jsonb); Type: FUNCTION; Schema: graphql_public; Owner: -
--

CREATE FUNCTION graphql_public.graphql("operationName" text DEFAULT NULL::text, query text DEFAULT NULL::text, variables jsonb DEFAULT NULL::jsonb, extensions jsonb DEFAULT NULL::jsonb) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;


--
-- Name: get_auth(text); Type: FUNCTION; Schema: pgbouncer; Owner: -
--

CREATE FUNCTION pgbouncer.get_auth(p_usename text) RETURNS TABLE(username text, password text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $_$
  BEGIN
      RAISE DEBUG 'PgBouncer auth request: %', p_usename;

      RETURN QUERY
      SELECT
          rolname::text,
          CASE WHEN rolvaliduntil < now()
              THEN null
              ELSE rolpassword::text
          END
      FROM pg_authid
      WHERE rolname=$1 and rolcanlogin;
  END;
  $_$;


--
-- Name: activate_my_employee(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.activate_my_employee() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_profile public.profiles%rowtype;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select * into v_profile
  from public.profiles
  where id = v_uid
  for update;

  if not found then
    raise exception 'PROFILE_NOT_FOUND';
  end if;

  if v_profile.role <> 'employee' then
    return jsonb_build_object('status', v_profile.employment_status::text);
  end if;

  if v_profile.employment_status = 'terminated' then
    raise exception 'PROFILE_TERMINATED';
  end if;

  if v_profile.employment_status = 'inactive' then
    raise exception 'PROFILE_INACTIVE';
  end if;

  if v_profile.employment_status = 'invited' then
    update public.profiles
    set employment_status = 'active',
        hired_at = coalesce(hired_at, (now() at time zone 'Asia/Ho_Chi_Minh')::date)
    where id = v_uid
    returning * into v_profile;
  end if;

  return jsonb_build_object(
    'status', v_profile.employment_status::text,
    'role', v_profile.role::text,
    'store_id', v_profile.store_id
  );
end;
$$;


--
-- Name: add_template_schedules_to_date(uuid, date, uuid[], integer[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_template_schedules_to_date(p_store_id uuid, p_work_date date, p_template_ids uuid[], p_slots integer[] DEFAULT NULL::integer[], p_note text DEFAULT NULL::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_my_store uuid;
  v_tz text;
  v_today date;
  v_created integer := 0;
  v_group uuid;
  v_template public.shift_template_versions%rowtype;
  v_slots integer;
  i integer;
begin
  select role::text,store_id into v_role,v_my_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') or v_my_store is distinct from p_store_id then
    raise exception 'FORBIDDEN';
  end if;
  if p_work_date is null or p_work_date < current_date then
    select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz from public.stores where id=p_store_id;
    v_today := (now() at time zone coalesce(v_tz,'Asia/Ho_Chi_Minh'))::date;
    if p_work_date is null or p_work_date < v_today then
      raise exception 'Không thể thêm ca cho ngày đã qua';
    end if;
  end if;
  if p_template_ids is null or cardinality(p_template_ids)=0 then
    raise exception 'Hãy chọn ít nhất một ca mẫu';
  end if;
  if p_slots is not null and cardinality(p_slots)<>cardinality(p_template_ids) then
    raise exception 'Dữ liệu số vị trí không khớp với danh sách ca mẫu';
  end if;

  -- Validate all selections before inserting anything (atomic operation).
  for i in 1..cardinality(p_template_ids) loop
    if p_template_ids[i] is null then raise exception 'Mẫu ca không hợp lệ'; end if;
    if exists (
      select 1 from public.work_schedules s
      where s.store_id=p_store_id
        and s.work_date=p_work_date
        and s.shift_template_id=p_template_ids[i]
        and s.status<>'cancelled'
    ) then
      raise exception 'CA_MAU_DA_CO_TRONG_NGAY';
    end if;
    select * into v_template
    from public.get_shift_template_version(p_template_ids[i],p_work_date);
    if not found or v_template.shift_template_id is null or v_template.is_active=false then
      raise exception 'Mẫu ca không tồn tại hoặc chưa có hiệu lực';
    end if;
    v_slots := coalesce(p_slots[i],v_template.capacity,1);
    if v_slots<1 or v_slots>10 then raise exception 'Số vị trí ca phải từ 1 đến 10'; end if;
  end loop;

  for i in 1..cardinality(p_template_ids) loop
    select * into v_template
    from public.get_shift_template_version(p_template_ids[i],p_work_date);
    v_slots := greatest(1,least(10,coalesce(p_slots[i],v_template.capacity,1)));
    v_group := gen_random_uuid();
    insert into public.work_schedules(
      store_id,shift_template_id,shift_group_id,work_date,start_time,end_time,
      employee_id,status,note,created_by,schedule_kind,custom_name
    )
    select
      p_store_id,p_template_ids[i],v_group,p_work_date,v_template.start_time,v_template.end_time,
      null,'open',nullif(trim(p_note),''),auth.uid(),'template',null
    from generate_series(1,v_slots);
    v_created := v_created + v_slots;
  end loop;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'add_template_schedules_to_date','work_schedule',p_template_ids[1],
         jsonb_build_object('work_date',p_work_date,'template_ids',p_template_ids,'created_slots',v_created));
  return v_created;
end;
$$;


--
-- Name: assign_employee_to_schedule(uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_employee_to_schedule(p_schedule_id uuid, p_employee_id uuid, p_note text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_result jsonb;
begin
  v_result:=public.assign_employees_to_schedule_group(p_schedule_id,array[p_employee_id],p_note);
  return true;
end;
$$;


--
-- Name: assign_employees_to_schedule_group(uuid, uuid[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.assign_employees_to_schedule_group(p_schedule_id uuid, p_employee_ids uuid[], p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text; v_store uuid; v_schedule public.work_schedules%rowtype;
  v_start timestamptz; v_end timestamptz; v_now timestamptz:=now();
  v_open integer; v_need integer; v_employee uuid; v_conflict uuid;
  v_assigned integer:=0; v_slot uuid;
  v_tz text:='Asia/Ho_Chi_Minh'; v_emp_store uuid; v_emp_role public.user_role;
begin
  select role::text,store_id into v_role,v_store from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  if p_employee_ids is null or coalesce(array_length(p_employee_ids,1),0)=0 then raise exception 'CHUA_CHON_NHAN_VIEN'; end if;
  if (select count(*) from (select distinct unnest(p_employee_ids) as id) q) <> array_length(p_employee_ids,1) then raise exception 'TRUNG_NHAN_VIEN'; end if;

  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz from public.stores where id=v_store;
  select * into v_schedule from public.work_schedules where id=p_schedule_id and store_id=v_store for update;
  if not found then raise exception 'CA_NOT_FOUND'; end if;
  v_start:=v_schedule.start_at;
  v_end:=v_schedule.end_at;
  if v_schedule.status='cancelled' then raise exception 'CA_DA_HUY'; end if;
  if v_schedule.status='completed' then raise exception 'CA_KHONG_CON_MO'; end if;
  if v_now>v_end then raise exception 'CA_DA_KET_THUC'; end if;
  -- Owner và Manager đều được điều chỉnh lịch bất cứ lúc nào trước khi ca kết thúc.
  if v_start<=v_now and v_role not in ('owner','manager') then raise exception 'CA_DA_BAT_DAU'; end if;

  -- Khóa toàn bộ slot trong group để capacity được kiểm tra atomically.
  perform pg_advisory_xact_lock(hashtextextended(coalesce(v_schedule.shift_group_id,p_schedule_id)::text||':group_assign',0));
  select count(*) into v_open from public.work_schedules
  where store_id=v_store and coalesce(shift_group_id,id)=coalesce(v_schedule.shift_group_id,p_schedule_id)
    and status='open' and employee_id is null;
  v_need:=array_length(p_employee_ids,1);
  if v_need>v_open then raise exception 'KHONG_DU_CHO'; end if;

  for v_employee in select distinct unnest(p_employee_ids) loop
    select store_id,role into v_emp_store,v_emp_role from public.profiles
    where id=v_employee and employment_status='active';
    if v_emp_store is distinct from v_store or v_emp_role<>'employee' then raise exception 'NHAN_VIEN_KHONG_HOP_LE'; end if;
    select public.employee_schedule_conflict(v_employee,v_start,v_end,p_schedule_id) into v_conflict;
    if v_conflict is not null then raise exception 'TRUNG_CA'; end if;
  end loop;

  for v_employee in select distinct unnest(p_employee_ids) loop
    select id into v_slot from public.work_schedules
    where store_id=v_store and coalesce(shift_group_id,id)=coalesce(v_schedule.shift_group_id,p_schedule_id)
      and status='open' and employee_id is null order by id limit 1 for update skip locked;
    if v_slot is null then raise exception 'KHONG_DU_CHO'; end if;
    update public.work_schedules set employee_id=v_employee,status='assigned',assigned_at=v_now,
      note=concat_ws(' · ',note,nullif(trim(p_note),'')),updated_at=v_now
    where id=v_slot;
    update public.shift_registrations set status=case when employee_id=v_employee then 'approved'::public.registration_status else 'rejected'::public.registration_status end,
      reviewed_by=auth.uid(),reviewed_at=v_now,
      rejection_reason=case when employee_id=v_employee then null else 'Ca đã được xếp cho nhân viên khác' end,
      updated_at=v_now
    where schedule_id=v_slot and status='pending';
    insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
    values(auth.uid(),'assign_employee_to_schedule','work_schedule',v_slot,
      jsonb_build_object('employee_id',v_employee,'started_shift_override',v_start<=v_now,'group_id',v_schedule.shift_group_id,'note',p_note));
    v_assigned:=v_assigned+1;
  end loop;
  return jsonb_build_object('assigned_count',v_assigned,'group_id',v_schedule.shift_group_id);
end;
$$;


--
-- Name: attendance_punch(text, text, double precision, double precision, double precision, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.attendance_punch(p_action text, p_device_key text, p_latitude double precision, p_longitude double precision, p_accuracy_m double precision DEFAULT NULL::double precision, p_schedule_id uuid DEFAULT NULL::uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_timezone text := 'Asia/Ho_Chi_Minh';
  v_radius integer;
  v_early integer;
  v_schedule public.work_schedules%rowtype;
  v_previous public.work_schedules%rowtype;
  v_template public.shift_templates%rowtype;
  v_previous_template public.shift_templates%rowtype;
  v_device public.devices%rowtype;
  v_att public.attendance%rowtype;
  v_previous_att public.attendance%rowtype;
  v_now timestamptz := now();
  v_distance double precision;
  v_late integer;
  v_worked integer;
  v_previous_worked integer;
  v_allowed integer;
  v_previous_allowed integer;
  v_early_leave integer;
  v_shop_lat double precision;
  v_shop_lng double precision;
  v_cutoff integer := 30;
  v_checkout_grace integer := 60;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if lower(p_action) not in ('checkin', 'checkout') then raise exception 'ACTION_KHONG_HOP_LE'; end if;
  if p_schedule_id is null then raise exception 'THIEU_SCHEDULE_ID'; end if;
  if p_latitude is null or p_longitude is null
     or p_latitude not between -90 and 90
     or p_longitude not between -180 and 180 then
    raise exception 'TOA_DO_KHONG_HOP_LE';
  end if;

  select store_id into v_store
  from public.profiles
  where id = v_uid and role = 'employee' and employment_status = 'active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select timezone, gps_radius_m, checkin_early_minutes, latitude, longitude
    into v_timezone, v_radius, v_early, v_shop_lat, v_shop_lng
  from public.stores where id = v_store;
  v_timezone := coalesce(v_timezone, 'Asia/Ho_Chi_Minh');

  select * into v_device
  from public.devices
  where employee_id = v_uid and device_key = trim(p_device_key)
  for update;
  if not found or v_device.status <> 'approved' then
    raise exception 'THIET_BI_KHONG_HOP_LE';
  end if;
  if v_shop_lat is null or v_shop_lng is null then raise exception 'GPS_CHUA_CAU_HINH'; end if;
  v_distance := public.gps_distance_m(v_shop_lat, v_shop_lng, p_latitude, p_longitude);
  if v_distance > coalesce(v_radius, 100) then raise exception 'NGOAI_VUNG_GPS'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_uid::text, 0));
  select * into v_schedule
  from public.work_schedules
  where id = p_schedule_id and employee_id = v_uid and store_id = v_store
  for update;
  if not found then raise exception 'CA_KHONG_THUOC_NHAN_VIEN'; end if;
  if v_schedule.status not in ('assigned', 'completed') then
    raise exception 'CA_KHONG_THE_CHAM_CONG';
  end if;
  if exists (
    select 1 from public.leave_requests l
    where l.employee_id = v_uid and l.status = 'approved'
      and (v_schedule.start_at at time zone v_timezone)::date <= l.end_date
      and (v_schedule.end_at at time zone v_timezone)::date >= l.start_date
  ) then raise exception 'NGHI_DA_DUYET'; end if;

  select * into v_template
  from public.shift_templates where id = v_schedule.shift_template_id;
  v_allowed := greatest(
    0,
    floor(extract(epoch from (v_schedule.end_at - v_schedule.start_at)) / 60)::integer
      - coalesce(v_template.break_minutes, 0)
  );
  select * into v_att
  from public.attendance where schedule_id = v_schedule.id
  for update;

  if lower(p_action) = 'checkin' then
    if v_att.id is not null and v_att.check_in is not null then raise exception 'DA_CHECKIN'; end if;
    if v_now < v_schedule.start_at - make_interval(mins => coalesce(v_early, 60)) then
      raise exception 'CHUA_DEN_GIO_CHECKIN';
    end if;
    if v_now > v_schedule.start_at + make_interval(mins => v_cutoff) then
      raise exception 'CHECKIN_QUA_HAN_CAN_QUAN_LY';
    end if;
    if v_now > v_schedule.end_at then raise exception 'DA_QUA_CUA_CHECKIN'; end if;

    -- A genuine adjacent shift handoff closes the prior shift exactly at the
    -- scheduled boundary. The employee can then work/check out the new shift
    -- normally, or skip its check-in and have it inferred at the final checkout.
    select * into v_previous
    from public.work_schedules s
    where s.employee_id = v_uid and s.store_id = v_store
      and s.end_at = v_schedule.start_at
      and s.id <> v_schedule.id and s.status in ('assigned', 'completed')
    order by s.start_at desc
    limit 1
    for update;
    if found then
      select * into v_previous_att
      from public.attendance a
      where a.schedule_id = v_previous.id
      for update;
      if v_previous_att.id is not null
         and v_previous_att.check_in is not null
         and v_previous_att.check_out is null then
        select * into v_previous_template
        from public.shift_templates where id = v_previous.shift_template_id;
        v_previous_allowed := greatest(
          0,
          floor(extract(epoch from (v_previous.end_at - v_previous.start_at)) / 60)::integer
            - coalesce(v_previous_template.break_minutes, 0)
        );
        v_previous_worked := greatest(
          0,
          least(
            v_previous_allowed,
            floor(extract(epoch from (
              v_previous.end_at - greatest(v_previous_att.check_in, v_previous.start_at)
            )) / 60)::integer - coalesce(v_previous_template.break_minutes, 0)
          )
        );
        update public.attendance
        set check_out = v_schedule.start_at,
            check_out_latitude = p_latitude,
            check_out_longitude = p_longitude,
            check_out_distance_m = v_distance,
            check_out_status = 'valid'::public.attendance_status,
            worked_minutes = v_previous_worked,
            check_out_device_key = p_device_key,
            updated_at = v_now
        where id = v_previous_att.id;
        update public.work_schedules
        set status = 'completed', updated_at = v_now
        where id = v_previous.id;
        insert into public.attendance_events(
          attendance_id, employee_id, event_type, event_at, latitude, longitude,
          distance_m, device_id, success, metadata
        ) values (
          v_previous_att.id, v_uid, 'check_out_handoff', v_schedule.start_at,
          p_latitude, p_longitude, v_distance, v_device.id, true,
          jsonb_build_object('next_schedule_id', v_schedule.id,
                             'worked_minutes', v_previous_worked,
                             'accuracy_m', p_accuracy_m)
        );
      end if;
    end if;

    v_late := greatest(
      0, floor(extract(epoch from (v_now - v_schedule.start_at)) / 60)::integer
    );
    if v_att.id is null then
      insert into public.attendance(
        schedule_id, employee_id, device_id, check_in, check_in_latitude,
        check_in_longitude, check_in_distance_m, check_in_status, late_minutes,
        check_in_device_key
      ) values (
        v_schedule.id, v_uid, v_device.id, v_now, p_latitude, p_longitude,
        v_distance,
        case when v_late > 0 then 'late'::public.attendance_status
             else 'valid'::public.attendance_status end,
        v_late, p_device_key
      ) returning * into v_att;
    else
      update public.attendance
      set device_id = v_device.id, check_in = v_now,
          check_in_latitude = p_latitude, check_in_longitude = p_longitude,
          check_in_distance_m = v_distance,
          check_in_status = case when v_late > 0 then 'late'::public.attendance_status
                                 else 'valid'::public.attendance_status end,
          late_minutes = v_late, check_in_device_key = p_device_key,
          updated_at = v_now
      where id = v_att.id returning * into v_att;
    end if;

    insert into public.attendance_events(
      attendance_id, employee_id, event_type, event_at, latitude, longitude,
      distance_m, device_id, success, metadata
    ) values (
      v_att.id, v_uid, 'check_in', v_now, p_latitude, p_longitude,
      v_distance, v_device.id, true,
      jsonb_build_object('accuracy_m', p_accuracy_m, 'schedule_id', v_schedule.id,
                         'late_minutes', v_late)
    );
    return jsonb_build_object(
      'attendance_id', v_att.id, 'schedule_id', v_schedule.id,
      'action', 'checkin', 'check_in', v_att.check_in,
      'late_minutes', v_att.late_minutes
    );
  end if;

  -- When no check-in was recorded for this shift, a checkout at the end of an
  -- exactly adjacent shift proves the handoff: both boundary actions are
  -- recorded at the scheduled boundary, then this shift is checked out now.
  if v_att.id is null or v_att.check_in is null then
    select * into v_previous
    from public.work_schedules s
    where s.employee_id = v_uid and s.store_id = v_store
      and s.end_at = v_schedule.start_at
      and s.id <> v_schedule.id and s.status in ('assigned', 'completed')
    order by s.start_at desc
    limit 1
    for update;
    if not found then raise exception 'CHUA_CHECKIN'; end if;

    select * into v_previous_att
    from public.attendance a
    where a.schedule_id = v_previous.id
    for update;
    if v_previous_att.id is null or v_previous_att.check_in is null
       or v_previous_att.check_out is not null then
      raise exception 'CHUA_CHECKIN';
    end if;
    if v_now < v_schedule.start_at then raise exception 'CHUA_DEN_GIO_CHECKOUT'; end if;
    if v_now > v_schedule.end_at + make_interval(mins => v_checkout_grace) then
      raise exception 'QUA_GIO_CHECKOUT';
    end if;

    select * into v_previous_template
    from public.shift_templates where id = v_previous.shift_template_id;
    v_previous_allowed := greatest(
      0,
      floor(extract(epoch from (v_previous.end_at - v_previous.start_at)) / 60)::integer
        - coalesce(v_previous_template.break_minutes, 0)
    );
    v_previous_worked := greatest(
      0,
      least(
        v_previous_allowed,
        floor(extract(epoch from (
          v_previous.end_at - greatest(v_previous_att.check_in, v_previous.start_at)
        )) / 60)::integer - coalesce(v_previous_template.break_minutes, 0)
      )
    );
    update public.attendance
    set check_out = v_schedule.start_at,
        check_out_latitude = p_latitude, check_out_longitude = p_longitude,
        check_out_distance_m = v_distance,
        check_out_status = 'valid'::public.attendance_status,
        worked_minutes = v_previous_worked, check_out_device_key = p_device_key,
        updated_at = v_now
    where id = v_previous_att.id;
    update public.work_schedules
    set status = 'completed', updated_at = v_now
    where id = v_previous.id;

    v_worked := greatest(
      0,
      least(
        v_allowed,
        floor(extract(epoch from (
          least(v_now, v_schedule.end_at) - v_schedule.start_at
        )) / 60)::integer - coalesce(v_template.break_minutes, 0)
      )
    );
    v_early_leave := case when v_now < v_schedule.end_at
      then greatest(0, floor(extract(epoch from (v_schedule.end_at - v_now)) / 60)::integer)
      else 0 end;

    if v_att.id is null then
      insert into public.attendance(
        schedule_id, employee_id, device_id, check_in, check_out,
        check_in_latitude, check_in_longitude, check_in_distance_m,
        check_out_latitude, check_out_longitude, check_out_distance_m,
        check_in_status, check_out_status, late_minutes, early_leave_minutes,
        worked_minutes, check_in_device_key, check_out_device_key
      ) values (
        v_schedule.id, v_uid, v_device.id, v_schedule.start_at, v_now,
        p_latitude, p_longitude, v_distance, p_latitude, p_longitude, v_distance,
        'valid'::public.attendance_status, 'valid'::public.attendance_status,
        0, v_early_leave, v_worked, p_device_key, p_device_key
      ) returning * into v_att;
    else
      update public.attendance
      set device_id = v_device.id, check_in = v_schedule.start_at, check_out = v_now,
          check_in_latitude = p_latitude, check_in_longitude = p_longitude,
          check_in_distance_m = v_distance,
          check_out_latitude = p_latitude, check_out_longitude = p_longitude,
          check_out_distance_m = v_distance,
          check_in_status = 'valid'::public.attendance_status,
          check_out_status = 'valid'::public.attendance_status,
          late_minutes = 0, early_leave_minutes = v_early_leave,
          worked_minutes = v_worked, check_in_device_key = p_device_key,
          check_out_device_key = p_device_key, updated_at = v_now
      where id = v_att.id returning * into v_att;
    end if;

    insert into public.attendance_events(
      attendance_id, employee_id, event_type, event_at, latitude, longitude,
      distance_m, device_id, success, metadata
    ) values
      (v_previous_att.id, v_uid, 'check_out_handoff', v_schedule.start_at,
       p_latitude, p_longitude, v_distance, v_device.id, true,
       jsonb_build_object('next_schedule_id', v_schedule.id,
                          'worked_minutes', v_previous_worked,
                          'accuracy_m', p_accuracy_m)),
      (v_att.id, v_uid, 'check_in_handoff', v_schedule.start_at,
       p_latitude, p_longitude, v_distance, v_device.id, true,
       jsonb_build_object('previous_schedule_id', v_previous.id,
                          'accuracy_m', p_accuracy_m)),
      (v_att.id, v_uid, 'check_out', v_now, p_latitude, p_longitude,
       v_distance, v_device.id, true,
       jsonb_build_object('schedule_id', v_schedule.id,
                          'worked_minutes', v_worked,
                          'early_leave_minutes', v_early_leave,
                          'accuracy_m', p_accuracy_m));

    update public.work_schedules
    set status = 'completed', updated_at = v_now
    where id = v_schedule.id and status = 'assigned';
    return jsonb_build_object(
      'attendance_id', v_att.id, 'schedule_id', v_schedule.id,
      'action', 'checkout', 'check_in', v_att.check_in,
      'check_out', v_att.check_out, 'worked_minutes', v_att.worked_minutes,
      'early_leave_minutes', v_att.early_leave_minutes, 'handoff', true
    );
  end if;

  if v_att.check_out is not null then raise exception 'DA_CHECKOUT'; end if;
  if v_now < v_schedule.start_at then raise exception 'CHUA_DEN_GIO_CHECKOUT'; end if;
  if v_now > v_schedule.end_at + make_interval(mins => v_checkout_grace) then
    raise exception 'QUA_GIO_CHECKOUT';
  end if;

  -- Close an unclosed exact-adjacent prior shift as a fallback for shifts
  -- whose next-shift check-in was recorded before this version was deployed.
  select * into v_previous
  from public.work_schedules s
  where s.employee_id = v_uid and s.store_id = v_store
    and s.end_at = v_schedule.start_at
    and s.id <> v_schedule.id and s.status in ('assigned', 'completed')
  order by s.start_at desc
  limit 1
  for update;
  if found then
    select * into v_previous_att
    from public.attendance a where a.schedule_id = v_previous.id for update;
    if v_previous_att.id is not null and v_previous_att.check_in is not null
       and v_previous_att.check_out is null then
      select * into v_previous_template
      from public.shift_templates where id = v_previous.shift_template_id;
      v_previous_allowed := greatest(
        0,
        floor(extract(epoch from (v_previous.end_at - v_previous.start_at)) / 60)::integer
          - coalesce(v_previous_template.break_minutes, 0)
      );
      v_previous_worked := greatest(
        0,
        least(
          v_previous_allowed,
          floor(extract(epoch from (
            v_previous.end_at - greatest(v_previous_att.check_in, v_previous.start_at)
          )) / 60)::integer - coalesce(v_previous_template.break_minutes, 0)
        )
      );
      update public.attendance
      set check_out = v_schedule.start_at, check_out_latitude = p_latitude,
          check_out_longitude = p_longitude, check_out_distance_m = v_distance,
          check_out_status = 'valid'::public.attendance_status,
          worked_minutes = v_previous_worked, check_out_device_key = p_device_key,
          updated_at = v_now
      where id = v_previous_att.id;
      update public.work_schedules set status = 'completed', updated_at = v_now
      where id = v_previous.id;
      insert into public.attendance_events(
        attendance_id, employee_id, event_type, event_at, latitude, longitude,
        distance_m, device_id, success, metadata
      ) values (
        v_previous_att.id, v_uid, 'check_out_handoff', v_schedule.start_at,
        p_latitude, p_longitude, v_distance, v_device.id, true,
        jsonb_build_object('next_schedule_id', v_schedule.id,
                           'worked_minutes', v_previous_worked,
                           'accuracy_m', p_accuracy_m)
      );
    end if;
  end if;

  v_worked := greatest(
    0,
    least(
      v_allowed,
      floor(extract(epoch from (
        least(v_now, v_schedule.end_at) - greatest(v_att.check_in, v_schedule.start_at)
      )) / 60)::integer - coalesce(v_template.break_minutes, 0)
    )
  );
  v_early_leave := case when v_now < v_schedule.end_at
    then greatest(0, floor(extract(epoch from (v_schedule.end_at - v_now)) / 60)::integer)
    else 0 end;
  update public.attendance
  set check_out = v_now, check_out_latitude = p_latitude,
      check_out_longitude = p_longitude, check_out_distance_m = v_distance,
      check_out_status = 'valid'::public.attendance_status,
      early_leave_minutes = v_early_leave, worked_minutes = v_worked,
      check_out_device_key = p_device_key, updated_at = v_now
  where id = v_att.id returning * into v_att;
  update public.work_schedules
  set status = 'completed', updated_at = v_now
  where id = v_schedule.id and status = 'assigned';
  insert into public.attendance_events(
    attendance_id, employee_id, event_type, event_at, latitude, longitude,
    distance_m, device_id, success, metadata
  ) values (
    v_att.id, v_uid, 'check_out', v_now, p_latitude, p_longitude,
    v_distance, v_device.id, true,
    jsonb_build_object('accuracy_m', p_accuracy_m, 'schedule_id', v_schedule.id,
                       'worked_minutes', v_worked,
                       'early_leave_minutes', v_early_leave,
                       'scheduled_end', v_schedule.end_at,
                       'checkout_grace_minutes', v_checkout_grace)
  );
  return jsonb_build_object(
    'attendance_id', v_att.id, 'schedule_id', v_schedule.id,
    'action', 'checkout', 'check_out', v_att.check_out,
    'worked_minutes', v_att.worked_minutes,
    'early_leave_minutes', v_att.early_leave_minutes,
    'capped_at_end', v_now > v_schedule.end_at
  );
end;
$$;


--
-- Name: auto_finalize_due_shift_registrations(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_finalize_due_shift_registrations() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  w record;
  r record;
  s public.work_schedules%rowtype;
  conflict_id uuid;
  rule_auto_approve boolean;
  approved integer:=0;
  rejected integer:=0;
  windows_done integer:=0;
  total_approved integer:=0;
  total_rejected integer:=0;
begin
  for w in
    select *
    from public.shift_registration_windows
    where status='open' and close_at<=now()
    order by close_at
    for update
  loop
    select coalesce(rr.auto_approve,true)
      into rule_auto_approve
    from public.shift_registration_recurring_rules rr
    where rr.store_id=w.store_id and rr.is_active=true
    limit 1;

    if coalesce(rule_auto_approve,true) then
      approved:=0; rejected:=0;

      for r in
        select sr.id registration_id,sr.employee_id,sr.schedule_id
        from public.shift_registrations sr
        join public.work_schedules ws on ws.id=sr.schedule_id
        where sr.status='pending'
          and ws.store_id=w.store_id
          and ws.work_date>=w.week_start
          and ws.work_date<w.week_start+7
        order by sr.requested_at,sr.id
        for update of sr
      loop
        select * into s
        from public.work_schedules
        where id=r.schedule_id
        for update;

        if not found or s.status<>'open' or s.employee_id is not null then
          update public.shift_registrations
          set status='rejected',reviewed_at=now(),
              rejection_reason='Ca không còn chỗ tại thời điểm tự chốt',
              updated_at=now()
          where id=r.registration_id;
          rejected:=rejected+1;
          continue;
        end if;

        select id into conflict_id
        from public.employee_schedule_conflict(
          r.employee_id,s.start_at,s.end_at,s.id
        );

        if conflict_id is not null then
          update public.shift_registrations
          set status='rejected',reviewed_at=now(),
              rejection_reason='Nhân viên bị trùng ca tại thời điểm tự chốt',
              updated_at=now()
          where id=r.registration_id;
          rejected:=rejected+1;
          continue;
        end if;

        update public.shift_registrations
        set status='approved',reviewed_at=now(),
            rejection_reason=null,updated_at=now()
        where id=r.registration_id;

        update public.work_schedules
        set employee_id=r.employee_id,status='assigned',
            assigned_at=now(),updated_at=now()
        where id=s.id;

        approved:=approved+1;
      end loop;

      total_approved:=total_approved+approved;
      total_rejected:=total_rejected+rejected;
    end if;

    update public.shift_registration_windows
    set status='finalized',
        finalized_at=now(),
        updated_at=now()
    where id=w.id;

    insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
    values(
      null,'auto_finalize_shift_registrations','shift_registration_window',w.id,
      jsonb_build_object(
        'week_start',w.week_start,
        'auto_approve',coalesce(rule_auto_approve,true),
        'approved',approved,
        'rejected',rejected
      )
    );

    windows_done:=windows_done+1;
  end loop;

  return jsonb_build_object(
    'windows',windows_done,
    'approved',total_approved,
    'rejected',total_rejected
  );
end;
$$;


--
-- Name: auto_generate_weekly_schedule_from_plan(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_generate_weekly_schedule_from_plan(p_store_id uuid, p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_week date:=date_trunc('week',p_week_start)::date;
  v_tz text;
  v_item record;
  v_tpl record;
  v_work_date date;
  v_group uuid;
  v_hash text;
  v_existing integer;
  v_needed integer;
  v_created integer:=0;
  v_groups integer:=0;
  v_template_ok boolean;
  v_start_at timestamptz;
  v_end_at timestamptz;
  i integer;
begin
  if p_store_id is null then raise exception 'STORE_NOT_FOUND'; end if;

  select coalesce(timezone,'Asia/Ho_Chi_Minh')
    into v_tz
  from public.stores
  where id=p_store_id;
  if not found then raise exception 'STORE_NOT_FOUND'; end if;

  for v_item in
    select id,weekday,shift_template_id,capacity,note,sort_order
    from public.weekly_shift_plan_items
    where store_id=p_store_id
      and is_active=true
    order by weekday,sort_order,id
  loop
    v_work_date:=v_week+(v_item.weekday-1);

    select id,name,start_time,end_time,is_active
      into v_tpl
    from public.shift_templates
    where id=v_item.shift_template_id
      and store_id=p_store_id;

    if not found or not coalesce(v_tpl.is_active,false) then
      continue;
    end if;

    v_needed:=greatest(1,least(50,coalesce(v_item.capacity,1)));

    -- Respect schedules that were already created manually or by an older
    -- generator for the same day/template. Do not duplicate capacity.
    select count(*)::integer
      into v_existing
    from public.work_schedules ws
    where ws.store_id=p_store_id
      and ws.work_date=v_work_date
      and ws.shift_template_id=v_item.shift_template_id
      and ws.status<>'cancelled';

    if v_existing>=v_needed then
      continue;
    end if;

    v_hash:=md5(p_store_id::text||'|'||v_week::text||'|'||v_item.id::text);
    v_group:=substr(v_hash,1,8)||'-'||substr(v_hash,9,4)||'-'||substr(v_hash,13,4)||'-'||substr(v_hash,17,4)||'-'||substr(v_hash,21,12);
    v_group:=v_group::uuid;

    v_start_at:=((v_work_date+v_tpl.start_time) at time zone v_tz);
    v_end_at:=((v_work_date+v_tpl.end_time) at time zone v_tz);
    if v_tpl.end_time<=v_tpl.start_time then
      v_end_at:=v_end_at+interval '1 day';
    end if;

    for i in 1..greatest(0,v_needed-v_existing) loop
      insert into public.work_schedules(
        store_id,shift_template_id,shift_group_id,work_date,start_time,end_time,
        start_at,end_at,employee_id,status,note,created_by
      ) values(
        p_store_id,v_item.shift_template_id,v_group,v_work_date,v_tpl.start_time,v_tpl.end_time,
        v_start_at,v_end_at,null,'open',
        concat_ws(' · ',nullif(trim(v_item.note),''),'Tự động từ mẫu lịch tuần'),
        null
      );
      v_created:=v_created+1;
    end loop;

    if v_needed>v_existing then v_groups:=v_groups+1; end if;
  end loop;

  return jsonb_build_object(
    'week_start',v_week,
    'created_slots',v_created,
    'created_groups',v_groups
  );
end;
$$;


--
-- Name: can_manager_view_employee_payroll(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manager_view_employee_payroll(p_employee_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
  SELECT coalesce(
    public.my_role() = 'manager'
    AND public.current_user_has_manager_permission('payroll_view')
    AND EXISTS (
      SELECT 1
      FROM public.profiles p
      WHERE p.id = p_employee_id
        AND p.store_id IS NOT NULL
        AND public.is_store_member(p.store_id)
    ),
    false
  );
$$;


--
-- Name: can_manager_view_payroll_run(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_manager_view_payroll_run(p_payroll_period_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
  SELECT coalesce(
    public.my_role() = 'manager'
    AND public.current_user_has_manager_permission('payroll_view')
    AND EXISTS (
      SELECT 1
      FROM public.payroll_periods pp
      WHERE pp.id = p_payroll_period_id
        AND public.is_store_member(pp.store_id)
    ),
    false
  );
$$;


--
-- Name: can_owner_manage_payroll_run(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.can_owner_manage_payroll_run(p_payroll_period_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
  select coalesce(public.is_owner(), false)
    and exists (
      select 1
      from public.payroll_periods as pp
      where pp.id = p_payroll_period_id
        and public.is_store_owner(pp.store_id)
    );
$$;


--
-- Name: cancel_work_schedule(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_work_schedule(p_schedule_id uuid, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select * into v_schedule from public.work_schedules where id=p_schedule_id for update;
  if not found then raise exception 'CA_NOT_FOUND'; end if;
  if v_schedule.store_id is distinct from v_store then raise exception 'FORBIDDEN'; end if;
  if v_schedule.status='cancelled' then raise exception 'CA_DA_HUY'; end if;
  if v_schedule.status='completed' then raise exception 'CA_DA_HOAN_TAT'; end if;
  if exists(select 1 from public.attendance where schedule_id=p_schedule_id and check_in is not null) then
    raise exception 'CA_DA_CHECKIN_KHONG_THE_HUY';
  end if;

  update public.work_schedules
  set status='cancelled',note=concat_ws(' · ',nullif(note,''),nullif(trim(p_reason),''))
  where id=p_schedule_id;

  update public.shift_registrations
  set status='cancelled',reviewed_by=auth.uid(),reviewed_at=now(),
      rejection_reason=coalesce(nullif(trim(p_reason),''),'Ca đã bị hủy')
  where schedule_id=p_schedule_id and status in ('pending','approved');

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'cancel_work_schedule','work_schedule',p_schedule_id,
         jsonb_build_object('reason',nullif(trim(coalesce(p_reason,'')),'')));
  return true;
end;
$$;


--
-- Name: close_shift_registration_window(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.close_shift_registration_window(p_week_start date) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_store uuid; v_role text; v_row public.shift_registration_windows%rowtype;
begin
  select store_id,role::text into v_store,v_role from public.profiles where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  select * into v_row from public.shift_registration_windows where store_id=v_store and week_start=date_trunc('week',p_week_start)::date for update;
  if not found then raise exception 'CHUA_CAI_CUA_SO_DANG_KY'; end if;
  if v_row.status='finalized' then raise exception 'TUAN_DA_CHOT'; end if;
  update public.shift_registration_windows set status='closed',closed_at=now(),closed_by=auth.uid(),updated_at=now() where id=v_row.id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(auth.uid(),'close_shift_registration_window','shift_registration_window',v_row.id,jsonb_build_object('week_start',v_row.week_start));
  return true;
end; $$;


--
-- Name: confirm_late_checkin(uuid, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_late_checkin(p_schedule_id uuid, p_check_in_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text; v_store uuid; v_schedule public.work_schedules%rowtype; v_att public.attendance%rowtype; v_employee uuid; v_in timestamptz; v_late integer; v_device public.devices%rowtype;
begin
  select role::text,store_id into v_role,v_store from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  select * into v_schedule from public.work_schedules where id=p_schedule_id and store_id=v_store for update;
  if not found or v_schedule.employee_id is null then raise exception 'CA_NOT_FOUND'; end if;
  if v_schedule.status<>'assigned' then raise exception 'CA_KHONG_THE_XU_LY'; end if;
  if v_schedule.start_at>now() then raise exception 'CA_CHUA_BAT_DAU'; end if;
  if now()>v_schedule.end_at then raise exception 'CA_DA_KET_THUC'; end if;
  if exists(select 1 from public.attendance a where a.schedule_id=v_schedule.id and a.check_in is not null) then raise exception 'DA_CHECKIN'; end if;
  v_in:=coalesce(p_check_in_at,now());
  if v_in>now() or v_in<v_schedule.start_at then raise exception 'GIO_CHECKIN_KHONG_HOP_LE'; end if;
  if v_in>v_schedule.end_at then raise exception 'GIO_CHECKIN_KHONG_HOP_LE'; end if;
  select * into v_device from public.devices where employee_id=v_schedule.employee_id and status='approved' order by approved_at desc nulls last limit 1;
  v_late:=greatest(0,floor(extract(epoch from(v_in-v_schedule.start_at))/60)::integer);
  insert into public.attendance(schedule_id,employee_id,device_id,check_in,check_in_status,late_minutes,note,check_in_device_key)
  values(v_schedule.id,v_schedule.employee_id,v_device.id,v_in,'manual',v_late,concat_ws(' · ','Quản lý xác nhận check-in muộn',nullif(trim(p_note),'')),v_device.device_key)
  returning * into v_att;
  insert into public.attendance_events(attendance_id,employee_id,event_type,event_at,success,reason,metadata)
  values(v_att.id,v_att.employee_id,'manual_check_in',now(),true,'Quản lý xác nhận check-in muộn',jsonb_build_object('schedule_id',v_schedule.id,'check_in_at',v_in,'late_minutes',v_late,'actor_id',auth.uid()));
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'confirm_late_checkin','attendance',v_att.id,jsonb_build_object('schedule_id',v_schedule.id,'employee_id',v_att.employee_id,'check_in_at',v_in,'late_minutes',v_late));
  return jsonb_build_object('attendance_id',v_att.id,'schedule_id',v_schedule.id,'check_in',v_att.check_in,'late_minutes',v_att.late_minutes);
end;
$$;


--
-- Name: create_branch(text, text, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_branch(p_name text, p_address text DEFAULT NULL::text, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_current public.stores%rowtype;
  v_new public.stores%rowtype;
  v_current_store_id uuid;
  v_role text;
  v_rule public.shift_registration_recurring_rules%rowtype;
begin
  if v_uid is null then raise exception 'UNAUTHENTICATED'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'TEN_CHI_NHANH_KHONG_HOP_LE'; end if;

  select role::text,store_id into v_role,v_current_store_id
  from public.profiles
  where id=v_uid and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;

  if v_current_store_id is not null then
    select * into v_current from public.stores where id=v_current_store_id;
  end if;
  if v_current.id is null or not public.is_store_owner(v_current.id) then
    raise exception 'STORE_CONTEXT_MISSING';
  end if;

  insert into public.stores(
    name,address,latitude,longitude,gps_radius_m,late_grace_minutes,
    checkin_early_minutes,checkout_late_minutes,timezone,wifi_enabled,
    wifi_name,wifi_note,hourly_default_rate
  ) values(
    trim(p_name),nullif(trim(p_address),''),
    coalesce(p_latitude,v_current.latitude),coalesce(p_longitude,v_current.longitude),
    v_current.gps_radius_m,v_current.late_grace_minutes,
    v_current.checkin_early_minutes,v_current.checkout_late_minutes,
    v_current.timezone,v_current.wifi_enabled,v_current.wifi_name,v_current.wifi_note,
    v_current.hourly_default_rate
  ) returning * into v_new;

  insert into public.store_memberships(user_id,store_id,role,is_active)
  values(v_uid,v_new.id,'owner',true);

  -- Give the new branch the same recurring registration window defaults,
  -- but do not create schedules or registrations.
  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id=v_current.id and is_active=true
  order by created_at desc limit 1;
  if found then
    insert into public.shift_registration_recurring_rules(
      store_id,open_weekday,open_time,close_weekday,close_time,is_active
    ) values(
      v_new.id,v_rule.open_weekday,v_rule.open_time,v_rule.close_weekday,v_rule.close_time,true
    );
  end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data,store_id)
  values(
    v_uid,'create_branch','store',v_new.id,
    jsonb_build_object('name',v_new.name,'address',v_new.address),v_new.id
  );

  return jsonb_build_object('id',v_new.id,'name',v_new.name,'address',v_new.address);
end;
$$;


--
-- Name: create_schedule_slots(uuid, uuid, date, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_schedule_slots(p_store_id uuid, p_shift_template_id uuid, p_work_date date, p_note text DEFAULT NULL::text, p_slots integer DEFAULT 1) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text; v_manager_store uuid; v_template public.shift_template_versions%rowtype;
  v_created integer:=0; v_group uuid:=gen_random_uuid(); v_tz text; v_today date;
begin
  select role::text,store_id into v_role,v_manager_store from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') or v_manager_store is distinct from p_store_id then raise exception 'FORBIDDEN'; end if;
  if p_slots<1 or p_slots>10 then raise exception 'Số vị trí ca phải từ 1 đến 10'; end if;
  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz from public.stores where id=p_store_id;
  v_today:=(now() at time zone v_tz)::date;
  if p_work_date<v_today then raise exception 'Không thể tạo ca cho ngày đã qua'; end if;
  select * into v_template from public.get_shift_template_version(p_shift_template_id,p_work_date);
  if not found or v_template.shift_template_id is null or v_template.is_active=false then raise exception 'Mẫu ca không tồn tại hoặc chưa có hiệu lực'; end if;
  for i in 1..p_slots loop
    insert into public.work_schedules(store_id,shift_template_id,shift_group_id,work_date,start_time,end_time,employee_id,status,note,created_by)
    values(p_store_id,p_shift_template_id,v_group,p_work_date,v_template.start_time,v_template.end_time,null,'open',nullif(trim(p_note),''),auth.uid());
    v_created:=v_created+1;
  end loop;
  return v_created;
end;
$$;


--
-- Name: create_supplemental_schedule(uuid, date, text, time without time zone, time without time zone, uuid[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_supplemental_schedule(p_store_id uuid, p_work_date date, p_name text, p_start_time time without time zone, p_end_time time without time zone, p_employee_ids uuid[], p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_my_store uuid;
  v_tz text;
  v_today date;
  v_group uuid := gen_random_uuid();
  v_employee uuid;
  v_schedule_id uuid;
  v_conflict uuid;
  v_count integer := 0;
  v_start_at timestamptz;
  v_end_at timestamptz;
begin
  select role::text,store_id into v_role,v_my_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') or v_my_store is distinct from p_store_id then
    raise exception 'FORBIDDEN';
  end if;
  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz from public.stores where id=p_store_id;
  v_tz:=coalesce(v_tz,'Asia/Ho_Chi_Minh');
  v_today:=(now() at time zone v_tz)::date;
  if p_work_date is null or p_work_date<v_today then raise exception 'Không thể tạo ca cho ngày đã qua'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Tên ca không được để trống'; end if;
  if p_start_time is null or p_end_time is null or p_start_time=p_end_time then raise exception 'Giờ bắt đầu và kết thúc không hợp lệ'; end if;
  if p_employee_ids is null or cardinality(p_employee_ids)=0 then raise exception 'Hãy chọn ít nhất một nhân viên'; end if;
  if cardinality(p_employee_ids)>10 then raise exception 'Một ca chỉ được tối đa 10 nhân viên'; end if;

  v_start_at := ((p_work_date+p_start_time) at time zone v_tz);
  v_end_at := ((p_work_date+p_end_time) at time zone v_tz)
    + case when p_end_time<=p_start_time then interval '1 day' else interval '0 day' end;
  if v_end_at<=v_start_at then raise exception 'CA_THOI_GIAN_KHONG_HOP_LE'; end if;

  -- Validate all employees before creating anything.
  foreach v_employee in array p_employee_ids loop
    if v_employee is null then raise exception 'Nhân viên không hợp lệ'; end if;
    if not exists(
      select 1 from public.profiles p
      where p.id=v_employee and p.store_id=p_store_id
        and p.role='employee' and p.employment_status='active'
    ) then raise exception 'NHAN_VIEN_KHONG_HOP_LE'; end if;
    if public.employee_schedule_conflict(v_employee,v_start_at,v_end_at,null) is not null then
      raise exception 'NHAN_VIEN_TRUNG_CA';
    end if;
  end loop;

  -- One row per employee, same shift_group_id, so the existing schedule model remains intact.
  foreach v_employee in array p_employee_ids loop
    insert into public.work_schedules(
      store_id,shift_template_id,shift_group_id,work_date,start_time,end_time,
      employee_id,status,note,created_by,assigned_at,schedule_kind,custom_name
    ) values(
      p_store_id,null,v_group,p_work_date,p_start_time,p_end_time,
      v_employee,'assigned',nullif(trim(p_note),''),auth.uid(),now(),'supplemental',trim(p_name)
    ) returning id into v_schedule_id;
    v_count:=v_count+1;
  end loop;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'create_supplemental_schedule','work_schedule',v_group,
         jsonb_build_object('work_date',p_work_date,'name',trim(p_name),'start_time',p_start_time,'end_time',p_end_time,'employee_ids',p_employee_ids,'count',v_count));

  return jsonb_build_object('shift_group_id',v_group,'created_count',v_count,'name',trim(p_name));
end;
$$;


--
-- Name: current_user_has_manager_permission(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.current_user_has_manager_permission(p_permission_key text) RETURNS boolean
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


--
-- Name: delete_supplemental_schedule(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.delete_supplemental_schedule(p_schedule_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
  v_group uuid;
  v_now timestamptz:=now();
  v_count integer:=0;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select * into v_schedule
  from public.work_schedules
  where id=p_schedule_id and store_id=v_store
  for update;
  if not found then raise exception 'CA_NOT_FOUND'; end if;
  if coalesce(v_schedule.schedule_kind,'template')<>'supplemental' then
    raise exception 'CA_KHONG_PHAI_BO_SUNG';
  end if;

  v_group:=coalesce(v_schedule.shift_group_id,v_schedule.id);

  perform pg_advisory_xact_lock(
    hashtextextended(v_store::text || ':' || v_group::text || ':delete_supplemental',0)
  );

  if exists (
    select 1 from public.work_schedules ws
    where ws.store_id=v_store
      and coalesce(ws.shift_group_id,ws.id)=v_group
      and ws.status<>'cancelled'
      and ws.start_at is not null
      and v_now>=ws.start_at
  ) then
    raise exception 'CA_DA_BAT_DAU';
  end if;

  if exists (
    select 1
    from public.attendance a
    join public.work_schedules ws on ws.id=a.schedule_id
    where ws.store_id=v_store
      and coalesce(ws.shift_group_id,ws.id)=v_group
      and (a.check_in is not null or a.check_out is not null)
  ) then
    raise exception 'DA_CO_CHAM_CONG';
  end if;

  delete from public.attendance a
  using public.work_schedules ws
  where a.schedule_id=ws.id
    and ws.store_id=v_store
    and coalesce(ws.shift_group_id,ws.id)=v_group;

  update public.shift_registrations
  set status='cancelled',reviewed_by=auth.uid(),reviewed_at=v_now,
      rejection_reason='Ca bổ sung đã bị xóa',updated_at=v_now
  where schedule_id in (
    select ws.id from public.work_schedules ws
    where ws.store_id=v_store and coalesce(ws.shift_group_id,ws.id)=v_group
  )
  and status in ('pending','approved');

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data)
  select auth.uid(),'delete_supplemental_schedule','work_schedule',v_group,
    jsonb_build_object('work_date',v_schedule.work_date,'name',v_schedule.custom_name,
      'start_time',v_schedule.start_time,'end_time',v_schedule.end_time,
      'employee_id',ws.employee_id,'schedule_id',ws.id)
  from public.work_schedules ws
  where ws.store_id=v_store
    and coalesce(ws.shift_group_id,ws.id)=v_group
    and ws.status<>'cancelled';

  delete from public.work_schedules
  where store_id=v_store
    and coalesce(shift_group_id,id)=v_group;

  get diagnostics v_count=row_count;

  return jsonb_build_object('shift_group_id',v_group,'deleted_slots',v_count);
end;
$$;


--
-- Name: employee_get_payroll_advance_limit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_get_payroll_advance_limit() RETURNS jsonb
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_timezone text;
  v_month_start date;
  v_month_end date;
  v_earned numeric;
  v_requested numeric;
  v_count integer;
  v_pending_count integer;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = v_uid
    and p.role = 'employee'::public.user_role
    and p.employment_status = 'active'::public.employment_status;
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select coalesce(s.timezone, 'Asia/Ho_Chi_Minh') into v_timezone
  from public.stores s where s.id = v_store;

  v_month_start := date_trunc(
    'month', now() at time zone v_timezone
  )::date;
  v_month_end := (v_month_start + interval '1 month')::date;

  select coalesce(sum(
    a.worked_minutes * public.get_employee_hourly_rate(a.employee_id, s.work_date) / 60
  ), 0)
  into v_earned
  from public.attendance a
  join public.work_schedules s on s.id = a.schedule_id
  where a.employee_id = v_uid
    and s.store_id = v_store
    and s.work_date >= v_month_start
    and s.work_date < v_month_end
    and a.check_in is not null
    and a.check_out is not null;

  select count(*)::integer,
         count(*) filter (where a.status = 'pending'::public.adjustment_status)::integer,
         coalesce(sum(a.amount), 0)
  into v_count, v_pending_count, v_requested
  from public.payroll_adjustments a
  where a.employee_id = v_uid
    and a.adjustment_type = 'advance'::public.adjustment_type
    and a.status in (
      'pending'::public.adjustment_status,
      'approved'::public.adjustment_status
    )
    and a.created_at >= (v_month_start::timestamp at time zone v_timezone)
    and a.created_at < (v_month_end::timestamp at time zone v_timezone);

  return jsonb_build_object(
    'month_start', v_month_start,
    'earned_amount', round(v_earned, 2),
    'maximum_amount', round(v_earned * 0.5, 2),
    'requested_amount', round(v_requested, 2),
    'remaining_amount', greatest(0, round(v_earned * 0.5 - v_requested, 2)),
    'request_count', v_count,
    'pending_count', v_pending_count,
    'monthly_request_limit', 2
  );
end;
$$;


--
-- Name: employee_request_payroll_advance(numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_request_payroll_advance(p_amount numeric, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_timezone text;
  v_id uuid;
  v_month_start date;
  v_month_end date;
  v_earned numeric;
  v_requested numeric;
  v_request_count integer;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = v_uid
    and p.role = 'employee'::public.user_role
    and p.employment_status = 'active'::public.employment_status;

  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  if p_amount is null or p_amount <= 0
     or length(trim(coalesce(p_reason, ''))) = 0 then
    raise exception 'KHOAN_TAM_UNG_KHONG_HOP_LE';
  end if;

  select coalesce(s.timezone, 'Asia/Ho_Chi_Minh') into v_timezone
  from public.stores s where s.id = v_store;

  perform pg_advisory_xact_lock(
    hashtextextended(v_uid::text || ':payroll-advance:' ||
      to_char((now() at time zone v_timezone)::date, 'YYYY-MM'), 0)
  );

  v_month_start := date_trunc(
    'month', now() at time zone v_timezone
  )::date;
  v_month_end := (v_month_start + interval '1 month')::date;

  select coalesce(sum(
    a.worked_minutes * public.get_employee_hourly_rate(a.employee_id, s.work_date) / 60
  ), 0)
  into v_earned
  from public.attendance a
  join public.work_schedules s on s.id = a.schedule_id
  where a.employee_id = v_uid
    and s.store_id = v_store
    and s.work_date >= v_month_start
    and s.work_date < v_month_end
    and a.check_in is not null
    and a.check_out is not null;

  select count(*)::integer, coalesce(sum(a.amount), 0)
  into v_request_count, v_requested
  from public.payroll_adjustments a
  where a.employee_id = v_uid
    and a.adjustment_type = 'advance'::public.adjustment_type
    and a.status in (
      'pending'::public.adjustment_status,
      'approved'::public.adjustment_status
    )
    and a.created_at >= (v_month_start::timestamp at time zone v_timezone)
    and a.created_at < (v_month_end::timestamp at time zone v_timezone);

  if v_request_count >= 2 then
    raise exception 'TAM_UNG_VUOT_SO_LAN_THANG';
  end if;
  if v_requested + p_amount > round(v_earned * 0.5, 2) then
    raise exception 'TAM_UNG_VUOT_HAN_MUC_50_PERCENT';
  end if;

  insert into public.payroll_adjustments(
    employee_id, payroll_period_id, adjustment_type, amount, reason,
    status, created_by
  )
  values (
    v_uid, null, 'advance'::public.adjustment_type, p_amount,
    trim(p_reason), 'pending'::public.adjustment_status, v_uid
  )
  returning id into v_id;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    v_uid, v_store, 'employee_request_payroll_advance',
    'payroll_adjustment', v_id,
    jsonb_build_object('amount', p_amount, 'reason', trim(p_reason))
  );

  return v_id;
end;
$$;


--
-- Name: employee_schedule_conflict(uuid, timestamp with time zone, timestamp with time zone, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.employee_schedule_conflict(p_employee_id uuid, p_start_at timestamp with time zone, p_end_at timestamp with time zone, p_exclude_schedule_id uuid DEFAULT NULL::uuid) RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select s.id
  from public.work_schedules s
  where s.employee_id = p_employee_id
    and s.id is distinct from p_exclude_schedule_id
    and s.status in ('open','assigned')
    and s.start_at < p_end_at
    and s.end_at > p_start_at
  union all
  select s.id
  from public.work_schedules s
  join public.shift_registrations r on r.schedule_id=s.id
  where r.employee_id = p_employee_id
    and r.status = 'pending'
    and s.id is distinct from p_exclude_schedule_id
    and s.status = 'open'
    and s.start_at < p_end_at
    and s.end_at > p_start_at
  limit 1;
$$;


--
-- Name: enforce_manager_business_permission(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.enforce_manager_business_permission() RETURNS trigger
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


--
-- Name: ensure_recurring_shift_registration_windows(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_recurring_shift_registration_windows() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  r record;
  d integer;
  ws date;
  x record;
  n integer:=0;
begin
  for r in
    select * from public.shift_registration_recurring_rules
    where is_active=true
  loop
    for d in 0..8 loop
      ws:=date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date+(d*7);

      select * into x
      from public.registration_window_times(
        ws,r.open_weekday,r.open_time,r.close_weekday,r.close_time
      );

      insert into public.shift_registration_windows(
        store_id,week_start,open_at,close_at,status
      )
      values(r.store_id,ws,x.open_at,x.close_at,'open')
      on conflict(store_id,week_start) do update set
        open_at=case when public.shift_registration_windows.status='finalized'
                     then public.shift_registration_windows.open_at else excluded.open_at end,
        close_at=case when public.shift_registration_windows.status='finalized'
                      then public.shift_registration_windows.close_at else excluded.close_at end;

      n:=n+1;
    end loop;
  end loop;

  return jsonb_build_object('windows_checked',n);
end;
$$;


--
-- Name: ensure_shift_registration_window(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_shift_registration_window(p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_week date:=date_trunc('week',p_week_start)::date;
  v_row public.shift_registration_windows%rowtype;
  v_sync jsonb;
begin
  select store_id into v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  perform public.sync_shift_registration_automation();

  select * into v_row
  from public.shift_registration_windows
  where store_id=v_store and week_start=v_week;

  if not found then return null; end if;

  return jsonb_build_object(
    'id',v_row.id,'store_id',v_row.store_id,'week_start',v_row.week_start,
    'open_at',v_row.open_at,'close_at',v_row.close_at,'status',v_row.status
  );
end;
$$;


--
-- Name: finalize_shift_registrations(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.finalize_shift_registrations(p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid; v_role text; v_week date; v_window public.shift_registration_windows%rowtype; r record; v_schedule public.work_schedules%rowtype; v_conflict uuid; v_approved integer:=0; v_rejected integer:=0;
begin
  select store_id,role::text into v_store,v_role from public.profiles where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  v_week:=date_trunc('week',p_week_start)::date;
  select * into v_window from public.shift_registration_windows where store_id=v_store and week_start=v_week for update;
  if not found then raise exception 'CHUA_CAI_CUA_SO_DANG_KY'; end if;
  if v_window.status='finalized' then return jsonb_build_object('approved',0,'rejected',0,'already_finalized',true); end if;
  if v_window.status<>'closed' and now()<v_window.close_at then raise exception 'DANG_KY_CHUA_KET_THUC'; end if;
  for r in select sr.id as registration_id,sr.employee_id,sr.schedule_id,sr.requested_at from public.shift_registrations sr join public.work_schedules ws on ws.id=sr.schedule_id where sr.status='pending' and ws.store_id=v_store and ws.work_date>=v_week and ws.work_date< v_week+7 order by sr.requested_at,sr.id for update of sr
  loop
    select * into v_schedule from public.work_schedules where id=r.schedule_id for update;
    if v_schedule.status<>'open' or v_schedule.employee_id is not null then
      update public.shift_registrations set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason='Ca không còn chỗ tại thời điểm chốt',updated_at=now() where id=r.registration_id; v_rejected:=v_rejected+1; continue;
    end if;
    select id into v_conflict from public.employee_schedule_conflict(r.employee_id,v_schedule.start_at,v_schedule.end_at,v_schedule.id);
    if v_conflict is not null then
      update public.shift_registrations set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason='Nhân viên bị trùng ca tại thời điểm chốt',updated_at=now() where id=r.registration_id; v_rejected:=v_rejected+1; continue;
    end if;
    update public.shift_registrations set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason=null,updated_at=now() where id=r.registration_id;
    update public.work_schedules set employee_id=r.employee_id,status='assigned',assigned_at=now(),updated_at=now() where id=v_schedule.id;
    v_approved:=v_approved+1;
  end loop;
  update public.shift_registration_windows set status='finalized',finalized_at=now(),finalized_by=auth.uid(),updated_at=now() where id=v_window.id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(auth.uid(),'finalize_shift_registrations','shift_registration_window',v_window.id,jsonb_build_object('week_start',v_week,'approved',v_approved,'rejected',v_rejected));
  return jsonb_build_object('approved',v_approved,'rejected',v_rejected,'already_finalized',false);
end; $$;


--
-- Name: generate_weekly_schedule_from_plan(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.generate_weekly_schedule_from_plan(p_store_id uuid, p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_store uuid;
  v_tz text := 'Asia/Ho_Chi_Minh';
  v_local_today date;
  v_local_monday date;
  v_item record;
  v_template public.shift_templates%rowtype;
  v_work_date date;
  v_group uuid;
  v_created_slots integer := 0;
  v_created_groups integer := 0;
  v_skipped_groups integer := 0;
  v_existing_group uuid;
  v_start time;
  v_end time;
  v_note text;
  i integer;
begin
  select role::text, store_id into v_role, v_store
  from public.profiles
  where id = v_uid and employment_status = 'active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  if v_store is null or v_store <> p_store_id then raise exception 'FORBIDDEN'; end if;
  if p_week_start is null then raise exception 'TUẦN_KHÔNG_HỢP_LỆ'; end if;
  if extract(isodow from p_week_start) <> 1 then raise exception 'TUẦN_PHẢI_BẮT_ĐẦU_THỨ_HAI'; end if;

  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz
  from public.stores where id = v_store;
  v_tz := coalesce(v_tz,'Asia/Ho_Chi_Minh');
  v_local_today := (now() at time zone v_tz)::date;
  v_local_monday := v_local_today - (extract(isodow from v_local_today)::integer - 1);
  if p_week_start < v_local_monday then raise exception 'KHÔNG_THỂ_TẠO_TUẦN_ĐÃ_QUA'; end if;

  for v_item in
    select * from public.weekly_shift_plan_items
    where store_id = v_store and is_active = true
    order by weekday, sort_order, id
  loop
    v_work_date := p_week_start + (v_item.weekday - 1);

    -- A non-cancelled generated group already exists for this plan item/date.
    select s.shift_group_id into v_existing_group
    from public.work_schedules s
    where s.store_id = v_store
      and s.work_date = v_work_date
      and s.weekly_plan_item_id = v_item.id
      and s.status <> 'cancelled'
    order by s.shift_group_id
    limit 1;
    if v_existing_group is not null then
      v_skipped_groups := v_skipped_groups + 1;
      continue;
    end if;

    select * into v_template
    from public.shift_templates
    where id = v_item.shift_template_id
      and store_id = v_store
      and is_active = true;
    if not found then raise exception 'Mẫu ca của lịch tuần đã bị tắt hoặc xóa'; end if;

    v_start := v_template.start_time;
    v_end := v_template.end_time;
    v_note := v_item.note;
    v_group := gen_random_uuid();

    -- If an identical open/assigned group already exists for this date/time/template,
    -- attach it to the plan item instead of creating duplicate shifts.
    declare
      v_existing_slots integer := 0;
    begin
      select s.shift_group_id into v_existing_group
      from public.work_schedules s
      where s.store_id = v_store
        and s.work_date = v_work_date
        and s.shift_template_id = v_template.id
        and s.start_time = v_start
        and s.end_time = v_end
        and s.status in ('open','assigned')
      order by s.shift_group_id
      limit 1;

      if v_existing_group is not null then
        select count(*) into v_existing_slots
        from public.work_schedules s
        where s.store_id = v_store
          and s.work_date = v_work_date
          and s.shift_group_id = v_existing_group
          and s.status in ('open','assigned');

        update public.work_schedules
        set weekly_plan_item_id = v_item.id
        where store_id = v_store
          and work_date = v_work_date
          and shift_group_id = v_existing_group
          and status in ('open','assigned')
          and weekly_plan_item_id is null;

        if v_existing_slots < v_item.capacity then
          for i in 1..(v_item.capacity-v_existing_slots) loop
            insert into public.work_schedules(
              store_id, shift_template_id, shift_group_id, weekly_plan_item_id,
              work_date, start_time, end_time, employee_id, status, note, created_by
            ) values (
              v_store, v_template.id, v_existing_group, v_item.id,
              v_work_date, v_start, v_end, null, 'open', v_note, v_uid
            );
            v_created_slots := v_created_slots + 1;
          end loop;
        end if;
        v_skipped_groups := v_skipped_groups + 1;
        continue;
      end if;
    end;

    for i in 1..v_item.capacity loop
      insert into public.work_schedules(
        store_id, shift_template_id, shift_group_id, weekly_plan_item_id,
        work_date, start_time, end_time, employee_id, status, note, created_by
      ) values (
        v_store, v_template.id, v_group, v_item.id,
        v_work_date, v_start, v_end, null, 'open', v_note, v_uid
      );
      v_created_slots := v_created_slots + 1;
    end loop;
    v_created_groups := v_created_groups + 1;
  end loop;

  insert into public.audit_logs(actor_id, action, entity_type, new_data)
  values (
    v_uid,
    'generate_weekly_schedule_from_plan',
    'work_schedule_week',
    jsonb_build_object(
      'store_id',v_store,
      'week_start',p_week_start,
      'created_slots',v_created_slots,
      'created_groups',v_created_groups,
      'skipped_groups',v_skipped_groups
    )
  );

  return jsonb_build_object(
    'week_start',p_week_start,
    'created_slots',v_created_slots,
    'created_groups',v_created_groups,
    'skipped_groups',v_skipped_groups
  );
end;
$$;


--
-- Name: get_employee_hourly_rate(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_hourly_rate(p_employee_id uuid, p_work_date date) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select coalesce((select v.hourly_rate from public.employee_salary_versions v where v.employee_id=p_employee_id and v.effective_from<=p_work_date order by v.effective_from desc limit 1),(select hourly_rate from public.profiles where id=p_employee_id),0)
$$;


--
-- Name: get_employee_schedule_overview(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_schedule_overview(p_start_date date, p_end_date date) RETURNS TABLE(id uuid, work_date date, start_time time without time zone, end_time time without time zone, start_at timestamp with time zone, end_at timestamp with time zone, status text, note text, employee_id uuid, shift_group_id uuid, template_name text, employee_name text, employee_phone text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
begin
  if v_uid is null then
    raise exception 'NOT_AUTHENTICATED';
  end if;

  select p.store_id
    into v_store
  from public.profiles p
  where p.id = v_uid
    and p.role = 'employee'
    and p.employment_status = 'active';

  if v_store is null then
    raise exception 'FORBIDDEN';
  end if;

  if p_start_date is null or p_end_date is null or p_start_date > p_end_date then
    raise exception 'NGAY_KHONG_HOP_LE';
  end if;

  if p_end_date - p_start_date > 31 then
    raise exception 'KHOANG_NGAY_QUA_DAI';
  end if;

  return query
  select
    ws.id,
    ws.work_date,
    ws.start_time,
    ws.end_time,
    ws.start_at,
    ws.end_at,
    ws.status::text,
    ws.note,
    ws.employee_id,
    ws.shift_group_id,
    coalesce(st.name, 'Ca làm')::text as template_name,
    case
      when ws.employee_id is null then null::text
      else ep.full_name::text
    end as employee_name,
    case
      when ws.employee_id is null then null::text
      else ep.phone::text
    end as employee_phone
  from public.work_schedules ws
  left join public.shift_templates st
    on st.id = ws.shift_template_id
   and st.store_id = v_store
  left join public.profiles ep
    on ep.id = ws.employee_id
   and ep.store_id = v_store
  where ws.store_id = v_store
    and ws.work_date between p_start_date and p_end_date
    and ws.status::text <> 'cancelled'
  order by
    ws.work_date asc,
    ws.start_time asc,
    ws.shift_group_id nulls last,
    ws.employee_id nulls first;
end;
$$;


--
-- Name: get_employee_shift_capacity(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_shift_capacity(p_schedule_ids uuid[]) RETURNS TABLE(schedule_id uuid, group_id uuid, capacity integer, assigned_count integer, reserved_count integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id=v_uid and p.role='employee' and p.employment_status='active';
  if v_store is null then raise exception 'FORBIDDEN'; end if;

  return query
  with requested as (
    select ws.id,
           coalesce(ws.shift_group_id,ws.id) as gid
    from public.work_schedules ws
    where ws.store_id=v_store
      and ws.id = any(coalesce(p_schedule_ids,'{}'::uuid[]))
      and ws.status<>'cancelled'
  )
  select
    r.id as schedule_id,
    r.gid as group_id,
    (
      select count(*)::integer
      from public.work_schedules s
      where s.store_id=v_store
        and coalesce(s.shift_group_id,s.id)=r.gid
        and s.status<>'cancelled'
    ) as capacity,
    (
      select count(*)::integer
      from public.work_schedules s
      where s.store_id=v_store
        and coalesce(s.shift_group_id,s.id)=r.gid
        and s.status<>'cancelled'
        and s.employee_id is not null
    ) as assigned_count,
    (
      select count(*)::integer
      from public.shift_registrations sr
      join public.work_schedules s on s.id=sr.schedule_id
      where s.store_id=v_store
        and coalesce(s.shift_group_id,s.id)=r.gid
        and s.status<>'cancelled'
        and sr.status='pending'
    ) as reserved_count
  from requested r
  order by r.id;
end;
$$;


--
-- Name: get_employee_shift_registrants(uuid[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_employee_shift_registrants(p_schedule_ids uuid[]) RETURNS TABLE(schedule_id uuid, employee_id uuid, employee_name text, requested_at timestamp with time zone, status text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id=v_uid and p.role='employee' and p.employment_status='active';
  if v_store is null then raise exception 'FORBIDDEN'; end if;

  return query
  select
    sr.schedule_id,
    sr.employee_id,
    coalesce(p.full_name,'Nhân viên')::text as employee_name,
    sr.requested_at,
    sr.status::text
  from public.shift_registrations sr
  join public.work_schedules ws on ws.id=sr.schedule_id
  left join public.profiles p on p.id=sr.employee_id
  where ws.store_id=v_store
    and ws.status<>'cancelled'
    and sr.schedule_id = any(coalesce(p_schedule_ids,'{}'::uuid[]))
    and sr.status='pending'
  order by sr.requested_at asc;
end;
$$;


--
-- Name: get_my_active_store_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_active_store_id() RETURNS uuid
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.store_id
  from public.profiles p
  where p.id=auth.uid()
    and p.employment_status='active'
  limit 1;
$$;


--
-- Name: get_my_bank_details(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_bank_details() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_result jsonb;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and employment_status<>'terminated') then
    raise exception 'PROFILE_NOT_FOUND';
  end if;
  select jsonb_build_object(
    'bank_name',bank_name,
    'account_holder',account_holder,
    'account_number',account_number,
    'branch_name',branch_name
  ) into v_result
  from public.employee_bank_details
  where employee_id=v_uid;
  return coalesce(v_result,jsonb_build_object(
    'bank_name','','account_holder','','account_number','','branch_name',''
  ));
end;
$$;


--
-- Name: get_my_manager_permissions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_manager_permissions() RETURNS TABLE(permission_key text, enabled boolean)
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


--
-- Name: get_my_payroll_slips(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_payroll_slips() RETURNS TABLE(payroll_period_id uuid, period_name text, start_date date, end_date date, status public.payroll_status, paid_at timestamp with time zone, worked_minutes integer, gross_amount numeric, bonus_amount numeric, penalty_amount numeric, advance_amount numeric, net_amount numeric, items jsonb, adjustments jsonb)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select p.id,p.period_name,p.start_date,p.end_date,p.status,p.paid_at,
    r.worked_minutes,r.gross_amount,r.bonus_amount,r.penalty_amount,r.advance_amount,r.net_amount,
    coalesce((select jsonb_agg(jsonb_build_object('work_date',i.work_date,'start_at',i.schedule_start_at,
      'end_at',i.schedule_end_at,'check_in',i.check_in_at,'check_out',i.check_out_at,
      'worked_minutes',i.worked_minutes,'hourly_rate',i.hourly_rate,'gross_amount',i.gross_amount,
      'source',i.source) order by i.work_date,i.schedule_start_at)
      from public.payroll_run_items i where i.payroll_run_id=r.id),'[]'::jsonb),
    coalesce((select jsonb_agg(jsonb_build_object('type',a.adjustment_type,'amount',a.amount,
      'reason',a.reason,'status',a.status) order by a.created_at)
      from public.payroll_adjustments a where a.payroll_period_id=p.id and a.employee_id=auth.uid()),'[]'::jsonb)
  from public.payroll_runs r join public.payroll_periods p on p.id=r.payroll_period_id
  where r.employee_id=auth.uid()
  order by p.start_date desc;
$$;


--
-- Name: get_my_work_state(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_my_work_state() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid(); v_store uuid; v_tz text:='Asia/Ho_Chi_Minh';
  v_early integer:=60; v_checkout_late integer:=240; v_cutoff integer:=30; v_now timestamptz:=now();
  v_att public.attendance%rowtype; v_current public.work_schedules%rowtype;
  v_upcoming public.work_schedules%rowtype; v_past public.work_schedules%rowtype;
  v_start timestamptz; v_end timestamptz; v_today date;
begin
  select store_id into v_store from public.profiles
  where id=v_uid and role='employee' and employment_status='active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select coalesce(timezone,'Asia/Ho_Chi_Minh'),coalesce(checkin_early_minutes,60),
         coalesce(checkout_late_minutes,240),coalesce(checkin_cutoff_minutes,30)
  into v_tz,v_early,v_checkout_late,v_cutoff from public.stores where id=v_store;
  v_today:=(v_now at time zone v_tz)::date;

  if exists(select 1 from public.leave_requests l where l.employee_id=v_uid and l.status='approved'
            and l.start_date<=v_today and l.end_date>=v_today) then
    return jsonb_build_object('state','ON_LEAVE');
  end if;

  if (select count(*) from public.attendance a join public.work_schedules s on s.id=a.schedule_id
      where a.employee_id=v_uid and a.check_in is not null and a.check_out is null and s.store_id=v_store)>1 then
    return jsonb_build_object('state','DATA_CONFLICT','message','Có nhiều ca chưa checkout. Cần Owner/Manager kiểm tra.');
  end if;

  -- Ưu tiên xử lý ca của HÔM NAY trước mọi ca quên checkout từ ngày trước.
  for v_current in
    select s.* from public.work_schedules s
    where s.employee_id=v_uid and s.store_id=v_store and s.status='assigned'
      and (s.start_at at time zone v_tz)::date=v_today
    order by s.start_at nulls last, s.start_time
  loop
    v_start:=coalesce(v_current.start_at,((v_current.work_date+v_current.start_time)::timestamp at time zone v_tz));
    v_end:=coalesce(v_current.end_at,(((v_current.work_date + case when v_current.end_time<=v_current.start_time then 1 else 0 end)+v_current.end_time)::timestamp at time zone v_tz));

    if (v_now>v_end and v_current.work_date=v_today) then
      -- bỏ qua để tìm ca đang diễn ra; ca đã kết thúc được xử lý bên MISSED_CHECKIN
      continue;
    end if;

    if v_now>v_start+make_interval(mins=>v_cutoff) and v_now<=v_end then
      if not exists(select 1 from public.attendance a where a.schedule_id=v_current.id and a.check_in is not null) then
        return jsonb_build_object('state','CHECKIN_EXPIRED','schedule_id',v_current.id,'start_at',v_start,'end_at',v_end,
          'cutoff_at',v_start+make_interval(mins=>v_cutoff),'message','Đã quá thời gian check-in tự động. Cần quản lý xử lý bổ sung chấm công.');
      end if;
    end if;

    if v_now>=v_start-make_interval(mins=>v_early) and v_now<=v_start+make_interval(mins=>v_cutoff) then
      if not exists(select 1 from public.attendance a where a.schedule_id=v_current.id and a.check_in is not null) then
        return jsonb_build_object('state','CHECKIN_AVAILABLE','schedule_id',v_current.id,'start_at',v_start,'end_at',v_end,
          'cutoff_at',v_start+make_interval(mins=>v_cutoff));
      end if;
    end if;
  end loop;

  -- Sau khi xử lý xong ca hôm nay mới xét ca trước đó đang thiếu checkout.
  select a.* into v_att
  from public.attendance a join public.work_schedules s on s.id=a.schedule_id
  where a.employee_id=v_uid and a.check_in is not null and a.check_out is null and s.store_id=v_store
  order by a.check_in desc limit 1;
  if v_att.id is not null then
    select * into v_current from public.work_schedules where id=v_att.schedule_id;
    v_start:=coalesce(v_current.start_at,((v_current.work_date+v_current.start_time)::timestamp at time zone v_tz));
    v_end:=coalesce(v_current.end_at,(((v_current.work_date + case when v_current.end_time<=v_current.start_time then 1 else 0 end)+v_current.end_time)::timestamp at time zone v_tz));
    if v_now>v_end+make_interval(mins=>v_checkout_late) then
      return jsonb_build_object('state','MISSING_CHECKOUT','schedule_id',v_current.id,'attendance_id',v_att.id,'check_in',v_att.check_in,'start_at',v_start,'end_at',v_end,'late_minutes',v_att.late_minutes);
    end if;
    return jsonb_build_object('state','WORKING','schedule_id',v_current.id,'attendance_id',v_att.id,'check_in',v_att.check_in,'start_at',v_start,'end_at',v_end,'late_minutes',v_att.late_minutes);
  end if;

  -- Ca tương lai gần nhất.
  for v_upcoming in
    select s.* from public.work_schedules s
    where s.employee_id=v_uid and s.store_id=v_store and s.status='assigned'
      and coalesce(s.start_at,((s.work_date+s.start_time)::timestamp at time zone v_tz))>v_now
    order by coalesce(s.start_at,((s.work_date+s.start_time)::timestamp at time zone v_tz))
  loop
    v_start:=coalesce(v_upcoming.start_at,((v_upcoming.work_date+v_upcoming.start_time)::timestamp at time zone v_tz));
    v_end:=coalesce(v_upcoming.end_at,(((v_upcoming.work_date + case when v_upcoming.end_time<=v_upcoming.start_time then 1 else 0 end)+v_upcoming.end_time)::timestamp at time zone v_tz));
    if not exists(select 1 from public.attendance a where a.schedule_id=v_upcoming.id and a.check_out is not null) then
      return jsonb_build_object('state','UPCOMING','schedule_id',v_upcoming.id,'start_at',v_start,'end_at',v_end);
    end if;
  end loop;

  -- Ca hôm nay đã kết thúc nhưng chưa có check-in.
  for v_past in
    select s.* from public.work_schedules s
    where s.employee_id=v_uid and s.store_id=v_store and s.status in ('assigned','completed')
      and coalesce(s.end_at,(((s.work_date + case when s.end_time<=s.start_time then 1 else 0 end)+s.end_time)::timestamp at time zone v_tz))<v_now
      and s.work_date=v_today
    order by coalesce(s.end_at,(((s.work_date + case when s.end_time<=s.start_time then 1 else 0 end)+s.end_time)::timestamp at time zone v_tz)) desc
  loop
    if not exists(select 1 from public.attendance a where a.schedule_id=v_past.id and a.check_in is not null) then
      return jsonb_build_object('state','MISSED_CHECKIN','schedule_id',v_past.id,
        'start_at',coalesce(v_past.start_at,((v_past.work_date+v_past.start_time)::timestamp at time zone v_tz)),
        'end_at',coalesce(v_past.end_at,(((v_past.work_date + case when v_past.end_time<=v_past.start_time then 1 else 0 end)+v_past.end_time)::timestamp at time zone v_tz)));
    end if;
  end loop;

  -- Nếu có bản ghi đã checkout, trả completed.
  select s.* into v_current
  from public.work_schedules s join public.attendance a on a.schedule_id=s.id
  where s.employee_id=v_uid and s.store_id=v_store and a.check_out is not null
  order by a.check_out desc limit 1;
  if v_current.id is not null then
    v_start:=coalesce(v_current.start_at,((v_current.work_date+v_current.start_time)::timestamp at time zone v_tz));
    v_end:=coalesce(v_current.end_at,(((v_current.work_date + case when v_current.end_time<=v_current.start_time then 1 else 0 end)+v_current.end_time)::timestamp at time zone v_tz));
    return jsonb_build_object('state','COMPLETED','schedule_id',v_current.id,'start_at',v_start,'end_at',v_end);
  end if;
  return jsonb_build_object('state','NO_SHIFT');
end;
$$;


--
-- Name: get_shift_registration_recurring_rule(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_shift_registration_recurring_rule() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_current jsonb;
  v_next jsonb;
begin
  select store_id into v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';

  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id=v_store and is_active=true;

  if not found then return null; end if;

  v_current:=public.get_shift_registration_window(
    date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date
  );
  v_next:=public.get_shift_registration_window(
    date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date + 7
  );

  return jsonb_build_object(
    'id',v_rule.id,
    'open_weekday',v_rule.open_weekday,
    'open_time',v_rule.open_time,
    'close_weekday',v_rule.close_weekday,
    'close_time',v_rule.close_time,
    'is_active',v_rule.is_active,
    'auto_open',v_rule.auto_open,
    'auto_approve',v_rule.auto_approve,
    'current_window',v_current,
    'next_window',v_next
  );
end;
$$;


--
-- Name: get_shift_registration_window(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_shift_registration_window(p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_row public.shift_registration_windows%rowtype;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_status text;
begin
  select store_id into v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';

  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id=v_store and is_active=true;

  if not found then return null; end if;

  perform public.ensure_shift_registration_window(date_trunc('week',p_week_start)::date);

  select * into v_row
  from public.shift_registration_windows
  where store_id=v_store
    and week_start=date_trunc('week',p_week_start)::date;

  if not found then return null; end if;

  v_status:=v_row.status;
  if v_status='open' and now()<v_row.open_at then v_status:='scheduled'; end if;
  if v_status='open' and now()>v_row.close_at then v_status:='closed'; end if;

  return jsonb_build_object(
    'id',v_row.id,
    'store_id',v_row.store_id,
    'week_start',v_row.week_start,
    'open_at',v_row.open_at,
    'close_at',v_row.close_at,
    'status',v_status,
    'auto_open',v_rule.auto_open,
    'auto_approve',v_rule.auto_approve,
    'closed_at',v_row.closed_at,
    'finalized_at',v_row.finalized_at
  );
end;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: shift_template_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_template_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    shift_template_id uuid NOT NULL,
    effective_from date NOT NULL,
    name text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    break_minutes integer DEFAULT 0 NOT NULL,
    capacity integer DEFAULT 1 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shift_template_versions_break_minutes_check CHECK (((break_minutes >= 0) AND (break_minutes <= 180))),
    CONSTRAINT shift_template_versions_capacity_check CHECK (((capacity >= 1) AND (capacity <= 50))),
    CONSTRAINT shift_template_versions_check CHECK ((start_time <> end_time))
);


--
-- Name: get_shift_template_version(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_shift_template_version(p_shift_template_id uuid, p_work_date date) RETURNS public.shift_template_versions
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v public.shift_template_versions%rowtype;
begin
  select * into v
  from public.shift_template_versions
  where shift_template_id=p_shift_template_id and effective_from<=p_work_date
  order by effective_from desc
  limit 1;
  if found then return v; end if;
  select gen_random_uuid(), t.id, t.created_at::date, t.name, t.start_time, t.end_time, t.break_minutes, t.capacity, t.is_active, null::uuid, t.created_at, t.updated_at
    into v.id, v.shift_template_id, v.effective_from, v.name, v.start_time, v.end_time, v.break_minutes, v.capacity, v.is_active, v.created_by, v.created_at, v.updated_at
  from public.shift_templates t where t.id=p_shift_template_id;
  return v;
end;
$$;


--
-- Name: gps_distance_m(double precision, double precision, double precision, double precision); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.gps_distance_m(p_lat1 double precision, p_lon1 double precision, p_lat2 double precision, p_lon2 double precision) RETURNS double precision
    LANGUAGE sql IMMUTABLE
    AS $$
  select 6371000 * 2 * asin(sqrt(
    power(sin(radians(p_lat2-p_lat1)/2),2) +
    cos(radians(p_lat1))*cos(radians(p_lat2))*power(sin(radians(p_lon2-p_lon1)/2),2)
  ));
$$;


--
-- Name: guard_owner_schedule_configuration(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_owner_schedule_configuration() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store_id uuid;
begin
  if v_uid is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  v_store_id := coalesce(new.store_id, old.store_id);
  if exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.role = 'owner'
      and p.employment_status = 'active'
      and p.store_id = v_store_id
  ) then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  raise exception 'FORBIDDEN_OWNER_CONFIGURATION';
end;
$$;


--
-- Name: guard_registration_window_write(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.guard_registration_window_write() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_auto_open text := current_setting('app.hr_registration_auto_open', true);
begin
  if v_uid is null then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if exists (
    select 1 from public.profiles p
    where p.id = v_uid
      and p.role = 'owner'
      and p.employment_status = 'active'
      and p.store_id = coalesce(new.store_id, old.store_id)
  ) then
    if tg_op = 'DELETE' then return old; end if;
    return new;
  end if;

  if v_auto_open = 'on'
     and exists (
       select 1 from public.profiles p
       where p.id = v_uid and p.role = 'employee'
         and p.employment_status = 'active'
         and p.store_id = coalesce(new.store_id, old.store_id)
     )
     and tg_op <> 'DELETE'
     and new.status = 'open' then
    return new;
  end if;

  raise exception 'FORBIDDEN_OWNER_REGISTRATION_SETTINGS';
end;
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, full_name, role, employment_status)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    'employee',
    'invited'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;


--
-- Name: is_manager_or_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_manager_or_owner() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.my_role() in ('owner','manager');
$$;


--
-- Name: is_owner(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_owner() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select public.my_role() = 'owner';
$$;


--
-- Name: is_store_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_store_member(p_store_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists(
    select 1
    from public.store_memberships m
    where m.user_id=auth.uid()
      and m.store_id=p_store_id
      and m.is_active=true
  );
$$;


--
-- Name: is_store_owner(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.is_store_owner(p_store_id uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select exists(
    select 1
    from public.store_memberships m
    where m.user_id=auth.uid()
      and m.store_id=p_store_id
      and m.role='owner'
      and m.is_active=true
  );
$$;


--
-- Name: manager_list_payroll_advance_requests(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_list_payroll_advance_requests() RETURNS TABLE(adjustment_id uuid, employee_id uuid, employee_name text, amount numeric, reason text, created_at timestamp with time zone, payroll_period_id uuid, advance_status text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_store uuid;
  v_role text;
begin
  select p.store_id, p.role::text into v_store, v_role
  from public.profiles p
  where p.id = auth.uid()
    and p.employment_status = 'active'::public.employment_status
    and p.role in ('owner'::public.user_role, 'manager'::public.user_role);

  if v_store is null or v_role not in ('owner', 'manager') then
    raise exception 'FORBIDDEN';
  end if;

  return query
  select a.id, a.employee_id, p.full_name, a.amount, a.reason, a.created_at,
         a.payroll_period_id, a.status::text
  from public.payroll_adjustments a
  join public.profiles p on p.id = a.employee_id
  where p.store_id = v_store
    and p.role = 'employee'::public.user_role
    and a.adjustment_type = 'advance'::public.adjustment_type
    and (
      a.status = 'pending'::public.adjustment_status
      or (
        a.status = 'approved'::public.adjustment_status
        and a.payroll_period_id is null
      )
    )
  order by a.created_at;
end;
$$;


--
-- Name: manager_review_payroll_advance(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_review_payroll_advance(p_adjustment_id uuid, p_action text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_store uuid;
  v_role text;
  v_adjustment public.payroll_adjustments%rowtype;
  v_period public.payroll_periods%rowtype;
  v_advance numeric;
begin
  select p.store_id, p.role::text into v_store, v_role
  from public.profiles p
  where p.id = auth.uid()
    and p.employment_status = 'active'::public.employment_status
    and p.role in ('owner'::public.user_role, 'manager'::public.user_role);

  if v_store is null or v_role not in ('owner', 'manager') then
    raise exception 'FORBIDDEN';
  end if;
  if lower(coalesce(p_action, '')) not in ('approve', 'reject') then
    raise exception 'ACTION_KHONG_HOP_LE';
  end if;

  select a.* into v_adjustment
  from public.payroll_adjustments a
  join public.profiles e on e.id = a.employee_id
  where a.id = p_adjustment_id
    and e.store_id = v_store
    and e.role = 'employee'::public.user_role
    and a.adjustment_type = 'advance'::public.adjustment_type
  for update of a;

  if not found then raise exception 'TAM_UNG_NOT_FOUND'; end if;
  if v_adjustment.status <> 'pending'::public.adjustment_status then
    raise exception 'TAM_UNG_DA_XU_LY';
  end if;

  if lower(p_action) = 'approve' then
    select pp.* into v_period
    from public.payroll_periods pp
    where pp.store_id = v_store
      and pp.status in ('draft'::public.payroll_status, 'review'::public.payroll_status)
    order by abs(pp.start_date - current_date), pp.start_date, pp.created_at
    limit 1
    for update;

    update public.payroll_adjustments
    set status = 'approved'::public.adjustment_status,
        approved_by = auth.uid(),
        approved_at = now(),
        payroll_period_id = v_period.id,
        updated_at = now()
    where id = v_adjustment.id;

    if v_period.id is not null then
      select coalesce(sum(a.amount), 0) into v_advance
      from public.payroll_adjustments a
      where a.payroll_period_id = v_period.id
        and a.employee_id = v_adjustment.employee_id
        and a.adjustment_type = 'advance'::public.adjustment_type
        and a.status = 'approved'::public.adjustment_status;

      update public.payroll_runs r
      set advance_amount = v_advance,
          net_amount = greatest(0, r.gross_amount + r.bonus_amount
                                  - r.penalty_amount - v_advance),
          updated_at = now()
      where r.payroll_period_id = v_period.id
        and r.employee_id = v_adjustment.employee_id;
    end if;
  else
    update public.payroll_adjustments
    set status = 'rejected'::public.adjustment_status,
        approved_by = auth.uid(),
        approved_at = now(),
        updated_at = now()
    where id = v_adjustment.id;
  end if;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(), v_store, 'manager_review_payroll_advance',
    'payroll_adjustment', v_adjustment.id,
    jsonb_build_object(
      'action', lower(p_action),
      'payroll_period_id', v_period.id
    )
  );

  return jsonb_build_object(
    'action', lower(p_action),
    'payroll_period_id', v_period.id,
    'queued_for_next_open_period', lower(p_action) = 'approve' and v_period.id is null
  );
end;
$$;


--
-- Name: manager_update_employee_contact(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.manager_update_employee_contact(p_employee_id uuid, p_full_name text, p_phone text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_target_store uuid;
  v_target_role public.user_role;
begin
  select role::text,store_id into v_role,v_store from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'manager' then raise exception 'FORBIDDEN'; end if;
  select store_id,role into v_target_store,v_target_role from public.profiles where id=p_employee_id for update;
  if not found or v_target_store is distinct from v_store or v_target_role<>'employee' then raise exception 'FORBIDDEN'; end if;
  if length(trim(coalesce(p_full_name,'')))=0 then raise exception 'THIEU_HO_TEN'; end if;
  update public.profiles set full_name=trim(p_full_name),phone=nullif(trim(coalesce(p_phone,'')),'') where id=p_employee_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'manager_update_employee_contact','profile',p_employee_id,jsonb_build_object('full_name',trim(p_full_name),'phone',nullif(trim(coalesce(p_phone,'')),'')));
  return true;
end;
$$;


--
-- Name: materialize_weekly_registration_slots(uuid, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.materialize_weekly_registration_slots(p_store_id uuid, p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_owner uuid;
  p record;
  v_existing integer;
  v_missing integer;
  v_group uuid;
  v_created integer:=0;
begin
  select id into v_owner
  from public.profiles
  where store_id=p_store_id and role='owner' and employment_status='active'
  order by created_at
  limit 1;

  if v_owner is null then raise exception 'STORE_OWNER_NOT_FOUND'; end if;

  for p in
    select i.id as plan_item_id,
           i.weekday,
           i.capacity,
           t.id as template_id,
           t.start_time,
           t.end_time,
           t.name as template_name
    from public.weekly_shift_plan_items i
    join public.shift_templates t on t.id=i.shift_template_id
    where i.store_id=p_store_id
      and i.is_active=true
      and t.store_id=p_store_id
      and t.is_active=true
    order by i.weekday,i.sort_order,i.id
  loop
    if p.weekday<1 or p.weekday>7 then continue; end if;

    v_existing:=(
      select count(*)
      from public.work_schedules s
      where s.store_id=p_store_id
        and s.work_date=p_week_start+(p.weekday-1)
        and s.shift_template_id=p.template_id
        and s.status<>'cancelled'
    );

    v_missing:=greatest(0,coalesce(p.capacity,1)-v_existing);

    if v_missing>0 then
      v_group:=gen_random_uuid();

      insert into public.work_schedules(
        store_id,shift_template_id,work_date,start_time,end_time,
        employee_id,status,note,created_by,shift_group_id
      )
      select
        p_store_id,p.template_id,
        p_week_start+(p.weekday-1),
        p.start_time,p.end_time,
        null,'open',
        'Tự động mở đăng ký · '+coalesce(p.template_name,'Ca'),
        v_owner,v_group
      from generate_series(1,v_missing);

      v_created:=v_created+v_missing;
    end if;
  end loop;

  return jsonb_build_object(
    'store_id',p_store_id,
    'week_start',p_week_start,
    'created_slots',v_created
  );
end;
$$;


--
-- Name: my_role(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_role() RETURNS public.user_role
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
  select role
  from public.profiles
  where id = auth.uid()
    and employment_status = 'active'
  limit 1;
$$;


--
-- Name: open_shift_registration_window(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.open_shift_registration_window(p_week_start date) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_store uuid;
  v_role text;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_week date:=date_trunc('week',p_week_start)::date;
  x record;
  v_window public.shift_registration_windows%rowtype;
  v_created integer:=0;
begin
  select store_id,role::text into v_store,v_role
  from public.profiles
  where id=v_uid and employment_status='active';

  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;

  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id=v_store and is_active=true;

  if not found then raise exception 'DANG_KY_CHUA_CAI'; end if;

  select * into x
  from public.registration_window_times(
    v_week,v_rule.open_weekday,v_rule.open_time,
    v_rule.close_weekday,v_rule.close_time
  );

  insert into public.shift_registration_windows(
    store_id,week_start,open_at,close_at,status,closed_at,closed_by,finalized_at,finalized_by
  )
  values(
    v_store,v_week,x.open_at,x.close_at,'open',null,null,null,null
  )
  on conflict(store_id,week_start) do update set
    open_at=excluded.open_at,
    close_at=excluded.close_at,
    status='open',
    closed_at=null,
    closed_by=null,
    finalized_at=null,
    finalized_by=null
  returning * into v_window;

  v_created:=coalesce(
    (public.materialize_weekly_registration_slots(v_store,v_week)->>'created_slots')::integer,
    0
  );

  return jsonb_build_object(
    'id',v_window.id,
    'week_start',v_week,
    'open_at',v_window.open_at,
    'close_at',v_window.close_at,
    'status','open',
    'generated_slots',v_created
  );
end;
$$;


--
-- Name: owner_add_payroll_adjustment(uuid, uuid, text, numeric, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_add_payroll_adjustment(p_employee_id uuid, p_payroll_period_id uuid, p_type text, p_amount numeric, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_role text; v_store uuid; v_id uuid; v_type public.adjustment_type;
begin
  select role::text,store_id into v_role,v_store from public.profiles where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  if p_amount<=0 or length(trim(coalesce(p_reason,'')))=0 then raise exception 'KHOAN_DIEU_CHINH_KHONG_HOP_LE'; end if;
  begin v_type:=lower(p_type)::public.adjustment_type; exception when others then raise exception 'LOAI_DIEU_CHINH_KHONG_HOP_LE'; end;
  if not exists(select 1 from public.profiles where id=p_employee_id and store_id=v_store and role='employee') then raise exception 'NHAN_VIEN_KHONG_HOP_LE'; end if;
  if not exists(select 1 from public.payroll_periods where id=p_payroll_period_id and store_id=v_store and status in ('draft','review')) then raise exception 'KY_LUONG_KHONG_HOP_LE'; end if;
  insert into public.payroll_adjustments(employee_id,payroll_period_id,adjustment_type,amount,reason,status,created_by) values(p_employee_id,p_payroll_period_id,v_type,p_amount,trim(p_reason),'pending',auth.uid()) returning id into v_id;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(auth.uid(),'owner_add_payroll_adjustment','payroll_adjustment',v_id,jsonb_build_object('employee_id',p_employee_id,'period_id',p_payroll_period_id,'type',v_type,'amount',p_amount,'reason',p_reason));
  return v_id;
end;
$$;


--
-- Name: owner_assign_queued_payroll_advances(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_assign_queued_payroll_advances(p_payroll_period_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_store uuid;
  v_period public.payroll_periods%rowtype;
  v_count integer := 0;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid()
    and p.role = 'owner'::public.user_role
    and p.employment_status = 'active'::public.employment_status;
  if v_store is null then raise exception 'FORBIDDEN'; end if;

  select pp.* into v_period
  from public.payroll_periods pp
  where pp.id = p_payroll_period_id and pp.store_id = v_store
  for update;
  if not found then raise exception 'KY_LUONG_NOT_FOUND'; end if;
  if v_period.status not in ('draft'::public.payroll_status, 'review'::public.payroll_status) then
    raise exception 'KY_LUONG_DA_CHOT';
  end if;

  update public.payroll_adjustments a
  set payroll_period_id = v_period.id, updated_at = now()
  from public.profiles e
  where a.employee_id = e.id
    and e.store_id = v_store
    and e.role = 'employee'::public.user_role
    and a.adjustment_type = 'advance'::public.adjustment_type
    and a.status = 'approved'::public.adjustment_status
    and a.payroll_period_id is null
    and not exists (
      select 1
      from public.payroll_periods nearer
      where nearer.store_id = v_store
        and nearer.status in ('draft'::public.payroll_status, 'review'::public.payroll_status)
        and (abs(nearer.start_date - current_date), nearer.start_date, nearer.created_at)
            < (abs(v_period.start_date - current_date), v_period.start_date, v_period.created_at)
    );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;


--
-- Name: owner_calculate_payroll(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_calculate_payroll(p_payroll_period_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text; v_store uuid; v_period public.payroll_periods%rowtype;
  v_emp record; v_run_id uuid; v_minutes integer; v_rate numeric;
  v_gross numeric; v_bonus numeric; v_penalty numeric; v_advance numeric;
  v_net numeric; v_count integer:=0;
begin
  select role::text,store_id into v_role,v_store from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  select * into v_period from public.payroll_periods
  where id=p_payroll_period_id and store_id=v_store for update;
  if not found then raise exception 'KY_LUONG_NOT_FOUND'; end if;
  if v_period.status in ('locked','paid') then raise exception 'KY_LUONG_DA_CHOT'; end if;

  -- Only this unlocked period is rebuilt. Source attendance remains untouched.
  delete from public.payroll_run_items i using public.payroll_runs r
  where i.payroll_run_id=r.id and r.payroll_period_id=v_period.id;

  for v_emp in
    select p.id from public.profiles p
    where p.store_id=v_store and p.role='employee'
      and (p.employment_status in ('active','inactive') or exists (
        select 1 from public.attendance a join public.work_schedules s on s.id=a.schedule_id
        where a.employee_id=p.id and a.check_in is not null and a.check_out is not null
          and s.store_id=v_store and s.work_date between v_period.start_date and v_period.end_date
      )) order by p.full_name
  loop
    select coalesce(sum(a.worked_minutes),0)::integer,
           coalesce(sum(a.worked_minutes * public.get_employee_hourly_rate(a.employee_id,s.work_date) / 60),0)
      into v_minutes,v_gross
    from public.attendance a join public.work_schedules s on s.id=a.schedule_id
    where a.employee_id=v_emp.id and a.check_in is not null and a.check_out is not null
      and s.store_id=v_store and s.work_date between v_period.start_date and v_period.end_date;
    select coalesce(sum(case when adjustment_type='bonus' then amount else 0 end),0),
           coalesce(sum(case when adjustment_type='penalty' then amount else 0 end),0),
           coalesce(sum(case when adjustment_type='advance' then amount else 0 end),0)
      into v_bonus,v_penalty,v_advance
    from public.payroll_adjustments
    where employee_id=v_emp.id and payroll_period_id=v_period.id and status='approved';
    v_rate:=case when v_minutes>0 then round(v_gross/(v_minutes/60),2)
                 else public.get_employee_hourly_rate(v_emp.id,v_period.end_date) end;
    v_gross:=round(v_gross,2); v_net:=greatest(0,v_gross+v_bonus-v_penalty-v_advance);
    insert into public.payroll_runs(payroll_period_id,employee_id,hourly_rate,worked_minutes,
      gross_amount,bonus_amount,penalty_amount,advance_amount,net_amount,calculated_at,calculated_by)
    values(v_period.id,v_emp.id,v_rate,v_minutes,v_gross,v_bonus,v_penalty,v_advance,v_net,now(),auth.uid())
    on conflict(payroll_period_id,employee_id) do update set hourly_rate=excluded.hourly_rate,
      worked_minutes=excluded.worked_minutes,gross_amount=excluded.gross_amount,
      bonus_amount=excluded.bonus_amount,penalty_amount=excluded.penalty_amount,
      advance_amount=excluded.advance_amount,net_amount=excluded.net_amount,
      calculated_at=now(),calculated_by=auth.uid(),updated_at=now()
    returning id into v_run_id;
    insert into public.payroll_run_items(payroll_run_id,attendance_id,employee_id,work_date,
      schedule_start_at,schedule_end_at,check_in_at,check_out_at,worked_minutes,hourly_rate,gross_amount,source)
    select v_run_id,a.id,a.employee_id,s.work_date,s.start_at,s.end_at,a.check_in,a.check_out,
      a.worked_minutes,public.get_employee_hourly_rate(a.employee_id,s.work_date),
      round(a.worked_minutes * public.get_employee_hourly_rate(a.employee_id,s.work_date)/60,2),
      case when a.check_in_status='manual'::public.attendance_status then 'manual' else 'attendance' end
    from public.attendance a join public.work_schedules s on s.id=a.schedule_id
    where a.employee_id=v_emp.id and a.check_in is not null and a.check_out is not null
      and s.store_id=v_store and s.work_date between v_period.start_date and v_period.end_date;
    v_count:=v_count+1;
  end loop;
  update public.payroll_periods set status='review',updated_at=now()
  where id=v_period.id and status='draft';
  insert into public.audit_logs(actor_id,store_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),v_store,'owner_calculate_payroll','payroll_period',v_period.id,
    jsonb_build_object('employee_count',v_count,'snapshot_items',true));
  return jsonb_build_object('period_id',v_period.id,'employee_count',v_count);
end;
$$;


--
-- Name: owner_create_payroll_period(text, date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_create_payroll_period(p_period_name text, p_start_date date, p_end_date date, p_note text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_role text; v_store uuid; v_id uuid;
begin
  select role::text,store_id into v_role,v_store from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then
    raise exception 'KY_LUONG_KHONG_HOP_LE';
  end if;
  if length(trim(coalesce(p_period_name,'')))=0 then raise exception 'THIEU_TEN_KY_LUONG'; end if;
  perform pg_advisory_xact_lock(hashtextextended(v_store::text||':payroll-periods',0));
  if exists (
    select 1 from public.payroll_periods p
    where p.store_id=v_store and daterange(p.start_date,p.end_date,'[]')
      && daterange(p_start_date,p_end_date,'[]')
  ) then raise exception 'KY_LUONG_BI_CHONG_NGAY'; end if;
  insert into public.payroll_periods(store_id,period_name,start_date,end_date,note)
  values(v_store,trim(p_period_name),p_start_date,p_end_date,nullif(trim(p_note),''))
  returning id into v_id;
  insert into public.audit_logs(actor_id,store_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),v_store,'owner_create_payroll_period','payroll_period',v_id,
    jsonb_build_object('period_name',p_period_name,'start_date',p_start_date,'end_date',p_end_date));
  return v_id;
exception when unique_violation then raise exception 'KY_LUONG_DA_TON_TAI';
end;
$$;


--
-- Name: owner_generate_payroll_penalties(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_generate_payroll_penalties(p_payroll_period_id uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_store uuid;
  v_period public.payroll_periods%rowtype;
  v_rule public.payroll_penalty_rules%rowtype;
  v_event record;
  v_amount numeric;
  v_created integer := 0;
  v_rows integer := 0;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid()
    and p.role = 'owner'::public.user_role
    and p.employment_status = 'active'::public.employment_status;
  if v_store is null then raise exception 'FORBIDDEN'; end if;

  select pp.* into v_period
  from public.payroll_periods pp
  where pp.id = p_payroll_period_id and pp.store_id = v_store
  for update;
  if not found then raise exception 'KY_LUONG_NOT_FOUND'; end if;
  if v_period.status not in ('draft'::public.payroll_status, 'review'::public.payroll_status) then
    raise exception 'KY_LUONG_DA_CHOT';
  end if;

  for v_rule in
    select r.*
    from public.payroll_penalty_rules r
    where r.store_id = v_store and r.enabled
    order by r.created_at, r.id
  loop
    if v_rule.rule_type = 'late' then
      for v_event in
        select a.id as attendance_id, a.employee_id, a.late_minutes, s.id as schedule_id, s.work_date
        from public.attendance a
        join public.work_schedules s on s.id = a.schedule_id
        join public.profiles e on e.id = a.employee_id
        where s.store_id = v_store
          and s.work_date between v_period.start_date and v_period.end_date
          and s.status <> 'cancelled'
          and s.employee_id = a.employee_id
          and e.role = 'employee'::public.user_role
          and a.check_in is not null
          and coalesce(a.late_minutes, 0) > v_rule.threshold_minutes
          and not exists (
            select 1
            from public.schedule_requests sr
            where sr.schedule_id = s.id
              and sr.employee_id = a.employee_id
              and sr.request_type = 'late'
              and sr.status = 'approved'
          )
      loop
        v_amount := case
          when v_rule.amount_mode = 'per_minute'
            then round((v_event.late_minutes - v_rule.threshold_minutes) * v_rule.amount, 2)
          else v_rule.amount
        end;
        if v_amount > 0 then
          insert into public.payroll_adjustments(
            employee_id, payroll_period_id, adjustment_type, amount, reason,
            status, created_by, source_key, source_schedule_id, source_rule_id
          )
          values (
            v_event.employee_id, v_period.id, 'penalty'::public.adjustment_type,
            v_amount, v_rule.label || ' · đi trễ ' || v_event.late_minutes || ' phút',
            'pending'::public.adjustment_status, auth.uid(),
            'rule:' || v_rule.id || ':late:' || v_event.attendance_id,
            v_event.schedule_id, v_rule.id
          )
          on conflict (source_key) where source_key is not null do nothing;
          get diagnostics v_rows = row_count;
          v_created := v_created + v_rows;
        end if;
      end loop;
    elsif v_rule.rule_type = 'late_monthly' then
      for v_event in
        with eligible_lates as (
          select a.employee_id, s.id as schedule_id, s.work_date,
                 date_trunc('month', s.work_date::timestamp)::date as month_start,
                 row_number() over (
                   partition by a.employee_id, date_trunc('month', s.work_date::timestamp)
                   order by s.work_date, s.start_at, a.id
                 ) as occurrence_number
          from public.attendance a
          join public.work_schedules s on s.id = a.schedule_id
          join public.profiles e on e.id = a.employee_id
          where s.store_id = v_store
            and s.status <> 'cancelled'
            and s.employee_id = a.employee_id
            and e.role = 'employee'::public.user_role
            and a.check_in is not null
            and coalesce(a.late_minutes, 0) > 0
            and not exists (
              select 1
              from public.schedule_requests sr
              where sr.schedule_id = s.id
                and sr.employee_id = a.employee_id
                and sr.request_type = 'late'
                and sr.status = 'approved'
            )
        )
        select employee_id, schedule_id, work_date, month_start
        from eligible_lates
        where occurrence_number = v_rule.threshold_occurrences
          and work_date between v_period.start_date and v_period.end_date
      loop
        insert into public.payroll_adjustments(
          employee_id, payroll_period_id, adjustment_type, amount, reason,
          status, created_by, source_key, source_schedule_id, source_rule_id
        )
        values (
          v_event.employee_id, v_period.id, 'penalty'::public.adjustment_type,
          v_rule.amount, v_rule.label || ' · đủ ' || v_rule.threshold_occurrences
            || ' lần đi trễ trong tháng ' || to_char(v_event.month_start, 'YYYY-MM'),
          'pending'::public.adjustment_status, auth.uid(),
          'rule:' || v_rule.id || ':late-month:' || to_char(v_event.month_start, 'YYYY-MM'),
          v_event.schedule_id, v_rule.id
        )
        on conflict (source_key) where source_key is not null do nothing;
        get diagnostics v_rows = row_count;
        v_created := v_created + v_rows;
      end loop;
    elsif v_rule.rule_type = 'early_leave' then
      for v_event in
        select a.id as attendance_id, a.employee_id, a.early_leave_minutes, s.id as schedule_id
        from public.attendance a
        join public.work_schedules s on s.id = a.schedule_id
        join public.profiles e on e.id = a.employee_id
        where s.store_id = v_store
          and s.work_date between v_period.start_date and v_period.end_date
          and s.status <> 'cancelled'
          and s.employee_id = a.employee_id
          and e.role = 'employee'::public.user_role
          and a.check_in is not null
          and coalesce(a.early_leave_minutes, 0) > v_rule.threshold_minutes
      loop
        v_amount := case
          when v_rule.amount_mode = 'per_minute'
            then round((v_event.early_leave_minutes - v_rule.threshold_minutes) * v_rule.amount, 2)
          else v_rule.amount
        end;
        if v_amount > 0 then
          insert into public.payroll_adjustments(
            employee_id, payroll_period_id, adjustment_type, amount, reason,
            status, created_by, source_key, source_schedule_id, source_rule_id
          )
          values (
            v_event.employee_id, v_period.id, 'penalty'::public.adjustment_type,
            v_amount, v_rule.label || ' · về sớm ' || v_event.early_leave_minutes || ' phút',
            'pending'::public.adjustment_status, auth.uid(),
            'rule:' || v_rule.id || ':early:' || v_event.attendance_id,
            v_event.schedule_id, v_rule.id
          )
          on conflict (source_key) where source_key is not null do nothing;
          get diagnostics v_rows = row_count;
          v_created := v_created + v_rows;
        end if;
      end loop;
    elsif v_rule.rule_type = 'absence' then
      for v_event in
        select s.id as schedule_id, s.employee_id, s.work_date
        from public.work_schedules s
        join public.profiles e on e.id = s.employee_id
        where s.store_id = v_store
          and s.work_date between v_period.start_date and v_period.end_date
          and s.status <> 'cancelled'
          and s.employee_id is not null
          and e.role = 'employee'::public.user_role
          and s.end_at is not null
          and s.end_at <= now()
          and not exists (
            select 1 from public.attendance a where a.schedule_id = s.id
          )
          and not exists (
            select 1 from public.leave_requests lr
            where lr.employee_id = s.employee_id
              and lr.store_id = v_store
              and lr.status = 'approved'
              and lr.start_date <= s.work_date
              and lr.end_date >= s.work_date
          )
      loop
        insert into public.payroll_adjustments(
          employee_id, payroll_period_id, adjustment_type, amount, reason,
          status, created_by, source_key, source_schedule_id, source_rule_id
        )
        values (
          v_event.employee_id, v_period.id, 'penalty'::public.adjustment_type,
          v_rule.amount, v_rule.label || ' · vắng ca ngày ' || v_event.work_date,
          'pending'::public.adjustment_status, auth.uid(),
          'rule:' || v_rule.id || ':absence:' || v_event.schedule_id,
          v_event.schedule_id, v_rule.id
        )
        on conflict (source_key) where source_key is not null do nothing;
        get diagnostics v_rows = row_count;
        v_created := v_created + v_rows;
      end loop;
    end if;
  end loop;

  insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
  values (
    auth.uid(), v_store, 'owner_generate_payroll_penalties',
    'payroll_period', v_period.id,
    jsonb_build_object('created_adjustments', v_created)
  );

  return v_created;
end;
$$;


--
-- Name: owner_get_employee_bank_details(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_get_employee_bank_details(p_employee_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_employee_store uuid;
  v_result jsonb;
begin
  select store_id into v_store
  from public.profiles
  where id=auth.uid() and role='owner' and employment_status='active';
  if not found or v_store is null then raise exception 'FORBIDDEN'; end if;
  select store_id into v_employee_store
  from public.profiles
  where id=p_employee_id and role='employee';
  if not found or v_employee_store is distinct from v_store then raise exception 'FORBIDDEN'; end if;
  select jsonb_build_object(
    'bank_name',bank_name,
    'account_holder',account_holder,
    'account_number',account_number,
    'branch_name',branch_name
  ) into v_result
  from public.employee_bank_details
  where employee_id=p_employee_id;
  return coalesce(v_result,jsonb_build_object(
    'bank_name','','account_holder','','account_number','','branch_name',''
  ));
end;
$$;


--
-- Name: owner_get_manager_permissions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_get_manager_permissions() RETURNS TABLE(permission_key text, enabled boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: owner_review_payroll_adjustment(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_review_payroll_adjustment(p_adjustment_id uuid, p_action text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_status public.adjustment_status;
  v_period_id uuid;
  v_period_status public.payroll_status;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;

  select a.status,a.payroll_period_id,p.status
    into v_status,v_period_id,v_period_status
  from public.payroll_adjustments a
  join public.payroll_periods p on p.id=a.payroll_period_id
  where a.id=p_adjustment_id and p.store_id=v_store
  for update;

  if not found then raise exception 'DIEU_CHINH_NOT_FOUND'; end if;
  if v_status<>'pending' then raise exception 'DIEU_CHINH_DA_XU_LY'; end if;
  if v_period_status in ('locked','paid') then raise exception 'KY_LUONG_DA_CHOT'; end if;

  if lower(p_action)='approve' then
    update public.payroll_adjustments
    set status='approved',approved_by=auth.uid(),approved_at=now(),updated_at=now()
    where id=p_adjustment_id;

    -- Recalculate immediately so payroll_runs.net_amount reflects the approval.
    perform public.owner_calculate_payroll(v_period_id);
  elsif lower(p_action)='reject' then
    update public.payroll_adjustments
    set status='rejected',approved_by=auth.uid(),approved_at=now(),updated_at=now()
    where id=p_adjustment_id;
  else
    raise exception 'ACTION_KHONG_HOP_LE';
  end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'owner_review_payroll_adjustment','payroll_adjustment',p_adjustment_id,
         jsonb_build_object('action',lower(p_action),'payroll_recalculated',lower(p_action)='approve'));
  return true;
end;
$$;


--
-- Name: owner_review_payroll_adjustment_guarded(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_review_payroll_adjustment_guarded(p_adjustment_id uuid, p_action text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
declare
  v_store uuid;
  v_adjustment public.payroll_adjustments%rowtype;
  v_period public.payroll_periods%rowtype;
  v_source_date date;
  v_required integer;
  v_late_count integer;
  v_exempt boolean := false;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = auth.uid()
    and p.role = 'owner'::public.user_role
    and p.employment_status = 'active'::public.employment_status;
  if v_store is null then raise exception 'FORBIDDEN'; end if;
  if lower(coalesce(p_action, '')) not in ('approve', 'reject') then
    raise exception 'ACTION_KHONG_HOP_LE';
  end if;

  select a.* into v_adjustment
  from public.payroll_adjustments a
  join public.payroll_periods pp on pp.id = a.payroll_period_id
  join public.profiles e on e.id = a.employee_id
  where a.id = p_adjustment_id
    and pp.store_id = v_store
    and e.store_id = v_store
  for update of a, pp;
  if not found then raise exception 'DIEU_CHINH_NOT_FOUND'; end if;
  if v_adjustment.status <> 'pending'::public.adjustment_status then
    raise exception 'DIEU_CHINH_DA_XU_LY';
  end if;

  select pp.* into v_period
  from public.payroll_periods pp
  where pp.id = v_adjustment.payroll_period_id
  for update;
  if not found then raise exception 'KY_LUONG_NOT_FOUND'; end if;
  if v_period.status in ('locked'::public.payroll_status, 'paid'::public.payroll_status) then
    raise exception 'KY_LUONG_DA_CHOT';
  end if;

  if lower(p_action) = 'approve'
     and v_adjustment.source_key like 'rule:%:late:%'
     and v_adjustment.source_schedule_id is not null then
    select exists (
      select 1
      from public.schedule_requests sr
      where sr.schedule_id = v_adjustment.source_schedule_id
        and sr.employee_id = v_adjustment.employee_id
        and sr.request_type = 'late'
        and sr.status = 'approved'
    ) into v_exempt;
  elsif lower(p_action) = 'approve'
     and v_adjustment.source_key like 'rule:%:late-month:%'
     and v_adjustment.source_schedule_id is not null
     and v_adjustment.source_rule_id is not null then
    select s.work_date into v_source_date
    from public.work_schedules s
    where s.id = v_adjustment.source_schedule_id
      and s.store_id = v_store;
    select r.threshold_occurrences into v_required
    from public.payroll_penalty_rules r
    where r.id = v_adjustment.source_rule_id
      and r.rule_type = 'late_monthly';
    if v_source_date is not null and v_required is not null then
      select count(*)::integer into v_late_count
      from public.attendance a
      join public.work_schedules s on s.id = a.schedule_id
      where a.employee_id = v_adjustment.employee_id
        and s.store_id = v_store
        and date_trunc('month', s.work_date::timestamp)
            = date_trunc('month', v_source_date::timestamp)
        and s.status <> 'cancelled'
        and s.employee_id = a.employee_id
        and a.check_in is not null
        and coalesce(a.late_minutes, 0) > 0
        and not exists (
          select 1
          from public.schedule_requests sr
          where sr.schedule_id = s.id
            and sr.employee_id = a.employee_id
            and sr.request_type = 'late'
            and sr.status = 'approved'
        );
      v_exempt := v_late_count < v_required;
    end if;
  end if;

  if v_exempt then
    update public.payroll_adjustments
    set status = 'rejected'::public.adjustment_status,
        approved_by = auth.uid(),
        approved_at = now(),
        updated_at = now()
    where id = v_adjustment.id;

    insert into public.audit_logs(actor_id, store_id, action, entity_type, entity_id, new_data)
    values (
      auth.uid(), v_store, 'owner_auto_reject_exempt_late_penalty',
      'payroll_adjustment', v_adjustment.id,
      jsonb_build_object('schedule_id', v_adjustment.source_schedule_id)
    );

    return jsonb_build_object('status', 'approved_late_exempted');
  end if;

  perform public.owner_review_payroll_adjustment(p_adjustment_id, p_action);
  return jsonb_build_object('status', 'processed');
end;
$$;


--
-- Name: owner_save_employee_bank_details(uuid, text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_save_employee_bank_details(p_employee_id uuid, p_bank_name text, p_account_holder text, p_account_number text, p_branch_name text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_employee_store uuid;
  v_bank text:=trim(coalesce(p_bank_name,''));
  v_holder text:=trim(coalesce(p_account_holder,''));
  v_number text:=trim(coalesce(p_account_number,''));
  v_branch text:=trim(coalesce(p_branch_name,''));
begin
  select store_id into v_store
  from public.profiles
  where id=auth.uid() and role='owner' and employment_status='active';
  if not found or v_store is null then raise exception 'FORBIDDEN'; end if;
  select store_id into v_employee_store
  from public.profiles
  where id=p_employee_id and role='employee';
  if not found or v_employee_store is distinct from v_store then raise exception 'FORBIDDEN'; end if;
  if length(v_bank)>120 or length(v_holder)>160 or length(v_number)>64 or length(v_branch)>160 then
    raise exception 'BANK_DETAILS_TOO_LONG';
  end if;
  if num_nonnulls(nullif(v_bank,''),nullif(v_holder,''),nullif(v_number,'')) not in (0,3) then
    raise exception 'BANK_DETAILS_INCOMPLETE';
  end if;
  insert into public.employee_bank_details(
    employee_id,bank_name,account_holder,account_number,branch_name,updated_by,updated_at
  ) values(p_employee_id,v_bank,v_holder,v_number,v_branch,auth.uid(),now())
  on conflict(employee_id) do update set
    bank_name=excluded.bank_name,
    account_holder=excluded.account_holder,
    account_number=excluded.account_number,
    branch_name=excluded.branch_name,
    updated_by=excluded.updated_by,
    updated_at=now();
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'owner_update_employee_bank_details','employee_bank_details',p_employee_id,
    jsonb_build_object('bank_details_updated',true));
  return true;
end;
$$;


--
-- Name: owner_save_manager_permissions(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_save_manager_permissions(p_permissions jsonb) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid;
  v_row jsonb;
  v_key text;
  v_enabled boolean;
begin
  if public.my_role()<>'owner' then raise exception 'FORBIDDEN'; end if;
  select store_id into v_store from public.profiles where id=auth.uid() and employment_status='active';
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;
  if jsonb_typeof(coalesce(p_permissions,'[]'::jsonb))<>'array' then raise exception 'DU_LIEU_QUYEN_KHONG_HOP_LE'; end if;

  for v_row in select value from jsonb_array_elements(p_permissions) loop
    v_key:=v_row->>'permission_key';
    v_enabled:=coalesce((v_row->>'enabled')::boolean,false);
    if v_key not in ('attendance_process','schedule_manage','shift_registration','leave_manage','employee_basic','employee_create','audit_view') then
      raise exception 'QUYEN_KHONG_HOP_LE';
    end if;
    insert into public.manager_permissions(store_id,permission_key,enabled,updated_by,updated_at)
    values(v_store,v_key,v_enabled,auth.uid(),now())
    on conflict(store_id,permission_key) do update set enabled=excluded.enabled,updated_by=excluded.updated_by,updated_at=now();
  end loop;

  insert into public.audit_logs(actor_id,action,entity_type,new_data)
  values(auth.uid(),'owner_save_manager_permissions','manager_permissions',jsonb_build_object('permissions',p_permissions));
  return true;
end;
$$;


--
-- Name: owner_save_manager_permissions_v2(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_save_manager_permissions_v2(p_permissions jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    SET row_security TO 'off'
    AS $$
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
$$;


--
-- Name: owner_set_employee_salary(uuid, numeric, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_set_employee_salary(p_employee_id uuid, p_hourly_rate numeric, p_effective_date date DEFAULT CURRENT_DATE) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_store uuid; v_tz text; v_today date;
begin
  if public.my_role()<>'owner' then raise exception 'FORBIDDEN'; end if;
  if p_hourly_rate is null or p_hourly_rate<0 then raise exception 'MUC_LUONG_KHONG_HOP_LE'; end if;
  select store_id into v_store from public.profiles where id=p_employee_id and role='employee';
  if v_store is null then raise exception 'NHAN_VIEN_NOT_FOUND'; end if;
  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz from public.stores where id=v_store;
  v_today:=(now() at time zone v_tz)::date;
  if p_effective_date is null or p_effective_date<v_today then raise exception 'NGAY_AP_DUNG_KHONG_HOP_LE'; end if;
  insert into public.employee_salary_versions(employee_id,effective_from,hourly_rate,created_by,updated_at)
  values(p_employee_id,p_effective_date,p_hourly_rate,auth.uid(),now())
  on conflict(employee_id,effective_from) do update set hourly_rate=excluded.hourly_rate,created_by=excluded.created_by,updated_at=now();
  if p_effective_date=v_today then
    update public.profiles set hourly_rate=p_hourly_rate,updated_at=now() where id=p_employee_id;
  end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'owner_set_employee_salary','profile',p_employee_id,jsonb_build_object('effective_date',p_effective_date,'hourly_rate',p_hourly_rate));
  return true;
end;
$$;


--
-- Name: owner_set_payroll_status(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_set_payroll_status(p_payroll_period_id uuid, p_status text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_role text; v_store uuid; v_old public.payroll_status; v_new public.payroll_status;
begin
  select role::text,store_id into v_role,v_store from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  begin v_new:=lower(p_status)::public.payroll_status; exception when others then
    raise exception 'TRANG_THAI_LUONG_KHONG_HOP_LE'; end;
  select status into v_old from public.payroll_periods
  where id=p_payroll_period_id and store_id=v_store for update;
  if not found then raise exception 'KY_LUONG_NOT_FOUND'; end if;
  if not ((v_old='draft' and v_new='review') or (v_old='review' and v_new='locked')
    or (v_old='locked' and v_new='paid')) then raise exception 'CHUYEN_TRANG_THAI_KHONG_HOP_LE'; end if;
  if v_new='locked' then
    if exists(select 1 from public.payroll_adjustments where payroll_period_id=p_payroll_period_id and status='pending') then
      raise exception 'CON_DIEU_CHINH_CHO_DUYET';
    end if;
    if not exists(select 1 from public.payroll_runs where payroll_period_id=p_payroll_period_id) then
      raise exception 'CHUA_TINH_LUONG';
    end if;
  end if;
  update public.payroll_periods set status=v_new,
    locked_at=case when v_new='locked' then now() else locked_at end,
    locked_by=case when v_new='locked' then auth.uid() else locked_by end,
    paid_at=case when v_new='paid' then now() else paid_at end,
    paid_by=case when v_new='paid' then auth.uid() else paid_by end,updated_at=now()
  where id=p_payroll_period_id;
  insert into public.audit_logs(actor_id,store_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),v_store,'owner_set_payroll_status','payroll_period',p_payroll_period_id,
    jsonb_build_object('from',v_old,'to',v_new));
  return true;
end;
$$;


--
-- Name: owner_supplement_attendance(uuid, timestamp with time zone, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.owner_supplement_attendance(p_schedule_id uuid, p_check_in_at timestamp with time zone, p_check_out_at timestamp with time zone, p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
  v_att public.attendance%rowtype;
  v_template public.shift_templates%rowtype;
  v_start timestamptz;
  v_end timestamptz;
  v_worked integer;
  v_allowed integer;
  v_break integer := 0;
  v_late integer;
  v_early integer;
  v_now timestamptz := now();
  v_old jsonb;
  v_reason text := nullif(trim(coalesce(p_note, '')), '');
begin
  select role::text, store_id into v_role, v_store
  from public.profiles
  where id = auth.uid() and employment_status = 'active';
  if v_role not in ('owner', 'manager') then raise exception 'FORBIDDEN'; end if;
  if v_reason is null then raise exception 'LY_DO_BAT_BUOC'; end if;

  perform pg_advisory_xact_lock(hashtextextended(coalesce(p_schedule_id::text, '') || ':attendance', 0));
  select * into v_schedule
  from public.work_schedules
  where id = p_schedule_id and store_id = v_store
  for update;
  if not found or v_schedule.employee_id is null then raise exception 'CA_KHONG_HOP_LE'; end if;
  if v_schedule.status not in ('assigned', 'completed') then raise exception 'CA_KHONG_HOP_LE'; end if;
  if exists (
    select 1 from public.payroll_periods p
    where p.store_id = v_store and p.status in ('locked', 'paid')
      and v_schedule.work_date between p.start_date and p.end_date
  ) then raise exception 'KY_LUONG_DA_CHOT'; end if;

  v_start := v_schedule.start_at;
  v_end := v_schedule.end_at;
  if p_check_in_at is null or p_check_out_at is null or p_check_out_at <= p_check_in_at then
    raise exception 'GIO_KHONG_HOP_LE';
  end if;
  if p_check_in_at < v_start or p_check_in_at >= v_end or p_check_out_at <= v_start then
    raise exception 'GIO_NAM_NGOAI_CA';
  end if;
  if p_check_in_at > v_now or p_check_out_at > v_now then raise exception 'GIO_TUONG_LAI'; end if;

  select * into v_template
  from public.shift_templates where id = v_schedule.shift_template_id;
  v_break := coalesce(v_template.break_minutes, 0);
  v_allowed := greatest(
    0, floor(extract(epoch from (v_end - v_start)) / 60)::integer - v_break
  );
  -- Apply the fixed break after clipping the actual work interval to the
  -- scheduled shift, so late arrival/early departure are both reflected.
  v_worked := greatest(
    0,
    least(
      v_allowed,
      floor(extract(epoch from (
        least(p_check_out_at, v_end) - greatest(p_check_in_at, v_start)
      )) / 60)::integer - v_break
    )
  );
  v_late := greatest(0, floor(extract(epoch from (p_check_in_at - v_start)) / 60)::integer);
  v_early := greatest(0, floor(extract(epoch from (v_end - p_check_out_at)) / 60)::integer);

  select * into v_att
  from public.attendance where schedule_id = v_schedule.id
  for update;
  if v_att.id is null then
    insert into public.attendance(
      schedule_id, employee_id, device_id, check_in, check_out,
      check_in_status, check_out_status, late_minutes, early_leave_minutes,
      worked_minutes, note
    ) values (
      v_schedule.id, v_schedule.employee_id, null, p_check_in_at, p_check_out_at,
      'manual'::public.attendance_status, 'manual'::public.attendance_status,
      v_late, v_early, v_worked,
      concat_ws(' · ', case when v_role = 'owner' then 'Owner bổ sung chấm công'
                            else 'Quản lý bổ sung chấm công' end, v_reason)
    ) returning * into v_att;
    v_old := '{}'::jsonb;
  else
    v_old := jsonb_build_object(
      'check_in', v_att.check_in, 'check_out', v_att.check_out,
      'worked_minutes', v_att.worked_minutes, 'late_minutes', v_att.late_minutes,
      'early_leave_minutes', v_att.early_leave_minutes, 'note', v_att.note
    );
    update public.attendance
    set check_in = p_check_in_at, check_out = p_check_out_at, device_id = null,
        check_in_latitude = null, check_in_longitude = null, check_in_distance_m = null,
        check_out_latitude = null, check_out_longitude = null, check_out_distance_m = null,
        check_in_status = 'manual'::public.attendance_status,
        check_out_status = 'manual'::public.attendance_status,
        late_minutes = v_late, early_leave_minutes = v_early,
        worked_minutes = v_worked, check_in_device_key = null,
        check_out_device_key = null,
        note = concat_ws(' · ', case when v_role = 'owner' then 'Owner điều chỉnh chấm công'
                                     else 'Quản lý điều chỉnh chấm công' end, v_reason),
        updated_at = v_now
    where id = v_att.id returning * into v_att;
  end if;

  update public.work_schedules
  set status = 'completed', updated_at = v_now
  where id = v_schedule.id and status in ('assigned', 'completed');

  insert into public.attendance_events(
    attendance_id, employee_id, event_type, event_at, success, reason, metadata
  ) values (
    v_att.id, v_att.employee_id,
    case when v_old = '{}'::jsonb then 'manual_attendance_added' else 'manual_attendance_updated' end,
    v_now, true, v_reason,
    jsonb_build_object('schedule_id', v_schedule.id, 'check_in_at', p_check_in_at,
                       'check_out_at', p_check_out_at, 'worked_minutes', v_worked,
                       'late_minutes', v_late, 'early_leave_minutes', v_early)
  );
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, old_data, new_data)
  values (
    auth.uid(),
    case when v_old = '{}'::jsonb
      then case when v_role = 'owner' then 'owner_supplement_attendance' else 'manager_supplement_attendance' end
      else case when v_role = 'owner' then 'owner_adjust_attendance' else 'manager_adjust_attendance' end
    end,
    'attendance', v_att.id, v_old,
    jsonb_build_object('schedule_id', v_schedule.id, 'employee_id', v_att.employee_id,
                       'check_in', v_att.check_in, 'check_out', v_att.check_out,
                       'worked_minutes', v_att.worked_minutes, 'late_minutes', v_att.late_minutes,
                       'early_leave_minutes', v_att.early_leave_minutes, 'reason', v_reason)
  );
  return jsonb_build_object(
    'attendance_id', v_att.id, 'schedule_id', v_schedule.id,
    'employee_id', v_att.employee_id, 'check_in', v_att.check_in,
    'check_out', v_att.check_out, 'worked_minutes', v_att.worked_minutes,
    'late_minutes', v_att.late_minutes, 'early_leave_minutes', v_att.early_leave_minutes
  );
end;
$$;


--
-- Name: process_shift_registration_automation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.process_shift_registration_automation() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  r record;
  w record;
  v_now timestamptz:=now();
  prepared integer:=0;
  generated integer:=0;
  finalized jsonb;
  ws date;
begin
  perform public.ensure_recurring_shift_registration_windows();

  for r in
    select * from public.shift_registration_recurring_rules
    where is_active=true and auto_open=true
  loop
    for w in
      select *
      from public.shift_registration_windows
      where store_id=r.store_id
        and status='open'
        and open_at<=v_now
        and close_at>v_now
    loop
      ws:=w.week_start;
      generated:=generated+
        coalesce(
          (public.materialize_weekly_registration_slots(r.store_id,ws)->>'created_slots')::integer,
          0
        );
      prepared:=prepared+1;
    end loop;
  end loop;

  finalized:=public.auto_finalize_due_shift_registrations();

  return jsonb_build_object(
    'prepared_windows',prepared,
    'created_slots',generated,
    'finalized',finalized
  );
end;
$$;


--
-- Name: register_for_shift(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.register_for_shift(p_schedule_id uuid, p_note text DEFAULT NULL::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_window public.shift_registration_windows%rowtype;
  v_reg uuid;
  v_existing uuid;
  v_conflict uuid;
  v_group uuid;
  v_capacity integer;
  v_reserved integer;
  v_open timestamptz;
  v_close timestamptz;
  v_week date;
  v_now timestamptz := now();
  v_window_is_authoritative boolean := false;
begin
  select p.store_id into v_store
  from public.profiles p
  where p.id = v_uid and p.role = 'employee' and p.employment_status = 'active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select * into v_schedule
  from public.work_schedules
  where id = p_schedule_id and store_id = v_store
  for update;
  if not found then raise exception 'CA_KHONG_TON_TAI'; end if;
  if v_schedule.status = 'cancelled' then raise exception 'CA_DA_HUY'; end if;
  if v_schedule.status <> 'open' or v_schedule.employee_id is not null then
    raise exception 'CA_DA_DUOC_XEP';
  end if;

  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id = v_store and is_active = true
  order by updated_at desc nulls last
  limit 1;
  if not found then raise exception 'DANG_KY_CHUA_MO'; end if;

  v_week := date_trunc('week', v_schedule.work_date)::date;
  select x.open_at, x.close_at into v_open, v_close
  from public.registration_window_times(
    v_week, v_rule.open_weekday, v_rule.open_time,
    v_rule.close_weekday, v_rule.close_time
  ) x;

  select * into v_window
  from public.shift_registration_windows
  where store_id = v_store and week_start = v_week
  for update;

  if found then
    if v_window.status = 'finalized' then raise exception 'DANG_KY_DA_DONG'; end if;
    if v_window.status = 'open' then
      if v_now < v_window.open_at then
        if not (coalesce(v_rule.auto_open, true) and v_now >= v_open and v_now <= v_close) then
          raise exception 'DANG_KY_CHUA_MO';
        end if;
      elsif v_now <= v_window.close_at then
        v_window_is_authoritative := true;
      end if;
      if v_window_is_authoritative then
        v_open := v_window.open_at;
        v_close := v_window.close_at;
      end if;
    end if;

    if not v_window_is_authoritative
       and coalesce(v_rule.auto_open, true)
       and v_now >= v_open and v_now <= v_close then
      perform set_config('app.hr_registration_auto_open', 'on', true);
      update public.shift_registration_windows
      set open_at = v_open, close_at = v_close, status = 'open',
          closed_at = null, closed_by = null, finalized_at = null,
          finalized_by = null, updated_at = v_now
      where id = v_window.id
      returning * into v_window;
      perform set_config('app.hr_registration_auto_open', 'off', true);
      v_window_is_authoritative := true;
    elsif not v_window_is_authoritative then
      if v_window.status <> 'open' then raise exception 'DANG_KY_CHUA_MO'; end if;
      if v_now > v_window.close_at then raise exception 'DANG_KY_DA_DONG'; end if;
    end if;
  else
    if not (coalesce(v_rule.auto_open, true) and v_now >= v_open and v_now <= v_close) then
      raise exception 'DANG_KY_CHUA_MO';
    end if;
    perform set_config('app.hr_registration_auto_open', 'on', true);
    insert into public.shift_registration_windows(
      store_id, week_start, open_at, close_at, status
    ) values (v_store, v_week, v_open, v_close, 'open')
    returning * into v_window;
    perform set_config('app.hr_registration_auto_open', 'off', true);
    v_window_is_authoritative := true;
  end if;

  if v_now < v_open then raise exception 'DANG_KY_CHUA_MO'; end if;
  if v_now > v_close then raise exception 'DANG_KY_DA_DONG'; end if;
  if v_window.status <> 'open' then raise exception 'DANG_KY_CHUA_MO'; end if;

  select r.id into v_existing
  from public.shift_registrations r
  where r.schedule_id = p_schedule_id
    and r.employee_id = v_uid
    and r.status in ('pending', 'approved')
  order by r.created_at desc
  limit 1;
  if v_existing is not null then return v_existing; end if;

  select public.employee_schedule_conflict(
    v_uid, v_schedule.start_at, v_schedule.end_at, p_schedule_id
  ) into v_conflict;
  if v_conflict is not null then raise exception 'TRUNG_CA'; end if;

  v_group := coalesce(v_schedule.shift_group_id, v_schedule.id);
  -- Serialize all reservations for the same shift group so simultaneous taps
  -- on different capacity slots cannot exceed the configured headcount.
  perform pg_advisory_xact_lock(
    hashtextextended(v_store::text || ':' || v_group::text, 0)
  );

  if exists (
    select 1
    from public.shift_registrations r
    where r.schedule_id = p_schedule_id
      and r.status in ('pending', 'approved')
  ) then
    raise exception 'CA_DA_HET_CHO';
  end if;

  select count(*)::integer into v_capacity
  from public.work_schedules s
  where s.store_id = v_store
    and coalesce(s.shift_group_id, s.id) = v_group
    and s.status <> 'cancelled';

  select count(*)::integer into v_reserved
  from public.work_schedules s
  where s.store_id = v_store
    and coalesce(s.shift_group_id, s.id) = v_group
    and s.status = 'assigned';

  select v_reserved + count(distinct r.schedule_id)::integer into v_reserved
  from public.shift_registrations r
  join public.work_schedules s on s.id = r.schedule_id
  where s.store_id = v_store
    and coalesce(s.shift_group_id, s.id) = v_group
    and s.status = 'open'
    and r.status = 'pending';

  if v_reserved >= v_capacity then raise exception 'CA_DA_HET_CHO'; end if;

  insert into public.shift_registrations(
    schedule_id, employee_id, status, note, requested_at
  ) values (
    p_schedule_id, v_uid, 'pending', nullif(trim(p_note), ''), v_now
  ) returning id into v_reg;

  insert into public.audit_logs(
    actor_id, store_id, action, entity_type, entity_id, new_data
  ) values (
    v_uid, v_store, 'register_for_shift', 'shift_registration', v_reg,
    jsonb_build_object(
      'schedule_id', p_schedule_id, 'week_start', v_week,
      'open_at', v_open, 'close_at', v_close
    )
  );
  return v_reg;
end;
$$;


--
-- Name: registration_window_times(date, integer, time without time zone, integer, time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.registration_window_times(p_week_start date, p_open_weekday integer, p_open_time time without time zone, p_close_weekday integer, p_close_time time without time zone) RETURNS TABLE(open_at timestamp with time zone, close_at timestamp with time zone)
    LANGUAGE sql IMMUTABLE
    SET search_path TO 'public'
    AS $$
  with x as (
    select
      date_trunc('week',p_week_start)::date + (p_open_weekday - 1) as od,
      date_trunc('week',p_week_start)::date + (p_close_weekday - 1) as cd
  ), y as (
    select od, case when cd < od then cd + 7 else cd end as cd
    from x
  )
  select
    (od::text || ' ' || p_open_time::text || '+07:00')::timestamptz,
    (cd::text || ' ' || p_close_time::text || '+07:00')::timestamptz
  from y;
$$;


--
-- Name: replace_employees_to_schedule_group(uuid, uuid[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.replace_employees_to_schedule_group(p_schedule_id uuid, p_employee_ids uuid[] DEFAULT '{}'::uuid[], p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
  v_now timestamptz := now();
  v_group uuid;
  v_employee uuid;
  v_slot_id uuid;
  v_conflict uuid;
  v_current_ids uuid[];
  v_selected_ids uuid[] := coalesce(p_employee_ids,'{}'::uuid[]);
  v_assigned_count integer := 0;
  v_capacity integer := 0;
begin
  select role::text, store_id
    into v_role, v_store
  from public.profiles
  where id = auth.uid()
    and employment_status = 'active';

  if v_role not in ('owner','manager') then
    raise exception 'FORBIDDEN';
  end if;

  if (select count(*) from unnest(v_selected_ids)) <> (select count(*) from (select distinct unnest(v_selected_ids)) q) then
    raise exception 'TRUNG_NHAN_VIEN';
  end if;

  select *
    into v_schedule
  from public.work_schedules
  where id = p_schedule_id
    and store_id = v_store
  for update;

  if not found then
    raise exception 'CA_NOT_FOUND';
  end if;

  if v_schedule.status = 'cancelled' then
    raise exception 'CA_DA_HUY';
  end if;

  if v_schedule.end_at is not null and v_now > v_schedule.end_at then
    raise exception 'CA_DA_KET_THUC';
  end if;

  v_group := coalesce(v_schedule.shift_group_id, v_schedule.id);

  -- Serialize all changes to this shift group. This is the concurrency guard
  -- used in addition to Realtime, so two devices cannot save conflicting capacity.
  perform pg_advisory_xact_lock(
    hashtextextended(v_store::text || ':' || v_group::text || ':replace_assign', 0)
  );

  -- Lock every slot in the group before comparing the submitted selection.
  perform 1
  from public.work_schedules ws
  where ws.store_id = v_store
    and coalesce(ws.shift_group_id, ws.id) = v_group
    and ws.status <> 'cancelled'
  order by ws.id
  for update;

  select count(*)::integer
    into v_capacity
  from public.work_schedules ws
  where ws.store_id = v_store
    and coalesce(ws.shift_group_id, ws.id) = v_group
    and ws.status <> 'cancelled';

  if coalesce(array_length(v_selected_ids,1),0) > v_capacity then
    raise exception 'KHONG_DU_CHO';
  end if;

  select array_agg(ws.employee_id order by ws.id)
    into v_current_ids
  from public.work_schedules ws
  where ws.store_id = v_store
    and coalesce(ws.shift_group_id, ws.id) = v_group
    and ws.status = 'assigned'
    and ws.employee_id is not null;

  -- An employee already assigned to this group is not a conflict with himself.
  -- New selections are checked against all other schedules.
  foreach v_employee in array v_selected_ids loop
    if not exists (
      select 1
      from public.profiles p
      where p.id = v_employee
        and p.store_id = v_store
        and p.role = 'employee'
        and p.employment_status = 'active'
    ) then
      raise exception 'NHAN_VIEN_KHONG_HOP_LE';
    end if;

    if not coalesce(v_employee = any(v_current_ids),false) then
      select public.employee_schedule_conflict(v_employee,v_schedule.start_at,v_schedule.end_at,v_schedule.id)
        into v_conflict;
      if v_conflict is not null then
        raise exception 'TRUNG_CA';
      end if;
    end if;
  end loop;

  -- Never detach a person after real attendance has started. Empty placeholder
  -- attendance rows are safe to remove with the assignment.
  for v_slot_id in
    select ws.id
    from public.work_schedules ws
    where ws.store_id = v_store
      and coalesce(ws.shift_group_id,ws.id) = v_group
      and ws.status = 'assigned'
      and ws.employee_id is not null
      and not coalesce(ws.employee_id = any(v_selected_ids),false)
    order by ws.id
  loop
    if exists (
      select 1
      from public.attendance a
      where a.schedule_id = v_slot_id
        and (a.check_in is not null or a.check_out is not null)
    ) then
      raise exception 'DA_CO_CHAM_CONG';
    end if;

    delete from public.attendance
    where schedule_id = v_slot_id
      and check_in is null
      and check_out is null;

    update public.shift_registrations
    set status = 'cancelled',
        reviewed_by = auth.uid(),
        reviewed_at = v_now,
        rejection_reason = coalesce(nullif(trim(p_note),''),'Đã thay khỏi ca'),
        updated_at = v_now
    where schedule_id = v_slot_id
      and status in ('pending','approved');

    insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
    select auth.uid(),'replace_employee_from_schedule','work_schedule',ws.id,
      jsonb_build_object('employee_id',ws.employee_id,'status',ws.status),
      jsonb_build_object('employee_id',null,'status','open','reason',p_note)
    from public.work_schedules ws
    where ws.id = v_slot_id;

    update public.work_schedules
    set employee_id = null,
        status = 'open',
        assigned_at = null,
        note = concat_ws(' · ',note,nullif(trim(p_note),'')),
        updated_at = v_now
    where id = v_slot_id;
  end loop;

  -- Keep already-selected employees in their existing slots. Assign only the
  -- newly selected employees to the now-open slots, in deterministic order.
  foreach v_employee in array v_selected_ids loop
    if not exists (
      select 1
      from public.work_schedules ws
      where ws.store_id = v_store
        and coalesce(ws.shift_group_id,ws.id) = v_group
        and ws.status = 'assigned'
        and ws.employee_id = v_employee
    ) then
      select ws.id
        into v_slot_id
      from public.work_schedules ws
      where ws.store_id = v_store
        and coalesce(ws.shift_group_id,ws.id) = v_group
        and ws.status = 'open'
        and ws.employee_id is null
      order by ws.id
      limit 1
      for update;

      if v_slot_id is null then
        raise exception 'KHONG_DU_CHO';
      end if;

      update public.work_schedules
      set employee_id = v_employee,
          status = 'assigned',
          assigned_at = v_now,
          note = concat_ws(' · ',note,nullif(trim(p_note),'')),
          updated_at = v_now
      where id = v_slot_id;

      -- The direct Owner/Manager assignment is authoritative for this slot.
      update public.shift_registrations
      set status = case when employee_id = v_employee then 'approved'::public.registration_status else 'rejected'::public.registration_status end,
          reviewed_by = auth.uid(),
          reviewed_at = v_now,
          rejection_reason = case when employee_id = v_employee then null else 'Ca đã được xếp cho nhân viên khác' end,
          updated_at = v_now
      where schedule_id = v_slot_id
        and status in ('pending','approved');

      insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
      values(auth.uid(),'replace_employee_to_schedule','work_schedule',v_slot_id,
        jsonb_build_object('employee_id',v_employee,'group_id',v_group,'note',p_note));
    end if;
  end loop;

  select count(*)::integer into v_assigned_count
  from public.work_schedules ws
  where ws.store_id = v_store
    and coalesce(ws.shift_group_id,ws.id) = v_group
    and ws.status = 'assigned'
    and ws.employee_id is not null;

  return jsonb_build_object(
    'group_id',v_group,
    'assigned_count',v_assigned_count,
    'slots',coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',ws.id,
        'employee_id',ws.employee_id,
        'status',ws.status,
        'assigned_at',ws.assigned_at
      ) order by ws.id)
      from public.work_schedules ws
      where ws.store_id = v_store
        and coalesce(ws.shift_group_id,ws.id) = v_group
        and ws.status <> 'cancelled'
    ),'[]'::jsonb)
  );
end;
$$;


--
-- Name: request_attendance_device(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_attendance_device(p_device_key text, p_device_name text DEFAULT NULL::text, p_platform text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_employee uuid := auth.uid();
  v_store uuid;
  v_role text;
  v_existing public.devices%rowtype;
  v_approved public.devices%rowtype;
  v_pending public.devices%rowtype;
  v_device_name text := nullif(trim(coalesce(p_device_name,'')), '');
  v_platform text := nullif(trim(coalesce(p_platform,'')), '');
  v_user_agent text := nullif(trim(coalesce(p_user_agent,'')), '');
begin
  if v_employee is null then
    raise exception 'FORBIDDEN';
  end if;

  select role::text, store_id
    into v_role, v_store
  from public.profiles
  where id=v_employee
    and employment_status='active'
  for update;

  if v_role is null then
    raise exception 'FORBIDDEN';
  end if;
  if v_role<>'employee' then
    raise exception 'EMPLOYEE_REQUIRED';
  end if;
  if nullif(trim(coalesce(p_device_key,'')), '') is null then
    raise exception 'DEVICE_KEY_REQUIRED';
  end if;

  -- device_key là định danh của browser/device trong WebApp và unique toàn hệ thống.
  -- Nếu key đã thuộc tài khoản khác thì không được chuyển quyền bằng request này.
  select * into v_existing
  from public.devices
  where device_key=trim(p_device_key)
  for update;

  if found and v_existing.employee_id<>v_employee then
    raise exception 'THIET_BI_DA_LIEN_KET_TAI_KHOAN_KHAC';
  end if;

  if found then
    if v_existing.status='approved' then
      update public.devices
      set device_name=coalesce(v_device_name,device_name),
          platform=coalesce(v_platform,platform),
          user_agent=coalesce(v_user_agent,user_agent),
          last_seen_at=now(),
          updated_at=now()
      where id=v_existing.id;

      insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
      values(auth.uid(),'attendance_device_accessed','device',v_existing.id,
             jsonb_build_object('status',v_existing.status),
             jsonb_build_object('status','approved','reused',true));

      return jsonb_build_object('status','approved','reused',true,'device_id',v_existing.id);
    end if;

    if v_existing.status='pending' then
      update public.devices
      set device_name=coalesce(v_device_name,device_name),
          platform=coalesce(v_platform,platform),
          user_agent=coalesce(v_user_agent,user_agent),
          requested_at=now(),
          last_seen_at=now(),
          updated_at=now()
      where id=v_existing.id;

      return jsonb_build_object('status','pending','reused',true,'device_id',v_existing.id);
    end if;

    if v_existing.status in ('revoked','rejected') then
      update public.devices
      set status='pending',
          device_name=coalesce(v_device_name,device_name),
          platform=coalesce(v_platform,platform),
          user_agent=coalesce(v_user_agent,user_agent),
          requested_at=now(),
          approved_by=null,
          approved_at=null,
          rejected_reason=null,
          revoked_at=null,
          last_seen_at=now(),
          updated_at=now()
      where id=v_existing.id;

      insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
      values(auth.uid(),'request_attendance_device_reactivation','device',v_existing.id,
             jsonb_build_object('status',v_existing.status),
             jsonb_build_object('status','pending','reused',true));

      return jsonb_build_object('status','pending','reused',true,'device_id',v_existing.id);
    end if;
  end if;

  -- Chỉ cho tạo device mới nếu tài khoản chưa có thiết bị active/pending khác.
  select * into v_approved
  from public.devices
  where employee_id=v_employee
    and status='approved'
  order by approved_at desc nulls last, created_at desc
  limit 1
  for update;

  if found then
    raise exception 'NHAN_VIEN_DA_CO_THIET_BI_DUOC_DUYET';
  end if;

  select * into v_pending
  from public.devices
  where employee_id=v_employee
    and status='pending'
  order by requested_at desc, created_at desc
  limit 1
  for update;

  if found then
    return jsonb_build_object('status','pending','reused',true,'device_id',v_pending.id);
  end if;

  insert into public.devices(
    employee_id,device_key,device_name,platform,user_agent,status,requested_at,last_seen_at,created_at,updated_at
  ) values (
    v_employee,trim(p_device_key),v_device_name,v_platform,v_user_agent,'pending',now(),now(),now(),now()
  )
  returning * into v_existing;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'request_attendance_device','device',v_existing.id,
         jsonb_build_object('status','pending','reused',false));

  return jsonb_build_object('status','pending','reused',false,'device_id',v_existing.id);
end;
$$;


--
-- Name: request_leave(date, date, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_leave(p_start_date date, p_end_date date, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_store uuid;
  v_id uuid;
  v_today date;
begin
  select store_id into v_store from public.profiles
  where id=v_uid and role='employee' and employment_status='active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  select (now() at time zone coalesce(s.timezone,'Asia/Ho_Chi_Minh'))::date into v_today
  from public.stores s where s.id=v_store;
  if p_start_date is null or p_end_date is null or p_end_date<p_start_date then raise exception 'NGAY_NGHI_KHONG_HOP_LE'; end if;
  if p_start_date<v_today then raise exception 'NGAY_NGHI_DA_QUA'; end if;
  if length(trim(coalesce(p_reason,'')))<2 then raise exception 'THIEU_LY_DO_NGHI'; end if;
  if exists(select 1 from public.leave_requests where employee_id=v_uid and status in ('pending','approved')
            and start_date<=p_end_date and end_date>=p_start_date) then raise exception 'NGHI_DA_CO_YEU_CAU'; end if;
  insert into public.leave_requests(employee_id,store_id,start_date,end_date,reason,status)
  values(v_uid,v_store,p_start_date,p_end_date,trim(p_reason),'pending') returning id into v_id;
  return v_id;
end;
$$;


--
-- Name: resolve_missing_checkout(uuid, timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resolve_missing_checkout(p_attendance_id uuid, p_checkout_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_att public.attendance%rowtype;
  v_schedule public.work_schedules%rowtype;
  v_out timestamptz;
  v_allowed integer;
  v_worked integer;
  v_early integer;
  v_break integer:=0;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select * into v_att from public.attendance where id=p_attendance_id for update;
  if not found then raise exception 'CHAM_CONG_NOT_FOUND'; end if;
  select * into v_schedule from public.work_schedules where id=v_att.schedule_id;
  if not found or v_schedule.store_id is distinct from v_store then raise exception 'FORBIDDEN'; end if;
  if v_att.check_in is null then raise exception 'CHUA_CHECKIN'; end if;
  if v_att.check_out is not null then raise exception 'DA_CHECKOUT'; end if;

  select break_minutes into v_break from public.shift_templates where id=v_schedule.shift_template_id;
  v_allowed:=greatest(0,floor(extract(epoch from(v_schedule.end_at-v_schedule.start_at))/60)::integer-coalesce(v_break,0));
  v_out:=coalesce(p_checkout_at,v_schedule.end_at);
  if v_out<v_att.check_in then raise exception 'GIO_CHECKOUT_KHONG_HOP_LE'; end if;
  if v_out>now() then raise exception 'GIO_CHECKOUT_O_TUONG_LAI'; end if;
  v_worked:=greatest(0,least(v_allowed,floor(extract(epoch from(v_out-v_att.check_in))/60)::integer));
  v_early:=greatest(0,floor(extract(epoch from(v_schedule.end_at-v_out))/60)::integer);

  update public.attendance
  set check_out=v_out,check_out_status='missing_checkout',early_leave_minutes=v_early,worked_minutes=v_worked,
      note=concat_ws(' · ',note,nullif(trim(p_note),''),'Quản lý xử lý quên checkout'),updated_at=now()
  where id=v_att.id returning * into v_att;
  update public.work_schedules set status='completed',updated_at=now() where id=v_schedule.id and status='assigned';

  insert into public.attendance_events(attendance_id,employee_id,event_type,event_at,success,reason,metadata)
  values(v_att.id,v_att.employee_id,'manual_checkout',now(),true,'Quản lý xử lý quên checkout',
         jsonb_build_object('checkout_at',v_out,'worked_minutes',v_worked,'early_leave_minutes',v_early));
  return jsonb_build_object('attendance_id',v_att.id,'check_out',v_att.check_out,'worked_minutes',v_att.worked_minutes,'early_leave_minutes',v_att.early_leave_minutes);
end;
$$;


--
-- Name: review_attendance_device(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_attendance_device(p_device_id uuid, p_action text, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
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
$$;


--
-- Name: review_leave(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_leave(p_leave_id uuid, p_action text, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_employee uuid;
  v_status public.leave_status;
  v_start date;
  v_end date;
  v_tz text:='Asia/Ho_Chi_Minh';
  v_conflict uuid;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select employee_id,status,start_date,end_date into v_employee,v_status,v_start,v_end
  from public.leave_requests
  where id=p_leave_id and store_id=v_store
  for update;
  if not found then raise exception 'NGHI_NOT_FOUND'; end if;
  if v_status<>'pending' then raise exception 'NGHI_DA_XU_LY'; end if;

  if lower(p_action)='reject' then
    update public.leave_requests
    set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),
        rejection_reason=nullif(trim(coalesce(p_reason,'Từ chối bởi quản lý')),'')
    where id=p_leave_id;
    return true;
  end if;

  if lower(p_action)<>'approve' then raise exception 'ACTION_KHONG_HOP_LE'; end if;

  select coalesce(s.timezone,'Asia/Ho_Chi_Minh') into v_tz
  from public.stores s where s.id=v_store;

  -- Không cho duyệt nghỉ nếu nhân viên đang thực sự làm một ca giao với ngày nghỉ.
  select s.id into v_conflict
  from public.work_schedules s
  join public.attendance a on a.schedule_id=s.id
  where s.employee_id=v_employee
    and s.store_id=v_store
    and s.status='assigned'
    and a.check_in is not null
    and a.check_out is null
    and (s.start_at at time zone v_tz)::date <= v_end
    and (s.end_at at time zone v_tz)::date >= v_start
  limit 1;
  if v_conflict is not null then raise exception 'NGHI_TRUNG_CA_DANG_LAM'; end if;

  update public.leave_requests
  set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason=null
  where id=p_leave_id;

  -- Ca tương lai của nhân viên bị nghỉ: hủy assignment nhưng không xóa lịch sử.
  update public.work_schedules s
  set status='cancelled',
      note=concat_ws(' · ',nullif(s.note,''),'Hủy do nghỉ phép đã được duyệt')
  where s.employee_id=v_employee
    and s.store_id=v_store
    and s.status='assigned'
    and (s.start_at at time zone v_tz)::date <= v_end
    and (s.end_at at time zone v_tz)::date >= v_start
    and not exists(select 1 from public.attendance a where a.schedule_id=s.id and a.check_in is not null);

  update public.shift_registrations r
  set status='cancelled',reviewed_by=auth.uid(),reviewed_at=now(),
      rejection_reason='Ca bị hủy do nghỉ phép đã được duyệt'
  from public.work_schedules s
  where r.schedule_id=s.id
    and r.employee_id=v_employee
    and r.status in ('pending','approved')
    and s.status='cancelled'
    and (s.start_at at time zone v_tz)::date <= v_end
    and (s.end_at at time zone v_tz)::date >= v_start;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'approve_leave','leave_request',p_leave_id,
         jsonb_build_object('employee_id',v_employee,'start_date',v_start,'end_date',v_end));
  return true;
end;
$$;


--
-- Name: schedule_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schedule_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    request_type text NOT NULL,
    schedule_id uuid NOT NULL,
    target_schedule_id uuid,
    note text,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    review_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT schedule_requests_request_type_check CHECK ((request_type = ANY (ARRAY['late'::text, 'swap'::text]))),
    CONSTRAINT schedule_requests_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text])))
);


--
-- Name: review_schedule_request(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_schedule_request(p_request_id uuid, p_action text, p_reason text DEFAULT NULL::text) RETURNS public.schedule_requests
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_req public.schedule_requests; v_target public.work_schedules; v_source public.work_schedules; v_conflict boolean; v_result public.schedule_requests;
begin
  select role into v_role from public.profiles where id=v_uid and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  select * into v_req from public.schedule_requests where id=p_request_id and store_id=(select p.store_id from public.profiles p where p.id=v_uid and p.employment_status='active' and p.role in ('owner','manager')) and status='pending' for update;
  if v_req.id is null then raise exception 'YEU_CAU_KHONG_TON_TAI'; end if;
  if p_action not in ('approve','reject') then raise exception 'THAO_TAC_KHONG_HOP_LE'; end if;
  if p_action='reject' then
    update public.schedule_requests set status='rejected',reviewed_by=v_uid,reviewed_at=now(),review_note=nullif(trim(coalesce(p_reason,'')),'') where id=v_req.id returning * into v_result;
  else
    if v_req.request_type='swap' then
      select * into v_source from public.work_schedules where id=v_req.schedule_id and employee_id=v_req.employee_id and status='assigned' for update;
      select * into v_target from public.work_schedules where id=v_req.target_schedule_id and store_id=v_req.store_id and status='open' and employee_id is null for update;
      if v_source.id is null or v_target.id is null then raise exception 'CA_DOI_KHONG_CON_TRONG'; end if;
      select public.employee_schedule_conflict(v_req.employee_id,v_target.start_at,v_target.end_at,v_source.id) into v_conflict;
      if v_conflict then raise exception 'TRUNG_CA'; end if;
      update public.work_schedules set employee_id=v_req.employee_id,status='assigned' where id=v_target.id;
      update public.work_schedules set employee_id=null,status='open' where id=v_source.id;
    end if;
    update public.schedule_requests set status='approved',reviewed_by=v_uid,reviewed_at=now(),review_note=nullif(trim(coalesce(p_reason,'')),'') where id=v_req.id returning * into v_result;
  end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(v_uid,'review_schedule_request','schedule_request',v_req.id,jsonb_build_object('action',p_action,'reason',p_reason));
  return v_result;
end;
$$;


--
-- Name: review_shift_registration(uuid, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.review_shift_registration(p_registration_id uuid, p_action text, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule_id uuid;
  v_employee uuid;
  v_status public.registration_status;
  v_schedule public.work_schedules%rowtype;
  v_overlap uuid;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select schedule_id,employee_id,status into v_schedule_id,v_employee,v_status
  from public.shift_registrations where id=p_registration_id for update;
  if not found then raise exception 'DANG_KY_NOT_FOUND'; end if;
  if v_status<>'pending' then raise exception 'DANG_KY_DA_XU_LY'; end if;

  perform pg_advisory_xact_lock(hashtextextended(v_employee::text,0));

  select * into v_schedule from public.work_schedules where id=v_schedule_id for update;
  if not found then raise exception 'CA_NOT_FOUND'; end if;
  if v_schedule.store_id is distinct from v_store then raise exception 'FORBIDDEN'; end if;

  if lower(p_action)='reject' then
    update public.shift_registrations
    set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),
        rejection_reason=nullif(trim(coalesce(p_reason,'Từ chối bởi quản lý')),'')
    where id=p_registration_id;
    return true;
  end if;

  if lower(p_action)<>'approve' then raise exception 'ACTION_KHONG_HOP_LE'; end if;
  if v_schedule.status<>'open' or v_schedule.employee_id is not null then raise exception 'CA_DA_DUOC_XEP'; end if;
  if v_schedule.start_at<=now() then raise exception 'CA_DA_BAT_DAU'; end if;

  select s.id into v_overlap
  from public.work_schedules s
  where s.employee_id=v_employee
    and s.status in ('assigned','open')
    and s.id<>v_schedule.id
    and s.start_at<v_schedule.end_at
    and s.end_at>v_schedule.start_at
  limit 1;
  if v_overlap is not null then raise exception 'NHAN_VIEN_TRUNG_CA'; end if;

  update public.shift_registrations
  set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason=null
  where id=p_registration_id;

  update public.work_schedules
  set employee_id=v_employee,status='assigned',assigned_at=now()
  where id=v_schedule.id;

  -- Các request khác cho cùng slot bị đóng nhưng giữ lịch sử.
  update public.shift_registrations
  set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),
      rejection_reason='Ca đã được duyệt cho nhân viên khác'
  where schedule_id=v_schedule.id and id<>p_registration_id and status='pending';

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'review_shift_registration','shift_registration',p_registration_id,
         jsonb_build_object('action','approve','schedule_id',v_schedule.id,'employee_id',v_employee));
  return true;
end;
$$;


--
-- Name: save_my_bank_details(text, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_my_bank_details(p_bank_name text, p_account_holder text, p_account_number text, p_branch_name text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_bank text:=trim(coalesce(p_bank_name,''));
  v_holder text:=trim(coalesce(p_account_holder,''));
  v_number text:=trim(coalesce(p_account_number,''));
  v_branch text:=trim(coalesce(p_branch_name,''));
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if not exists(select 1 from public.profiles where id=v_uid and employment_status<>'terminated') then
    raise exception 'PROFILE_NOT_FOUND';
  end if;
  if length(v_bank)>120 or length(v_holder)>160 or length(v_number)>64 or length(v_branch)>160 then
    raise exception 'BANK_DETAILS_TOO_LONG';
  end if;
  if num_nonnulls(nullif(v_bank,''),nullif(v_holder,''),nullif(v_number,'')) not in (0,3) then
    raise exception 'BANK_DETAILS_INCOMPLETE';
  end if;
  insert into public.employee_bank_details(
    employee_id,bank_name,account_holder,account_number,branch_name,updated_by,updated_at
  ) values(v_uid,v_bank,v_holder,v_number,v_branch,v_uid,now())
  on conflict(employee_id) do update set
    bank_name=excluded.bank_name,
    account_holder=excluded.account_holder,
    account_number=excluded.account_number,
    branch_name=excluded.branch_name,
    updated_by=excluded.updated_by,
    updated_at=now();
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(v_uid,'employee_update_own_bank_details','employee_bank_details',v_uid,
    jsonb_build_object('bank_details_updated',true));
  return true;
end;
$$;


--
-- Name: save_shift_registration_recurring_rule(integer, time without time zone, integer, time without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_shift_registration_recurring_rule(p_open_weekday integer, p_open_time time without time zone, p_close_weekday integer, p_close_time time without time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_store uuid; v_role text; v_rule public.shift_registration_recurring_rules%rowtype;
  d integer; v_week date; v_open timestamptz; v_close timestamptz;
  v_current jsonb; v_next jsonb;
begin
  select store_id,role::text into v_store,v_role
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  if p_open_weekday not between 1 and 7
     or p_close_weekday not between 1 and 7
     or p_open_time is null or p_close_time is null then
    raise exception 'THOI_GIAN_DANG_KY_KHONG_HOP_LE';
  end if;
  if p_open_weekday=p_close_weekday and p_close_time<=p_open_time then
    raise exception 'THOI_GIAN_DANG_KY_KHONG_HOP_LE';
  end if;

  insert into public.shift_registration_recurring_rules(
    store_id,open_weekday,open_time,close_weekday,close_time,is_active
  )
  values(v_store,p_open_weekday,p_open_time,p_close_weekday,p_close_time,true)
  on conflict(store_id) do update set
    open_weekday=excluded.open_weekday,
    open_time=excluded.open_time,
    close_weekday=excluded.close_weekday,
    close_time=excluded.close_time,
    is_active=true,
    updated_at=now()
  returning * into v_rule;

  -- Materialize enough future target weeks immediately. Existing finalized weeks
  -- are immutable; all other windows adopt the newly saved sample.
  for d in 0..16 loop
    v_week:=date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date+(d*7);
    select open_at,close_at into v_open,v_close
    from public.registration_window_times(
      v_week,v_rule.open_weekday,v_rule.open_time,
      v_rule.close_weekday,v_rule.close_time
    );
    insert into public.shift_registration_windows(store_id,week_start,open_at,close_at,status)
    values(v_store,v_week,v_open,v_close,'open')
    on conflict(store_id,week_start) do update
    set open_at=case when public.shift_registration_windows.status='finalized' then public.shift_registration_windows.open_at else excluded.open_at end,
        close_at=case when public.shift_registration_windows.status='finalized' then public.shift_registration_windows.close_at else excluded.close_at end,
        updated_at=now();
  end loop;

  v_current:=public.ensure_shift_registration_window(date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date);
  v_next:=public.ensure_shift_registration_window(date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date+7);

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(
    auth.uid(),'save_shift_registration_recurring_rule','shift_registration_recurring_rule',v_rule.id,
    jsonb_build_object(
      'open_weekday',v_rule.open_weekday,'open_time',v_rule.open_time,
      'close_weekday',v_rule.close_weekday,'close_time',v_rule.close_time
    )
  );

  return jsonb_build_object(
    'id',v_rule.id,
    'open_weekday',v_rule.open_weekday,'open_time',v_rule.open_time,
    'close_weekday',v_rule.close_weekday,'close_time',v_rule.close_time,
    'is_active',v_rule.is_active,
    'current_window',v_current,
    'next_window',v_next
  );
end; $$;


--
-- Name: save_shift_registration_settings(integer, time without time zone, integer, time without time zone, boolean, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_shift_registration_settings(p_open_weekday integer, p_open_time time without time zone, p_close_weekday integer, p_close_time time without time zone, p_auto_open boolean DEFAULT true, p_auto_approve boolean DEFAULT true) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_role text;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_week date;
  d integer;
  x record;
begin
  select store_id,role::text into v_store,v_role
  from public.profiles
  where id=v_uid and employment_status='active';

  if v_role <> 'owner' then raise exception 'FORBIDDEN'; end if;
  if p_open_weekday not between 1 and 7
     or p_close_weekday not between 1 and 7
     or p_open_time is null
     or p_close_time is null then
    raise exception 'THOI_GIAN_DANG_KY_KHONG_HOP_LE';
  end if;

  if p_open_weekday=p_close_weekday and p_close_time<=p_open_time then
    raise exception 'THOI_GIAN_DANG_KY_KHONG_HOP_LE';
  end if;

  insert into public.shift_registration_recurring_rules(
    store_id,open_weekday,open_time,close_weekday,close_time,
    is_active,auto_open,auto_approve,updated_at
  )
  values(
    v_store,p_open_weekday,p_open_time,p_close_weekday,p_close_time,
    true,coalesce(p_auto_open,true),coalesce(p_auto_approve,true),now()
  )
  on conflict(store_id) do update set
    open_weekday=excluded.open_weekday,
    open_time=excluded.open_time,
    close_weekday=excluded.close_weekday,
    close_time=excluded.close_time,
    is_active=true,
    auto_open=excluded.auto_open,
    auto_approve=excluded.auto_approve,
    updated_at=now()
  returning * into v_rule;

  -- Materialize current + next 8 weeks. This creates the durable time windows;
  -- the actual work slots are created only when auto-open reaches the opening time.
  for d in 0..8 loop
    v_week := date_trunc('week',(now() at time zone 'Asia/Ho_Chi_Minh')::date)::date + d*7;
    select * into x from public.registration_window_times(
      v_week,v_rule.open_weekday,v_rule.open_time,v_rule.close_weekday,v_rule.close_time
    );

    insert into public.shift_registration_windows(
      store_id,week_start,open_at,close_at,status
    )
    values(v_store,v_week,x.open_at,x.close_at,'open')
    on conflict(store_id,week_start) do update set
      open_at=case when public.shift_registration_windows.status='finalized'
                   then public.shift_registration_windows.open_at else excluded.open_at end,
      close_at=case when public.shift_registration_windows.status='finalized'
                    then public.shift_registration_windows.close_at else excluded.close_at end;
  end loop;

  return jsonb_build_object(
    'id',v_rule.id,
    'open_weekday',v_rule.open_weekday,
    'open_time',v_rule.open_time,
    'close_weekday',v_rule.close_weekday,
    'close_time',v_rule.close_time,
    'auto_open',v_rule.auto_open,
    'auto_approve',v_rule.auto_approve
  );
end;
$$;


--
-- Name: save_shift_registration_window(date, timestamp with time zone, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_shift_registration_window(p_week_start date, p_open_at timestamp with time zone, p_close_at timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_store uuid; v_role text; v_week date; v_row public.shift_registration_windows%rowtype;
begin
  select store_id,role::text into v_store,v_role from public.profiles where id=auth.uid() and employment_status='active';
  if v_role<>'owner' then raise exception 'FORBIDDEN'; end if;
  if p_open_at is null or p_close_at is null or p_close_at<=p_open_at then raise exception 'THOI_GIAN_DANG_KY_KHONG_HOP_LE'; end if;
  v_week:=date_trunc('week',p_week_start)::date;
  select * into v_row from public.shift_registration_windows where store_id=v_store and week_start=v_week for update;
  if found and v_row.status='finalized' then raise exception 'TUAN_DA_CHOT'; end if;
  insert into public.shift_registration_windows(store_id,week_start,open_at,close_at,status,closed_at,closed_by)
  values(v_store,v_week,p_open_at,p_close_at,'open',null,null)
  on conflict(store_id,week_start) do update set open_at=excluded.open_at,close_at=excluded.close_at,status='open',closed_at=null,closed_by=null,updated_at=now()
  returning * into v_row;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(auth.uid(),'save_shift_registration_window','shift_registration_window',v_row.id,jsonb_build_object('week_start',v_week,'open_at',p_open_at,'close_at',p_close_at));
  return jsonb_build_object('id',v_row.id,'week_start',v_row.week_start,'open_at',v_row.open_at,'close_at',v_row.close_at,'status',v_row.status);
end; $$;


--
-- Name: save_shift_template(uuid, text, time without time zone, time without time zone, integer, integer, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_shift_template(p_template_id uuid, p_name text, p_start_time time without time zone, p_end_time time without time zone, p_break_minutes integer DEFAULT 0, p_capacity integer DEFAULT 1, p_is_active boolean DEFAULT true) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_store uuid;
  v_id uuid;
  v_duration integer;
begin
  select role::text, store_id into v_role, v_store
  from public.profiles
  where id = v_uid and employment_status = 'active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;
  if nullif(trim(p_name),'') is null or p_start_time is null or p_end_time is null then raise exception 'MẪU_CA_THIẾU_DỮ_LIỆU'; end if;
  if p_start_time = p_end_time then raise exception 'CA_THOI_GIAN_KHONG_HOP_LE'; end if;
  if p_capacity < 1 or p_capacity > 10 then raise exception 'Số vị trí ca phải từ 1 đến 10'; end if;
  v_duration := extract(epoch from ((p_end_time - p_start_time) + case when p_end_time <= p_start_time then interval '24 hours' else interval '0 hours' end))/60;
  if p_break_minutes < 0 or p_break_minutes >= v_duration then raise exception 'Thời gian nghỉ không hợp lệ'; end if;

  if p_template_id is null then
    insert into public.shift_templates(store_id,name,start_time,end_time,break_minutes,capacity,is_active)
    values(v_store,trim(p_name),p_start_time,p_end_time,p_break_minutes,p_capacity,coalesce(p_is_active,true))
    returning id into v_id;
  else
    update public.shift_templates
    set name=trim(p_name), start_time=p_start_time, end_time=p_end_time,
        break_minutes=p_break_minutes, capacity=p_capacity, is_active=coalesce(p_is_active,true)
    where id=p_template_id and store_id=v_store
    returning id into v_id;
    if v_id is null then raise exception 'MẪU_CA_NOT_FOUND'; end if;
  end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(v_uid,case when p_template_id is null then 'create_shift_template' else 'update_shift_template' end,'shift_template',v_id,
    jsonb_build_object('name',trim(p_name),'start_time',p_start_time,'end_time',p_end_time,'break_minutes',p_break_minutes,'capacity',p_capacity,'is_active',coalesce(p_is_active,true)));
  return v_id;
end;
$$;


--
-- Name: save_shift_template(uuid, text, time without time zone, time without time zone, integer, integer, boolean, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_shift_template(p_template_id uuid DEFAULT NULL::uuid, p_name text DEFAULT ''::text, p_start_time time without time zone DEFAULT NULL::time without time zone, p_end_time time without time zone DEFAULT NULL::time without time zone, p_break_minutes integer DEFAULT 0, p_capacity integer DEFAULT 1, p_is_active boolean DEFAULT true, p_effective_date date DEFAULT CURRENT_DATE) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_id uuid;
  v_t public.shift_templates%rowtype;
  v_tz text;
  v_today date;
  v_changed integer:=0;
begin
  select role::text,store_id
    into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';

  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;
  if coalesce(trim(p_name),'')='' or p_start_time is null or p_end_time is null then raise exception 'THIEU_THONG_TIN_CA'; end if;
  if p_start_time=p_end_time then raise exception 'GIO_CA_KHONG_HOP_LE'; end if;
  if coalesce(p_break_minutes,0)<0 or coalesce(p_break_minutes,0)>180 then raise exception 'THOI_GIAN_NGHI_KHONG_HOP_LE'; end if;
  if coalesce(p_capacity,1)<1 or coalesce(p_capacity,1)>50 then raise exception 'SO_VI_TRI_KHONG_HOP_LE'; end if;

  select coalesce(timezone,'Asia/Ho_Chi_Minh')
    into v_tz
  from public.stores
  where id=v_store;

  v_today:=(now() at time zone v_tz)::date;
  if p_effective_date is null or p_effective_date<v_today then raise exception 'NGAY_AP_DUNG_KHONG_HOP_LE'; end if;

  -- Creating a brand-new template remains a current-day operation.
  -- A future version should be created by editing an existing template.
  if p_template_id is null then
    if p_effective_date<>v_today then raise exception 'CA_MOI_CHI_AP_DUNG_TU_HOM_NAY'; end if;

    insert into public.shift_templates(
      store_id,name,start_time,end_time,break_minutes,capacity,is_active,updated_at
    )
    values(
      v_store,trim(p_name),p_start_time,p_end_time,
      coalesce(p_break_minutes,0),coalesce(p_capacity,1),
      coalesce(p_is_active,true),now()
    )
    returning id into v_id;

    insert into public.shift_template_versions(
      shift_template_id,effective_from,name,start_time,end_time,
      break_minutes,capacity,is_active,created_by,updated_at
    )
    values(
      v_id,p_effective_date,trim(p_name),p_start_time,p_end_time,
      coalesce(p_break_minutes,0),coalesce(p_capacity,1),
      coalesce(p_is_active,true),auth.uid(),now()
    );

    return v_id;
  end if;

  select *
    into v_t
  from public.shift_templates
  where id=p_template_id and store_id=v_store
  for update;

  if not found then raise exception 'MAU_CA_NOT_FOUND'; end if;

  -- Upsert the version that becomes effective on the selected date.
  insert into public.shift_template_versions(
    shift_template_id,effective_from,name,start_time,end_time,
    break_minutes,capacity,is_active,created_by,updated_at
  )
  values(
    p_template_id,p_effective_date,trim(p_name),p_start_time,p_end_time,
    coalesce(p_break_minutes,0),coalesce(p_capacity,1),
    coalesce(p_is_active,true),auth.uid(),now()
  )
  on conflict(shift_template_id,effective_from) do update set
    name=excluded.name,
    start_time=excluded.start_time,
    end_time=excluded.end_time,
    break_minutes=excluded.break_minutes,
    capacity=excluded.capacity,
    is_active=excluded.is_active,
    created_by=excluded.created_by,
    updated_at=now();

  -- The base template reflects the definition effective TODAY.
  -- Future edits remain in shift_template_versions until their effective date.
  if p_effective_date=v_today then
    update public.shift_templates
    set name=trim(p_name),
        start_time=p_start_time,
        end_time=p_end_time,
        break_minutes=coalesce(p_break_minutes,0),
        capacity=coalesce(p_capacity,1),
        is_active=coalesce(p_is_active,true),
        updated_at=now()
    where id=p_template_id;
  end if;

  -- Propagate the selected version to future schedules only.
  -- IMPORTANT: no LATERAL reference to UPDATE alias is used here.
  -- Schedules that already have check-in are protected from retroactive changes.
  update public.work_schedules ws
  set start_time=(
        select vv.start_time
        from public.shift_template_versions vv
        where vv.shift_template_id=ws.shift_template_id
          and vv.effective_from<=ws.work_date
        order by vv.effective_from desc
        limit 1
      ),
      end_time=(
        select vv.end_time
        from public.shift_template_versions vv
        where vv.shift_template_id=ws.shift_template_id
          and vv.effective_from<=ws.work_date
        order by vv.effective_from desc
        limit 1
      ),
      updated_at=now()
  where ws.shift_template_id=p_template_id
    and ws.store_id=v_store
    and ws.work_date>=p_effective_date
    and not exists(
      select 1
      from public.attendance a
      where a.schedule_id=ws.id
        and a.check_in is not null
    )
    and (
      ws.work_date>v_today
      or (
        ws.work_date=v_today
        and now() < ((ws.work_date+ws.start_time) at time zone v_tz)
      )
    );

  get diagnostics v_changed=row_count;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data)
  values(
    auth.uid(),
    'save_shift_template',
    'shift_template',
    p_template_id,
    jsonb_build_object(
      'effective_date',p_effective_date,
      'changed_schedules',v_changed
    )
  );

  return p_template_id;
end;
$$;


--
-- Name: save_weekly_shift_plan(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_weekly_shift_plan(p_items jsonb) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_store uuid;
  v_item jsonb;
  v_id uuid;
  v_weekday integer;
  v_template uuid;
  v_capacity integer;
  v_note text;
  v_sort integer;
  v_count integer := 0;
begin
  select role::text, store_id into v_role, v_store
  from public.profiles
  where id = v_uid and employment_status = 'active';

  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  if v_store is null then raise exception 'STORE_NOT_FOUND'; end if;
  if p_items is null or jsonb_typeof(p_items) <> 'array' then raise exception 'MẪU_TUẦN_KHÔNG_HỢP_LỆ'; end if;

  -- First validate the complete payload. Nothing is changed if any row is invalid.
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_weekday := (v_item->>'weekday')::integer;
    v_template := (v_item->>'shift_template_id')::uuid;
    v_capacity := coalesce((v_item->>'capacity')::integer, 1);
    if v_weekday < 1 or v_weekday > 7 then raise exception 'THỨ_TRONG_TUẦN_KHÔNG_HỢP_LỆ'; end if;
    if v_capacity < 1 or v_capacity > 10 then raise exception 'Số vị trí ca phải từ 1 đến 10'; end if;
    if not exists (
      select 1 from public.shift_templates t
      where t.id = v_template and t.store_id = v_store and t.is_active = true
    ) then raise exception 'Mẫu ca không tồn tại, đã tắt hoặc khác cửa hàng'; end if;
  end loop;

  -- Soft-delete rows omitted from the new weekly plan so existing generated schedules
  -- can keep their source reference without breaking history.
  update public.weekly_shift_plan_items
  set is_active = false, updated_at = now()
  where store_id = v_store and is_active = true;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_id := nullif(v_item->>'id','')::uuid;
    v_weekday := (v_item->>'weekday')::integer;
    v_template := (v_item->>'shift_template_id')::uuid;
    v_capacity := coalesce((v_item->>'capacity')::integer, 1);
    v_note := nullif(trim(v_item->>'note'),'');
    v_sort := coalesce((v_item->>'sort_order')::integer, v_count);

    if v_id is not null and exists (
      select 1 from public.weekly_shift_plan_items where id = v_id and store_id = v_store
    ) then
      update public.weekly_shift_plan_items
      set weekday = v_weekday,
          shift_template_id = v_template,
          capacity = v_capacity,
          note = v_note,
          sort_order = v_sort,
          is_active = true,
          updated_at = now()
      where id = v_id and store_id = v_store;
    else
      insert into public.weekly_shift_plan_items(
        store_id, weekday, shift_template_id, capacity, note, sort_order, is_active
      ) values (
        v_store, v_weekday, v_template, v_capacity, v_note, v_sort, true
      );
    end if;
    v_count := v_count + 1;
  end loop;

  insert into public.audit_logs(actor_id, action, entity_type, new_data)
  values (
    v_uid,
    'save_weekly_shift_plan',
    'weekly_shift_plan',
    jsonb_build_object('item_count',v_count)
  );

  return jsonb_build_object('item_count',v_count);
end;
$$;


--
-- Name: set_audit_store_id(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_audit_store_id() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.store_id is null and new.actor_id is not null then
    select p.store_id into new.store_id
    from public.profiles p
    where p.id=new.actor_id;
  end if;
  return new;
end;
$$;


--
-- Name: set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
begin
  new.updated_at = now();
  return new;
end;
$$;


--
-- Name: submit_schedule_request(text, uuid, uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.submit_schedule_request(p_request_type text, p_schedule_id uuid, p_target_schedule_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text) RETURNS public.schedule_requests
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid(); v_profile public.profiles; v_source public.work_schedules; v_target public.work_schedules; v_conflict boolean;
  v_result public.schedule_requests;
begin
  select * into v_profile from public.profiles where id=v_uid and employment_status='active';
  if v_profile.id is null or v_profile.role<>'employee' then raise exception 'FORBIDDEN'; end if;
  if p_request_type not in ('late','swap') then raise exception 'LOAI_YEU_CAU_KHONG_HOP_LE'; end if;
  select * into v_source from public.work_schedules where id=p_schedule_id and store_id=v_profile.store_id and employee_id=v_uid and status='assigned';
  if v_source.id is null then raise exception 'CA_KHONG_HOP_LE'; end if;
  if p_request_type='late' then
    if p_target_schedule_id is not null then raise exception 'DU_LIEU_KHONG_HOP_LE'; end if;
  else
    select * into v_target from public.work_schedules where id=p_target_schedule_id and store_id=v_profile.store_id and status='open' and employee_id is null;
    if v_target.id is null then raise exception 'CA_DOI_KHONG_CON_TRONG'; end if;
    if v_target.start_at <= now() then raise exception 'CA_DOI_KHONG_CON_TRONG'; end if;
    select public.employee_schedule_conflict(v_uid,v_target.start_at,v_target.end_at,v_source.id) into v_conflict;
    if v_conflict then raise exception 'TRUNG_CA'; end if;
  end if;
  if exists(select 1 from public.schedule_requests r where r.employee_id=v_uid and r.schedule_id=p_schedule_id and r.request_type=p_request_type and r.status='pending') then raise exception 'DA_CO_YEU_CAU'; end if;
  insert into public.schedule_requests(store_id,employee_id,request_type,schedule_id,target_schedule_id,note)
  values(v_profile.store_id,v_uid,p_request_type,p_schedule_id,p_target_schedule_id,nullif(trim(coalesce(p_note,'')),''))
  returning * into v_result;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,new_data) values(v_uid,'submit_schedule_request','schedule_request',v_result.id,jsonb_build_object('request_type',p_request_type,'schedule_id',p_schedule_id,'target_schedule_id',p_target_schedule_id));
  return v_result;
end;
$$;


--
-- Name: switch_active_store(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.switch_active_store(p_store_id uuid) RETURNS jsonb
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


--
-- Name: sync_profile_store_membership(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_profile_store_membership() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
begin
  if new.store_id is not null then
    insert into public.store_memberships(user_id,store_id,role,is_active)
    values(new.id,new.store_id,new.role,true)
    on conflict(user_id,store_id) do update
      set role=excluded.role,is_active=true,left_at=null,updated_at=now();
  end if;
  return new;
end;
$$;


--
-- Name: sync_shift_registration_automation(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_shift_registration_automation() RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid:=auth.uid();
  v_my_store uuid;
  r record;
  d integer;
  v_week date;
  v_open timestamptz;
  v_close timestamptz;
  v_row public.shift_registration_windows%rowtype;
  v_created boolean:=false;
  v_opened integer:=0;
  v_materialized integer:=0;
  v_generated_slots integer:=0;
  v_now timestamptz:=now();
  v_rule_auto boolean;
  v_gen jsonb;
begin
  if v_uid is not null then
    select store_id into v_my_store
    from public.profiles
    where id=v_uid and employment_status='active';
    if v_my_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;
  end if;

  for r in
    select rr.*
    from public.shift_registration_recurring_rules rr
    where rr.is_active=true
      and (v_uid is null or rr.store_id=v_my_store)
  loop
    v_rule_auto:=coalesce(r.auto_open,true);

    -- Check current week plus adjacent weeks. The adjacent week is needed
    -- because a window can open in the previous calendar week for a target
    -- work week (e.g. T7 -> T4).
    for d in -1..8 loop
      v_week:=date_trunc('week',(v_now at time zone 'Asia/Ho_Chi_Minh')::date)::date+(d*7);

      select open_at,close_at into v_open,v_close
      from public.registration_window_times(
        v_week,r.open_weekday,r.open_time,r.close_weekday,r.close_time
      );

      select * into v_row
      from public.shift_registration_windows
      where store_id=r.store_id and week_start=v_week
      for update;

      if not found then
        insert into public.shift_registration_windows(
          store_id,week_start,open_at,close_at,status,closed_at,closed_by,finalized_at,finalized_by
        ) values(
          r.store_id,v_week,v_open,v_close,
          case when v_rule_auto and v_now>=v_open and v_now<v_close then 'open' else 'closed' end,
          null,null,null,null
        ) returning * into v_row;
        v_materialized:=v_materialized+1;
        v_created:=true;
      end if;

      -- Finalized windows are immutable history.
      if v_row.status='finalized' then
        continue;
      end if;

      -- IMPORTANT: never close an OPEN window early from a stale close_at.
      -- If its stored close is earlier than the canonical close and the
      -- canonical close is still in the future, extend it first.
      if v_row.status='open' then
        if v_row.close_at<v_close and v_close>v_now then
          update public.shift_registration_windows
          set close_at=v_close,updated_at=now()
          where id=v_row.id and close_at is distinct from v_close;
          v_row.close_at:=v_close;
        end if;

        -- A currently-open window is authoritative until its reconciled close.
        if v_now<v_row.close_at then
          v_gen:=public.auto_generate_weekly_schedule_from_plan(r.store_id,v_week);
          v_generated_slots:=v_generated_slots+coalesce((v_gen->>'created_slots')::integer,0);
          continue;
        end if;
      end if;

      -- Automatic opening happens ONLY inside the configured canonical window.
      if v_rule_auto and v_row.closed_by is null and v_now>=v_open and v_now<v_close then
        update public.shift_registration_windows
        set open_at=v_open,
            close_at=case when close_at>v_close then close_at else v_close end,
            status='open',
            closed_at=null,
            closed_by=null,
            updated_at=now()
        where id=v_row.id
          and (open_at is distinct from v_open
               or close_at is distinct from (case when close_at>v_close then close_at else v_close end)
               or status is distinct from 'open'
               or closed_at is not null
               or closed_by is not null);

        v_opened:=v_opened+1;
        v_gen:=public.auto_generate_weekly_schedule_from_plan(r.store_id,v_week);
        v_generated_slots:=v_generated_slots+coalesce((v_gen->>'created_slots')::integer,0);
      elsif v_now<v_open and v_row.closed_by is null then
        -- Future window: keep it CLOSED until the actual opening time.
        update public.shift_registration_windows
        set open_at=v_open,
            close_at=v_close,
            status='closed',
            closed_at=null,
            closed_by=null,
            updated_at=now()
        where id=v_row.id
          and (open_at is distinct from v_open
               or close_at is distinct from v_close
               or status is distinct from 'closed'
               or closed_at is not null
               or closed_by is not null);
      end if;
    end loop;
  end loop;

  return jsonb_build_object(
    'materialized',v_materialized,
    'opened',v_opened,
    'generated_slots',v_generated_slots
  );
end;
$$;


--
-- Name: sync_work_schedule_datetimes(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.sync_work_schedule_datetimes() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_tz text;
begin
  select coalesce(timezone,'Asia/Ho_Chi_Minh') into v_tz
  from public.stores where id=new.store_id;

  v_tz:=coalesce(v_tz,'Asia/Ho_Chi_Minh');
  new.start_at:=((new.work_date+new.start_time) at time zone v_tz);
  new.end_at:=(((new.work_date+new.end_time) at time zone v_tz)
    + case when new.end_time<=new.start_time then interval '1 day' else interval '0 day' end);

  if new.end_at<=new.start_at then
    raise exception 'CA_THOI_GIAN_KHONG_HOP_LE';
  end if;
  return new;
end;
$$;


--
-- Name: transfer_employee_branch(uuid, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.transfer_employee_branch(p_employee_id uuid, p_target_store_id uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_actor_role text;
  v_actor_status text;
  v_actor_store_id uuid;
  v_employee_role text;
  v_employee_status text;
  v_old_store_id uuid;
  v_target_name text;
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  IF p_employee_id IS NULL OR p_target_store_id IS NULL THEN
    RAISE EXCEPTION 'EMPLOYEE_AND_TARGET_REQUIRED';
  END IF;

  SELECT p.role::text, p.employment_status::text, p.store_id
    INTO v_actor_role, v_actor_status, v_actor_store_id
  FROM public.profiles p
  WHERE p.id = v_actor_id;

  IF NOT FOUND OR v_actor_status <> 'active' THEN
    RAISE EXCEPTION 'CALLER_PROFILE_NOT_ACTIVE';
  END IF;
  IF v_actor_role NOT IN ('owner', 'manager') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;
  IF v_actor_role = 'manager'
     AND NOT public.current_user_has_manager_permission('employee_create') THEN
    RAISE EXCEPTION 'FORBIDDEN';
  END IF;

  SELECT p.role::text, p.employment_status::text, p.store_id
    INTO v_employee_role, v_employee_status, v_old_store_id
  FROM public.profiles p
  WHERE p.id = p_employee_id
  FOR UPDATE;

  IF NOT FOUND THEN RAISE EXCEPTION 'EMPLOYEE_NOT_FOUND'; END IF;
  IF v_employee_role <> 'employee' THEN
    RAISE EXCEPTION 'ONLY_EMPLOYEE_CAN_BE_TRANSFERRED';
  END IF;
  IF v_old_store_id = p_target_store_id THEN
    RETURN jsonb_build_object('ok', true, 'unchanged', true, 'store_id', p_target_store_id);
  END IF;

  SELECT s.name INTO v_target_name
  FROM public.stores s
  WHERE s.id = p_target_store_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'TARGET_STORE_NOT_FOUND'; END IF;

  -- Owner must own both the employee's current branch and the destination branch.
  IF v_actor_role = 'owner' THEN
    IF v_old_store_id IS NULL OR NOT public.is_store_owner(v_old_store_id)
       OR NOT public.is_store_owner(p_target_store_id) THEN
      RAISE EXCEPTION 'FORBIDDEN_BRANCH_SCOPE';
    END IF;
  ELSE
    -- A Manager may act only within branches where they are an active member;
    -- employee_create permission is checked above for the manager's current store.
    IF v_old_store_id IS DISTINCT FROM v_actor_store_id
       OR NOT public.is_store_member(v_old_store_id)
       OR NOT public.is_store_member(p_target_store_id) THEN
      RAISE EXCEPTION 'FORBIDDEN_BRANCH_SCOPE';
    END IF;
  END IF;

  -- Preserve membership history but mark previous workplace memberships inactive.
  UPDATE public.store_memberships sm
  SET is_active = false,
      left_at = COALESCE(sm.left_at, now()),
      updated_at = now()
  WHERE sm.user_id = p_employee_id
    AND sm.is_active = true
    AND sm.store_id <> p_target_store_id;

  -- Re-activate an existing destination membership or create one; avoid duplicate rows.
  UPDATE public.store_memberships sm
  SET is_active = true,
      role = 'employee'::public.user_role,
      joined_at = CASE WHEN sm.is_active THEN sm.joined_at ELSE now() END,
      left_at = NULL,
      updated_at = now()
  WHERE sm.user_id = p_employee_id
    AND sm.store_id = p_target_store_id;

  IF NOT FOUND THEN
    INSERT INTO public.store_memberships(user_id, store_id, role, is_active, joined_at, left_at)
    VALUES (p_employee_id, p_target_store_id, 'employee'::public.user_role, true, now(), NULL);
  END IF;

  -- Current workplace pointer for existing app flows. Historical attendance and schedules
  -- are deliberately untouched, so past records continue to reference their original shifts.
  UPDATE public.profiles
  SET store_id = p_target_store_id,
      updated_at = now()
  WHERE id = p_employee_id;

  RETURN jsonb_build_object(
    'ok', true,
    'employee_id', p_employee_id,
    'old_store_id', v_old_store_id,
    'store_id', p_target_store_id,
    'store_name', v_target_name,
    'history_preserved', true
  );
END;
$$;


--
-- Name: unassign_employee_from_schedule(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unassign_employee_from_schedule(p_schedule_id uuid, p_reason text DEFAULT NULL::text) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare v_role text; v_store uuid; v_schedule public.work_schedules%rowtype; v_now timestamptz:=now();
begin
  select role::text,store_id into v_role,v_store from public.profiles where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;
  select * into v_schedule from public.work_schedules where id=p_schedule_id for update;
  if not found or v_schedule.store_id is distinct from v_store then raise exception 'FORBIDDEN'; end if;
  if v_schedule.status<>'assigned' or v_schedule.employee_id is null then raise exception 'CA_KHONG_CO_NGUOI'; end if;
  -- Owner/Manager có thể điều chỉnh lịch bất cứ lúc nào; vẫn bảo vệ lịch sử đã có chấm công.
  if exists(select 1 from public.attendance where schedule_id=p_schedule_id and (check_in is not null or check_out is not null)) then raise exception 'DA_CO_CHAM_CONG'; end if;
  update public.work_schedules set employee_id=null,status='open',assigned_at=null,
    note=concat_ws(' · ',note,nullif(trim(p_reason),''),'Bỏ người khỏi ca'),updated_at=v_now where id=p_schedule_id;
  update public.shift_registrations set status='cancelled',reviewed_by=auth.uid(),reviewed_at=v_now,
    rejection_reason=coalesce(nullif(trim(p_reason),''),'Đã bỏ khỏi ca')
  where schedule_id=p_schedule_id and employee_id=v_schedule.employee_id and status in ('pending','approved');
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(auth.uid(),'unassign_employee_from_schedule','work_schedule',p_schedule_id,
    jsonb_build_object('employee_id',v_schedule.employee_id,'status','assigned'),
    jsonb_build_object('employee_id',null,'status','open','reason',p_reason));
  return true;
end;
$$;


--
-- Name: update_supplemental_schedule(uuid, text, time without time zone, time without time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_supplemental_schedule(p_schedule_id uuid, p_name text, p_start_time time without time zone, p_end_time time without time zone, p_note text DEFAULT NULL::text) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_role text;
  v_store uuid;
  v_schedule public.work_schedules%rowtype;
  v_group uuid;
  v_tz text;
  v_start_at timestamptz;
  v_end_at timestamptz;
  v_now timestamptz:=now();
  v_employee uuid;
  v_conflict uuid;
  v_count integer:=0;
begin
  select role::text,store_id into v_role,v_store
  from public.profiles
  where id=auth.uid() and employment_status='active';
  if v_role not in ('owner','manager') then raise exception 'FORBIDDEN'; end if;

  select * into v_schedule
  from public.work_schedules
  where id=p_schedule_id and store_id=v_store
  for update;
  if not found then raise exception 'CA_NOT_FOUND'; end if;
  if v_schedule.status='cancelled' then raise exception 'CA_DA_HUY'; end if;
  if coalesce(v_schedule.schedule_kind,'template')<>'supplemental' then
    raise exception 'CA_KHONG_PHAI_BO_SUNG';
  end if;

  v_group:=coalesce(v_schedule.shift_group_id,v_schedule.id);

  -- Serialize the whole supplemental shift before reading/updating its slots.
  perform pg_advisory_xact_lock(
    hashtextextended(v_store::text || ':' || v_group::text || ':edit_supplemental',0)
  );

  if exists (
    select 1 from public.work_schedules ws
    where ws.store_id=v_store
      and coalesce(ws.shift_group_id,ws.id)=v_group
      and ws.status<>'cancelled'
      and ws.start_at is not null
      and v_now>=ws.start_at
  ) then
    raise exception 'CA_DA_BAT_DAU';
  end if;

  if nullif(trim(p_name),'') is null then raise exception 'TEN_CA_KHONG_HOP_LE'; end if;
  if p_start_time is null or p_end_time is null or p_start_time=p_end_time then
    raise exception 'CA_THOI_GIAN_KHONG_HOP_LE';
  end if;

  select coalesce(s.timezone,'Asia/Ho_Chi_Minh') into v_tz
  from public.stores s where s.id=v_store;
  v_tz:=coalesce(v_tz,'Asia/Ho_Chi_Minh');

  v_start_at:=((v_schedule.work_date+p_start_time) at time zone v_tz);
  v_end_at:=((v_schedule.work_date+p_end_time) at time zone v_tz)
    + case when p_end_time<=p_start_time then interval '1 day' else interval '0 day' end;
  if v_end_at<=v_start_at then raise exception 'CA_THOI_GIAN_KHONG_HOP_LE'; end if;
  if v_schedule.work_date < (now() at time zone v_tz)::date then raise exception 'NGAY_DA_QUA'; end if;

  -- Existing attendance/check-in makes changing the shift unsafe.
  if exists (
    select 1
    from public.attendance a
    join public.work_schedules ws on ws.id=a.schedule_id
    where ws.store_id=v_store
      and coalesce(ws.shift_group_id,ws.id)=v_group
      and (a.check_in is not null or a.check_out is not null)
  ) then
    raise exception 'DA_CO_CHAM_CONG';
  end if;

  -- Re-check every assigned employee against schedules outside this group.
  for v_employee in
    select distinct ws.employee_id
    from public.work_schedules ws
    where ws.store_id=v_store
      and coalesce(ws.shift_group_id,ws.id)=v_group
      and ws.status='assigned'
      and ws.employee_id is not null
  loop
    select s.id into v_conflict
    from public.work_schedules s
    where s.store_id=v_store
      and s.employee_id=v_employee
      and s.status<>'cancelled'
      and coalesce(s.shift_group_id,s.id)<>v_group
      and s.start_at<v_end_at
      and s.end_at>v_start_at
    limit 1;
    if v_conflict is not null then raise exception 'NHAN_VIEN_TRUNG_CA'; end if;
  end loop;

  update public.work_schedules
  set start_time=p_start_time,
      end_time=p_end_time,
      start_at=v_start_at,
      end_at=v_end_at,
      custom_name=trim(p_name),
      note=nullif(trim(p_note),''),
      updated_at=v_now
  where store_id=v_store
    and coalesce(shift_group_id,id)=v_group
    and status<>'cancelled';

  get diagnostics v_count=row_count;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,old_data,new_data)
  values(
    auth.uid(),'update_supplemental_schedule','work_schedule',v_group,
    jsonb_build_object('work_date',v_schedule.work_date,'old_name',v_schedule.custom_name,
      'old_start_time',v_schedule.start_time,'old_end_time',v_schedule.end_time),
    jsonb_build_object('work_date',v_schedule.work_date,'name',trim(p_name),
      'start_time',p_start_time,'end_time',p_end_time,'updated_slots',v_count)
  );

  return jsonb_build_object('shift_group_id',v_group,'updated_slots',v_count,'name',trim(p_name));
end;
$$;


--
-- Name: withdraw_shift_registration(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.withdraw_shift_registration(p_registration_id uuid) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public'
    AS $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_reg public.shift_registrations%rowtype;
  v_schedule public.work_schedules%rowtype;
  v_rule public.shift_registration_recurring_rules%rowtype;
  v_window public.shift_registration_windows%rowtype;
  v_open timestamptz;
  v_close timestamptz;
  v_week date;
  v_now timestamptz := now();
  v_window_is_authoritative boolean := false;
begin
  -- 1. Only an active employee can cancel their own pending registration.
  select p.store_id into v_store
  from public.profiles p
  where p.id=v_uid
    and p.role='employee'
    and p.employment_status='active';
  if v_store is null then raise exception 'PROFILE_NOT_ACTIVE'; end if;

  select r.* into v_reg
  from public.shift_registrations r
  join public.work_schedules s on s.id=r.schedule_id
  where r.id=p_registration_id
    and r.employee_id=v_uid
    and s.store_id=v_store
  for update;
  if not found then raise exception 'DANG_KY_KHONG_TON_TAI'; end if;
  if v_reg.status<>'pending' then raise exception 'DANG_KY_KHONG_THE_HUY'; end if;

  select * into v_schedule
  from public.work_schedules
  where id=v_reg.schedule_id
    and store_id=v_store;
  if not found then raise exception 'CA_KHONG_TON_TAI'; end if;

  v_week := date_trunc('week',v_schedule.work_date)::date;

  -- 2. Load the canonical recurring rule only as the auto-open fallback.
  select * into v_rule
  from public.shift_registration_recurring_rules
  where store_id=v_store
    and is_active=true
  order by updated_at desc nulls last
  limit 1;

  if found then
    select x.open_at,x.close_at into v_open,v_close
    from public.registration_window_times(
      v_week,
      v_rule.open_weekday,
      v_rule.open_time,
      v_rule.close_weekday,
      v_rule.close_time
    ) x;
  end if;

  -- 3. An explicitly materialized weekly window is authoritative.
  --    This is the same rule used by V84.9 register_for_shift.
  select * into v_window
  from public.shift_registration_windows
  where store_id=v_store
    and week_start=v_week
  for update;

  if found then
    if v_window.status='finalized' then
      raise exception 'DANG_KY_DA_DONG';
    end if;

    if v_window.status='open' and v_now>=v_window.open_at and v_now<=v_window.close_at then
      v_window_is_authoritative := true;
      v_open := v_window.open_at;
      v_close := v_window.close_at;
    end if;

    -- If the persisted row is stale/closed but auto-open is enabled and the
    -- canonical recurring window is currently active, repair it exactly as the
    -- registration RPC does.
    if not v_window_is_authoritative
       and found
       and v_rule.id is not null
       and coalesce(v_rule.auto_open,true)
       and v_now>=v_open
       and v_now<=v_close then
      update public.shift_registration_windows
      set open_at=v_open,
          close_at=v_close,
          status='open',
          closed_at=null,
          closed_by=null,
          finalized_at=null,
          finalized_by=null,
          updated_at=v_now
      where id=v_window.id
      returning * into v_window;
      v_window_is_authoritative := true;
    end if;
  else
    -- No persisted window: only auto-open may create the canonical window.
    if v_rule.id is not null
       and coalesce(v_rule.auto_open,true)
       and v_now>=v_open
       and v_now<=v_close then
      insert into public.shift_registration_windows(
        store_id,week_start,open_at,close_at,status,
        closed_at,closed_by,finalized_at,finalized_by
      ) values(
        v_store,v_week,v_open,v_close,'open',
        null,null,null,null
      ) returning * into v_window;
      v_window_is_authoritative := true;
    end if;
  end if;

  -- 4. Final authoritative time check.
  if not v_window_is_authoritative then
    raise exception 'DANG_KY_DA_DONG';
  end if;
  if v_now < v_open then raise exception 'DANG_KY_DA_DONG'; end if;
  if v_now > v_close then raise exception 'DANG_KY_DA_DONG'; end if;
  if v_window.status<>'open' then raise exception 'DANG_KY_DA_DONG'; end if;

  -- 5. Cancel only the employee's own pending registration.
  update public.shift_registrations
  set status='cancelled',
      reviewed_at=v_now,
      updated_at=v_now,
      rejection_reason=null
  where id=v_reg.id
    and employee_id=v_uid
    and status='pending';

  if not found then raise exception 'DANG_KY_KHONG_THE_HUY'; end if;

  insert into public.audit_logs(
    actor_id,store_id,action,entity_type,entity_id,new_data
  ) values(
    v_uid,
    v_store,
    'withdraw_shift_registration',
    'shift_registration',
    v_reg.id,
    jsonb_build_object(
      'schedule_id',v_reg.schedule_id,
      'week_start',v_week,
      'open_at',v_open,
      'close_at',v_close
    )
  );

  return true;
end;
$$;


--
-- Name: attendance; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    schedule_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    device_id uuid,
    check_in timestamp with time zone,
    check_out timestamp with time zone,
    check_in_latitude double precision,
    check_in_longitude double precision,
    check_out_latitude double precision,
    check_out_longitude double precision,
    check_in_distance_m double precision,
    check_out_distance_m double precision,
    check_in_status public.attendance_status,
    check_out_status public.attendance_status,
    late_minutes integer DEFAULT 0 NOT NULL,
    worked_minutes integer DEFAULT 0 NOT NULL,
    check_in_device_key text,
    check_out_device_key text,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    early_leave_minutes integer DEFAULT 0 NOT NULL,
    CONSTRAINT attendance_early_leave_minutes_check CHECK ((early_leave_minutes >= 0)),
    CONSTRAINT attendance_late_minutes_check CHECK ((late_minutes >= 0)),
    CONSTRAINT attendance_worked_minutes_check CHECK ((worked_minutes >= 0))
);


--
-- Name: attendance_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendance_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    attendance_id uuid,
    employee_id uuid,
    event_type text NOT NULL,
    event_at timestamp with time zone DEFAULT now() NOT NULL,
    latitude double precision,
    longitude double precision,
    distance_m double precision,
    device_id uuid,
    success boolean DEFAULT true NOT NULL,
    reason text,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: audit_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    actor_id uuid,
    action text NOT NULL,
    entity_type text,
    entity_id uuid,
    old_data jsonb,
    new_data jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    store_id uuid
);


--
-- Name: devices; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.devices (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    device_key text NOT NULL,
    device_name text,
    platform text,
    user_agent text,
    status public.device_status DEFAULT 'pending'::public.device_status NOT NULL,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    approved_by uuid,
    approved_at timestamp with time zone,
    rejected_reason text,
    revoked_at timestamp with time zone,
    last_seen_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: employee_bank_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_bank_accounts (
    employee_id uuid NOT NULL,
    bank_name text NOT NULL,
    account_number text NOT NULL,
    account_holder text NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_bank_accounts_nonempty_values CHECK (((length(btrim(bank_name)) > 0) AND (length(btrim(account_number)) > 0) AND (length(btrim(account_holder)) > 0)))
);


--
-- Name: employee_bank_details; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_bank_details (
    employee_id uuid NOT NULL,
    bank_name text DEFAULT ''::text NOT NULL,
    account_holder text DEFAULT ''::text NOT NULL,
    account_number text DEFAULT ''::text NOT NULL,
    branch_name text DEFAULT ''::text NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_bank_details_account_holder_length CHECK ((char_length(account_holder) <= 160)),
    CONSTRAINT employee_bank_details_account_number_length CHECK ((char_length(account_number) <= 64)),
    CONSTRAINT employee_bank_details_bank_name_length CHECK ((char_length(bank_name) <= 120)),
    CONSTRAINT employee_bank_details_branch_name_length CHECK ((char_length(branch_name) <= 160))
);


--
-- Name: employee_salary_versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.employee_salary_versions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    effective_from date NOT NULL,
    hourly_rate numeric(12,2) NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT employee_salary_versions_hourly_rate_check CHECK ((hourly_rate >= (0)::numeric))
);


--
-- Name: leave_requests; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.leave_requests (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    store_id uuid NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    reason text NOT NULL,
    status public.leave_status DEFAULT 'pending'::public.leave_status NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT leave_requests_check CHECK ((end_date >= start_date))
);


--
-- Name: manager_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.manager_permissions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    permission_key text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    updated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payroll_adjustments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_adjustments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    employee_id uuid NOT NULL,
    payroll_period_id uuid,
    adjustment_type public.adjustment_type NOT NULL,
    amount numeric(14,2) NOT NULL,
    reason text NOT NULL,
    status public.adjustment_status DEFAULT 'pending'::public.adjustment_status NOT NULL,
    created_by uuid,
    approved_by uuid,
    approved_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    source_key text,
    source_schedule_id uuid,
    source_rule_id uuid,
    CONSTRAINT payroll_adjustments_amount_check CHECK ((amount > (0)::numeric))
);


--
-- Name: payroll_penalty_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_penalty_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    rule_type text NOT NULL,
    label text NOT NULL,
    threshold_minutes integer DEFAULT 0 NOT NULL,
    threshold_occurrences integer,
    amount_mode text DEFAULT 'fixed'::text NOT NULL,
    amount numeric NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_penalty_rules_amount_check CHECK ((amount > (0)::numeric)),
    CONSTRAINT payroll_penalty_rules_amount_mode_check CHECK ((amount_mode = ANY (ARRAY['fixed'::text, 'per_minute'::text]))),
    CONSTRAINT payroll_penalty_rules_label_check CHECK ((length(TRIM(BOTH FROM label)) > 0)),
    CONSTRAINT payroll_penalty_rules_nonminute_shape CHECK (((rule_type <> ALL (ARRAY['absence'::text, 'late_monthly'::text])) OR (amount_mode = 'fixed'::text))),
    CONSTRAINT payroll_penalty_rules_rule_type_check CHECK ((rule_type = ANY (ARRAY['late'::text, 'late_monthly'::text, 'early_leave'::text, 'absence'::text]))),
    CONSTRAINT payroll_penalty_rules_threshold_minutes_check CHECK ((threshold_minutes >= 0)),
    CONSTRAINT payroll_penalty_rules_threshold_shape CHECK ((((rule_type = 'late_monthly'::text) AND (threshold_occurrences IS NOT NULL) AND (threshold_occurrences > 0) AND (amount_mode = 'fixed'::text)) OR ((rule_type <> 'late_monthly'::text) AND (threshold_occurrences IS NULL))))
);


--
-- Name: payroll_periods; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_periods (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    period_name text NOT NULL,
    start_date date NOT NULL,
    end_date date NOT NULL,
    status public.payroll_status DEFAULT 'draft'::public.payroll_status NOT NULL,
    locked_at timestamp with time zone,
    locked_by uuid,
    paid_at timestamp with time zone,
    paid_by uuid,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_periods_check CHECK ((end_date >= start_date))
);


--
-- Name: payroll_run_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_run_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_run_id uuid NOT NULL,
    attendance_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    work_date date NOT NULL,
    schedule_start_at timestamp with time zone NOT NULL,
    schedule_end_at timestamp with time zone NOT NULL,
    check_in_at timestamp with time zone,
    check_out_at timestamp with time zone,
    worked_minutes integer NOT NULL,
    hourly_rate numeric NOT NULL,
    gross_amount numeric NOT NULL,
    source text DEFAULT 'attendance'::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_run_items_gross_amount_check CHECK ((gross_amount >= (0)::numeric)),
    CONSTRAINT payroll_run_items_hourly_rate_check CHECK ((hourly_rate >= (0)::numeric)),
    CONSTRAINT payroll_run_items_source_check CHECK ((source = ANY (ARRAY['attendance'::text, 'manual'::text]))),
    CONSTRAINT payroll_run_items_worked_minutes_check CHECK ((worked_minutes >= 0))
);


--
-- Name: payroll_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payroll_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payroll_period_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    hourly_rate numeric(12,2) DEFAULT 0 NOT NULL,
    worked_minutes integer DEFAULT 0 NOT NULL,
    gross_amount numeric(14,2) DEFAULT 0 NOT NULL,
    bonus_amount numeric(14,2) DEFAULT 0 NOT NULL,
    penalty_amount numeric(14,2) DEFAULT 0 NOT NULL,
    advance_amount numeric(14,2) DEFAULT 0 NOT NULL,
    net_amount numeric(14,2) DEFAULT 0 NOT NULL,
    note text,
    calculated_at timestamp with time zone,
    calculated_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT payroll_runs_advance_amount_check CHECK ((advance_amount >= (0)::numeric)),
    CONSTRAINT payroll_runs_bonus_amount_check CHECK ((bonus_amount >= (0)::numeric)),
    CONSTRAINT payroll_runs_gross_amount_check CHECK ((gross_amount >= (0)::numeric)),
    CONSTRAINT payroll_runs_hourly_rate_check CHECK ((hourly_rate >= (0)::numeric)),
    CONSTRAINT payroll_runs_penalty_amount_check CHECK ((penalty_amount >= (0)::numeric)),
    CONSTRAINT payroll_runs_worked_minutes_check CHECK ((worked_minutes >= 0))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    full_name text DEFAULT ''::text NOT NULL,
    phone text,
    email text,
    avatar_url text,
    date_of_birth date,
    national_id text,
    address text,
    role public.user_role DEFAULT 'employee'::public.user_role NOT NULL,
    employment_status public.employment_status DEFAULT 'invited'::public.employment_status NOT NULL,
    hourly_rate numeric(12,2) DEFAULT 0 NOT NULL,
    store_id uuid,
    hired_at date,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT profiles_hourly_rate_check CHECK ((hourly_rate >= (0)::numeric))
);


--
-- Name: shift_registration_recurring_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_registration_recurring_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    open_weekday smallint NOT NULL,
    open_time time without time zone NOT NULL,
    close_weekday smallint NOT NULL,
    close_time time without time zone NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    auto_open boolean DEFAULT true NOT NULL,
    auto_approve boolean DEFAULT true NOT NULL,
    CONSTRAINT shift_registration_recurring_rules_close_weekday_check CHECK (((close_weekday >= 1) AND (close_weekday <= 7))),
    CONSTRAINT shift_registration_recurring_rules_open_weekday_check CHECK (((open_weekday >= 1) AND (open_weekday <= 7)))
);


--
-- Name: shift_registration_windows; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_registration_windows (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    week_start date NOT NULL,
    open_at timestamp with time zone NOT NULL,
    close_at timestamp with time zone NOT NULL,
    status text DEFAULT 'open'::text NOT NULL,
    closed_at timestamp with time zone,
    closed_by uuid,
    finalized_at timestamp with time zone,
    finalized_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shift_registration_windows_check CHECK ((close_at > open_at)),
    CONSTRAINT shift_registration_windows_status_check CHECK ((status = ANY (ARRAY['open'::text, 'closed'::text, 'finalized'::text])))
);


--
-- Name: shift_registrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_registrations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    schedule_id uuid NOT NULL,
    employee_id uuid NOT NULL,
    status public.registration_status DEFAULT 'pending'::public.registration_status NOT NULL,
    note text,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    reviewed_by uuid,
    reviewed_at timestamp with time zone,
    rejection_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: shift_templates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.shift_templates (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    name text NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    break_minutes integer DEFAULT 0 NOT NULL,
    capacity integer DEFAULT 1 NOT NULL,
    color text,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT shift_templates_break_minutes_check CHECK (((break_minutes >= 0) AND (break_minutes <= 180))),
    CONSTRAINT shift_templates_capacity_check CHECK (((capacity >= 1) AND (capacity <= 50)))
);


--
-- Name: store_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.store_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    store_id uuid NOT NULL,
    role public.user_role NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    joined_at timestamp with time zone DEFAULT now() NOT NULL,
    left_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: stores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.stores (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    address text,
    latitude double precision,
    longitude double precision,
    gps_radius_m integer DEFAULT 100 NOT NULL,
    late_grace_minutes integer DEFAULT 5 NOT NULL,
    checkin_early_minutes integer DEFAULT 60 NOT NULL,
    checkout_late_minutes integer DEFAULT 240 NOT NULL,
    timezone text DEFAULT 'Asia/Ho_Chi_Minh'::text NOT NULL,
    wifi_enabled boolean DEFAULT false NOT NULL,
    wifi_name text,
    wifi_note text,
    hourly_default_rate numeric(12,2) DEFAULT 30000 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    checkin_cutoff_minutes integer DEFAULT 30 NOT NULL,
    CONSTRAINT stores_checkin_cutoff_minutes_check CHECK (((checkin_cutoff_minutes >= 0) AND (checkin_cutoff_minutes <= 240))),
    CONSTRAINT stores_checkin_early_minutes_check CHECK (((checkin_early_minutes >= 0) AND (checkin_early_minutes <= 360))),
    CONSTRAINT stores_checkout_late_minutes_check CHECK (((checkout_late_minutes >= 0) AND (checkout_late_minutes <= 1440))),
    CONSTRAINT stores_gps_radius_m_check CHECK (((gps_radius_m >= 20) AND (gps_radius_m <= 1000))),
    CONSTRAINT stores_hourly_default_rate_check CHECK ((hourly_default_rate >= (0)::numeric)),
    CONSTRAINT stores_late_grace_minutes_check CHECK (((late_grace_minutes >= 0) AND (late_grace_minutes <= 60)))
);


--
-- Name: weekly_shift_plan_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.weekly_shift_plan_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    weekday smallint NOT NULL,
    shift_template_id uuid NOT NULL,
    capacity integer DEFAULT 1 NOT NULL,
    note text,
    sort_order integer DEFAULT 0 NOT NULL,
    is_active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT weekly_shift_plan_items_capacity_check CHECK (((capacity >= 1) AND (capacity <= 10))),
    CONSTRAINT weekly_shift_plan_items_weekday_check CHECK (((weekday >= 1) AND (weekday <= 7)))
);


--
-- Name: work_schedules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_schedules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    store_id uuid NOT NULL,
    shift_template_id uuid,
    work_date date NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    employee_id uuid,
    status public.schedule_status DEFAULT 'open'::public.schedule_status NOT NULL,
    note text,
    created_by uuid,
    assigned_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    shift_group_id uuid,
    start_at timestamp with time zone NOT NULL,
    end_at timestamp with time zone NOT NULL,
    weekly_plan_item_id uuid,
    custom_name text,
    schedule_kind text DEFAULT 'template'::text NOT NULL,
    CONSTRAINT work_schedules_check CHECK ((end_time <> start_time)),
    CONSTRAINT work_schedules_schedule_kind_check CHECK ((schedule_kind = ANY (ARRAY['template'::text, 'supplemental'::text]))),
    CONSTRAINT work_schedules_start_end_at_check CHECK ((end_at > start_at))
);


--
-- Name: attendance_events attendance_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_events
    ADD CONSTRAINT attendance_events_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_pkey PRIMARY KEY (id);


--
-- Name: attendance attendance_schedule_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_schedule_id_key UNIQUE (schedule_id);


--
-- Name: audit_logs audit_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_pkey PRIMARY KEY (id);


--
-- Name: devices devices_device_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_device_key_key UNIQUE (device_key);


--
-- Name: devices devices_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_pkey PRIMARY KEY (id);


--
-- Name: employee_bank_accounts employee_bank_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_accounts
    ADD CONSTRAINT employee_bank_accounts_pkey PRIMARY KEY (employee_id);


--
-- Name: employee_bank_details employee_bank_details_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_details
    ADD CONSTRAINT employee_bank_details_pkey PRIMARY KEY (employee_id);


--
-- Name: employee_salary_versions employee_salary_versions_employee_id_effective_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_salary_versions
    ADD CONSTRAINT employee_salary_versions_employee_id_effective_from_key UNIQUE (employee_id, effective_from);


--
-- Name: employee_salary_versions employee_salary_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_salary_versions
    ADD CONSTRAINT employee_salary_versions_pkey PRIMARY KEY (id);


--
-- Name: leave_requests leave_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_pkey PRIMARY KEY (id);


--
-- Name: manager_permissions manager_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_permissions
    ADD CONSTRAINT manager_permissions_pkey PRIMARY KEY (id);


--
-- Name: manager_permissions manager_permissions_store_id_permission_key_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_permissions
    ADD CONSTRAINT manager_permissions_store_id_permission_key_key UNIQUE (store_id, permission_key);


--
-- Name: payroll_adjustments payroll_adjustments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_pkey PRIMARY KEY (id);


--
-- Name: payroll_penalty_rules payroll_penalty_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_penalty_rules
    ADD CONSTRAINT payroll_penalty_rules_pkey PRIMARY KEY (id);


--
-- Name: payroll_periods payroll_periods_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_pkey PRIMARY KEY (id);


--
-- Name: payroll_periods payroll_periods_store_id_start_date_end_date_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_store_id_start_date_end_date_key UNIQUE (store_id, start_date, end_date);


--
-- Name: payroll_run_items payroll_run_items_payroll_run_id_attendance_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_run_items
    ADD CONSTRAINT payroll_run_items_payroll_run_id_attendance_id_key UNIQUE (payroll_run_id, attendance_id);


--
-- Name: payroll_run_items payroll_run_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_run_items
    ADD CONSTRAINT payroll_run_items_pkey PRIMARY KEY (id);


--
-- Name: payroll_runs payroll_runs_payroll_period_id_employee_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_payroll_period_id_employee_id_key UNIQUE (payroll_period_id, employee_id);


--
-- Name: payroll_runs payroll_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_pkey PRIMARY KEY (id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: schedule_requests schedule_requests_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_pkey PRIMARY KEY (id);


--
-- Name: shift_registration_recurring_rules shift_registration_recurring_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_recurring_rules
    ADD CONSTRAINT shift_registration_recurring_rules_pkey PRIMARY KEY (id);


--
-- Name: shift_registration_recurring_rules shift_registration_recurring_rules_store_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_recurring_rules
    ADD CONSTRAINT shift_registration_recurring_rules_store_id_key UNIQUE (store_id);


--
-- Name: shift_registration_windows shift_registration_windows_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_windows
    ADD CONSTRAINT shift_registration_windows_pkey PRIMARY KEY (id);


--
-- Name: shift_registration_windows shift_registration_windows_store_id_week_start_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_windows
    ADD CONSTRAINT shift_registration_windows_store_id_week_start_key UNIQUE (store_id, week_start);


--
-- Name: shift_registrations shift_registrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registrations
    ADD CONSTRAINT shift_registrations_pkey PRIMARY KEY (id);


--
-- Name: shift_template_versions shift_template_versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_template_versions
    ADD CONSTRAINT shift_template_versions_pkey PRIMARY KEY (id);


--
-- Name: shift_template_versions shift_template_versions_shift_template_id_effective_from_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_template_versions
    ADD CONSTRAINT shift_template_versions_shift_template_id_effective_from_key UNIQUE (shift_template_id, effective_from);


--
-- Name: shift_templates shift_templates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT shift_templates_pkey PRIMARY KEY (id);


--
-- Name: shift_templates shift_templates_store_id_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT shift_templates_store_id_name_key UNIQUE (store_id, name);


--
-- Name: store_memberships store_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_memberships
    ADD CONSTRAINT store_memberships_pkey PRIMARY KEY (id);


--
-- Name: store_memberships store_memberships_user_id_store_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_memberships
    ADD CONSTRAINT store_memberships_user_id_store_id_key UNIQUE (user_id, store_id);


--
-- Name: stores stores_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.stores
    ADD CONSTRAINT stores_pkey PRIMARY KEY (id);


--
-- Name: weekly_shift_plan_items weekly_shift_plan_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_shift_plan_items
    ADD CONSTRAINT weekly_shift_plan_items_pkey PRIMARY KEY (id);


--
-- Name: work_schedules work_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_pkey PRIMARY KEY (id);


--
-- Name: idx_adjustments_employee_period; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_adjustments_employee_period ON public.payroll_adjustments USING btree (employee_id, payroll_period_id, status);


--
-- Name: idx_attendance_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_employee_date ON public.attendance USING btree (employee_id, check_in);


--
-- Name: idx_attendance_events_attendance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_attendance_events_attendance ON public.attendance_events USING btree (attendance_id, event_at DESC);


--
-- Name: idx_audit_actor_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_actor_time ON public.audit_logs USING btree (actor_id, created_at DESC);


--
-- Name: idx_audit_entity; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_entity ON public.audit_logs USING btree (entity_type, entity_id, created_at DESC);


--
-- Name: idx_audit_store_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_store_time ON public.audit_logs USING btree (store_id, created_at DESC);


--
-- Name: idx_devices_employee_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_devices_employee_status ON public.devices USING btree (employee_id, status);


--
-- Name: idx_employee_salary_versions_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_employee_salary_versions_lookup ON public.employee_salary_versions USING btree (employee_id, effective_from DESC);


--
-- Name: idx_leave_employee_dates; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_employee_dates ON public.leave_requests USING btree (employee_id, start_date, end_date, status);


--
-- Name: idx_leave_store_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_leave_store_status ON public.leave_requests USING btree (store_id, status, start_date);


--
-- Name: idx_manager_permissions_store; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_manager_permissions_store ON public.manager_permissions USING btree (store_id, permission_key);


--
-- Name: idx_payroll_run_items_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_run_items_employee_date ON public.payroll_run_items USING btree (employee_id, work_date);


--
-- Name: idx_payroll_run_items_run; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payroll_run_items_run ON public.payroll_run_items USING btree (payroll_run_id, work_date);


--
-- Name: idx_profiles_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_status ON public.profiles USING btree (employment_status);


--
-- Name: idx_profiles_store_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_profiles_store_role ON public.profiles USING btree (store_id, role);


--
-- Name: idx_registrations_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_registrations_status ON public.shift_registrations USING btree (status, requested_at);


--
-- Name: idx_shift_registration_recurring_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_registration_recurring_active ON public.shift_registration_recurring_rules USING btree (store_id, is_active);


--
-- Name: idx_shift_registration_windows_store_week; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_registration_windows_store_week ON public.shift_registration_windows USING btree (store_id, week_start);


--
-- Name: idx_shift_template_versions_lookup; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_shift_template_versions_lookup ON public.shift_template_versions USING btree (shift_template_id, effective_from DESC);


--
-- Name: idx_store_memberships_store; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_store_memberships_store ON public.store_memberships USING btree (store_id, is_active, role, user_id);


--
-- Name: idx_store_memberships_user; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_store_memberships_user ON public.store_memberships USING btree (user_id, is_active, store_id);


--
-- Name: idx_weekly_shift_plan_store_day; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_weekly_shift_plan_store_day ON public.weekly_shift_plan_items USING btree (store_id, weekday, sort_order);


--
-- Name: idx_work_schedules_employee_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_employee_date ON public.work_schedules USING btree (employee_id, work_date);


--
-- Name: idx_work_schedules_employee_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_employee_start_at ON public.work_schedules USING btree (employee_id, start_at);


--
-- Name: idx_work_schedules_group; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_group ON public.work_schedules USING btree (shift_group_id, status);


--
-- Name: idx_work_schedules_store_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_store_date ON public.work_schedules USING btree (store_id, work_date);


--
-- Name: idx_work_schedules_store_date_template; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_store_date_template ON public.work_schedules USING btree (store_id, work_date, shift_template_id, status);


--
-- Name: idx_work_schedules_store_start_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_store_start_at ON public.work_schedules USING btree (store_id, start_at);


--
-- Name: idx_work_schedules_weekly_plan_item; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_schedules_weekly_plan_item ON public.work_schedules USING btree (weekly_plan_item_id, work_date);


--
-- Name: payroll_adjustments_source_key_uq; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX payroll_adjustments_source_key_uq ON public.payroll_adjustments USING btree (source_key) WHERE (source_key IS NOT NULL);


--
-- Name: payroll_adjustments_source_schedule_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payroll_adjustments_source_schedule_idx ON public.payroll_adjustments USING btree (source_schedule_id) WHERE (source_schedule_id IS NOT NULL);


--
-- Name: schedule_requests_employee_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedule_requests_employee_idx ON public.schedule_requests USING btree (employee_id, created_at DESC);


--
-- Name: schedule_requests_store_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX schedule_requests_store_status_idx ON public.schedule_requests USING btree (store_id, status, created_at DESC);


--
-- Name: uq_assigned_employee_shift; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_assigned_employee_shift ON public.work_schedules USING btree (employee_id, work_date, start_time, end_time) WHERE ((employee_id IS NOT NULL) AND (status = ANY (ARRAY['open'::public.schedule_status, 'assigned'::public.schedule_status])));


--
-- Name: uq_shift_registration_employee_schedule_active; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_shift_registration_employee_schedule_active ON public.shift_registrations USING btree (schedule_id, employee_id) WHERE (status = ANY (ARRAY['pending'::public.registration_status, 'approved'::public.registration_status]));


--
-- Name: attendance trg_attendance_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_attendance_updated_at BEFORE UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: audit_logs trg_audit_store_id; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_audit_store_id BEFORE INSERT ON public.audit_logs FOR EACH ROW EXECUTE FUNCTION public.set_audit_store_id();


--
-- Name: devices trg_devices_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_devices_updated_at BEFORE UPDATE ON public.devices FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.attendance FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: attendance_events trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.attendance_events FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: leave_requests trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: profiles trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: schedule_requests trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.schedule_requests FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: shift_registration_recurring_rules trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.shift_registration_recurring_rules FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: shift_registration_windows trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.shift_registration_windows FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: shift_registrations trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.shift_registrations FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: shift_template_versions trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.shift_template_versions FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: shift_templates trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.shift_templates FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: weekly_shift_plan_items trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.weekly_shift_plan_items FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: work_schedules trg_enforce_manager_business_permission; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_enforce_manager_business_permission BEFORE INSERT OR DELETE OR UPDATE ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.enforce_manager_business_permission();


--
-- Name: leave_requests trg_leave_requests_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_leave_requests_updated_at BEFORE UPDATE ON public.leave_requests FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shift_registration_recurring_rules trg_owner_registration_rules; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_owner_registration_rules BEFORE INSERT OR DELETE OR UPDATE ON public.shift_registration_recurring_rules FOR EACH ROW EXECUTE FUNCTION public.guard_owner_schedule_configuration();


--
-- Name: shift_registration_windows trg_owner_registration_windows; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_owner_registration_windows BEFORE INSERT OR DELETE OR UPDATE ON public.shift_registration_windows FOR EACH ROW EXECUTE FUNCTION public.guard_registration_window_write();


--
-- Name: shift_templates trg_owner_shift_templates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_owner_shift_templates BEFORE INSERT OR DELETE OR UPDATE ON public.shift_templates FOR EACH ROW EXECUTE FUNCTION public.guard_owner_schedule_configuration();


--
-- Name: weekly_shift_plan_items trg_owner_weekly_shift_plan; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_owner_weekly_shift_plan BEFORE INSERT OR DELETE OR UPDATE ON public.weekly_shift_plan_items FOR EACH ROW EXECUTE FUNCTION public.guard_owner_schedule_configuration();


--
-- Name: payroll_adjustments trg_payroll_adjustments_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_adjustments_updated_at BEFORE UPDATE ON public.payroll_adjustments FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_periods trg_payroll_periods_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_periods_updated_at BEFORE UPDATE ON public.payroll_periods FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: payroll_runs trg_payroll_runs_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_payroll_runs_updated_at BEFORE UPDATE ON public.payroll_runs FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: profiles trg_profile_store_membership; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_profile_store_membership AFTER INSERT OR UPDATE OF store_id, role ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.sync_profile_store_membership();


--
-- Name: profiles trg_profiles_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shift_registrations trg_shift_registrations_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_registrations_updated_at BEFORE UPDATE ON public.shift_registrations FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: shift_templates trg_shift_templates_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_shift_templates_updated_at BEFORE UPDATE ON public.shift_templates FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: store_memberships trg_store_memberships_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_store_memberships_updated_at BEFORE UPDATE ON public.store_memberships FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: stores trg_stores_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_stores_updated_at BEFORE UPDATE ON public.stores FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: weekly_shift_plan_items trg_weekly_shift_plan_items_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_weekly_shift_plan_items_updated_at BEFORE UPDATE ON public.weekly_shift_plan_items FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: work_schedules trg_work_schedule_datetimes; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_schedule_datetimes BEFORE INSERT OR UPDATE OF store_id, work_date, start_time, end_time ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.sync_work_schedule_datetimes();


--
-- Name: work_schedules trg_work_schedules_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_work_schedules_updated_at BEFORE UPDATE ON public.work_schedules FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();


--
-- Name: attendance attendance_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: attendance_events attendance_events_attendance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_events
    ADD CONSTRAINT attendance_events_attendance_id_fkey FOREIGN KEY (attendance_id) REFERENCES public.attendance(id) ON DELETE CASCADE;


--
-- Name: attendance_events attendance_events_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_events
    ADD CONSTRAINT attendance_events_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.devices(id) ON DELETE SET NULL;


--
-- Name: attendance_events attendance_events_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance_events
    ADD CONSTRAINT attendance_events_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: attendance attendance_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendance
    ADD CONSTRAINT attendance_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.work_schedules(id) ON DELETE RESTRICT;


--
-- Name: audit_logs audit_logs_actor_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_actor_id_fkey FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: audit_logs audit_logs_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_logs
    ADD CONSTRAINT audit_logs_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE SET NULL;


--
-- Name: devices devices_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: devices devices_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.devices
    ADD CONSTRAINT devices_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: employee_bank_accounts employee_bank_accounts_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_accounts
    ADD CONSTRAINT employee_bank_accounts_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: employee_bank_details employee_bank_details_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_details
    ADD CONSTRAINT employee_bank_details_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: employee_bank_details employee_bank_details_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_bank_details
    ADD CONSTRAINT employee_bank_details_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: employee_salary_versions employee_salary_versions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_salary_versions
    ADD CONSTRAINT employee_salary_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: employee_salary_versions employee_salary_versions_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.employee_salary_versions
    ADD CONSTRAINT employee_salary_versions_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: leave_requests leave_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: leave_requests leave_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: leave_requests leave_requests_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.leave_requests
    ADD CONSTRAINT leave_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: manager_permissions manager_permissions_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_permissions
    ADD CONSTRAINT manager_permissions_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: manager_permissions manager_permissions_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.manager_permissions
    ADD CONSTRAINT manager_permissions_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments payroll_adjustments_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments payroll_adjustments_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments payroll_adjustments_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: payroll_adjustments payroll_adjustments_payroll_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_payroll_period_id_fkey FOREIGN KEY (payroll_period_id) REFERENCES public.payroll_periods(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments payroll_adjustments_source_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_source_rule_id_fkey FOREIGN KEY (source_rule_id) REFERENCES public.payroll_penalty_rules(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments payroll_adjustments_source_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_adjustments
    ADD CONSTRAINT payroll_adjustments_source_schedule_id_fkey FOREIGN KEY (source_schedule_id) REFERENCES public.work_schedules(id) ON DELETE SET NULL;


--
-- Name: payroll_penalty_rules payroll_penalty_rules_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_penalty_rules
    ADD CONSTRAINT payroll_penalty_rules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_penalty_rules payroll_penalty_rules_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_penalty_rules
    ADD CONSTRAINT payroll_penalty_rules_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: payroll_periods payroll_periods_locked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_locked_by_fkey FOREIGN KEY (locked_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_paid_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_paid_by_fkey FOREIGN KEY (paid_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_periods payroll_periods_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_periods
    ADD CONSTRAINT payroll_periods_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: payroll_run_items payroll_run_items_attendance_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_run_items
    ADD CONSTRAINT payroll_run_items_attendance_id_fkey FOREIGN KEY (attendance_id) REFERENCES public.attendance(id) ON DELETE RESTRICT;


--
-- Name: payroll_run_items payroll_run_items_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_run_items
    ADD CONSTRAINT payroll_run_items_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: payroll_run_items payroll_run_items_payroll_run_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_run_items
    ADD CONSTRAINT payroll_run_items_payroll_run_id_fkey FOREIGN KEY (payroll_run_id) REFERENCES public.payroll_runs(id) ON DELETE CASCADE;


--
-- Name: payroll_runs payroll_runs_calculated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_calculated_by_fkey FOREIGN KEY (calculated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: payroll_runs payroll_runs_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: payroll_runs payroll_runs_payroll_period_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payroll_runs
    ADD CONSTRAINT payroll_runs_payroll_period_id_fkey FOREIGN KEY (payroll_period_id) REFERENCES public.payroll_periods(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: profiles profiles_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE SET NULL;


--
-- Name: schedule_requests schedule_requests_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: schedule_requests schedule_requests_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id);


--
-- Name: schedule_requests schedule_requests_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.work_schedules(id) ON DELETE CASCADE;


--
-- Name: schedule_requests schedule_requests_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: schedule_requests schedule_requests_target_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schedule_requests
    ADD CONSTRAINT schedule_requests_target_schedule_id_fkey FOREIGN KEY (target_schedule_id) REFERENCES public.work_schedules(id) ON DELETE SET NULL;


--
-- Name: shift_registration_recurring_rules shift_registration_recurring_rules_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_recurring_rules
    ADD CONSTRAINT shift_registration_recurring_rules_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: shift_registration_windows shift_registration_windows_closed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_windows
    ADD CONSTRAINT shift_registration_windows_closed_by_fkey FOREIGN KEY (closed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: shift_registration_windows shift_registration_windows_finalized_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_windows
    ADD CONSTRAINT shift_registration_windows_finalized_by_fkey FOREIGN KEY (finalized_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: shift_registration_windows shift_registration_windows_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registration_windows
    ADD CONSTRAINT shift_registration_windows_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: shift_registrations shift_registrations_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registrations
    ADD CONSTRAINT shift_registrations_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: shift_registrations shift_registrations_reviewed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registrations
    ADD CONSTRAINT shift_registrations_reviewed_by_fkey FOREIGN KEY (reviewed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: shift_registrations shift_registrations_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_registrations
    ADD CONSTRAINT shift_registrations_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.work_schedules(id) ON DELETE CASCADE;


--
-- Name: shift_template_versions shift_template_versions_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_template_versions
    ADD CONSTRAINT shift_template_versions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: shift_template_versions shift_template_versions_shift_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_template_versions
    ADD CONSTRAINT shift_template_versions_shift_template_id_fkey FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE CASCADE;


--
-- Name: shift_templates shift_templates_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.shift_templates
    ADD CONSTRAINT shift_templates_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: store_memberships store_memberships_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_memberships
    ADD CONSTRAINT store_memberships_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: store_memberships store_memberships_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.store_memberships
    ADD CONSTRAINT store_memberships_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: weekly_shift_plan_items weekly_shift_plan_items_shift_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_shift_plan_items
    ADD CONSTRAINT weekly_shift_plan_items_shift_template_id_fkey FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE RESTRICT;


--
-- Name: weekly_shift_plan_items weekly_shift_plan_items_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.weekly_shift_plan_items
    ADD CONSTRAINT weekly_shift_plan_items_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: work_schedules work_schedules_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: work_schedules work_schedules_employee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_employee_id_fkey FOREIGN KEY (employee_id) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: work_schedules work_schedules_shift_template_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_shift_template_id_fkey FOREIGN KEY (shift_template_id) REFERENCES public.shift_templates(id) ON DELETE SET NULL;


--
-- Name: work_schedules work_schedules_store_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_store_id_fkey FOREIGN KEY (store_id) REFERENCES public.stores(id) ON DELETE CASCADE;


--
-- Name: work_schedules work_schedules_weekly_plan_item_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_schedules
    ADD CONSTRAINT work_schedules_weekly_plan_item_fk FOREIGN KEY (weekly_plan_item_id) REFERENCES public.weekly_shift_plan_items(id) ON DELETE SET NULL;


--
-- Name: payroll_adjustments adjustments_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY adjustments_owner_manage_branch ON public.payroll_adjustments TO authenticated USING ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = payroll_adjustments.employee_id) AND public.is_store_owner(p.store_id)))))) WITH CHECK ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = payroll_adjustments.employee_id) AND public.is_store_owner(p.store_id))))));


--
-- Name: attendance; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.attendance_events ENABLE ROW LEVEL SECURITY;

--
-- Name: attendance_events attendance_events_manager_select_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_events_manager_select_branch ON public.attendance_events FOR SELECT TO authenticated USING ((public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM (public.attendance a
     JOIN public.work_schedules s ON ((s.id = a.schedule_id)))
  WHERE ((a.id = attendance_events.attendance_id) AND public.is_store_member(s.store_id) AND public.current_user_has_manager_permission('attendance_process'::text))))));


--
-- Name: attendance_events attendance_events_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_events_self_read_branch ON public.attendance_events FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM (public.attendance a
     JOIN public.work_schedules s ON ((s.id = a.schedule_id)))
  WHERE ((a.id = attendance_events.attendance_id) AND public.is_store_member(s.store_id) AND public.current_user_has_manager_permission('attendance_process'::text)))))));


--
-- Name: attendance attendance_manager_select_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_manager_select_branch ON public.attendance FOR SELECT TO authenticated USING ((public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.work_schedules s
  WHERE ((s.id = attendance.schedule_id) AND public.is_store_member(s.store_id) AND public.current_user_has_manager_permission('attendance_process'::text))))));


--
-- Name: attendance attendance_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY attendance_self_read_branch ON public.attendance FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.work_schedules s
  WHERE ((s.id = attendance.schedule_id) AND public.is_store_member(s.store_id) AND public.current_user_has_manager_permission('attendance_process'::text)))))));


--
-- Name: audit_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: audit_logs audit_manager_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY audit_manager_read_branch ON public.audit_logs FOR SELECT TO authenticated USING ((public.is_manager_or_owner() AND (store_id IS NOT NULL) AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('audit_view'::text)));


--
-- Name: devices; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.devices ENABLE ROW LEVEL SECURITY;

--
-- Name: devices devices_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY devices_owner_manage_branch ON public.devices TO authenticated USING ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = devices.employee_id) AND public.is_store_owner(p.store_id)))))) WITH CHECK ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = devices.employee_id) AND public.is_store_owner(p.store_id))))));


--
-- Name: devices devices_self_insert_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY devices_self_insert_branch ON public.devices FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND public.is_store_member(p.store_id)))) AND (status = 'pending'::public.device_status)));


--
-- Name: devices devices_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY devices_self_read_branch ON public.devices FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = devices.employee_id) AND public.is_store_member(p.store_id)))))));


--
-- Name: devices devices_self_update_pending_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY devices_self_update_pending_branch ON public.devices FOR UPDATE TO authenticated USING (((employee_id = auth.uid()) AND (status = 'pending'::public.device_status))) WITH CHECK (((employee_id = auth.uid()) AND (status = 'pending'::public.device_status)));


--
-- Name: employee_bank_accounts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_bank_accounts ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_bank_accounts employee_bank_accounts_delete_self_or_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_delete_self_or_owner ON public.employee_bank_accounts FOR DELETE TO authenticated USING (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_bank_accounts.employee_id) AND (p.store_id IS NOT NULL) AND public.is_store_owner(p.store_id)))))));


--
-- Name: employee_bank_accounts employee_bank_accounts_insert_self_or_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_insert_self_or_owner ON public.employee_bank_accounts FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_bank_accounts.employee_id) AND (p.store_id IS NOT NULL) AND public.is_store_owner(p.store_id)))))));


--
-- Name: employee_bank_accounts employee_bank_accounts_manager_payroll_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_manager_payroll_read ON public.employee_bank_accounts FOR SELECT TO authenticated USING (public.can_manager_view_employee_payroll(employee_id));


--
-- Name: employee_bank_accounts employee_bank_accounts_read_self_or_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_read_self_or_owner ON public.employee_bank_accounts FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_bank_accounts.employee_id) AND (p.store_id IS NOT NULL) AND public.is_store_owner(p.store_id)))))));


--
-- Name: employee_bank_accounts employee_bank_accounts_update_self_or_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_bank_accounts_update_self_or_owner ON public.employee_bank_accounts FOR UPDATE TO authenticated USING (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_bank_accounts.employee_id) AND (p.store_id IS NOT NULL) AND public.is_store_owner(p.store_id))))))) WITH CHECK (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_bank_accounts.employee_id) AND (p.store_id IS NOT NULL) AND public.is_store_owner(p.store_id)))))));


--
-- Name: employee_bank_details; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_bank_details ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_salary_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.employee_salary_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: employee_salary_versions employee_salary_versions_employee_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_salary_versions_employee_read_own ON public.employee_salary_versions FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: employee_salary_versions employee_salary_versions_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY employee_salary_versions_manage_branch ON public.employee_salary_versions TO authenticated USING ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_salary_versions.employee_id) AND public.is_store_owner(p.store_id)))))) WITH CHECK ((public.is_owner() AND (EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = employee_salary_versions.employee_id) AND public.is_store_owner(p.store_id))))));


--
-- Name: leave_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.leave_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: leave_requests leave_self_insert_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_self_insert_branch ON public.leave_requests FOR INSERT TO authenticated WITH CHECK (((employee_id = auth.uid()) AND public.is_store_member(store_id)));


--
-- Name: leave_requests leave_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY leave_self_read_branch ON public.leave_requests FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('leave_manage'::text))));


--
-- Name: manager_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.manager_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: manager_permissions manager_permissions_manager_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY manager_permissions_manager_read ON public.manager_permissions FOR SELECT TO authenticated USING (((public.my_role() = 'manager'::public.user_role) AND (store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid())))));


--
-- Name: manager_permissions manager_permissions_owner_manage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY manager_permissions_owner_manage ON public.manager_permissions TO authenticated USING (public.is_owner()) WITH CHECK (public.is_owner());


--
-- Name: payroll_adjustments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_adjustments ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_adjustments payroll_adjustments_employee_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_adjustments_employee_read_own ON public.payroll_adjustments FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: payroll_adjustments payroll_adjustments_manager_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_adjustments_manager_read_branch ON public.payroll_adjustments FOR SELECT TO authenticated USING (public.can_manager_view_employee_payroll(employee_id));


--
-- Name: payroll_penalty_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_penalty_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_penalty_rules payroll_penalty_rules_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_penalty_rules_owner_manage_branch ON public.payroll_penalty_rules TO authenticated USING ((public.is_owner() AND public.is_store_owner(store_id))) WITH CHECK ((public.is_owner() AND public.is_store_owner(store_id)));


--
-- Name: payroll_periods; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_periods ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_periods payroll_periods_employee_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_periods_employee_read_own ON public.payroll_periods FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.payroll_runs r
  WHERE ((r.payroll_period_id = payroll_periods.id) AND (r.employee_id = auth.uid())))));


--
-- Name: payroll_periods payroll_periods_manager_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_periods_manager_read_branch ON public.payroll_periods FOR SELECT TO authenticated USING (((public.my_role() = 'manager'::public.user_role) AND public.current_user_has_manager_permission('payroll_view'::text) AND public.is_store_member(store_id)));


--
-- Name: payroll_periods payroll_periods_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_periods_owner_manage_branch ON public.payroll_periods TO authenticated USING (public.is_store_owner(store_id)) WITH CHECK (public.is_store_owner(store_id));


--
-- Name: payroll_run_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_run_items ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_run_items payroll_run_items_employee_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_run_items_employee_read ON public.payroll_run_items FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_owner() AND (EXISTS ( SELECT 1
   FROM (public.payroll_runs r
     JOIN public.payroll_periods p ON ((p.id = r.payroll_period_id)))
  WHERE ((r.id = payroll_run_items.payroll_run_id) AND public.is_store_owner(p.store_id)))))));


--
-- Name: payroll_runs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payroll_runs ENABLE ROW LEVEL SECURITY;

--
-- Name: payroll_runs payroll_runs_employee_read_own; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_runs_employee_read_own ON public.payroll_runs FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: payroll_runs payroll_runs_manager_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_runs_manager_read_branch ON public.payroll_runs FOR SELECT TO authenticated USING (public.can_manager_view_payroll_run(payroll_period_id));


--
-- Name: payroll_runs payroll_runs_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payroll_runs_owner_manage_branch ON public.payroll_runs TO authenticated USING (public.can_owner_manage_payroll_run(payroll_period_id)) WITH CHECK (public.can_owner_manage_payroll_run(payroll_period_id));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_owner_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_owner_manage_branch ON public.profiles TO authenticated USING ((public.is_owner() AND (store_id IS NOT NULL) AND public.is_store_owner(store_id))) WITH CHECK ((public.is_owner() AND (store_id IS NOT NULL) AND public.is_store_owner(store_id)));


--
-- Name: profiles profiles_self_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_self_read ON public.profiles FOR SELECT TO authenticated USING ((id = auth.uid()));


--
-- Name: profiles profiles_self_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_self_update ON public.profiles FOR UPDATE TO authenticated USING ((id = auth.uid())) WITH CHECK (((id = auth.uid()) AND (role = ( SELECT profiles_1.role
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))) AND (employment_status = ( SELECT profiles_1.employment_status
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))) AND (hourly_rate = ( SELECT profiles_1.hourly_rate
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid()))) AND (store_id = ( SELECT profiles_1.store_id
   FROM public.profiles profiles_1
  WHERE (profiles_1.id = auth.uid())))));


--
-- Name: profiles profiles_staff_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_staff_read_branch ON public.profiles FOR SELECT TO authenticated USING ((public.is_manager_or_owner() AND (store_id IS NOT NULL) AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('employee_basic'::text)));


--
-- Name: shift_registration_recurring_rules registration_recurring_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY registration_recurring_read_branch ON public.shift_registration_recurring_rules FOR SELECT TO authenticated USING ((public.is_store_member(store_id) AND ((NOT public.is_manager_or_owner()) OR public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: shift_registration_windows registration_windows_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY registration_windows_read_branch ON public.shift_registration_windows FOR SELECT TO authenticated USING ((public.is_store_member(store_id) AND ((NOT public.is_manager_or_owner()) OR public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: shift_registrations registrations_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY registrations_self_read_branch ON public.shift_registrations FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.work_schedules s
  WHERE ((s.id = shift_registrations.schedule_id) AND public.is_store_member(s.store_id) AND public.current_user_has_manager_permission('shift_registration'::text)))))));


--
-- Name: schedule_requests; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.schedule_requests ENABLE ROW LEVEL SECURITY;

--
-- Name: schedule_requests schedule_requests_employee_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_requests_employee_select ON public.schedule_requests FOR SELECT TO authenticated USING ((employee_id = auth.uid()));


--
-- Name: schedule_requests schedule_requests_self_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_requests_self_read_branch ON public.schedule_requests FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR (public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('leave_manage'::text))));


--
-- Name: schedule_requests schedule_requests_staff_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_requests_staff_select ON public.schedule_requests FOR SELECT TO authenticated USING ((public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('leave_manage'::text)));


--
-- Name: schedule_requests schedule_requests_staff_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedule_requests_staff_update ON public.schedule_requests FOR UPDATE TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.store_id = schedule_requests.store_id) AND (p.role = ANY (ARRAY['owner'::public.user_role, 'manager'::public.user_role])) AND (p.employment_status = 'active'::public.employment_status))))) WITH CHECK ((EXISTS ( SELECT 1
   FROM public.profiles p
  WHERE ((p.id = auth.uid()) AND (p.store_id = schedule_requests.store_id) AND (p.role = ANY (ARRAY['owner'::public.user_role, 'manager'::public.user_role])) AND (p.employment_status = 'active'::public.employment_status)))));


--
-- Name: work_schedules schedules_employee_select_v21; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedules_employee_select_v21 ON public.work_schedules FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ((status = 'open'::public.schedule_status) AND (employee_id IS NULL) AND (store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE ((profiles.id = auth.uid()) AND (profiles.role = 'employee'::public.user_role) AND (profiles.employment_status = 'active'::public.employment_status)))))));


--
-- Name: work_schedules schedules_read_employee_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY schedules_read_employee_branch ON public.work_schedules FOR SELECT TO authenticated USING (((employee_id = auth.uid()) OR ((employee_id IS NULL) AND public.is_store_member(store_id) AND (status = 'open'::public.schedule_status) AND (NOT public.is_manager_or_owner())) OR (public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: shift_registration_recurring_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_registration_recurring_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_registration_windows; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_registration_windows ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_registrations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_registrations ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_template_versions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_template_versions ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_template_versions shift_template_versions_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_template_versions_manage_branch ON public.shift_template_versions TO authenticated USING ((public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.shift_templates t
  WHERE ((t.id = shift_template_versions.shift_template_id) AND public.is_store_member(t.store_id) AND public.current_user_has_manager_permission('schedule_manage'::text)))))) WITH CHECK ((public.is_manager_or_owner() AND (EXISTS ( SELECT 1
   FROM public.shift_templates t
  WHERE ((t.id = shift_template_versions.shift_template_id) AND public.is_store_member(t.store_id) AND public.current_user_has_manager_permission('schedule_manage'::text))))));


--
-- Name: shift_template_versions shift_template_versions_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_template_versions_read_branch ON public.shift_template_versions FOR SELECT TO authenticated USING ((EXISTS ( SELECT 1
   FROM public.shift_templates t
  WHERE ((t.id = shift_template_versions.shift_template_id) AND public.is_store_member(t.store_id) AND ((NOT public.is_manager_or_owner()) OR public.current_user_has_manager_permission('schedule_manage'::text))))));


--
-- Name: shift_templates; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.shift_templates ENABLE ROW LEVEL SECURITY;

--
-- Name: shift_templates shift_templates_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_templates_manage_branch ON public.shift_templates TO authenticated USING ((public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('schedule_manage'::text))) WITH CHECK ((public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('schedule_manage'::text)));


--
-- Name: shift_templates shift_templates_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY shift_templates_read_branch ON public.shift_templates FOR SELECT TO authenticated USING ((public.is_store_member(store_id) AND ((NOT public.is_manager_or_owner()) OR public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: store_memberships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.store_memberships ENABLE ROW LEVEL SECURITY;

--
-- Name: store_memberships store_memberships_owner_manage; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY store_memberships_owner_manage ON public.store_memberships TO authenticated USING (public.is_store_owner(store_id)) WITH CHECK (public.is_store_owner(store_id));


--
-- Name: store_memberships store_memberships_owner_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY store_memberships_owner_read ON public.store_memberships FOR SELECT TO authenticated USING (public.is_store_owner(store_id));


--
-- Name: store_memberships store_memberships_self_read; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY store_memberships_self_read ON public.store_memberships FOR SELECT TO authenticated USING ((user_id = auth.uid()));


--
-- Name: stores; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

--
-- Name: stores stores_owner_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_owner_update ON public.stores FOR UPDATE TO authenticated USING (public.is_store_owner(id)) WITH CHECK (public.is_store_owner(id));


--
-- Name: stores stores_read_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY stores_read_member ON public.stores FOR SELECT TO authenticated USING (public.is_store_member(id));


--
-- Name: weekly_shift_plan_items weekly_plan_manage_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_plan_manage_branch ON public.weekly_shift_plan_items TO authenticated USING ((public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('schedule_manage'::text))) WITH CHECK ((public.is_manager_or_owner() AND public.is_store_member(store_id) AND public.current_user_has_manager_permission('schedule_manage'::text)));


--
-- Name: weekly_shift_plan_items weekly_plan_read_branch; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_plan_read_branch ON public.weekly_shift_plan_items FOR SELECT TO authenticated USING ((public.is_store_member(store_id) AND ((NOT public.is_manager_or_owner()) OR public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: weekly_shift_plan_items weekly_shift_plan_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_shift_plan_delete ON public.weekly_shift_plan_items FOR DELETE TO authenticated USING (((store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))) AND (( SELECT (profiles.role)::text AS role
   FROM public.profiles
  WHERE (profiles.id = auth.uid())) = ANY (ARRAY['owner'::text, 'manager'::text]))));


--
-- Name: weekly_shift_plan_items weekly_shift_plan_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_shift_plan_insert ON public.weekly_shift_plan_items FOR INSERT TO authenticated WITH CHECK (((store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))) AND (( SELECT (profiles.role)::text AS role
   FROM public.profiles
  WHERE (profiles.id = auth.uid())) = ANY (ARRAY['owner'::text, 'manager'::text]))));


--
-- Name: weekly_shift_plan_items; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.weekly_shift_plan_items ENABLE ROW LEVEL SECURITY;

--
-- Name: weekly_shift_plan_items weekly_shift_plan_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_shift_plan_select ON public.weekly_shift_plan_items FOR SELECT TO authenticated USING (((store_id = ( SELECT p.store_id
   FROM public.profiles p
  WHERE (p.id = auth.uid()))) AND (public.is_owner() OR public.current_user_has_manager_permission('schedule_manage'::text))));


--
-- Name: weekly_shift_plan_items weekly_shift_plan_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY weekly_shift_plan_update ON public.weekly_shift_plan_items FOR UPDATE TO authenticated USING (((store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))) AND (( SELECT (profiles.role)::text AS role
   FROM public.profiles
  WHERE (profiles.id = auth.uid())) = ANY (ARRAY['owner'::text, 'manager'::text])))) WITH CHECK (((store_id = ( SELECT profiles.store_id
   FROM public.profiles
  WHERE (profiles.id = auth.uid()))) AND (( SELECT (profiles.role)::text AS role
   FROM public.profiles
  WHERE (profiles.id = auth.uid())) = ANY (ARRAY['owner'::text, 'manager'::text]))));


--
-- Name: work_schedules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.work_schedules ENABLE ROW LEVEL SECURITY;

--
-- Name: supabase_realtime; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime_messages_publication; Type: PUBLICATION; Schema: -; Owner: -
--

CREATE PUBLICATION supabase_realtime_messages_publication WITH (publish = 'insert, update, delete, truncate');


--
-- Name: supabase_realtime attendance; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.attendance;


--
-- Name: supabase_realtime shift_registration_recurring_rules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.shift_registration_recurring_rules;


--
-- Name: supabase_realtime shift_registration_windows; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.shift_registration_windows;


--
-- Name: supabase_realtime shift_registrations; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.shift_registrations;


--
-- Name: supabase_realtime shift_template_versions; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.shift_template_versions;


--
-- Name: supabase_realtime shift_templates; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.shift_templates;


--
-- Name: supabase_realtime work_schedules; Type: PUBLICATION TABLE; Schema: public; Owner: -
--

ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.work_schedules;


--
-- Name: supabase_realtime_messages_publication messages; Type: PUBLICATION TABLE; Schema: realtime; Owner: -
--

ALTER PUBLICATION supabase_realtime_messages_publication ADD TABLE ONLY realtime.messages;


--
-- Name: issue_graphql_placeholder; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_graphql_placeholder ON sql_drop
         WHEN TAG IN ('DROP EXTENSION')
   EXECUTE FUNCTION extensions.set_graphql_placeholder();


--
-- Name: issue_pg_cron_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_cron_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_cron_access();


--
-- Name: issue_pg_graphql_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_graphql_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_graphql_access();


--
-- Name: issue_pg_net_access; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER issue_pg_net_access ON ddl_command_end
         WHEN TAG IN ('CREATE EXTENSION')
   EXECUTE FUNCTION extensions.grant_pg_net_access();


--
-- Name: pgrst_ddl_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_ddl_watch ON ddl_command_end
   EXECUTE FUNCTION extensions.pgrst_ddl_watch();


--
-- Name: pgrst_drop_watch; Type: EVENT TRIGGER; Schema: -; Owner: -
--

CREATE EVENT TRIGGER pgrst_drop_watch ON sql_drop
   EXECUTE FUNCTION extensions.pgrst_drop_watch();


--
-- PostgreSQL database dump complete
--

\unrestrict V2qfbHKDNYYXBi3uuew3XjhfSd3ta4dkN3dEU5Lfov5rDVKpV51f91T0KsgyT2P

