# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	var source=ClassDB.instantiate("NativeBlockPrefab")
	source.configure(PackedInt32Array([0,0,0,1]))
	var item := {"model":"furniture/table/v1","transform":Transform3D(Basis.IDENTITY,Vector3(0.25,1,0.75))}
	check(source.configure_model_attachments([item]),"authored model attachment accepted")
	item.model="furniture/chair/v1"
	var copy: Array=source.get_model_attachments();copy[0].model="furniture/shelf/v1"
	check(source.get_model_attachments()[0].model=="furniture/table/v1","input and output cannot mutate native ownership")
	var assembled=ClassDB.instantiate("NativeBlockPrefab")
	for turn in range(4):
		check(assembled.compose([source],PackedInt32Array([0,10,20,30,turn])),"compose attachment quarter turn %d"%turn)
		var expected:=Vector3(0.25,1,0.75)
		for r in range(turn):expected=Vector3(1-expected.z,expected.y,expected.x)
		expected+=Vector3(10,20,30)
		var pose: Transform3D=assembled.get_model_attachments()[0].transform
		check(pose.origin.is_equal_approx(expected),"model follows cell-centred block rotation %d"%turn)
	var before: Array=assembled.get_model_attachments();var blocks: PackedInt32Array=assembled.get_records()
	check(not assembled.compose([source],PackedInt32Array([0,0,0,0,0,0,0,0,0,0])) and assembled.get_records()==blocks and assembled.get_model_attachments()==before,"overlapping block rejection preserves complete prefab")
	for bad: Variant in [42,{}, {"model":"../invalid","transform":Transform3D.IDENTITY}, {"model":"valid/v1","transform":Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)}, {"model":"valid/v1","transform":Transform3D(Basis.IDENTITY,Vector3(NAN,0,0))}]:
		check(not assembled.configure_model_attachments([bad]) and assembled.get_model_attachments()==before,"malformed attachment rejected without mutation")
	var many: Array=[];many.resize(4097);many.fill(source.get_model_attachments()[0])
	check(not source.configure_model_attachments(many),"attachment count bound enforced")
	many.resize(2049);check(source.configure_model_attachments(many),"bounded dense source admitted")
	check(not assembled.compose([source],PackedInt32Array([0,0,0,0,0,0,2,0,0,0])) and assembled.get_model_attachments()==before and assembled.get_records()==blocks,"composition count overflow is transactional")

	var bounded=ClassDB.instantiate("NativeBlockPrefab")
	many.resize(2048);source.configure_model_attachments(many)
	check(bounded.compose([source],PackedInt32Array([0,0,0,0,0,0,2,0,0,0])) and bounded.get_model_attachments().size()==4096,"maximum attachment count composes")
	source.configure_model_attachments([{"model":"valid/v1","transform":Transform3D(Basis.IDENTITY,Vector3(4096,0,0))}])
	check(not assembled.compose([source],PackedInt32Array([0,1,0,0,0])) and assembled.get_model_attachments()==before and assembled.get_records()==blocks,"transformed attachment outside coordinate bounds rejects atomically")
	source.configure_model_attachments([{"model":"furniture/table/v1","transform":Transform3D.IDENTITY}])
	var path: String="user://attached_prefab_%d.res"%Time.get_ticks_usec()
	check(ResourceSaver.save(assembled,path)==OK,"combined resource saves")
	var restored=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.get_model_attachments()==before and restored.get_records()==blocks,"resource reload preserves exact models and blocks")
	DirAccess.remove_absolute(path)
	var library=preload("res://addons/structures/prefab_library.gd").new()
	library.directory="user://attached_library_%d"%Time.get_ticks_usec()
	check(library.begin_frontage_sources([source],2,8,3,1703,"Attached settlement",2).ok,"worker admits attached sources")
	source.configure_model_attachments([])
	var result: Dictionary={};var deadline:=Time.get_ticks_msec()+10000
	while result.is_empty() and Time.get_ticks_msec()<deadline: result=library.poll_frontage();await process_frame
	check(result.get("ok",false) and result.asset.get_model_attachments().size()==8,"nested settlement composition retains captured attachments")
	if result.get("ok",false):
		var loaded=ResourceLoader.load(result.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		check(loaded.get_model_attachments()==result.asset.get_model_attachments(),"worker-produced resource retains exact attachments")
		DirAccess.remove_absolute(result.path)
	library.shutdown_frontage();DirAccess.remove_absolute(library.directory)
	check(assembled.configure(PackedInt32Array([0,0,0,1])) and assembled.get_model_attachments().is_empty(),"replacing block definition clears stale attachments")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output:=FileAccess.open("res://reports/prefab_model_attachments.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures}));output.close()
	print("PREFAB_ATTACHMENTS checks=%d failures=%d"%[checks,failures]);quit(1 if failures else 0)
