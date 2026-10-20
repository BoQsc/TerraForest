extends RefCounted
## Main-thread registration/capture only. Packing, checksums, validation and disk
## publication run in native code on the terrain-owned worker.
var last_capture: Dictionary = {}
var _terrain: Node
var _providers: Dictionary = {}
var _restored_epoch: int = -1
var _region_structures := false
var _metadata_first := false
var _model_metadata_first := false

func enable_region_structures(metadata_first: bool = false, model_metadata_first: bool = false) -> bool:
	if _terrain != null or not _providers.has("structures") or not ClassDB.class_exists("NativeRegionWorldArchive"):
		return false
	if model_metadata_first and not metadata_first:
		return false
	_model_metadata_first = model_metadata_first
	_region_structures = true
	_metadata_first = metadata_first
	return true

func register_component(name: String, capture: Callable, restore: Callable, validator: RefCounted, empty: PackedByteArray) -> bool:
	return register_components([{"name":name,"capture":capture,"restore":restore,"validator":validator,"empty":empty}])

# Setup-only transaction: validate all entries before publishing any provider.
func register_components(components: Array[Dictionary]) -> bool:
	if _terrain != null or components.is_empty() or _providers.size()+components.size()>63:return false
	var staged:Dictionary={}
	for entry:Dictionary in components:
		for key in ["name","capture","restore","validator","empty"]:
			if not entry.has(key):return false
		if not entry.name is String:return false
		var name:String=entry.name
		if _providers.has(name) or staged.has(name) or name=="terrain" or name.length()>48 or name.to_lower()!=name or name.to_utf8_buffer().size()!=name.length() or not name.is_valid_identifier():return false
		if not entry.capture is Callable or not entry.restore is Callable or not entry.validator is RefCounted or not entry.empty is PackedByteArray:return false
		if not entry.capture.is_valid() or not entry.restore.is_valid() or not entry.validator.has_method("validate_snapshot") or not entry.validator.validate_snapshot(entry.empty):return false
		staged[name]={"capture":entry.capture,"restore":entry.restore,"validator":entry.validator,"empty":entry.empty}
	_providers.merge(staged)
	return true

func attach(terrain: Node) -> Error:
	if _terrain != null or terrain.world_ready or terrain._started:
		return ERR_ALREADY_IN_USE
	if not ClassDB.class_exists("NativeWorldArchive"):
		GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	if not ClassDB.class_exists("NativeWorldArchive"):
		return ERR_CANT_OPEN
	var archive: RefCounted = ClassDB.instantiate("NativeWorldArchive")
	if _region_structures:
		var adapter: RefCounted = ClassDB.instantiate("NativeRegionWorldArchive")
		if not adapter.configure(archive,_providers["structures"]["validator"],_metadata_first,_model_metadata_first):
			return ERR_INVALID_PARAMETER
		archive = adapter
	_terrain = terrain
	terrain.backend.snapshot_codec = archive
	terrain.backend.snapshot_capture = _capture
	for name: String in _providers:
		terrain.backend.snapshot_validators[name] = archive if _region_structures and name == "structures" else _providers[name]["validator"]
	terrain.snapshot_restored.connect(_restore)
	return OK

func _capture() -> Dictionary:
	var sections: Dictionary = {}
	var measurements: Dictionary = {}
	var began:=Time.get_ticks_usec()
	for name: String in _providers:
		if _providers[name]["capture"].is_valid():
			var section_begin:=Time.get_ticks_usec()
			sections[name] = _providers[name]["capture"].call()
			measurements[name]={"us":Time.get_ticks_usec()-section_begin,"bytes":sections[name].size()}
	last_capture={"total_us":Time.get_ticks_usec()-began,"sections":measurements}
	return {"epoch": _restored_epoch, "sections": sections}

func _restore(sections: Dictionary, epoch_id: int) -> void:
	for name: String in _providers:
		if _providers[name]["restore"].is_valid():
			var restore_begin:=Time.get_ticks_usec()
			if not _providers[name]["restore"].call(sections.get(name, _providers[name]["empty"])):
				_terrain.snapshot_restore_ok = false
			if _terrain.has_method("_record_stage"):_terrain._record_stage("restore "+name,(Time.get_ticks_usec()-restore_begin)/1000.0)
	_restored_epoch = epoch_id
