# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake ready")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 game.session_menu.toggle_developer();game.session_menu.show_page("Water")
 var editor=game.session_menu.pages["Water"].get_child(0)
 var remove:Button;var add:Button;var instructions:=""
 for child in editor.get_children():
  if child is Label:instructions+=child.text
  if child is Button and child.text.begins_with("Remove water at aim"):remove=child
  if child is Button and child.text.begins_with("Add water at aim"):add=child
 check(remove!=null and add!=null,"Visible water controls are wired")
 if remove==null or add==null:await finish();return
 check(instructions.contains("1 m³") and not instructions.contains("1 L"),"Editor describes current whole-unit static water")
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var center:=Vector3(entry.seed.x,entry.level,entry.seed.z)
 game.camera.global_position=center+Vector3.UP
 game.camera.look_at(center+Vector3.UP*4,Vector3.FORWARD)
 var before:int=game.lakes.statistics().water_ml
 remove.pressed.emit()
 check(game.lakes.statistics().water_ml==before,"No-hit removal changes no water")
 check(game.session_menu.message.text.contains("Aim at visible water"),"No-hit removal reports no target, not success")
 game.camera.look_at(center-Vector3.UP,Vector3.FORWARD)
 var hit:Dictionary=game.lakes.water.raycast_surface(game.camera.global_position,game.camera.global_position-Vector3.UP*5)
 check(hit.hit,"Visible water target found")
 if hit.hit:
  var wet:Vector3=hit.point-Vector3.UP*.125
  remove.pressed.emit()
  check(await ready_water(),"Editor removal publishes")
  check(game.lakes.depth_at(wet)==0,"Removal reaches the aimed surface instead of the floor behind it")
  check(game.lakes.statistics().water_ml<before,"Successful removal changes water")
  check(game.session_menu.message.text.begins_with("Removed"),"Removal feedback uses actual removed amount")
 var dry:=center+Vector3(0,0,25)
 var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(dry+Vector3.UP*30,dry-Vector3.UP*30,1))
 check(not floor_hit.is_empty(),"Dry placement target exists")
 if not floor_hit.is_empty():
  game.camera.global_position=floor_hit.position+Vector3.UP*2
  game.camera.look_at(floor_hit.position,Vector3.FORWARD)
  before=game.lakes.statistics().water_ml;add.pressed.emit()
  deadline=Time.get_ticks_msec()+10000
  while Time.get_ticks_msec()<deadline:
   await process_frame
   if game.lakes._pending_dev.is_empty() and game.lakes.statistics().render_ready:break
  check(game.lakes.statistics().water_ml==before+1000000,"Editor places one whole unit on ordinary ground")
  check(game.session_menu.message.text=="Placed water","Queued completion reaches editor feedback")
  before=game.lakes.statistics().water_ml
  check(game.terrain.sculpt_sphere(floor_hit.position-Vector3.UP,0.5),"Start a real terrain edit")
  add.pressed.emit()
  check(game.session_menu.message.text=="Wait for the terrain edit to finish","Busy editor reports rejection instead of queued success")
  check(game.lakes.statistics().water_ml==before and game.lakes._pending_dev.is_empty(),"Rejected editor click does not change or queue water")
  check(await ready_water(),"Terrain edit completes normally")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/water_editor_actions.png")
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_EDITOR_ACTIONS failures=",failures);quit(failures)
