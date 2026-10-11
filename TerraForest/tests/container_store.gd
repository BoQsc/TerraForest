# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func inventory() -> RefCounted:
	var inv: RefCounted=ClassDB.instantiate("NativePlayerInventory");inv.register_item(201,1000000);return inv
func move(store: RefCounted,player: RefCounted,id: int,count: int,deposit: bool=true) -> Dictionary:
	return store.deposit(id,player,0,count,player.snapshot().revision,store.snapshot(id).store_revision) if deposit else store.withdraw(id,player,0,count,player.snapshot().revision,store.snapshot(id).store_revision)
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var player:=inventory();player.grant(201,100,0)
	var store: RefCounted=ClassDB.instantiate("NativeContainerStore")
	check(store.configure(player,2) and not store.configure(player,3),"capacity and catalog configure once")
	var empty: PackedByteArray=store.capture_storage_snapshot()
	check(empty.size()==16 and store.validate_snapshot(empty) and store.get_ids().is_empty(),"empty store uses only canonical header")
	for id in 1000:store.snapshot(id+1)
	check(store.capture_storage_snapshot()==empty,"reading empty containers allocates no saved rows")
	check(move(store,player,10,7).ok and move(store,player,20,3).ok,"two separate identities receive items")
	var first_revision: int=store.snapshot(10).store_revision
	check(move(store,player,20,1).ok and store.snapshot(10).store_revision==first_revision,"another nonempty container does not invalidate this view")
	var before: PackedByteArray=store.capture_storage_snapshot();var player_before: Dictionary=player.snapshot()
	check(not move(store,player,30,1).ok and store.capture_storage_snapshot()==before and player.snapshot()==player_before,"capacity rejection preserves player and all contents")
	check(not store.deposit(10,player,0,1,player_before.revision,first_revision-1).ok and store.capture_storage_snapshot()==before and player.snapshot()==player_before,"stale container token is atomic")
	check(move(store,player,10,7,false).ok and not store.has_contents(10),"last withdrawal removes sparse row")
	check(not store.deposit(10,player,0,1,player.snapshot().revision,first_revision).ok,"empty-recreated identity cannot accept prior nonempty token")
	check(move(store,player,30,2).ok and store.get_ids()==PackedInt64Array([20,30]),"freed capacity is reusable with sorted stable identities")
	before=store.capture_storage_snapshot()
	check(before.size()==560,"two inventories use 16 plus two fixed 272-byte records")
	var restored: RefCounted=ClassDB.instantiate("NativeContainerStore");restored.configure(player,2)
	check(restored.restore_storage_snapshot(before) and restored.capture_storage_snapshot()==before,"binary roundtrip exactly preserves contents")
	var old_token: int=restored.snapshot(20).store_revision
	check(restored.restore_storage_snapshot(before) and restored.snapshot(20).store_revision!=old_token,"reload invalidates open transfer tokens")
	for kind in 6:
		var damaged:=before.duplicate()
		match kind:
			0:damaged[0]^=1
			1:damaged.encode_u64(8,3)
			2:damaged.encode_u64(16,0)
			3:damaged.encode_u64(288,20)
			4:damaged.encode_u32(32,999)
			5:damaged.resize(damaged.size()-1)
		check(not restored.validate_snapshot(damaged) and not restored.restore_storage_snapshot(damaged) and restored.capture_storage_snapshot()==before,"malformed snapshot rejects without partial restore: "+str(kind))
	var owner_token: int=restored.snapshot(20).store_revision
	check(restored.restore_storage_snapshot(empty) and restored.get_ids().is_empty() and restored.snapshot(20).store_revision!=owner_token,"whole-world empty restore releases all content rows and invalidates tokens")
	var large: RefCounted=ClassDB.instantiate("NativeContainerStore");large.configure(player,4096)
	var supply:=inventory();supply.grant(201,4097,0)
	var player_revision: int=supply.snapshot().revision
	var store_revision:=0
	var filled:=true
	for id in range(1,4097):
		var result: Dictionary=large.deposit(id,supply,0,1,player_revision,store_revision)
		filled=filled and result.ok
		if not result.ok:break
		player_revision=result.player_revision;store_revision=result.store_revision
	var bytes: PackedByteArray=large.capture_storage_snapshot()
	check(filled and large.get_ids().size()==4096 and bytes.size()==1114128,"configured 4096 nonempty containers fit exact bounded representation")
	check(not large.deposit(4097,supply,0,1,player_revision,store_revision).ok and supply.snapshot().slots[0].count==1,"full-size capacity rejects without losing remaining supply")
	var large_copy: RefCounted=ClassDB.instantiate("NativeContainerStore");large_copy.configure(supply,4096)
	check(large_copy.restore_storage_snapshot(bytes) and large_copy.capture_storage_snapshot()==bytes,"full-capacity snapshot roundtrips without identity or content changes")
	var report: Dictionary={"checks":checks,"failures":failures,"serialized_capacity_bytes":bytes.size()}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/container_store.json",FileAccess.WRITE);file.store_string(JSON.stringify(report));file.close()
	print("CONTAINER_STORE ",JSON.stringify(report));quit(1 if failures else 0)
