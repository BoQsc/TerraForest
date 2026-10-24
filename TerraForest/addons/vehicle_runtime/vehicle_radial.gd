# SPDX-License-Identifier: 0BSD
extends CanvasLayer
# E tap retains normal interaction. Holding selects a live, reachable vehicle.
var game:Node
var held_since:=-1
var identity:=0
var opened:=false
var choice:=-1
var view:Control
class Wheel extends Control:
	var radial:CanvasLayer
	func _draw()->void:radial.paint(self)
func _ready()->void:
	layer=45;view=Wheel.new();view.radial=self;view.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(view);view.hide()
func valid_context()->bool:
	return game.app_focused and not game.loading_active and not game.shutdown_requested and not game.session_menu.visible_ui() and not game.player_hud.inventory_open and not game.world_vehicle.driving and not game.fly and game.terrain.world_ready
func cancel()->void:
	var restore:=opened;opened=false;held_since=-1;identity=0;choice=-1;view.hide()
	if restore and valid_context():Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func consume(event:InputEvent)->bool:
	if opened:
		if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:cancel();return true
		if event is InputEventMouseButton and event.pressed:
			if event.button_index==MOUSE_BUTTON_LEFT:activate(choice)
			elif event.button_index==MOUSE_BUTTON_RIGHT:cancel()
			return true
		if event is InputEventKey and event.pressed and event.physical_keycode in [KEY_1,KEY_2]:activate(0 if event.physical_keycode==KEY_1 else 1);return true
	if not event is InputEventKey or event.echo or event.physical_keycode!=KEY_E:return opened
	if not event.pressed:
		if held_since<0:return false
		if opened:activate(choice)
		else:
			cancel()
			if valid_context():game._interact_on_foot()
		return true
	if not valid_context() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return false
	# Doors, storage and loose objects keep their direct tap interaction.
	if not game.world_interaction.describe(game,game.world_interaction.hit(game)).is_empty():return false
	identity=game.world_vehicle.candidate(game)
	if identity==0:return false
	held_since=Time.get_ticks_msec();game._cancel_edit_input();view.show();return true
func _process(_delta:float)->void:
	if held_since<0:return
	if not valid_context():cancel();return
	if not opened and Time.get_ticks_msec()-held_since>=350:
		opened=true;game._clear_motion();Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
		Input.warp_mouse(get_viewport().get_visible_rect().size*.5)
	if opened:
		var offset:Vector2=view.get_global_mouse_position()-get_viewport().get_visible_rect().size*.5
		choice=-1 if offset.length()<48 or offset.length()>220 else (0 if offset.y<0 else 1)
	view.queue_redraw()
func activate(selected:int)->void:
	var id:=identity;cancel()
	if selected<0 or not valid_context():return
	if selected==0:
		if game.world_vehicle.enter(game,id):game._clear_motion();game._show_lake_notice("Driving · E exit · Space brake")
		else:game._show_lake_notice("Vehicle entry unavailable; move closer to the same vehicle")
	else:game._show_lake_notice(game.world_vehicle.pickup(game,id))
func paint(canvas:Control)->void:
	var center:Vector2=get_viewport().get_visible_rect().size*.5
	if not opened:
		canvas.draw_arc(center,30,-PI*.5,-PI*.5+TAU*clampf(float(Time.get_ticks_msec()-held_since)/350,0,1),32,Color("8ee0bc"),4,true);return
	canvas.draw_circle(center,190,Color(.015,.03,.035,.94))
	canvas.draw_line(center+Vector2(-165,0),center+Vector2(165,0),Color("45665a"),2,true)
	for index in 2:
		canvas.draw_arc(center,178,PI+index*PI,TAU+index*PI,48,Color("8ce2bb") if choice==index else Color("45665a"),8,true)
	var font:Font=ThemeDB.fallback_font
	for row:Array in [["1 · Enter vehicle",-88],["2 · Pick up vehicle",100],["Release E to choose",230],["Esc / right mouse: cancel",256]]:
		var size:=20 if abs(int(row[1]))<200 else 16
		var text:String=row[0];var width:float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		canvas.draw_string(font,center+Vector2(-width*.5,row[1]),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("daf4e7"))
