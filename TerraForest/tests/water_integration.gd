extends SceneTree
const Scene = preload("res://demo/world.tscn")
const Presentation = preload("res://addons/presentation/fullscreen_policy.gd")
var game: Node3D
var failures: int = 0
var checks: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var samples: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"pass":ok})
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ",label)

func wait_settled(water: bool = false) -> bool:
	var deadline: int = Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		if not game.loading_active and not game.terrain.pending_edit and game.terrain.world_ready:
			if not water or game.lakes.statistics()["ready"] == 1:
				return true
		await process_frame
	return false

func run() -> void:
	DirAccess.make_dir_recursive_absolute("res://reports")
	game = Scene.instantiate()
	game.temporary_world = true
	root.add_child(game)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	check(await wait_settled(),"terrain/player loading gate settles")
	if failures:
		await finish()
		return
	var point: Vector3 = game.player.global_position + Vector3(0,0,-18)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*60,point-Vector3.UP*60,1))
	check(not hit.is_empty(),"lake authoring target has real terrain collision")
	if hit.is_empty():
		await finish()
		return
	var center: Vector3 = (hit["position"] as Vector3).floor()
	var id: int = game.create_lake(center)
	check(id>0,"lake tool accepts bounded excavation and water definition")
	check(await wait_settled(true),"worker-baked lake publishes in real terrain scene")
	check(game.lakes.depth_at(center-Vector3(0,6,0))>2.5,"scene water query finds submerged volume")
	check(game.lakes.depth_at(center+Vector3(0,2,0))==0,"scene water query rejects point above lake")
	game.fly=false
	game.needs_floor_spawn=false
	game.player.position=center-Vector3(0,6,0)
	game._clear_motion()
	Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
	check(game._player_water_depth()>0,"player chest sample enters baked volumetric lake")
	var swim_start: Vector3=game.player.position
	game.controls.set_key(KEY_SPACE,true,Time.get_ticks_usec())
	for i in range(12): await physics_frame
	check(game.player.position.y>swim_start.y and game.player.velocity.y>0,"real player swims upward through collision-aware movement")
	game.water_camera.update()
	check(game.water_camera.underwater and game.camera.environment!=null and game.camera.environment.fog_enabled,"submerged camera enables local underwater fog")
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/water_underwater.png")
	game._clear_motion()
	game.player.position=center+Vector3(0,2,0)
	check(game._player_water_depth()==0,"player leaving volume returns to dry movement")
	game.water_camera.update()
	check(not game.water_camera.underwater and game.camera.environment==null,"leaving water restores inherited scene environment")
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	snapshots.append(game.lakes.statistics())
	game.fly = true
	game.player.position = center+Vector3(18,15,22)
	game.yaw = 0.68
	game.pitch = -0.5
	game.player.rotation.y = game.yaw
	game.camera.rotation.x = game.pitch
	await create_timer(3).timeout
	if DisplayServer.get_name() != "headless":
		check(Presentation.measurement(root)["fair_graphical_sample"],"water visual check uses 1920x1080 fullscreen at 100 percent scale")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://reports/water_lake.png")
		Engine.max_fps = 60
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		var previous: int = Time.get_ticks_usec()
		for i in range(120):
			await process_frame
			var now: int = Time.get_ticks_usec()
			samples.append((now-previous)/1000.0)
			previous = now
	# Hide both volume and surface immediately, before edited terrain publishes.
	check(game.terrain.sculpt_sphere(center+Vector3(5,-7,0),2,true),"submerged terrain edit accepted")
	check(game.lakes.depth_at(center-Vector3(0,6,0))==0 and game.lakes.statistics()["ready"]==0,"accepted terrain edit immediately invalidates stale water")
	check(await wait_settled(true),"water rebakes after edited terrain publishes")
	check(game.lakes.statistics()["outstanding_slices"]==0,"completed bake leaves no outstanding worker slice")
	snapshots.append(game.lakes.statistics())
	game.lakes.remove_lake(id)
	await process_frame
	check(game.lakes.statistics()["lakes"]==0 and game.lakes.statistics()["resident_occupancy_bytes"]==0,"removing lake releases surface ownership and resident volume")
	var pending: int = game.lakes.add_lake(center-Vector3(16,16,16),Vector3i(32,20,32),1,center.y-3,center-Vector3(0,6,0))
	await process_frame
	await process_frame
	game.lakes.remove_lake(pending)
	await create_timer(0.5).timeout
	check(game.lakes.statistics()["ready"]==0 and game.lakes.statistics()["outstanding_slices"]==0,"removal during sampling discards late worker completion")
	await finish()

func finish() -> void:
	var output := FileAccess.open("res://reports/water_integration.json",FileAccess.WRITE)
	samples.sort()
	var frame: Dictionary = {}
	if not samples.is_empty():
		frame = {"count":samples.size(),"p50_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*0.95)],"p99_ms":samples[int(samples.size()*0.99)],"max_ms":samples[-1]}
	output.store_string(JSON.stringify({"checks":checks,"failures":failures,"snapshots":snapshots,"presentation":Presentation.measurement(root),"engine":Engine.get_version_info(),"frame_times":frame,"scope":"Fixed warmed lake scene; excludes bake/travel tails and is not a speedup comparison"},"  "))
	output.close()
	game.terrain.shutdown()
	game.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)
