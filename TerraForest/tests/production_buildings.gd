# SPDX-License-Identifier: 0BSD
extends "res://tests/civic_world.gd"
const E2=preload("res://addons/structures/expansion_catalog.gd")

func run()->void:
	folder="res://reports/production_buildings";DirAccess.make_dir_recursive_absolute(folder)
	restoration="--restore-production" in OS.get_cmdline_user_args()
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	await wait_for(browser_catalog_ready)
	var browser=current_scene
	if "--create-production" in OS.get_cmdline_user_args():
		selected_slot="CivicTown_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		browser.name_field.text=selected_slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.world_style.get_item_text(browser.world_style.selected)=="Connected countryside","normal default recipe is Connected countryside")
		check(browser.selected_options()==Recipe.DEFAULTS,"unchanged normal UI settings reach generation")
		await photograph("create_world")
		browser.generate_button.pressed.emit()
		var status_path:String=browser.preparation_status
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return state is Dictionary and state.get("state","") in ["failed","cancelled"]
			return false,520)
		if not check(game_ready(),"normal Generate & play creates and opens the civic world"):
			print("PRODUCTION_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
		var state:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path))
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(str(state.report).path_join("run.json")))
		var ordinary:=true
		for phase:Dictionary in receipt.phases:
			for argument:String in phase.arguments:ordinary=ordinary and argument not in ["--civic-review","--building-expansion-review","--review-generation"]
		check(ordinary,"production generation uses no review-only flags")
		FileAccess.open(folder.path_join("slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"status":status_path,"report":state.report}))
		check(current_scene.generated_region.store.get_plan().places.any(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE),"normal generated world persists resident trader location")
		await photograph("first_play")
		await finish();return
	var saved=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("slot.json")))
	if not check(saved is Dictionary and str(saved.get("slot","")).begins_with("CivicTown_1703_"),"integration owns its new world only"):await finish();return
	selected_slot=saved.slot
	var selected:=-1
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==selected_slot:selected=index;break
	if not check(selected>=0,"normal saved-world browser lists the generated world"):await finish();return
	browser.worlds.select(selected);browser.launch_selected(false)
	if not check(await wait_for(game_ready,120),"normal Open selected world restores in a fresh process"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	check(not Options.arguments().has("--civic-review") and not Options.arguments().has("--building-expansion-review"),"ordinary saved-world session needs no review switches")
	var settings:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",settings))
	while worker.is_alive():await process_frame
	planned=worker.wait_to_finish()
	if not check(planned.get("ok",false),"normal recipe reconstructs the generated plan"):await finish();return
	check(planned.cache_hit and planned.sites[0].recipe_kind=="civic","preview and generation reuse the same approved civic plan")
	var markers:Array=game.generated_region.store.get_plan().places.filter(func(place:Dictionary):return int(place.id)==Civic.MERCHANT_PLACE)
	check(markers.size()==1,"exactly one resident trader map destination persists")
	var available:={}
	for asset:Resource in game.structure_prefabs:
		if asset.has_meta("expansion_id"):available[str(asset.get_meta("expansion_id"))]=true
	check(available.size()==9,"all nine approved E2 buildings are in normal construction")
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			if not lot.asset.has_meta("expansion_id"):continue
			var id:String=lot.asset.get_meta("expansion_id")
			if approved_records.has(id):continue
			var transformed:Resource=ClassDB.instantiate("NativeBlockPrefab")
			transformed.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
			approved_records[id]=transformed.get_records();approved_lots[id]=lot
	check(approved_records.size()==8,"default civic and market plan includes all five civic and three small-building E2 types")
	if not restoration:await verify_approved_records(game)
	await trade_world(game,planned.sites[0].lots[0])
	if not restoration:
		for lot:Dictionary in planned.sites[0].lots:await inspect_detail(game,lot)
	FileAccess.open(folder.path_join("restore.json" if restoration else "result.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"checks":checks,"failures":failures,"generation":"normal UI, no review flags","recipe":settings,"plan_digest":planned.plan_digest}))
	await finish()

func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.trader.ui.close();current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"normal generated world durably saves after interaction")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("PRODUCTION_BUILDINGS checks=",checks," failures=",failures," slot=",selected_slot)
	quit(1 if failures else 0)
