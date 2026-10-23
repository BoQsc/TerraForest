# Zombie Lab — R4 Actions & Behavior

Open `project.godot` in Godot 4.5.2 (the version used for validation), let the three active GLBs import, and press **F6/F5** to run the main scene/project. The project uses native Godot APIs with no addons. Blender source and the reproducible R4 authoring script are included.

## Versions

| Selection | Role | Complete model | Editable source |
| --- | --- | --- | --- |
| F1 | Original / Main; startup default | `assets/Zombie.glb` | `source/Zombie.blend` |
| F2 | Preserved original alternate | `assets/Zombie.r2.glb` | `source/Zombie.r2.blend` |
| F4 | Active R4 development; new actions and behavior | `assets/Zombie.r4.glb` | `source/Zombie.r4.blend` |
| F3 / R3 | Deprecated; archived, no active selection | `archive/r3/Zombie.r3.glb` | `archive/r3/Zombie.r3.blend` |

F1 and F2 retain their original model, rig, animations and Blender source bytes. R3 remains available as an archive. The R4 from before this action update is preserved in `archive/r4.previous/`. The visible asset label identifies the model actually loaded. `assets/zombie.revisions.json` records the exact matching file hashes and timings.

F1 remains the default each time the project opens. Selecting F4 loads its complete GLB and enables the new controller features. Reset restores the current selection. Selecting a version restores its limbs, preserves the inspection camera, and carries a paused frame across when the destination supports that clip; an unsupported extra action falls back to Idle.

This update remains **F4 / R4**. Its visible label is **`Zombie.r4.glb · 15 clips`**. Unzip the complete package into a fresh folder when replacing an older download, then open the included `project.godot`; this keeps the model, behavior contract, controller and preview evidence together.

## Run the demonstration

1. Press **Esc** to release the pointer.
2. Click **Run R4 demonstration**. This selects F4 and restores an intact R4 zombie.
3. Observe pursuit, a close bite, left hand, right hand and both hands, a short hop over the bar, ladder ascent and platform exit, then one-leg and both-leg loss followed by living crawl pursuit and biting.
4. Orbit with the mouse to inspect the interaction. **Stop** leaves the current subject available to inspect; **Restart cycle** restores the stations and zombie. A completed demonstration repeats until stopped.

The demo uses a collidable target, the real zombie controller, its animation contact markers, and the actual limb-severing system. Target health changes only after a validated hit. Attack stages wait for contact and recovery. Traversal stages wait for a real landing or platform exit. The station controller arranges the demonstration and requests actions; the zombie controller decides whether each request is physically and anatomically eligible.

The live card shows the station, movement mode, current action, target health, and confirmed contact count. F1/F2 stay available throughout.

## Inspection and controls

| Control | Action |
| --- | --- |
| F1 / F2 / F4 | Select a complete active version |
| Action dropdown | Preview any animation exported in that version |
| 1 / 2 / 3 / 4 | Idle / Shamble / Original attack / Hit reaction |
| P or Pause / play | Freeze or resume the current animation |
| Comma / Period, or −1 / +1 frame | Step one authored 60 Hz frame; endpoints are clamped |
| Tab | Switch first-person and orbit inspection |
| Mouse in orbit | Rotate inspection view; wheel changes distance |
| Esc | Release the pointer for buttons and dropdown |
| Left mouse button | Damage the hit region under the pointer |
| Right mouse button | Sever the selected limb chain |
| E | Trigger ragdoll death |
| R | Restore the current version and all limbs |
| G | Toggle pursuit of the player |
| C | Show or hide fitted collision proxies |
| W / A / S / D, Shift, Space | Move / run / jump as the player |

The action dropdown is an animation preview. The demonstration exercises actual root movement, targets, damage, and traversal. While a looping animation is paused, the inspector holds its true last pose without wrapping; its original loop setting returns when playback resumes.

## R4 animation set

R4 contains 15 clips at 60 Hz. The four base clips are preserved, and 11 clips are added. Frame endpoints below are inclusive when inspecting; a clip from frame 0 to frame 81 has a duration of 81/60 seconds.

| Clip | End frame | Duration | Contact / use |
| --- | ---: | ---: | --- |
| Zombie_Idle | 180 | 3.00 s | Preserved base idle |
| Zombie_Walk | 84 | 1.40 s | Preserved R4 shamble; 0.72 m/s reference |
| Zombie_Attack | 96 | 1.60 s | Preserved original R4 attack; frame 42 |
| Zombie_Hit | 36 | 0.60 s | Preserved upright hit |
| Zombie_Attack_Bite | 81 | 1.35 s | Mouth contact at frame 36 |
| Zombie_Attack_Left | 78 | 1.30 s | Left-hand contact at frame 32 |
| Zombie_Attack_Right | 84 | 1.40 s | Right-hand contact at frame 36 |
| Zombie_Attack_Both | 96 | 1.60 s | Two-hand attack; contact at frame 42 |
| Zombie_To_Crawl | 48 | 0.80 s | Transition from standing to prone |
| Zombie_Crawl | 96 | 1.60 s | Prone movement; 0.32 m/s reference |
| Zombie_Crawl_Idle | 120 | 2.00 s | Prone idle |
| Zombie_Crawl_Bite | 72 | 1.20 s | Low mouth contact at frame 30 |
| Zombie_Crawl_Hit | 30 | 0.50 s | Prone hit reaction |
| Zombie_Jump | 72 | 1.20 s | Small hop; takeoff 21, nominal landing 44 |
| Zombie_Climb_Ladder | 120 | 2.00 s | Alternating climb; 0.30 m/s, 0.30 m rungs |

`assets/Zombie.r4.behavior.json` is the exact action/traversal contract. The native `BiteOpen` morph is synchronized with the bite clips; all other clips explicitly reset it. Local knee-bend correctives keep skin and trouser fabric separated during deep flexion. `SlamDrape` gives the collar and underarm room during the two-hand attack; the small `LeftDrape` corrective keeps the left collar fold from collapsing during the left-hand attack. Each corrective returns to zero in other actions. All added morphs stay at zero in the four preserved base clips. The skeleton remains 59 bones.

## Living limb behavior

R4 checks the complete arm chain before selecting a hand attack. A missing left hand/forearm/upper arm removes left-hand and both-hand attacks; the other arm and bite remain available as appropriate. The autonomous attack selector avoids repeating the previous choice when another eligible attack is available and uses the target distance to determine which attacks can be attempted.

Losing a thigh, shin or foot enters the prone transition. The zombie stays alive and uses the crawl set. One functional arm produces slower crawling; with no functional arm it stays prone and can bite if the target is close enough. Prone damage uses the prone hit reaction. The standing jump and ladder actions require supporting limbs. Head loss and fatal damage still enter ragdoll.

Attack contacts are checked at the authored marker against the evaluated animated hand or mouth, with range, facing, target-height, limb-availability and solid-world obstruction checks. A moving target can evade the committed strike. Loss of a required limb before the marker cancels that attack.

F1 and F2 keep their established behavior branch, including their original leg-loss death behavior. Shared collision, replay, model-selection and joint fixes remain active.

## Root motion and traversal

Walk and crawl are authored in place; the controller translates the CharacterBody3D at the matching animation reference speed. Ladder animation is also in place and requires upward root travel at 0.30 m/s. The rung plane is 0.40 m ahead of the root. Applying the declared root ascent keeps support poses on the same world rung during their plant interval.

Jump contains the small authored elevation for GLB preview. During a real hop, the controller subtracts that model elevation and applies gravity to the CharacterBody3D so height is applied once. The nominal hop is about 0.18 m. An extended fall holds the airborne pose until actual ground contact; landing does not occur solely because an animation timer expired.

Ladder entry requires a nearby grounded zombie, complete supporting limbs and a real platform at the requested exit. The controller aligns, ascends against world collision, and moves onto the platform. A lost support limb or blocked traversal cancels climbing and restores gravity. A game can use its navigation/obstacle logic to call these requests.

## Controller integration

The main public methods are:

```gdscript
zombie.target = target_node
zombie.set_behavior(true)

# Each request returns whether it was accepted. Availability, contact and
# completion are still decided by the controller.
zombie.request_attack()        # choose an eligible attack
zombie.request_attack("bite")   # also: left, right, both, crawl_bite
zombie.request_jump(0.70)       # forward speed, metres per second
zombie.request_climb({
    "base": ladder_base_world,
    "facing": Vector3(0, 0, 1),
    "height": 0.90,
    "exit": supported_platform_point_world,
})
zombie.cancel_traversal()
var state = zombie.get_behavior_snapshot()
```

`attack_started`, `attack_contact`, `attack_missed`, `action_finished`, and `movement_mode_changed` expose controller outcomes. Existing damage, limb-severing, death and `attack_landed` signals remain available. A target may implement `get_zombie_attack_target_point(action)`, `get_zombie_attack_radius()`, and `receive_zombie_attack(damage)`. The included target also provides its exact visible pad shapes, including their current recoil transform, for surface contact checks; it is a working integration example.

## Model and source contract

The current R4 character uses 14,992 triangles including hidden sever caps, with 59 skin bones, 14 damage regions and 13 paired sever locations. Clothes are a skinned game mesh. The checks evaluate their geometry during animation; the project does not add a separate cloth simulation. Severed pieces freeze the evaluated pose, including active morphs, and become native articulated rigid bodies. The remaining corpse uses the constrained native physical-bone rig. R4 hands use separate palm and finger collision shapes so gripping a rung does not fill the opening with one solid hand hull.

The corrected R4 body proportions, weights and four base animations are retained. The added oral interior and shape-key articulation support a visible bite while preserving the neutral exterior face. The assets use embedded textures and separate import identities for each active revision.

## Validation and review

Current reports are under `validation/`. `asset.identity.json` checks original bytes, catalog hashes, the actual exported clips, morph resets and model budget. `lab.assets.json` checks real version keys, GUI pointer selection, the exact frame inspector and native import identity. Controller and demo reports cover contact decisions, limb transitions, traversal and reset/stop behavior. Mesh, fabric and motion reports record their exact sampled frames and geometric limits.

`tools/capture_behavior_frames.gd` renders all authored frames from four simultaneous directions after two completed render frames settle the skin deformation; clip endpoints also receive a third-draw pixel stability check. Captured images and their numerical pose facts are distinct from the recorded visual inspection. The live demonstration review uses actual gameplay outcomes and multiple orbit positions. The packaged validation summary identifies the final source hashes and the checks performed on those exact files.

The final review covers all 1,308 authored integer poses in 15 clips, including endpoints, from front, right, back and left: 5,232 directional body views. Both bite clips also have 620 directional mouth close-ups. Every row in all 257 final atlases was actually inspected. Separate structural and fabric checks sample 2,601 poses at half-frame intervals. The eight automated suites pass 230 checks; the promoted main project repeats the 43 version, UI and import checks. Dynamic ragdoll review has its own explicitly sampled scope.

`preview/Zombie.r4.demo.mp4` shows the real demonstration with GUI Run and Stop. `preview/Zombie.r4.actions.mp4` includes every authored frame in four directions, followed by mouth close-ups. The 44 live outcome stills are in `preview/live.demo/`. Exact capture and review manifests accompany the videos; the reproducible capture tool can rebuild the larger raw frame PNG sets.

The `archive/` directory is excluded from Godot imports. Historical reports there describe their previous builds only. All project code is native Godot, native Blender/Python standard library, or small standard-library verification utilities; there are no runtime addons or third-party character assets.
