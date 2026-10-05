# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	Engine.max_fps=60
	var layer:=CanvasLayer.new();root.add_child(layer)
	var background:=ColorRect.new();background.color=Color("182820");background.size=Vector2(1920,1080);layer.add_child(background)
	var labels: Array[Label]=[]
	for row in range(20):
		var label:=Label.new();label.position=Vector2(20,20+row*48);label.add_theme_font_size_override("font_size",24)
		label.text="Living terrain · WASD Move Shift Sprint · Terrain: Wheel Brush size · 60 FPS · 1907 trees · Wood ×64"
		layer.add_child(label);labels.append(label)
	for frame in range(30): await RenderingServer.frame_post_draw
	for index in range(labels.size()):
		if index%2==0: labels[index].text="Living terrain · Harvested 4 wood · 60 FPS · 1906 trees · Wood ×68 · 0123456789 ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	for frame in range(60): await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://docs/evidence/natural_harvest/text_only.png")
	layer.free();print("TEXT_RENDER_PROBE completed; visual inspection required")
	quit()
