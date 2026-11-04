# SPDX-License-Identifier: 0BSD
extends SceneTree
class BrowserProbe extends "res://demo/worlds.gd":
	var launched:=PackedStringArray()
	var dispatch_cover:CanvasLayer
	var remove_before_launch:=false
	func _open_game(arguments:PackedStringArray)->void:
		launched=arguments;dispatch_cover=session.cover
	func _catalog_ready(found:PackedStringArray)->void:
		if remove_before_launch and not found.is_empty():
			DirAccess.remove_absolute(library.directory.path_join(found[0]+".trw"))
			DirAccess.remove_absolute("user://worlds".path_join(found[0]+".trw"))
		super._catalog_ready(found)
var failures:=0
var checks:=0
var folder:="res://reports/continue_last_presentation"
var fixture:=""
var owned_slots:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func until(predicate:Callable)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
func attach(session:Node,remove_save:bool=false)->Control:
	session.continue_consumed=false;session.last_error=""
	var browser:=BrowserProbe.new();browser.remove_before_launch=remove_save;root.add_child(browser)
	browser.library.directory=fixture;browser.refresh()
	return browser
func photograph(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder.path_join(label+".png"))
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--continue-output="):folder=arg.trim_prefix("--continue-output=")
	if not "--continue-last" in OS.get_cmdline_user_args():quit(2);return
	DirAccess.make_dir_recursive_absolute(folder)
	fixture="user://continue_ui_"+Crypto.new().generate_random_bytes(6).hex_encode();DirAccess.make_dir_recursive_absolute(fixture)
	var prefix:="ContinueUI_"+Crypto.new().generate_random_bytes(6).hex_encode()
	for item in [{"name":"older","played":1},{"name":"newest","played":2}]:
		var slot:String=prefix+item.name;owned_slots.append(slot)
		assert(not FileAccess.file_exists("user://worlds".path_join(slot+".trw")))
		for path:String in [fixture.path_join(slot+".trw"),"user://worlds".path_join(slot+".trw")]:
			FileAccess.open(path,FileAccess.WRITE).store_string("owned fixture, intercepted before world initialization")
		FileAccess.open(fixture.path_join(slot+".presentation.json"),FileAccess.WRITE).store_string(JSON.stringify({"last_played":item.played}))
	var session:Node=root.get_node("WorldSession")
	var browser:Control=attach(session)
	var cover:CanvasLayer=session.cover
	check(is_instance_valid(cover) and cover.layer>0,"Last World creates opaque loading cover synchronously before catalog returns")
	check(cover.panel.title.text=="Loading your world" and cover.panel.detail.text=="Finding last played world…","first loading phase reports actual catalog work")
	check(not cover.cancel_button.visible,"continue cover does not offer generation cancellation")
	await photograph("first_loading_frame")
	await until(func():return not browser.launched.is_empty())
	check("--world-slot="+owned_slots[1] in browser.launched,"continue selects newest saved world without using browser selection controls")
	check(is_instance_valid(cover) and browser.dispatch_cover==cover and session.cover==cover,"same cover survives catalog-to-world dispatch without a browser gap")
	check(browser.library.selected_slot.is_empty() and browser.library.cache.is_empty(),"continue skips browser thumbnails and selected-world detail work")
	check(not session.take_continue_request(PackedStringArray(["--continue-last"])),"returning to browser cannot repeat the process startup request")
	browser.free();session.dismiss_continue();await process_frame
	for name in owned_slots:
		DirAccess.remove_absolute(fixture.path_join(name+".trw"));DirAccess.remove_absolute("user://worlds".path_join(name+".trw"))
	browser=attach(session)
	await until(func():return not browser.library.loading and session.cover==null)
	check(browser.notice.text=="No saved world to continue." and browser.launched.is_empty(),"empty catalog dismisses cover and shows usable browser feedback")
	await photograph("empty_fallback")
	browser.free();await process_frame
	var vanished:=prefix+"vanished";owned_slots.append(vanished)
	for path:String in [fixture.path_join(vanished+".trw"),"user://worlds".path_join(vanished+".trw")]:FileAccess.open(path,FileAccess.WRITE).store_string("owned fixture")
	browser=attach(session,true)
	await until(func():return not browser.library.loading and session.cover==null)
	check(browser.notice.text.contains("no longer available") and browser.launched.is_empty(),"save removed after scan returns to browser instead of retaining the cover")
	browser.free();await process_frame
	session.continue_consumed=false;session.last_error="Fixture initialization failed"
	browser=BrowserProbe.new();root.add_child(browser)
	check(session.cover==null and not browser.continue_pending and browser.notice.text=="Fixture initialization failed","failed world return does not automatically retry continue-last")
	browser.free();session.last_error="";await process_frame
	for name in DirAccess.get_files_at(fixture):DirAccess.remove_absolute(fixture.path_join(name))
	DirAccess.remove_absolute(fixture)
	for name in owned_slots:
		if FileAccess.file_exists("user://worlds".path_join(name+".trw")):DirAccess.remove_absolute("user://worlds".path_join(name+".trw"))
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"startup checks leave desktop pointer uncaptured")
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures}))
	print("CONTINUE_LAST_PRESENTATION checks=",checks," failures=",failures);quit(1 if failures else 0)
