extends SceneTree
var rows: Array[Dictionary]=[]
var failures:=0
func _initialize() -> void: run.call_deferred()
func command(values: Array) -> PackedByteArray:
	var packet:=PackedByteArray();packet.resize(values.size()*4)
	for i in range(values.size()): packet.encode_u32(i*4,values[i])
	return packet
func edges(packet: PackedByteArray,axis: int,plane: float) -> Array:
	var nv:=int(packet.decode_u32(24));var positions:=packet.slice(36,36+nv*12).to_vector3_array();var start:=36+nv*56
	var found: Dictionary={}
	for i in range(0,packet.decode_u32(28),3):
		var triangle: Array[Vector3]=[]
		for j in range(3): triangle.append(positions[packet.decode_u32(start+(i+j)*4)])
		for j in range(3):
			var a:=triangle[j];var b:=triangle[(j+1)%3]
			if a[axis]!=plane or b[axis]!=plane or a==b: continue
			var keys: Array[String]=[PackedVector3Array([a]).to_byte_array().hex_encode(),PackedVector3Array([b]).to_byte_array().hex_encode()];keys.sort()
			var key:=keys[0]+keys[1]
			if found.has(key): found.erase(key)
			else: found[key]=[a,b]
	return found.values()
func discrepancy(source: Array,target: Array) -> Dictionary:
	var maximum:=0.0;var witness:=Vector3.ZERO
	for edge: Array in source:
		for point: Vector3 in [edge[0],edge[1],(edge[0]+edge[1])*0.5]:
			var nearest:=INF
			for other: Array in target:
				var delta: Vector3=other[1]-other[0]
				var t:=clampf((point-other[0]).dot(delta)/delta.length_squared(),0,1)
				nearest=minf(nearest,point.distance_to(other[0]+delta*t))
			if nearest>maximum: maximum=nearest;witness=point
	return {"distance":maximum,"witness":[witness.x,witness.y,witness.z]}
func signature(segments: Array) -> Array[String]:
	var result: Array[String]=[]
	for edge: Array in segments:
		var pair: Array[String]=[PackedVector3Array([edge[0]]).to_byte_array().hex_encode(),PackedVector3Array([edge[1]]).to_byte_array().hex_encode()];pair.sort();result.append(pair[0]+pair[1])
	result.sort();return result
func snapshot(core: Object,x: int,z: int,revision: int) -> PackedByteArray:
	if not core.experimental_snapshot_submit(x,z,32,1,revision): return PackedByteArray()
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		var packets: Array=core.experimental_snapshot_poll()
		if not packets.is_empty(): return core.experimental_snapshot_encode(packets[0],x,z,32)
		await process_frame
	return PackedByteArray()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
	for site: Vector2i in [Vector2i(1376,1376),Vector2i(960,960)]:
		var core=ClassDB.instantiate("TerrainCore")
		var ox:=site.x/256*256;var oz:=site.y/256*256
		var reply: PackedByteArray=core.execute(command([1,ox,oz,256,8]))
		var retained:=reply.slice(16)
		for size: int in [128,64,32]:
			var children: Array=core.experimental_partition_mesh(retained)
			var selected:=PackedByteArray()
			for child: PackedByteArray in children:
				if child.decode_u32(8)<=site.x and site.x<child.decode_u32(8)+size and child.decode_u32(12)<=site.y and site.y<child.decode_u32(12)+size: selected=child
			if selected.is_empty(): quit(2);return
			retained=selected
		var before: PackedByteArray=await snapshot(core,site.x,site.y,0)
		if before.is_empty(): quit(2);return
		var point:=Vector3(site.x+16,0,site.y+16)
		var codec=load("res://addons/volumetric_terrain/mesh_codec.gd")
		var height_reply: PackedByteArray=core.execute(codec.point_command(point))
		point.y=height_reply.decode_float(12)
		core.execute(codec.brush(point,point,2.5,0,false,1))
		var stats: PackedByteArray=core.execute(command([0]));var revision:=stats.decode_u32(12)
		var after: PackedByteArray=await snapshot(core,site.x,site.y,revision)
		if after.is_empty(): quit(2);return
		for side in range(4):
			var axis:=0 if side<2 else 2
			var plane:=float((site.x if axis==0 else site.y)+(32 if side%2 else 0))
			var old_edges:=edges(retained,axis,plane);var new_edges:=edges(before,axis,plane);var edited_edges:=edges(after,axis,plane)
			var outward:=discrepancy(old_edges,new_edges);var inward:=discrepancy(new_edges,old_edges)
			var edit_change:=maxf(discrepancy(new_edges,edited_edges).distance,discrepancy(edited_edges,new_edges).distance)
			var gap:=maxf(outward.distance,inward.distance)
			# Report the world-bottom component separately; do not hide it from admission.
			var old_above:=old_edges.filter(func(e: Array): return e[0].y>2 and e[1].y>2)
			var new_above:=new_edges.filter(func(e: Array): return e[0].y>2 and e[1].y>2)
			var above_gap:=maxf(discrepancy(old_above,new_above).distance,discrepancy(new_above,old_above).distance)
			var neighbor:=site
			if axis==0: neighbor.x+=32 if side%2 else -32
			else: neighbor.y+=32 if side%2 else -32
			var adjacent: PackedByteArray=await snapshot(core,neighbor.x,neighbor.y,revision)
			if adjacent.is_empty(): quit(2);return
			var matched: bool=signature(edited_edges)==signature(edges(adjacent,axis,plane))
			var passes: bool=gap<=0.001 and edit_change<=0.001 and matched
			if not passes: failures+=1
			rows.append({"site":[site.x,site.y],"side":side,"retained_edges":old_edges.size(),"candidate_edges":new_edges.size(),"gap_lower_bound_m":gap,"above_bottom_gap_lower_bound_m":above_gap,"candidate_neighbor_edges_match_exactly":matched,"before_after_boundary_difference_m":edit_change,"outward":outward,"inward":inward,"passes":passes,"edit_revision":revision})
			print("PASS " if passes else "FAIL ","retained-to-candidate boundary ",site," side ",side," above-bottom gap ",above_gap," candidate neighbor exact ",matched)
		core.experimental_snapshot_stop();core=null
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/command.json",FileAccess.WRITE);file.store_string(JSON.stringify({"failures":failures,"rows":rows,"scope":"Geometric mismatch witnesses at endpoints/midpoints, a lower bound on separation. Does not prove seamlessness when zero; no GPU, collider, winding or topology qualification."},"  "));file.close()
	quit(0 if failures==0 else 1)
