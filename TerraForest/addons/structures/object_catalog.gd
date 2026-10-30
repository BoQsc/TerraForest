# SPDX-License-Identifier: 0BSD
extends RefCounted
## Readable content admission at startup. Geometry/state remain in native stores.
const BUILTIN := "res://addons/structures/objects/wooden_door.object.json"
const MAX_DOORS := 16
const MATERIALS := {"brick":101, "wood":102, "concrete":103, "metal":104}
var definitions: Dictionary = {}
var diagnostics: Array[String] = []
var visuals = preload("res://addons/structures/object_mesh.gd").new()

func prepare(config_path: String = "") -> bool:
	definitions.clear()
	diagnostics.clear()
	var original := _read(BUILTIN)
	if not _admit(original, BUILTIN.get_base_dir()): return false
	if config_path.is_empty(): return true
	var config := ConfigFile.new()
	var status := config.load(config_path)
	if status == ERR_FILE_NOT_FOUND: return true
	if status != OK: return _fail("Cannot read object mod configuration: " + config_path)
	var manifests: Variant = config.get_value("objects", "manifests", PackedStringArray())
	if not manifests is PackedStringArray or manifests.size() > MAX_DOORS:
		return _fail("[objects] manifests must be a PackedStringArray of at most 16 paths")
	var packs := {}
	var replacements := {}
	for path: String in manifests:
		if not _manifest_path(path): return _fail("Object manifest must be inside user://mods or res://mods: " + path)
		var pack := _read(path)
		if pack.is_empty(): return false
		if not _fields(pack, ["schema", "id", "objects", "replacements"]) or pack.get("schema") != 1 or not _id(pack.get("id")) or packs.has(pack.id):
			return _fail("Invalid or duplicate object pack: " + path)
		packs[pack.id] = true
		if not pack.get("objects", []) is Array or not pack.get("replacements", []) is Array:
			return _fail("Pack objects/replacements must be arrays: " + path)
		for definition: Variant in pack.get("objects", []):
			if not definition is Dictionary or not _admit(definition, path.get_base_dir()): return false
		for replacement: Variant in pack.get("replacements", []):
			if not replacement is Dictionary or not _fields(replacement, ["id", "visual"]) or not _id(replacement.get("id")):
				return _fail("A replacement may contain only id and visual: " + path)
			var id: String = replacement.id
			if not definitions.has(id) or replacements.has(id): return _fail("Unknown or multiply replaced object: " + id)
			if not _visual(replacement.get("visual")): return false
			replacements[id] = true
			definitions[id].visual = replacement.visual.duplicate(true)
			definitions[id].directory = path.get_base_dir()
	return true

func register_all(world: Node3D) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	# Validate every visual before publishing any model collection.
	for id: String in definitions:
		var definition: Dictionary = definitions[id]
		var mesh: Mesh = visuals.load_visual(definition.visual, definition.directory)
		if mesh == null:
			_fail(id + ": " + visuals.error)
			return []
		definition.mesh = mesh
	for id: String in definitions:
		var definition: Dictionary = definitions[id]
		var collection: Node3D = world.register_model(id, definition.mesh)
		if collection == null or not collection.configure_collision(definition.bounds, 64, 256, 8):
			_fail("Could not register door: " + id)
			return []
		world.object_definitions[id] = definition
		var costs := recipe(definition.recipe)
		var labels: Array[String] = []
		for material: String in definition.recipe: labels.append("%d %s" % [definition.recipe[material], material])
		entries.append({"id":id, "title":definition.name + " (E open / close)", "mesh":definition.mesh, "collection":collection, "scale":Vector3.ONE, "costs":costs, "cost_label":", ".join(labels)})
	return entries

static func recipe(values: Dictionary) -> PackedInt64Array:
	var result := PackedInt64Array()
	for material: String in MATERIALS:
		if values.has(material): result.append_array(PackedInt64Array([MATERIALS[material], int(values[material])]))
	return result

func _admit(value: Dictionary, directory: String) -> bool:
	if not _fields(value, ["schema","id","name","visual","collision","behavior","recipe","salvage","durability"]) or value.get("schema") != 1 or not _id(value.get("id")):
		return _fail("Invalid object schema or identity in " + directory)
	if definitions.has(value.id) or definitions.size() >= MAX_DOORS: return _fail("Duplicate door ID or 16-door limit: " + value.id)
	if not value.get("name") is String or value.name.strip_edges().is_empty() or value.name.length() > 80: return _fail("Door name must contain 1–80 characters")
	if not _visual(value.get("visual")): return false
	var collision: Variant = value.get("collision")
	if not collision is Dictionary or not _fields(collision, ["position","size"]) or not _vector(collision.get("position"), 16) or not _vector(collision.get("size"), 8, true): return _fail("Expected bounded collision position and positive size")
	var behavior: Variant = value.get("behavior")
	if not behavior is Dictionary or not _fields(behavior, ["type","pivot","opening_degrees","zombie_breakable"]) or behavior.get("type") != "hinged_door" or not _vector(behavior.get("pivot"), 16): return _fail("Expected hinged_door behavior and pivot")
	if not _number(behavior.get("opening_degrees")) or absf(behavior.opening_degrees) < 1 or absf(behavior.opening_degrees) > 170 or not behavior.get("zombie_breakable") is bool: return _fail("Opening angle must be 1–170 degrees in either direction, with explicit zombie_breakable")
	if not _recipe(value.get("recipe"), false) or not _recipe(value.get("salvage"), true): return false
	for material: String in value.salvage:
		if value.salvage[material] > value.recipe.get(material, 0): return _fail("Salvage cannot exceed construction inputs")
	var durability: Variant = value.get("durability")
	if not durability is Dictionary or not _fields(durability, ["health","material"]) or not _integer(durability.get("health"), 1, 100000) or durability.get("material") not in ["wood","stone","other"]: return _fail("Invalid door durability")
	var definition := value.duplicate(true)
	definition.directory = directory
	definition.bounds = AABB(_vec(collision.position), _vec(collision.size))
	if definition.bounds.position.length() > 16 or _vec(behavior.pivot).length() > 16: return _fail("Collision origin or hinge exceeds 16 metres")
	definitions[value.id] = definition
	return true

func _visual(value: Variant) -> bool:
	if not value is Dictionary or not _fields(value, ["source","offset","rotation_degrees","scale"]) or not value.get("source") is String: return _fail("Expected visual source and optional offset, rotation_degrees, scale")
	var source: String = value.source
	if source != "builtin:wooden_door" and (source.is_absolute_path() or source.contains(":") or source.contains("\\") or ".." in source.split("/") or source.get_extension().to_lower() != "glb"):
		return _fail("Visual source must be builtin:wooden_door or a relative .glb path inside the pack")
	for field: String in ["offset","rotation_degrees","scale"]:
		if value.has(field) and not _vector(value[field], 360 if field == "rotation_degrees" else 16, field == "scale"): return _fail("Invalid visual " + field)
	return true

func _recipe(value: Variant, allow_empty: bool) -> bool:
	if not value is Dictionary or (value.is_empty() and not allow_empty): return _fail("Expected a material recipe")
	for material: String in value:
		if not MATERIALS.has(material) or not _integer(value[material], 1, 10000): return _fail("Recipe materials are brick, wood, concrete, metal with positive integer quantities")
	return true

func _read(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 65536:
		_fail("Missing or oversized object definition: " + path)
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		_fail("Invalid JSON object: " + path + ": " + parser.get_error_message())
		return {}
	return parser.data

static func _manifest_path(path: String) -> bool:
	return (path.begins_with("user://mods/") or path.begins_with("res://mods/")) and not path.contains("\\") and not ".." in path.split("/") and path.ends_with(".objects.json")
static func _fields(value: Dictionary, allowed: Array) -> bool:
	for key: Variant in value:
		if key not in allowed: return false
	return true
static func _id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length() > 96 or value.begins_with("/") or value.ends_with("/") or value.contains("..") or value.contains("//"): return false
	for character: String in value:
		if character not in "abcdefghijklmnopqrstuvwxyz0123456789._-/": return false
	return true
static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))
static func _integer(value: Variant, low: int, high: int) -> bool:
	return _number(value) and value == floor(value) and value >= low and value <= high
static func _vector(value: Variant, limit: float, positive: bool = false) -> bool:
	if not value is Array or value.size() != 3: return false
	for component: Variant in value:
		if not _number(component) or absf(component) > limit or (positive and component < 0.001): return false
	return true
static func _vec(value: Array) -> Vector3:
	return Vector3(value[0], value[1], value[2])
func _fail(message: String) -> bool:
	diagnostics.append(message)
	return false
