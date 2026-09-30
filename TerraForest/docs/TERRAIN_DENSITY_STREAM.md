# Stream-side density reply freshness

TerrainStream now exposes opt-in `request_density_ray(from, to, token, budget=256)`
and the `density_ray_received` signal. It tracks the native terrain revision from
stats separately from the existing publication counter. Each accepted query gets
a monotonically increasing internal serial, while the caller's token is restored
on delivery. At most eight stream requests remain outstanding.

Admission requires a ready world with no pending edit or shutdown. Replies are
checked against the saved request's epoch, native revision and edit ticket, as
well as the reply's provenance. Non-hit outcomes carry no position/fraction.
Duplicate or unknown serials are ignored. Reusing a caller token cannot let an
old reply consume a newer request.

Accepted edits and reloads explicitly finish outstanding requests as stale;
shutdown/failure cancels them. The request set is cleared before signals emit,
and admission is closed during those transitions. Late native replies are ignored.
This also covers worker results already completed but not yet consumed by the
stream, which worker-side revision checking alone could not protect.

## Evidence

`python tools/probe_terrain_publication.py --density-stream --godot PATH` passes
22 checks with real worker replies held before consumption, then delivered across
an actual edit, reset and shutdown. It includes duplicate suppression, caller token
reuse, forged revision rejection and updated native revisions after edit/reset.
The 38 backend queue checks and 42 existing publication checks still pass.
Reports: [retained evidence](evidence/terrain_density_stream).

No player code calls this API yet. The eventual caller must still reject replies
for an obsolete camera/aim request and arbitrate against building/entity hits.
Normals/materials, query latency under meshing load and rendered-surface accuracy
remain open. Passing freshness checks does not qualify 1080p performance or the
broader world foundation.
