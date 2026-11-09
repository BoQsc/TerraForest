# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainProbe extends Node:
	var changed_since_save:=false
	var stages:Dictionary={}
	func _record_stage(label:String,milliseconds:float)->void:stages[label]=milliseconds
class AttackProbe extends Node:
	var durability:RefCounted=ClassDB.instantiate("NativeWorldDurability")
	func block_key(cell:Vector3i)->String:return "block:%d:%d:%d"%[cell.x,cell.y,cell.z]
class GameProbe extends Node3D:
	var structures:Dictionary={}
	var terrain:=TerrainProbe.new()
	var world_attack:=AttackProbe.new()
var checks:=0
var failures:=0
var changed:=0
var bounds_changed:=0
var published_bounds:=AABB()
var history_clear_at_publication:=true
var game:GameProbe
var blocks:Node3D
var combat:Node3D
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func install(records:PackedInt32Array)->void:
	check(blocks.set_cells(records),"fixture cells install")
	changed=0;bounds_changed=0;history_clear_at_publication=true
func run()->void:
	game=GameProbe.new();root.add_child(game);game.add_child(game.terrain);game.add_child(game.world_attack)
	blocks=ClassDB.instantiate("NativeBlockWorld");game.add_child(blocks);blocks.set_process(false);game.structures={"blocks":blocks}
	blocks.configure_history(1048576,64)
	combat=preload("res://addons/player_runtime/combat_world.gd").new();game.add_child(combat);combat.set_physics_process(false)
	combat.game=game;combat.add_child(combat.effects);combat.effects.blocks=blocks
	blocks.changed.connect(func():changed+=1)
	blocks.cells_changed.connect(func(bounds:AABB):
		bounds_changed+=1;published_bounds=bounds;history_clear_at_publication=history_clear_at_publication and not blocks.can_undo())
	var word:int=blocks.encode_block(1,0,1)
	var source:=PackedInt32Array([0,3,0,word,1,3,0,word,2,3,0,word])
	install(source)
	var revision:int=blocks.survey_revision_id()
	check(not blocks.erase_cells(source,revision-1) and changed==0 and blocks.get_cell(Vector3i(0,3,0))==word,"stale revision rejects the entire removal without signals")
	var stale:=source.duplicate();stale[7]=blocks.encode_block(1,0,0)
	check(not blocks.erase_cells(stale,revision) and blocks.can_undo(),"changed cell rejects the entire removal and preserves history")
	check(not blocks.erase_cells(source.slice(0,4)+source.slice(0,4),revision),"duplicate expected coordinates reject atomically")
	blocks.set_edit_admission(func(_bounds:AABB)->bool:return false)
	check(not combat.damage_block(Vector3i(0,3,0),word,300,Vector3.ZERO,1) and game.world_attack.durability.record_count()==0,"rejected single demolition does not consume durability")
	check(not blocks.erase_cells(source,revision) and blocks.can_undo() and changed==0,"unavailable admission preserves all cells, history and revision")
	blocks.set_edit_admission(Callable())
	check(blocks.erase_cells(source,revision),"one bounded compare-and-remove accepts unchanged cells")
	check(changed==1 and bounds_changed==1 and history_clear_at_publication and published_bounds==AABB(Vector3(0,3,0),Vector3(3,1,1)),"one publication covers the whole edit after its undo barrier")
	check(blocks.get_cell(Vector3i(0,3,0))==0 and blocks.get_cell(Vector3i(2,3,0))==0 and not blocks.can_undo(),"destruction removes all selected cells and cannot be undone")
	var excessive:=PackedInt32Array()
	for i in 65:excessive.append_array(PackedInt32Array([i,3,0,word]))
	check(not blocks.erase_cells(excessive,blocks.survey_revision_id()),"native removal has a hard 64-cell transaction limit")
	# A real combat batch mixes full destruction, partial damage and a stale cell.
	source=PackedInt32Array([0,3,0,word,1,3,0,word,4,3,0,word,2,3,0,word])
	install(source)
	var jobs:=[{"center":Vector3(.5,3.5,.5),"records":source,"offset":0}]
	combat.blast_jobs.assign(jobs)
	blocks.set_edit_admission(func(_bounds:AABB)->bool:return false)
	combat.step_blasts()
	check(combat.blast_jobs[0].offset==0 and game.world_attack.durability.record_count()==0 and combat.effects.fragments.is_empty(),"rejected blast does not consume cursor, partial damage or debris")
	blocks.set_edit_admission(Callable())
	blocks.set_cells(PackedInt32Array([2,3,0,blocks.encode_block(1,0,0)]));changed=0;bounds_changed=0
	combat.step_blasts()
	check(combat.blast_jobs.is_empty() and changed==1 and bounds_changed==1,"accepted blast publishes once and completes its cursor")
	check(blocks.get_cell(Vector3i(2,3,0))!=0 and blocks.get_cell(Vector3i(4,3,0))==0,"stale replacement is protected and edge damage keeps the original falloff")
	check(combat.effects.fragments.size()==3 and combat.effects.geometry_loads==1 and combat.effects.convex_builds==0,"equal shape/rotation debris shares exact baked geometry without runtime decomposition")
	var first:RigidBody3D=combat.effects.fragments[0].body
	var second:RigidBody3D=combat.effects.fragments[1].body
	check(first.get_child(1).shape==second.get_child(1).shape and first.get_child(0).material_override==second.get_child(0).material_override,"debris shares immutable collision and material resources")
	check(first.mass==5.0 and first.collision_mask==7 and first.continuous_cd and first.linear_velocity.length()>0,"debris mass, collision, CCD and impulse behavior are retained")
	combat.effects.step(.1,false);check(first.freeze,"pause suspends debris")
	combat.effects.step(.1,true);check(not first.freeze,"resume restores debris physics")
	combat.effects.step(8.0,true);check(combat.effects.fragments.is_empty(),"debris lifetime is retained")
	await process_frame
	# Fully persistent cursor semantics, including exactly one partial hit per cell.
	var edge:=Vector3i(5,3,0);var center:=Vector3(1,3.5,.5)
	install(PackedInt32Array([edge.x,edge.y,edge.z,word]))
	combat.blast_jobs.assign([{"center":center,"records":PackedInt32Array([edge.x,edge.y,edge.z,word]),"offset":0}])
	combat.step_blasts()
	check(blocks.get_cell(edge)==word and game.world_attack.durability.damage(game.world_attack.block_key(edge),60)==30 and combat.blast_jobs.is_empty(),"surviving block receives its exact partial damage once")
	var costs:Array=[]
	for count in [1,24,64]:
		var records:=PackedInt32Array()
		for i in count:records.append_array(PackedInt32Array([i%8,10,i/8,word]))
		blocks.set_cells(records)
		var begin:=Time.get_ticks_usec()
		for i in range(0,records.size(),4):
			blocks.set_cells(PackedInt32Array([records[i],records[i+1],records[i+2],0]));blocks.clear_history()
		var legacy_us:=Time.get_ticks_usec()-begin
		blocks.set_cells(records);changed=0;bounds_changed=0;begin=Time.get_ticks_usec()
		var okay:bool=blocks.erase_cells(records,blocks.survey_revision_id())
		var batch_us:=Time.get_ticks_usec()-begin
		check(okay and changed==1 and bounds_changed==1,"batch size %d retains a single publication"%count)
		costs.append({"cells":count,"legacy_us":legacy_us,"batch_us":batch_us})
	print("DESTRUCTION_COST ",JSON.stringify(costs))
	game.free();await process_frame;await process_frame
	print("DESTRUCTION_BATCHES checks=",checks," failures=",failures);quit(1 if failures else 0)
