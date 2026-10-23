extends SceneTree
## Small native smoke for an independently cold-extracted/imported archive.
## godot --headless --path EXTRACTED --script res://tests/revision_package_smoke.gd --fixed-fps 240
## CLI startup case: append -- --revision=r4 --expected-startup=r4 --cli-only --output=res://validation/cold_cli_r4.json

const MANIFEST = "res://assets/zombie.revisions.json"
const IDS = ["original", "r4", "r2", "r3"]
var lab: Node3D
var profiles: Dictionary = {}
var checks: Array[Dictionary] = []
var model_records: Dictionary = {}
var source_hashes: Dictionary = {}
var expected_startup = "original"
var cli_only = false
var output_path = "res://validation/cold_package.json"


func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--expected-startup="):
			expected_startup = argument.trim_prefix("--expected-startup=")
		elif argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
		elif argument == "--cli-only":
			cli_only = true
	call_deferred("run")


func _ticks(count: int) -> void:
	for _index in range(count):
		await physics_frame
		await process_frame


func _check(name: String, passed: bool, details: Dictionary = {}) -> void:
	checks.append({"name": name, "passed": passed, "details": details})
	if not passed:
		print("REVISION_PACKAGE_CHECK_FAILED ", JSON.stringify(checks.back()))


func _selected() -> String:
	return String(lab.call("get_selected_revision"))


func _files_below(directory: String, result: Array[String]) -> void:
	for filename in DirAccess.get_files_at(directory):
		result.append(directory.path_join(filename))
	for child in DirAccess.get_directories_at(directory):
		_files_below(directory.path_join(child), result)


func _all_meshes(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and node.mesh != null:
		result.append(node)
	for child in node.get_children():
		_all_meshes(child, result)


func _dependency_path(dependency: String) -> String:
	var parts = dependency.split("::")
	var path = String(parts[parts.size() - 1])
	if path.begins_with("uid://"):
		var id = ResourceUID.text_to_id(path)
		if ResourceUID.has_id(id):
			path = ResourceUID.get_id_path(id)
	return path


func _dependencies(model_path: String, compiled_path: String) -> Dictionary:
	var pending: Array[String] = [model_path, compiled_path]
	var visited: Dictionary = {}
	var edges: Array = []
	var external_images: Array = []
	var unresolved: Array = []
	while not pending.is_empty():
		var path: String = pending.pop_back()
		if visited.has(path):
			continue
		visited[path] = true
		if not FileAccess.file_exists(path):
			unresolved.append(path)
			continue
		for dependency in ResourceLoader.get_dependencies(path):
			var resolved = _dependency_path(String(dependency))
			edges.append({"resource": path, "dependency": String(dependency), "resolved_path": resolved})
			if resolved.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"]:
				external_images.append(resolved)
			if not visited.has(resolved):
				pending.append(resolved)
	return {"visited_resources": visited.keys(), "dependency_edges": edges,
		"external_image_dependencies": external_images, "unresolved_dependencies": unresolved}


func _imported_md5(compiled_path: String) -> String:
	var hash_path = compiled_path.get_basename() + ".md5"
	if not FileAccess.file_exists(hash_path):
		return ""
	for line in FileAccess.get_file_as_string(hash_path).split("\n"):
		if line.begins_with("source_md5="):
			return line.get_slice('"', 1)
	return ""


func _labels_match(id: String) -> bool:
	var profile: Dictionary = profiles[id]
	var label = lab.find_child("ActiveRevision", true, false) as Label
	var file_label = lab.find_child("ActiveRevisionFile", true, false) as Label
	var button = lab.find_child("Revision_" + id, true, false) as Button
	return label != null and file_label != null and button != null and button.button_pressed \
		and label.text == String(profile.label).to_upper() \
		and file_label.text == "ASSET  " + String(profile.model_path).get_file()


func _load_profile(id: String) -> void:
	lab.call("select_revision", id)
	var zombie: Node3D = lab.get("subject")
	var model: Node3D = zombie.get("model")
	var skeleton: Skeleton3D = zombie.get("skeleton")
	var scene: PackedScene = zombie.get("model_scene")
	var profile: Dictionary = profiles[id]
	var path = String(profile.model_path)
	var config = ConfigFile.new()
	var config_ok = config.load(path + ".import") == OK
	var compiled = String(config.get_value("remap", "path", ""))
	var actual_sha = FileAccess.get_sha256(path)
	var source_md5 = FileAccess.get_md5(path)
	var import_md5 = _imported_md5(compiled)
	var cap_pairs = 0
	for pair in (zombie.get("caps") as Dictionary).values():
		if pair.has("body") and pair.has("detached") and is_instance_valid(pair.body) and is_instance_valid(pair.detached):
			cap_pairs += 1
	var record = {"revision": id, "expected_glb_sha256": profile.model_sha256, "actual_glb_sha256": actual_sha,
		"packed_scene_resource_path": scene.resource_path if scene != null else "", "instance_scene_file_path": model.scene_file_path,
		"compiled_scene_path": compiled, "source_md5": source_md5, "imported_source_md5": import_md5,
		"bones": skeleton.get_bone_count(), "parts": (zombie.get("part_meshes") as Dictionary).size(),
		"hit_regions": (zombie.get("hit_areas") as Dictionary).size(), "complete_cap_pairs": cap_pairs}
	_check(id + ": cold imported exact full model, rig and limb regions", _selected() == id
		and String(zombie.get("revision_id")) == id and actual_sha == String(profile.model_sha256)
		and scene != null and scene.resource_path == path and model.scene_file_path == path
		and skeleton.get_bone_count() == 59 and (zombie.get("part_meshes") as Dictionary).size() == 14
		and (zombie.get("hit_areas") as Dictionary).size() == 14 and cap_pairs == 13
		and source_md5 == import_md5 and not import_md5.is_empty() and _labels_match(id), record)
	var dependencies = _dependencies(path, compiled)
	var meshes: Array[MeshInstance3D] = []
	_all_meshes(model, meshes)
	var textures: Dictionary = {}
	var bad_textures: Array = []
	for mesh in meshes:
		for surface in range(mesh.mesh.get_surface_count()):
			var material = mesh.get_active_material(surface)
			if material == null:
				continue
			for property in material.get_property_list():
				if not String(property.name).ends_with("_texture"):
					continue
				var value = material.get(property.name)
				if not value is Texture2D:
					continue
				var texture: Texture2D = value
				var key = str(texture.get_instance_id())
				textures[key] = {"resource_path": texture.resource_path, "width": texture.get_width(), "height": texture.get_height()}
				if texture.get_width() <= 0 or texture.get_height() <= 0:
					bad_textures.append(textures[key])
	var embedded_mode = int(config.get_value("params", "gltf/embedded_image_handling", -1))
	record["embedded_image_handling"] = embedded_mode
	record["compiled_dependencies"] = dependencies
	record["assigned_material_textures"] = textures.values()
	record["invalid_material_textures"] = bad_textures
	model_records[id] = record
	_check(id + ": compiled scene and materials need no extracted PNG files", config_ok and embedded_mode == 3
		and FileAccess.file_exists(compiled) and dependencies.external_image_dependencies.is_empty()
		and dependencies.unresolved_dependencies.is_empty() and textures.size() > 0 and bad_textures.is_empty(),
		{"embedded_mode": embedded_mode, "compiled_dependencies": dependencies,
			"assigned_material_texture_count": textures.size(), "bad_textures": bad_textures})


func _pause_comparison() -> void:
	lab.call("select_revision", "original")
	lab.call("_select_clip", 2)
	lab.call("_set_animation_paused", true)
	lab.call("_seek_animation_frame", 42)
	var skeleton: Skeleton3D = lab.get("subject").get("skeleton")
	skeleton.force_update_all_bone_transforms()
	var old_hand = skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
	for id in ["r4", "original"]:
		lab.call("select_revision", id)
		var zombie: Node3D = lab.get("subject")
		var player: AnimationPlayer = zombie.get("animation_player")
		skeleton = zombie.get("skeleton")
		skeleton.force_update_all_bone_transforms()
		var hand = skeleton.get_bone_global_pose(skeleton.find_bone("RightHand")).origin
		var finite = true
		for bone in range(skeleton.get_bone_count()):
			finite = finite and skeleton.get_bone_global_pose(bone).is_finite()
		var separation = old_hand.distance_to(hand)
		_check("paused Original/R4 comparison selects " + id + " at attack frame 42", _selected() == id
			and bool(lab.get("animation_paused")) and int(lab.get("inspection_frame")) == 42
			and String(player.assigned_animation).get_file() == "Zombie_Attack" and absf(player.current_animation_position - 0.7) < 0.00001
			and not player.is_playing() and _labels_match(id) and finite
			and (separation > 0.01 if id == "r4" else separation < 0.00001),
			{"revision": _selected(), "clip": player.assigned_animation, "frame": lab.get("inspection_frame"),
				"clip_time_seconds": player.current_animation_position, "all_bones_finite": finite,
				"right_hand_difference_from_original_m": separation})


func _finish() -> void:
	var changed: Array = []
	for path in source_hashes:
		if FileAccess.get_sha256("res://" + path) != String(source_hashes[path]):
			changed.append(path)
	_check("cold smoke leaves source files unchanged", changed.is_empty(), {"changed_files": changed})
	var failed = 0
	for check in checks:
		if not bool(check.passed):
			failed += 1
	var report = {"passed": failed == 0, "checks": checks.size(), "failed": failed,
		"mode": "cli_startup_only" if cli_only else "cold_package_smoke", "expected_startup_revision": expected_startup,
		"godot_version": Engine.get_version_info(), "project_root": ProjectSettings.globalize_path("res://"),
		"source_sha256_at_start": source_hashes, "files_changed_during_test": changed,
		"models": model_records, "results": checks,
		"scope": "Small archive smoke after the caller performs a fresh import without .godot or extracted asset PNGs. Checks complete model loading, embedded material dependencies, startup and paused comparison; the independent broad integration report covers gameplay and collisions."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file = FileAccess.open(output_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write cold package smoke: " + output_path)
		quit(2)
		return
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("REVISION_PACKAGE_SMOKE_RESULT ", JSON.stringify({"passed": failed == 0, "checks": checks.size(), "failed": failed, "report": output_path}))
	quit(0 if failed == 0 else 1)


func run() -> void:
	var manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not manifest is Dictionary:
		_check("revision catalog parses", false)
		_finish()
		return
	for row in manifest.revisions:
		profiles[String(row.id)] = row
	for path in [MANIFEST, "res://main.gd", "res://main.tscn", "res://scripts/zombie.gd", "res://project.godot", "res://scenes/Zombie.tscn",
		"res://tests/revision_package_smoke.gd"]:
		source_hashes[String(path).trim_prefix("res://")] = FileAccess.get_sha256(path)
	for profile in profiles.values():
		for path in [String(profile.model_path), String(profile.model_path) + ".import"]:
			source_hashes[path.trim_prefix("res://")] = FileAccess.get_sha256(path)
	_check("catalog retains Original default and explicitly marks R4 latest", String(manifest.default_revision) == "original"
		and String(manifest.latest_revision) == "r4" and profiles.size() == 4 and profiles.has(expected_startup))
	lab = (load("res://main.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(lab)
	lab.set_process(false)
	lab.set_physics_process(false)
	Engine.max_fps = 0
	await _ticks(2)
	_check("actual application startup selects " + expected_startup, _selected() == expected_startup
		and String(lab.get("subject").get("revision_id")) == expected_startup
		and String(lab.get("subject").get("model_path")) == String(profiles[expected_startup].model_path))
	_check("startup revision and asset filename are correctly identified in the UI", _labels_match(expected_startup))
	if not cli_only:
		var asset_files: Array[String] = []
		_files_below("res://assets", asset_files)
		var extracted_images: Array = []
		for path in asset_files:
			if path.get_extension().to_lower() in ["png", "jpg", "jpeg", "webp", "tga", "bmp", "exr", "hdr"]:
				extracted_images.append(path)
		_check("asset directory has no old extracted image files", extracted_images.is_empty(), {"external_images_found": extracted_images})
		for id in IDS:
			_load_profile(id)
		_pause_comparison()
	lab.queue_free()
	await _ticks(3)
	_finish()
