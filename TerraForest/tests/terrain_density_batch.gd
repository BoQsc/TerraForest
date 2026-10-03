# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var replies: Array[Dictionary]=[]
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func packet(points: PackedVector3Array,revision: int) -> PackedByteArray:
	var p:=Codec.command(29,[revision,points.size()]);p.append_array(points.to_byte_array());return p
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,2]))
	var revision: int=core.execute(Codec.command(0)).decode_u32(12)
	var points:=PackedVector3Array([Vector3(400,179,400),Vector3(400,230,400)])
	var reply: PackedByteArray=core.execute(packet(points,revision))
	check(Codec.reply_ok(reply) and reply.size()==28 and reply.decode_u32(12)==revision,"native bounded query includes revision and exact result size")
	var same:=true
	for i in points.size():
		var q:=Codec.point_command(points[i]);q.encode_u32(0,26)
		same=same and reply.decode_float(20+i*4)==core.execute(q).decode_float(16)
	check(same,"batch agrees with authoritative lattice density samples")
	check(not Codec.reply_ok(core.execute(packet(points,revision+1))),"stale revision supplies no accepted density values")
	var limit:=PackedVector3Array();limit.resize(512);limit.fill(points[0])
	var full: PackedByteArray=core.execute(packet(limit,revision))
	check(Codec.reply_ok(full) and full.size()==2068 and full.decode_u32(16)==512,"maximum 512-probe batch remains bounded")
	var too_many:=PackedVector3Array();too_many.resize(513);too_many.fill(Vector3(400,100,400))
	for bad in [packet(PackedVector3Array(),revision),packet(too_many,revision),packet(PackedVector3Array([Vector3(NAN,0,0)]),revision),packet(points,revision).slice(0,20)]:
		check(not Codec.reply_ok(core.execute(bad)),"invalid or oversized batch rejected")
	var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=2;root.add_child(terrain)
	terrain.density_batch_ready.connect(func(result: Dictionary): replies.append(result))
	check(terrain.start(StandardMaterial3D.new(),true)==OK,"terrain starts")
	var deadline:=Time.get_ticks_msec()+30000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready and terrain.request_density_batch(points,10),"public facade submits query to terrain worker")
	check(not terrain.request_density_batch(points,11),"one outstanding reservation includes unconsumed completion")
	deadline=Time.get_ticks_msec()+10000
	while replies.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(replies.size()==1 and replies[0].status=="ok" and replies[0].values.size()==2 and replies[0].token==10,"worker publishes requested batch")
	replies.clear()
	check(terrain.backend.submit({"kind":"density_batch","points":points,"token":12,"epoch":terrain.epoch,"revision":terrain.density_revision+1}),"stale worker fixture admitted")
	deadline=Time.get_ticks_msec()+10000
	while replies.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(replies.size()==1 and replies[0].status=="stale" and replies[0].values.is_empty(),"stale worker result contains no usable values")
	replies.clear()
	terrain._receive({"kind":"density_batch","token":13,"epoch":terrain.epoch-1,"revision":terrain.density_revision,"status":"ok","values":PackedFloat32Array([-1.0])})
	check(replies.size()==1 and replies[0].status=="stale" and replies[0].values.is_empty(),"old world epoch cannot authorize placement")
	replies.clear();terrain.pending_edit=true
	terrain._receive({"kind":"density_batch","token":14,"epoch":terrain.epoch,"revision":terrain.density_revision,"status":"ok","values":PackedFloat32Array([-1.0])})
	check(replies.size()==1 and replies[0].status=="stale" and replies[0].values.is_empty(),"unpublished edit invalidates apparently current support result")
	terrain.pending_edit=false
	replies.clear()
	var scan:=PackedVector3Array();scan.resize(4096);scan.fill(points[0]);scan[4095]=points[1]
	check(not terrain.request_density_batch(scan,20),"ordinary batch retains 512 limit")
	check(terrain.request_density_scan(scan,21),"4096-point scan admitted")
	check(not terrain.request_density_batch(points,22),"scan shares one outstanding reservation with ordinary batches")
	deadline=Time.get_ticks_msec()+10000
	while replies.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(replies.size()==1 and replies[0].status=="ok" and replies[0].values.size()==4096 and replies[0].values[0]==reply.decode_float(20) and replies[0].values[4095]==reply.decode_float(24),"all eight pages preserve sample ordering and native values")
	if not replies.is_empty(): print("SCAN_WORKER_US ",replies[0].get("worker_us",-1))
	scan.append(points[0]);check(not terrain.request_density_scan(scan,23),"scan over 4096 rejected")
	scan.resize(4096);scan[4095]=Vector3(NAN,0,0);replies.clear()
	check(terrain.request_density_scan(scan,24),"late invalid-page fixture admitted to native validator")
	deadline=Time.get_ticks_msec()+10000
	while replies.is_empty() and Time.get_ticks_msec()<deadline: await process_frame
	check(replies.size()==1 and replies[0].status=="error" and replies[0].values.is_empty(),"last-page failure discards all earlier page values")
	terrain.shutdown();terrain.free();quit(1 if failures else 0)
