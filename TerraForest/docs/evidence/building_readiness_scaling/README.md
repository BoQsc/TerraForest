# Local building-readiness query scaling

The native collision-readiness query previously inspected every authored chunk
before applying its region/occupancy checks. It now enumerates the chunk coordinates
covered by a small local query and looks them up in the existing ordered map.
For wide sparse queries it retains the authored-record scan, whichever touches
fewer coordinates/records. Coordinates are clamped to the existing authored domain
before conversion; large finite inputs cannot overflow the enumeration volume.

This changes candidate selection only. Occupancy masks, transformed bounds,
dirty/pending/disabled collision, budget-deferred geometry and unavailable regions
keep their previous checks. Lookup is O(log authored chunks) per addressed chunk,
not constant time; a local query no longer iterates all distant records. Diagnostic
counters expose queries and candidate probes, not elapsed-time estimates.

Debug and release DLLs built with Zig/prebuilt godot-cpp. Debug-runtime checks:

- `building_readiness_scaling`, report `20261015T214337898024Z`: 512 chunks,
  1,000 small empty-space queries perform 1,000 probes; a far occupied query
  performs one probe and remains blocked. A huge empty layer performs 512 probes;
  a query outside the authored domain performs none. A huge containing volume
  still detects unfinished construction.
- `building_readiness`, `20261015T214337897266Z`: existing negative-coordinate,
  boundary contact, transformed bounds, singular transforms, edits, collision
  disabling, streaming-budget and deletion checks pass.
- `block_regions`, `20261015T214337922710Z`: existing region lifecycle checks
  pass, including refusing movement into unloaded authored space that looks empty.

These are headless correctness/work-count tests, run alongside the release build.
No timing, frame-rate, thermal or end-to-end actor performance improvement is
claimed. Wide queries remain bounded by authored records; this does not replace
the entire storage/streaming architecture or close the full project scope.
