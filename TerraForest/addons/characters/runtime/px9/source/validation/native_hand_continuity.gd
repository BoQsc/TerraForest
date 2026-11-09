# SPDX-License-Identifier: CC0-1.0
# Native read-only verification of the final Rack half/quarter-frame hand path.
extends SceneTree

const Definition = preload("res://item_definition.gd")
const Mount = preload("res://item_mount.gd")
const Motion = preload("res://item_motion.gd")
const Instance = preload("res://item_instance.gd")

var probes_path: String = "res://validation/FINAL_RAW_GLB_HAND_PATH.json"
var output_path: String = "res://validation/FINAL_NATIVE_HAND_PATH.json"

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		if args[i] == "--probes": probes_path = args[i + 1]
		if args[i] == "--output": output_path = args[i + 1]
	call_deferred("run")

func decode(path: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	state.use_named_skin_binds = true
	assert(document.append_from_file(path, state) == OK)
	return document.generate_scene(state, 60.0, false, false)

func point(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

func quaternion_error_degrees(actual: Quaternion, expected_wxyz: Array) -> float:
	# Accumulate as script floats so nearly identical float32 quaternions do
	# not acquire the approximately 0.04-degree error of a rounded native dot.
	var values: Array = [float(actual.w),float(actual.x),float(actual.y),float(actual.z)]
	var dot: float = 0.0
	var actual_norm_squared: float = 0.0
	var expected_norm_squared: float = 0.0
	for i: int in range(4):
		dot += values[i] * float(expected_wxyz[i])
		actual_norm_squared += values[i] * values[i]
		expected_norm_squared += float(expected_wxyz[i]) * float(expected_wxyz[i])
	return rad_to_deg(2.0 * acos(clampf(absf(dot) / sqrt(actual_norm_squared * expected_norm_squared),-1.0,1.0)))

func run() -> void:
	var definition := Definition.load_definition("res://item_px9.json")
	var human := decode("res://Human.r11.glb")
	var item := decode("res://PX9_Eclipse_FP.glb")
	root.add_child(human)
	var hs := Mount.find_skeleton(human)
	var player := Mount.find_player(human)
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(Motion.find_animation(player,"Idle"),0.0)
	player.seek(0.0,true,true)
	player.pause()
	var library := load("res://Human.px9_eclipse.res") as AnimationLibrary
	var adapter := Instance.new()
	adapter.auto_process = false
	root.add_child(adapter)
	assert(adapter.equip(human,item,library,definition,"res://item_px9.json") == OK)
	adapter.motion.auto_return = false
	adapter.motion.repeat_override = false
	assert(adapter.request("rack") == OK)
	adapter.motion.pause()
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(probes_path))
	assert(FileAccess.get_sha256("res://Human.px9_eclipse.glb") == source.source_hashes["Human.px9_eclipse.glb"])
	assert(FileAccess.get_sha256("res://Human.px9_eclipse.res") == source.source_hashes["Human.px9_eclipse.res"])
	assert(FileAccess.get_sha256("res://Human.r11.glb") == source.source_hashes["Human.r11.glb"])
	assert(FileAccess.get_sha256("res://item_px9.json") == source.source_hashes["item_px9.json"])
	var samples: Array = []
	var maxima: Dictionary = {"left_recipe":0.0,"right_recipe":0.0,"left_raw":0.0,"right_raw":0.0}
	var maximum_bone_rotation_error_degrees: float = 0.0
	for sample: Dictionary in source.samples:
		var frame: float = sample.frame
		adapter.motion.seek_frame(frame)
		hs.force_update_all_bone_transforms()
		await process_frame
		var record: Dictionary = {"frame":frame,"left_contact":sample.left_contact}
		for side: String in ["left","right"]:
			var index: int = hs.find_bone(side.capitalize()+"Hand")
			var actual: Transform3D = hs.global_transform * hs.get_bone_global_pose(index)
			var expected := point(sample["expected_"+side+"_hand_translation_glb"])
			var raw := point(sample[side+"_hand_translation_glb"])
			var error_recipe: float = actual.origin.distance_to(expected)
			var error_raw: float = actual.origin.distance_to(raw)
			record[side+"_hand_error_vs_continuous_recipe_metres"] = error_recipe
			record[side+"_hand_error_vs_raw_glb_metres"] = error_raw
			record[side+"_hand_position"] = [actual.origin.x,actual.origin.y,actual.origin.z]
			maxima[side+"_recipe"] = maxf(maxima[side+"_recipe"],error_recipe)
			maxima[side+"_raw"] = maxf(maxima[side+"_raw"],error_raw)
		var rotation_errors: Dictionary = {}
		for bone: String in source.samples[0].bone_world_quaternions.keys():
			var index: int = hs.find_bone(bone)
			var actual: Quaternion = (hs.global_transform * hs.get_bone_global_pose(index)).basis.get_rotation_quaternion()
			var error: float = quaternion_error_degrees(actual,sample.bone_world_quaternions[bone])
			rotation_errors[bone] = error
			maximum_bone_rotation_error_degrees = maxf(maximum_bone_rotation_error_degrees,error)
		record["bone_rotation_error_vs_raw_glb_degrees"] = rotation_errors
		samples.append(record)
	var checks: Dictionary = {"289samples":samples.size()==289,"left_path_under1mm":maxima.left_recipe<0.001,"right_path_under1mm":maxima.right_recipe<0.001,"native_agrees_with_glb_under10micrometres":maxf(maxima.left_raw,maxima.right_raw)<0.00001,"native_bone_rotations_agree_with_glb_under_point01degrees":maximum_bone_rotation_error_degrees<0.01}
	var report: Dictionary = {"schema":"px9-final-native-hand-path-audit-1","engine":Engine.get_version_info().string,"source_hashes":source.source_hashes,"scope":"All Rack quarter-frame samples, using the actual portable item adapter and native AnimationLibrary.","maxima_metres":maxima,"maximum_bone_rotation_error_degrees":maximum_bone_rotation_error_degrees,"samples":samples,"checks":checks,"passed":not checks.values().has(false)}
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("PX9_NATIVE_HAND_PATH ",JSON.stringify({"passed":report.passed,"checks":checks,"maxima_metres":maxima,"maximum_bone_rotation_error_degrees":maximum_bone_rotation_error_degrees}))
	adapter.unequip()
	await process_frame
	human.queue_free()
	quit(0 if report.passed else 1)
