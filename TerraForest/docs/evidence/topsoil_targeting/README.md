# Topsoil targeting correction - review pending, 2026-10-24

This page records the pre-responsiveness baseline. The follow-up replaces the
stable-aim-only cache with a native neighbourhood mask and buffers cold clicks;
see [moving-aim evidence](../terrain_placement_responsiveness/README.md).

The accepted build-friendly generator was committed separately as `b31e7137`.
The user requested this correction be committed as a baseline, but reported that
the marker is too often not green in normal play. Responsiveness remains rejected
and is the next correction; the stationary checks below do not close it. Roads are deferred
until the user approves topsoil placement; no road or block-grid rules changed.

## Cause and correction

The old target rounded `hit + normal * 0.25` to a lattice sample. The octahedron
extends 0.35 m around that sample, so its lower half could disappear into terrain.
Rounding on a low crown can also pick an already-solid sample; command38 correctly
rejects that no-op and refunds it, making repeated placement appear not to work.

A read-only native command39 now examines at most 27 nearby lattice candidates.
It selects an empty sample just outside the aimed surface plane, with a bounded
distance. When necessary, only the visual marker lifts along the surface normal
to keep its 0.35 m tips visible. The actual paid cell stays on the lattice; it must
not skip a whole soil layer just to fit the marker. This is not another edit or a larger
stamp. The existing 0.75 m single-paid-sample command, material identities,
refunding and inventory accounting remain unchanged. Marker size/transparency and
the lack of blocking notices also remain unchanged.

The existing terrain worker owns the query. Shared bounded query slots, revision,
edit-ticket and world-epoch validation reject stale answers; at most one request
is outstanding per player placement adapter. Stable aim reuses its result.
Preview runs at the existing 20 Hz rate; clicks recheck live aim, field revision,
inventory, player/object/vehicle clearance and publication readiness. Pending
answers use an amber marker without a blocking caption. There is no synchronous
scene-thread density scan or GPU readback.

## Scope of checks

Native debug/release pass 70 checks covering repeated placement of all four materials,
100 shoulder probes, an occupied low-crown reproduction, stale revisions and
invalid normals. The first 100-probe sweep found 68 old embedded-marker cases;
its density-ray surface did not reproduce occupied rounding, so the explicit
low-crown case is separate rather than claimed as a measured world-wide rate.

The source integrated forest test passes 33 checks: it places topsoil through real right-click input, verifies
native topsoil readback/payment, adds three more layers, then places a paid grid
block on the player-added soil. It also checks all held terrain materials,
preview-side nonmutation, silent obstruction rejection, and menu/focus/reach/tool
hiding. Original material conservation and mining/reward persistence checks pass.
Broader slopes, caves, rapid moving-aim feel and terrain/object contact aesthetics
still need user review; this is not a claim that block/terrain gaps are eliminated.

Ready, placed, stacked and blocked source captures were inspected. The initial
marker is fully visible over the forest floor; later stamps build upward, and
the blocked prop shows color without a blocking caption. The stacked top-down
capture catches an amber pending-query frame very close to the camera; it is not
a marker-size or steady-performance benchmark. User visual/interaction approval
remains open.

The final exported pack also passes the same 33 graphical interaction checks
(`packaged_world/`), including adjacent-layer stacking and block placement.
Export/startup passes with 14 external libraries; source and packaged terrain
DLL hashes match. Native debug and release each pass 70 checks. These engineering
results do not replace the requested user approval.

## Retained failures

- The first debug DLL installation was blocked by another chat's running test.
  Release validation proceeded independently; debug installation succeeded once
  the test released the library. No other chat's process was terminated.
- The first integrated run passed stacking and block placement but two fixture
  assertions failed: its obstruction prop was inside the newly added soil column,
  and its sky ray hit that column. Moving those probes clear of the column fixes
  the fixture, without changing gameplay rules.
- The first mining check used the wrong success marker (`failures=0` instead of
  its JSON-formatted summary). It exited zero with all 35 checks passing; rerunning
  with the correct marker passes the harness too.
- An added low-crown test exposed an overly conservative first candidate margin:
  fitting the whole marker by moving the target could skip a soil layer. Native
  selection now chooses the adjacent empty sample; visual-only lift keeps the
  marker exposed without moving the paid cell. Adjacent-layer tests guard this.
- The first visual-lift run hit a GDScript type-inference error. Explicitly typing
  the anchor as Vector3 fixes it; the failed owned test was stopped and retained.
