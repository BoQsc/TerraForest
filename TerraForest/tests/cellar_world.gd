# SPDX-License-Identifier: 0BSD
extends "res://tools/prepare_combined_world.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await wait_until(func():return not game.loading_active,90):quit(1);return
 game.set_physics_process(false);game._clear_motion();game.structure_mode=true
 var existing:bool="--existing-cellar" in OS.get_cmdline_user_args()
 var ok:=true
 if existing:
  var layout:Dictionary=preload("res://addons/volumetric_terrain/generated_layout.gd").describe(game.terrain.backend.world_seed,game.terrain.backend.world_generator)
  var center:Vector3=layout.sites[1].position+Vector3(20,0,20)
  game.teleport(center+Vector3(15,0,15))
  ok=await wait_until(func():return not game.loading_active,60)
  game.set_physics_process(false);game._clear_motion()
  game.site_preparation.plan={"target":Vector3i(center)-Vector3i(0,5,0)}
 else:ok=await prepare_cellar_location()
 if ok:
  game.construction_palette.survey_dialog.hide()
  print("CELLAR_STAGE interior ready")
  var origin:Vector3=Vector3(game.site_preparation.plan.target)
  game.needs_floor_spawn=false;game.fly=true;game.player.position=origin+Vector3(0,1.1,-1)
  game.terrain.focus=game.player.position
  game.camera.position=Vector3(0,1.6,0);game.camera.look_at(origin+Vector3(1.5,4,3))
  game.headlamp.visible=true
  for frame in 180:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/cellar_room.png")
  game.fly=false;game.player.position=origin+Vector3(1.5,1.05,3.05);game.player.velocity=Vector3.ZERO;game.player.rotation=Vector3.ZERO
  game.camera.transform=Transform3D(Basis.IDENTITY,Vector3(0,1.6,0));game.app_focused=true
  print("CELLAR_STAGE climbing")
  game.controls.held[KEY_W]=true
  for frame in 300:
   await physics_frame
   if game.player.position.z<origin.z+1.5:game.controls.held.clear()
   game._physics_process(1.0/60)
  game.controls.held.clear()
  var climbed:bool=game.player.position.y>origin.y+6.8 and game.player.position.z<origin.z+2
  print("PASS " if climbed else "FAIL ","cellar ladder reaches house floor actual=",game.player.position-origin)
  ok=ok and climbed
  game.controls.held[KEY_S]=true
  for frame in 300:
   await physics_frame
   if game.player.position.y<origin.y+1.2:game.controls.held.clear()
   game._physics_process(1.0/60)
  game.controls.held.clear()
  var descended:bool=game.player.position.y<origin.y+1.2 and game.player.position.y>origin.y+.8
  print("PASS " if descended else "FAIL ","cellar return reaches lower floor actual=",game.player.position-origin)
  ok=ok and descended
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/cellar_interior.png")
 print("CELLAR_WORLD failures=",0 if ok else 1)
 if not ok:print("CELLAR_DIAGNOSTIC status=",game.site_preparation.status," reason=",game.site_preparation.reason," dialog=",game.construction_palette.survey_dialog.dialog_text)
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;quit(0 if ok else 1)
