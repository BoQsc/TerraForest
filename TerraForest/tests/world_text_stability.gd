# SPDX-License-Identifier: 0BSD
# Graphical diagnostic; screenshot readback invalidates performance measurements.
extends SceneTree
const REGION:=Rect2i(1100,20,800,160)
const HELP_REGION:=Rect2i(0,995,1920,85)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var output:="res://docs/evidence/text_stability/native"
	if "--scripted-vegetation-flush" in OS.get_cmdline_user_args(): output="res://docs/evidence/text_stability/scripted"
	DirAccess.make_dir_recursive_absolute(output)
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	root.add_child(game)
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline: await process_frame
	if game.loading_active:
		game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();quit(2);return
	game.set_physics_process(false)
	var selected:=0;var distance:=INF
	for id: int in game.vegetation.renderer.roots:
		var pose: Transform3D=game.vegetation.renderer.roots[id].t
		var d:=pose.origin.distance_squared_to(game.player.global_position)
		if d<distance: distance=d;selected=id
	if selected>0:
		var pose: Transform3D=game.vegetation.renderer.roots[selected].t
		game.camera.global_position=pose.origin+Vector3(0,1.7,2)
		game.camera.look_at(pose.origin+Vector3(0,1.7,0))
	var layer:=CanvasLayer.new();layer.layer=100;root.add_child(layer)
	var help_background:=ColorRect.new();help_background.position=HELP_REGION.position;help_background.size=HELP_REGION.size;help_background.color=Color.BLACK
	game.help.get_parent().add_child(help_background);game.help.get_parent().move_child(help_background,0)
	var background:=ColorRect.new();background.position=REGION.position;background.size=REGION.size;background.color=Color.BLACK;layer.add_child(background)
	for row in range(4):
		var label:=Label.new();label.position=Vector2(1110,28+row*36)
		label.text="Living terrain · Harvested 4 wood · WASD · 0123456789"
		label.add_theme_font_size_override("font_size",[15,16,24,28][row]);layer.add_child(label)
	for frame in range(12): await RenderingServer.frame_post_draw
	var reference: Image=root.get_texture().get_image().get_region(REGION)
	reference.save_png(output+"/reference.png")
	var bytes:=reference.get_data()
	var help_reference: Image=root.get_texture().get_image().get_region(HELP_REGION)
	help_reference.save_png(output+"/help_reference.png")
	var help_bytes:=help_reference.get_data()
	var harvested: bool=selected>0 and game._harvest_aimed_tree() and game.ecosystem.harvest_state.contains(selected)
	var changes:=0
	var help_changes:=0
	for sample in range(12):
		# Exercise changing UI text while the reference labels remain static.
		game.telemetry.text="Harvested %d wood · inventory %d"%[sample,sample*7]
		for frame in range(10): await RenderingServer.frame_post_draw
		var current: Image=root.get_texture().get_image().get_region(REGION)
		var help_current: Image=root.get_texture().get_image().get_region(HELP_REGION)
		if help_current.get_data()!=help_bytes:
			help_changes+=1;help_current.save_png(output+"/help_changed_%02d.png"%sample)
		if current.get_data()!=bytes:
			changes+=1
			current.save_png(output+"/changed_%02d.png"%sample)
	print("WORLD_TEXT_STABILITY ",JSON.stringify({"samples":12,"harvested":harvested,"changed_panels":changes,"changed_help":help_changes,"scope":"static opaque text pixels; not frame rate"}))
	layer.free();game.shutdown_requested=true
	await game.terrain.shutdown_after_edits();game.free()
	for frame in range(2): await process_frame
	quit(1 if changes or help_changes or not harvested else 0)
