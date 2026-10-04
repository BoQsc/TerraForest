# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
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
func paved_at(core: Object,ends: PackedVector3Array) -> bool:
	# Only call after close_world has joined the owning worker. Keep a reference
	# to its core so this test never races native mutations or mesh production.
	for point in [ends[0],ends[0].lerp(ends[1],0.5),ends[1]]:
		var packet:=Codec.point_command(point-Vector3.UP);packet.encode_u32(0,26)
		var reply: PackedByteArray=core.execute(packet)
		if not Codec.reply_ok(reply) or reply.decode_u32(12)!=4 or reply.decode_float(16)>=0: return false
		packet=Codec.point_command(point+Vector3.UP*2);packet.encode_u32(0,26)
		reply=core.execute(packet)
		if not Codec.reply_ok(reply) or reply.decode_float(16)<=0: return false
	return true
func run() -> void:
	Engine.max_fps=60
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not create_world() or not await wait_ready(): close_world();quit(1);return
	var ends:=PackedVector3Array([Vector3(400,180,400),Vector3(464,180,400)])
	var revision: int=terrain.density_revision
	var accepted: bool=terrain.construct_road_bed(ends[0],ends[1],4,8,12)
	var edit_deadline:=Time.get_ticks_msec()+15000
	while terrain.pending_edit and Time.get_ticks_msec()<edit_deadline: await process_frame
	var published: bool=accepted and not terrain.pending_edit and terrain.last_edit_outcome.get("status","")=="published" and terrain.density_revision==revision+1
	check(published,"real native street publishes before anchors are registered")
	if not published: close_world();quit(1);return
	palette.register_prepared_street({"paving_segments":1,"street_ends":ends,"street_width":8},terrain.epoch)
	var snapshot: PackedByteArray=palette.capture_anchors()
	check(snapshot.size()==64 and palette.anchor_storage.validate_snapshot(snapshot),"bounded native anchor encoding")
	check(palette.restore_anchors(snapshot) and palette.prepared_streets.size()==1 and palette.selected_street==0,"legacy single-street record restores as catalog")
	var maximum:=PackedByteArray()
	for i in 256: maximum.append_array(snapshot)
	var maximum_encoded: PackedByteArray=palette.anchor_storage.encode_collection(maximum,255)
	check(maximum_encoded.size()==16400 and palette.anchor_storage.validate_snapshot(maximum_encoded),"native catalog accepts its exact 256-record bound")
	maximum.append_array(snapshot)
	check(palette.anchor_storage.encode_collection(maximum,0).is_empty(),"native catalog rejects 257 records")
	var bad:=snapshot.duplicate();bad.encode_double(8,NAN)
	check(not palette.restore_anchors(bad) and palette.capture_anchors()==snapshot,"invalid coordinates cannot replace anchors")
	bad=snapshot.duplicate();bad.encode_u32(4,3)
	check(not palette.anchor_storage.validate_snapshot(bad),"unknown version rejected")
	bad=snapshot.duplicate();bad.append(0)
	check(not palette.anchor_storage.validate_snapshot(bad),"trailing bytes rejected")
	bad=snapshot.duplicate();bad.encode_double(56,65)
	check(not palette.anchor_storage.validate_snapshot(bad),"unsupported street width rejected")
	var second:=PackedVector3Array([Vector3(400,180,420),Vector3(464,180,420)])
	accepted=terrain.construct_road_bed(second[0],second[1],4,8,12)
	edit_deadline=Time.get_ticks_msec()+15000
	while terrain.pending_edit and Time.get_ticks_msec()<edit_deadline: await process_frame
	check(accepted and not terrain.pending_edit and terrain.last_edit_outcome.get("status","")=="published","second street publishes")
	palette.register_prepared_street({"paving_segments":1,"street_ends":second,"street_width":8},terrain.epoch)
	palette.register_prepared_street({"paving_segments":1,"street_ends":second,"street_width":8},terrain.epoch)
	check(palette.prepared_streets.size()==2 and palette.street_selector.item_count==2,"distinct streets retained and repeated registration deduplicated")
	check(palette.select_prepared_street(0) and palette.prepared_street.ends==ends,"earlier street remains selectable")
	snapshot=palette.capture_anchors()
	check(snapshot.size()==144 and palette.anchor_storage.validate_snapshot(snapshot),"two streets use bounded version-two collection")
	bad=snapshot.duplicate();bad.encode_u32(8,257)
	check(not palette.anchor_storage.validate_snapshot(bad),"oversized catalog count rejected")
	bad=snapshot.duplicate();bad.encode_u32(12,2)
	check(not palette.restore_anchors(bad) and palette.capture_anchors()==snapshot,"invalid selected index leaves catalog unchanged")
	messages.clear();terrain.save_world()
	var deadline:=Time.get_ticks_msec()+15000
	while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline: await process_frame
	check(messages.any(func(m):return m.begins_with("World saved and verified")),"compound anchor save published")
	var original_core: Object=terrain.backend.native
	close_world()
	check(paved_at(original_core,ends),"saved street has asphalt support and open clearance at both entrances and midpoint")
	check(paved_at(original_core,second),"second saved street has asphalt and clearance")
	original_core=null
	if not create_world() or not await wait_ready(): close_world();quit(1);return
	check(palette.capture_anchors()==snapshot and palette.street_controls.visible,"new world restores anchors from disk")
	check(palette.prepared_streets.size()==2 and palette.selected_street==0,"catalog and selected earlier street restore together")
	check(palette.select_street_end(1,terrain) and palette.start==ends[1] and not palette.has_finish,"restored entrance selects exact preview endpoint")
	var restored_core: Object=terrain.backend.native
	check(palette.restore_anchors(PackedByteArray()) and palette.prepared_street.is_empty() and not palette.street_controls.visible,"missing legacy section clears anchors")
	close_world()
	check(paved_at(restored_core,ends),"reopened terrain preserves asphalt and clearance at restored anchor coordinates")
	check(paved_at(restored_core,second),"reopened terrain preserves second street too")
	restored_core=null
	var path:=ProjectSettings.globalize_path("user://worlds/"+slot+".trw")
	for suffix in ["",".bak",".lock"]: DirAccess.remove_absolute(path+suffix)
	quit(0 if failures==0 else 1)
