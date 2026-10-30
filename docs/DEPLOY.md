# Hướng dẫn triển khai (deploy) — HongCha HRM

Thay thế `DEPLOY_README.txt` (nội dung cũ chỉ đúng cho V66).

## 1. Thông tin môi trường

| Thành phần | Giá trị |
|---|---|
| Trang đang chạy | https://mikepham102.github.io/appchamcong/ |
| Repo | https://github.com/mikepham102/appchamcong |
| Nhánh phát hành | `main` (GitHub Pages publish từ thư mục gốc) |
| Backend | Supabase project `qwrcjxicudxlspxqfjkj` (Postgres + Auth + RLS + RPC) |
| Múi giờ nghiệp vụ | `Asia/Ho_Chi_Minh` |

## 2. Bộ file bắt buộc phải có trên host

```
index.html                 ← toàn bộ ứng dụng (bắt buộc)
manifest.webmanifest       ← để cài app ra màn hình chính (bắt buộc)
icons/apple-touch-icon.png ← icon iPhone
icons/icon-192.png
icons/icon-512.png
icons/icon-512-maskable.png
```

Thiếu `manifest.webmanifest` hoặc `icons/` thì app vẫn chạy nhưng **không cài được PWA** và icon bị trắng.
Không có Service Worker (`sw.js`) → không có cache offline; đây là chủ ý hiện tại.

## 3. Quy trình phát hành frontend (6 bước)

1. Sửa `index.html` (hoặc nhận file mới từ dev) — **luôn giữ bản cũ**: git đã lưu, không cần copy thủ công.
2. Commit với tiêu đề theo mẫu: `V84.31: <mô tả ngắn>`.
3. Đặt tag phiên bản: `git tag v84.31 && git push --tags` (mốc để quay lui).
4. `git push origin main` → GitHub Pages tự build, thường xong sau 1–2 phút.
5. Kiểm tra 3 URL trả `HTTP 200`:
   `index.html`, `manifest.webmanifest`, `icons/apple-touch-icon.png`.
6. Mở app, **hard refresh** (Ctrl/Cmd + Shift + R), đăng nhập thử 1 tài khoản mỗi vai trò.

## 4. Quay lui (rollback) khi bản mới lỗi

```bash
git log --oneline -10                       # tìm commit tốt gần nhất
git revert <commit_lỗi>                     # tạo commit đảo ngược (an toàn, giữ lịch sử)
git push origin main
```
Khôi phục nhanh 1 file từ mốc cũ:
```bash
git checkout <commit_tốt> -- index.html && git commit -m "rollback index.html" && git push
```

## 5. Quy tắc bắt buộc khi sửa database (Supabase)

> Gói Supabase **Free không có backup tự động**. Quy trình thay thế ở mục 5b.

1. **Chỉ thêm, không phá**: `CREATE TABLE IF NOT EXISTS`, `CREATE OR REPLACE FUNCTION`, `ADD COLUMN` (có default), `CREATE INDEX`.
   **Cấm**: `DROP TABLE/COLUMN`, `ALTER TYPE`, `TRUNCATE`, `DELETE`/`UPDATE` dữ liệu nghiệp vụ.
2. Mỗi file SQL phải: bọc `BEGIN; … COMMIT;`, có block `DO $preflight$` kiểm tra bảng/hàm phụ thuộc tồn tại, chạy lại lần 2 không lỗi (idempotent).
3. **Sao lưu trước** (xem mục 5b).
4. Chạy trong **giờ thấp điểm** (sau 22:00) và thông báo trước cho cửa hàng.
5. Hàm `SECURITY DEFINER` phải có `SET search_path TO 'public'` và `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated;`
6. Sau khi chạy: kiểm tra lại bằng script trong `sql/audits/` (chỉ đọc) + test tay 3 vai trò.
7. Lưu file migration vào `sql/migrations/` và commit — **không để SQL chỉ nằm trong Supabase SQL Editor**.

### 5b. Khi không có backup (gói Free)

**Nguyên tắc:** biết chính xác migration sửa gì trước khi lo backup.

- Migration **chỉ sửa cấu trúc/hàm** (không INSERT/UPDATE/DELETE dữ liệu) → thứ cần khôi phục chỉ là **định nghĩa hàm cũ**, không phải dữ liệu.
- Quy trình 5 bước:
  1. Chạy `sql/audits/HongCha_HRM_PreMigration_Snapshot_ReadOnly.sql` → Download CSV → lưu `sql/snapshots/premig_<phiên bản>_<ngày>.csv` (gồm **số dòng từng bảng** + **định nghĩa 4 hàm sắp thay**).
  2. Chạy migration (đã có `BEGIN/COMMIT` + `preflight`).
  3. Chạy lại đúng script đó → lưu `..._after.csv`.
  4. So 2 file: số dòng từng bảng phải **giống hệt**.
  5. Nếu sai → chạy file rollback tương ứng trong `sql/rollback/`.
- **Nếu vẫn muốn backup toàn bộ dữ liệu:** cài PostgreSQL client rồi dump:
  ```bash
  brew install libpq
  export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
  pg_dump "postgresql://postgres:<MẬT_KHẨU_DB>@db.qwrcjxicudxlspxqfjkj.supabase.co:5432/postgres" \
          -Fc -f ~/hongcha_backup_$(date +%Y%m%d).dump
  ```
  (mật khẩu: Supabase → Project Settings → Database → Reset database password)
  File `.dump` phải lưu **ngoài repo GitHub** — có dữ liệu lương/ngân hàng.


## 6. Những việc KHÔNG được làm

- Không chạy lại bộ "COMPLETE ONE RUN" (cài đặt từ đầu) trên database đang có dữ liệu.
- Không sửa `index.html` trên GitHub web mà không ghi chú phiên bản (dễ mất dấu).
- Không đổi cấu trúc DB và frontend trong cùng một lần phát hành (khó xác định nguyên nhân khi lỗi).
- Không đổi `profiles.store_id` trực tiếp bằng tay — phải qua `switch_active_store` / `transfer_employee_branch`.

## 7. Kiểm tra sức khỏe sau mỗi lần phát hành

| Hạng mục | Cách kiểm tra |
|---|---|
| Trang tải được | Mở URL, thấy màn hình đăng nhập |
| Đăng nhập 3 vai trò | Owner / Manager / Employee |
| Chấm công | 1 nhân viên check-in → check-out (dùng tài khoản test nếu có) |
| Lịch | Đổi ngày/tuần, thấy ca đúng chi nhánh |
| Lương | Mở báo cáo kỳ lương, số liệu không đổi bất thường |
| Tự chốt đăng ký ca | Xem `audit_logs` có bản ghi `auto_finalize_shift_registrations` đúng tuần |
