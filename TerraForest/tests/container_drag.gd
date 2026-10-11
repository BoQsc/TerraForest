# SPDX-License-Identifier: 0BSD
extends SceneTree
var fails:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:fails+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var p: RefCounted=ClassDB.instantiate("NativePlayerInventory");p.register_item(102,10);p.register_item(201,10)
	p.grant(102,8,0);p.grant(201,5,1)
	var c: RefCounted=ClassDB.instantiate("NativeContainerStore");c.configure(p,2)
	check(c.drag_slots(1,p,false,true,0,9,4,p.snapshot().revision,c.snapshot(1).store_revision).ok,"partial deposit targets exact chest slot")
	check(c.snapshot(1).slots[9].count==4 and c.snapshot(1).slots[0].count==0 and p.snapshot().slots[0].count==4,"source and exact target amounts")
	check(c.drag_slots(1,p,false,true,0,9,4,p.snapshot().revision,c.snapshot(1).store_revision).ok and c.snapshot(1).slots[9].count==8,"matching stacks merge")
	check(c.drag_slots(1,p,false,true,1,9,5,p.snapshot().revision,c.snapshot(1).store_revision).ok,"different full stacks swap across inventories")
	check(p.snapshot().slots[1].item==102 and p.snapshot().slots[1].count==8 and c.snapshot(1).slots[9].item==201,"swap conserves both items")
	var before: PackedByteArray=c.capture_storage_snapshot();var prior: Dictionary=p.snapshot()
	check(not c.drag_slots(1,p,false,true,1,9,2,p.snapshot().revision,c.snapshot(1).store_revision).ok and before==c.capture_storage_snapshot() and prior==p.snapshot(),"partial cross swap rejects atomically")
	check(not c.drag_slots(1,p,true,false,9,0,1,p.snapshot().revision-1,c.snapshot(1).store_revision).ok and before==c.capture_storage_snapshot(),"stale player revision rejects drag")
	check(not c.drag_slots(1,p,true,false,9,0,1,p.snapshot().revision,c.snapshot(1).store_revision-1).ok and prior==p.snapshot(),"stale container revision rejects drag")
	check(c.drag_slots(1,p,true,true,9,31,5,p.snapshot().revision,c.snapshot(1).store_revision).ok and c.snapshot(1).slots[31].count==5,"reorder within chest")
	check(c.drag_slots(1,p,true,false,31,9,5,p.snapshot().revision,c.snapshot(1).store_revision).ok and not c.has_contents(1) and p.snapshot().slots[9].count==5,"last withdrawal targets belt slot ten and frees content row")
	check(c.drag_slots(1,p,false,false,9,8,5,p.snapshot().revision,c.snapshot(1).store_revision).ok and p.snapshot().slots[8].count==5 and not c.has_contents(1),"player reorder inside chest UI does not allocate contents")
	for slot in [-1,32]:check(not c.drag_slots(1,p,false,true,8,slot,1,p.snapshot().revision,c.snapshot(1).store_revision).ok,"invalid target rejected")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/container_drag.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":fails}));file.close()
	print("CONTAINER_DRAG ",JSON.stringify({"checks":checks,"failures":fails}));quit(1 if fails else 0)
