# SPDX-License-Identifier: 0BSD
extends SceneTree
var submitted: Array=[]
func _initialize() -> void: call_deferred("run")
func run() -> void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	root.gui_embed_subwindows=true
	var palette=load("res://addons/structures/construction_palette.gd").new();root.add_child(palette)
	var assets: Array[Resource]=[load("res://addons/structures/prefabs/brick_cottage.tres")]
	palette.configure(assets);palette.synchronize(true,1,0,0,0)
	palette.capture_name.text="Cottage street"
	palette.frontage_requested.connect(func(lots,width,gap,seed,title): submitted=[lots,width,gap,seed,title])
	palette.frontage_button.pressed.emit()
	palette.frontage_lots.value=4;palette.frontage_width.value=12;palette.frontage_gap.value=3
	await process_frame;await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://reports/frontage_editor.png")
	var passed: bool=palette.frontage_dialog.visible and not palette.frontage_button.disabled
	palette.frontage_dialog.confirmed.emit()
	passed=passed and submitted==[4,12,3,1703,"Cottage street"]
	palette.synchronize(false,1,0,0,-1)
	passed=passed and not palette.frontage_dialog.visible and palette.frontage_button.disabled
	print("FRONTAGE_EDITOR ",{"passed":passed,"submitted":submitted,"world_script_loads":load("res://demo/world.gd")!=null})
	palette.free();quit(0 if passed else 1)
