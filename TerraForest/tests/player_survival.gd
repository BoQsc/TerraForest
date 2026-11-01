# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var rules:=PackedInt64Array([214,0,25,0,0,215,0,10,0,0,216,0,15,2,120,217,35,0,1,180,218,20,0,0,0,219,10,0,0,0])
var effects:=PackedInt64Array([1,50,0,2,0,100])
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var store:RefCounted=ClassDB.instantiate("NativePlayerSurvival")
	check(not store.configure(PackedInt64Array([214,0,0,0,0]),effects) and not store.configure(PackedInt64Array([214,10,0,8,60]),effects),"invalid or unknown effect catalogs reject without mutation")
	check(store.configure(rules,effects) and not store.configure(rules,effects),"consumable and effect schemas configure once")
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for identity in range(214,220):inventory.register_item(identity,999)
	inventory.register_item(1,1)
	inventory.grant_items(PackedInt64Array([214,4,215,1,216,2,217,4,218,1,219,1,1,1]),0)
	var progression:RefCounted=ClassDB.instantiate("NativePlayerProgression");progression.configure(PackedInt64Array([1,5,50]))
	var pristine:PackedByteArray=store.capture_storage_snapshot();var original:PackedByteArray=inventory.capture_storage_snapshot()
	check(pristine.size()==24 and store.validate_snapshot(pristine) and store.snapshot().food_ms==3600000,"new character has full food and a 24-byte condition snapshot")
	check(not store.use(inventory,progression,3,inventory.snapshot().revision,store.snapshot().revision).ok and inventory.capture_storage_snapshot()==original and store.capture_storage_snapshot()==pristine,"full character cannot accidentally waste food")
	check(not store.use(inventory,progression,0,0,store.snapshot().revision).ok and not store.use(inventory,progression,6,inventory.snapshot().revision,store.snapshot().revision).ok,"stale inventory and non-consumables cannot be used")
	var before:int=inventory.snapshot().revision
	var journal:Dictionary=store.use(inventory,progression,2,before,store.snapshot().revision)
	check(journal.ok and journal.xp==15 and inventory.snapshot().slots[2].count==1 and store.snapshot().effects[2]==120000,"journal atomically consumes one, teaches and adds Focused")
	check(not store.use(inventory,progression,2,before,store.snapshot().revision).ok and progression.snapshot().xp==15,"duplicate use cannot consume or teach twice")
	check(store.scale_experience(100)==110 and store.scale_damage(100)==100,"Focused modifies learning only")
	check(store.use(inventory,progression,0,inventory.snapshot().revision,store.snapshot().revision).xp==28 and store.snapshot().readings[214]==1,"active learning modifier affects an actual readable award")
	check(store.advance(60000) and store.snapshot().effects[2]==60000 and store.snapshot().food_ms==3540000,"elapsed gameplay time drains food and buffs together")
	var meal:Dictionary=store.use(inventory,progression,3,inventory.snapshot().revision,store.snapshot().revision)
	check(meal.ok and meal.food_ms==60000 and store.snapshot().food_ms==3600000 and store.snapshot().effects[1]==180000,"food clamps at fullness and starts its actual damage buff")
	check(store.scale_damage(100)==105,"Well fed changes action damage")
	store.advance(1000);store.use(inventory,progression,3,inventory.snapshot().revision,store.snapshot().revision)
	check(store.snapshot().effects[1]==180000 and store.scale_damage(100)==105,"same buff refreshes duration without stacking its strength")
	var saved:PackedByteArray=store.capture_storage_snapshot();var clone:RefCounted=ClassDB.instantiate("NativePlayerSurvival");clone.configure(rules,effects)
	check(clone.restore_storage_snapshot(saved) and clone.capture_storage_snapshot()==saved,"fresh native instance preserves food, simultaneous buffs and reading history exactly")
	var bad:Array[PackedByteArray]=[]
	for offset in [0,4,8,12,16,20,24,28]:
		var data:=saved.duplicate();data.encode_u32(offset,4294967295);bad.append(data)
	for length in saved.size():bad.append(saved.slice(0,length))
	var extra:=saved.duplicate();extra.append(0);bad.append(extra)
	var atomic:=true
	for data:PackedByteArray in bad:atomic=atomic and not clone.restore_storage_snapshot(data) and clone.capture_storage_snapshot()==saved
	check(atomic,"malformed and truncated condition data never partially mutates live state")
	var expanded:RefCounted=ClassDB.instantiate("NativePlayerSurvival");var future:=rules.duplicate();future.append_array(PackedInt64Array([220,10,0,0,0]));expanded.configure(future,effects)
	check(expanded.restore_storage_snapshot(saved) and expanded.snapshot().readings[214]==1,"new consumable identities preserve existing reading and effect records")
	check(not store.advance(-1) and not store.advance(86400001),"invalid elapsed times are rejected")
	store.advance(60000)
	check(not store.snapshot().effects.has(2) and store.scale_experience(100)==100,"Focused expires on the precise elapsed boundary")
	store.advance(3000000)
	check(store.scale_damage(100)==90 and store.snapshot().effects.is_empty(),"low food is a bounded ten-percent damage penalty after buffs expire")
	store.advance(3600000)
	check(store.snapshot().food_ms==0 and store.scale_damage(100)==80 and not store.advance(1000),"starvation clamps to zero with bounded penalty and no idle dirty revisions")
	check(store.use(inventory,progression,4,inventory.snapshot().revision,store.snapshot().revision).food_ms==720000,"bread can be eaten to recover from zero food")
	check(store.use(inventory,progression,5,inventory.snapshot().revision,store.snapshot().revision).food_ms==360000 and store.scale_damage(100)==100,"berries lift food out of the low-food penalty")
	check(clone.restore_storage_snapshot(pristine) and clone.snapshot().readings.is_empty() and clone.snapshot().effects.is_empty(),"legacy missing-section default does not leak another world's history or buffs")
	check_trader_migration()
	print("PLAYER_SURVIVAL ",JSON.stringify({"checks":checks,"failures":failures,"active_snapshot_bytes":saved.size()}));quit(1 if failures else 0)

func check_trader_migration()->void:
	var stock:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for identity in [201,217,218,219,601]:stock.register_item(identity,999)
	stock.grant_items(PackedInt64Array([201,7,601,40]),stock.snapshot().revision)
	var old:PackedByteArray=stock.capture_storage_snapshot()
	var ledger:RefCounted=ClassDB.instantiate("NativeTraderStock")
	check(not ledger.configure(stock,PackedInt64Array([217,16,217,16])) and ledger.configure(stock,PackedInt64Array([217,16,218,24,219,24])) and not ledger.configure(stock,PackedInt64Array([217,16])),"merchant migration schema validates atomically and configures once")
	check(ledger.restore_storage_snapshot(old) and stock.snapshot().slots[0].count==7 and stock.snapshot().slots[1].count==40 and stock.snapshot().slots[2].item==217,"legacy merchant gains newly introduced foods without refilling original stock or money")
	stock.consume(2,16,stock.snapshot().revision)
	var used:PackedByteArray=ledger.capture_storage_snapshot()
	check(ledger.restore_storage_snapshot(used) and ledger.capture_storage_snapshot()==used and not ledger.flush_pending() and stock.snapshot().slots[2].count==0,"sold-out migrated food never refills after save/reload")
	var partial:PackedByteArray=stock.capture_storage_snapshot();stock.consume(3,1,stock.snapshot().revision);partial=stock.capture_storage_snapshot()
	check(ledger.restore_storage_snapshot(partial) and stock.snapshot().slots[3].count==23,"legacy-present new goods keep their remaining quantity instead of receiving duplicates")
	var full:Dictionary=stock.snapshot()
	for index in 32:full.slots[index]={"item":201,"count":999}
	stock.restore(full,stock.snapshot().revision)
	check(ledger.restore_storage_snapshot(stock.capture_storage_snapshot()) and ledger.capture_storage_snapshot().size()==560,"full legacy stock preserves all goods and queues bounded additions")
	var queued:PackedByteArray=ledger.capture_storage_snapshot()
	check(ledger.restore_storage_snapshot(queued) and ledger.capture_storage_snapshot()==queued,"queued migration survives exact save/reopen without loss")
	stock.consume(0,999,stock.snapshot().revision)
	check(ledger.flush_pending() and stock.snapshot().slots[0].item==217 and ledger.capture_storage_snapshot().size()==552,"freeing one merchant slot admits exactly one pending food type")
	var valid:PackedByteArray=ledger.capture_storage_snapshot();var malformed:=valid.duplicate();malformed.encode_u32(valid.size()-4,99999)
	check(not ledger.restore_storage_snapshot(malformed) and ledger.capture_storage_snapshot()==valid,"invalid pending migration fails without mutating merchant inventory")
