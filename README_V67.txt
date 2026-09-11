HongCha HRM V67 — Attendance Fix

Based on V66.
- Fixes attendance_punch enum/text mismatch for check-in/check-out status.
- After an RPC error, the employee UI verifies whether an attendance row was actually recorded and says so explicitly.
- No business-rule, permission, payroll, or schedule logic changes.

Database:
Run HongCha_HRM_V67_Attendance_Fix.sql once on the existing Supabase database.
