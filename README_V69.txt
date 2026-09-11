HongCha HRM V69
- Fix employee attendance state after early check-in.
- Early check-in remains recorded against the exact assigned shift.
- Before scheduled start: status = Đã check-in sớm; checkout is disabled.
- From scheduled start: status = Đang làm việc; checkout is enabled.
- Prevents checkout before shift start at database level.
- Preserves all prior V65 effective-date, V66 UI, V67 attendance enum, and V68 template-save fixes.
