extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var core: RefCounted
var failures := 0
var checks := 0
var samples: Array[Dictionary] = []

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func command(op: int, values: Array = []) -> PackedByteArray:
	return core.execute(Codec.command(op, values))

func stats() -> Array:
	var reply := command(21)
	var values: Array = []
	if Codec.reply_ok(reply) and reply.size() == 84:
		for i in range(9): values.append(reply.decode_u64(12 + i * 8))
	return values

func parity(x: int, z: int, size: int, step: int, label: String) -> void:
	var reference := command(1, [x,z,size,step])
	var cached := command(20, [x,z,size,step])
	check(Codec.reply_ok(reference) and Codec.reply_ok(cached) and reference.slice(12) == cached.slice(12), label)
	var s := stats()
	check(s.size() == 9 and s[4] <= 512 and s[5] <= s[6], label + " bounded cache")

func measure(op: int, state: String, iteration: int) -> PackedByteArray:
	var begin := Time.get_ticks_usec()
	var result := command(op, [1280,1280,256,8])
	var elapsed := (Time.get_ticks_usec() - begin) / 1000.0
	var profile := command(19)
	samples.append({"state":state,"op":op,"iteration":iteration,"total_ms":elapsed,
		"extraction_ms":profile.decode_float(12),"simplification_ms":profile.decode_float(16),
		"shading_ms":profile.decode_float(24),"cache":stats(),"packet_bytes":result.size()})
	return result

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	core = ClassDB.instantiate("TerrainCore")
	check(stats().size() == 9 and stats()[4] == 0, "initial cache empty")
	for request in [Codec.command(21,[0]), Codec.command(22), Codec.command(22,[65535]), Codec.command(22,[33554433]), Codec.command(22,[65536,0]), Codec.command(20,[0,0,17,1])]:
		check(not Codec.reply_ok(core.execute(request)), "malformed cache request rejected")
	var snapshot := command(4)
	for patch in [[0,0,16,1],[1984,1984,16,1],[2000,2000,16,1],[2032,2032,16,1],[1279,1291,32,2],[960,960,64,1],[1280,1280,128,4],[1280,1280,256,8]]:
		parity(patch[0],patch[1],patch[2],patch[3],"fresh %s" % [patch])
	check(command(4) == snapshot, "derived cache does not change authoritative snapshot")
	var before := stats()
	parity(1280,1280,256,8,"warm exact mesh including collision and shading")
	var after := stats()
	check(after[1] == before[1] and after[0] > before[0], "warm patch uses hits only")
	var point := Vector3(1312,0,1312)
	point.y = core.execute(Codec.point_command(point)).decode_float(12)
	before = stats()
	var edit: PackedByteArray = core.execute(Codec.brush(point,point,2.5,0,false,1))
	check(Codec.reply_ok(edit) and edit.decode_u32(16) > 0, "corner excavation changes terrain")
	after = stats()
	check(after[3] - before[3] == 4, "corner edit invalidates four owned regions")
	before = after
	parity(1280,1280,256,8,"local edit exact mesh")
	after = stats()
	check(after[1] - before[1] == 4 and after[0] - before[0] == 285, "local rebuild reuses 285 of 289 regions")
	before = stats()
	point = Vector3(600,0,600)
	point.y = core.execute(Codec.point_command(point)).decode_float(12)
	core.execute(Codec.brush(point,point,3,0,true,2))
	check(stats()[3] == before[3], "distant edit retains unrelated reconstruction")
	parity(1280,1280,256,8,"distant edit shading remains exact")
	for step in [1,2,4,8]: parity(1297,1303,32,step,"unaligned edited patch LOD %d" % step)
	command(3,[1312,200,1312,2])
	parity(1280,1280,64,2,"legacy block appended to cached density")
	command(14,[1])
	check(stats()[4] == 0,"surface style clears cache")
	parity(1280,1280,64,1,"smooth style parity")
	var load_packet := Codec.command(5)
	load_packet.append_array(snapshot.slice(12))
	check(Codec.reply_ok(core.execute(load_packet)) and stats()[4] == 0,"snapshot load clears derived cache")
	command(14,[0])
	for i in range(9): parity(256+i*144,512,128,4,"slot pressure patch %d" % i)
	check(stats()[2] > 0,"working set exceeds 512 slots and evicts")
	parity(256,512,128,4,"revisit evicted patch")
	check(Codec.reply_ok(command(22,[65536])) and stats()[5] <= 65536,"lower budget immediately evicts")
	parity(960,960,64,1,"64 KiB pressure and oversized region fallback")
	var small_budget := stats()
	check(small_budget[2] > 0 and small_budget[8] > 0,"byte pressure evicts and oversized regions bypass")
	var old_epoch := command(13).decode_u32(12)
	command(12)
	var cancelled := command(20,[960,960,64,1,old_epoch])
	check(cancelled.size() == 12 and cancelled.decode_u32(8) == 4,"stale epoch rejects without partial mesh")
	parity(960,960,64,1,"valid request after cancellation")
	command(6,[1703])
	var worker := Thread.new()
	check(worker.start(func(): return command(20,[960,960,256,1])) == OK,"cached worker starts")
	var deadline := Time.get_ticks_msec() + 5000
	while worker.is_alive() and core.executing_command()!=20 and Time.get_ticks_msec()<deadline:
		OS.delay_usec(100)
	check(core.executing_command()==20,"cached worker observed inside native build")
	# Allow several regions to complete so cancellation also exercises a partial cache.
	OS.delay_msec(10)
	var cancel_begin := Time.get_ticks_usec()
	command(12)
	var stopped: PackedByteArray = worker.wait_to_finish()
	var cancel_join_ms := (Time.get_ticks_usec()-cancel_begin)/1000.0
	check(stopped.size()==12 and stopped.decode_u32(8)==4,"active cached build cancels without publishing partial mesh")
	check(cancel_join_ms<1000,"cached cancellation joins within one second")
	parity(960,960,256,1,"partial cache after active cancellation remains exact")
	command(6,[1703])
	# Adversarial additions/subtractions cross ownership boundaries at several depths.
	var changed := 0
	for i in range(96):
		point = Vector3(1280 + (i*17)%64,0,1280 + (i*29)%64)
		point.y = core.execute(Codec.point_command(point)).decode_float(12) - (i%5)*4
		var result: PackedByteArray = core.execute(Codec.brush(point,point,2.5 + i%4,i%2,i%3==0,1+i%3))
		if Codec.reply_ok(result) and result.decode_u32(16)>0: changed += 1
		parity(1280,1280,64,[1,2,4,8][i%4],"mixed boundary/depth edit %d" % i)
	check(changed >= 80,"mixed edit sequence performs real mutations")
	command(6,[1703])
	check(stats()[4] == 0 and stats()[7] == 0,"reset frees all cache allocations")
	command(18,[1])
	# Pair outputs and alternate order. Timings exclude comparison/report serialization.
	for iteration in range(7):
		if iteration == 4:
			point = Vector3(1312,0,1312)
			point.y = core.execute(Codec.point_command(point)).decode_float(12)
			core.execute(Codec.brush(point,point,2.5,0,false,1))
		var state := "cold" if iteration == 0 else ("local_edit" if iteration == 4 else "warm")
		var first := measure(1 if iteration % 2 == 0 else 20,state,iteration)
		var second := measure(20 if iteration % 2 == 0 else 1,state,iteration)
		check(Codec.reply_ok(first) and Codec.reply_ok(second) and first.slice(12) == second.slice(12),"matched benchmark parity %d" % iteration)
	# Retained integrated workload, including travel edits away from the measured patch.
	var compressed := FileAccess.get_file_as_bytes("res://docs/evidence/foundation_mining/scale_16/foundation_mining.json.gz")
	var fixture: Dictionary = JSON.parse_string(compressed.decompress_dynamic(64*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	command(6,[1703])
	command(18,[1])
	var replayed := 0
	var replay_changed := 0
	var replay_ok := true
	for phase in fixture.phases:
		for row in phase.edits:
			var d: Dictionary = row.descriptor
			var a := Vector3(d.a[0],d.a[1],d.a[2])
			var b := Vector3(d.b[0],d.b[1],d.b[2])
			var reply: PackedByteArray = core.execute(Codec.brush(a,b,d.radius,0,d.add,1))
			replay_ok = Codec.reply_ok(reply) and replay_ok
			if Codec.reply_ok(reply) and reply.decode_u32(16)>0: replay_changed += 1
			replayed += 1
	check(replay_ok and replayed == 2176,"replay all 2176 retained edit commands")
	check(replay_changed >= replayed*0.9,"at least 90 percent of replay commands change terrain")
	for iteration in range(4):
		var first := measure(1 if iteration%2==0 else 20,"retained_edits",iteration)
		var second := measure(20 if iteration%2==0 else 1,"retained_edits",iteration)
		check(Codec.reply_ok(first) and Codec.reply_ok(second) and first.slice(12)==second.slice(12),"retained edit benchmark parity %d" % iteration)
	# Under a cache smaller than the working set, repeated queries must stay correct;
	# record the thrashing cost rather than reporting warm-cache speed as universal.
	command(22,[65536])
	for iteration in range(3):
		var first := measure(1 if iteration%2==0 else 20,"thrashing_64KiB",iteration)
		var second := measure(20 if iteration%2==0 else 1,"thrashing_64KiB",iteration)
		check(Codec.reply_ok(first) and Codec.reply_ok(second) and first.slice(12)==second.slice(12),"thrashing benchmark parity %d" % iteration)
	var report := {"checks":checks,"failures":failures,"samples":samples,"small_budget_stats":small_budget,"mixed_changed":changed,"replayed":replayed,"replay_changed":replay_changed,"seed":1703,"cancel_join_ms":cancel_join_ms,
		"scope":"Native reconstruction cache only. Exact mesh, collision and shading bytes relative to uncached current mesher; no GPU/FPS, multiplayer or endurance claim. Cache payload excludes transient and final mesh allocations."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_region_cache.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("REGION_CACHE ",JSON.stringify(report))
	core = null
	quit(0 if failures == 0 else 1)
