# SPDX-License-Identifier: 0BSD
extends "res://tests/village_shop_review.gd"
var failures:=0
func check(ok:bool,label:String)->void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func footprint_ready(mask:PackedByteArray,column:Vector2i)->bool:
 for z in range(column.y-5,column.y+6):
  for x in range(column.x-5,column.x+6):
   if x<0 or z<0 or x>=500 or z>=500 or mini(mini(x,z),mini(499-x,499-z))>=35:continue
   if mask[x+z*500]==0:return false
 return true
func run()->void:
 var game=load("res://demo/world.tscn").instantiate()
 game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 var start:=Time.get_ticks_msec()
 game.teleport(Vector3(50,43,1000))
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 check(game.terrain.backend.world_generator==19,"surrounding coast profile loaded in actual world")
 var mask:=PackedByteArray()
 while Time.get_ticks_msec()-start<60000:
  await process_frame
  mask=game.lakes.water.ocean_publication_mask()
  if mask[12+500*250]>0 and game.lakes.statistics().render_ready:break
 check(mask[12+500*250]>0,"near coastal column replaces far proxy only after publication")
 var hit:Dictionary=game.lakes.water.raycast_surface(Vector3(50.25,41,1000.25),Vector3(50.25,39,1000.25))
 check(hit.get("hit",false) and absf(hit.get("point",Vector3.ZERO).y-40)<0.01,"published ocean surface is targetable at sea level")
 print("OCEAN_LOAD_MS ",Time.get_ticks_msec()-start," ",game.lakes.statistics())
 if game.session_menu.developer:game.session_menu.toggle_developer()
 var inventory=game.player_hud.inventory
 inventory.grant(401,1,0);check(game.player_hud.equip_item(401),"normal gameplay bucket equipped")
 var slot:int=game.player_hud.active_slot
 var total:int=game.lakes.statistics().water_ml
 for button:int in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
  game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  game.camera.global_position=Vector3(50.25,42,1000.25);game.camera.look_at(Vector3(50.25,39.9,1000.25),Vector3.FORWARD)
  var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true
  game._unhandled_input(event)
  var deadline:=Time.get_ticks_msec()+6000
  while Time.get_ticks_msec()<deadline:
   await process_frame
   if game.lakes._pending_bucket.is_empty() and game.lakes.statistics().render_ready:break
  if button==MOUSE_BUTTON_LEFT:
   check(inventory.snapshot().slots[slot].water_ml==1000000 and game.lakes.statistics().water_ml==total-1000000,"ocean scoop transfers exactly one unit")
  else:check(inventory.snapshot().slots[slot].water_ml==0 and game.lakes.statistics().water_ml==total,"ocean return restores quantity")
 var bytes:PackedByteArray=game.lakes.capture_snapshot();var restored=ClassDB.instantiate("NativeRegionalWater")
 check(restored.restore_snapshot(bytes) and restored.statistics().water_ml==total and restored.statistics().ocean_edited_regions>0,"actual ocean bucket edit snapshot restores")

 game.camera.global_position=Vector3(80,48,1000);game.camera.look_at(Vector3(0,40,1000))
 for frame in 90:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/surrounding_ocean_west.png")
 # Elevated image includes the shoreline/detail boundary, not only open water.
 game.camera.global_position=Vector3(95,90,1040);game.camera.look_at(Vector3(40,40,1000))
 for frame in 15:await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/surrounding_ocean_overview.png")
 if "--coast-travel" in OS.get_cmdline_user_args():
  var sites:=[Vector3(1950,43,1000),Vector3(50,43,50),Vector3(1000,43,50),Vector3(1000,43,1950),Vector3(50,43,1000)]
  for index in sites.size():
   var site:Vector3=sites[index];var began:=Time.get_ticks_msec()
   game.player.position=site;game.terrain.focus=site
   var column:=Vector2i(floori(site.x/4),floori(site.z/4))
   var end:=Time.get_ticks_msec()+60000
   while Time.get_ticks_msec()<end:
    await process_frame
    var coverage:PackedByteArray=game.lakes.water.ocean_publication_mask()
    if footprint_ready(coverage,column) and game.lakes.statistics().render_ready:break
   var coverage:PackedByteArray=game.lakes.water.ocean_publication_mask()
   check(footprint_ready(coverage,column),"travel destination %d full footprint published"%index)
   var target:=Vector3(site.x+0.25,40,site.z+0.25)
   var picked:Dictionary=game.lakes.water.raycast_surface(target+Vector3.UP,target-Vector3.UP)
   check(picked.get("hit",false) and absf(picked.get("point",Vector3.ZERO).y-40)<0.01,"destination %d target matches surface"%index)
   check(game.lakes.statistics().regions<1600 and not game.lakes.statistics().capacity_reached,"travel resident regions remain bounded")
   print("OCEAN_TRAVEL ",index," ms=",Time.get_ticks_msec()-began," regions=",game.lakes.statistics().regions," scene_meshes=",game.lakes._meshes.size())
   game.camera.global_position=site+Vector3(-45 if index==0 else 45,45,35)
   game.camera.look_at(target)
   for frame in 30:await process_frame
   await RenderingServer.frame_post_draw
   root.get_texture().get_image().save_png("res://reports/surrounding_ocean_travel_%d.png"%index)
 game.free();print("SURROUNDING_OCEAN_WORLD failures=",failures);quit(failures)
