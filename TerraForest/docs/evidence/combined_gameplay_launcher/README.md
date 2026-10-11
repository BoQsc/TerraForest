# Separate combined gameplay launcher — 2026-10-11

`Play Combined Gameplay.cmd` uses the existing furnished settlement as a first-run
source, copying its canonical .trw and both .regions/.models stores into the
separate `combined_gameplay` slot. Later launches retain that slot's progress.
The original `Play Combined World.cmd` remains the free-editor checkpoint.

Both enable ground cover, actors and the bounded vehicle fleet, with 1920x1080
fullscreen, VSync and cap60. Gameplay additionally enables costs, mining/harvest
resources and furniture salvage. Normal launch records include Git identity, DLL
hashes, the source-copy disposition and engine/console logs. A dry-run writes
neither a copy nor a game launch record.

Copy publication writes the canonical root last. A changed source root rejects;
existing destinations, partial region stores and an existing clone lock are never
overwritten. Failed staging data is retained for inspection. This is a local
first-run checkpoint copy, not a live backup service or crash-atomic multi-file
transaction. An interrupted publication may require manual inspection before retry.

Synthetic checks verify both sidecars, exact bytes, retention of changed destination
progress, invalid names and partial-destination rejection. The real check copied 40
files into a disposable slot, verified every copy hash, then passed actual main-world
startup/presentation with gameplay and combined feature flags in 14.42 seconds.
All 40 source file hashes stayed unchanged. Engine diagnostics were empty. The
human `combined_gameplay` slot was not created by this test. Existing editor launcher
configuration also passed its dry-run. Evidence does not establish sustained FPS,
thermal behavior, gameplay balance or human acceptance.

Reproduce: `python tools/check_gameplay_copy.py`. This requires the local furnished
checkpoint; repository clones do not include personal world saves.
