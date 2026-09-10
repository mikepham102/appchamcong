HongCha HRM V62 – Owner Attendance Supplement Position

UI-only adjustment based on the current payroll/app baseline.
- Owner attendance: the “Bổ sung” action remains only beside the shift title.
- Removed the duplicate “Bổ sung” button from the employee row below.
- Existing “Điều chỉnh” action remains available for an employee who already has check-in data.
- Existing “Xác nhận checkout” action remains unchanged.
- No database schema, permissions, attendance rules, payroll logic, or other business logic changed.

Deploy: upload the contents of this folder to the GitHub Pages publishing root, with index.html at root.

V63: Nếu bấm Tạo kỳ lương nhưng kỳ đó đã tồn tại (KY_LUONG_DA_TON_TAI), app sẽ tự mở báo cáo của kỳ lương hiện có thay vì chỉ báo lỗi.
QUAN TRỌNG: index.html nằm ngay thư mục gốc của gói để upload trực tiếp lên GitHub Pages.


V64 DESIGN DIRECTOR UI
- UI/UX-only visual pass for Owner and Employee screens.
- Schedule and Owner attendance shift rows now use clearer hierarchy, subtle accent rails, title/time styling, and semantic status chips.
- Improved mobile density and scanability.
- Refined Home, Attendance, Salary, Admin, forms, cards, buttons, and calendar surfaces.
- No database, RPC, permissions, business rules, or data logic changed.
- Upload the contents of this package so index.html is at repository root.
