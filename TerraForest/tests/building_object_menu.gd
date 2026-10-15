# SPDX-License-Identifier: 0BSD
extends "res://tests/combined_resource_route.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	if not check(await wait_for(func():return not game.loading_active and game.session_menu.ready_to_dock,45),"normal world and menu ready"):await finish();return
	if not game.session_menu.developer:game.session_menu.toggle_developer()
	game.session_menu.show_page("Objects")
	for i in 3:await process_frame
	var menu=game.session_menu
	check(Rect2(Vector2.ZERO,Vector2(1920,1080)).encloses(menu.panel.get_global_rect()),"object workspace fits 1080p")
	var reachable:=true
	for index in game.model_tool.choices.size():
		var button: Button=game.model_tool.choices[index]
		menu.scroll.ensure_control_visible(button)
		await process_frame
		reachable=reachable and menu.scroll.get_global_rect().encloses(button.get_global_rect())
		button.pressed.emit()
		reachable=reachable and game.model_tool.selected==index
	check(reachable,"all production object choices scroll into view and select their own model")
	var last: Button=game.model_tool.choices.back()
	check(last.icon!=null,"last guardrail choice has baked icon")
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports/building_object_menu")
	root.get_texture().get_image().save_png("res://reports/building_object_menu/objects.png")
	game.session_menu.set_open(false)
	check(game.model_tool.selected==game.model_tool.choices.size()-1 and game.model_tool.active,"return to world preserves selected placement")
	await finish()
