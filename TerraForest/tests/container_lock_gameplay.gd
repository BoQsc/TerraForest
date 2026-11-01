# SPDX-License-Identifier: 0BSD
extends SceneTree
const Rules=preload("res://addons/player_runtime/container_rules.gd")
class Collection extends Node3D:
	var protection:Dictionary={}
	var identities:=PackedInt64Array([10,20])
	func get_ids()->PackedInt64Array:return identities
	func placement_for_body(_body:RID)->int:return 10
	func set_removal_protected(id:int,value:bool)->bool:protection[id]=value;return true
	func is_removal_protected(id:int)->bool:return protection.get(id,false)
	func get_instance(id:int)->Dictionary:return {"id":id} if id in identities else {}
class Game extends Node:
	var player_hud=preload("res://addons/player_runtime/player_hud.gd").new()
	var storage=preload("res://addons/player_runtime/storage.gd").new()
	var camera:=Camera3D.new()
	var terrain:Dictionary={"world_ready":true,"pending_edit":false,"changed_since_save":false}
	var world_vehicle:Dictionary={"driving":false}
	var app_focused:=true
	var loading_active:=false
	var shutdown_requested:=false
	var fly:=false
	var equipped_tool:=2
	var notice:=""
	func _clear_motion()->void:pass
	func _show_lake_notice(text:String)->void:notice=text
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true);ProjectSettings.set_setting("terraforest/offscreen_session",true)
	run.call_deferred()
func run()->void:
	var game:=Game.new();root.add_child(game);game.add_child(game.camera);game.add_child(game.player_hud)
	var collection:=Collection.new();game.add_child(collection)
	var ui=game.storage;ui.game=game;ui.collection=collection;ui.store=ClassDB.instantiate("NativeContainerStore")
	var inventory:RefCounted=game.player_hud.inventory
	check(ui.store.configure(inventory,Rules.CAPACITY,16,Rules.PICK_ITEM),"real player catalog admits lockpick schema")
	game.add_child(ui);game.player_hud.equip(1)
	var hit:Dictionary={"collider":collection,"rid":RID()}
	check(ui.store.seed_contents(10,PackedInt64Array([201,7])) and ui.store.seed_lock(10,180,8) and ui.protect(10,true),"stocked locked chest fixture admitted")
	var before:PackedByteArray=ui.store.capture_storage_snapshot()
	check(ui.try_open(hit) and not ui.opened and not game.player_hud.inventory_open and "lockpick" in game.notice,"E handles missing key without opening UI or falling through to other interactions")
	check(ui.store.capture_storage_snapshot()==before and "Unlock" in ui.prompt(10),"failed unlock preserves contents and advertises both entry choices")
	var attack=preload("res://addons/player_runtime/world_attack.gd").new();attack.game=game;attack.durability=ClassDB.instantiate("NativeWorldDurability")
	var durability_before:PackedByteArray=attack.durability.capture_storage_snapshot()
	var target:Dictionary={"kind":"model","key":"model:storage/wooden_chest/v1:10","id":10,"collection":collection,"asset":"storage/wooden_chest/v1","health":90,"material":"wood","name":"Wooden chest"}
	var wear:int=inventory.snapshot().slots[1].wear
	for index in 6:
		check(attack.apply_target(target) and ui.store.is_locked(10)==(index<5) and ui.store.lock_state(10).remaining==maxi(0,150-index*30),"actual attack adapter hit %d damages lock at 30 points"%(index+1))
	check(inventory.snapshot().slots[1].wear==wear+6 and game.terrain.changed_since_save,"forcing lock charges tool wear and marks save dirty")
	check(attack.durability.capture_storage_snapshot()==durability_before and ui.store.has_contents(10) and collection.is_removal_protected(10),"forced entry neither destroys chest nor clears supplies/removal protection")
	check("Lock broken" in game.notice and not ui.opened and not target.destroyed,"final blow leaves player in game rather than opening a modal")
	check(ui.try_open(hit) and ui.opened and game.player_hud.inventory_open,"next E opens newly forced chest")
	var key:=InputEventKey.new();key.physical_keycode=KEY_E;key.pressed=true;ui._input(key)
	check(not ui.opened and not game.player_hud.inventory_open,"E closes container after forced entry")
	check(not attack.apply_target(target) and ui.store.snapshot(10).slots[0].count==7,"continued swings cannot destroy a now-unlocked stocked chest")
	inventory.grant(104,1,inventory.snapshot().revision)
	var crafting=preload("res://addons/player_runtime/crafting.gd")
	check(crafting.craft(inventory,crafting.RECIPES.size()-1,1,inventory.snapshot().revision).ok and inventory.can_afford(PackedInt64Array([213,3]),inventory.snapshot().revision).ok,"ordinary crafting converts one metal into three lockpicks")
	var trader=preload("res://addons/player_runtime/trader_inventory.gd").new()
	inventory.grant(601,8,inventory.snapshot().revision)
	check(trader.exchange(inventory,213,1,true,inventory.snapshot().revision,trader.stock.snapshot().revision).ok,"normal trader exchange sells a lockpick")
	var chosen:=-1
	for seed in 32:
		var probe:RefCounted=ClassDB.instantiate("NativeContainerStore");probe.configure(inventory,1,16,213);probe.seed_lock(10,180,seed)
		var test_player:RefCounted=ClassDB.instantiate("NativePlayerInventory");test_player.register_item(213,999);test_player.grant(213,1,0)
		if probe.attempt_unlock(10,test_player,test_player.snapshot().revision,probe.snapshot(10).store_revision).opened:chosen=seed;break
	check(chosen>=0 and ui.store.seed_lock(10,180,chosen),"deterministic successful-pick fixture selected without altering player's items")
	var player_before:PackedByteArray=inventory.capture_storage_snapshot()
	check(ui.try_open(hit) and ui.opened and not ui.store.is_locked(10) and inventory.capture_storage_snapshot()==player_before,"one E unlocks and opens with reusable pick")
	ui.close()
	check(preload("res://addons/player_runtime/item_icons.gd").texture(213)!=null and load("res://addons/player_runtime/art/drops/213.res") is Mesh,"lockpick has imported icon and baked world-drop mesh")
	generation_checks(inventory)
	game.free()
	print("CONTAINER_LOCK_GAMEPLAY ",JSON.stringify({"checks":checks,"failures":failures,"scope":"Real native stores, HUD, storage and attack adapter; fake picking/collection, not populated-world or animation proof"}))
	quit(1 if failures else 0)
func generation_checks(inventory:RefCounted)->void:
	var collection:=Collection.new();collection.identities.clear()
	for identity in range(1,101):collection.identities.append(identity)
	var ui=preload("res://addons/player_runtime/storage.gd").new();ui.collection=collection;ui.store=ClassDB.instantiate("NativeContainerStore");ui.store.configure(inventory,Rules.CAPACITY,16,Rules.PICK_ITEM)
	var result:Dictionary=Rules.seed_generated(ui,1703)
	check(result.ok and result.locked.size()>5 and result.locked.size()<35,"new-world rules select a minority of 100 generated chests")
	var valid:=true
	for identity in result.locked:valid=valid and ui.store.has_contents(identity) and ui.store.lock_state(identity).maximum==180 and collection.is_removal_protected(identity)
	check(valid,"every generated lock has doubled health, actual supplies and removal protection")
	var clone=preload("res://addons/player_runtime/storage.gd").new();clone.collection=collection;clone.store=ClassDB.instantiate("NativeContainerStore");clone.store.configure(inventory,Rules.CAPACITY,16,Rules.PICK_ITEM)
	var repeat:Dictionary=Rules.seed_generated(clone,1703)
	check(repeat.locked==result.locked and clone.store.capture_storage_snapshot()==ui.store.capture_storage_snapshot(),"generation is deterministic across separate stores")
	ui.free();clone.free();collection.free()
