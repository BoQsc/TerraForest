extends SceneTree
## Render both alternatives together; no saves are opened or changed.
func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Use a graphical renderer for the material preview")
		quit(1)
		return
	var scene := Node3D.new()
	root.add_child(scene)
	var names := ["BRICK", "WOOD", "CONCRETE", "METAL"]
	for row in range(2):
		var blocks: Node3D = ClassDB.instantiate("NativeBlockWorld")
		scene.add_child(blocks)
		if not blocks.set_texture_set("original" if row == 0 else "terraforest"):
			quit(1)
			return
		blocks.set_collision_radius(0)
		var records := PackedInt32Array()
		for layer in range(4):
			for z in range(2):
				for y in range(3):
					for x in range(3):
						records.append_array(PackedInt32Array([layer*4+x, row*5+y, z, 1+(layer<<5)]))
			var title := Label3D.new()
			title.text = names[layer]
			title.position = Vector3(layer*4+1.5,row*5+3.5,2.1)
			title.font_size = 52
			title.pixel_size = 0.008
			title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			scene.add_child(title)
		blocks.set_cells(records)
		blocks.flush_bakes()
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30,-25,0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	scene.add_child(sun)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("182026")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e1e7ed")
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	scene.add_child(world_environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(19,13,27)
	camera.look_at(Vector3(7.5,4,1))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 20
	camera.current = true
	var canvas := CanvasLayer.new()
	scene.add_child(canvas)
	var label := Label.new()
	label.position = Vector2(36,28)
	label.add_theme_font_size_override("font_size",24)
	label.text = "TERRAFOREST / MATERIAL ALTERNATIVES\nUpper row: new 1024px textures    Lower row: preserved originals"
	canvas.add_child(label)
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://reports")
	root.get_texture().get_image().save_png("res://reports/block_texture_comparison.png")
	scene.free()
	quit()
