# Cold lake loading: queue starvation in default meshing

2026-10-11, baseline 5d4d1f3 plus test instrumentation. Both graphical comparisons
use fresh derived-cache paths, a temporary generator4/seed1703 world and fullscreen
1920x1080/cap60. No native binary changes. Manifests retain binary and engine hashes.

## Attribution and change

At 30 seconds, only two of four lakes were ready. Ninety-four completed slices
accounted for 227.109 ms of worker time versus 28,127.531 ms of queue wait; maximum
queue wait was 2,538.234 ms. One slice was still outstanding and the worker was
meshing. This is waiting behind background work, not primarily sampling cost.

The default worker loop serviced density queries before dequeuing another mesh,
but lake service points existed only inside regional meshing. One existing bounded
lake-slice selector now runs before the next job in every meshing mode. It still
stops at mutation/save/load/reset/partition/unknown barriers and admits at most one
slice. The native 2 ms sampling deadline, node cap, one outstanding reservation,
revision/cancellation checks and immutable publication are unchanged.

## Results

All four lakes ready at 2.356, 3.472, 4.739 and 5.889 seconds. The unchanged
30-second gate and all eight Water-page functional checks pass. Across 133 slices,
worker time was 326.527 ms, queue wait 3,775.369 ms, max queue wait 263.828 ms.
Maximum worker slice was 21.501 ms versus 22.743 ms before: identity/cache/finalize
operations are still indivisible and the sampling deadline is not a hard total-job
bound. This is a loading improvement, not a frame-rate or thermal optimization.

Twelve worker scheduling checks pass, including mutation barriers, one-slice
service, shutdown rejection and reservation-through-completion consumption.
Actual graphical water integration passes terrain carving, volume queries, swimming,
accepted-edit invalidation, rebake, completed-worker release and removal during
sampling. Details and scoped frame samples are in edit_integration.json.

The first attempted patch failed its exact-text match because of mixed newlines;
an accidentally launched unchanged check was stopped and is not comparison evidence.
The passing comparison uses the verified four-line worker-loop addition.

Scope: one declared cold-start seed/load and existing edit scenario, not all seeds,
maximum-size lakes, long travel, whole-world save/reopen, sustained frame times,
older hardware or dynamic fluids. Historical failures remain retained in lake_editor.
Next water gate: integrated shoreline/cave occupancy under edits and world reload,
with cached generated water and actual player/vegetation interaction.
