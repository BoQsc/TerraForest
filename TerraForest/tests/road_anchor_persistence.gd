# SPDX-License-Identifier: 0BSD
extends SceneTree
var terrain: Node
var palette: Node
var persistence: RefCounted
var messages: Array[String]=[]
var slot: String="road_anchors_%d" % OS.get_process_id()
var failures:=0
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func create_world() -> bool:
	terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false
	root.add_child(terrain)
	palette=load("res://addons/volumetric_terrain/road_palette.gd").new();root.add_child(palette)
	persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	if not palette.prepare_persistence(terrain,persistence) or persistence.attach(terrain)!=OK: return false
	terrain.message_changed.connect(func(message: String):messages.append(message))
	return terrain.start(StandardMaterial3D.new(),false)==OK
func wait_ready() -> bool:
	var deadline:=Time.get_ticks_msec()+15000
	while not terrain.world_ready and terrain.latest_error.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	return terrain.world_ready
func close_world() -> void:
	terrain.shutdown();palette.free();terrain.free();persistence=null
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not create_world() or not await wait_ready(): close_world();quit(1);return
	var ends:=PackedVector3Array([Vector3(400,80,400),Vector3(464,80,400)])
	palette.register_prepared_street({"paving_segments":1,"street_ends":ends,"street_width":8},terrain.epoch)
	var snapshot: PackedByteArray=palette.capture_anchors()
	check(snapshot.size()==64 and palette.anchor_storage.validate_snapshot(snapshot),"bounded native anchor encoding")
	var bad:=snapshot.duplicate();bad.encode_double(8,NAN)
	check(not palette.restore_anchors(bad) and palette.capture_anchors()==snapshot,"invalid coordinates cannot replace anchors")
	bad=snapshot.duplicate();bad.encode_u32(4,2)
	check(not palette.anchor_storage.validate_snapshot(bad),"unknown version rejected")
	bad=snapshot.duplicate();bad.append(0)
	check(not palette.anchor_storage.validate_snapshot(bad),"trailing bytes rejected")
	bad=snapshot.duplicate();bad.encode_double(56,65)
	check(not palette.anchor_storage.validate_snapshot(bad),"unsupported street width rejected")
	messages.clear();terrain.save_world()
	var deadline:=Time.get_ticks_msec()+15000
	while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline: await process_frame
	check(messages.any(func(m):return m.begins_with("World saved and verified")),"compound anchor save published")
	close_world()
	if not create_world() or not await wait_ready(): close_world();quit(1);return
	check(palette.capture_anchors()==snapshot and palette.street_controls.visible,"new world restores anchors from disk")
	check(palette.select_street_end(1,terrain) and palette.start==ends[1] and not palette.has_finish,"restored entrance selects exact preview endpoint")
	check(palette.restore_anchors(PackedByteArray()) and palette.prepared_street.is_empty() and not palette.street_controls.visible,"missing legacy section clears anchors")
	close_world()
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	for suffix in ["",".bak",".lock"]: DirAccess.remove_absolute(path+suffix)
	quit(0 if failures==0 else 1)
