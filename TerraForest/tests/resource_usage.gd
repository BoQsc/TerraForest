extends SceneTree
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
var output:="res://reports/resource_usage"
var checks:=0
var failures:=0
var game:Node
var opened_paths:Array[String]=[]
var timings:Dictionary={}
var storage_snapshot:Dictionary={}
var inspected_paths:Dictionary={}

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()

func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition

func write(path:String,bytes:int)->void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE);var data:=PackedByteArray();data.resize(bytes);file.store_buffer(data)

func wait_scan(probe:RefCounted)->Dictionary:
	var deadline:=Time.get_ticks_msec()+30000
	while probe.scan_status().running and Time.get_ticks_msec()<deadline:await process_frame
	var status:Dictionary=probe.scan_status();check(not status.running,"native scan finishes within deadline");return status

func native_checks()->void:
	if not check(ClassDB.class_exists("NativeResourceUsage"),"native usage probe is registered"):return
	var probe:RefCounted=ClassDB.instantiate("NativeResourceUsage")
	var start:=Time.get_ticks_usec();var sample:Dictionary=probe.sample(OS.get_user_data_dir());timings.initial_sample_us=Time.get_ticks_usec()-start
	check(sample.get("private_bytes",0)>0 and sample.get("working_bytes",0)>0,"native memory includes process-private and resident allocations")
	check(sample.get("disk_free_bytes",0)>0 and sample.get("disk_total_bytes",0)>=sample.disk_free_bytes,"native free space is a real volume measurement")
	check(not sample.has("gpu_bytes") or sample.gpu_bytes>=0,"unsupported GPU telemetry is absent, not a fake measurement")
	for locations:Array in [[],[{"id":"bad","path":"relative/path"}],[{"id":"bad","path":"user://cache"}],[{"id":"bad","path":"//server/share"}],[{"id":"bad","path":output,"mode":9}],[{"id":"bad","path":output,"pack_file":"../pack.pck"}],[{"id":"same","path":output},{"id":"same","path":output}]]:
		check(not probe.start_scan(locations),"invalid scan request rejected: "+str(locations))
	var fixture:=output.path_join("fixture")
	for pair:Array in [["content/Game.pck",11],["content/TerraForest.pending.pck",100],["content/addons/native/runtime.dll",13],["content/game.exe",17],["content/old-source.zip",100],["content/reports/evidence.png",100],["data/derived/.terraforest-derived.lock",0],["data/derived/good.trc",19],["data/derived/readme.txt",100],["data/unrelated/not-cache.trc",100],["data/worlds/save.trw",23],["data/worlds/not-cache.trc",100],["data/logs/not-cache.trc",100]]:write(fixture.path_join(pair[0]),pair[1])
	var protected_file:=fixture.path_join("data/worlds/save.trw");var digest:=FileAccess.get_sha256(protected_file)
	var request:Array=[{"id":"content","path":fixture.path_join("content"),"mode":1,"pack_file":"Game.pck"},{"id":"cache","path":fixture.path_join("data"),"mode":2},{"id":"worlds","path":fixture.path_join("data/worlds")},{"id":"missing","path":fixture.path_join("absent")}]
	start=Time.get_ticks_usec();check(probe.start_scan(request),"valid scan starts");timings.scan_dispatch_us=Time.get_ticks_usec()-start
	var status:=await wait_scan(probe);var areas:Dictionary={}
	for area:Dictionary in status.areas:areas[area.id]=area
	check(areas.content.bytes==41 and areas.content.files==3,"content counts chosen pack, executable and libraries, not pending/source/report files")
	check(areas.cache.bytes==19 and areas.cache.files==1,"cache estimate excludes worlds, logs and undeclared folders")
	check(areas.worlds.bytes==123 and areas.worlds.files==2,"worlds are counted separately, including associated files")
	check(areas.missing.started and not areas.missing.available,"absent folders are explicit, never claimed as zero measured bytes")
	probe.cancel_scan();check(not probe.scan_status().cancelled,"closing an already finished scan does not falsely mark it partial")
	check(probe.start_scan(request),"finished scan can restart");probe.cancel_scan();await wait_scan(probe)
	check(probe.start_scan(request),"cancelled scan can restart");await wait_scan(probe)
	check(FileAccess.get_sha256(protected_file)==digest,"read-only scans preserve world bytes")
	var costs:Array[int]=[]
	for iteration in 10:
		start=Time.get_ticks_usec();probe.sample(OS.get_user_data_dir());costs.append(Time.get_ticks_usec()-start)
	timings.repeat_sample_us=costs

func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(label+".png"))==OK,"captured "+label)

func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--usage-output="):output=argument.trim_prefix("--usage-output=")
	output=ProjectSettings.globalize_path(output);DirAccess.make_dir_recursive_absolute(output);FileAccess.open(output.path_join(".gdignore"),FileAccess.WRITE).close()
	await native_checks()
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";root.add_child(game)
	var deadline:=Time.get_ticks_msec()+90000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec()<deadline:await process_frame
	if not check(not game.loading_active and not game.needs_floor_spawn,"temporary world is playable"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.zombies.population_enabled=false;game.zombies.clear()
	var menu:CanvasLayer=game.session_menu;var panel:VBoxContainer=menu.usage_panel
	check(not panel.active and panel.probe==null and not panel.is_processing(),"normal play has no usage sampling or scan")
	menu.set_open(true);check(menu.current_page=="Session","ESC still opens on Session")
	menu.navigation.Usage.pressed.emit();check(panel.active and panel.is_processing() and menu.pages.Usage.visible,"Usage navigation enables only its own work")
	check(panel.budgets.vram_limit_bytes==4294967296 and panel.budgets.redistributable_limit_bytes==5000000000,"shared 4 GiB GPU and 5 GB content targets load in this build")
	check(panel.budgets.ram_limit_bytes==6442450944 and panel.budgets.ram_status.contains("Provisional"),"provisional RAM policy is retained")
	check(panel.budgets.derived_cache_total_bytes==3221225472,"terrain-cache quota remains 3 GiB")
	check(panel.paths.content.ends_with("/TerraForest/dist"),"content folder is the installed game, never the engine installation")
	check(panel.paths.worlds==OS.get_user_data_dir().path_join("worlds"),"world folder matches actual save location")
	inspected_paths=panel.paths.duplicate()
	check(not panel.probe.scan_status().running and panel.probe.scan_status().areas.is_empty(),"opening Usage never starts a directory scan")
	check(not panel.has_method("start_scan") and not panel.has_method("refresh_scan"),"Usage has no scan launcher or status polling")
	var scan_controls:=false
	for control:Button in panel.find_children("*","Button",true,false):
		if control.text.contains("Refresh") or control.text.contains("Scan"):scan_controls=true
	check(not scan_controls,"Usage has no directory-audit button")
	panel.opener=func(path:String)->Error:opened_paths.append(path);return OK
	for key:String in panel.paths:
		if DirAccess.dir_exists_absolute(panel.paths[key]):check(panel.open_folder(key)==OK and opened_paths[-1]==panel.paths[key],"Explorer request uses exact existing folder: "+key)
	check(panel.open_folder("arbitrary_path")==ERR_INVALID_PARAMETER,"unlisted paths cannot open")
	panel.notice.text=""
	check(panel.live.get("private_bytes",0)>0 and panel.meters.ram.label.text.contains("6.00 GiB"),"UI shows current private RAM and its actual limit")
	var sampled:int=panel.live_samples;await create_timer(1.2).timeout;check(panel.live_samples>sampled,"live counters refresh while visible")
	storage_snapshot=panel.probe.scan_status();check(not storage_snapshot.running and storage_snapshot.areas.is_empty(),"live updates never enumerate storage folders")
	panel.notice.text="";await capture("usage-top")
	menu.scroll.scroll_vertical=10000;await capture("usage-storage-policies")
	var hidden_samples:int=panel.live_samples;menu.navigation.Player.pressed.emit();await create_timer(1.2).timeout
	check(not panel.active and not panel.is_processing() and panel.live_samples==hidden_samples,"leaving Usage stops sampling")
	menu.navigation.Usage.pressed.emit();check(panel.active and panel.probe.scan_status().areas.is_empty(),"Usage reopens without scanning")
	menu.set_open(false);check(not panel.active and not panel.is_processing(),"closing ESC also stops Usage")
	check(Mouse.captures==0,"offscreen test never captures or centres the cursor")
	await finish()

func finish()->void:
	if game!=null:
		game.session_menu.set_open(false);await game.terrain.shutdown_after_edits();game.queue_free();await process_frame;await process_frame
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"native_timings":timings,"storage_snapshot":storage_snapshot,"paths":inspected_paths,"cursor_captures":Mouse.captures},"  "))
	print("RESOURCE_USAGE ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
