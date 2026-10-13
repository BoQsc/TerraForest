# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):quit(1);return
 game.set_process(false);game.set_physics_process(false);game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:Vector3=entry.seed
 game.camera.global_position=Vector3(center.x,entry.level-1.2,center.z+4)
 game.camera.look_at(Vector3(center.x,entry.level-1.3,center.z-4),Vector3.UP)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_contact_underwater.png")
 game.camera.global_position=Vector3(center.x,entry.level+2,center.z+6)
 game.camera.look_at(Vector3(center.x,entry.level,center.z),Vector3.UP)
 for frame in 4:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_contact_above.png")
 print("WATER_CONTACT_VISUAL captured; visual inspection required")
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame;quit()
