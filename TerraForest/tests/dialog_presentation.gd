# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var force_reapply:=true
var frames: Array[float]=[]
var previous:=0
var focus_returns:=0
func _initialize() -> void: call_deferred("run")
func _focus_returned() -> void:
	focus_returns+=1
	if force_reapply: DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	else: Presentation.restore_vsync()
func _drawn() -> void:
	var now:=Time.get_ticks_usec()
	if previous>0: frames.append((now-previous)/1000.0)
	previous=now
func run() -> void:
	Engine.max_fps=60;Presentation.apply(root)
	root.focus_entered.connect(_focus_returned)
	var dialog:=AcceptDialog.new();dialog.dialog_text="Presentation focus regression";root.add_child(dialog)
	RenderingServer.frame_post_draw.connect(_drawn)
	var results: Dictionary={}
	for unconditional in [true,false]:
		force_reapply=unconditional
		for warmup in 6: await RenderingServer.frame_post_draw
		frames.clear();focus_returns=0
		for cycle in 4:
			dialog.popup_centered(Vector2i(600,240))
			for settle in 3: await RenderingServer.frame_post_draw
			dialog.hide()
			for settle in 3: await RenderingServer.frame_post_draw
		var sorted:=frames.duplicate();sorted.sort()
		results["unconditional" if unconditional else "conditional"]={"frames_ms":frames.duplicate(),"max_ms":sorted[-1],"median_ms":sorted[sorted.size()/2],"focus_returns":focus_returns}
	var valid: bool=DisplayServer.window_get_vsync_mode()==DisplayServer.VSYNC_ENABLED and Presentation.measurement(root).fair_graphical_sample and results.conditional.focus_returns==4 and results.unconditional.focus_returns==4
	results["passed"]=valid;results["embedded"]=dialog.is_embedded()
	results["scope"]="Four close/reopen cycles per policy in one fullscreen process. Wall intervals include frame cap. No terrain or gameplay throughput claim."
	var file:=FileAccess.open("res://reports/dialog_presentation.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	print("DIALOG_PRESENTATION ",results)
	RenderingServer.frame_post_draw.disconnect(_drawn);dialog.free();quit(0 if valid else 1)
