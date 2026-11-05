# SPDX-License-Identifier: 0BSD
extends SceneTree
const Registry=preload("res://addons/ui_sets/registry.gd")
const Set=preload("res://addons/ui_sets/ui_set.gd")
var checks:=0
var failures:=0
var folder:="res://reports/ui_sets"
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-output="):folder=arg.trim_prefix("--ui-output=")
	run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	var original_path:=Registry.preference_path;var original_id:=Registry.session_id
	Registry.preference_path=folder.path_join("preferences.cfg");Registry.session_id="shipped"
	var prefs:=ConfigFile.new();prefs.set_value("unrelated","preserved",123);prefs.save(Registry.preference_path)
	var catalog:=Registry.discover()
	check(catalog.size()==5 and Registry.diagnostics.is_empty(),"all preserved sets are discovered from manifests")
	check(not Registry.activate("missing").ok and Registry.session_id=="shipped","unknown activation preserves the current set")
	for id:String in ["diorama","campfire"]:
		var reference:Resource=catalog[id]
		var resolved:Resource=Registry.resolve(reference)
		check(reference.preview!=resolved.runtime_preview,"loading reference stays separate from its live adapter: "+id)
		check(Registry.activate(id).ok and Registry.active().id==id,"loading-only design activates through the working adapters: "+id)
	var custom=Set.new();custom.id="fixture_plugin";custom.title="Plugin fixture";custom.base=Registry.DEFAULT;custom.preview=Registry.DEFAULT.preview;custom.preview_pages=Registry.DEFAULT.preview_pages;custom.runtime_enabled=true
	var directory:=folder.path_join("plugin");DirAccess.make_dir_recursive_absolute(directory)
	ResourceSaver.save(custom,directory.path_join("set.tres"))
	var plugins:=Registry.discover([folder])
	check(plugins.has("fixture_plugin") and Registry.validate(plugins.fixture_plugin,true).is_empty(),"a new folder/manifest inherits working adapters without a registry edit")
	custom.base=Resource.new()
	check(not Registry.validate(custom,true).is_empty(),"invalid inheritance fails before touching active preferences")
	for id:String in ["shipped","survey","expedition","diorama","campfire"]:
		check(Registry.activate(id).ok and Registry.active().id==id,"functional set activates: "+id)
		var browser=load("res://demo/worlds.gd").new();browser.preview_mode=true;root.add_child(browser);browser.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		check(browser.library==null and browser.preparation_pid<0 and browser.photograph_pid<0 and not browser.is_processing(),"mockup browser cannot read saves or start background jobs: "+id)
		check(browser.ui_set.id==id and browser.worlds!=null and browser.generate_button!=null and browser.preparation_panel!=null,"live adapters provide all browser/create bindings: "+id)
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"presentation set preserves actual generation recipe: "+id)
		if id in ["survey","expedition"]:
			check(browser.get_meta("ui_layout","") in ["survey","planet"],"reference composition is used by the live browser: "+id)
			browser.saved_title.text="Sample world";browser.saved_details.text="Preview data · no save opened";browser.worlds.add_item("Sample world")
			await process_frame;await process_frame
			if DisplayServer.get_name()!="headless":
				await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join(id+"_browser.png"))
			browser.world_tabs.current_tab=1
			await process_frame;await process_frame
			check(browser.preview_view.get_global_rect().end.x<browser.name_field.get_global_rect().position.x,"actual survey and recipe occupy the reference's left/right columns: "+id)
		browser.free()
		var screen=load("res://addons/world_runtime/generation_screen.gd").new();root.add_child(screen)
		screen.panel.reset();screen.update_stage("Baking destructible sidewalk plates",500,1000)
		check(is_equal_approx(screen.panel.bar.value,63.5) and screen.panel.get_meta("ui_set").id==id,"live progress uses measured coordinator stages: "+id)
		screen.panel.show_progress("Loading your world","Contact preparation",71)
		screen.panel.show_progress("Loading your world","Late sample",50)
		check(screen.panel.bar.value==71 and screen.diagnostics!=null and screen.cancel_button.disabled,"progress, diagnostics and action guards are retained: "+id)
		if id!="shipped":
			check(not screen.diagnostics.panel.visible,"technical details start collapsed: "+id)
			screen.diagnostics.ribbon.pressed.emit();screen.diagnostics.refresh()
			check(screen.diagnostics.panel.visible and screen.diagnostics.live.text.contains("completed = 500"),"details toggle exposes actual counters: "+id)
			screen.diagnostics.ribbon.pressed.emit()
		if id in ["expedition","diorama"]:check(is_equal_approx(screen.background.ring.value,0.71),"planet ring follows measured progress: "+id)
		if DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(id+"_loading.png"))
		screen.cancel_path=folder.path_join(id+"_cancel.request");screen.cancel_button.disabled=false
		screen.cancel_button.pressed.emit();screen.update_stage("World generation complete",0,0)
		check(FileAccess.file_exists(screen.cancel_path) and screen.cancellation_requested and screen.detail.text=="Cancelling generation…" and screen.panel.bar.value==71,"live cancel writes its request and protects cancellation state: "+id)
		screen.free();await process_frame
	prefs.load(Registry.preference_path)
	check(prefs.get_value("unrelated","preserved")==123,"activation preserves other preferences")
	Registry.session_id=""
	check(Registry.selected_id()=="campfire","selected set restores from disk without a session override")
	Registry.session_id="removed_plugin"
	check(Registry.active().id=="shipped","missing plugin restores the working Classic set")
	Registry.session_id="shipped"
	var studio=load("res://addons/ui_sets/studio.tscn").instantiate();root.add_child(studio)
	for id:String in catalog:
		studio.chooser.select(studio.ids.find(id));studio.mode.select(0);studio.refresh_preview()
		await process_frame
		check(studio.preview!=null and studio.viewport.gui_disable_input,"reference preview is isolated from gameplay input: "+id)
		if DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(id+"_studio.png"))
	studio.chooser.select(studio.ids.find("survey"));studio.mode.select(1);studio.refresh_preview();studio.screen.select(1);studio.preview.show_screen(1)
	await process_frame
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("live_create_studio.png"))
	studio.activate_button.pressed.emit()
	check(Registry.active().id=="survey" and studio.status.text.begins_with("Activated"),"studio activation action persists the chosen functional set")
	var activated=load("res://demo/worlds.gd").new();activated.preview_mode=true;root.add_child(activated)
	check(activated.ui_set.id=="survey","next browser instance consumes the studio selection")
	activated.free()
	studio.free()
	# Exercise an actual GUI click and scene replacement, rather than just emitting
	# the preference callback. Each installed design must return to its live browser.
	for id:String in ["survey","expedition","diorama","campfire","shipped"]:
		var live_studio=load("res://addons/ui_sets/studio.tscn").instantiate();root.add_child(live_studio);current_scene=live_studio
		live_studio.chooser.select(live_studio.ids.find(id));live_studio.refresh_preview()
		await process_frame;await process_frame
		var point:Vector2=live_studio.activate_button.get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion)
		for pressed:bool in [true,false]:
			var click:=InputEventMouseButton.new();click.position=point;click.global_position=point;click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;root.push_input(click);await process_frame
		var deadline:=Time.get_ticks_msec()+5000
		while (current_scene==null or current_scene==live_studio) and Time.get_ticks_msec()<deadline:await process_frame
		var live_browser=current_scene
		if live_browser==live_studio:print("ACTIVATION_DIAGNOSTIC set=",id," status=",live_studio.status.text," button=",live_studio.activate_button.get_global_rect()," pressed=",live_studio.activate_button.button_pressed," disabled=",live_studio.activate_button.disabled)
		check(is_instance_valid(live_browser) and live_browser.scene_file_path=="res://demo/worlds.tscn" and live_browser.ui_set.id==id,"clicking Activate opens the selected live world screens: "+id)
		if is_instance_valid(live_browser):current_scene=null;live_browser.free()
	Registry.session_id=original_id;Registry.preference_path=original_path;await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("UI_SETS checks=",checks," failures=",failures);quit(1 if failures else 0)
