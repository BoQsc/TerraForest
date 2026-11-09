PX-9 ECLIPSE — HAND CONTINUITY AUDITS
SPDX-License-Identifier: CC0-1.0

Run these commands from the package directory after rebuilding both the
Human animation GLB and native AnimationLibrary. Only validation reports
are written; these scripts do not change model, rig or animation assets.

1. Every authored integer sample and local joint rotation step

   python3 source/validation/joint_step_summary.py --package . --output validation

   Outputs FINAL_PER_FRAME_JOINT_STEPS.json and .csv: 20 clips, 1,582
   inclusive frame samples, 92,158 adjacent Human-bone rotation pairs.
   Frame 0 has no preceding pose and therefore has null step fields.
   This is a rotation-continuity measurement, not a skin-collision test.

2. Raw GLB Rack hand path, including quarter frames

   blender -b --factory-startup --python-exit-code 1 --python source/validation/export_hand_path_probe.py -- --package . --output validation

   Outputs FINAL_RAW_GLB_HAND_PATH.json. The script uses only Blender's
   native mathutils and Python's standard library. Interpolated quaternion
   rotations are normalized before matrix construction. The comparison
   uses the current continuous wrist targets in source/px9_motion.py.

3. Native Godot Rack hand path using the portable item adapter

   godot --headless --path . --script source/validation/native_hand_continuity.gd

   Reads validation/FINAL_RAW_GLB_HAND_PATH.json and checks matching hashes.
   Outputs validation/FINAL_NATIVE_HAND_PATH.json. It checks all 289 quarter
   samples from frame 0 to 72 against both the raw GLB and authored targets,
   plus world-rotation agreement for the checked arm and hand bones.
   Optional --probes and --output arguments after -- override report paths.

Acceptance limits
  - Rack hand path versus continuous targets: below 1 mm for each hand.
  - Integer raw GLB left-wrist target error: below 10 micrometres.
  - Native versus raw GLB wrist position: below 10 micrometres.
  - Native versus raw GLB checked world rotations: below 0.01 degrees.
  - Joint-step report lists all steps above 30 and 45 degrees for review;
    the delivered revision contains none.

The native comparison was run with Godot 4.6.3. All exported animation
samples use 60 FPS. Successful continuity checks do not by themselves
prove anatomical accuracy or eliminate every possible mesh intersection.
