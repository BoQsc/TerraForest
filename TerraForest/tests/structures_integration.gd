extends SceneTree
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var checks: Array[Dictionary] = []
var failures: int = 0
var placements: Array[Dictionary] = []
var invalidated_owners: int = 0
var messages: Array[String] = []
var slot: String = "construction_test_%d_%d" % [OS.get_process_id(),Time.get_ticks_usec()]

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
func until(predicate: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec()+90000
	while not predicate.call() and Time.get_ticks_msec()<deadline: await process_frame
	return predicate.call()
func settled() -> bool:
	return game.terrain.world_ready and not game.terrain.pending_edit and not game.loading_active
func ground(point: Vector3) -> Dictionary:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*50,point-Vector3.UP*50,1))
func run() -> void:
	game = Scene.instantiate()
	game.terrain.save_slot = slot
	root.add_child(game)
	game.terrain.message_changed.connect(func(text: String): messages.append(text))
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await until(settled),"scene terrain and player collision finish loading")
	if failures:
		await finish()
		return
	check(game.structure_buttons.size()==5,"construction toolbelt exposes five reusable presets")
	var select := InputEventKey.new()
	select.pressed = true
	select.physical_keycode = KEY_8
	game._unhandled_input(select)
	check(game.selected_structure==3,"shape shortcut selects slope preset")
	select.physical_keycode = KEY_T
	game._unhandled_input(select)
	check(game.structure_turn==1 and game.structure_hint.text.contains("90"),"rotation shortcut updates placement orientation and visible hint")
	check(not game.create_structure(game.player.position,0),"placement cannot enclose the player capsule")
	check(not game.terrain.edit(PackedByteArray([17,0,0,0]),Vector3.ZERO,Vector3.ONE),"scene boundary rejects malformed native stamps")
	check(not game.structures.place(game.Structures.PRESETS[0],Vector3(1800,100,1800)) and not game.terrain.pending_edit,"unloaded construction footprint rejects before queuing a mutation")
	var base: Vector3 = game.player.position+Vector3(0,0,-28)
	for i in range(5):
		var query: Vector3 = base+Vector3((i-2)*14,0,0)
		var hit: Dictionary = ground(query)
		check(not hit.is_empty(),"preset %d target has terrain collision" % i)
		if hit.is_empty(): continue
		var point: Vector3 = hit["position"]
		var turn: int = 1 if i==3 else 0
		var preset = game.Structures.PRESETS[i]
		var center: Vector3 = point.floor()+Vector3(0,preset.half_extents.y-0.5,0)
		check(await until(func(): return game.structures.can_place(preset,center,turn)),"preset %d entire reconstruction footprint has fine collision" % i)
		var candidates: Array[int] = []
		for id: int in game.vegetation.renderer.roots:
			var p: Vector3 = game.vegetation.renderer.roots[id]["t"].origin
			if absf(p.x-point.x)<7 and absf(p.z-point.z)<7: candidates.append(id)
		invalidated_owners += candidates.size()
		check(game.create_structure(point,i,turn),"preset %d submitted through terrain edit boundary" % i)
		check(await until(settled),"preset %d render and collision publish" % i)
		await physics_frame
		await physics_frame
		var probe: Vector3 = point.floor()+Vector3(0.25,15,0.25)
		var placed: Dictionary = ground(probe)
		check(not placed.is_empty() and placed["position"].y>point.y+1,"preset %d collision rises above original ground" % i)
		check(not game.terrain.natural_column_available(point),"preset %d marks construction columns against vegetation regrowth" % i)
		check(candidates.all(func(id): return not game.vegetation.renderer.roots.has(id)),"preset %d invalidates vegetation owners inside construction support" % i)
		if not placed.is_empty(): placements.append({"point":point,"height":placed["position"].y,"index":i})
		if i>=3:
			var direction := Vector3(4,0,0) if i==3 else Vector3(0,0,6)
			var high: Dictionary = ground(probe+direction)
			var low: Dictionary = ground(probe-direction)
			print("PROFILE ",i," origin ",point," high ",high.get("position")," low ",low.get("position"))
			check(not high.is_empty() and not low.is_empty() and high["position"].y-low["position"].y>3,"preset %d collision follows slope or stair elevation" % i)
	check(invalidated_owners>0,"vegetation invalidation checks exercised actual existing tree owners")
	messages.clear()
	game.terrain.save_world()
	check(await until(func(): return messages.any(func(text): return text.begins_with("World saved and verified"))),"constructed world saved through compound persistence")
	game.terrain.reload_world()
	check(await until(settled),"constructed world reloads and collision becomes ready")
	await physics_frame
	await physics_frame
	for placement: Dictionary in placements:
		var hit: Dictionary = ground(placement["point"].floor()+Vector3(0.25,15,0.25))
		check(not hit.is_empty() and absf(hit["position"].y-placement["height"])<0.02,"preset %d collision survives reload" % placement["index"])
	game.fly = true
	game.player.position = base+Vector3(0,50,-20)
	game.yaw = PI
	game.pitch = -1.15
	game.player.rotation.y = game.yaw
	game.camera.rotation.x = game.pitch
	game._select_structure(4)
	await create_timer(3).timeout
	if DisplayServer.get_name()!="headless":
		check(Presentation.measurement(root)["fair_graphical_sample"],"construction visual uses 1920x1080 fullscreen at full scale")
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute("res://reports")
		root.get_texture().get_image().save_png("res://reports/construction.png")
	await finish()
func finish() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	var output := FileAccess.open("res://reports/structures_integration.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"presentation":Presentation.measurement(root),"scope":"Five terrain primitive stamps, UI, collision and persistence; no city or instanced-prefab scaling claim"},"  "))
	output.close()
	game.terrain.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	for suffix in [".trw",".trw.bak",".trw.lock"]:
		var path: String = ProjectSettings.globalize_path("user://worlds/"+slot+suffix)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	quit(0 if failures==0 else 1)
