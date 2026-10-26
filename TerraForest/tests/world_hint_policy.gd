extends SceneTree

const Catalog=preload("res://addons/world_ecosystem/ground_catalog.gd")
var failures:=0

class Identity extends RefCounted:
	var identity:=0
	func aimed_id(_target:Dictionary)->int:return identity

class Hinge extends RefCounted:
	var opened:=false
	func is_open(_identity:int)->bool:return opened

class Door extends Identity:
	var state:=Hinge.new()

class Vehicle extends RefCounted:
	var identity:=0
	var queries:=0
	func candidate(_game:Node)->int:queries+=1;return identity

class Game extends Node:
	var corpse_loot:=Identity.new()
	var storage:=Identity.new()
	var doors:=Door.new()
	var world_vehicle:=Vehicle.new()
	var construction_inventory:Dictionary={"gameplay":true}
	var pickups:Dictionary={"ITEMS":{1:"Pickaxe",201:"Stone",501:"Vehicle"}}
	var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()

class Adapter extends "res://demo/world_interaction.gd":
	var loose:Dictionary={}
	var enabled:=true
	func available(_game:Node)->bool:return enabled
	func hit(_game:Node)->Dictionary:return {}
	func loose_target(_game:Node,_target:Dictionary)->Dictionary:return loose

func check(passed:bool,label:String)->void:
	print("PASS " if passed else "FAIL ",label)
	if not passed:failures+=1

func _initialize()->void:run.call_deferred()

func run()->void:
	var game:=Game.new()
	game.player_hud.interaction_hint=Label.new()
	game.player_hud.add_child(game.player_hud.interaction_hint)
	var adapter:=Adapter.new()
	check(Catalog.WORLD_HINTS.size()==Catalog.COUNT,"every ground species declares hint visibility")
	game.world_vehicle.identity=9
	for gameplay in [true,false]:
		game.construction_inventory.gameplay=gameplay
		for species in Catalog.COUNT:
			adapter.loose={"kind":"ground","hit":{"species":species,"large":false}}
			adapter.update(game,1.0)
			var expected:="E · "+("Collect " if gameplay else "Remove ")+Catalog.NAMES[species] if species in [0,3,4,5] else ""
			check(game.player_hud.interaction_hint.text==expected and game.player_hud.interaction_hint.visible==not expected.is_empty(),"species %d labels only stones and flowers in %s"%[species,"gameplay" if gameplay else "editor"])
			adapter.loose.hit.large=true
			adapter.update(game,1.0)
			check(game.player_hud.interaction_hint.text.is_empty() and not game.player_hud.interaction_hint.visible,"large ground object %d stays unlabeled in %s"%[species,"gameplay" if gameplay else "editor"])
	check(game.world_vehicle.queries==0,"presenter does not invent a vehicle prompt for a resolved ground target")
	game.construction_inventory.gameplay=true
	for item in [1,201,501]:
		adapter.loose={"kind":"pickup","item":item}
		check(adapter.describe(game,{})=="E · Pick up "+game.pickups.ITEMS[item],"dropped item %d retains its pickup label"%item)
	game.corpse_loot.identity=1
	check(adapter.describe(game,{})=="E · Search zombie corpse","corpse storage keeps search prompt")
	game.corpse_loot.identity=0;game.storage.identity=1
	check(adapter.describe(game,{})=="E · Open wooden chest","container keeps open prompt")
	game.storage.identity=0;game.doors.identity=1
	check(adapter.describe(game,{})=="E · Open wooden door","closed door keeps open prompt")
	game.doors.state.opened=true
	check(adapter.describe(game,{})=="E · Close wooden door","open door keeps close prompt")
	game.doors.identity=0;adapter.loose={}
	adapter.update(game,1.0)
	check(game.player_hud.interaction_hint.text.contains("Enter vehicle") and game.world_vehicle.queries==1,"vehicle hint remains when no aimed interaction takes priority")
	adapter.loose={"kind":"ground","hit":{"species":2,"large":false}}
	adapter.update(game,1.0)
	check(not game.player_hud.interaction_hint.visible and game.player_hud.interaction_hint.text.is_empty(),"moving onto grass clears previous label")
	adapter.enabled=false;adapter.update(game,1.0)
	check(not game.player_hud.interaction_hint.visible,"unavailable interaction remains hidden")
	game.player_hud.free();game.free()
	print("WORLD_HINT_POLICY failures=",failures)
	quit(1 if failures else 0)
