extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Lakes=preload("res://addons/volumetric_terrain/generated_lakes.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var failures:=0
var checks:=0
const FOLDER:="res://reports/distributed_generation"
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
 checks+=1
 if not value:failures+=1
 print("PASS " if value else "FAIL ",message)
func field_signature(core:RefCounted)->String:
 var points:=PackedVector3Array()
 for depth in range(12,1999,64):
  for across in range(12,1999,64):points.append(Vector3(across,0,depth))
 var data:=PackedByteArray()
 for start in range(0,points.size(),256):
  var batch:=points.slice(start,mini(start+256,points.size()))
  var command:=Codec.command(37,[batch.size()]);command.append_array(batch.to_byte_array())
  data.append_array(core.execute(command))
 data.append_array(core.execute(Codec.command(27)))
 data.append_array(core.execute(Codec.command(25)))
 return preload("res://addons/world_runtime/survey_cache.gd").digest(data).hex_encode()
func run()->void:
 DirAccess.make_dir_recursive_absolute(FOLDER)
 var baseline:bool="--baseline" in OS.get_cmdline_user_args()
 var fields:Dictionary={};var reports:Array=[]
 for seed_value in [0,42,1703]:
  for generator in [17,19,20,21,22,23]:
   var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
   fields["%d/%d"%[seed_value,generator]]=field_signature(core)
 if baseline:
  FileAccess.open(FOLDER+"/legacy.json",FileAccess.WRITE).store_string(JSON.stringify(fields))
  print("DISTRIBUTED_BASELINE failures=0");quit();return
 check(fields==JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/distributed_legacy.json")),"18 legacy fields and lake/cave definitions remain byte-identical")
 for seed_value in [0,42,1703]:
  for generator in [24,25,26,27]:
   var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,generator]))
   var lakes:=Lakes.describe(core,generator)
   check(lakes.get("ok",false) and lakes.records.size()>=10,"distributed lakes seed=%d generator=%d count=%d"%[seed_value,generator,lakes.get("records",[]).size()])
   var catalog=ClassDB.instantiate("NativeLakeCatalog")
   var encoded:PackedByteArray=catalog.encode(lakes.records)
   check(not encoded.is_empty() and catalog.decode(encoded).records.size()==lakes.records.size(),"all lake identities survive binary catalog admission")
   var quadrants:Dictionary={}
   for lake:Dictionary in lakes.get("records",[]):quadrants[Vector2i(int(lake.seed.x)/1000,int(lake.seed.z)/1000)]=true
   check(quadrants.size()==4,"lakes cover every quadrant")
   var survey:Dictionary=core.survey_generated_lake_surfaces(lakes.records)
   check(survey.get("ok",false) and not survey.points.is_empty(),"every generated lake catalog supports native map survey")
   var offset:=0;var calls:=0;var started:=Time.get_ticks_usec()
   while offset<survey.points.size():
    var reply:Dictionary=core.survey_water_visibility(survey.points.slice(offset,mini(offset+256,survey.points.size())))
    if not reply.get("ok",false) or reply.visible.is_empty():failures+=1;break
    offset+=reply.visible.size();calls+=1
   reports.append({"seed":seed_value,"generator":generator,"lakes":lakes.records.size(),"points":offset,"visibility_calls":calls,"visibility_ms":(Time.get_ticks_usec()-started)/1000.0})
 if "--fields-only" not in OS.get_cmdline_user_args():
  var cache:="user://distributed_check_"+Crypto.new().generate_random_bytes(6).hex_encode()
  for seed_value in [0,42,1703]:
   var options:=Recipe.DEFAULTS.duplicate();options.settlements=3;options.network=1
   var worker:=Thread.new();worker.start(Plan.build.bind(seed_value,24,true,true,cache,options))
   while worker.is_alive():await process_frame
   var plan:Dictionary=worker.wait_to_finish()
   check(plan.get("ok",false),"distributed three-town plan seed=%d: %s"%[seed_value,plan.get("reason","ok")])
   if not plan.get("ok",false):reports.append({"seed":seed_value,"failure":plan});continue
   var low:=Vector3(2000,0,2000);var high:=Vector3.ZERO
   for site:Dictionary in plan.sites:low=low.min(site.center);high=high.max(site.center)
   check(high.z-low.z>950 and high.x-low.x>450,"towns span the region rather than center cluster")
   check(plan.network.road_length_m>1800,"regional roads traverse over 1.8 km")
   var warm:=Plan.build(seed_value,24,true,true,cache,options)
   check(warm.get("cache_hit",false) and warm.plan_digest==plan.plan_digest,"cached distributed plan is deterministic")
   reports.append({"seed":seed_value,"sites":plan.sites.map(func(site:Dictionary):return site.center),"roads_m":plan.network.road_length_m,"cold_ms":plan.worker_ms,"warm_ms":warm.worker_ms})
 FileAccess.open(FOLDER+"/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"reports":reports},"  "))
 print("DISTRIBUTED_GENERATION checks=",checks," failures=",failures);quit(1 if failures else 0)
