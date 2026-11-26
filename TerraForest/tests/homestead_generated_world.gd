# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
## Explicit user-requested playable world, never a disposable fixture or retrofit.
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const Plan=preload("res://addons/world_runtime/world_generation_plan.gd")
var slot:="Homestead_Valley"
var source:=""
var report:=""
var readonly:=false
var original_hash:=""

func _initialize()->void:
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--check-evidence-dir="):folder=argument.trim_prefix("--check-evidence-dir=")
		if argument.begins_with("--homestead-source="):source=argument.trim_prefix("--homestead-source=")
	run.call_deferred()

func run()->void:
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	if not check(await wait_for(browser_catalog_ready),"normal world browser is ready"):await finish();return
	var browser=current_scene
	if "--create-homestead-world" in OS.get_cmdline_user_args():
		if not check(not FileAccess.file_exists("user://worlds/"+slot+".trw"),"requested new world refuses to overwrite an existing save"):await finish();return
		browser.name_field.text=slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.world_style.get_item_text(browser.world_style.selected)=="Frontier expedition" and browser.selected_options()==Recipe.DEFAULTS,"untouched Frontier expedition recipe reaches Generate & play")
		var started:=Time.get_ticks_msec()
		browser.generate_button.pressed.emit()
		var status_path:String=browser.preparation_status
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return state is Dictionary and state.get("state","") in ["failed","cancelled"]
			return false,520)
		if not check(game_ready(),"normal generation publishes and opens the new furnished world"):
			print("HOMESTEAD_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
		var state:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(status_path));report=state.report
		var receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.path_join("run.json")))
		var ordinary:=true
		for phase:Dictionary in receipt.phases:
			for argument:String in phase.arguments:ordinary=ordinary and argument not in ["--civic-review","--building-expansion-review","--review-generation"]
		check(ordinary,"normal production phases use no review content switches")
		check(not current_scene.temporary_world and current_scene.terrain.save_slot==slot,"published world is an ordinary persistent playable save")
		var outdoors:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.path_join("outdoor_objects.json")))
		check(outdoors.get("ok",false) and outdoors.placements.size()>=100,"many supported outdoor objects are published across the generated lots")
		print("HOMESTEAD_GENERATED milliseconds=",Time.get_ticks_msec()-started," outdoor_objects=",outdoors.placements.size()," report=",report)
		await prepare_view(current_scene)
		await photograph("arrival")
		await finish();return
	if not check(not source.is_empty() and FileAccess.file_exists(source),"fresh-process inspection identifies its generation receipt"):await finish();return
	var record:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	if not check(record.get("slot","")==slot and record.get("sha256","")==FileAccess.get_sha256("user://worlds/"+slot+".trw"),"published new world matches its saved generation hash"):await finish();return
	report=record.report;readonly=true;original_hash=record.sha256
	var generation:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.path_join("run.json")))
	# Native recipe admission requires integer values; JSON parses numbers as floats.
	var options:Dictionary=generation.world_options.duplicate()
	for key:String in options:options[key]=int(options[key])
	check(Recipe.encode(options)==Recipe.encode(Recipe.DEFAULTS) and generation.destination==slot and generation.get("publication",{}).get("ok",false),"normal default Frontier expedition recipe completed native publication")
	var listed:=false
	for index in browser.worlds.item_count:
		if browser.worlds.get_item_metadata(index)==slot:listed=true;break
	check(listed,"My worlds lists the new playable world")
	var request:Dictionary=Launch.command(slot,false,Launch.INTEGRATED_PRESET,1703,true)
	request.args.append_array(PackedStringArray(["--snapshot-readonly","--temporary"]))
	browser._open_game(request.args)
	if not check(await wait_for(game_ready,120),"fresh process restores the normal published world"):await finish();return
	var game=current_scene
	await prepare_view(game)
	var settings:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
	var worker:=Thread.new();worker.start(Plan.build.bind(1703,game.terrain.backend.world_generator,true,true,"user://generation_plans",settings))
	while worker.is_alive():await process_frame
	var planned:Dictionary=worker.wait_to_finish()
	if not check(planned.get("ok",false) and planned.cache_hit,"saved recipe restores the exact generated placement plan"):await finish();return
	var house:Dictionary={};var cottage:Dictionary={}
	var furnished:=0;var attachments:=0
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			attachments+=lot.asset.get_model_attachments().size()
			if lot.asset.has_meta("homestead_furnishings"):furnished+=1
			if house.is_empty() and lot.asset.get_meta("homestead_archetype","")=="house_c1":house=lot
			if cottage.is_empty() and lot.asset.get_meta("homestead_archetype","")=="cottage_a2":cottage=lot
	check(furnished>=20 and not house.is_empty() and not cottage.is_empty(),"generated plan contains furnished houses throughout the settlements")
	if not house.is_empty():
		await view_lot(game,house,Vector3(-1.4,6.6,-1),Vector3(-2.8,5.8,-4.6),"house_interior")
	if not cottage.is_empty():
		await view_lot(game,cottage,Vector3(.3,3.6,3.4),Vector3(0,2.8,-2.2),"cottage_interior")
	var outdoors:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(report.path_join("outdoor_objects.json")))
	var positions:=PackedVector3Array()
	for item:Dictionary in outdoors.placements:
		var values:=str(item.position).trim_prefix("(").trim_suffix(")").split(",")
		positions.append(Vector3(float(values[0]),float(values[1]),float(values[2])))
	# Photograph a populated yard, with the camera on its outside edge. The
	# previous fixed world-space offset could put a house between camera and props.
	var selected:=0;var largest:=0
	for index in positions.size():
		var nearby:=0
		for other:Vector3 in positions:
			if positions[index].distance_squared_to(other)<25:nearby+=1
		if nearby>largest:largest=nearby;selected=index
	var row:Dictionary=outdoors.placements[selected];var focus:Vector3=positions[selected]
	var outward:=Vector3.FORWARD;var closest:=INF
	for site:Dictionary in planned.sites:
		for lot:Dictionary in site.lots:
			var offset:Vector3=focus-lot.asset.placement_bounds(lot.origin,lot.rotation).get_center();offset.y=0
			if offset.length_squared()<closest:closest=offset.length_squared();outward=offset.normalized()
	game.teleport(focus+Vector3.UP*2)
	if check(await wait_for(func():return not game.loading_active and game.ecosystem.coverage_status().ready,90),"outdoor yard streams with ordinary gameplay systems"):
		var collection=game.structures.model_collections()[row.model]
		var pose:PackedFloat32Array=collection.get_instance(int(row.id))
		check(pose.size()==12 and Vector3(pose[3],pose[7],pose[11]).distance_to(focus)<.001,"generated outdoor object identity and pose survive fresh-process restoration")
		game.set_physics_process(false);game._clear_motion()
		game.camera.global_position=focus+outward*7+Vector3.UP*3.1;game.camera.look_at(focus+Vector3.UP*.6)
		for frame in 90:game.app_focused=true;await process_frame
		await photograph("outdoor_yard")
	FileAccess.open(folder.path_join("inspection.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":slot,"report":report,"checks":checks,"failures":failures,"furnished_lots":furnished,"planned_attachments":attachments,"outdoor_objects":outdoors.placements.size(),"plan_digest":planned.plan_digest,"fresh_process":true}))
	await finish()

func prepare_view(game:Node)->void:
	game.background_fps=60;game.app_focused=true
	game.player_view.entry.finish();game.session_menu.set_open(false)
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.developer_hud.hidden_by_user=true;game.session_menu.developer_hud.refresh()
	game.camera.cull_mask&=~((1<<18)|(1<<19))
	await process_frame

func point(lot:Dictionary,local:Vector3)->Vector3:
	for turn in lot.rotation:local=Vector3(1-local.z,local.y,local.x)
	return Vector3(lot.origin)+local

func view_lot(game:Node,lot:Dictionary,eye:Vector3,target:Vector3,label:String)->void:
	game.set_physics_process(true);game.teleport(point(lot,eye))
	var bounds:AABB=lot.asset.placement_bounds(lot.origin,lot.rotation)
	if not check(await wait_for(func():return not game.loading_active and game.structures.is_collision_region_ready(bounds),90),label+" actual saved building streams with collision"):return
	# Compare every persisted Homestead attachment against its authored native pose.
	var collections:Dictionary=game.structures.model_collections();var exact:=true;var tested:=0
	var frame:=Transform3D(Basis(Vector3.UP,-PI/2*lot.rotation),point(lot,Vector3.ZERO))
	for attachment:Dictionary in lot.asset.get_model_attachments():
		if not attachment.model.begins_with("packs/"):continue
		var expected:Transform3D=frame*attachment.transform
		var found:=false
		var collection=collections[attachment.model]
		for identity:int in collection.get_ids():
			var pose:PackedFloat32Array=collection.get_instance(identity)
			if pose.size()==12 and Vector3(pose[3],pose[7],pose[11]).distance_to(expected.origin)<.001:found=true;break
		exact=exact and found;tested+=1
	check(exact and tested>=15,label+" all authored Homestead object positions restore in native collections")
	game.set_physics_process(false);game._clear_motion();game.fly=true
	game.camera.global_position=point(lot,eye);game.camera.look_at(point(lot,target))
	for tick in 90:game.app_focused=true;await process_frame
	await photograph(label)

func photograph(label:String)->void:
	await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.convert(Image.FORMAT_RGB8)
	check(picture.save_png(folder.path_join(label+".png"))==OK,"captured "+label+" in the new generated world")

func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"generated world closes cleanly")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	var path:="user://worlds/"+slot+".trw"
	if readonly:check(FileAccess.get_sha256(path)==original_hash,"read-only photographs preserve the new save hash")
	elif not report.is_empty():FileAccess.open(folder.path_join("created_world.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":slot,"sha256":FileAccess.get_sha256(path),"report":report,"user_requested_playable_world":true}))
	print("HOMESTEAD_GENERATED_WORLD checks=",checks," failures=",failures," slot=",slot)
	quit(1 if failures else 0)
