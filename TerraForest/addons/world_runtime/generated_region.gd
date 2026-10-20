# SPDX-License-Identifier: 0BSD
extends RefCounted
# Baked public navigation metadata, distinct from planning hints and secret POIs.
var store:RefCounted
func prepare(persistence:RefCounted)->bool:
 if not ClassDB.class_exists("NativeGeneratedRegion"):
  GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 store=ClassDB.instantiate("NativeGeneratedRegion")
 return store!=null and persistence.register_component("generated_region",store.capture_snapshot,store.restore_snapshot,store,PackedByteArray())
func revision()->int:
 return store.get_revision() if store!=null else 0
func describe(seed_value:int,generator:int)->Dictionary:
 if store==null:return {}
 var result:Dictionary=store.get_plan()
 if not result.get("present",false) or result.seed!=seed_value or result.generator!=generator:return {}
 return result
func publish_neighborhood(seed_value:int,plan:Dictionary)->bool:
 if store==null:return false
 var data:Dictionary=neighborhood_metadata(plan,3,"North neighborhood","Homes and local streets fitted to the hillside.")
 return not data.is_empty() and store.set_plan(seed_value,17,data.places,data.roads)
static func neighborhood_metadata(plan:Dictionary,id:int,title:String,detail:String)->Dictionary:
 if not plan.get("ok",false):return {}
 var roads:Array=[];var arrival:=Vector3.ZERO;var closest:=INF
 for road:Dictionary in plan.roads:
  # The one-metre junction patches are not separate navigable streets.
  if road.start.distance_to(road.finish)<2:continue
  var steps:int=ceili(Vector2(road.finish.x-road.start.x,road.finish.z-road.start.z).length()/2)
  for i in steps:
   var a:Vector3=road.start.lerp(road.finish,float(i)/steps)
   var b:Vector3=road.start.lerp(road.finish,float(i+1)/steps)
   a.y=lerpf(road.start.y,road.finish.y,smoothstep(0,1,float(i)/steps))
   b.y=lerpf(road.start.y,road.finish.y,smoothstep(0,1,float(i+1)/steps))
   roads.append({"a":a,"b":b,"width":road.half_width*2})
   var distance:float=Vector2(a.x-plan.center.x,a.z-plan.center.z).length_squared()
   if distance<closest:closest=distance;arrival=a
 if roads.is_empty():return {}
 var places:Array=[{"id":id,"title":title,"detail":detail,"position":arrival}]
 # Publication must happen only after terrain and buildings finish successfully.
 return {"places":places,"roads":roads}
