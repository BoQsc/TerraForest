<!-- SPDX-License-Identifier: CC0-1.0 -->
# Startup audit evidence

`audit.json` is original AI-assisted diagnostic output, CC0-1.0, collected on
2026-11-02 from local TerraForest reports and an existing save. The audit script
and tests are original 0BSD code. No third-party implementation or asset was
imported. Source code and prior evidence retain their existing terms.
`provenance.json` records the inspected source hashes, checkout revision and
diagnostic verification scope; the checkout contained concurrent runtime edits.

The four generation report IDs are preserved inside the JSON. Their source is
`%APPDATA%/Godot/app_userdata/TerraForest/generation_reports/<id>/run.json`, plus
`earthworks_bake.json`, `generated_lakes_bake.json` and `photograph_timings.json`.
The input run hashes are recorded. Existing timing schema 1 loses later stages;
the audit exposes this as unaccounted time rather than inventing attribution.

The loading receipt is `reports/menu_transition/20261102T144641939776Z/latency.json`;
its source hash is recorded. It belongs to the previously verified installed pack
`5b8c7c63...638920`, not a new measurement of this working tree. Warm OS/plan caches,
offscreen Forward+, 1920x1080, 60 FPS and the harness's `--no-zombies` restriction
apply. Phase sums include yielding and boundary frames.

Storage reads target Emerald_Meadow. The root's SHA-256 is checked before/after;
its outer container digest also passes. This is not an exclusive snapshot of every
sidecar file or validation of every native component schema. Counts are logical
file lengths, not filesystem allocated sizes or proof that old checkpoints can
be deleted. No save, cache or report source was changed.

The optional compression experiment uses Python's installed zlib runtime only
in memory; it does not install a codec or change the world format. Times are
single local samples and vary with machine load. Both outputs roundtrip exactly.

Reproduce from the repository root (PowerShell):

```powershell
python TerraForest/tools/audit_world_startup.py --slot Emerald_Meadow --compression-experiment --report-id 866836a85c1cbd8345e78a18748f5975 --report-id 1b35464f949fc30ee81ad45db82df40f --report-id 6bad3582193b7fc14d22e8df1205c235 --report-id 69811f0aaa20f709b768e1eb67b6af81 --loading-report TerraForest/reports/menu_transition/20261102T144641939776Z/latency.json
python -m unittest discover -s TerraForest/tools -p test_audit_world_startup.py -v
```

Run `tests/generation_progress.gd` with the existing Godot executable in headless
mode. Result: `GENERATION_PROGRESS failures=0`; six Python tests pass. The test
creates and removes only its uniquely named progress JSON, never a world.
Its UID was generated with Godot's ResourceUID API. No native build/export ran.

For follow-up, collect a complete new trace after exporting the telemetry fix.
Use repeated source and package runs, record build/native hashes, cache state,
world identity, worker limits and concurrent load, and distinguish first play
from later background completion. Existing measurements do not qualify broader
seeds, larger worlds, foreground smoothness or a performance improvement.
