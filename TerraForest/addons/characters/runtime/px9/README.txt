PX-9 ECLIPSE — FIRST-PERSON ANIMATION EDITION
BG5 / Human R11 / CC0-1.0 / 60 FPS

START HERE — RACK RELEASE THUMB REVISION 8

The left thumb opens from the RACK grasp with a lower base and a gently
curved, separate silhouette. The release pose reduces the inward swing that
produced the angular thumb-web fold around frame 044. The new shape is
retained through frame 052, then blends back to the accepted support motion
by frame 058. Finger curls, palm and wrist motion, the held grasp at frame
031, and the rest of the animation set are preserved.

RACK_FIX_NOTES.txt records current changes, per-frame findings and limits.
The earlier frame 031 grasp, reload correction and hand skin repair remain.

For a fresh extraction, run the cache-initialization command under INTEGRATION
AND REBUILD once before opening project.godot. Then use Godot 4.6.3, select
Rack, play/pause, scrub or step frames.
Review release frame 044 and surrounding frames 040–060; frame 031 provides
the retained-grasp comparison. Native preview controls and host integration
are documented in PORTABLE_INTEGRATION.txt.

previews/PX9_Rack_Review.mp4 is the current Rack preview.
previews/PX9_First_Person_Review.mp4 contains all 20 paired clips.
previews/first_person_rack_044.png is the actual native frame 044.
previews/Rack044_Before_After.png compares release poses in revisions 7 and 8.
previews/Rack031_Before_After.png shows preservation of the earlier held grasp.
source/Human.px9_eclipse.blend contains the editable scene and packed textures.
The Blender Text Editor helper Preview_FirstPerson.py selects matching human
and weapon Actions. The Rack human Action is FP_PX9_ECLIPSE_Rack.

DELIVERED MOTION AND ASSET

Idle, Walk, Run, Jump, Equip, Holster, Inspect, Aim In, Aim Idle, Aim Out,
Fire, Fire Last, Aim Fire, Aim Fire Last, Idle Empty, Aim Idle Empty,
Reload, Reload Empty, Rack, Dry Fire

Both rigs use explicit integer keys at 60 FPS: 1,582 inclusive samples
per rig across 20 paired clips. The original 11 weapon-only clips are retained,
including decorative assembly and disassembly. CLIPS.txt and item_px9.json
define durations, loops, returns and event times.

Weapon: 19,616 triangles including casing; 17 separate meshes;
22 bones; original PBR materials/maps. The 20,000-triangle weapon budget
excludes Human R11. The human retains 59 rest bones, 497 original source
Actions and 71 original runtime clips.

REVISION 8 UPDATE

Only the Rack release-thumb animation changes at frames 041–057. Frame 031,
the preceding held grasp, hand/wrist and other fingers are preserved. All
19 other human clips, weapon files, mounts, definitions and runtime adapters
retain their earlier data. Skin patch revision 5 and its optional body
resource are byte-identical to revision 7.

Existing revision 7 native installs only need Human.px9_eclipse.res replaced.
Keep the current body/weight override active. For GLB importing, use the updated
Human.px9_eclipse.glb. For editable or reproducible work, carry the full source
folder: the Blender scene, px9_motion.py and author_px9_first_person.py must
remain together. The authoring helper passes the new release-thumb control;
updating only the motion file is insufficient for a rebuild.
The human GLB is an animation carrier; the corrected skin is
a separate per-item body override. The original body is restored on unequip.
Use the complete package for new installations or upgrades from revision 5
and earlier so all prior skin corrections are included.

INTEGRATION AND REBUILD

RightHand/BoneAttachment3D supplies the mount. WeaponSkeleton animates separate
parts. No human helper bone is added. Relative paths allow moving the item
folder. item_instance.gd exposes equip/request/unequip; item_equip_example.gd
shows bindings. Both mount routes are documented in PORTABLE_INTEGRATION.txt.
Each new weapon/tool has its own item definition and paired clips.

Shot, casing, magazine and ready events are host hooks. Gameplay hit logic,
ammunition, audio, muzzle effects and projectiles belong to the host. First-
person movement clips are upper-body layers over host locomotion. Standalone
validation does not claim full BG5 host integration.

The scripts use Blender bpy/mathutils, Python standard library and native
Godot APIs. No third-party add-on or package is required.

  blender -b --factory-startup --python-exit-code 1 --python source/author_px9_first_person.py -- --build --output /absolute/rebuilt_px9

Copy the runtime/reference files into a separate rebuild folder before import.
The initializer prepares generated Godot import metadata for the unchanged
reference human scene. It is required for a fresh extraction or rebuild;
generated cache/import files are intentionally omitted from the archive.
To initialize the cache and refresh native resources in a complete folder:

  python3 source/validation/initialize_native_cache.py --package . --report validation/NATIVE_CACHE_INITIALIZATION.json
  godot --headless --path . --script import_item_animations.gd -- --definition res://item_px9.json
  python3 source/validation/check_first_person_release.py .
  godot --headless --path . --script test_item_motion.gd

VALIDATION.txt indexes current evidence; reference/rack_revision7/ retains
the previous revision as history. Tested tools: Blender 4.3.2 and Godot 4.6.3.

LICENSE

LICENSE.txt contains the unchanged CC0 1.0 Universal legal code. Authored
animation/source edits retain those terms. Existing PBR/OpenAI texture
provenance, Human R11 CC0 statement and user-supplied TRELLIS.2 provenance
remain in the package. No new texture or external runtime library was added.
Tool software/services are not bundled or relicensed.
