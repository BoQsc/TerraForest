# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func inventory(limit: int=10,include_wood: bool=true) -> RefCounted:
	var value: RefCounted=ClassDB.instantiate("NativePlayerInventory")
	if include_wood: value.register_item(102,limit)
	value.register_item(201,limit)
	return value
func amount(value: RefCounted,item: int) -> int:
	var total:=0
	for row: Dictionary in value.snapshot().slots:
		if row.item==item: total+=int(row.count)
	return total
func transfer(source: RefCounted,target: RefCounted,slot: int,count: int) -> Dictionary:
	return source.transfer_to(target,slot,count,source.snapshot().revision,target.snapshot().revision)
func unchanged_failure(source: RefCounted,target: RefCounted,slot: int,count: int,label: String) -> void:
	var a: Dictionary=source.snapshot();var b: Dictionary=target.snapshot()
	check(not transfer(source,target,slot,count).ok and source.snapshot()==a and target.snapshot()==b,label)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var source:=inventory();var target:=inventory()
	check(source.grant(102,17,0).ok and target.grant(102,8,0).ok,"fixture creates split source and partly occupied destination")
	var a: Dictionary=source.snapshot();var b: Dictionary=target.snapshot()
	var moved: Dictionary=source.transfer_to(target,0,7,a.revision,b.revision)
	check(moved.ok and moved.item==102 and moved.count==7,"partial stack transfers between inventories")
	check(source.snapshot().slots[0].count==3 and target.snapshot().slots[0].count==10 and target.snapshot().slots[1].count==5,"destination fills existing stack before an empty slot")
	check(amount(source,102)+amount(target,102)==25,"successful transfer conserves items")
	check(moved.revision==a.revision+1 and moved.destination_revision==b.revision+1,"both revisions advance once")
	var after_a: Dictionary=source.snapshot();var after_b: Dictionary=target.snapshot()
	check(not source.transfer_to(target,0,7,a.revision,b.revision).ok and source.snapshot()==after_a and target.snapshot()==after_b,"replayed stale request cannot duplicate or lose items")
	check(not source.transfer_to(target,0,1,after_a.revision,after_b.revision-1).ok and source.snapshot()==after_a and target.snapshot()==after_b,"stale destination alone rejects both writes")
	check(not source.transfer_to(target,0,1,after_a.revision-1,after_b.revision).ok and source.snapshot()==after_a and target.snapshot()==after_b,"stale source alone rejects both writes")
	for slot in [-1,32,9223372036854775807]: unchanged_failure(source,target,slot,1,"invalid slot preserves both inventories: "+str(slot))
	for count in [-1,0,4,9223372036854775807]: unchanged_failure(source,target,0,count,"invalid count preserves both inventories: "+str(count))
	unchanged_failure(source,target,31,1,"empty source slot cannot produce an item")
	unchanged_failure(source,source,0,1,"self transfer rejected without mutation")
	check(not source.transfer_to(null,0,1,after_a.revision,0).ok and source.snapshot()==after_a,"null destination rejected")
	var unknown:=inventory(10,false)
	unchanged_failure(source,unknown,0,1,"destination without matching catalog item rejects transfer")
	var full:=inventory();full.grant(201,320,0)
	unchanged_failure(source,full,0,1,"full destination rejects without source debit")
	var last_space:=inventory();last_space.grant(201,310,0);last_space.grant(102,9,1)
	unchanged_failure(source,last_space,0,2,"insufficient partial capacity rejects whole transfer")
	check(transfer(source,last_space,0,1).ok and amount(last_space,102)==10,"exact last capacity accepts transfer")
	var smaller:=inventory(1)
	check(transfer(source,smaller,1,7).ok and amount(smaller,102)==7,"different destination stack limit respected across slots")
	check(smaller.snapshot().slots.slice(0,7).all(func(row: Dictionary):return row.count==1),"one-item stacks remain bounded")
	check(transfer(smaller,source,0,1).ok,"withdrawal uses the same native operation")
	var packed_a: PackedByteArray=source.capture_storage_snapshot();var packed_b: PackedByteArray=target.capture_storage_snapshot()
	var reload_a:=inventory();var reload_b:=inventory()
	check(reload_a.restore_storage_snapshot(packed_a) and reload_b.restore_storage_snapshot(packed_b),"both post-transfer inventories restore through existing binary codec")
	check(reload_a.snapshot().slots==source.snapshot().slots and reload_b.snapshot().slots==target.snapshot().slots,"restored contents exactly match both committed sides")
	var round_a:=inventory();var round_b:=inventory();round_a.grant(102,10,0)
	var repeated_ok:=true
	for i in 1000:
		repeated_ok=repeated_ok and transfer(round_a,round_b,0,10).ok and transfer(round_b,round_a,0,10).ok
	check(repeated_ok and amount(round_a,102)==10 and amount(round_b,102)==0,"1000 deposit-withdraw cycles conserve all items")
	check(round_a.snapshot().revision==2001 and round_b.snapshot().revision==2000,"repeat-cycle revisions track both commits without extra writes")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report: Dictionary={"checks":checks,"failures":failures,"scope":"atomic native cross-inventory mutation; no container UI or world persistence integration"}
	var file:=FileAccess.open("res://reports/inventory_transfer.json",FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("INVENTORY_TRANSFER ",JSON.stringify(report));quit(1 if failures else 0)
