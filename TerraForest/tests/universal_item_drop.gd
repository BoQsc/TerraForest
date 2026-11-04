# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog=preload("res://addons/player_runtime/item_catalog.gd")
const Pickups=preload("res://addons/world_runtime/material_pickups.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
var failures:=0
var checks:=0
class TerrainFixture extends Node:
	var prepared_snapshot_components:Dictionary={}
	var snapshot_restore_ok:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func schema()->RefCounted:
	var inventory:=Catalog.create_inventory()
	# Future items have no name, baked art or entry in the legacy pickup list.
	inventory.register_item(9001,27)
	inventory.register_item(9002,1);inventory.register_durable(9002,123)
	return inventory
func run()->void:
	var inventory:=schema()
	var persistence:=Persistence.new()
	var pickups:=Pickups.new();root.add_child(pickups)
	check(pickups.prepare(persistence,inventory),"pickup containers inherit the exact inventory schema")
	var restore_fixture:=TerrainFixture.new();root.add_child(restore_fixture);persistence._terrain=restore_fixture
	var ids:Array=Catalog.names().keys();ids.append_array([9001,9002])
	var points:Dictionary={};var expected:Dictionary={};var identities:Dictionary={}
	for index in ids.size():
		var item:int=ids[index]
		var granted:Dictionary=inventory.grant(item,1,inventory.snapshot().revision)
		check(granted.ok,"catalog item %d can enter inventory"%item)
		if not granted.ok:continue
		var row:Dictionary=inventory.snapshot().slots[0]
		if row.max_durability>0:
			check(inventory.wear_tool(0,7,inventory.snapshot().revision).ok,"item %d has wear before dropping"%item)
		if item==401:
			check(inventory.exchange_water(0,false,inventory.snapshot().revision,123456),"bucket has exact partial water metadata")
		expected[item]=inventory.snapshot().slots[0]
		points[item]=Vector3(index*8,2,0)
		var before:Dictionary=inventory.snapshot()
		var dropped:=pickups.drop_one(inventory,0,before.revision,points[item])
		check(dropped.ok and dropped.get("item")==item and inventory.snapshot().slots[0].count==0,"item %d drops without any per-item opt-in"%item)
		if not dropped.ok:continue
		identities[item]=dropped.id
		var aimed:=pickups.aimed(points[item]-Vector3.RIGHT,points[item]+Vector3.RIGHT,func(_p:Vector3):return true)
		check(aimed.ok and aimed.item==item and pickups.item_name(aimed.item)==Catalog.item_name(item),"item %d retains its aimed pickup identity and name"%item)
		var saved:PackedByteArray=inventory.capture_storage_snapshot()
		check(not pickups.drop_one(inventory,0,before.revision,Vector3.ZERO).ok and inventory.capture_storage_snapshot()==saved,"stale drop cannot duplicate item %d"%item)
	var sections:Dictionary=persistence._capture().sections
	check(sections.size()==(Pickups.ITEMS.size()+1)*2,"future items use two fixed save sections instead of growing provider count")
	var restored:=Pickups.new();root.add_child(restored)
	var restored_provider:=Persistence.new()
	check(restored.prepare(restored_provider,schema()),"fresh pickup providers initialize with the same future schema")
	restored_provider._terrain=restore_fixture
	restored_provider._restore(sections,1)
	check(restore_fixture.snapshot_restore_ok,"compound restore accepts all dropped item metadata")
	for item:int in identities:
		var batch:=restored.store_item(item)
		var handle:int=restored.stores[batch].resolve_identity(identities[item])
		check(handle>0 and restored.stores[batch].get_position(handle)==points[item],"item %d retains persistent identity and position"%item)
		var collected:=restored.collect_aimed(points[item]-Vector3.RIGHT,points[item]+Vector3.RIGHT,inventory,func(_p:Vector3):return true)
		check(collected.ok and inventory.snapshot().slots[0]==expected[item],"item %d recollects exact quantity, wear and water after reload"%item)
		if inventory.snapshot().slots[0].count>0:inventory.consume(0,1,inventory.snapshot().revision)
		check(not restored.collect_near(points[item],inventory,func(_p:Vector3):return true).ok,"item %d cannot be collected twice"%item)
	var future_point:=Vector3(-10,2,0)
	check(restored.spawn(9001,future_point)>0,"future authored items inherit the same native schema")
	check(restored.collect_near(future_point,inventory,func(_p:Vector3):return true).ok and inventory.snapshot().slots[0].item==9001,"future authored item recollects its real identity")
	inventory.consume(0,1,inventory.snapshot().revision)
	check(inventory.grant(9001,27,inventory.snapshot().revision).ok,"future item obeys its custom stack limit")
	var stack_drop:=restored.drop_stack(inventory,0,inventory.snapshot().revision,future_point,13)
	check(stack_drop.ok and inventory.snapshot().slots[0].count==14,"universal pickup transfers a requested stack quantity")
	var incompatible:RefCounted=ClassDB.instantiate("NativePlayerInventory");incompatible.register_item(101,999)
	check(not restored.collect_near(future_point,incompatible,func(_p:Vector3):return true).ok and restored.stores[0].statistics().active==1,"schema rejection preserves the entire world stack")
	check(restored.collect_near(future_point,inventory,func(_p:Vector3):return true).ok and inventory.snapshot().slots[0].count==27,"stack recollection conserves every unit")
	for i in 4096:restored.stores[0].spawn(Vector3(i,10,0),Vector3.ZERO)
	var before_capacity:PackedByteArray=inventory.capture_storage_snapshot()
	check(not restored.drop_one(inventory,0,inventory.snapshot().revision,Vector3.ZERO).ok and inventory.capture_storage_snapshot()==before_capacity,"full universal store preserves inventory contents and revision")
	# New section absence in old worlds means empty universal storage.
	sections.erase("pickups_0");sections.erase("pickup_stacks_0")
	restored_provider._restore(sections,2)
	check(restored.stores[0].statistics().active==0,"old saves without universal drops restore empty defaults")
	pickups.free();restored.free();restore_fixture.free()
	print("UNIVERSAL_ITEM_DROP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
