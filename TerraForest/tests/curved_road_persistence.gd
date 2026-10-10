# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const DIR="res://reports/curved_road_persistence/"
var failures:=0
var messages: Array[String]=[]
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var slot:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--road-slot="):slot=arg.trim_prefix("--road-slot=")
	if not slot.begins_with("curved_road_test_") or not slot.is_valid_identifier():quit(1);return
	var reopen: bool="--reopen-road" in OS.get_cmdline_user_args()
	var archive:="user://worlds/"+slot+".trw"
	if not reopen and FileAccess.file_exists(archive):quit(1);return
	if reopen and not FileAccess.file_exists(archive):quit(1);return
	DirAccess.make_dir_recursive_absolute(DIR)
	var terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.save_slot=slot;terrain.diagnostics_pause_streaming=true
	terrain.backend.world_generator=4;terrain.backend.world_seed=1703
	terrain.backend.disk_cache.enabled=false;terrain.focus=Vector3(600,82,1310)
	terrain.message_changed.connect(func(message: String):messages.append(message))
	root.add_child(terrain)
	check(terrain.start(StandardMaterial3D.new(),false)==OK,"persistent terrain worker starts")
	var deadline:=Time.get_ticks_msec()+20000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline:await process_frame
	check(terrain.world_ready,"persistent terrain ready")
	if not terrain.world_ready:terrain.shutdown();quit(1);return
	if not reopen:
		var coefficients:=PackedFloat64Array()
		for i in 4:coefficients.append_array(PackedFloat64Array([0,0.256,-4+0.512*i,85.96295-4*i+0.256*i*i]))
		for i in 4:
			var a:=Vector3(576+i*16,coefficients[i*4+3],1310)
			var b:=a+Vector3(16,coefficients[i*4+1]+coefficients[i*4+2],0)
			var accepted: bool=terrain.construct_curved_road_bed(a,b,coefficients,i)
			deadline=Time.get_ticks_msec()+20000
			while terrain.pending_edit and Time.get_ticks_msec()<deadline:await process_frame
			check(accepted and not terrain.pending_edit and terrain.last_edit_outcome.get("status","")=="published","curved section publishes "+str(i))
	else:
		var epoch: int=terrain.epoch
		terrain.reload_world()
		deadline=Time.get_ticks_msec()+20000
		while (not terrain.world_ready or terrain.epoch==epoch) and Time.get_ticks_msec()<deadline:await process_frame
		check(terrain.world_ready and terrain.epoch>epoch,"normal reload completes before persistence comparison")
	messages.clear();terrain.save_world();deadline=Time.get_ticks_msec()+20000
	while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline:await process_frame
	check(messages.any(func(m):return m.begins_with("World saved and verified")),"manual save verified")
	var core: RefCounted=terrain.backend.native
	terrain.backend.disable_snapshot_writes();terrain.shutdown();terrain.free()
	# Owning worker is joined before direct native probes.
	var hashes: Array=[];var epoch: int=core.execute(Codec.command(13)).decode_u32(12)
	for x in [576,592,608,624]:
		for z in [1296,1312]:
			for y in [32,64,96]:
				var packet: PackedByteArray=core.build_owned_region(x,z,16,1,y,y+32,epoch)
				check(not Codec.decode_mesh(packet).has("error"),"saved collision mesh valid "+str(Vector3i(x,y,z)))
				var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(packet);hashes.append(hash.finish().hex_encode())
	var probes:=PackedByteArray()
	for x in [584,600,616,632]:
		var height: float=85.96295-(x-576)*0.25+0.001*(x-576)*(x-576)
		for offset in [-1.0,1.0]:
			var command:=Codec.point_command(Vector3(x,height+offset,1310));command.encode_u32(0,26)
			var reply: PackedByteArray=core.execute(command)
			check(Codec.reply_ok(reply) and (reply.decode_float(16)<0 and reply.decode_u32(12)==4 if offset<0 else reply.decode_float(16)>0),"asphalt support and open clearance")
			probes.append_array(reply.slice(12))
	var state:={"hashes":hashes,"probes":probes.hex_encode(),"slot":slot}
	if reopen:
		var expected: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIR+"baseline.json"))
		check(state==expected,"fresh process plus reload preserves exact collision geometry materials and densities")
	else:
		var baseline:=FileAccess.open(DIR+"baseline.json",FileAccess.WRITE);baseline.store_string(JSON.stringify(state,"  "));baseline.close()
	var file:=FileAccess.open(DIR+("reopen.json" if reopen else "create.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"slot":slot,"reopen":reopen,"meshes":hashes.size()},"  "));file.close()
	quit(1 if failures else 0)
