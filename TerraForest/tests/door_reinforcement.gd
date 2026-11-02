# SPDX-License-Identifier: 0BSD
extends SceneTree

const Locks=preload("res://addons/structures/door_locks.gd")
const Visual=preload("res://addons/structures/door_reinforcement.gd")
const Generation=preload("res://addons/structures/door_reinforcement_generation.gd")
var checks:=0
var failures:=0

class Host extends Node3D:
	var doors=preload("res://addons/structures/door_interaction.gd").new()
	var _initial_generation_spawn:=Vector3.ZERO
	var terrain:Dictionary={"changed_since_save":false}

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func _initialize()->void:run.call_deferred()

func run()->void:
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	inventory.register_item(213,999)
	var locks:=Locks.new();var other:=Locks.new()
	check(locks.store!=null and other.store!=null,"native lock-only ledgers configure")
	check(locks.seed(1,180,1703) and other.seed(1,180,1703),"different door collections can own the same placement identity")
	var original:=locks.capture_storage_snapshot()
	check(locks.validate_snapshot(original) and original.size()==48,"one reinforced door uses a compact native binary lock record")
	var missing:=locks.attempt(1,inventory)
	check(not missing.ok and missing.reason=="missing_lockpick" and locks.capture_storage_snapshot()==original,"missing lockpick cannot unlock or change lock state")
	check(locks.damage(1,61).ok and locks.store.lock_state(1).remaining==119,"weapon damage reduces reinforcement health")
	check(other.store.lock_state(1).remaining==180,"damage never leaks between door namespaces")
	var partial:=locks.capture_storage_snapshot();var reopened:=Locks.new()
	check(reopened.restore_storage_snapshot(partial) and reopened.store.lock_state(1).remaining==119,"partially broken reinforcement restores exactly")
	check(reopened.damage(1,119).opened and not reopened.store.is_locked(1),"last hit removes the lock without requiring door destruction")
	check(reopened.capture_storage_snapshot().size()==16,"removed reinforcement leaves no stale lock record")
	check(locks.restore_storage_snapshot(original),"full reinforcement can restore its original state")
	var before:int=inventory.snapshot().revision
	check(inventory.grant(213,64,before).ok,"test player has lockpicks")
	var broke:=false;var opened:=false
	for candidate in 64:
		var trial:=Locks.new();trial.seed(1,180,candidate)
		var response:=trial.attempt(1,inventory)
		broke=broke or response.broken_pick;opened=opened or response.opened
		if broke and opened:break
	check(broke and opened,"native pick attempts cover both breakage and successful unlocking")
	var contaminated:=Locks.new();contaminated.store.seed_contents(2,PackedInt64Array([213,1]))
	check(not locks.validate_snapshot(contaminated.capture_storage_snapshot()),"door-lock persistence rejects hidden container contents")
	locks.forget(1);check(not locks.store.is_locked(1),"removing a door forgets its reinforcement")
	var host:=Node3D.new();root.add_child(host)
	var collection:Node3D=ClassDB.instantiate("NativeStaticBatch");host.add_child(collection)
	var mesh:=BoxMesh.new();mesh.size=Vector3(1,2,.14)
	check(collection.configure_asset("test/door",mesh) and collection.upsert_instances(PackedInt64Array([7]),PackedFloat32Array([1,0,0,0,0,1,0,0,0,0,1,0])),"actual native door placement is available")
	var visual:=Visual.new();host.add_child(visual);visual.configure(collection,locks,AABB(Vector3(0,0,-.07),Vector3(1,2,.14)))
	locks.seed(7,180,1703);visual._process(0)
	check(visual.shown.get(7,0)==3 and not visual.is_processing(),"full lock renders three shared batched boards and then idles")
	locks.damage(7,61);visual._process(0)
	check(visual.shown.get(7,0)==2 and visual.batches[3].get_ids().is_empty(),"damage removes one visible reinforcement stage")
	locks.damage(7,60);visual._process(0)
	check(visual.shown.get(7,0)==1,"last remaining board reflects remaining lock health")
	locks.damage(7,59);visual._process(0)
	check(not visual.shown.has(7) and not collection.get_instance(7).is_empty(),"broken reinforcement vanishes while the original door remains")
	locks.seed(7,180,1703);visual._process(0)
	var region:PackedByteArray=collection.capture_region(Vector3i.ZERO)
	check(collection.unload_region(region),"authoritative door region retires")
	visual._process(0)
	check(not visual.shown.has(7) and locks.store.is_locked(7),"paging hides boards without losing saved lock state")
	check(collection.restore_region(region),"authoritative door region returns")
	visual._process(0)
	check(visual.shown.get(7,0)==3,"paging restores derived boards without reseeding locks")
	collection.remove_instances(PackedInt64Array([7]));visual._process(0)
	check(not visual.shown.has(7),"retired door residency removes its derived visual")
	host.free()
	generation()
	print("DOOR_REINFORCEMENT checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)

func generation()->void:
	var host:=Host.new();root.add_child(host);host.add_child(host.doors)
	var catalog=preload("res://addons/structures/expansion_catalog.gd")
	var house:Resource=catalog.asset("house_c1")
	var lots:Array=[]
	for index in 64:lots.append({"asset":house,"origin":Vector3i((index%8)*40,64,(index/8)*40),"rotation":index%4})
	var selected:=Generation.candidates(lots,1703,Vector3.ZERO)
	check(selected.size()>0 and selected.size()<16 and selected==Generation.candidates(lots,1703,Vector3.ZERO),"rare reinforced homes are deterministic across all four rotations")
	var spawn:=selected[0].origin+Vector3.UP
	check(Generation.candidates(lots,1703,spawn).size()==selected.size()-1,"the entire starting house stays unlocked")
	check(Generation.candidates([{"asset":catalog.asset("trader_t1"),"origin":Vector3i.ZERO,"rotation":0}],1703,Vector3.INF).is_empty(),"trader and essential civic access are never reinforced")
	var collection:Node3D=ClassDB.instantiate("NativeStaticBatch");host.add_child(collection)
	var locks:=Locks.new();var state:RefCounted=ClassDB.instantiate("NativeHingedDoors")
	var bounds:=AABB(Vector3(0,0,-.07),Vector3(1,2.2,.14))
	check(collection.configure_asset(Generation.DOOR,BoxMesh.new()) and state.configure(bounds,Vector3.ZERO,90),"generated lock fixture has native door owners")
	host.doors.types[Generation.DOOR]={"collection":collection,"locks":locks,"state":state,"definition":{"durability":{"health":90}}}
	var identity:=0
	for pose:Transform3D in selected:
		identity+=1
		var values:=PackedFloat32Array()
		for row in 3:
			for column in 3:values.append(pose.basis[column][row])
			values.append(pose.origin[row])
		collection.upsert_instances(PackedInt64Array([identity]),values)
	collection.set_removal_protected(1,true)
	var seeded:=Generation.seed_generated(host,lots,1703)
	check(seeded.ok and seeded.locked.size()==selected.size()-1 and not locks.store.is_locked(1),"generation resolves exact door transforms and respects protected placements")
	var visual:=Visual.new();host.add_child(visual);visual.configure(collection,locks,bounds)
	for frame in 8:visual._process(0)
	var rotations_ok:=true
	for placed:int in seeded.locked:
		var expected:Transform3D=host.doors._pose(collection.get_instance(placed))*visual.fit
		var actual:Transform3D=host.doors._pose(visual.batches[3].get_instance(placed))
		rotations_ok=rotations_ok and expected.is_equal_approx(actual)
	check(rotations_ok,"reinforcement preserves rotated and scaled door transforms without transposing axes")
	host.free()
