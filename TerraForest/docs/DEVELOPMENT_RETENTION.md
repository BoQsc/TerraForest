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
Empty files/directories survive. Logs, screenshots, source provenance and original
build manifests stay at their existing paths. Completed rolling traces additionally
use `tools/maintain_performance_traces.py`: two ordinary captures remain ready,
older traces are reconstructed/hash-verified before their exact loose files retire.
Each report keeps `traces.archive.json`; `.retain`/`RETAIN_READY` pins are respected.
The FPS launcher performs this maintenance before admission and after gameplay.
Use the existing archive restore command with a new inspection directory to read
cold traces. No regression evidence is discarded and no budget is raised.

Before any loose source is removed, all archived files are reconstructed as a
stream and checked against their complete hashes; all sources are rechecked too.
Changed, linked, corrupt or unknown data fails closed. Retirement removes only
the exact verified paths. Partial retirement can be resumed from its immutable
archive. The tool writes a separate receipt under `reports/artifact_retention`.

## Restoring evidence

Rendered water checks use `run_godot_check.py --isolated-render` on Windows.
The process owns a separate non-input desktop; it never switches desktops or
sends input. This is rendering isolation, not save isolation: the player-world
driver explicitly loads the canonical input read-only into a temporary session
and verifies its hash afterward. The launcher admits 32 MiB of reports for each
integrated water driver, records the command/native hashes and retains logs.
`maintain_water_captures.py` archives receipt-owned PNGs after process exit,
keeping two ordinary ready runs per family (`water_barrel_world` and
`water_player_world`). Failed runs retain their logs and archive receipts too.
The owned capture names include the four reverse-angle shoreline views. If a
run's original views were already archived, these use a supplemental receipt;
the original receipt is never overwritten. Under report-budget pressure,
`maintain_water_captures.py --apply --keep-ready 1` explicitly keeps the latest
ready run per family and cold-retains the older one, within the at-most-two
policy. At least one ready run is always retained; pins are respected.
The desktop and process handles close after the owned child exits. No full
export, source copy or saved world is allocated by these rendered checks.

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

The shared Godot test runner additionally enforces project-wide developer-output
admission through `tools/development_storage.py`: 4 GiB loose reports, 2 GiB
isolated scratch builds, 10 GiB verified local archives, 4 GiB native compiler
caches and 2 GiB source import caches. Planned report/scratch growth counts before
launch. Source assets, Git history, the installed distribution and player saves
are outside these development-output categories. A limit failure preserves all
files and prevents launching another test; it never triggers blanket deletion.
Building/regional isolated-copy launchers and frozen/FPS captures also preflight
before materializing large copies. Admission time is recorded separately from
engine startup timing. These controls operate only in development tools.

Receipt-identified test worlds have a separate 3 GiB admission budget, including
128 MiB of planned next-world growth. The shared runner registers explicit FPS /
startup slots and known test-world creation receipts after exit. Registry entries
are accounting evidence only, never permission to delete a save. Unknown/player
saves remain outside this test budget and the existing runtime save policy is
unchanged. Failure to record an owned test world fails the check visibly.

Do not loosen a limit to conceal accumulated output. Archive/verify and retire
obsolete owned artifacts, reuse the main checkout and current compiler/import
caches, then rerun admission. Full export/build duplication must have a specific
comparison purpose and a lifecycle, not merely a new report label.

Other historical test families are not inferred safe from folder names. They need
equivalent ownership receipts before joining this lifecycle. Retained unknown or
modified worlds remain explicit exceptions, not silently cleaned saves.

The receipt adapter now covers the declared quest, survival, exploration,
parking, mine, reinforcement, lights, sleepers, expedition and private trader-copy
drivers. It requires their actual creation phase or verified clone receipt, the
exact driver and evidence directory, and a completed process. Later receipts
extend the last-use boundary. Creation receipts and runs are hashed again before
retirement. Input/source fixtures, pins, unknown sidecars and later-modified saves
remain protected. Active families keep at most two ready worlds; non-performance
families inactive for three days can retain all their evidence cold, with no
ordinary loose copy. FPS/startup families retain their two recent captures.
Packaged drivers frozen beside a report also require exact equality with the
recorded Git revision after undoing the helper-path rewrite. Their current full
hash is retained in the ownership proof; a generic `driver.gd` name is insufficient.

Completed isolated native checks release only matching copied DLL bytes and
rebuildable `imported`/`shader_cache` directories. Bootstrap cfg, original assets,
Godot identity files, logs and failure evidence survive. Linked paths abort cache
cleanup. Navigation release checks now use this lifecycle as building checks do.

`tools/retire_backed_outputs.py` moves obsolete local captures/build binaries to
the already verified GitHub backup. It requires a complete matching catalog and
receipt, rechecks remote asset hashes and every selected local file, preserves
pins/current captures/referenced media/local archives, then removes exact files.
Each affected folder gets a restore pointer. Windows access refusals are retained
and recorded. No recursive deletion, cache scan or compression runs in gameplay.

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
test passes. Automatic approval review initially blocked recursive removal of
two temporary restore copies. A later, safer exact-file retirement revalidated
the complete inventory and every hash against the original archives before
removing the copies (0.516 GiB); no recursive deletion was used. Receipt:
`reports/artifact_retention/verified_restore_retirement_20261110.json`.

The requested project-only GitHub backup is complete, including the later archive
delta and frozen-driver fixtures. All archived evidence retains both manifests
and shared chunks or its complete raw-file mapping. Private Codex conversations
and credentials remain local. Ownership-verified retirement also covers the
historical families and four obsolete worktrees; branches/history are preserved.

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

The [separate backup branch](https://github.com/BoQsc/TerraForest/tree/codex/generated-backup-2026-11-10/generated-backup)
carries exact inventories, exclusions, upload checksums and restore instructions.
Its four draft backup releases contain 55 volumes / 18.459 GiB uploaded; all remote
sizes and SHA-256 digests match. A real GitHub download reconstructs one complete
world (305 files / 62,205,099 bytes) with every file hash matching, without reading
the local source world. Earlier full local world/build restoration checks pass.

Final cleanup: 161 test worlds, 11 frozen builds, 12 regional derived caches and
four worktrees; 49.749 GiB net logical file bytes reclaimed, excluding Git packing,
transparent compression and verification copies created during cleanup. Volume
free space was 50.490 GiB. These are distinct measurements, not an inferred NTFS
allocation saving. Reports use 3.301 GiB, scratch 0.969 GiB, archive 2.102 GiB,
compiler caches 1.751 GiB, imports 0.158 GiB and owned test worlds 2.581 GiB;
admission passes including planned next-output growth. Nine backed-up media files
refused by Windows remain explicitly retained. Final proof maps 63,820 retired
world/cache files to raw remote objects or remotely preserved archive chains.
Evidence: `reports/artifact_backup_20261110/cleanup_summary.json` and the branch's
`generated-backup/cleanup-receipts.json.gz`. Source fixture/PCK hashes and all
14 installed native pairs remain unchanged. Git object packing preserved refs,
reflogs and history; private Codex session data was not uploaded or deleted.

Water barrel captures use `tools/maintain_water_captures.py --apply` before and
after checks. It admits only named PNGs and optional native replay snapshots
from completed `water_barrel_world` runs whose command declares that exact
evidence directory. Two unpinned runs remain ready;
older images are hash-verified in the shared chunk archive before retirement.
Logs and JSON remain loose. Restore `captures.archive.json` with the existing
`maintain_performance_artifacts.py --restore ... --destination ...` command.


## Native launcher regression family

`tools/check_launcher_world_flow.py` admits 16 MiB of reports and 128 MiB for
creation before launching. It uses only the receipt-owned `LauncherUI_1703_Fixed`
and `LauncherUI_1703_Final` slots; creation refuses to overwrite an existing slot.
Reuse these two fixtures for load checks. No third ordinary ready copy is admitted.
Keep ownership/run receipts and failed-run logs under `reports/launcher_generation`.
After continuation verification, mark these test slots diagnostic so ordinary
Continue returns to the player's worlds. This does not delete or alter save data.
The generic owned-world registry accounts for bytes; it never authorizes deletion.
Retiring this family requires receipt/hash verification and the existing archive
format before any loose files are removed. Until that adapter is provided, retain
these two fixtures in place; do not silently evict them or increase the budget.
The Godot launcher itself creates no saves or exports during preparation. It uses
fixed report filenames and bounded Godot log rotation; shortcut backups are kept
once, with installed-target receipts, rather than duplicated per installation.
