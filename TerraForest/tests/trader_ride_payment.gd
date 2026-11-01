# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func wallet()->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativePlayerInventory");result.register_item(601,1000);result.register_item(201,999);return result
func amount(inventory:RefCounted)->int:
	var total:=0
	for slot:Dictionary in inventory.snapshot().slots:
		if slot.item==601:total+=slot.count
	return total
func pay(a:RefCounted,b:RefCounted,n:int)->Dictionary:return a.transfer_items_to(b,PackedInt64Array([601,n]),a.snapshot().revision,b.snapshot().revision)
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var player:=wallet();var trader:=wallet()
	player.grant(601,100,0);player.transfer(0,1,50,player.snapshot().revision)
	var p:int=player.snapshot().revision;var t:int=trader.snapshot().revision
	check(pay(player,trader,74).ok and amount(player)==26 and amount(trader)==74,"fare aggregates split coin stacks and credits merchant exactly once")
	check(player.snapshot().revision==p+1 and trader.snapshot().revision==t+1,"both wallet revisions advance once")
	var before:PackedByteArray=player.capture_storage_snapshot();var peer:PackedByteArray=trader.capture_storage_snapshot()
	check(not player.transfer_items_to(trader,PackedInt64Array([601,74]),p,t).ok and player.capture_storage_snapshot()==before and trader.capture_storage_snapshot()==peer,"replayed stale fare cannot charge twice")
	check(not pay(player,trader,27).ok and player.capture_storage_snapshot()==before and trader.capture_storage_snapshot()==peer,"insufficient money changes neither purse")
	check(pay(trader,player,74).ok and amount(player)==100 and amount(trader)==0,"cancellation refunds exact fare through the same atomic operation")
	var full:=wallet();var state:Dictionary=full.snapshot()
	for i in state.slots.size():state.slots[i]={"item":201,"count":999}
	full.restore(state,full.snapshot().revision)
	before=player.capture_storage_snapshot();peer=full.capture_storage_snapshot()
	check(not pay(player,full,10).ok and player.capture_storage_snapshot()==before and full.capture_storage_snapshot()==peer,"full purse rejects after debit staging and rolls both inventories back")
	check(not pay(player,player,10).ok,"self payment rejected")
	var unknown:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	check(not pay(player,unknown,10).ok and player.capture_storage_snapshot()==before,"unknown destination currency cannot consume money")
	for values in [PackedInt64Array(),PackedInt64Array([601]),PackedInt64Array([601,0]),PackedInt64Array([601,-1]),PackedInt64Array([601,60,601,60])]:
		check(not player.transfer_items_to(trader,values,player.snapshot().revision,trader.snapshot().revision).ok and player.capture_storage_snapshot()==before,"invalid or cumulatively unaffordable payment rejects atomically")
	check(pay(player,trader,100).ok and amount(player)==0 and amount(trader)==100,"exact remaining fare permits emptying the wallet")
	var saved:PackedByteArray=trader.capture_storage_snapshot();var restored:=wallet()
	check(restored.restore_storage_snapshot(saved) and amount(restored)==100,"paid merchant purse persists with the ordinary inventory codec")
	print("TRADER_RIDE_PAYMENT checks=",checks," failures=",failures);quit(1 if failures else 0)
