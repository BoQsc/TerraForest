# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var output:="";var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--crossing-output="):output=arg.trim_prefix("--crossing-output=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if output.is_empty() or not slot.begins_with("actor_crossing_"):quit(2);return
 var game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:int=Time.get_ticks_msec()+45000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 check(not game.loading_active,"furnished settlement loads")
 if game.loading_active:game.terrain.shutdown();game.free();quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var street:Dictionary=game.road_palette.prepared_streets[0]
 var direction:Vector3=(street.ends[1]-street.ends[0]).normalized()
 var side:=Vector3(-direction.z,0,direction.x)
 var a:Vector3=street.ends[0]+direction*5+Vector3.UP*0.93
 var b:Vector3=street.ends[0]+direction*17+Vector3.UP*0.93
 game.player.position=a+side*5;game.terrain.focus=a
 game.camera.global_position=(a+b)*0.5+side*10+Vector3.UP*7;game.camera.look_at((a+b)*0.5)
 for frame in 90:await physics_frame
 var first:int=game.actors.spawn(a);var second:int=game.actors.spawn(b)
 var h1:int=game.actors.store.resolve_identity(first);var h2:int=game.actors.store.resolve_identity(second)
 game.actors.orders.set_target(first,b);game.actors.orders.set_target(second,a)
 var minimum:=INF;var trace:Array=[];var peak_work:=0
 for frame in 720:
  await physics_frame
  game.actors.update_simulation(1.0/60,(a+b)*0.5,true,game._actor_collision_ready)
  var p:Vector3=game.actors.store.get_position(h1);var q:Vector3=game.actors.store.get_position(h2)
  minimum=minf(minimum,p.distance_to(q));peak_work=maxi(peak_work,game.actors.simulation_status.route_work)
  if frame%12==0:trace.append({"a":p,"b":q,"a_state":game.actors.pool.navigation_status(h1),"b_state":game.actors.pool.navigation_status(h2)})
 check(minimum>=0.69,"street crossing preserves separation: %.3f m"%minimum)
 check(game.actors.store.get_position(h1).distance_to(b)<0.3 and game.actors.store.get_position(h2).distance_to(a)<0.3,"both actors arrive through ordinary main-world navigation")
 check(peak_work<=12,"shared route planning budget remains bounded")
 await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output+"/street.png")
 var file:=FileAccess.open(output+"/motion.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"minimum_separation":minimum,"peak_route_work":peak_work,"trace":trace},"  "));file.close()
 game.terrain.shutdown();game.free();await process_frame
 print("ACTOR_STREET_CROSSING failures=",failures);quit(1 if failures else 0)
