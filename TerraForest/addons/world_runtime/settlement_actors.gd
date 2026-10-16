# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded editor authoring only; native actor ownership/routing handles runtime.
static func populate(game: Node)->Dictionary:
 if game.actors.pool==null:return {"ok":false,"reason":"Enable actor simulation first."}
 if game.actors.store.statistics().active!=0:return {"ok":false,"reason":"Actors already exist. Use individual actor tools to edit this population."}
 var nearest: Dictionary={};var distance:=32.0
 for street: Dictionary in game.road_palette.prepared_streets:
  var middle: Vector3=(street.ends[0]+street.ends[1])*.5
  var delta: Vector3=middle-game.player.global_position;delta.y=0
  if delta.length()<distance:nearest=street;distance=delta.length()
 if nearest.is_empty():return {"ok":false,"reason":"Move within 32 m of a prepared street centre."}
 var a: Vector3=nearest.ends[0];var b: Vector3=nearest.ends[1]
 var direction:=b-a;direction.y=0
 if direction.length()<12:return {"ok":false,"reason":"Choose a prepared street at least 12 m long."}
 direction=direction.normalized();var side:=Vector3(-direction.z,0,direction.x)
 var center: Vector3=(a+b)*.5
 var points:Array[Vector3]=[]
 var capsule:=CapsuleShape3D.new();capsule.radius=.35;capsule.height=1.8
 for lane in [-1,1]:
  for end in [-1,1]:
   var p: Vector3=center+direction*(end*4)+side*(lane*1.5)
   var ray:=PhysicsRayQueryParameters3D.create(p+Vector3.UP*4,p-Vector3.UP*4,3)
   var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
   if hit.is_empty() or hit.normal.y<.85:return {"ok":false,"reason":"Street patrol requires supported, level ground."}
   p=hit.position+Vector3.UP*.93
   var region:=AABB(p-Vector3(.4,1.2,.4),Vector3(.8,2.4,.8))
   if not game._actor_collision_ready(region):return {"ok":false,"reason":"Street collision is still loading; move closer and retry."}
   if game.lakes.depth_at(p-Vector3.UP*.8)>0:return {"ok":false,"reason":"Street patrol endpoints must be dry."}
   var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.transform=Transform3D(Basis.IDENTITY,p);query.collision_mask=0xFFFFFFFF
   if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return {"ok":false,"reason":"Street patrol space is occupied."}
   points.append(p)
 if points[0].distance_to(points[1])>16 or points[2].distance_to(points[3])>16:return {"ok":false,"reason":"Street grade exceeds local patrol range."}
 var empty: PackedByteArray=game.actors.store.capture_storage_snapshot()
 var previous_orders: PackedByteArray=game.actors.orders.capture_storage_snapshot()
 var ids:Array[int]=[]
 for pair in [[0,1],[3,2]]:
  var id: int=game.actors.spawn(points[pair[0]])
  if id==0 or not game.actors.orders.set_patrol(id,points[pair[1]]):
   game.actors._restore(empty);game.actors.orders.restore_storage_snapshot(previous_orders)
   return {"ok":false,"reason":"Actor creation failed; population restored."}
  ids.append(id)
 game.actors.select_near(game.player.global_position)
 return {"ok":true,"ids":ids,"reason":"Two street patrol actors placed. F5 saves the population."}
