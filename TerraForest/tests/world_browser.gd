# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
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
	check(integrated.ok and integrated.get("prepare",false) and "districts" in integrated.args and "50" in integrated.args,"integrated preset routes through verified offline preparation")
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
	file=FileAccess.open(path.path_join("preparing.prepare.lock"),FileAccess.WRITE);file.close()
	check(not Launch.command("preparing",true,6,1703,true,path).ok,"in-progress preparation name is reserved")
	check(Launch.saved_slots(path)==PackedStringArray(["saved_world"]) and not Launch.command("missing",false,6,1703,true,path).ok,"listing selects canonical saves and missing save fails")
	auto_accept_quit=false
	var browser=load("res://demo/worlds.tscn").instantiate();root.add_child(browser)
	check(auto_accept_quit,"browser restores window close after returning from a world")
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
	browser.free()
	print("WORLD_BROWSER failures=",failures);quit(1 if failures else 0)
