# SPDX-License-Identifier: 0BSD
extends SceneTree
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
const Launch=preload("res://demo/world_launch.gd")
func _initialize()->void:
 var failures:=0
 var digests:=[]
 var folder:="user://generation_preview_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
 for option in ["connected","road","settlement"]:
  var market:bool=option=="connected"
  var connection:bool=option!="settlement"
  var plan:=Plan.build(42,19,market,connection)
  if not plan.get("ok",false):failures+=1;continue
  var preview:=Plan.preview(42,19,true,market,connection,folder)
  var warm:=Plan.preview(42,19,true,market,connection,folder)
  if preview.get("preview_cache_hit",true) or not warm.get("preview_cache_hit",false) or preview.pixels!=warm.pixels:failures+=1
  if not preview.get("ok",false) or preview.plan_digest!=plan.plan_digest:failures+=1
  if preview.get("building_count",0)!=(20 if market else 12):failures+=1
  if plan.market.is_empty()==market or plan.connection.is_empty()==connection:failures+=1
  var command:=Launch.command("layout_options_check",true,Launch.INTEGRATED_PRESET,42,true,"user://layout_options_check",true,option)
  if not command.ok or not "--settlement-layout="+option in command.args:failures+=1
  if plan.plan_digest in digests:failures+=1
  digests.append(plan.plan_digest)
  print("LAYOUT ",option," digest=",plan.plan_digest," buildings=",preview.get("building_count",0))
 if Launch.command("invalid",true,Launch.INTEGRATED_PRESET,42,true,"user://layout_options_check",true,"invalid").ok:failures+=1
 print("GENERATION_LAYOUT_OPTIONS failures=",failures)
 quit(1 if failures else 0)
