extends "res://tests/combined_resource_route.gd"

var view:=SubViewport.new()
var samples:Array=[]
var publications:Array=[]
var impacts:Array=[]

func probe()->Dictionary:
	var origin:Vector3=game.camera.global_position
	var endpoint:Vector3=origin-game.camera.global_basis.z*game.world_attack.reach()
	var solid:Dictionary=game.structures.blocks.raycast_scene(origin,endpoint,0xFFFFFFFF,[game.player.get_rid()])
	var terrain_hit:Dictionary=game.structures.blocks.raycast_scene(origin,endpoint,1,[game.player.get_rid()])
	var selected:Dictionary=game.world_attack.target()
	return {"solid":solid,"terrain_hit":terrain_hit,"selected":selected,"available":game._model_edit_available(),"error":game.terrain.latest_error,"pending":game.terrain.pending_edit,"revision":game.terrain.native_revision,"dirty_cover":game.ground_cover._dirty.size(),"pending_cover":game.ground_cover._pending.size()}

func picture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await RenderingServer.frame_post_draw
	check(game.get_viewport().get_texture().get_image().save_png(evidence.path_join(label+".png"))==OK,"capture "+label)

func run()->void:
	var arguments:=OS.get_cmdline_user_args()
	var slot:=""
	for argument in arguments:
		if argument.begins_with("--mining-evidence="):evidence=argument.trim_prefix("--mining-evidence=")
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
	if evidence.is_empty() or not slot.begins_with("mining_target_") or "--snapshot-readonly" not in arguments or "--temporary" not in arguments:quit(2);return
	var animated:bool="--mining-input" in arguments
	ProjectSettings.set_setting("terraforest/offscreen_session",not animated)
	if not animated:
		view.size=Vector2i(1920,1080);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	else:view.free()
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path=""
	if animated:root.add_child(game)
	else:view.add_child(game)
	game.set_physics_process(false)
	if not check(await wait_for(func():return not game.loading_active and not game.waiting_spawn and game.terrain.snapshot_restore_ok,90),"saved mining spot loads read-only"):await finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.session_menu.set_open(false)
	game.zombies.set_process(false);game.zombies.set_physics_process(false)
	for zombie:Node in game.zombies.residents:zombie.set_physics_process(false)
	game.player_hud.equip(0)
	game.terrain.edit_measured.connect(func(row:Dictionary):publications.append(row))
	game.world_attack.impact_resolved.connect(func(identity:int,accepted:bool):impacts.append({"identity":identity,"accepted":accepted,"clip_time":game.tool_view.human.animation_player.current_animation_position}))
	for frame in 180:
		await process_frame
		if frame%30==0:
			var sample:=probe();samples.append(sample);print("MINING_PROBE ",JSON.stringify(sample))
	await picture("before")
	if animated:
		root.grab_focus()
		check(await wait_for(func():return game.app_focused,3),"input test window has real focus")
		Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	for attempt in 3:
		var selected:Dictionary=game.world_attack.target()
		var previous_count:=publications.size()
		var accepted:=false
		if animated:
			var wear:int=game.player_hud.inventory.snapshot().slots[0].wear
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true
			game._unhandled_input(event)
			check(not game.world_attack.pending.is_empty() and publications.size()==previous_count,"input starts windup without early mining")
			await wait_for(func():return game.world_attack.pending.is_empty(),4)
			accepted=game.world_attack.last_hit
			check(impacts.size()==attempt+1 and impacts.back().accepted and game.player_hud.inventory.snapshot().slots[0].wear==wear+1,"one contact and wear point per animated strike")
			check(not impacts.is_empty() and is_equal_approx(impacts.back().clip_time,game.tool_view.attack_profile().contact),"mining resolves at the authored animation contact time")
		else:
			accepted=not selected.is_empty() and game.world_attack.apply_target(selected)
		print("MINING_APPLY ",attempt," accepted=",accepted," target=",selected)
		check(accepted and selected.get("kind")=="terrain","saved aim accepts terrain strike %d"%attempt)
		check(await wait_for(func():return not game.terrain.pending_edit,10),"strike %d completes"%attempt)
		for frame in 30:await process_frame
		check(publications.size()==previous_count+1 and publications.back().changed,"strike %d changes terrain instead of accepting a no-op"%attempt)
		var next:Dictionary=game.world_attack.target()
		check(next.get("kind")=="terrain" and next.position.distance_to(selected.position)>0.03,"strike %d moves visible matching collision"%attempt)
		samples.append(probe())
	await picture("after")
	FileAccess.open(evidence.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"player":game.player.position,"camera":game.camera.global_transform,"samples":samples,"publications":publications,"impacts":impacts,"failures":failures},"  "))
	await finish()

func finish()->void:
	if is_instance_valid(game):
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits()
		game.free();await process_frame;await process_frame
	print("MINING_SAVED_TARGET failures=",failures);quit(1 if failures else 0)
