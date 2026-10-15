# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
	var world: Node3D=ClassDB.instantiate("NativeBlockWorld");root.add_child(world)
	world.set_collision_radius(16)
	var cells:=PackedInt32Array()
	for i in 512:cells.append_array(PackedInt32Array([(i%32)*16,0,(i/32)*16,1]))
	check(world.set_cells(cells),"512 independent mesh chunks authored")
	world.flush_bakes()
	var before: Dictionary=world.collision_stats()
	check(before.ready and before.ready_chunks>0,"initial nearby collision settles")
	for frame in 30:
		world.set_focus(Vector3.ZERO);world.set_collision_radius(16)
		await process_frame
	var idle: Dictionary=world.collision_stats()
	check(idle.ticks>before.ticks and idle.selection_scans==before.selection_scans,"idle frames and unchanged focus/radius perform zero selection scans")
	check(idle.pieces_built==before.pieces_built and idle.pieces_retired==before.pieces_retired,"idle collision has no shape churn")
	world.set_focus(Vector3(256,0,128));world.flush_bakes()
	var moved: Dictionary=world.collision_stats()
	check(moved.ready and moved.selection_scans>idle.selection_scans and moved.pieces_built>idle.pieces_built and moved.pieces_retired>idle.pieces_retired,"moving focus resumes admission and retirement")
	check(world.set_cells(PackedInt32Array([256,1,128,1])),"edit adds a supported upper block")
	world.flush_bakes()
	var edited: Dictionary=world.collision_stats()
	check(edited.ready and edited.selection_scans>moved.selection_scans and edited.pieces_built>moved.pieces_built,"new mesh publication wakes collision after idle")
	world.set_collision_radius(0);world.flush_bakes()
	check(world.collision_stats().live_pieces==0 and world.collision_stats().retired_bodies==0,"disable drains every collision body")
	world.set_collision_radius(16);world.flush_bakes()
	check(world.collision_stats().ready and world.collision_stats().live_pieces>0,"reenable restores nearby collision")
	var final: Dictionary=world.collision_stats()
	for frame in 10:await process_frame
	check(world.collision_stats().selection_scans==final.selection_scans,"collision returns to scan-free idle after changes")
	print("COLLISION_IDLE_STATS ",JSON.stringify({"initial":before,"idle":idle,"moved":moved,"edited":edited,"final":final}))
	world.free();print("BUILDING_COLLISION_IDLE failures=",failures);quit(1 if failures else 0)
