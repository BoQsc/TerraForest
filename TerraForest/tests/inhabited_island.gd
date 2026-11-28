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
func legacy_samples()->Dictionary:
 var output:Dictionary={};var points:=PackedVector3Array()
 for z in range(0,2001,40):
  for x in range(0,2001,40):points.append(Vector3(x,0,z))
 var batch:RefCounted=ClassDB.instantiate("NativeGenerationEarthworks")
 for generator:int in [1,19,33,35]:
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
 if "--legacy-reference" in OS.get_cmdline_user_args():
  var file:=FileAccess.open(folder.path_join("legacy.json"),FileAccess.WRITE);file.store_string(JSON.stringify(legacy_samples()));file.close();finish();return
 var reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/island_legacy_terrain.json")).hashes
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--legacy-reference-file="):reference=JSON.parse_string(FileAccess.get_file_as_string(argument.trim_prefix("--legacy-reference-file=")))
 check(legacy_samples()==reference,"new island leaves all twelve legacy terrain lattices byte-identical")
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
 check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,36]))),"new immutable island terrain admitted")
 var points:=PackedVector3Array()
 for t in range(0,2001,40):points.append(Vector3(t,0,0));points.append(Vector3(t,0,2000));points.append(Vector3(0,0,t));points.append(Vector3(2000,0,t))
 var heights:PackedFloat32Array=ClassDB.instantiate("NativeGenerationEarthworks").heights(core,points)
 var submerged:=heights.size()==points.size()
 for value in heights:submerged=submerged and value<40
 check(submerged,"all island boundaries are below the surrounding sea")
 if "--preview-only" in OS.get_cmdline_user_args():
  var preview:Dictionary=load("res://addons/world_runtime/world_generation_plan.gd").preview(seed_value,36,true,true,true,folder.path_join("surface_cache"),Recipe.INHABITED_ISLAND)
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
func finish()->void:
 print("INHABITED_ISLAND checks=",checks," failures=",failures)
 quit(1 if failures else 0)
