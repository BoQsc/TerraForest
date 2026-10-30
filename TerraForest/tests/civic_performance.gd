# SPDX-License-Identifier: 0BSD
extends "res://tests/civic_world.gd"
func run()->void:
	folder="res://reports/civic_world"
	var saved=JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("slot.json")))
	if not check(saved is Dictionary and str(saved.get("slot","")).begins_with("CivicReview_1703_"),"isolated performance world"):await finish();return
	selected_slot=saved.slot
	Options.set_arguments(PackedStringArray(["--world-slot="+selected_slot,"--snapshot-readonly","--gameplay-construction","--ground-cover","--actors","--vehicle-fleet","--no-zombies"]),true)
	change_scene_to_file("res://demo/world.tscn");await scene_changed
	if not check(await wait_for(game_ready,120),"populated world restored for paired timing"):await finish();return
	var game=current_scene;game.background_fps=60;game.app_focused=true
	for place:Dictionary in game.generated_region.store.get_plan().places:
		if place.id==Civic.MERCHANT_PLACE:game.teleport(place.position+Vector3(0,0,2.9));break
	if not check(await wait_for(func():return not game.loading_active and is_instance_valid(game.trader.actor) and game.ecosystem.coverage_status().ready,90),"merchant and forest resident"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.fly=false
	game.player.global_position=game.trader.anchor+Vector3(.5,.02,2.9)
	game.camera.position=Vector3(0,1.65,0);game.camera.look_at(game.trader.anchor+Vector3.UP*1.45)
	game.player_hud.equip(9)
	var viewport:=root.get_viewport_rid();RenderingServer.viewport_set_measure_render_time(viewport,true)
	# Main traversal remains capped at 60. This separate paired stationary check
	# removes cap/vsync waiting to expose incremental CPU/GPU cost at full quality.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=0;game.max_fps=0;game.background_fps=0
	var groups:={"merchant_off":[],"merchant_on":[]}
	var gpu:={"merchant_off":[],"merchant_on":[]}
	for enabled in [false,true,true,false]:
		var name:String="merchant_on" if enabled else "merchant_off"
		game.trader.actor.visible=enabled
		game.trader.actor.process_mode=Node.PROCESS_MODE_INHERIT if enabled else Node.PROCESS_MODE_DISABLED
		for frame in 60:await process_frame
		var previous:=Time.get_ticks_usec()
		for frame in 300:
			await RenderingServer.frame_post_draw
			var now:=Time.get_ticks_usec();groups[name].append((now-previous)/1000.0);previous=now
			gpu[name].append(RenderingServer.viewport_get_measured_render_time_gpu(viewport))
	for name:String in groups:
		var times:Array=groups[name];times.sort();gpu[name].sort()
		var total:=0.0
		for value:float in times:total+=value
		metrics.append({"state":name,"frames":times.size(),"mean_ms":total/times.size(),"p95_ms":times[int(times.size()*.95)],"worst_ms":times[-1],"gpu_p95_ms":gpu[name][int(gpu[name].size()*.95)]})
	game.trader.actor.visible=true;game.trader.actor.process_mode=Node.PROCESS_MODE_INHERIT
	Engine.max_fps=60;game.max_fps=60;game.background_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	FileAccess.open(folder.path_join("performance_pair.json"),FileAccess.WRITE).store_string(JSON.stringify({"gpu":RenderingServer.get_video_adapter_name(),"resolution":root.size,"scope":"Same populated view, unchanged quality, 600 samples per state in ABBA order; uncapped to separate render cost from cap waiting. Screenshots outside samples. No endurance or hardware-wide guarantee.","metrics":metrics},"  "))
	check(true,"paired full-quality merchant timing recorded")
	await finish()
