# SPDX-License-Identifier: 0BSD
extends SceneTree
const Stream=preload("res://addons/volumetric_terrain/terrain_stream.gd")
var failures:=0
func check(value: bool, label: String) -> void:
	print(("PASS " if value else "FAIL ")+label)
	if not value: failures+=1
func _initialize() -> void:
	var stream=Stream.new()
	var old:=Vector3i(0,0,128)
	var target:=Vector3i(1280,1248,16)
	var background: Dictionary={"data":{"kind":"mesh","key":old},"piece_at":17}
	stream.preparation=background
	stream.staging.assign([{"kind":"mesh","key":Vector3i(256,0,128)},{"kind":"mesh","key":target}])
	stream.activation_keys[target]=true
	stream._select_preparation_work()
	check(stream.preparation.is_empty() and stream.staging.front().key==target,"ready target bypasses unrelated scene uploads")
	check(stream.paused_preparations.size()==1 and stream.paused_preparations[0].piece_at==17,"background partial progress retained")
	stream.preparation={"data":stream.staging.pop_front(),"piece_at":2}
	stream.pending_edit=true
	stream._select_preparation_work()
	check(stream.preparation.is_empty() and stream.paused_preparations.size()==2,"edit can interrupt urgent preparation without losing earlier suspended work")
	check(stream._has_paused_preparation(old) and stream._has_paused_preparation(target),"suspended jobs remain protected from duplicate scheduling")
	stream.pending_edit=false
	stream._select_preparation_work()
	check(stream.preparation.data.key==target and stream.preparation.piece_at==2,"target resumes before unrelated background work")
	stream.preparation={}
	stream.activation_keys.clear()
	stream._select_preparation_work()
	check(stream.preparation.data.key==old and stream.preparation.piece_at==17,"background resumes without rebuilding completed pieces")
	stream.preparation={};stream.paused_preparations.clear();stream.staging.clear()
	stream.free()
	quit(1 if failures else 0)
