# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var game: Node
var messages: Array[String]=[]
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var slot=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if not slot.begins_with("actor_settlement_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60
 game.terrain.message_changed.connect(func(message: String):messages.append(message))
 var deadline=Time.get_ticks_msec()+30000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 game.set_physics_process(false);game._clear_motion();game.needs_floor_spawn=false;game.fly=true
 check(not game.loading_active and game.actors.pool!=null,"saved furnished world loads with native actors")
 check(game.structures.model("furniture/table/v1").get_ids().size()==4,"all four furnished cottage tables are present")
 var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://docs/evidence/generated_furnished/manifest.json"))
 var origin=Vector3(manifest.target[0],manifest.target[1],manifest.target[2])
 var room=Transform3D(Basis(),Vector3(origin.x+4.5,origin.y+2,game.road_palette.prepared_streets[0].ends[0].z-14.5))
 var start=room*Vector3(0,-1.07,9);var goal=room*Vector3(0,.93,2.5)
 game.player.position=start+Vector3(3,2,2);game.terrain.focus=start;game.structures.set_model_focus(start)
 game.camera.global_position=start+Vector3(0,2.5,4);game.camera.look_at(goal)
 for i in 90:await physics_frame
 var identity: int=game.actors.spawn(start);var handle: int=game.actors.store.resolve_identity(identity)
 game.actors.orders.set_target(identity,goal)
 var delta=1.0/Engine.physics_ticks_per_second;var trace: Array=[];var moving=false;var peak_work=0
 for tick in int(6.0/delta):
  await physics_frame
  game.actors.update_simulation(delta,start,true,game._actor_collision_ready)
  peak_work=maxi(peak_work,game.actors.simulation_status.route_work)
  var point: Vector3=game.actors.store.get_position(handle)
  if tick%30==0:trace.append({"tick":tick,"position":point,"navigation":game.actors.pool.navigation_status(handle)})
  if point.distance_to(start)>.8:moving=true;break
 check(moving,"actor begins the authored furnished-settlement route")
 if moving:
  var saved: Vector3=game.actors.store.get_position(handle)
  messages.clear();game.terrain.save_world();deadline=Time.get_ticks_msec()+15000
  while not messages.any(func(m):return m.begins_with("World saved and verified")) and Time.get_ticks_msec()<deadline:await process_frame
  check(messages.any(func(m):return m.begins_with("World saved and verified")),"normal world save verifies the in-progress destination")
  var epoch: int=game.terrain.epoch;game.terrain.reload_world();deadline=Time.get_ticks_msec()+20000
  while (game.terrain.epoch==epoch or not game.terrain.world_ready or game.loading_active) and Time.get_ticks_msec()<deadline:await process_frame
  check(game.terrain.epoch>epoch and not game.actors.store.contains(handle) and game.actors.pool.active_handles().is_empty(),"world reload retires old actor physics handles")
  handle=game.actors.store.resolve_identity(identity)
  check(game.actors.store.get_position(handle)==saved and game.actors.orders.get_target(identity).get("target")==goal,"world reload restores exact actor position and destination")
  game.terrain.focus=start;game.structures.set_model_focus(start)
  for i in 60:await physics_frame
  for tick in int(8.0/delta):
   await physics_frame
   game.actors.update_simulation(delta,start,true,game._actor_collision_ready)
   peak_work=maxi(peak_work,game.actors.simulation_status.route_work)
   if tick%30==0:trace.append({"reload_tick":tick,"position":game.actors.store.get_position(handle),"navigation":game.actors.pool.navigation_status(handle)})
   if game.actors.pool.navigation_status(handle).state=="arrived":break
  check(game.actors.store.get_position(handle).distance_to(goal)<.25,"saved actor climbs entrance and reaches furnished interior")
 check(peak_work<=12,"integrated navigation retains shared planner work cap")
 DirAccess.make_dir_recursive_absolute("res://reports/actor_settlement_navigation")
 var file=FileAccess.open("res://reports/actor_settlement_navigation/result.json",FileAccess.WRITE)
 file.store_string(JSON.stringify({"failures":failures,"slot":slot,"start":start,"goal":goal,"trace":trace,"peak_work":peak_work},"  "));file.close()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/actor_settlement_navigation/route.png")
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("ACTOR_SETTLEMENT_NAVIGATION failures=",failures);quit(1 if failures else 0)
