# Transactional terrain brushes - 2026-10-23

A targeted allocator check reproduced partial authoritative edits on failure.
The old new-page case returned false, changed its archive from 36 to 12,328 bytes
and reported four changes. The existing-page case returned false and changed
stored density without changing archive size. Original results are in before.json
and before.log. This is a confirmed defect, not hypothetical capacity exhaustion.

Brush/graded-bed edits now stage changed samples and virtual first-touch pages,
reserve metadata, and allocate every needed density/material page before applying
any staged sample. Failure rolls back newly allocated pages and preserves existing
samples, metadata and reward receipts. Virtual admission preserves the old page
order, quantization and material repaint semantics. Existing exact-block removal
runs only after successful field admission. No resident-cap increase is involved.

The first candidate also exposed a pre-existing Map::put allocation bug: a failed
initial table allocation could retry with capacity zero and access invalid memory.
That candidate exited with Windows access violation 3221225477. The map now returns
cleanly on initial/growing allocation failure. This intermediate failure is recorded
here from the observed process result; its blank buffered stdout was not useful.

Native protocol edit replies and the GDExtension result are allocated before brush
mutation. Successful fixed-size replies require no allocation after committing the
field. This applies to commands 2 and 28, not an assertion that every unrelated
command or engine allocation failure has been exhaustively qualified.

The current probe sweeps 512 combinations of empty/additive and natural/mining
fields, existing/missing pages, direct edits/protocol dispatch, allocation and
reallocation, and failure positions 1-32. It exercises 224 actual forced failures,
checks exact rollback or successful state, and ends with zero tracked live native
allocations. A failed process or missing fixture file is always a failed probe.

Eight frozen SHA256 fixtures were recorded against core.cpp from commit 8b756bb8
before changing edit arithmetic. Successful fields and receipts remain identical
for generators 1, 3, 5 and 19 through sphere, cube, capsule, road/curve, material,
bedrock and boundary edits. The three full generated earthworks archives also
retain their prior hashes for seeds 0, 42 and 1703. The actual mining rewards,
compound save/reopen and teardown guard check passes all 25 assertions.

The 2,048-excavation native history check still passes exact restoration and
control queries: late edit median/p95 approximately 0.471/1.111 ms in this sample.
These are native CPU/data checks, not rendered mining latency, sustained frame
pacing, thermal qualification or proof of all large-world capacity. The failed
150 ms first-visible arrival gate, full-history capture, selective paging and
retention-aware collection remain active requirements in TERRAIN_REGIONAL_STORAGE.

Run: python tools/probe_terrain_edit_atomicity.py; then the retained Godot checks
terrain_history_scaling, generation_earthworks and mining_rewards. The pre-change
fixture hashes must not be regenerated to hide a behavior change.
