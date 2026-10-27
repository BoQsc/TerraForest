# SPDX-License-Identifier: 0BSD
extends SceneTree
class ReviewControls extends CanvasLayer:
	var game:Node
	var note:Label
	func _ready()->void:
		note=Label.new();note.position=Vector2(24,232);note.add_theme_font_size_override("font_size",20);add_child(note);refresh()
	func refresh()->void:
		var state:="TIP-FIRST FORWARD-LEFT CANDIDATE" if game.tool_view.human.candidate_enabled else "ACCEPTED DEFAULT"
		note.text=state+"\nF6: compare versions · temporary world · no default change"
		DisplayServer.window_set_title("TerraForest — pickaxe comparison — "+state)
	func _input(event:InputEvent)->void:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6:
			game.tool_view.cancel_attack();game.tool_view.human.set_candidate(not game.tool_view.human.candidate_enabled);refresh();get_viewport().set_input_as_handled()
func _initialize()->void:run.call_deferred()
func run()->void:
	var args:=OS.get_cmdline_user_args()
	if "--temporary" not in args:args.append("--temporary")
	ProjectSettings.set_setting("terraforest/session_arguments",args)
	var game=load("res://demo/world.tscn").instantiate();game.temporary_world=true
	game.tool_view.human.free();game.tool_view.free();game.tool_view=preload("res://addons/characters/experiments/pickaxe_crosscut_tools.gd").new()
	root.add_child(game);current_scene=game
	var deadline:=Time.get_ticks_msec()+90000
	while (game.loading_active or game.needs_floor_spawn) and Time.get_ticks_msec()<deadline:await process_frame
	if game.loading_active or game.needs_floor_spawn:push_error("Pickaxe comparison world failed to load");quit(2);return
	game.player_hud.equip_item(1)
	var controls:=ReviewControls.new();controls.game=game;root.add_child(controls)
	print("PICKAXE_CROSSCUT_READY temporary=",game.temporary_world," profile=",game.tool_view.attack_profile())
