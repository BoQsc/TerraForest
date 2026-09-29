extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var fingerprints: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	return h.finish().hex_encode()
func core() -> RefCounted:
	return ClassDB.instantiate("TerrainCore")
func wait_build(instance: RefCounted, worker: Thread) -> bool:
	var end: int = Time.get_ticks_msec()+5000
	while worker.is_alive() and instance.executing_command()!=1 and Time.get_ticks_msec()<end:
		OS.delay_usec(100)
	return instance.executing_command()==1

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var a: RefCounted = core()
	var b: RefCounted = core()
	check(Codec.reply_ok(a.execute(Codec.command(0))),"native terrain initializes")
	var original: PackedByteArray = a.execute(Codec.command(4)).slice(12)
	fingerprints["initial_snapshot"] = digest(original)
	var locations := [Vector3(320,35,1312),Vector3(985,61,985),Vector3(1050,76,1115),Vector3(0,1,0),Vector3(2000,255,2000)]
	var samples := PackedByteArray()
	for p: Vector3 in locations:
		samples.append_array(a.execute(Codec.point_command(p)))
	fingerprints["field_samples"] = digest(samples)
	var edit: PackedByteArray = Codec.brush(Vector3(330,140,1320),Vector3(330,140,1320),8,0,true,1)
	check(Codec.reply_ok(a.execute(edit)),"native sphere edit accepted")
	check(b.execute(Codec.command(4)).slice(12)==original,"editing one world leaves second world unchanged")
	var snapshot: PackedByteArray = a.execute(Codec.command(4)).slice(12)
	fingerprints["edited_snapshot"] = digest(snapshot)
	var load_packet: PackedByteArray = Codec.command(5)
	load_packet.append_array(snapshot)
	check(Codec.reply_ok(b.execute(load_packet)) and b.execute(Codec.command(4)).slice(12)==snapshot,"snapshot loads into independent world with identical bytes")
	for key: Vector3i in [Vector3i(320,1312,32),Vector3i(960,960,32),Vector3i(1024,1088,64)]:
		var mesh: PackedByteArray = a.execute(Codec.command(1,[key.x,key.y,key.z,1]))
		check(Codec.reply_ok(mesh),"native mesh generated at %s" % str(key))
		fingerprints[str(key)] = digest(mesh)
	if not "--parity-only" in OS.get_cmdline_user_args():
		var support: RefCounted = core()
		var support_packet: PackedByteArray = Codec.command(17, [1])
		support_packet.append_array(PackedVector3Array([Vector3(320.4, 0, 1312.3)]).to_byte_array())
		var supported: PackedByteArray = support.execute(support_packet)
		check(Codec.reply_ok(supported) and supported.size() == 40 and supported.decode_float(32) > 0.8, "native fractional root support returns a valid surface normal")
		var support_point := Vector3(supported.decode_float(16), supported.decode_float(20), supported.decode_float(24))
		support.execute(Codec.brush(support_point - Vector3(0,20,0), support_point - Vector3(0,20,0), 3, 0, false, 1))
		check(support.execute(support_packet) == supported, "underground excavation preserves native surface support exactly")
		support.execute(Codec.brush(support_point, support_point, 1.5, 0, false, 1))
		var unsupported: PackedByteArray = support.execute(support_packet)
		check(Codec.reply_ok(unsupported) and unsupported.decode_float(32) == 0.0, "small excavation rejects unsupported root at fractional coordinates")
		check(not Codec.reply_ok(support.execute(support_packet.slice(0,19))), "truncated support batch rejected")
		check(not Codec.reply_ok(support.execute(Codec.command(17,[65]))) and not Codec.reply_ok(support.execute(Codec.command(17,[0]))), "support batch admission bounded to 1 through 64 points")
		var invalid_support := support_packet.duplicate()
		invalid_support.encode_float(8, NAN)
		check(not Codec.reply_ok(support.execute(invalid_support)), "nonfinite support coordinate rejected before sampling")
		check(a.has_method("supports_isolated_worlds") and a.supports_isolated_worlds(),"typed binding advertises independent native worlds")
		check(not Codec.reply_ok(a.execute(PackedByteArray([1,2,3]))),"truncated request rejected")
		check(not Codec.reply_ok(a.execute(Codec.command(12,[1]))),"malformed cancellation cannot change epoch")
		var epoch_a: int = a.execute(Codec.command(13)).decode_u32(12)
		var epoch_b: int = b.execute(Codec.command(13)).decode_u32(12)
		check(a.execute(Codec.command(12)).decode_u32(12)==epoch_a+1 and b.execute(Codec.command(13)).decode_u32(12)==epoch_b,"cancellation belongs only to its owner")
		check(Codec.reply_ok(a.execute(load_packet)) and a.execute(Codec.command(13)).decode_u32(12)==epoch_a+1,"snapshot load preserves owner cancellation counter")
		check(Codec.reply_ok(a.execute(Codec.command(6,[1703]))) and a.execute(Codec.command(13)).decode_u32(12)==epoch_a+1,"world reset preserves owner cancellation counter")
		# Deliberately cold detailed terrain jobs are long enough to observe entry.
		var c: RefCounted = core()
		var d: RefCounted = core()
		var mesh_packet: PackedByteArray = Codec.command(1,[960,960,128,1,0])
		var first := Thread.new()
		var second := Thread.new()
		check(first.start(func(): return c.execute(mesh_packet))==OK,"first native worker starts")
		var started: bool = wait_build(c,first)
		check(started,"first worker observed inside native mesh operation")
		check(second.start(func(): return d.execute(mesh_packet))==OK,"second native worker starts")
		check(wait_build(d,second),"second worker observed inside native mesh operation")
		var begin: int = Time.get_ticks_usec()
		c.execute(Codec.command(12))
		var stopped: PackedByteArray = first.wait_to_finish()
		var cancel_ms: float = (Time.get_ticks_usec()-begin)/1000.0
		var continued: PackedByteArray = second.wait_to_finish()
		check(stopped.size()>=12 and stopped.decode_u32(8)==4,"owner cancellation aborts active native mesh")
		check(Codec.reply_ok(continued) and d.execute(Codec.command(13)).decode_u32(12)==0,"other active world completes despite neighboring cancellation")
		check(cancel_ms<1000,"cancellation remains nonblocking and joins within one second")
		fingerprints["cancellation_join_ms"] = cancel_ms
		var e: RefCounted = core()
		check(continued==e.execute(mesh_packet),"concurrent mesh equals a fresh sequential world byte for byte")
		check(c.executing_command()==-1 and d.executing_command()==-1,"native execution diagnostics return idle after completion")
		var mutable: RefCounted = core()
		var left := Thread.new()
		var right := Thread.new()
		left.start(func():
			for x in range(400,500):
				if not Codec.reply_ok(mutable.execute(Codec.command(3,[x,180,160,1]))): return false
			return true)
		right.start(func():
			for x in range(500,600):
				if not Codec.reply_ok(mutable.execute(Codec.command(3,[x,180,160,2]))): return false
			return true)
		var left_ok: bool = left.wait_to_finish()
		var right_ok: bool = right.wait_to_finish()
		var stats: PackedByteArray = mutable.execute(Codec.command(0))
		check(left_ok and right_ok and stats.decode_u32(12)==200 and stats.decode_u32(24)==200,"concurrent callers serialize all 200 same-world block edits without losing revisions")
		var serial: RefCounted = core()
		for x in range(400,600): serial.execute(Codec.command(3,[x,180,160,1 if x<500 else 2]))
		var mesh_blocks: PackedByteArray = Codec.command(1,[384,128,256,8])
		check(mutable.execute(mesh_blocks)==serial.execute(mesh_blocks),"serialized concurrent block edits produce the sequential collision and render mesh")
		var resetting: RefCounted = core()
		var reset_thread := Thread.new()
		reset_thread.start(func():
			for i in range(1000):
				if not Codec.reply_ok(resetting.execute(Codec.command(6,[1703]))): return false
			return true)
		for i in range(1000): resetting.execute(Codec.command(12))
		var resets_ok: bool = reset_thread.wait_to_finish()
		check(resets_ok and resetting.execute(Codec.command(13)).decode_u32(12)==1000,"1000 resets cannot lose any of 1000 concurrent owner cancellation increments")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_native.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"fingerprints":fingerprints},"  "))
	file.close()
	quit(0 if failures==0 else 1)
