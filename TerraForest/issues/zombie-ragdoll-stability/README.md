# Zombie ragdoll stability

- Status: Improved / partial. Dense impact piles and some contact poses still fail.
- Updated: 2026-10-26. Native source and matching debug/release libraries.
- User review: New changes and captures not yet reviewed.
- Symptom: Corpses can chatter, stretch at joints, or remain suspended after support changes.

## Changes and verification

- A reproduced 12 cm support withdrawal left rotated resting parts floating. The
  old half-metre centre ray incorrectly accepted the lower floor as support.
  Cached real contact anchors now use a 5 cm verification segment. Wall contacts
  cannot qualify as ground; resting contact separation is checked too.
- Native contact islands now span different zombie anatomy owners, not just a
  corpse and its own detached limbs. Work runs once per physics frame, with a
  10 Hz support/settling graph, hashed body ownership and expired-body cleanup.
  Disabled/frozen subtrees are excluded. Joints remain connected throughout rest.
- Grounded passive damping is stronger; original airborne damping, gravity
  integration and CCD return when support disappears. No velocity cap, automatic
  death timeout, deleted joints, extra animation motor or collision exemption.
- Shared health, limb health, dismemberment balance, live AI and save schemas are
  unchanged. Test worlds are disposable; player saves are not modified.
- The new regression checks small support edits, rotated shapes, a three-owner
  stack, restored airborne settings and gravity. The stress matrix covers four
  death poses on flat ground, slope, stairs, rubble, a wall, a ledge, eight-corpse
  ground/drop piles, severed chains and far-origin coordinates. It retains strict 8 cm
  anchor, 120 rad/s angular and 2.5 m anatomy-radius gates.

## 60 Hz packaged headless stress results

Peak initial-settle joint separation; sleep count at the end of the settle window.
Each case also checks impulses and a 12 cm support withdrawal. Four corpses per
case, eight in the drop pile; all three phases must pass for a case to pass.

| Fixture | Peak anchor error | Settled bodies | Result |
| --- | ---: | ---: | --- |
| Flat | 66.6 mm | 60/60 | Pass |
| 20-degree slope | 53.4 mm | 60/60 | Pass |
| Stairs | 60.5 mm | 60/60 | Pass |
| Rubble | 70.1 mm | 60/60 | Pass |
| Wall/corner | 73.1 mm | 60/60 | Pass |
| Ledge fall | 86.7 mm | 60/60 | Fails initial 80 mm gate |
| Drop pile | 452.5 mm | 0/120 | Fails impact and rest; peak 261.3 rad/s |
| Severed chains | 58.3 mm | 60/60 | Pass |
| Far origin (1550,45,1550) | 80.4 mm | 45/60 | Fails initial/wake/support-edit gates |
| Ground-level pile | 70.7 mm | 15/120 | Bounded but fails rest deadline |

[Raw final matrix](evidence/pack-stress-final.json),
[exact command/hashes](evidence/pack-stress-run.json),
[failed assertions](evidence/pack-stress.log).
The earlier nine-case matrix at original damping failed 14 gates; the same nine
cases with final tuning fail 7. Adding the ground-level pile gives 8 failed gates.
That is improvement, **not** closure. In particular, do not round the far-origin
80.4 mm result down to a pass. Rejected trials and earlier results stay archived.

Passing ordinary interaction tests does **not** close the failing stress cases.
Instrumented physics timings include observer/spawn cost, not an uninstrumented
gameplay benchmark; another development task briefly ran graphical tests too.

Native debug/release compilation, 50 release health/anatomy checks and 31 release
awareness checks pass. Source regression suites pass anatomy, awareness, geometry
reuse (30), behavior (18), physical hit/severing regions (39), capsule step/slope
contracts and all 15 corpse reactivation phases. Final packaged equivalents pass;
the first package runner's anatomy/awareness **report-directory errors** were
retained and fixed by writing external-driver reports outside the read-only PCK.

The final support regression passes 31 checks, including airborne damping/CCD
restoration, native rest across three anatomy owners and expired-group cleanup.
Early stack assertions mistakenly read a stale `RigidBody3D.sleeping` scene
property after native-server sleep. The corrected test reads authoritative native
statistics; those earlier assertions are harness failures, not proof of suspension.
The contact-anchor-cache trial did not cure dense-pile chatter and was reverted.

Targeted flat/severed runs fail four gates at 30 Hz and pass at 120 Hz. These are
alternative **physics tick rates**, not render FPS measurements. The game remains
at its normal 60 Hz; do not lower that setting as a performance workaround.

Graphical forest interaction passes all 15 phases. Fresh-process packaged corpse
save/reopen passes 18 build / 9 reopen checks, including visible target selection,
rest and physical reactivation. It uses its own `gather_lifecycle_*` slot.
Graphical stairs/severed fixtures remain bounded but each leaves one corpse awake
at the eight-second settle deadline: those two failures remain open, despite the
headless passes. Captures are not evidence of zero motion or player approval.

The final graphical flat case passes, with 60/60 bodies asleep. The ground pile
fails rest (0/120 asleep) and its impulse-phase anchor gate. Actual held-tool combat,
shared/limb health, severing and world corpse restoration pass all 43 world checks.
The initial world-test launch omitted gameplay mode, leaving encounters disabled;
the runner now requests that required mode explicitly rather than bypassing spawn
admission. Its earlier failed launch remains in the local run history.

Hardware: i5-12450H (8 cores / 12 threads), RTX 4050 Laptop GPU, Windows 10,
Godot 4.7.2, 1080p graphical captures. Native/runtime identity is in the archived
run manifests; no new global solver iterations or GPU passes are introduced.

## Images

![Final flat fixture](images/flat-final.png)
Final packaged 60 Hz, isolated flat fixture: all 60 bodies asleep. No world seed.

![Unresolved ground pile](images/ground-pile-unresolved.png)
Final packaged 60 Hz ground pile: 0/120 asleep. This remains a failed case.

![Fresh-process corpse restoration](images/corpse-reopened-final.png)
Seed 1703, owned test slot, final packaged read-only reopen; intact visible corpse.

![Forest contact regression](images/forest-contact.png)
Earlier verified packaged link, temporary seed 1703 forest after all 15 interaction
phases. Different view/pose from the reopen; not a matching before/after pair.

![Earlier stairs failure](images/prior-stairs-window.png)
Earlier 60 Hz graphical stairs: bounded but 45/60 asleep at eight seconds.

![Earlier severed-chain failure](images/prior-severed-window.png)
Earlier 60 Hz severed chains: 45/60 asleep at eight seconds. White diagnostic
materials/camera differ from final gray fixtures. These failures are not erased.

Sources, hashes and build identity: [image manifest](images/manifest.json).
All images were inspected; user visual/motion approval is still required.

## Remaining / resume here

- Diagnose initial-impact joint stretch and persistent contact chatter in the
  retained failing cases. The drop pile falls into a small area from up to 12.6 m;
  this is deliberately more severe than an ordinary ground-level death group.
  Return with reproducible frame/bone traces and compare solver/body geometry,
  not wider assertion tolerances or blanket collision suppression.
- Simple mass/angular/joint substitutions worsened other cases, so a constraint/
  geometry investigation is needed rather than shipping those trials. Retained
  failing fixtures and their existing gates are the prerequisite for that work.
- Require the full stress matrix, existing contact/loot/restoration regressions,
  and reviewed rendered motion before claiming broad ragdoll stability.
- Long-session piles, moving vehicles/doors against corpses, extreme speeds,
  lower-end hardware and aesthetic/player acceptance remain unqualified.
- [Earlier contact/save repair](../../docs/evidence/zombie_corpse_contact/README.md)
  retains its original failures, captures and narrower passing evidence.

## Reproduce / history

Run from the project folder:

```powershell
python tools/check_zombie_ragdolls.py
python tools/check_zombie_ragdolls.py --checks zombie_ragdoll_stress --stress-case pile
python tools/check_zombie_ragdolls.py --checks zombie_ragdoll_stress --stress-hz 30
python tools/check_zombie_ragdolls.py --pack --graphical --checks zombie_ragdoll_stress --stress-case stairs --stress-case severed
```

The complete campaign intentionally exits nonzero while any stress gate fails.
Pack checks require a fresh export with matching external native DLLs. The runner
retains commands, script/native/engine/PCK hashes, logs and every failed check.
Report folders are local and ignored; selected evidence is archived here.

Rejected trials: doubling terminal masses, reducing angular recovery to 0.05,
cone wrists/ankles, hinge substitutions and contact-anchor caching did not pass. Some substantially
worsened high-impact behavior; none is shipped. Their failed results are retained.

Code: [native anatomy](../../addons/world_runtime/native/zombie_anatomy.cpp),
[support regression](../../tests/zombie_rest_support.gd),
[stress matrix](../../tests/zombie_ragdoll_stress.gd),
[campaign runner](../../tools/check_zombie_ragdolls.py).
