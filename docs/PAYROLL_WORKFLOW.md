# Quy trình tab Lương — đánh giá theo chuẩn HRM

Cập nhật: 30/10/2026. Đối tượng: Owner, Manager, Employee.

## 1. Chuẩn HRM (7 bước)

| # | Bước | Mục đích | Ai làm |
|---|---|---|---|
| 1 | **Ghi nhận công** | Chấm công / bổ sung công / nghỉ phép | NV, Manager |
| 2 | **Chốt công kỳ** | Khoá dữ liệu công của kỳ, không cho sửa nữa | Owner |
| 3 | **Điều chỉnh** | Thưởng, phạt, tạm ứng — có duyệt | Manager/Owner |
| 4 | **Tính lương** | Sinh bảng lương (gross → net) | Owner |
| 5 | **Duyệt kỳ** | Owner xem lại, xác nhận số liệu | Owner |
| 6 | **Chi trả** | Đánh dấu đã trả + xuất file chuyển khoản | Owner |
| 7 | **Phiếu lương** | Nhân viên xem phiếu lương chính thức của kỳ | NV |

## 2. Hiện trạng của app

| Bước chuẩn | App hiện có | Đánh giá |
|---|---|---|
| 1. Ghi nhận công | Chấm công GPS + thiết bị, bổ sung công, nghỉ phép | ✅ Tốt, có audit |
| 2. Chốt công | **Không có** — vẫn sửa được công sau khi đã tính lương | ❌ Thiếu |
| 3. Điều chỉnh | Phiếu thưởng/phạt/tạm ứng có trạng thái chờ duyệt | ✅ Có, nay hiện theo ngày |
| 4. Tính lương | `owner_calculate_payroll` (gộp điều chỉnh + thưởng tự động + lễ) | ✅ Có |
| 5. Duyệt kỳ | `draft → review → paid → locked` | ✅ Có |
| 6. Chi trả | Xuất Excel có ngân hàng | ✅ Có |
| 7. Phiếu lương NV | **Không có** — NV chỉ thấy "lương tạm tính" từ chấm công | ❌ Thiếu |

### Hai khái niệm đang song song (dễ nhầm)

| Màn | Bản chất | Dùng khi nào |
|---|---|---|
| **Xem lương theo tháng** | Truy vấn trực tiếp, **không lưu** kỳ | Xem nhanh, ước tính |
| **Kỳ lương** | Bản ghi chính thức, có trạng thái, khoá sau khi trả | Trả lương thật |

→ Người dùng dễ tưởng số ở màn "xem theo tháng" là số chính thức. Cần ghi rõ nhãn "dự kiến / chưa chốt".

## 3. Khoảng trống cần xử lý (theo thứ tự ưu tiên)

### P1 — Phiếu lương cho nhân viên (quan trọng nhất)
- Nhân viên cần xem **phiếu lương chính thức** của kỳ đã tính: lương công, thưởng, phạt, tạm ứng, thực nhận.
- Nguồn: `payroll_runs` + `payroll_adjustments` của kỳ (RLS đã cho NV đọc của mình).
- Hiện NV chỉ thấy ước tính từ chấm công → dễ thắc mắc khi số chính thức khác.

### P2 — Chốt công trước khi tính lương
- Thêm bước "khoá công" cho kỳ: chặn bổ sung/sửa chấm công trong khoảng ngày của kỳ đã chốt.
- Tránh trường hợp: tính lương xong, sửa công, số liệu lệch mà không ai biết.

### P3 — Làm rõ 2 khái niệm báo cáo
- Đổi tên: "Báo cáo nhanh (chưa chốt)" và "Kỳ lương chính thức".
- Thêm nhãn trạng thái ở đầu mỗi màn.

### P4 — Manager xem kỳ lương
- Manager có `payroll_view` hiện chỉ thấy báo cáo tháng, chưa thấy danh sách kỳ đã chốt.
- Nên cho xem (chỉ đọc) để đối chiếu với nhân viên.

### P5 — Sao lưu & đối soát
- Mỗi lần "Tính lương" nên ghi `audit_logs` (ai tính, thời điểm, tổng tiền) để đối soát về sau.

## 4. Trạng thái hiển thị theo ngày (đã làm 30/10/2026)

- **Nhân viên:** danh sách ngày có chip `+ Thưởng`, `− Phạt`, `Chờ duyệt`; cột phải là **thực nhận ngày** = lương công + thưởng − phạt.
- **Owner/Manager (báo cáo tháng):** mỗi ngày hiện thêm dòng thưởng/phạt và số thực nhận; Excel sheet "Theo ngày" thêm 3 cột Thưởng / Phạt / Thực nhận ngày.
- Ngày chỉ có thưởng/phạt (không có ca) vẫn hiện trong danh sách.
- Phiếu không có `effective_date` được xếp theo **ngày tạo phiếu** để không bị mất khỏi báo cáo.

## 5. Lộ trình đề xuất

| Giai đoạn | Việc | Ảnh hưởng |
|---|---|---|
| A (đã xong) | Hiển thị thưởng/phạt theo ngày + Excel | Chỉ đọc |
| B | Phiếu lương chính thức cho NV | Frontend (dùng dữ liệu sẵn có) |
| C | Chốt công kỳ (khoá sửa công) | DB + frontend |
| D | Đổi tên/nhãn 2 màn báo cáo | Frontend |
| E | Manager xem kỳ lương + audit lần tính | Policy + frontend |
