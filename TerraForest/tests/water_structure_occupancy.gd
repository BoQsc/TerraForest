# SPDX-License-Identifier: 0BSD
extends "res://tests/water_bucket_roundtrip.gd"
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual water world ready")
 if failures:await finish();return
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var cell:=Vector3i(floori(entry.seed.x),floori(entry.level)-1,floori(entry.seed.z))
 var bounds:=AABB(Vector3(cell),Vector3.ONE)
 check(game.lakes.water.overlaps_occupied(bounds),"Construction target contains water")
 check(game.structures.blocks.get_cell(cell)==0,"Construction target has no existing block")
 var before:Dictionary=amounts(game.lakes.capture_snapshot())
 game.construction_inventory.gameplay=false
 var placed:bool=game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,cell,1)
 results={"target":cell,"placed":placed,"block":game.structures.blocks.get_cell(cell),"water_overlap":game.lakes.water.overlaps_occupied(bounds),"water_unchanged":before==amounts(game.lakes.capture_snapshot())}
 check(not placed or not results.water_overlap,"Solid construction must not coexist with occupied water")
 await finish()
func finish():
 results.failures=failures
 var file:=FileAccess.open("res://reports/water_structure_occupancy.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 game.terrain.shutdown();game.queue_free();await process_frame;await process_frame
 print("WATER_STRUCTURE_OCCUPANCY failures=",failures);quit(failures)
