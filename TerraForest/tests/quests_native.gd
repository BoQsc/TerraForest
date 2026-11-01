# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var inventory:RefCounted

func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)

func make_store()->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativeQuestLog");result.configure(inventory,601);return result

func location(identity:int=1)->Dictionary:
	var point:=Vector3(100+(identity%16)*10,40,100+(identity/16)*10)
	return {"key":identity,"layout":"mine_test","title":"Mine %d"%identity,"origin":Vector3i(point),"rotation":0,"marker":point-Vector3(0,0,2),"bounds":AABB(point,Vector3(5,5,5)),"residents":PackedInt64Array([10000+identity*2,10001+identity*2]),"containers":PackedInt64Array([20000+identity]),"coins":20,"xp":80}

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	inventory=ClassDB.instantiate("NativePlayerInventory");inventory.register_item(601,1000000)
	var store:=make_store();var pristine:PackedByteArray=store.capture_storage_snapshot()
	check(pristine.size()==48 and store.validate_snapshot(pristine) and store.validate_snapshot(PackedByteArray()),"empty binary log and old-world missing section are supported")
	check(not store.configure(inventory,601),"reward currency schema is immutable")
	check(not store.register_locations(-1,[location()]).ok and store.capture_storage_snapshot()==pristine,"invalid seed makes no mutation")
	var first:=location();var second:=location(2)
	check(store.register_locations(1703,[second,first]).added==2 and store.get_locations()[0].key==1,"generation publishes sorted stable ownership records atomically")
	var registered:PackedByteArray=store.capture_storage_snapshot();var revision:int=store.snapshot().revision
	check(store.register_locations(1703,[first,second]).added==0 and store.snapshot().revision==revision,"repeated identical publication is idempotent")
	check(not store.register_locations(1704,[location(3)]).ok,"another world cannot take over a catalog")
	var conflicting:=location(3);conflicting.residents=first.residents
	check(not store.register_locations(1703,[conflicting]).ok and store.capture_storage_snapshot()==registered,"shared zombie identity rejects the whole registration")
	conflicting=location(3);conflicting.containers=first.containers
	check(not store.register_locations(1703,[conflicting]).ok,"shared chest identity is not jointly owned")
	conflicting=location(3);conflicting.bounds=first.bounds
	check(not store.register_locations(1703,[conflicting]).ok,"overlapping reset regions are rejected")
	conflicting=first.duplicate(true);conflicting.xp=90
	check(not store.register_locations(1703,[location(3),conflicting]).ok and store.capture_storage_snapshot()==registered,"changed definitions cannot partially append or alter reward values")
	for field in ["key","rotation","coins","xp"]:
		conflicting=location(3);conflicting[field]=1.5
		check(not store.register_locations(1703,[conflicting]).ok,"integer metadata rejects coercion: "+field)
	for change in [{"marker":Vector3(NAN,0,0)},{"bounds":AABB(Vector3.ZERO,Vector3(500,2,2))},{"layout":"../outside"},{"title":"bad\nlabel"},{"coins":4294967297},{"residents":PackedInt64Array([6,6])}]:
		conflicting=location(3);conflicting.merge(change,true)
		check(not store.register_locations(1703,[conflicting]).ok,"malformed location rejects: "+str(change.keys()[0]))
	check(store.accept(1,revision).ok and not store.accept(2,revision).ok,"one revision-checked contract may be accepted")
	check(not store.record_defeated(first.residents[0],0).ok,"kills before starting the location do not count")
	var reservation:Dictionary=store.begin_reset(store.snapshot().revision)
	check(reservation.ok and store.snapshot().phase==2,"reset reserves a monotonic encounter token")
	check(not store.validate_snapshot(store.capture_storage_snapshot()),"an unfinished multi-owner reset cannot be published as a valid save")
	check(not store.abandon(store.snapshot().revision).ok and not store.restore_storage_snapshot(pristine),"reset lock rejects abandonment and replacement of live state")
	check(not store.finish_reset(reservation.cycle+1,true,store.snapshot().revision).ok,"another reset token cannot commit")
	check(store.finish_reset(reservation.cycle,false,store.snapshot().revision).ok and store.snapshot().phase==1,"failed reset returns to travel without awarding progress")
	var retry:Dictionary=store.begin_reset(store.snapshot().revision)
	check(retry.cycle>reservation.cycle and store.finish_reset(retry.cycle,true,store.snapshot().revision).ok,"retry receives a new token before activation")
	check(not store.record_defeated(first.residents[0],reservation.cycle).ok and not store.record_defeated(second.residents[0],retry.cycle).ok,"old attempts and other locations cannot advance objectives")
	check(store.record_defeated(first.residents[0],retry.cycle).ok and store.snapshot().defeated==1,"owned defeat advances exactly one objective")
	revision=store.snapshot().revision
	check(store.record_defeated(first.residents[0],retry.cycle).ok and store.snapshot().revision==revision,"duplicate death delivery is idempotent")
	var active:PackedByteArray=store.capture_storage_snapshot();var restored:=make_store()
	check(restored.restore_storage_snapshot(active) and restored.capture_storage_snapshot()==active and restored.snapshot().defeated==1,"active partial objective and its generation identities round-trip exactly")
	var inbox:RefCounted=ClassDB.instantiate("NativeRewardInbox");var progression:RefCounted=ClassDB.instantiate("NativePlayerProgression");progression.configure(PackedInt64Array([1,5,50]))
	check(not restored.claim(inbox,progression,restored.snapshot().revision).ok,"unfinished objectives cannot pay rewards")
	check(restored.record_defeated(first.residents[1],retry.cycle).ok and restored.snapshot().phase==4,"final owned defeat makes the contract returnable")
	var empty_progress:RefCounted=ClassDB.instantiate("NativePlayerProgression")
	check(not restored.claim(inbox,empty_progress,restored.snapshot().revision).ok and inbox.get_pending().is_empty(),"invalid XP owner cannot receive a partial currency reward")
	var full:RefCounted=ClassDB.instantiate("NativeRewardInbox");var items:=PackedInt64Array()
	for identity in 32:items.append_array(PackedInt64Array([1000+identity,1]))
	full.accept(items,1)
	check(not restored.claim(full,progression,restored.snapshot().revision).ok and progression.snapshot().xp==0 and restored.snapshot().phase==4,"full reward escrow leaves XP and quest completion untouched")
	var award:Dictionary=restored.claim(inbox,progression,restored.snapshot().revision)
	check(award.ok and award.coins==20 and award.gained==80 and inbox.get_pending()==PackedInt64Array([601,20]) and progression.snapshot().xp==80,"native reward commits coins, XP and completion together")
	check(not restored.claim(inbox,progression,restored.snapshot().revision).ok and restored.get_locations()[0].completed==1,"completed reward cannot be claimed twice")
	var paid:PackedByteArray=restored.capture_storage_snapshot();var paid_reload:=make_store()
	check(paid_reload.restore_storage_snapshot(paid) and paid_reload.capture_storage_snapshot()==paid,"claimed state persists without resurrecting reward eligibility")
	check(restored.accept(1,restored.snapshot().revision).ok and restored.abandon(restored.snapshot().revision).ok,"repeat contract can be accepted then cancelled without undoing past rewards")
	var malformed:=active.duplicate();malformed.encode_u32(28,2)
	check(not store.validate_snapshot(malformed),"persisted resetting state is rejected")
	malformed=active.duplicate();malformed.encode_u32(32,128)
	check(not store.validate_snapshot(malformed),"objective mask cannot reference nonexistent residents")
	malformed=active.duplicate();malformed.encode_u32(28,4)
	check(not store.validate_snapshot(malformed),"return state requires all objective bits")
	malformed=active.duplicate();malformed.encode_u32(40,602)
	check(not store.validate_snapshot(malformed),"binary currency schema mismatch is rejected")
	malformed=active.duplicate();malformed.encode_u32(48+76,retry.cycle)
	check(not store.validate_snapshot(malformed),"an active cycle cannot already have paid all recorded resets")
	malformed=active.duplicate();malformed.set(48+84+2,0)
	check(not store.validate_snapshot(malformed),"binary text cannot silently truncate at an embedded null")
	malformed=active.duplicate();malformed.append(0)
	check(not store.validate_snapshot(malformed),"trailing bytes are rejected")
	var truncations:=true
	for count in range(1,active.size()):
		if store.validate_snapshot(active.slice(0,count)):truncations=false;break
	check(truncations,"every truncated binary prefix rejects safely")
	check(not paid_reload.restore_storage_snapshot(malformed) and paid_reload.capture_storage_snapshot()==paid,"malformed restore leaves live state unchanged")
	var maximum:=make_store();var definitions:Array=[]
	for identity in range(1,129):
		var full_location:=location(identity);full_location.residents=PackedInt64Array();full_location.containers=PackedInt64Array()
		for target in 32:full_location.residents.append(identity*32+target)
		for target in 16:full_location.containers.append(identity*16+target)
		definitions.append(full_location)
	check(maximum.register_locations(1703,definitions).ok and maximum.snapshot().locations==128,"full bounded location catalog is supported")
	var maximum_bytes:PackedByteArray=maximum.capture_storage_snapshot();var before:=Time.get_ticks_usec()
	check(maximum.validate_snapshot(maximum_bytes) and maximum_bytes.size()<131072,"maximum location catalog stays within the binary storage bound")
	print("QUEST_CATALOG bytes=",maximum_bytes.size()," validation_us=",Time.get_ticks_usec()-before)
	check(not maximum.register_locations(1703,[location(129)]).ok and maximum.capture_storage_snapshot()==maximum_bytes,"catalog overflow preserves all prior locations")
	maximum.accept(1,maximum.snapshot().revision);var full_cycle:Dictionary=maximum.begin_reset(maximum.snapshot().revision);maximum.finish_reset(full_cycle.cycle,true,maximum.snapshot().revision)
	for target in definitions[0].residents:maximum.record_defeated(target,full_cycle.cycle)
	check(maximum.snapshot().phase==4 and maximum.snapshot().defeated==32 and maximum.validate_snapshot(maximum.capture_storage_snapshot()),"all 32 objective bits including the unsigned high bit survive binary validation")
	print("QUESTS_NATIVE checks=",checks," failures=",failures);quit(1 if failures else 0)
