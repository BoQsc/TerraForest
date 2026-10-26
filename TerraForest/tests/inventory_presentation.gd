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
func drag(source: Control,target: Control) -> void:
	var start:=source.get_global_rect().get_center();var end:=target.get_global_rect().get_center()
	Input.warp_mouse(start)
	var motion:=InputEventMouseMotion.new();motion.position=start;motion.global_position=start;Input.parse_input_event(motion)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=start;click.global_position=start;Input.parse_input_event(click)
	for i in 2:await process_frame
	motion=InputEventMouseMotion.new();motion.position=start+Vector2(25,0);motion.global_position=motion.position;motion.relative=Vector2(25,0);motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion)
	for i in 2:await process_frame
	motion=InputEventMouseMotion.new();motion.position=end;motion.global_position=end;motion.relative=end-start;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;Input.parse_input_event(motion)
	for i in 2:await process_frame
	click=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=false;click.position=end;click.global_position=end;Input.parse_input_event(click)
	for i in 3:await process_frame
func _initialize() -> void:run.call_deferred()
func run() -> void:
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true;root.add_child(game)
	var deadline:=Time.get_ticks_msec()+45000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	check(not game.loading_active,"main world ready")
	var hud=game.player_hud
	check(hud.slots.size()==22 and not hud.slots.has(0) and not hud.slots.has(9) and hud.slots.has(10),"backpack excludes all ten belt slots")
	hud.equip(0)
	var icons=preload("res://addons/player_runtime/item_icons.gd")
	var complete:=true
	for id in hud.CATALOG.keys()+hud.MATERIALS.keys()+hud.RESOURCES.keys():complete=complete and icons.texture(id)!=null
	check(complete,"every carried item has a baked icon")
	check(icons.texture(1)==icons.texture(1) and icons.texture(1).atlas==icons.texture(104).atlas,"icons share cached regions and one atlas")
	check(hud.belt[0].item_texture!=null and hud.belt[9].item_texture==null,"occupied icon and empty slot presentation")
	hud.inventory.wear_tool(0,160,hud.inventory.snapshot().revision);hud.refresh()
	check(is_equal_approx(hud.belt[0].durability_ratio,0.2) and hud.belt[0].durability_color()==Color("ef6660"),"low durability red bar")
	check(hud.belt[0].tooltip_text.contains("Pickaxe") and hud.belt[0].tooltip_text.contains("40 / 200 (20%)"),"hover identifies tool and exact remaining durability")
	var sample=preload("res://addons/player_runtime/inventory_slot.gd").new();root.add_child(sample)
	sample.present({"item":1,"count":1,"durability":100,"max_durability":200},"Pickaxe")
	check(sample.durability_color()==Color("edc96a"),"medium durability amber bar")
	sample.present({"item":1,"count":1,"durability":200,"max_durability":200},"Pickaxe")
	check(sample.durability_color()==Color("75dba1"),"full durability green bar")
	sample.clear_presentation();check(sample.durability_ratio<0 and sample.item_texture==null and not sample.item_picture.visible,"developer presentation clears icon and durability")
	sample.free()
	check(hud.belt[9].get_theme_stylebox("normal").bg_color.a<hud.belt[1].get_theme_stylebox("normal").bg_color.a,"empty belt slots are translucent")
	check(hud.belt[0].get_theme_stylebox("normal").border_width_bottom==4 and hud.belt[1].get_theme_stylebox("normal").border_width_bottom==1,"only equipped slot has prominent active border")
	hud.equip(9)
	check(hud.belt[9].get_theme_stylebox("normal").border_width_bottom==4 and hud.active_slot==9,"empty slot remains selectable")
	hud.equip(0)
	DirAccess.make_dir_recursive_absolute("res://reports/inventory_presentation")
	for i in 4:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/inventory_presentation/toolbelt.png")
	hud.inventory.grant(201,3,hud.inventory.snapshot().revision);hud.set_open(true)
	check(hud.recipe_buttons.size()==hud.Crafting.RECIPES.size() and not hud.recipe_buttons[0].disabled and not hud.recipe_buttons[1].disabled and hud.recipe_buttons[2].disabled,"all catalog recipe cards reflect available ingredients")
	check(hud.recipe_buttons[0].text.contains("3 / 2"),"recipe shows owned and required amounts")
	hud.select_slot(10)
	check(hud.belt[0].get_theme_stylebox("normal").border_color!=hud.slots[10].get_theme_stylebox("normal").border_color,"equipped and selected slots have distinct highlights")
	for i in 4:await RenderingServer.frame_post_draw
	var screen:=Rect2(Vector2.ZERO,Vector2(1920,1080))
	var inventory_panel: Control=hud.modal.get_child(0)
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
	check(hud.modal.mouse_filter==Control.MOUSE_FILTER_IGNORE and hud.modal.get_child_count()==3,"no fullscreen dimmer or input-blocking overlay")
	await drag(hud.belt[0],hud.slots[20])
	check(hud.state.slots[20].item==1 and hud.state.slots[0].item==0 and game.equipped_tool==0,"real belt-to-inventory drag puts away equipped tool")
	check(hud.slots[20].item_texture!=null and is_equal_approx(hud.slots[20].durability_ratio,0.2) and hud.belt[0].item_texture==null,"drag transfers icon and durability without stale source presentation")
	await drag(hud.slots[20],hud.belt[0])
	check(hud.state.slots[0].item==1 and hud.state.slots[20].item==0 and game.equipped_tool==1,"real inventory-to-belt drag restores equipped tool")
	await drag(hud.belt[1],hud.slots[21])
	await drag(hud.slots[21],hud.belt[0])
	check(hud.state.slots[0].item==2 and hud.state.slots[21].item==1 and game.equipped_tool==2,"occupied belt drop swaps items through native transaction")
	var wood:=count_item(hud,102)
	var shift:=InputEventKey.new();shift.physical_keycode=KEY_SHIFT;shift.keycode=KEY_SHIFT;shift.pressed=true;Input.parse_input_event(shift);Input.flush_buffered_events()
	await drag(hud.belt[5],hud.slots[22])
	shift=InputEventKey.new();shift.physical_keycode=KEY_SHIFT;shift.keycode=KEY_SHIFT;Input.parse_input_event(shift);Input.flush_buffered_events()
	check(hud.state.slots[5].count==32 and hud.state.slots[22].count==32,"Shift-drag splits belt stack into inventory")
	await drag(hud.slots[22],hud.belt[5])
	check(hud.state.slots[5].count==64 and hud.state.slots[22].count==0 and count_item(hud,102)==wood,"inventory-to-belt merge preserves total materials")
	for i in 3:await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/inventory_presentation/inventory_belt_drag.png")
	hud.equip_inventory(21)
	check(hud.active_slot==1 and hud.state.slots[21].item==0 and hud.active_item==1,"equipping backpack item moves it into empty belt slot")
	hud.equip(0);hud.select_slot(0)
	hud.set_open(false)
	check(hud.belt[0].appearance==2,"closing inventory removes selection styling from equipped belt slot")
	check(not hud.modal.visible and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED,"closing inventory closes crafting and restores gameplay capture")
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"fullscreen 1920x1080")
	game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame;await process_frame
	print("INVENTORY_PRESENTATION checks=",checks," failures=",failures);quit(1 if failures else 0)
