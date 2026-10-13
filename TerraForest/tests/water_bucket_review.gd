# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize():call_deferred("run")
func published(game)->bool:
 var deadline:=Time.get_ticks_msec()+6000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  if game.lakes._pending_bucket.is_empty() and game.lakes.statistics().render_ready:return true
 return false
func held(game)->int:
 return int(game.player_hud.inventory.snapshot().slots[game.player_hud.active_slot].get("water_ml",-1))
func run():
 var game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 var ok:bool=game.has_meta("water_bucket_review_ready") and game.temporary_world and game.player_hud.active_item==401
 for frame in 8:await process_frame
 var start:Vector3=game.camera.global_position;var end:Vector3=start-game.camera.global_basis.z*3.5
 var hit:Dictionary=game.lakes.water.raycast_surface(start,end)
 ok=ok and hit.hit and hit.normal.y>0.5 and start.y>hit.point.y+0.5
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_bucket_review.png")
 var before:int=game.lakes.statistics().water_ml
 game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;game._unhandled_input(click)
 click.pressed=false;game._unhandled_input(click)
 var scoop_ready:bool=await published(game)
 ok=ok and scoop_ready and held(game)==1000000 and game.lakes.statistics().water_ml==before-1000000
 click.button_index=MOUSE_BUTTON_RIGHT;click.pressed=true;game._unhandled_input(click)
 click.pressed=false;game._unhandled_input(click)
 var pour_ready:bool=await published(game)
 ok=ok and pour_ready and held(game)==0 and game.lakes.statistics().water_ml==before
 print("BUCKET_REVIEW ",JSON.stringify({"camera":start,"feet":game.player.global_position,"pitch":game.pitch,"camera_rotation":game.camera.rotation,"ready":game.has_meta("water_bucket_review_ready"),"temporary":game.temporary_world,"initial_hit":hit,"pass":ok}))
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_BUCKET_REVIEW failures=",0 if ok else 1);quit(0 if ok else 1)
