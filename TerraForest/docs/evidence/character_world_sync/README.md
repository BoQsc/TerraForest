# Character and world checkpoint synchronization

2026-10-23. Combines character/navigation checkpoint `f9e4b4ad` with the latest
paused world checkpoint `3e568575` (native lake generation and map identities).
Both histories are preserved. Source and documentation changes merge cleanly.
The two structures DLL conflicts are resolved by rebuilding debug and release
from the combined sources, preserving navigation collision interests and the new
logical-content revision separately from residency-sensitive survey cursors.
Water DLLs come from the incoming world checkpoint; unchanged navigation, player
and terrain libraries retain their checked identities. See `combined_native.json`
and both structures build manifests.

## Functional verification

All 15 launcher outcomes in `run.json` pass (the release outcome includes four
separate checks):

- Eleven debug checks: regional navigation, collision residency, legacy actor
  routes, zombie navigation, slow zombie steps, player cottage stairs, block/map
  identity, water/map identity, offline lake startup/protection/cancellation,
  exact generated-lake equivalence, and actual-host wooden-door destruction.
- Release DLL checks: regional navigation, collision residency, slow zombie
  steps, and player cottage stairs, in an isolated project.
- Actual production generation: seed 1703, generator 19, connected layout,
  unique published slot `workflow_25344_134992`. One generation child and native
  saved-data verification pass. Lake bake completes in 1.07 seconds; total
  generation is 56.8 seconds in this run. These are observations, not a controlled
  performance comparison.
- Fresh full-game playback at 1920x1080: ready, unchanged canonical root, and all
  four map layers hit their caches with zero terrain patch rebuilding. The
  inspected world/map images are retained here. They establish loading and UI
  continuity; world design and steady frame cost remain unqualified.
- Autonomous actual-world tower journey: 13 checks pass, including intact-door
  attack/destruction, authored stairs to the second upper floor, player attack
  contact, and return to the exterior. All 210 source files, including regional
  sidecars, retain their SHA-256 hashes. This sync run is headless; prior rendered
  tower/cave evidence remains in `../regional_navigation/`.

Each outcome retains its console, engine log and run manifest. The tower result
also retains route, motion and timing diagnostics. Generation job records and
the fresh playback report are included. None of these checks closes the existing
world/art, survival gameplay, arbitrary reachability or population acceptance gaps.

## Remaining navigation limits

This merge changes no navigation capabilities or budgets. The headless tower's
first complete paths take 21.8 seconds outbound and 17.0 seconds on return, with
actual contact at 116.3 and 76.6 seconds. Peak planning is 48 work quanta and
4,575 microseconds: the cooperative 750-microsecond deadline can overrun inside
work. Cold planning and CPU/frame qualification remain open. These headless
observations are not comparable to stable rendered FPS.

The existing six-zombie, 96-metre domain, broader seed/building/mine, moving-target,
heterogeneous crowd, automatic jump/ladder, crawler and compound-door-persistence
requirements remain in `../../REGIONAL_NAVIGATION.md` and the existing character
entry in `../../WORLD_FOUNDATION_STATUS.md`.

## Continuing in separate worktrees

The original folder uses `codex/foundation-vegetation-support`; the character
folder uses `codex/character-integration`. A worktree is a separate working folder
and branch sharing the repository history. Future edits do not appear in both
folders automatically. Merge committed checkpoints regularly, rebuild affected
native libraries from combined sources, and check the affected host behavior.
Advance the paused world branch only after checking it has no new source edits.
Keep another checkout's unfinished edits and generated files intact.
