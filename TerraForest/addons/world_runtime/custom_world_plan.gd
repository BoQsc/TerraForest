extends RefCounted
const VERSION:=21
const LIMIT:=32*1024*1024
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
const Market=preload("res://addons/structures/central_market.gd")
const Survey=preload("res://addons/world_runtime/survey_cache.gd")
const Routes=preload("res://addons/structures/regional_route_planner.gd")
static func read_plan(path:String,key:String)->Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()<40 or file.get_length()>LIMIT:return {}
 var checksum:=file.get_buffer(32);var bytes:=file.get_buffer(file.get_length()-32)
 if Survey.digest(bytes)!=checksum:return {}
 var value=bytes_to_var(bytes)
 if not value is Dictionary or value.get("recipe_key")!=key or value.get("recipe_version")!=VERSION or not value.get("ok",false):return {}
 if not value.get("sites") is Array or value.sites.is_empty() or value.sites.size()>9:return {}
 for site:Dictionary in value.sites:
  var source:Array=Market.recipe(site.center) if site.recipe_kind=="market" else Lots.recipe(site.center,true)
  if site.lots.size()!=source.size():return {}
  for index in site.lots.size():site.lots[index].asset=source[(index+int(site.get("variant",0)))%source.size()].asset
 value.plan=value.sites[0];value.market=value.sites[1] if value.options.settlements>1 else {}
 value["plan_digest"]=checksum.hex_encode();value["cache_hit"]=true
 value["mineral_plan_ms"]=0.0
 return value
static func build(seed_value:int,generator:int,options:Dictionary,folder:String,layout_variant:int=0,progress:RefCounted=null)->Dictionary:
 var started:=Time.get_ticks_usec()
 var encoded:=Recipe.encode(options)
 if encoded.is_empty() or seed_value<0 or seed_value>2147483647 or generator not in [17,19,20,21,22,23,24,25,26,27]:return {"ok":false,"reason":"Unsupported world recipe"}
 if progress!=null:progress.record("Checking the binary placement-plan cache",0,0,"Seed %d / terrain %d / recipe v%d"%[seed_value,generator,VERSION])
 var core=ClassDB.instantiate("TerrainCore")
 var suffix:="template_release" if core.build_variant()=="template_release" else "template_debug"
 var terrain_library:="res://addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll" if suffix=="template_release" else "res://addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll"
 var key:="%d|%d|%d|%s|%s|%s"%[VERSION,seed_value,generator,encoded.hex_encode(),FileAccess.get_sha256(terrain_library),FileAccess.get_sha256("res://addons/structures/bin/structures.windows.%s.x86_64.dll"%suffix)]
 var path:=folder.path_join("recipe_%d_%s.bin"%[VERSION,Survey.digest(key.to_utf8_buffer()).hex_encode()])
 var cached:=read_plan(path,key)
 if not cached.is_empty():cached["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0;return cached
 if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {"ok":false,"reason":"Native terrain initialization failed"}
 var layout:=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
 var sites:Array=[];var occupied:Array=[];var works:Dictionary={"ok":true,"segments":[],"bounds":AABB()}
 var distributed:=generator>=24
 var hints:Array=[3,4,2 if seed_value%2 else 1] if distributed else [3,0,1]
 if distributed and layout_variant%2==1:hints[2]=3-hints[2]
 for town in options.settlements:
  if progress!=null:progress.record("Fitting settlement %d of %d"%[town+1,options.settlements],sites.size(),options.settlements*options.districts,"Native streets, foundation samples and entrances / layout pass %d / maximum fill 2 m, cut 3 m"%[layout_variant+1])
  var hint:Vector3=layout.sites[hints[town]].position
  var shift:=144 if distributed else 96
  if distributed or town==2:hint+=[Vector3.ZERO,Vector3(shift,0,0),Vector3(-shift,0,0),Vector3(0,0,-shift)][layout_variant]
  var search_area:=Rect2()
  if distributed and town==2:search_area=Rect2(Vector2(120 if hints[town]==1 else 1450,600),Vector2(430,800))
  var site:Dictionary=Market.locate(core,hint,occupied[0]) if town==1 else Planner.locate(core,hint,occupied,search_area)
  if not site.get("ok",false):
   site["reason"]="Settlement %d: %s"%[town+1,site.get("reason","Site fitting failed")]
   return retry(seed_value,generator,options,folder,layout_variant,started,site,progress) if distributed or town==2 else site
  site["recipe_kind"]="market" if town==1 else "neighborhood";site["town"]=town;site["district"]=0
  var earthworks:=Planner.earthworks(site)
  if not earthworks.get("ok",false):return earthworks
  occupied.append(earthworks.bounds);sites.append(site)
  works.bounds=earthworks.bounds if sites.size()==1 else works.bounds.merge(earthworks.bounds)
  works.segments.append_array(earthworks.segments)
 for expansion in options.settlements*(options.districts-1):
  var town:int=expansion%options.settlements
  var district:int=1+expansion/options.settlements
  if progress!=null:progress.record("Expanding settlement %d of %d"%[town+1,options.settlements],sites.size(),options.settlements*options.districts,"Relocating independent districts around terrain, occupied lots, water and protected sites")
  var offset:Vector3=[Vector3(192,0,0),Vector3(0,0,192),Vector3(-192,0,0),Vector3(0,0,-192)][(layout_variant+district-1)%4]
  var hint:Vector3=sites[town].center+offset*(1 if town%2==0 else -1)
  if distributed:
   var spread:Vector3=Vector3(360 if district==1 else -360,0,0) if town<2 else Vector3(0,0,360 if district==1 else -360)
   hint=sites[town].center+spread
  var search_area:=Rect2()
  if distributed and options.settlements>1 and town<2 and district==1:search_area=Rect2(Vector2(1250,120 if town==0 else 1000),Vector2(630,880))
  var site:=Planner.locate(core,hint,occupied,search_area)
  if (options.districts==3 or distributed) and not site.get("ok",false):
   for direction in 4:
    var reach:=600 if distributed else 384
    var alternate:Vector3=[Vector3(reach,0,0),Vector3(0,0,reach),Vector3(-reach,0,0),Vector3(0,0,-reach)][(direction+layout_variant)%4]
    if search_area.has_area():alternate=Vector3(1680,0,440+direction*192 if town==0 else 1560-direction*192)-sites[town].center
    if progress!=null:progress.record("Finding space for district %d"%[district+1],direction,4,"Bounded alternate site search / unchanged 2 m fill and 3 m cut limits")
    site=Planner.locate(core,sites[town].center+alternate,occupied,search_area)
    if site.get("ok",false):break
  if not site.get("ok",false):
   site["reason"]="Settlement %d district %d: %s"%[town+1,district+1,site.get("reason","Site fitting failed")]
   site["hint"]=hint;site["search_area"]=search_area
   return retry(seed_value,generator,options,folder,layout_variant,started,site,progress)
  site["recipe_kind"]="neighborhood";site["town"]=town;site["district"]=district
  var earthworks:=Planner.earthworks(site)
  if not earthworks.get("ok",false):return earthworks
  occupied.append(earthworks.bounds);sites.append(site);works.bounds=works.bounds.merge(earthworks.bounds);works.segments.append_array(earthworks.segments)
 var protected:=Planner.reservations(core,layout.sites[hints[0]].position)
 if not protected.get("ok",false):return {"ok":false,"reason":"Native route reservations unavailable"}
 var reserved:Array=protected.areas.duplicate()
 for town in options.settlements:
  var hint:Dictionary=layout.sites[hints[town]]
  reserved.erase(Rect2(Vector2(hint.position.x,hint.position.z)-Vector2.ONE*(hint.radius+32),Vector2.ONE*(hint.radius+32)*2))
 if options.districts==3 or distributed:
  for site:Dictionary in sites:
   if not site.has("reservation_owner"):continue
   var claimed:Dictionary=layout.sites[int(site.reservation_owner)]
   reserved.erase(Rect2(Vector2(claimed.position.x,claimed.position.z)-Vector2.ONE*(claimed.radius+32),Vector2.ONE*(claimed.radius+32)*2))
 var building_count:=0
 for site:Dictionary in sites:
  for lot:Dictionary in site.lots:
   var bounds:AABB=lot.bounds
   reserved.append(Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z)).grow(2));building_count+=1
 var exits:Array=[];var streets:Array=[]
 for site:Dictionary in sites:
  var points:=PackedVector3Array(Routes.arrival_points(site,reserved,true))
  for point:Vector3 in Routes.arrival_points(site,reserved,false):
   if not points.has(point):points.append(point)
  exits.append(points);streets.append_array(site.roads)
 if progress!=null:progress.record("Connecting %d districts and planning offroads"%sites.size(),0,0,"Native A* / shared crossing grades / up to %d wilderness trails"%[options.trails*sites.size()])
 var network:Dictionary=core.plan_region_network(exits,reserved,options.network,options.trails,seed_value,streets)
 if not network.get("ok",false):return retry(seed_value,generator,options,folder,layout_variant,started,network,progress)
 var normalization:Dictionary={"enabled":false}
 if int(options.get("road_grid",0))>0:
  if progress!=null:progress.record("Planning build-friendly road grades",0,0,("Native footprint rules" if int(options.road_grid)==3 else "Native connected grades" if int(options.road_grid)==2 else "Native road normalization")+" / protected entrances / full-width cut and fill survey")
  var connected:bool=int(options.road_grid)>=2
  var exclusions:=reserved.duplicate()
  var network_mode:int=options.network
  for attempt in range(9):
   normalization=preload("res://addons/world_runtime/road_normalization.gd").apply(core,sites,network,connected,int(options.road_grid)==3)
   if normalization.get("ok",false):break
   if not connected:return normalization
   if not normalization.has("reroute_position") or attempt%3==2:
    if network_mode==0:return retry(seed_value,generator,options,folder,layout_variant,started,normalization,progress)
    network_mode-=1;exclusions=reserved.duplicate()
    if progress!=null:progress.record("Rejecting optional road loops that exceed terrain limits",options.network-network_mode,options.network,"All districts still required / no relaxation of earthworks or crossing rules")
   else:
    var failed:Vector3=normalization.reroute_position
    exclusions.append(Rect2(Vector2(failed.x-4,failed.z-4),Vector2(8,8)))
    if progress!=null:progress.record("Replanning a road that failed its terrain limits",attempt+1,9,"Connected grades / alternate native corridor / no silent fallback")
   network=core.plan_region_network(exits,exclusions,network_mode,options.trails,seed_value,streets)
   if not network.get("ok",false):return network
  if not normalization.get("ok",false):return normalization
  network["accepted_network_mode"]=network_mode
  network["optional_loops_reduced"]=network_mode<int(options.network)
  normalization["reroute_exclusions"]=exclusions.size()-reserved.size()
  normalization["enabled"]=true
  works={"ok":true,"segments":[],"bounds":AABB()}
  for site:Dictionary in sites:
   var normalized_works:=Planner.earthworks(site)
   if not normalized_works.get("ok",false):return normalized_works
   works.bounds=normalized_works.bounds if works.segments.is_empty() else works.bounds.merge(normalized_works.bounds)
   works.segments.append_array(normalized_works.segments)
 if not network.links.is_empty():works.segments=network.segments+works.segments;works.bounds=works.bounds.merge(network.bounds)
 var result:Dictionary={"ok":true,"version":3,"recipe_version":VERSION,"recipe_key":key,"seed":seed_value,"generator":generator,"options":options.duplicate(),"sites":sites,"connection":network if not network.links.is_empty() else {},"works":works,"building_count":building_count,"network":network}
 result["layout_variant"]=layout_variant
 result["road_normalization"]=normalization
 if int(options.get("material_veins",0))==1:
  if progress!=null:progress.record("Locating material veins and surface stones",0,0,"Native geology / dry gentle ground / outside roads and construction")
  var minerals:Dictionary=core.plan_material_deposits(works.segments)
  if not minerals.get("ok",false):return {"ok":false,"reason":"Material deposit planning failed"}
  result["material_deposits"]=minerals.deposits
  result["mineral_plan_ms"]=minerals.worker_ms
 var navigation:=navigation_metadata(sites,network)
 if not ClassDB.instantiate("NativeGeneratedRegion").set_plan(seed_value,generator,navigation.places,navigation.roads):return {"ok":false,"reason":"Regional navigation exceeds native storage limits"}
 result["navigation"]=navigation
 var packed:Dictionary=result.duplicate(true)
 packed.erase("mineral_plan_ms")
 if progress!=null:progress.record("Validating and caching the placement plan",sites.size(),sites.size(),"%d buildings / %d districts / native binary navigation validation"%[building_count,sites.size()])
 for site:Dictionary in packed.sites:
  for lot:Dictionary in site.lots:lot.erase("asset")
 var bytes:=var_to_bytes(packed);var checksum:=Survey.digest(bytes)
 result["plan"]=sites[0];result["market"]=sites[1] if options.settlements>1 else {}
 result["plan_digest"]=checksum.hex_encode();result["cache_hit"]=false;result["cache_persisted"]=false
 if bytes.size()+32<=LIMIT:
  DirAccess.make_dir_recursive_absolute(folder)
  var temporary:=path+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
  var file:=FileAccess.open(temporary,FileAccess.WRITE)
  if file!=null:
   file.store_buffer(checksum);file.store_buffer(bytes);file.close()
   if not read_plan(temporary,key).is_empty():result.cache_persisted=DirAccess.rename_absolute(temporary,path)==OK
   if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
 result["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
 result["cache_path"]=path
 return result
static func retry(seed_value:int,generator:int,options:Dictionary,folder:String,layout_variant:int,started:int,failure:Dictionary,progress:RefCounted)->Dictionary:
 var elapsed:float=(Time.get_ticks_usec()-started)/1000.0
 if layout_variant>=3:failure["worker_ms"]=elapsed;return failure
 var result:=build(seed_value,generator,options,folder,layout_variant+1,progress)
 result["worker_ms"]=float(result.get("worker_ms",0))+elapsed
 return result
static func navigation_metadata(sites:Array,network:Dictionary)->Dictionary:
 var metadata:Dictionary={"places":[],"roads":[]}
 for index in sites.size():
  var site:Dictionary=sites[index]
  var district:=preload("res://addons/world_runtime/generated_region.gd").neighborhood_metadata(site,30+index,"Settlement %d / District %d"%[site.town+1,site.district+1],"Terrain-fitted buildings and individually destructible sidewalk plates.")
  metadata.places.append_array(district.places);metadata.roads.append_array(district.roads)
 if network.has("grid_navigation"):metadata.roads.append_array(network.grid_navigation)
 else:
  for link:Dictionary in network.links:
   for index in range(1,link.points.size()):metadata.roads.append({"a":link.points[index-1],"b":link.points[index],"width":5.0 if link.trail else 8.0})
 return metadata
