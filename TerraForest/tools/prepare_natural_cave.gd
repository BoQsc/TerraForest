# SPDX-License-Identifier: 0BSD
extends SceneTree
const Checkpoint=preload("res://demo/cave_checkpoint.gd")
var game:Node
var evidence:=""
func wait_until(predicate:Callable,seconds:int)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func require(ok:bool,message:String)->bool:
 print("PASS " if ok else "FAIL ",message)
 return ok
func _initialize()->void:run.call_deferred()
func run()->void:
 var slot:=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--checkpoint-report="):evidence=arg.trim_prefix("--checkpoint-report=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("cave_stage_"):quit(2);return
 game=load("res://demo/world.tscn").instantiate();game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not require(await wait_until(func():return not game.loading_active,180),"generated cave world loads"):await finish(false);return
 if not require(game.terrain.backend.world_generator==6 and game.terrain.backend.world_seed==1703 and not game.temporary_world,"persistent generator6 seed1703 world"):await finish(false);return
 game.set_physics_process(false);game._clear_motion()
 var reopening:bool="--reopen-checkpoint" in OS.get_cmdline_user_args()
 if reopening:
  var expected:Dictionary=FileAccess.open(evidence,FileAccess.READ).get_var()
  if not require(game.player.position.distance_to(expected.position)<0.1 and not game.fly,"saved on-foot cave entrance restores without relocation"):await finish(false);return
  if not require(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"inventory and tool wear restore exactly"):await finish(false);return
 else:
  var route:Dictionary=Checkpoint.route()
  if not require(not route.is_empty(),"native generator finds cave entrance"):await finish(false);return
  Checkpoint.position_player(game,route)
  if not require(await wait_until(func():return not game.loading_active,90),"entrance collision arrives"):await finish(false);return
 game.set_physics_process(true);game.headlamp.visible=true
 for frame in 12:await physics_frame
 game.set_physics_process(false);game._clear_motion()
 if not require(game.player.is_on_floor() and game.construction_inventory.gameplay and not game.session_menu.developer,"grounded player in ordinary resource-cost gameplay"):await finish(false);return
 if not require(await wait_until(func():return not game.lakes.capture_snapshot().is_empty(),60),"generated components ready for compound save"):await finish(false);return
 if not reopening:
  var file:=FileAccess.open(evidence,FileAccess.WRITE)
  file.store_var({"position":game.player.position,"inventory":game.player_hud.inventory.capture_storage_snapshot()});file.close()
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence+(".reopened.png" if reopening else ".created.png"))
 await finish(true)
func finish(ok:bool)->void:
 game.shutdown_requested=true
 if ok:ok=await game.terrain.shutdown_after_edits()
 else:game.terrain.shutdown()
 game.free();await process_frame
 print("NATURAL_CAVE_PREPARATION failures=",0 if ok else 1)
 quit(0 if ok else 1)
