# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog = preload("res://addons/house_lights/catalog.gd")
var checks := 0
var failures := 0

class TransformProbe extends OmniLight3D:
	var notifications:=0
	func _notification(what:int)->void:
		if what==NOTIFICATION_TRANSFORM_CHANGED:notifications+=1

class Host extends Node:
	var structures: Node3D
	var terrain: Dictionary = {"backend": {"world_seed": 1703}, "changed_since_save": false}
	var world_vehicle: Dictionary = {"fleet": ClassDB.instantiate("NativeVehicleFleet")}
	var quests: Dictionary = {"store": ClassDB.instantiate("NativeQuestLog")}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
	return ok

func pump(frames: int = 15) -> void:
	for frame in frames: await process_frame

func run() -> void:
	var catalog := Catalog.new()
	if not check(catalog.prepare(false), "three bounded GLB provider definitions load: " + str(catalog.errors)): quit(1); return
	for key: String in catalog.definitions:
		var mesh: Mesh = catalog.definitions[key].mesh
		var animated := false
		for surface in mesh.get_surface_count(): animated = animated or mesh.surface_get_material(surface) is ShaderMaterial
		check(animated, "GLB flame surface uses bounded GPU animation: " + key)
	var structures := preload("res://addons/structures/structures_world.gd").new(); root.add_child(structures)
	check(structures.prepare(), "native structure owner prepares")
	for name: String in ["furniture", "storage", "window", "door"]:
		load("res://addons/structures/" + name + "_catalog.gd").register(structures)
	var entries := catalog.register(structures)
	check(entries.size() == 3, "shared mesh/collision collections registered")
	var empty: PackedByteArray = structures.capture_storage_snapshot()
	var pool: Node3D = catalog.runtime(structures)
	if not check(pool != null, "native fixed four-light pool configures"): structures.free(); quit(1); return
	var identity := 0
	for key: String in catalog.definitions:
		var collection: Node3D = structures.model(key)
		var transforms := PackedFloat32Array()
		var ids := PackedInt64Array()
		for index in 6:
			identity += 1; ids.append(identity)
			var pose := Transform3D(Basis.IDENTITY, Vector3(index * 4, 0, 0))
			for row in 3:
				for column in 3: transforms.append(pose.basis[column][row])
				transforms.append(pose.origin[row])
		check(collection.upsert_instances(ids, transforms), "native GLB placements accepted: " + key)
	pool.set_focus(Vector3(4, 1, 0)); await pump()
	check(pool.statistics().active == 4 and pool.get_child_count() == 4, "eighteen objects use exactly four pooled light nodes")
	for light:OmniLight3D in pool.get_children():
		light.set_script(TransformProbe);light.set_notify_transform(true)
	await pump(2)
	for light:OmniLight3D in pool.get_children():light.notifications=0
	await pump(10)
	var notifications:=0
	for light:OmniLight3D in pool.get_children():notifications+=light.notifications
	check(notifications==0,"stationary pooled lights do not emit redundant transform notifications every frame")
	# Moving a source collection still moves every retained light belonging to it.
	for key:String in catalog.definitions:structures.model(key).position.y+=.25
	await pump(2)
	var moved:=0
	for light:OmniLight3D in pool.get_children():moved+=light.notifications
	check(moved>0,"real placement transform changes still reach pooled lights")
	for key:String in catalog.definitions:structures.model(key).position.y-=.25
	await pump(2)
	var before: PackedByteArray = structures.capture_storage_snapshot()
	for key: String in catalog.definitions:
		var collection: Node3D = structures.model(key)
		collection.remove_instances(collection.get_ids())
	await pump(2)
	check(pool.statistics().active == 0, "destroyed objects stop emitting light immediately")
	check(structures.restore_storage_snapshot(before), "ordinary native model persistence restores objects")
	await pump()
	check(pool.statistics().active == 4, "restored object residency restores pooled light")
	pool.set_enabled(false)
	check(pool.statistics().active == 0 and not pool.is_processing(), "disabled pool contributes no processing or lights")
	pool.set_enabled(true); pool.set_focus(Vector3(1000, 1, 1000)); await pump()
	check(pool.statistics().active == 0, "far objects retain mesh ownership without real light nodes")
	pool.set_focus(Vector3(4, 1, 0)); await pump()
	check(pool.statistics().active == 4 and pool.statistics().visited <= 512, "near readmission and native per-update work budget")
	var invalid: Node3D = ClassDB.instantiate("NativeResidentLights"); structures.add_child(invalid)
	check(not invalid.configure([], 4) and not invalid.configure([{}], 4) and invalid.get_child_count() == 0, "bad providers cannot partially allocate lights")
	for key: String in catalog.definitions: structures.model(key).remove_instances(structures.model(key).get_ids())
	var dense: Node3D = structures.model("lighting/iron_fireplace/v1")
	var dense_ids := PackedInt64Array(); var dense_values := PackedFloat32Array()
	for index in 1536:
		dense_ids.append(10000 + index)
		dense_values.append_array(PackedFloat32Array([1,0,0,20 if index < 1535 else 0,0,1,0,0,0,0,1,0]))
	check(dense.upsert_instances(dense_ids, dense_values), "dense native light-source group publishes without per-object light nodes")
	pool.set_focus(Vector3(0, .75, .15)); await pump(45)
	var late_found := false
	for light: Dictionary in pool.statistics().lights: late_found = late_found or light.id == 11535
	check(late_found and pool.statistics().visited <= 512 and pool.get_child_count() == 4, "dense scan continues across bounded updates rather than starving late identities")
	check(structures.restore_storage_snapshot(empty), "empty furnished fixture restores for room planning")
	var building_catalog = preload("res://addons/structures/expansion_catalog.gd")
	for kind: String in building_catalog.IDS:
		var asset: Resource = building_catalog.asset(kind)
		var plan: Dictionary = asset.interior_light_sites()
		check(plan.ok and not plan.rooms.is_empty() and plan.probes <= 200000, "native cached room survey: " + kind + " rooms=" + str(plan.get("rooms", []).size()))
	var house: Resource = building_catalog.asset("house_c1")
	var placement: RefCounted = ClassDB.instantiate("NativePrefabPlacement")
	check(placement.place(structures.blocks, house, Vector3i(100, 30, 100), 0, structures.model_collections(), []).ok, "unchanged approved C1 and all attached models publish")
	var host := Host.new(); root.add_child(host); host.structures = structures
	var generated := preload("res://addons/house_lights/generation.gd").publish(host, [{"asset": house, "origin": Vector3i(100, 30, 100), "rotation": 0, "label": "C1"}])
	check(generated.ok and generated.placements.size() > 0 and host.terrain.changed_since_save, "normal light generation uses native rooms and publishes breakable objects: " + str(generated))
	host.free()
	structures.free(); await process_frame
	print("HOUSE_LIGHTS checks=%d failures=%d" % [checks, failures]); quit(1 if failures else 0)
