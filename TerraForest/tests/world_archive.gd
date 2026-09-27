extends SceneTree
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ",label)
func resign(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes.slice(8,16))
	hash.update(bytes.slice(48))
	var digest: PackedByteArray = hash.finish()
	for i in range(32): bytes[16+i] = digest[i]
	return bytes
func run() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	GDExtensionManager.load_extension("res://addons/volumetric_water/volumetric_water.gdextension")
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	var catalog: RefCounted = ClassDB.instantiate("NativeLakeCatalog")
	var record: Dictionary = {"id":7,"origin":Vector3(2,10,2),"cells":Vector3i(16,16,16),"spacing":1.0,"level":20.0,"seed":Vector3(10,15,10)}
	var water: PackedByteArray = catalog.encode([record])
	check(water.size()==76 and catalog.decode(water)["records"][0]==record,"native lake catalog round-trips stable IDs and definitions")
	check(catalog.decode(catalog.encode([],500))["next_id"]==500,"empty catalog retains persistent ID allocation cursor")
	check(catalog.encode([record],7).is_empty(),"catalog rejects cursor that would reuse a live ID")
	check(catalog.encode([record,record]).is_empty(),"duplicate lake IDs rejected")
	var bad: Dictionary = record.duplicate()
	bad["level"] = NAN
	check(catalog.encode([bad]).is_empty(),"nonfinite lake definition rejected")
	var invalid_water: PackedByteArray = water.duplicate()
	invalid_water.encode_u32(20+52,1)
	check(not catalog.validate_snapshot(invalid_water),"unsupported lake record flags rejected")
	check(not catalog.validate_snapshot(water.slice(0,-1)),"truncated lake definition rejected")
	var sections := {"volumetric_water":water,"terrain":PackedByteArray([1,2,3]),"future_addon":PackedByteArray([9,8,7])}
	var first: PackedByteArray = archive.encode(sections)
	var reordered := {"future_addon":sections["future_addon"],"terrain":sections["terrain"],"volumetric_water":water}
	check(first==archive.encode(reordered),"archive byte representation independent of dictionary insertion order")
	var restored: Dictionary = archive.decode(first)
	check(restored["ok"] and restored["sections"]==sections,"native archive round-trips opaque addon sections")
	check(archive.encode({"terrain":"wrong type"}).is_empty(),"section value type checked")
	check(archive.encode({"terrain":PackedByteArray(),"UPPER":PackedByteArray()}).is_empty(),"noncanonical section name rejected")
	check(archive.encode({"missing_terrain":water}).is_empty(),"required terrain section enforced")
	var mutated: PackedByteArray = first.duplicate()
	mutated[-1] ^= 1
	check(not archive.decode(mutated)["ok"],"payload corruption detected by SHA-256")
	mutated = first.duplicate()
	mutated.encode_u32(8,2)
	check(not archive.decode(mutated)["ok"],"unsupported archive schema rejected")
	mutated = first.duplicate()
	mutated.encode_u32(52,0xffffffff)
	check(not archive.decode(resign(mutated))["ok"],"authenticated oversized section length rejected before allocation")
	mutated = first.duplicate()
	mutated.append(1)
	check(not archive.decode(resign(mutated))["ok"],"authenticated trailing bytes rejected")
	check(not archive.decode(first.slice(0,-1))["ok"],"truncated archive rejected")
	var path: String = ProjectSettings.globalize_path("user://archive_test_%d.tfworld" % OS.get_process_id())
	var other: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	check(archive.acquire(path) and not other.acquire(path),"exclusive save lease rejects competing writer")
	check(other.publish(path,first)!=OK,"unleased writer cannot publish")
	check(archive.publish(path,first)==OK and archive.read(path)==first,"native file write flushed verified and published")
	sections["terrain"] = PackedByteArray([4,5,6])
	var second: PackedByteArray = archive.encode(sections)
	check(archive.publish(path,second)==OK and archive.read(path)==second and archive.read(path+".bak")==first,"atomic replacement retains previous full snapshot backup")
	check(archive.publish(path,mutated)!=OK and archive.read(path)==second,"invalid publication leaves canonical save untouched")
	archive.release()
	check(other.acquire(path),"save lease released for next owner")
	other.release()
	for suffix in ["",".bak",".lock"]:
		DirAccess.remove_absolute(path+suffix)
	DirAccess.make_dir_recursive_absolute("res://reports")
	var report := FileAccess.open("res://reports/world_archive.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
	report.close()
	quit(0 if failures==0 else 1)
