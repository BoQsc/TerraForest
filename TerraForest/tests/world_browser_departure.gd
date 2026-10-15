# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainStub extends Node:
	signal save_completed(ok: bool)
	var world_ready:=true
	var stopping:=false
	var latest_error:=""
	var saves:=0
	func save_world()->void:
		saves+=1;save_completed.emit(false)
class VehicleStub extends RefCounted:
	var driving:=false
	func safe_exit_position(_game: Node)->Vector3:return Vector3.INF
class GameStub extends Node:
	var shutdown_requested:=false
	var loading_active:=false
	var temporary_world:=false
	var terrain:=TerrainStub.new()
	var world_vehicle:=VehicleStub.new()
	func _cancel_edit_input()->void:pass
	func _clear_motion()->void:pass
var failures:=0
func check(ok: bool,label: String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var game:=GameStub.new()
	var menu=preload("res://addons/player_runtime/session_menu.gd").new()
	menu.game=game;menu.message=Label.new();menu.panel=PanelContainer.new()
	await menu.leave_to_browser()
	check(game.terrain.saves==0 and not game.shutdown_requested and menu.message.text.begins_with("No world browser"),"unconfigured addon has no demo dependency or save side effects")
	menu.world_browser_path="res://missing_world_browser.tscn"
	await menu.leave_to_browser()
	check(game.terrain.saves==0 and not menu.leaving_world,"missing host destination refuses departure before save")
	menu.world_browser_path="res://demo/worlds.tscn"
	game.loading_active=true
	await menu.leave_to_browser()
	check(game.terrain.saves==0 and not game.shutdown_requested,"loading refuses departure without touching saves")
	game.loading_active=false;game.world_vehicle.driving=true
	await menu.leave_to_browser()
	check(game.terrain.saves==0 and menu.message.text.begins_with("Park"),"unsafe seated restore refuses departure")
	game.world_vehicle.driving=false
	await menu.leave_to_browser()
	check(game.terrain.saves==1 and not menu.leaving_world and not game.shutdown_requested,"failed save releases departure guard and stays in session")
	check(menu.panel.process_mode==Node.PROCESS_MODE_INHERIT and menu.message.text.begins_with("Save did not complete"),"failed save restores menu with explicit feedback")
	check(game.terrain.save_completed.get_connections().is_empty(),"failed save removes temporary callback")
	menu.message.free();menu.panel.free();menu.free();game.terrain.free();game.free()
	print("WORLD_BROWSER_DEPARTURE failures=",failures);quit(1 if failures else 0)
