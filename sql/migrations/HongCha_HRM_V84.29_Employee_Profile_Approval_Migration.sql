-- Employee profile change approval workflow (additive; does not touch attendance or schedules)
begin;

create table if not exists public.employee_profile_change_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  store_id uuid not null references public.stores(id) on delete restrict,
  full_name text not null,
  phone text not null,
  address text not null,
  bank_name text,
  account_number text,
  account_holder text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  review_note text,
  created_at timestamptz not null default now(),
  constraint employee_profile_change_bank_complete check (
    (coalesce(bank_name,'')='' and coalesce(account_number,'')='' and coalesce(account_holder,'')='')
    or (nullif(trim(bank_name),'') is not null and nullif(trim(account_number),'') is not null and nullif(trim(account_holder),'') is not null)
  )
);

create unique index if not exists employee_profile_change_one_pending_per_employee
  on public.employee_profile_change_requests(employee_id) where status='pending';
create index if not exists employee_profile_change_owner_queue
  on public.employee_profile_change_requests(store_id,created_at desc) where status='pending';


create or replace function public.guard_employee_profile_self_update()
returns trigger language plpgsql
set search_path=public,pg_temp
as $$
begin
  if old.role::text='employee' and auth.uid()=old.id then
    if new.email is distinct from old.email then raise exception 'EMPLOYEE_EMAIL_CHANGE_NOT_ALLOWED'; end if;
    if nullif(trim(old.full_name),'') is not null
       and nullif(trim(old.phone),'') is not null
       and nullif(trim(old.address),'') is not null
       and (new.full_name is distinct from old.full_name or new.phone is distinct from old.phone or new.address is distinct from old.address) then
      raise exception 'PROFILE_CHANGE_APPROVAL_REQUIRED';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists guard_employee_profile_self_update on public.profiles;
create trigger guard_employee_profile_self_update
before update on public.profiles
for each row execute function public.guard_employee_profile_self_update();

create or replace function public.guard_employee_bank_self_update()
returns trigger language plpgsql
set search_path=public,pg_temp
as $$
declare
  v_employee_id uuid;
  v_complete boolean;
begin
  v_employee_id:=case when tg_op='DELETE' then old.employee_id else new.employee_id end;
  if auth.uid()=v_employee_id then
    select (nullif(trim(full_name),'') is not null and nullif(trim(phone),'') is not null and nullif(trim(address),'') is not null)
      into v_complete from public.profiles where id=v_employee_id and role::text='employee';
    if coalesce(v_complete,false) then raise exception 'PROFILE_CHANGE_APPROVAL_REQUIRED'; end if;
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;

drop trigger if exists guard_employee_bank_self_update on public.employee_bank_accounts;
create trigger guard_employee_bank_self_update
before insert or update or delete on public.employee_bank_accounts
for each row execute function public.guard_employee_bank_self_update();

create or replace function public.complete_my_employee_profile(
  p_full_name text,p_phone text,p_address text,
  p_bank_name text default null,p_account_number text default null,p_account_holder text default null
) returns jsonb
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare v_profile public.profiles%rowtype;
begin
  select * into v_profile from public.profiles
  where id=auth.uid() and role::text='employee' and store_id is not null
  for update;
  if not found then raise exception 'EMPLOYEE_PROFILE_REQUIRED'; end if;
  if nullif(trim(v_profile.full_name),'') is not null
     and nullif(trim(v_profile.phone),'') is not null
     and nullif(trim(v_profile.address),'') is not null then
    raise exception 'PROFILE_ALREADY_COMPLETE';
  end if;
  if nullif(trim(p_full_name),'') is null or nullif(trim(p_phone),'') is null or nullif(trim(p_address),'') is null then
    raise exception 'PROFILE_FIELDS_REQUIRED';
  end if;
  if (coalesce(trim(p_bank_name),'')='' and coalesce(trim(p_account_number),'')='' and coalesce(trim(p_account_holder),'')='') then
    null;
  elsif nullif(trim(p_bank_name),'') is null or nullif(trim(p_account_number),'') is null or nullif(trim(p_account_holder),'') is null then
    raise exception 'BANK_FIELDS_INCOMPLETE';
  else
    insert into public.employee_bank_accounts(employee_id,bank_name,account_number,account_holder)
    values(auth.uid(),trim(p_bank_name),trim(p_account_number),trim(p_account_holder))
    on conflict(employee_id) do update set bank_name=excluded.bank_name,account_number=excluded.account_number,account_holder=excluded.account_holder;
  end if;
  update public.profiles set full_name=trim(p_full_name),phone=trim(p_phone),address=trim(p_address) where id=auth.uid();
  return jsonb_build_object('status','complete');
end;
$$;

revoke all on function public.complete_my_employee_profile(text,text,text,text,text,text) from public,anon;
grant execute on function public.complete_my_employee_profile(text,text,text,text,text,text) to authenticated;

alter table public.employee_profile_change_requests enable row level security;
revoke all on public.employee_profile_change_requests from anon, authenticated;
grant select on public.employee_profile_change_requests to authenticated;

drop policy if exists employee_profile_change_read_self_or_owner on public.employee_profile_change_requests;
create policy employee_profile_change_read_self_or_owner
on public.employee_profile_change_requests for select to authenticated
using (employee_id=auth.uid() or public.is_store_owner(store_id));

create or replace function public.request_employee_profile_change(
  p_full_name text,
  p_phone text,
  p_address text,
  p_bank_name text default null,
  p_account_number text default null,
  p_account_holder text default null
) returns jsonb
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
  v_store_id uuid;
  v_id uuid;
begin
  select store_id into v_store_id
  from public.profiles
  where id=auth.uid() and role::text='employee' and store_id is not null;

  if not found then raise exception 'EMPLOYEE_PROFILE_REQUIRED'; end if;
  if nullif(trim(p_full_name),'') is null or nullif(trim(p_phone),'') is null or nullif(trim(p_address),'') is null then
    raise exception 'PROFILE_FIELDS_REQUIRED';
  end if;
  if (coalesce(trim(p_bank_name),'')='' and coalesce(trim(p_account_number),'')='' and coalesce(trim(p_account_holder),'')='')
     then null;
  elsif nullif(trim(p_bank_name),'') is null or nullif(trim(p_account_number),'') is null or nullif(trim(p_account_holder),'') is null then
    raise exception 'BANK_FIELDS_INCOMPLETE';
  end if;

  insert into public.employee_profile_change_requests(
    employee_id,store_id,full_name,phone,address,bank_name,account_number,account_holder
  ) values (
    auth.uid(),v_store_id,trim(p_full_name),trim(p_phone),trim(p_address),
    nullif(trim(p_bank_name),''),nullif(trim(p_account_number),''),nullif(trim(p_account_holder),'')
  ) returning id into v_id;

  return jsonb_build_object('id',v_id,'status','pending');
exception when unique_violation then
  raise exception 'PROFILE_CHANGE_PENDING';
end;
$$;

create or replace function public.owner_review_employee_profile_change(
  p_request_id uuid,
  p_approve boolean,
  p_note text default null
) returns jsonb
language plpgsql security definer
set search_path=public,pg_temp
as $$
declare
  v_request public.employee_profile_change_requests%rowtype;
  v_employee_store_id uuid;
begin
  if not exists(select 1 from public.profiles where id=auth.uid() and role::text='owner') then
    raise exception 'OWNER_REQUIRED';
  end if;

  select * into v_request
  from public.employee_profile_change_requests
  where id=p_request_id and status='pending'
  for update;

  if not found then raise exception 'PROFILE_REQUEST_NOT_PENDING'; end if;
  if not public.is_store_owner(v_request.store_id) then raise exception 'BRANCH_ACCESS_DENIED'; end if;
  select store_id into v_employee_store_id from public.profiles where id=v_request.employee_id and role::text='employee';
  if not found or v_employee_store_id is distinct from v_request.store_id then raise exception 'EMPLOYEE_BRANCH_CHANGED'; end if;

  if p_approve then
    update public.profiles
    set full_name=v_request.full_name,phone=v_request.phone,address=v_request.address
    where id=v_request.employee_id and role::text='employee';

    if v_request.bank_name is not null then
      insert into public.employee_bank_accounts(employee_id,bank_name,account_number,account_holder)
      values(v_request.employee_id,v_request.bank_name,v_request.account_number,v_request.account_holder)
      on conflict(employee_id) do update
      set bank_name=excluded.bank_name,account_number=excluded.account_number,account_holder=excluded.account_holder;
    end if;
  end if;

  update public.employee_profile_change_requests
  set status=case when p_approve then 'approved' else 'rejected' end,
      reviewed_by=auth.uid(),reviewed_at=now(),review_note=nullif(trim(p_note),'')
  where id=v_request.id;

  return jsonb_build_object('id',v_request.id,'status',case when p_approve then 'approved' else 'rejected' end);
end;
$$;

revoke all on function public.request_employee_profile_change(text,text,text,text,text,text) from public,anon;
grant execute on function public.request_employee_profile_change(text,text,text,text,text,text) to authenticated;
revoke all on function public.owner_review_employee_profile_change(uuid,boolean,text) from public,anon;
grant execute on function public.owner_review_employee_profile_change(uuid,boolean,text) to authenticated;

commit;
