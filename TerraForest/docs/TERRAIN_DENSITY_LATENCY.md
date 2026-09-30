# Density query scheduling rejection

The shared terrain worker is rejected as the interactive query path under large
mesh loads. Retained evidence is in
`evidence/terrain_density_latency/terrain_density_latency_probe.json.gz`.
All source hashes matched the working files when the evidence was retained.

Run with:

```text
python tools/probe_terrain_publication.py --density-latency --godot <Godot executable>
```

This command intentionally exits nonzero while the latency gate fails. The runner
retains the JSON and log on test failure, not only on success.

Three repetitions use fresh worlds with disk cache disabled. Each submits eight
queries behind zero, one or four mesh jobs. Every loaded sample observes queued
work or an active mesh job before query submission. All 168 queries return hits;
all submitted mesh jobs complete. There are zero correctness failures and 72
responses exceed the provisional 50 ms rejection threshold.

| Mesh size / jobs ahead | Median response ms | Maximum response ms |
|---|---:|---:|
| None | 0.51 | 6.63 |
| 16 m / 1 | 6.89 | 8.29 |
| 16 m / 4 | 6.84 | 13.75 |
| 64 m / 1 | 20.74 | 20.90 |
| 64 m / 4 | 61.94 | 75.81 |
| 256 m / 1 | 1097.57 | 1363.87 |
| 256 m / 4 | 2297.61 | 2325.40 |

The maximum query execution/decode time is 0.072 ms. Waiting dominates this
workload. These are headless CPU measurements, not 1080p rendering, physical
input latency, a player-frame polling measurement, or FPS qualification.

## Architectural consequence

`terrain_backend.gd` consumes a single FIFO queue. Queries deliberately cannot
overtake mutations. `native/terrain_binding.cpp` also holds the per-world mutex
through `process_request` and reply copying; only cancellation commands bypass
it. Adding a query thread using the same native object would still encounter
that lock. Promoting queued queries cannot interrupt an already executing mesh.

Do not enable query priority as a supposed solution or weaken the latency gate.
The next implementation must give authoritative queries bounded access while
meshing is active. Candidate designs are bounded resumable mesh work or immutable
revisioned mesh inputs captured with bounded cost, allowing mesh computation
outside the authoritative-world lock. Neither design is implemented or qualified
by this test. Copying the entire world for each edit is not an acceptable shortcut.

Before adoption, measure capture/lock time, peak snapshot memory, query latency,
edit-to-publication latency and mesh progress together. Exercise edits, reset,
load and shutdown while both paths run. Reuse the existing revision and stale-hit
controls. No reader may observe partial mutation, and continuous queries must
not starve mesh completion. Then repeat the integrated mining/forest workload
at 1920x1080 fullscreen and run endurance tests.

This gate addresses interaction scheduling only. Local edit ownership, terrain
topology, LOD validity, collision robustness and vegetation preservation remain
separate unresolved requirements.
