# SPDX-License-Identifier: 0BSD
extends SceneTree
class TerrainStub extends Node:
	var epoch:=4
	var edit_ticket:=7
	var density_revision:=10
	var pending_edit:=true
	var stopping:=false
	var last_edit_outcome: Dictionary={}
var failures:=0
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var panel=preload("res://addons/volumetric_terrain/road_palette.gd").new();root.add_child(panel)
	var terrain:=TerrainStub.new()
	panel.mark(true,Vector3(100,50,100));panel.mark(false,Vector3(120,52,100));panel.width.value=4
	panel.track_submission(terrain)
	check(not panel.continue_selection(terrain),"pending section cannot authorize continuation")
	panel.mark(false,Vector3(180,80,180));panel.width.value=8
	terrain.pending_edit=false;terrain.density_revision=11
	terrain.last_edit_outcome={"epoch":4,"ticket":7,"revision":11,"status":"published"};panel.poll_submission(terrain)
	check(panel.pending.is_empty() and not panel.continue_button.disabled,"matching published outcome authorizes continuation")
	check(panel.continue_selection(terrain) and panel.start==Vector3(120,52,100) and not panel.has_finish and panel.width.value==4,"continuation uses captured endpoint and width despite later selection changes")
	check(terrain.density_revision==11,"continuation only changes the preview")
	panel.mark(false,Vector3(130,52,100));terrain.edit_ticket=8;panel.track_submission(terrain)
	terrain.last_edit_outcome={"epoch":4,"ticket":8,"revision":11,"status":"unchanged"};panel.poll_submission(terrain)
	check(panel.completed.finish==Vector3(130,52,100),"confirmed no-op section can be continued without revision increment")
	panel.mark(false,Vector3(140,52,100));terrain.edit_ticket=9;panel.track_submission(terrain)
	terrain.last_edit_outcome={"epoch":4,"ticket":8,"revision":11,"status":"unchanged"};panel.poll_submission(terrain)
	check(panel.completed.finish==Vector3(130,52,100) and panel.status.text.contains("did not publish"),"wrong ticket cannot replace last completed endpoint")
	terrain.epoch=5;panel.poll_submission(terrain)
	check(panel.completed.is_empty() and panel.continue_button.disabled and not panel.continue_selection(terrain),"world reload invalidates continuation")
	panel.free();terrain.free();print("ROAD_CONTINUATION failures=",failures);quit(1 if failures else 0)
