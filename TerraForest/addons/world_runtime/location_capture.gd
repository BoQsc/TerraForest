# SPDX-License-Identifier: 0BSD
extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const OWNERS=["terrain","blocks","cubes","models","doors","damage","containers","residents","corpses","trees","ground","water"]
const VERSION:=1

static func definition(location:Dictionary)->PackedByteArray:
	return digest(var_to_bytes([VERSION,location.key,location.layout,location.origin,location.rotation,location.bounds,location.residents,location.containers]))

static func digest(bytes:PackedByteArray)->PackedByteArray:
	var hash:=HashingContext.new()
	if hash.start(HashingContext.HASH_SHA256)!=OK or hash.update(bytes)!=OK:return PackedByteArray()
	return hash.finish()

static func envelope(kind:String,bounds:AABB,records:Array)->PackedByteArray:
	return var_to_bytes([VERSION,kind,bounds,records])

static func unpack(bytes:PackedByteArray,kind:String,bounds:AABB)->Dictionary:
	if bytes.is_empty() or bytes.size()>16*1024*1024:return {}
	var value:Variant=bytes_to_var(bytes)
	if not value is Array or value.size()!=4 or value[0]!=VERSION or value[1]!=kind or value[2]!=bounds or not value[3] is Array:return {}
	return {"records":value[3]}

static func tiles(origin:Vector3i,size:Vector3i)->Array:
	var result:Array=[]
	for depth in range(0,size.z,64):
		for height in range(0,size.y,64):
			for across in range(0,size.x,64):
				var offset:=Vector3i(across,height,depth)
				result.append([origin+offset,(size-offset).min(Vector3i.ONE*64)])
	return result

static func valid_bounds(bounds:AABB)->bool:
	if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.position!=bounds.position.floor() or bounds.size!=bounds.size.floor():return false
	for axis in 3:
		if bounds.size[axis]<1 or bounds.size[axis]>128:return false
	return bounds.position.x>=2 and bounds.position.z>=2 and bounds.end.x<=1998 and bounds.end.z<=1998 and bounds.position.y>=4 and bounds.end.y<=254

static func patch(owner:Object,kind:String,arguments:Array)->PackedByteArray:
	var token:Dictionary=owner.call(kind+"_patch_state")
	arguments=arguments.duplicate();arguments.append(token.revision);arguments.append(token.get("owner",token.get("epoch",-1)))
	var bytes:PackedByteArray=owner.callv("capture_"+kind+"_patch",arguments)
	return bytes if owner.call("validate_"+kind+"_patch",bytes) else PackedByteArray()

static func surface(field:RefCounted,points:PackedVector3Array)->Dictionary:
	if points.is_empty():return {"points":points,"normals":PackedVector3Array()}
	var command:=Codec.command(17,[points.size()]);command.append_array(points.to_byte_array())
	var reply:PackedByteArray=field.execute(command)
	if not Codec.reply_ok(reply) or reply.size()!=16+points.size()*24 or reply.decode_u32(12)!=points.size():return {}
	return {"points":Codec._packed_channel(reply,16,points.size(),12,TYPE_PACKED_VECTOR3_ARRAY),"normals":Codec._packed_channel(reply,16+points.size()*12,points.size(),12,TYPE_PACKED_VECTOR3_ARRAY)}

static func selected_roots(placed:Dictionary,bounds:AABB)->PackedInt64Array:
	var result:=PackedInt64Array()
	for index in placed.ids.size():
		var point:Vector3=placed.transforms[index].origin
		if point.x>=bounds.position.x and point.y>=bounds.position.y and point.z>=bounds.position.z and point.x<bounds.end.x and point.y<bounds.end.y and point.z<bounds.end.z:result.append(placed.ids[index])
	return result

static func capture_natural(config:Dictionary,bounds:AABB)->Dictionary:
	var tree_ids:=PackedInt64Array();var ground_ids:=PackedInt64Array()
	var tree_cells:Dictionary={}
	var first:=Vector2i(floori(bounds.position.x/32),floori(bounds.position.z/32))
	var last:=Vector2i(ceili(bounds.end.x/32)-1,ceili(bounds.end.z/32)-1)
	for depth in range(first.y,last.y+1):
		for across in range(first.x,last.x+1):
			var shelter:=PackedVector3Array()
			for tree_depth in range(maxi(0,floori((depth*32-5)/64.0)),mini(31,floori((depth*32+37)/64.0))+1):
				for tree_across in range(maxi(0,floori((across*32-5)/64.0)),mini(31,floori((across*32+37)/64.0))+1):
					var key:=Vector2i(tree_across,tree_depth)
					shelter.append_array(config.scatter.candidates(key,config.seed,config.density,config.regional).points)
					if tree_cells.has(key):continue
					tree_cells[key]=true
					var candidates:Dictionary=config.scatter.candidates(key,config.seed,config.density,config.regional,config.biome)
					var samples:=surface(config.field,candidates.points)
					if samples.is_empty():return {"ok":false,"reason":"tree_surface"}
					var placed:Dictionary=config.scatter.place_surface(candidates.ids,samples.points,samples.normals,candidates.rotations,candidates.scales,config.min_up)
					if not placed.get("ok",false):return {"ok":false,"reason":"tree_placement"}
					tree_ids.append_array(selected_roots(placed,bounds))
			for layer in 16:
				var candidates:Dictionary=config.cover.candidates(Vector2i(across,depth),config.seed,layer,shelter,true)
				var samples:=surface(config.field,candidates.points)
				if samples.is_empty():return {"ok":false,"reason":"ground_surface"}
				var placed:Dictionary=config.cover.place(candidates.ids,samples.points,samples.normals)
				if not placed.get("ok",false):return {"ok":false,"reason":"ground_placement"}
				ground_ids.append_array(selected_roots(placed,bounds))
	var trees:=patch(config.harvest,"harvest",[tree_ids]) if not tree_ids.is_empty() else PackedByteArray()
	var ground:=patch(config.removed,"ground",[bounds,ground_ids])
	if (not tree_ids.is_empty() and trees.is_empty()) or ground.is_empty():return {"ok":false,"reason":"natural_patch"}
	return {"ok":true,"trees":[tree_ids,trees,config.seed,config.density,config.biome,config.min_up,config.scatter.capture_storage_snapshot()],"ground":[ground_ids,ground],"tree_roots":tree_ids.size(),"ground_roots":ground_ids.size()}

static func capture_fields(config:Dictionary,bounds:AABB)->Dictionary:
	var token:Dictionary=config.field.field_patch_state()
	var sections:Dictionary={}
	for kind:String in ["terrain","cubes"]:
		var records:Array=[]
		var origin:=Vector3i(bounds.position)
		var size:=Vector3i(bounds.size)+(Vector3i.ONE if kind=="terrain" else Vector3i.ZERO)
		for tile:Array in tiles(origin,size):
			var bytes:=patch(config.field,"field" if kind=="terrain" else "cube",tile)
			if bytes.is_empty():return {"ok":false,"reason":kind+"_patch"}
			records.append(bytes)
		sections[kind]=envelope(kind,bounds,records)
	var natural:=capture_natural(config,bounds)
	if not natural.ok:return natural
	if config.field.field_patch_state()!=token:return {"ok":false,"reason":"terrain_changed_during_capture"}
	sections["trees"]=envelope("trees",bounds,natural.trees)
	sections["ground"]=envelope("ground",bounds,natural.ground)
	return {"ok":true,"sections":sections,"tree_roots":natural.tree_roots,"ground_roots":natural.ground_roots}

static func capture_scene(game:Node,location:Dictionary)->Dictionary:
	var bounds:AABB=location.bounds
	var sections:Dictionary={};var records:Array=[]
	for tile:Array in tiles(Vector3i(bounds.position),Vector3i(bounds.size)):
		var bytes:=patch(game.structures.blocks,"cell",tile)
		if bytes.is_empty():return {"ok":false,"reason":"block_patch"}
		records.append(bytes)
	sections["blocks"]=envelope("blocks",bounds,records)
	records=[]
	for tile:Array in tiles(Vector3i(bounds.position)*2,Vector3i(bounds.size)*2):
		var bytes:=patch(game.lakes.water,"water",tile)
		if bytes.is_empty():return {"ok":false,"reason":"water_patch","location":location.layout,"tile":tile,"water":game.lakes.statistics()}
		records.append(bytes)
	sections["water"]=envelope("water",bounds,records)
	var models:Array=[];var doors:Array=[];var collections:Dictionary=game.structures.model_collections()
	var assets:Array=collections.keys();assets.sort()
	for asset:String in assets:
		var collection:Node3D=collections[asset]
		if collection.global_transform!=Transform3D.IDENTITY:return {"ok":false,"reason":"transformed_model_collection:"+asset}
		var bytes:=patch(collection,"placement",[Vector3i(bounds.position),Vector3i(bounds.size)])
		if bytes.is_empty():return {"ok":false,"reason":"model_boundary_or_unavailable:"+asset}
		var members:Dictionary=collection.placement_patch_members(bytes)
		if not members.get("ok",false):return {"ok":false,"reason":"model_members:"+asset}
		var protected_ids:=PackedInt64Array()
		for identity in members.ids:
			if collection.is_removal_protected(identity):protected_ids.append(identity)
		models.append([asset,bytes,members.ids,protected_ids])
		if game.doors.types.has(asset):
			var hinges:=patch(game.doors.types[asset].state,"door",[members.ids]) if not members.ids.is_empty() else PackedByteArray()
			if not members.ids.is_empty() and hinges.is_empty():return {"ok":false,"reason":"door_patch:"+asset}
			var row:Array=[asset,members.ids,hinges]
			if game.doors.types[asset].has("locks"):
				var locks:=patch(game.doors.types[asset].locks.store,"container",[members.ids]) if not members.ids.is_empty() else PackedByteArray()
				if not members.ids.is_empty() and locks.is_empty():return {"ok":false,"reason":"door_lock_patch:"+asset}
				row.append(locks)
			doors.append(row)
	sections["models"]=envelope("models",bounds,models)
	sections["doors"]=envelope("doors",bounds,doors)
	if game.world_attack.durability.record_count()!=0 or game.ground_cover.rock_damage.record_count()!=0:return {"ok":false,"reason":"generation_has_damage"}
	sections["damage"]=envelope("damage",bounds,["pristine_generation",game.world_attack.durability.capture_storage_snapshot(),game.ground_cover.rock_damage.capture_storage_snapshot()])
	var resident_ids:PackedInt64Array=game.zombies.population.store.authored_identities(location.residents)
	if resident_ids.size()!=location.residents.size():return {"ok":false,"reason":"resident_identity"}
	for index in resident_ids.size():
		var resident:Dictionary=game.zombies.population.store.resident(resident_ids[index])
		if resident.get("anchor",0)!=location.residents[index] or resident.get("state",0)!=1 or resident.sleep.decode_u32(32)!=1:return {"ok":false,"reason":"generation_resident_not_sleeping"}
	for kind:String in ["containers","residents","corpses"]:
		var owner:Object=game.storage.store if kind=="containers" else game.zombies.population.store if kind=="residents" else game.corpse_loot.store
		var arguments:Array=[location.containers] if kind=="containers" else [resident_ids] if kind=="residents" else [resident_ids,location.residents]
		var method:String="container" if kind=="containers" else "resident" if kind=="residents" else "corpse"
		var bytes:=patch(owner,method,arguments)
		if bytes.is_empty():return {"ok":false,"reason":kind+"_patch"}
		sections[kind]=envelope(kind,bounds,[bytes])
	return {"ok":true,"sections":sections}

static func owner_tokens(game:Node)->Array:
	var result:Array=[]
	for entry:Array in [[game.terrain.backend.native,"field"],[game.structures.blocks,"cell"],[game.lakes.water,"water"],[game.world_attack.durability,"damage"],[game.storage.store,"container"],[game.zombies.population.store,"resident"],[game.corpse_loot.store,"corpse"],[game.ecosystem.harvest_state,"harvest"],[game.ground_cover.removed,"ground"]]:
		var token:Dictionary=entry[0].call(entry[1]+"_patch_state")
		result.append([token.revision,token.get("owner",token.get("epoch",-1))])
	var collections:Dictionary=game.structures.model_collections();var names:Array=collections.keys();names.sort()
	for name:String in names:
		result.append([name,collections[name].placement_patch_state()])
		if game.doors.types.has(name):
			result.append([name,game.doors.types[name].state.door_patch_state()])
			if game.doors.types[name].has("locks"):result.append([name+"/locks",game.doors.types[name].locks.store.container_patch_state()])
	return result

static func publish_generated(game:Node,progress:Callable,cancelled:Callable)->Dictionary:
	if not game.terrain.diagnostics_pause_streaming or game.ecosystem.is_processing() or game.ground_cover.is_processing():return {"ok":false,"reason":"capture_requires_generation_barrier"}
	if not game.persistence.initialize_location_baselines():return {"ok":false,"reason":"not_fresh_generation"}
	if not game.ground_cover.removed.bind_world(game.terrain.backend.world_seed,1):return {"ok":false,"reason":"ground_identity"}
	progress.call("Finishing quest-location water contacts",0,0,{"activity":"Settling terrain and building changes before preserving originals"})
	var deadline:=Time.get_ticks_msec()+120000
	while game.lakes.statistics().pending_regions>0 or game.lakes._busy or game.lakes._builder!=null or game.lakes.water.water_patch_state().filling:
		if cancelled.call() or Time.get_ticks_msec()>deadline:return {"ok":false,"reason":"water_contacts_not_ready"}
		await game.get_tree().process_frame
	var store:RefCounted=game.persistence.location_baselines
	var locations:Array=game.quests.store.get_locations();var evidence:Array=[]
	var config:Dictionary={"field":game.terrain.backend.native,"water":game.lakes.water,"scatter":game.ecosystem._scatter(),"cover":game.ground_cover.native,"harvest":game.ecosystem.harvest_state,"removed":game.ground_cover.removed,"seed":game.terrain.backend.world_seed,"density":game.ecosystem.density,"biome":game.ecosystem.biome_profile,"regional":game.terrain.backend.world_generator>=14,"min_up":cos(deg_to_rad(game.ecosystem.max_slope_degrees))}
	for index in locations.size():
		var location:Dictionary=locations[index];var bounds:AABB=location.bounds
		if cancelled.call():return {"ok":false,"reason":"cancelled"}
		if not valid_bounds(bounds):return {"ok":false,"reason":"location_bounds:"+location.layout}
		progress.call("Preserving original quest locations",index,locations.size(),{"activity":location.title+" · structures, supplies and sleepers"})
		await game.get_tree().process_frame
		var started:=Time.get_ticks_usec()
		var expected_tokens:=owner_tokens(game)
		var captured:=capture_scene(game,location)
		if not captured.ok:return captured
		var scene_us:=Time.get_ticks_usec()-started
		progress.call("Preserving original quest locations",index,locations.size(),{"activity":location.title+" · terrain and natural roots"})
		var worker:=Thread.new()
		if worker.start(capture_fields.bind(config,bounds))!=OK:return {"ok":false,"reason":"capture_worker"}
		while worker.is_alive():await game.get_tree().process_frame
		var fields:Dictionary=worker.wait_to_finish()
		if not fields.ok:return fields
		if owner_tokens(game)!=expected_tokens:return {"ok":false,"reason":"owners_changed_during_capture"}
		captured.sections.merge(fields.sections)
		for kind:String in OWNERS:
			if not captured.sections.has(kind) or unpack(captured.sections[kind],kind,bounds).is_empty():return {"ok":false,"reason":"incomplete_owner:"+kind}
		if cancelled.call():return {"ok":false,"reason":"cancelled"}
		var token:Dictionary=store.state()
		if worker.start(store.publish_baseline.bind(location.key,definition(location),captured.sections,token.revision,token.owner))!=OK:return {"ok":false,"reason":"publication_worker"}
		while worker.is_alive():await game.get_tree().process_frame
		var published:Dictionary=worker.wait_to_finish()
		if not published.ok:return published
		evidence.append({"key":location.key,"layout":location.layout,"capture_us":Time.get_ticks_usec()-started,"scene_us":scene_us,"tree_roots":fields.tree_roots,"ground_roots":fields.ground_roots,"referenced_bytes":store.state().bytes})
	return {"ok":true,"locations":evidence,"bytes":store.state().bytes}
