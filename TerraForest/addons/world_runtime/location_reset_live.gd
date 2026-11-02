# SPDX-License-Identifier: 0BSD
extends Node

const Plan = preload("res://addons/world_runtime/location_reset_plan.gd")
const Capture = preload("res://addons/world_runtime/location_capture.gd")
signal completed(result: Dictionary)
var game: Node
var busy := false
var phase := "idle"
var last_result: Dictionary = {}
var plan: RefCounted
var batch: RefCounted
var worker: Thread
var cancelled := false
var _paused: Dictionary = {}
var _streaming_paused := false
var _started := 0
var _checkpoint := false
var _mutated := false
var _epoch := -1
var _physics_enabled := false

func exclusion(location: Dictionary) -> String:
	var bounds: AABB = location.bounds.grow(1.0)
	if bounds.intersects(AABB(game.player.global_position-Vector3(.34,0,.34),Vector3(.68,1.8,.68))):return "Step outside the location before resetting it."
	if game.world_vehicle.overlaps_edit(bounds):return "Move vehicles outside the location before resetting it."
	var owned: PackedInt64Array = game.zombies.population.store.authored_identities(location.residents)
	if game.corpse_loot.store.foreign_corpse_in_region(bounds,owned):return "An unrelated corpse is inside the location."
	var radius: float = Vector2(bounds.size.x,bounds.size.z).length()*.5+3
	var residents: Array = game.zombies.population.store.nearby(bounds.get_center(),radius)
	if radius>96 or residents.size()>=32:return "Location occupancy exceeds the checked query budget."
	for resident: Dictionary in residents:
		if not owned.has(int(resident.id)) and resident.state<2 and bounds.grow(2).has_point(resident.position):return "Another inhabitant is inside the location."
	var actors: Dictionary = game.actors.store.query_sphere(bounds.get_center(),radius,1024,4096)
	if not actors.ok or not actors.complete:return "Location occupancy is not ready."
	for identity: int in actors.ids:
		if bounds.grow(1).has_point(game.actors.store.get_position(identity)):return "Another inhabitant is inside the location."
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new();shape.size=bounds.size
	query.shape=shape;query.transform=Transform3D(Basis.IDENTITY,bounds.get_center())
	query.collision_mask=8|game.zombies.CHARACTER_LAYER|game.zombies.RAGDOLL_LAYER
	var excluded: Array[RID] = []
	var bodies: Array = game.zombies.residents.duplicate()
	bodies.append_array(game.corpse_loot.active.values())
	for zombie: Node3D in bodies:
		if not is_instance_valid(zombie) or not owned.has(int(zombie.get_meta("world_zombie_id",0))):continue
		excluded.append(zombie.get_rid())
		for bone: PhysicalBone3D in zombie.physical_bones.values():excluded.append(bone.get_rid())
		for detached: RigidBody3D in zombie.detached_parts:
			if is_instance_valid(detached):excluded.append(detached.get_rid())
	query.exclude=excluded
	if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():return "Another body is inside the location."
	return ""

func begin() -> Dictionary:
	if busy or game.loading_active or game.shutdown_requested or game.temporary_world or game.terrain.backend.readonly_snapshot or not game.terrain.world_ready or not game.terrain.latest_error.is_empty():return {"ok":false,"reason":"World is not ready to reset a location."}
	var state: Dictionary = game.quests.store.snapshot()
	if state.phase!=1 or game.terrain.pending_edit or game.world_vehicle.driving or game.player_life.dead or not game._foundation_placement.is_empty() or game.site_preparation.status=="running":return {"ok":false,"reason":"Finish the current action before resetting the location."}
	if not game.world_vehicle.coasting.is_empty() or game.trader.ride.active():return {"ok":false,"reason":"Wait for moving vehicles before resetting the location."}
	var reason := exclusion(state.location)
	if not reason.is_empty():return {"ok":false,"reason":reason}
	busy=true;phase="checkpoint";cancelled=false;_checkpoint=false;_mutated=false;_started=Time.get_ticks_usec();_epoch=game.terrain.epoch
	last_result={};plan=null;batch=null
	game.trader.ui.close();game.storage.close();game.corpse_loot.ui.close()
	game.player_hud.set_open(false);game.session_menu.set_open(false)
	game._cancel_edit_input();game._begin_loading("Restoring quest location")
	_physics_enabled=game.is_physics_processing();game.set_physics_process(false)
	game.zombies.update(0,game.player.global_position,false)
	game.actors.update_simulation(0,game.terrain.focus,false,game._actor_collision_ready)
	_run.call_deferred(state)
	return {"ok":true,"reason":""}

func cancel() -> void:
	if busy:cancelled=true

func _alive() -> bool:
	return is_inside_tree() and is_instance_valid(game) and not game.shutdown_requested and not game.terrain.stopping

func _wait(predicate: Callable, seconds: int = 60, allow_cancel: bool = true) -> bool:
	var deadline := Time.get_ticks_msec()+seconds*1000
	while _alive() and game.terrain.epoch==_epoch and game.terrain.latest_error.is_empty() and (not allow_cancel or not cancelled):
		if predicate.call():return true
		if Time.get_ticks_msec()>=deadline:return false
		await get_tree().process_frame
	return false

func _pause(node: Node) -> void:
	if _paused.has(node):return
	_paused[node]=node.process_mode;node.process_mode=Node.PROCESS_MODE_DISABLED

func _resume() -> void:
	for node: Node in _paused:
		if is_instance_valid(node):node.process_mode=_paused[node]
	_paused.clear()
	game.terrain.diagnostics_pause_streaming=_streaming_paused
	game.set_physics_process(_physics_enabled)
	game.lakes.release_location_reset()
	if game.model_paging!=null:game.model_paging.release_location()

func _idle() -> bool:
	return game.terrain.backend.status()=="idle" and game.terrain.backend.queued()==0 and not game.terrain.pending_edit and not game.terrain.backend.publication_pending() and not game.terrain._manual_save_requested

func _save() -> bool:
	if not await _wait(_idle):return false
	var reply := {"received":false,"ok":false}
	var listener := func(ok:bool):reply.received=true;reply.ok=ok
	game.terrain.save_completed.connect(listener)
	game.terrain.save_world()
	var received := await _wait(func()->bool:return reply.received,60,false)
	if game.terrain.save_completed.is_connected(listener):game.terrain.save_completed.disconnect(listener)
	return received and reply.ok

func _run(state: Dictionary) -> void:
	_streaming_paused=game.terrain.diagnostics_pause_streaming
	game.terrain.diagnostics_pause_streaming=true
	_pause(game.ecosystem);_pause(game.ground_cover)
	if not await _wait(func()->bool:return not game.lakes._busy and game.lakes._builder==null and game.lakes._cached_task<0):
		await _recover("Water preparation did not settle.");return
	_pause(game.lakes)
	if not await _save():await _recover("Pre-reset checkpoint did not complete.");return
	_checkpoint=true
	phase="preparing"
	if game.model_paging!=null and not await _wait(game.model_paging.hold_location):await _recover("Object pages did not settle.");return
	if not await _wait(_idle):await _recover("World work did not settle.");return
	worker=Thread.new()
	if worker.start(game.persistence.location_baselines.load_baseline.bind(state.key,Capture.definition(state.location)))!=OK:await _recover("Location original could not be read.");return
	while worker.is_alive():await get_tree().process_frame
	var original: Dictionary = worker.wait_to_finish();worker=null
	if not _alive():return
	if cancelled or game.terrain.epoch!=_epoch or not original.get("ok",false):await _recover("Location original is unavailable or the reset was cancelled.");return
	var reason := exclusion(state.location)
	if not reason.is_empty():await _recover(reason);return
	var current: Dictionary = game.quests.store.snapshot()
	if current.revision!=state.revision or not game.quests.store.begin_reset(current.revision).ok:await _recover("Quest changed before reset.");return
	_mutated=true
	game.lakes.location_reset_hold=true
	var owned: PackedInt64Array = game.zombies.population.store.authored_identities(state.location.residents)
	game.corpse_loot.retire_location(owned);game.zombies.retire_location(owned)
	await get_tree().physics_frame
	await get_tree().process_frame
	if not _alive():return
	plan=Plan.new()
	var prepared: Dictionary = plan.prepare(Plan.context(game),state.location,original.sections)
	if not prepared.ok:await _recover("Location ownership: "+str(prepared.reason));return
	batch=plan.create_batch()
	if batch.status().phase!="prepared":await _recover("Reset plan is no longer current.");return
	for record: Dictionary in plan.protections:record.target.set_removal_protected(record.id,false)
	phase="restoring"
	while not batch.status().terminal and _alive() and not cancelled:
		batch.advance()
		await get_tree().process_frame
	if not _alive():return
	if cancelled or batch.status().phase!="restored":await _recover("Location reset cancelled or an owner rejected restoration.");return
	for record: Dictionary in plan.protections:record.target.set_removal_protected(record.id,record.original)
	if game.vegetation.falling_trees!=null:game.vegetation.falling_trees.clear_region(state.location.bounds)
	if game.ground_cover.fractures!=null:
		for operation: Dictionary in plan.operations:
			if operation.kind=="ground":game.ground_cover.fractures.refresh_damage(operation.arguments[1])
	game.doors.update(0)
	game.zombies.invalidate_navigation(state.location.bounds)
	phase="publishing"
	var revision: int = game.terrain.backend.native.field_patch_state().revision
	if not game.terrain.republish_native_region(state.location.bounds,revision):await _recover("Local terrain publication was unavailable.");return
	_resume()
	if not await _wait(func()->bool:return not game.terrain.pending_edit,120):await _recover("Local terrain publication did not complete.");return
	if not await _wait(func()->bool:return game._actor_collision_ready(state.location.bounds) and game.lakes.statistics().pending_regions==0 and not game.lakes._busy and game.lakes._builder==null,120):await _recover("Local contacts did not become ready.");return
	phase="saving"
	current=game.quests.store.snapshot()
	if not game.quests.store.finish_reset(current.cycle,true,current.revision).ok:await _recover("Quest activation failed.");return
	game.terrain.changed_since_save=true
	if not await _save():await _recover("Reset save did not complete; reopening the authoritative checkpoint.");return
	_finish(true,"")

func _recover(reason: String) -> void:
	if not _alive():
		if is_instance_valid(game):game.terrain.backend.disable_snapshot_writes("Location reset interrupted")
		return
	if not game.terrain.latest_error.is_empty():reason+=" "+game.terrain.latest_error
	phase="recovering";_resume()
	if not _mutated:
		_finish(false,reason);return
	if not _checkpoint:
		game.terrain.backend.disable_snapshot_writes("Location reset has no verified checkpoint")
		game.terrain.latest_error=reason;_finish(false,reason);return
	game.terrain.recover_native_region()
	var deadline:=Time.get_ticks_msec()+120000
	while _alive() and (game.terrain.epoch==_epoch or not game.terrain.world_ready):
		if Time.get_ticks_msec()>=deadline or not game.terrain.latest_error.is_empty():
			game.terrain.backend.disable_snapshot_writes("Location recovery did not finish")
			game.terrain.latest_error="Location recovery failed; saved checkpoint preserved. "+reason
			_finish(false,game.terrain.latest_error);return
		await get_tree().process_frame
	if not _alive():return
	if not game.terrain.snapshot_restore_ok or not game.terrain.latest_error.is_empty():
		game.terrain.backend.disable_snapshot_writes("Location recovery rejected the saved checkpoint")
		game.terrain.latest_error="Location recovery failed; saved checkpoint preserved. "+reason
		_finish(false,game.terrain.latest_error);return
	_finish(false,reason)

func _finish(ok: bool, reason: String) -> void:
	busy=false;phase="complete" if ok else "cancelled" if cancelled else "failed"
	last_result={"ok":ok,"reason":reason,"phase":phase,"elapsed_us":Time.get_ticks_usec()-_started,"checkpoint":_checkpoint,"mutation_started":_mutated,"operations":plan.operations.size() if plan!=null else 0}
	if batch!=null:last_result["batch"]=batch.status()
	game._show_lake_notice("Quest location restored" if ok else reason)
	completed.emit(last_result)

func _exit_tree() -> void:
	if worker!=null and worker.is_started():worker.wait_to_finish()
