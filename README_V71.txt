HongCha HRM V71 – Employee Home Shift Summary

Based on V70.
UI/UX + employee home dashboard only; no database migration required.
Employee home now shows:
- If today has assigned shifts: “Hôm nay bạn có ca” with every assigned shift name and time.
- If today has no assigned shift: “Hôm nay bạn không có ca làm” and the nearest upcoming assigned shift with name, time and date.
- Shift names are resolved from shift_template_id; no attendance status of other employees is exposed.

Deploy: replace index.html at the root of GitHub Pages. Keep manifest/icons as before.
