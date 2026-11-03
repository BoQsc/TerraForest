# SPDX-License-Identifier: 0BSD
extends SceneTree
const Escape=preload("res://addons/player_runtime/escape_policy.gd")
var checks:=0
var failures:=0

class FakeTraderUI extends Node:
	var opened:=true
	var closed:=false
	func close()->void:
		closed=true;opened=false
class FakeTrader extends Node:
	var ui:=FakeTraderUI.new()
class FakeHud extends Node:
	var modal:Control
class FakeVehicle extends Node:
	var opened:=false
	var held_since:=-1
	func cancel()->void:pass
class FakeCorpseUI extends Node:
	var opened:=false
	func close()->void:pass
class FakeCorpse extends Node:
	var ui:=FakeCorpseUI.new()
class FakeStorage extends Node:
	var opened:=false
	func close()->void:pass
class FakeGame extends Node:
	var trader:=FakeTrader.new()
	var vehicle_radial:=FakeVehicle.new()
	var corpse_loot:=FakeCorpse.new()
	var storage:=FakeStorage.new()
	var player_hud:=FakeHud.new()
class FakeMenu extends CanvasLayer:
	var game:Node
	var confirmation:Control
	var world_map=null
	var player_actions=null
	var workspace:=false
	var opened:=false
	var developer_hud=null
	func set_open(value:bool)->void:opened=value

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)

func _initialize()->void:
	var game:=FakeGame.new()
	game.trader.add_child(game.trader.ui)
	game.add_child(game.trader)
	game.add_child(game.vehicle_radial)
	game.corpse_loot.add_child(game.corpse_loot.ui)
	game.add_child(game.corpse_loot)
	game.add_child(game.storage)
	game.player_hud.modal=Control.new();game.player_hud.modal.visible=false
	game.player_hud.add_child(game.player_hud.modal);game.add_child(game.player_hud)
	var menu:=FakeMenu.new();menu.game=game;menu.confirmation=Control.new();menu.confirmation.visible=false
	menu.add_child(menu.confirmation)
	Escape.close_or_pause(menu)
	check(game.trader.ui.closed and not game.trader.ui.opened,"Esc closes the active trader")
	check(not menu.opened,"Esc does not open the session menu while the trader is active")
	print("ESCAPE_POLICY_TRADER checks=",checks," failures=",failures)
	game.free();menu.free()
	quit(1 if failures else 0)
