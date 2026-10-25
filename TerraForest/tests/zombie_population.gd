extends SceneTree
var checks := 0
var failures := 0
var folder := "res://reports/zombie_population"
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void:run.call_deferred()
func run() -> void:
	if not ClassDB.class_exists("NativeZombiePopulation"):GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeZombiePopulation"):push_error("Native zombie population unavailable");quit(1);return
	var read_path := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--population-output="):folder = argument.trim_prefix("--population-output=")
		if argument.begins_with("--population-read="):read_path = argument.trim_prefix("--population-read=")
	DirAccess.make_dir_recursive_absolute(folder)
	var store = ClassDB.instantiate("NativeZombiePopulation")
	if not read_path.is_empty():
		var bytes := FileAccess.get_file_as_bytes(read_path)
		check(store.restore_snapshot(bytes), "fresh process restores population bytes")
		check(store.capture_snapshot() == bytes, "fresh process preserves every identity and injury byte")
		check(store.resident(1).state == 2, "fresh process retains dead resident tombstone")
		if store.statistics().slots>2500:check(store.resident(2501).state==1 and not store.resident(2501).vitals.is_empty(), "fresh process retains developer-spawned resident and injuries")
		finish();return
	check(store.validate_snapshot(PackedByteArray()), "older worlds accept an absent population section")
	check(store.initialize(1703, Vector3(800, 0, 1310)), "seeded world population initializes")
	check(store.statistics().slots == 2500, "whole world has bounded native population slots before activation")
	var baseline: PackedByteArray = store.capture_snapshot()
	var other = ClassDB.instantiate("NativeZombiePopulation")
	check(other.initialize(1703, Vector3(800, 0, 1310)) and other.capture_snapshot() == baseline, "same world seed produces identical world positions")
	check(not store.initialize(9, Vector3.ZERO) and store.capture_snapshot() == baseline, "different seed cannot overwrite an existing population")
	var nearby: Array = store.nearby(Vector3(800, 80, 1310), 88.0)
	check(not nearby.is_empty() and nearby.size() <= 32, "spatial query returns bounded local residents")
	var safe := true
	for record: Dictionary in nearby:
		var offset: Vector3 = record.position - Vector3(800, 0, 1310);offset.y = 0
		safe = safe and offset.length() >= 40.0
	check(safe, "world arrival sanctuary is free of generated zombies")
	store.nearby(Vector3(1300, 80, 120), 88.0)
	check(store.nearby(Vector3(800, 80, 1310), 88.0) == nearby and store.capture_snapshot() == baseline, "moving focus never creates or relocates inhabitants")
	var anatomy = ClassDB.instantiate("NativeZombieAnatomy")
	var definitions := {}
	var names := ["torso", "head", "upper_arm_l", "forearm_l", "hand_l", "upper_arm_r", "forearm_r", "hand_r", "thigh_l", "shin_l", "foot_l", "thigh_r", "shin_r", "foot_r"]
	var maximum := [180, 50, 50, 38, 24, 50, 38, 24, 65, 52, 32, 65, 52, 32]
	var parents := [-1, 0, 0, 2, 3, 0, 5, 6, 0, 8, 9, 0, 11, 12]
	for index in names.size():definitions[names[index]] = {"health":maximum[index], "parent":names[parents[index]] if parents[index] >= 0 else ""}
	check(anatomy.configure(definitions), "anatomy persistence fixture configures")
	anatomy.hit("upper_arm_l", 20.0, false, "melee")
	var wound: PackedByteArray = anatomy.capture_vitals()
	var copy = ClassDB.instantiate("NativeZombieAnatomy")
	copy.configure(definitions)
	check(copy.restore_vitals(wound) and copy.capture_vitals() == wound, "shared body health and separate limb health roundtrip")
	var broken := wound.duplicate();broken.encode_float(0, NAN)
	check(not copy.restore_vitals(broken) and copy.capture_vitals() == wound, "invalid anatomy restore is atomic")
	anatomy.detach("shin_l")
	var amputated: PackedByteArray = anatomy.capture_vitals()
	check(copy.restore_vitals(amputated) and copy.snapshot().missing.shin_l and copy.snapshot().missing.foot_l, "detached limb chain roundtrips without healing")
	check(store.update_resident(1, Vector3(500, 80, 500), 1.3, wound), "live record stores moved position and injury")
	check(store.nearby(Vector3(500, 80, 500), 5.0).any(func(record):return record.id == 1), "native spatial index follows resident movement")
	anatomy.kill()
	check(store.update_resident(1, Vector3(500, 80, 500), 1.3, anatomy.capture_vitals()), "death persists in the population independently of loot")
	check(not store.nearby(Vector3(500, 80, 500), 5.0).any(func(record):return record.id == 1), "dead resident is never selected for activation")
	check(not store.update_resident(1, Vector3(500, 80, 500), 0, wound), "dead resident cannot be resurrected by stale synchronization")
	check(store.update_resident(2, Vector3(520, 80, 500), 0, amputated), "injured survivor stores severed limb state")
	check(store.exclude(3), "unsuitable ground excludes only its own unplaced slot")
	var saved: PackedByteArray = store.capture_snapshot()
	check(saved.size() == 210032 and other.restore_snapshot(saved) and other.capture_snapshot() == saved, "bounded binary population roundtrip preserves all records")
	broken = saved.duplicate();broken.encode_u32(32 + 16, 9)
	check(not other.restore_snapshot(broken) and other.capture_snapshot() == saved, "corrupt state is rejected without replacing live records")
	broken = saved.duplicate();broken.encode_float(32, INF)
	check(not other.validate_snapshot(broken), "nonfinite saved position rejects")
	check(not other.validate_snapshot(saved.slice(0, saved.size() - 1)), "truncated binary population rejects")
	broken = saved.duplicate();broken.encode_float(32 + 84 + 24, 181)
	check(not other.validate_snapshot(broken), "population validates anatomical maximum before loading")
	broken = saved.duplicate();broken.encode_u32(32 + 84 + 24 + 56, 1 << 9)
	check(not other.validate_snapshot(broken), "population rejects inconsistent missing limb chains")
	check(not other.update_resident(0, Vector3.ZERO, 0, wound), "invalid identity rejects")
	var added:int=other.add_resident(Vector3(800,80,1310),0,wound)
	check(added==2501 and other.resident(added).vitals==wound, "explicit developer zombie gets an independent saved identity even inside sanctuary")
	var expanded:PackedByteArray=other.capture_snapshot()
	FileAccess.open(folder.path_join("population_extended.bin"),FileAccess.WRITE).store_buffer(expanded)
	check(expanded.decode_u32(4)==2 and store.restore_snapshot(expanded) and store.capture_snapshot()==expanded, "extended population roundtrip preserves added residents without changing legacy records")
	check(store.nearby(Vector3(800,80,1310),5).any(func(record):return record.id==added), "added resident enters native spatial index")
	check(store.add_resident(Vector3.INF,0,wound)==0 and store.add_resident(Vector3.ZERO,0,PackedByteArray())==0 and store.capture_snapshot()==expanded, "invalid additions are atomic")
	broken=expanded.duplicate();broken.encode_u32(12,2757)
	check(not store.restore_snapshot(broken) and store.capture_snapshot()==expanded, "oversized extended population is rejected atomically")
	for index in 255:other.add_resident(Vector3(810,80,1310),0,wound)
	var capped:PackedByteArray=other.capture_snapshot()
	check(other.statistics().slots==2756 and other.add_resident(Vector3.ZERO,0,wound)==0 and other.capture_snapshot()==capped, "developer additions retain a fixed 256-record budget")
	check(other.restore_snapshot(saved) and other.capture_snapshot()==saved, "original version-one saves still restore byte exactly after extended use")
	FileAccess.open(folder.path_join("population.bin"), FileAccess.WRITE).store_buffer(saved)
	finish()
func finish() -> void:
	FileAccess.open(folder.path_join("result.json"), FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures}, "  "))
	if folder == "res://reports/zombie_population":FileAccess.open("res://reports/zombie_population.json", FileAccess.WRITE).store_string(JSON.stringify({"checks":checks, "failures":failures}))
	print("ZOMBIE_POPULATION checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
