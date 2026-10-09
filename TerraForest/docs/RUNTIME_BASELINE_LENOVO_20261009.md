# New-host runtime baseline, 2026-10-09

Reference revision: `d8cd97a7d13190353171bc23eb36ceaee0c5c083`.
Git label: `baseline/lenovo-rtx4050-20261009` (a measured reference, not a
"last good" or release-qualified declaration).
Raw evidence: [reference result](evidence/runtime_baseline_lenovo_20261009/reference/result.json),
[manifest](evidence/runtime_baseline_lenovo_20261009/reference/manifest.json),
[frame samples](evidence/runtime_baseline_lenovo_20261009/reference/world.frames.csv),
[device aggregates](evidence/runtime_baseline_lenovo_20261009/reference/aggregates.json).

This establishes the runtime reference that was missing from the earlier
hardware inventory. It includes the already completed foundation work; it is
not a retroactive before-measurement for those changes. No comparison with the
old GTX 1060 Max-Q laptop is treated as a software speedup.

## Conditions

- Lenovo 82XV; i5-12450H; RTX 4050 Laptop GPU; 16 GiB RAM; NVIDIA driver 617.14.
- Godot 4.7.2.stable.steam.ed1daf0bf; Vulkan Forward+; project-native DLL variants
  selected by the development project. Exact engine, command and DLL hashes are
  retained in the manifest. This is not an exported-release executable benchmark.
- Actual sampled presentation: 1920x1080 fullscreen, 100% render scale, VSync
  enabled, 60 Hz display, 60 FPS cap and focused window throughout measured samples.
- AC connected throughout; Windows Balanced plan. The user's settings were not
  changed. Lenovo thermal mode and Windows power-mode overlay remain unknown.
- Temporary generator-1 world, seed 1703; eight existing scripted camera/workload
  phases, each with three seconds warmup and five seconds measurement.
- Fresh, isolated derived-terrain cache. Existing engine shader/import caches
  remain warm. The earlier run using the existing terrain cache is retained under
  `preliminary/` but is not the reference for subsequent comparisons.
- Reference duration: 90.98 seconds including startup/transitions; 2,406 measured
  frames. Phase transitions/startup waits are outside the measured frame CSV.

## Observations

| Phase | Mean FPS | Frame p95, ms | Frame p99, ms | GPU median, ms |
| --- | ---: | ---: | ---: | ---: |
| Display-only control | 60.05 | 19.16 | 19.51 | 5.27 |
| Moving surface | 60.04 | 19.22 | 19.83 | 5.04 |
| Underground | 60.04 | 19.75 | 20.16 | 5.47 |
| Construction proof | 60.03 | 19.72 | 20.17 | 4.62 |
| Before digging | 60.02 | 19.86 | 20.50 | 5.72 |
| Continuous digging | 60.04 | 22.49 | 25.41 | 5.71 |
| After digging | 60.03 | 19.97 | 20.59 | 5.73 |
| Whole-map view | 60.03 | 18.90 | 19.22 | 5.46 |

The maximum measured frame was 25.98 ms. Continuous digging published 30 edits
in its five-second measurement, with 36.04 ms p95 edit-to-publication latency.
These results do not cover far-away arrival followed by extended mining, or
establish that every edit changed visible geometry; the dedicated mining
diagnostic remains the appropriate check for that behavior.

82 whole-device GPU samples over the full run recorded 9.67 W median, 16.19 W
p95 and 19.32 W peak power; temperature ranged from 40 to 42 C. Median device
utilization was 37%, illustrating why utilization alone is not a heat/power
measurement. Other applications and Windows presentation are included in these
device readings. CPU package temperature and CPU power were not measured.

Godot-tracked static memory peaked at 355.1 MiB; this is not process RSS or a
bound on native allocations. The sampled scene contained up to 1,793 trees.
This workload is not a densely furnished city, a large multiplayer session,
high-speed vehicle travel, a high-entity-count workload or sustained thermal test.
The separate dense-model transfer gate remains failed despite this scene's
60 FPS average; see `docs/evidence/model_admission_pressure`.

## Repeating and comparing

Run `python TerraForest/tools/runtime_baseline.py` from the repository root.
It creates timestamped reports, uses another empty derived cache, records the
revision/settings/binaries, and fails if phases are missing, engine errors occur,
or sampled presentation/focus/cap requirements are violated. Completion means a
valid reference was captured; it is not an automatic claim that performance is
acceptable. Raw frame distributions and workload counts remain the evidence.

Use this same host, driver, power/thermal settings, engine, rendering configuration,
seed and script for before/after comparisons. Re-establish the cohort after any
of those change. Preserve frame-time tails and startup/transition duration rather
than crediting an unchanged capped average as extra headroom. Repeated matched
runs are required for small optimization claims; this short reference alone
does not establish variance or long-run stability.
