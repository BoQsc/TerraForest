# SPDX-License-Identifier: 0BSD
extends RefCounted
# Shared preview/bake orchestration. All field, road and lot searches are native.
# Derived plans contain plain values; prefab Resources are reconstructed from recipes.
const VERSION:=9
const CACHE_BYTES:=64*1024*1024
const CACHE_ENTRIES:=32
const LIMIT:=8*1024*1024
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Planner=preload("res://addons/structures/terrain_lot_planner.gd")
const Market=preload("res://addons/structures/central_market.gd")
const Lots=preload("res://addons/structures/northern_lots.gd")
const Survey=preload("res://addons/world_runtime/survey_cache.gd")
static func path_for(seed_value:int,generator:int,market:bool,connection:bool,folder:String)->String:
 return folder.path_join("plan_%d_%d_%d_%d_%d.bin"%[VERSION,seed_value,generator,int(market),int(connection)])
static func without_assets(plan:Dictionary)->Dictionary:
 var packed:Dictionary=plan.duplicate(true)
 for site:String in ["plan","market"]:
  for lot:Dictionary in packed[site].get("lots",[]):lot.erase("asset")
 return packed
static func attach_assets(result:Dictionary)->bool:
 for site:String in ["plan","market"]:
  var plan:Dictionary=result.get(site,{})
  if plan.is_empty():continue
  if not plan.has("center") or not plan.has("lots"):return false
  var recipe:Array=Lots.recipe(plan.center,true) if site=="plan" else Market.recipe(plan.center)
  if recipe.size()!=plan.lots.size():return false
  var variant:int=plan.get("variant",0)
  for i in plan.lots.size():plan.lots[i].asset=recipe[(i+variant)%recipe.size()].asset
 return true
static func read_plan(path:String,seed_value:int,generator:int,market:bool,connection:bool)->Dictionary:
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()<40 or file.get_length()>LIMIT:return {}
 var expected:=file.get_buffer(32);var bytes:=file.get_buffer(file.get_length()-32)
 if Survey.digest(bytes)!=expected:return {}
 var decoded=bytes_to_var(bytes) # Objects are deliberately disabled.
 if not decoded is Dictionary:return {}
 if decoded.get("version")!=VERSION or decoded.get("seed")!=seed_value or decoded.get("generator")!=generator or decoded.get("with_market")!=market or decoded.get("with_connection")!=connection:return {}
 if not decoded.get("ok",false) or not decoded.has("works") or not decoded.has("connection") or not attach_assets(decoded):return {}
 decoded["plan_digest"]=expected.hex_encode()
 return decoded
static func trim_cache(folder:String,keep:String)->void:
 # Only regenerable files in this dedicated cache; never canonical world storage.
 var entries:Array=[];var total:=0
 var pattern:=RegEx.new();pattern.compile("^(plan_[0-9]+_[0-9]+_[0-9]+_[01]_[01]|recipe_[0-9]+_[0-9a-f]{64})\\.bin$")
 for name:String in DirAccess.get_files_at(folder):
  if pattern.search(name)==null:continue
  var path:=folder.path_join(name);var file:=FileAccess.open(path,FileAccess.READ)
  if file==null:continue
  var size:int=file.get_length();file.close();total+=size
  entries.append({"path":path,"size":size,"time":FileAccess.get_modified_time(path)})
 entries.sort_custom(func(a:Dictionary,b:Dictionary):return a.time<b.time if a.time!=b.time else a.path<b.path)
 var count:=entries.size()
 for entry:Dictionary in entries:
  if count<=CACHE_ENTRIES and total<=CACHE_BYTES:break
  if entry.path==keep:continue
  if DirAccess.remove_absolute(entry.path)==OK:count-=1;total-=entry.size
static func build(seed_value:int,generator:int,with_market:bool=true,with_connection:bool=true,folder:String="user://generation_plans",options:Dictionary={},progress:RefCounted=null)->Dictionary:
 if not options.is_empty():
  var result:=preload("res://addons/world_runtime/custom_world_plan.gd").build(seed_value,generator,options,folder,0,progress)
  if result.get("cache_persisted",false):trim_cache(folder,str(result.get("cache_path","")))
  result.erase("cache_path")
  return result
 var started:=Time.get_ticks_usec()
 if seed_value<0 or seed_value>2147483647 or generator not in [17,18,19,20,21,22,23]:return {"ok":false,"reason":"Unsupported generation settings"}
 with_connection=with_connection or with_market
 var path:=path_for(seed_value,generator,with_market,with_connection,folder)
 var cached:=read_plan(path,seed_value,generator,with_market,with_connection)
 if not cached.is_empty():
  cached["cache_hit"]=true;cached["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
  return cached
 var core=ClassDB.instantiate("TerrainCore")
 if core==null or not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {"ok":false,"reason":"Native world initialization failed"}
 var stage_started:=Time.get_ticks_usec()
 var timings:Dictionary={}
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,16)
 var plan:Dictionary=Planner.locate(core,layout.sites[3].position)
 if not plan.ok:return plan
 timings["northern_plan_ms"]=(Time.get_ticks_usec()-stage_started)/1000.0
 stage_started=Time.get_ticks_usec()
 var works:Dictionary=Planner.earthworks(plan)
 if not works.ok:return works
 timings["northern_earthworks_ms"]=(Time.get_ticks_usec()-stage_started)/1000.0
 var market:Dictionary={};var connection:Dictionary={}
 if with_market:
  stage_started=Time.get_ticks_usec()
  market=Market.locate(core,layout.sites[0].position,works.bounds)
  if not market.ok:return market
  var market_works:=Planner.earthworks(market)
  if not market_works.ok:return market_works
  works.segments.append_array(market_works.segments);works.bounds=works.bounds.merge(market_works.bounds)
 if with_market:timings["market_plan_and_earthworks_ms"]=(Time.get_ticks_usec()-stage_started)/1000.0
 if with_connection:
  stage_started=Time.get_ticks_usec()
  connection=preload("res://addons/structures/regional_route_planner.gd").central_connection(core,plan,layout,market)
  if not connection.ok:return connection
  works.segments=connection.segments+works.segments;works.bounds=works.bounds.merge(connection.bounds)
 if with_connection:timings["regional_route_ms"]=(Time.get_ticks_usec()-stage_started)/1000.0
 var result:Dictionary={"ok":true,"version":VERSION,"seed":seed_value,"generator":generator,"with_market":with_market,"with_connection":with_connection,"plan":plan,"market":market,"connection":connection,"works":works}
 var bytes:=var_to_bytes(without_assets(result));var checksum:=Survey.digest(bytes)
 result["plan_digest"]=checksum.hex_encode();result["cache_hit"]=false;result["cache_persisted"]=false
 if bytes.size()+32<=LIMIT:
  DirAccess.make_dir_recursive_absolute(folder)
  var temporary:=path+".tmp_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
  var file:=FileAccess.open(temporary,FileAccess.WRITE)
  if file!=null:
   file.store_buffer(checksum);file.store_buffer(bytes);file.close()
   if not read_plan(temporary,seed_value,generator,with_market,with_connection).is_empty():result.cache_persisted=DirAccess.rename_absolute(temporary,path)==OK
   if FileAccess.file_exists(temporary):DirAccess.remove_absolute(temporary)
 if result.cache_persisted:trim_cache(folder,path)
 result["timings"]=timings
 result["worker_ms"]=(Time.get_ticks_usec()-started)/1000.0
 return result
static func water_preview(core,generator:int)->PackedByteArray:
 # Reuse the runtime's native implicit-ocean source, visibility and rasterizer.
 # No resident water regions, meshes or scene nodes are created for this preview.
 var water=ClassDB.instantiate("NativeRegionalWater")
 water.set_surrounding_ocean(generator in [19,21,23])
 var raster=ClassDB.instantiate("NativeSurfaceMapRaster")
 var cursor:=0
 while generator in [19,21,23] and cursor<512*512:
  var source:Dictionary=water.survey_ocean(cursor,water.survey_revision_id())
  if not source.get("ok",false) or source.cursor<=cursor or not raster.offer(source.points):return PackedByteArray()
  cursor=source.cursor
 var definitions:=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,generator)
 if not definitions.get("ok",false):return PackedByteArray()
 var inland:Dictionary=core.survey_generated_lake_surfaces(definitions.records)
 if not inland.get("ok",false):return PackedByteArray()
 var points:PackedVector3Array=inland.points
 for first in range(0,points.size(),256):
  if not raster.offer(points.slice(first,mini(first+256,points.size()))):return PackedByteArray()
 var offset:=0
 while offset<raster.count():
  var visibility:Dictionary=core.survey_water_visibility(raster.batch(offset,256))
  if not visibility.get("ok",false) or visibility.visible.is_empty() or not raster.accept_prefix(offset,visibility.visible):return PackedByteArray()
  offset+=visibility.visible.size()
 return raster.pixels(Color(54/255.0,117/255.0,140/255.0))
static func preview(seed_value:int,generator:int,integrated:bool=true,with_market:bool=true,with_connection:bool=true,preview_folder:String="user://cartography/generation",options:Dictionary={},progress:RefCounted=null)->Dictionary:
 if progress!=null:progress.record("Surveying terrain heights and coastlines",0,0,"Native 256 × 256 overview / binary terrain cache")
 var terrain:=Survey.build(seed_value,generator)
 if not terrain.get("ok",false):return terrain
 if not integrated or generator not in [17,18,19,20,21,22,23]:return terrain
 var plan:=build(seed_value,generator,with_market,with_connection,"user://generation_plans",options,progress)
 if not plan.get("ok",false):return plan
 if progress!=null:progress.record("Compositing the actual regional plan",0,0,"Terrain grades, water surfaces, vegetation biome, roads and buildings")
 var sites:Array=plan.get("sites",[plan.plan,plan.market])
 var roads:Array=plan.connection.get("segments",[]).duplicate()
 for site:Dictionary in sites:roads.append_array(site.get("roads",[]))
 var bounds:Array=[]
 for site:Dictionary in sites:
  for lot:Dictionary in site.get("lots",[]):bounds.append(lot.bounds)
 var core=ClassDB.instantiate("TerrainCore")
 var suffix:="template_release" if core.build_variant()=="template_release" else "template_debug"
 var library:="res://addons/volumetric_terrain/bin/terrain_core.windows.template_release.x86_64.dll" if suffix=="template_release" else "res://addons/volumetric_terrain/bin/terrain_core.windows.x86_64.dll"
 var terrain_binary:=FileAccess.get_sha256(library)
 var water_binary:=FileAccess.get_sha256("res://addons/volumetric_water/bin/volumetric_water.windows.%s.x86_64.dll"%suffix)
 var cache_key:String="generation-preview-v1|"+plan.plan_digest+"|"+terrain_binary+"|"+water_binary
 if not options.is_empty():cache_key+="|"+FileAccess.get_sha256("res://addons/world_runtime/bin/world_runtime.windows.%s.x86_64.dll"%suffix)
 var cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
 var cached:Dictionary=cache.read(cache_key,cache_key,preview_folder) if not terrain_binary.is_empty() and not water_binary.is_empty() else {}
 terrain["preview_cache_hit"]=cached.get("hit",false)
 if cached.get("hit",false):terrain.pixels=cached.pixels
 else:
  if not Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))):return {"ok":false,"reason":"Preview terrain initialization failed"}
  var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(plan.works.segments,plan.get("material_deposits",[]))
  if not core.bake_generated_earthworks(packets).get("ok",false):return {"ok":false,"reason":"Preview earthworks unavailable"}
  var water:=water_preview(core,generator)
  if water.is_empty():return {"ok":false,"reason":"Water preview unavailable"}
  if not options.is_empty():terrain.pixels=preload("res://addons/world_runtime/world_recipe.gd").codec().render_biomes(terrain.pixels,seed_value,options.biome)
  terrain.pixels=core.render_plan_map(terrain.pixels,roads,bounds,water)
  terrain.pixels=preload("res://addons/world_runtime/material_deposits.gd").preview_pixels(terrain.pixels,plan.get("material_deposits",[]))
  if not terrain_binary.is_empty() and not water_binary.is_empty():cache.write(cache_key,cache_key,terrain.pixels,preview_folder,32)
 terrain["plan_digest"]=plan.plan_digest;terrain["building_count"]=bounds.size();terrain["plan_cache_hit"]=plan.cache_hit;terrain["plan_ms"]=plan.worker_ms;terrain["plan_reusable"]=plan.get("cache_hit",false) or plan.get("cache_persisted",false)
 if not options.is_empty():terrain["options"]=options.duplicate();terrain["network"]=plan.network
 return terrain
