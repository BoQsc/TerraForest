# SPDX-License-Identifier: 0BSD
extends "res://tests/surrounding_ocean_world.gd"
var record_path:String
func samples(game:Node)->Array:
 var result:Array=[]
 for z in range(999,1003):
  for x in range(49,53):
   for y in [38.5,39.5,40.5]:result.append(game.lakes.depth_at(Vector3(x+0.25,y,z+0.25)))
 return result
func run()->void:
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--ocean-record="):record_path=argument.trim_prefix("--ocean-record=")
 if record_path.is_empty():quit(1);return
 var reopen:bool="--reopen-ocean-edit" in OS.get_cmdline_user_args()
 var game=load("res://demo/world.tscn").instantiate()
 game.max_fps=60;game.background_fps=60;root.add_child(game)
 if not await ready_world(game):quit(1);return
 check(game.terrain.save_slot.begins_with("ocean_persist_"),"isolated persistence slot")
 if failures:game.free();quit(1);return
 game.terrain.autosave_timer=-3600.0
 game.teleport(Vector3(50,43,1000))
 if not await ready_world(game):quit(1);return
 game.set_physics_process(false);game._clear_motion()
 var deadline:=Time.get_ticks_msec()+60000
 while Time.get_ticks_msec()<deadline:
  await process_frame
  if footprint_ready(game.lakes.water.ocean_publication_mask(),Vector2i(12,250)) and game.lakes.statistics().render_ready:break
 check(game.lakes.statistics().render_ready,"coastal water published")
 if game.session_menu.developer:game.session_menu.toggle_developer()
 var inventory=game.player_hud.inventory
 if not reopen:inventory.grant(401,1,0)
 check(game.player_hud.equip_item(401),"saved gameplay bucket available")
 var slot:int=game.player_hud.active_slot
 if not reopen:
  var original:Array=samples(game)
  check(game.lakes.depth_at(Vector3(50.25,39.5,1000.25))>0,"scoop target initially contains water")
  var total:int=game.lakes.statistics().water_ml
  game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
  game.camera.global_position=Vector3(50.25,42,1000.25);game.camera.look_at(Vector3(50.25,39.9,1000.25),Vector3.FORWARD)
  var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
  game._unhandled_input(event)
  deadline=Time.get_ticks_msec()+10000
  while Time.get_ticks_msec()<deadline:
   await process_frame
   if game.lakes._pending_bucket.is_empty() and game.lakes.statistics().render_ready:break
  check(inventory.snapshot().slots[slot].water_ml==1000000 and game.lakes.statistics().water_ml==total-1000000,"player scoop removes exactly one unit before save")
  var record:={"samples":samples(game),"edited":game.lakes.statistics().ocean_edited_regions}
  check(record.samples!=original,"local water occupancy changes after scoop")
  var saved:Array=[];game.terrain.save_completed.connect(func(ok:bool):saved.append(ok))
  game.terrain.changed_since_save=true;game.terrain.save_world()
  deadline=Time.get_ticks_msec()+30000
  while saved.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
  check(not saved.is_empty() and saved[0],"compound world save succeeds")
  if not failures:
   var file:=FileAccess.open(record_path,FileAccess.WRITE);file.store_string(JSON.stringify(record));file.close()
 else:
  var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(record_path))
  check(inventory.snapshot().slots[slot].water_ml==1000000,"full bucket survives fresh process")
  check(game.lakes.statistics().ocean_edited_regions==int(record.edited),"edited ocean ownership survives fresh process")
  var actual:Array=samples(game);var matches:bool=actual.size()==record.samples.size()
  for i in actual.size():matches=matches and absf(float(actual[i])-float(record.samples[i]))<0.0001
  check(matches,"48 local depth samples survive fresh process and residency refill")
 game.shutdown_requested=true
 check(await game.terrain.shutdown_after_edits(),"durable shutdown succeeds")
 var archive=ClassDB.instantiate("NativeWorldArchive")
 var saved:Dictionary=archive.decode(archive.read(ProjectSettings.globalize_path(game.terrain.backend.save_path)))
 var water_component:PackedByteArray=saved.get("sections",{}).get("volumetric_water",PackedByteArray())
 check(water_component.size()>=48 and water_component.slice(0,4).get_string_from_ascii()=="TFWS","canonical gameplay save references durable water checkpoint")
 game.free();print("OCEAN_EDIT_REOPEN failures=",failures," reopen=",reopen);quit(failures)
