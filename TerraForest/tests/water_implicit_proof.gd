# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
const N:=32
const S:=N+2
const STEP:=.25
const ORIGIN:=Vector3(42,40,42)
var failures:=0
var evidence:=""
var extractor:RefCounted
var core:RefCounted
var equilibrium:RefCounted
var heads:Array[float]=[]
var scene:Node3D
var camera:Camera3D
var objects:Array[Node3D]=[]
var results:Array=[]
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func point(i:int)->Vector3:return Vector3(i%S,(i/S)%S,i/(S*S))*STEP-Vector3.ONE*STEP
func terrain_samples()->PackedFloat32Array:
 var values:=PackedFloat32Array();values.resize(S*S*S)
 var revision:int=core.execute(Codec.command(0)).decode_u32(12)
 for first in range(0,values.size(),256):
  var count:=mini(256,values.size()-first);var query:=PackedByteArray();query.resize(12+count*12)
  query.encode_u32(0,31);query.encode_u32(4,revision);query.encode_u32(8,count)
  for j in count:
   var p:=ORIGIN+point(first+j)
   for axis in 3:query.encode_float(12+j*12+axis*4,p[axis])
  var reply:PackedByteArray=core.execute(query)
  if reply.size()!=20+count*4 or not Codec.reply_ok(reply):return PackedFloat32Array()
  for j in count:values[first+j]=reply.decode_float(20+j*4)
 return values
func mesh(packet:Dictionary,color:Color)->void:
 if not packet.ok or packet.triangles==0:return
 var resource:=ArrayMesh.new();resource.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,packet.arrays)
 var instance:=MeshInstance3D.new();instance.mesh=resource
 var material:=StandardMaterial3D.new();material.albedo_color=color;material.roughness=.28 if color.b>.5 else .85
 if color.a<1:material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 material.cull_mode=BaseMaterial3D.CULL_DISABLED
 instance.material_override=material;scene.add_child(instance);objects.append(instance)
func volume(packet:Dictionary)->float:
 var vertices:PackedVector3Array=packet.arrays[Mesh.ARRAY_VERTEX];var result:=0.0
 for i in range(0,vertices.size(),3):result+=vertices[i].dot(vertices[i+1].cross(vertices[i+2]))/6.0
 return absf(result)
func capture(label:String)->void:
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join(label+".png"))
func show_case(label:String,terrain:PackedFloat32Array,sphere:bool=false)->void:
 for object in objects:object.queue_free()
 objects.clear();await process_frame
 var water:=PackedFloat32Array();water.resize(S*S*S)
 var ground:=PackedFloat32Array();ground.resize(S*S*S)
 for i in water.size():
  var p:=point(i)
  if sphere:water[i]=p.distance_to(Vector3(4,4,4))-2.2;ground[i]=1
  else:
   var boundary:=maxf(absf(p.x-4),maxf(absf(p.y-4),absf(p.z-4)))-3.75
   ground[i]=maxf(terrain[i],boundary)
   water[i]=1 # The equilibrium service supplies the actual field below.
 var settled:Dictionary={}
 if not sphere:
  settled=equilibrium.solve(terrain,N,STEP,40000000,4.75)
  check(settled.ok,label+" finite quantity reaches closed-basin equilibrium: "+str(settled.get("reason","ok")))
  if not settled.ok:return
  check(settled.quantity_ml==40000000,label+" retains the authoritative integer quantity")
  water=settled.field
  heads.append(settled.head)
 var packet:Dictionary=extractor.extract(water,N,STEP)
 check(packet.ok and packet.triangles>0,label+" produces a continuous field boundary")
 if not packet.ok:return
 var terrain_packet:Dictionary=extractor.extract(ground,N,STEP)
 check(terrain_packet.ok,label+" terrain extraction stays within its budgets")
 if sphere:check(absf(volume(packet)-4.0/3.0*PI*pow(2.2,3))/(4.0/3.0*PI*pow(2.2,3))<.03,"Sphere boundary volume agrees with its independent analytic volume")
 # Opaque blue is a geometry inspection material, matching the reference.
 # Transparent water presentation is a separate acceptance check.
 mesh(terrain_packet,Color(.56,.48,.34));mesh(packet,Color(.025,.24,.8))
 camera.position=Vector3(11,9,12);camera.look_at(Vector3(4,3.5,4))
 await capture(label+"_shaded")
 root.debug_draw=Viewport.DEBUG_DRAW_WIREFRAME
 await capture(label+"_wireframe")
 root.debug_draw=Viewport.DEBUG_DRAW_DISABLED
 if label in ["terrain_cut","terrain_overhang"]:
  objects[0].queue_free();objects.remove_at(0)
  for i in ground.size():ground[i]=maxf(ground[i],point(i).x-4)
  mesh(extractor.extract(ground,N,STEP),Color(.56,.48,.34))
  camera.position=Vector3(11,5,12);camera.look_at(Vector3(4,3.5,4))
  await capture(label+"_cutaway")
 results.append({"case":label,"triangles":packet.triangles,"extract_us":packet.extract_us,"mesh_bytes":packet.mesh_bytes,"sample_bytes":packet.sample_bytes,"terrain_triangles":terrain_packet.triangles,"boundary_volume_m3":volume(packet),"head":settled.get("head",0),"solve_us":settled.get("solve_us",0),"quantity_ml":settled.get("quantity_ml",0)})
func run()->void:
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
 if evidence.is_empty():push_error("Use the admitted check launcher");quit(2);return
 root.size=Vector2i(1280,720)
 root.content_scale_size=Vector2i(1280,720)
 extractor=ClassDB.instantiate("NativeImplicitWaterSurface");core=ClassDB.instantiate("TerrainCore");equilibrium=ClassDB.instantiate("NativeWaterBasinEquilibrium")
 check(extractor!=null and core!=null and equilibrium!=null,"Native proof services load")
 if failures:quit(1);return
 scene=Node3D.new();root.add_child(scene)
 var environment:=WorldEnvironment.new();var settings:=Environment.new();settings.background_mode=Environment.BG_COLOR;settings.background_color=Color(.14,.18,.22)
 settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;settings.ambient_light_color=Color(.8,.85,1);settings.ambient_light_energy=.65;environment.environment=settings;scene.add_child(environment)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-25,0);light.light_energy=1.8;scene.add_child(light)
 camera=Camera3D.new();camera.far=80;scene.add_child(camera);camera.make_current()
 await show_case("sphere",PackedFloat32Array(),true)
 core.execute(Codec.command(6,[42,5]))
 core.execute(Codec.brush(Vector3(46,40,46),Vector3(46,40,46),5,1,true,1))
 core.execute(Codec.brush(Vector3(46,45.5,46),Vector3(46,45.5,46),3.5,0,false,0))
 var samples:=terrain_samples();check(samples.size()==S*S*S,"Authoritative native terrain density samples are available")
 if failures:quit(1);return
 await show_case("terrain_basin",samples)
 core.execute(Codec.brush(Vector3(48,43.8,46),Vector3(48,43.8,46),1.4,0,false,0))
 await show_case("terrain_cut",terrain_samples())
 core.execute(Codec.brush(Vector3(44.5,44,46),Vector3(47.5,44,46),.65,0,true,1))
 await show_case("terrain_overhang",terrain_samples())
 if heads.size()==3:
  check(heads[1]<heads[0]-.01,"Excavation lowers the level at constant quantity")
  check(heads[2]>heads[1]+.01,"Deposited overhang displaces water upwards at constant quantity")
 else:check(false,"All terrain response cases produced equilibrium")
 core.execute(Codec.brush(Vector3(50,43,46),Vector3(50,43,46),2,0,false,0))
 var open_result:Dictionary=equilibrium.solve(terrain_samples(),N,STEP,40000000,4.75)
 check(not open_result.ok and open_result.quantity_ml==40000000 and open_result.get("reason","")=="Basin reaches unavailable boundary","Open domain preserves quantity and requires expansion instead of inventing a wall")
 var isolated:=PackedFloat32Array();isolated.resize(S*S*S)
 for i in isolated.size():
  var p:=point(i)
  isolated[i]=-minf(p.distance_to(Vector3(2,3,4))-1,p.distance_to(Vector3(6,3,4))-1)
 var isolated_result:Dictionary=equilibrium.solve(isolated,N,STEP,1000000,4.75)
 check(not isolated_result.ok and isolated_result.get("reason","")=="Separate basin quantities required","Isolated basins cannot receive one fictitious shared level")
 check(not extractor.extract(PackedFloat32Array(),N,STEP).ok,"Malformed field is rejected without partial mesh")
 var report:=FileAccess.open(evidence.path_join("implicit_proof.json"),FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"cases":results,"scope":"Continuous boundary extraction using actual TerrainCore density edits. Cutaway captures hide half of terrain for inspection only; occupancy uses the complete terrain field. Closed single-basin finite-volume reference with conserved quantity across native terrain edits. Open/disconnected domains remain explicit pending cases; no gameplay, spill solver or GPU-cost acceptance claimed."},"  "));report.close()
 print("WATER_IMPLICIT_PROOF failures=",failures)
 scene.queue_free();await process_frame;quit(failures)
