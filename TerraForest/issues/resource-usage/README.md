# Resource usage visibility

- Status: Implemented; scoped engineering checks, not user visual approval.
- Updated: 2026-10-28. Builds on resource-budget checkpoint `3e8ae48e`.
- Request: Inspect the sources of storage/memory usage from ESC and see limits.
- Policy follow-up: user raised terrain-cache maintenance from 2 to 3 GiB on
  2026-10-28. The shared policy updates Usage and maintenance together; original
  screenshots/receipts below retain the earlier 2 GiB setting. Other limits stay unchanged.
  Nine resource-policy unit tests and the focused installed-pack policy/Usage-label
  check pass; logs: `reports/cache_policy_3gib/{unit,export,packed}.log`.

## Directory-audit removal

The user rejected scanning thousands of filesystem entries for this page. Usage
now retains live counters, shared limits and direct folder buttons only. It has
no folder-size calculation, full-audit button, scan task or progress polling.
Limits are not presented as measured folder usage. No filesystem contents were
deleted or changed. The separate native scanner API and offline maintenance
tools are not invoked by Usage.

Installed-pack checks pass 55 assertions, including an empty/non-running native
scanner before and after live updates/reopening, no audit controls, unchanged
folder destinations and zero cursor captures. Nine resource-policy tests pass;
export validates all 14 native hashes. [Receipts](no-scan-evidence.json).

![Usage without directory audits](images/usage-no-scan-top.png)
Current installed-pack temporary world, seed 1703, 1920×1080. Live counters and
direct folder buttons only; not an FPS or incremental-memory comparison.

![Retained limits without folder scans](images/usage-no-scan-policies.png)
Same run, lower page; 3 GiB cache quota and other storage policies remain.
Earlier screenshots and rejected audit measurements are preserved below.

## Original implementation and verification

- ESC → Usage displays process-private RAM, resident RAM, process GPU allocation
  when available, free disk space and the shared runtime/tool limits. RAM limits
  are provisional; unavailable GPU counters are never presented as zero.
- A lower-priority C++ worker counts folders read-only. Ordinary play has no
  sampling loop; leaving Usage stops sampling and cancels scanning. Manual refresh
  updates snapshots. Per-area bounds and skipped/inaccessible files stay visible.
- Folder buttons use `OS.shell_open`, with known existing paths only. There are
  no deletion buttons. Tests inject an opener to verify destinations without
  opening Explorer over the user's work.
- Content excludes old packs, source archives and reports. Worlds are separate;
  cache estimates scan only declared terrain-cache roots, skip worlds/logs and
  are explicitly not safe-deletion audits. Development directories are not the
  game's redistributable size.
- Installed-pack verification passes 53 assertions; 15 Python unit tests and the
  process-counter check pass. Both native configurations build; export validates
  14 external DLLs. [Receipts, failed attempts and exact hashes](evidence.json).
  Parser, cold-scan timeout and packed-path failures remain in reports; initial
  compiler/fixture-import errors are summarized in the receipt. New evidence
  folders carry `.gdignore`.

## Original images

![Usage counters and folders](images/usage-top.png)
1920×1080 installed-pack temporary world, seed 1703, Usage top. Native counters
and completed folder snapshot; offscreen test, no mouse capture. Not a performance
qualification or user-approved design.

![Storage policies and development folders](images/usage-storage-policies.png)
Same run, scrolled lower. World warnings do not delete saves. Cache quota is an
offline maintenance policy, not a live allocator cap. [Provenance](images/manifest.json).

## Remaining / resume here

- Historical cost audit, before removal: [measurements](cost-audit.json).
  An isolated rendered-page test visits 650,965 entries in about 67 s, with about
  60.5 s in cache roots. All 2,048 sampled geometry-leaf directories across eight
  roots were empty; this is a capped sample, not a census. Earlier file-only cache
  maintenance retains directory trees. No directories were deleted by this audit.
- On the 12-logical-processor machine, the isolated process averages 5.05% total
  CPU scanning, 0.90% with the page settled and 0.77% hidden afterward. Typical
  live refresh is 190 µs once/sec; scan/status refresh 108 µs four times/sec, even
  after completion. First activation costs 64.8 ms. The isolated first-use rise
  is about 111 MiB private / 32 MiB dedicated GPU, including fonts, renderer and
  counter initialization; these are not measured incremental full-game figures.
- The previous manual-audit recommendation is superseded by removing folder
  audits from this page altogether. First-counter initialization and real-game
  incremental memory costs remain unqualified; investigate if requested and
  require matched game-page CPU/I/O/memory and open/close responsiveness. Safe
  empty-directory maintenance remains separate, not an automatic cleanup here.
- User review: ESC → Usage, scroll down, and try the folder buttons in normal play.
- Current Usage intentionally has no folder totals. Use the system file manager
  or separate explicit offline maintenance to inspect stored files.
- [Resource qualification and storage recovery](../../docs/RESOURCE_BUDGETS.md)
  remain separate: 100 GB free-space goal and physical 4 GiB GPU testing are not
  completed by adding this page.

## Reproduce

- `python tools/run_godot_check.py resource_usage --headless --timeout 180 --require "RESOURCE_USAGE PASS"`
- Rendered checks use the same driver offscreen with a nonactivating window;
  source and installed pack commands and exact hashes are retained in receipts.
- [Native implementation](../../addons/world_runtime/native/resource_usage.cpp),
  [UI](../../addons/player_runtime/usage_panel.gd),
  [regression test](../../tests/resource_usage.gd),
  [player guide](../../docs/PLAYER_UI.md#usage).
