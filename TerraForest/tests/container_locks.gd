# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func inventory(picks:int=0)->RefCounted:
	var player:RefCounted=ClassDB.instantiate("NativePlayerInventory")
	player.register_item(201,999);player.register_item(213,999)
	if picks:player.grant(213,picks,player.snapshot().revision)
	return player
func storage(player:RefCounted,capacity:int=4)->RefCounted:
	var store:RefCounted=ClassDB.instantiate("NativeContainerStore")
	store.configure(player,capacity,16,213);return store
func attempt(store:RefCounted,player:RefCounted,id:int=10)->Dictionary:
	return store.attempt_unlock(id,player,player.snapshot().revision,store.snapshot(id).store_revision)
func strike(store:RefCounted,damage:int,id:int=10)->Dictionary:
	return store.damage_lock(id,damage,store.snapshot(id).store_revision)
func reject_snapshot(store:RefCounted,bytes:PackedByteArray,label:String)->void:
	var before:PackedByteArray=store.capture_storage_snapshot()
	check(not store.validate_snapshot(bytes) and not store.restore_storage_snapshot(bytes) and store.capture_storage_snapshot()==before,label)
func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var player:=inventory()
	var legacy:RefCounted=ClassDB.instantiate("NativeContainerStore")
	check(not legacy.configure(player,4,16,999) and legacy.configure(player,4,16),"unknown pick rejects configure without partial mutation")
	check(not legacy.seed_lock(10,180,1),"corpse/equipment-style stores cannot acquire locks")
	var corpse:RefCounted=ClassDB.instantiate("NativeCorpseStore")
	check(not corpse.configure(player,4,8,213) and corpse.configure(player,4,8),"corpse persistence cannot opt into unsupported lock records")
	var store:=storage(player)
	var empty:PackedByteArray=store.capture_storage_snapshot()
	check(empty.size()==16 and empty[4]==3,"unlocked stores retain exact version-three envelope")
	for args in [[0,180,1],[-1,180,1],[10,0,1],[10,1000001,1],[10,180,-1]]:
		check(not store.seed_lock(args[0],args[1],args[2]) and store.capture_storage_snapshot()==empty,"invalid lock admission is atomic "+str(args))
	check(store.seed_lock(10,180,8) and not store.seed_lock(10,180,9),"lock admits once with doubled chest health")
	check(store.is_locked(10) and store.requires_protection(10) and not store.has_contents(10) and store.get_ids()==PackedInt64Array([10]),"empty locked container retains identity and removal protection")
	check(store.seed_contents(10,PackedInt64Array([201,7])) and store.seed_contents(20,PackedInt64Array([201,3])) and store.seed_lock(30,180,2),"contents and locks share identities without duplicate capacity")
	check(store.get_ids()==PackedInt64Array([10,20,30]),"mixed sparse identities are sorted and unique")
	var original:PackedByteArray=store.capture_storage_snapshot()
	check(original[4]==4 and original.size()==24+528*2+24*2 and store.validate_snapshot(original),"version-four cost is 24 bytes per lock plus shared header")
	var player_before:PackedByteArray=player.capture_storage_snapshot()
	check(attempt(store,player).reason=="missing_lockpick" and store.capture_storage_snapshot()==original and player.capture_storage_snapshot()==player_before,"missing pick neither advances random state nor edits either inventory")
	player.grant(213,4,player.snapshot().revision)
	player_before=player.capture_storage_snapshot()
	var token:int=store.snapshot(10).store_revision
	check(not store.attempt_unlock(10,player,player.snapshot().revision-1,token).ok and not store.attempt_unlock(10,player,player.snapshot().revision,token-1).ok and store.capture_storage_snapshot()==original and player.capture_storage_snapshot()==player_before,"stale pick attempts are atomic")
	check(store.deposit(10,player,0,1,player.snapshot().revision,token).reason=="container_locked" and store.withdraw(10,player,0,1,player.snapshot().revision,token).reason=="container_locked","both transfer directions enforce locks natively")
	for sides in [[true,true],[true,false],[false,true]]:
		check(store.drag_slots(10,player,sides[0],sides[1],0,1,1,player.snapshot().revision,token).reason=="container_locked","drag cannot bypass lock "+str(sides))
	check(store.capture_storage_snapshot()==original and player.capture_storage_snapshot()==player_before,"blocked transfers preserve all contents")
	check(store.drag_slots(30,player,false,false,0,1,1,player.snapshot().revision,store.snapshot(30).store_revision).ok,"player-only rearrangement works alongside locked empty chest")
	check(not strike(store,0).ok and not strike(store,-1).ok and not strike(store,1000001).ok and store.capture_storage_snapshot()==original,"invalid damage preserves lock and contents")
	var hit:=strike(store,30)
	check(hit.ok and not hit.opened and hit.remaining==150 and hit.maximum==180 and hit.applied==30,"actual impact reduces only lock durability")
	var partial:PackedByteArray=store.capture_storage_snapshot()
	check(not store.damage_lock(10,30,token).ok and store.capture_storage_snapshot()==partial,"stale impact cannot be replayed")
	var restored:=storage(player)
	check(restored.restore_storage_snapshot(partial) and restored.capture_storage_snapshot()==partial and restored.lock_state(10).remaining==150,"partial damage and random state roundtrip exactly")
	var restored_token:int=restored.snapshot(10).store_revision
	check(restored.restore_storage_snapshot(partial) and restored.snapshot(10).store_revision!=restored_token,"restore invalidates open lock tokens")
	hit=strike(restored,500)
	check(hit.opened and hit.applied==150 and hit.remaining==0 and not restored.is_locked(10) and restored.has_contents(10) and restored.requires_protection(10) and restored.snapshot(10).slots[0].count==7,"forced entry opens rather than destroys stocked container")
	check(not strike(restored,30).ok,"unlocked lock cannot receive further lock damage")
	check(restored.withdraw(10,player,0,7,player.snapshot().revision,restored.snapshot(10).store_revision).ok and not restored.requires_protection(10),"contents become reachable after forced entry")
	for kind in 13:
		var bad:=partial.duplicate()
		var row:=24+528*2
		match kind:
			0:bad[0]^=1
			1:bad.resize(20)
			2:bad.encode_u64(8,5)
			3:bad.encode_u64(16,0)
			4:bad.encode_u64(16,5)
			5:bad.encode_u64(row,0)
			6:bad.encode_u64(row+24,10)
			7:bad.encode_u32(row+8,0)
			8:bad.encode_u32(row+8,181)
			9:bad.encode_u32(row+12,1000001)
			10:bad.encode_u64(row+16,0)
			11:bad.resize(bad.size()-1)
			12:bad.encode_u64(row,-1)
		reject_snapshot(store,bad,"malformed lock snapshot rejects atomically "+str(kind))
	reject_snapshot(legacy,partial,"lock-disabled stores reject version four")
	check(store.restore_storage_snapshot(empty) and store.get_ids().is_empty() and not store.is_locked(10),"legacy empty restore removes all locks and damage")
	capacity_checks(player)
	random_checks()
	print("CONTAINER_LOCKS ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
func capacity_checks(player:RefCounted)->void:
	var store:=storage(player,2)
	check(store.seed_contents(10,PackedInt64Array([201,1])) and store.seed_lock(20,180,2),"capacity counts union of content and lock identities")
	var before:PackedByteArray=store.capture_storage_snapshot()
	check(not store.seed_lock(30,180,3) and not store.seed_contents(30,PackedInt64Array([201,1])) and store.capture_storage_snapshot()==before,"both admission paths obey union capacity")
	check(store.seed_contents(20,PackedInt64Array([201,1])) and store.seed_lock(10,180,1),"existing lock/content identity can acquire the other component at capacity")
	check(strike(store,180,20).opened and store.has_contents(20) and not store.seed_lock(30,180,3),"unlocking stocked container does not release occupied identity")
	var empty_lock:=storage(player,1)
	check(empty_lock.seed_lock(10,180,1) and strike(empty_lock,180).opened and empty_lock.seed_lock(20,180,2),"unlocking empty container releases capacity")
	var overflow:=storage(player,4)
	overflow.seed_contents(10,PackedInt64Array([201,1]));overflow.seed_contents(20,PackedInt64Array([201,1]));overflow.seed_lock(30,180,3)
	reject_snapshot(store,overflow.capture_storage_snapshot(),"individually bounded tables cannot overflow shared capacity on restore")
	var copy:=storage(player,2)
	check(copy.restore_storage_snapshot(before) and copy.seed_contents(20,PackedInt64Array([201,2])) and not copy.seed_lock(30,180,3),"restored lock-only accounting remains bounded")
	var large:=storage(player,4096)
	var started:=Time.get_ticks_usec();var admitted:=true
	for id in range(1,4097):admitted=large.seed_lock(id,180,1703) and admitted
	var bytes:PackedByteArray=large.capture_storage_snapshot()
	var large_copy:=storage(player,4096)
	check(admitted and bytes.size()==98328 and not large.seed_lock(4097,180,1703) and large_copy.restore_storage_snapshot(bytes) and large_copy.capture_storage_snapshot()==bytes,"4096 locks fit 98328 bytes and preserve full bounded state")
	print("LOCK_CAPACITY_US ",Time.get_ticks_usec()-started)
func random_checks()->void:
	var broken:=0;var opened:=0;var consistent:=true;var break_checked:=false
	for seed in 1000:
		var player:=inventory(2);var store:=storage(player);store.seed_lock(10,180,seed)
		var clone:=storage(player);clone.restore_storage_snapshot(store.capture_storage_snapshot())
		var player_copy:=inventory(2)
		var first:=attempt(store,player);var second:=attempt(clone,player_copy)
		consistent=consistent and first.ok and second.ok and first.opened==second.opened and first.broken_pick==second.broken_pick and store.capture_storage_snapshot()==clone.capture_storage_snapshot() and player.capture_storage_snapshot()==player_copy.capture_storage_snapshot()
		if first.broken_pick:
			broken+=1
			consistent=consistent and store.is_locked(10) and player.snapshot().slots[0].count==1
			if not break_checked:
				var advanced:PackedByteArray=store.capture_storage_snapshot()
				clone.restore_storage_snapshot(advanced)
				var next:=attempt(store,player);var next_copy:=attempt(clone,player_copy)
				check(next.opened==next_copy.opened and store.capture_storage_snapshot()==clone.capture_storage_snapshot() and player.capture_storage_snapshot()==player_copy.capture_storage_snapshot(),"broken-pick random continuation persists across reload")
				break_checked=true
		else:
			opened+=1
			consistent=consistent and not store.is_locked(10) and player.snapshot().slots[0].count==2 and store.capture_storage_snapshot().size()==16
	check(consistent and break_checked,"1000 attempts are deterministic, successful picks reusable, broken picks consumed once")
	check(broken>60 and broken<140 and opened+broken==1000,"fixed sample has small approximately ten-percent break rate")
	print("LOCK_ATTEMPTS ",JSON.stringify({"opened":opened,"broken":broken}))
