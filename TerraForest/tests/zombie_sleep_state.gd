# SPDX-License-Identifier: 0BSD
extends SceneTree
var checks:=0
var failures:=0
var folder:=""
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func run()->void:
	if not ClassDB.class_exists("NativeZombiePopulation"):GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	var read_path:=""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--sleeper-output="):folder=argument.trim_prefix("--sleeper-output=")
		if argument.begins_with("--sleep-read="):read_path=argument.trim_prefix("--sleep-read=")
	var store=ClassDB.instantiate("NativeZombiePopulation")
	var brain=ClassDB.instantiate("NativeZombieAwareness");brain.configure(6,1703);brain.add_agent(1,Vector3(11,0,12))
	var validator=ClassDB.instantiate("NativeZombiePosture")
	if not read_path.is_empty():
		var restored:=FileAccess.get_file_as_bytes(read_path)
		check(store.restore_snapshot(restored) and store.capture_snapshot()==restored,"fresh process preserves version-three resident bytes exactly")
		var sleep:PackedByteArray=store.resident(1).sleep
		check(validator.validate_snapshot(sleep) and brain.restore_sleep(1,sleep.slice(0,28)),"fresh process restores matching physical and native wake state")
		check(brain.status(1).state=="waking" and absf(brain.status(1).wake_elapsed-1.25)<.00001 and brain.status(1).goal==Vector3(10,0,10),"fresh process retains elapsed time and last heard source")
		finish();return
	check(store.initialize(1703,Vector3(800,0,1310)),"population initializes without touching a world save")
	var legacy:PackedByteArray=store.capture_snapshot()
	check(brain.set_sleeping(1,2),"sleeping intent initializes")
	var asleep:PackedByteArray=brain.capture_sleep(1)
	var other=ClassDB.instantiate("NativeZombieAwareness");other.configure(6,1);other.add_agent(1,Vector3(11,0,12))
	check(other.restore_sleep(1,asleep) and other.capture_sleep(1)==asleep,"sleep intent roundtrips without waking")
	brain.provoke(1,Vector3(10,0,10))
	for frame in 75:brain.advance(1,Vector3(11,0,12),1./60.,true,"none")
	var waking:PackedByteArray=brain.capture_sleep(1)
	var physical:=PackedByteArray();physical.resize(16);physical.fill(0);physical.encode_u32(0,2);physical.encode_u32(4,2);physical.encode_float(12,.9)
	var combined:=waking.duplicate();combined.append_array(physical)
	check(validator.validate_snapshot(combined),"44-byte state binds native intent to the same physical pose")
	var vitals:=PackedByteArray();vitals.resize(60);vitals.fill(0)
	var maximum:=[180.,50.,50.,38.,24.,50.,38.,24.,65.,52.,32.,65.,52.,32.]
	for part in 14:vitals.encode_float(part*4,maximum[part])
	check(store.update_resident(1,Vector3(11,0,12),.5,vitals,combined),"living resident stores the full sleeper state atomically")
	var saved:PackedByteArray=store.capture_snapshot()
	check(saved.decode_u32(4)==3 and saved.size()==330032,"sleepers use a bounded version-three binary layout")
	check(store.restore_snapshot(saved) and store.capture_snapshot()==saved and store.resident(1).sleep==combined,"version-three roundtrip preserves every sleep and health byte")
	FileAccess.open(folder.path_join("population_sleep.bin"),FileAccess.WRITE).store_buffer(saved)
	for offset in [0,4,24,28,32,36]:
		var broken:=combined.duplicate();broken.encode_u32(offset,99)
		check(not validator.validate_snapshot(broken) and not store.update_resident(1,Vector3(11,0,12),0,vitals,broken) and store.capture_snapshot()==saved,"invalid sleep identity/state/flags reject atomically at %d"%offset)
	for offset in [8,12,16,20,40]:
		var broken:=combined.duplicate();broken.encode_float(offset,NAN)
		check(not validator.validate_snapshot(broken),"nonfinite intent/pose rejects at %d"%offset)
	var broken:=combined.duplicate();broken.encode_u32(28,1)
	check(not validator.validate_snapshot(broken),"mismatched seated/lying components reject")
	broken=combined.duplicate();broken.encode_float(40,6.)
	check(not validator.validate_snapshot(broken),"animation cursor beyond the authored clip rejects")
	broken=saved.duplicate();broken.encode_u32(32+84,45)
	check(not store.restore_snapshot(broken) and store.capture_snapshot()==saved,"corrupt population sleep length cannot replace live records")
	check(not store.validate_snapshot(saved.slice(0,saved.size()-1)),"truncated version-three file rejects")
	var dead:=vitals.duplicate();dead.encode_float(0,0.)
	check(not store.update_resident(1,Vector3(11,0,12),0,dead,combined),"dead residents cannot retain sleeping intent")
	check(store.update_resident(1,Vector3(11,0,12),0,dead) and store.resident(1).sleep.is_empty(),"death clears sleeper state without allowing resurrection")
	check(store.restore_snapshot(legacy) and store.capture_snapshot()==legacy,"old version-one population remains byte compatible")
	finish()
func finish()->void:
	print("ZOMBIE_SLEEPERS_STATE checks=",checks," failures=",failures)
	quit(1 if failures else 0)
