# SPDX-License-Identifier: 0BSD
extends SceneTree
class Terrain:
	extends Node
	var pending_edit:=false
	var world_ready:=true
	var stopping:=false
	var epoch:=0
	var density_revision:=0
	var calls:=0
	var edit_ticket:=0
	var last_edit_outcome: Dictionary={}
	func construct_graded_bed(_a,_b,_width,_depth,_clearance,_material,_shoulder) -> bool:
		calls+=1;edit_ticket+=1;pending_edit=true;return true
	func finish(changed: bool=true) -> void:
		if changed: density_revision+=1
		pending_edit=false;last_edit_outcome={"epoch":epoch,"ticket":edit_ticket,"status":"published" if changed else "unchanged","revision":density_revision}
var failures:=0
var obstruction:=""
func guard(_bounds: AABB) -> String: return obstruction
func check(ok: bool,label: String) -> void:
	print("PASS " if ok else "FAIL ",label)
	if not ok: failures+=1
func _initialize() -> void:
	var terrain=Terrain.new()
	var runner=preload("res://addons/structures/site_preparation.gd").new()
	var segment={"start":Vector3(100,40,100),"finish":Vector3(120,40,100),"half_width":8,"depth":8,"clearance":12,"material":1,"shoulder":8}
	var plan={"ok":true,"bounds":AABB(Vector3(80,30,80),Vector3(60,30,40)),"segments":[segment,segment.duplicate()]}
	obstruction="occupied"
	check(not runner.begin(plan,terrain,guard) and terrain.calls==0,"whole-site obstruction rejects before any edit")
	obstruction=""
	check(runner.begin(plan,terrain,guard),"clear site admitted")
	runner.tick(terrain,guard);runner.tick(terrain,guard)
	check(terrain.calls==1 and runner.completed==0,"only one edit is in flight")
	runner.cancel();runner.tick(terrain,guard)
	check(runner.status=="running" and terrain.calls==1,"stop waits for accepted edit")
	terrain.finish();runner.tick(terrain,guard)
	check(runner.status=="stopped" and runner.completed==1,"stop preserves and accounts for completed terrain edit")
	check(runner.resume(terrain,guard),"unchanged partial preparation resumes")
	obstruction="vehicle entered";runner.tick(terrain,guard)
	check(runner.status=="stopped" and terrain.calls==1,"new obstruction prevents next edit")
	obstruction="";runner.resume(terrain,guard);runner.tick(terrain,guard);terrain.finish();runner.tick(terrain,guard)
	check(runner.status=="complete" and runner.completed==2 and terrain.calls==2,"resume applies only remaining edit")
	runner.begin(plan,terrain,guard);runner.tick(terrain,guard);terrain.finish();terrain.density_revision+=1;runner.tick(terrain,guard)
	check(runner.status=="failed" and terrain.calls==3,"unrelated terrain revision prevents remaining edits")
	runner.begin(plan,terrain,guard);runner.tick(terrain,guard);terrain.finish(false);runner.tick(terrain,guard)
	check(runner.completed==1 and runner.status=="running","confirmed no-op completes a section without revision increment")
	terrain.finish(false);terrain.last_edit_outcome.status="rejected";runner.tick(terrain,guard)
	check(runner.status=="failed" and runner.completed==1,"rejected edit is not mistaken for successful no-op")
	terrain.free();quit(1 if failures else 0)
