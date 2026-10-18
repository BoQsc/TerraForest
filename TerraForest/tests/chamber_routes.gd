# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func ray(core:RefCounted,a:Vector3,b:Vector3)->Dictionary:
 return Codec.decode_density_ray(core.execute(Codec.density_ray_command(a,b,512,0,true)))
func _initialize()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore");core.execute(Codec.command(6,[1703,9]))
 var data:PackedByteArray=core.execute(Codec.command(25))
 var failures:=0;var samples:=0;var min_normal:=1.0
 for network in 4:
  for segment in [0,1,3,5]:
   var offset:int=24+(network*7+segment)*28
   var a:=Vector3(data.decode_float(offset),data.decode_float(offset+4),data.decode_float(offset+8))-Vector3.UP*5
   var b:=Vector3(data.decode_float(offset+12),data.decode_float(offset+16),data.decode_float(offset+20))-Vector3.UP*5
   var steps:=ceili(a.distance_to(b)/2)
   var route_ok:=true
   for i in steps+1:
    var p:=a.lerp(b,float(i)/steps)
    var floor_hit:=ray(core,p+Vector3.UP*3,p-Vector3.UP*5)
    samples+=1
    if floor_hit.status!="hit":
     if route_ok:print("ROUTE_MISSING at=",p," result=",floor_hit)
     route_ok=false;continue
    min_normal=minf(min_normal,floor_hit.normal.y)
    if floor_hit.normal.y<0.7072 or absf(floor_hit.position.y-p.y)>1.0:
     if route_ok:print("ROUTE_FLOOR at=",p," hit=",floor_hit)
     route_ok=false
    var head:=ray(core,floor_hit.position+Vector3.UP*.3,floor_hit.position+Vector3.UP*2.3)
    if head.status!="miss":route_ok=false
   print("PASS " if route_ok else "FAIL ","route network=",network," segment=",segment)
   if not route_ok:failures+=1
 print("CHAMBER_ROUTES failures=",failures," samples=",samples," min_floor_normal=",min_normal)
 quit(1 if failures else 0)
