# Native dirty terrain capture

2026-10-23. Scope: immutable native capture and actual compound save/load, not
whole-world readiness, rendering, thermal or sustained 60 FPS qualification.

Both ordinary asynchronous and synchronous/shutdown compound saves now capture
only dirty density/material pages. Captures retain all page keys/versions and
legacy exact blocks, and are globally admitted under a 256 MiB pending-byte cap.
Scripts cannot mutate their native arrays. Publication merges touched regions,
preserves unchanged pack references and verifies retained compressed dependencies.
Only successful outer-root publication acknowledges the native baseline. Failed
publication retains dirty pages; newer edits survive acknowledgement of an older
capture. Reset/load epochs reject stale captures even with reused revisions.

Checks retained here:

- Native capture: 20261023T101829988558Z, including exact initial/incremental/full
  checkpoint equivalence, immutable captures, edit-during-publication, ownership,
  stale epoch, rejected interruption, material-only repaint and legacy exact blocks.
- Production root failure/retry: 20261023T101726284198Z. Canonical protection,
  corruption/missing sidecars, retry without losing dirty pages, exact fresh reopen
  and clone isolation pass.
- Real asynchronous worker migration/reopen: 20261023T101641084623Z.
- Controlled asynchronous race/shutdown: 20261023T101642165897Z; queued save
  ordering: 20261023T101643364546Z. Native edits continue during publication;
  reload/shutdown retain publication barriers and the lease.
- Production history fixture: 20261023T101727127285Z, 2,048 excavations,
  6,612 pages, 81,274,740-byte full archive. First sample capture 23.5 ms;
  unchanged capture 0.106 ms / zero sample bytes; local capture 0.100 ms / 12,288
  sample bytes. Local publication writes 127,043 bytes in two files. Complete
  saves still take approximately 102 ms unchanged / 123 ms local because retained
  compressed regions are verified. These are fixed-order observations on the
  current hardware, not unbiased comparisons or old-laptop estimates.
- Allocation-failure probe still passes 512 cases / 224 forced failures, with
  exact prechange field/receipt hashes and zero tracked allocation leaks.

Earlier failures retained: 101316 unit fixture repeated a contained/no-op brush,
so its dirty assertions failed; 101644 root-failure fixture likewise used a
contained brush. The tests now extend beyond the prior excavation and explicitly
verify that the later archive changes. These were test defects, not ignored passes.

Still required: native selective residency/full-history capacity, retained distant
representations, retention-aware collection/compaction, corruption-safe reduction
of repeated compressed-history verification, combined populated-world performance
and the failed rendered mining-arrival gate. Broad pending-lake shutdown/ID-cursor
persistence failures remain open. No water simulation or visual change here.
