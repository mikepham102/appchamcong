-- HongCha HRM — KIỂM TRA VẬN HÀNH (CHỈ ĐỌC)
-- Chạy trong Supabase SQL Editor. Không sửa gì, không đọc dữ liệu lương/ngân hàng.
-- Mỗi câu chạy riêng, chụp màn hình kết quả gửi dev.

-- ============================================================
-- CÂU 1. Job tự chốt đăng ký ca có tồn tại và đang bật không?
-- Nếu báo lỗi "relation cron.job does not exist" => KHÔNG có job nào.
-- ============================================================
select jobid, schedule, command, active
from cron.job
order by jobid;

-- ============================================================
-- CÂU 2. 10 lần chạy gần nhất của các job (nếu có)
-- ============================================================
select jobid, status, return_message, start_time, end_time
from cron.job_run_details
order by start_time desc
limit 10;

-- ============================================================
-- CÂU 3. switch_active_store trên DB là bản cũ (chỉ Owner)
--        hay bản mới (cho Manager chuyển chi nhánh)?
-- Ket qua: has_manager_logic = true => bản mới đã áp dụng.
-- ============================================================
select p.proname,
       position('manager' in coalesce(p.prosrc, '')) > 0 as has_manager_logic,
       length(coalesce(p.prosrc, '')) as do_dai_body
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('switch_active_store', 'auto_finalize_due_shift_registrations')
order by p.proname;

-- ============================================================
-- CÂU 4. auto_finalize_due_shift_registrations đã được vá V84.30 chưa?
-- da_va_v8430 = true  => đã dùng biến conflict_id (bản đúng)
-- ============================================================
select p.proname,
       position('conflict_id :=' in coalesce(p.prosrc, '')) > 0 as da_va_v8430
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'auto_finalize_due_shift_registrations';
