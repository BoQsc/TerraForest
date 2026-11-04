# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()
func check(condition:bool,message:String)->bool:
	checks+=1
	if not condition:failures+=1
	print("PASS " if condition else "FAIL ",message)
	return condition
func until(predicate:Callable,seconds:int)->bool:
	var deadline:=Time.get_ticks_msec()+seconds*1000
	while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
	return predicate.call()
func click(control:Control)->void:
	var point:=control.get_global_rect().get_center()
	for pressed:bool in [true,false]:
		var event:=InputEventMouseButton.new()
		event.button_index=MOUSE_BUTTON_LEFT;event.position=point;event.global_position=point;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()
	await process_frame
func type_key(code:int,unicode_value:int)->void:
	for pressed:bool in [true,false]:
		var event:=InputEventKey.new()
		event.physical_keycode=code;event.keycode=code;event.unicode=unicode_value;event.pressed=pressed
		Input.parse_input_event(event);Input.flush_buffered_events()
func run()->void:
	game=load("res://demo/world.tscn").instantiate()
	game.temporary_world=true;game.background_fps=60;game.zombies.population_enabled=false
	root.add_child(game)
	if not check(await until(func():return not game.loading_active and game.session_menu.ready_to_dock,60),"world ready"):
		finish();return
	game.set_physics_process(false);game._clear_motion();game.app_focused=true;game.needs_floor_spawn=false
	var menu=game.session_menu
	for title in ["Dev Bag","Dev Shapes"]:
		menu.show_page(title);await process_frame
		var field:LineEdit=menu.dev_bag.search if title=="Dev Bag" else menu.dev_shapes.search
		check(field.is_visible_in_tree(),title+" search is visible")
		await click(field)
		check(root.gui_get_focus_owner()==field,title+" search owns focus after click")
		type_key(KEY_M,109);await process_frame
		check(field.text=="m" and not game.world_map.opened,title+" M is text, not the map")
		field.text=""
	finish()
func finish()->void:
	if is_instance_valid(game):
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free()
	await process_frame;await process_frame
	print("TEXT_INPUT_FOCUS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
