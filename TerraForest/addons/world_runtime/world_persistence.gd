extends RefCounted
## Main-thread registration/capture only. Packing, checksums, validation and disk
## publication run in native code on the terrain-owned worker.
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
	if _terrain != null or _providers.size() >= 63 or _providers.has(name) or name == "terrain" or name.length()>48 or name.to_lower()!=name or name.to_utf8_buffer().size()!=name.length() or not name.is_valid_identifier() or not capture.is_valid() or not restore.is_valid() or validator == null:
		return false
	if not validator.validate_snapshot(empty):
		return false
	_providers[name] = {"capture": capture, "restore": restore, "validator": validator, "empty": empty}
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
	for name: String in _providers:
		if _providers[name]["capture"].is_valid():
			sections[name] = _providers[name]["capture"].call()
	return {"epoch": _restored_epoch, "sections": sections}

func _restore(sections: Dictionary, epoch_id: int) -> void:
	for name: String in _providers:
		if _providers[name]["restore"].is_valid():
			if not _providers[name]["restore"].call(sections.get(name, _providers[name]["empty"])):
				_terrain.snapshot_restore_ok = false
	_restored_epoch = epoch_id
