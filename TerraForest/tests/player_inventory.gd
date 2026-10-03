# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	call_deferred("run")
func run() -> void:
	var inventory=ClassDB.instantiate("NativePlayerInventory")
	check(inventory.register_item(1,10) and inventory.register_item(2,1),"catalog registers bounded stack limits")
	check(not inventory.register_item(1,20),"duplicate catalog definitions rejected")
	check(inventory.grant(1,15,0).ok,"grant spans stacks atomically")
	var before: Dictionary=inventory.snapshot()
	check(before.slots[0].count==10 and before.slots[1].count==5,"deterministic stacking")
	check(not inventory.register_item(3,1),"catalog freezes after inventory mutation")
	check(not inventory.grant(1,1,0).ok and inventory.snapshot()==before,"stale command cannot duplicate items")
	check(not inventory.grant(1,9223372036854775807,1).ok and inventory.snapshot()==before,"oversized grant is rejected without partial write")
	check(inventory.transfer(1,2,2,1).ok,"partial transfer splits a stack")
	check(inventory.snapshot().slots[1].count==3 and inventory.snapshot().slots[2].count==2,"split conserves counts")
	before=inventory.snapshot()
	check(not inventory.transfer(1,0,1,before.revision).ok and inventory.snapshot()==before,"full destination rejects without losing items")
	check(inventory.grant(2,1,before.revision).ok,"different item admitted")
	before=inventory.snapshot()
	check(inventory.transfer(3,0,1,before.revision).ok,"whole different stacks swap")
	before=inventory.snapshot()
	check(before.slots[0].item==2 and before.slots[3].count==10,"swap preserves both items")
	var malformed: Dictionary=before.duplicate(true)
	malformed.slots[31]={"item":99,"count":1}
	check(not inventory.restore(malformed,before.revision).ok and inventory.snapshot()==before,"invalid late snapshot slot cannot partially restore")
	malformed=before.duplicate(true);malformed.slots[0].count=1.0
	check(not inventory.restore(malformed,before.revision).ok,"float counts rejected")
	check(inventory.consume(3,10,before.revision).ok,"consume exact stack")
	check(inventory.snapshot().slots[3].item==0,"empty slot canonicalized")
	check(inventory.restore(before,inventory.snapshot().revision).ok,"valid snapshot restores catalog-checked contents")
	before=inventory.snapshot()
	var exposed: Dictionary=inventory.snapshot();exposed.slots[0].count=999
	check(inventory.snapshot()==before,"returned snapshot cannot mutate native state")
	check(not inventory.transfer(-1,0,1,before.revision).ok and not inventory.consume(32,1,before.revision).ok,"invalid slot bounds rejected")
	var packed: PackedByteArray=inventory.capture_storage_snapshot()
	check(packed.size()==264 and inventory.validate_snapshot(packed),"bounded native save format validates")
	check(inventory.consume(0,1,before.revision).ok and inventory.restore_storage_snapshot(packed),"binary load restores after mutation")
	check(inventory.snapshot().slots==before.slots,"binary roundtrip preserves all slots")
	before=inventory.snapshot()
	for offset in [0,4,8,12,256,260]:
		var corrupt:=packed.duplicate();corrupt.encode_u32(offset,0xffffffff)
		check(not inventory.validate_snapshot(corrupt) and not inventory.restore_storage_snapshot(corrupt) and inventory.snapshot()==before,"corrupt field rejected atomically at byte %d"%offset)
	check(not inventory.validate_snapshot(packed.slice(0,263)),"truncated load rejected")
	var oversized:=packed.duplicate();oversized.append(0)
	check(not inventory.validate_snapshot(oversized),"trailing bytes rejected")
	var path:="user://player_inventory_test.bin"
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_buffer(packed);file.close()
	file=FileAccess.open(path,FileAccess.READ)
	var disk:=file.get_buffer(file.get_length());file.close()
	check(inventory.restore_storage_snapshot(disk) and inventory.snapshot().slots==before.slots,"disk roundtrip preserves loadout")
	DirAccess.remove_absolute(path)
	print("PLAYER_INVENTORY ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
