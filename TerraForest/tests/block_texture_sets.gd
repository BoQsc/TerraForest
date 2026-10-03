extends SceneTree
## Graphical integration: actual GPU arrays, live switching and unchanged save data.
var failures := 0
var checks := 0
var blocks: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func digest(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Texture readback requires a graphical renderer")
		quit(1)
		return
	if not ClassDB.class_exists("NativeBlockWorld"):
		if GDExtensionManager.load_extension("res://addons/structures/structures.gdextension") != OK:
			push_error("Cannot load the structures extension")
			quit(1)
			return
	blocks = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	check(blocks.set_cells(PackedInt32Array([0,0,0,1, 2,0,0,33, 4,0,0,65, 6,0,0,97])), "all four material IDs retain existing cell words")
	blocks.flush_bakes()
	var mesh: Mesh
	for child in blocks.get_children():
		if child is MeshInstance3D:
			mesh = child.mesh
			break
	var material: ShaderMaterial = mesh.surface_get_material(0)
	var bytes: PackedByteArray = blocks.capture_snapshot()
	var published: int = blocks.stats().published_bakes
	var collision: Dictionary = blocks.collision_stats()
	check(blocks.set_texture_set("original"), "original image set loads")
	var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/block_material_tiles.json"))
	var tiles: Texture2DArray = material.get_shader_parameter("tiles")
	for layer in range(4):
		var data: PackedByteArray = tiles.get_layer_data(layer).get_data()
		check(data.size() == reference[layer].bytes and digest(data) == reference[layer].sha256, "original layer %d preserves every texel and mip byte" % layer)
	check(blocks.set_texture_set("terraforest") and blocks.get_texture_set() == "terraforest", "generated texture set switches live")
	check(mesh.surface_get_material(0) == material, "published geometry keeps its shared material")
	tiles = material.get_shader_parameter("tiles")
	var names := ["brick", "wood", "concrete", "metal"]
	for layer in range(4):
		var source := Image.new()
		var path: String = "res://addons/structures/textures/terraforest/" + names[layer] + "_albedo.png"
		var ok := true
		if FileAccess.file_exists(path):
			ok = source.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK
		else:
			var imported: Texture2D = load(path)
			source = imported.get_image()
			if source.is_compressed(): ok = source.decompress() == OK
		source.convert(Image.FORMAT_RGB8)
		source.generate_mipmaps()
		var actual := tiles.get_layer_data(layer)
		check(ok and actual.get_size() == Vector2i(1024,1024) and actual.has_mipmaps() and digest(actual.get_data()) == digest(source.get_data()), "new %s GPU layer matches the 1024 PNG and its mip chain" % names[layer])
	check(not blocks.set_texture_set("../original") and not blocks.set_texture_set("missing"), "invalid names reject without changing textures")
	check(blocks.get_texture_set() == "terraforest", "rejected switch preserves the active set")
	check(blocks.capture_snapshot() == bytes and blocks.stats().published_bakes == published and blocks.collision_stats() == collision, "switching leaves saves, geometry and collision unchanged")
	check(blocks.set_texture_set("original") and blocks.get_texture_set() == "original", "original materials restore live")
	check(blocks.capture_snapshot() == bytes, "restoring appearance preserves authored buildings")
	blocks.free()
	print("TEXTURE_SETS ", checks, " checks, ", failures, " failures")
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file := FileAccess.open("res://reports/block_texture_sets.json",FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks,"failures":failures},"  "))
		file.close()
	quit(1 if failures else 0)
