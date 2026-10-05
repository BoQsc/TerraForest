# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void:
	var script=load("res://addons/volumetric_terrain/terrain_backend.gd")
	var backend=script.new()
	backend.temporary=false
	backend.disable_snapshot_writes()
	check(not backend._snapshot_writable(),"explicit block still prevents save admission")
	check(backend._save().contains("snapshot writes explicitly disabled") and not backend._save().contains("corrupt"),"explicit block does not claim disk corruption")
	backend=script.new();backend.temporary=false
	backend.disable_snapshot_writes("addon restoration failed")
	backend.disable_snapshot_writes("teardown")
	check(backend._save().contains("addon restoration failed") and not backend._save().contains("teardown"),"first blocking cause survives subsequent shutdown protection")
	backend=script.new();backend.temporary=false;backend.write_allowed=false
	check(backend._save().contains("world initialization or snapshot validation failure"),"worker validation gate reports its scope without asserting corruption")
	backend=script.new();backend.temporary=false;backend.disable_snapshot_writes("   ")
	check(backend._save().contains("snapshot writes explicitly disabled"),"blank reason gets useful default")
	backend=script.new();backend.temporary=false;backend.disable_snapshot_writes("x".repeat(1000))
	check(backend._snapshot_write_block_reason().length()==240,"diagnostic reason is bounded")
	backend.temporary=true
	check(backend._save()=="Temporary test world: save skipped","temporary world retains existing no-write behavior")
	print("SAVE_BLOCK_REASON checks=",checks," failures=",failures)
	quit(1 if failures else 0)
