extends SceneTree
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const CreationPanel=preload("res://demo/world_creation_panel.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(accepted:bool,message:String)->void:
 checks+=1
 if not accepted:failures+=1
 print("PASS " if accepted else "FAIL ",message)
func run()->void:
 var codec:=Recipe.codec()
 var original:=Recipe.encode(Recipe.DEFAULTS)
 check(original.size()==36 and original.decode_u32(4)==5,"existing default recipe retains exact version-five format")
 var expanded:=Recipe.DEFAULTS.duplicate();expanded.districts=3;expanded.network=2
 var bytes:=Recipe.encode(expanded)
 check(bytes.size()==36 and bytes.decode_u32(4)==6 and codec.decode(bytes)==expanded,"larger districts and road networks roundtrip with separate version-six identity")
 var corrupted:=bytes.duplicate();corrupted.encode_u32(4,5)
 check(not codec.validate_snapshot(corrupted),"new settings cannot masquerade as older recipes")
 for field:String in ["settlements","districts","network","trails"]:
  var invalid:=expanded.duplicate();invalid[field]=10
  check(Recipe.encode(invalid).is_empty(),"bounded admission for "+field)
 var core=ClassDB.instantiate("TerrainCore")
 core.execute(preload("res://addons/volumetric_terrain/mesh_codec.gd").command(6,[1703,23]))
 for mode in [-1,3]:
  check(not core.plan_region_network([PackedVector3Array([Vector3(500,50,500)])],[],mode,0,1703).ok,"invalid native network mode rejected: "+str(mode))
 var oversized:Array=[];oversized.resize(16385)
 check(core.bake_generated_earthworks(oversized).get("reason","")=="Invalid generation command count","native generation retains a hard command budget")
 var folder:="user://generator_options_"+Crypto.new().generate_random_bytes(6).hex_encode()
 var reports:Array=[]
 for style:Dictionary in CreationPanel.STYLES:
  var values:Array=style.values
  var options:=Recipe.DEFAULTS.duplicate()
  options.biome=values[0];options.settlements=values[1]+1;options.districts=values[2]+1;options.network=values[3];options.trails=values[4]
  var generator:=preload("res://demo/world_launch.gd").terrain_generator(values[5],true)
  var worker:=Thread.new();worker.start(Plan.build.bind(1703,generator,true,true,folder,options))
  while worker.is_alive():await process_frame
  var result:Dictionary=worker.wait_to_finish()
  print("GENERATOR_STYLE ",style.name," ",result.get("reason","ok")," ms=",result.get("worker_ms",0))
  check(result.get("ok",false),"real plan fits preset "+style.name)
  if not result.get("ok",false):reports.append({"style":style.name,"error":result});continue
  check(result.sites.size()==options.settlements*options.districts,"all requested districts present: "+style.name)
  var owners:Array=[]
  for index in result.sites.size():owners.append(index)
  for link:Dictionary in result.network.links:
   if link.trail:continue
   var previous:int=owners[link.target];var replacement:int=owners[link.source]
   for index in owners.size():
    if owners[index]==previous:owners[index]=replacement
  check(owners.all(func(owner:int):return owner==owners[0]),"every district connected: "+style.name)
  check(result.network.trail_count<=options.trails*result.sites.size(),"offroads obey per-district budget: "+style.name)
  var warm:=Plan.build(1703,generator,true,true,folder,options)
  check(warm.get("cache_hit",false) and result.plan_digest==warm.plan_digest,"warm plan restores exact expanded layout: "+style.name)
  var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(result.works.segments,result.get("material_deposits",[]))
  check(not packets.is_empty() and packets.size()==result.works.segments.size()+result.get("material_deposits",[]).size(),"entire plan admitted to native generation: "+style.name)
  var region=ClassDB.instantiate("NativeGeneratedRegion")
  var restored=ClassDB.instantiate("NativeGeneratedRegion")
  check(region.set_plan(1703,generator,result.navigation.places,result.navigation.roads) and restored.restore_snapshot(region.capture_snapshot()) and restored.capture_snapshot()==region.capture_snapshot(),"all generated road metadata survives binary storage: "+style.name)
  reports.append({"style":style.name,"buildings":result.building_count,"sites":result.sites.size(),"roads_m":result.network.road_length_m,"trails_m":result.network.trail_length_m,"loops":result.network.loop_count,"ms":result.worker_ms,"packets":packets.size(),"road_fit":result.road_normalization})
 DirAccess.make_dir_recursive_absolute("res://reports/generator_options")
 FileAccess.open("res://reports/generator_options/result.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"plans":reports},"  "))
 print("GENERATOR_RECIPE_OPTIONS checks=",checks," failures=",failures);quit(1 if failures else 0)
