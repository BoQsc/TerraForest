# SPDX-License-Identifier: 0BSD
extends RefCounted
# Bounded interaction adapter. Native stores own damage, inventories and geometry.
var game: Node
var durability: RefCounted
var next_attack:=0
var rejection_reason:=""
const TOOLS={0:{"stone":5,"wood":5,"other":5},1:{"stone":30,"wood":10,"other":15},2:{"stone":10,"wood":30,"other":15},3:{"stone":15,"wood":15,"other":20},4:{"stone":10,"wood":15,"other":15}}
func prepare(world: Node) -> bool:
	game=world;durability=ClassDB.instantiate("NativeWorldDurability")
	return game.persistence.register_component("world_durability",durability.capture_storage_snapshot,durability.restore_storage_snapshot,durability,durability.capture_storage_snapshot())
func block_key(cell: Vector3i) -> String:return "block:%d:%d:%d"%[cell.x,cell.y,cell.z]
func target() -> Dictionary:
	var start: Vector3=game.camera.global_position
	var end: Vector3=start-game.camera.global_basis.z*3.5
	var hit: Dictionary=game.structures.blocks.raycast_scene(start,end,0xFFFFFFFF,[game.player.get_rid()])
	if game.ground_enabled and game.ground_interaction.available():
		var cover: Dictionary=game.ground_cover.picker.pick(start,hit.position if not hit.is_empty() else end)
		if cover.get("hit",false):
			if game.ground_cover._dirty.has(cover.cell) or game.ground_cover._pending.has(cover.cell):return {}
			return {"kind":"cover","key":"cover:%d"%cover.id,"id":cover.id,"cell":cover.cell,"health":45 if cover.species==0 else (40 if cover.species==6 else 10),"material":"stone" if cover.species==0 else "wood","name":game.player_hud.GroundCatalog.NAMES[cover.species],"end":end}
	if hit.is_empty():
		if game.terrain.backend.region_terrain:hit=game._terrain_pick(start,end)
		if hit.is_empty():return {}
	var collider=hit.get("collider")
	if collider==game.structures.blocks and hit.has("cell"):
		var cell: Vector3i=hit.cell
		var word: int=game.structures.blocks.get_cell(cell)
		return {"kind":"block","key":block_key(cell),"health":[90,60,120,180][(word>>5)&3],"material":"wood" if ((word>>5)&3)==1 else "stone","name":"Building block","cell":cell}
	if collider!=null and collider==game.vegetation.trunk_collision:
		var id: int=collider.placement_for_body(hit.rid)
		if id>0:return {"kind":"tree","key":"tree:%d"%id,"id":id,"health":90,"material":"wood","name":"Tree"}
	for asset: String in game.structures._models:
		var collection=game.structures._models[asset]
		if collider==collection:
			var id: int=collection.placement_for_body(hit.rid)
			if id>0:return {"kind":"model","key":"model:%s:%d"%[asset,id],"id":id,"collection":collection,"health":90,"material":"wood" if "wood" in asset or "furniture" in asset or "storage" in asset else "other","name":"Object"}
	if collider!=null and game.actors.pool!=null and collider.get_parent()==game.actors.pool:
		var handle: int=collider.entity_handle(game.actors.store)
		if handle!=0:
			var id: int=game.actors.store.persistent_id(handle)
			return {"kind":"actor","key":"actor:%d"%id,"id":id,"handle":handle,"health":100,"material":"other","name":"Actor"}
	var vehicles=game.world_vehicle
	var vehicle_id: int=vehicles.car_identity if collider!=null and collider==vehicles.car else 0
	if vehicles.fleet_enabled and collider!=null:
		for id: int in vehicles.activation.residents:
			if vehicles.activation.residents[id]==collider:vehicle_id=id
		if collider==vehicles.activation.parked_view and collider.has_method("identity_for_body"):vehicle_id=collider.identity_for_body(hit.rid)
	if vehicle_id>0:return {"kind":"vehicle","key":"vehicle:%d"%vehicle_id,"id":vehicle_id,"health":300,"material":"other","name":"Vehicle"}
	if collider==null or (collider is CollisionObject3D and game.terrain.is_ancestor_of(collider) and collider.collision_layer&1):
		var cell:=Vector3i((hit.position-hit.normal*0.05).floor())
		return {"kind":"terrain","key":"terrain:%d:%d:%d"%[cell.x,cell.y,cell.z],"health":30,"material":"stone","name":"Terrain","position":hit.position,"normal":hit.normal}
	return {}
func attack() -> bool:
	if game.session_menu.developer or not TOOLS.has(game.equipped_tool) or not game._model_edit_available() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or game.session_menu.visible_ui():return false
	var now:=Time.get_ticks_msec()
	if now<next_attack:return false
	next_attack=now+250;game.tool_view.swing();game.terrain.note_interaction()
	var selected:=target()
	if selected.is_empty():return false
	if selected.kind=="terrain":game.terrain.set_interaction_target(selected.position)
	return apply_target(selected)
func apply_target(t: Dictionary) -> bool:
	var hud=game.player_hud
	var item: int=game.equipped_tool
	if not TOOLS.has(item) or (item!=0 and hud.active_slot<0):return false
	if t.kind=="actor" and (t.handle==0 or game.actors.store.resolve_identity(t.id)!=t.handle):return false
	if t.kind=="cover" and (game.ground_cover._dirty.has(t.cell) or game.ground_cover._pending.has(t.cell)):return false
	if t.kind=="model" and t.collection.is_removal_protected(t.id):
		game._show_lake_notice("Empty stored contents before damaging this container");return false
	var result: Dictionary=durability.hit(t.key,t.health,TOOLS[item][t.material])
	if not result.ok:game._show_lake_notice(result.get("reason","Damage unavailable"));return false
	game.terrain.changed_since_save=true
	rejection_reason=""
	var accepted:=true
	if result.destroyed:accepted=destroy(t)
	if not accepted:
		game._show_lake_notice(rejection_reason if not rejection_reason.is_empty() else "Destruction blocked; make inventory room or wait for the world");return false
	if result.destroyed:durability.forget(t.key)
	var wear: Dictionary=hud.inventory.wear_tool(hud.active_slot,1,hud.inventory.snapshot().revision) if item!=0 else {}
	hud.refresh()
	game._show_lake_notice("Tool broke" if wear.get("broken",false) else (t.name+" destroyed" if result.destroyed else "%s: %d / %d durability"%[t.name,result.remaining,result.maximum]))
	return true
func destroy(t: Dictionary) -> bool:
	match t.kind:
		"block":return game.construction_inventory.place_block(game.structures.blocks,game.player_hud.inventory,t.cell,0)
		"tree":return game.ecosystem.harvest_root(t.id,game.player_hud.inventory).ok
		"model":return game._remove_inventory_model(game.model_tool.history,t.collection,t.id)
		"cover":
			var collected: Dictionary=game.ground_interaction.collect(game.camera.global_position,t.end,game.player_hud.inventory,true)
			rejection_reason=collected.reason;return collected.ok
		"terrain":
			var center: Vector3=t.position-t.normal*0.35
			if not game.stroke_buffer.push_sweep(center,center,0.65,0,false,game.material_id,false):return false
			game._consume_stroke();return game.terrain.pending_edit
		"actor":
			return game._remove_actor(t.id)
		"vehicle":
			var vehicles=game.world_vehicle
			if not vehicles.fleet.remove(t.id):return false
			if vehicles.fleet_enabled:
				if vehicles.activation.residents.has(t.id):vehicles.activation.retire(t.id)
				vehicles.activation.refresh_parked(game)
			elif vehicles.car_identity==t.id:
				vehicles.car.queue_free();vehicles.car=null;vehicles.car_identity=0
			return true
	return false
