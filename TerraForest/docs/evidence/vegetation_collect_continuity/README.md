# Native single-plant removal continuity — 2026-10-18

Cause: NativeStaticBatch::remove_instances called rebuild(touched), which released
all render pages in each touched 32 m group. Streaming republished pages under its
per-tick budget, leaving neighbours invisible between frames. Existing fade tests
waited eight frames and therefore missed the gap.

Single-instance removal now compacts the native render index by moving the group's
last identity into the vacated slot. Only the vacated and tail pages are republished
synchronously before the call returns. Other pages remain resident. Existing fade
birth values survive; removed identity, collision proxy, group bounds and durable
membership update normally. The render index need no longer be sorted, so the
same-group movement lookup uses find rather than lower_bound. Snapshot ordering
continues to come from authoritative ordered placement maps.

At production vegetation settings each page is at most 128 records / 8192 bytes;
a single removal uploads at most two pages / 16384 bytes, independent of the number
of other resident pages. This is an immediate edit path; background streaming still
uses its configured budgets. Bounds refresh/index lookup still scale with the local
group, not the entire world. Bulk mutations retain their existing rebuild path.

Native graphical regression: 900 records in one group, one-page background upload
budget. Seven deletions exercise first/interior/tail/same-page cases. Every survivor
and its fade packet must exist immediately and for each of the next three frames.
Also verifies moving a swap-compacted identity, deletion when tail is nonresident,
residency byte cap and bulk cleanup. Native removal samples 1.110–2.492 ms including
renderer operations on current hardware. Fade and mesh LOD regressions pass.

Actual readonly saved-world gameplay collection: two reachable natural grass clumps
collected through production interaction/inventory/removal path at fullscreen
1920x1080. Every survivor in the touched render group remains identical immediately
and over three subsequent frames. Capture readbacks inspected: only the selected
clump and its shadow disappear; neighbouring grass remains. Collection samples
1.908 and 1.331 ms, excluding screenshots and verification readbacks. No rejected
vegetation publication. Debug and release native libraries rebuilt and installed.

No sustained FPS/thermal or unrelated bulk-edit continuity claim. Initial world
test had a GDScript inference error; fixed explicit integer type, retained log.
