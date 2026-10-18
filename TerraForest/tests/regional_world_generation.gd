# SPDX-License-Identifier: 0BSD
extends "res://tests/road_vegetation.gd"
const Layout=preload("res://addons/volumetric_terrain/generated_layout.gd")
func run()->void:
 GDExtensionManager.load_extension("res://addons/volumetric_terrain/terrain_core.gdextension")
 var core=ClassDB.instantiate("TerrainCore")
 var plan:Dictionary=Layout.describe(1703)
 check(plan.get("sites",[]).size()==5 and plan.get("roads",[]).size()==4,"one shared native layout exposes five settlement sites and four connecting roads")
 if plan.is_empty():quit(1);return
 core.execute(Codec.command(6,[1703,7]))
 var baseline:PackedByteArray=core.execute(Codec.command(34))
 var saved:PackedByteArray=core.execute(Codec.command(4)).slice(12)
 check(saved.size()<1024 and saved.decode_u32(28)==7,"map-wide roads and grading require no authored voxel pages")
 var length:=0.0;var max_grade:=0.0;var samples:=0
 for road:Dictionary in plan.roads:
  var a:Vector3=plan.sites[road.from].position;var b:Vector3=plan.sites[road.to].position
  length+=a.distance_to(b)
  var points:=PackedVector3Array()
  for i in 49:points.append(a.lerp(b,i/48.0))
  var ground:=sample(core,points)
  var clear:=not ground.is_empty();var connected:=true
  for i in ground.get("points",[]).size():
   clear=clear and ground.normals[i]==Vector3.ZERO
   if i>0:
    var grade:float=absf(ground.points[i].y-ground.points[i-1].y)/Vector2(points[i].x-points[i-1].x,points[i].z-points[i-1].z).length()
    max_grade=maxf(max_grade,grade);connected=connected and grade<.25
   samples+=1
  check(clear and connected,"entire connector is paved, vegetation-free and below 25 percent sampled grade")
 for site:Dictionary in plan.sites:
  var flat:=true
  for offset in [Vector3(15,0,15),Vector3(-15,0,15),Vector3(15,0,-15),Vector3(-15,0,-15)]:
   var h:float=core.execute(Codec.point_command(site.position+offset)).decode_float(12)
   flat=flat and absf(h-site.position.y)<.001
  check(flat,"settlement footprint has native level foundation ground")
 check(length>3000,"connected arterial network exceeds three kilometres")
 var center:Vector3=plan.sites[0].position
 var epoch:int=core.execute(Codec.command(13)).decode_u32(12)
 var mesh:Dictionary=Codec.decode_mesh(core.build_owned_region(floori(center.x/16)*16,floori(center.z/16)*16,16,1,floori(center.y/32)*32,floori(center.y/32)*32+32,epoch))
 var painted:=false
 if mesh.has("arrays"):
  for uv:Vector2 in mesh.arrays[Mesh.ARRAY_TEX_UV2]:painted=painted or uv.y-floorf(uv.y)>.24
 check(painted,"native generated road mesh carries asphalt surface weight")
 var packet:=Codec.command(5);packet.append_array(saved)
 var restored=ClassDB.instantiate("TerrainCore")
 check(Codec.reply_ok(restored.execute(packet)) and restored.execute(Codec.command(34))==baseline,"fresh native owner restores the exact generated layout")
 check(restored.execute(Codec.command(4)).slice(12)==saved,"generator identity roundtrips exactly")
 var lakes:PackedByteArray=core.execute(Codec.command(27))
 check(lakes.decode_u32(12)==4 and core.execute(Codec.command(25)).decode_u32(20)==20,"existing lake and cave systems remain in the generated world")
 check(Layout.describe(1704)!=plan and Layout.describe(1703)==plan,"layout is seed-dependent and reproducible")
 print("REGIONAL_METRICS road_metres=",length," samples=",samples," max_grade=",max_grade," save_bytes=",saved.size())
 print("REGIONAL_WORLD_GENERATION failures=",failures);quit(1 if failures else 0)
