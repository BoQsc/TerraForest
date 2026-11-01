# SPDX-License-Identifier: 0BSD
extends Node3D
## One stationary shopkeeper, activated only within resident local collision.
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
const Mouse=preload("res://addons/world_runtime/mouse_ownership.gd")
const PLACE=preload("res://addons/structures/civic_catalog.gd").MERCHANT_PLACE
var game:Node
var trader:=Trade.new()
var ui:=preload("res://addons/player_runtime/trader_panel.gd").new()
var actor:StaticBody3D
var anchor:=Vector3.INF
var seen_revision:=-1
var remaining:=0.0
var prior_mouse:=Input.MOUSE_MODE_CAPTURED

func prepare(owner_game:Node,persistence:RefCounted)->bool:
	game=owner_game
	return trader.register_persistence(persistence)

func _ready()->void:
	add_child(ui)
	ui.closed.connect(_closed)
	ui.traded.connect(func():game.terrain.changed_since_save=true;game.player_hud.refresh())

func allowed()->bool:
	return game.app_focused and game.terrain.world_ready and not game.loading_active and not game.shutdown_requested and not game.terrain.pending_edit and not game.world_vehicle.driving and not game.fly and not game.session_menu.visible_ui()

func aimed(target:Dictionary)->bool:
	return is_instance_valid(actor) and not target.is_empty() and target.get("collider")==actor

func reachable()->bool:
	if not allowed() or not is_instance_valid(actor):return false
	var origin:Vector3=game.camera.global_position
	var target:Vector3=actor.global_position+Vector3.UP*1.45
	if origin.distance_squared_to(target)>9:return false
	var hit:Dictionary=game.structures.blocks.raycast_scene(origin,target,15,[game.player.get_rid()])
	return aimed(hit)

func try_open(target:Dictionary)->bool:
	if not aimed(target) or not allowed() or game.player_hud.inventory_open:return false
	if not ui.open_for(trader,game.player_hud.inventory,reachable):return false
	prior_mouse=Input.mouse_mode;game._clear_motion()
	game.player_hud.inventory_open=true;game.player_hud.enabled=false
	Mouse.set_mode(game,Input.MOUSE_MODE_VISIBLE)
	return true

func _closed()->void:
	game.player_hud.inventory_open=false;game.player_hud.enabled=true;game.player_hud.refresh()
	game._clear_motion();Mouse.set_mode(game,prior_mouse)

func _process(delta:float)->void:
	remaining-=delta
	if remaining>0:return
	remaining=.25
	var revision:int=game.generated_region.revision()
	if revision!=seen_revision:
		seen_revision=revision;anchor=Vector3.INF
		for place:Dictionary in game.generated_region.store.get_plan().get("places",[]):
			if place.id==PLACE:anchor=place.position;break
	var resident:bool=anchor.is_finite() and game.terrain.world_ready and not game.terrain.pending_edit and not game.loading_active and not game.shutdown_requested
	if resident:resident=game.player.global_position.distance_squared_to(anchor)<72*72 and game._actor_collision_ready(AABB(anchor-Vector3(.4,.3,.4),Vector3(.8,2.2,.8)))
	if resident:
		# Destructible floors remain authoritative; a removed shop floor suspends
		# the resident instead of leaving a floating collision/interaction proxy.
		var floor_hit:Dictionary=game.structures.blocks.raycast_scene(anchor+Vector3.UP*.12,anchor-Vector3.UP*.2,7,[game.player.get_rid()])
		resident=not floor_hit.is_empty() and floor_hit.normal.y>=.85
	if not resident:
		ui.close()
		if is_instance_valid(actor):actor.free();actor=null
		return
	if not is_instance_valid(actor):
		actor=StaticBody3D.new();actor.name="Trader_civic_01";actor.collision_layer=8;actor.collision_mask=0
		var shape:=CapsuleShape3D.new();shape.radius=.34;shape.height=1.8
		var collision:=CollisionShape3D.new();collision.shape=shape;collision.position.y=.9;actor.add_child(collision)
		add_child(actor);actor.global_position=anchor
		var human:=preload("res://addons/characters/runtime/human_view.gd").new();actor.add_child(human)
		human.position=Vector3.ZERO;human.rotation=Vector3.ZERO;human.set_third_person(true);human.set_process(false)
		# Role appearance only: no goods are transferred from the finite stock.
		human.clothing.set_slots([{"item":301,"count":1},{"item":302,"count":1},{"item":303,"count":1}])
		human.animation_player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
		human.animation_player.play(human.clips.get("Idle",human.clips["FP_Unarmed_Idle"]))
	if ui.opened and not reachable():ui.close()

