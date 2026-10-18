# Prefab envelope library integration — 2026-10-18

The library's background frontage boundary previously copied block records and model transforms but omitted explicit attachment bounds. It now copies AABB values alongside the immutable authoring snapshots and validates them before native composition. Verified resource publication now compares attachment_envelope as well as records, attachments, name and metadata.

Capturing blocks plus models declares the entire selected local volume as the envelope. Native capture already requires included models to fit the selection. This preserves an overhang outside the occupied block cells. Block-only capture retains previous behavior. The conservative selected extent can enlarge subsequent site grading/protection; it is not automatic tight model-bound inference.

Targeted check captures one block plus an offset table into an isolated library, places the captured resource with rotation through NativePrefabPlacement, generates a frontage on the real library worker, compares its bounds/records/attachments with direct native composition, then opens both saved resources through a fresh library. All checks pass. Existing mixed-frontage generation and grading/paving test also passes. No user library or world save is touched; fixture files use unique user-data directories.

Reproduce: run_godot_check.py prefab_library_envelope --timeout 30 --require 'PREFAB_LIBRARY_ENVELOPE failures=0' --headless. Existing regression: frontage_async, require 'mixed frontage supports existing grading and paving planner'. This is editor integration correctness, not a graphical building-content or performance qualification. Water unchanged.
