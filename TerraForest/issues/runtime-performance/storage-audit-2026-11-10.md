# Performance investigation storage accumulation

Status: confirmed workflow failure; launch preflight corrected. Storage retention
and stable 60 FPS remain open. No production limiter, visual or gameplay change.

The investigation accumulated full world clones, report sessions and historical
builds without an aggregate lifecycle for those artifacts. Asking the user to
free space before auditing those outputs was the wrong response. The existing
2 GiB hard reserve correctly blocked another launch; it did not cause the growth.
The launcher checked that reserve only after creating another approximately
49 MiB world clone. The recorder's eight-file ring is per output directory, not
a bound across sessions. Existing cache quotas exclude saves and evidence by
design and therefore cannot contain this accumulation.

## Measured inventory

Read-only inventory at 2026-11-10 05:50 UTC; GiB means 2^30 bytes. These are
retained footprints, not proof of the exact time each byte was newly allocated.
Junctions are excluded from the directory totals. In particular, the apparent
ragdoll trial's `addons` and `.godot` are junctions to the live project and must
not be counted or cleaned as independent copies.

| Category | Retained footprint | Qualification |
| --- | ---: | --- |
| Project reports | 22.67 GiB | Logs, images, test projects, old packaged builds and traces |
| Startup optimization reports | 5.26 GiB | Included above; eleven approximately 449 MiB PCKs |
| Performance-change reports | 2.98 GiB | Included above; before this audit's trace compression |
| All worlds | 20.55 GiB | Includes protected user saves and test/generation worlds |
| 113 `StartupBench_FPS_` slots | 5.41 GiB | Included above; includes the retained source fixture |
| Explicit diagnostic markers | 18 slots / 0.86 GiB | 16 successful checks / 0.77 GiB; not deleted |
| Ordinary `.build` artifacts | 6.46 GiB logical / 5.33 GiB reported on disk | Includes compiler cache and retained historical checkpoint |
| Git directory | 5.09 GiB | History retained; not a cleanup target |

Raw evidence: `reports/performance_changes/storage_audit_20261110.json` and
`world_storage_audit_20261110.json`; the read-only scripts are retained in
`.build/audit_performance_storage.py` and `.build/audit_world_storage.py`.
Uncompressed file storage is reported by Windows as file length; cluster slack
and any hardlink sharing are not reconciled. The numbers are not a whole-drive
accounting. Free space changed during the audit, so no exact attribution is made
for the earlier fall below the reserve or later recovery.

## Corrective work and verification

`tools/check_frame_trace_world.py` now checks the hard reserve **plus the source
clone and planned report space before creating either the clone or report**.
Native package pairing also runs before materialization. It records the planned
storage and emits the existing 10 GiB free-space warning before another batch.
No budget was relaxed. The regression checks both insufficient space and wrong
native pairing: neither may create files, copy a world, or launch the engine;
the source fixture remains byte-identical. The existing ten resource-budget
tests pass as well.

The blocked `20261110T053223851883Z_canopy_remaining_render_markers` run created
a clone before the old late check, but launched no engine and supplies no FPS
evidence. This failed attempt remains visible.

Lossless NTFS compression of 160 existing performance JSON files reclaims
469,014,029 bytes (447 MiB); all 160 SHA-256 checks match. It does not set
compression on report directories, so future captures do not inherit it.
Receipt: `reports/performance_changes/retained_trace_compression_20261110.json`.
Earlier cache/snapshot compression verification now confirms 6,338 import files
and 4,476 retained/native/asset paths unchanged. The latter includes live assets
reached through the trial junction; it is not a separate reclaimed test copy.
Receipt: `canopy_retained_compression_verification.json` in the same report folder.

The earlier compiler-cache deletion was rejected by automatic approval review
with only “blocked by policy”; it was not retried through another deletion tool.
The distinct existing terrain-cache maintenance dry run finds 3,477,425,953 bytes
of recognized derived packets against the approved 3 GiB budget, with 256,349,165
bytes eligible for identity/digest-verified retirement. Saves, logs, images,
unknown files and source fixtures are excluded.

The apply run retires **2,571 verified packets / 242,102,508 bytes (231 MiB)**.
It returns failure for the remaining candidates that could not be verified;
those files are retained, not forced through deletion. Thus it is partial
maintenance, not a clean quota pass. Receipt:
`reports/storage_maintenance/20261110T060028261380Z.json`. Together with trace
compression, this audit reclaims 711,116,537 file bytes (678 MiB); volume free
space is not used to infer that amount because other activity changes it.

## Remaining requirements

Establish a bounded archival lifecycle for diagnostic worlds and historical
builds, preserving referenced regression evidence and the fresh-default source
fixture. Older worlds without ownership markers must not become deletion
candidates from their names alone. Lossless compression and earlier preflight
reduce pressure but do not close aggregate retention. Do not start another large
test batch without accounting for its output.

Storage pressure blocked verification; it does not establish the cause of the
remaining 42–43 ms renderer stalls. Return to the pending completed-frame marker
capture once the reserve plus planned work is available and maintenance is idle.
Keep the approved cap, VSync, quality and gameplay settings. Close performance
only after repeated normal foreground gameplay establishes frame-time headroom,
visual/gameplay parity and resource stability.
