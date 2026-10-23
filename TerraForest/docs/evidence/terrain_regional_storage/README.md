# Regional terrain storage checks - 2026-10-23

Implementation and still-required work: [contract](../../TERRAIN_REGIONAL_STORAGE.md).
The rewrite remains active. These checks do not establish sustained gameplay,
selective native residency, dirty-page capture or safe storage collection.

- `terrain_region_store`: exact region reconstruction, unchanged publication,
  local edits, selective reads, corruption, malformed membership and writer lease.
  The first 080417 run failed the compression target. A sample-only run scheme
  stored about 726 KB from a 1.1 MB fixture. FastLZ/raw fallback reduced it to
  about 297 KB. Keeping separate flushed region files still took about 559 ms;
  bounded packs reduced this fixture to two files and about 24 ms (080934 run).
  Retain the failed primitive's log; this change did not weaken its assertion.
- `terrain_page_codec` (083200): independently framed legacy fields exercise runs,
  high-entropy raw fallback and FastLZ, preserving every density/material byte.
- `terrain_save_format` (081125019679): actual backend legacy migration, exact
  original backup and fresh worker reopen through the small regional reference.
- `terrain_storage_failure` (082441605980): actual publisher/loader, damaged and
  missing sidecars, unchanged live native state after failure, failed root
  publication, unknown addon retention, cloning, and matching cache identity.
- `terrain_history_storage` (082938): 2,048 excavations, 6,612 pages, exact complete
  and prior-backup reconstruction. The terrain-only root is 103 bytes; initial
  terrain files total 19,358,013 bytes from 81,274,740 raw bytes. Unchanged terrain
  writes zero files. A later local edit writes 127,043 bytes in two files.
  Four workers produced identical checkpoint bytes to one worker. This matched
  sample measured about 235 ms publication versus 317 ms serial. Native capture
  was about 88 ms and full restore about 307 ms; recompression still traverses
  history. Diagnostic timings are hardware-specific, fixed-order observations,
  not unbiased benchmark estimates or FPS/thermal/endurance proof.
- Async save/barrier checks (081125022500, 081321, 082416) still pass; later native
  edits do not get certified under an older save's derived identity.
- Native cloning/recovery (081320) includes all four stores and interruptions
  before/after each promotion. 081125059517 is a retained harness failure: the
  implementation completed successfully but the requested output token was wrong.
- Water deferred publication/failure checks (083202/083203) still pass with the
  terrain checkpoint integration. No water simulation or visuals changed.
- A cache-identity edit caused parse failures (082300/082341), retained here.
  It incorrectly replaced the standalone raw-save branch too; that branch now
  uses its raw identity, while compound checkpoint saves use the small reference.

Actual source generation: `source/`, report a6db5bff938a88413d5d19060f3c3a07,
world regional_storage_1703_20261023. It created 20 buildings and 367 grading
sections, reopened in a fresh process and published all four stores. Native terrain
matches the prior offline generator (081917); the complete building/furnishing/
water/navigation signature also matches (`source_signature_equivalence.json`).
The loading image was inspected: correct scene preservation, but repetitive
buildings and landscaping remain unaccepted world art/design.

Actual explicit-PCK generation: `bundle_native_argv/`, report
 d4340f6f90ce21f9e3b5a0f5abc1542c, published
regional_storage_bundled_1703_20261023. Creation and fresh reopening run at
1920x1080/fullscreen with a 60 FPS cap. Their child arguments explicitly carry
the same PCK, without a source-project path or Python dependency. The complete
world signature equals the source result. The road loading photograph was inspected.
This does not establish a clean-machine release-template installer.

Two earlier PCK attempts are retained. The first dropped pack identity in child
launches. Parsing OS.get_cmdline_args() alone did not fix it because this engine
consumed that flag. The final native Windows argument reader uses the platform's
CommandLineToArgvW parser; source and packed child launches now share the same
identity. Pure prefix tests plus the actual bundled workflow pass. The UI's stale
script UID warning was also removed by retaining its script UID and matching scene
reference; exported startup now logs no such warning.

`world_entry_review` (085026) passes after the launcher/UID changes. Cold-world
photograph refresh (085113) hashes the cloned world's terrain/root/block/model/
water data before and after, now including `.terrain`. It passes without changing
canonical files. It is a supported existing-world refresh, not an extra runtime
viewport. Source images and the failed logs remain available.

The broad pending-lake shutdown / deleted-ID failures remain reproduced and open
in the adjacent terrain_history_storage evidence. These narrower passes do not
close them. No claim that all persistence or the whole rewrite is finished.
