# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var scene=Node3D.new();root.add_child(scene)
 var floor_body=StaticBody3D.new();floor_body.collision_layer=1;floor_body.position=Vector3(0,-.5,0);scene.add_child(floor_body)
 var shape=BoxShape3D.new();shape.size=Vector3(16,1,32);var collision=CollisionShape3D.new();collision.shape=shape;floor_body.add_child(collision)
 var persistence=preload("res://addons/world_runtime/world_persistence.gd").new()
 var actors=preload("res://addons/world_runtime/actor_world.gd").new();scene.add_child(actors);actors.prepare(persistence);actors.enable(16)
 var handles: Array=[];var first_ready: Array=[];var goals: Array=[]
 for i in 16:
  var point=Vector3(-3,.93,(i-7.5)*1.2);var identity: int=actors.spawn(point)
  handles.append(actors.store.resolve_identity(identity));goals.append(point+Vector3.RIGHT*6);first_ready.append(-1.0);actors.orders.set_target(identity,goals[-1])
 var distant: PackedInt64Array=actors.store.spawn_grid(1000,Vector3(1000,1,1000),1,Vector3.ZERO)
 check(distant.size()==1000,"one thousand sleeping records accompany sixteen active actors")
 var peak_work=0;var peak_active=0;var peak_planning_us=0;var peak_tick_us=0
 for i in 3:await physics_frame
 var delta=1.0/Engine.physics_ticks_per_second
 for tick in int(6.0/delta):
  await physics_frame
  var begin=Time.get_ticks_usec();actors.update_simulation(delta,Vector3.ZERO,true,func(_bounds: AABB):return true)
  peak_tick_us=maxi(peak_tick_us,Time.get_ticks_usec()-begin);peak_work=maxi(peak_work,actors.simulation_status.route_work);peak_active=maxi(peak_active,actors.pool.active_handles().size());peak_planning_us=maxi(peak_planning_us,actors.simulation_status.route_planning_us)
  for i in 16:
   if first_ready[i]<0 and actors.pool.navigation_status(handles[i]).state in ["following","arrived"]:first_ready[i]=(tick+1)*delta
 check(first_ready.all(func(t):return t>0 and t<=1.0),"all sixteen clear six-metre routes become usable within one second")
 var arrived=true
 for i in 16:arrived=arrived and actors.store.get_position(handles[i]).distance_to(goals[i])<.2
 check(arrived,"all sixteen actors arrive without hand-authored waypoints")
 check(peak_work<=12 and peak_active==16 and actors.pool.get_child_count()==16,"shared planner work and physics pool stay capped")
 check(actors.store.get_position(distant[0])==Vector3(1000,1,1000),"distant record stays asleep")
 var output={"failures":failures,"stored":1016,"active":peak_active,"first_ready_seconds":first_ready,"peak_work":peak_work,"peak_planning_us":peak_planning_us,"peak_adapter_us":peak_tick_us,"scope":"Headless clear-path latency and activation fixture; no render, crowd avoidance, settlement or thermal qualification"}
 DirAccess.make_dir_recursive_absolute("res://reports/actor_planning_latency");var file=FileAccess.open("res://reports/actor_planning_latency/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"  "));file.close();print(JSON.stringify(output))
 scene.free();await process_frame;print("ACTOR_PLANNING_LATENCY failures=",failures);quit(1 if failures else 0)
