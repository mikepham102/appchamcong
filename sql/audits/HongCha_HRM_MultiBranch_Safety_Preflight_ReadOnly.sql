-- HongCha HRM — KIỂM TRA AN TOÀN TRƯỚC KHI CHẠY MIGRATION ĐA CHI NHÁNH (CHỈ ĐỌC)
-- Chỉ trả về SỐ ĐẾM. Không đọc tên, số điện thoại, lương, tài khoản ngân hàng.
-- Chạy trong Supabase SQL Editor, gửi kết quả cho dev.
--
-- Vì sao cần: migration đa chi nhánh thay hàm current_user_has_manager_permission()
-- bằng bản YÊU CẦU manager phải có store_memberships active đúng chi nhánh.
-- Nếu dữ liệu hiện tại thiếu các dòng đó, Manager sẽ MẤT quyền sau khi chạy migration.

-- ============================================================
-- CÂU 1. Đếm mức độ an toàn
-- ============================================================
select
  (select count(*) from public.profiles
     where role = 'manager' and employment_status = 'active')                        as managers_active,
  (select count(*) from public.profiles
     where role = 'manager' and employment_status = 'active' and store_id is null)    as managers_no_store,
  (select count(*) from public.profiles p
     where p.role = 'manager' and p.employment_status = 'active'
       and exists (select 1 from public.store_memberships m
                    where m.user_id = p.id and m.store_id = p.store_id
                      and m.role = 'manager' and m.is_active))                        as managers_ok,
  (select count(*) from public.profiles p
     where p.role = 'manager' and p.employment_status = 'active'
       and not exists (select 1 from public.store_memberships m
                    where m.user_id = p.id and m.store_id = p.store_id
                      and m.role = 'manager' and m.is_active))                        as managers_would_lose_access,
  (select count(*) from public.profiles
     where role = 'owner' and employment_status = 'active')                           as owners_active,
  (select count(*) from public.profiles p
     where p.role = 'owner' and p.employment_status = 'active'
       and not exists (select 1 from public.store_memberships m
                    where m.user_id = p.id and m.store_id = p.store_id
                      and m.role = 'owner' and m.is_active))                          as owners_not_member,
  (select count(*) from public.store_memberships
     where is_active and role = 'manager')                                            as manager_memberships_active,
  (select count(*) from public.store_memberships
     where is_active and role = 'owner')                                              as owner_memberships_active,
  (select count(*) from public.stores)                                                as stores_total;

-- ============================================================
-- CÂU 2. Manager nào đã có nhiều hơn 1 chi nhánh active? (đếm theo số chi nhánh)
-- Ket qua: neu co dong "2" hoac "3" => da co nguoi duoc gan nhieu chi nhanh tay.
-- ============================================================
select so_chi_nhanh, count(*) as so_nguoi
from (
  select m.user_id, count(*) as so_chi_nhanh
  from public.store_memberships m
  join public.profiles p on p.id = m.user_id
  where p.role = 'manager' and p.employment_status = 'active'
    and m.role = 'manager' and m.is_active
  group by m.user_id
) x
group by so_chi_nhanh
order by so_chi_nhanh;

-- ============================================================
-- CÂU 3. Có dòng membership trùng/inactive bất thường không?
-- ============================================================
select
  (select count(*) from public.store_memberships where is_active = false)             as memberships_inactive,
  (select count(*) from public.store_memberships m
     join public.profiles p on p.id = m.user_id
     where m.is_active and m.store_id = p.store_id and m.role <> p.role)              as role_lech_profile,
  (select count(*) from public.profiles p
     where p.employment_status = 'active' and p.store_id is not null
       and not exists (select 1 from public.store_memberships m
                        where m.user_id = p.id and m.store_id = p.store_id
                          and m.is_active))                                       as active_user_thieu_membership;
