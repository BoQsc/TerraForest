extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Earthworks=preload("res://addons/world_runtime/generation_earthworks.gd")
func _initialize()->void:
 var options:Dictionary=preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS.duplicate()
 options.merge({"settlements":3,"districts":3,"network":2,"trails":2},true)
 var plan:=Plan.build(1703,25,true,true,"user://generation_plans",options)
 if not plan.get("ok",false):print("GENERATED_ROAD_MATERIALS failures=1 plan=",plan);quit(1);return
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,25]))
 var result:Dictionary=core.bake_generated_earthworks(Earthworks.packets(plan.works.segments))
 if not result.get("ok",false):print("GENERATED_ROAD_MATERIALS failures=1 bake=",result);quit(1);return
 var misses:Array=[];var total:=0
 for road:Dictionary in plan.works.segments:
  if int(road.material)!=4:continue
  for fraction:float in [.25,.5,.75]:
   var point:Vector3=road.start.lerp(road.finish,fraction)
   point=Vector3(floorf(point.x)+.01,250,floorf(point.z)+.01)
   var ray:=Codec.decode_density_ray(core.execute(Codec.density_ray_command(point,Vector3(point.x,4,point.z),1024,0)))
   total+=1
   if ray.status!="hit":misses.append({"point":point,"ray":ray});continue
   var hit:Vector3=ray.position-Vector3.UP*.05
   var query:=Codec.point_command(hit);query.encode_u32(0,26)
   var surface:PackedByteArray=core.execute(query)
   if surface.decode_u32(12)!=4:misses.append({"point":hit,"material":surface.decode_u32(12),"road_start":road.start,"road_finish":road.finish})
 DirAccess.make_dir_recursive_absolute("res://reports/road_materials")
 FileAccess.open("res://reports/road_materials/result.json",FileAccess.WRITE).store_string(JSON.stringify({"total":total,"misses":misses,"bake":result,"options":options},"  "))
 print("GENERATED_ROAD_MATERIALS failures=",0 if misses.is_empty() else 1," probes=",total," missing_asphalt=",misses.size()," bake_ms=",result.worker_ms)
 quit(0 if misses.is_empty() else 1)
