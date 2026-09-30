# Tiny-face collision isolation

`python tools/probe_terrain_collision_isolation.py --godot PATH` reads the frozen
21 missed-ray triangles from the candidate collision report. Each triangle is
cooked alone through the existing native recipe interface. The test varies three
coordinate representations (world vertices, local vertices on a translated body,
and origin), four geometric scales, and three ray lengths: 756 cases total.
Scaling is a diagnostic intervention, not a proposed change to the world.

The retained [report](evidence/terrain_collision_isolation/terrain_collision_isolation.json.gz)
and [log](evidence/terrain_collision_isolation/terrain_collision_isolation.log.gz)
record physics queries, Geometry3D ray tests using segment-sized directions, and
Geometry3D ray tests using unit directions. All cases completed on Godot 4.7.2
Steam ed1daf0bf. Runner success means the experiment completed, not that the
candidate passed collision qualification.

Every coordinate representation gives the same outcomes below. Each table entry
applies to all 21 triangles; ray length is total segment length.

| Triangle scale | Physics 0.04 m ray | Physics 4 m ray | Physics 40 m ray | Unit-direction Geometry3D ray |
|---|---|---|---|---|
| 1 | Miss | Miss | Miss | Miss |
| 4 | Miss | Hit | Hit | Miss |
| 16 | Miss | Hit | Hit | Hit |
| 64 | Hit | Hit | Hit | Hit |

Segment-direction Geometry3D tests match physics hits in every tested case.
This supports an intersection-tolerance sensitivity involving both triangle size
and ray direction magnitude. It does not identify a particular engine source
constant or prove contact behavior for player-sized bodies. The single-triangle
controls eliminate another triangle intercepting the ray as the explanation.
Moving these faces to the origin does not resolve their failure.

The original faces have area approximately 1.19209e-7 square metres. The result
rejects coordinate rebasing alone as the fix for these misses. Keep the original
ray thresholds and frozen evidence. Next investigate the candidate's displaced
exact-zero intersections and a topology-preserving treatment that avoids tiny
faces while retaining valid partitions. Dropping triangles or scaling the world
to satisfy these tests is not an accepted solution.
