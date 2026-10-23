AK47 AMMUNITION GAME ASSET — RECOVERY REBUILD

This package was rebuilt from the user's original AK47--V2.glb after the previous
working files were removed during workspace maintenance. It is a new validated
build, not a byte-for-byte copy of the former export.

ASSET
  Total triangles, including every hidden ammunition/effect mesh: 14,307
  Rifle triangles: 13,357
  Ammunition and effects triangles: 950
  Separate mesh objects: 19
  Bones: 48
  Magazine capacity modeled: 24 cartridges
  Frame rate: 60 fps
  Units: meters; original rifle is approximately one meter long
  Blender forward/up: -Y / +Z
  glTF forward/up: +Z / +Y
  Default pose: loaded Idle at frame 0; bullet and casing hidden at scale 0.00001

FILES
  AK47_Ammo_Under15k.blend  Editable meshes, packed textures, rig and all actions.
  AK47_Ammo_Under15k.glb    Self-contained glTF 2.0 with meshes, skin, materials,
                           embedded textures and all six animations.
  textures/                Extracted copies of the three embedded 2K rifle maps.
  AK47_Ammo_Preview.png    Actual Blender render of the magazine and cartridges.
  AK47_Ammo_Preview.mp4    Actual Blender animation preview.
  AK47_Ammo_Events.json    Frame events and inventory transitions for integration.
  AK47_Ammo_Contract.json  Exact animation ranges, bones and layout metadata.
  AK47_Ammo_Verification.json / AK47_Ammo_Roundtrip.json / AK47_Ammo_Contacts.json
                           Independent structural, import and contact checks.
  AK47_Ammo_Checksums.sha256
                           SHA-256 checksums of packaged asset files.
  build_sources/           Scripts used to rebuild, render and validate this asset.

ANIMATIONS
  Action                    Frames  Time   Start -> End ammunition
  Idle                      0- 60   1.0s  24 -> 24
  Fire                      0- 12   0.2s  24 -> 23
  Empty_Magazine            0-288   4.8s  24 ->  0
  Reload                    0-180   3.0s   0 -> 24
  Disassemble_Reassemble    0-360   6.0s  24 -> 24
  Inspect_Ammo              0-240   4.0s  24 -> 24

  Fire: a cartridge feeds at the magazine mouth, the bolt/charging handle cycles,
  the trigger moves and the weapon recoils. A separate projectile exits the
  muzzle and a hollow spent casing ejects outward. Effects become hidden before
  their positions reset. The 24-to-23 clip is a single-shot animation example.

  Empty_Magazine: the complete 24-shot sequence visibly consumes every cartridge
  and raises the follower. It finishes with an empty magazine. Hold the last
  frame until Reload if demonstrating depletion; loaded Idle resets all 24.

  Reload: the empty magazine is removed; the off-weapon replacement state is
  loaded at frame 50. The magazine is reseated and the bolt returns to ready.

  Disassemble_Reassemble: the 15 rifle parts separate and return to their exact
  assembled transforms. The cartridges and follower remain with the magazine.

  Inspect_Ammo: the magazine is removed and its full stack/follower lift out for
  inspection. Frame 125 shows the full lift. All parts return at the end.

BLENDER
  Open the .blend file. Select AK47_GameRig and choose an action in the Action
  Editor. Use its listed frame range and 60 fps. The file opens on loaded Idle.
  The rig uses rigid, single-bone weights: mechanical parts do not bend.
  Each cartridge is a separate connected mesh island assigned to Round_01
  through Round_24. AmmoStack groups their inspection lift and travels with
  the magazine. Follower is independently animated beneath the rounds.

GAME INTEGRATION
  Import the GLB with the engine's glTF importer. Keep the authored node names,
  skeleton hierarchy and scale. Use the event JSON to synchronize ammunition
  count, sound, muzzle effects and game-controlled projectile behavior.

  Game code owns the persistent ammunition count. Replaying Fire by itself
  repeats its authored 24-to-23 demonstration; it does not store an arbitrary
  runtime inventory between animation plays. For repeated player-controlled
  shots, use that count to drive the round-bone states after the base animation,
  or use the complete Empty_Magazine animation for the supplied 24-shot demo.
  The adjacent contract provides the fitted centerline and named round bones.
  Use animation masks when layering game-controlled inventory state, and avoid
  crossfading loaded Idle over an empty magazine state.

  Visibility uses positive tiny scale, not negative/zero scale or object-hide
  properties. The GLB uses standard STEP scale samplers for exact visibility
  events. Case_Eject and Projectile are children of Root, keeping their flight
  independent from the weapon recoil. Muzzle_Socket local +Y aims forward;
  Ejection_Socket local +Y aims outward on the charging-handle side.

  The exported projectile/casing motion is an animation demonstration. Use the
  engine's desired projectile and effect lifecycle for gameplay. Materials use
  the metallic/roughness PBR workflow; the normal map is tangent-space +Y.

MOVABLE PARTS
  01_Stock -> Stock
  02_Receiver -> Receiver
  03_Receiver_Cover -> Receiver_Cover
  04_Pistol_Grip -> Pistol_Grip
  05_Trigger_Guard -> Trigger_Guard
  06_Magazine -> Magazine
  07_Lower_Handguard -> Lower_Handguard
  08_Upper_Handguard -> Upper_Handguard
  09_Rear_Sight -> Rear_Sight
  10_Gas_Tube -> Gas_Tube
  11_Barrel -> Barrel
  12_Front_Sight -> Front_Sight
  13_Muzzle -> Muzzle
  14_Bolt -> Bolt
  15_Trigger -> Trigger

VALIDATION
  The total triangle count is computed from actual indexed geometry, including
  hidden ammunition and effects. All material images are embedded in the GLB.
  The structural validator inspects buffers, finite data, skin weights, clip
  ranges, inventory progression and hidden resets. A fresh Blender import is
  compared against the source at sampled animation states, including the
  default loaded state. Evaluated cartridge surfaces are checked for crossings
  against neighboring cartridges and the magazine during the feed cycle.
  Read the included JSON reports for exact sample counts, tolerances and scope.

SOURCE / REBUILD
  Original filename: AK47--V2.glb
  Original SHA-256: e3b04255b4bccafa5c66ad6190efab2c5c61ec13f6bdc95474b1e716c2e328a8
  Blender version used: 4.5.3 LTS
  Build scripts use Blender built-ins and Python's standard library.
  Re-running the source preparation requires the user's original source file.
  The delivered .blend and .glb are complete and do not need the original file.
