extends RefCounted

const Modules = preload("res://addons/world_runtime/runtime_modules.gd")
const Adapter = preload("res://addons/vehicle_runtime/vehicle_adapter.gd")
const DEFAULT := "terraforest.ranger.v1"
var registry = Modules.new()
var vehicles: Dictionary = {}
var scenes: Dictionary = {}
var requested: Dictionary = {}
var failed: Dictionary = {}
var errors: Array[String] = []

func prepare(load_external: bool = true) -> bool:
	if not registry.register_manifest("res://addons/vehicle_runtime/ranger.module.json", true).ok: return false
	if load_external: registry.load_enabled()
	var definitions: Array[Dictionary]=registry.entries("vehicle")
	definitions.sort_custom(func(first:Dictionary,second:Dictionary):return first.id==DEFAULT if first.id==DEFAULT or second.id==DEFAULT else first.id<second.id)
	for entry: Dictionary in definitions:
		if vehicles.size() >= 8:
			errors.append("Vehicle provider limit reached: " + entry.id); continue
		if not entry.get("scene", null) is String or not entry.get("adapter", null) is String or not entry.get("name", null) is String:
			errors.append("Invalid vehicle provider: " + entry.id); continue
		if not ResourceLoader.exists(entry.scene, "PackedScene") or not ResourceLoader.exists(entry.adapter, "Script"):
			errors.append("Missing vehicle resources: " + entry.id); continue
		var driver: Script = load(entry.adapter)
		var sample: Variant = driver.new() if driver != null and driver.can_instantiate() else null
		if not sample is Adapter:
			errors.append("Vehicle adapter must implement API 1: " + entry.id); continue
		vehicles[entry.id] = entry
	return vehicles.has(DEFAULT)

func request(kind: String) -> bool:
	if not vehicles.has(kind): return false
	var path: String = vehicles[kind].scene
	if failed.has(path): return false
	if scenes.has(path) or requested.has(path): return true
	if ResourceLoader.load_threaded_request(path, "PackedScene") != OK: failed[path]=true; return false
	requested[path] = true
	return true

func ready(kind: String) -> bool:
	if not vehicles.has(kind): return false
	var path: String = vehicles[kind].scene
	if scenes.has(path): return true
	if not request(kind): return false
	var status := ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		_consume(path); return false
	if status != ResourceLoader.THREAD_LOAD_LOADED: return false
	return take(kind) != null

func take(kind: String) -> PackedScene:
	if not vehicles.has(kind): return null
	var path: String = vehicles[kind].scene
	if not scenes.has(path):
		if not request(kind): return null
		_consume(path)
	return scenes.get(path)

func _consume(path: String) -> void:
	if not requested.has(path): return
	var scene := ResourceLoader.load_threaded_get(path) as PackedScene
	requested.erase(path)
	if scene != null: scenes[path] = scene
	else: failed[path] = true

func unavailable(kind: String) -> bool:
	return not vehicles.has(kind) or failed.has(vehicles[kind].scene)

func adapter(kind: String) -> RefCounted:
	if not vehicles.has(kind): return null
	return load(vehicles[kind].adapter).new()

func finish() -> void:
	for path: String in requested.keys(): _consume(path)
