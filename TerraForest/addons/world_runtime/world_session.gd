# SPDX-License-Identifier: 0BSD
extends Node
# Persistent host: scenes may change, the root Window and graphics device do not.
const Options=preload("res://addons/world_runtime/session_options.gd")
var transitioning:=false
var cover:CanvasLayer
var last_error:=""
static func obtain(tree:SceneTree)->Node:
	var host:=tree.root.get_node_or_null("WorldSession")
	if host==null:
		host=load("res://addons/world_runtime/world_session.gd").new();host.name="WorldSession";tree.root.add_child.call_deferred(host)
	tree.root.gui_embed_subwindows=true
	return host
func open_world(command:PackedStringArray)->bool:
	if transitioning:return false
	var arguments:=Options.user_arguments(command)
	if arguments.is_empty():last_error="World launch settings are missing";return false
	transitioning=true
	cover=preload("res://addons/world_runtime/generation_screen.gd").new();add_child(cover)
	cover.panel.show_progress("Loading your world","Loading game resources…",0)
	await get_tree().process_frame
	var path:="res://demo/world.tscn"
	# This script graph initializes native RefCounted helpers. Keep that setup
	# on the owner thread; terrain/planning/baking still use their native workers.
	var scene:PackedScene=load(path)
	if scene==null:await _failed("Game resources could not be loaded");return false
	Options.set_arguments(arguments)
	if get_tree().change_scene_to_packed(scene)!=OK:await _failed("World scene could not be opened");return false
	await get_tree().scene_changed
	# The game's loading UI now owns presentation; keep the cover across the gap.
	if is_instance_valid(cover):cover.queue_free();cover=null
	transitioning=false;return true
func _failed(reason:String)->void:
	last_error=reason;transitioning=false;Options.reset()
	var scene:=get_tree().current_scene
	if is_instance_valid(scene) and scene.scene_file_path=="res://demo/worlds.tscn":scene.notice.text=reason
	if is_instance_valid(cover):cover.queue_free();cover=null
	await get_tree().process_frame
func reject_world(game:Node,code:int)->void:
	last_error="World initialization failed (%d). Previous saved data is protected."%code
	if is_instance_valid(game):game.shutdown_requested=true
	await get_tree().process_frame
	if is_instance_valid(game):game.terrain.shutdown()
	transitioning=false
	if is_instance_valid(cover):cover.queue_free();cover=null
	get_tree().change_scene_to_file("res://demo/worlds.tscn")
