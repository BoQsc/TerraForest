# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():run.call_deferred()
func run():
 var scene=Node3D.new();root.add_child(scene)
 var body=StaticBody3D.new();body.position=Vector3(0,-1.5,0);scene.add_child(body)
 var shape=BoxShape3D.new();shape.size=Vector3(24,1,24);var collision=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
 var blocks=ClassDB.instantiate("NativeBlockWorld");scene.add_child(blocks);blocks.set_collision_radius(48);blocks.set_cells(load("res://addons/structures/prefabs/brick_cottage.tres").get_records());blocks.flush_bakes()
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 var actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors);actors.prepare(persistence);actors.enable(3)
 var handles: Array=[]
 for z in [9.0,8.167,8.33]:
  var identity: int=actors.spawn(Vector3(.5,-.09906,z));handles.append(actors.store.resolve_identity(identity));actors.orders.set_target(identity,Vector3(.5,1.93,2.5))
 for i in 3:await physics_frame
 for i in 480:
  await physics_frame
  actors.update_simulation(1.0/60,Vector3.ZERO,true,func(_bounds: AABB):return true)
 var failures=0
 for handle in handles:
  var point: Vector3=actors.store.get_position(handle);var ok=point.distance_to(Vector3(.5,1.93,2.5))<.25
  if not ok:failures+=1
  print("PASS " if ok else "FAIL ","stair origin ",handle," end=",point," status=",actors.pool.navigation_status(handle))
 scene.free();await process_frame;print("ACTOR_STAIR_ORIGINS failures=",failures);quit(1 if failures else 0)
