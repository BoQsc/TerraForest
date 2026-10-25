extends CanvasLayer
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
var game:Node
var menu:CanvasLayer
var opened:=false
var choice:=-1
var view:Control
class Wheel extends Control:
	var radial:CanvasLayer
	func _draw()->void:radial.paint(self)
func _ready()->void:
	layer=46;view=Wheel.new();view.radial=self;view.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(view);view.hide()
func available()->bool:
	return game.app_focused and not game.loading_active and not game.shutdown_requested and game.terrain.world_ready and not menu.visible_ui() and not game.player_hud.inventory_open and not game.world_vehicle.driving
func cancel()->void:
	var restore:=opened;opened=false;choice=-1;menu.tilde_down=-1;menu.tilde_chord=false;view.hide()
	if restore and available():Mouse.set_mode(game,Input.MOUSE_MODE_CAPTURED)
func consume(event:InputEvent)->bool:
	if opened and event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:cancel();return true
	if opened and event is InputEventKey and event.pressed and event.physical_keycode in [KEY_1,KEY_F]:choice=0;activate();return true
	if opened and event is InputEventMouseButton:
		if event.pressed:
			if event.button_index==MOUSE_BUTTON_LEFT:activate()
			elif event.button_index==MOUSE_BUTTON_RIGHT:cancel()
		return true
	if not event is InputEventKey or event.echo or event.physical_keycode!=KEY_QUOTELEFT:return opened
	if event.pressed:
		if not available():return false
		menu.tilde_down=Time.get_ticks_msec();menu.tilde_chord=false;game._cancel_edit_input();view.show()
	elif menu.tilde_down>=0:
		if opened:activate()
		else:
			var tap:bool=not menu.tilde_chord;cancel()
			if tap:menu.toggle_developer()
	return true
func _process(_delta:float)->void:
	if menu.tilde_down<0:return
	if not available():cancel();return
	if not opened and not menu.tilde_chord and Time.get_ticks_msec()-menu.tilde_down>=350:
		opened=true;game._clear_motion()
		if Mouse.set_mode(game,Input.MOUSE_MODE_VISIBLE):Input.warp_mouse(get_viewport().get_visible_rect().size*.5)
	if opened:
		var offset:=view.get_global_mouse_position()-get_viewport().get_visible_rect().size*.5
		choice=0 if offset.length()>=48 and offset.length()<=220 else -1
	view.queue_redraw()
func activate()->void:
	var selected:=choice;cancel()
	if selected==0 and available():menu.toggle_flight()
func paint(canvas:Control)->void:
	var center:=get_viewport().get_visible_rect().size*.5
	if not opened:
		canvas.draw_arc(center,30,-PI*.5,-PI*.5+TAU*clampf(float(Time.get_ticks_msec()-menu.tilde_down)/350,0,1),32,Color("8ee0bc"),4,true);return
	canvas.draw_circle(center,190,Color(.015,.03,.035,.94))
	canvas.draw_arc(center,178,0,TAU,64,Color("8ce2bb") if choice==0 else Color("45665a"),8,true)
	var font:Font=ThemeDB.fallback_font
	for row:Array in [["1 · Return to walking" if game.fly else "1 · Enable fly",-12],["Move mouse outward to select",35],["Release ` to choose",230],["Esc / right mouse: cancel",256]]:
		var size:=22 if int(row[1])<0 else 16
		var text:String=row[0];var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
		canvas.draw_string(font,center+Vector2(-width*.5,row[1]),text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,Color("daf4e7"))
