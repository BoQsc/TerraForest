extends SceneTree
var checks: Array[Dictionary]=[]
var creation_ms: Array[float]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("TerrainCore"): quit(1);return
	for size in [16,32]:
		var native=ClassDB.instantiate("TerrainCore")
		check(native.experimental_snapshot_submit(960,960,size,1,0),"surface request admitted")
		var rows: Array=[];var deadline:=Time.get_ticks_msec()+5000
		while rows.is_empty() and Time.get_ticks_msec()<deadline:
			rows=native.experimental_snapshot_poll();await process_frame
		check(rows.size()==1,"surface packet received")
		if rows.is_empty(): native.experimental_snapshot_stop();continue
		var packet: Dictionary=rows[0]
		var encoded: PackedByteArray=native.experimental_snapshot_encode(packet,960,960,size)
		check(encoded.size()>=36 and encoded.decode_u32(0)==0x324d5254 and encoded.decode_u32(32)==packet.indices.size()/4,"stream packet includes exact collision triangle count")
		var begin:=Time.get_ticks_usec();var mesh: ArrayMesh=native.experimental_snapshot_create_mesh(packet);creation_ms.append((Time.get_ticks_usec()-begin)/1000.0)
		check(mesh!=null and mesh.get_surface_count()==1,"native adapter creates one render surface")
		if mesh!=null:
			var arrays: Array=mesh.surface_get_arrays(0)
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var valid: bool=positions.size()*12==packet.positions.size() and normals.size()==positions.size() and indices.size()*4==packet.indices.size()
			for i in range(positions.size()):
				var p:=Vector3(packet.positions.decode_float(i*12),packet.positions.decode_float(i*12+4),packet.positions.decode_float(i*12+8))
				var n:=Vector3(packet.normals.decode_float(i*12),packet.normals.decode_float(i*12+4),packet.normals.decode_float(i*12+8))
				valid=valid and positions[i].distance_to(p)<0.001 and normals[i].dot(n)>0.999
			for i in range(indices.size()): valid=valid and indices[i]==packet.indices.decode_u32(i*4)
			check(valid,"engine mesh preserves positions normals and indices")
		for fault in ["missing_normals","bad_index","nan_position","zero_normal","foreign_owner","stale_revision","stale_epoch"]:
			var bad: Dictionary=packet.duplicate(true)
			if fault=="missing_normals": bad.erase("normals")
			elif fault=="bad_index": bad.indices.encode_u32(0,0xffffffff)
			elif fault=="nan_position": bad.positions.encode_float(0,NAN)
			elif fault=="zero_normal":
				for offset in [0,4,8]: bad.normals.encode_float(offset,0.0)
			elif fault=="foreign_owner": bad.source_id+=1
			elif fault=="stale_revision": bad.validated_revision+=1
			elif fault=="stale_epoch": bad.epoch+=1
			check(native.experimental_snapshot_create_mesh(bad)==null,"reject "+fault)
			check(native.experimental_snapshot_encode(bad,960,960,size).is_empty(),"stream conversion rejects "+fault)
		var reset:=PackedByteArray();reset.resize(8);reset.encode_u32(0,6);reset.encode_u32(4,1703);native.execute(reset)
		check(native.experimental_snapshot_create_mesh(packet)==null,"actual reset rejects retained old packet")
		check(native.experimental_snapshot_encode(packet,960,960,size).is_empty(),"stream conversion rejects actual reset")
		native.experimental_snapshot_stop();native=null;mesh=null
	var failures:=0
	for row: Dictionary in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"creation_ms":creation_ms},"  "));file.close()
	quit(0 if failures==0 else 1)
