# SPDX-License-Identifier: 0BSD
extends Node
signal presentation_changed(fullscreen:bool)
# Persistent host: scenes may change, the root Window and graphics device do not.
const Options=preload("res://addons/world_runtime/session_options.gd")
const MeshHandoff=preload("res://addons/world_runtime/generation_mesh_handoff.gd")
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var transitioning:=false
var cover:CanvasLayer
var last_error:=""
var stage_timings:Dictionary={}
var continue_started_ms:=0
var continue_consumed:=false
func _enter_tree()->void:
	# The host exists before browser, loading, generation and gameplay scenes.
	Presentation.migrate_boot_settings()
	Presentation.apply(get_window())
func _ready()->void:
	if "--frame-trace" in OS.get_cmdline_user_args():
		var trace:=preload("res://addons/world_runtime/frame_trace.gd").new()
		trace.name="FrameTrace";add_child(trace)
	get_tree().scene_changed.connect(_restore_presentation)
	get_window().focus_entered.connect(_restore_presentation.call_deferred)
	get_tree().scene_changed.connect(_attach_optional_audio)
	_attach_optional_audio.call_deferred()
func _restore_presentation()->void:
	Presentation.apply(get_window())
func _input(event:InputEvent)->void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F11:
		Presentation.toggle(get_window())
		presentation_changed.emit(Presentation.fullscreen_enabled())
		get_viewport().set_input_as_handled()
func _attach_optional_audio()->void:
	var world:=get_tree().current_scene
	var path:="res://addons/audio_runtime/world_audio.gd"
	var args:=PackedStringArray(ProjectSettings.get_setting("terraforest/session_arguments",OS.get_cmdline_user_args()))
	if world==null or world.scene_file_path!="res://demo/world.tscn" or world.has_node("WorldAudio") or "--no-audio" in args or not ProjectSettings.get_setting("terraforest/audio",true) or not ResourceLoader.exists(path):return
	var adapter:Node3D=load(path).new();world.add_child(adapter);adapter.attach(world)
static func obtain(tree:SceneTree)->Node:
	var host:=tree.root.get_node_or_null("WorldSession")
	if host==null:
		host=load("res://addons/world_runtime/world_session.gd").new();host.name="WorldSession";tree.root.add_child.call_deferred(host)
	tree.root.gui_embed_subwindows=true
	return host
func take_continue_request(arguments:PackedStringArray)->bool:
	if continue_consumed or not last_error.is_empty() or "--continue-last" not in arguments:return false
	continue_consumed=true;return true
func begin_continue()->void:
	continue_started_ms=preload("res://addons/world_runtime/loading_timer.gd").unix_milliseconds()
	if not is_instance_valid(cover):
		cover=preload("res://addons/world_runtime/generation_screen.gd").new();add_child(cover)
	cover.panel.reset(continue_started_ms,0)
	cover.panel.show_progress("Loading your world","Finding last played world…",0)
	cover.cancel_button.hide()
func dismiss_continue()->void:
	continue_started_ms=0
	if is_instance_valid(cover):cover.queue_free();cover=null
func set_world_photograph(slot:String,directory:String="user://worlds")->void:
	if is_instance_valid(cover):cover.picture.texture=preload("res://addons/world_runtime/world_presentation.gd").display_texture(slot,directory)
func open_world(command:PackedStringArray)->bool:
	if transitioning:return false
	var arguments:=Options.user_arguments(command)
	if arguments.is_empty():last_error="World launch settings are missing";return false
	transitioning=true
	var generation:="--generation-handoff" in arguments
	var baseline:=94.0 if generation else 0.0
	var range:=.48 if generation else 8.0
	var started_ms:=continue_started_ms if continue_started_ms>0 else preload("res://addons/world_runtime/loading_timer.gd").unix_milliseconds()
	for argument:String in arguments:
		if argument.begins_with("--loading-started-ms="):started_ms=int(argument.trim_prefix("--loading-started-ms="))
	if not is_instance_valid(cover):
		cover=preload("res://addons/world_runtime/generation_screen.gd").new();add_child(cover)
	for argument:String in arguments:
		if argument.begins_with("--world-slot="):set_world_photograph(argument.trim_prefix("--world-slot="));break
	cover.panel.reset(started_ms,baseline)
	cover.panel.show_progress("Loading your world","Loading game resources…",baseline)
	await get_tree().process_frame
	var path:="res://demo/world.tscn"
	var started:=Time.get_ticks_usec()
	var resources:=preload("res://addons/world_runtime/startup_resources.gd").new()
	if not await resources.prepare(self,"res://demo/world.gd",func(done:int,total:int):cover.panel.show_progress("Loading your world","Loading game resources · %d / %d"%[done,total],baseline+float(done)/maxi(1,total)*range)):
		await _failed("Game resources could not be loaded");return false
	var scene:=load(path) as PackedScene
	stage_timings={"resources_ms":(Time.get_ticks_usec()-started)/1000.0}
	stage_timings["slowest_resource"]=resources.slowest
	if scene==null:await _failed("Game resources could not be loaded");return false
	Options.set_arguments(arguments)
	started=Time.get_ticks_usec()
	if get_tree().change_scene_to_packed(scene)!=OK:await _failed("World scene could not be opened");return false
	stage_timings["instantiate_ms"]=(Time.get_ticks_usec()-started)/1000.0;started=Time.get_ticks_usec()
	await get_tree().scene_changed
	var game:=get_tree().current_scene
	while is_instance_valid(game) and game==get_tree().current_scene and not game.startup_complete:
		if is_instance_valid(cover):cover.panel.show_progress("Loading your world",game.startup_stage,baseline+range)
		await get_tree().process_frame
	if not is_instance_valid(game) or game!=get_tree().current_scene:return false
	stage_timings["ready_ms"]=(Time.get_ticks_usec()-started)/1000.0
	game.loading_panel.reset(started_ms,baseline+range)
	# The game's loading UI now owns presentation; keep the cover across the gap.
	if is_instance_valid(cover):cover.queue_free();cover=null
	continue_started_ms=0;transitioning=false;return true
func _failed(reason:String)->void:
	last_error=reason;transitioning=false;Options.reset()
	var scene:=get_tree().current_scene
	if is_instance_valid(scene) and scene.scene_file_path=="res://demo/worlds.tscn":scene.filter_list();scene.notice.text=reason
	dismiss_continue()
	await get_tree().process_frame
func reject_world(game:Node,code:int)->void:
	last_error="World initialization failed (%d). Previous saved data is protected."%code
	if is_instance_valid(game):game.shutdown_requested=true
	await get_tree().process_frame
	if is_instance_valid(game):game.terrain.shutdown()
	transitioning=false
	dismiss_continue()
	get_tree().change_scene_to_file("res://demo/worlds.tscn")
