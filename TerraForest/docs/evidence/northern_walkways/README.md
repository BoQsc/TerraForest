# Northern pedestrian walkways — 2026-10-18

The northern recipe adds two-metre concrete walkways along the inner street edges,
with crossings at the arterial, cross streets and building entrance paths. Paving
uses existing native concrete cubes with their top at street grade, avoiding a
half-/one-metre curb. The terrain bed is recessed 0.1 m to prevent coplanar terrain
and block rendering. Entrance ramps are applied afterward through the existing
native terrain edit path; paving is interrupted at those ramps.

The blocks are authored once in the generated world and persisted/streamed through
the normal native structure system. No additional runtime script, individual node
per paving tile or separate sidewalk renderer is added. This is not a claim of
zero runtime cost: the native structure data and collision workload are larger.

Seven-seed lot/road checks pass. Native seed-42 grading checks all 3,504 building
and walkway support samples with none unsupported. Geometric checks reject paving
inside traffic lanes. An initial diagnostic bake was intentionally stopped before
publication to correct an entrance-opening offset; it did not replace a user save.

Complete generation and fresh-process restoration pass in walkways_42_20261018.
Overview and ground view were inspected: concrete paths are visibly distinct from
the asphalt, with level crossings rather than high curbs. Planting/public-space
design remains separate work; these paths do not establish overall world quality.

All twelve entrance roundtrips pass after paving. The continuous pedestrian loop
passes all 7 waypoints with ordinary W/Shift, including street/arterial crossings.
Movement p95 17.660 ms, worst 20.286 ms. This short route does not qualify sustained
60 FPS, vehicle use, ecology or thermal performance.
