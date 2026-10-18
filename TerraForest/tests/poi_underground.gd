# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func v(data:PackedByteArray,at:int)->Vector3:
 return Vector3(data.decode_float(at),data.decode_float(at+4),data.decode_float(at+8))
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 for seed_value in [1703,1,42,9999]:
  check(Codec.reply_ok(core.execute(Codec.command(6,[seed_value,11]))),"profile initializes")
  var metadata:PackedByteArray=core.execute(Codec.command(35))
  check(metadata.size()==76 and metadata.decode_u32(16)==1,"one owned mine")
  check(metadata.decode_u32(24)==2 and metadata.decode_u32(72)==7,"east location owns all seven primitives")
  var sites:PackedByteArray=core.execute(Codec.command(34))
  var entrance:=v(metadata,32)
  check(entrance.distance_to(v(sites,56)+Vector3(0,0,50))<.01,"entrance belongs to graded surface location")
  var data:PackedByteArray=core.execute(Codec.command(25))
  check(data.decode_u32(20)==7,"no unrelated ambient networks")
  for segment in [0,1,3,5]:
   var at:int=24+segment*28
   var a:=v(data,at)-Vector3.UP*5
   var b:=v(data,at+12)-Vector3.UP*5
   var steps:=ceili(a.distance_to(b)/2)
   var valid:=true
   for i in steps+1:
    var point:=a.lerp(b,float(i)/steps)
    var hit:=Codec.decode_density_ray(core.execute(Codec.density_ray_command(point+Vector3.UP*3,point-Vector3.UP*5,512,0,true)))
    if hit.status!="hit" or hit.normal.y<.7072 or absf(hit.position.y-point.y)>1:valid=false
   check(valid,"floor route seed=%d segment=%d" % [seed_value,segment])
  var covered:=true
  for segment in [1,2,3,4,5,6]:
   var at:int=24+segment*28
   var a:=v(data,at);var b:=v(data,at+12);var radius:=data.decode_float(at+24)
   var low:=a.min(b)-Vector3(radius,0,radius)
   var high:=a.max(b)+Vector3(radius,0,radius)
   for x in range(floori(low.x),ceili(high.x)+1,2):
    for z in range(floori(low.z),ceili(high.z)+1,2):
     var top:float=core.execute(Codec.point_command(Vector3(x,0,z))).decode_float(12)
     var query:=Codec.point_command(Vector3(x,top-2,z));query.encode_u32(0,26)
     if core.execute(query).decode_float(16)>=0:covered=false
  check(covered,"solid terrain roof over all underground chambers and branches")
  var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
  core.execute(Codec.command(6,[seed_value+1,11]))
  var restore:=Codec.command(5);restore.append_array(saved)
  check(Codec.reply_ok(core.execute(restore)) and core.execute(Codec.command(35))==metadata and core.execute(Codec.command(25))==data,"save restores exact owned underground")
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,11)
  check(layout.get("underground",[]).size()==1,"shared layout exposes mine ownership")
 print("POI_UNDERGROUND failures=",failures)
 quit(1 if failures else 0)
