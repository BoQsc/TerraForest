extends SceneTree
const Codec = preload("res://addons/volumetric_terrain/mesh_codec.gd")
var samples: Array[Dictionary]=[]
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, text: String) -> void:
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",text)

func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var instance: RefCounted=ClassDB.instantiate("TerrainCore")
	check(not Codec.reply_ok(instance.execute(Codec.command(18,[2]))) and not Codec.reply_ok(instance.execute(Codec.command(18))),"invalid profiling configuration rejected")
	check(not Codec.reply_ok(instance.execute(Codec.command(19,[0]))),"malformed profile read rejected")
	var compressed := FileAccess.get_file_as_bytes("res://docs/evidence/foundation_mining/scale_16/foundation_mining.json.gz")
	var fixture: Dictionary=JSON.parse_string(compressed.decompress_dynamic(64*1024*1024,FileAccess.COMPRESSION_GZIP).get_string_from_utf8())
	for state in ["fresh","after_2176_commands"]:
		if state!="fresh":
			var replay_ok := true
			var commands := 0
			for phase in fixture.phases:
				for row in phase.edits:
					var d: Dictionary=row.descriptor
					var a:=Vector3(d.a[0],d.a[1],d.a[2])
					var b:=Vector3(d.b[0],d.b[1],d.b[2])
					replay_ok=Codec.reply_ok(instance.execute(Codec.brush(a,b,d.radius,0,d.add,1))) and replay_ok
					commands+=1
			check(replay_ok and commands==2176,"replay all 2176 retained edit commands")
		for size in [16,32,64,128,256]:
			var packet := Codec.command(1,[1280,1280,size,maxi(1,size/32)])
			# Profiling is opt-in and must not change geometry or material bytes.
			instance.execute(Codec.command(18,[0]))
			var reference: PackedByteArray=instance.execute(packet)
			instance.execute(Codec.command(18,[1]))
			for repeat in range(3):
				var begin := Time.get_ticks_usec()
				var result: PackedByteArray=instance.execute(packet)
				var elapsed := (Time.get_ticks_usec()-begin)/1000.0
				var profile: PackedByteArray=instance.execute(Codec.command(19))
				check(result==reference and Codec.reply_ok(result),"profile preserves mesh bytes %s/%d/%d" % [state,size,repeat])
				check(Codec.reply_ok(profile) and profile.size()==28,"valid stage profile")
				samples.append({"state":state,"size":size,"repeat":repeat,"total_ms":elapsed,"extraction_ms":profile.decode_float(12),"simplification_ms":profile.decode_float(16),"blocks_ms":profile.decode_float(20),"shading_ms":profile.decode_float(24),"packet_bytes":result.size()})
	var report := {"failures":failures,"samples":samples,"scope":"Isolated native rebuilds of the same mountain patch, before/after replaying the retained integrated workload. Warm lighting caches; no GPU, scene publication, collision or FPS claims."}
	var file := FileAccess.open("res://reports/terrain_mesh_pressure.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("MESH_PRESSURE ",JSON.stringify(report))
	quit(0 if failures==0 else 1)
