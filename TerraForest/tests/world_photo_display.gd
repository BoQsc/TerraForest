# SPDX-License-Identifier: 0BSD
extends SceneTree
const Pictures=preload("res://addons/world_runtime/world_presentation.gd")
const Registry=preload("res://addons/ui_sets/registry.gd")
class TerrainProbe extends Node:
	signal save_completed(ok:bool)
	var save_slot:="arrival_fixture"
	var backend:={"readonly_snapshot":false}
class GameProbe extends Node3D:
	var temporary_world:=false
	var shutdown_requested:=false
	var loading_active:=false
	var presentation_ready:=false
	var tool_view:Node3D
	var terrain:=TerrainProbe.new()
var failures:=0
var checks:=0
var folder:=""
var output:=""
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true);run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func until(predicate:Callable)->void:
	var deadline:=Time.get_ticks_msec()+5000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
func run()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--ui-output="):output=argument.trim_prefix("--ui-output=")
	folder="user://photo_check_"+Crypto.new().generate_random_bytes(6).hex_encode();DirAccess.make_dir_recursive_absolute(folder)
	var original:=Registry.session_id;Registry.session_id="shipped"
	var game:=GameProbe.new();root.add_child(game);game.add_child(game.terrain);game.set_process(true)
	var landscape:=ColorRect.new();landscape.color=Color("4488cc");landscape.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);game.add_child(landscape)
	var hud:=CanvasLayer.new();game.add_child(hud)
	var overlay:=ColorRect.new();overlay.color=Color.RED;overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);hud.add_child(overlay)
	root.gui_embed_subwindows=true
	var popup:=ConfirmationDialog.new();game.add_child(popup);popup.popup_centered(Vector2i(240,120))
	var capture=preload("res://addons/world_runtime/arrival_photograph.gd").new();capture.directory=folder;game.add_child(capture);capture.attach(game,func():return game.presentation_ready);capture.request()
	await process_frame;await process_frame
	check(not capture.captured and popup.visible,"automatic photograph waits for modal dialogs to close")
	popup.hide()
	await process_frame;await process_frame
	check(not capture.captured,"automatic photograph waits for the entry camera to finish")
	game.presentation_ready=true
	var frames:=0
	while not capture.captured and frames<600:frames+=1;await process_frame
	check(capture.captured and capture.readbacks==1,"automatic photograph takes one frame at the first clean moment")
	check(capture.image!=null and not capture.published and not FileAccess.file_exists(folder.path_join("arrival_fixture.preview/arrival.png")),"unsaved arrival stays in memory until a successful save")
	check(hud.visible and game.is_processing(),"capture restores HUD and game processing")
	var canonical:=FileAccess.open(folder.path_join("arrival_fixture.trw"),FileAccess.WRITE);canonical.store_string("canonical bytes must not change");canonical.close()
	var digest:=FileAccess.get_sha256(folder.path_join("arrival_fixture.trw"))
	game.terrain.save_completed.emit(true);await until(func():return capture.published)
	var arrival:=Pictures.read_image("arrival_fixture",folder)
	check(arrival!=null and arrival.get_pixelv(arrival.get_size()/2).is_equal_approx(Color("4488cc")),"arrival PNG contains the clean world frame rather than the HUD")
	check(Pictures.metadata("arrival_fixture",folder).get("preview_count",0)==1 and FileAccess.get_sha256(folder.path_join("arrival_fixture.trw"))==digest,"background capture updates presentation metadata without changing canonical save bytes")
	var first_hash:=FileAccess.get_sha256(folder.path_join("arrival_fixture.preview/arrival.png"));capture.request();game.terrain.save_completed.emit(true)
	await process_frame
	check(FileAccess.get_sha256(folder.path_join("arrival_fixture.preview/arrival.png"))==first_hash,"existing photographs are preserved without repeated captures")
	game.free()
	var bare:=folder.path_join("bare_only")
	DirAccess.make_dir_recursive_absolute(bare)
	var bare_save:=FileAccess.open(bare.path_join("bare_fixture.trw"),FileAccess.WRITE);bare_save.store_string("bare fixture");bare_save.close()
	FileAccess.open(bare.path_join("bare_fixture.presentation.json"),FileAccess.WRITE).store_string(JSON.stringify({"seed":9,"created":1793000000}))
	var bare_browser=load("res://demo/worlds.gd").new();bare_browser.preview_mode=true;root.add_child(bare_browser);bare_browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bare_browser.library=load("res://demo/world_library.gd").new();bare_browser.library.directory=bare;bare_browser.add_child(bare_browser.library)
	bare_browser.library.catalog_ready.connect(bare_browser._catalog_ready);bare_browser.library.details_ready.connect(bare_browser._saved_details_ready);bare_browser.refresh()
	await until(func():return bare_browser.saved_picture.texture!=null)
	await process_frame;await RenderingServer.frame_post_draw
	var bare_pixel:=root.get_texture().get_image().get_pixelv(bare_browser.saved_picture.get_global_rect().get_center())
	check(bare_browser.saved_picture.texture!=null and bare_pixel.v>0.02 and bare_browser.saved_caption.visible and bare_browser.saved_caption.text=="No world picture yet","world selector draws the general picture with centred caption when no photograph exists")
	bare_browser.free()
	for mode:String in ["temporary","readonly"]:
		game=GameProbe.new();game.temporary_world=mode=="temporary";game.terrain.backend.readonly_snapshot=mode=="readonly";root.add_child(game);game.add_child(game.terrain)
		capture=load("res://addons/world_runtime/arrival_photograph.gd").new();capture.directory=folder;game.add_child(capture);capture.attach(game);capture.request();await process_frame
		check(not capture.captured and not capture.capturing,"automatic capture excludes "+mode+" worlds");game.free()
	for id:String in ["shipped","survey","expedition","diorama","campfire"]:
		Registry.session_id=id
		var browser=load("res://demo/worlds.gd").new();browser.preview_mode=true;root.add_child(browser);browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		browser.library=load("res://demo/world_library.gd").new();browser.library.directory=folder;browser.add_child(browser.library)
		browser.library.catalog_ready.connect(browser._catalog_ready);browser.library.details_ready.connect(browser._saved_details_ready);browser.refresh()
		await until(func():return browser.saved_picture.texture!=null)
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var pixel:=root.get_texture().get_image().get_pixelv(browser.saved_picture.get_global_rect().get_center())
		check(browser.saved_picture.texture!=null and pixel.b>0.5 and pixel.r<0.4,"saved-world browser visibly displays the loaded photograph: "+id)
		if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(id+"_photo_browser.png"))
		var loading=load("res://addons/world_runtime/generation_screen.gd").new();root.add_child(loading)
		var session:Node=root.get_node("WorldSession");session.cover=loading;session.set_world_photograph("arrival_fixture",folder)
		await process_frame;await RenderingServer.frame_post_draw
		pixel=root.get_texture().get_image().get_pixel(1800,100)
		check(loading.picture.texture!=null and pixel.b>0.3 and pixel.r<0.3,"resource-loading cover visibly displays the same world photograph: "+id)
		if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(id+"_photo_loading.png"))
		check(Pictures.image_for("missing",folder)==null,"world without a photograph has an explicit empty result: "+id)
		check(Pictures.display_image("missing",folder)!=null and not Pictures.has_photograph("missing",folder),"world without a photograph shows the general picture without counting it: "+id)
		session.cover=null;loading.free();browser.free()
	Registry.session_id=original
	print("WORLD_PHOTO_DISPLAY checks=",checks," failures=",failures," fixture=",folder)
	quit(1 if failures else 0)
