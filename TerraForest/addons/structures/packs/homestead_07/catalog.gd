# SPDX-License-Identifier: 0BSD
extends RefCounted
## Pack admission only. Baked meshes use the shared native model/save owners.
const ROOT := "res://addons/structures/packs/homestead_07/"
const ID := "terraforest.homestead_07"
const TITLE := "Homestead 07"
static var _definitions: Array = []
static var _atlas: ImageTexture
static var _icons: Dictionary = {}

static func definitions() -> Array:
	if _definitions.is_empty():
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(ROOT + "pack.json"))
		if manifest is Dictionary and manifest.get("id") == ID:
			_definitions = manifest.get("objects", [])
	return _definitions.duplicate(true)

static func key(slug: String) -> String:
	return "packs/homestead_07/" + slug + "/v1"

static func title(definition: Dictionary) -> String:
	return TITLE + " · " + definition.name.trim_prefix("Homestead ").capitalize()

static func register(world: Node3D) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for definition: Dictionary in definitions():
		var mesh: Mesh = load(ROOT + "models/" + definition.id + ".tres")
		if mesh == null: return []
		var collection: Node3D = world.register_model(key(definition.id), mesh)
		if collection == null or not collection.configure_compound_collision(mesh.get_meta("collision_boxes"), 64, 256, 8, 1792, 56): return []
		var labels: PackedStringArray = []
		var names := {102:"wood",104:"metal",201:"stone",203:"copper ore",204:"plant fibre",225:"cloth scraps",226:"copper wire",227:"fasteners"}
		for index in range(0, definition.recipe.size(), 2):
			labels.append("%d %s" % [definition.recipe[index+1], names[int(definition.recipe[index])]])
		entries.append({"id":key(definition.id), "item":int(definition.item), "pack":TITLE, "pack_id":ID, "mount":definition.get("mount","floor"), "title":title(definition), "mesh":mesh, "collection":collection, "scale":Vector3.ONE, "costs":PackedInt64Array(definition.recipe), "cost_label":", ".join(labels)})
	return entries

static func recipes(salvage: bool = false) -> Dictionary:
	var result := {}
	for definition: Dictionary in definitions():
		var values: Array = definition.salvage if salvage else definition.recipe
		if not values.is_empty(): result[key(definition.id)] = PackedInt64Array(values)
	return result

static func profile(asset: String) -> Dictionary:
	for definition: Dictionary in definitions():
		if asset == key(definition.id):
			return {"name":definition.name,"health":int(definition.health),"material":definition.material}
	return {}

static func icon(value: Variant) -> Texture2D:
	var index := -1
	var entries := definitions()
	for i in entries.size():
		if str(value) == str(int(entries[i].item)) or str(value) == title(entries[i]): index = i; break
	if index < 0: return null
	if _icons.has(index): return _icons[index]
	if _atlas == null:
		var pixels := Image.new()
		if pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(ROOT + "icons.trtex")) != OK: return null
		_atlas = ImageTexture.create_from_image(pixels)
	var tile := AtlasTexture.new()
	tile.atlas = _atlas
	tile.region = Rect2((index % 5)*256, (index / 5)*256, 256, 256)
	tile.filter_clip = true
	_icons[index] = tile
	return tile

static func light_sources(world: Node3D) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition: Dictionary in definitions():
		if not definition.has("light"): continue
		var collection: Node3D = world.model(key(definition.id))
		if collection == null: continue
		var light: Dictionary = definition.light
		result.append({"collection":collection,"offset":Vector3(light.offset[0],light.offset[1],light.offset[2]),"color":Color(light.color),"energy":float(light.energy),"range":float(light.range),"shadows":bool(light.shadows)})
	return result
