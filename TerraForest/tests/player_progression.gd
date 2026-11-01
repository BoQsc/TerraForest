# SPDX-License-Identifier: 0BSD
extends SceneTree

var checks:=0
var failures:=0
var DEFINITIONS:=PackedInt64Array([1,5,50,2,5,50,3,5,50])

func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)

func _initialize()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var store:RefCounted=ClassDB.instantiate("NativePlayerProgression")
	check(not store.configure(PackedInt64Array([2,5,50,1,5,50])) and not store.configure(PackedInt64Array([1,21,50])) and not store.configure(PackedInt64Array([1,5,251])),"invalid catalogs rejected atomically")
	check(store.configure(DEFINITIONS) and not store.configure(DEFINITIONS),"bounded catalog configured exactly once")
	var empty:PackedByteArray=store.capture_storage_snapshot()
	check(empty.size()==48 and store.validate_snapshot(empty),"three skills need a 48-byte binary component")
	check(store.snapshot().level==1 and store.snapshot().points==0 and store.snapshot().xp==0,"new character starts without fabricated experience")
	check(not store.spend(1,0).ok and not store.award(0,0).ok and not store.award(1000001,0).ok,"no free points or invalid awards")
	check(store.award(249,0).gained==249 and store.snapshot().level==1,"XP stays below first threshold")
	var unchanged:PackedByteArray=store.capture_storage_snapshot()
	check(not store.award(249,0).ok and store.capture_storage_snapshot()==unchanged,"same revision cannot replay an award")
	check(store.award(1,store.snapshot().revision).levels==1 and store.snapshot().points==1,"crossing threshold earns one skill point")
	var old_revision:int=store.snapshot().revision
	check(store.spend(1,old_revision).ok and store.snapshot().skills[1]==1 and store.snapshot().points==0,"native spend exchanges exactly one point for one rank")
	check(not store.spend(2,old_revision).ok and not store.spend(999,store.snapshot().revision).ok,"stale clicks and unknown skills cannot spend")
	check(store.scale_action(1,30)==32 and store.scale_action(2,30)==30 and store.scale_action(999,30)==30 and store.scale_action(1,-1)==0,"native skill bonus only changes its selected action")
	check(store.award(500,store.snapshot().revision).levels==1 and store.spend(2,store.snapshot().revision).ok,"next level supports a different skill")
	var saved:PackedByteArray=store.capture_storage_snapshot()
	var clone:RefCounted=ClassDB.instantiate("NativePlayerProgression");clone.configure(DEFINITIONS)
	check(clone.restore_storage_snapshot(saved) and clone.capture_storage_snapshot()==saved and clone.snapshot().points==0,"exact binary XP and rank restoration")
	var expanded:RefCounted=ClassDB.instantiate("NativePlayerProgression")
	expanded.configure(PackedInt64Array([1,5,50,2,5,50,3,5,50,4,5,50]))
	check(expanded.restore_storage_snapshot(saved) and expanded.snapshot().skills[1]==1 and expanded.snapshot().skills[4]==0 and expanded.snapshot().xp==750,"adding a stable skill identity preserves old saves and starts its rank at zero")
	var removed:RefCounted=ClassDB.instantiate("NativePlayerProgression");removed.configure(PackedInt64Array([1,5,50,3,5,50]))
	check(not removed.restore_storage_snapshot(saved),"removing a saved skill needs an explicit migration instead of silently losing points")
	var malformed:Array[PackedByteArray]=[]
	for offset in [0,4,8,12,24,32]:
		var bytes:=saved.duplicate();bytes.encode_u32(offset,999999);malformed.append(bytes)
	var bytes:=saved.duplicate();bytes.encode_u64(16,9223372036854775807);malformed.append(bytes)
	bytes=saved.duplicate();bytes.encode_u32(28,6);malformed.append(bytes)
	bytes=saved.duplicate();bytes.encode_u32(44,1);malformed.append(bytes)
	bytes=saved.duplicate();bytes.append(0);malformed.append(bytes)
	for length in saved.size():malformed.append(saved.slice(0,length))
	var rejected:=true
	for candidate:PackedByteArray in malformed:
		rejected=rejected and not clone.validate_snapshot(candidate) and not clone.restore_storage_snapshot(candidate) and clone.capture_storage_snapshot()==saved
	check(rejected,"malformed, over-budget, truncated and extended saves never mutate live progression")
	var capped:Dictionary=store.award(1000000,store.snapshot().revision)
	check(capped.gained==305500 and store.snapshot().level==50 and store.snapshot().points==47,"large awards cap safely and preserve spent point accounting")
	var maximum_revision:int=store.snapshot().revision
	check(store.award(1,maximum_revision).gained==0 and store.snapshot().revision==maximum_revision,"maximum-level rewards do not create dirty state")
	for rank in 4:check(store.spend(1,store.snapshot().revision).ok,"successive skill rank "+str(rank+2))
	check(not store.spend(1,store.snapshot().revision).ok and store.scale_action(1,100)==125,"rank cap and full bonus agree")
	var maximum:RefCounted=ClassDB.instantiate("NativePlayerProgression");var catalog:=PackedInt64Array()
	for identity in range(1,33):catalog.append_array(PackedInt64Array([identity,20,250]))
	check(maximum.configure(catalog) and maximum.capture_storage_snapshot().size()==280,"maximum 32-skill schema stays bounded")
	var too_large:RefCounted=ClassDB.instantiate("NativePlayerProgression");catalog.append_array(PackedInt64Array([33,5,50]))
	check(not too_large.configure(catalog),"oversized mod catalog is rejected")
	var elapsed:=Time.get_ticks_usec()
	for index in 10000:store.scale_action(3,30)
	elapsed=Time.get_ticks_usec()-elapsed
	check(store.restore_storage_snapshot(empty) and store.snapshot().xp==0 and store.snapshot().skills[1]==0,"missing legacy component default resets without carrying another world's skills")
	print("PLAYER_PROGRESSION ",JSON.stringify({"checks":checks,"failures":failures,"scale_10000_us":elapsed,"bytes":saved.size()}))
	quit(1 if failures else 0)
