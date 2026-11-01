# SPDX-License-Identifier: 0BSD
extends "res://tests/window_session_flow.gd"
const Recipe=preload("res://addons/world_runtime/world_recipe.gd")
const SignPlan=preload("res://addons/world_runtime/town_sign_plan.gd")
var selected_slot:=""
var reopen:=false
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	node_added.connect(func(node:Node):
		if node.scene_file_path=="res://demo/world.tscn":ProjectSettings.set_setting("terraforest/offscreen_session",true))
	folder="res://reports/town_signs_world"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--session-evidence-dir="):folder=argument.trim_prefix("--session-evidence-dir=")
	reopen="--reopen-signs" in OS.get_cmdline_user_args()
	run.call_deferred()
func run()->void:
	DirAccess.make_dir_recursive_absolute(folder)
	change_scene_to_file("res://demo/worlds.tscn");await scene_changed
	if not check(await wait_for(browser_catalog_ready),"ordinary world browser ready"):await finish();return
	var browser=current_scene
	if not reopen:
		selected_slot="TownSigns_1703_"+Crypto.new().generate_random_bytes(4).hex_encode()
		browser.name_field.text=selected_slot;browser.seed_field.value=1703;browser.world_tabs.current_tab=1
		check(browser.world_style.get_item_text(browser.world_style.selected)=="Connected countryside" and browser.selected_options()==Recipe.DEFAULTS,"unchanged normal Connected countryside recipe")
		browser.generate_button.pressed.emit()
		var status_path:String=browser.preparation_status
		await wait_for(func():
			if game_ready():return true
			if browser_ready() and current_scene.preparation_pid<0 and FileAccess.file_exists(status_path):
				var state=JSON.parse_string(FileAccess.get_file_as_string(status_path))
				return state is Dictionary and state.get("state","") in ["failed","cancelled"]
			return false,520)
		if not check(game_ready(),"Generate & play publishes ordinary signed towns"):
			print("SIGN_GENERATION_STATUS ",FileAccess.get_file_as_string(status_path));await finish();return
		FileAccess.open(folder.path_join("slot.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"status":status_path}))
	else:
		var saved=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("slot.json")))
		if not check(saved is Dictionary and str(saved.get("slot","")).begins_with("TownSigns_1703_"),"restore only this test's own generated world"):await finish();return
		selected_slot=saved.slot;var index:=-1
		for i in browser.worlds.item_count:
			if browser.worlds.get_item_metadata(i)==selected_slot:index=i;break
		if not check(index>=0,"saved signed town appears in My worlds"):await finish();return
		browser.worlds.select(index);browser.launch_selected(false)
		if not check(await wait_for(game_ready,120),"Open selected world restores in fresh process"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	game.zombies.update(0,game.player.global_position,false)
	# Ordinary empty belt selection keeps the held tool out of evidence photos.
	game.player_hud.equip(6)
	check(not Options.arguments().has("--civic-review") and not Options.arguments().has("--building-expansion-review"),"normal play has no content review flags")
	var signs=game.town_signs;var saved:Dictionary=signs.store.get_plan()
	var settings:Dictionary=Recipe.codec().decode(game.world_recipe.store.capture_snapshot())
	var counts:Dictionary={}
	for place:Dictionary in saved.get("places",[]):counts[place.title]=int(counts.get(place.title,0))+1
	var correct:bool=counts.size()==settings.settlements and saved.places.size()<=6
	for title:String in counts:correct=correct and counts[title]>=1 and counts[title]<=2
	check(correct,"one or two persistent signs per town, at most six per world")
	var names_match:=true
	for town in int(settings.settlements):
		var title:=SignPlan.town_name(1703,town)
		names_match=names_match and counts.has(title) and game.generated_region.store.get_plan().places.any(func(place:Dictionary):return place.title.begins_with(title+" / District"))
	check(names_match,"road signs and normal map share the actual town names")
	var captured:Array=[];var timings:Array=[]
	for place:Dictionary in saved.places:
		if captured.has(place.title):continue
		captured.append(place.title)
		game.teleport(place.position+Vector3(6,1,6))
		if not check(await wait_for(func():game.app_focused=true;return not game.loading_active and signs.collection.get_instance(place.id).size()==12,90),"sign body streams at "+place.title):continue
		game.set_physics_process(false);game._clear_motion()
		var camera_local:Transform3D=game.camera.transform
		var tool_visible:bool=game.tool_view.visible;game.tool_view.hide()
		var label:Node3D=signs.labels.get(place.id)
		if not check(is_instance_valid(label),"persistent lettering streams with body at "+place.title):continue
		var pose:Transform3D=label.transform*Transform3D(Basis.IDENTITY,Vector3(0,-1.88,-.04))
		var eye:Vector3=pose.origin+pose.basis.z*14-pose.basis.x*8+Vector3.UP*1.7
		game.camera.global_position=eye;game.camera.look_at(pose.origin+Vector3.UP*1.85)
		for i in 90:await process_frame
		# No image readback, compression or logging during these scoped samples.
		if not "--signs-untimed" in OS.get_cmdline_user_args():
			var samples:Array[float]=[];var previous:=Time.get_ticks_usec()
			for i in 120:
				await process_frame
				var now:=Time.get_ticks_usec();samples.append((now-previous)/1000.0);previous=now
			samples.sort();timings.append({"town":place.title,"frames":120,"p95_ms":samples[113],"worst_ms":samples[-1],"scope":"stationary populated roadside; 1080p, 60 FPS cap; no image readback"})
		else:timings.append({"town":place.title,"scope":"timing skipped: concurrent native build; functional/visual checks only"})
		await photograph(("restore_" if reopen else "road_")+place.title.to_lower().replace(" ","_"))
		game.camera.global_position=pose.origin+pose.basis.z*5.5-pose.basis.x*1.5+Vector3.UP*1.8
		game.camera.look_at(pose.origin+Vector3.UP*1.8)
		for i in 30:await process_frame
		await photograph("close_"+place.title.to_lower().replace(" ","_"))
		var body:RID=signs.collection.collision_body_for(place.id)
		check(body.is_valid(),"native sign collision is resident")
		var query:=PhysicsRayQueryParameters3D.create(pose*Vector3(0,1.9,2),pose*Vector3(0,1.9,-2))
		var hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(query)
		check(not hit.is_empty() and hit.rid==body,"physical board receives ordinary world ray hits")
		var probes:=PackedVector3Array([pose*Vector3(-1.04,0,-.2),pose*Vector3(1.04,0,-.2)])
		var survey:Dictionary=await signs.survey(game.terrain,probes)
		var supported:bool=survey.get("ok",false) and survey.get("supported",false)
		if supported:
			for point:Vector3 in survey.points:supported=supported and point.y>=pose.origin.y-.4 and point.y<=pose.origin.y+.05
		check(supported,"both sign posts penetrate actual edited terrain without floating")
		game.camera.transform=camera_local;game.tool_view.visible=tool_visible;game.set_physics_process(true)
	FileAccess.open(folder.path_join("restore.json" if reopen else "create.json"),FileAccess.WRITE).store_string(JSON.stringify({"slot":selected_slot,"checks":checks,"failures":failures,"signs":saved.places,"counts":counts,"timings":timings},"\t"))
	await finish()
func finish()->void:
	if is_instance_valid(current_scene) and current_scene.scene_file_path=="res://demo/world.tscn":
		current_scene.shutdown_requested=true
		check(await current_scene.terrain.shutdown_after_edits(),"signed world durably saves")
	if is_instance_valid(current_scene):current_scene.free()
	await process_frame
	print("TOWN_SIGNS_WORLD checks=",checks," failures=",failures," reopen=",reopen," slot=",selected_slot)
	quit(1 if failures else 0)
