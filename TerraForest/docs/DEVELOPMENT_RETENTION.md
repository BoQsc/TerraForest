# Development artifact retention

The native world inspector's `native-check` admits 2 MiB of reports and zero
world/scratch bytes, then records a headless check under `reports/world_inspector/`.
It retains small completed/failed logs and JSON with the receipt and verifies that
the input root stayed unchanged. It creates no world clone, export or source copy.
The native outdoor and inspector regression fixtures reserve zero saved-world
bytes; synthetic inspector roots and label backups together stay below 128 KiB.
Explicit operator label edits retain their adjacent recovery backup and are not
eligible for automatic developer-evidence retirement. See
[BINARY_WORLD_FORMAT.md](BINARY_WORLD_FORMAT.md).

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
Full cadence observations and the driver's named, unreferenced screenshots use
`observation.archive.json` after the matching run has exited. Slot and output
directory must match the command; pins and the two newest ordinary observations
stay ready. Referenced screenshots remain loose. This also covers earlier runs
whose observation is their completion record. Restore with the same archive
command below into a new inspection directory. Human `--in-place` captures grant
no ownership or retirement rights over their source player save.
Use the existing archive restore command with a new inspection directory to read
cold traces. No regression evidence is discarded and no budget is raised.

Before any loose source is removed, all archived files are reconstructed as a
stream and checked against their complete hashes; all sources are rechecked too.
Changed, linked, corrupt or unknown data fails closed. Retirement removes only
the exact verified paths. Partial retirement can be resumed from its immutable
archive. The tool writes a separate receipt under `reports/artifact_retention`.

## Restoring evidence

Checks default to headless operation. An interactive window requires the explicit
`--visible-render` option; omit it for unattended work.

Rendered water checks use `run_godot_check.py --isolated-render` on Windows.
The process owns a separate non-input desktop; it never switches desktops or
sends input. This is rendering isolation, not save isolation: the player-world
driver explicitly loads the canonical input read-only into a temporary session
and verifies its hash afterward. The launcher admits 40 MiB of reports for each
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

The rendered `physics_residency_world` check reuses an explicitly selected player
save read-only and allocates no export or world copy. The shared runner admits
16 MiB for its bounded cadence JSON and logs. The optional `--capture-replay-view`
adds one additional
MiB, enforced by the driver, for `replay_view.jpg` captured after timing ends.
Only receipts containing that flag authorize archiving/retiring the image along
with their cadence; an unowned image is left untouched. The same two-ready-run
retention applies. `maintain_physics_captures.py` otherwise
archives only `physics_residency.json` from completed matching driver/output
receipts, verifies reconstruction before retiring loose bytes, and retains two
ordinary ready runs plus `.retain`/`RETAIN_READY` pins. Each cold run keeps
`physics.archive.json`, logs and small analysis summaries. The analysis tool can
read and hash-check archived cadence directly. Maintenance runs before launch
and after process exit, never during the route. The audited headless zombie
regressions declare 2 MiB of logs/JSON; their source import cache is reused.
The headless `structure_exclusion_paging` regression also declares 2 MiB for its
small archive fixture, assertions and JSON. It uses the receipt-owned check
directory, with no exported build or player-world copy.
This includes `zombie_collision_cloud`: bounded certificate/contact assertions
and construction timings go into the owned log, with no capture images, world
files, geometry dumps or exported builds.
The residency route can retain at most 512 posed clouds / 524,288 vertices in
memory for a post-route paired construction check. Only hashes, counts and
timings enter its existing cadence JSON; raw geometry is released without a
separate artifact. Its 16 MiB output allowance and receipt lifecycle are unchanged.

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


## Object pack and mansion captures

`grand_buildings` admits 8 MiB headless or 32 MiB rendered for three native
snapshots capped at 1 MiB each, nine normalized 1280 × 720 RGB pictures and
small logs/JSON. Bake-only and fresh-process restore runs admit 2 MiB. Its
`grand_buildings_world` check admits 2 MiB and opens an existing player world
read-only. Neither check allocates a save, export or source copy; their planned
test-world growth is zero. Named snapshots, measurements and pictures join
`maintain_homestead_captures.py`'s receipt-owned lifecycle. Default retention is
two ready runs per family. Under report-budget pressure, explicit
`--apply --keep-ready 1` keeps the newest ordinary run and cold-retains older
receipt-owned output with reconstruction/hash verification. Pins, logs and
unknown files stay protected; no storage budget is raised. The November 27
admission failure was resolved by cold-retaining 59,814,706 bytes of older object
captures and 6,859,494 bytes of water captures using this one-ready policy.
If another player/game process is active, grand-building checks explicitly record
pending archival and keep the exact output/receipts for the next idle maintenance
invocation. They neither stop that process nor compress during gameplay; ordinary
storage admission still blocks a launch if those retained bytes exhaust the budget.

`run_godot_check.py` admits 2 MiB for registry/container/restore checks, 16 MiB
for an Outdoor 01 sheet, 64 MiB for six mansion views, and 32 MiB for the ordinary
object-system run (three PNGs, a native state fixture capped at 4 MiB, timing JSON
and logs). No full export, source copy or saved world is allocated. Headless pack
and mansion checks admit 2 MiB. The native state fixture is reused by hash for a
fresh-process restoration test.

The full-game `object_rendering_world` walk admits 32 MiB for two PNGs, a frame
trace capped at 8 MiB, logs and the receipt. It reads the existing Hidden_Meadow
snapshot without saving; its floor and 1,000 added objects exist only in memory.
Its named captures and trace use the same two-ready receipt-owned lifecycle.
The `model_horizon` regression admits 2 MiB, puts its small `fixture.trw` and
`result.json` inside the receipt directory and uses that lifecycle too. Its
100,000-record pressure case stays in memory.
`object_pack_render_mesh` admits 16 MiB for four 1152×768 RGB material/LOD sheets,
pixel/geometry results and logs (2 MiB headless), under the same two-ready policy.
`zombie_render_mesh` uses the same allowance and lifecycle for two 1024×1536 RGB
rig comparisons and its small pixel/geometry JSON. The headless geometry-bake
and mesh-bake regressions admit 2 MiB for assertions and receipts; they write no
images, world copies or exports.
`house_furnishings` admits 8 MiB headless or 32 MiB rendered for a native fixture
capped at 4 MiB, small JSON/logs and three 1080p pictures. A fresh process
can verify that fixture by its supplied SHA-256. `house_population_world` admits
16 MiB for one 1080p outdoor picture and bounded publication JSON/logs; it reuses
Hidden Meadow read-only and creates no saved world. Both families join the same
two-ready receipt-owned capture lifecycle; a test name does not grant ownership
over its source save. No output limit is increased.
`homestead_generated_world` admits 24 MiB per run for at most three RGB 1080p
views and small logs/JSON. It creates the one explicitly requested playable
`Homestead_Valley` through the ordinary browser, refusing existing saves, and
inspects the same published world in a fresh read-only process. Its photos and
inspection JSON join the two-ready receipt-owned lifecycle. `created_world.json`
remains loose as provenance; the requested player world is never a disposable
fixture or a capture-retirement member. Production staging uses the existing
verified generation-copy lifecycle; no source copy or export is allocated.
The audited headless `furnished_capture` library roundtrip declares 2 MiB for
logs and its small temporary prefab; the driver removes only its exact owned
library files after verifying capture, reopen, rejection and rotated placement.
The headless-only `original_size_drops` check admits 2 MiB for its assertion log
and receipt. Its tiny process-owned preference fixture is removed by the test;
the headless branch writes no screenshot, save or export. Rendered variants keep
the existing conservative allowance and are not admitted by this exception.

`maintain_homestead_captures.py` archives the receipt-owned Outdoor 01, mansion
and object-system families after the owned engine exits, keeping at most two
ordinary ready runs per family. Native state and timing JSON are archived with
the object-system pictures; run receipts and diagnostic logs stay loose. Explicit
`.retain` witnesses preserve rejected R1 mansion and Outdoor 01 comparisons until
the linked visual issue is closed. All archives use the existing verified shared
chunk store and inspection restore workflow; this adds no storage budget.

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

## First-UI timing captures

`world_browser_responsiveness` admits 8 MiB for one RGB 1080p image, small timing
JSON and logs. It reads the existing save library without opening a world; its
functional mode uses only tiny disposable metadata fixtures. `first_ui.png` and
`first_ui.json` join the existing two-ready receipt-owned capture lifecycle in
`maintain_homestead_captures.py`; logs and run receipts remain loose. No save,
source copy, export or storage-budget increase is needed.
The matched `reports/checks/first_ui_20261126T191351710067Z` bundle was separately
admitted for 32 MiB and is pinned by `.retain` until the browser-latency issue's
comparison review. It keeps before/after pictures, timing records and rejected
trials together, with small launcher/UI/startup verification logs in that allowance.

`tools/benchmark_source_launch.py` admits 16 MiB before a complete source-launch
measurement. It uses the existing checkout and executable, opens no world, and
writes one RGB 1080p menu image, timing JSON and small logs/receipts. Its `full_launch`
family keeps two ordinary ready runs through `maintain_homestead_captures.py`;
only the named screenshot/timing files are archived after process exit. The
`full_launch_20261126T192359792537Z` comparison was admitted for 32 MiB and is pinned
until browser review, including its original slow preparation and four captures.
The production preparation cache uses two fixed JSON records capped at 4 MiB each
and one temporary atomic replacement, without new saves, exports or source copies.


## Outdoor generation comparison

`tools/benchmark_outdoor_generation.py` admits 12 MiB of logs/JSON and one ready
image plus 128 MiB for generation per run. It uses the ordinary source browser
recipe and `startup_benchmark.gd`, with a fresh receipt-owned `StartupBench_` slot.
Existing startup retention archives verified older fixtures after the engine exits
and keeps two ready worlds across that family. Generation staging follows the
normal publication lifecycle. Existing player saves are never benchmark targets.
The small source witness, exact placement transforms and receipts remain loose;
no export, full source copy or storage-budget increase is allocated. The focused
`outdoor_support_batches` check needs only 2 MiB of admitted logs, no saved world.


The `planning` comparison mode reuses the outdoor generation runner's existing
12 MiB reports / 128 MiB world admission and two-ready `StartupBench_` lifecycle.
It preserves only three small source witnesses and the measured dependency index.
`cached_world_plan`, `startup_resources` and the read-only
`generation_saved_equivalence` checks admit 2 MiB each; the combined final check
bundle admits 4 MiB. They allocate no saved world or export. Final source
preparation admits 2 MiB of small logs/receipts in the same comparison directory,
using the existing checkout/import cache. No storage limits are increased.


`benchmark_outdoor_generation.py --load-slot StartupBench_<id>` uses an existing
owned fixture read-only: 12 MiB of admitted logs, hashes, source witnesses, one
image and timing/profile JSON, with zero world/scratch allocation. Before/after
hashes cover its root and all sidecars. `maintain_homestead_captures.py` keeps two
ready `startup_loading` image/profile captures by timestamp, archives older
receipt-owned `ready.png`/`result.json` after process exit, and retains small logs,
source hashes and receipts. It excludes writable-load commands, mismatched output
paths and pins; it never retires the source save through capture ownership.
Incremental native builds reuse the existing build cache; this follow-up admits
2 MiB reports / 64 MiB scratch per variant before replacing the changed object and
DLL. Plan-rekey checks admit 2 MiB each and reuse the bounded production plan cache.
No full source copy, new test family world or export is needed.

The combined final terrain/cancellation, release-build and preparation bundle
admits 6 MiB reports / 64 MiB scratch once; it reuses both owned worlds read-only
and the existing incremental build/import caches.


`vegetation_reconstruction` admits 20 MiB of reports: an enforced 16 MiB
combined image/frame ceiling, 3 MiB bounded motion previews and 1 MiB metadata/logs.
It loads an existing player save read-only, with no world copy, build or export.
White-point attribution, TAA controls and far-only coverage trials share this
family. The receipt records source/native/engine identities; the driver freezes
its code and helper shaders beside the results. `maintain_homestead_captures.py`
retains two ordinary ready runs, verifies older chunks before retirement, and
keeps failed logs/receipts. `analyze_vegetation_reconstruction.py` validates a
completed admitted receipt before creating its bounded lossless motion previews.
Selected versioned issue images retain original capture/underlying-asset terms.
The `--surface-parity-only` mode reserves 10 MiB, enforces an 8 MiB image ceiling,
and creates no motion packets or previews.

`vegetation_gameplay` also admits 20 MiB, with an enforced 16 MiB combined
capture/timing-JSON cap and a 3 MiB preview cap. It loads the existing source save
read-only; it creates no world, source copy or export. Physics, actors and cover
streaming remain active. Capture phases are excluded from GPU timing summaries.
`maintain_homestead_captures.py` retains two ordinary ready runs and cold-retains
older receipt-owned captures; failed logs and receipts remain available.

`run_vegetation_lab.py` validates the one-factor matrix without allocating output
when invoked with `--list`. Rendered runs use the shared Godot runner and a 20 MiB
admission, no world copy, export or native rebuild. The driver caps all captured
data/source snapshots at 16 MiB, including at most 8 MiB of lossless motion frames.
Analysis may add a maximum 3 MiB review animation; remaining space covers logs,
receipts and a bounded 128 KiB process-overlap witness. Timing windows exclude
capture/analysis. The existing receipt-owned Homestead retention family lists
every lab output, keeps two ready runs and cold-retains older completed evidence.
The launcher refuses existing render jobs, samples other render jobs during a
run, and preserves observed overlap for cost qualification. Storage limits stay
unchanged. Laboratory validity and ordinary gameplay/human review are separate.

2026-11-27 vegetation admission recovery: completed lab
`20261127T183409513441Z` and prior gameplay `20261127T171249751501Z` were fully
cold-retained after their native motion reviews, hashes/provenance and analysis
were preserved in `issues/vegetation-lod/`. This explicitly leaves zero loose raw
copies of those completed captures until replacement gameplay finishes; no save
or regression evidence is deleted. The same archive/verify/retire library checks
receipt ownership, pins, confinement and full reconstruction hashes, with recorded
`completed-review-preserved-capture` provenance. 24,628,160 bytes were reclaimed;
report/archive limits remain unchanged.

`maintain_location_baseline_captures.py` cold-retains only the historical native
baseline driver's 15–16 MiB `bulk/*.baseline` test payloads. It requires completed
create/reopen commands, matching `--baseline-dir`/driver paths, the recorded
source hash after reversing the launcher's two path substitutions, unchanged
receipt/driver identities and pre-completion payload timestamps. Pins and the
newest two eligible runs stay ready; logs, other fixtures and player saves remain.
Recovery stages manifests inside the bounded archive category, verifies complete
reconstruction, retires exact hash-checked paths, then publishes a much smaller
manifest beside the original receipt. Thus it can shrink already-over-budget
reports without increasing a limit or admitting a new capture. An interrupted
stage remains under `reports/retained_artifacts/location_bulk_recovery` for
inspection; it is evidence, not disposable scratch.
The first recovery cold-retained 173,093,140 bytes across six completed November 2
runs. Each owning folder retains `bulk.archive.json`; the newest two remain ready.

## Metropolis recipe verification — 2026-11-27

`check_metropolis_world.py` declares 160 MiB of reports and a 224 MiB peak for
its single new ordinary-UI fixture. `recheck_metropolis_world.py` reuses an
unretired publication with matching native inputs, admitting 160 MiB for full
interaction or 16 MiB for restore only, and no additional world. Restore-only
reuse also requires the exact driver hash and a passed interaction. Failed
receipts stay intact; capture groups have separate completion records. Successful
rechecks verify/cold-retire the exact creation-receipt-owned staging and published
slots. `--archive-only --completion recheck.json` retries deferred retirement.
Capture retention selects declared filenames, never arbitrary report files.

This session's explicitly approved `--approved-headroom` adds 256 MiB each for
reports and owned worlds in that Python process only; repository limits remain
unchanged. It is not a standing permission for later work. Selected versioned
issue images keep their capture provenance and inherited asset terms.

One admitted 224 MiB scratch allowance freezes only the structures native module
and its retained notices for focused binary integration, plus tiny room-API
fixtures. It uses committed inputs and the three room-planner edits, preserving
parallel uncommitted renderer work in the main checkout. The report allowance is
4 MiB; 128 MiB of existing compiler headroom is reserved. No full project copy,
world or export is made. `reports/metropolis_clean_native.json` owns this input
hash/build; its scratch tree is verified and cold-retired after the exact DLL
objects have been stored for the focused commit.

Vegetation validation admission recovery also cold-retained 15,735,740 bytes from
the receipt-proven 2026-11-02 bulk fixture with explicit `--keep-ready 1` (default
remains two). Sixteen completed historical `gameplay_performance.gd` captures in
`reports/runtime_performance` contributed 37,443,045 bytes of `frames.json` and
`gameplay.json`. Each matched its successful temporary-game command, canonical
`--profile-dir`, source hash receipt, pins and confined paths. Their data was
reconstructed/hash-verified before retirement; screenshots/logs/saves and the
newest ready legacy capture remain. Each folder records `legacy.archive.json`.
Recovery manifests were staged in the separately admitted archive category and
moved into loose reports only after more bytes had been retired. No storage limit
was raised. The source gameplay check retains its 20MiB admission and 16MiB
capture/data cap.

Full-frame vegetation counterfactuals use the admitted shared runner with a 20 MiB report ceiling and no new world. Raw 1080p pixels are streamed to a local analyzer in memory; saved metrics, four context PNGs, one mask and three review videos use a 16 MiB media allowance plus 1 MiB analysis allowance inside the unchanged 20 MiB total admission. Encoder flush and final metadata are checked before success. Receipt-owned vegetation_fullframe captures join Homestead verified cold retention (two ready by default). Videos illustrate; raw-pixel hashes and full-viewport measurements establish comparisons.

The extended physical vegetation review captures 192 consecutive 1080p frames (3.2 seconds at 60 Hz). Its test-only RGBA buffer is bounded to about 1.48 GiB and is consumed one image at a time after cost measurement. The review movie uses H264 CRF22; raw RGB hashes and full-frame detector measurements remain independent of video compression. One lossless context PNG and the movie stay within the same 16 MiB media allowance. This capture buffer is not part of ordinary gameplay.
