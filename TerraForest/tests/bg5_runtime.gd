# SPDX-License-Identifier: 0BSD
extends SceneTree
const Visual = preload("res://addons/structures/object_mesh.gd")
const Structures = preload("res://addons/structures/structures_world.gd")
var checks := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func run() -> void:
	if "--packed-bg5-check" in OS.get_cmdline_user_args():
		check(not FileAccess.file_exists("res://authoring/bg5/BG5.Door.Parts.glb"),"editable masters are excluded from game export")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://mods/bg5_runtime/bake.json"))
	var limits := {"door_leaf":3,"door_frame":3,"chest":1,"chair":2,"table":2,"shelf":1}
	var expected := {
		"chest":AABB(Vector3(-.6075,0,-.39),Vector3(1.215,.75,.8075)),
		"chair":AABB(Vector3(-.24,0,-.24),Vector3(.48,.98,.48)),
		"table":AABB(Vector3(-.8,0,-.45),Vector3(1.6,.8,.9)),
		"shelf":AABB(Vector3(-.6,0,-.2),Vector3(1.2,1.8,.4))}
	var visual := Visual.new()
	for name: String in data.assets:
		var entry: Dictionary = data.assets[name]
		var mesh := visual.load_visual({"source":name+".glb"},"res://mods/bg5_runtime")
		check(mesh != null,"portable "+name+" passes real loose-GLB admission: "+visual.error)
		if mesh == null: continue
		check(mesh.get_surface_count()<=limits[name],name+" has consolidated material surfaces")
		if not entry.has("prefab"): continue
		var baked: Mesh = load(entry.prefab)
		check(baked.get_surface_count()<=limits[name],name+" built-in uses the same bounded shared mesh")
		check(mesh.get_aabb().position.distance_to(baked.get_aabb().position)<.0002 and mesh.get_aabb().size.distance_to(baked.get_aabb().size)<.0002,name+" GLB and native resource have matching bounds")
		var triangle_count := 0
		var lod_count := 0
		for surface: Dictionary in baked.get("_surfaces"):
			triangle_count += int(surface.index_count)/3
			lod_count += surface.get("lods",{}).size()
		check(triangle_count==int(entry.triangles) and lod_count>0,name+" retains offline geometry LODs")
		if expected.has(name):
			var bounds: AABB = expected[name]
			check(bounds.position.distance_to(baked.get_aabb().position)<.0002 and bounds.size.distance_to(baked.get_aabb().size)<.0002,name+" matches the previous mesh size and ground origin")
		for index in baked.get_surface_count():
			var material: StandardMaterial3D = baked.surface_get_material(index)
			check(material.texture_filter==BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC,name+" uses mipmapped anisotropic filtering")
	for path: String in data.textures:
		var texture: Texture2D = load(path)
		check(texture is CompressedTexture2D and texture.get_image().is_compressed() and texture.get_image().has_mipmaps() and maxi(texture.get_width(),texture.get_height())<=1024,"built-in VRAM-compressed mipmapped texture stays inside 1024px limit")
	var scaled := visual.load_visual({"source":"builtin:wooden_door","scale":[.8,1,1]},"")
	var scaled_lods := 0
	for surface: Dictionary in scaled.get("_surfaces"):scaled_lods+=surface.get("lods",{}).size()
	check(scaled_lods>0,"scaled built-in mod door retains generated geometry LODs")
	var world := Structures.new()
	root.add_child(world)
	var door: Dictionary = preload("res://addons/structures/door_catalog.gd").register(world)
	var furniture: Array[Dictionary] = preload("res://addons/structures/furniture_catalog.gd").register(world)
	check(furniture.size()==3,"replacement furniture registers original native compound collision")
	var hinges: RefCounted = ClassDB.instantiate("NativeHingedDoors")
	check(door.collection != null,"new default door uses original native collection identity")
	var fixture := "res://tests/fixtures/door_legacy/"
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--door-fixtures="): fixture=argument.trim_prefix("--door-fixtures=").path_join("")
	check(world.restore_snapshot(FileAccess.get_file_as_bytes(fixture+"structures.bin")),"actual pre-content model packet restores with replacement art")
	check(hinges.restore_storage_snapshot(FileAccess.get_file_as_bytes(fixture+"hinges.bin")) and hinges.is_open(7),"actual pre-content open hinge packet restores")
	var closed := PackedFloat32Array([1,0,0,10,0,1,0,0,0,0,1,0])
	check(hinges.toggle(door.collection,7,AABB()).ok and door.collection.get_instance(7)==closed,"replaced old door closes to its exact historical transform")
	check(hinges.toggle(door.collection,7,AABB()).ok and hinges.capture_storage_snapshot()==FileAccess.get_file_as_bytes(fixture+"hinges.bin"),"reopening preserves exact legacy hinge bytes")
	check(door.collection.get_child_count()==0,"replacement creates no per-door scene children")
	var boxes := {"chair":6,"table":5,"shelf":7}
	for name: String in boxes:
		var native_mesh: Mesh = load("res://addons/structures/prefabs/"+name+"_model.tres")
		check(native_mesh.get_meta("collision_boxes").size()==boxes[name],name+" keeps its canonical proxy count")
	var before_nodes := world.get_child_count()
	var ids := PackedInt64Array()
	var poses := PackedFloat32Array()
	for i in 10000:
		ids.append(i+1)
		poses.append_array(PackedFloat32Array([1,0,0,float(i%100)*3,0,1,0,0,0,0,1,float(i/100)*3]))
	check(door.collection.upsert_instances(ids,poses),"10000 supplied door leaves remain in native placement storage")
	check(world.get_child_count()==before_nodes and door.collection.get_child_count()==0,"supplied art adds no per-placement node or animation player")
	world.free()
	var oversized := PackedByteArray()
	# Malformed content is rejected before the GLTF decoder allocates images.
	var json := JSON.stringify({"asset":{"version":"2.0"},"images":[{},{},{},{},{},{},{},{},{}]}).to_utf8_buffer()
	while json.size()%4:json.append(32)
	oversized.resize(20);oversized.encode_u32(0,0x46546c67);oversized.encode_u32(4,2);oversized.encode_u32(8,20+json.size());oversized.encode_u32(12,json.size());oversized.encode_u32(16,0x4e4f534a);oversized.append_array(json)
	var invalid := "user://bg5_invalid_%d.glb" % OS.get_process_id()
	var file := FileAccess.open(invalid,FileAccess.WRITE);file.store_buffer(oversized);file.close()
	check(visual.load_visual({"source":invalid.get_file()},"user://")==null and "eight" in visual.error,"nine embedded images reject before decode")
	DirAccess.remove_absolute(invalid)
	print("BG5_RUNTIME_CHECK checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
