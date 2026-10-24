# SPDX-License-Identifier: 0BSD
extends Node
# One bounded job owns one offscreen world. No OS process/window is created.
signal completed(code:int)
const Options=preload("res://addons/world_runtime/session_options.gd")
var task:Node
var viewport:SubViewport
var done:=false
var code:=-1
var previous_arguments:PackedStringArray
var had_override:=false
var previous_offscreen:=false
var previous_mouse:=Input.MOUSE_MODE_VISIBLE
var previous_title:=""
var previous_fps:=60
var main_window_id:=-1
func start(script:Script,arguments:PackedStringArray,render_world:bool=true)->void:
	had_override=ProjectSettings.has_setting(Options.KEY);previous_arguments=Options.arguments()
	previous_offscreen=ProjectSettings.get_setting(Options.OFFSCREEN,false)
	previous_mouse=Input.mouse_mode;previous_title=get_tree().root.title;previous_fps=Engine.max_fps
	main_window_id=get_tree().root.get_window_id();Options.set_arguments(arguments,true)
	if render_world:
		viewport=SubViewport.new();viewport.size=Vector2i(1920,1080);viewport.own_world_3d=true
		viewport.msaa_3d=get_tree().root.msaa_3d;viewport.screen_space_aa=get_tree().root.screen_space_aa
		viewport.use_taa=get_tree().root.use_taa;viewport.scaling_3d_scale=1.0
		viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;add_child(viewport)
	task=script.new();task.root=viewport if render_world else get_tree().root
	if render_world:viewport.set_meta("terraforest_scene_task",task)
	task.finished.connect(_finish);add_child(task)
func cancel()->void:
	if not done and is_instance_valid(task):task.request_cancel()
func _finish(value:int)->void:
	code=value;_cleanup.call_deferred()
func _cleanup()->void:
	# Let the coroutine return before destroying its world and joining workers.
	await get_tree().process_frame
	if is_instance_valid(viewport):viewport.free();viewport=null
	if is_instance_valid(task):task.free();task=null
	if had_override:Options.set_arguments(previous_arguments,previous_offscreen)
	else:Options.reset()
	get_tree().root.title=previous_title;Engine.max_fps=previous_fps;Input.mouse_mode=previous_mouse
	done=true;completed.emit(code)
