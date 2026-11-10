# SPDX-License-Identifier: 0BSD
extends RefCounted
## Feasibility gate, not an eventual-completion benchmark. Never flush bakes here.
class DeadlineObserver extends Node:
	signal sampled
	var game:Node
	var deadline:int
	var initial_explosions:int
	var result:Dictionary={}
	func _physics_process(_delta:float)->void:
		var tick:=Engine.get_physics_frames()
		if tick<deadline:return
		result={"sample_tick":tick,"deadline_tick":deadline,
			"explosions":game.combat.explosions-initial_explosions,
			"pending_blast_jobs":game.combat.blast_jobs.size(),
			"pending_detonations":game.combat.detonations.size(),
			"terrain_pending":game.terrain.pending_edit,
			"terrain_revision":game.terrain.published_revision,
			"debris_bodies":game.combat.effects.fragments.size()}
		set_physics_process(false)
		sampled.emit()

func run(driver:SceneTree,game:Node,count:int)->Dictionary:
	driver.label="destruction_deadline_preparation"
	var report:={"ok":false,"requested":count,"scope":"Next-tick feasibility in an owned world; no synchronous flush, pacing override or delayed trigger clock. Incomplete work fails; full render/collision parity needs transaction publication identities."}
	if game.combat.barrels.get_ids().size()+count>256:
		report.reason="fixture would exceed the approved barrel placement limit";return report
	var points:=PackedVector3Array()
	var records:=PackedInt32Array()
	var occupied:Dictionary={}
	var side:=ceili(sqrt(float(count)))
	var anchor:Vector3=game.player.global_position+Vector3(0,0,-24)
	# One grounded barrel per 1.5 m grid site; nearby blocks form dense obstructions
	# without intersecting the barrel's 0.72 m footprint or existing authored cells.
	for index in count:
		var desired:=anchor+Vector3((index%side-(side-1)*.5)*1.5,0,(index/side-(side-1)*.5)*1.5)
		var hit:Dictionary=game.structures.blocks.raycast_scene(desired+Vector3.UP*24,desired-Vector3.UP*40,1,[])
		if hit.is_empty():report.reason="fixture ground unavailable";return report
		var point:Vector3=hit.position+Vector3.UP*.02
		if not game._actor_collision_ready(AABB(point-Vector3.ONE*6,Vector3.ONE*12)):
			report.reason="all trigger neighborhoods must be resident before measurement";return report
		points.append(point)
		var cell:=Vector3i(point.floor())+Vector3i(0,3,0)
		if not occupied.has(cell) and game.structures.blocks.get_cell(cell)==0:
			occupied[cell]=true
			records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,game.structures.blocks.encode_block(1,0,index%4)]))
	if not game.structures.blocks.set_cells(records):report.reason="fixture building admission rejected";return report
	var ids:=PackedInt64Array()
	for point:Vector3 in points:
		var id:int=game.combat.barrels.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,point),game.combat.barrels),AABB())
		if id<=0:report.reason="fixture barrel insertion failed";return report
		ids.append(id)
	if not await driver.wait_for(func():
		for point:Vector3 in points:
			if not game._actor_collision_ready(AABB(point-Vector3.ONE*6,Vector3.ONE*12)):return false
		return not game.terrain.pending_edit,20):
		report.reason="fixture publication did not become ready";return report
	await driver.wait_for(func():return false,2)
	var observer:=DeadlineObserver.new();observer.game=game
	observer.process_physics_priority=1000000;observer.set_physics_process(false)
	driver.root.add_child(observer)
	game.combat.destruction_trace.enabled=true
	await RenderingServer.frame_post_draw
	driver.label="destruction_next_tick"
	var trigger_tick:=Engine.get_physics_frames()
	observer.deadline=trigger_tick+1;observer.initial_explosions=game.combat.explosions
	var started:=Time.get_ticks_usec();var accepted:=0
	for id:int in ids:
		if game.combat.damage_barrel(id,50):accepted+=1
	var trigger_us:=Time.get_ticks_usec()-started
	observer.set_physics_process(true)
	await observer.sampled
	report.merge(observer.result)
	report.trigger_tick=trigger_tick;report.trigger_us=trigger_us;report.accepted=accepted
	report.fixture_cells=records.size()/4
	report.next_tick_lower_bound_pass=accepted==count and report.sample_tick==observer.deadline and report.explosions==count and report.pending_blast_jobs==0 and report.pending_detonations==0 and not report.terrain_pending
	# Freeze only after recording the deadline. Preserve queued damage in the save
	# rather than waiting minutes for the old serialized pipeline to hide failure.
	game.combat.set_physics_process(false)
	observer.queue_free()
	await RenderingServer.frame_post_draw
	report.timeline=game.combat.destruction_trace.sample(Engine.get_physics_frames(),Time.get_ticks_usec())
	report.full_publication_parity_verified=false
	report.reason="full next-tick transaction publication is not implemented" if report.next_tick_lower_bound_pass else "current pipeline misses the next-physics-tick deadline"
	driver.label="destruction_deadline_recovery"
	return report
