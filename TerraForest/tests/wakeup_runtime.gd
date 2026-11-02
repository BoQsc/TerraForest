# SPDX-License-Identifier: 0BSD
extends SceneTree
class Menu extends RefCounted:
	func visible_ui()->bool:return false
class Game extends Node3D:
	var shutdown_requested:=false
	var loading_active:=false
	var waiting_spawn:=false
	var needs_floor_spawn:=false
	var app_focused:=true
	var camera:=Camera3D.new()
	var player_hud:Dictionary={"inventory_open":false,"active_item":1}
	var terrain:Dictionary={"changed_since_save":false,"render_view":Vector3.INF,"render_projection_scale":1.,"schedule_timer":0.}
	var world_vehicle:Dictionary={"driving":false}
	var session_menu:=Menu.new()
	var tool_view:Node3D
	func _clear_motion()->void:pass
class View extends Node:
	func set_overview(_value:bool)->void:pass
	func set_enabled(_value:bool,_persist:bool)->void:pass
	func refresh_processing()->void:pass
	func _bind_view(_camera:Camera3D)->void:pass
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var game:=Game.new();root.add_child(game);game.add_child(game.camera)
	game.tool_view=preload("res://addons/player_runtime/tool_view.gd").new();game.camera.add_child(game.tool_view)
	var view:=View.new();game.add_child(view)
	var entry=preload("res://addons/player_runtime/entry_fly_in.gd").new();entry.game=game;entry.view=view
	for item:int in [0,1,2,3,6,8,405]:
		game.player_hud.active_item=item;entry.wake_pending=true
		check(entry.begin() and entry.waking and entry.blocks_actions(),"waking starts with actions blocked; item "+str(item))
		for frame in 301:entry.step(1.0/60)
		var human:Node=game.tool_view.human
		check(not entry.active and not entry.wake_pending and human.is_processing(),"five seconds returns normal animation processing")
		check(game.tool_view.current==(401 if item==405 else item) and human.active_clip==human._motion_clip("Idle") and human.action_remaining==0,"selected item is already idle at completion: "+str(item))
	game.player_hud.active_item=8;entry.wake_pending=true;entry.begin();entry.step(.2);game.app_focused=false;entry.step(.01)
	check(not entry.active and game.tool_view.current==8 and game.tool_view.human.is_processing(),"focus loss returns selected weapon without replaying waking")
	check(Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED,"waking never takes mouse ownership")
	game.free();print("WAKEUP_RUNTIME checks=",checks," failures=",failures);quit(1 if failures else 0)
