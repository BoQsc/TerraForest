# SPDX-License-Identifier: 0BSD
extends SceneTree
const Library=preload("res://demo/world_library.gd")
var failures:=0
var deliveries:Array[String]=[]
var folder:=""
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func wait_for(predicate:Callable,seconds:int=10)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func write_metadata(slot:String,played:int)->void:
	FileAccess.open(folder.path_join(slot+".presentation.json"),FileAccess.WRITE).store_string(JSON.stringify({"last_played":played,"created":100-played}))
func run()->void:
	if "--measure-first-ui" in OS.get_cmdline_user_args():await measure_first_ui();return
	folder="user://browser_responsiveness_"+Crypto.new().generate_random_bytes(8).hex_encode()
	DirAccess.make_dir_recursive_absolute(folder)
	for i in 10:
		var slot:="world_%02d"%i
		FileAccess.open(folder.path_join(slot+".trw"),FileAccess.WRITE).store_string("fixture: never a real world")
		write_metadata(slot,i)
	var picture_dir:=folder.path_join("world_09.preview")
	DirAccess.make_dir_recursive_absolute(picture_dir)
	var picture:=Image.create(1920,1080,false,Image.FORMAT_RGB8);picture.fill(Color.RED);picture.save_png(picture_dir.path_join("north.png"))
	var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
	check(not ResourceLoader.has_cached("res://addons/world_runtime/world_generation_plan.gd") and not ResourceLoader.has_cached("res://addons/world_runtime/generation_coordinator.gd"),"opening saved worlds does not load generation code")
	check(browser.library.loading and browser.credits_button!=null and browser.world_tabs.get_tab_count()==2,"browser controls exist while the catalog is still loading")
	browser.library.directory=folder;browser.refresh()
	check(await wait_for(func():return not browser.library.loading and browser.library.cache.has("world_09")),"catalog and selected photograph finish asynchronously")
	check(browser.slots.size()==10 and browser.worlds.get_item_metadata(0)=="world_09","last played order selects the newest fixture")
	check(browser.library.dates.world_09==9,"date drawing uses metadata delivered by the catalog worker")
	check(browser.saved_picture.texture!=null and browser.saved_picture.texture.get_width()<=Library.THUMBNAIL_SIZE.x and browser.saved_picture.texture.get_height()<=Library.THUMBNAIL_SIZE.y,"browser uploads a bounded thumbnail")
	check(Image.load_from_file(picture_dir.path_join("north.png")).get_size()==Vector2i(1920,1080),"source photograph stays full resolution")
	var cached:Texture2D=browser.saved_picture.texture
	var started:=Time.get_ticks_usec()
	for i in 20:browser.filter_list()
	print("CACHED_FILTER_20_MS ",(Time.get_ticks_usec()-started)/1000.0)
	check(browser.saved_picture.texture==cached and browser.library.worker==null,"repeated filtering reuses the texture without more disk work")
	browser.library.details_ready.connect(func(slot:String,_data:Dictionary,_texture:Texture2D):deliveries.append(slot))
	# Queue three selections without yielding: only the last may reach the panel.
	for index in [9,8,7]:browser.worlds.select(index);browser.show_saved_details(index)
	check(browser.saved_title.text=="world_02" and browser.saved_picture.texture==null,"selection changes immediately and clears the previous photograph")
	check(await wait_for(func():return browser.library.cache.has("world_02")),"latest selection resolves")
	check(deliveries==["world_02"] and browser.saved_title.text=="world_02","superseded work never replaces the latest details")
	browser.filter_field.text="nothing_matches";browser.filter_list()
	check(browser.worlds.item_count==0 and browser.library.selected_slot.is_empty() and browser.saved_picture.texture==null,"empty results clear selection and photo")
	browser.filter_field.clear();browser.filter_list()
	# Refresh during an in-flight selection; its old revision must be discarded.
	browser.library.select("world_03")
	write_metadata("world_09",99);picture.fill(Color.BLUE);picture.save_png(picture_dir.path_join("north.png"))
	browser.refresh()
	check(await wait_for(func():return not browser.library.loading and browser.library.cache.has("world_09")),"refresh supersedes old catalog and photo work")
	check(browser.library.cache.world_09.details.last_played==99 and browser.saved_picture.texture!=cached,"refresh reads changed metadata and replaces the cached photo")
	check(browser.library.dates.world_09==99,"refresh replaces dates together with the catalog")
	check(browser.saved_picture.texture.get_image().get_pixel(0,0).b>0.9,"refreshed photo contains the new pixels")
	for i in 10:
		var slot:="world_%02d"%i;browser.library.select(slot)
		check(await wait_for(func():return browser.library.cache.has(slot)),"browse "+slot)
	check(browser.library.cache.size()==Library.CACHE_LIMIT,"thumbnail cache has a fixed memory bound")
	browser.library.select("../outside")
	check(await wait_for(func():return browser.library.cache.has("../outside")),"invalid selection completes safely")
	check(browser.library.cache["../outside"].details.is_empty() and browser.library.cache["../outside"].picture==null,"invalid slots cannot escape the save directory")
	browser.sort_order.select(2);browser.refresh()
	check(await wait_for(func():return not browser.library.loading),"name sort completes")
	check(browser.slots[0]=="world_00","sort order remains correct")
	for i in 10:check(FileAccess.get_file_as_string(folder.path_join("world_%02d.trw"%i))=="fixture: never a real world","save bytes preserved "+str(i))
	# A cheap native terrain survey exercises the deferred script load without
	# baking a regional world or depending on concurrent world-generation edits.
	browser.preset.add_item("Original woodland fixture",1);browser.preset.select(browser.preset.item_count-1)
	browser.start_preview()
	check(await wait_for(func():return not browser.preview_loading and browser.preview_worker==null,45),"explicit preview completes its staged resource loading and worker")
	check(ResourceLoader.has_cached("res://addons/world_runtime/world_generation_plan.gd"),"preview code loads when explicitly requested")
	check(await wait_for(func():return browser.preview_worker==null) and browser.preview_view.texture!=null,"deferred preview still returns a native terrain image")
	browser.library.select("world_08");browser.free()
	check(true,"browser teardown joins in-flight read work")
	# This fixture owns only files below its fresh, unique directory.
	for name:String in DirAccess.get_files_at(picture_dir):DirAccess.remove_absolute(picture_dir.path_join(name))
	DirAccess.remove_absolute(picture_dir)
	for name:String in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
	DirAccess.remove_absolute(folder)
	print("WORLD_BROWSER_RESPONSIVENESS failures=",failures);quit(1 if failures else 0)

func measure_first_ui()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):folder=argument.trim_prefix("--check-evidence-dir=")
	var start:=Time.get_ticks_usec()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	var browser=current_scene
	var built:=(Time.get_ticks_usec()-start)/1000.0
	await RenderingServer.frame_post_draw
	var first:=Time.get_ticks_usec()/1000.0
	var first_wall_usec:=Time.get_unix_time_from_system()*1000000.0
	browser.filter_field.grab_focus()
	var sent:=Time.get_ticks_usec()
	var event:=InputEventKey.new();event.keycode=KEY_Z;event.unicode=122;event.pressed=true
	root.push_input(event)
	await process_frame
	var response:=(Time.get_ticks_usec()-sent)/1000.0
	var input_wall_usec:=Time.get_unix_time_from_system()*1000000.0
	check(browser.filter_field.text=="z","first painted browser accepts keyboard input while background work runs")
	browser.filter_field.clear();browser.filter_list()
	var intervals:Array[float]=[];var previous:=Time.get_ticks_usec()
	for tick in 180:
		await process_frame
		var now:=Time.get_ticks_usec();intervals.append((now-previous)/1000.0);previous=now
	check(not browser.library.loading,"normal saved-world catalog completes")
	check(not ResourceLoader.has_cached("res://addons/world_runtime/world_generation_plan.gd"),"first UI does not load world-generation resources")
	intervals.sort()
	var metrics:={"first_frame_ms":first,"scene_build_ms":built,"first_input_ms":response,"frame_p95_ms":intervals[int(intervals.size()*.95)],"frame_max_ms":intervals[-1],"worlds":browser.slots.size(),"ui_set":browser.ui_set.id,"failures":failures}
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--launch-start-unix-usec="):
			var epoch:=float(argument.trim_prefix("--launch-start-unix-usec="))
			metrics["launch_to_first_frame_ms"]=(first_wall_usec-epoch)/1000.0
			metrics["launch_to_first_input_ms"]=(input_wall_usec-epoch)/1000.0
	print("FIRST_UI ",JSON.stringify(metrics))
	FileAccess.open(folder.path_join("first_ui.json"),FileAccess.WRITE).store_string(JSON.stringify(metrics))
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8);picture.save_png(folder.path_join("first_ui.png"))
	current_scene=null;browser.free();await process_frame
	print("WORLD_BROWSER_RESPONSIVENESS failures=",failures);quit(1 if failures else 0)
