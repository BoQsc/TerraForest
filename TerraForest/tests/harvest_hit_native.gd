extends SceneTree

var checks:=0
var failures:=0
func check(condition:bool,label:String)->void:
	checks+=1;print("PASS " if condition else "FAIL ",label)
	if not condition:failures+=1
func inventory()->RefCounted:
	var result:RefCounted=ClassDB.instantiate("NativePlayerInventory");result.register_item(102,999);result.register_item(201,999);return result
func amount(store:RefCounted,item:int)->int:
	var total:=0
	for row:Dictionary in store.snapshot().slots:
		if row.item==item:total+=row.count
	return total
func _initialize()->void:
	var extension:="res://addons/player_runtime/player_runtime.gdextension"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--native-extension="):extension=argument.trim_prefix("--native-extension=")
	GDExtensionManager.load_extension(extension)
	var health:RefCounted=ClassDB.instantiate("NativeWorldDurability");var bag:=inventory()
	var planned:Dictionary=health.preview_harvest("tree:1",90,30,30,1)
	check(planned.ok and planned.reward_count==1 and health.record_count()==0 and amount(bag,102)==0,"harvest quote is read-only")
	var first:Dictionary=health.harvest_hit("tree:1",90,30,102,30,1,bag,bag.snapshot().revision)
	check(first.ok and first.applied==30 and first.reward_count==1 and first.remaining==60 and amount(bag,102)==1,"accepted damaging hit grants resources atomically")
	var damage:PackedByteArray=health.capture_storage_snapshot();var items:PackedByteArray=bag.capture_storage_snapshot()
	var restored:RefCounted=ClassDB.instantiate("NativeWorldDurability");var restored_bag:=inventory()
	check(restored.restore_storage_snapshot(damage) and restored_bag.restore_storage_snapshot(items),"existing damage and inventory formats retain harvest progress")
	var next:Dictionary=restored.harvest_hit("tree:1",90,30,102,30,1,restored_bag,restored_bag.snapshot().revision)
	check(next.reward_count==1 and amount(restored_bag,102)==2,"reloading pays only new damage, not previous hits")
	var final:Dictionary=restored.harvest_hit("tree:1",90,999,102,30,1,restored_bag,restored_bag.snapshot().revision)
	check(final.destroyed and final.applied==30 and final.reward_count==2 and amount(restored_bag,102)==4,"overkill clips to real damage and final hit adds an extra bonus")
	var repeat:Dictionary=restored.harvest_hit("tree:1",90,30,102,30,1,restored_bag,restored_bag.snapshot().revision)
	check(repeat.applied==0 and repeat.reward_count==0 and amount(restored_bag,102)==4,"already-lethal target cannot pay again on a retry")
	var weak:RefCounted=ClassDB.instantiate("NativeWorldDurability");var weak_bag:=inventory()
	for strike in 18:weak.harvest_hit("tree:1",90,5,102,30,1,weak_bag,weak_bag.snapshot().revision)
	check(amount(weak_bag,102)==4,"many weak hits cannot increase the total resource yield")
	var legacy:RefCounted=ClassDB.instantiate("NativeWorldDurability");var legacy_bag:=inventory();legacy.hit("stone:old",360,90)
	check(legacy.harvest_hit("stone:old",360,30,201,30,1,legacy_bag,legacy_bag.snapshot().revision).reward_count==1,"older saved partial damage does not grant retroactive rewards")
	var before:PackedByteArray=health.capture_storage_snapshot();var original:PackedByteArray=bag.capture_storage_snapshot();var revision:int=bag.snapshot().revision
	check(not health.harvest_hit("tree:1",90,30,102,30,1,bag,revision-1).ok and health.capture_storage_snapshot()==before and bag.capture_storage_snapshot()==original,"stale inventory rejects without damage or rewards")
	check(not health.harvest_hit("bad",90,30,9999,30,1,bag,revision).ok and health.capture_storage_snapshot()==before,"unknown resource item cannot consume damage progress")
	check(not health.harvest_hit("bad",90,5,9999,30,1,bag,revision).ok and health.capture_storage_snapshot()==before,"unknown item also rejects a non-paying partial hit")
	check(not health.harvest_hit("bad",90,30,102,0,1,bag,revision).ok and health.capture_storage_snapshot()==before,"invalid reward interval is rejected")
	var full:=inventory();full.grant(201,32*999,full.snapshot().revision);var full_revision:int=full.snapshot().revision
	check(not health.harvest_hit("tree:1",90,30,102,30,1,full,full_revision).ok and health.capture_storage_snapshot()==before and full.snapshot().revision==full_revision,"full inventory rejects atomically without damage or revision changes")
	check(health.validate_snapshot(before),"harvested damage uses the existing validated sparse snapshot")
	var crowded:RefCounted=ClassDB.instantiate("NativeWorldDurability");var benchmark_bag:=inventory()
	for index in 10000:crowded.hit("tree:%d"%index,90,1)
	var begin:=Time.get_ticks_usec()
	for index in 1000:crowded.harvest_hit("tree:%d"%index,90,30,102,30,1,benchmark_bag,benchmark_bag.snapshot().revision)
	var elapsed:=Time.get_ticks_usec()-begin
	check(amount(benchmark_bag,102)==1000 and crowded.record_count()==10000,"one thousand rewards with ten thousand damaged nodes remain bounded and exact")
	DirAccess.make_dir_recursive_absolute("res://reports")
	FileAccess.open("res://reports/harvest_hit_native.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"1000_hits_at_10000_nodes_us":elapsed},"  "))
	print("HARVEST_1000_HITS_AT_10000_NODES_US=",elapsed)
	print("HARVEST_HIT_NATIVE checks=",checks," failures=",failures);quit(1 if failures else 0)
