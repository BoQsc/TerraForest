extends "res://tests/northern_tower_walk.gd"

const Plan = preload("res://addons/world_runtime/world_generation_plan.gd")
var output := "res://reports/approved_shop_world"
var measuring := false
var samples: Array[float] = []
var rows: Array[Dictionary] = []
var previous_frame_usec := 0

func _process(_delta: float) -> bool:
	var now:=Time.get_ticks_usec()
	if measuring and previous_frame_usec>0:samples.append((now-previous_frame_usec)/1000.0)
	previous_frame_usec=now
	return false

func run() -> void:
	var slot := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--world-slot="):slot=argument.trim_prefix("--world-slot=")
		if argument.begins_with("--shop-world-output="):output=argument.trim_prefix("--shop-world-output=")
	if not slot.begins_with("recipe_generated_") or not slot.is_valid_identifier():quit(2);return
	DirAccess.make_dir_recursive_absolute(output)
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;game.max_fps=60;game.background_fps=60;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,90),"fresh process loads the generated shop world"):await done();return
	var options: Dictionary=game.world_recipe.store.decode(game.world_recipe.store.capture_snapshot())
	if not check(game.terrain.backend.readonly_snapshot and not options.is_empty(),"existing generated snapshot loads read-only with its durable recipe"):await done();return
	if not check(game.ground_enabled and game.construction_inventory.gameplay and game.world_vehicle.fleet_enabled and "--actors" in OS.get_cmdline_user_args(),"normal gameplay vegetation, actors and vehicle systems enabled"):await done();return
	var worker:=Thread.new()
	worker.start(Plan.build.bind(game.terrain.backend.world_seed,game.terrain.backend.world_generator,true,true,"user://approved_shop_plan_"+str(Time.get_ticks_usec()),options))
	while worker.is_alive():await process_frame
	var planned: Dictionary=worker.wait_to_finish()
	if not planned.get("ok",false):print("SHOP_PLAN_DIAGNOSTIC ",planned)
	if not check(planned.get("ok",false),"reconstruct deterministic approved-shop placement plan"):await done();return
	var selected: Dictionary={}
	for site: Dictionary in planned.sites:
		if site.recipe_kind!="market":continue
		for lot: Dictionary in site.lots:
			var revision: String=lot.asset.get_meta("approved_revision","")
			if revision in ["B1 R1","B2 R2"] and not selected.has(revision):selected[revision]=lot
	check(selected.size()==2,"both approved shop variants are present in actual market plans")
	for revision: String in selected:
		var lot: Dictionary=selected[revision]
		var world_asset: Resource=ClassDB.instantiate("NativeBlockPrefab")
		var composed: bool=world_asset.compose([lot.asset],PackedInt32Array([0,lot.origin.x,lot.origin.y,lot.origin.z,lot.rotation]))
		var exact:=composed
		var records: PackedInt32Array=world_asset.get_records()
		for offset in range(0,records.size(),4):
			exact=exact and game.structures.blocks.get_cell(Vector3i(records[offset],records[offset+1],records[offset+2]))==records[offset+3]
		check(exact,"published and freshly loaded "+revision+" matches every approved block")
		if not await visit_shop(lot,revision):break
	await done()

func visit_shop(lot: Dictionary, revision: String) -> bool:
	var start: Vector3=lot.entrance.segment.finish
	game.set_physics_process(true);game.session_menu.set_open(false)
	game.teleport(start+Vector3.UP)
	if not check(await wait_for(func():return not game.loading_active,60),"street residency ready "+revision):return false
	game.set_physics_process(false);game._clear_motion();game.app_focused=true
	var expected:=Vector3(0,1,8.5)
	for turn in lot.rotation:expected=Vector3(1-expected.z,expected.y,expected.x)
	expected+=Vector3(lot.origin)
	var door_id:=0
	var pose:=Transform3D.IDENTITY
	for identity: int in game.doors.collection.get_ids():
		var packed: PackedFloat32Array=game.doors.collection.get_instance(identity)
		if packed.size()!=12:continue
		var origin:=Vector3(packed[3],packed[7],packed[11])
		if origin.distance_to(expected)>.1:continue
		door_id=identity
		pose=Transform3D(Basis(Vector3(packed[0],packed[4],packed[8]),Vector3(packed[1],packed[5],packed[9]),Vector3(packed[2],packed[6],packed[10])).orthonormalized(),origin)
		break
	if not check(door_id>0,"saved shop entrance found after residency "+revision):return false
	if not check(await wait_for(func():return not game._terrain_pick(start+Vector3.UP*6,start-Vector3.UP*8).is_empty(),15),"generated street surface exists "+revision):return false
	start.y=game._terrain_pick(start+Vector3.UP*6,start-Vector3.UP*8).position.y+.05
	aim(start,pose*Vector3(.5,1,0))
	if not check(await wait_for(func():return game.structures.is_collision_region_ready(lot.asset.placement_bounds(lot.origin,lot.rotation).grow(3)),30),"shop collision ready "+revision):return false
	for frame in 60:await process_frame
	samples.clear();measuring=true
	if not check(await go(pose,Vector3(.5,0,.8)),"walk from generated street to shop door "+revision):measuring=false;return false
	game.camera.look_at(pose*Vector3(.5,1,0));game.app_focused=true;use()
	if not check(game.doors.state.is_open(door_id),"E opens generated shop door "+revision):measuring=false;return false
	for frame in 15:await physics_frame
	for target: Vector3 in [Vector3(.5,0,-3),Vector3(.5,0,-8),Vector3(.5,0,-13),Vector3(.5,0,-8),Vector3(.5,0,-3),Vector3(.5,0,.8)]:
		if not check(await go(pose,target),"shop interior route "+revision+" "+str(target)):measuring=false;return false
	var street: Vector3=pose.affine_inverse()*start
	street.y-=.05
	if not check(await go(pose,street),"walk back to generated street "+revision):measuring=false;return false
	measuring=false;samples.sort()
	var metrics: Dictionary={"revision":revision,"frames":samples.size(),"p95_ms":samples[floori((samples.size()-1)*.95)] if not samples.is_empty() else 0,"worst_ms":samples[-1] if not samples.is_empty() else 0,"ground_regions":game.ground_cover.resident.size(),"survey":lot.survey,"quality":lot.get("quality",{}),"origin":lot.origin,"rotation":lot.rotation}
	rows.append(metrics);print("SHOP_WORLD_METRICS ",metrics)
	game.camera.global_position=pose*Vector3(23,15,22)
	game.camera.look_at(Vector3(lot.origin)+Vector3(.5,5,.5))
	for frame in 12:await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(revision.left(2)+".png"))==OK,"capture generated shop "+revision)
	return true

func done() -> void:
	measuring=false
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"routes":rows,"trace":trace,"cpu":OS.get_processor_name(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Fresh generated-save load, exact approved cells and physical street/shop routes with normal resident systems; wall-clock frames at capped 1920x1080 exclude loading and screenshots, not an endurance or headroom guarantee"},"  "))
	print("APPROVED_SHOP_WORLD failures=",failures)
	if is_instance_valid(game):
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	await process_frame
	quit(1 if failures else 0)
