# Dense woodland review

Run **Play Woodland Preview.cmd** to walk through a disposable dense patch in
the actual terrain/forest world. Normal saved worlds are not opened or changed.
The preview creates a fresh derived cache and blocks snapshot writes. Closing
discards edits; F5 does not make a persistent version of this preview. The cache
and launch logs are retained. Use the normal window close action to exit.

The current generator1/seed1703 patch contains 818 grass clumps, 63 ferns, 18
stones, 12 flowers, 16 bushes and 19 twig clusters in14.4 by14.4 metres, across four existing placement owners. A curved gap
leaves a walking path, with clustered plants beside it. It uses the same native
ground-cover state, support checks, picker and rendering batches as gameplay.
This is a local authored preview, not a global vegetation density increase.

WASD/mouse control the normal player. H enables removal/placement; keys 1-8 choose
stone, fern, grass, white/gold/violet flowers, bush and dry twigs. LMB/E removes and RMB places in the free editor. G toggles flight.
The launcher starts fullscreen1920x1080, cap60, with the normal15FPS unfocused cap
restored after preparation. Automated screenshots/checks keep cap60 throughout.

The evidence at `docs/evidence/woodland_patch` includes two player-height views.
This makes the art easier to judge, especially repeated tuft silhouettes, thin
blade aliasing, spacing, plant clusters and the stone material. These remain
first-pass assets; the dense view is not final visual acceptance.

The120-frame cost sample after screenshot readback settled records frame p95
18.774ms, maximum20.949ms and GPU p95 5.811ms on the current RTX4050 laptop. It
**misses** the declared18.5ms frame-p95 gate. Do not call it sustained60FPS, an
old-laptop comparison, thermal qualification or proof that vegetation caused
the whole frame cost. No unchanged benchmark reruns or optimization campaign
were performed to turn that result green.

## Support correctness exposed by density

Initially945 authored records were accepted but only170 passed publication.
Natural surface placement used trilinearly interpolated terrain density while
authored support used floor-rounded voxel coordinates. Native command31 now
provides a bounded, revision-checked interpolated query. Ground-cover support
uses it; existing command29/30 semantics stay unchanged for other clients.
The backend validates and retains the interpolation flag across its worker
handoff. All945 patch records now publish. This is a resident record count,
not a count of instances within a particular view frustum.

Native debug and clean-release checks pass10 each:64 valid natural surfaces also
pass authored support, where the old query rejected40; independent interpolation
error stays below1e-5. Stale/invalid/oversize inputs are rejected. Streaming83 and
actual-world interaction/exclusion/mined-support regressions pass. Automated
preview handoff confirms normal1.68m eye offset and ground collision. The pinned
Zig/prebuilt SDK was reused; no godot-cpp sources were compiled.

Original failure logs remain, including the initially dropped handoff flag and
a fixture assertion that incorrectly compared command-specific response headers.
The first release invocation passed native assertions but its wrapper required
a JSON report the fixture did not yet write; the fixture now writes it and the
complete release invocation passes. These are separate from the retained frame
gate failure.

Latest accent preview and checks: `docs/evidence/woodland_accents`. Earlier measurements
and the support-fix history below/above remain historical evidence.

The latest shape revision replaces narrow grass fans and crossed dry sticks with
leafier grass and standing woody scrub, and fills out bush crowns. See
`docs/evidence/woodland_shape_review` for matching camera captures and costs.

F7 toggles the optional generated grass texture at subtle strength. It starts
off each session and does not change saves or geometry. Comparison captures and
short GPU observations: `docs/evidence/grass_texture`.
