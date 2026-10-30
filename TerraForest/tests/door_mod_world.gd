# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
const SECOND := "example/doors/narrow_right/v1"
var directory := "user://mods/door_world_%d" % OS.get_process_id()

func run() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var manifest := directory.path_join("example.objects.json")
	FileAccess.open(manifest,FileAccess.WRITE).store_string(FileAccess.get_file_as_string("res://mods/example_doors/example.objects.json"))
	var config := ConfigFile.new()
	config.set_value("objects","manifests",PackedStringArray([manifest]))
	config.save(directory.path_join("enabled.cfg"))
	game = load("res://demo/world.tscn").instantiate()
	game.temporary_world = true
	game.object_mod_config = directory.path_join("enabled.cfg")
	game.background_fps = 60
	root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active,60),"normal world loads both door definitions"):
		await finish_mod();return
	game.set_physics_process(false)
	game._clear_motion()
	game.session_menu.set_open(false)
	if game.session_menu.developer: game.session_menu.toggle_developer()
	game.zombies.clear()
	game.zombies.population_enabled = false
	var entry: Dictionary = game.doors.types[SECOND]
	var batch: Node3D = entry.collection
	var origin: Vector3 = game.player.position + Vector3(0,8,-3)
	var pose := Transform3D(Basis.IDENTITY,origin)
	var catalog_entry: Dictionary = {}
	for candidate: Dictionary in game.model_tool.catalog:
		if candidate.get("id") == SECOND: catalog_entry = candidate
	check(not catalog_entry.is_empty(),"mod door appears in normal construction catalog")
	game.player_hud.inventory.grant(102,20,game.player_hud.inventory.snapshot().revision)
	var wood_before := amount(102)
	var identity: int = game.construction_inventory.place_model(game.model_tool.history,batch,game.player_hud.inventory,game.model_tool.records(pose,batch),AABB(),catalog_entry.costs)
	check(identity > 0 and amount(102) == wood_before-5,"normal native placement charges the mod's five wood recipe")
	batch.set_collision_focus(origin)
	aim(origin+Vector3(.4,0,2),origin+Vector3(.4,1,0))
	for frame in 15: await physics_frame;await process_frame
	check(game.player_hud.interaction_hint.text == "E · Open narrow right-hinged door","HUD discovers mod name and door capability")
	var damage_target: Dictionary = game.world_attack.target()
	check(damage_target.get("asset") == SECOND and damage_target.get("health") == 75,"actual attack targeting uses mod durability")
	use()
	check(entry.state.is_open(identity) and game.terrain.changed_since_save,"normal E input opens mod door and marks world dirty")
	var sections: Dictionary = game.persistence._capture().sections
	var section := "door_"+SECOND.sha256_text().left(40)
	check(sections.has(section) and entry.state.validate_snapshot(sections[section]),"actual compound capture includes independent mod hinges")
	aim(origin+Vector3(2,0,-.4),origin+Vector3(.8,1,-.4))
	for frame in 15: await physics_frame;await process_frame
	check(game.player_hud.interaction_hint.text == "E · Close narrow right-hinged door","HUD tracks right-hinged mod state")
	use()
	check(not entry.state.is_open(identity) and batch.get_instance(identity) == game.model_tool.records(pose,batch),"normal E input closes mod door without pose drift")
	check(not game.doors.breakable_bodies().has(batch.collision_body_for(identity)),"mod's explicit zombie restriction reaches navigation")
	if DisplayServer.get_name() != "headless":
		var original: Node3D = game.doors.collection
		var original_pose := Transform3D(Basis.IDENTITY,origin+Vector3(-1.6,0,0))
		original.insert_instance(game.model_tool.records(original_pose,original),AABB())
		original.set_collision_focus(origin)
		aim(origin+Vector3(.4,0,2),origin+Vector3(.4,1,0))
		for frame in 15: await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports/door_content")
		root.get_texture().get_image().save_png("res://reports/door_content/world.png")
	check(entry.state.toggle(batch,identity,AABB()).ok,"open mod door before salvage")
	wood_before = amount(102)
	check(game._remove_inventory_model(game.model_tool.history,batch,identity) and amount(102) == wood_before+2,"normal dismantling recovers mod's two wood salvage")
	check(not entry.state.is_open(identity) and batch.get_instance(identity).is_empty(),"dismantling clears the correct native hinge store")
	await finish_mod()

func finish_mod() -> void:
	game.shutdown_requested = true
	check(await game.terrain.shutdown_after_edits(),"temporary world shutdown completes")
	game.free()
	await process_frame
	for name in ["example.objects.json","enabled.cfg"]: DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)
	print("DOOR_MOD_WORLD failures=",failures)
	quit(1 if failures else 0)
