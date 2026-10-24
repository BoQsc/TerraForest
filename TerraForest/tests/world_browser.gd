# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
class NameBrowser extends "res://demo/worlds.gd":
	var submitted_slot:=""
	var submitted_args:=PackedStringArray()
	func start_preparation(result:Dictionary,slot:String)->void:
		submitted_slot=slot;submitted_args=result.args
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var path: String="user://browser_policy_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(path)
	check(not Launch.command("../world",true,6,1703,true,path).ok and not Launch.valid_slot("1world") and not Launch.valid_slot("x".repeat(49)),"invalid names cannot escape or alias save paths")
	check(not Launch.command("new_world",true,6,-1,true,path).ok and not Launch.command("new_world",true,99,1703,true,path).ok,"invalid seed and generator rejected")
	var integrated:=Launch.command("integrated",true,Launch.INTEGRATED_PRESET,50,true,path)
	var buildable:=Launch.command("buildable",true,Launch.INTEGRATED_PRESET,50,true,path,true,"connected",true)
	check(buildable.ok and "--generator=21" in buildable.args,"build-friendly coast routes to its own saved generator identity")
	check("--generator=20" in Launch.command("buildable_inland",true,Launch.INTEGRATED_PRESET,50,true,path,false,"connected",true).args,"build-friendly terrain also supports no-ocean worlds")
	check(integrated.ok and integrated.get("prepare",false) and "--generator=21" in integrated.args and "--seed=50" in integrated.args,"integrated preset routes through verified offline preparation")
	check("--generator=21" in integrated.args and "res://addons/world_runtime/generation_job.gd" in integrated.args,"new integrated worlds default to the accepted build-friendly coast recipe")
	check("--generator=19" in Launch.command("original_coast",true,Launch.INTEGRATED_PRESET,50,true,path,true,"connected",false).args,"explicit opt-out retains the original coastal terrain")
	var legacy:=Launch.command("legacy",true,Launch.LEGACY_INTEGRATED_PRESET,50,true,path,false)
	check(legacy.ok and legacy.get("prepare",false) and "--generator=13" in legacy.args,"earlier authored recipe remains available without unsupported coast overrides")
	var inland:=Launch.command("inland",true,Launch.INTEGRATED_PRESET,50,true,path,false)
	check(inland.ok and "--generator=20" in inland.args,"ocean can be disabled while keeping build-friendly terrain")
	check("--generator=17" in Launch.command("original_inland",true,Launch.INTEGRATED_PRESET,50,true,path,false,"connected",false).args,"explicit opt-out retains the original inland terrain")
	var created:=Launch.command("new_world",true,6,1703,true,path)
	check(created.ok and "--world-generator=6" in created.args and "--world-seed=1703" in created.args and "--gameplay-construction" in created.args and "--ground-cover" in created.args,"new world command uses chosen generation and gameplay settings")
	check("--fullscreen" in created.args and "1920x1080" in created.args and "res://demo/world.tscn" in created.args,"launch targets actual world at full resolution")
	check(not FileAccess.file_exists(path.path_join("new_world.trw")),"command preparation never creates or changes canonical data")
	var file:=FileAccess.open(path.path_join("saved_world.trw"),FileAccess.WRITE);file.store_string("sentinel");file.close()
	check(not Launch.command("saved_world",true,6,1703,true,path).ok,"creation refuses an existing world")
	var opened:=Launch.command("saved_world",false,1,99,false,path)
	check(opened.ok and not "--world-generator=1" in opened.args and not "--world-seed=99" in opened.args and not "--gameplay-construction" in opened.args,"opening preserves saved generation and permits chosen editor mode")
	check(FileAccess.get_file_as_string(path.path_join("saved_world.trw"))=="sentinel","opening command preserves canonical bytes")
	DirAccess.make_dir_recursive_absolute(path.path_join("orphan.trw.models"))
	check(not Launch.command("orphan",true,6,1703,true,path).ok,"orphan model data prevents accidental name reuse")
	var preparation_lease=ClassDB.instantiate("NativeWorldArchive")
	check(preparation_lease.acquire(ProjectSettings.globalize_path(path.path_join("preparing.prepare"))),"fixture owns preparation lease")
	check(not Launch.command("preparing",true,6,1703,true,path).ok,"in-progress preparation name is reserved")
	preparation_lease.release()
	check(Launch.command("preparing",true,6,1703,true,path).ok,"stale preparation lock does not permanently reserve a name")
	check(Launch.saved_slots(path)==PackedStringArray(["saved_world"]) and not Launch.command("missing",false,6,1703,true,path).ok,"listing selects canonical saves and missing save fails")
	var staging:="combined_stage_"+"a".repeat(32)
	file=FileAccess.open(path.path_join(staging+".trw"),FileAccess.WRITE);file.store_string("unverified stage");file.close()
	check(not staging in Launch.saved_slots(path) and staging in Launch.saved_slots(path,true),"unverified staging saves are hidden by default and retained for recovery")
	check(not Launch.preparation_slot("combined_stage_my_home"),"ordinary similarly named worlds remain visible")
	check(not Launch.command(staging,true,Launch.INTEGRATED_PRESET,50,true,path).ok,"reserved staging identity cannot be used for new playable world")
	check("--snapshot-readonly" in Launch.command(staging,false,12,50,true,path).args,"explicit preparation review disables snapshot writes")
	check(FileAccess.get_file_as_string(path.path_join(staging+".trw"))=="unverified stage","listing and launch preparation preserve stage bytes")
	auto_accept_quit=false
	var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
	check(not auto_accept_quit and browser.has_method("request_quit"),"browser owns close requests so preparation can cancel safely")
	check(browser.ocean.button_pressed and browser.ocean.visible,"coast creation option is visible and enabled by default")
	browser.preset.select(1);browser.preset.item_selected.emit(1)
	check(not browser.ocean.visible,"legacy landscape choices do not expose an unsupported coast option")
	browser.preset.select(0);browser.preset.item_selected.emit(0)
	browser.slots=PackedStringArray(["woodland_home","natural_cave_gameplay","mixed_neighborhood_review"]);browser.filter_list()
	browser.filter_field.text="CAVE";browser.filter_field.text_changed.emit("CAVE");check(browser.worlds.item_count==1,"saved-world filtering ignores case")
	browser.filter_field.text="";browser.filter_field.text_changed.emit("");browser.name_field.text="../bad";browser.launch_selected(true)
	check(browser.notice.text.begins_with("Use 1–48"),"invalid create action stays in browser with guidance")
	if DisplayServer.get_name()!="headless":
		for i in 3:await process_frame
		var screen:=Rect2(Vector2.ZERO,Vector2(root.size))
		check(screen.encloses(browser.worlds.get_global_rect()) and screen.encloses(browser.notice.get_global_rect()) and screen.encloses(browser.seed_field.get_global_rect()),"primary world controls fit 1920x1080")
		browser.name_field.text="woodland_home";browser.notice.text="Choose a saved world, or create a new one. Existing data is preserved."
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports/world_browser")
		root.get_texture().get_image().save_png("res://reports/world_browser/browser.png")
		var pages:TabContainer=browser.buildable_ground.get_parent().get_parent().get_parent()
		pages.current_tab=1
		for frame in 3:await process_frame
		check(browser.buildable_ground.is_visible_in_tree() and screen.encloses(browser.buildable_ground.get_global_rect()) and screen.encloses(browser.seed_field.get_global_rect()),"build-friendly terrain control and seed fit the visible creation page")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/world_browser/buildable_create.png")
	browser.free()
	# Exercise the real create action without starting an unnecessary world bake.
	var naming:=NameBrowser.new();root.add_child(naming)
	check(naming.buildable_ground.button_pressed and naming.selected_preview_key().contains("/21/"),"browser and map preview default to the same accepted terrain profile")
	naming.buildable_ground.button_pressed=false
	check(naming.selected_preview_key().contains("/19/"),"turning terrain experiment off restores the original landscape preview")
	naming.buildable_ground.button_pressed=true
	naming.name_field.text="   ";naming.seed_field.value=123;naming.launch_selected(true)
	var generated:String=naming.name_field.text
	check(Launch.valid_slot(generated) and generated.split("_").size()>=2 and naming.submitted_slot==generated and "--destination="+generated in naming.submitted_args,"blank create action assigns and submits a two-word world name")
	check(naming.seed_field.value==123 and "--seed=123" in naming.submitted_args,"automatic naming preserves the chosen terrain seed")
	var chosen:="Named_World_%d"%Time.get_ticks_usec()
	naming.name_field.text=chosen;naming.launch_selected(true)
	check(naming.name_field.text==chosen and naming.submitted_slot==chosen,"explicit world name remains unchanged")
	naming.free()
	file=FileAccess.open(path.path_join("misty_grove.trw.bak"),FileAccess.WRITE);file.store_string("keep backup");file.close()
	DirAccess.make_dir_recursive_absolute(path.path_join("Misty_Grove_2.trw.models"))
	file=FileAccess.open(path.path_join("Misty_Grove_3.clone.lock"),FileAccess.WRITE);file.store_string("keep lock");file.close()
	var available:String=Launch.unique_world_name("Misty_Grove",path)
	check(available=="Misty_Grove_4" and Launch.valid_slot(available) and FileAccess.get_file_as_string(path.path_join("misty_grove.trw.bak"))=="keep backup","automatic names avoid case aliases backups model folders and preparation locks")
	print("WORLD_BROWSER failures=",failures);quit(1 if failures else 0)
