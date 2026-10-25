extends SceneTree
var game: Node
var checks := 0
var failures := 0
var folder := "res://reports/zombie_population_world"
var disk_mode := ""
var saved_ok := false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func until(predicate: Callable, seconds: float) -> bool:
	var end := Time.get_ticks_msec() + int(seconds * 1000)
	while not predicate.call() and Time.get_ticks_msec() < end:
		await physics_frame
		game.app_focused = true
	return predicate.call()
func _initialize() -> void:run.call_deferred()
func run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--zombie-evidence-dir="):folder = argument.trim_prefix("--zombie-evidence-dir=")
		if argument.begins_with("--population-disk="):disk_mode = argument.trim_prefix("--population-disk=")
	DirAccess.make_dir_recursive_absolute(folder)
	if not disk_mode.is_empty():
		var slot := ""
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--world-slot="):slot = argument.trim_prefix("--world-slot=")
		if not slot.begins_with("zombie_population_check_"):push_error("Persistent fixture requires its own disposable slot");quit(1);return
	game = load("res://demo/world.tscn").instantiate();game.temporary_world = disk_mode.is_empty();game.background_fps = 60;root.add_child(game)
	check(await until(func():return not game.loading_active, 65), "actual world becomes playable with inhabitants loaded")
	if game.loading_active:
		print("POPULATION_FAILURE ", game.zombies.population.status());await finish();return
	game._clear_motion();game.needs_floor_spawn = false;game.fly = false;game.app_focused = true
	if game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.set_open(false);Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if "--no-zombies" in OS.get_cmdline_user_args():
		check(not game.zombies.enabled and game.zombies.residents.is_empty(), "no-zombies mode skips population admission")
		check(game.zombies.population.store.statistics().slots == 0, "disabled mode does not allocate or initialize world population")
		await finish();return
	var first_count: int = game.zombies.residents.size()
	check(first_count > 0 and first_count <= 6, "zombies already exist on the first playable frame")
	check(game.zombies.population.initial_complete, "loading barrier waits for initial population admission")
	if disk_mode == "read":
		var expected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("expected.json")))
		var identity_found := false
		for zombie in game.zombies.residents:
			if zombie.get_meta("world_zombie_id", 0) == int(expected.survivor):
				identity_found = true
				check(zombie.anatomy.capture_vitals().hex_encode() == expected.vitals, "fresh world process restores exact body and limb health")
		check(identity_found, "fresh world process activates same saved survivor")
		check(game.zombies.population.store.resident(int(expected.dead)).state == 2, "fresh world process never resurrects saved death")
		check(game.corpse_loot.store.corpse(int(expected.corpse)).size() > 0, "fresh world process restores corpse loot alongside death record")
		await finish();return
	var safe := true
	var identities := PackedInt64Array()
	for zombie in game.zombies.residents:
		identities.append(zombie.get_meta("world_zombie_id", 0))
		var offset: Vector3 = zombie.global_position - game.player.global_position;offset.y = 0
		safe = safe and offset.length() >= 39.5 and zombie.target == null
	check(safe and not identities.has(0), "initial residents have stable identities, safety distance and independent awareness")
	if first_count >= 2:
		var victim: Node3D = game.zombies.residents[0]
		var survivor: Node3D = game.zombies.residents[1]
		var dead_id: int = victim.get_meta("world_zombie_id")
		var survivor_id: int = survivor.get_meta("world_zombie_id")
		survivor.receive_hit("upper_arm_l", 12.0, survivor.global_position + Vector3.UP, Vector3.ZERO, false, "melee")
		survivor.sever_limb("shin_l")
		var wounded: PackedByteArray = survivor.anatomy.capture_vitals()
		victim.receive_hit("torso", 1000.0, victim.global_position + Vector3.UP, Vector3.ZERO, false, "melee")
		await until(func():return victim not in game.zombies.residents, 3)
		check(game.zombies.population.store.resident(dead_id).state == 2, "death immediately retires its persistent population identity")
		var after_death: int = game.zombies.residents.size()
		for tick in 60 * 3:await physics_frame;game.app_focused = true
		check(game.zombies.residents.size() == after_death, "waiting after a death does not refill the encounter pool")
		var population_bytes: PackedByteArray = game.zombies.population.capture()
		var corpse_bytes: PackedByteArray = game.corpse_loot.capture()
		if disk_mode == "write":
			game.session_menu.set_open(true)
			game.terrain.save_completed.connect(func(ok: bool):saved_ok = ok)
			game.terrain.save_world()
			check(await until(func():return saved_ok, 40), "real compound world save publishes population, injuries and corpse")
			FileAccess.open(folder.path_join("expected.json"), FileAccess.WRITE).store_string(JSON.stringify({"dead":dead_id, "survivor":survivor_id, "vitals":wounded.hex_encode(), "corpse":victim.get_meta("corpse_identity", 0)}))
			await finish();return
		game.set_physics_process(false);game.set_process(false)
		check(game.zombies.population.restore(population_bytes) and game.corpse_loot.restore(corpse_bytes), "scene reload restores population and existing corpse storage")
		var deadline := Time.get_ticks_msec() + 20000
		while not game.zombies.population.advance(game.player.global_position, true) and Time.get_ticks_msec() < deadline:await physics_frame
		var restored: Node3D
		var duplicate := false
		var restored_ids := PackedInt64Array()
		for zombie in game.zombies.residents:
			var identity: int = zombie.get_meta("world_zombie_id")
			duplicate = duplicate or restored_ids.has(identity) or identity == dead_id
			restored_ids.append(identity)
			if identity == survivor_id:restored = zombie
		check(not duplicate and not restored_ids.is_empty(), "reload has no duplicate or resurrected residents")
		check(restored != null and restored.anatomy.capture_vitals() == wounded, "real zombie keeps body and limb injuries through unload/reload")
		check(restored != null and restored.missing.shin_l and restored.missing.foot_l and restored.get_behavior_snapshot().crawling, "restored missing legs still produce a crawling zombie")
		if restored != null:
			restored.skeleton.force_update_all_bone_transforms()
			var head: Vector3 = restored.skeleton.global_transform * restored.skeleton.get_bone_global_pose(restored.skeleton.find_bone("Head")).origin
			check(head.y - restored.global_position.y < 1.1, "restored crawler mesh is already prone before any simulation tick")
		if restored != null and DisplayServer.get_name() != "headless":
			var camera := Camera3D.new();game.add_child(camera);camera.global_position = restored.global_position + Vector3(3, 2.5, 4);camera.look_at(restored.global_position + Vector3.UP);camera.current = true;game.tool_view.hide()
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(folder.path_join("world_resident.png"))
		game.set_physics_process(true);game.set_process(true)
		var origin: Vector3 = game.player.global_position
		game.teleport(origin + Vector3(180, 0, 0))
		check(await until(func():return not game.loading_active, 50), "travel loads world residents at the destination before returning input")
		check(game.zombies.residents.size() > 0 and game.zombies.residents.all(func(zombie):return zombie.global_position.distance_to(game.player.global_position) < 96), "travel retires old scene bodies and admits destination identities")
		game.teleport(origin)
		check(await until(func():return not game.loading_active, 50), "return travel completes the inhabitants loading stage")
		check(game.zombies.population.store.resident(dead_id).state == 2, "travel never resurrects the killed world resident")
	await finish()
func finish() -> void:
	FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures, "population":game.zombies.population.status()}, "  "))
	game.shutdown_requested = true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("ZOMBIE_POPULATION_WORLD checks=", checks, " failures=", failures);quit(1 if failures else 0)
