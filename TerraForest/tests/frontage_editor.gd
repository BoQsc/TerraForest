# SPDX-License-Identifier: 0BSD
extends SceneTree
var submitted: Array=[]
var mixed: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	root.gui_embed_subwindows=true
	var palette=load("res://addons/structures/construction_palette.gd").new();root.add_child(palette)
	var assets: Array[Resource]=[load("res://addons/structures/prefabs/brick_cottage.tres"),load("res://addons/structures/prefabs/tower_floor.tres")]
	palette.configure(assets);palette.synchronize(true,1,0,0,0)
	palette.capture_name.text="Cottage street"
	palette.frontage_requested.connect(func(lots,width,gap,seed,title): submitted=[lots,width,gap,seed,title])
	palette.frontage_sources_requested.connect(func(indices,lots,width,gap,seed,title): mixed=[indices,lots,width,gap,seed,title])
	palette.frontage_button.pressed.emit()
	palette.frontage_lots.value=4;palette.frontage_width.value=12;palette.frontage_gap.value=3
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/frontage_editor.png")
	var passed: bool=palette.frontage_dialog.visible and not palette.frontage_button.disabled
	palette.frontage_dialog.confirmed.emit()
	passed=passed and submitted==[4,12,3,1703,"Cottage street"]
	palette.frontage_mix.button_pressed=true;palette.frontage_sources.select(0,false);palette.frontage_sources.select(1,false)
	palette.frontage_seed.value=4294967295
	palette.frontage_dialog.confirmed.emit()
	passed=passed and mixed==[PackedInt32Array([0,1]),4,12,3,4294967295,"Cottage street"]
	palette.frontage_button.pressed.emit()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/frontage_editor_mix.png")
	passed=passed and palette.frontage_dialog.size.y<=1080
	palette.synchronize(false,1,0,0,-1)
	passed=passed and not palette.frontage_dialog.visible and palette.frontage_button.disabled
	print("FRONTAGE_EDITOR ",{"passed":passed,"submitted":submitted,"world_script_loads":load("res://demo/world.gd")!=null})
	palette.free();quit(0 if passed else 1)
