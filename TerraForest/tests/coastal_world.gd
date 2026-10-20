# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
var game:Node3D
var failed:=false
func require(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 failed=failed or not ok
func water_ready()->bool:
 var end:=Time.get_ticks_msec()+30000
 while Time.get_ticks_msec()<end:
  if game.lakes.statistics().render_ready:return true
  await process_frame
 return false
func click(point:Vector3,button:int)->void:
 game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.camera.global_position=point+Vector3.UP*2;game.camera.look_at(point,Vector3.FORWARD)
 var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true
 game._unhandled_input(event)
 var end:=Time.get_ticks_msec()+6000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<end:await process_frame
 require(await water_ready(),"bucket publication settled")
func horizon_cost()->Dictionary:
 RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
 var result:Dictionary={}
 for enabled:bool in [false,true]:
  game.lakes._ocean_horizon.visible=enabled
  for frame in 30:await process_frame
  var samples:Array[float]=[]
  for frame in 90:
   await process_frame
   samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
  samples.sort()
  result["on" if enabled else "off"]={"gpu_median_ms":samples[45],"gpu_p95_ms":samples[85]}
 return result
func run()->void:
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 game.teleport(Vector3(39,43,1008))
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 require(game.terrain.backend.world_generator==18,"saved coastal terrain loaded")
 require(await water_ready() and game.lakes.statistics().lakes==1,"cached inlet loaded through lake runtime")
 var seam:Dictionary=game.lakes.water.raycast_surface(Vector3(0.01,41,1008.25),Vector3(0.01,39,1008.25))
 require(seam.get("hit",false) and absf(seam.get("point",Vector3.ZERO).y-40.0)<0.001,"native water meets offshore plane at exact sea level")
 require(game.generated_region.describe(42,18).places.size()==3,"coast and both settlements share saved world")
 if game.session_menu.developer:game.session_menu.toggle_developer()
 var inventory=game.player_hud.inventory
 inventory.grant(401,1,0);require(game.player_hud.equip_item(401),"normal gameplay bucket equipped")
 var slot:int=game.player_hud.active_slot
 var total:int=game.lakes.statistics().water_ml
 await click(Vector3(8.25,40,1008.25),MOUSE_BUTTON_LEFT)
 require(inventory.snapshot().slots[slot].water_ml==1000000 and game.lakes.statistics().water_ml==total-1000000,"coastal scoop transfers one unit")
 await click(Vector3(8.25,39.9,1008.25),MOUSE_BUTTON_RIGHT)
 require(inventory.snapshot().slots[slot].water_ml==0 and game.lakes.statistics().water_ml==total,"coastal return restores exact quantity")
 var saved:PackedByteArray=game.lakes.capture_snapshot();var copy=ClassDB.instantiate("NativeRegionalWater")
 require(copy.restore_snapshot(saved) and copy.statistics().water_ml==total,"edited coastal snapshot restores")
 game.camera.global_position=Vector3(39,44.7,1008);game.camera.look_at(Vector3(0,40,1008))
 for frame in 120:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/coastal_near.png")
 game.camera.global_position=Vector3(32,76,1045);game.camera.look_at(Vector3(8,40,1008))
 for frame in 120:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/coastal_overview.png")
 print("HORIZON_COST ",await horizon_cost())
 print("COASTAL_STATS ",game.lakes.statistics())
 print("COASTAL_WORLD failures=",1 if failed else 0)
 game.free();quit(1 if failed else 0)
