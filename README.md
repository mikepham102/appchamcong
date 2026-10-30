# HongCha HRM

Hệ thống quản lý nhân sự · chấm công · lương cho chuỗi quán HongCha.

- **Ứng dụng:** https://mikepham102.github.io/appchamcong/ (GitHub Pages, nhánh `main`)
- **Backend:** Supabase (Postgres + Auth + RLS + RPC + Realtime + pg_cron)
- **Phiên bản hiện tại:** V84.30

## Tài liệu

| File | Nội dung |
|---|---|
| [docs/PROJECT.md](docs/PROJECT.md) | Bản đồ dự án: kiến trúc, vai trò, bảng dữ liệu, luồng nghiệp vụ, vấn đề đã biết |
| [docs/DEPLOY.md](docs/DEPLOY.md) | Quy trình phát hành, quay lui, quy tắc sửa database |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Lịch sử phát triển V65 → V84.30 |
| [sql/README.md](sql/README.md) | Danh sách migration, script kiểm toán chỉ đọc, ảnh chụp cấu trúc DB |

## File triển khai

`index.html` + `manifest.webmanifest` + `icons/` — đặt ở thư mục gốc của repo để GitHub Pages phục vụ.

## Nguyên tắc

1. Database đang có dữ liệu thật của cửa hàng — mọi thay đổi phải **chỉ thêm, không phá**.
2. Mỗi lần phát hành đều gắn tag phiên bản để quay lui được.
3. Không chạy bộ SQL "cài đặt từ đầu" trên database đang có dữ liệu.
