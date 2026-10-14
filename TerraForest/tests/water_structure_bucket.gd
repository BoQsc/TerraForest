# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
var results:Dictionary={}
func click_bucket(point:Vector3,button:int):
 game.app_focused=true;Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
 game.camera.global_position=point+Vector3.UP*2
 game.camera.look_at(point,Vector3.FORWARD)
 var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=true
 game._unhandled_input(event)
 var deadline:=Time.get_ticks_msec()+6000
 while not game.lakes._pending_bucket.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
 check(await ready_water(),"Bucket edit finishes publishing")
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual bucket world ready")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 if game.session_menu.developer:game.session_menu.toggle_developer()
 var inventory=game.player_hud.inventory;var slot:int=game.player_hud.active_slot
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var origin:=Vector3i(floori(entry.seed.x),floori(entry.level)-1,floori(entry.seed.z))
 game.construction_inventory.gameplay=false
 results.cases=[]
 for shape:int in [3,4,6]:
  var target:=origin+Vector3i(4 if shape==3 else 6 if shape==4 else -4,0,0)
  var inside:=Vector3(target)+(Vector3(.5,.8,.9) if shape==3 else Vector3(.5,.2,.8) if shape==4 else Vector3(.5,.5,.5))
  var outside:=Vector3(target)+(Vector3(.5,.8,.1) if shape==3 else Vector3(.5,.8,.2) if shape==4 else Vector3(.9,.9,.9))
  check(game.construction_inventory.place_block(game.structures.blocks,inventory,target,shape),"Construct bucket-test shape")
  check(await ready_water(),"Building occupancy ready for bucket")
  var before:int=game.lakes.statistics().water_ml
  check(inventory.snapshot().slots[slot].water_ml==0,"Bucket starts empty")
  await click_bucket(outside,MOUSE_BUTTON_LEFT)
  check(inventory.snapshot().slots[slot].water_ml==1000000 and game.lakes.statistics().water_ml==before-1000000,"Normal left click collects exactly one unit beside building")
  check(game.lakes.depth_at(inside)==0,"Scoop leaves building interior dry")
  await click_bucket(outside,MOUSE_BUTTON_RIGHT)
  check(inventory.snapshot().slots[slot].water_ml==0 and game.lakes.statistics().water_ml==before,"Normal right click returns exactly one unit beside building")
  check(game.lakes.depth_at(inside)==0 and game.lakes.depth_at(outside)>0,"Returned water respects solid and refills adjacent space")
  results.cases.append({"shape":shape,"notice":game.telemetry.text})
 # History restores building geometry, never refunds water destroyed by a solid.
 var target:=origin+Vector3i(8,0,0)
 check(game.construction_inventory.place_block(game.structures.blocks,inventory,target,5),"Place post for edit-history check")
 check(await ready_water(),"Post replacement publishes")
 var replaced:Dictionary=amounts(game.lakes.capture_snapshot())
 check(game.structures.blocks.undo(),"Undo constructed post")
 check(await ready_water(),"Undo occupancy publishes")
 check(game.structures.blocks.get_cell(target)==0 and amounts(game.lakes.capture_snapshot())==replaced,"Undo removes post without restoring deleted water")
 check(game.structures.blocks.redo(),"Redo constructed post")
 check(await ready_water(),"Redo occupancy publishes")
 check(game.structures.blocks.get_cell(target)==5 and game.lakes.depth_at(Vector3(target)+Vector3.ONE*.5)==0,"Redo keeps solid interior dry")
 # Paging unchanged solids must preserve cached water; replacement must notify.
 var region:=Vector3i(floori(float(target.x)/64),floori(float(target.y)/64),floori(float(target.z)/64))
 var region_bytes:PackedByteArray=game.structures.blocks.capture_region(region)
 var before_page:PackedByteArray=game.lakes.capture_snapshot()
 check(game.structures.blocks.unload_region(region_bytes),"Unload authored building region")
 check(game.lakes.capture_snapshot()==before_page,"Unloading solids does not erase water occupancy cache")
 check(game.structures.blocks.restore_region(region_bytes,PackedByteArray()),"Reload unchanged building region")
 check(game.lakes.capture_snapshot()==before_page,"Paging unchanged region preserves exact water state")
 check(game.structures.blocks.set_cells(PackedInt32Array([target.x,target.y,target.z,0])),"Remove post before region replacement")
 check(await ready_water(),"Post removal cache ready")
 var empty_region:PackedByteArray=game.structures.blocks.capture_region(region)
 check(game.structures.blocks.restore_region(region_bytes,empty_region),"Replace resident region with saved post")
 check(game.lakes.statistics().pending_regions>0,"Resident replacement invalidates water occupancy")
 check(await ready_water(),"Resident replacement occupancy publishes")
 check(game.lakes.depth_at(Vector3(target)+Vector3.ONE*.5)==0,"Restored resident post excludes water")
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_structure_bucket.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_STRUCTURE_BUCKET failures=",failures);quit(failures)
