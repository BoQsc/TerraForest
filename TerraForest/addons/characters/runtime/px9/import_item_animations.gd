# SPDX-License-Identifier: CC0-1.0
# Portable Human R11 animation importer; it never rewrites the reference GLB.
# Usage: godot --headless --path . --script import_item_animations.gd --
#        --definition res://item_px9.json [--output res://Human.px9_eclipse.res]
extends SceneTree

const Definition = preload("item_definition.gd")
const Mount = preload("item_mount.gd")
const Motion = preload("item_motion.gd")
const HandWeights = preload("item_hand_weights.gd")
const LOWER_BODY := ["Root", "Hips", "LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase",
	"RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"]

var errors := PackedStringArray()
var report: Dictionary = {}
var report_path := "res://ANIMATION_IMPORT_REPORT.json"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var options := _options()
	var local_directory: String = get_script().resource_path.get_base_dir()
	var definition_path := String(options.get("definition", local_directory.path_join("item_px9.json")))
	var definition := Definition.load_definition(definition_path)
	if definition.is_empty():
		_fail("Cannot read item definition")
		_finish()
		return
	var files: Dictionary = definition["files"]
	var reference_path := Definition.resolve_file(definition_path, String(files["human_reference"]))
	var source_path := Definition.resolve_file(definition_path, String(files["human_animation_source"]))
	var output_path := String(options.get("output", Definition.resolve_file(definition_path, String(files["human_library"]))))
	report_path = String(options.get("report", local_directory.path_join("ANIMATION_IMPORT_REPORT.json")))
	var expected: Dictionary = definition.get("human", {})
	var reference_sha := FileAccess.get_sha256(reference_path)
	var declared_sha := String(expected.get("reference_sha256", ""))
	if not declared_sha.is_empty() and reference_sha != declared_sha:
		_fail("Reference model SHA-256 differs from the declared integration target")
		_finish()
		return
	var reference := _decode(reference_path, float(definition["fps"]))
	var source := _decode(source_path, float(definition["fps"]))
	if reference == null or source == null:
		_finish()
		return
	root.add_child(reference)
	root.add_child(source)
	var target_skeleton := Mount.find_skeleton(reference)
	var source_skeleton := Mount.find_skeleton(source)
	var source_player := Mount.find_player(source)
	var original_player := Mount.find_player(reference)
	if target_skeleton == null or source_skeleton == null or source_player == null or original_player == null:
		_fail("Both GLBs must contain the expected human skeleton and AnimationPlayer")
		_finish()
		return
	source_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	original_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	original_player.stop()
	var tolerance := float(expected.get("reference_rest_tolerance", 0.0001))
	var bone_count := int(expected.get("expected_bones", 59))
	var rest_result := _compare_rest(source_skeleton, target_skeleton, bone_count, tolerance)
	report = {
		"schema": "bg5-fp-human-import-1", "engine": Engine.get_version_info().string,
		"reference_file": reference_path.get_file(), "reference_sha256": reference_sha,
		"animation_source_file": source_path.get_file(), "animation_source_sha256": FileAccess.get_sha256(source_path),
		"definition_sha256": FileAccess.get_sha256(definition_path),
		"fps": definition["fps"], "rest_validation": rest_result,
		"original_animation_count": original_player.get_animation_list().size(),
		"target_skeleton_path": String(reference.get_path_to(target_skeleton)),
		"animation_player_root": "Human model scene root",
		"track_policy": "Native upper-body transform tracks only. Constant inherited lower-body baseline is checked then omitted; Root/Hips/legs/feet and Weapon_* tracks never enter this layer.",
		"source_carrier_mesh_used_at_runtime": false,
		"reference_model_modified": false,
		"clips": {}, "output": output_path.get_file()
	}
	if not errors.is_empty():
		reference.free()
		source.free()
		_finish()
		return
	var skeleton_path := String(reference.get_path_to(target_skeleton))
	var library := AnimationLibrary.new()
	var target_bones: Array = []
	for index in target_skeleton.get_bone_count():
		target_bones.append({"name":String(target_skeleton.get_bone_name(index)),
			"parent":target_skeleton.get_bone_parent(index),"rest":target_skeleton.get_bone_rest(index)})
	library.set_meta("item_human_bones", target_bones)
	library.set_meta("item_human_skeleton_path", skeleton_path)
	library.set_meta("item_human_reference_sha256", reference_sha)
	library.set_meta("item_human_contract_engine", Engine.get_version_info().string)
	for action: Dictionary in definition["actions"]:
		var requested := String(action["human_clip"])
		var imported_name := Motion.find_animation(source_player, requested)
		if imported_name.is_empty():
			_fail("Missing human action " + requested)
			continue
		var source_animation := source_player.get_animation(imported_name)
		var duration := float(action["frame_end"]) / float(definition["fps"])
		if absf(source_animation.length - duration) > 0.00002:
			_fail("Action duration does not match frame_end/FPS: " + requested)
			continue
		var lower_result := _check_constant_lower_body(source_player, source_skeleton, imported_name,
			int(action["frame_end"]), float(definition["fps"]), tolerance)
		var animation := source_animation.duplicate(true) as Animation
		var removed := 0
		var bone_names := {}
		for index in range(animation.get_track_count() - 1, -1, -1):
			var path := animation.track_get_path(index)
			var type := animation.track_get_type(index)
			var bone := String(path.get_subname(0)) if path.get_subname_count() == 1 else ""
			if type not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D] or target_skeleton.find_bone(bone) < 0 or _excluded_bone(bone):
				animation.remove_track(index)
				removed += 1
				continue
			animation.track_set_path(index, NodePath(skeleton_path + ":" + bone))
			bone_names[bone] = true
		if animation.get_track_count() == 0:
			_fail("No upper-body bone tracks survived in " + requested)
			continue
		animation.resource_name = requested
		animation.loop_mode = Animation.LOOP_LINEAR if bool(action.get("loop", false)) else Animation.LOOP_NONE
		var add_error := library.add_animation(StringName(requested), animation)
		if add_error != OK:
			_fail("Cannot add action to the library: " + requested)
		report["clips"][requested] = {
			"duration_seconds": animation.length, "frame_end": action["frame_end"],
			"loop": bool(action.get("loop", false)), "tracks": animation.get_track_count(),
			"upper_body_bones": bone_names.keys(), "omitted_tracks": removed,
			"lower_body_constant_check": lower_result, "events": action.get("events", [])
		}
	if errors.is_empty():
		var hand_patch_path := String(expected.get("hand_weight_patch", ""))
		if not hand_patch_path.is_empty():
			report["hand_skin_variant"] = _build_hand_variant(reference, target_skeleton, expected, definition_path, reference_sha)
	if errors.is_empty():
		var output_dir := output_path.get_base_dir()
		if not output_dir.is_empty():
			DirAccess.make_dir_recursive_absolute(output_dir)
		var save_error := ResourceSaver.save(library, output_path, ResourceSaver.FLAG_COMPRESS)
		report["save_error"] = save_error
		if save_error != OK:
			_fail("AnimationLibrary save failed: " + str(save_error))
		else:
			report["output_sha256"] = FileAccess.get_sha256(output_path)
			report["output_bytes"] = FileAccess.get_file_as_bytes(output_path).size()
	reference.free()
	source.free()
	_finish()

func _build_hand_variant(reference: Node, skeleton: Skeleton3D, human_settings: Dictionary,
		definition_path: String, reference_sha: String) -> Dictionary:
	var patch_path := Definition.resolve_file(definition_path, String(human_settings["hand_weight_patch"]))
	var patch_value: Variant = JSON.parse_string(FileAccess.get_file_as_string(patch_path))
	if not patch_value is Dictionary:
		_fail("Cannot parse the optional hand-weight patch")
		return {"passed":false}
	var patch: Dictionary = patch_value
	if String(patch.get("source_glb_sha256", "")) != reference_sha:
		_fail("Hand-weight patch targets a different reference model")
		return {"passed":false}
	var mesh_name := String(patch.get("source_mesh", "Human_Body"))
	var body := reference.find_child(mesh_name, true, false) as MeshInstance3D
	var output := ""
	for override: Dictionary in human_settings.get("mesh_overrides", []):
		if String(override.get("mesh", "")) == mesh_name:
			output = Definition.resolve_file(definition_path, String(override["resource"]))
	if output.is_empty():
		_fail("The hand patch needs a matching human.mesh_overrides output path")
		return {"passed":false}
	var built := HandWeights.build_variant(body, skeleton, patch)
	var result: Dictionary = built["report"]
	result["source_patch_sha256"] = FileAccess.get_sha256(patch_path)
	result["source_glb_sha256"] = reference_sha
	result["output"] = output.get_file()
	if not bool(result["passed"]):
		_fail("Hand skin variant failed: " + str(result.get("errors", [])))
		return result
	var variant: ArrayMesh = built["mesh"]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := ResourceSaver.save(variant, output, ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		_fail("Cannot save the per-item body mesh variant")
		result["passed"] = false
		return result
	var loaded := ResourceLoader.load(output, "", ResourceLoader.CACHE_MODE_REPLACE) as ArrayMesh
	result["saved_geometry_buffers_byte_identical"] = loaded != null and HandWeights.compare_geometry_buffers(body.mesh, loaded)
	result["saved_skin_buffers_match_variant"] = loaded != null
	if loaded != null:
		for surface in variant.get_surface_count():
			var a := RenderingServer.mesh_get_surface(variant.get_rid(), surface)
			var b := RenderingServer.mesh_get_surface(loaded.get_rid(), surface)
			if a.get("skin_data") != b.get("skin_data"):
				result["saved_skin_buffers_match_variant"] = false
	result["output_sha256"] = FileAccess.get_sha256(output)
	result["output_bytes"] = FileAccess.get_file_as_bytes(output).size()
	result["passed"] = result["saved_geometry_buffers_byte_identical"] and result["saved_skin_buffers_match_variant"]
	if not bool(result["passed"]):
		_fail("Saved hand variant did not preserve its validated native buffers")
	return result

func _decode(path: String, fps: float) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.use_named_skin_binds = true
	var error := document.append_from_file(path, state)
	if error != OK:
		_fail("GLB decode failed: " + path + " (" + str(error) + ")")
		return null
	# Keep constant upper-body base-pose keys, matching the supplied import
	# scripts: another held item must not leave its clavicle/torso pose behind.
	return document.generate_scene(state, fps, false, false)

func _compare_rest(source: Skeleton3D, target: Skeleton3D, expected_count: int, tolerance: float) -> Dictionary:
	var rows: Array = []
	var maximum := 0.0
	if source.get_bone_count() != expected_count or target.get_bone_count() != expected_count:
		_fail("Human bone count changed")
	for bone in source.get_bone_count():
		var name := String(source.get_bone_name(bone))
		var target_bone := target.find_bone(name)
		if target_bone < 0:
			_fail("Missing reference bone: " + name)
			continue
		var source_parent := source.get_bone_parent(bone)
		var target_parent := target.get_bone_parent(target_bone)
		var source_parent_name := String(source.get_bone_name(source_parent)) if source_parent >= 0 else ""
		var target_parent_name := String(target.get_bone_name(target_parent)) if target_parent >= 0 else ""
		if source_parent_name != target_parent_name:
			_fail("Bone parent changed: " + name)
		var global_error := _difference(source.get_bone_global_rest(bone), target.get_bone_global_rest(target_bone))
		var local_error := _difference(source.get_bone_rest(bone), target.get_bone_rest(target_bone))
		maximum = maxf(maximum, maxf(global_error, local_error))
		rows.append({"bone": name, "parent": source_parent_name,
			"global_error": global_error, "local_error": local_error})
	if maximum > tolerance:
		_fail("Human rest transforms changed beyond tolerance: " + str(maximum))
	return {"source_bones": source.get_bone_count(), "reference_bones": target.get_bone_count(),
		"maximum_rest_error": maximum, "tolerance": tolerance, "bones": rows,
		"passed": maximum <= tolerance and source.get_bone_count() == expected_count and target.get_bone_count() == expected_count}

func _check_constant_lower_body(player: AnimationPlayer, skeleton: Skeleton3D, clip: String,
		frame_end: int, fps: float, tolerance: float) -> Dictionary:
	player.play(clip, 0.0)
	player.seek(0.0, true, true)
	var first := {}
	for bone in skeleton.get_bone_count():
		var name := String(skeleton.get_bone_name(bone))
		if _excluded_bone(name):
			first[bone] = skeleton.get_bone_pose(bone)
	var maximum := 0.0
	for frame in range(frame_end + 1):
		player.seek(float(frame) / fps, true, true)
		for bone: int in first:
			maximum = maxf(maximum, _difference(first[bone], skeleton.get_bone_pose(bone)))
	if maximum > tolerance:
		_fail("Lower-body or unused mount bone moves in " + clip + ": " + str(maximum))
	return {"sampled_frames": frame_end + 1, "bones": first.size(),
		"maximum_pose_variation": maximum, "passed": maximum <= tolerance,
		"baseline": "Frame 0; an inherited constant Idle lower-body baseline is permitted and stripped from the runtime library."}

func _difference(a: Transform3D, b: Transform3D) -> float:
	var difference := a.affine_inverse() * b
	var maximum := difference.origin.length()
	for axis in 3:
		maximum = maxf(maximum, (difference.basis[axis] - Basis.IDENTITY[axis]).length())
	return maximum if is_finite(maximum) else INF

func _excluded_bone(name: String) -> bool:
	return name in LOWER_BODY or name.begins_with("Weapon_")

func _options() -> Dictionary:
	var result := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			result[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			i += 1
	return result

func _fail(message: String) -> void:
	errors.append(message)
	push_error(message)

func _finish() -> void:
	report["errors"] = errors
	report["passed"] = errors.is_empty()
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("FP_ITEM_ANIMATION_IMPORT ", JSON.stringify({"passed": report["passed"],
		"clip_count": report.get("clips", {}).size(), "errors": errors, "report": report_path}))
	quit(0 if errors.is_empty() else 1)
