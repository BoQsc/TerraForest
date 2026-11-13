# Combat CPU work after the seed-1703 human playtest

Status: scoped fixes implemented and measured; **60 FPS with headroom remains open**.
This continues the [anatomy admission work](anatomy-geometry-2026-11-09.md).

## Problems and changes

The human confirmed close-range zombie combat during the hitches. The retained
human capture has 133/126 ms gameplay frames with substantial unattributed process
time. Those two stalls are not claimed fixed by this change.

Controlled damage isolated another real cost: an arm sever took 7.98–14.94 ms.
The controller read render arrays and skinned vertices in GDScript during the hit.
It also maintained 15 animated physics hit areas per zombie although ordinary
combat already uses the native evaluated-mesh picker. Corpse restoration built
detached meshes/bodies only to delete them immediately.

- Complete body/cap render attributes now join the existing offline geometry
  resource. Resource identity and change invalidation protect shared immutable
  CPU packets. The first default actor performs zero render-mesh readbacks;
  edited/replacement/unbaked meshes retain a live fallback. The existing inherited
  character provenance is unchanged. The compressed resource grows from 339,622
  to 1,213,565 bytes.
- Native CPU skinning retains the current bone/death pose, normalized or relative
  morphs, normals, tangents and handedness, materials, custom vertex channels and
  untouched attributes. The former script implementation remains an independent
  test reference.
- Redundant hit areas and their bone attachments are removed: 45 scene nodes and
  15 animated physics proxies per zombie. All 14 native damage regions, physical
  ragdoll bones and hand collision compounds remain. Collision shape refresh no
  longer builds a hand hull solely for an unused area.
- Corpse restoration uses the existing no-debris sever operation. Missing limbs,
  caps, visibility, death state and remaining physical anatomy are preserved.

New native/cache/test/tool work is original 0BSD. The retained script reference
keeps its inherited CC0-1.0 declaration; derived character data keeps GAP-002 and
its existing notice. No external material or dependency was introduced.

## Measurements

Both world runs clone the same post-human seed-1703 save. They use 1920×1080
Forward+ Vulkan, normal foreground operation and uncapped pacing. They directly
apply damage to three existing residents, then turn the camera and idle. They
do **not** replay the player's attack input or outside combat camera route.
Residents continue their normal simulation, so their poses/locations differ.

| Measurement | Before | After |
| --- | ---: | ---: |
| Median arm-sever call, three samples | 8.605 ms | 3.852 ms |
| Arm-sever range | 7.979–14.936 ms | 3.254–5.480 ms |
| Combat phases, mean frame time | 14.302 ms | 13.096 ms |
| Combat phases, p95 / p99 | 18.521 / 23.111 ms | 16.683 / 19.434 ms |
| Combat phases, maximum | 43.488 ms | 39.573 ms |
| Missing-limb restore work, head / arm chain / mixed extremities | 12.550 / 6.327 / 3.559 ms | 0.142 / 0.205 / 0.159 ms |

The isolated graphical mesh comparison matches 503 surfaces: the old reference
takes 248.400 ms total, the new baker 20.558 ms total. These are component totals,
not whole-frame speedups. Full-world severing improves about 55% at the median.
Afterward, turning/settled-idle still reach 78.019/74.809 ms and arrival reaches
174.664 ms. Sustained headroom is not qualified.
Peak private commit remains in the resource monitor's warning range, about
4.06 GiB before and 4.07 GiB after; this pass does not establish memory headroom.

## Evidence and verification

- [Human baseline and initial findings](../../reports/performance_changes/20261113T065623989365Z_human_baseline/initial_findings.json).
  Rolling traces may be cold-archived; the owning manifests preserve them.
- [Before: full cadence, actions, source/native hashes](../../reports/performance_changes/20261113T075517708930Z_combat_before/run.json)
  and [analysis](../../reports/performance_changes/20261113T075517708930Z_combat_before/combat_analysis.json).
  This receipt intentionally remains **failed**: the harness incorrectly required
  background cap 15 during an explicitly uncapped run. Save succeeded, all measured
  gameplay frames were focused, and pacing mismatches were zero. The validation
  check is corrected; the failed result is not rewritten as a pass.
- [After: passed capture and retention](../../reports/performance_changes/20261113T081144958492Z_combat_after/run.json)
  and [analysis](../../reports/performance_changes/20261113T081144958492Z_combat_after/combat_analysis.json).
- [Graphical geometry equality and zero first-actor readback](../../reports/checks/20261113T081003778891Z/console.log):
  503 surfaces, four animated/morphed poses, cut caps, death pose, resource edits
  and replacement, four/eight influences, zero-weight fallback and immutable source
  arrays. [Earlier headless comparison](../../reports/checks/20261113T080000356984Z/console.log)
  also passes.
- Corpse restoration [before](../../reports/checks/20261113T075831151479Z/console.log)
  / [after](../../reports/checks/20261113T080016015654Z/console.log): no discarded debris
  construction, identical expected missing limbs and physical anatomy.
- [39 combat/rest/support checks](../../reports/checks/20261113T081017930794Z/console.log)
  pass, including all 14 visible damage regions, every sever root, corpse hits,
  displaced corpses, resting fragments, new impacts and support removal.
- Debug and release native libraries compile. Ten Python launcher/analysis tests
  pass. Installed-package qualification is separate from these source-run results.
- Final [geometry bake](../../reports/checks/20261113T082139896146Z/console.log),
  [geometry cache](../../reports/checks/20261113T082159890676Z/console.log), and
  [character runtime](../../reports/checks/20261113T082212440712Z/console.log)
  regressions pass: 19, 30 and 41 assertions respectively. These follow the final
  native rebuild after source line-ending normalization; that rebuild changes
  binary identities, not the measured skinning implementation.

The earlier script-profiler world run is diagnostic only: profiler printing
introduces large stalls and cannot establish gameplay FPS. The first extended
bake attempt also failed on a script scope error; its receipt remains at
`reports/checks/20261113T080831814397Z_zombie_bake`. The corrected bake passes at
`reports/checks/20261113T080941257898Z_zombie_bake`.

![Before controlled capture](../../reports/performance_changes/20261113T075517708930Z_combat_before/arrival.png)
Before, saved trader-room viewpoint after the controlled damage sequence. This
is an engineering capture, not a reenactment of close-range outdoor combat.

![After controlled capture](../../reports/performance_changes/20261113T081144958492Z_combat_after/arrival.png)
After, same viewpoint and quality settings. Both captures were inspected; the
images do not establish full visual approval or pixel equality of moving actors.

## Remaining work and return criteria

Attribute the original 109–121 ms process intervals and the remaining automated
physics/render/catch-up spikes before choosing another rewrite. Extend the
nonhuman test to real melee input and the recorded outside combat route, then
repeat matched captures at unchanged population, simulation and rendering quality.
Require both damage/persistence equivalence and sustained 60 FPS with headroom;
these short component improvements do not close that gate.

The human harness also still needs normal-menu-exit save completion and explicit
menu-phase tagging before its next human capture. Ordinary successful game quit
did not produce its controlled-finish receipt in the original run.

The fresh-world variety regression now checks native missing-limb state instead
of removed hit-area nodes. Its full rerun remains pending the parallel default
generator repair; saved-world capture and isolated combat/restore checks above
do not depend on that fresh-generation path. Run it with an owned evidence
directory after that prerequisite passes, before claiming full population-suite
qualification.

Reproduce the controlled source run with:

```text
python tools/check_frame_trace_world.py --source StartupBench_FPS_20261113T065623989365 --short --combat-probe --uncapped --normal-window --label combat_repeat
python tools/analyze_combat_probe.py reports/performance_changes/<capture>
```

The launcher owns cloned-world admission and post-exit archival. Do not replace
the source fixture with an already-damaged output clone for an A/B comparison.
