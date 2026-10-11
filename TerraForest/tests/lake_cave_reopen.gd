# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://reports/lake_cave_world/result.json"))
 if data.failures!=0 or not str(data.slot).begins_with("lake_cave_"):quit(2);return
 var requested=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--world-slot="):requested=arg.trim_prefix("--world-slot=")
 if requested!=data.slot:quit(2);return
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60
 var deadline=Time.get_ticks_msec()+30000
 while (game.loading_active or game.lakes.statistics().ready!=4) and Time.get_ticks_msec()<deadline:await process_frame
 check(game.terrain.save_slot==data.slot and game.lakes.statistics().ready==4,"fresh process loads the exact copied cave world")
 var pocket: Vector3=str_to_var("Vector3"+data.pocket)
 var seed: Vector3=str_to_var("Vector3"+data.seed)
 check(is_equal_approx(game.lakes.depth_at(pocket),data.depth),"fresh process retains flooded pocket depth")
 game.teleport(seed+Vector3.UP*12,seed.y+12);deadline=Time.get_ticks_msec()+20000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 game.set_physics_process(false);game._clear_motion();game.fly=true;game.needs_floor_spawn=false
 game.player.position=pocket-Vector3.UP*1.1;game.headlamp.visible=true;game.camera.look_at(seed)
 for i in 4:await physics_frame
 game.water_camera.update()
 var roof: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(pocket,pocket+Vector3.UP*5,1))
 check(not roof.is_empty() and game._player_water_depth()>5 and game.water_camera.underwater,"restored cave roof and actual player immersion agree")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/lake_cave_world/underground.png")
 game.player.position=seed+Vector3.UP*12
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("LAKE_CAVE_REOPEN failures=",failures);quit(1 if failures else 0)
