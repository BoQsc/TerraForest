extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func run() -> void:
	ProjectSettings.set_setting("terraforest/graphics_settings_path", "")
	var game: Node3D = load("res://demo/world.tscn").instantiate()
	game.temporary_world = true
	game.background_fps = 60
	root.add_child(game)
	var deadline := Time.get_ticks_msec() + 60000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec() < deadline: await process_frame
	check(not game.loading_active and not game.needs_floor_spawn, "actual temporary world is playable")
	var menu: CanvasLayer = game.session_menu
	var blocks: Node3D = game.structures.blocks
	menu.set_open(true)
	menu.navigation.Graphics.pressed.emit()
	menu.refresh()
	check(menu.current_page == "Graphics" and menu.building_lod_toggle.get_parent() == menu.pages.Graphics, "LOD toggle belongs to ESC Graphics")
	check(menu.building_lod_toggle.button_pressed and blocks.is_geometry_lod_enabled(), "actual world and UI default on")
	menu.building_lod_toggle.set_pressed(false)
	check(not blocks.is_geometry_lod_enabled(), "UI disables native LOD immediately")
	menu.building_lod_toggle.set_pressed(true)
	check(blocks.is_geometry_lod_enabled(), "UI restores native LOD immediately")
	await game.terrain.shutdown_after_edits()
	game.queue_free()
	await process_frame
	await process_frame
	ProjectSettings.set_setting("terraforest/graphics_settings_path", null)
	print("BUILDING_LOD_MENU checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
