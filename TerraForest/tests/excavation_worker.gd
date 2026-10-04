# SPDX-License-Identifier: 0BSD
extends SceneTree
const Codec=preload("res://addons/volumetric_terrain/mesh_codec.gd")
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func wait_edit(terrain: Node) -> void:
	var deadline:=Time.get_ticks_msec()+10000
	while terrain.pending_edit and Time.get_ticks_msec()<deadline: await process_frame
	check(not terrain.pending_edit,"bounded edit wait completes")
func run() -> void:
	Engine.max_fps=60
	var terrain=load("res://addons/volumetric_terrain/terrain_world.gd").new()
	terrain.diagnostics_pause_streaming=true;terrain.backend.disk_cache.enabled=false
	terrain.backend.world_generator=3;terrain.focus=Vector3(800,30,1310);root.add_child(terrain)
	check(terrain.start(StandardMaterial3D.new(),true)==OK,"temporary native worker starts")
	var deadline:=Time.get_ticks_msec()+10000
	while not terrain.world_ready and Time.get_ticks_msec()<deadline: await process_frame
	check(terrain.world_ready,"temporary world becomes ready")
	if terrain.world_ready:
		var center:=Vector3(800,30,1310)
		var command:=Codec.brush(center,center,2,0,false,3)
		var reference=ClassDB.instantiate("TerrainCore");reference.execute(Codec.command(6,[1703,3]))
		var expected:=Codec.excavation_samples(reference.execute(command))
		var commands: Array[PackedByteArray]=[command,command]
		check(terrain.edit(command,center-Vector3.ONE*8,center+Vector3.ONE*8,0,commands),"duplicate brushes admitted as one worker group")
		await wait_edit(terrain)
		check(terrain.last_edit_outcome.get("status")=="published" and terrain.last_edit_outcome.get("removed_samples")==expected,"worker group and facade preserve exact counts without double counting")
		check(terrain.edit(command,center-Vector3.ONE*8,center+Vector3.ONE*8),"repeat brush admitted")
		await wait_edit(terrain)
		var zero:=PackedInt64Array();zero.resize(16)
		check(terrain.last_edit_outcome.get("status")=="unchanged" and terrain.last_edit_outcome.get("removed_samples")==zero,"unchanged async edit clears previous accounting")
	terrain.shutdown();terrain.free()
	print("EXCAVATION_WORKER ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
