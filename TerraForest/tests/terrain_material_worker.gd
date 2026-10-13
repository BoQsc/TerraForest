# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var replies:Array[Dictionary]=[]
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func wait_reply():
 var deadline:=Time.get_ticks_msec()+5000
 while replies.is_empty() and Time.get_ticks_msec()<deadline:await process_frame
func run():
 var terrain=preload("res://addons/volumetric_terrain/terrain_world.gd").new()
 terrain.diagnostics_pause_streaming=true;terrain.backend.world_generator=2;root.add_child(terrain)
 terrain.material_edit_ready.connect(func(result:Dictionary):replies.append(result))
 check(terrain.start(StandardMaterial3D.new(),true)==OK,"Real terrain worker starts")
 var deadline:=Time.get_ticks_msec()+10000
 while not terrain.world_ready and Time.get_ticks_msec()<deadline:await process_frame
 if not terrain.world_ready:
  check(false,"Worker became ready");terrain.shutdown();terrain.queue_free();quit(1);return
 var field=ClassDB.instantiate("TerrainCore")
 field.execute(Codec.command(6,[1703,Codec.MATERIAL_FIELD_GENERATOR]))
 var revision:int=field.execute(Codec.command(0)).decode_u32(12)
 var low:=Vector3(400,220,400);var high:=Vector3(408,228,408)
 check(terrain.request_material_edit(field,low,high,true,revision,1),"Public facade admits direct material edit")
 check(not terrain.request_material_edit(field,low,high,true,revision,2),"Pending or unconsumed mutation holds one reservation")
 await wait_reply()
 check(replies.size()==1 and replies[0].accepted and replies[0].current_world and replies[0].token==1,"Worker publishes accepted edit receipt")
 check(field.execute(Codec.point_command(Vector3(404,224,404))).decode_float(16)<0,"Worker edits the same authoritative field used by mesh and save")
 var saved:PackedByteArray=field.execute(Codec.command(4))
 replies.clear()
 check(terrain.request_material_edit(field,low,high,false,revision,3),"Stale field request reaches guarded worker")
 await wait_reply()
 check(replies.size()==1 and not replies[0].accepted and replies[0].status=="stale" and field.execute(Codec.command(4))==saved,"Stale material revision cannot remove newer material")
 replies.clear();revision=field.execute(Codec.command(0)).decode_u32(12)
 check(terrain.request_material_edit(field,low-Vector3.ONE,high+Vector3.ONE,false,revision,4),"Direct removal admitted after completion consumption")
 await wait_reply()
 check(replies.size()==1 and replies[0].accepted and field.execute(Codec.point_command(Vector3(404,224,404))).decode_float(16)>0,"Worker removes material through the same field")
 check(not terrain.request_material_edit(field,low,low+Vector3(33,1,1),true,revision,5),"Oversized material work is rejected before queuing")
 terrain.shutdown();terrain.queue_free();await process_frame
 print("TERRAIN_MATERIAL_WORKER failures=",failures);quit(failures)
