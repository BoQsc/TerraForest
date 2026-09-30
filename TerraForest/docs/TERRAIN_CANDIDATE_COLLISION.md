# Candidate collision qualification fails on tiny triangles

Run `python tools/probe_terrain_candidate_collision.py --godot PATH`.
The runner rebuilds and verifies native candidate fixtures, expands their exact
indices to triangle faces in the test harness, and loads a temporary headless
Godot project with the existing release native collision extension. The expansion
is diagnostic Python/GDScript plumbing, not a proposed runtime implementation.

All fifteen fixtures pass native recipe admission and exact face preservation.
The recipe pieces are resolved into real ConcavePolygonShape3D objects attached
to a StaticBody3D, then queried after physics updates. Twelve deterministic triangle
centers per fixture receive short normal-aligned rays with backface queries enabled.
The existing test threshold requires a hit within 0.002 m of each center.

## Rejection evidence

The retained [report](evidence/terrain_candidate_collision/terrain_candidate_collision.json.gz)
contains 46 checks: eleven fixture ray groups fail. Of 180 individual rays, 159
pass and 21 return no hit. Every failed ray targets a triangle with cross-product
length 2.38418579101563e-7, i.e. area approximately 1.19209e-7 square metres.
Per-ray vertices, triangle index, area, hit state and distance are recorded.
The [log](evidence/terrain_candidate_collision/terrain_candidate_collision.log.gz)
identifies Godot 4.7.2 Steam revision ed1daf0bf. Source, DLL and fixture hashes are
retained, along with the generating native report.

This contradicts collision readiness despite the earlier topology, exact partition
and nonzero-area checks passing. It points toward numerical sensitivity around
very small faces; it does not yet isolate physics cooking from ray intersection
precision, or prove player-sized bodies fall through those locations. The current
zero-value displacement convention is a candidate cause to investigate, not an
established diagnosis.

Do not delete tiny faces, skip their rays, or enlarge tolerances to claim success.
Next isolate these faces at local coordinates and with single-triangle controls,
then evaluate a topology-preserving treatment of exact-zero samples against both
partition equality and actual collision queries. Keep the existing failure as the
baseline. Runtime mesher adoption remains rejected. This headless test does not
qualify cooking cost, worker publication, visuals, 1080p FPS or endurance.
