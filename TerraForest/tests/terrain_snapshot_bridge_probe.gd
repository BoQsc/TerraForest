extends SceneTree
var checks: Array[Dictionary]=[]
var query_ms: Array[float]=[]
var poll_ms: Array[float]=[]
func _initialize() -> void: run.call_deferred()
func check(ok: bool,label: String) -> void:
	checks.append({"passed":ok,"name":label});print("PASS " if ok else "FAIL ",label)
func command(id: int,values: Array=[]) -> PackedByteArray:
	var packet:=PackedByteArray();packet.resize(4+4*values.size());packet.encode_u32(0,id)
	for i in range(values.size()): packet.encode_u32(4+4*i,values[i])
	return packet
func gather(native) -> Array:
	var rows: Array=[];var deadline:=Time.get_ticks_msec()+5000
	while rows.size()<2 and Time.get_ticks_msec()<deadline:
		var epoch: int=native.execute(command(13)).decode_u32(12)
		var ray:=PackedByteArray();ray.resize(36);ray.encode_u32(0,23)
		for i in range(6): ray.encode_float(4+i*4,[100.0,1.02,100.0,100.0,0.98,100.0][i])
		ray.encode_u32(28,256);ray.encode_u32(32,epoch)
		var begin:=Time.get_ticks_usec();var hit: PackedByteArray=native.execute(ray)
		query_ms.append((Time.get_ticks_usec()-begin)/1000.0)
		if hit.size()!=40 or hit.decode_u32(8)!=0 or hit.decode_u32(16)!=0: check(false,"density query during snapshot processing")
		begin=Time.get_ticks_usec();rows.append_array(native.experimental_snapshot_poll());poll_ms.append((Time.get_ticks_usec()-begin)/1000.0)
		await process_frame
	return rows
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	if not ClassDB.class_exists("TerrainCore"):
		check(false,"native extension loads");quit(1);return
	var native=ClassDB.instantiate("TerrainCore")
	check(native.has_method("experimental_snapshot_submit"),"opt-in snapshot API available")
	check(not native.experimental_snapshot_submit(-1,960,32,0,0) and not native.experimental_snapshot_submit(960,960,32,0,1),"invalid coordinate and wrong revision rejected")
	check(native.experimental_snapshot_submit(960,960,32,10,0) and native.experimental_snapshot_submit(960,960,32,11,0) and not native.experimental_snapshot_submit(960,960,32,12,0),"two outstanding bridge jobs bound admission")
	var rows: Array=await gather(native)
	var valid: bool=rows.size()==2
	for row: Dictionary in rows:
		valid=valid and row.status==0 and not row.stale and row.positions.size()>0 and row.positions.size()%12==0 and row.indices.size()%12==0
		valid=valid and row.normals.size()==row.positions.size()
		for at in range(0,row.normals.size(),12):
			var normal:=Vector3(row.normals.decode_float(at),row.normals.decode_float(at+4),row.normals.decode_float(at+8))
			valid=valid and normal.is_finite() and absf(normal.length()-1.0)<0.0001
		for at in range(0,row.indices.size(),4): valid=valid and row.indices.decode_u32(at)<row.positions.size()/12
	check(valid,"bridge transfers indexed geometry with valid ranges")
	check(rows.size()==2 and rows[0].positions==rows[1].positions and rows[0].indices==rows[1].indices and rows[0].normals==rows[1].normals,"identical captures transfer identical bytes")
	check(not native.experimental_snapshot_submit_brick(960,960,32,20,0,-1,32) and not native.experimental_snapshot_submit_brick(960,960,32,20,0,32,32) and not native.experimental_snapshot_submit_brick(960,960,32,20,0,32,257),"invalid vertical bounds rejected")
	check(native.experimental_snapshot_submit_brick(960,960,32,20,0,0,128) and native.experimental_snapshot_submit_brick(960,960,32,21,0,128,256),"bounded vertical jobs admitted")
	rows=await gather(native);valid=rows.size()==2
	for row: Dictionary in rows:
		var bottom: int=0 if row.token==20 else 128
		valid=valid and row.status==0 and not row.stale and row.y_begin==bottom and row.y_end==bottom+128
		for at in range(0,row.positions.size(),12):
			var y: float=row.positions.decode_float(at+4)
			valid=valid and y>=bottom and y<=bottom+128
		check(native.experimental_snapshot_encode(row,960,960,32).is_empty(),"partial column rejected by full-column publication codec")
	check(valid,"bounded geometry transfers with matching vertical metadata")
	for action in [6,5,12,3,2]:
		var revision: int=native.execute(command(0)).decode_u32(12)
		check(native.experimental_snapshot_submit(960,960,32,action*10,revision) and native.experimental_snapshot_submit(960,960,32,action*10+1,revision),"stale-control submissions admitted")
		if action==6: native.execute(command(6,[1703]))
		elif action==5:
			var saved: PackedByteArray=native.execute(command(4))
			var load_packet:=command(5);load_packet.append_array(saved.slice(12));native.execute(load_packet)
		elif action==12: native.execute(command(12))
		elif action==2: native.execute(command(2)) # Failed edit: conservative invalidation.
		else: native.execute(command(3,[100,30,100,1]))
		rows=await gather(native);valid=rows.size()==2
		for row: Dictionary in rows: valid=valid and row.stale and row.status==2 and row.positions.is_empty() and row.indices.is_empty() and row.normals.is_empty()
		check(valid,"reset/cancel/edit rejects old snapshot %d" % action)
	var revision: int=native.execute(command(0)).decode_u32(12)
	check(native.experimental_snapshot_submit(960,960,32,90,revision) and native.experimental_snapshot_submit(960,960,32,91,revision),"shutdown jobs admitted")
	native.experimental_snapshot_stop();rows=native.experimental_snapshot_poll()
	check(rows.size()==2 and not native.experimental_snapshot_submit(960,960,32,92,revision),"stop joins and preserves accepted completions")
	native=null
	var failures:=0
	for row: Dictionary in checks:
		if not row.passed: failures+=1
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"query_ms":query_ms,"poll_ms":poll_ms},"  "));file.close()
	quit(0 if failures==0 else 1)
