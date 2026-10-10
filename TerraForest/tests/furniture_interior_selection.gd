# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String) -> void:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 var deadline:=Time.get_ticks_msec()+60000
 while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
 game.terrain.backend.disable_snapshot_writes();game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.fly=true
 var collection=game.structures.model("furniture/table/v1")
 var ids: PackedInt64Array=collection.get_ids()
 check(ids.size()==4,"checkpoint has four furnished cottage tables")
 var before: PackedByteArray=game.structures.capture_storage_snapshot()
 game._set_player_tool_mode(true,true,game.tool)
 for id in ids:
  var record: PackedFloat32Array=collection.get_instance(id)
  var point: Vector3=collection.global_transform*Vector3(record[3],record[7],record[11])+Vector3.UP*0.7
  game.player.position=point+Vector3.UP*3;game.structures.set_model_focus(point)
  for tick in 20:await physics_frame
  var inside:=false;var blocked:=false
  for direction in [Vector3.RIGHT,Vector3.LEFT,Vector3.FORWARD,Vector3.BACK]:
   game.camera.global_position=point+direction*2;game.camera.look_at(point)
   game.model_tool.update(0,true)
   var hit: Dictionary=game.model_tool.ray()
   if not inside and not hit.is_empty() and hit.collider==collection and collection.placement_for_body(hit.rid)==id:
    game.model_tool.pick();inside=game.model_tool.picked_id==id
   game.camera.global_position=point+direction*12;game.camera.look_at(point)
   game.model_tool.update(0,true);hit=game.model_tool.ray()
   if not blocked and not hit.is_empty() and hit.collider==game.structures.blocks:
    game.model_tool.pick()
    blocked=game.model_tool.picked_id==0 and game.model_tool.edit(true)==0
  check(inside,"interior selection reaches table %d"%id)
  check(blocked,"cottage wall blocks selection and removal of table %d"%id)
 check(game.structures.capture_storage_snapshot()==before,"interaction probes leave all buildings and furniture unchanged")
 check(load("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample and Engine.max_fps==60,"fullscreen1080p cap60")
 game.terrain.shutdown();game.free();await process_frame
 print("FURNITURE_INTERIOR failures=",failures);quit(1 if failures else 0)
