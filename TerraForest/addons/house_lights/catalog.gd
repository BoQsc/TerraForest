# SPDX-License-Identifier: 0BSD
extends RefCounted

const Modules = preload("res://addons/world_runtime/runtime_modules.gd")
const Visual = preload("res://addons/structures/object_mesh.gd")
const MANIFEST := "res://addons/house_lights/house_lights.module.json"
var definitions: Dictionary = {}
var errors: Array[String] = []
static var visuals = Visual.new()

func prepare(external: bool = true) -> bool:
	definitions.clear(); errors.clear()
	var registry := Modules.new()
	if not registry.register_manifest(MANIFEST, true).ok: return false
	if external: registry.load_enabled()
	for entry: Dictionary in registry.entries("world_light"):
		if definitions.size() >= 8: errors.append("World light provider limit"); return false
		var path: Variant = entry.get("definition")
		if not path is String or not path.begins_with("res://") or path.contains(".."): return false
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null or file.get_length() > 65536: return false
		var value: Variant = JSON.parse_string(file.get_as_text())
		if not value is Dictionary: return false
		var row: Dictionary = value
		if row.get("schema") != 1 or not row.get("asset") is String or definitions.has(row.asset): return false
		for field: String in ["name", "mesh", "bounds", "offset", "color", "energy", "range", "health", "material", "costs", "salvage"]:
			if not row.has(field): return false
		if not row.name is String or row.name.is_empty() or row.name.length() > 80 or not row.mesh is String or row.mesh.get_extension() != "glb": return false
		if row.material not in ["wood", "stone", "other"] or not _number(row.health, 1, 10000) or row.health != int(row.health): return false
		if not _vector(row.offset) or not row.bounds is Array or row.bounds.size() != 2 or not _vector(row.bounds[0]) or not _vector(row.bounds[1], true): return false
		if not _number(row.energy, .01, 8) or not _number(row.range, .1, 16) or not row.color is String or not Color.html_is_valid(row.color): return false
		if not _recipe(row.costs, false) or not _recipe(row.salvage, true): return false
		for material: String in row.salvage:
			if row.salvage[material] > row.costs.get(material, 0): return false
		var mesh: Mesh
		if entry.module == "terraforest.house_lights":
			var source_path: String = path.get_base_dir().path_join(row.mesh)
			var baked_path: String = source_path.get_basename() + "_model.res"
			if ResourceLoader.exists(baked_path): mesh = load(baked_path) as Mesh
			if mesh != null and FileAccess.file_exists(source_path) and mesh.get_meta("source_glb_sha256", "") != FileAccess.get_sha256(source_path):
				errors.append("Rebake changed GLB: " + source_path); return false
		else: mesh = visuals.load_visual({"source": row.mesh}, path.get_base_dir())
		if mesh == null: errors.append(visuals.error); return false
		if not mesh.get_meta("house_flame_ready", false):
			for surface in mesh.get_surface_count():
				var original: Material = mesh.surface_get_material(surface)
				if original != null and original.resource_name.contains("TerraForestFlame"):
					var fire := ShaderMaterial.new(); fire.shader = preload("res://addons/house_lights/flame.gdshader")
					mesh.surface_set_material(surface, fire)
			mesh.set_meta("house_flame_ready", true)
		row.mesh = mesh; row.offset = _vec(row.offset); row.color = Color(row.color)
		row.bounds = AABB(_vec(row.bounds[0]), _vec(row.bounds[1])); row.health = int(row.health)
		if not row.bounds.grow(.01).encloses(mesh.get_aabb()): errors.append("GLB exceeds declared placement bounds: " + row.asset); return false
		definitions[row.asset] = row
	return definitions.size() >= 3

func register(world: Node3D) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for key: String in definitions:
		var row: Dictionary = definitions[key]
		var collection: Node3D = world.register_model(key, row.mesh)
		if collection == null or not collection.configure_collision(row.bounds, 64, 128, 4): return []
		world.object_definitions[key] = {"name": row.name, "durability": {"health": row.health, "material": row.material}, "recipe": row.costs, "salvage": row.salvage, "behavior": {"type": "world_light"}}
		entries.append({"id": key, "title": row.name, "mesh": row.mesh, "collection": collection, "scale": Vector3.ONE, "costs": preload("res://addons/structures/object_catalog.gd").recipe(row.costs), "cost_label": "Light source object"})
	return entries

func runtime(world: Node3D) -> Node3D:
	var sources: Array[Dictionary] = []
	for key: String in definitions:
		var row: Dictionary = definitions[key]
		sources.append({"collection": world.model(key), "offset": row.offset, "color": row.color, "energy": row.energy, "range": row.range, "shadows": true})
	var pool: Node3D = ClassDB.instantiate("NativeResidentLights")
	world.add_child(pool)
	if not pool.configure(sources, 4): pool.free(); return null
	pool.set_meta("source_keys", definitions.keys())
	return pool

static func _number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(value) and value >= minimum and value <= maximum

static func _vector(value: Variant, positive: bool = false) -> bool:
	return value is Array and value.size() == 3 and _number(value[0], .001 if positive else -4, 4) and _number(value[1], .001 if positive else -4, 4) and _number(value[2], .001 if positive else -4, 4)

static func _vec(value: Array) -> Vector3: return Vector3(value[0], value[1], value[2])

static func _recipe(value: Variant, empty: bool) -> bool:
	if not value is Dictionary or (value.is_empty() and not empty) or value.size() > 4: return false
	for key: Variant in value:
		if not key is String or not key in ["wood", "metal", "concrete", "brick"] or not _number(value[key], 1, 100) or value[key] != int(value[key]): return false
	return true
