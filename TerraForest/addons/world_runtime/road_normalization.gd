extends RefCounted
static func protected_areas(sites:Array)->Array:
	var result:Array=[]
	for site:Dictionary in sites:
		for lot:Dictionary in site.lots:
			var bounds:AABB=lot.bounds
			result.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(.25))
			var entrance:Dictionary=lot.entrance.segment
			var start:Vector3=entrance.start
			var finish:Vector3=entrance.finish
			result.append(Rect2(Vector2(minf(start.x,finish.x),minf(start.z,finish.z)),Vector2(absf(start.x-finish.x),absf(start.z-finish.z))).grow(float(entrance.half_width)+.25))
	return result
static func apply(core:RefCounted,sites:Array,network:Dictionary,connected:bool=false,footprint_policy:bool=false)->Dictionary:
	var roads:Array=[]
	var supports:Dictionary={}
	for support:Dictionary in network.segments:
		if int(support.material)!=1:continue
		var key:Array=[support.start,support.finish]
		var previous:Dictionary=supports.get(key,{"half_width":0.0,"shoulder":0.0})
		supports[key]={"half_width":maxf(previous.half_width,float(support.half_width)),"shoulder":maxf(previous.shoulder,float(support.shoulder))}
	for index in sites.size():
		for road:Dictionary in sites[index].roads:
			var record:=road.duplicate();record["normalization_owner"]=index
			if footprint_policy:
				var support:Dictionary=preload("res://addons/structures/terrain_lot_planner.gd").road_support(road)
				record["support_half_width"]=support.half_width;record["support_shoulder"]=support.shoulder
			roads.append(record)
	for index in network.segments.size():
		var road:Dictionary=network.segments[index]
		if int(road.material)!=4:continue
		var record:=road.duplicate();record["normalization_owner"]=-index-1
		if footprint_policy:
			record["support_half_width"]=float(road.half_width);record["support_shoulder"]=float(road.shoulder)
			var support:Dictionary=supports.get([road.start,road.finish],{})
			if not support.is_empty():record.support_half_width=maxf(record.support_half_width,float(support.half_width));record.support_shoulder=maxf(record.support_shoulder,float(support.shoulder))
		roads.append(record)
	var result:Dictionary=core.fit_road_network(roads,protected_areas(sites),footprint_policy) if connected else core.normalize_roads(roads,protected_areas(sites))
	if not result.get("ok",false):
		var failed:int=int(result.get("road",-1))
		var other:int=int(result.get("other_road",-1))
		if other>=0 and other<roads.size() and int(roads[other].normalization_owner)<0:failed=other
		if connected and failed>=0 and failed<roads.size() and int(roads[failed].normalization_owner)<0:
			result["reroute_position"]=result.get("position",(roads[failed].start+roads[failed].finish)*.5)
		return result
	var groups:Dictionary={}
	for road:Dictionary in result.segments:
		var owner:int=road.normalization_owner
		if not groups.has(owner):groups[owner]=[]
		var record:=road.duplicate();record.erase("normalization_owner");record["grid_normalized"]=true;groups[owner].append(record)
	for index in sites.size():sites[index].roads=groups[index]
	var regional:Array=[]
	var profiles:Dictionary={}
	for index in network.segments.size():
		if groups.has(-index-1):profiles[[network.segments[index].start,network.segments[index].finish]]=groups[-index-1]
	for index in network.segments.size():
		if groups.has(-index-1):regional.append_array(groups[-index-1])
		else:
			var original:Dictionary=network.segments[index]
			var key:Array=[original.start,original.finish]
			if not profiles.has(key):regional.append(original);continue
			for surface:Dictionary in profiles[key]:
				var support:=original.duplicate()
				for field:String in ["start","finish","coefficients","curve_index"]:
					if surface.has(field):support[field]=surface[field]
				support.bounds=original.bounds.grow(.55)
				regional.append(support)
	network.segments=regional
	if connected:
		var surfaces:Dictionary={};var navigation:Array=[];var bounds:=AABB()
		for index in regional.size():
			var road:Dictionary=regional[index]
			bounds=road.bounds if index==0 else bounds.merge(road.bounds)
			if int(road.material)==4:surfaces[[road.start,road.finish]]=true;navigation.append({"a":road.start,"b":road.finish,"width":float(road.half_width)*2})
		for road:Dictionary in regional:
			if int(road.material)==1 and not surfaces.has([road.start,road.finish]):navigation.append({"a":road.start,"b":road.finish,"width":float(road.half_width)*2})
		network["grid_navigation"]=navigation;network.bounds=bounds
	result.erase("segments")
	return result
