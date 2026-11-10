# World and player headroom

Status: ongoing. Stable 60 FPS with headroom is not achieved.
Original code and tests in this change are AI-assisted 0BSD project work;
engine sources were inspected as references, not copied into the project.

## Valid installed-world baseline

`reports/performance_changes/20261110T094742623629Z_world_player_headroom` passes
with zero unfocused samples, approved cap 60 / VSync / background cap 15,
grounded walking, three-barrel destruction, saving and shutdown. Walking mean
is 16.634 ms, p99 21.028 ms and maximum 37.807 ms. Destruction-chain maximum is
24.193 ms. These are complete observation samples; detailed triggered traces are
a selected subset. Screenshot/preparation phases are not gameplay acceptance.
This closes the missing normal-gameplay functional check for the native render
selection change, but does not prove a whole-game FPS improvement or stable FPS.

Trace frame 4119 spends 25.791 ms drawing, including a 21.384 ms gap from
`Cull DirectionalLight3D, Split 3` to `Render 3D Scene`. Main-thread draw cycles
are 11.075 million, similar to neighboring 4.5–5.2 ms draws. Player physics is
0.200 ms and world processing 0.173 ms; pipeline compilation counts do not change.
The [matching engine culling implementation](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/servers/rendering/renderer_scene_cull.cpp)
places scene culling, a worker-group completion wait, mesh updates and shadow
setup inside that gap. A dispatch/synchronization cause is a hypothesis, not a
proven diagnosis of one internal call.

Two source-only serial-culling probes (`095301225182`, `095743401954`) lost focus
and are rejected. Their project setting was restored byte-for-byte; the receipts
are `reports/performance_changes/cull_dispatch_probe.json` and
`cull_dispatch_direct.json`. No culling/quality/pacing policy was adopted.

## Terrain collision preparation

Destruction frame 4645 spends 9.057 ms in processing, including 4.337 ms staging
and 2.447 ms LOD scheduling. Nested stage timings overlap. Preparing each collision
piece attaches it to a layer-zero body already in the physics space. In the
[matching Jolt integration](https://raw.githubusercontent.com/godotengine/godot/ed1daf0bf/modules/jolt_physics/objects/jolt_shaped_object_3d.cpp),
shape addition commits a compound immediately when the body is in a space;
outside a space it avoids that rebuild.

**Retained runtime change:** only retiring terrain bodies leave physics before
shape deletion. This applies recursively to vertical slab bodies. Incremental
preparation and completed cached-body registration retain their original behavior;
geometry, publication ordering, old-surface protection and budgets are unchanged.
The worker fixture also now attaches its manually injected background container,
fixing a test-created orphan (commit `3aece6d6`).

**Rejected preparation experiments:** the following measurements explain why
preparing compounds outside physics was not retained.

The 64-box compound fixture (`reports/checks/20261110T100050238139Z`) measures:

| Preparation | Median build | Median publication | p99 single addition |
| --- | --- | --- | --- |
| In physics space | 1,266 us | 12 us | 115 us |
| Detached until complete | 233 us | 46 us | 38 us |

This isolates compound construction; it is not a claim about all concave terrain
or whole-world FPS. The actual four-region publication test passes 62 checks
(`100143534097`), including physics-space ownership, ray queries, complete old
surfaces until commit, stale replies and same-call publication with available
budget. The worker/coarse/partial-replacement/seam test passes 77 checks without
leak diagnostics (`100408415623`). The first worker run (`100234737535`) is retained
as failed: its manually injected background container lacked a scene parent and
leaked 16 meshes. The fixture now mirrors runtime attachment and asserts ownership;
this was a test-created orphan, not evidence that all gameplay leaks are fixed.

The first installed candidate (`20261110T100818325600Z_detached_terrain_compounds`)
passed functional checks with zero unfocused samples and no diagnostics, but is
**rejected for performance**: walking p99 22.000 ms / maximum 37.837 ms; destruction
recovery maximum 39.067 ms. Coverage activation reached 21.378 ms during recovery
(baseline gameplay coverage maximum 0.910 ms). Per-piece attachment fell from a
traced maximum 2.536 ms to 0.437 ms, but deferred work moved into activation.

A follow-up retained cached registration and prewarmed exact shapes on one
reusable layer-zero physics body within the existing budget. Publication and worker
checks passed (`102021224800Z`, `102003222804Z`), but the installed capture
`20261110T102447301760Z_prewarmed_terrain_compounds` lost focus during walking and
failed movement acceptance. More decisively, foreground destruction recovery still
contained a 24.747 ms coverage stage. This approach is also rejected and removed;
its box benchmark is not representative of full terrain activation.

The remaining retirement-only change passes actual terrain publication
(`reports/checks/20261110T102800472782Z`, 70 checks) and recursive worker/slab/seam
checks (`102836038460Z`, 77 checks) without diagnostics. In the 64-piece fixture
`102909821845Z`, freeing a live layer-zero compound costs 569 us median / 878 us max;
detaching before freeing costs 138 us median / 335 us max. This is a scoped teardown
measurement, not a whole-game FPS gain. Final installed gameplay passes (details below).

Outdoor and destruction screenshots were inspected against the baseline. The destruction view contains floating vegetation/exposed terrain in both versions; this is an existing visual defect, not visual-quality acceptance.
The scoped retirement gate is closed by the installed capture and image review
below; whole-game frame-headroom acceptance remains open.
The renderer wait and occasional actor admission costs remain open separately.

## Final retirement-only installed check

`reports/performance_changes/20261110T103412999213Z_retired_terrain_compounds`
passes walking, three-barrel destruction, saving and shutdown with zero unfocused
samples and no diagnostics. PCK SHA-256:
`041f238f863a48ce38e9e3face0873c4e15901f3647d326b507ad7fade8679d9`.
The export validates all 14 external native libraries. RAM private-commit peak is
4.05 GiB (warning); this is not an endurance/leak-freedom claim.

| Phase | Mean ms | p99 ms | Maximum ms |
| --- | ---: | ---: | ---: |
| Grounded walking | 16.634 | 20.525 | 22.202 |
| Explosion chain | 16.615 | 22.720 | 22.720 |
| Destruction recovery | 16.634 | 21.088 | 39.991 |
| Save during play | 16.364 | 18.108 | 18.108 |

Coverage maximum in retained gameplay traces is 1.039 ms, with incremental
preparation restored. Outdoor and destruction screenshots were inspected against
the baseline; the pre-existing exposed terrain/floating vegetation remains visible.
There is no quality reduction in this fix, but those visual defects remain open.

Recovery frame 5267 spends 27.749 ms drawing, including a 22.508 ms gap from
`Update Occlusion Buffer` to `Update Visibility Dependencies`; player physics is
0.061 ms and world processing 0.170 ms. Scene-culling waits are not the sole remaining
renderer stall. The matching raycast occlusion implementation dispatches worker
groups and waits for completion; marker gaps do not identify a single internal call.

## Renderer dispatch diagnostics

The installed serial-culling probe
`20261110T103653161133Z_cull_dispatch_serial_installed` passes with zero unfocused
samples. Walking p99/max is 20.536/23.443 ms, destruction recovery 19.179/21.825 ms.
However, settled idle still reaches 26.232 ms, with a 10.618 ms occlusion-update gap.
The headless preflight confirmed the effective setting was 65536. Its temporary
`dist/override.cfg` was removed in `finally`; receipt
`reports/performance_changes/cull_dispatch_installed.json` confirms restoration.
No permanent renderer setting has been adopted from this one comparison.

A four-worker-pool diagnostic was prepared but did not launch: storage admission
blocked it before any override or world was created. It remains the next isolation
step, not a measured result. The stock worker setting remains installed.
The final acceptance gate remains repeated normal gameplay with frame headroom,
no changed visibility/collision/gameplay, and no new leak diagnostics.

## Bounded evidence retention

Raw traces for rejected runs `095301225182`, `095743401954`, `100818325600` and
`102447301760` are cold-archived through the existing verified chunk store. Each
original report has `traces.archive.json` containing original file hashes, chunk
order and owning run/completion hashes. All 21 files were reconstructed and verified
before removing only their exact loose paths: 70,381,549 bytes reclaimed versus
4,308,875 archive bytes added. Observations, screenshots and run records stay loose;
the valid baseline and final comparisons stay ready. Restore any manifest through
`tools/maintain_performance_artifacts.py --restore MANIFEST --destination NEW_DIR`.
No save, regression evidence or budget was discarded or raised.
