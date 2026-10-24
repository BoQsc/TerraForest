# SPDX-License-Identifier: 0BSD
extends Node
# Coroutine adapter shared by standalone CLI runners and in-window jobs.
signal finished(code:int)
signal progress_changed(stage:String,completed:int,total:int,details:Dictionary)
var root:Viewport
var result:=-1
var cancel_requested:=false
var cancellation_file:=""
var process_frame:Signal:
	get:return root.get_tree().process_frame
var physics_frame:Signal:
	get:return root.get_tree().physics_frame
func _ready()->void:
	if root==null:root=get_tree().root
	for argument:String in preload("res://addons/world_runtime/session_options.gd").arguments():
		if argument.begins_with("--cancel-file="):cancellation_file=argument.trim_prefix("--cancel-file=")
	_begin.call_deferred()
func _begin()->void:
	if cancelled():quit(2);return
	_initialize()
func _initialize()->void:pass
func cancelled()->bool:
	return cancel_requested or (not cancellation_file.is_empty() and FileAccess.file_exists(cancellation_file))
func request_cancel()->void:cancel_requested=true
func quit(code:int=0)->void:
	if result>=0:return
	result=2 if cancelled() else code;finished.emit(result)
func _exit_tree()->void:
	if has_method("_finalize"):call("_finalize")
