# SPDX-License-Identifier: 0BSD
extends SceneTree
const Outdoors=preload("res://addons/structures/outdoor_generation.gd")
const Homes=preload("res://addons/structures/furniture_catalog.gd")
var checks:=0
var failures:=0
var folder:=""
var game:Node
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--check-evidence-dir="):folder=arg.trim_prefix("--check-evidence-dir=")
	run.call_deferred()
func check(ok:bool,label:String)->bool:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label);return ok
func run()->void:
	var source:="user://worlds/Hidden_Meadow.trw";var before:=FileAccess.get_sha256(source)
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot=Hidden_Meadow","--snapshot-readonly","--temporary","--no-derived-cache","--ground-cover","--actors","--vehicle-fleet"]),true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.model_region_paging=false;game.background_fps=60;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+120000
	while game.loading_active and Time.get_ticks_msec()<deadline:game.app_focused=true;await process_frame
	if check(game.startup_complete and not game.loading_active,"ordinary read-only world loads with furnished construction catalog"):
		game.player_view.entry.finish();game.session_menu.set_open(false);game.app_focused=true
		if game.session_menu.developer:game.session_menu.toggle_developer()
		game.session_menu.developer_hud.hidden_by_user=true;game.session_menu.developer_hud.refresh()
		check(game.structure_prefabs.any(func(asset:Resource):return asset.get_meta("homestead_archetype","")=="cottage_a2"),"normal construction offers the furnished cottage")
		check(game.structure_prefabs.any(func(asset:Resource):return asset.get_meta("homestead_archetype","")=="house_c1"),"normal construction offers the furnished large house")
		var lots:Array=[]
		for point:Vector3i in [Vector3i(1840,40,1450),Vector3i(1880,40,1470),Vector3i(1820,40,1510)]:lots.append({"asset":Homes.enclosed_cottage(),"origin":point,"rotation":lots.size(),"label":"Transient outdoor admission fixture %d"%lots.size()})
		var roads:Array=game.generated_region.store.get_plan().get("roads",[])
		var result:=await Outdoors.publish(game,lots,roads,1703)
		check(result.get("ok",false),"normal generation outdoor publication runs against actual terrain: "+str(result.get("reason","ok")))
		if result.get("ok",false):
			check(result.placements.size()>=16,"many outdoor objects pass real terrain, clearance and water checks")
			var saved:PackedByteArray=game.structures.capture_storage_snapshot()
			var validator:RefCounted=game.structures.snapshot_validator()
			check(validator.validate_storage_snapshot(saved),"outdoor additions remain valid ordinary native save data")
			if DisplayServer.get_name()!="headless" and not result.placements.is_empty():
				var focus:Vector3=result.placements[0].position;game.camera.global_position=focus+Vector3(5,3,7);game.camera.look_at(focus+Vector3.UP*.5)
				for frame in 45:game.app_focused=true;await process_frame
				await RenderingServer.frame_post_draw
				check(root.get_texture().get_image().save_png(folder.path_join("outdoors.png"))==OK,"captured real terrain-supported outdoor objects")
		FileAccess.open(folder.path_join("outdoor_publication.json"),FileAccess.WRITE).store_string(JSON.stringify(result))
	game.shutdown_requested=true
	check(await game.terrain.shutdown_after_edits(),"temporary gameplay shuts down cleanly")
	game.free();await process_frame;await process_frame
	check(FileAccess.get_sha256(source)==before,"existing Hidden Meadow save remains byte-for-byte unchanged")
	print("HOUSE_POPULATION_WORLD checks=",checks," failures=",failures);quit(1 if failures else 0)
