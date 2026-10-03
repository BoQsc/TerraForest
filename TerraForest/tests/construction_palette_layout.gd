# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var palette:=preload("res://addons/structures/construction_palette.gd").new()
	root.add_child(palette)
	palette.synchronize(true,1,0,0,-1)
	palette.stack_count.value=32
	Engine.max_fps=60
	for frame in 3: await process_frame
	var valid: bool=palette.stack_count.size.x>=130 and palette.panel.position.x+palette.panel.size.x<=1920 and palette.panel.position.y+palette.panel.size.y<900
	print("PASS panel and count control fit" if valid else "FAIL panel layout")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/construction_palette_layout.png")
	palette.free();quit(0 if valid else 1)
