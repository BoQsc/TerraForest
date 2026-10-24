# SPDX-License-Identifier: 0BSD
extends RefCounted
const STAMP_RADIUS:=.75 # Native terrain command 38: one paid lattice sample.
var clearance:=SphereShape3D.new()
var obstruction:=PhysicsShapeQueryParameters3D.new()
func _init()->void:
	clearance.radius=.74;obstruction.shape=clearance;obstruction.collision_mask=6
func active(game:Node)->bool:
	return not game.session_menu.developer and game.equipped_tool in game.mining_rewards.TERRAIN_ITEMS and game._model_edit_available() and not game.session_menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
func target(game:Node)->Dictionary:
	if not active(game):return {}
	var item:int=game.equipped_tool
	var start:Vector3=game.camera.global_position
	var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3.5,7,[game.player.get_rid()])
	if hit.is_empty() or not hit.has("normal"):return {}
	var cell:=Vector3i((hit.position+hit.normal*.25).round())
	var bounds:=AABB(Vector3(cell)-Vector3.ONE*.85,Vector3.ONE*1.7)
	var result:={"cell":cell,"position":Vector3(cell),"normal":hit.normal,"bounds":bounds,"item":item,"ok":false,"reason":""}
	if cell.x<1 or cell.x>=2000 or cell.z<1 or cell.z>=2000 or cell.y<4 or cell.y>=254:
		result.reason="Outside terrain placement limits";return result
	var player_bounds:=AABB(game.player.global_position-Vector3(.4,.05,.4),Vector3(.8,1.9,.8))
	if bounds.intersects(player_bounds):result.reason="Move placement clear of yourself";return result
	if not game.world_vehicle.ready_bounds(game,bounds):result.reason="Placement area is still loading";return result
	if game.world_vehicle.overlaps_edit(bounds):result.reason="Move placement clear of the vehicle";return result
	obstruction.transform.origin=Vector3(cell)
	if not game.get_world_3d().direct_space_state.intersect_shape(obstruction,1).is_empty():result.reason="Blocked by an object";return result
	var rewards=game.mining_rewards
	if not rewards.enabled or rewards.failed or not rewards.payment.is_empty():result.reason="Terrain placement is not ready";return result
	var state:Dictionary=game.player_hud.inventory.snapshot();var slot:int=game.player_hud.active_slot
	if slot<0 or slot>=state.slots.size() or state.slots[slot].item!=item or state.slots[slot].count<1:result.reason="No carried material in this slot";return result
	result.ok=true;return result
func place(game:Node)->bool:
	if not active(game):return false
	# Re-evaluate the live target on click; the display is never edit authority.
	var selected:=target(game)
	# Invalid targets use marker color only, without repeated blocking notices.
	if selected.is_empty() or not selected.ok:return false
	var accepted:bool=game.mining_rewards.place(selected.cell,selected.item,game.player_hud.active_slot)
	if accepted:game._show_lake_notice("Placing "+game.player_hud.RESOURCES[selected.item])
	return accepted
