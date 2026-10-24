# Gathering boulders, falling trees and corpse storage — 2026-10-24

Large gathering stones reuse a sparse deterministic subset of existing native
base-stone identities. Their varied scales produce roughly 4–11 m widths; steep
support rejects the boulder rather than changing its identity into a small stone.
Native scattering/picking, shared mesh rendering, saved removal masks and the
usual structure/water exclusions remain in use. Tree anchors exclude overlapping
boulders. Road clearance additionally samples the full large footprint. Nearby
solid proxies use the existing bounded native collision collection and participate
in player/actor readiness and route invalidation. A boulder has 240 durability and
yields 24 existing stone items when mined; ordinary E pickup cannot bypass mining.

Successful tree harvest removes its standing render/collision/harvest identity
once and starts a native transient toppling instance using the shared source mesh
and materials. It tips away from the strike, samples three landing points, eases
into the landing, then fades after five seconds and retires at six. At most sixteen
falls are active. This is cosmetic animation: it does not introduce another
physical integration owner, falling-tree damage or permanent log obstacles. The
existing four-wood reward and persistent removal remain unchanged.

Zombie death now creates a stable native corpse inventory containing a few stone
and wood items, with occasional clothing. E over the skinned corpse surface opens
the standard inventory transfer/drag UI, including depositing items. Contents
never refill after reopening. The native binary corpse section publishes inventory,
identity, missing-limb mask and all fifteen physical-bone poses together with the
player inventory in the compound world save. The pelvis is included. Bodies
stream out beyond 96 m; stored contents survive and bodies can return within 80 m.
At most twelve corpse bodies are resident, independently of the six living
encounters. Native nearby queries return a bounded candidate set from at most
4,096 saved records. Empty corpses can retire; nonempty inventories are retained.
Menus and unavailable collision freeze corpse physics. Pose capture occurs on
save, settling and retirement, rather than iterating every bone every frame.
Detached fragments remain transient; the saved mask retains anatomical loss.

## Verification

Source interaction/save/reopen evidence and final packaged interaction/save/reopen
evidence are retained separately. The final packaged check passes eighteen live
checks and six fresh-process checks: actual world/component initialization, native
boulder distribution/picking, rejection of pickup bypass, stone reward and repeat
harvest rejection, natural tree harvest/toppling, real zombie death/loot creation,
skinned corpse picking, E storage UI, paused corpse physics, native withdrawal,
truncated-packet rejection, naturally streamed boulder imagery, compound save,
matching restored corpse/player packets, persistent harvest masks, restored corpse
residency and orderly shutdown. Unique `gather_lifecycle_` slots protect user saves;
the reopening process is read-only. The harvest fixture exercises the actual
collection transaction; mining durability/animation timing still uses the existing
world attack path, now selecting the boulder's larger maximum.

Container-store (23 checks), ground picker (20) and ground scatter (1,084) regressions
pass. Both modified native addons were built for debug and release; export/startup
passes with fourteen external libraries. Run manifests retain commands, native/test
hashes, parent revision and the packaged PCK hash.

The natural boulder, toppling/fallen tree, loot panel and restored corpse images
were inspected. Standing tree rendering is hidden in the tree-only captures to
make the fall readable; normal forest rendering is restored afterward. These
captures are feature evidence, not settlement-art acceptance or a frame-time
qualification. Existing navigation/world-quality/storage-scaling gates remain open.

## Retained failures

- The first native tree build omitted the complete Mesh header; the compiler log
  is retained and the include was corrected before either build was accepted.
- The initial scene fixture supplied an untyped empty array to a typed publication
  argument. Correcting fixture setup resolved that script failure.
- Early reopen fixtures compared a pose captured before the final shutdown save;
  only small physical-pose floats differed. The fixture now compares against the
  actual final publication, without relaxing byte equality.
- Packaged reopen exposed a fixture race: disabling the player physics callback
  also stopped the real zombie update loop. Corpses appeared only if the host had
  received a tick before that. The fixture now drives the actual zombie host each
  physics tick while keeping its player/camera stationary, including normal menu,
  focus and readiness gates. Earlier focus-only correction did not close this;
  both failed packaged attempts remain visible.

Logs/manifests for these attempts remain under `retained_failures/`.

Reproduce from the project directory with the configured Godot executable:

```powershell
python tools/check_gathering_lifecycle.py
python tools/export_pack.py --godot $env:GODOT_EXE
python tools/check_gathering_lifecycle.py --pack
```
