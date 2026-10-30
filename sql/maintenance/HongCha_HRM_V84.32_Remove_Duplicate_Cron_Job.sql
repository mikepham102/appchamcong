-- HongCha HRM V84.32 — Xóa job cron trùng lặp (job 10 trùng job 9)
--
-- Hiện trạng (kiểm tra 30/10/2026): cron có 2 job cùng gọi
--   public.process_shift_registration_automation()
--     jobid 9  : */1 * * * *   (mỗi phút)
--     jobid 10 : * * * * *     (mỗi phút)  <= trùng
-- Hai job chạy song song mỗi phút. Không sai dữ liệu (bảng
-- shift_registration_windows có UNIQUE (store_id, week_start)), nhưng tốn tài nguyên
-- và gây tranh khóa.
--
-- Script này:
--   1. Kiểm tra job 9 và 10 có thật, cùng lệnh, job 9 đang bật.
--   2. Chỉ khi thỏa hết điều kiện mới bỏ job 10.
--   3. Nếu có bất kỳ điểm nào khác => DỪNG, không thay đổi gì.
--
-- Chạy trong Supabase SQL Editor. Chỉ tác động bảng nội bộ của pg_cron,
-- không đụng dữ liệu nghiệp vụ.

BEGIN;

DO $do$
DECLARE
  v_cmd9    text;
  v_cmd10   text;
  v_active9 boolean;
BEGIN
  SELECT command, active INTO v_cmd9, v_active9 FROM cron.job WHERE jobid = 9;
  SELECT command INTO v_cmd10 FROM cron.job WHERE jobid = 10;

  IF v_cmd9 IS NULL OR v_cmd10 IS NULL THEN
    RAISE NOTICE 'Khong tim thay job 9 hoac job 10 -> khong thay doi gi.';
    RETURN;
  END IF;

  IF v_active9 IS NOT TRUE THEN
    RAISE NOTICE 'Job 9 khong con active -> khong thay doi gi.';
    RETURN;
  END IF;

  IF regexp_replace(lower(v_cmd9), '\s+', '', 'g')
     <> regexp_replace(lower(v_cmd10), '\s+', '', 'g') THEN
    RAISE EXCEPTION 'Job 9 va job 10 KHONG cung lenh -> dung lai de tranh xoa nham.';
  END IF;

  PERFORM cron.unschedule(10);
  RAISE NOTICE 'Da xoa job 10 (trung job 9).';
END;
$do$;

COMMIT;

-- Kiểm tra sau khi chạy: phải còn đúng 1 job gọi process_shift_registration_automation
select jobid, schedule, command, active
from cron.job
order by jobid;
