# FPS / world overview

- Status: Improved-partial; whole rendering/modding overhaul remains open.
- Updated: 2026-10-30. Implementation: commit introducing this folder.
- User review: Not reviewed. Engineering evidence is not visual acceptance.
- Symptom: Camera zoom and distant object coverage are not yet a seamless strategy/FPS hybrid.

## Images

All captures use the disposable populated `recipe_generated_4644d8cfc8f97e43`
save, seed 1703, player-following view; the source archive remains unchanged.
Source/build/run hashes are in `images/manifest.json` and linked run manifests.

![Overview near the player](images/overview_32.png)
32 m installed-build overview; existing vegetation and water, no alternative world/map.

![Initial rejected fog washout](images/rejected_fog_768.png)
Initial 768 m source trial: existing distance fog washes out the overview. Rejected
presentation, retained for comparison; tests passing did not make this acceptable.

![Current overview](images/overview_768.png)
Same 768 m view with camera-local fog scaling. Colors improve; coarse terrain,
large flat patches and incomplete forest coverage remain visible. **Not seamless/approved.**

![Maximum overview exposes remaining coverage defects](images/overview_1800.png)
1800 m installed build: large flat grey areas and hard terrain boundaries are
unacceptable for a finished overview. Coverage assertions are not geometry-quality
checks. Diagnose these separately from tree residency; do not hide them with fog.

## Changes and verification

- Native terrain requests accept render focus/projection separately from player
  collision/travel. Coarse coverage survives asynchronous refinement.
- Optional ESC Player overview uses the existing collision boom; wheel zoom and
  mouse orbit do not change physical position, first-person aim or save state.
- Resident tree LOD/culling follows render camera; tree ownership/trunk collision
  stay at the player. Native world-wide building horizon stays enabled.
- Installed fixture: 32/256/768/1800 m; 151 horizon chunks, 2.76 MiB mesh payload;
  no remote editable-building hydration or source-save changes. Frame p95
  18.63–21.48 ms; GPU p95 6.38–8.82 ms. Not a perfect-frame-time claim.
  Sampled process peaks: 3.17 GiB private RAM, 1.39 GiB dedicated GPU allocations.
- Native planner fixture: mean 0.114/0.135/0.122 ms for disabled/remote/high view,
  264/296/264 requested keys; physical activation unchanged. Small synthetic case.
- Generation signature fixture: 4,096 → 32 region captures, 22.058 → 0.326 ms;
  exact digest parity, paging/reload/mutation checked. Not whole generation timing.
- Module fixtures exercise independent controller, external PCK, binary v3,
  missing-provider preservation, malformed data, pooling and parked-kind selection.
- Initial headless parked-mesh readback test failed; the rendered check passes.
  Initial dev-spawner invocation omitted required fleet/gameplay flags and failed;
  the corrected invocation passes. Motion check initially used the wrong completion
  marker; rerun with `MOTION_PARITY` passes. Failed logs remain under reports/checks.
- Installed parked-renderer check initially wrote to read-only `res://reports`;
  it now uses the runner's explicit evidence folder. An external-pack run completed
  before enough GPU samples; tests now keep a three-second telemetry window rather
  than weakening the budget gate. Both corrected installed checks pass.

Evidence: source runs `reports/runtime_views/20261030T063802496788Z` (initial fog)
and `20261030T064221141424Z` (camera-local atmosphere); installed overview
`reports/runtime_views/20261030T072103356539Z`; planner
`reports/checks/20261030T070537951196Z`; signature
`reports/checks/20261030T070538663789Z`. Installed validation is recorded in
`verification.json`; use those exact run manifests for process RAM/GPU observations.

## Remaining / resume here

[Open architecture milestones](../../docs/WORLD_RENDERING_CONTRACT.md): canonical
world-wide tree/medium-object pages, seam-safe volumetric transitions, remote
prop/vehicle tiers, general service providers, full generation/loading profiling
and physical 4 GiB hardware/endurance. Custom vehicles currently use the small-car
envelope; pack inventory registration and native dependency installation are open.
The high view deliberately exposes current gaps instead of claiming they are fixed.

## Reproduce

ESC → Player → World overview camera (preview). Click back into the game; mouse
orbits, wheel zooms, WASD moves the actual character. No remote building/mining.
Turn the checkbox off to return to the normal view. Camera defaults stay unchanged.

Safe automated check: `python tools/check_runtime_views.py world_overview --pack`.
Requires the disposable fixture named above. Offscreen/nonactivating; no OS mouse
capture, no player-save writes. See [vehicle pack setup](../../docs/VEHICLE_PACKS.md).
