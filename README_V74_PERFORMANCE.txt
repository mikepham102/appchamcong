HongCha HRM V74 · Performance & Data Loading Pass

BASELINE: V73
SCOPE: Performance/data-loading only. No new business feature and no intended change to permissions, attendance rules, payroll rules, schedule rules, effective dates, or employee-calendar behavior.

AUDIT RESULT
1. LOGIN
   Previous: after authentication, loadApp waited for profile/device and then multiple employee/owner data loads sequentially before finishing boot.
   Fixed: show the app shell immediately after required profile/device gate; load only the currently active screen's data afterward.
   Result: login no longer waits for unrelated screens (salary/history/full schedule/admin employee list).

2. EMPLOYEE HOME
   Previous: initial render could trigger duplicate schedule/home loads through renderRoleUI -> navigate -> loadApp.
   Fixed: deferred initial navigation; active view loads once. Attendance state can refresh the home summary in the background.
   Result: removed duplicate initial data work.

3. OPEN SCHEDULE
   Previous: duplicate initial loads were possible during login/restore.
   Fixed: one active-view load; weekly employee schedule already uses a 20s client cache and parallel first-stage requests.
   Result: fewer requests and fewer loading states.

4. CHANGE DAY/WEEK
   Fixed: selected day inside a cached 7-day window renders locally; only a new week needs network data. Existing next-week prefetch remains non-blocking.
   Result: day switching should be effectively local; week switching remains network-bound only when uncached.

5. OPEN ATTENDANCE
   Previous: attendance screen starts state/history/device/GPS work together, but initial boot could also duplicate these.
   Fixed: state/history/device are parallel; GPS is explicitly non-blocking and no longer delays the active-view completion.
   Result: screen does not wait for geolocation before being considered loaded.

6. SAVE ACTIONS
   Fixed: successful attendance punch, shift registration/withdrawal, template save, direct schedule creation, and registration review no longer block UI on full refresh chains. Refreshes continue in background using Promise.allSettled where safe.
   Result: user gets immediate success feedback after the authoritative write returns.

NETWORK / HOSTING / DATABASE CONCLUSION
- GitHub Pages is not the main source of the 1s+ delay for in-app actions after the HTML is loaded. Those actions primarily use JavaScript + Supabase.
- The largest confirmed bottleneck in V73 was frontend orchestration: duplicate loads and sequential post-write refreshes.
- Supabase/network latency can still contribute to the remaining time because login, uncached weeks, attendance state, and writes require network round trips.
- No database/RPC migration is required for V74. The existing RPC/schema are retained.
- V74 adds only lightweight console timing markers for app-shell/active-view readiness; no user-facing feature.

VALIDATION
- JavaScript extracted from index.html and checked with Node.js v22: PASS.
- Package contains index.html at root, manifest, icons, and this report.
