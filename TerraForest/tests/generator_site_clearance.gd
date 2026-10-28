extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func run()->void:
 var options:=Recipe.DEFAULTS.duplicate();options.biome=2;options.settlements=3;options.districts=3;options.network=2;options.trails=2
 var folder:="user://generator_clearance_"+Crypto.new().generate_random_bytes(6).hex_encode()
 var worker:=Thread.new();worker.start(preload("res://addons/world_runtime/world_generation_plan.gd").build.bind(1703,22,true,true,folder,options))
 while worker.is_alive():await process_frame
 var plan:Dictionary=worker.wait_to_finish()
 if not plan.get("ok",false):print("FAIL ",plan);quit(1);return
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,22]))
 var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(plan.works.segments,plan.material_deposits)
 worker=Thread.new();worker.start(core.bake_generated_earthworks_staged.bind(packets,ProjectSettings.globalize_path(folder+"/bake")))
 while worker.is_alive():await process_frame
 var baked:Dictionary=worker.wait_to_finish()
 if not baked.get("ok",false):print("FAIL ",baked);quit(1);return
 var violations:Array=[];var count:=0
 for site:Dictionary in plan.sites:
  for lot:Dictionary in site.lots:
   count+=1
   for offset in range(0,lot.asset.clearance_sample_count(),512):
    var points:PackedVector3Array=lot.asset.clearance_samples(lot.origin,lot.rotation,offset,512,int(lot.asset.get_meta("site_sample_band",0)))
    var query:=Codec.command(31,[baked.revision,points.size()]);query.append_array(points.to_byte_array())
    var reply:PackedByteArray=core.execute(query)
    if not Codec.reply_ok(reply):print("FAIL clearance query");quit(1);return
    for index in points.size():
     var density:=reply.decode_float(20+index*4)
     if density>=0:continue
     if violations.size()<48:violations.append({"town":site.town,"district":site.district,"lot":lot.label,"origin":lot.origin,"rotation":lot.rotation,"point":points[index],"density":density})
     failures+=1
 var report:={"failures":failures,"buildings":count,"violations":violations}
 DirAccess.make_dir_recursive_absolute("res://reports/generator_options")
 FileAccess.open("res://reports/generator_options/clearance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("GENERATOR_SITE_CLEARANCE ",JSON.stringify(report));quit(1 if failures else 0)
