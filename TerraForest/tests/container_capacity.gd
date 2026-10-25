extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var inventory:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	for item in range(1,34):inventory.register_item(item,1)
	inventory.register_item(102,64);inventory.register_item(201,64)
	inventory.register_item(301,1)
	inventory.grant_items(PackedInt64Array([1,1,2,1,3,1,4,1,5,1,6,1,7,1,8,1,9,1]),0)
	var small:RefCounted=ClassDB.instantiate("NativeContainerStore")
	check(small.configure(inventory,16,8) and small.snapshot(1).capacity==8,"small container exposes eight native slots")
	for slot in 8:
		check(small.deposit(1,inventory,slot,1,inventory.snapshot().revision,small.snapshot(1).store_revision).ok,"deposit fits bounded slot "+str(slot))
	var before:PackedByteArray=inventory.capture_storage_snapshot();var stored:PackedByteArray=small.capture_storage_snapshot()
	check(not small.deposit(1,inventory,8,1,inventory.snapshot().revision,small.snapshot(1).store_revision).ok and inventory.capture_storage_snapshot()==before and small.capture_storage_snapshot()==stored,"full compact storage rejects atomically without hidden overflow slots")
	check(not small.drag_slots(1,inventory,false,true,8,8,1,inventory.snapshot().revision,small.snapshot(1).store_revision).ok,"direct drag cannot bypass native capacity")
	var old:RefCounted=ClassDB.instantiate("NativeContainerStore");old.configure(inventory,16)
	check(old.drag_slots(1,inventory,false,true,8,31,1,inventory.snapshot().revision,old.snapshot(1).store_revision).ok,"legacy fixture stores an item in slot thirty-two")
	var restore:RefCounted=ClassDB.instantiate("NativeContainerStore");restore.configure(inventory,16,8)
	check(restore.restore_storage_snapshot(old.capture_storage_snapshot()) and restore.snapshot(1).capacity==32 and restore.snapshot(1).slots[31].item==9,"legacy overflow remains visible and retrievable without data loss")
	check(restore.withdraw(1,inventory,31,1,inventory.snapshot().revision,restore.snapshot(1).store_revision).ok and restore.snapshot(1).capacity==8,"empty legacy overflow shrinks back to the compact default")
	var corpse:RefCounted=ClassDB.instantiate("NativeCorpseStore");corpse.configure(inventory,16,8)
	var id:int=corpse.create_corpse(Vector3.ZERO,0,1703)
	check(id>0 and corpse.snapshot(id).capacity==8,"corpse loot uses compact slots without changing pose storage")
	print("CONTAINER_CAPACITY failures=",failures);quit(1 if failures else 0)
