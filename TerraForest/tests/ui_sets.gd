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
	check(not Registry.activate("diorama").ok and Registry.session_id=="shipped","reference-only sample stages cannot become live progress")
	var custom=Set.new();custom.id="fixture_plugin";custom.title="Plugin fixture";custom.base=Registry.DEFAULT;custom.preview=Registry.DEFAULT.preview;custom.preview_pages=Registry.DEFAULT.preview_pages;custom.runtime_enabled=true
	var directory:=folder.path_join("plugin");DirAccess.make_dir_recursive_absolute(directory)
	ResourceSaver.save(custom,directory.path_join("set.tres"))
	var plugins:=Registry.discover([folder])
	check(plugins.has("fixture_plugin") and Registry.validate(plugins.fixture_plugin,true).is_empty(),"a new folder/manifest inherits working adapters without a registry edit")
	custom.base=Resource.new()
	check(not Registry.validate(custom,true).is_empty(),"invalid inheritance fails before touching active preferences")
	for id:String in ["shipped","survey","expedition"]:
		check(Registry.activate(id).ok and Registry.active().id==id,"functional set activates: "+id)
		var browser=load("res://demo/worlds.gd").new();browser.preview_mode=true;root.add_child(browser)
		check(browser.library==null and browser.preparation_pid<0 and browser.photograph_pid<0 and not browser.is_processing(),"mockup browser cannot read saves or start background jobs: "+id)
		check(browser.ui_set.id==id and browser.worlds!=null and browser.generate_button!=null and browser.preparation_panel!=null,"live adapters provide all browser/create bindings: "+id)
		check(browser.selected_options()==preload("res://addons/world_runtime/world_recipe.gd").DEFAULTS,"presentation set preserves actual generation recipe: "+id)
		browser.free()
		var screen=load("res://addons/world_runtime/generation_screen.gd").new();root.add_child(screen)
		screen.panel.reset();screen.update_stage("Baking destructible sidewalk plates",500,1000)
		check(is_equal_approx(screen.panel.bar.value,63.5) and screen.panel.get_meta("ui_set").id==id,"live progress uses measured coordinator stages: "+id)
		screen.panel.show_progress("Loading your world","Contact preparation",71)
		screen.panel.show_progress("Loading your world","Late sample",50)
		check(screen.panel.bar.value==71 and screen.diagnostics!=null and screen.cancel_button.disabled,"progress, diagnostics and action guards are retained: "+id)
		if DisplayServer.get_name()!="headless":
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(folder.path_join(id+"_loading.png"))
		screen.free();await process_frame
	prefs.load(Registry.preference_path)
	check(prefs.get_value("unrelated","preserved")==123,"activation preserves other preferences")
	Registry.session_id=""
	check(Registry.selected_id()=="expedition","selected set restores from disk without a session override")
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
	studio.free();Registry.session_id=original_id;Registry.preference_path=original_path;await process_frame
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	print("UI_SETS checks=",checks," failures=",failures);quit(1 if failures else 0)
