# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 var deadline:int=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"actual world loads")
 if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 if game.session_menu.developer:game.session_menu.toggle_developer()
 if game.actors.pool==null:check(game.actors.enable(),"actor simulation enabled")
 var point:Vector3=game.player.position+Vector3(0,10,0)
 var identity:int=game.actors.spawn(point)
 var handle:int=game.actors.store.resolve_identity(identity)
 game.actors.select_near(point)
 # Only the first actor has a collision body. Other stationary records share
 # its position, as can happen before activation or after authority updates.
 var others:=PackedInt64Array()
 for i in 80:others.append(game.actors.store.spawn(point,Vector3.ZERO))
 var old_query:Dictionary=game.actors.store.query_sphere_nearest(point,0.01,1,64)
 check(not old_query.complete,"dense position lookup is incomplete")
 game.camera.global_position=point+Vector3(0,0,2);game.camera.look_at(point)
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.player_hud.equip(0)
 for frame in 4:await physics_frame
 var target:Dictionary=game.world_attack.target()
 check(target.get("kind")=="actor" and target.get("id")==identity and target.get("handle")==handle,"physics hit identifies its exact actor despite coincident records")
 if target.get("id")==identity:
  for hit in 7:game.world_attack.apply_target(target)
  check(game.actors.store.resolve_identity(identity)==0,"attacked actor is retired")
  var intact:=true
  for other in others:intact=intact and game.actors.store.contains(other)
  check(intact,"all eighty neighbouring records remain intact")
 game.terrain.shutdown();game.free();await process_frame
 print("ACTOR_ATTACK_IDENTITY failures=",failures)
 quit(1 if failures else 0)
