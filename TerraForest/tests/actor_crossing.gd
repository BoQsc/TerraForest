# SPDX-License-Identifier: 0BSD
extends SceneTree
const Extension=preload("res://addons/world_runtime/world_runtime.gdextension")
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var scene:=Node3D.new();root.add_child(scene)
 var floor_body:=StaticBody3D.new();var collision:=CollisionShape3D.new()
 var shape:=BoxShape3D.new();shape.size=Vector3(20,1,20);collision.shape=shape
 floor_body.position.y=-0.5;floor_body.add_child(collision);scene.add_child(floor_body)
 var store=ClassDB.instantiate("NativeEntityStore");store.configure(100)
 var offset:=0.0 if "--head-on" in OS.get_cmdline_user_args() else 0.1
 var stationary:bool="--stationary" in OS.get_cmdline_user_args()
 var handles:=PackedInt64Array([store.spawn(Vector3(-3,0.93,0),Vector3.ZERO),store.spawn(Vector3(3,0.93,offset),Vector3.ZERO)])
 var pool=ClassDB.instantiate("NativeEntityActivation");scene.add_child(pool)
 check(pool.configure(store,2),"two-body pool configures")
 pool.select(Vector3(0,1,0),10,100)
 var goals:=PackedVector3Array()
 for handle in pool.active_handles():goals.append(Vector3(-3 if stationary else 3,0.93,0) if handle==handles[0] else Vector3(-5 if stationary else -3,0.93,offset))
 var minimum:=INF
 var drift:=0.0
 for frame in 480:
  await physics_frame
  pool.tick(goals,1.0/60,PackedByteArray([1,1]))
  minimum=minf(minimum,store.get_position(handles[0]).distance_to(store.get_position(handles[1])))
  if stationary:
   var position:Vector3=store.get_position(handles[0])
   drift=maxf(drift,Vector2(position.x+3,position.z).length())
 check(minimum>=0.69,"opposing routes retain capsule separation: %.3f m"%minimum)
 check(store.get_position(handles[0]).distance_to(Vector3(-3 if stationary else 3,0.93,0))<0.3 and store.get_position(handles[1]).distance_to(Vector3(-5 if stationary else -3,0.93,offset))<0.3,"both actors reach their destinations")
 if stationary:check(drift<0.001,"stationary actor holds its order throughout: %.4f m drift"%drift)
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report:=FileAccess.open("res://reports/actor_crossing.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"minimum_separation":minimum,"offset":offset}));report.close()
 scene.free();await process_frame
 print("ACTOR_CROSSING failures=",failures);quit(1 if failures else 0)
