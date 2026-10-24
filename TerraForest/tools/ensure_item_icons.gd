# SPDX-License-Identifier: 0BSD
extends SceneTree
const Cache=preload("res://tools/item_icon_cache.gd")
const LOCK="res://reports/item_icon_refresh/lock"
var lock_owned:=false
func _initialize()->void:run.call_deferred()
func finish(code:int=0)->void:
	if lock_owned:
		DirAccess.remove_absolute(LOCK.path_join("pid"));DirAccess.remove_absolute(LOCK)
	quit(code)
func acquire_lock()->bool:
	var deadline:=Time.get_ticks_msec()+45000
	while Time.get_ticks_msec()<deadline:
		if DirAccess.make_dir_absolute(LOCK)==OK:
			var file:=FileAccess.open(LOCK.path_join("pid"),FileAccess.WRITE)
			if file==null:DirAccess.remove_absolute(LOCK);return false
			file.store_string(str(OS.get_process_id()));file.close();lock_owned=true;return true
		var pid_text:=FileAccess.get_file_as_string(LOCK.path_join("pid")) if FileAccess.file_exists(LOCK.path_join("pid")) else ""
		if pid_text.is_valid_int() and not OS.is_process_running(int(pid_text)):
			DirAccess.remove_absolute(LOCK.path_join("pid"));DirAccess.remove_absolute(LOCK)
		await create_timer(0.1).timeout
	printerr("Another icon refresh is still running or its lock is incomplete: ",LOCK);return false
func invoke(args:PackedStringArray,log_path:String)->int:
	var output:Array=[]
	var result:=OS.execute(OS.get_executable_path(),args,output,true)
	var log:="\n".join(output)
	var file:=FileAccess.open(log_path,FileAccess.WRITE)
	if file!=null:file.store_string(log);file.close()
	if result!=0 or "ERROR:" in log or "SCRIPT ERROR" in log:
		printerr(log.right(6000));return 1
	return 0
func run()->void:
	var plan:=Cache.plan(Cache.snapshot())
	if plan.ids.is_empty():print("ITEM_ICONS current; bake skipped");quit();return
	if "--check-only" in OS.get_cmdline_user_args():print("ITEM_ICONS stale ",plan.ids," ",plan.reason);quit(2);return
	print("ITEM_ICONS refreshing ",plan.ids," (",plan.reason,")")
	DirAccess.make_dir_recursive_absolute("res://reports/item_icon_refresh")
	if not await acquire_lock():finish(1);return
	plan=Cache.plan(Cache.snapshot())
	if plan.ids.is_empty():print("ITEM_ICONS current after another refresh; bake skipped");finish();return
	var project:=ProjectSettings.globalize_path("res://")
	# Import changed source models/textures before rendering their current geometry.
	if invoke(["--headless","--editor","--path",project,"--import"],"res://reports/item_icon_refresh/import.log")!=0:finish(1);return
	plan=Cache.plan(Cache.snapshot())
	var args:PackedStringArray=["--path",project,"--windowed","--resolution","512x512","--position","-32000,-32000","--max-fps","60","--script","res://tests/bake_item_icons.gd","--","--icons-only"]
	if not plan.full:args.append("--icon-items="+",".join(plan.ids))
	if invoke(args,"res://reports/item_icon_refresh/bake.log")!=0:finish(1);return
	var remaining:=Cache.plan(Cache.snapshot())
	if not remaining.ids.is_empty():push_error("Icon refresh did not produce a current dependency receipt");finish(1);return
	print("ITEM_ICONS refreshed; static images ready");finish()
