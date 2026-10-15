# Settlement road checkpoint

Water remains deferred. This checkpoint extends the existing furnished settlement
with a 112 m terrain-following asphalt road using the normal road editor pipeline.
It exercises the normal car across terrain region boundaries and retains the
result as a separate, playable `settlement_travel` save.

Run **Review Settlement Road.cmd**. If the checkpoint already exists it opens
directly, preserving progress. Otherwise it copies `combined_gameplay`, constructs
the road, runs the drive and fresh-process reopen checks, then publishes the copy
only after those pass. Prepare Combined Gameplay.cmd must have created the source
first. Preparation assumes the original furnished settlement's first street and
an unused vehicle fleet; modified source worlds may reject the fixture. They are
never overwritten. The review launches paid gameplay at fullscreen 1920x1080,
60 FPS cap. You start beside the parked car at the far end; the settlement lies
back along the road. E enters/exits the stopped car. Escape exposes controls.

`python tools/run_settlement_road_trip.py` repeats validation on a new copy without
launching a human session or replacing an existing review save.

## Recorded check, 2026-10-15

- Road profile fitted and all sections built through existing guarded authoring.
- Ordinary keyboard throttle/braking: 113.90 m including braking distance;
  seven distinct 16 m terrain regions sampled, peak 26.68 m/s (96.1 km/h).
- Car stayed within 3 m of the road centre, stopped, and permitted ordinary exit.
- Fresh process restored exact road entrance data, parked vehicle data and saved
  player pose. Canonical source-save hash unchanged.
- 55 motion samples recorded 59–60 FPS and no streaming hold. This short run
  does not qualify sustained frame time, power/thermals, long distances, turns,
  traffic, dense cities or older hardware. Startup still logged a 151.95 ms
  receive hitch (156.65 ms on reopen).

Evidence: [drive](evidence/settlement_road_trip/drive.log),
[reopen](evidence/settlement_road_trip/reopen.log),
[motion](evidence/settlement_road_trip/motion.json),
[manifest](evidence/settlement_road_trip/run.json).
Earlier setup failures are retained: car aiming placed it outside entry range,
then too near the player before the camera was aimed after settling. The initial
reopen assertion compared a live physics position with a pre-save position;
the final check freezes motion before capture and compares the stored pose bytes.
No runtime movement/road/streaming behavior was changed to make these checks pass.

The initial player placement is fixture setup on the existing street; measured
driving has no teleport, velocity injection or pose correction. Road authoring
uses free development controls; the human launcher returns to paid gameplay.
