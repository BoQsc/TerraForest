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
	if game.storage.aimed_id(target)>0:return "E · Open wooden chest"
	var door_id: int=game.doors.aimed_id(target)
	if door_id>0:return "E · Close wooden door" if game.doors.state.is_open(door_id) else "E · Open wooden door"
	return ""
func update(game: Node, delta: float) -> void:
	if not available(game):
		remaining=0.0;game.player_hud.show_interaction_hint("");return
	remaining-=delta
	if remaining>0.0:return
	# One native scene ray at most every 100 ms, never a catch-up loop.
	remaining=0.1
	game.player_hud.show_interaction_hint(describe(game,hit(game)))
func interact(game: Node) -> bool:
	if not available(game):return false
	# Re-pick at the input event: the presentation cache is never authoritative.
	var target:=hit(game)
	var handled: bool=game.storage.try_open(target) or game.doors.try_interact(target)
	remaining=0.0
	return handled
