# SPDX-License-Identifier: 0BSD
extends RefCounted
## Offline district recipes; preserve existing cells/attachments and fit each lot.
const Grand=preload("res://addons/structures/grand_buildings/catalog.gd")
const Civic=preload("res://addons/structures/civic_catalog.gd")
const City=preload("res://addons/structures/city_catalog.gd")
const Houses=preload("res://addons/structures/furniture_catalog.gd")
const Shops=preload("res://addons/structures/workshop_catalog.gd")
const Market=preload("res://addons/structures/central_market.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Routes=preload("res://addons/structures/regional_route_planner.gd")
const HINTS=[Vector3(800,0,780),Vector3(1180,0,780),Vector3(1000,0,1230),Vector3(300,0,300),Vector3(1690,0,300),Vector3(300,0,950),Vector3(1690,0,950),Vector3(320,0,1660),Vector3(1690,0,1660)]
const TITLES=["Cathedral & civic quarter","Foundry & apartment quarter","Needle Street & manor quarter","Millford market village","Crossfield service village","Oakwell workshops","Brookstead community","Meadowgate village","Stoneford market village"]
const EXTRA_IDS=["homestead_manor","house_c1","cottage_a2","shop_b1","shop_b2","workshop","tower_2","tower_3","tower_4"]
static var _sources:Dictionary={}
static var _market:Array=[]

static func generation_asset(source:Resource,id:String="")->Resource:
	if source==null:return null
	var asset:Resource=source.duplicate(true)
	# Deep buildings have some low walls/stair columns outside their cellar floor.
	# Give those columns real buried masonry roots. This preserves room air and
	# every authored cell/attachment while avoiding soil pedestals under stairs.
	var band:int=asset.get_meta("site_surface_offset",0)
	if band in [5,9]:
		var records:PackedInt32Array=asset.get_records();var roots:Dictionary={};var added:=0
		for at in range(0,records.size(),4):
			var column:=Vector2i(records[at],records[at+2])
			roots[column]=mini(int(roots.get(column,4096)),records[at+1])
		for column:Vector2i in roots:
			var low:int=roots[column]
			if low<=0 or low>band:continue
			for y in low:records.append_array(PackedInt32Array([column.x,y,column.y,65]));added+=1
		if added>0:
			var attachments:Array=asset.get_model_attachments()
			if not asset.configure(records) or not asset.configure_model_attachments(attachments):return null
			asset.set_meta("metropolis_foundation_footings",added)
	# The original review envelope adds 1 cm below zero. Keep all fabric/model
	# transforms intact; only the planning envelope excludes that empty padding.
	var box:AABB=asset.get_attachment_envelope()
	if box!=AABB() and box.position.y<0 and box.position.y>=-.02:
		var high:=box.end.y;box.position.y=0;box.size.y=high
		if not asset.configure_attachment_envelope(box):return null
	if not id.is_empty():asset.set_meta("metropolis_content_id",id)
	if asset.has_meta("grand_building_id") or id=="homestead_manor":
		band=int(asset.get_meta("site_surface_offset",1))
		asset.set_meta("site_surface_offset",band);asset.set_meta("site_sample_band",band)
		var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
		var x:float={"courtyard_flats":65.5,"grand_cathedral":52.0,"street_tower":27.0,"homestead_manor":19.0}.get(id,bounds.get_center().x)
		asset.set_meta("site_entrance",Vector3(x,band,bounds.end.z+.5))
	if id=="grand_cathedral":
		# Interior excavation only: the cross and stair chapel, never the whole lot.
		asset.set_meta("cellar_volumes",[AABB(Vector3(33,1,1),Vector3(39,8,79)),AABB(Vector3(1,1,29),Vector3(103,8,23)),AABB(Vector3(23,1,56),Vector3(9,8,24))])
	return asset

static func sources(block:int)->Array:
	if block>=3:
		if not _sources.has(3):_sources[3]=recipe(Vector3(1000,0,1000),3).map(func(lot:Dictionary):return lot.asset)
		return _sources[3]
	if _sources.has(block):return _sources[block]
	var cottage:Resource=Houses.enclosed_cottage()
	var small:Resource=Shops.village_shop()
	var hipped:Resource=Shops.hipped_shop()
	var workshop:Resource=Shops.workshop()
	var raw:Array
	if block==0:
		raw=[Grand.asset(1),Civic.asset(0),Civic.asset(1),Civic.asset(2),Civic.asset(3),Civic.asset(4),Houses.large_house(),cottage,small,workshop,cottage,cottage]
	elif block==1:
		raw=[Grand.asset(0),City.asset(0),City.asset(3),City.asset(5),City.asset(4),City.asset(1),City.asset(2),Houses.furnished_tower(4),cottage,cottage,hipped,cottage]
	else:
		raw=[Grand.asset(2),preload("res://addons/structures/mansion/catalog.gd").asset(),Houses.large_house(),Houses.furnished_tower(2),Houses.furnished_tower(3),workshop,small,hipped,cottage,cottage,cottage,cottage]
	var result:Array=[]
	for index in raw.size():
		var asset:Resource=raw[index]
		var id:String=asset.get_meta("grand_building_id",asset.get_meta("city_id",asset.get_meta("expansion_id","")))
		if block==2 and index==1:id="homestead_manor"
		if (block==0 and index==9) or (block==2 and index==5):id="workshop"
		if block==1 and index==7:id="tower_4"
		if block==2 and index in [3,4]:id="tower_"+str(index-1)
		result.append(generation_asset(asset,id))
	_sources[block]=result
	return result

static func recipe(center:Vector3,block:int)->Array:
	if block>=3:
		if _market.is_empty():
			_market=Market.recipe(Vector3(1000,0,1000))
			for lot:Dictionary in _market:lot.asset=generation_asset(lot.asset)
		return Planner.translated_recipe(_market,Vector3(1000,0,1000),center)
	var source:=sources(block);var result:Array=[]
	for row in [-112,0,112]:
		for side in [-1,1]:
			for x in [-72,72]:
				var index:=result.size();var asset:Resource=source[index]
				var rotation:=0 if side<0 else 2
				var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,rotation)
				var entrance:Vector3=asset.get_meta("site_entrance",Vector3(.5,0,asset.get_bounds().end.z+.5))
				for turn in rotation:entrance=Vector3(1-entrance.z,entrance.y,entrance.x)
				var street:float=center.z+row
				var origin:=Vector3i(roundi(center.x+x-bounds.get_center().x),0,roundi(street+side*14-entrance.z))
				result.append({"asset":asset,"origin":origin,"rotation":rotation,"street_z":street,"general_access":true,"label":asset.resource_name})
	return result

static func streets(center:Vector3,block:int)->Array:
	var result:Array=[]
	var rows:Array=[-112,0,112] if block<3 else [-24,24]
	var width:=148 if block<3 else 44
	for row in rows:result.append(Lots._segment(center+Vector3(-width,0,row),center+Vector3(width,0,row),4 if block<3 else 3,3,4,0,4))
	for x in [-width,width]:result.append(Lots._segment(center+Vector3(x,0,rows.front()),center+Vector3(x,0,rows.back()),4 if block<3 else 3,3,4,0,4))
	return result

static func mini_sources(block:int,part:int)->Array:
	var count:=3 if block<3 else 4
	return sources(block).slice(part*count,(part+1)*count)

static func mini_recipe(center:Vector3,block:int,part:int,heading:int=0)->Array:
	var source:Array=mini_sources(block,part)
	var result:Array=[]
	# Frontages share the gentle side of a street; do not force a second row
	# uphill merely to fill a rectangular grid. Routes join these real blocks.
	var positions:Array=[Vector2(0,-1),Vector2(-88,-1),Vector2(88,-1)]
	if block>=3 or part>0:
		positions=[]
		var widths:Array=[];var total:float=(source.size()-1)*12.0
		for asset:Resource in source:
			var width:float=asset.placement_bounds(Vector3i.ZERO,0).size.x
			widths.append(width);total+=width
		var cursor:float=-total*.5
		for width:float in widths:positions.append(Vector2(cursor+width*.5,-1));cursor+=width+12
	for index in source.size():
		var asset:Resource=source[index];var side:int=int(positions[index].y);var rotation:=((0 if side<0 else 2)+heading)%4
		var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,rotation)
		var entrance:Vector3=asset.get_meta("site_entrance",Vector3(.5,0,asset.get_bounds().end.z+.5))
		for turn in rotation:entrance=Vector3(1-entrance.z,entrance.y,entrance.x)
		var axis:=Vector3.RIGHT;var across:=Vector3(0,0,1)
		for turn in heading:axis=Vector3(-axis.z,0,axis.x);across=Vector3(-across.z,0,across.x)
		var target:Vector3=center+axis*float(positions[index].x)+across*side*14
		var origin:=Vector3i((target-entrance).round());origin.y=0
		if absf(axis.x)>.5:origin.x=roundi(center.x+axis.x*positions[index].x-bounds.get_center().x)
		else:origin.z=roundi(center.z+axis.z*positions[index].x-bounds.get_center().z)
		result.append({"asset":asset,"origin":origin,"rotation":rotation,"street_z":center.z,"general_access":true,"label":asset.resource_name})
	return result

static func mini_streets(center:Vector3,heading:int=0,block:int=0,part:int=0)->Array:
	var axis:=Vector3.RIGHT
	for turn in heading:axis=Vector3(-axis.z,0,axis.x)
	var half:=90.0
	if block>=3 or part>0:
		var source:=mini_sources(block,part)
		half=8.0+(source.size()-1)*6.0
		for asset:Resource in source:half+=asset.placement_bounds(Vector3i.ZERO,0).size.x*.5
		half=maxf(48,half)
	return [Lots._segment(center-axis*half,center+axis*half,4,3,4,0,4)]

static func mini_envelope(block:int,part:int,heading:int)->Vector2:
	if block<3 and part==0:return Vector2(204,204)
	var width:float=40.0+(mini_sources(block,part).size()-1)*12.0;var depth:=0.0
	for asset:Resource in mini_sources(block,part):
		var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
		width+=bounds.size.x;depth=maxf(depth,bounds.size.z)
	var result:=Vector2(maxf(128,width),depth*2+48)
	return Vector2(result.y,result.x) if heading%2 else result

static func connect_mini(candidate:Dictionary,core:RefCounted,roads:Array,lots:Array)->Dictionary:
	if roads.is_empty():return {"ok":true,"segments":[]}
	var exclusions:Array=Planner.reservations(core,candidate.center).areas.duplicate()
	for lot:Dictionary in lots+candidate.lots:
		exclusions.append(Rect2(Vector2(lot.bounds.position.x,lot.bounds.position.z),Vector2(lot.bounds.size.x,lot.bounds.size.z)).grow(2))
	var points:Array=[]
	for road:Dictionary in roads:
		for point:Vector3 in [road.start,road.finish]:
			if points.has(point):continue
			var blocked:=false
			for area:Rect2 in exclusions:
				if area.grow(6).has_point(Vector2(point.x,point.z)):blocked=true;break
			if not blocked:points.append(point)
	points.sort_custom(func(a:Vector3,b:Vector3):return a.distance_squared_to(candidate.center)<b.distance_squared_to(candidate.center))
	var arrivals:=PackedVector3Array(Routes.arrival_points(candidate,exclusions,true))
	for point:Vector3 in Routes.arrival_points(candidate,exclusions,false):
		if not arrivals.has(point):arrivals.append(point)
	return core.plan_region_network([PackedVector3Array(points.slice(0,16)),arrivals],exclusions,0,0,0,roads+candidate.roads,7.5)

static func locate(core:RefCounted,road_grid:int,variant:int,progress:RefCounted=null)->Dictionary:
	var sites:Array=[];var occupied:Array=[];var works:Dictionary={"ok":true,"segments":[],"bounds":AABB()}
	var city_roads:Array=[];var city_lots:Array=[]
	var relocation:=Vector3.ZERO
	var heading:=0
	var village_hints:Array=HINTS.slice(3)
	var city_offsets:Array=[Vector3.ZERO,Vector3(380,0,0),Vector3(200,0,450)]
	for block in 9:
		if progress!=null:progress.record("Fitting "+TITLES[block],block,9,"One large city and six outlying communities / per-lot terrain fitting")
		var hint:Vector3=HINTS[0]+relocation+city_offsets[block] if block<3 else village_hints[block-3]
		if block<3:hint+=[Vector3.ZERO,Vector3(24,0,24),Vector3(-24,0,24),Vector3(0,0,-24)][variant]
		var site:Dictionary={}
		# Independently fitted street blocks can straddle preserved open
		# space. Their connecting roads use native routing around water/POIs.
		var parts:Array=[];var all_roads:Array=[];var all_lots:Array=[]
		var part_count:=4 if block<3 else 2
		for part in part_count:
			if progress!=null:progress.record("Fitting %s / block %d"%[TITLES[block],part+1],block*4+part if block<3 else 12+(block-3)*2+part,24,"Separate street grades and full foundation/entrance surveys")
			var point:Vector3=hint+([Vector3(-105,0,-95),Vector3(105,0,-95),Vector3(-105,0,95),Vector3(105,0,95)][part] if block<3 else Vector3(0,0,-65 if part==0 else 65))
			var reach:=192 if block==0 and part==0 else 320
			var area:=Rect2(Vector2(point.x-reach,point.z-reach),Vector2(reach*2,reach*2))
			var gate:=connect_mini.bind(core,city_roads+all_roads,city_lots+all_lots)
			var fitted:=Planner.locate(core,point,occupied,area,mini_recipe.bind(block,part,heading),mini_streets.bind(heading,block,part),mini_envelope(block,part,heading),road_grid,false,gate)
			if not fitted.get("ok",false) and not (block==0 and part==0):
				for turn in range(1,4):
					var facing:=(heading+turn)%4
					fitted=Planner.locate(core,point,occupied,area,mini_recipe.bind(block,part,facing),mini_streets.bind(facing,block,part),mini_envelope(block,part,facing),road_grid,false,gate)
					if fitted.get("ok",false):break
			if not fitted.get("ok",false) and block==0 and part==0:
				if progress!=null:progress.record("Surveying a dry, gentle city anchor",0,1,"Bounded central-region search / preserve every requested landmark")
				for direction in 4:
					fitted=Planner.locate(core,point,occupied,Rect2(Vector2(128,128),Vector2(1744,1744)),mini_recipe.bind(block,part,direction),mini_streets.bind(direction),Vector2(204,204),road_grid,true)
					if fitted.get("ok",false):heading=direction;break
				if fitted.get("ok",false):
					relocation=fitted.center-point;hint+=relocation
					var center:Vector3=fitted.center
					var edges:Array=[center.x,center.z,2000-center.x,2000-center.z]
					var edge:int=edges.find(edges.min())
					if float(edges[edge])<320:
						var axis:=Vector3(0,0,1 if center.z<1000 else -1) if edge in [0,2] else Vector3(1 if center.x<1000 else -1,0,0)
						city_offsets=[Vector3.ZERO,axis*340,axis*640]
						if minf(center.x,2000-center.x)<400 and minf(center.z,2000-center.z)<400:
							# A corner city grows along both gentle shores, keeping the
							# civic quarter between its residential quarters.
							city_offsets=[Vector3.ZERO,Vector3(0,0,340 if center.z<1000 else -340),Vector3(340 if center.x<1000 else -340,0,0)]
						village_hints=[Vector3(350,0,850),Vector3(1650,0,700),Vector3(300,0,1450),Vector3(1700,0,1450),Vector3(900,0,1700),Vector3(1000,0,1050)]
						for index in village_hints.size():
							var p:Vector3=village_hints[index]
							if edge==0:p=Vector3(2000-p.z,0,p.x)
							elif edge==2:p=Vector3(p.z,0,2000-p.x)
							elif edge==3:p=Vector3(2000-p.x,0,2000-p.z)
							village_hints[index]=p
			if not fitted.get("ok",false):
				print("METROPOLIS_SITE_REJECTION ",JSON.stringify({"quarter":block,"block":part,"road_rejections":fitted.get("road_rejections",{}),"lot_rejections":fitted.get("lot_rejections",{}),"street_candidates":fitted.get("street_candidates",0),"best_missing":fitted.get("best_missing",0)}))
				fitted["reason"]=TITLES[block]+" / block %d: "%[part+1]+str(fitted.get("reason","No terrain-fitting site"));return fitted
			if progress!=null:progress.record("Compiling %s / block %d"%[TITLES[block],part+1])
			var prepared:=Planner.earthworks(fitted)
			if not prepared.get("ok",false):return prepared
			occupied.append(prepared.bounds);parts.append(fitted);all_roads.append_array(fitted.roads);all_lots.append_array(fitted.lots)
			for road:Dictionary in fitted.get("site_connection",{}).get("segments",[]):
				if int(road.material)!=4:continue
				var street:Dictionary=road.duplicate()
				street["coefficients"]=PackedFloat64Array([0,0,street.finish.y-street.start.y,street.start.y]);street["curve_index"]=0
				all_roads.append(street);occupied.append(street.bounds.grow(6))
		city_roads.append_array(all_roads);city_lots.append_array(all_lots)
		var center:=Vector3.ZERO
		for fitted:Dictionary in parts:center+=fitted.center/part_count
		site={"ok":true,"center":center,"lots":all_lots,"roads":all_roads,"variant":0}
		if not site.get("ok",false):
			print("METROPOLIS_SITE_REJECTION ",JSON.stringify({"block":block,"attempts":site.get("attempts",0),"road_rejections":site.get("road_rejections",{}),"street_candidates":site.get("street_candidates",0),"best_missing":site.get("best_missing",0)}))
			site["reason"]=TITLES[block]+": "+str(site.get("reason","No terrain-fitting site"));return site
		site["recipe_kind"]="metropolis";site["metro_block"]=block
		site["town"]=0 if block<3 else block-2;site["district"]=block if block<3 else 0
		site["title"]=TITLES[block];site["introduction_home"]=false
		if progress!=null:progress.record("Compiling complete "+TITLES[block])
		var earthworks:=Planner.earthworks(site)
		if not earthworks.get("ok",false):return earthworks
		sites.append(site)
		works.bounds=earthworks.bounds if sites.size()==1 else works.bounds.merge(earthworks.bounds)
		works.segments.append_array(earthworks.segments)
	return {"ok":true,"sites":sites,"occupied":occupied,"works":works}

static func audit(sites:Array,bridges:Array)->Dictionary:
	var ids:Dictionary={};var city_count:=0;var small:=0;var large:=0
	for site:Dictionary in sites:
		if int(site.get("metro_block",99))<3:city_count+=site.lots.size()
		for lot:Dictionary in site.lots:
			var id:String=lot.asset.get_meta("metropolis_content_id",lot.asset.get_meta("expansion_id",""))
			if not id.is_empty():ids[id]=int(ids.get(id,0))+1
	for crossing:Dictionary in bridges:
		if crossing.get("kind","")=="small" and int(crossing.span)<=28:small+=1
		elif int(crossing.span)>=32:large+=1
	var missing:Array=[]
	for id:String in Grand.IDS+City.IDS+Civic.IDS+EXTRA_IDS:
		if not ids.has(id):missing.append(id)
	var farthest:=0.0;var covered:=0;var total:=0
	for z in range(100,2000,100):
		for x in range(100,2000,100):
			var nearest:=INF
			for site:Dictionary in sites:nearest=minf(nearest,Vector2(x-site.center.x,z-site.center.z).length())
			farthest=maxf(farthest,nearest);total+=1
			if nearest<=400:covered+=1
	var coherent:=sites.size()==9
	if coherent:
		for block in [1,2]:coherent=coherent and sites[block].center.distance_to(sites[0].center)<=750
	return {"ok":missing.is_empty() and city_count>=36 and small>=1 and large>=2 and coherent and farthest<=750,"missing":missing,"city_buildings":city_count,"large_bridges":large,"small_bridges":small,"communities":sites.size()-2,"maximum_distance_to_community_m":farthest,"land_grid_within_400m_percent":100.0*covered/maxi(1,total),"content":ids}
