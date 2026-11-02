# SPDX-License-Identifier: 0BSD
extends "res://tests/zombie_impacts.gd"
class Residents extends RefCounted:
	var rows:Array=[]
	func authored_identities(_anchors:PackedInt64Array)->PackedInt64Array:return PackedInt64Array([1,2,3])
	func resident(identity:int)->Dictionary:return rows[identity-1]
class Menu extends RefCounted:
	var paused:=false
	func pauses_world()->bool:return paused
class Guide extends RefCounted:
	var destination:Dictionary={}
	func refresh()->void:pass
class Game extends Node:
	var loading_active:=false
	var shutdown_requested:=false
	var app_focused:=true
	var player:=Node3D.new()
	var camera:=Camera3D.new()
	var session_menu:=Menu.new()
	var player_hud:Dictionary={"inventory_open":false,"quests_notice":Label.new()}
	var terrain:Dictionary={"changed_since_save":false}
	var trader:Dictionary={"ui":{"opened":false}}
	var destination_guide:=Guide.new()
	var map_markers:Dictionary={"markers":[]}
	var zombies:Dictionary={"population":{"store":Residents.new()}}
	var quests:Node
class Atlas extends Node:
	var game:Node
	var texture:Texture2D
	var water_survey:Dictionary={"texture":null}
	var model_survey:Dictionary={"texture":null}
	var block_survey:Dictionary={"texture":null}
	var show_grid:=false
	var show_roads:=false
	var show_places:=false
	var show_deposits:=false
	var places:Array=[]
	var deposits:Array=[]

func run()->void:
	var game:=Game.new();root.add_child(game);game.add_child(game.player);game.add_child(game.camera);game.add_child(game.player_hud.quests_notice)
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(601,1000)
	var store:RefCounted=ClassDB.instantiate("NativeQuestLog");store.configure(inventory,601)
	var location:={"key":1,"layout":"mine_test","title":"Mine search","origin":Vector3i(100,40,100),"rotation":0,"marker":Vector3(110,40,100),"bounds":AABB(Vector3(100,40,100),Vector3(40,15,30)),"residents":PackedInt64Array([101,102,103]),"containers":PackedInt64Array([201]),"coins":20,"xp":80}
	store.register_locations(1703,[location]);store.accept(1,store.snapshot().revision);var cycle:Dictionary=store.begin_reset(store.snapshot().revision);store.finish_reset(cycle.cycle,true,store.snapshot().revision)
	game.quests=preload("res://addons/player_runtime/quest_world.gd").new();game.quests.game=game;game.quests.store=store;game.add_child(game.quests);game.quests.set_process(false)
	var sleepers:=PackedByteArray();sleepers.resize(44);sleepers.encode_u32(32,1)
	game.zombies.population.store.rows=[{"id":1,"anchor":101,"state":1,"sleep":PackedByteArray(),"position":Vector3(105,40,95)},{"id":2,"anchor":102,"state":1,"sleep":sleepers,"position":Vector3(118,40,90)},{"id":3,"anchor":103,"state":1,"sleep":PackedByteArray(),"position":Vector3(125,40,105)}]
	game.quests._process(.5);check(not game.quests.marker().get("area",false) and game.quests.contacts.is_empty(),"distant quest keeps waypoint and no contact spoilers")
	game.player.position=location.marker;game.quests._process(.5)
	check(game.quests.marker().get("area",false) and game.quests.contacts.size()==2,"arrival replaces waypoint with circle and only awake contacts")
	var compass=preload("res://addons/player_runtime/compass.gd").new();root.add_child(compass);compass.position=Vector2(330,28);compass.size=Vector2(620,58)
	compass.update_view(game.player.position,Vector3.FORWARD,game.quests.marker(),game.quests.contacts)
	check(not compass.has_marker and compass.contacts.size()==2,"compass removes point while preserving awake red spheres")
	var atlas:=Atlas.new();atlas.game=game;game.add_child(atlas)
	var map=preload("res://addons/world_runtime/world_map_view.gd").new();map.atlas=atlas;map.position=Vector2(150,145);map.size=Vector2(980,540);map.center=Vector2(120,115);map.zoom=12;root.add_child(map)
	await photograph("active-area-red-contacts")
	game.zombies.population.store.rows[0].state=2;game.quests._process(.5)
	for tick in 59:store.advance_search(location.marker,1000)
	game.app_focused=false;var before:int=store.snapshot().search_ms
	game.quests._process(.5);check(store.snapshot().search_ms==before,"unfocused time does not reveal sleepers")
	game.app_focused=true;store.advance_search(location.marker,1000);game.quests._process(.5)
	check(game.quests.contacts.size()==2 and game.quests.contacts.any(func(contact):return contact.sleeping),"minute after first kill reveals yellow sleeper alongside surviving awake zombie")
	compass.update_view(game.player.position,Vector3.FORWARD,game.quests.marker(),game.quests.contacts);map.queue_redraw();await photograph("search-assist-yellow-contact")
	game.zombies.population.store.rows[1].state=2;game.quests._process(.5)
	check(not store.snapshot().reveal_sleepers and game.quests.contacts.size()==1,"another kill removes contact and resets search timer")
	game.zombies.population.store.rows[2].state=2;game.quests._process(.5)
	check(store.snapshot().phase==4 and game.quests.contacts.is_empty(),"completion clears all enemy compass markers")
	game.free();map.free();compass.free();print("QUEST_GUIDANCE checks=",checks," failures=",failures);quit(1 if failures else 0)
