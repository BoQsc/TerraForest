# SPDX-License-Identifier: 0BSD
extends RefCounted
# Offline location planting only. Native authored records own persistence and picking.
const Tokens=preload("res://addons/volumetric_terrain/surface_tokens.gd")
static func centers(seed_value:int,generator:int)->PackedVector3Array:
 var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(seed_value,generator)
 var result:=PackedVector3Array()
 if layout.is_empty():return result
 for site in [0,4]:
  var at:Vector3=layout.sites[site].position+Vector3(64,0,64)
  result.append(Vector3(roundf(at.x/32)*32,at.y,roundf(at.z/32)*32))
 if generator>=13:
  var north:Vector3=layout.sites[3].position
  for x in [-12,12]:result.append(north+Vector3(x,0,26))
 return result
static func plant(game:Node,center:Vector3,patch_seed:int, side:int=32)->Dictionary:
 if side<1 or side>32:return {"ok":false,"reason":"Invalid planting size"}
 var rng:=RandomNumberGenerator.new();rng.seed=patch_seed
 var counts:Array[int]=[0,0,0,0,0,0,0,0]
 var owners:Dictionary={}
 for row in side:
  var points:=PackedVector3Array()
  for col in side:points.append(center+Vector3((col-(side-1)*0.5)*0.45+rng.randf_range(-0.12,0.12),0,(row-(side-1)*0.5)*0.45+rng.randf_range(-0.12,0.12)))
  var token:=Tokens.allocate();var replies:Array=[]
  var receive:=func(id:int,positions:PackedVector3Array,normals:PackedVector3Array,_epoch:int,_revision:int):
   if id==token:replies.append({"points":positions,"normals":normals})
  game.terrain.surface_batch_ready.connect(receive)
  var deadline:=Time.get_ticks_msec()+15000;var accepted:=false
  while replies.is_empty() and Time.get_ticks_msec()<deadline:
   if not accepted:accepted=game.terrain.request_surface_batch(points,token)
   await game.get_tree().process_frame
  game.terrain.surface_batch_ready.disconnect(receive)
  if replies.is_empty():return {"ok":false,"reason":"Woodland surface sampling timed out"}
  var poses:Array[Transform3D]=[];var species:Array[int]=[]
  for col in side:
   var point:Vector3=replies[0].points[col]
   if replies[0].normals[col].y<0.82:continue
   var local:Vector3=point-center
   if absf(local.x-sin(local.z*0.35)*0.9)<0.55:continue
   var clustered:bool=sin(local.x*0.9)*cos(local.z*0.65)>0.55
   var kind:int=1 if clustered and rng.randf()<0.42 else (0 if rng.randf()<0.025 else 2)
   var scale:float=rng.randf_range(0.85,1.4)
   var pose:=Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),point-Vector3.UP*0.03)
   var accent:=rng.randf()
   if kind==2:
    if accent<0.015:kind=3+rng.randi_range(0,2)
    elif accent<0.04:kind=6
    elif accent<0.07:kind=7
   poses.append(pose);species.append(kind)
  var blocked:PackedByteArray=game.structures.overlap_mask(poses,AABB(Vector3(-0.4,0,-0.4),Vector3(0.8,0.8,0.8)))
  var wet:PackedByteArray=game.lakes.placement_mask(poses)
  if blocked.size()!=poses.size() or wet.size()!=poses.size():return {"ok":false,"reason":"Woodland exclusion query failed"}
  for index in poses.size():
   if blocked[index] or wet[index]:continue
   if game.ground_cover.removed.add(species[index],poses[index])==0:return {"ok":false,"reason":"Woodland authored capacity exceeded"}
   counts[species[index]]+=1
   var at:Vector3=poses[index].origin
   owners[Vector2i(floori(at.x/32),floori(at.z/32))]=true
 for key in owners:game.ground_cover._dirty[key]=true
 return {"ok":true,"counts":counts,"owners":owners.size()}
