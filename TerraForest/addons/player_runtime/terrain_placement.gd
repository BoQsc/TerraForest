# SPDX-License-Identifier: 0BSD
extends RefCounted
const STAMP_RADIUS:=.75 # Native terrain command 38: one paid lattice sample.
var clearance:=SphereShape3D.new()
var obstruction:=PhysicsShapeQueryParameters3D.new()
var queried_terrain:Node
var pending:Dictionary={}
var cached:Dictionary={}
var sequence:=0
var queued:Dictionary={}
var held:=false
var last_held_cell:=Vector3i(-1,-1,-1)
func cancel()->void:
	held=false;queued={};last_held_cell=Vector3i(-1,-1,-1)
func begin_hold(game:Node)->bool:
	if not active(game,true):return false
	held=true;last_held_cell=Vector3i(-1,-1,-1)
	return place(game)
func _init()->void:
	clearance.radius=.74;obstruction.shape=clearance;obstruction.collision_mask=6
func active(game:Node,allow_pending:bool=false)->bool:
	return not game.session_menu.developer and game.equipped_tool in game.mining_rewards.TERRAIN_ITEMS and game._model_edit_available(allow_pending) and not game.session_menu.visible_ui() and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED
func receive_target(reply:Dictionary)->void:
	if pending.is_empty() or reply.token!=pending.token:return
	cached=pending.duplicate();cached.reply=reply;pending={}
	if reply.get("status") not in ["hit","miss"]:cached={}
func matches(query:Dictionary,terrain:Node)->bool:
	return not query.is_empty() and query.epoch==terrain.epoch and query.revision==terrain.native_revision and query.ticket==terrain.edit_ticket
func update(game:Node)->void:
	if not active(game,true):cancel();return
	if held and queued.is_empty() and not game.terrain.pending_edit:
		var current:=target(game)
		if current.get("ok",false) and current.cell!=last_held_cell:submit(game,current)
	if queued.is_empty():return
	if not active(game,true) or Time.get_ticks_msec()>queued.deadline or game.equipped_tool!=queued.item or game.player_hud.active_slot!=queued.slot or game.terrain.epoch!=queued.epoch or game.camera.global_position.distance_squared_to(queued.eye)>.0225 or (-game.camera.global_basis.z).dot(queued.direction)<.998:
		queued={};return
	if game.terrain.pending_edit:return
	var selected:=target(game)
	if selected.get("reason")=="Checking terrain":return
	queued={}
	if selected.get("ok",false):submit(game,selected)
func target(game:Node)->Dictionary:
	if not active(game,true):return {}
	var item:int=game.equipped_tool
	var start:Vector3=game.camera.global_position
	var hit:Dictionary=game.structures.blocks.raycast_scene(start,start-game.camera.global_basis.z*3.5,7,[game.player.get_rid()])
	if hit.is_empty() or not hit.has("normal"):return {}
	if queried_terrain!=game.terrain:
		queried_terrain=game.terrain;pending={};cached={}
		queried_terrain.placement_target_received.connect(receive_target)
	var cell:=Vector3i((hit.position+hit.normal*.5).round())
	var axis:int=hit.normal.abs().max_axis_index()
	if (Vector3(cell)-hit.position).dot(hit.normal)<.38:cell[axis]+=1 if hit.normal[axis]>0 else -1
	var selection:Dictionary={}
	if matches(cached,game.terrain):selection=game.terrain.planner.placement_target(hit.position,hit.normal,cached.reply.origin,cached.reply.empty)
	var resolved:bool=selection.get("status") in ["hit","miss"]
	if selection.get("status")=="hit":cell=selection.cell
	if not resolved and pending.is_empty() and not game.terrain.pending_edit:
		sequence+=1
		if game.terrain.request_placement_target(hit.position,hit.normal,sequence):
			pending={"token":sequence,"point":hit.position,"normal":hit.normal,"epoch":game.terrain.epoch,"revision":game.terrain.native_revision,"ticket":game.terrain.edit_ticket}
	var bounds:=AABB(Vector3(cell)-Vector3.ONE*.85,Vector3.ONE*1.7)
	var anchor:Vector3=Vector3(cell)+hit.normal*maxf(0,.38-(Vector3(cell)-hit.position).dot(hit.normal))
	var result:={"cell":cell,"position":anchor,"normal":hit.normal,"surface":hit.position,"bounds":bounds,"item":item,"ok":false,"reason":""}
	if game.terrain.pending_edit:result.reason="Terrain is updating";return result
	if cell.x<1 or cell.x>=2000 or cell.z<1 or cell.z>=2000 or cell.y<4 or cell.y>=254:
		result.reason="Outside terrain placement limits";return result
	if not resolved:result.reason="Checking terrain";return result
	if selection.get("status")!="hit":result.reason="No exposed terrain sample";return result
	var player_bounds:=AABB(game.player.global_position-Vector3(.4,.05,.4),Vector3(.8,1.9,.8))
	var nearest:Vector3=Vector3(cell).clamp(player_bounds.position,player_bounds.end)
	if nearest.distance_squared_to(Vector3(cell))<=STAMP_RADIUS*STAMP_RADIUS:result.reason="Move placement clear of yourself";return result
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
	if not active(game,true):return false
	# Re-evaluate the live target on click; the display is never edit authority.
	var selected:=target(game)
	if game.terrain.pending_edit or selected.get("reason")=="Checking terrain":
		queued={"deadline":Time.get_ticks_msec()+1500,"item":game.equipped_tool,"slot":game.player_hud.active_slot,"epoch":game.terrain.epoch,"eye":game.camera.global_position,"direction":-game.camera.global_basis.z}
		return true
	# Invalid targets use marker color only, without repeated blocking notices.
	if selected.is_empty() or not selected.ok:return false
	queued={}
	return submit(game,selected)
func submit(game:Node,selected:Dictionary)->bool:
	var accepted:bool=game.mining_rewards.place(selected.cell,selected.item,game.player_hud.active_slot)
	if accepted:
		last_held_cell=selected.cell
		game._show_lake_notice("Placing "+game.player_hud.RESOURCES[selected.item])
	return accepted
