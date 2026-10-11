# Chest/vehicle interaction priority — 2026-10-11

The normal E dispatcher previously offered nearby vehicle entry before picking
an aimed chest. An enterable car beside a chest could therefore take the action.
The dispatcher now offers the reachable aimed chest first, then normal vehicle
entry. Existing editor selection and ground-cover interaction modes retain E.

The main-world storage fixture temporarily installs an entry probe (always accepts
entry) during two synchronous E calls. Actual world input, actual chest collision
picking and actual storage UI run unchanged. No frame runs with the probe installed.
This isolates dispatch priority, not car physics, visibility or driving behavior.

Before: 20 create checks, two failures. The first proves chest priority was wrong;
the second was the cumulative entry counter (2 rather than 1), so is not a second
independent defect. The final fixture resets the counter before testing fallback.
After: 20 create + 20 fresh-process reopen checks pass; the original storage
save/reload, transfer, reach, occlusion and deletion checks also pass. Both runs use
fullscreen 1920x1080 with cap60 and disposable test save slots. No native rebuild or
user save changes. This is short correctness coverage, not performance acceptance.

Reproduce: `python tools/check_storage_world.py`.
