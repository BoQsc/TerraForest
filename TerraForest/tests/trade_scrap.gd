# SPDX-License-Identifier: 0BSD
extends SceneTree
const Trade=preload("res://addons/player_runtime/trader_inventory.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:
	root.set_flag(Window.FLAG_NO_FOCUS,true)
	run.call_deferred()
class Collection extends Node3D:
	var ids:=PackedInt64Array(range(1,21))
	func get_ids()->PackedInt64Array:return ids
	func stats()->Dictionary:return {"last_identity":20}
	func get_instance(id:int)->PackedFloat32Array:return PackedFloat32Array([1,0,0,100+id,0,1,0,0,0,0,1,100])
class Region extends RefCounted:
	func get_plan()->Dictionary:return {"places":[{"id":30,"position":Vector3(100,0,100)}]}
class World extends Node:
	var loading_active:=false
	var shutdown_requested:=false
	var terrain:Dictionary={"world_ready":true,"pending_edit":false,"changed_since_save":false,"backend":{"world_seed":1703,"readonly_snapshot":false}}
	var generated_region:Dictionary={"store":Region.new()}
class Storage extends Node:
	var collection:Node3D
	var store:RefCounted
	var game:Node
	func protect(_id:int,_enabled:bool)->bool:return true
func run()->void:
	var hud:=preload("res://addons/player_runtime/player_hud.gd").new()
	check(hud.prepare(),"player schema admits salvage without native format changes")
	var player:RefCounted=hud.inventory
	var storage:=Storage.new();root.add_child(storage);storage.game=World.new();storage.add_child(storage.game)
	storage.collection=Collection.new();storage.add_child(storage.collection)
	storage.store=ClassDB.instantiate("NativeContainerStore");storage.store.configure(player,4096,16,213)
	var seeded:Dictionary=preload("res://addons/player_runtime/container_rules.gd").seed_generated(storage,1703)
	check(seeded.ok and seeded.containers==20,"ordinary generator stocks all twenty chests")
	var full:=true
	for id in storage.collection.get_ids():full=full and storage.store.has_contents(id)
	check(full,"unlocked chests contain salvage and locked bundles remain stocked")
	var before:PackedByteArray=storage.store.capture_storage_snapshot()
	var migration:=preload("res://addons/player_runtime/town_loot.gd").new()
	for tick in 8:migration.step(storage)
	check(migration.complete and storage.store.capture_storage_snapshot()==before,"existing contents survive the one-time town pass")
	var ledger:PackedByteArray=migration.capture_snapshot()
	check(migration.validate_snapshot(ledger) and not migration.validate_snapshot(ledger.slice(0,ledger.size()-1)),"one-time ledger validates bounded complete records")
	var restored:=preload("res://addons/player_runtime/town_loot.gd").new();restored.restore_snapshot(ledger)
	check(restored.complete and restored.capture_snapshot()==ledger,"one-time marker survives fresh-instance save restoration")
	var empty_storage:=Storage.new();root.add_child(empty_storage);empty_storage.game=World.new();empty_storage.add_child(empty_storage.game)
	empty_storage.collection=Collection.new();empty_storage.add_child(empty_storage.collection)
	empty_storage.store=ClassDB.instantiate("NativeContainerStore");empty_storage.store.configure(player,4096,16,213)
	empty_storage.store.seed_contents(1,PackedInt64Array([102,7]))
	var upgrade:=preload("res://addons/player_runtime/town_loot.gd").new()
	for tick in 8:upgrade.step(empty_storage)
	check(upgrade.complete and empty_storage.store.has_contents(2),"old empty town chests receive a one-time scrap bundle")
	check(empty_storage.store.snapshot(1).slots[0].item==102 and empty_storage.store.snapshot(1).slots[0].count==7,"existing player contents are preserved")
	for slot in 16:
		var contents:Dictionary=empty_storage.store.snapshot(2)
		if contents.slots[slot].count>0:empty_storage.store.withdraw(2,player,slot,contents.slots[slot].count,player.snapshot().revision,contents.store_revision)
	var emptied:PackedByteArray=empty_storage.store.capture_storage_snapshot()
	var loaded:=preload("res://addons/player_runtime/town_loot.gd").new();loaded.restore_snapshot(upgrade.capture_snapshot());loaded.step(empty_storage)
	check(empty_storage.store.capture_storage_snapshot()==emptied,"looted chest does not refill after one-time marker restoration")
	empty_storage.collection.ids=PackedInt64Array([21]);loaded.rescan()
	for tick in 3:loaded.step(empty_storage)
	check(not empty_storage.store.has_contents(21),"chests placed after the initial identity bound receive no free loot")
	empty_storage.collection.ids=PackedInt64Array([19]);loaded.visited.erase(19);loaded.rescan()
	for tick in 3:loaded.step(empty_storage)
	check(loaded.visited.has(19),"later paging can visit an original chest below the saved bound")
	empty_storage.free()
	var supply:PackedInt64Array=preload("res://addons/player_runtime/salvage_catalog.gd").supplies(1703,4)
	check(supply==preload("res://addons/player_runtime/salvage_catalog.gd").supplies(1703,4),"scrap bundles are deterministic")
	player.grant_items(PackedInt64Array([224,3,225,2,226,2,227,4,601,200]),player.snapshot().revision)
	var recipes:Array=preload("res://addons/player_runtime/crafting.gd").RECIPES
	for index in range(recipes.size()-4,recipes.size()):
		check(preload("res://addons/player_runtime/crafting.gd").craft(player,index,1,player.snapshot().revision).ok,"salvage recycling recipe "+str(index))
	var trader:=Trade.new()
	var ui:=preload("res://addons/player_runtime/trader_panel.gd").new();root.add_child(ui)
	check(ui.open_for(trader,player,func():return true),"two-list shop opens with live reach permission")
	ui.quantity.get_line_edit().text="3"
	var index:=0
	for row in ui.rows.item_count:
		if ui.rows.get_item_metadata(row)==102:index=row
	var payload:Dictionary=ui.drag_offer("merchant",index)
	var wallet:int=Trade.count(player,601)
	var wood:int=Trade.count(player,102)
	check(ui.accepts_offer("player",payload) and not ui.accepts_offer("merchant",payload),"only cross-list drops accept this shop's offer")
	ui.drop_offer("player",payload)
	check(Trade.count(player,102)==wood+3 and Trade.count(player,601)==wallet-12,"drag purchase pays exact fixed price and adds selected quantity")
	var snapshot:PackedByteArray=player.capture_storage_snapshot();ui.drop_offer("player",payload)
	check(player.capture_storage_snapshot()==snapshot,"replayed stale drop cannot duplicate items or coins")
	for row in ui.selling.item_count:
		if ui.selling.get_item_metadata(row)==102:index=row
	ui.drop_offer("merchant",ui.drag_offer("player",index))
	check(Trade.count(player,102)==wood and Trade.count(player,601)==wallet-6,"drag sale applies the bid and transfers finite goods")
	ui.search.text="wire";ui.refresh()
	check(ui.rows.item_count==1 and ui.rows.get_item_metadata(0)==226,"search filters the item listings")
	ui.search.text="";ui.refresh();ui.quantity.value=1
	var cancelled:Dictionary=ui.drag_offer("merchant",0);snapshot=player.capture_storage_snapshot()
	check(player.capture_storage_snapshot()==snapshot,"starting and cancelling a drag changes nothing")
	ui.close();ui.open_for(trader,player,func():return true)
	check(not ui.accepts_offer("player",cancelled),"closing and reopening invalidates old drag offers")
	if DisplayServer.get_name()!="headless":
		for frame in 3:await process_frame
		await RenderingServer.frame_post_draw
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--trade-evidence="):root.get_texture().get_image().save_png(arg.trim_prefix("--trade-evidence="))
	ui.free();hud.free();storage.free();await process_frame
	print("TRADE_SCRAP checks=",checks," failures=",failures);quit(1 if failures else 0)
