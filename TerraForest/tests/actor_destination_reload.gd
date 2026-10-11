# SPDX-License-Identifier: 0BSD
extends SceneTree
# Actor-component archive round trip; terrain payload is deliberately a fixture.
class RestoreOwner extends Node:
 var snapshot_restore_ok:=true
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var scene=Node3D.new();root.add_child(scene)
 var body=StaticBody3D.new();body.position=Vector3(0,-.5,0);body.collision_layer=1;scene.add_child(body)
 var shape=BoxShape3D.new();shape.size=Vector3(16,1,16);var collision=CollisionShape3D.new();collision.shape=shape;body.add_child(collision)
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 var owner=RestoreOwner.new();scene.add_child(owner)
 var actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors);actors.prepare(persistence);actors.enable(2)
 persistence._terrain=owner
 var identity: int=actors.spawn(Vector3(-3,.93,0));var handle: int=actors.store.resolve_identity(identity);var goal=Vector3(3,.93,0)
 actors.orders.set_target(identity,goal)
 for i in 3:await physics_frame
 var delta=1.0/Engine.physics_ticks_per_second
 for i in int(.6/delta):
  await physics_frame
  actors.update_simulation(delta,Vector3.ZERO,true,func(_bounds: AABB):return true)
 var saved_point: Vector3=actors.store.get_position(handle)
 check(saved_point.x>-3 and saved_point.x<2,"capture a moving actor before arrival")
 var sections: Dictionary=persistence._capture().sections
 check(sections.keys()==["world_actors","actor_orders"],"only authoritative actor records and orders are captured")
 sections["terrain"]=PackedByteArray([1,2,3])
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var path=ProjectSettings.globalize_path("user://actor_destination_%d_%d.trw"%[OS.get_process_id(),Time.get_ticks_usec()])
 DirAccess.make_dir_recursive_absolute(path.get_base_dir())
 var encoded: PackedByteArray=archive.encode(sections)
 check(archive.acquire(path) and archive.publish(path,encoded)==OK,"publish actor component archive to isolated disk file")
 var decoded: Dictionary=archive.decode(archive.read(path));archive.release()
 if not decoded.get("ok",false):check(false,"decode saved archive");scene.free();quit(1);return
 persistence._restore(decoded.sections,1)
 check(owner.snapshot_restore_ok and not actors.store.contains(handle) and actors.pool.active_handles().is_empty(),"reload retires active proxies and invalidates old runtime handles")
 check(actors.store.get_position(actors.store.resolve_identity(identity))==saved_point and actors.orders.get_target(identity).target==goal,"reload restores exact position and persistent destination")
 actors.free();persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors);actors.prepare(persistence)
 persistence._terrain=owner;persistence._restore(decoded.sections,2)
 check(owner.snapshot_restore_ok and actors.pool==null and actors.orders.get_target(identity).target==goal,"new component instance restores orders before activating physics")
 actors.enable(2);handle=actors.store.resolve_identity(identity)
 var peak_work=0
 for i in int(3.0/delta):
  await physics_frame
  actors.update_simulation(delta,Vector3.ZERO,true,func(_bounds: AABB):return true)
  peak_work=maxi(peak_work,actors.simulation_status.route_work)
 check(actors.store.get_position(handle).distance_to(goal)<.2 and actors.pool.navigation_status(handle).state=="arrived" and peak_work<=12,"restored destination replans and arrives under the shared work cap")
 DirAccess.remove_absolute(path);DirAccess.remove_absolute(path+".lock")
 scene.free();await process_frame
 print("ACTOR_DESTINATION_RELOAD failures=",failures);quit(1 if failures else 0)
