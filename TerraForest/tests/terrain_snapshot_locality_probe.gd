extends SceneTree
var checks: Array[Dictionary]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func pair(native,revision: int) -> void:
	check(native.experimental_snapshot_submit(960,960,32,1,revision) and native.experimental_snapshot_submit(960,960,32,2,revision),"two local jobs admitted")
func gather(native) -> Array:
	var rows: Array=[];var deadline:=Time.get_ticks_msec()+5000
	while rows.size()<2 and Time.get_ticks_msec()<deadline:
		rows.append_array(native.experimental_snapshot_poll());await process_frame
	return rows
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("TerrainCore"): quit(1);return
	for site in [Vector3(100,20,100),Vector3(960,20,976),Vector3(960,20,960),Vector3(976,20,976)]:
		var remote: bool=site.x==100
		var native=ClassDB.instantiate("TerrainCore")
		pair(native,0);var original: Array=await gather(native)
		pair(native,0)
		var edit:=PackedByteArray();edit.resize(44);edit.encode_u32(0,2)
		for offset in [4,16]:
			for axis in range(3): edit.encode_float(offset+4*axis,site[axis])
		edit.encode_float(28,3.0);edit.encode_u32(40,1)
		var reply: PackedByteArray=native.execute(edit)
		check(reply.decode_u32(8)==0 and reply.decode_u32(16)>0,"edit changes density")
		var revision: int=reply.decode_u32(12)
		# A subsequent remote edit must advance a valid chain without resurrecting
		# a completion invalidated by the first, intersecting edit.
		for offset in [4,16]: edit.encode_float(offset,200.0);edit.encode_float(offset+8,200.0)
		reply=native.execute(edit);revision=reply.decode_u32(12)
		check(reply.decode_u32(8)==0 and reply.decode_u32(16)>0,"second remote edit advances revision chain")
		var old: Array=await gather(native)
		var valid: bool=old.size()==2
		for row: Dictionary in old:
			valid=valid and ((row.status==0 and not row.stale) if remote else (row.status==2 and row.stale and row.positions.is_empty()))
			valid=valid and row.validated_revision==(revision if remote else -1) and row.revision==0
		check(valid,"unrelated edit preserves useful work" if remote else "intersecting edit rejects old work")
		pair(native,revision);var fresh: Array=await gather(native)
		check(original.size()==2 and fresh.size()==2 and fresh[0].status==0,"reference builds complete")
		if original.size()==2 and fresh.size()==2:
			var equal: bool=original[0].positions==fresh[0].positions and original[0].indices==fresh[0].indices
			check(equal==remote,"fresh geometry independently confirms edit locality")
			if remote and old.size()==2: check(old[0].positions==fresh[0].positions and old[0].indices==fresh[0].indices,"preserved completion matches fresh post-edit build")
		native.experimental_snapshot_stop();native=null
	var failures:=0
	for row: Dictionary in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "));file.close()
	quit(0 if failures==0 else 1)
