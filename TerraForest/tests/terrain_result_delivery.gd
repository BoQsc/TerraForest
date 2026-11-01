# SPDX-License-Identifier: 0BSD
extends SceneTree

class Probe extends "res://addons/volumetric_terrain/terrain_world.gd":
	var delivered:Array[Dictionary]=[]
	func _receive(result:Dictionary)->void:
		delivered.append(result)
		if result.get("kind","")=="surface_batch":OS.delay_usec(2000)

class AttackOwner extends Node:
	var terrain:Node
	var tool_view:Dictionary={"attack_identity":0}

class PreparationProbe extends "res://addons/volumetric_terrain/terrain_world.gd":
	var installed:=false
	func _begin_entry(_data:Dictionary)->Dictionary:
		var parent:=Node3D.new()
		parent.visible=false
		var body:=StaticBody3D.new()
		body.collision_layer=0;body.collision_mask=0
		var shape:=CollisionShape3D.new()
		shape.shape=BoxShape3D.new()
		body.add_child(shape);parent.add_child(body)
		OS.delay_usec(2000)
		return {"node":parent,"body":body,"active":false}
	func _prepare_piece()->bool:
		preparation.piece_at+=1
		OS.delay_usec(2000)
		return preparation.piece_at>=2
	func _install(_key:Vector3i,entry:Dictionary)->void:
		installed=true
		_set_active(entry,true)

var checks:=0
var failures:=0

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var probe:=Probe.new()
	probe.initial_loading=false
	var ready:Array[Dictionary]=[]
	for token in 4:ready.append({"kind":"surface_batch","token":token,"epoch":7,"revision":9})
	ready.append({"kind":"edit_chunk","token":40})
	ready.append({"kind":"placement_target","token":41})
	probe._dispatch_results(ready)
	check(probe.delivered.size()==3 and probe._surface_replies.size()==3,"one expensive background callback consumes the soft budget")
	check(probe.delivered[0].token==40 and probe.delivered[1].token==41,"mining and targeting overtake background-only surface replies")
	probe.world_ready=true
	probe._surface_replies.append_array(ready.slice(0,4))
	probe._surface_replies.append_array(ready.slice(0,4))
	check(not probe.request_surface_batch(PackedVector3Array([Vector3.ONE]),100),"deferred replies apply admission backpressure")
	check(not probe.request_surface_page(PackedVector3Array([Vector3.ONE]),Vector2i.ZERO,101),"cached surface pages share admission backpressure")
	probe._surface_replies.resize(3)
	probe._dispatch_results([{"kind":"density_ray","token":42}])
	check(probe.delivered[3].token==42,"new targeting replies also overtake an older surface backlog")
	for step in 2:probe._dispatch_results([])
	check(probe._surface_replies.is_empty() and probe.delivered.size()==7,"remaining replies drain without loss or duplication")
	var surfaces:Array=probe.delivered.filter(func(result:Dictionary)->bool:return result.kind=="surface_batch")
	for token in 4:
		var result:Dictionary=surfaces[token]
		check(result.token==token and result.epoch==7 and result.revision==9,"surface FIFO and revision identity remain unchanged")
	probe._dispatch_results([])
	check(probe.delivered.size()==7,"empty polling never replays a result")
	probe.set_attack_active(true)
	check(probe.backend._input_active() and not probe.foreground_brush,"attack windup defers optional worker I/O without brush streaming restrictions")
	probe.set_brush_active(false)
	check(probe.backend._input_active(),"inactive developer brush cannot clear an active gameplay attack")
	probe.set_brush_active(true)
	probe.set_attack_active(false)
	check(probe.backend._input_active(),"completed gameplay attack cannot clear an active developer brush")
	probe.set_brush_active(false)
	check(not probe.backend._input_active(),"idle interaction releases optional background worker I/O")
	var owner:=AttackOwner.new()
	owner.terrain=probe
	var attack=preload("res://addons/player_runtime/world_attack.gd").new()
	attack.game=owner
	probe.set_attack_active(true)
	owner.tool_view.attack_identity=3
	attack.pending={"identity":3,"contacted":false}
	attack.finish_swing(2,true)
	check(probe.foreground_attack and attack.pending.identity==3,"stale swing completion cannot release another attack's priority")
	owner.tool_view.attack_identity=0
	attack.finish_swing(3,false)
	check(not probe.foreground_attack and not probe.backend._input_active() and attack.pending.is_empty(),"real swing completion releases attack priority")
	probe.set_attack_active(true)
	attack.pending={"identity":4,"contacted":false}
	attack.next_attack=250
	attack.finish_swing(4,true)
	check(not probe.backend._input_active() and attack.next_attack==0 and attack.pending.is_empty(),"cancelled swing releases priority and input debounce")
	probe.set_attack_active(true)
	attack.finish_swing(5,false)
	check(not probe.backend._input_active(),"test-driven animation completion releases priority without a pending inventory attack")
	owner.free()
	probe.free()
	var staging_probe:=PreparationProbe.new()
	root.add_child(staging_probe)
	check(staging_probe.is_inside_tree(),"preparation fixture belongs to a live scene tree")
	staging_probe.main_build_budget_us=1000
	staging_probe.staging.append({"kind":"mesh","key":Vector3i(0,0,16),"epoch":staging_probe.epoch,"stamp":0,"worker_ms":0.0})
	staging_probe._drain_staging()
	var entry:Dictionary=staging_probe.preparation.entry
	check(entry.node.is_inside_tree() and not staging_probe.installed,"empty preparation root attaches before bounded preparation completes")
	check(not entry.node.is_visible_in_tree() and entry.body.collision_layer==0,"unfinished geometry remains hidden and non-colliding")
	staging_probe._drain_staging()
	check(not staging_probe.installed and not entry.node.is_visible_in_tree() and entry.body.collision_layer==0,"partial preparation cannot publish visibility or collision")
	staging_probe._drain_staging()
	check(staging_probe.installed and entry.node.is_visible_in_tree() and entry.body.collision_layer==1,"completed preparation publishes visibility and matching collision together")
	staging_probe.free()
	print("RESULT_DELIVERY ","PASS" if failures==0 else "FAIL"," checks=",checks," failures=",failures)
	quit(1 if failures else 0)
