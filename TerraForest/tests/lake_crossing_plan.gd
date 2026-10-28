extends "res://tests/distributed_generation.gd"

const Crossings=preload("res://addons/structures/lake_crossings.gd")

func run()->void:
 DirAccess.make_dir_recursive_absolute("res://reports/lake_landscape")
 var reports:=[]
 var launch=preload("res://demo/world_launch.gd")
 check(launch.terrain_generator(true,true)==29 and launch.terrain_generator(false,true)==28 and launch.terrain_generator(true,false)==31 and launch.terrain_generator(false,false)==30,"new default keeps independent ocean and terrain-grid options")
 check(Crossings.Catalog.footbridge().get_cell_count()==92,"existing twelve-metre bridge remains unchanged")
 for span in range(24,45,2):
  var asset:=Crossings.Catalog.lake_crossing(span)
  for rotation in 4:
   var blocks=ClassDB.instantiate("NativeBlockWorld")
   check(asset!=null and blocks.place_prefab(asset,Vector3i(100,40,100),rotation,false),"individual bridge cells place at span %d rotation %d"%[span,rotation])
   var snapshot:PackedByteArray=blocks.capture_snapshot()
   check(blocks.restore_snapshot(snapshot) and blocks.capture_snapshot()==snapshot,"bridge rotation persists exactly")
   blocks.free()
 for seed_value in [0,42,1703]:
  var options:=Recipe.DEFAULTS.duplicate()
  var cache:="user://lake_plan_"+Crypto.new().generate_random_bytes(6).hex_encode()
  var worker:=Thread.new();worker.start(Plan.build.bind(seed_value,29,true,true,cache,options))
  while worker.is_alive():await process_frame
  var planned:Dictionary=worker.wait_to_finish()
  check(planned.get("ok",false),"complete lake landscape plan / %d / %s"%[seed_value,planned.get("reason","")])
  if not planned.get("ok",false):reports.append(planned);continue
  var warm:=Plan.build(seed_value,29,true,true,cache,options)
  check(warm.get("cache_hit",false) and warm.plan_digest==planned.plan_digest,"bridge plan and trails reuse exact cached layout")
  if seed_value==1703:check(not planned.get("bridges",[]).is_empty(),"default test seed has a connected generated bridge")
  for crossing:Dictionary in planned.get("bridges",[]):
   var asset:=Crossings.asset(crossing)
   check(asset!=null and asset.get_cell_count()>200,"lake bridge uses individual native blocks")
   var blocks=ClassDB.instantiate("NativeBlockWorld")
   check(blocks.place_prefab(asset,crossing.origin,crossing.rotation,false),"atomic bridge placement accepts both grid rotations")
   var snapshot:PackedByteArray=blocks.capture_snapshot()
   check(blocks.restore_snapshot(snapshot) and blocks.capture_snapshot()==snapshot,"every bridge block survives exact native roundtrip")
   blocks.free()
   check(crossing.connections.size()==2 and crossing.approaches.size()>=4,"both banks have flat landings and connected regional paths")
   check(crossing.grade-2>crossing.level,"bridge structure leaves water below its girders")
  reports.append({"seed":seed_value,"bridges":planned.get("bridges",[]),"rejected":planned.get("bridge_rejections",[]),"cold_ms":planned.worker_ms,"warm_ms":warm.worker_ms,"digest":planned.plan_digest})
  var core:RefCounted=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[seed_value,29]))
  var packets:=preload("res://addons/world_runtime/generation_earthworks.gd").packets(planned.works.segments,planned.material_deposits)
  check(core.bake_generated_earthworks(packets).get("ok",false),"all generated lake approaches and roads bake through native admission")
 FileAccess.open("res://reports/lake_landscape/plans.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"plans":reports},"  "))
 print("LAKE_CROSSING_PLAN checks=",checks," failures=",failures);quit(1 if failures else 0)
