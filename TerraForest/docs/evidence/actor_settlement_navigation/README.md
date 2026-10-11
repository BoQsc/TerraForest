# Furnished settlement actor route and world reload

2026-10-11. Baseline dbe3a59; manifests retain native binary hashes and working-tree
state. Both native targets built; tests use debug. Graphical run uses fullscreen
1920x1080 and a 60 FPS cap, not a measured frame-time acceptance gate.

## Reproduced failure

A disposable copy of the saved generated furnished settlement loaded with all four
tables. An actor began walking from the first cottage's road approach. Normal world
save and reload preserved its exact position and persistent destination and retired
old runtime handles. However, planning from the restored position near the stairs
failed to produce a usable route within eight seconds. The original approach had
worked. Baseline log, trace and image are retained.

The short `actor_stair_origins` fixture reproduces this with the original cottage's
full two-metre stairs and three starting phases: z=9 passed, z=8.167 and z=8.33
failed. No terrain streaming, save or furniture is needed to reproduce it.

## Fix and verification

The planner's capsule clearance adjustment stopped at 15 cm. Near tread edges it
needs up to the same 30 cm already supported by the movement step. The bounded
clearance search now checks seven heights through 30 cm, retaining capsule
occupancy, support, admission and swept segment checks. Riser limits and movement
are unchanged. Worst-case stair-edge queries increase from 24 to 33; the shared
12-unit/cooperative750us scheduler remains unchanged. Flat edges are unchanged.

- Three stair-origin checks now pass, including both retained failures.
- Eight integrated checks pass: furnished world loads, four tables present, actor
  starts, normal save verifies, reload retires handles, exact position/destination
  restored, actor reaches interior, shared work cap holds.
- Screenshot inspected: actor visible inside the cottage doorway after reload.
- Fourteen route-contract checks still pass, including wall detours, edits,
  unavailable collision, sealed areas and departure/return.
- Sixteen clear routes still pass within one second, with 1,000 sleeping records.
- The source save's canonical hash is unchanged. Only a unique copy is modified.

`python tools/run_actor_settlement_check.py` clones the local generated-furnished
checkpoint and runs the graphical route. It requires that source save and the
configured Godot engine to exist, and no competing game should be running. Copies
and fresh derived caches are retained, not automatically deleted.

Scope: one actor, one cottage approach and central interior destination in the
actual furnished saved world, normal save and same-process reload. The fixture
freezes player movement and drives the actor adapter at the real physics cadence
using production collision readiness. This is not a fresh-process continuation,
all four orientations, routing around every furnishing, crowds, regional routing,
general multistorey navigation, sustained performance or older-laptop qualification.
Those remain open; this is enough bounded integration evidence to resume the
broader first-round coverage plan instead of indefinitely expanding navigation.
