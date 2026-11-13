# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():call_deferred("run")
func run():
 var evidence:=""
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--check-evidence-dir="):evidence=argument.trim_prefix("--check-evidence-dir=")
 if evidence.is_empty():push_error("Use run_godot_check.py so captures have an admitted evidence directory");quit(2);return
 var game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+120000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):
  print("WATER_CONTACT_VISUAL startup_not_ready terrain=",game.terrain.world_ready," lakes=",game.lakes.statistics())
  game.terrain.shutdown();quit(1);return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:Vector3=entry.seed
 game.camera.global_position=Vector3(center.x,entry.level-1.2,center.z+4)
 game.camera.look_at(Vector3(center.x,entry.level-1.3,center.z-4),Vector3.UP)
 game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join("water_contact_underwater.png"))
 game.camera.global_position=Vector3(center.x,entry.level+2,center.z+6)
 game.camera.look_at(Vector3(center.x,entry.level,center.z),Vector3.UP)
 game.water_camera.update()
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence.path_join("water_contact_above.png"))
 var report:=FileAccess.open(evidence.path_join("water_visual.json"),FileAccess.WRITE)
 report.store_string(JSON.stringify({"lake":entry,"water":game.lakes.statistics(),"scope":"Fixed-camera geometry and immersion; frozen HUD FPS is not a performance measurement"},"  "));report.close()
 print("WATER_CONTACT_VISUAL captured; visual inspection required")
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame;quit()
