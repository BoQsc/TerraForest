# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("This fixture requires graphical MultiMesh transform readback; run fullscreen at 1920x1080.")
		quit(2);return
	Engine.max_fps=60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	await process_frame
	check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen presentation")
	var pickups=load("res://addons/world_runtime/material_pickups.gd").new()
	var persistence=load("res://addons/world_runtime/world_persistence.gd").new()
	root.add_child(pickups)
	check(pickups.prepare(persistence),"seven pickup stores and renderers initialize")
	for item: int in pickups.stores:
		var ids: PackedInt64Array=pickups.stores[item].spawn_grid(4096,Vector3.ZERO,0.5,Vector3.ZERO)
		check(ids.size()==4096,"full store admitted: %d"%item)
	pickups.update_view(0,Vector3.ZERO,true)
	var rendered:=0
	var uploads:=0
	for item: int in pickups.stores:
		var result: Dictionary=pickups.render_status[item]
		check(result.ok and result.visited<=4096 and result.rendered==256 and result.upload_bytes<=256*48,"bounded first selection and upload: %d"%item)
		rendered+=result.rendered;uploads+=result.upload_bytes
	check(rendered==1792 and uploads==86016,"seven full stores respect combined visible and upload caps")
	var times: Array[int]=[]
	var idle_bytes:=0
	for iteration in range(30):
		var start:=Time.get_ticks_usec()
		pickups.update_view(0.11,Vector3.ZERO,true)
		times.append(Time.get_ticks_usec()-start)
		for item: int in pickups.stores: idle_bytes+=pickups.render_status[item].upload_bytes
	check(idle_bytes==0,"thirty stationary full-population refreshes upload zero transform bytes")
	# Camera movement can change the nearest subset, but never the render cap.
	pickups.update_view(0.11,Vector3(7,0,7),true)
	for item: int in pickups.stores:
		var result: Dictionary=pickups.render_status[item]
		check(result.ok and result.rendered<=256 and result.upload_bytes<=12288,"moving focus stays bounded: %d"%item)
	var store: RefCounted=pickups.stores[201]
	var renderer: MultiMeshInstance3D=pickups.renderers[201]
	var selected: Dictionary=store.query_sphere_nearest(Vector3(7,0,7),64,256,4096)
	for handle: int in selected.ids: store.despawn(handle)
	pickups.update_view(0.11,Vector3(7,0,7),true)
	var current: Dictionary=store.query_sphere_nearest(Vector3(7,0,7),64,256,4096)
	var exact:=true
	for i in range(current.ids.size()):
		if i==0: print("TRANSFORM_PROBE actual=",renderer.multimesh.get_instance_transform(i).origin," expected=",store.get_position(current.ids[i]))
		exact=exact and renderer.multimesh.get_instance_transform(i).origin==store.get_position(current.ids[i])
	check(exact and renderer.multimesh.visible_instance_count==256,"removed visible population is replaced with live nearest positions")
	pickups.update_view(0.11,Vector3(1000,0,1000),true)
	var hidden:=true
	for item: int in pickups.stores:
		hidden=hidden and pickups.render_status[item].rendered==0 and pickups.renderers[item].multimesh.visible_instance_count==0
	check(hidden,"leaving populated area hides every pickup batch")
	times.sort()
	print("PICKUP_RENDER_PRESSURE population=28672 visible_cap=1792 first_upload_bytes=",uploads," idle_upload_bytes=",idle_bytes," refresh_cpu_us_p50=",times[15]," p95=",times[28]," max=",times[29]," checks=",checks," failures=",failures)
	pickups.free()
	quit(1 if failures else 0)
