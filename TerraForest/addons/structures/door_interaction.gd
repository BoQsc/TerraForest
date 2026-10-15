# SPDX-License-Identifier: 0BSD
# Click-time scene adapter only; native store owns hinge state and mutations.
extends RefCounted
var state: RefCounted
var game: Node
var collection: Node3D
func prepare(world: Node) -> bool:
	game=world;collection=game.structures.model(preload("res://addons/structures/door_catalog.gd").KEY)
	state=ClassDB.instantiate("NativeHingedDoors")
	return collection!=null and game.persistence.register_component("door_hinges",state.capture_storage_snapshot,state.restore_storage_snapshot,state,state.capture_storage_snapshot())
func try_interact() -> bool:
	if not game._model_edit_available():return false
	var start: Vector3=game.camera.global_position
	var hit: Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3,7,[game.player.get_rid()])
	if hit.is_empty() or hit.collider!=collection:return false
	var id: int=collection.placement_for_body(hit.rid)
	var result: Dictionary=state.toggle(collection,id,game.model_tool.protection())
	if result.ok:game.terrain.changed_since_save=true
	game._show_lake_notice(result.reason)
	return true
