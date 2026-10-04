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
	var plan:={"paving_segments":1,"street_width":8,"street_ends":PackedVector3Array([Vector3(500,50,500),Vector3(540,50,500)])}
	panel.register_prepared_street(plan,terrain.epoch)
	var actions: Array[String]=[];panel.action_requested.connect(func(action: String): actions.append(action))
	panel.street_controls.get_child(0).pressed.emit();panel.street_controls.get_child(1).pressed.emit()
	check(actions==["street_a","street_b"],"street buttons identify their distinct endpoints")
	check(panel.select_street_end(1,terrain) and panel.start==Vector3(540,50,500) and panel.width.value==4 and not panel.has_finish,"prepared street endpoint transfers exact height and width into road preview")
	plan.street_ends[1]=Vector3.ZERO
	check(panel.select_street_end(1,terrain) and panel.start==Vector3(540,50,500),"street entrance capture does not follow later plan mutation")
	panel.register_prepared_street({"paving_segments":1,"street_width":8,"street_ends":PackedVector3Array([Vector3(580,52,500),Vector3(620,52,500)])},terrain.epoch)
	var captured_start: Vector3=panel.start
	check(panel.select_street_end(0,terrain,true) and panel.start==captured_start and panel.finish==Vector3(580,52,500) and panel.validation_error().is_empty(),"another street supplies exact finish without moving start")
	check(terrain.density_revision==11 and panel.pending.is_empty(),"street-to-street selection only changes preview")
	panel.width.value=3
	check(not panel.select_street_end(1,terrain,true) and panel.finish==Vector3(580,52,500),"mismatched width rejects without replacing finish")
	panel.width.value=4;panel.clear()
	check(not panel.select_street_end(0,terrain,true) and not panel.has_finish,"end selection requires a start")
	plan.street_width=64;panel.register_prepared_street(plan,terrain.epoch)
	check(not panel.select_street_end(0,terrain),"oversized street does not silently narrow connecting road")
	terrain.epoch+=1;panel.poll_submission(terrain)
	check(panel.prepared_street.is_empty() and not panel.street_controls.visible,"world reload clears captured street entrances")
	panel.free();terrain.free();print("ROAD_CONTINUATION failures=",failures);quit(1 if failures else 0)
