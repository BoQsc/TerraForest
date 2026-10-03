# SPDX-License-Identifier: 0BSD
extends SceneTree
const Presentation=preload("res://addons/presentation/fullscreen_policy.gd")
var failures:=0
var checks: Array[Dictionary]=[]
func _initialize() -> void: call_deferred("run")
func refresh() -> void: Presentation.refresh_frame_cap(60,15)
func schedule_refresh() -> void: refresh.call_deferred()
func check(expected: int,label: String) -> void:
	var passed:=Engine.max_fps==expected
	checks.append({"name":label,"passed":passed,"cap":Engine.max_fps,"expected":expected,"window_mode":DisplayServer.window_get_mode()})
	if not passed: failures+=1
func settle() -> void:
	for frame in 3: await process_frame
func run() -> void:
	Engine.max_fps=60;Presentation.apply(root)
	root.focus_entered.connect(schedule_refresh);root.focus_exited.connect(schedule_refresh)
	for embedded in [true,false]:
		root.gui_embed_subwindows=embedded
		var dialog:=AcceptDialog.new();dialog.dialog_text="Frame cap focus regression";root.add_child(dialog)
		dialog.focus_entered.connect(schedule_refresh);dialog.focus_exited.connect(schedule_refresh)
		for cycle in 2:
			dialog.popup_centered(Vector2i(600,240));await settle()
			check(60,"focused dialog embedded=%s cycle=%d" % [embedded,cycle])
			dialog.hide();await settle()
			check(60,"closed dialog embedded=%s cycle=%d" % [embedded,cycle])
		dialog.free()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	await create_timer(0.25).timeout
	check(15,"minimized application")
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN);root.grab_focus()
	await create_timer(0.25).timeout
	check(60,"restored application")
	var report:={"failures":failures,"checks":checks,"presentation":Presentation.measurement(root)}
	var file:=FileAccess.open("res://reports/dialog_frame_cap.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("DIALOG_FRAME_CAP ",report);quit(0 if failures==0 else 1)
