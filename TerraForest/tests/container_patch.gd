# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func inventory()->RefCounted:
	var value:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	value.register_item(201,999);value.register_item(213,999);value.register_item(401,1);value.register_item(1,1);value.register_durable(1,100)
	return value

func storage(player:RefCounted,capacity:int=16,slots:int=8,pick:int=213)->RefCounted:
	var value:RefCounted=ClassDB.instantiate("NativeContainerStore")
	value.configure(player,capacity,slots,pick);return value

func capture(store:RefCounted,ids:PackedInt64Array)->PackedByteArray:
	var state:Dictionary=store.container_patch_state()
	return store.capture_container_patch(ids,state.revision,state.owner)

func restore(store:RefCounted,bytes:PackedByteArray)->Dictionary:
	var state:Dictionary=store.container_patch_state()
	return store.restore_container_patch(bytes,state.revision,state.owner)

func checksum(bytes:PackedByteArray)->PackedByteArray:
	var value:=bytes.duplicate();var hash:=HashingContext.new();hash.start(HashingContext.HASH_SHA256)
	hash.update(value.slice(0,value.size()-32));var digest:=hash.finish()
	for index in 32:value[value.size()-32+index]=digest[index]
	return value

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var player:=inventory();var store:=storage(player)
	check(store.seed_contents(10,PackedInt64Array([201,7])) and store.seed_lock(10,180,8),"stocked locked target initializes")
	check(store.seed_contents(20,PackedInt64Array([201,9])) and store.seed_lock(30,180,9),"outside contents and empty lock initialize")
	var before:PackedByteArray=store.capture_storage_snapshot();var state:Dictionary=store.container_patch_state()
	var baseline:=capture(store,PackedInt64Array([40,10]))
	check(baseline.size()==1144 and store.validate_container_patch(baseline),"bounded patch includes locked contents and empty target")
	check(baseline==capture(store,PackedInt64Array([10,40])) and store.capture_storage_snapshot()==before and store.container_patch_state()==state,"capture sorts identities deterministically without mutation")
	for ids in [PackedInt64Array(),PackedInt64Array([10,10]),PackedInt64Array([-1]),PackedInt64Array([0])]:
		check(capture(store,ids).is_empty(),"invalid identity selection rejects "+str(ids))
	var too_many:=PackedInt64Array();too_many.resize(65)
	for index in 65:too_many[index]=index+1
	check(capture(store,too_many).is_empty(),"oversized selection rejects")
	check(store.damage_lock(10,180,store.snapshot(10).store_revision).opened,"target lock can be destroyed")
	check(store.withdraw(10,player,0,7,player.snapshot().revision,store.snapshot(10).store_revision).ok,"target contents can be looted")
	check(store.seed_contents(40,PackedInt64Array([201,5])) and store.seed_lock(40,180,3),"initially empty owned target can be modified")
	var outside:=capture(store,PackedInt64Array([20,30]));var outside_token:int=store.snapshot(20).store_revision
	var player_bytes:PackedByteArray=player.capture_storage_snapshot()
	check(not store.restore_container_patch(baseline,state.revision,state.owner).ok,"stale revision rejects restoration")
	check(store.capture_container_patch(PackedInt64Array([10]),state.revision,state.owner).is_empty(),"stale revision rejects capture")
	state=store.container_patch_state()
	check(not store.restore_container_patch(baseline,state.revision,state.owner+1).ok and store.capture_container_patch(PackedInt64Array([10]),state.revision,state.owner+1).is_empty(),"different owner rejects capture and restore")
	var response:=restore(store,baseline)
	check(response.ok and response.changes==2 and capture(store,PackedInt64Array([10,40]))==baseline,"baseline restores supplies and lock while clearing added owned contents")
	check(capture(store,PackedInt64Array([20,30]))==outside and store.snapshot(20).store_revision==outside_token,"outside supplies locks and live transfer token remain exact")
	check(player.capture_storage_snapshot()==player_bytes,"restoration never edits player inventory")
	check(not store.has_contents(40) and not store.is_locked(40) and store.requires_protection(10),"empty and stocked ownership remains sparse and protected")
	state=store.container_patch_state();response=restore(store,baseline)
	check(response.ok and response.changes==0 and store.container_patch_state()==state,"identical restore does not invalidate views")
	var fresh:=storage(player)
	check(not fresh.restore_container_patch(baseline,state.revision,state.owner).ok and restore(fresh,baseline).ok,"fresh owner requires its own current token then accepts persistent baseline")
	check(capture(fresh,PackedInt64Array([10,40]))==baseline,"fresh restoration retains exact lock random state")
	var raw:PackedByteArray=store.capture_storage_snapshot();state=store.container_patch_state()
	check(store.restore_storage_snapshot(raw) and not store.restore_container_patch(baseline,state.revision,state.owner).ok,"whole-store reload invalidates old scoped token")
	var reopened:=storage(player)
	check(reopened.restore_storage_snapshot(raw) and capture(reopened,PackedInt64Array([10,40]))==baseline,"ordinary saved store reopens restored baseline")
	var malformed:=baseline.duplicate();malformed[40]^=1
	before=store.capture_storage_snapshot()
	check(not store.validate_container_patch(malformed) and not restore(store,malformed).ok,"corrupted patch rejects")
	malformed=baseline.duplicate();malformed.encode_u64(24+544,10)
	check(not restore(store,checksum(malformed)).ok,"duplicate identity rejects even with valid checksum")
	malformed=baseline.duplicate();malformed.encode_u32(24+8+8,999)
	check(not restore(store,checksum(malformed)).ok,"unknown inventory item rejects before any mutation")
	malformed=baseline.duplicate();malformed.encode_u32(24+528,181)
	check(not restore(store,checksum(malformed)).ok,"invalid lock health rejects")
	malformed=baseline.duplicate();malformed.encode_u64(24+536,0)
	check(not restore(store,checksum(malformed)).ok,"invalid lock random state rejects")
	malformed=baseline.duplicate();malformed.encode_u32(24+544+532,180)
	check(not restore(store,checksum(malformed)).ok,"empty lock cannot hide stale maximum")
	check(not restore(store,baseline.slice(0,baseline.size()-1)).ok and not restore(store,baseline+PackedByteArray([0])).ok,"truncated and trailing data reject")
	check(store.capture_storage_snapshot()==before,"all rejected requests preserve complete store")
	var no_locks:=storage(player,16,8,0);var fewer_slots:=storage(player,16,6)
	check(not no_locks.validate_container_patch(baseline) and not fewer_slots.validate_container_patch(baseline),"different container schema rejects")
	var full:=storage(player,1);full.seed_contents(50,PackedInt64Array([201,2]));before=full.capture_storage_snapshot()
	check(not restore(full,baseline).ok and full.capture_storage_snapshot()==before,"capacity rejection preserves unrelated occupied container")
	var replacement:=capture(store,PackedInt64Array([10,50]))
	check(restore(full,replacement).ok and full.get_ids()==PackedInt64Array([10]),"full capacity permits owned removal and replacement atomically")
	var maximum_ids:=PackedInt64Array();maximum_ids.resize(64)
	for index in 64:maximum_ids[index]=100+index
	var largest:=capture(store,maximum_ids)
	check(largest.size()==34872 and store.validate_container_patch(largest) and restore(store,largest).ok,"maximum 64-container empty patch stays bounded")
	var tools:=inventory();var equipment:=storage(tools)
	check(tools.grant_durable(1,37,tools.snapshot().revision).ok and tools.grant(401,1,tools.snapshot().revision).ok and tools.exchange_water(1,false,tools.snapshot().revision,1234),"worn tool and partially filled water container initialize")
	check(equipment.deposit(91,tools,0,1,tools.snapshot().revision,equipment.snapshot(91).store_revision).ok and equipment.deposit(91,tools,1,1,tools.snapshot().revision,equipment.snapshot(91).store_revision).ok,"container accepts actual worn tool and water state")
	var gear:=capture(equipment,PackedInt64Array([91]));var looter:=inventory()
	check(equipment.withdraw(91,looter,0,1,looter.snapshot().revision,equipment.snapshot(91).store_revision).ok and equipment.withdraw(91,looter,1,1,looter.snapshot().revision,equipment.snapshot(91).store_revision).ok and not equipment.has_contents(91),"equipment is completely withdrawn through ordinary transfers")
	check(restore(equipment,gear).ok and equipment.snapshot(91).slots[0].wear==37 and equipment.snapshot(91).slots[1].water_ml==1234 and capture(equipment,PackedInt64Array([91]))==gear,"baseline preserves tool durability and exact water volume")
	var populated:=storage(player,4096);var replacement_store:=storage(player,64);var selected:=PackedInt64Array()
	for identity in range(1,2049):populated.seed_contents(identity,PackedInt64Array([201,9]))
	for identity in range(1,65):
		selected.append(identity);replacement_store.seed_contents(identity,PackedInt64Array([201,3]))
	var replacement_stock:=capture(replacement_store,selected);var outside_view:Dictionary=populated.snapshot(2048)
	var begin:=Time.get_ticks_usec();var original_stock:=capture(populated,selected);var capture_us:=Time.get_ticks_usec()-begin
	begin=Time.get_ticks_usec();response=restore(populated,replacement_stock);var restore_us:=Time.get_ticks_usec()-begin
	check(response.ok and response.changes==64 and populated.snapshot(1).slots[0].count==3 and populated.snapshot(2048)==outside_view,"maximum target selection preserves distant live inventory in populated store")
	check(restore(populated,original_stock).ok and capture(populated,selected)==original_stock,"populated store can roll back selected supplies without whole-store replacement")
	print("CONTAINER_PATCH_TIMING ",JSON.stringify({"stored_containers":2048,"selected":64,"bytes":original_stock.size(),"capture_us":capture_us,"restore_us":restore_us}))
	print("CONTAINER_PATCH checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
