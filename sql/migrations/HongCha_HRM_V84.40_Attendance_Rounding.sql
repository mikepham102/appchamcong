-- HongCha HRM V84.40 — Làm tròn phút khi chấm công
--
-- Vấn đề: check-in 07:30:0x + ca kết thúc 12:00 => giờ công 4h29p (mất 1 phút do giây lẻ).
-- Sửa:  check-in làm tròn LÊN phút (07:30:02 -> 07:31, trễ 1 phút)
--        check-out làm tròn XUỐNG phút (12:05:47 -> 12:05)
--        late_minutes / worked_minutes / early_leave_minutes tính từ giờ đã làm tròn
--        => số hiển thị trên app và số tính lương luôn khớp nhau.
-- Giữ nguyên: kiểm tra thiết bị, GPS, khung giờ, handoff ca liền kề, mức chốt tối đa
--             đến giờ kết thúc ca (V70). Bằng chứng giây thực tế vẫn nằm trong
--             public.attendance_events (event_at = giờ chấm thật).
-- Không sửa dữ liệu chấm công đã có.

BEGIN;

CREATE OR REPLACE FUNCTION public.attendance_punch(p_action text, p_device_key text, p_latitude double precision, p_longitude double precision, p_accuracy_m double precision DEFAULT NULL::double precision, p_schedule_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_in_at timestamptz;
  v_out_at timestamptz;
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

  -- V84.40: làm tròn theo phút để giờ hiển thị và giờ công luôn khớp nhau.
  --   check-in : 07:30:00 -> 07:30 ; 07:30:02 -> 07:31 (làm tròn LÊN)
  --   check-out: 12:05:47 -> 12:05                        (làm tròn XUỐNG)
  -- Giây thực tế vẫn được lưu nguyên vẹn trong public.attendance_events.
  v_in_at := (
    date_trunc('minute', v_now at time zone v_timezone)
    + case when extract(second from (v_now at time zone v_timezone)) > 0
           then interval '1 minute' else interval '0 minute' end
  ) at time zone v_timezone;
  v_out_at := date_trunc('minute', v_now at time zone v_timezone) at time zone v_timezone;

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
      0, floor(extract(epoch from (v_in_at - v_schedule.start_at)) / 60)::integer
    );
    if v_att.id is null then
      insert into public.attendance(
        schedule_id, employee_id, device_id, check_in, check_in_latitude,
        check_in_longitude, check_in_distance_m, check_in_status, late_minutes,
        check_in_device_key
      ) values (
        v_schedule.id, v_uid, v_device.id, v_in_at, p_latitude, p_longitude,
        v_distance,
        case when v_late > 0 then 'late'::public.attendance_status
             else 'valid'::public.attendance_status end,
        v_late, p_device_key
      ) returning * into v_att;
    else
      update public.attendance
      set device_id = v_device.id, check_in = v_in_at,
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
          least(v_out_at, v_schedule.end_at) - v_schedule.start_at
        )) / 60)::integer - coalesce(v_template.break_minutes, 0)
      )
    );
    v_early_leave := case when v_out_at < v_schedule.end_at
      then greatest(0, floor(extract(epoch from (v_schedule.end_at - v_out_at)) / 60)::integer)
      else 0 end;

    if v_att.id is null then
      insert into public.attendance(
        schedule_id, employee_id, device_id, check_in, check_out,
        check_in_latitude, check_in_longitude, check_in_distance_m,
        check_out_latitude, check_out_longitude, check_out_distance_m,
        check_in_status, check_out_status, late_minutes, early_leave_minutes,
        worked_minutes, check_in_device_key, check_out_device_key
      ) values (
        v_schedule.id, v_uid, v_device.id, v_schedule.start_at, v_out_at,
        p_latitude, p_longitude, v_distance, p_latitude, p_longitude, v_distance,
        'valid'::public.attendance_status, 'valid'::public.attendance_status,
        0, v_early_leave, v_worked, p_device_key, p_device_key
      ) returning * into v_att;
    else
      update public.attendance
      set device_id = v_device.id, check_in = v_schedule.start_at, check_out = v_out_at,
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
        least(v_out_at, v_schedule.end_at) - greatest(v_att.check_in, v_schedule.start_at)
      )) / 60)::integer - coalesce(v_template.break_minutes, 0)
    )
  );
  v_early_leave := case when v_out_at < v_schedule.end_at
    then greatest(0, floor(extract(epoch from (v_schedule.end_at - v_out_at)) / 60)::integer)
    else 0 end;
  update public.attendance
  set check_out = v_out_at, check_out_latitude = p_latitude,
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
$function$;


COMMIT;

-- ---------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY: da_ap_dung phải = true
-- ---------------------------------------------------------------------------
select p.proname,
       position('v_in_at' in coalesce(p.prosrc, '')) > 0 as da_ap_dung
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'attendance_punch';

