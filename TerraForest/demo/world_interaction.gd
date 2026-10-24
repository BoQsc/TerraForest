# SPDX-License-Identifier: 0BSD
# UI coordination only; picking, hinge state and storage mutations remain native.
extends RefCounted
var remaining:=0.0
func available(game: Node) -> bool:
	return game._model_edit_available() and not game.fly and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and not game.session_menu.visible_ui()
func hit(game: Node) -> Dictionary:
	var origin: Vector3=game.camera.global_position
	return game.structures.blocks.raycast_scene(origin,origin-game.camera.global_basis.z*3.0,7,[game.player.get_rid()])
func describe(game: Node, target: Dictionary) -> String:
	if game.corpse_loot.aimed_id(target)>0:return "E · Search zombie corpse"
	if game.storage.aimed_id(target)>0:return "E · Open wooden chest"
	var door_id: int=game.doors.aimed_id(target)
	if door_id>0:return "E · Close wooden door" if game.doors.state.is_open(door_id) else "E · Open wooden door"
	var loose:=loose_target(game,target)
	if loose.get("kind")=="pickup":return "E · Pick up "+game.pickups.ITEMS[loose.item]
	if loose.get("kind")=="ground":
		if game.construction_inventory.gameplay and loose.hit.get("large",false):return "Left mouse · Mine stone boulder (pickaxe)"
		if game.construction_inventory.gameplay and loose.hit.species==8:return "Left mouse · Harvest woody bush (two hits)"
		var name: String=preload("res://addons/world_ecosystem/ground_catalog.gd").NAMES[loose.hit.species]
		return "E · "+("Collect " if game.construction_inventory.gameplay else "Remove ")+name
	return ""
func ground_target(game: Node,target: Dictionary) -> Dictionary:
	if not game.ground_enabled:return {"ok":false}
	var origin: Vector3=game.camera.global_position
	return game.ground_interaction.collection_probe(origin,origin-game.camera.global_basis.z*2.5,target)
func pickup_end(game: Node,target: Dictionary) -> Vector3:
	var origin: Vector3=game.camera.global_position
	var endpoint: Vector3=origin-game.camera.global_basis.z*2.5
	return target.position if not target.is_empty() and origin.distance_squared_to(target.position)<origin.distance_squared_to(endpoint) else endpoint
func loose_target(game: Node,target: Dictionary) -> Dictionary:
	var ground:=ground_target(game,target)
	if ground.ok:ground.kind="ground"
	if game.pickups==null:return ground
	var origin: Vector3=game.camera.global_position
	var pickup: Dictionary=game.pickups.aimed(origin,pickup_end(game,target),game._pickup_reachable)
	if pickup.ok and (not ground.ok or origin.distance_squared_to(pickup.position)<origin.distance_squared_to(ground.hit.position)):
		pickup.kind="pickup";return pickup
	return ground
func update(game: Node, delta: float) -> void:
	if not available(game):
		remaining=0.0;game.player_hud.show_interaction_hint("");return
	remaining-=delta
	if remaining>0.0:return
	# One native scene ray at most every 100 ms, never a catch-up loop.
	remaining=0.1
	var hint:=describe(game,hit(game))
	if hint.is_empty() and game.world_vehicle.candidate(game)>0:hint="E · Enter vehicle  /  Hold E · Vehicle actions"
	game.player_hud.show_interaction_hint(hint)
func interact(game: Node) -> bool:
	if not available(game):return false
	# Re-pick at the input event: the presentation cache is never authoritative.
	var target:=hit(game)
	var handled: bool=game.corpse_loot.ui.try_open(target) or game.storage.try_open(target) or game.doors.try_interact(target)
	var loose: Dictionary={} if handled else loose_target(game,target)
	if not handled and loose.get("kind")=="pickup":
		var result: Dictionary=game.pickups.collect_aimed(game.camera.global_position,pickup_end(game,target),game.player_hud.inventory,game._pickup_reachable)
		if result.ok:game.player_hud.refresh()
		game._show_lake_notice(result.reason);handled=true
	if not handled and loose.get("kind")=="ground":
		var origin: Vector3=game.camera.global_position
		var result: Dictionary=game.ground_interaction.collect(origin,origin-game.camera.global_basis.z*2.5,game.player_hud.inventory,game.construction_inventory.gameplay,target)
		if result.ok:
			game.world_attack.durability.forget("cover:%d"%result.id)
			game.player_hud.refresh()
		game._show_lake_notice(result.reason)
		handled=true
	remaining=0.0
	return handled
