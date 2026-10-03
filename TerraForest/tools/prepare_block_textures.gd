extends SceneTree
## Normalize generated source dimensions only; preserve the archived 128px originals.
func _initialize() -> void:
	for name: String in ["brick", "wood", "concrete", "metal"]:
		var path := "res://addons/structures/textures/terraforest/" + name + "_albedo.png"
		var img := Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			quit(1)
			return
		img.resize(1024,1024,Image.INTERPOLATE_LANCZOS)
		img.convert(Image.FORMAT_RGB8)
		if img.save_png(path) != OK:
			quit(1)
			return
		print("Prepared 1024px RGB tile: ", name)
	quit()
