# SPDX-License-Identifier: 0BSD
extends RefCounted
func place(game:Node)->bool:
	if not game._model_edit_available() or game.session_menu.visible_ui() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED:return false
	var item:int=game.equipped_tool
	if item not in game.mining_rewards.TERRAIN_ITEMS:return false
	var start:Vector3=game.camera.global_position
	var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3.5,7,[game.player.get_rid()])
	if hit.is_empty() or not hit.has("normal"):game._show_lake_notice("Aim at reachable ground to place terrain");return false
	var cell:=Vector3i((hit.position+hit.normal*.25).round())
	var bounds:=AABB(Vector3(cell)-Vector3.ONE*.85,Vector3.ONE*1.7)
	var player_bounds:=AABB(game.player.global_position-Vector3(.4,.05,.4),Vector3(.8,1.9,.8))
	if bounds.intersects(player_bounds) or not game.world_vehicle.ready_bounds(game,bounds) or game.world_vehicle.overlaps_edit(bounds):
		game._show_lake_notice("Terrain placement needs clear, loaded space away from player and vehicles");return false
	var shape:=SphereShape3D.new();shape.radius=.74
	var query:=PhysicsShapeQueryParameters3D.new();query.shape=shape;query.transform.origin=Vector3(cell);query.collision_mask=6
	if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():game._show_lake_notice("Terrain placement is obstructed");return false
	var accepted:bool=game.mining_rewards.place(cell,item,game.player_hud.active_slot)
	game._show_lake_notice("Placing "+game.player_hud.RESOURCES[item] if accepted else "Terrain placement unavailable; wait for the current edit")
	return accepted
