# Development artifact retention

Original tooling is 0BSD. Archives preserve the licenses and bytes of existing
material; storage transformation does not relicense it or change runtime assets.

Performance investigations must preserve reproducible evidence without leaving
unbounded full working copies in the world browser and report folders.

`tools/maintain_performance_artifacts.py` is dry-run by default. `--apply` archives
obsolete completed FPS worlds; `--builds --apply` also archives receipt-verified
frozen startup builds. It requires gameplay/native builds to be idle and takes
an exclusive archive writer lease. It never stops another process.

The world selection requires a completed `run.json`, a `clone.created` receipt,
matching source/destination slots and the exact frame-trace driver argument.
Source fixtures, the two newest completed captures, `.retain` pins, unknown
sidecars and saves modified after their run are excluded. A name alone is not
ownership. Each selected world is leased while its files are archived and
retired. Existing player saves and unmatched test-looking worlds remain intact.

Startup benchmark worlds require their matching generation command, or a normal
load receipt proving a fresh copy and unchanged source. Explicit read-only inputs
and copied source fixtures are protected. Two recent worlds are retained per
launcher family (FPS and startup), not two per label or directory.

Frozen build selection requires its original file hashes and a matching benchmark
run with the same build manifest and package path. Current source, installed
`dist`, compiler caches, Git history, and junction targets are outside this tool's
selection. `RETAIN_READY` inside a build pins its loose binaries.

Every selected file is divided into 1 MiB chunks, compressed using Python's
standard zlib, and stored by SHA-256 under `reports/retained_artifacts/chunks`.
The owning report retains `world.archive.json` or `build.archive.json`, including
the original names, complete file hashes, chunk order and ownership receipt hash.
Empty files/directories survive. Logs, traces, screenshots, source provenance and
original build manifests stay at their existing paths.

Before any loose source is removed, all archived files are reconstructed as a
stream and checked against their complete hashes; all sources are rechecked too.
Changed, linked, corrupt or unknown data fails closed. Retirement removes only
the exact verified paths. Partial retirement can be resumed from its immutable
archive. The tool writes a separate receipt under `reports/artifact_retention`.

## Restoring evidence

Use a **new directory**, never an existing save or checkout:

```text
python tools/maintain_performance_artifacts.py --restore reports/startup_optimization/baseline_build/build.archive.json --destination .build/restored_baseline
```

The tool checks chunks and complete files before and after restoration and refuses
to overwrite an existing directory. A restored build can be passed to
`tools/benchmark_world_startup.py --build .build/restored_baseline`. Restored world
files remain in the chosen inspection directory; installing them as a playable
slot is a separate explicit operation, not an automatic overwrite of a save.
Keep both the archive manifests and shared chunks when backing up the evidence.

## Automatic lifecycle and storage admission

The gameplay capture launcher archives old completed worlds **after** gameplay
ends, leaving two recent worlds ready to open. Startup benchmarks retain two
recently used frozen builds; archival occurs before a new freeze and after a
completed batch. No compression, scanning or retention runs inside timed gameplay.

New capture/freeze admission stops when performance reports would exceed 8 GiB
(including a 256 MiB next-capture allowance), or the archive reaches 10 GiB.
These are development-output budgets; they do not alter any approved gameplay,
resource or pacing limit. Reaching a budget requests evidence review/storage
management; it never evicts regression evidence to make a test pass. The existing
2 GiB free-space floor plus planned working space is also preserved.

Other historical test families are not inferred safe from folder names. They need
equivalent ownership receipts before joining this lifecycle. Retained unknown or
modified worlds remain explicit exceptions, not silently cleaned saves.

## Verified first retirement, 2026-11-10

Receipt `reports/artifact_retention/20261110T062528179507Z.json` records 99 FPS
worlds and 11 frozen builds, zero archival errors: 9.886 GiB of loose file bytes
replaced by 1.514 GiB of shared compressed chunks, reclaiming 8.372 GiB net.
The baseline build (18 files, 502,349,055 bytes) and one full world (1,029 files,
51,399,815 bytes) were restored into new inspection directories and every file
hash matched. `reports/artifact_retention/roundtrip_20261110.json` records these
checks and the unchanged fresh-default source fixture hash.

Fifteen retention checks cover corruption, changed sources, ownership, paths,
budgets, leases and interrupted retirement; fourteen pass and one symlink
creation case is skipped by Windows permissions. The separate Windows junction
test passes. Two temporary restore copies remain because automatic approval
review blocked their removal; do not count that space as reclaimed.

The requested project-only GitHub backup is in progress. All archived evidence
must retain both manifests and shared chunks. Private Codex conversations and
credentials are excluded. Other test families and extra worktree retirement
remain pending ownership/backup verification, not approved for blanket deletion.

Regional read-only tests previously bypassed temporary-world cache cleanup.
`check_zombie_regional_world.py` now reserves space before launching and archives
its owned derived cache after exit and source-hash verification. The dedicated
archive retains failed-run payloads too; source worlds are never retired by this
adapter. It verifies the exact driver, timestamp, cache argument and unchanged
source receipt, takes the normal cache lease, then uses the same full-byte archive
verification. The additional failed-evidence/source-protection regression passes.

## Project-only GitHub backup

`tools/generated_backup.py` catalogs explicit project artifact roots and groups
identical full files by SHA-256. It rejects linked paths and credential-looking
content; it excludes private account/chat state and rebuildable tool caches.
Each ZIP volume contains objects named by content hash. The catalog restores
their original relative paths, including duplicates and empty directories.
Existing licenses and provenance remain unchanged; the backup is not an assertion
that inherited artifacts have default licenses or that builds are FPS-qualified.

Publication uses the explicitly requested backup branch and a dedicated **draft**
release. Volumes are bounded to 512 MiB of input in ordinary cases (individual
objects must remain below 1,800 MiB); one in-memory volume is uploaded at a time,
without another archive tree on disk. Credentials come from Git's credential
helper and stay in memory. A durable receipt is written only after GitHub reports
the exact uploaded size and SHA-256. Resume verifies prior uploads and refuses a
changed catalog or mismatched asset; local source evidence is never deleted by
the backup command. Missing remote checksums fail verification.

Restore requires the catalog, required `objects-*.zip` files and a **new** output
directory. `--prefix` can select one report/world instead of reconstructing all
duplicates. Every restored file is checked against the catalog's complete hash:

```text
python tools/generated_backup.py restore catalog.json.gz downloaded_volumes restored --prefix project/reports/performance_changes/
```

The separate backup branch will carry its exact inventory, exclusions, upload
checksums and instructions. Until that inventory reports complete remote
verification, the GitHub backup must be described as incomplete.
