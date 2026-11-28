# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:=""
var game:Node
func _initialize()->void:
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
 run.call_deferred()
func check(ok:bool,label:String)->bool:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label);return ok
func wait_for(action:Callable,seconds:float)->bool:
 var deadline:=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:
  if action.call():return true
  await process_frame
 return false
func run()->void:
 if folder.is_empty() or not "--snapshot-readonly" in OS.get_cmdline_user_args():quit(2);return
 ProjectSettings.set_setting("terraforest/offscreen_session",true)
 var slot:=""
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
 var normal:Dictionary=preload("res://demo/world_launch.gd").command(slot,false,36,1703,true)
 if not check(normal.get("ok",false),"ordinary launcher accepts the existing island"):quit(1);return
 for flag:String in ["--ground-cover","--actors","--vehicle-fleet","--gameplay-construction"]:
  check(flag in normal.args and flag in OS.get_cmdline_user_args(),"human launcher matches ordinary content flag "+flag)
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.max_fps=60;root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,150),"existing island ready read-only"):await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 check(game.temporary_world and game.ground_enabled and game.ground_cover.is_processing(),"ground cover enabled in protected review")
 var cover:Node=game.ground_cover
 check(await wait_for(func():return cover.resident.size()==cover._wanted.size() and cover._requests.is_empty() and cover._dirty.is_empty(),40),"native cover population settled")
 var counts:Array=[]
 for batch:Node in cover.batches:counts.append(batch.get_ids().size())
 check(counts.size()>=9 and counts[2]>0,"natural grass instances published")
 check(counts.size()>=9 and counts[1]>0,"natural fern instances published")
 var center:Vector3=game.player.global_position;var best:=INF
 for owner:Variant in cover.resident:
  var row:Dictionary=cover.resident[owner][2];var transforms:PackedFloat32Array=row.transforms
  for index in row.ids.size():
   var point:=Vector3(transforms[index*12+3],transforms[index*12+7],transforms[index*12+11]);var distance:=point.distance_to(game.player.global_position)
   if distance>8 and distance<best:best=distance;center=point
 check(best<64,"nearby natural grass view located")
 game.player_hud.set_open(false);game.player_hud.visible=false;game.hud.hide();game.status.hide();game.help.hide()
 game.camera.global_position=center+Vector3(1,1.65,4);game.camera.look_at(center+Vector3(0,.15,-4))
 for frame in 30:await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(folder.path_join("island_grass_restored.png"))
 var data:Dictionary={"checks":checks,"failures":failures,"species_counts":counts,"center":center,"scope":"Read-only island with normal launcher content flags; grass presence, not density or FPS acceptance."}
 FileAccess.open(folder.path_join("ecology.json"),FileAccess.WRITE).store_string(JSON.stringify(data,"  "))
 await finish()
func finish()->void:
 if is_instance_valid(game):game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
 for frame in 8:await process_frame
 print("ISLAND_ECOLOGY checks=",checks," failures=",failures);quit.call_deferred(1 if failures else 0)
