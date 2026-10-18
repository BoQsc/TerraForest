# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
 var catalog=preload("res://addons/structures/furniture_catalog.gd")
 var cottage:Resource=catalog.enclosed_cottage();var tower:Resource=catalog.furnished_tower(3)
 var available:Dictionary={cottage.resource_name:cottage,tower.resource_name:tower}
 var workshop:Resource=preload("res://addons/structures/workshop_catalog.gd").workshop()
 available[workshop.resource_name]=workshop
 var failures:=0
 for site in range(1,5):
  var plan:Dictionary=preload("res://addons/structures/regional_districts.gd").plan(site)
  var sources:Array[Resource]=[]
  for title:String in plan.sources:sources.append(available[title])
  var asset:Resource=ClassDB.instantiate("NativeBlockPrefab")
  var ok:bool=asset.compose_frontage(sources,plan.lots,plan.width,plan.gap,1703+site) if plan.streets==1 else asset.compose_settlement(sources,plan.lots,plan.width,plan.gap,1703+site,plan.streets)
  if not ok:failures+=1;continue
  asset.set_meta("frontage_version",1 if plan.streets==1 else 2);asset.set_meta("street_width",plan.width)
  asset.set_meta("entrance_paths",true)
  var doors:=0
  for model:Dictionary in asset.get_model_attachments():
   if model.model=="architecture/wooden_door/v1":doors+=1
  var bounds:AABB=asset.placement_bounds(Vector3i.ZERO,0)
  var origin:=Vector3i(floori(1000-12-bounds.end.x),50,floori(1000-12-bounds.end.z))
  var grading:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,origin,0,50)
  ok=doors==plan.buildings and grading.get("entrance_paths",0)==doors and grading.ok and bounds.size.x<=60 and bounds.size.z<=60
  for turn in range(1,4):
   var rotated:Dictionary=preload("res://addons/structures/site_plan.gd").prepare(asset,Vector3i(1000,50,1000),turn,50)
   ok=ok and rotated.ok and rotated.get("entrance_paths",0)==doors and rotated.segments.size()<=256
   if rotated.ok:
    for path:Dictionary in rotated.segments.slice(rotated.foundation_segments):
     ok=ok and path.start.y==50 and path.finish.y==50 and path.bounds.has_point(path.start) and path.bounds.has_point(path.finish)
  print("PASS " if ok else "FAIL ",plan.title," buildings=",doors," bounds=",bounds," grading=",grading.get("ok",false))
  if not ok:failures+=1
 print("REGIONAL_DISTRICTS failures=",failures);quit(1 if failures else 0)
