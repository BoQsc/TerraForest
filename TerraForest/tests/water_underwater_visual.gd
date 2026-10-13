# SPDX-License-Identifier: 0BSD
extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 if not game.has_meta("water_bucket_review_ready"):quit(1);return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(entry.seed.x,entry.level,entry.seed.z)
 game.camera.global_position=center+Vector3(0,-1.3,4)
 game.camera.look_at(center+Vector3(0,-2.0,-4),Vector3.UP)
 game.water_camera.update()
 print("UNDERWATER_DEPTH ",game.lakes.depth_at(game.camera.global_position))
 var shader:Shader=game.lakes._material.shader
 var installed:=shader.code
 shader.code=installed.replace(", fog_disabled", "")
 for frame in 12:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_underwater_before.png")
 shader.code=installed
 for frame in 12:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_underwater_after.png")
 for instance:MeshInstance3D in game.lakes._meshes.values():instance.visible=false
 for frame in 12:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_underwater_reference.png")
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_UNDERWATER_VISUAL failures=0");quit()
