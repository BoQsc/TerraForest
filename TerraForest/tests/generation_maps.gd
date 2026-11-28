# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
class Backend extends RefCounted:
 var native:RefCounted
 var world_generator:=5
 var build_epoch:=0
class Terrain extends Node:
 var backend:=Backend.new()
 var world_ready:=true
 var diagnostics_pause_streaming:=true
 var pending_edit:=false
 var stopping:=false
 var epoch:=1
 var density_revision:=0
 var modified_columns:Dictionary={Vector2i(4,4):true}
class Structures extends Node:
 var blocks:Node3D
 var models:Dictionary={}
 func model_collections()->Dictionary:return models
class Lakes extends Node:
 var water:RefCounted=ClassDB.instantiate("NativeRegionalWater")
class World extends Node:
 var terrain:=Terrain.new()
 var structures:=Structures.new()
 var lakes:=Lakes.new()
 var shutdown_requested:=false
func fixture()->World:
 var state:=World.new();root.add_child(state)
 state.add_child(state.terrain);state.add_child(state.structures);state.add_child(state.lakes)
 state.terrain.backend.native=ClassDB.instantiate("TerrainCore");state.terrain.backend.native.execute(Codec.command(6,[1703,5]))
 var blocks:Node3D=ClassDB.instantiate("NativeBlockWorld");state.structures.add_child(blocks);state.structures.blocks=blocks
 blocks.set_cells(PackedInt32Array([70,150,70,1,70,151,70,2,72,4,72,3]));blocks.position=Vector3(5,0,9)
 var model:Node3D=ClassDB.instantiate("NativeStaticBatch");model.configure_collision_only()
 var mesh:=BoxMesh.new();mesh.size=Vector3(4,6,8);model.configure_asset("map/wood",mesh)
 state.structures.add_child(model);state.structures.models["map/wood"]=model
 model.transform=Transform3D(Basis(Vector3.UP,.3),Vector3(120,0,50))
 model.upsert_transforms(PackedInt64Array([1,2]),[Transform3D(Basis.IDENTITY,Vector3(70,150,70)),Transform3D(Basis.IDENTITY,Vector3(72,2,72))])
 return state
func pixels(core:RefCounted,raster:RefCounted,tint:Color)->PackedByteArray:
 var offset:=0
 while offset<raster.count():
  var reply:Dictionary=core.survey_water_visibility(raster.batch(offset,256))
  if not check(reply.get("ok",false) and raster.accept_prefix(offset,reply.visible),"reference visibility prefix accepted"):return PackedByteArray()
  offset+=reply.visible.size()
 return raster.pixels(tint)
func check_planning(core:RefCounted)->void:
 var native:RefCounted=ClassDB.instantiate("NativeGenerationEarthworks")
 var roads:Array=[];var reserved:Array=[Rect2(100,100,30,30),Rect2(200,0,10,500)]
 for i in 2500:
  roads.append({"start":Vector3(i%300,30,i%200),"finish":Vector3((i+1)%300,30,(i+1)%200)})
 for south:bool in [false,true]:
  var expected:Array=[]
  for road:Dictionary in roads:
   for point:Vector3 in [road.start,road.finish]:
    if expected.has(point):continue
    var blocked:=false
    for area:Rect2 in reserved:
     if area.grow(6).has_point(Vector2(point.x,point.z)):blocked=true;break
    if not blocked:expected.append(point)
  expected.sort_custom(func(a:Vector3,b:Vector3):return a.x>b.x if a.z==b.z else a.z>b.z if south else a.z<b.z)
  check(native.arrival_points(roads,reserved,south)==expected.slice(0,8),"native road exits preserve duplicate, exclusion and ordering rules")
 var points:=PackedVector3Array()
 for i in 1030:points.append(Vector3(300+i*.35,100,400+(i%31)*.4))
 var expected:=PackedFloat32Array()
 for offset in range(0,points.size(),256):
  var batch:=points.slice(offset,offset+256);var query:=Codec.command(37,[batch.size()]);query.append_array(batch.to_byte_array())
  var reply:PackedByteArray=core.execute(query)
  for i in batch.size():expected.append(reply.decode_float(12+i*8))
 check(native.heights(core,points)==expected,"native foundation survey preserves every float across batch boundaries")
 check(native.arrival_points([{}],[],true).is_empty(),"malformed road exits rejected")
 for displacement:Vector3 in [Vector3(0,0,0),Vector3(0.125,0,0),Vector3(12.3,1,8.7),Vector3(-8.7,-1,12.3),Vector3(64,0,0),Vector3(65,0,0),Vector3(2,3,0)]:
  var paths:Array=[{"start":Vector3(340.25,55.125,420.75),"finish":Vector3(340.25,55.125,420.75)+displacement,"half_width":1.375}]
  var reference:Dictionary=preload("res://tests/fixtures/generation_earthworks_reference.gd").access_quality(core,paths)
  check(native.access_quality(core,paths)==reference,"native approach survey preserves probes, grade and cut/fill acceptance "+str(displacement))
func run()->void:
 var state:=fixture();var core:RefCounted=state.terrain.backend.native
 core.execute(Codec.command(6,[1703,19]))
 check_planning(core)
 state.terrain.backend.build_epoch=core.execute(Codec.command(12)).decode_u32(12)
 var probes:=PackedVector3Array()
 for x in [64,66,68]:
  var p:=Vector3(x,100,64);p.y=core.execute(Codec.point_command(p)).decode_float(12);probes.append(p)
 var ground:Dictionary=ClassDB.instantiate("NativeGenerationEarthworks").sample_ground(state.terrain,probes)
 var ground_points:=PackedVector3Array();var ground_normals:=PackedVector3Array()
 for point:Vector3 in probes:
  var ray:Dictionary=Codec.decode_density_ray(core.execute(Codec.density_ray_command(point+Vector3.UP*8,point-Vector3.UP*8,64,state.terrain.backend.build_epoch,true)))
  check(ray.get("status")=="hit","reference sign footing ray hits")
  if ray.get("status")=="hit":ground_points.append(ray.position);ground_normals.append(ray.normal)
 check(ground.get("ok",false) and ground.get("points")==ground_points and ground.get("normals")==ground_normals,"native footing rays exactly match ordered ground probes")
 core.execute(Codec.command(6,[1703,5]))
 var base:=PackedByteArray();base.resize(1024*1024*4);base.fill(0)
 var job:RefCounted=ClassDB.instantiate("NativeGenerationMaps")
 check(job.start(state,base),"native map captures resident scene inputs")
 while not job.advance():await process_frame
 check(job.get_result().get("ok",false),"native source batches and frozen worker complete")
 var expected:=base.duplicate()
 # Independent equivalent of the existing survey_updates.changed 8 m halo.
 var low:=floori((64.0-8)*1024/2000/16);var high:=floori((80.0+8)*1024/2000/16)
 for z in range(low,high+1):
  for x in range(low,high+1):
   var patch:Dictionary=core.survey_patch(1024,x*16,z*16,16,16)
   for row in 16:
    for byte in 64:expected[((z*16+row)*1024+x*16)*4+byte]=patch.pixels[row*64+byte]
 check(job.terrain_pixels()==expected,"native tile halo and compositing preserve every terrain pixel")
 for layer:int in [1,2]:
  var raster:RefCounted=ClassDB.instantiate("NativeSurfaceMapRaster");raster.configure(512)
  var source:Node3D=state.structures.blocks if layer==1 else state.structures.models["map/wood"]
  var index:Dictionary=source.survey_index()
  for r in index.keys.size()/3:
   var key:=Vector3i(index.keys[r*3],index.keys[r*3+1],index.keys[r*3+2])
   var offset:=0;var done:=false
   while not done:
    var part:Dictionary=source.survey_columns(key,offset,index.revision) if layer==1 else source.survey_bounds(key,offset,index.revision)
    if layer==1:
     raster.offer(index.transform*part.points,part.colors);offset=part.offset
    else:
     var cursor:=Vector2i.ZERO;var projected_done:=false
     while not projected_done:
      var projected:Dictionary=raster.project_bounds(part.bounds,index.transform,cursor)
      var colors:=PackedColorArray();colors.resize(projected.points.size());colors.fill(Color("776044"))
      raster.offer(projected.points,colors);cursor=projected.cursor;projected_done=projected.complete
     offset=part.after_id
    done=part.complete
  check(job.layer_pixels(layer)==pixels(core,raster,Color("d9c9ad") if layer==1 else Color("8e8b82")),"exact transformed and occluded overlay "+str(layer))
 check(not job.start(state,base),"completed map job cannot reuse mutable input")
 var cancelled:RefCounted=ClassDB.instantiate("NativeGenerationMaps");check(cancelled.start(state,base),"cancellable map admitted")
 cancelled.cancel();check(cancelled.advance() and not cancelled.get_result().ok and cancelled.terrain_pixels().is_empty(),"cancelled job exposes no pixels")
 var stale:RefCounted=ClassDB.instantiate("NativeGenerationMaps");check(stale.start(state,base),"stale-source map admitted")
 state.structures.blocks.set_cells(PackedInt32Array([70,151,70,0]))
 check(stale.advance() and not stale.get_result().ok,"changed geometry rejects captured source")
 var unloaded:RefCounted=ClassDB.instantiate("NativeGenerationMaps")
 var packet:PackedByteArray=state.structures.blocks.capture_region(Vector3i(1,2,1));state.structures.blocks.unload_region(packet)
 check(not unloaded.start(state,base) and unloaded.advance() and not unloaded.get_result().ok,"native fresh-world path refuses unavailable regions")
 job=null;cancelled=null;stale=null;unloaded=null;state.free()
 print("GENERATION_MAPS failures=",failures);quit(1 if failures else 0)
