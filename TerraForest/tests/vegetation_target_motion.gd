extends SceneTree

var game:Node
var checks:=0
var failures:=0
var folder:="res://reports/vegetation_target_motion"
var results:Dictionary={}

func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->bool:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
	return condition
func frames(count:int=3)->void:
	for frame in count:await process_frame
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func capture(label:String)->void:
	await frames();await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(folder.path_join(label+".png"))==OK,"capture "+label)
func run()->void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--navigation-evidence="):folder=argument.trim_prefix("--navigation-evidence=")
	folder=ProjectSettings.globalize_path(folder);DirAccess.make_dir_recursive_absolute(folder)
	ProjectSettings.set_setting("terraforest/offscreen_session",true)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.background_fps=60;game.player_view.settings_path="";game.first_person_view.settings_path="";root.add_child(game)
	if not check(await until(func():return not game.loading_active and not game.needs_floor_spawn,65),"temporary streamed forest becomes playable"):await finish();return
	game.set_physics_process(false);game.set_process(false);game._clear_motion();game.app_focused=true;game.zombies.population_enabled=false;game.zombies.clear();game.session_menu.set_open(false)
	game.player_hud.inventory.grant_items(PackedInt64Array([204,20,205,20]),game.player_hud.inventory.snapshot().revision);game.player_hud.refresh();game.player_hud.equip_item(204)
	if not check(await until(func():return game.ground_cover.resident.size()>=9,20),"vegetation residency is ready"):await finish();return
	var inventory:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot();var authored:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	var original_ray:Callable=game.ground_interaction.scene_ray;var calls:Dictionary={"count":0}
	game.ground_interaction.scene_ray=func(from:Vector3,to:Vector3):calls.count+=1;return original_ray.call(from,to)
	var base:Vector3=game.player.global_position;var matched:=0;var supported:=0;var hidden:=0;var worst_error:=0.0;var timings:Array=[]
	for frame in 120:
		var location:=base+Vector3(frame*9.9/60.0,0,0)
		var floor_hit:Dictionary=game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(location+Vector3.UP*8,location-Vector3.UP*8,1))
		if floor_hit.is_empty():continue
		game.player.global_position=floor_hit.position;game.camera.global_position=floor_hit.position+Vector3.UP*1.68;game.camera.look_at(floor_hit.position+Vector3(0,0,-2))
		var start:Vector3=game.camera.global_position;var expected:Dictionary=original_ray.call(start,start-game.camera.global_basis.z*3.5)
		var began:=Time.get_ticks_usec();game.ground_preview.update(game,1.0/60);timings.append(Time.get_ticks_usec()-began)
		if not expected.is_empty():
			supported+=1
			if not game.ground_preview.visible:hidden+=1
			if game.ground_preview.result.has("pose"):
				var error:float=game.ground_preview.global_position.distance_to(expected.position+Vector3.UP*.02);worst_error=maxf(worst_error,error)
				if error<.035:matched+=1
		await process_frame
	results.motion={"supported":supported,"matched":matched,"hidden":hidden,"worst_error_m":worst_error,"ray_calls":calls.count}
	timings.sort();results.probe_cpu_us={"median":timings[timings.size()/2],"p95":timings[int(timings.size()*.95)],"max":timings.back()}
	check(supported>=110 and hidden==0,"running-speed motion keeps a preview on every available nearby terrain hit")
	check(matched>=supported-1 and worst_error<.035,"preview follows the current running frame instead of the old 20 Hz position")
	await capture("running_preview")
	game.player.global_position=base;game.camera.global_position=base+Vector3.UP*1.68
	var angle_hits:=0;var angle_matches:=0
	for frame in 60:
		var angle:=deg_to_rad(frame*1.5-45)
		game.camera.look_at(base+Vector3(sin(angle)*2,0,-cos(angle)*2))
		var eye:Vector3=game.camera.global_position
		var expected:Dictionary=original_ray.call(eye,eye-game.camera.global_basis.z*3.5)
		game.ground_preview.update(game,1.0/60)
		if not expected.is_empty():
			angle_hits+=1
			if game.ground_preview.visible and game.ground_preview.global_position.distance_to(expected.position+Vector3.UP*.02)<.035:angle_matches+=1
		await process_frame
	results.look_motion={"supported":angle_hits,"matched":angle_matches}
	check(angle_hits>=55 and angle_matches>=angle_hits-1,"looking across the ground refreshes the live target without waiting for the stationary timer")
	game.camera.look_at(base+Vector3(0,0,-2))
	var blocker:=StaticBody3D.new();blocker.collision_layer=2;blocker.collision_mask=0
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,2,.15);collider.shape=box;blocker.add_child(collider);root.add_child(blocker)
	blocker.global_transform=Transform3D(game.camera.global_basis,game.camera.global_position-game.camera.global_basis.z*.9);await frames()
	game.ground_preview.update(game,.1)
	check(game.ground_preview.visible and not game.ground_preview.result.ok and game.ground_preview.global_position.distance_to(game.camera.global_position)<1.1,"nearest solid object still blocks vegetation targeting instead of selecting terrain through it")
	blocker.free();await frames()
	var was_pending:bool=game.terrain.pending_edit;game.terrain.pending_edit=true;game.ground_preview.update(game,.1)
	check(game.ground_preview.visible and game.ground_preview.result.reason=="Ground cover updating","temporary world updates show a pending marker instead of hiding it")
	game.terrain.pending_edit=was_pending
	game.ground_preview.remaining=.05;game.player_hud.equip_item(205);game.ground_preview.update(game,.001)
	check(game.ground_preview.ghost.mesh==game.ground_cover.preview_meshes[2],"switching vegetation species refreshes its ghost immediately")
	var before:int=calls.count
	for frame in 120:game.ground_preview.update(game,1.0/60)
	results.stationary_ray_calls=calls.count-before
	check(calls.count-before<=42,"stationary preview retains bounded 20 Hz validation")
	game.player_hud.equip_item(204)
	var plane:float=game.player.global_position.y
	game.ground_interaction.scene_ray=func(from:Vector3,to:Vector3):
		var direction:=to-from
		if direction.y>=-.0001:return {}
		var fraction:float=(plane-from.y)/direction.y
		return {"position":from+direction*fraction,"normal":Vector3.UP} if fraction>=0 and fraction<=1 else {}
	var boundary_visible:=0
	for distance:float in [3.35,3.45,3.55,3.7,4.0]:
		var target:=Vector3(game.player.global_position.x,plane,game.player.global_position.z-2)
		game.camera.global_position=target+Vector3(0,.5,.8660254)*distance;game.camera.look_at(target)
		game.ground_preview.remaining=0;game.ground_preview.update(game,.1)
		if game.ground_preview.visible and game.ground_preview.result.has("pose"):boundary_visible+=1
		if distance>3.5:
			check(not game.ground_preview.result.ok and game.ground_preview.result.reason=="Out of reach","out-of-reach vegetation remains non-placeable at %.2f m"%distance)
	results.range_boundary_visible=boundary_visible
	check(boundary_visible==5,"ground preview remains visible across the placement-reach boundary")
	await capture("out_of_reach")
	var state:PackedByteArray=game.player_hud.inventory.capture_storage_snapshot();var edits:PackedByteArray=game.ground_cover.removed.capture_storage_snapshot()
	var origin:Vector3=game.camera.global_position
	var placed:Dictionary=game.ground_interaction.place(1,origin,origin-game.camera.global_basis.z*3.5,game.player_hud.inventory,true)
	check(not placed.ok and game.player_hud.inventory.capture_storage_snapshot()==state and game.ground_cover.removed.capture_storage_snapshot()==edits,"out-of-reach click revalidates without spending or placing vegetation")
	game.camera.look_at(game.camera.global_position+Vector3.UP,Vector3.FORWARD);game.ground_preview.remaining=0;game.ground_preview.update(game,.1)
	check(not game.ground_preview.visible,"looking away from terrain hides the preview rather than pinning a stale target")
	game.ground_interaction.scene_ray=original_ray;game.camera.global_position=base+Vector3.UP*1.68;game.camera.look_at(base+Vector3(0,0,-2));game.ground_preview.update(game,.1)
	game.player_hud.set_open(true);game.ground_preview.update(game,.1)
	check(not game.ground_preview.visible,"inventory immediately hides the vegetation preview")
	game.player_hud.set_open(false)
	check(game.player_hud.inventory.capture_storage_snapshot()==inventory and game.ground_cover.removed.capture_storage_snapshot()==authored,"all movement/preview checks preserve carried items and authored vegetation")
	game.ground_interaction.scene_ray=original_ray
	var candidate:Dictionary={};var candidate_from:=Vector3.ZERO;var candidate_to:=Vector3.ZERO
	for horizontal in [-2.0,-1.0,0.0,1.0,2.0]:
		for depth in [-2.0,-1.0,1.0,2.0]:
			var target:=base+Vector3(horizontal,0,depth)
			candidate_from=target+Vector3(.3,2,.3);candidate_to=candidate_from+Vector3(0,-3.5,0)
			candidate=game.ground_interaction.placement_probe(1,candidate_from,candidate_to,game.player_hud.inventory,true)
			if candidate.ok:break
		if candidate.get("ok",false):break
	if check(candidate.get("ok",false),"normal nearby empty ground remains valid for planting"):
		var carried_before:=0
		for row:Dictionary in game.player_hud.inventory.snapshot().slots:
			if row.item==204:carried_before+=row.count
		var planted:Dictionary=game.ground_interaction.place(1,candidate_from,candidate_to,game.player_hud.inventory,true)
		var carried_after:=0
		for row:Dictionary in game.player_hud.inventory.snapshot().slots:
			if row.item==204:carried_after+=row.count
		check(planted.ok and carried_after==carried_before-1,"fresh in-range placement still consumes exactly one carried vegetation item")
		if planted.ok:
			check(await until(func():return game.ground_cover.batches[1].get_ids().has(planted.id),10),"placed vegetation publishes under its authored identity after final support checks")
	await finish()
func finish()->void:
	if game!=null:game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await frames(2)
	results.checks=checks;results.failures=failures
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"  "))
	print("VEGETATION_TARGET_MOTION checks=",checks," failures=",failures);quit(1 if failures else 0)
