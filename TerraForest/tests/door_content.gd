# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog = preload("res://addons/structures/object_catalog.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
const Interaction = preload("res://addons/structures/door_interaction.gd")
const LEGACY := "architecture/wooden_door/v1"
const SECOND := "example/doors/narrow_right/v1"
var failures := 0
var checks := 0
var directory := "user://mods/door_content_%d" % OS.get_process_id()

class Host extends Node3D:
	var structures: Node3D
	var persistence = preload("res://addons/world_runtime/world_persistence.gd").new()
	var doors = Interaction.new()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void: run.call_deferred()
func write_json(path: String, value: Dictionary) -> void:
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(value, "  "))
func configuration(manifests: PackedStringArray) -> String:
	var config := ConfigFile.new()
	config.set_value("objects", "manifests", manifests)
	var path := directory.path_join("enabled.cfg")
	config.save(path)
	return path
func host(config: String) -> Host:
	var game := Host.new()
	game.structures = Structures.new()
	game.add_child(game.structures)
	root.add_child(game)
	var catalog := Catalog.new()
	check(catalog.prepare(config), "read object pack definitions")
	check(catalog.register_all(game.structures).size() == 2, "register both door types as native shared models")
	check(game.doors.prepare(game), "independent native door states register with compound persistence")
	return game
func simple_glb(path: String) -> void:
	# Disposable importer fixture only: two boxes, no authored replacement art.
	var scene := Node3D.new()
	var parent := Node3D.new()
	parent.position = Vector3(0.25,0,0)
	scene.add_child(parent)
	var pixels := Image.create(2,2,false,Image.FORMAT_RGBA8)
	pixels.fill(Color(0.6,0.4,0.2))
	pixels.generate_mipmaps()
	var material := StandardMaterial3D.new()
	material.albedo_texture = ImageTexture.create_from_image(pixels)
	for x in [0.0, 0.5]:
		var part := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.5,2.2,0.14)
		mesh.material = material
		part.mesh = mesh
		part.position = Vector3(x,1.1,0)
		parent.add_child(part)
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	check(document.append_from_scene(scene, state) == OK, "encode simple GLB test fixture")
	FileAccess.open(path, FileAccess.WRITE).store_buffer(document.generate_buffer(state))
	scene.free()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	DirAccess.make_dir_recursive_absolute(directory)
	var pack_path := directory.path_join("example.objects.json")
	var pack: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mods/example_doors/example.objects.json"))
	write_json(pack_path, pack)
	var config := configuration(PackedStringArray([pack_path]))
	var first := host(config)
	var closed := PackedFloat32Array([1,0,0,10,0,1,0,0,0,0,1,0])
	var legacy: Dictionary = first.doors.types[LEGACY]
	var second: Dictionary = first.doors.types[SECOND]
	for entry: Dictionary in [legacy, second]:
		check(entry.collection.upsert_instances(PackedInt64Array([7]), closed), "same numeric placement identity admitted in " + entry.id)
		check(entry.state.toggle(entry.collection, 7, AABB()).ok, "open " + entry.id)
	check(legacy.state.is_open(7) and second.state.is_open(7), "same placement IDs do not alias hinge state")
	var expected_right := Transform3D(Basis(Vector3.UP, -PI/2), Vector3(10.8,0,-0.8))
	var right: PackedFloat32Array = second.collection.get_instance(7)
	check(Vector3(right[3],right[7],right[11]).is_equal_approx(expected_right.origin), "right hinge rotates around authored pivot")
	var snapshots: Dictionary = first.persistence._capture().sections
	var model_bytes: PackedByteArray = first.structures.capture_snapshot()
	check(snapshots.door_hinges.decode_u32(0) == 0x31524454 and snapshots.door_hinges.size() == 64, "original hinge packet stays byte-layout compatible")
	var fresh := host(config)
	check(fresh.structures.restore_snapshot(model_bytes), "fresh model collections restore both stable identities")
	for name: String in snapshots:
		check(fresh.persistence._providers[name].restore.call(snapshots[name]), "fresh hinge restore: " + name)
	for entry: Dictionary in fresh.doors.types.values():
		check(entry.state.is_open(7) and entry.state.toggle(entry.collection,7,AABB()).ok and entry.collection.get_instance(7) == closed, "fresh restored door closes to exact original pose: " + entry.id)
	var before: PackedByteArray = legacy.state.capture_storage_snapshot()
	check(second.state.toggle(second.collection,7,AABB()).ok and legacy.state.capture_storage_snapshot() == before, "one type closing leaves other type unchanged")
	var changed: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	check(changed.configure(second.definition.bounds,Vector3(0.8,0,0),-45), "different behavior contract configures")
	var section := "door_" + SECOND.sha256_text().left(40)
	check(not changed.validate_snapshot(snapshots[section]), "incompatible saved hinge geometry rejects instead of reinterpreting open pose")
	var old_only := Structures.new()
	root.add_child(old_only)
	preload("res://addons/structures/door_catalog.gd").register(old_only)
	var old_before: PackedByteArray = old_only.capture_snapshot()
	check(not old_only.restore_snapshot(model_bytes) and old_only.capture_snapshot() == old_before, "missing mod rejects model save without mutating existing world")
	var old_state: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	var historical_models := FileAccess.get_file_as_bytes("res://tests/fixtures/door_legacy/structures.bin")
	var historical_hinges := FileAccess.get_file_as_bytes("res://tests/fixtures/door_legacy/hinges.bin")
	check(fresh.structures.restore_snapshot(historical_models) and fresh.doors.state.restore_storage_snapshot(historical_hinges), "actual pre-change native saves restore with the extra mod installed")
	check(fresh.doors.state.capture_storage_snapshot() == historical_hinges, "legacy hinge bytes roundtrip unchanged")
	check(fresh.doors.state.toggle(fresh.doors.collection,7,AABB()).ok and fresh.doors.collection.get_instance(7) == closed, "actual legacy opened door closes to its original pose")
	var old_models: PackedByteArray = old_only.capture_snapshot()
	check(fresh.structures.restore_snapshot(old_models), "older world with no second door loads after enabling mod")
	check(fresh.structures.model(SECOND).get_ids().is_empty(), "new type defaults empty in older world")
	check(legacy.state.validate_snapshot(old_state.capture_storage_snapshot()), "legacy empty hinge default accepted")
	var recipes := preload("res://addons/structures/construction_catalog.gd").recipes(first.structures.object_definitions)
	var salvage := preload("res://addons/structures/construction_catalog.gd").salvage_recipes(first.structures.object_definitions)
	check(recipes[SECOND] == PackedInt64Array([102,5]) and salvage[SECOND] == PackedInt64Array([102,2]), "construction and salvage consume the readable definition")
	check(preload("res://addons/player_runtime/durability_catalog.gd").model_profile(SECOND,first.structures.object_definitions).health == 75, "damage profile consumes the same definition")
	var no_salvage: Dictionary = first.structures.object_definitions.duplicate(true)
	no_salvage[SECOND].salvage = {}
	check(not preload("res://addons/structures/construction_catalog.gd").salvage_recipes(no_salvage).has(SECOND), "empty salvage uses ordinary removal instead of an empty inventory grant")
	check(not second.definition.behavior.zombie_breakable and first.doors.breakable_bodies().is_empty(), "new doors do not grant implicit zombie permissions")
	var glb_path := directory.path_join("simple.glb")
	simple_glb(glb_path)
	pack.replacements = [{"id":LEGACY,"visual":{"source":"simple.glb"}}]
	write_json(pack_path,pack)
	var replacement := Catalog.new()
	check(replacement.prepare(config), "visual-only GLB replacement admitted")
	var visual: Mesh = replacement.visuals.load_visual(replacement.definitions[LEGACY].visual,directory)
	check(visual != null, "loose GLB imports without editor or resource pack: " + replacement.visuals.error)
	if visual != null:
		check(visual.get_aabb().position.is_equal_approx(Vector3(0,0,-.07)) and visual.get_aabb().size.is_equal_approx(Vector3(1,2.2,.14)), "nested GLB transforms and parts consolidate correctly")
		var material: StandardMaterial3D = visual.surface_get_material(0)
		check(material != null and material.albedo_texture != null and material.albedo_texture.get_width()==2, "embedded GLB texture and material survive consolidation")
		check(visual == replacement.visuals.load_visual(replacement.definitions[LEGACY].visual,directory), "repeated visual request reuses one mesh")
	check(replacement.definitions[LEGACY].bounds == legacy.definition.bounds and replacement.definitions[LEGACY].behavior == legacy.definition.behavior, "replacement preserves collision and behavior contract")
	var swapped := host(config)
	check(swapped.structures.restore_snapshot(model_bytes) and swapped.doors.state.restore_storage_snapshot(snapshots.door_hinges), "GLB visual swap restores prior model and hinge saves")
	check(swapped.doors.state.toggle(swapped.doors.collection,7,AABB()).ok and swapped.doors.collection.get_instance(7) == closed, "replaced open legacy door closes exactly")
	for bad in ["../outside.glb", "C:/outside.glb", "https://example.com/a.glb", "bad.tres"]:
		pack.replacements[0].visual.source = bad
		write_json(pack_path,pack)
		var rejected := Catalog.new()
		check(not rejected.prepare(config) and not rejected.diagnostics.is_empty(), "reject invalid visual source: " + bad)
	pack.replacements[0].visual.source = "simple.glb"
	pack.replacements[0].collision = {"size":[2,2,2]}
	write_json(pack_path,pack)
	check(not Catalog.new().prepare(config), "visual replacement cannot change gameplay collision")
	pack.replacements[0].erase("collision")
	pack.replacements.append(pack.replacements[0].duplicate(true))
	write_json(pack_path,pack)
	check(not Catalog.new().prepare(config), "conflicting replacements reject explicitly")
	pack.replacements = []
	pack.objects[0].behavior.opening_degrees = 0
	write_json(pack_path,pack)
	check(not Catalog.new().prepare(config), "invalid behavior rejected before registration")
	var swing_batch: Node3D = ClassDB.instantiate("NativeStaticBatch")
	var wide_swing: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	check(swing_batch.configure_asset("test/sweep/v1",BoxMesh.new()) and swing_batch.upsert_instances(PackedInt64Array([1]),closed), "independent native swing fixture")
	check(wide_swing.configure(AABB(Vector3(0,0,-.07),Vector3(1,2.2,.14)),Vector3.ZERO,150), "configurable large opening angle")
	var hinge_before: PackedByteArray = wide_swing.capture_storage_snapshot()
	check(not wide_swing.toggle(swing_batch,1,AABB(Vector3(9.95,.5,-1.02),Vector3(.1,1,.12))).ok and swing_batch.get_instance(1)==closed and wide_swing.capture_storage_snapshot()==hinge_before, "intermediate swing occupancy blocks a 150-degree turn transactionally")
	var cycles_ok := true
	for cycle in 100:
		cycles_ok = wide_swing.toggle(swing_batch,1,AABB()).ok and wide_swing.toggle(swing_batch,1,AABB()).ok and swing_batch.get_instance(1)==closed and cycles_ok
	check(cycles_ok, "100 arbitrary-angle cycles close without accumulated drift")
	check(not wide_swing.configure(second.definition.bounds,Vector3.ZERO,45), "native profile cannot change after configuration")
	swing_batch.free()
	# Model batches keep node count independent of placement count.
	var poses := PackedFloat32Array()
	var ids := PackedInt64Array()
	for i in 10000:
		ids.append(i+1)
		poses.append_array(PackedFloat32Array([1,0,0,float(i%100)*2,0,1,0,0,0,0,1,float(i/100)*2]))
	var nodes_before: int = second.collection.get_child_count()
	check(second.collection.upsert_instances(ids,poses), "10000 door placements use native collection storage")
	check(second.collection.get_child_count() == nodes_before, "no scene node or script per placed door")
	for node: Node in [first,fresh,old_only,swapped]: node.free()
	for name in ["example.objects.json","enabled.cfg","simple.glb"]: DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/door_content.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("DOOR_CONTENT checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
