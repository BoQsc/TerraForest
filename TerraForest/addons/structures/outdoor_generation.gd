# SPDX-License-Identifier: 0BSD
extends RefCounted
## One generation-time pass. No gameplay scatter/refill or per-object scripts.
const Packs=preload("res://addons/structures/pack_registry.gd")
const Scatter=preload("res://addons/structures/outdoor_scatter.gd")
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
const TARGET_PER_LOT:=16
const MAX_OBJECTS:=4096
const ATTEMPTS:=48
const SUPPORT_BATCH_LIMIT:=4096
const ITEMS:=[828,827,822,823,824,825,821,826,829,798,799,736,735]

static func candidates(lot:Dictionary,world_seed:int,roads:Array=[])->Array[Dictionary]:
	var bounds:AABB=lot.asset.placement_bounds(Vector3i.ZERO,0)
	var rotation:=Basis(Vector3.UP,-int(lot.rotation)*PI*.5)
	var half:=Vector3(.5,0,.5)
	var frame:=Transform3D(rotation,Vector3(lot.origin)+half-rotation*half)
	var random:=RandomNumberGenerator.new();random.seed=world_seed^lot.origin.x*73856093^lot.origin.z*19349663
	var result:Array[Dictionary]=[]
	for index in ATTEMPTS:
		var point:=bounds.get_center()
		# Side and rear yard groups. Never use the front/garage approach.
		var side:=index%3;var amount:=random.randf_range(.1,.85)
		if side==0:point.x=bounds.position.x-random.randf_range(1.2,3.8);point.z=lerpf(bounds.position.z,bounds.end.z,amount)
		elif side==1:point.x=bounds.end.x+random.randf_range(1.2,3.8);point.z=lerpf(bounds.position.z,bounds.end.z,amount)
		else:point.z=bounds.position.z-random.randf_range(1.2,3.8);point.x=lerpf(bounds.position.x,bounds.end.x,amount)
		point=frame*point
		if point.x<5 or point.z<5 or point.x>1995 or point.z>1995 or Scatter.near_road(point,2,roads):continue
		var item:int=ITEMS[index%ITEMS.size()]
		var row:Dictionary=Packs.by_item[item]
		var mesh:Mesh=load(row.directory+"/models/"+row.id+".tres")
		var pose:=Transform3D(Basis(Vector3.UP,random.randf()*TAU),point)
		result.append({"item":item,"model":row.key,"pose":pose,"mesh":mesh})
	return result

static func support_probes(bounds:AABB)->PackedVector3Array:
	var result:=PackedVector3Array()
	var columns:=maxi(1,ceili(bounds.size.x/.35));var rows:=maxi(1,ceili(bounds.size.z/.35))
	for x in columns+1:
		for z in rows+1:
			var point:=Vector3(lerpf(bounds.position.x+.002,bounds.end.x-.002,float(x)/columns),bounds.position.y,lerpf(bounds.position.z+.002,bounds.end.z-.002,float(z)/rows))
			result.append(point-Vector3.UP*.04);result.append(point+Vector3.UP*.04)
	return result

static func tree_blocked(game:Node,bounds:AABB,cache:Dictionary)->bool:
	var key:=Vector2i(floori(bounds.get_center().x/64),floori(bounds.get_center().z/64))
	for z in range(maxi(0,key.y-1),mini(31,key.y+1)+1):
		for x in range(maxi(0,key.x-1),mini(31,key.x+1)+1):
			var cell:=Vector2i(x,z)
			if not cache.has(cell):cache[cell]=game.ecosystem._scatter().candidates(cell,game.terrain.backend.world_seed,game.ecosystem.density,true,game.ecosystem.biome_profile)
			var trees:Dictionary=cache[cell]
			for index in trees.points.size():
				if game.ecosystem.harvest_state.contains(trees.ids[index]):continue
				var root:Vector3=trees.points[index]
				var footprint:=Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(.8)
				if footprint.has_point(Vector2(root.x,root.z)):return true
	return false

static func _surface(terrain:Node,points:PackedVector3Array)->Dictionary:
	var token:int=Tokens.allocate();var received:Array=[]
	var density_revision:int=terrain.density_revision;var surface_revision:int=terrain.published_revision
	var callback:=func(id:int,positions:PackedVector3Array,normals:PackedVector3Array,epoch:int,revision:int):
		if id==token:received.append({"points":positions,"normals":normals,"epoch":epoch,"revision":revision})
	terrain.surface_batch_ready.connect(callback)
	var deadline:=Time.get_ticks_msec()+10000;var sent:=false
	while not terrain.stopping and Time.get_ticks_msec()<deadline:
		if not sent:sent=terrain.request_surface_batch(points,token)
		if not received.is_empty():break
		await terrain.get_tree().process_frame
	terrain.surface_batch_ready.disconnect(callback)
	if received.is_empty() or received[0].epoch!=terrain.epoch or received[0].revision!=surface_revision or terrain.density_revision!=density_revision:return {}
	return received[0]

static func _density(terrain:Node,points:PackedVector3Array)->PackedFloat32Array:
	var token:int=Tokens.allocate();var received:Array=[]
	var callback:=func(result:Dictionary):
		if result.token==token:received.append(result)
	terrain.density_batch_ready.connect(callback)
	var deadline:=Time.get_ticks_msec()+10000;var sent:=false
	while not terrain.stopping and Time.get_ticks_msec()<deadline:
		if not sent:sent=terrain.request_density_scan(points,token,0,true)
		if not received.is_empty():break
		await terrain.get_tree().process_frame
	terrain.density_batch_ready.disconnect(callback)
	if received.is_empty() or received[0].status!="ok" or received[0].epoch!=terrain.epoch or received[0].revision!=terrain.density_revision:return PackedFloat32Array()
	return received[0].values

static func _support(terrain:Node,bounds:Array[AABB])->Dictionary:
	var supported:Array[bool]=[];var cursor:=0;var requests:=0;var sample_count:=0
	var epoch:int=terrain.epoch;var revision:int=terrain.density_revision
	while cursor<bounds.size():
		if terrain.stopping:return {"ok":false}
		var points:=PackedVector3Array();var spans:Array[Vector2i]=[]
		while cursor<bounds.size():
			var probes:=support_probes(bounds[cursor])
			if probes.size()>SUPPORT_BATCH_LIMIT:return {"ok":false}
			if points.size()+probes.size()>SUPPORT_BATCH_LIMIT:break
			spans.append(Vector2i(points.size(),probes.size()));points.append_array(probes);cursor+=1
		var samples:=await _density(terrain,points);requests+=1;sample_count+=points.size()
		if samples.size()!=points.size() or terrain.epoch!=epoch or terrain.density_revision!=revision:return {"ok":false}
		for span in spans:
			var valid:=true
			for offset in span.y:
				var sample:float=samples[span.x+offset]
				if not is_finite(sample) or (sample<0)!=(offset%2==0):valid=false;break
			supported.append(valid)
	return {"ok":true,"supported":supported,"requests":requests,"samples":sample_count}

static func publish(game:Node,lots:Array,roads:Array,world_seed:int)->Dictionary:
	var placements:Array[Dictionary]=[];var skipped:=0
	var tree_cache:Dictionary={}
	var models:Dictionary=game.structures.model_collections()
	var density_requests:=0;var density_samples:=0
	for lot:Dictionary in lots:
		if game.shutdown_requested:return {"ok":false,"reason":"Outdoor generation cancelled"}
		if placements.size()+TARGET_PER_LOT>MAX_OBJECTS:return {"ok":false,"reason":"Outdoor generation exceeds its 4096-object authoring budget"}
		var proposals:=candidates(lot,world_seed,roads)
		if proposals.is_empty():continue
		var points:=PackedVector3Array()
		for proposal:Dictionary in proposals:points.append(proposal.pose.origin)
		var epoch:int=game.terrain.epoch;var revision:int=game.terrain.density_revision
		var surface:=await _surface(game.terrain,points)
		if surface.is_empty() or surface.points.size()!=points.size() or surface.normals.size()!=points.size():return {"ok":false,"reason":"Outdoor terrain survey unavailable"}
		var prepared:Array[Dictionary]=[];var support_bounds:Array[AABB]=[]
		var protected:=[AABB(game._initial_generation_spawn-Vector3(2,0,2),Vector3(4,3,4))]
		for location:Dictionary in game.quests.store.get_locations():protected.append(location.bounds)
		# Only terrain reads move ahead. Object conflicts are checked below, after
		# every earlier accepted insertion, in the original candidate order.
		for index in proposals.size():
			var proposal:Dictionary=proposals[index];var point:Vector3=surface.points[index]
			if not point.is_finite() or surface.normals[index].y<.96 or game.lakes.water.depth_at(point)>.02:prepared.append({});continue
			var prototype:AABB=proposal.mesh.get_aabb()
			for part:AABB in proposal.mesh.get_meta("collision_boxes"):prototype=prototype.merge(part)
			var pose:Transform3D=proposal.pose;pose.origin=point-Vector3.UP*prototype.position.y
			var bounds:AABB=pose*prototype
			var blocked:=false
			for box:AABB in protected:
				if box.intersects(bounds.grow(.3)):blocked=true;break
			if blocked or Scatter.near_road(point,maxf(bounds.size.x,bounds.size.z)*.5+1.2,roads):prepared.append({});continue
			if tree_blocked(game,bounds,tree_cache):prepared.append({});continue
			prepared.append({"proposal":proposal,"pose":pose,"bounds":bounds,"point":point,"support_index":support_bounds.size()});support_bounds.append(bounds)
		var support:Dictionary=await _support(game.terrain,support_bounds)
		if game.shutdown_requested:return {"ok":false,"reason":"Outdoor generation cancelled"}
		if not support.ok or game.terrain.epoch!=epoch or game.terrain.density_revision!=revision:return {"ok":false,"reason":"Outdoor support survey unavailable"}
		density_requests+=support.requests;density_samples+=support.samples
		var inserted:=0
		for entry:Dictionary in prepared:
			if inserted>=TARGET_PER_LOT:break
			if entry.is_empty():skipped+=1;continue
			var proposal:Dictionary=entry.proposal;var pose:Transform3D=entry.pose;var bounds:AABB=entry.bounds
			if not preload("res://addons/vehicle_runtime/building_parking.gd")._clear(game.structures.blocks,models,bounds.grow(.15)):skipped+=1;continue
			var car:Dictionary=game.world_vehicle.fleet.query_near(entry.point,6,32,128)
			if not car.get("ok",false) or not car.get("complete",false) or not car.ids.is_empty():skipped+=1;continue
			if not support.supported[entry.support_index]:skipped+=1;continue
			var packed:=PackedFloat32Array()
			for row in 3:
				for column in 3:packed.append(pose.basis[column][row])
				packed.append(pose.origin[row])
			var identity:int=models[proposal.model].insert_instance(packed,AABB())
			if identity<=0:return {"ok":false,"reason":"Outdoor object publication failed"}
			placements.append({"model":proposal.model,"id":identity,"position":pose.origin,"transform":Marshalls.raw_to_base64(packed.to_byte_array()),"lot":lot.get("label","Building")});inserted+=1
	if not placements.is_empty():game.terrain.changed_since_save=true
	return {"ok":true,"placements":placements,"skipped":skipped,"target_per_lot":TARGET_PER_LOT,"density_requests":density_requests,"density_samples":density_samples}
