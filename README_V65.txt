HongCha HRM V65

V65 adds effective-date rules for shift and salary changes.
- Shift template changes have an effective date.
- Future work schedules linked to that template synchronize from the effective date.
- A schedule that has started or has attendance check-in is never rewritten.
- Salary changes have an effective date.
- Payroll calculates the hourly rate by the work date, so a future salary change does not affect earlier work.

Deployment:
1. Upload index.html and manifest/icons to the GitHub Pages root.
2. For an EXISTING production database, run only 02_DATABASE_SQL/02_V65_Effective_Date.sql in Supabase SQL Editor.
3. For a NEW/EMPTY database, use 01_HONGCHA_HRM_V65_COMPLETE_ONE_RUN.sql instead of historical migrations.
