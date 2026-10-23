# SPDX-License-Identifier: 0BSD
extends "res://tests/world_map_cache.gd"
func run()->void:
 var slot:="";var source:=""
 for arg:String in OS.get_cmdline_user_args():
  if arg.begins_with("--review-world="):slot=arg.trim_prefix("--review-world=")
  if arg.begins_with("--preparation-world="):source=arg.trim_prefix("--preparation-world=")
 var launch=preload("res://demo/world_launch.gd")
 if not launch.valid_slot(slot) or not launch.preparation_slot(source):quit(2);return
 if not "--prepared-map-child" in OS.get_cmdline_user_args():
  var command:Dictionary=launch.command(slot,false,1,0,true)
  if not command.ok:quit(2);return
  var args:PackedStringArray=command.args
  var scene:=args.find("res://demo/world.tscn");args.remove_at(scene);args.insert(scene,get_script().resource_path);args.insert(scene,"--script")
  var log:=ProjectSettings.globalize_path("user://prepared_map_%d_%d.log"%[OS.get_process_id(),Time.get_ticks_usec()])
  args.insert(0,log);args.insert(0,"--log-file")
  args.append_array(PackedStringArray(["--snapshot-readonly","--temporary","--prepared-map-child","--review-world="+slot,"--preparation-world="+source]))
  var pid:=OS.create_process(OS.get_executable_path(),args,false)
  var deadline:=Time.get_ticks_msec()+100000
  while pid>0 and OS.is_process_running(pid) and Time.get_ticks_msec()<deadline:await process_frame
  var success:=pid>0 and not OS.is_process_running(pid) and OS.get_process_exit_code(pid)==0
  if pid>0 and OS.is_process_running(pid):OS.kill(pid)
  var output:=FileAccess.get_file_as_string(log) if FileAccess.file_exists(log) else ""
  success=success and "WORLD_MAP_CACHE failures=0" in output and not "ERROR:" in output
  print(output);print("PREPARED_MAP_PARENT failures=",0 if success else 1);quit(0 if success else 1);return
 var cache=preload("res://addons/world_runtime/survey_patch_cache.gd")
 check(cache.promote(source,slot).promoted,"verified prepared map is re-keyed to published world")
 game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60
 root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,60),"published world opens read-only"):await done();return
 game.world_map.set_open(true);var updates=game.world_map.updates
 if check(await wait_for(func():return updates.image!=null and updates.identity_checked and updates.dirty.is_empty() and updates.pending.is_empty() and updates.io==null and updates.cache_saved,40),"prepared terrain map reaches ready"):
  check(updates.cache_hits==1 and updates.patches==0,"first playable map uses prepared edited terrain with zero native resurvey")
 print("PREPARED_MAP_PROFILE hits=",updates.cache_hits," patches=",updates.patches)
 await done()
