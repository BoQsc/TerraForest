# SPDX-License-Identifier: 0BSD
extends SceneTree
## Separate create/missing-mod/reopen processes, exclusively on a new fixture slot.
const LEGACY := "architecture/wooden_door/v1"
const SECOND := "example/doors/narrow_right/v1"
var failures := 0
var slot := ""
var reopening := false
var missing := false
var messages: Array[String] = []
var terrain: Node3D
var host: Node3D

class Host extends Node3D:
	var structures = preload("res://addons/structures/structures_world.gd").new()
	var persistence = preload("res://addons/world_runtime/world_persistence.gd").new()
	var doors = preload("res://addons/structures/door_interaction.gd").new()

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> bool:
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
	return ok
func until(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec()+20000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func save() -> bool:
	messages.clear()
	terrain.changed_since_save = true
	terrain.save_world()
	return await until(func():return messages.any(func(message:String):return message.begins_with("World saved and verified")))
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--door-content-slot="): slot = argument.trim_prefix("--door-content-slot=")
		reopening = reopening or argument == "--reopen-doors"
		missing = missing or argument == "--missing-doors"
	reopening = reopening or missing
	if not slot.begins_with("door_content_check_") or not slot.is_valid_identifier(): quit(2);return
	var directory := "user://mods/" + slot
	var save_path := "user://worlds/" + slot + ".trw"
	var expected_path := directory.path_join("expected.bin")
	if not reopening and (FileAccess.file_exists(save_path) or DirAccess.dir_exists_absolute(directory)):
		push_error("Fixture must use a new unique slot");quit(2);return
	if reopening and (not FileAccess.file_exists(expected_path) or not FileAccess.file_exists(save_path)):
		push_error("Only reopen a slot created by this fixture");quit(2);return
	if not reopening:
		DirAccess.make_dir_recursive_absolute(directory)
		FileAccess.open(directory.path_join("example.objects.json"),FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://mods/example_doors/example.objects.json"))
		var config := ConfigFile.new()
		config.set_value("objects","manifests",PackedStringArray([directory.path_join("example.objects.json")]))
		config.save(directory.path_join("enabled.cfg"))
	terrain = preload("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot = slot
	terrain.diagnostics_pause_streaming = true
	root.add_child(terrain)
	host = Host.new()
	root.add_child(host)
	host.add_child(host.structures)
	var catalog := preload("res://addons/structures/object_catalog.gd").new()
	if not check(catalog.prepare("" if missing else directory.path_join("enabled.cfg")) and catalog.register_all(host.structures).size()==(1 if missing else 2),"persistent host loads enabled definitions"):
		quit(1);return
	check(host.persistence.register_component("structures",host.structures.capture_snapshot,host.structures.restore_snapshot,host.structures.snapshot_validator(),host.structures.empty_snapshot()),"structure models register with real compound world persistence")
	check(host.doors.prepare(host) and host.persistence.attach(terrain)==OK,"door components attach before persistent terrain startup")
	terrain.message_changed.connect(func(message:String):messages.append(message))
	var original_hash := FileAccess.get_sha256(save_path) if missing else ""
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"isolated persistent world starts")
	if missing:
		check(await until(func():return not terrain.latest_error.is_empty()) and not terrain.world_ready,"missing door mod blocks real world startup")
		check(not terrain.backend.write_allowed,"missing model disables world writes")
		terrain.shutdown();host.free();terrain.free()
		check(FileAccess.get_sha256(save_path)==original_hash,"failed load and shutdown preserve exact original save file")
		print("DOOR_CONTENT_STORAGE phase=missing failures=%d" % failures)
		quit(1 if failures else 0);return
	if not check(await until(func():return terrain.world_ready),"persistent world restore finishes"):
		terrain.shutdown();host.free();terrain.free();quit(1);return
	var closed := PackedFloat32Array([1,0,0,10,0,1,0,100,0,0,1,10])
	if reopening:
		var expected: Dictionary = FileAccess.open(expected_path,FileAccess.READ).get_var()
		check(host.structures.capture_snapshot()==expected.models,"fresh process restores exact saved model bytes")
		for entry: Dictionary in host.doors.types.values():
			check(entry.state.is_open(7) and entry.state.capture_storage_snapshot()==expected[entry.id],"fresh process restores opened state for "+entry.id)
			check(entry.state.toggle(entry.collection,7,AABB()).ok and entry.collection.get_instance(7)==closed,"reopened door closes to its original transform: "+entry.id)
		check(await save(),"reopened compound world saves both closed doors")
	else:
		var expected := {}
		for entry: Dictionary in host.doors.types.values():
			check(entry.collection.upsert_instances(PackedInt64Array([7]),closed) and entry.state.toggle(entry.collection,7,AABB()).ok,"place and open "+entry.id)
			expected[entry.id] = entry.state.capture_storage_snapshot()
		expected.models = host.structures.capture_snapshot()
		check(await save(),"compound terrain and both opened doors publish to disk")
		FileAccess.open(expected_path,FileAccess.WRITE).store_var(expected)
	check(await terrain.shutdown_after_edits(),"persistent shutdown completes")
	host.free();terrain.free()
	await process_frame
	if reopening:
		preload("res://tests/terrain_storage_support.gd").cleanup(ProjectSettings.globalize_path(save_path))
		for suffix in ["", ".bak", ".lock"]: DirAccess.remove_absolute(save_path + suffix)
		for name in ["example.objects.json","enabled.cfg","expected.bin"]: DirAccess.remove_absolute(directory.path_join(name))
		DirAccess.remove_absolute(directory)
	print("DOOR_CONTENT_STORAGE phase=%s failures=%d" % ["reopen" if reopening else "create",failures])
	quit(1 if failures else 0)
