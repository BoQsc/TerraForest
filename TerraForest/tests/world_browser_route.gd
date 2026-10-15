# SPDX-License-Identifier: 0BSD
extends SceneTree
const Launch=preload("res://demo/world_launch.gd")
var game: Node
var failures:=0
var report:=""
func check(ok: bool,message: String)->bool:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures+=1
	return ok
func _initialize()->void:run.call_deferred()
func wait_until(predicate: Callable,seconds: int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--browser-child" in args:
		await child(args);return
	var slot:="browser_route_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()]
	report=ProjectSettings.globalize_path("res://reports/world_browser/"+slot)
	DirAccess.make_dir_recursive_absolute(report)
	for reopen in [false,true]:
		var result:=Launch.command(slot,not reopen,1,7129,true)
		if not check(result.ok,"browser accepts create/open command"):break
		var command:PackedStringArray=result.args
		# Retain production engine/user flags; substitute an observing SceneTree
		# which instantiates the same world scene and performs an ordinary save.
		var index:=command.find("res://demo/world.tscn")
		command.remove_at(index);command.insert(index,"res://tests/world_browser_route.gd");command.insert(index,"--script")
		command.insert(0,report.path_join("reopen.log" if reopen else "create.log"));command.insert(0,"--log-file")
		command.append_array(PackedStringArray(["--browser-child","--browser-report="+report]))
		if reopen:command.append("--browser-reopen")
		var pid:=OS.create_process(OS.get_executable_path(),command)
		if not check(pid>0,"Godot process handoff starts"):break
		if not await wait_until(func():return not OS.is_process_running(pid),180):
			check(false,"child process deadline");OS.kill(pid);break
		var output:=report.path_join("reopen.json" if reopen else "create.json")
		var recorded=JSON.parse_string(FileAccess.get_file_as_string(output)) if FileAccess.file_exists(output) else null
		if not check(recorded is Dictionary and recorded.get("failures",-1)==0,"child world assertions and compound save pass"):break
	print("WORLD_BROWSER_ROUTE failures=",failures," report=",report)
	quit(1 if failures else 0)
func child(args: PackedStringArray)->void:
	var slot:=""
	for arg in args:
		if arg.begins_with("--browser-report="):report=arg.trim_prefix("--browser-report=")
		if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
	if not slot.begins_with("browser_route_") or report.is_empty():quit(2);return
	var reopen:bool="--browser-reopen" in args
	game=load("res://demo/world.tscn").instantiate();game.background_fps=60;root.add_child(game)
	if check(await wait_until(func():return not game.loading_active,90),"actual world loading completes"):
		game.set_physics_process(false);game._clear_motion()
		check(game.terrain.save_slot==slot and not game.temporary_world,"isolated persistent slot active")
		check(game.terrain.backend.world_generator==1 and game.terrain.backend.world_seed==7129,"selected generation survives fresh reopen without overrides")
		check(game.construction_inventory.gameplay and not game.session_menu.developer,"paid gameplay active")
		check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1080p fullscreen full render scale")
		var snapshot:=report.path_join("inventory.bin")
		if reopen:
			check(game.player_hud.inventory.capture_storage_snapshot()==FileAccess.open(snapshot,FileAccess.READ).get_var(),"exact inventory restored in new process")
		else:
			var inventory=game.player_hud.inventory
			check(inventory.consume_items(PackedInt64Array([102,7]),inventory.snapshot().revision).ok,"change starter wood count to distinguish saved state from defaults")
			var file:=FileAccess.open(snapshot,FileAccess.WRITE);file.store_var(game.player_hud.inventory.capture_storage_snapshot());file.close()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(report.path_join("reopen.png" if reopen else "create.png"))
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"ordinary compound save completes")
	game.free();await process_frame
	var output:=FileAccess.open(report.path_join("reopen.json" if reopen else "create.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"failures":failures,"slot":slot}));output.close()
	quit(1 if failures else 0)
