# SPDX-License-Identifier: 0BSD
extends "res://tests/water_blast_settling.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var core:RefCounted
func publish(water:RefCounted)->bool:
	for n in 4096:
		var batch:Dictionary=water.next_mesh_batch()
		if batch.is_empty():return true
		if batch.get("complete",false) and not water.commit_mesh_batch(batch.batch):return false
	return false
func prepare_requests(water:RefCounted)->bool:
	for n in 1024:
		var request:Dictionary=water.next_request()
		if request.is_empty():return true
		var patch:RefCounted=ClassDB.instantiate("NativeWaterTerrainPatch")
		if not patch.configure(request.coordinate):return false
		var revision:int=core.execute(Codec.command(0)).decode_u32(12)
		var status:=0
		for step in 32:
			status=patch.sample_terrain(core,256,revision,0)
			if status!=0:break
		if status!=1 or not water.accept_patch(patch):return false
	return false
func moment(values:Dictionary)->float:
	var sum:=0.0
	for p:Vector3i in values:sum+=p.y*float(values[p])
	return sum
func _initialize()->void:
	core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[42,5]))
	# Real terrain protocol rejects coordinates at its half-open outer bound.
	# Water's final lattice node must nevertheless prepare at all four corners.
	for coordinate in [Vector3i(0,9,0),Vector3i(499,9,0),Vector3i(0,9,499),Vector3i(499,9,499)]:
		var edge=ClassDB.instantiate("NativeWaterTerrainPatch")
		check(edge.configure(coordinate),"world-edge water patch configures")
		var revision:int=core.execute(Codec.command(0)).decode_u32(12)
		var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
		var status:=0
		for attempt in 64:
			status=edge.sample_terrain(core,2048,revision,epoch)
			if status!=0:break
		check(status==1,"world-edge occupancy completes without stale retry: "+str(coordinate))
	var block:=Vector3(46,40,46);core.execute(Codec.brush(block,block,5,1,true,0))
	var basin:=Vector3(46,45,46);core.execute(Codec.brush(basin,basin,2,0,false,0))
	var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
	if OS.get_cmdline_user_args().has("--profile-settling"):water.configure_settling_profile(true)
	check(water.begin_fill(AABB(Vector3(43,42,43),Vector3(6,4,6)),44.5,Vector3(46,44,46),-1),"native carved basin fill begins")
	for n in 1000:
		water.advance(2048)
		if not prepare_requests(water):check(false,"initial terrain occupancy prepares");break
		if not water.statistics().fill_active:break
	var before:=amounts(water);var total:int=water.statistics().water_ml
	check(total>0 and not water.statistics().fill_active,"actual terrain bowl owns finite water")
	check(publish(water),"initial native water mesh and query revision publish together")
	var from:=Vector3(46,46,46);var to:=Vector3(46,41,46)
	var old_hit:Dictionary=water.raycast_surface(from,to)
	check(old_hit.get("hit",false),"initial published water surface is present")
	var blast:=Vector3(46,43.5,46);core.execute(Codec.brush(blast,blast,1.5,0,false,0))
	var bounds:=AABB(blast-Vector3.ONE*2,Vector3.ONE*4)
	water.invalidate(bounds);water.settle_after_edit(bounds)
	var max_us:=0;var total_us:=0;var done:=false
	for n in 128:
		if not prepare_requests(water):check(false,"blast occupancy prepares");break
		var job:RefCounted=water.begin_equilibrium()
		if job==null:break
		job.prepare();var result:Dictionary=water.finish_equilibrium(job)
		var elapsed:int=result.get("worker_us",0);total_us+=elapsed;max_us=maxi(max_us,elapsed)
		if not result.get("ok",false) and not result.get("pending",false):check(false,"equilibrium failure: "+str(result));break
		if water.statistics().settling_regions==0:done=true;break
	check(done,"actual carved-crater settling finishes")
	check(water.statistics().water_ml==total,"actual crater conserves finite water")
	check(moment(amounts(water))<moment(before),"water moves down into actual excavated terrain")
	check(water.raycast_surface(from,to)==old_hit,"unpublished settling retains the displayed query revision")
	check(publish(water),"settled native water mesh and query revision publish together")
	var new_hit:Dictionary=water.raycast_surface(from,to)
	check(new_hit.get("hit",false) and old_hit.get("hit",false) and new_hit.point.y<old_hit.point.y,"published water surface follows the lowered water")
	var obstacle:=Vector3(46,44,46)
	core.execute(Codec.brush(obstacle,obstacle,.75,0,true,0))
	var changed:=AABB(obstacle-Vector3.ONE*3,Vector3.ONE*6)
	water.invalidate(changed,true);water.settle_after_edit(changed)
	var displaced:=false
	for n in 128:
		if not prepare_requests(water):break
		var job:RefCounted=water.begin_equilibrium()
		if job==null:break
		job.prepare();var result:Dictionary=water.finish_equilibrium(job)
		if result.get("ok",false):displaced=true;break
		if not result.get("pending",false):break
	check(displaced and water.statistics().water_ml==total,"Actual density overhang displaces water without loss")
	check(publish(water),"Overhang geometry and immersion publish together")
	check(water.depth_at(obstacle)==0 and water.depth_at(Vector3(46,42.75,46))>0,"Actual 3D terrain excludes water in the overhang while retaining water below it")
	var digest:=HashingContext.new();digest.start(HashingContext.HASH_SHA256);digest.update(snapshot(water))
	print("WATER_BLAST_TERRAIN total_settling_us=",total_us," max_settling_step_us=",max_us," snapshot_sha256=",digest.finish().hex_encode()," statistics=",water.statistics()," failures=",failures)
	quit(1 if failures else 0)
