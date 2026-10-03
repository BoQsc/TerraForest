extends SceneTree
## Run before changing the legacy generator, using a graphical renderer.
## Refuses to overwrite the preserved originals.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer to read the texture array")
		quit(1)
		return
	var folder := "res://addons/structures/textures/original"
	var names := ["brick", "wood", "concrete", "metal"]
	for name in names:
		if FileAccess.file_exists(folder + "/" + name + "_albedo.png"):
			push_error("Original textures already exist; refusing to overwrite")
			quit(1)
			return
	DirAccess.make_dir_recursive_absolute(folder)
	var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
	root.add_child(blocks)
	blocks.set_collision_radius(0)
	blocks.set_cells(PackedInt32Array([0, 0, 0, 1]))
	blocks.flush_bakes()
	var tiles: Texture2DArray
	for child in blocks.get_children():
		if child is MeshInstance3D:
			tiles = child.mesh.surface_get_material(0).get_shader_parameter("tiles")
			break
	var reference: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/block_material_tiles.json"))
	for layer in range(4):
		var img := tiles.get_layer_data(layer)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(img.get_data())
		if hash.finish().hex_encode() != reference[layer].sha256:
			push_error("Legacy material differs from recorded fixture")
			quit(1)
			return
		if img.save_png(folder + "/" + names[layer] + "_albedo.png") != OK:
			quit(1)
			return
		print("Preserved exact original: ", names[layer])
	blocks.free()
	quit()
