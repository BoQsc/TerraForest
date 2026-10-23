# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,90),"generated world opens"):await done();return
 game.set_physics_process(false);game._clear_motion()
 var cover=game.ground_cover
 if not check(cover!=null,"production ground cover enabled"):await done();return
 check(await wait_for(func():return cover.resident.size()>=25,35),"production woodland streams around player")
 var point:Vector3=game.player.position
 var closest:=INF
 for key in cover.resident:
  var row:Dictionary=cover.resident[key][2]
  for i in row.ids.size():
   var candidate:=Vector3(row.transforms[i*12+3],row.transforms[i*12+7],row.transforms[i*12+11])
   if candidate.distance_to(game.player.position)<closest:closest=candidate.distance_to(game.player.position);point=candidate
 check(closest<50,"natural grass present near loaded arrival")
 DirAccess.make_dir_recursive_absolute("res://reports/generated_vegetation_review")
 game.player_hud.visible=false
 for view in [Vector3(0,2.2,5),Vector3(0,24,27)]:
  game.camera.global_position=point+view;game.camera.look_at(point)
  for frame in 90:await process_frame
  await RenderingServer.frame_post_draw
  root.get_texture().get_image().save_png("res://reports/generated_vegetation_review/"+("near" if view.y<3 else "overhead")+".png")
 check(cover.rejected_batches==0,"no native vegetation publication failures")
 check(root.size==Vector2i(1920,1080),"1080p review")
 await done()
func done()->void:
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("GENERATED_VEGETATION_REVIEW failures=",failures);quit(1 if failures else 0)
