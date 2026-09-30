extends SceneTree
var checks: Array[Dictionary] = []
func _initialize() -> void: run.call_deferred()
func command(number: int) -> PackedByteArray:
	var p := PackedByteArray();p.resize(4);p.encode_u32(0,number);return p
func query(from: Vector3,to: Vector3,budget: int,epoch: int) -> PackedByteArray:
	var p := PackedByteArray();p.resize(36);p.encode_u32(0,23)
	for i in range(3):
		p.encode_float(4+4*i,from[i]);p.encode_float(16+4*i,to[i])
	p.encode_u32(28,budget);p.encode_u32(32,epoch);return p
func add(ok: bool,name: String) -> void: checks.append({"passed":ok,"name":name})
func worker(core: RefCounted) -> void:
	add(OS.get_thread_caller_id()!=OS.get_main_thread_id(),"queries execute from a Godot worker thread")
	var epoch_packet: PackedByteArray=core.execute(command(13))
	var epoch := epoch_packet.decode_u32(12)
	var packet := query(Vector3(1288,1.02,1288),Vector3(1288,0.98,1288),4096,epoch)
	var hit: PackedByteArray=core.execute(packet)
	add(hit.size()==40 and hit.decode_u32(8)==0 and hit.decode_u32(16)==0 and abs(hit.decode_float(32)-1.0)<0.00001,"native hit packet contains bottom-plane surface")
	var miss: PackedByteArray=core.execute(query(Vector3(100,250,100),Vector3(100.1,250,100),4096,epoch))
	add(miss.size()==40 and miss.decode_u32(16)==1,"empty air reports miss")
	var limited: PackedByteArray=core.execute(query(Vector3(100,250,100),Vector3(110,250,100),1,epoch))
	add(limited.size()==40 and limited.decode_u32(16)==2 and limited.decode_u32(20)==1,"work exhaustion is distinct from miss")
	for budget in [0,8193]:
		var bad: PackedByteArray=core.execute(query(Vector3.ZERO,Vector3.ONE,budget,epoch))
		add(bad.size()==12 and bad.decode_u32(8)==1,"invalid budget rejected %d" % budget)
	for size in [35,37]:
		var bad_packet := packet.duplicate();bad_packet.resize(size)
		var bad: PackedByteArray=core.execute(bad_packet)
		add(bad.size()==12 and bad.decode_u32(8)==1,"invalid packet size rejected %d" % size)
	var edit := PackedByteArray();edit.resize(44);edit.encode_u32(0,2)
	for offset in [4,16]:
		edit.encode_float(offset,1288);edit.encode_float(offset+4,20);edit.encode_float(offset+8,1288)
	edit.encode_float(28,2);edit.encode_u32(40,1)
	var edited: PackedByteArray=core.execute(edit)
	add(edited.decode_u32(8)==0 and edited.decode_u32(16)>0,"world edit changes density")
	var after: PackedByteArray=core.execute(query(Vector3(1288,20,1288),Vector3(1288,24,1288),4096,epoch))
	add(after.size()==40 and after.decode_u32(12)==edited.decode_u32(12) and after.decode_u32(16)==0,"query sees edited world and returns its revision")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	var core: RefCounted=ClassDB.instantiate("TerrainCore")
	var other: RefCounted=ClassDB.instantiate("TerrainCore")
	var thread := Thread.new();var started := thread.start(worker.bind(core))
	if started!=OK: quit(1);return
	while thread.is_alive(): await process_frame
	thread.wait_to_finish()
	add(started==OK,"worker starts")
	var old: PackedByteArray=core.execute(command(13))
	core.execute(command(12))
	var cancelled: PackedByteArray=core.execute(query(Vector3.ZERO,Vector3.ONE,4096,old.decode_u32(12)))
	add(cancelled.size()==12 and cancelled.decode_u32(8)==4,"stale epoch returns cancellation without hit payload")
	var other_epoch: PackedByteArray=other.execute(command(13))
	var independent: PackedByteArray=other.execute(query(Vector3(100,250,100),Vector3(100.1,250,100),4096,other_epoch.decode_u32(12)))
	add(independent.size()==40 and independent.decode_u32(8)==0,"other world epoch remains independent")
	var failures := 0
	for check: Dictionary in checks:
		if not check.passed: failures+=1
		print("PASS " if check.passed else "FAIL ",check.name)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var f := FileAccess.open("res://reports/command.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));f.close()
	quit(0 if failures==0 else 1)
