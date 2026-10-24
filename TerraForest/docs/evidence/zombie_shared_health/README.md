# Shared zombie health and restrained severing, 2026-10-24

User request: all hit locations share health; dismemberment should be much rarer
with ordinary attacks than with guns or powerful weapons. Changes follow the
accepted `ea884f42` baseline. After playtesting, the user requested higher
dismemberment frequency for now and committing/pushing all current work. The
current tuning below implements that request; older verification records retain
their original, lower-trauma values.

## Behavior

Previously the main combat bar displayed the struck limb's small durability pool,
while arm/leg hits deducted only 35%/45% of their damage from overall health.
Depleting a limb immediately severed it, so a few tool hits could remove a chain
while leaving most of the zombie's life intact.

Native anatomy now subtracts full base damage from one 180 HP total for every
attached hit region, including the head. Changing regions never resets the bar
or reduces damage. Following the user's clarification, the HUD shows shared health
as its primary bar and the struck limb's independent health as smaller text and a
thin secondary bar. That secondary display is visible now; making it debug-only
is a later option, not silently enabled here. Internal limb integrity remains for local injury/sever effects and existing
anatomical movement/attack restrictions. Torso state mirrors shared health.

Sever trauma is deterministic and independently weighted by impact profile:

| Profile | Integrity damage | Current use |
| --- | --- | --- |
| `unarmed` | 0% | Empty-hand punches |
| `melee` | 30% | Pickaxe, repair hammer, assembly tool, shovel |
| `cutting` | 50% | Light hatchet |
| `heavy` | 100% | Explicit stronger-weapon adapter profile |
| `firearm` | 100% | Explicit projectile adapter profile |

The follow-up raises ordinary melee trauma from 10% to 30%, and cutting from
25% to 50%, without changing overall damage or either health display. A
15-damage hatchet now needs four focused hand hits instead of seven, or six
forearm hits instead of eleven. A 20-damage blunt hit can sever a hand on its
fourth focused strike. These remain harder thresholds than the original two/three
hatchet hits before the shared-health work. Punches still cannot sever.
Powerful impacts can still sever quickly, and head detachment remains fatal.
No gun item or firing system is introduced here. Public profile arguments have
backward-compatible defaults; explicit developer force-sever remains available.
Attack contact timing, base weapon damage, wear, occlusion and native body
ownership are unchanged. No new per-frame scans, workers or random rolls are added.

The integrated strong-hit test also exposed corpse saving indexing a physical
bone already removed by detachment. Missing regions now serialize a valid pelvis
placeholder alongside the existing missing-parts mask; the placeholder is not a
restored limb. Binary layout, loot identity and intact-part transforms are unchanged.

## Increased-severing verification

The current 30%/50% tuning passes 50 native checks in both debug and release,
including the exact hand/forearm thresholds and unchanged overall damage. The
39-check surface/anatomy/ragdoll fixture passes. The scoped source-world test
passes 45 checks in both source and exported builds: actual animated hatchet strikes sever the forearm on its sixth
focused hit, remove the attached hand, charge one tool wear per strike, retain
45 overall HP after the mixed-region sequence, and show zero limb HP plus the
severed label without resetting overall health. The resulting image was inspected.
The new records are under `increased_severing/`; export/startup and packaged
interaction checks pass, and source/package native DLL hashes match.
None of these scoped checks closes the existing full-world
corpse-settling failure recorded below.

## Earlier verification and retained failures

- Native debug/release each pass 43 checks: every region, mixed-region damage,
  weak attacks through death, focused cutting threshold, strong/firearm severing,
  invalid inputs, chain removal, corpse damage and explicit force-sever.
- Surface/anatomy/ragdoll fixture passes 39 checks, character runtime passes,
  encounters pass 17, dragging/crawling passes 24, and attack timing passes 27.
- Actual-world checks confirm animation-timed shared damage, one HUD total while
  switching between forearm/torso/arm/head, exactly-once wear, intact forearms after
  three weak cuts and strong-hit detachment. The shared-health HUD capture was
  inspected. Export/startup passes and source/package native DLL hashes match.
  The final exported-world run passes 37 of 38 assertions, including all shared
  health, HUD, weak/strong severing, timing, wear and corpse-data round-trip checks.
  It fails the separate six-second all-pieces-asleep check described below, so the
  overall combat-world suite is not reported as passing. No script errors remain.
- The first world command mistakenly disabled zombies and could not admit its
  fixture. Corrected commands use `--zombies`; no spawn rules were weakened.
- An initial character runner required the wrong completion marker. Assertions
  passed; rerunning with `CHARACTER_RUNTIME_OK` passes.
- The first enabled-world run passed 36 assertions but emitted the missing-head
  corpse-save script error. That failure is retained; subsequent checks explicitly
  validate missing-part pose bytes and a fresh native store restore.
- Subsequent source and packaged world runs passed the health/limb/save checks but did not have all
  corpse pieces sleeping after its six-second deadline. The previous enabled run
  did settle fully. This intermittent settling check is retained, not waived;
  no physics thresholds or deadlines were loosened to make it pass. The isolated
  39-check anatomy/ragdoll fixture still passes. A separate varied-pose/terrain
  settling investigation remains necessary; this balance change does not close it.

No limb pool was removed by the shared-health correction. The display follow-up
changes presentation only; ordinary/severe impact weights and shared damage remain
unchanged. Severe/critical trauma is represented by weapon impact strength, not a
new random critical-hit roll. A `--zombie-health-only` regression scope checks the
HUD and live attacks independently; its pass must not be treated as closing the
full combat suite's documented ragdoll-settling failure.

The secondary-display follow-up passes 35 health/HUD-only checks in both source
and exported worlds,
including independent forearm health after hits on other regions, main-health
continuity, switching back to the wounded forearm, and hiding the limb display
for non-zombie targets. Native anatomy still passes 43 checks. The rendered
overall/limb HUD was inspected: overall HP remains the larger primary bar, with
limb HP on a thin subdued bar below it. Export/startup and packaged HUD verification pass; the
older 37/38 full-suite result above remains historical evidence of the open
ragdoll issue, not a passing result for the display follow-up.

The latest tuning is a requested provisional baseline, not a claim of final
combat balance. Existing ragdoll variability,
navigation and larger-world performance qualifications remain separate; the new
health rules do not claim to solve those. Corpse data tests cover the current
binary serializer and fresh native-store restore, not a fresh-process world reload.
