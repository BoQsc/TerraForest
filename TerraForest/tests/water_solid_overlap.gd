# SPDX-License-Identifier: 0BSD
extends "res://tests/water_static_mining.gd"
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
func run():
 game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
 var deadline:=Time.get_ticks_msec()+35000
 while not game.has_meta("water_bucket_review_ready") and Time.get_ticks_msec()<deadline:await process_frame
 check(game.has_meta("water_bucket_review_ready"),"Actual lake review world ready")
 if failures:await finish();return
 game.set_process(false);game.set_physics_process(false);game._clear_motion()
 game.session_menu.toggle_developer()
 var entry:Dictionary=game.lakes._lakes.values()[0]
 var target:=Vector3(entry.seed.x+3,entry.level-0.5,entry.seed.z)
 check(game.lakes.depth_at(target)>0,"Solid placement target contains water")
 var before:PackedByteArray=game.terrain.backend.native.execute(Codec.command(4))
 var water_before:=amounts(game.lakes.capture_snapshot())
 var notices:Array[String]=[]
 game.terrain.message_changed.connect(func(message:String):notices.append(message))
 check(not game.terrain.sculpt_sphere(target,1.5,true),"Adding solid terrain into water is rejected before mutation")
 check(notices.any(func(message:String):return message.contains("scoop or remove")),"Rejected addition explains how to clear the area")
 check(not game.terrain.set_block(Vector3i(target.floor()),1),"Exact terrain block cannot occupy stored water")
 var dry:=target+Vector3(18,0,18)
 var batch:Array[PackedByteArray]=[Codec.brush(dry,dry,1.5,0,true,1),Codec.brush(target,target,1.5,0,true,1)]
 check(not game.terrain.edit(batch[0],dry.min(target),dry.max(target),0,batch),"Mixed dry/wet terrain batch rejects atomically")
 check(await ready_water(),"No outstanding edit work")
 check(game.terrain.backend.native.execute(Codec.command(4))==before,"Rejected addition leaves terrain unchanged")
 check(amounts(game.lakes.capture_snapshot())==water_before and game.lakes.depth_at(target)>0,"Water remains visible and owned instead of buried")
 check(game.terrain.sculpt_sphere(dry,1.5,true),"Solid terrain addition remains available away from water")
 check(await ready_water(),"Dry terrain addition publishes normally")
 check(game.terrain.sculpt_sphere(target,1.5,false),"Excavation inside water remains allowed")
 check(await ready_water(),"Excavation and water contact updates publish")
 check(amounts(game.lakes.capture_snapshot())==water_before,"Admission and excavation do not destroy or move water")
 await finish()
func finish():
 if is_instance_valid(game):game.terrain.shutdown();game.queue_free()
 await process_frame;await process_frame
 print("WATER_SOLID_OVERLAP failures=",failures);quit(failures)
