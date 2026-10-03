# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures := 0
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func _initialize() -> void:
	GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
	call_deferred("run")
func run() -> void:
	var store: RefCounted = ClassDB.instantiate("NativeEntityStore")
	store.configure(100000)
	var ids: PackedInt64Array = store.spawn_grid(100000, Vector3.ZERO, 4.0, Vector3.ZERO)
	var renderer: MultiMeshInstance3D = ClassDB.instantiate("NativeEntityRenderer")
	root.add_child(renderer)
	check(not renderer.refresh(Vector3.ZERO, 16).ok, "unconfigured renderer rejects refresh")
	var mesh := BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.2, 0.8, 0.5)
	mesh.material = material
	check(renderer.configure(store, mesh, 128), "fixed capacity renderer configured")
	var result: Dictionary = renderer.refresh(Vector3(32, 0, 32), 16)
	check(result.ok and result.complete and result.rendered > 0 and result.rendered < 128, "local entities selected from 100000 population")
	check(result.upload_bytes == 128 * 48 and result.visited < 1000, "upload and candidate work bounded independently of population")
	var correct := true
	for i: int in result.ids.size():
		correct = correct and renderer.multimesh.get_instance_transform(i).origin.is_equal_approx(store.get_position(result.ids[i]))
	check(correct, "uploaded transforms match generation checked handles")
	check(not renderer.configure(store, mesh, 0) and renderer.multimesh.instance_count == 128, "invalid reconfiguration preserves resource")
	result = renderer.refresh(Vector3(32, 0, 32), 100)
	check(not result.complete and result.reason == "result_limit" and result.rendered == 128, "overflow is explicit and never grows GPU capacity")
	result = renderer.refresh(Vector3(32, 0, 32), 16, 2)
	check(not result.complete and result.visited == 2, "candidate budget preserved by renderer")
	check(not renderer.refresh(Vector3.INF, 16).ok and renderer.multimesh.visible_instance_count == 0, "invalid query hides stale instances")
	result = renderer.refresh(Vector3(-1000, 0, -1000), 1)
	check(result.rendered == 0 and result.upload_bytes == 0 and renderer.multimesh.visible_instance_count == 0, "empty area hides instances without upload")
	store.despawn(ids[0])
	var replacement: int = store.spawn(Vector3.ZERO, Vector3(10, 0, 0))
	store.step(0.1)
	result = renderer.refresh(Vector3(1, 0, 0), 0.1)
	check(result.ids == PackedInt64Array([replacement]) and renderer.multimesh.get_instance_transform(0).origin.is_equal_approx(Vector3(1, 0, 0)), "removal reuse and movement publish current entity only")
	renderer.multimesh.instance_count = 1
	check(not renderer.refresh(Vector3.ZERO, 16).ok and renderer.multimesh == null, "external resource mutation fails closed")
	renderer.configure(store, mesh, 128)
	result = renderer.refresh(Vector3(32, 0, 32), 16)
	renderer.position = Vector3(100, 0, 0)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.position = Vector3(132, 35, 65)
	camera.look_at(Vector3(132, 0, 32))
	camera.current = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	Engine.max_fps = 60
	for frame in 5: await process_frame
	check(renderer.get_child_count() == 0 and renderer.multimesh.visible_instance_count == result.rendered, "one rendering node without per entity scene nodes")
	DirAccess.make_dir_recursive_absolute("res://reports")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/entity_renderer.png")
	var file := FileAccess.open("res://reports/entity_renderer.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "population": 100000, "rendered": result.rendered, "visited": result.visited, "upload_bytes": result.upload_bytes, "scope": "bounded renderer correctness; no sustained frame rate or thermal claim"}, "  "))
	file.close()
	renderer.free()
	camera.free()
	quit(1 if failures else 0)
