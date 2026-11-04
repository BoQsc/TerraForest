# SPDX-License-Identifier: 0BSD
extends SceneTree
const Pickups=preload("res://addons/world_runtime/material_pickups.gd")
const Persistence=preload("res://addons/world_runtime/world_persistence.gd")
const Catalog=preload("res://addons/player_runtime/item_catalog.gd")
var checks:=0
var failures:=0
class TerrainFixture extends Node:
	var prepared_snapshot_components:Dictionary={}
	var snapshot_restore_ok:=true
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var floor_body:=StaticBody3D.new();floor_body.collision_layer=1
	var collider:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(200,.2,200);collider.shape=box
	floor_body.add_child(collider);scene.add_child(floor_body);floor_body.position.y=-.1
	var pickups:=Pickups.new();scene.add_child(pickups)
	var provider:=Persistence.new();var inventory:=Catalog.create_inventory()
	inventory.register_item(9001,19)
	check(pickups.prepare(provider,inventory) and pickups.configure_physics(RID(),false),"native physics and original pickup stores initialize together")
	check(pickups.physics_enabled,"physical dropping defaults on")
	# Settings round trip uses a unique disposable file, never player preferences.
	var config_path:="user://drop_settings_%d.cfg"%OS.get_process_id()
	pickups.physics_settings_path=config_path;pickups.persist_physics_settings=true
	pickups.set_physics_enabled(false)
	var config:=ConfigFile.new()
	check(config.load(config_path)==OK and not config.get_value("items","physical_drops",true),"off preference persists")
	var reopened:=Pickups.new();scene.add_child(reopened);reopened.physics_settings_path=config_path
	check(reopened.prepare(Persistence.new()) and reopened.configure_physics(RID(),true) and not reopened.physics_enabled,"a fresh session loads the saved off preference")
	reopened.free()
	pickups.set_physics_enabled(true);config.load(config_path)
	check(config.get_value("items","physical_drops",false),"on preference persists")
	DirAccess.remove_absolute(config_path);pickups.persist_physics_settings=false
	await physics_frame;await physics_frame
	inventory.grant(8,1,inventory.snapshot().revision);inventory.wear_tool(0,9,inventory.snapshot().revision)
	var before:Dictionary=inventory.snapshot().slots[0]
	var result:=pickups.drop_stack(inventory,0,inventory.snapshot().revision,Vector3(0,2,0),1,true,Vector3(.8,.25,0))
	check(result.ok and inventory.snapshot().slots[0].count==0 and pickups.physics.statistics().active==1,"physical transaction transfers one worn rifle atomically")
	var handle:int=pickups.stores[0].resolve_identity(result.id)
	var start:Vector3=pickups.stores[0].get_position(handle)
	for i in 12:
		pickups.step_physics(1.0/60,true,func(_bounds:AABB):return true)
		await physics_frame
	var moving:Vector3=pickups.stores[0].get_position(handle)
	check(moving.y<start.y and moving.x>start.x,"engine gravity and drop impulse move the native pickup")
	# Capture in flight, discard all physics RIDs, restore position and velocity.
	var fixture:=TerrainFixture.new();scene.add_child(fixture);provider._terrain=fixture
	var sections:Dictionary=provider._capture().sections
	check(sections.pickup_physics.size()==48,"one active body adds one bounded motion record")
	pickups.physics.reset();provider._restore(sections,1)
	handle=pickups.stores[0].resolve_identity(result.id)
	check(fixture.snapshot_restore_ok and pickups.stores[0].get_position(handle)==moving,"compound restore preserves exact in-flight pickup position")
	var paused:Vector3=moving
	for i in 8:
		pickups.step_physics(1.0/60,false,func(_bounds:AABB):return true);await physics_frame
	check(pickups.stores[0].get_position(handle)==paused,"paused motion remains registered and preserves position")
	for i in 8:
		pickups.step_physics(1.0/60,true,func(_bounds:AABB):return false);await physics_frame
	check(pickups.stores[0].get_position(handle)==paused,"unready collision suspends the body without losing the item")
	var minimum:=100.0;var bounced:=false;var last_y:float=moving.y
	for i in 150:
		pickups.step_physics(1.0/60,true,func(_bounds:AABB):return true);await physics_frame
		var point:Vector3=pickups.stores[0].get_position(handle)
		minimum=minf(minimum,point.y)
		if last_y<.3 and point.y>last_y+.002:bounced=true
		last_y=point.y
	var landed:Vector3=pickups.stores[0].get_position(handle)
	check(minimum>.10 and absf(landed.y-.17)<.06,"continuous collision prevents tunnelling and rests on the actual floor")
	check(bounced,"floor contact produces a real bounce")
	check(pickups.physics.statistics().sleeping==1,"resting physics body goes to sleep")
	var collected:=pickups.collect_near(landed,inventory,func(_p:Vector3):return true)
	check(collected.ok and inventory.snapshot().slots[0]==before and pickups.physics.statistics().active==0,"E collection retains exact wear and retires the physical body")
	# Capacity rejection must happen before the inventory debit.
	inventory.consume(0,1,inventory.snapshot().revision)
	var ids:Array=Catalog.names().keys();ids.append(9001)
	for item:int in ids:
		inventory.grant(item,1,inventory.snapshot().revision)
		var row:Dictionary=inventory.snapshot().slots[0]
		var dropped:=pickups.drop_stack(inventory,0,inventory.snapshot().revision,Vector3(20,2,0),1,true,Vector3(.5,.2,0))
		var recovered:=pickups.collect_near(Vector3(20,2,0),inventory,func(_p:Vector3):return true)
		check(dropped.ok and recovered.ok and inventory.snapshot().slots[0]==row and pickups.physics.statistics().active==0,"item %d supports physical drop and exact recovery without special registration"%item)
		inventory.consume(0,1,inventory.snapshot().revision)
	inventory.grant(601,65,inventory.snapshot().revision)
	for i in 64:
		var drop:=pickups.drop_stack(inventory,0,inventory.snapshot().revision,Vector3(i,5,0),1,true,Vector3(0,.2,0))
		if not drop.ok:check(false,"pool admits body %d"%i)
	var saved:PackedByteArray=inventory.capture_storage_snapshot()
	check(not pickups.drop_stack(inventory,0,inventory.snapshot().revision,Vector3.ZERO,1,true).ok and inventory.capture_storage_snapshot()==saved,"full awake pool retains item and inventory revision")
	var motion:PackedByteArray=pickups.physics.capture_storage_snapshot();var corrupt:=motion.duplicate();corrupt[0]=0
	check(not pickups.physics.restore_storage_snapshot(corrupt) and pickups.physics.capture_storage_snapshot()==motion,"corrupt motion snapshots leave live bodies intact")
	# Missing section is the explicit migration default for old worlds.
	sections.erase("pickup_physics");provider._restore(sections,2)
	check(pickups.physics.statistics().active==0,"old saves without physical motion load with empty physics state")
	scene.free();await process_frame
	print("PHYSICAL_ITEM_DROPS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
