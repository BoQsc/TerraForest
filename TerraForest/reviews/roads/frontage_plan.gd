extends RefCounted
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
const Market=preload("res://addons/structures/central_market.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
static func lines(center:Vector3,trial:bool)->Array:
	var result:Array=[]
	for depth in [-24,24]:result.append(Lots._segment(center+Vector3(-52,0,depth),center+Vector3(52,0,depth),3,3,4,0,4))
	for across in [-52,52]:result.append(Lots._segment(center+Vector3(across,0,-24),center+Vector3(across,0,24),3,3,4,0,4))
	if trial:
		for index in result.size():result[index].frontage_trial=true;result[index].building_frontage=index<2
	return result
static func fit(core:RefCounted,center:Vector3,trial:bool)->Dictionary:
	var road_plan:=Planner.streets(core,center,lines(center,trial))
	if not road_plan.get("ok",false):return road_plan
	var source:=Market.recipe(center)
	var recipe:Array=[source[1],source[3],source[4],source[6]]
	if trial:
		for lot:Dictionary in recipe:lot.frontage_x=Vector2(center.x-24,center.x+24)
	var lots:=Planner.plan(core,center,road_plan.segments,0,recipe)
	if not lots.get("ok",false):return {"ok":false,"reason":"Approved building lots do not fit this road proposal"}
	if trial:
		for lot:Dictionary in lots.lots:
			var endpoint:Vector3=lot.entrance.segment.finish
			var on_frontage:=false
			for landing:Dictionary in road_plan.frontages:
				if absf(endpoint.z-landing.start.z)<.01 and endpoint.x>=landing.start.x+2 and endpoint.x<=landing.finish.x-2:on_frontage=true
			if not on_frontage:return {"ok":false,"reason":"Relocated entrance leaves the near-level frontage"}
	var result:Dictionary={"ok":true,"center":center,"roads":road_plan.segments,"lots":lots.lots,"road_survey":road_plan,"trial":trial}
	var works:=Planner.earthworks(result)
	if not works.get("ok",false):return works
	if trial:
		var plate_roads:Array=road_plan.segments.duplicate(true)
		for road:Dictionary in plate_roads:
			if absf(road.start.y-road.finish.y)<.0001:road.start.y=roundf(road.start.y);road.finish.y=road.start.y
		var paving:Dictionary=ClassDB.instantiate("NativeBlockPrefab").plan_paving(plate_roads)
		if not paving.get("ok",false):return paving
		result.block_paving=paving;works.segments.append_array(paving.beds)
		for bed:Dictionary in paving.beds:works.bounds=works.bounds.merge(bed.bounds)
	result.works=works
	return result
static func build(seed_value:int=1703)->Dictionary:
	var core:RefCounted=ClassDB.instantiate("TerrainCore")
	if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,21]))):return {"ok":false,"reason":"Terrain initialization failed"}
	var reasons:Dictionary={};var attempts:=0
	for radius in range(0,145,12):
		var offsets:Array[Vector3]=[]
		for across in range(-radius,radius+1,12):
			for depth in range(-radius,radius+1,12):
				if maxi(absi(across),absi(depth))==radius:offsets.append(Vector3(across,0,depth))
		for offset:Vector3 in offsets:
			var center:Vector3=Vector3(989,35,1117)+offset
			attempts+=1
			var trial:=fit(core,center,true)
			if not trial.get("ok",false):
				var reason:String=trial.get("reason","Trial failed")
				if trial.has("road_index"):reason+=" / road %d"%trial.road_index
				reasons[reason]=int(reasons.get(reason,0))+1;continue
			var baseline:=fit(core,center,false)
			if not baseline.get("ok",false):continue
			return {"ok":true,"seed":seed_value,"generator":21,"baseline":baseline,"trial":trial,"attempts":attempts,"rejections":reasons}
	return {"ok":false,"reason":"No paired street review fits the bounded candidate search","attempts":attempts,"rejections":reasons}
