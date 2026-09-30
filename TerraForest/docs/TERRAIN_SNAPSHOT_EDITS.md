# Snapshot progress under sustained distant edits

Run `python tools/probe_terrain_snapshot_edits.py --godot <executable>`.
It reuses the sustained load script with `--remote-edits`: the same 64/256 job
cases, two repetitions and two outstanding slots, now with one real command-2
excavation between submission and polling on successive consumer iterations.

The edits carve distinct sites in a distant grid at Y=20. All 640 edits change
density, and every edit occurs while at least one job is pending. All 640 mesh
jobs and 8,127 density queries finish without errors. There are no rejected
submissions, stale results or missing/duplicate completion tokens. Every received
result's validated revision matches authority after the latest edit.

| Jobs / repetition | Total ms | Query max ms | Capture max ms | Poll max ms | Edit max ms | Completion max ms |
|---|---:|---:|---:|---:|---:|---:|
| 64 / 0 | 1634.68 | 0.400 | 0.083 | 1.018 | 0.814 | 68.437 |
| 256 / 0 | 6415.77 | 0.654 | 0.068 | 0.565 | 0.857 | 49.999 |
| 64 / 1 | 1615.16 | 11.966 | 14.059 | 0.338 | 1.000 | 65.486 |
| 256 / 1 | 6448.55 | 0.597 | 0.077 | 0.730 | 2.169 | 50.585 |

The 50 ms query gate and 16.667 ms individual capture/poll/edit call gates all
pass. The latter do not gate their sum in a frame. Rare call outliers remain;
these results do not establish spare CPU time. The consumer uses a 60 Hz headless
cadence. No graphics, forest, collision or materials are processed.

This verifies progress through repeated certified remote revision changes in
the opt-in geometry API. It does not prove resilience to overlapping local edits,
high-radius brushes, density-page saturation, multiplayer message arrival, or
long-duration residency. The test requests small radius-2 edits and discards
geometry packets after consumption. It does not run the normal mining pipeline.

Raw calls, counts, overlap accounting and source hashes are retained at
`evidence/terrain_snapshot_edits/terrain_snapshot_edits.json.gz`.
