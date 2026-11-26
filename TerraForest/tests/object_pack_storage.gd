# SPDX-License-Identifier: 0BSD
extends SceneTree
const Packs=preload("res://addons/structures/pack_registry.gd")
const Items=preload("res://addons/player_runtime/item_catalog.gd")
const Scatter=preload("res://addons/structures/outdoor_scatter.gd")
var checks:=0
var failures:=0
class Hud extends RefCounted:
	var inventory: RefCounted
class Host extends Node:
	var structures: Node3D
	var player_hud: RefCounted
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: run.call_deferred()
func host() -> Node:
	var out:=Host.new(); root.add_child(out)
	out.player_hud=Hud.new(); out.player_hud.inventory=Items.create_inventory()
	out.structures=preload("res://addons/structures/structures_world.gd").new(); out.add_child(out.structures); Packs.register(out.structures)
	return out
func run() -> void:
	var game:=host(); var persistence:=preload("res://addons/world_runtime/world_persistence.gd").new()
	var storage:=preload("res://addons/player_runtime/pack_storage.gd").new()
	check(storage.prepare(game,persistence),"manifest container slots register native providers")
	check(storage.stores.size()==7,"seven outdoor container types; tires/litter remain props")
	var saved: Dictionary={}; var index:=0
	for key: String in storage.stores:
		var batch: Node3D=game.structures.model(key)
		var id: int=batch.insert_instance(PackedFloat32Array([1,0,0,index*3,0,1,0,0,0,0,1,0]),AABB())
		var store: RefCounted=storage.stores[key]
		check(id==1 and store.seed_contents(id,PackedInt64Array([225,index+1])),"independent placement #1 storage: "+key)
		storage.collection=batch; storage.store=store
		check(storage.protect(id,true) and not batch.remove_instances(PackedInt64Array([id])),"nonempty container cannot be destroyed/dismantled: "+key)
		saved[key]=store.capture_storage_snapshot(); index+=1
	var structures: PackedByteArray=game.structures.capture_storage_snapshot()
	var reopened:=host(); var second:=preload("res://addons/player_runtime/pack_storage.gd").new()
	check(second.prepare(reopened,preload("res://addons/world_runtime/world_persistence.gd").new()),"fresh native container owners")
	for key: String in saved: check(second.restore_pack(saved[key],key),"restore content bytes: "+key)
	check(reopened.structures.restore_storage_snapshot(structures) and second.restore_protection(true),"restore models then reinstate removal protection")
	index=0
	for key: String in second.stores:
		var store: RefCounted=second.stores[key]; var batch: Node3D=reopened.structures.model(key)
		check(store.snapshot(1).slots[0].count==index+1 and batch.is_removal_protected(1),"same local ids cannot mix contents between models: "+key)
		var inventory: RefCounted=reopened.player_hud.inventory
		var result: Dictionary=store.withdraw(1,inventory,0,index+1,inventory.snapshot().revision,store.snapshot(1).store_revision)
		check(result.ok and not store.requires_protection(1) and batch.set_removal_protected(1,false) and batch.remove_instances(PackedInt64Array([1])),"empty container becomes removable after native transfer: "+key)
		index+=1
	var proposals:=Scatter.proposals(1703,Vector3.ZERO,6,20,[AABB(Vector3(-1,-1,-8),Vector3(2,4,16))])
	check(proposals==Scatter.proposals(1703,Vector3.ZERO,6,20,[AABB(Vector3(-1,-1,-8),Vector3(2,4,16))]) and proposals.size()==20,"deterministic bounded outdoor scatter")
	var clear:=true
	for candidate: Dictionary in proposals: clear=clear and not candidate.bounds.grow(.34).intersects(AABB(Vector3(-1,-1,-8),Vector3(2,4,16)))
	check(clear,"scatter respects explicit access exclusions")
	check(Scatter.near_road(Vector3(0,0,0),1,[{"a":Vector3(-5,0,0),"b":Vector3(5,0,0),"width":4}]) and not Scatter.near_road(Vector3(0,0,5),1,[{"a":Vector3(-5,0,0),"b":Vector3(5,0,0),"width":4}]),"road clearance includes full width and object margin")
	var query: RefCounted=ClassDB.instantiate("NativeStructureQueries")
	var batch: Node3D=game.structures.model(Packs.by_item[826].key)
	var ids:=PackedInt64Array(); var transforms:=PackedFloat32Array()
	for i in 8300:
		ids.append(i+1); transforms.append_array(PackedFloat32Array([1,0,0,(i%20)*.02,0,1,0,0,0,0,1,(i/20)*.02]))
	check(batch.upsert_instances(ids,transforms),"dense inspection fixture uses one native collection")
	var start:=Time.get_ticks_usec(); var dense: Dictionary=query.nearby_models([batch],Vector3.ZERO,24,8)
	check(dense.objects.size()==8 and dense.scanned==8192 and dense.truncated,"native inspection enforces candidate and traversal budgets")
	print("OBJECT_INSPECTION_DENSE records=8300 scanned=",dense.scanned," returned=",dense.objects.size()," us=",Time.get_ticks_usec()-start)
	game.structures.position=Vector3(100,0,0)
	check(query.nearby_models([batch],Vector3.ZERO,24,8).objects.is_empty() and query.nearby_models([batch],Vector3(100,0,0),24,8).objects.size()==8,"inspection honors transformed collection coordinates")
	storage.free(); second.free(); game.free(); reopened.free(); await process_frame
	print("OBJECT_PACK_STORAGE checks=",checks," failures=",failures); quit(1 if failures else 0)
