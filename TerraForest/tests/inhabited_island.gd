# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
var failures:=0
var checks:=0
var folder:=""
var seed_value:=1703
func _initialize()->void:
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):folder=argument.trim_prefix("--check-evidence-dir=")
  if argument.begins_with("--seed="):seed_value=int(argument.trim_prefix("--seed="))
 run.call_deferred()
func check(value:bool,label:String)->void:
 checks+=1
 if not value:failures+=1
 print("PASS " if value else "FAIL ",label)
func wet_records(snapshot:PackedByteArray)->Dictionary:
 var result:Dictionary={}
 if snapshot.size()<32 or snapshot.decode_u32(4)!=13:return result
 var start:=32+snapshot.decode_u32(8)
 for index in snapshot.decode_u32(12):
  var at:=start+index*9076;var wet:=false
  for cell in 512:
   if snapshot.decode_u64(at+20+cell*12)>0:wet=true;break
  if wet:result[snapshot.decode_u64(at)]=snapshot.slice(at,at+9076)
 return result
func legacy_samples()->Dictionary:
 var output:Dictionary={};var points:=PackedVector3Array()
 for z in range(0,2001,40):
  for x in range(0,2001,40):points.append(Vector3(x,0,z))
 var batch:RefCounted=ClassDB.instantiate("NativeGenerationEarthworks")
 for generator:int in [1,19,33,35,36]:
  for seed_number:int in [0,1703,901]:
   var core:RefCounted=ClassDB.instantiate("TerrainCore")
   check(Codec.reply_ok(core.execute(Codec.command(6,[seed_number,generator]))),"legacy field admitted %d/%d"%[generator,seed_number])
   var heights:PackedFloat32Array=batch.heights(core,points)
   check(heights.size()==points.size(),"legacy lattice sampled completely")
   var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(heights.to_byte_array())
   output["%d/%d"%[generator,seed_number]]=hash.finish().hex_encode()
 return output
func run()->void:
 if folder.is_empty():quit(2);return
 if "--bake-lakes-only" in OS.get_cmdline_user_args():water_checks();finish();return
 if "--legacy-reference" in OS.get_cmdline_user_args():
  var file:=FileAccess.open(folder.path_join("legacy.json"),FileAccess.WRITE);file.store_string(JSON.stringify(legacy_samples()));file.close();finish();return
 var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/island_legacy_terrain.json")).hashes
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--legacy-reference-file="):reference=JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--legacy-reference-file=")))
 check(legacy_samples()==reference,"new island leaves all fifteen legacy terrain lattices byte-identical")
 var codec:=Recipe.codec();var bytes:=Recipe.encode(Recipe.INHABITED_ISLAND)
 check(bytes.size()==44 and bytes.decode_u32(4)==9 and codec.decode(bytes)==Recipe.INHABITED_ISLAND,"native version-9 recipe round trip")
 var old:=Recipe.encode(Recipe.METROPOLIS)
 check(old.size()==44 and old.decode_u32(4)==8 and codec.decode(old)==Recipe.METROPOLIS,"metropolis version-8 recipe preserved")
 for offset in range(0,44,4):
  var bad:=bytes.duplicate();bad.encode_u32(offset,0xffffffff)
  check(not codec.validate_snapshot(bad),"corrupt island field rejected "+str(offset))
 var plan:Dictionary=codec.island_layout(seed_value)
 check(plan==codec.island_layout(seed_value) and plan!=codec.island_layout(seed_value+1),"seeded district hierarchy is reproducible and varies")
 check(plan.parts==PackedInt32Array([4,4,4,4,4,1,1,1,1]),"one city, two towns and four smaller communities")
 check(plan.hints[3].distance_to(plan.hints[4])>1200,"town preferences are geographically distant")
 var metro=load("res://addons/structures/metropolis_catalog.gd")
 var total:=0
 for district in 9:
  var assets:Array=metro.sources(district,2);total+=assets.size()
  check(assets.size()==(12 if district<3 else 16 if district<5 else 4),"reusable district building count "+str(district))
 check(total==84,"native composition retains 84 buildings")
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,37]))),"new immutable island terrain admitted")
 var points:=PackedVector3Array()
 for t in range(0,2001,40):points.append(Vector3(t,0,0));points.append(Vector3(t,0,2000));points.append(Vector3(0,0,t));points.append(Vector3(2000,0,t))
 var heights:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(core,points)
 var submerged:=heights.size()==points.size()
 for value in heights:submerged=submerged and value<40
 check(submerged,"all island boundaries are below the surrounding sea")
 water_checks()
 if "--preview-only" in OS.get_cmdline_user_args():
  var preview:Dictionary=load("res://addons/world_runtime/world_generation_plan.gd").preview(seed_value,37,true,true,true,folder.path_join("surface_cache"),Recipe.INHABITED_ISLAND)
  check(preview.get("ok",false) and preview.get("building_count",0)==86,"ordinary preview resolves the complete island recipe")
  if preview.get("ok",false):
   check(Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,preview.pixels).save_png(folder.path_join("preview.png"))==OK,"bounded island preview image retained")
 if "--locate-only" in OS.get_cmdline_user_args():
  var progress=load("res://addons/world_runtime/world_plan_progress.gd").new()
  var start:=Time.get_ticks_usec();var result:Dictionary=metro.locate(core,3,0,progress,2,seed_value)
  check(result.get("ok",false),"all island settlement blocks fit native terrain and connect")
  var file:=FileAccess.open(folder.path_join("island_sites.json"),FileAccess.WRITE)
  var rows:Array=[]
  for site:Dictionary in result.get("sites",[]):rows.append({"title":site.title,"role":site.role,"center":site.center,"buildings":site.lots.size()})
  file.store_string(JSON.stringify({"microseconds":Time.get_ticks_usec()-start,"ok":result.get("ok",false),"reason":result.get("reason",""),"sites":rows,"phases":progress.timings()},"  "));file.close()
 finish()
func water_checks()->void:
 var water_rows:Array=[]
 for water_seed:int in [1703,901,42]:
  var water_core:RefCounted=ClassDB.instantiate("TerrainCore")
  water_core.execute(Codec.command(6,[water_seed,37]))
  var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(water_core,37)
  check(definitions.get("ok",false),"refined native lake catalog "+str(water_seed))
  if not definitions.get("ok",false):continue
  check(not ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records).is_empty(),"physical water accepts all curved basin sections")
  var fill_bounds:=true
  for section:Dictionary in definitions.records:
   var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
   fill_bounds=water.begin_fill(AABB(section.origin,Vector3(section.cells)*section.spacing),section.level,section.seed,-1) and fill_bounds
  check(fill_bounds,"every section fits the real half-metre water job budget")
  if water_seed==1703 and "--bake-lakes" in OS.get_cmdline_user_args():
   var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode(definitions.records)
   var control_catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode([definitions.records[0]])
   var revision:int=water_core.execute(Codec.command(0)).decode_u32(12)
   var epoch:int=water_core.execute(Codec.command(13)).decode_u32(12)
   var control:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(water_core,control_catalog,revision,epoch)
   var compact:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(water_core,control_catalog,revision,epoch,60000,true)
   check(control.get("ok",false) and compact.get("ok",false),"matched water compaction control bakes complete")
   if control.get("ok",false) and compact.get("ok",false):
    check(control.water_ml==compact.water_ml and wet_records(control.snapshot)==wet_records(compact.snapshot),"dry-cache compaction preserves every wet region quantity and density byte")
    check(compact.snapshot.size()<control.snapshot.size() and compact.dry_regions_released>0,"dry-cache compaction measurably reduces stored data")
    var original_water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
    var compact_water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
    var same:bool=original_water.restore_snapshot(control.snapshot) and compact_water.restore_snapshot(compact.snapshot)
    var source:Vector3=definitions.records[0].seed
    for x in range(-40,41,8):
     for z in range(-40,41,8):
      var probe:=source+Vector3(x,0,z)
      same=same and absf(original_water.depth_at(probe)-compact_water.depth_at(probe))<=.000001
    check(same,"compacted contact geometry preserves sampled physical depths within one micrometre")
    FileAccess.open(folder.path_join("water_compaction.json"),FileAccess.WRITE).store_string(JSON.stringify({"before_bytes":control.snapshot.size(),"after_bytes":compact.snapshot.size(),"water_ml":compact.water_ml,"released_dry_regions":compact.dry_regions_released,"depth_samples":121,"depth_tolerance_m":.000001},"  "))
   var baked:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(water_core,catalog,water_core.execute(Codec.command(0)).decode_u32(12),water_core.execute(Codec.command(13)).decode_u32(12),60000,true)
   check(baked.get("ok",false),"curved lakes complete the actual static-water bake within existing caps")
   if baked.get("ok",false):
    var restored:RefCounted=ClassDB.instantiate("NativeRegionalWater")
    check(restored.restore_snapshot(baked.snapshot) and restored.total_water_ml()==baked.water_ml,"all compacted lake volumes survive native restoration")
    baked["restored_runtime"]=restored.runtime_state()
    check(baked.restored_runtime.pending_regions==0 and baked.restored_runtime.settling_regions==0,"newly authored water restores without false over-capacity settlement")
   baked.erase("snapshot")
   FileAccess.open(folder.path_join("curved_lake_bake.json"),FileAccess.WRITE).store_string(JSON.stringify(baked,"  "))
  var audit:Dictionary=water_core.survey_generated_lake_surfaces(definitions.records)
  check(audit.get("ok",false) and int(audit.get("extensive_count",0))>=3,"three connected curved lakes exceed 330 m: "+str(water_seed))
  # Equal water elevations can belong to distant lakes. Enclosure must be
  # checked against each adjacent catalog group, never their combined box.
  var groups:Array=[];var assigned:Array=[]
  for first:Dictionary in definitions.records:
   if first.id in assigned:continue
   var bounds:=AABB(first.origin,Vector3(first.cells)*first.spacing);assigned.append(first.id)
   for pass_index in definitions.records.size():
    for section:Dictionary in definitions.records:
     if section.id in assigned or absf(section.level-first.level)>.001:continue
     var candidate:=AABB(section.origin,Vector3(section.cells)*section.spacing)
     if bounds.grow(.01).intersects(candidate):bounds=bounds.merge(candidate);assigned.append(section.id)
   groups.append({"bounds":bounds,"level":first.level})
  var closed:=true
  for point:Vector3 in audit.get("points",PackedVector3Array()):
   var contained:=false
   for group:Dictionary in groups:
    var bounds:AABB=group.bounds
    if absf(point.y-group.level)>.001 or not bounds.has_point(point):continue
    contained=true
    if point.x<=bounds.position.x+2 or point.z<=bounds.position.z+2 or point.x>=bounds.end.x-2 or point.z>=bounds.end.z-2:closed=false
   closed=closed and contained
  check(closed,"curved shores close before physical catalog limits")
  audit.erase("points");audit["seed"]=water_seed;water_rows.append(audit)
 FileAccess.open(folder.path_join("curved_lakes.json"),FileAccess.WRITE).store_string(JSON.stringify(water_rows,"  "))

func finish()->void:
 print("INHABITED_ISLAND checks=",checks," failures=",failures)
 quit(1 if failures else 0)
