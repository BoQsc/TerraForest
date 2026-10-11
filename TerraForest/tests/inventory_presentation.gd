# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func count_item(hud: Node,item: int) -> int:
	var total:=0
	for row in hud.inventory.snapshot().slots:
		if row.item==item:total+=int(row.count)
	return total
func click(button: Button) -> void:
	await RenderingServer.frame_post_draw
	var point:=button.get_global_rect().get_center();Input.warp_mouse(point)
	await RenderingServer.frame_post_draw
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;Input.parse_input_event(motion)
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.button_mask=MOUSE_BUTTON_MASK_LEFT;e.pressed=true;Input.parse_input_event(e);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
	e=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;Input.parse_input_event(e);Input.flush_buffered_events()
	await RenderingServer.frame_post_draw
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	var hud=game.player_hud
	hud.equip(0)
	check(hud.belt[9].get_theme_stylebox("normal").bg_color.a<hud.belt[1].get_theme_stylebox("normal").bg_color.a,"empty belt slots are translucent")
	check(hud.belt[0].get_theme_stylebox("normal").border_width_bottom==4 and hud.belt[1].get_theme_stylebox("normal").border_width_bottom==1,"only equipped slot has prominent active border")
	hud.equip(9)
	check(hud.belt[9].get_theme_stylebox("normal").border_width_bottom==4 and hud.active_slot==9,"empty slot remains selectable")
	hud.equip(0)
	DirAccess.make_dir_recursive_absolute("res://reports/inventory_presentation")
	for i in 4:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/inventory_presentation/toolbelt.png")
	hud.inventory.grant(201,3,hud.inventory.snapshot().revision);hud.set_open(true)
	check(hud.recipe_buttons.size()==4 and not hud.recipe_buttons[0].disabled and not hud.recipe_buttons[1].disabled and hud.recipe_buttons[2].disabled,"recipe cards reflect available ingredients")
	check(hud.recipe_buttons[0].text.contains("3 / 2"),"recipe shows owned and required amounts")
	hud.select_slot(1)
	check(hud.slots[0].get_theme_stylebox("normal").border_color!=hud.slots[1].get_theme_stylebox("normal").border_color,"equipped and selected slots have distinct highlights")
	for i in 4:await RenderingServer.frame_post_draw
	var screen:=Rect2(Vector2.ZERO,Vector2(1920,1080))
	var inventory_panel: Control=hud.modal.get_child(1)
	check(hud.crafting_panel.get_global_rect().end.x<inventory_panel.get_global_rect().position.x and screen.encloses(hud.crafting_panel.get_global_rect()) and screen.encloses(inventory_panel.get_global_rect()),"crafting is separate left panel and both fit 1080p")
	root.get_texture().get_image().save_png("res://reports/inventory_presentation/inventory.png")
	var bricks:=count_item(hud,101)
	await click(hud.recipe_buttons[0])
	check(count_item(hud,101)==bricks+1 and count_item(hud,201)==1,"one real mouse click crafts exactly one batch")
	check(hud.recipe_buttons[0].disabled and hud.recipe_buttons[1].disabled,"craft updates all recipe availability immediately")
	var before: PackedByteArray=hud.capture_snapshot()
	await click(hud.recipe_buttons[0])
	check(hud.capture_snapshot()==before,"disabled recipe click cannot consume materials")
	hud.inventory.grant(201,2,hud.inventory.snapshot().revision)
	hud.craft_recipe(0)
	check(count_item(hud,201)==3 and count_item(hud,101)==bricks+1 and hud.crafting_message.text.contains("refreshed"),"stale revision refuses craft and refreshes without losing inputs")
	await click(hud.recipe_buttons[1])
	check(count_item(hud,201)==0 and hud.crafting_message.text.begins_with("Crafted"),"another recipe crafts directly without selecting a dropdown")
	hud.set_open(false)
	check(not hud.modal.visible and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing inventory closes crafting and restores gameplay capture")
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"fullscreen 1920x1080")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("INVENTORY_PRESENTATION checks=",checks," failures=",failures);quit(1 if failures else 0)
