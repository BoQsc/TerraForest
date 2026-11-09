# Native structures save capture

Status: implemented, scoped save checks pass; stable 60 FPS and general frame-time
nonregression remain open. Implementation: `9a2cd2b8`. Exact run paths, hashes,
measurements, failed trials and resource receipts: [JSON](structures-save-capture-2026-11-09.json).

This milestone returns attention to world-wide stalls. Earlier structures capture
cost 6–9 ms on the gameplay thread even though archive publication already used a
worker. Block/model serialization and repeated validation/hashing were still
inside that capture callback.

`NativeStructuresCapture` now freezes canonical cells, model records and unavailable
region digests on the main thread. The existing ordered save worker encodes them
through the existing codecs. It owns no scene references. Repeated unchanged
captures reuse a payload; encoding releases the frozen buffers and caches bytes.
Edits, paging, checkpoint changes and restore invalidate the facade cache.
Formats, visual data, region identities, generation/epoch ordering, corruption
guards and canonical publication remain unchanged.

The 128 MiB aggregate pending reservation covers frozen values, not temporary
encoder allocations or serialized caches. The existing 64 MiB encoded section
ceiling still applies. Capture is still proportional to resident data, and worker
encoding rebuilds inputs. This moves work off the gameplay thread; lower total
CPU cost, zero-copy ownership and region/delta scalability are not established.
New implementation and fixture are original AI-assisted 0BSD code; no external
material or dependencies were added.

## Verification

- Native debug/release: 25 checks each, including byte-identical full/partial
  capture, concurrent edits, staged admission/rollback, retained identities,
  off-thread capture rejection, memory bound, cache isolation, and serialization
  after scene owners are freed.
- Compound persistence: 64 ordinary and 82 region checks in source; 82 region
  checks in isolated release. Real terrain-worker publication exercises opaque
  captures, shutdown edits, queued reloads, unknown assets and invalid saves.
- Save barriers: 15 checks. Destruction batches: 25 checks. Export building,
  content and packaged light gates pass; all 14 packaged DLL hashes match.
- Four packaged default-world clones save and exit without error/leak diagnostics.
  This does not qualify sustained allocation growth or dense explosive chains.

The new fixture initially missed an explicit extension preload in the isolated
project. The integration harness also needed its existing fullscreen-policy and
water texture dependencies. Their failed logs are retained. A stale assertion
expected three archive sections; the original provider reproduces that failure.
The test now requires the exact four-section contract, including the already
registered `location_baselines_v1`. No save format was changed to satisfy it.

## Actual default-world observation

The unchanged retained Frontier fixture uses generator 29 and seed 1703. The
diagnostic legacy switch is installed only after asynchronous startup completes.
All runs retain normal graphics, world services, 1920×1080 rendering and the
rolling recorder. A = old synchronous provider; B = native frozen provider.

| Run | Structures capture | All provider capture | Triggered gameplay p99 | Maximum |
| --- | ---: | ---: | ---: | ---: |
| A | 11.572 ms | 21.396 ms | 36.501 ms | 702.654 ms |
| B | 0.782 ms | 4.133 ms | 28.492 ms | 39.972 ms |
| B repeat | 0.790 ms | 4.352 ms | 38.101 ms | 47.827 ms |
| A repeat, contended | 7.068 ms | 9.312 ms | 33.371 ms | 54.050 ms |

Both B captures contain 182 chunks, 26 model collections, 832 resident model
records and 373 unavailable-region references. They retain 1,584,460 bytes while
pending, encode 155,898 bytes, and report zero pending/reserved frozen bytes after
publication. The release synthetic ABBA also preserves exact output while main
capture changes from 1.574/1.647 ms to 0.663/0.541 ms.

These observations support a substantial reduction in main-thread save capture.
They do **not** establish improved overall frame pacing: B's repeated p99 is worse
than A's, and save-period frame maxima are 24.987 and 47.799 ms in the two B runs.
Other provider costs vary and are not credited to this change. Triggered-window
statistics are biased toward stalls; the receipts also retain complete scripted
phase distributions.

At B-repeat frame 2500, the trace reports 22.080 ms of physics, 19.862 ms of draw,
and 13.266 ms render CPU time, while GPU time is 8.272 ms. These intervals overlap
and must not be summed. At A frame 3117, 692.813 ms of the 702.654 ms frame is
before process, with only 15.625 ms of reported CPU time in that interval and
0.424 ms measured zombie update. The long wait owner remains unknown.

Device-wide NVIDIA clock/limiting telemetry accompanies both controls. GPU work
in the scripted gameplay phases is roughly 7.6–8.2 ms, unlike earlier ~15 ms
controls; this does not prove a new rendering gain. The final A overlaps a
headless import in the separate handgun checkout, beginning 16:40:08 UTC. Other
host activity is not isolated. This is not a clean ABBA frame-time qualification.

One B launch was rejected before process creation because the disk guard reported
zero free space. A recheck showed available space without file deletion, and a
fresh retry passed. The transient remains unexplained; the guard and failed
manifest are retained. No saves or evidence were deleted.

All four arrival captures were inspected. Brickwork, doorway, hand/tool pose,
HUD and nearby composition match at this view; this is scoped parity, not broad
visual acceptance. Captions and original images:

- [A: unchanged room and player view](../../reports/performance_changes/20261109T163510662885Z_legacy_save_a/arrival.png).
- [B: same view after native save](../../reports/performance_changes/20261109T163741077835Z_frozen_save_b_retry/arrival.png).
- [B repeat: same view, frame pacing still variable](../../reports/performance_changes/20261109T163851059267Z_frozen_save_b2/arrival.png).
- [A repeat: same view with contended timings](../../reports/performance_changes/20261109T163959538634Z_legacy_save_a2/arrival.png).

## Whole-world priorities

The next milestone is broad physics/render attribution and long-frame waits,
not another pursuit-only optimization. Attribute unmeasured physics callbacks,
body/contact work, catch-up ticks, rendering submission and scheduling before
choosing a replacement system. Repeat an uncontended world/player traversal and
save control with clocks and host activity recorded to close pacing nonregression.

Travel selection/upload tails, collision/streaming transitions, dense barrel and
collapse chains, other save providers and long-session memory stability still
need their own event-correlated checks. Revisit native copy-on-write/delta save
ownership when resident scale or save backlog makes capture copying material.
Slow cold pursuit remains a gameplay problem within that wider budget. Existing
six `water_cut_cells` failures and the legacy 81-cell interaction fixture failure
remain visible; this milestone does not resolve them. Multiplayer authority,
replication, population scale and minimum-hardware headroom remain unqualified.
