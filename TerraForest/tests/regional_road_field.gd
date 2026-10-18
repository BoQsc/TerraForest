# SPDX-License-Identifier: 0BSD
extends "res://tests/road_vegetation.gd"
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 var total:=0
 var max_grade:=0.0
 for seed_value in [1703,1,42,9999]:
  core.execute(Codec.command(6,[seed_value,12]))
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,12)
  for road:Dictionary in layout.roads:
   var a:Vector3=layout.sites[road.from].position
   var b:Vector3=layout.sites[road.to].position
   var direction:Vector3=(b-a);direction.y=0;direction=direction.normalized()
   var side:=Vector3(-direction.z,0,direction.x)
   var steps:=ceili(Vector2(b.x-a.x,b.z-a.z).length()/2.0)
   for lane in [-0.6,0.0,0.6]:
    var points:=PackedVector3Array()
    for i in range(steps+1):points.append(a.lerp(b,float(i)/steps)+side*float(road.half_width)*lane)
    var result:={"points":PackedVector3Array(),"normals":PackedVector3Array()}
    for start in range(0,points.size(),64):
     var batch:=sample(core,points.slice(start,mini(start+64,points.size())))
     if batch.is_empty():result.clear();break
     result.points.append_array(batch.points);result.normals.append_array(batch.normals)
    var ok:bool=not result.is_empty()
    for i in result.get("points",[]).size():
     ok=ok and result.normals[i]==Vector3.ZERO and result.points[i].is_finite()
     if i>0:
      var grade:float=absf(result.points[i].y-result.points[i-1].y)/Vector2(points[i].x-points[i-1].x,points[i].z-points[i-1].z).length()
      max_grade=maxf(max_grade,grade);ok=ok and grade<0.25
     total+=1
    check(ok,"profile12 road seed=%d destination=%d lane=%s paved and grade under 25%%"%[seed_value,road.to,str(lane)])
 print("REGIONAL_ROAD_FIELD failures=",failures," samples=",total," max_grade=",max_grade," scope=generated_field_not_saved_edits_or_runtime_collision")
 quit(1 if failures else 0)
