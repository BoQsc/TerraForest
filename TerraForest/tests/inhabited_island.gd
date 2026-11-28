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
 for generator:int in [1,19,33,35,36,37]:
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
 if "--compare-plans" in OS.get_cmdline_user_args():compare_plans();finish();return
 if "--cold-native-probe" in OS.get_cmdline_user_args():cold_native_probe();finish();return
 if "--lake-margin-probe" in OS.get_cmdline_user_args():lake_margin_probe();finish();return
 if "--bake-lakes-only" in OS.get_cmdline_user_args():water_checks();finish();return
 if "--legacy-reference" in OS.get_cmdline_user_args():
  var file:=FileAccess.open(folder.path_join("legacy.json"),FileAccess.WRITE);file.store_string(JSON.stringify(legacy_samples()));file.close();finish();return
 var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/island_legacy_terrain.json")).hashes
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--legacy-reference-file="):reference=JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--legacy-reference-file=")))
 check(legacy_samples()==reference,"new island leaves all eighteen legacy terrain lattices byte-identical")
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
 check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,38]))),"new immutable island terrain admitted")
 var points:=PackedVector3Array()
 for t in range(0,2001,40):points.append(Vector3(t,0,0));points.append(Vector3(t,0,2000));points.append(Vector3(0,0,t));points.append(Vector3(2000,0,t))
 var heights:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(core,points)
 var submerged:=heights.size()==points.size()
 for value in heights:submerged=submerged and value<40
 check(submerged,"all island boundaries are below the surrounding sea")
 water_checks()
 if "--preview-only" in OS.get_cmdline_user_args():
  var preview:Dictionary=load("res://addons/world_runtime/world_generation_plan.gd").preview(seed_value,38,true,true,true,folder.path_join("surface_cache"),Recipe.INHABITED_ISLAND)
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
  water_core.execute(Codec.command(6,[water_seed,38]))
  var definitions:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(water_core,38)
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

func lake_margin_probe()->void:
 # Diagnostic-only sampling and image presentation, never runtime generation.
 var generator:=37
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--shore-generator="):generator=int(arg.trim_prefix("--shore-generator="))
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,generator]))),"shore probe native field admitted")
 var records:Dictionary=preload("res://addons/volumetric_terrain/generated_lakes.gd").describe(core,generator)
 var audit:Dictionary=core.survey_generated_lake_surfaces(records.records)
 var meta:Array=[]
 for index in 3:
  var center:Vector3=audit.lakes[index].center
  var origin:=center-Vector3(320,0,320);var points:=PackedVector3Array()
  for z in 321:
   for x in 321:points.append(origin+Vector3(x*2,0,z*2))
  var start:=Time.get_ticks_usec()
  var heights:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(core,points)
  check(heights.size()==points.size(),"complete native lake grid "+str(index))
  var elapsed:=Time.get_ticks_usec()-start
  for arg:String in OS.get_cmdline_user_args():
   if arg.begins_with("--shore-reference="):
    var reference:PackedByteArray=FileAccess.get_file_as_bytes(arg.trim_prefix("--shore-reference=").path_join("lake_%d_heights.bin"%index))
    check(heights.to_byte_array()==reference,"indexed native shore samples remain byte-identical "+str(index))
  FileAccess.open(folder.path_join("lake_%d_heights.bin"%index),FileAccess.WRITE).store_buffer(heights.to_byte_array())
  var image:=Image.create(321,321,false,Image.FORMAT_RGB8)
  for z in 321:
   for x in 321:
    var at:=x+z*321;var h:float=heights[at]
    var dx:float=heights[mini(x+1,320)+z*321]-heights[maxi(x-1,0)+z*321]
    var dz:float=heights[x+mini(z+1,320)*321]-heights[x+maxi(z-1,0)*321]
    var light:=clampf(.8+(dx+dz)*.07,.25,1.2)
    var color:=Color(.13,.41,.55) if h<center.y else Color(.4,.55,.24)*light
    image.set_pixel(x,z,color)
  image.save_png(folder.path_join("lake_%d_native_field.png"%index))
  if index==2:
   var sections:Array=[]
   for section:Dictionary in records.records:
    if absf(section.level-center.y)<.001 and Vector2(section.seed.x-center.x,section.seed.z-center.z).length()<400:sections.append(section)
   var catalog:PackedByteArray=ClassDB.instantiate("NativeLakeCatalog").encode(sections)
   var baked:Dictionary=ClassDB.instantiate("NativeGeneratedLakeBake").run(core,catalog,core.execute(Codec.command(0)).decode_u32(12),core.execute(Codec.command(13)).decode_u32(12),30000,true)
   check(baked.get("ok",false),"diagnostic physical lake bake")
   if baked.get("ok",false):
    var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
    check(water.restore_snapshot(baked.snapshot),"diagnostic native water restored")
    var wet_points:=0;var dry_field_water:=0;var missing:=0;var deep_missing:Array=[]
    var bounds:=AABB(sections[0].origin,Vector3(sections[0].cells)*sections[0].spacing)
    for section:Dictionary in sections:bounds=bounds.merge(AABB(section.origin,Vector3(section.cells)*section.spacing))
    for z in 321:
     for x in 321:
      var point:Vector3=points[x+z*321];point.y=center.y-.05
      var wet:bool=water.depth_at(point)>.001
      if wet:wet_points+=1
      if wet and heights[x+z*321]>center.y+.05:dry_field_water+=1
      if wet:image.set_pixel(x,z,Color(.08,.35,.8))
      elif heights[x+z*321]<center.y:image.set_pixel(x,z,Color(.8,.3,.2));missing+=1
      if not wet and bounds.has_point(point) and heights[x+z*321]<center.y-.65 and deep_missing.size()<2048:deep_missing.append([point.x,point.z,heights[x+z*321]])
    image.save_png(folder.path_join("lake_2_physical_water.png"))
    baked.erase("snapshot");baked["wet_points"]=wet_points;baked["dry_field_water"]=dry_field_water;baked["missing_field_points"]=missing
    baked["deep_missing_inside_catalog"]=deep_missing;baked["probe_below_level_m"]=.05
    if generator==38:check(deep_missing.is_empty() and int(baked.get("guide_seeds",0))>0,"all deep curved arms fill across native catalog sections")
    elif generator==37 and seed_value==1703:check(not deep_missing.is_empty(),"legacy single-source section reproduces the clipped inner arm")
    FileAccess.open(folder.path_join("lake_2_physical.json"),FileAccess.WRITE).store_string(JSON.stringify(baked,"  "))
  meta.append({"lake":index,"generator":generator,"seed":seed_value,"origin":[origin.x,origin.z],"water_level":center.y,"size":321,"spacing_m":2,"native_us":elapsed,"audit":audit.lakes[index]})
 FileAccess.open(folder.path_join("shore_field.json"),FileAccess.WRITE).store_string(JSON.stringify(meta,"  "))
 if generator==38 and seed_value==1703:
  # Fine finite differences across the observed inner-bank guide join. A broad
  # slope is intentional; a metre-scale height jump at a guide switch is not.
  var probes:=PackedVector3Array()
  for z in 81:
   for x in 81:probes.append(Vector3(1684+x*.25,0,1394+z*.25))
  var field:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(core,probes)
  var bend:=0.0;var step_height:=0.0
  for z in range(1,80):
   for x in range(1,80):
    var at:=x+z*81
    for offset in [1,81]:
     bend=maxf(bend,absf(field[at-offset]-2*field[at]+field[at+offset]))
     step_height=maxf(step_height,absf(field[at+offset]-field[at]))
  check(bend<.3,"dry bank joins contain no guide-switch height steps")
  FileAccess.open(folder.path_join("shore_continuity.json"),FileAccess.WRITE).store_string(JSON.stringify({"spacing_m":.25,"samples":field.size(),"maximum_second_difference_m":bend,"maximum_adjacent_height_m":step_height,"bounds":[1684,1394,1704,1414]},"  "))

func reference_canonical(value:Variant)->Variant:
 if value is Dictionary:
  var result:Dictionary={};var keys:Array=value.keys();keys.sort_custom(func(a,b):return str(a)<str(b))
  for key in keys:result[reference_canonical(key)]=reference_canonical(value[key])
  return result
 if value is Array:
  var result:Array=[]
  for item in value:result.append(reference_canonical(item))
  return result
 return str(value) if value is StringName else value
func cold_native_probe()->void:
 var core:RefCounted=ClassDB.instantiate("TerrainCore")
 var batch:RefCounted=ClassDB.instantiate("NativeGenerationEarthworks")
 var points:=PackedVector3Array()
 for z in range(1280,1345):
  for x in range(1536,1601):points.append(Vector3(x+.125,0,z+.375))
 var timings:Array=[]
 for generator:int in [19,36,37,38]:
  for seed_number:int in [1703,901,1703]:
   core.execute(Codec.command(6,[seed_number,generator]))
   core.configure_height_cache(false)
   var began:=Time.get_ticks_usec();var expected:PackedFloat32Array=batch.heights(core,points);var uncached:=Time.get_ticks_usec()-began
   core.configure_height_cache(true);began=Time.get_ticks_usec()
   var first:PackedFloat32Array=batch.heights(core,points);var second:PackedFloat32Array=batch.heights(core,points)
   var cached:=Time.get_ticks_usec()-began
   check(expected.to_byte_array()==first.to_byte_array() and expected.to_byte_array()==second.to_byte_array(),"exact native height reuse across seed/profile changes %d/%d"%[generator,seed_number])
   timings.append({"generator":generator,"seed":seed_number,"samples":points.size(),"uncached_us":uncached,"cold_and_reused_us":cached})
 for generator:int in [36,37,38]:
  core.execute(Codec.command(6,[1703,generator]))
  core.configure_height_cache(false) # Reader equivalence must not borrow authority cache hits.
  var revision:int=core.field_patch_state().revision;var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
  for origin:Vector2i in [Vector2i(624,480),Vector2i(1456,640),Vector2i(1584,1328)]:
   var surface:PackedFloat32Array=batch.heights(core,PackedVector3Array([Vector3(origin.x,0,origin.y)]))
   var reader:RefCounted=core.capture_edit_field(Rect2i(origin-Vector2i(8,8),Vector2i(32,32)),revision,epoch)
   var packet:=Codec.command(43,[revision,epoch,origin.x,floori(surface[0]/4)*4,origin.y])
   var expected:PackedByteArray=core.execute(packet)
   check(reader!=null and Codec.reply_ok(expected) and reader.execute(packet)==expected,"sealed native reader preserves island ridge/lake contacts %d/%s"%[generator,origin])
 var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
 asset.configure(PackedInt32Array([0,0,0,1,1,0,0,65]));asset.set_meta("z",{&"nested":[&"name",{"b":2,"a":1}]});asset.set_meta("a",Vector3(1,2,3))
 var metadata:Array=[];var keys:=PackedStringArray(asset.get_meta_list());keys.sort()
 for key:String in keys:metadata.append([key,asset.get_meta(key)])
 var fields:Array=[asset.get_records(),asset.get_model_attachments(),metadata]
 var expected:PackedByteArray=var_to_bytes(reference_canonical(fields))
 var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256);hash.update(expected)
 check(var_to_bytes(batch.canonical_value(fields))==expected and batch.prefab_fingerprint(asset)==hash.finish().hex_encode(),"native planning fingerprint preserves prior canonical bytes and metadata")
 asset.set_meta("a",Vector3(1,3,3));check(batch.prefab_fingerprint(asset)!=preload("res://addons/world_runtime/survey_cache.gd").digest(expected).hex_encode(),"planning metadata changes invalidate native fingerprint")
 FileAccess.open(folder.path_join("cold_native_probe.json"),FileAccess.WRITE).store_string(JSON.stringify(timings,"  "))
func compare_plans()->void:
 var paths:PackedStringArray=[]
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--plan-before="):paths.insert(0,argument.trim_prefix("--plan-before="))
  if argument.begins_with("--plan-after="):paths.append(argument.trim_prefix("--plan-after="))
 if not check_plan_paths(paths):return
 var plans:Array=[]
 for path:String in paths:
  var bytes:=FileAccess.get_file_as_bytes(path)
  var valid:bool=bytes.size()>32 and preload("res://addons/world_runtime/survey_cache.gd").digest(bytes.slice(32))==bytes.slice(0,32)
  check(valid,"compiled plan checksum verified")
  if not valid:return
  var plan:Dictionary=bytes_to_var(bytes.slice(32))
  plan.erase("recipe_key") # Native-library identity deliberately changes.
  for section:String in ["exploration","watchtowers"]:
   if plan.has(section):plan[section].erase("worker_ms")
  plans.append(plan)
 var differences:Array=[]
 for key in plans[0]:
  if not plans[1].has(key) or var_to_bytes(plans[0][key])!=var_to_bytes(plans[1][key]):differences.append(key)
 for key in plans[1]:
  if not plans[0].has(key):differences.append(key)
 check(differences.is_empty(),"complete cold-plan payload unchanged apart from native identity and observation timings")
 FileAccess.open(folder.path_join("plan_equivalence.json"),FileAccess.WRITE).store_string(JSON.stringify({"paths":paths,"differences":differences},"  "))
func check_plan_paths(paths:PackedStringArray)->bool:
 var valid:=paths.size()==2
 for path:String in paths:valid=valid and FileAccess.file_exists(path)
 check(valid,"both retained compiled plans available")
 return valid
func finish()->void:
 print("INHABITED_ISLAND checks=",checks," failures=",failures)
 quit(1 if failures else 0)
