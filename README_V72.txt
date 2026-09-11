HongCha HRM V72 – Employee Schedule Fix

V72 fixes the employee calendar data path.

Database:
- Run HongCha_HRM_V72_Employee_Schedule_Fix.sql once on the current Supabase database.
- The RPC get_employee_schedule_overview() is the authoritative employee-facing calendar source.
- Employees see all non-cancelled shifts in their store for the selected dates, including assigned employee name and phone.
- Attendance status of other employees is not returned.

Frontend:
- V72 no longer labels an RPC/load failure as “Ngày này chưa có lịch”.
- A real empty day is distinguished from a data-loading failure.
- Employee calendar header shows the total number of shifts in the selected day, not only the employee's own shifts.
- Existing shift registration and own-attendance status behavior is preserved.

Do not run the full one-run historical install SQL on an existing production database.
