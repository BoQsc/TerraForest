extends SceneTree

var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var fixtures:="res://tests/fixtures"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--module-fixtures="):fixtures=argument.trim_prefix("--module-fixtures=")
	var directory:="user://mods/vehicle_pack_check_%d"%OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var prefix:="res://mods/vehicle_pack_check_%d/"%OS.get_process_id()
	var original:=FileAccess.get_sha256("res://addons/vehicle_runtime/ranger.module.json")
	var files:={"vehicle.tscn":FileAccess.get_file_as_string(fixtures.path_join("module_vehicle.tscn")),"adapter.gd":FileAccess.get_file_as_string(fixtures.path_join("module_vehicle.gd")),"test.module.json":JSON.stringify({"api":1,"id":"test.external","providers":[{"capability":"vehicle","id":"test.external.cart.v1","name":"External test cart","scene":prefix+"vehicle.tscn","adapter":prefix+"adapter.gd"}]}),"replacement.json":"{}"}
	for name:String in files:
		FileAccess.open(directory.path_join(name),FileAccess.WRITE).store_string(files[name])
	var pack:=PCKPacker.new()
	var archive:=directory.path_join("test.pck")
	check(pack.pck_start(archive)==OK,"external module archive starts")
	for name:String in files:
		var target:="res://addons/vehicle_runtime/ranger.module.json" if name=="replacement.json" else prefix+name
		check(pack.add_file(target,directory.path_join(name))==OK,"external pack includes "+name)
	check(pack.flush()==OK,"external pack finalizes")
	var config:=ConfigFile.new()
	config.set_value("modules","trusted_packs",PackedStringArray([archive]))
	config.set_value("modules","trusted_manifests",PackedStringArray([prefix+"test.module.json"]))
	var config_path:=directory.path_join("enabled.cfg");config.save(config_path)
	var packs=load("res://addons/vehicle_runtime/vehicle_packs.gd").new()
	packs.registry.load_enabled(config_path)
	check(packs.registry.entries("vehicle").size()==1 and packs.prepare(false),"explicit trusted PCK registers a usable vehicle provider")
	check(FileAccess.get_sha256("res://addons/vehicle_runtime/ranger.module.json")==original,"external PCK cannot replace existing host resources")
	check(packs.request("test.external.cart.v1"),"mounted custom vehicle loads through regular threaded path")
	var scene:PackedScene=packs.take("test.external.cart.v1")
	check(scene!=null,"mounted pack supplies actual PackedScene")
	if scene!=null:
		var body:=scene.instantiate();var driver:RefCounted=packs.adapter("test.external.cart.v1")
		check(driver.accepts(body) and not body.has_method("bind_streamed_world"),"mounted pack supplies an independent adapter and body")
		body.free()
	packs.finish()
	for name:String in files:DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(config_path)
	DirAccess.remove_absolute(archive)
	DirAccess.remove_absolute(directory)
	await create_timer(3.0).timeout
	print("VEHICLE_MODULE_PACK failures=",failures)
	quit(1 if failures else 0)
