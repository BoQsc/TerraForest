# Populated combined gameplay route — 2026-10-18

Ran the existing three-process gather/build/store/walk/drive/reopen check against a unique clone of populated_review_20261016. Source hash remained unchanged (run.json). This uses the eight-building furnished mixed settlement with two native patrol residents, doors/windows, roads and ground cover.

Five natural stones gathered through E, two spent through crafting for a brick, paid right-click placement, chest deposit/withdraw and deletion protection passed. Normal player movement traversed the cottage aisle, door and stairs; normal vehicle inputs drove 12.02 m and reversed/stopped within 2.55 m of departure. Walking returned through the door and stairs. No pose correction during travel. Resource setup uses fixture positioning and freezes unrelated gameplay; travel runs ordinary world simulation.

Added assertions retain both resident identities and patrol orders throughout travel and require at least one resident position to change by more than 0.25 m. Exact post-travel actor positions/identities and patrol endpoints/current legs are captured with simulation frozen for the save boundary. A fresh process verifies those bytes alongside earned inventory, collected identities, chest contents, placed brick and doors. This checks mixed lifecycle integration, not every actor completing its patrol (separately covered in settlement_population).

The first fixture failed because freezing physics before load completion left streaming focus at its startup height, so the test's candidate distance filter rejected nearby stones. Explicitly focusing the frozen fixture on the restored player corrected this; no gameplay relaxation was made. The rejected log is retained.

All three functional phases pass at configured fullscreen1920x1080, cap60. This is NOT a performance pass: reopen logs include a 1388.89 ms world-process startup hitch, and prior terrain arrival/endurance/thermal limits remain open. Do not infer sustained FPS from these checks. Water unchanged. Reproduce: `python tools/run_combined_resource_route.py --source populated_review_20261016` (or another suitable untouched prepared save).
