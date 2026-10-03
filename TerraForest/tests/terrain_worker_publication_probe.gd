extends "res://tests/terrain_publication_probe.gd"

var worker_events: Array[Dictionary] = []
var preemption_observed := false

func pump_until(predicate: Callable, prepare: bool = true) -> bool:
	var deadline := Time.get_ticks_msec()+15000
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		for result: Dictionary in world.backend.poll():
			worker_events.append({"kind":result.kind,"ticket":result.get("ticket",-1),"remaining_before_receive":world.batch_remaining,"worker_ms":result.get("worker_ms",0.0),"region_parts":result.get("region_parts",0),"region_stages":result.get("region_stages",{})})
			world._receive(result)
		if prepare: world._drain_staging()
		if not world.paused_preparations.is_empty(): preemption_observed=true
		if not world.latest_error.is_empty(): return false
		await process_frame
	return predicate.call()

func run() -> void:
	world = FixedCut.new()
	root.add_child(world)
	world.set_process(false)
	world.material = StandardMaterial3D.new()
	world.backend.disk_cache.enabled = false
	check(world.backend.start(true)==OK,"real native terrain worker starts")
	check(await pump_until(func(): return world.world_ready),"real worker startup delivered")
	for z in [1280,1296]:
		for x in [1280,1296]: world.visible_cut.append(Vector3i(x,z,16))
	for key in world.visible_cut:
		check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":0,"base":false}),"initial region admitted %s" % key)
	check(await pump_until(func(): return world.tiles.size()==4),"worker meshes reach live staging and publication")
	# Obtain terrain height through the same worker, avoiding concurrent native access.
	var height_reply: Array[float] = []
	world.height_received.connect(func(_point: Vector3, height: float, _token: int): height_reply.append(height))
	world.request_height(Vector3(1296,0,1296),7)
	check(await pump_until(func(): return not height_reply.is_empty()),"worker height query completes")
	if height_reply.is_empty():
		world.shutdown()
		world.free()
		quit(1)
		return
	var point := Vector3(1296,height_reply[0],1296)
	var rows: Array[Dictionary] = []
	for mode in ["completion_before_preparation","overlapped"]:
		var old: Dictionary = world.tiles.duplicate()
		var old_brick_nodes: Dictionary={}
		for key in old:
			for bottom in old[key].get("bricks",{}): old_brick_nodes[Vector4i(key.x,bottom,key.y,key.z)]=old[key].bricks[bottom].node.get_instance_id()
		var before: Array[float] = await physics_hits(old,"worker fixture original physics "+mode)
		var revision_before: int = world.published_revision
		var start := Time.get_ticks_usec()
		check(world.edit(Codec.brush(point,point,4,0,false,1),point-Vector3.ONE*9,point+Vector3.ONE*9),"public stream edit accepted "+mode)
		check(world.last_density_tiles==4,"edit invalidates exactly four visible local regions "+mode)
		if mode=="completion_before_preparation":
			check(await pump_until(func(): return world.edit_worker_done,false),"worker completion received with staging deliberately held")
			check(world.pending_edit and world.batch_remaining==4 and world.staging.size()==4,"completion alone cannot publish unprepared batch")
			var held: Array[float] = await physics_hits(old,"worker completed but original collision retained")
			check(before==held,"completion-before-preparation keeps original physics surface")
		check(await pump_until(func(): return not world.pending_edit),"local worker edit commits "+mode)
		var elapsed := (Time.get_ticks_usec()-start)/1000.0
		check(world.published_revision==revision_before+1 and world.batch_remaining==0 and world.staged_batch.is_empty(),"worker transaction publishes exactly once "+mode)
		if world.backend.brick_terrain or world.backend.region_terrain:
			var retained:=0
			var rebuilt:=0
			for key in world.tiles:
				check(world.tiles[key].bricks.size()==8,"complete vertical ownership retained")
				for bottom: int in world.tiles[key].bricks:
					var identity:=Vector4i(key.x,bottom,key.y,key.z)
					var same: bool=world.tiles[key].bricks[bottom].node.get_instance_id()==old_brick_nodes[identity]
					if bottom>world.geometry_hi.y or bottom+33<world.geometry_lo.y:
						check(same,"unaffected brick mesh and collision node retained")
						retained+=1
					else:
						check(not same,"affected brick replaced")
						rebuilt+=1
			check(retained>0 and rebuilt>0 and retained+rebuilt==32,"edit updates a strict subset of cached vertical bricks")
			var counted_bytes:=0
			var exact_accounting:=true
			for key in world.tiles:
				var child_bytes:=0
				for child: Dictionary in world.tiles[key].bricks.values(): child_bytes+=int(child.bytes)
				exact_accounting=exact_accounting and child_bytes==int(world.tiles[key].bytes)
				counted_bytes+=child_bytes
			check(exact_accounting and counted_bytes==world.cache_bytes,"retained brick residency is counted exactly once")
		var after: Array[float] = await physics_hits(world.tiles,"worker fixture replacement physics "+mode)
		var lowered := 0
		for i in range(4):
			if after[i]<before[i]-0.01: lowered += 1
		check(lowered==4,"worker excavation lowers all four sampled surfaces "+mode)
		rows.append({"mode":mode,"elapsed_ms":elapsed,"worker_build_ms":world.last_total_build_ms,"worker_queue_ms":world.last_queue_ms,"publish_ms":world.last_commit_ms,"before_heights":before,"after_heights":after})
		point.y -= 2.0
	if world.backend.brick_terrain or world.backend.region_terrain:
		var retained_ids: Dictionary={}
		for key in world.tiles:
			for bottom in world.tiles[key].bricks: retained_ids[Vector4i(key.x,bottom,key.y,key.z)]=world.tiles[key].bricks[bottom].node.get_instance_id()
		world.last_geometry_done_us=0
		var deadline:=Time.get_ticks_msec()+10000
		while not world.lighting_dirty.is_empty() and Time.get_ticks_msec()<deadline:
			world._schedule_lighting()
			for result: Dictionary in world.backend.poll(): world._receive(result)
			world._drain_staging()
			await process_frame
		check(world.lighting_dirty.is_empty() and world.lighting_in_flight.is_empty(),"deferred brick lighting completes")
		var unchanged:=true
		for key in world.tiles:
			for bottom in world.tiles[key].bricks: unchanged=unchanged and world.tiles[key].bricks[bottom].node.get_instance_id()==retained_ids[Vector4i(key.x,bottom,key.y,key.z)]
		check(unchanged,"brick relighting retains meshes and collision nodes")
	if world.backend.region_terrain:
		await verify_coarse_locality(rows)
		verify_region_seams()
	world.shutdown()
	check(not world.backend.thread.is_started(),"real worker joins cleanly")
	world.free()
	await process_frame
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/terrain_worker_publication_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"checks":checks,"rows":rows,"events":worker_events,"scope":"Real native worker, public stream edit/invalidation, collision staging and physics queries. Fixed four-region cut; no quadtree transitions, draw/GPU or endurance. Snapshot candidate selected only with --snapshot-terrain. Held mode deliberately includes observer delay; all timings are headless diagnostic only."},"  "))
	file.close()
	quit(0 if failures==0 else 1)

func verify_coarse_locality(rows: Array[Dictionary]) -> void:
	for entry: Dictionary in world.tiles.values(): world._set_active(entry,false)
	var key:=Vector3i(1280,1280,256)
	world.visible_cut=[key]
	check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":world.stamps.get(key,0),"base":false}),"coarse container admitted")
	check(await pump_until(func(): return world.tiles.has(key)),"coarse container published through actual stream")
	if not world.tiles.has(key): return
	var before: Dictionary=world.tiles[key]
	check(before.bricks.size()==512,"256m container has 512 bounded 32x32x32 owners")
	var empty_without_render_instance:=0
	var inherited_visible:=true
	for child: Dictionary in before.bricks.values():
		if child.triangles==0 and not child.node is MeshInstance3D: empty_without_render_instance+=1
		inherited_visible=inherited_visible and child.node.is_visible_in_tree()
	check(empty_without_render_instance>0 and not before.node is MeshInstance3D,"empty owners and parent allocate no rendering instances")
	check(inherited_visible,"published owners inherit visible parent")
	world._set_active(before,false)
	var inherited_hidden:=true
	for child: Dictionary in before.bricks.values(): inherited_hidden=inherited_hidden and not child.node.is_visible_in_tree() and child.node.visible
	check(inherited_hidden,"one parent visibility switch hides every owner without changing child visibility")
	world._set_active(before,true)
	var ids: Dictionary={}
	for id in before.bricks: ids[id]=before.bricks[id].node.get_instance_id()
	var reply: Array[float]=[]
	world.height_received.connect(func(_p: Vector3,h: float,_t: int): reply.append(h))
	world.request_height(Vector3(1408,0,1408),99)
	check(await pump_until(func(): return not reply.is_empty()),"coarse edit height available")
	if reply.is_empty(): return
	var point:=Vector3(1408,reply[0],1408)
	var background_key:=Vector3i(1536,1280,256)
	check(world.backend.submit({"kind":"mesh","key":background_key,"epoch":world.epoch,"stamp":world.stamps.get(background_key,0),"base":false}),"unrelated background container admitted")
	var background: Dictionary={}
	var deadline:=Time.get_ticks_msec()+15000
	while background.is_empty() and Time.get_ticks_msec()<deadline:
		for result: Dictionary in world.backend.poll():
			if result.kind=="mesh" and result.key==background_key: background=result
			else: world._receive(result)
		await process_frame
	check(not background.is_empty() and not background.has("error"),"unrelated background container reaches preparation")
	if background.is_empty() or background.has("error"): return
	world.preparation={"data":background,"entry":world._begin_entry(background),"piece_at":0}
	world._prepare_piece()
	var background_node: int=world.preparation.entry.node.get_instance_id()
	check(world.edit(Codec.brush(point,point,2.5,0,false,1),point-Vector3.ONE*7.5,point+Vector3.ONE*7.5),"coarse corner excavation admitted")
	check(await pump_until(func(): return not world.pending_edit),"coarse corner excavation published")
	check(preemption_observed,"edit preempts an unfinished background container")
	check(await pump_until(func(): return world.tiles.has(background_key)),"background preparation resumes after edit publication")
	check(world.tiles.has(background_key) and world.tiles[background_key].node.get_instance_id()==background_node,"resumption preserves already prepared background resources")
	var current: Dictionary=world.tiles[key]
	var retained:=0
	var replaced:=0
	var exact:=true
	var bytes:=0
	var epoch_reply: PackedByteArray=world.backend.native.execute(Codec.command(13))
	for id in current.bricks:
		var child: Dictionary=current.bricks[id]
		bytes+=int(child.bytes)
		if child.node.get_instance_id()==ids[id]: retained+=1
		else: replaced+=1
		var bounds: AABB=child.region_bounds
		var fresh_packet: PackedByteArray=world.backend.native.build_owned_region(int(bounds.position.x),int(bounds.position.z),32,8,int(bounds.position.y),int(bounds.end.y),epoch_reply.decode_u32(12))
		var fresh: Dictionary=Codec.decode_mesh(fresh_packet)
		if fresh.has("error"): exact=false;continue
		for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:
			if child.arrays[channel]!=fresh.arrays[channel]: exact=false
	check(retained>0 and replaced>0 and retained+replaced==512,"coarse edit retains unaffected owners instead of rebuilding the parent")
	check(exact,"retained plus replaced coarse geometry equals full fresh reconstruction")
	check(bytes==int(current.bytes),"coarse partial publication accounts retained bytes once")
	rows.append({"mode":"coarse_locality","retained":retained,"replaced":replaced,"worker_ms":world.last_total_build_ms,"publication_ms":world.last_latency_ms})
	ids.clear()
	for id in current.bricks: ids[id]=current.bricks[id].node.get_instance_id()
	var pages_before: int=world.sdf_pages
	var fill:=point-Vector3.UP*1.5
	check(world.edit(Codec.brush(fill,fill,0.5,0,true,1),fill-Vector3.ONE*5.5,fill+Vector3.ONE*5.5),"existing-page coarse refill admitted")
	check(await pump_until(func(): return not world.pending_edit),"existing-page coarse refill published")
	check(world.sdf_pages==pages_before,"refill leaves simplifier page-presence mask unchanged")
	current=world.tiles[key]
	var local_replaced:=0
	exact=true
	epoch_reply=world.backend.native.execute(Codec.command(13))
	for id in current.bricks:
		var child: Dictionary=current.bricks[id]
		if child.node.get_instance_id()!=ids[id]: local_replaced+=1
		var bounds: AABB=child.region_bounds
		var fresh: Dictionary=Codec.decode_mesh(world.backend.native.build_owned_region(int(bounds.position.x),int(bounds.position.z),32,8,int(bounds.position.y),int(bounds.end.y),epoch_reply.decode_u32(12)))
		if fresh.has("error"): exact=false;continue
		for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_COLOR,Mesh.ARRAY_TEX_UV2,Mesh.ARRAY_INDEX]:
			if child.arrays[channel]!=fresh.arrays[channel]: exact=false
	check(local_replaced>0 and local_replaced<replaced,"unchanged page mask avoids rebuilding the broad simplification halo")
	check(exact,"narrow field invalidation matches full fresh coarse reconstruction")

func boundary_edges(packets: Array,axis: int,plane: float, interior: bool = false) -> Dictionary:
	var counts: Dictionary={}
	for packet: PackedByteArray in packets:
		var decoded: Dictionary=Codec.decode_mesh(packet)
		if decoded.has("error"): return {"invalid":1}
		var positions: PackedVector3Array=decoded.arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array=decoded.arrays[Mesh.ARRAY_INDEX]
		for at in range(0,indices.size(),3):
			for side in range(3):
				var a: Vector3=positions[indices[at+side]]
				var b: Vector3=positions[indices[at+(side+1)%3]]
				if a[axis]<plane-1 or b[axis]<plane-1 or a[axis]>plane or b[axis]>plane: continue
				# Exclude unrelated lateral open edges lying in this Y strip.
				if interior and (a.x<960 or b.x<960 or a.z<960 or b.z<960 or a.x>=991 or b.x>=991 or a.z>=991 or b.z>=991): continue
				var ka:=PackedVector3Array([a]).to_byte_array().hex_encode()
				var kb:=PackedVector3Array([b]).to_byte_array().hex_encode()
				var edge:=ka+kb if ka<kb else kb+ka
				counts[edge]=int(counts.get(edge,0))+1
	var boundary: Dictionary={}
	for edge: String in counts:
		if counts[edge]==1: boundary[edge]=true
	return boundary

func verify_region_seams() -> void:
	var native: Object=world.backend.native
	var epoch_reply: PackedByteArray=native.execute(Codec.command(13))
	var epoch: int=epoch_reply.decode_u32(12)
	for site: Vector3i in [Vector3i(1280,96,1280),Vector3i(960,32,960)]:
		var coarse: PackedByteArray=native.build_owned_region(site.x,site.z,32,8,site.y,site.y+32,epoch)
		var fine_a: PackedByteArray=native.build_owned_region(site.x+32,site.z,16,1,site.y,site.y+32,epoch)
		var fine_b: PackedByteArray=native.build_owned_region(site.x+32,site.z+16,16,1,site.y,site.y+32,epoch)
		var left:=boundary_edges([coarse],0,site.x+32)
		var right:=boundary_edges([fine_a,fine_b],0,site.x+32)
		check(not left.is_empty() and left==right,"coarse/fine shared edge bit multisets match "+str(site))
	var lower: PackedByteArray=native.build_owned_region(960,960,32,8,32,64,epoch)
	var upper: PackedByteArray=native.build_owned_region(960,960,32,8,64,96,epoch)
	var below:=boundary_edges([lower],1,64,true)
	var above:=boundary_edges([upper],1,64,true)
	var mismatch: Array=[]
	for edge: String in below:
		if not above.has(edge) and mismatch.size()<8: mismatch.append({"side":"below","edge":Array(edge.hex_decode().to_float32_array())})
	for edge: String in above:
		if not below.has(edge) and mismatch.size()<16: mismatch.append({"side":"above","edge":Array(edge.hex_decode().to_float32_array())})
	worker_events.append({"kind":"vertical_seam","below":below.size(),"above":above.size(),"mismatch":mismatch})
	check(not below.is_empty() and below==above,"vertical cave join interior edge bit multisets match")
	for origin: int in [960,1280]:
		var full: PackedByteArray=native.execute(Codec.command(1,[origin,origin,32,1,epoch]))
		var parts: Array=[]
		for bottom in range(0,256,32): parts.append(native.build_owned_region(origin,origin,32,1,bottom,bottom+32,epoch))
		check(triangle_multiset([full.slice(16)])==triangle_multiset(parts),"all vertical slabs reproduce full-height oriented geometry and normals "+str(origin))

func triangle_multiset(packets: Array) -> Dictionary:
	var triangles: Dictionary={}
	for packet: PackedByteArray in packets:
		var data: Dictionary=Codec.decode_mesh(packet)
		if data.has("error"): return {"invalid":packet.size()}
		var positions: PackedVector3Array=data.arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array=data.arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array=data.arrays[Mesh.ARRAY_INDEX]
		for at in range(0,indices.size(),3):
			var corners: Array[String]=[]
			for i in range(3):
				var index:=indices[at+i]
				corners.append(PackedVector3Array([positions[index],normals[index]]).to_byte_array().hex_encode())
			var rotations: Array[String]=[corners[0]+corners[1]+corners[2],corners[1]+corners[2]+corners[0],corners[2]+corners[0]+corners[1]]
			rotations.sort()
			triangles[rotations[0]]=int(triangles.get(rotations[0],0))+1
	return triangles
